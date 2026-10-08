import { GoogleGenAI, Type } from '@google/genai';
import { config } from '../config.js';

export type AssistantIntent =
  | 'TRAVEL_CARRY'
  | 'SEND_PARCEL'
  | 'BUY_FOR_ME'
  | 'FIND_RIDE'
  | 'OFFER_RIDE'
  | 'MARKETPLACE_SEARCH'
  | 'UNKNOWN';

export type AssistantInterpretation = {
  intent: AssistantIntent;
  originQuery: string;
  destinationQuery: string;
  travelDate: string;
  dateFlexible: boolean;
  availableWeightKg: number;
  passengers: number;
  marketplaceQuery: string;
  missingFields: string[];
  confidence: number;
};

export type AssistantContext = Partial<AssistantInterpretation>;

function cleanString(value: unknown): string {
  return typeof value === 'string' ? value.trim().slice(0, 180) : '';
}

function cleanNumber(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

function normalizeIntent(value: unknown): AssistantIntent {
  const allowed: AssistantIntent[] = [
    'TRAVEL_CARRY',
    'SEND_PARCEL',
    'BUY_FOR_ME',
    'FIND_RIDE',
    'OFFER_RIDE',
    'MARKETPLACE_SEARCH',
    'UNKNOWN',
  ];
  const text = String(value ?? '').trim().toUpperCase() as AssistantIntent;
  return allowed.includes(text) ? text : 'UNKNOWN';
}

function normalize(raw: any): AssistantInterpretation {
  return {
    intent: normalizeIntent(raw?.intent),
    originQuery: cleanString(raw?.originQuery),
    destinationQuery: cleanString(raw?.destinationQuery),
    travelDate: cleanString(raw?.travelDate),
    dateFlexible: raw?.dateFlexible === true,
    availableWeightKg: cleanNumber(raw?.availableWeightKg),
    passengers: Math.max(0, Math.min(8, Math.round(cleanNumber(raw?.passengers)))),
    marketplaceQuery: cleanString(raw?.marketplaceQuery),
    missingFields: Array.isArray(raw?.missingFields)
      ? raw.missingFields.map(cleanString).filter(Boolean).slice(0, 10)
      : [],
    confidence: Math.max(0, Math.min(1, cleanNumber(raw?.confidence))),
  };
}

function mergeInterpretations(
  previous: AssistantContext | undefined,
  current: AssistantInterpretation,
): AssistantInterpretation {
  const prior = previous ?? {};
  return normalize({
    intent: current.intent !== 'UNKNOWN' ? current.intent : prior.intent,
    originQuery: current.originQuery || prior.originQuery,
    destinationQuery: current.destinationQuery || prior.destinationQuery,
    travelDate: current.travelDate || prior.travelDate,
    dateFlexible: current.dateFlexible || prior.dateFlexible === true,
    availableWeightKg:
      current.availableWeightKg > 0
        ? current.availableWeightKg
        : prior.availableWeightKg,
    passengers: current.passengers > 0 ? current.passengers : prior.passengers,
    marketplaceQuery: current.marketplaceQuery || prior.marketplaceQuery,
    missingFields: current.missingFields,
    confidence: current.confidence,
  });
}

function deterministicMissingFields(
  value: AssistantInterpretation,
): string[] {
  const missing: string[] = [];
  switch (value.intent) {
    case 'TRAVEL_CARRY':
      if (!value.originQuery) missing.push('origin');
      if (!value.destinationQuery) missing.push('destination');
      if (!value.travelDate && !value.dateFlexible) missing.push('travelDate');
      if (value.availableWeightKg <= 0) missing.push('availableWeightKg');
      break;
    case 'SEND_PARCEL':
    case 'BUY_FOR_ME':
      if (!value.originQuery) missing.push('origin');
      if (!value.destinationQuery) missing.push('destination');
      break;
    case 'FIND_RIDE':
      if (!value.originQuery) missing.push('origin');
      if (!value.destinationQuery) missing.push('destination');
      if (!value.travelDate && !value.dateFlexible) missing.push('travelDate');
      if (value.passengers <= 0) missing.push('passengers');
      break;
    case 'OFFER_RIDE':
      if (!value.originQuery) missing.push('origin');
      if (!value.destinationQuery) missing.push('destination');
      if (!value.travelDate && !value.dateFlexible) missing.push('travelDate');
      break;
    case 'MARKETPLACE_SEARCH':
      if (!value.marketplaceQuery) missing.push('marketplaceQuery');
      break;
    case 'UNKNOWN':
      missing.push('intent');
      break;
  }
  return missing;
}

function followUpFor(field: string): string {
  switch (field) {
    case 'intent':
      return 'What would you like to do: carry requests on a trip, send a parcel, find a ride, offer a ride, bring an item, or search Marketplace?';
    case 'origin':
      return 'Where are you starting from? Please enter an Indian city, area, station, airport or landmark.';
    case 'destination':
      return 'Where are you going? Please enter an Indian city, area, station, airport or landmark.';
    case 'travelDate':
      return 'What date are you travelling? You can also say your dates are flexible.';
    case 'availableWeightKg':
      return 'How much spare parcel space do you have, approximately, in kilograms?';
    case 'passengers':
      return 'How many passengers need seats?';
    case 'marketplaceQuery':
      return 'What are you looking for in Marketplace?';
    default:
      return 'What detail should I use to continue this search?';
  }
}

export function assistantFollowUp(value: AssistantInterpretation): string | null {
  const missing = deterministicMissingFields(value);
  return missing.length > 0 ? followUpFor(missing[0]!) : null;
}

function deterministicAssistantInterpretation(
  message: string,
  previous?: AssistantContext,
): AssistantInterpretation {
  const lower = message.toLowerCase();
  let intent: AssistantIntent = 'UNKNOWN';

  if (/\b(buy[ -]?for[ -]?me|bring (?:me )?|someone to bring|pick up .* for me)\b/i.test(message)) {
    intent = 'BUY_FOR_ME';
  } else if (/\b(offer|drive|driving|have)\b.*\b(ride|carpool|seat|seats)\b/i.test(message)) {
    intent = 'OFFER_RIDE';
  } else if (/\b(find|need|want|looking for)\b.*\b(ride|carpool|seat|seats)\b/i.test(message)) {
    intent = 'FIND_RIDE';
  } else if (/\b(spare|carry|carrying|travell?ing|luggage)\b.*\b(kg|kgs|kilo|kilos|parcel|package|request)\b/i.test(message)) {
    intent = 'TRAVEL_CARRY';
  } else if (/\b(send|ship)\b.*\b(parcel|package|item|something)\b/i.test(message) || /^\s*(send|ship)\b/i.test(message)) {
    intent = 'SEND_PARCEL';
  } else if (/\b(find|search|buy|looking for)\b.*\b(marketplace|phone|bike|bicycle|laptop|item|product)\b/i.test(message)) {
    intent = 'MARKETPLACE_SEARCH';
  }

  const updates: Partial<AssistantInterpretation> = { intent, confidence: intent === 'UNKNOWN' ? 0.2 : 0.7 };
  const fromTo = message.match(/\bfrom\s+(.+?)\s+to\s+(.+?)(?=\s+(?:on|today|tomorrow|with|for|carrying|carry|and)\b|[,.!?]|$)/i);
  const simpleTo = !fromTo ? message.match(/^\s*([^,.!?]+?)\s+to\s+(.+?)(?=\s+(?:on|today|tomorrow|with|for|carrying|carry|and)\b|[,.!?]|$)/i) : null;
  const route = fromTo ?? simpleTo;
  if (route?.[1] && route?.[2]) {
    updates.originQuery = route[1].trim();
    updates.destinationQuery = route[2].trim();
  }

  const kg = message.match(/\b(\d+(?:\.\d+)?)\s*(?:kg|kgs|kilo|kilos|kilograms)\b/i);
  if (kg?.[1]) updates.availableWeightKg = Number(kg[1]);

  const people = message.match(/\b(\d+)\s*(?:people|persons|passengers|seats?)\b/i);
  if (people?.[1]) updates.passengers = Number(people[1]);

  const exactDate = message.match(/\b(20\d{2}-\d{2}-\d{2})\b/);
  if (exactDate?.[1]) updates.travelDate = exactDate[1];
  if (/\bflexible|any day|any date\b/i.test(message)) updates.dateFlexible = true;

  if (intent === 'MARKETPLACE_SEARCH') {
    const item = lower
      .replace(/\b(find|search|buy|looking for|marketplace|under|below)\b/gi, ' ')
      .replace(/₹?\s*\d+(?:\.\d+)?/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    if (item.length >= 2) updates.marketplaceQuery = item.slice(0, 180);
  }

  const merged = mergeInterpretations(previous, normalize(updates));
  return {
    ...merged,
    missingFields: deterministicMissingFields(merged),
  };
}

export async function interpretAssistantMessage(
  message: string,
  previous?: AssistantContext,
): Promise<AssistantInterpretation> {
  const ai = new GoogleGenAI({ apiKey: config.GEMINI_API_KEY });
  const today = new Date().toISOString().slice(0, 10);
  const previousJson = JSON.stringify(previous ?? {});

  let response;
  try {
    response = await ai.models.generateContent({
    model: config.GEMINI_SCAM_MODEL,
    contents: [
      {
        text: [
          'You are the intent interpreter for ShipdeHop, an India-only peer-to-peer logistics, carpool and marketplace app.',
          'Interpret the latest user message together with prior structured context.',
          'Do not invent places, dates, weights, passenger counts or products.',
          'Convert clear dates to YYYY-MM-DD. If the user says dates are flexible, set dateFlexible true and leave travelDate empty unless a concrete date is also supplied.',
          'TRAVEL_CARRY means the user is already travelling and wants compatible parcel/Buy-for-Me requests.',
          'SEND_PARCEL means the user wants to send something.',
          'BUY_FOR_ME means the user wants a traveller to bring/buy something.',
          'FIND_RIDE means the user wants a passenger seat.',
          'OFFER_RIDE means the user is driving/offering seats.',
          'MARKETPLACE_SEARCH means the user is looking for an item/listing.',
          'If unclear, use UNKNOWN.',
          `Today is ${today}.`,
          `Prior context: ${previousJson}`,
          `Latest message: ${message}`,
        ].join('\n'),
      },
    ],
    config: {
      responseMimeType: 'application/json',
      responseSchema: {
        type: Type.OBJECT,
        properties: {
          intent: {
            type: Type.STRING,
            enum: [
              'TRAVEL_CARRY',
              'SEND_PARCEL',
              'BUY_FOR_ME',
              'FIND_RIDE',
              'OFFER_RIDE',
              'MARKETPLACE_SEARCH',
              'UNKNOWN',
            ],
          },
          originQuery: { type: Type.STRING },
          destinationQuery: { type: Type.STRING },
          travelDate: { type: Type.STRING },
          dateFlexible: { type: Type.BOOLEAN },
          availableWeightKg: { type: Type.NUMBER },
          passengers: { type: Type.NUMBER },
          marketplaceQuery: { type: Type.STRING },
          missingFields: { type: Type.ARRAY, items: { type: Type.STRING } },
          confidence: { type: Type.NUMBER },
        },
        required: [
          'intent',
          'originQuery',
          'destinationQuery',
          'travelDate',
          'dateFlexible',
          'availableWeightKg',
          'passengers',
          'marketplaceQuery',
          'missingFields',
          'confidence',
        ],
      },
      temperature: 0.1,
    },
    });
  } catch {
    return deterministicAssistantInterpretation(message, previous);
  }

  let parsed: any = {};
  try {
    parsed = JSON.parse(response.text ?? '{}');
  } catch {
    parsed = {};
  }

  const merged = mergeInterpretations(previous, normalize(parsed));
  return {
    ...merged,
    missingFields: deterministicMissingFields(merged),
  };
}
