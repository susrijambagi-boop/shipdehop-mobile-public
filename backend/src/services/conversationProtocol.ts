/** Pure, validated conversation state. Model prose never authorizes a mutation. */
export const intents = ['UNKNOWN', 'TRAVEL_CARRY', 'SEND_PARCEL', 'BUY_FOR_ME',
  'FIND_RIDE', 'OFFER_RIDE', 'MARKETPLACE_SEARCH', 'MARKETPLACE_SELL'] as const;
export type Intent = typeof intents[number];
export type Context = {
  intent: Intent; originQuery: string; destinationQuery: string; travelDate: string;
  dateFlexible: boolean; availableWeightKg: number; passengers: number;
  marketplaceQuery: string; itemDescription: string; productUrl: string; maxPrice: number;
};
export type HistoryMessage = { role: 'user' | 'assistant'; text: string };
export type Turn = { kind: 'TASK' | 'ANSWER' | 'CLARIFY' | 'RESET'; topic: string;
  reply: string; context: Context; invalid: boolean };
const textKeys = ['originQuery', 'destinationQuery', 'travelDate', 'marketplaceQuery',
  'itemDescription', 'productUrl'] as const;
const numberKeys = ['availableWeightKg', 'passengers', 'maxPrice'] as const;
export const emptyContext = (): Context => ({ intent: 'UNKNOWN', originQuery: '',
  destinationQuery: '', travelDate: '', dateFlexible: false, availableWeightKg: 0,
  passengers: 0, marketplaceQuery: '', itemDescription: '', productUrl: '', maxPrice: 0 });
const object = (v: unknown): Record<string, unknown> => v && typeof v === 'object' &&
  !Array.isArray(v) ? v as Record<string, unknown> : {};
const isIntent = (v: unknown): v is Intent => intents.includes(v as Intent);
const clean = (v: unknown, max = 180): string => typeof v === 'string'
  ? v.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g, '').trim().slice(0, max) : '';

export function normalizeContext(value: unknown): Context {
  const raw = object(value); const next = emptyContext();
  if (isIntent(raw.intent)) next.intent = raw.intent;
  for (const key of textKeys) next[key] = clean(raw[key]);
  for (const key of numberKeys) next[key] = typeof raw[key] === 'number' &&
    Number.isFinite(raw[key]) && raw[key] >= 0 ? raw[key] : 0;
  next.dateFlexible = raw.dateFlexible === true;
  return next;
}

export function parseConversationTurn(rawText: string, previous: unknown): Turn {
  const prior = normalizeContext(previous);
  const invalid = (): Turn => ({ kind: 'CLARIFY', topic: 'GENERAL',
    reply: 'I could not reliably understand that. Could you rephrase what you need?',
    context: prior, invalid: true });
  let raw: Record<string, unknown>;
  try { raw = object(JSON.parse(rawText)); } catch { return invalid(); }
  if (!['TASK', 'ANSWER', 'CLARIFY', 'RESET'].includes(String(raw.kind))) return invalid();
  const kind = raw.kind as Turn['kind'];
  if (kind === 'RESET') return { kind, topic: 'GENERAL', reply: 'A fresh start. What would you like to do?',
    context: emptyContext(), invalid: false };
  const patch = object(raw.updates);
  if ('intent' in patch && !isIntent(patch.intent)) return invalid();
  for (const key of textKeys) if (key in patch && typeof patch[key] !== 'string') return invalid();
  for (const key of numberKeys) if (key in patch && (typeof patch[key] !== 'number' ||
      !Number.isFinite(patch[key]) || patch[key] < 0)) return invalid();
  if ('dateFlexible' in patch && typeof patch.dateFlexible !== 'boolean') return invalid();
  // A new purpose must not inherit unrelated products, weights or seat counts.
  // Explicitly restated route fields can still be sent in updates by the model.
  const changedIntent = isIntent(patch.intent) && patch.intent !== prior.intent;
  const base = raw.resetContext === true || changedIntent ? emptyContext() : prior;
  const ctx = normalizeContext({ ...base, ...patch });
  if ('travelDate' in patch && ctx.travelDate && !('dateFlexible' in patch)) ctx.dateFlexible = false;
  if (patch.dateFlexible === true && !('travelDate' in patch)) ctx.travelDate = '';
  return { kind, topic: clean(raw.topic, 40).toUpperCase(), reply: clean(raw.reply, 900),
    context: ctx, invalid: false };
}

export function indiaToday(now: Date): string {
  return new Date(now.getTime() + 19800000).toISOString().slice(0, 10);
}
export function validDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}
export function missingQuestion(ctx: Context, now = new Date()): string | null {
  if (ctx.intent === 'UNKNOWN') return 'What would you like help with: a parcel, a ride, something to buy or sell, or using ShipdeHop?';
  if (ctx.intent === 'MARKETPLACE_SEARCH' || ctx.intent === 'MARKETPLACE_SELL') {
    return ctx.marketplaceQuery || ctx.itemDescription ? null : 'What item do you have in mind?';
  }
  if (!ctx.originQuery) return 'Where are you starting from?';
  if (!ctx.destinationQuery) return 'Where should it go?';
  if (ctx.originQuery.toLowerCase() === ctx.destinationQuery.toLowerCase())
    return 'You gave the same starting point and destination. Which destination should I use?';
  if (ctx.travelDate && (!validDate(ctx.travelDate) || ctx.travelDate < indiaToday(now)))
    return 'That date is invalid or has passed in India. What date should I use instead?';
  if (!ctx.travelDate && !ctx.dateFlexible) return 'Which date are you travelling, or are your dates flexible?';
  if (ctx.intent === 'TRAVEL_CARRY' && ctx.availableWeightKg <= 0)
    return 'How much spare luggage space do you have, in kilograms?';
  if ((ctx.intent === 'FIND_RIDE' || ctx.intent === 'OFFER_RIDE') &&
      (!Number.isInteger(ctx.passengers) || ctx.passengers < 1 || ctx.passengers > 8))
    return ctx.intent === 'OFFER_RIDE' ? 'How many spare seats are you offering, from 1 to 8?'
      : 'How many passengers need seats, from 1 to 8?';
  return null;
}
export function searchWindow(ctx: Context, now = new Date()): { after: string; before: string } {
  const day = ctx.travelDate || indiaToday(now);
  const beginning = new Date(`${day}T00:00:00+05:30`).getTime();
  return { after: new Date(Math.max(beginning, now.getTime())).toISOString(),
    before: new Date(beginning + (ctx.travelDate ? 1 : 30) * 86400000).toISOString() };
}

export const helpReplies: Record<string, { message: string; type: string; label: string }> = {
  HOW_IT_WORKS: { message: 'ShipdeHop connects people who need to send a parcel, share a ride, or buy and sell items. Tell me what you need; I will ask for any missing details and show the next step. A conversation never publishes a listing or books anything for you.', type: 'OPEN_HELP', label: 'Explore how ShipdeHop works' },
  SAFETY: { message: 'Tell me the item you want to carry. Eligibility depends on the item and the current safety checks; a chat reply is not approval. Review the parcel information and safety guidance before agreeing to carry it. Do not share passwords or one-time codes in chat.', type: 'OPEN_HELP', label: 'Read safety guidance' },
  PAYMENTS: { message: 'In-app payment processing and payouts are currently disabled. ShipdeHop is not collecting a payment or holding funds through this chat. Review the current payment information before making an arrangement.', type: 'OPEN_PAYMENTS', label: 'View payment information' },
  VERIFICATION: { message: 'Some transactions require identity verification. I cannot verify you through chat or bypass those checks. Open your verification screen to see the actual status and currently supported next steps.', type: 'OPEN_IDENTITY', label: 'Check identity verification' },
  TRACKING: { message: 'I have not checked a live delivery location in this conversation. Open your activity, choose the delivery, and check its tracking status. A live location is available only when the authorised traveller is sharing it.', type: 'OPEN_ACTIVITY', label: 'Open my activity' },
  SUPPORT: { message: 'You can find the available support and help options in ShipdeHop Help. Do not include identity documents, passwords or payment codes in this chat.', type: 'OPEN_HELP', label: 'Open Help and Support' },
  PRIVACY: { message: 'I use the recent messages and trip details you provide to understand this conversation. Do not send sensitive identity or payment information here. This conversation cannot grant access to another person\'s private account, messages or location.', type: 'OPEN_HELP', label: 'Review help and privacy guidance' },
};
