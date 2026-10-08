import { GoogleGenAI, Type } from '@google/genai';
import { config } from '../config.js';

export type ScamAssessment = {
  action: 'SAFE' | 'WARN' | 'BLOCKED';
  riskScore: number;
  reasons: string[];
  detectedQr: boolean;
  requestsOffPlatformPayment: boolean;
  phishingLink: boolean;
};

const ai = new GoogleGenAI({ apiKey: config.GEMINI_API_KEY });
const riskyText = [
  /scan\s+(this\s+)?qr/i,
  /pay\s+(me\s+)?direct(ly)?/i,
  /outside\s+(the\s+)?app/i,
  /upi\s*id/i,
  /whats?app\s+me/i,
  /telegram/i,
  /gift\s*card/i,
  /crypto|usdt|bitcoin/i,
  /verify.*(?:bank|account).*https?:\/\//i,
];

export async function assessChat(input: {
  text?: string;
  imageBase64?: string;
  imageMimeType?: string;
}): Promise<ScamAssessment> {
  const deterministicReasons = riskyText
    .filter((r) => r.test(input.text ?? ''))
    .map((r) => `Text matched risk rule: ${r.source}`);

  const contents: Array<{ text: string } | { inlineData: { mimeType: string; data: string } }> = [];
  if (input.imageBase64 && input.imageMimeType) {
    contents.push({ inlineData: { mimeType: input.imageMimeType, data: input.imageBase64 } });
  }
  contents.push({
    text: [
      'You are HopShield, a safety classifier for a peer-to-peer marketplace, rideshare and crowdshipping chat.',
      'Assess ONLY scam/payment safety. Detect: payment QR solicitation, fake payment proof, phishing links, credential theft, requests to move payment off HopPay, gift-card/crypto payment, and impersonation.',
      'Do not infer protected traits. Do not mark ordinary phone numbers, addresses, meetup coordination, or legitimate product URLs as scams by themselves.',
      'Return SAFE for normal conversation, WARN for suspicious/ambiguous behavior, BLOCKED only for high-confidence active phishing, credential theft, or off-platform payment solicitation.',
      `Message: ${input.text ?? '[image only]'}`,
    ].join('\n'),
  });

  const response = await ai.models.generateContent({
    model: config.GEMINI_SCAM_MODEL,
    contents,
    config: {
      responseMimeType: 'application/json',
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          action: { type: Type.STRING, enum: ['SAFE', 'WARN', 'BLOCKED'] },
          riskScore: { type: Type.NUMBER },
          reasons: { type: Type.ARRAY, items: { type: Type.STRING } },
          detectedQr: { type: Type.BOOLEAN },
          requestsOffPlatformPayment: { type: Type.BOOLEAN },
          phishingLink: { type: Type.BOOLEAN },
        },
        required: ['action', 'riskScore', 'reasons', 'detectedQr', 'requestsOffPlatformPayment', 'phishingLink'],
      },
    },
  });

  const parsed = JSON.parse(response.text ?? '{}') as ScamAssessment;
  parsed.riskScore = Math.max(0, Math.min(1, Number(parsed.riskScore) || 0));
  parsed.reasons = [...deterministicReasons, ...(parsed.reasons ?? [])];

  if (deterministicReasons.length > 0 && parsed.action === 'SAFE') parsed.action = 'WARN';
  if (parsed.requestsOffPlatformPayment && parsed.riskScore >= 0.85) parsed.action = 'BLOCKED';
  return parsed;
}
