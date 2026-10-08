import { GoogleGenAI, Type } from '@google/genai';
import { config } from '../config.js';

export type ParcelInspection = {
  decision: 'APPROVED' | 'REVIEW' | 'BLOCKED';
  confidence: number;
  contentMismatch: boolean;
  prohibitedCategories: string[];
  rationale: string;
  timing?: {
    totalMs: number;
    loadMs?: number;
    promptEvalMs?: number;
    evalMs?: number;
    promptTokens?: number | undefined;
    evalTokens?: number | undefined;
  };
};

export const PARCEL_INSPECTION_MODEL =
  config.PARCEL_INSPECTION_PROVIDER === 'GEMINI'
    ? `gemini:${config.GEMINI_VISION_MODEL}`
    : `ollama:${config.OLLAMA_VISION_MODEL}`;

type OllamaChatResponse = {
  message?: {
    role?: string;
    content?: string;
  };
  total_duration?: number;
  load_duration?: number;
  prompt_eval_count?: number;
  prompt_eval_duration?: number;
  eval_count?: number;
  eval_duration?: number;
};

function extractJsonBlock(text: string): string {
  const trimmed = text.trim();
  const match = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  return (match?.[1] ?? trimmed).trim();
}

export function normalizeInspection(parsed: Partial<ParcelInspection>): ParcelInspection {
  let decision: ParcelInspection['decision'] = 'REVIEW';

  if (parsed.decision === 'APPROVED' || parsed.decision === 'REVIEW' || parsed.decision === 'BLOCKED') {
    decision = parsed.decision;
  }

  const rawConf = Number(parsed.confidence);
  const confidence = Number.isFinite(rawConf) ? Math.max(0, Math.min(1, rawConf)) : 0;
  const contentMismatch = Boolean(parsed.contentMismatch);
  const prohibitedCategories = Array.isArray(parsed.prohibitedCategories)
    ? parsed.prohibitedCategories.map(String).slice(0, 20)
    : [];
  const rationale = typeof parsed.rationale === 'string' && parsed.rationale.trim().length > 0
    ? parsed.rationale.slice(0, 2000)
    : 'Inspection completed.';

  if (contentMismatch && decision === 'APPROVED') {
    decision = 'REVIEW';
  }

  return {
    decision,
    confidence,
    contentMismatch,
    prohibitedCategories,
    rationale,
  };
}

export interface ParcelInspectionInput {
  imageBase64: string;
  imageMimeType: 'image/jpeg' | 'image/png' | 'image/webp';
  itemType: 'PARCEL' | 'URL_PURCHASE';
  productUrl?: string | null;
  keepAlive?: string;
}

const PROMPT_INSTRUCTIONS = [
  'You are HopShield Parcel Safety, a conservative pre-screening classifier for a peer-to-peer crowdshipping marketplace.',
  'Inspect the visible parcel/product only for transport and marketplace safety. Do not identify people or infer sensitive traits.',
  'Return only JSON.',
  'APPROVED: clearly ordinary consumer goods with no visible safety concern.',
  'REVIEW: uncertain contents or goods that may require carrier/customs/legal checks, including medicines, batteries, liquids, high-value documents/currency-like items, or ambiguous sealed packages.',
  'BLOCKED: only when the image provides high-confidence evidence of obviously prohibited or dangerous goods such as a weapon, explosive, illegal drug product, or clearly hazardous toxic material.',
  'contentMismatch is true only when the visible item clearly conflicts with the supplied request context.',
].join('\n');

export async function inspectWithGemini(
  input: ParcelInspectionInput,
  options?: { aiClient?: GoogleGenAI; timeoutMs?: number; modelName?: string },
): Promise<ParcelInspection> {
  const startTime = Date.now();
  const timeoutMs = options?.timeoutMs ?? 15000;
  const model = options?.modelName ?? config.GEMINI_VISION_MODEL;

  const prompt = [
    PROMPT_INSTRUCTIONS,
    `Request type: ${input.itemType}`,
    `Product URL context: ${input.productUrl ?? 'none'}`,
  ].join('\n');

  try {
    const ai = options?.aiClient ?? new GoogleGenAI({ apiKey: config.GEMINI_API_KEY });

    const timeoutPromise = new Promise<never>((_, reject) => {
      setTimeout(() => reject(new Error('HopShield Gemini inspection timed out')), timeoutMs);
    });

    const generatePromise = ai.models.generateContent({
      model,
      contents: [
        {
          inlineData: {
            mimeType: input.imageMimeType,
            data: input.imageBase64,
          },
        },
        { text: prompt },
      ],
      config: {
        responseMimeType: 'application/json',
        responseSchema: {
          type: Type.OBJECT,
          properties: {
            decision: { type: Type.STRING, enum: ['APPROVED', 'REVIEW', 'BLOCKED'] },
            confidence: { type: Type.NUMBER },
            contentMismatch: { type: Type.BOOLEAN },
            prohibitedCategories: { type: Type.ARRAY, items: { type: Type.STRING } },
            rationale: { type: Type.STRING },
          },
          required: ['decision', 'confidence', 'contentMismatch', 'prohibitedCategories', 'rationale'],
        },
      },
    });

    const response = await Promise.race([generatePromise, timeoutPromise]);
    const rawText = response.text ?? '';
    let parsed: Partial<ParcelInspection>;

    try {
      parsed = JSON.parse(extractJsonBlock(rawText)) as Partial<ParcelInspection>;
    } catch {
      return {
        decision: 'REVIEW',
        confidence: 0,
        contentMismatch: false,
        prohibitedCategories: [],
        rationale: 'AI output format unrecognized; flagged for manual review.',
        timing: { totalMs: Date.now() - startTime },
      };
    }

    const normalized = normalizeInspection(parsed);
    normalized.timing = { totalMs: Date.now() - startTime };
    return normalized;
  } catch {
    // Fail safe on quota, timeout, or network issues
    return {
      decision: 'REVIEW',
      confidence: 0,
      contentMismatch: false,
      prohibitedCategories: [],
      rationale: 'AI safety inspection service temporarily unavailable; queued for manual safety review.',
      timing: { totalMs: Date.now() - startTime },
    };
  }
}

export async function inspectWithOllama(
  input: ParcelInspectionInput,
  options?: { url?: string; model?: string },
): Promise<ParcelInspection> {
  const startTime = Date.now();
  const ollamaUrl = options?.url ?? config.OLLAMA_URL;
  const ollamaModel = options?.model ?? config.OLLAMA_VISION_MODEL;

  const prompt = [
    PROMPT_INSTRUCTIONS,
    'Use exactly these fields:',
    '{',
    '  "decision": "APPROVED" | "REVIEW" | "BLOCKED",',
    '  "confidence": number,',
    '  "contentMismatch": boolean,',
    '  "prohibitedCategories": string[],',
    '  "rationale": string',
    '}',
    `Request type: ${input.itemType}`,
    `Product URL context: ${input.productUrl ?? 'none'}`,
  ].join('\n');

  const response = await fetch(ollamaUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: ollamaModel,
      stream: false,
      keep_alive: input.keepAlive ?? '30m',
      options: {
        num_predict: 128,
        temperature: 0.1,
      },
      messages: [
        {
          role: 'user',
          content: prompt,
          images: [input.imageBase64],
        },
      ],
    }),
  });

  if (!response.ok) {
    throw new Error(`Ollama ${response.status}: ${await response.text()}`);
  }

  const payload = (await response.json()) as OllamaChatResponse;
  const rawContent = payload.message?.content;

  if (!rawContent) {
    throw new Error('Ollama returned no content');
  }

  let parsed: Partial<ParcelInspection>;
  try {
    parsed = JSON.parse(extractJsonBlock(rawContent)) as Partial<ParcelInspection>;
  } catch {
    throw new Error(`Ollama returned invalid JSON: ${rawContent}`);
  }

  const normalized = normalizeInspection(parsed);
  const totalMs = Date.now() - startTime;
  const loadMs = Math.round((payload.load_duration ?? 0) / 1e6);
  const promptEvalMs = Math.round((payload.prompt_eval_duration ?? 0) / 1e6);
  const evalMs = Math.round((payload.eval_duration ?? 0) / 1e6);

  normalized.timing = {
    totalMs,
    loadMs,
    promptEvalMs,
    evalMs,
    promptTokens: payload.prompt_eval_count,
    evalTokens: payload.eval_count,
  };

  return normalized;
}

export async function inspectParcel(input: ParcelInspectionInput): Promise<ParcelInspection> {
  if (config.PARCEL_INSPECTION_PROVIDER === 'GEMINI') {
    return inspectWithGemini(input);
  }
  return inspectWithOllama(input);
}