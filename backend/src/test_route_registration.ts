import assert from 'node:assert/strict';
import Fastify from 'fastify';
import sensible from '@fastify/sensible';
import type { AssistantContext, AssistantInterpretation } from './services/smartAssistant.js';

// Non-secret local fixtures. This suite must never contact a live service.
process.env.NODE_ENV = 'test';
process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_PUBLISHABLE_KEY = 'local-test-placeholder';
process.env.SUPABASE_SECRET_KEY = 'local-test-placeholder';
process.env.GEMINI_API_KEY = 'local-test';
process.env.GOOGLE_ROUTES_API_KEY = 'local-test';
process.env.GEOAPIFY_API_KEY = 'mock-key-for-tests';
process.env.PAYMENT_PROVIDER = 'DISABLED';

interface AssistantCase {
  name: string;
  model: Partial<AssistantInterpretation>;
  modelText?: string;
  context?: AssistantContext;
  expectedStatus: 'NEEDS_INFO' | 'READY';
  expectedIntent: AssistantInterpretation['intent'];
  expectedAction?: string;
  messageIncludes?: string;
}

const route = {
  originQuery: 'Mumbai CSMT',
  destinationQuery: 'Pune Junction',
  travelDate: '2099-10-05',
};
const cases: AssistantCase[] = [
  {
    name: 'unknown intent cannot fall through to Offer a Ride',
    model: { ...route, intent: 'UNKNOWN' },
    expectedStatus: 'NEEDS_INFO', expectedIntent: 'UNKNOWN',
    messageIncludes: 'What would you like to do',
  },
  {
    name: 'unrecognised model intent is normalised to UNKNOWN',
    model: {}, modelText: '{"intent":"UNRECOGNISED"}',
    expectedStatus: 'NEEDS_INFO', expectedIntent: 'UNKNOWN',
    messageIncludes: 'What would you like to do',
  },
  {
    name: 'malformed model output asks for clarification',
    model: {}, modelText: '{invalid json',
    expectedStatus: 'NEEDS_INFO', expectedIntent: 'UNKNOWN',
    messageIncludes: 'What would you like to do',
  },
  {
    name: 'sending without an origin asks for the origin',
    model: { intent: 'SEND_PARCEL', destinationQuery: route.destinationQuery },
    expectedStatus: 'NEEDS_INFO', expectedIntent: 'SEND_PARCEL',
    messageIncludes: 'Where are you starting from',
  },
  {
    name: 'carrying without a date asks for a date',
    model: { ...route, intent: 'TRAVEL_CARRY', travelDate: '', availableWeightKg: 2 },
    expectedStatus: 'NEEDS_INFO', expectedIntent: 'TRAVEL_CARRY',
    messageIncludes: 'What date are you travelling',
  },
  {
    name: 'carrying without capacity asks for spare weight',
    model: { ...route, intent: 'TRAVEL_CARRY' },
    expectedStatus: 'NEEDS_INFO', expectedIntent: 'TRAVEL_CARRY',
    messageIncludes: 'How much spare parcel space',
  },
  {
    name: 'finding a ride without a passenger count asks for seats',
    model: { ...route, intent: 'FIND_RIDE' },
    expectedStatus: 'NEEDS_INFO', expectedIntent: 'FIND_RIDE',
    messageIncludes: 'How many passengers',
  },
  {
    name: 'empty Marketplace search asks for the item',
    model: { intent: 'MARKETPLACE_SEARCH' },
    expectedStatus: 'NEEDS_INFO', expectedIntent: 'MARKETPLACE_SEARCH',
    messageIncludes: 'What are you looking for',
  },
  {
    name: 'Send Parcel selects the sending form',
    model: { ...route, intent: 'SEND_PARCEL' },
    expectedStatus: 'READY', expectedIntent: 'SEND_PARCEL',
    expectedAction: 'OPEN_PARCELPOOL_SEND',
  },
  {
    name: 'Buy-for-Me selects the bringing form',
    model: { ...route, intent: 'BUY_FOR_ME' },
    expectedStatus: 'READY', expectedIntent: 'BUY_FOR_ME',
    expectedAction: 'OPEN_PARCELPOOL_BRING',
  },
  {
    name: 'Offer a Ride selects the ride-offering form',
    model: { ...route, intent: 'OFFER_RIDE' },
    expectedStatus: 'READY', expectedIntent: 'OFFER_RIDE',
    expectedAction: 'OPEN_CARPOOL_OFFER',
  },
  {
    name: 'destination follow-up preserves the earlier intent, origin and date',
    model: { intent: 'UNKNOWN', destinationQuery: route.destinationQuery },
    context: { intent: 'SEND_PARCEL', originQuery: route.originQuery, travelDate: route.travelDate },
    expectedStatus: 'READY', expectedIntent: 'SEND_PARCEL',
    expectedAction: 'OPEN_PARCELPOOL_SEND',
  },
];

const originalFetch = globalThis.fetch;
let modelText = '{}';
let modelCalls = 0;
let unexpectedNetworkCalls = 0;
// Exercise the real interpreter and HTTP handler with canned model output.
// No request is delegated to originalFetch, even on an unexpected code path.
globalThis.fetch = async (input) => {
  const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
  if (url.hostname !== 'generativelanguage.googleapis.com' || !url.pathname.endsWith(':generateContent')) {
    unexpectedNetworkCalls += 1;
    throw new Error(`Unexpected network request in offline suite: ${url.hostname}${url.pathname}`);
  }
  modelCalls += 1;
  return new Response(JSON.stringify({
    candidates: [{
      content: { role: 'model', parts: [{ text: modelText }] },
      finishReason: 'STOP',
    }],
  }), { status: 200, headers: { 'Content-Type': 'application/json' } });
};

const app = Fastify();
try {
  await app.register(sensible);
  for (const [file, name] of [
    ['trips', 'tripRoutes'], ['orders', 'orderRoutes'], ['marketplace', 'marketplaceRoutes'],
    ['rideRequests', 'rideRequestRoutes'], ['chat', 'chatRoutes'], ['tracking', 'trackingRoutes'],
    ['notifications', 'notificationRoutes'], ['history', 'historyRoutes'], ['profile', 'profileRoutes'],
    ['phone_verification', 'phoneVerificationRoutes'], ['identity', 'identityRoutes'],
    ['hopshield', 'hopShieldRoutes'], ['devAuth', 'devAuthRoutes'], ['webhooks', 'webhookRoutes'],
    ['assistant', 'assistantRoutes'],
  ]) {
    const routes = await import(`./routes/${file}.js`);
    await app.register(routes[name!]);
  }
  await app.ready();
  console.log('All backend routes register without conflicts, including the assistant');

  for (const testCase of cases) {
    modelText = testCase.modelText ?? JSON.stringify(testCase.model);
    const response = await app.inject({
      method: 'POST', url: '/assistant/match',
      payload: { message: 'Offline assistant regression fixture', context: testCase.context },
    });
    assert.equal(response.statusCode, 200, `${testCase.name}: HTTP status`);
    const body = response.json();
    assert.equal(body.status, testCase.expectedStatus, testCase.name);
    assert.equal(body.context.intent, testCase.expectedIntent, testCase.name);
    assert.deepEqual(body.matches, [], testCase.name);
    if (testCase.messageIncludes) {
      assert.ok(body.message.includes(testCase.messageIncludes), testCase.name);
    }
    if (testCase.expectedAction) {
      assert.deepEqual(body.action, {
        type: testCase.expectedAction,
        origin: route.originQuery,
        destination: route.destinationQuery,
        date: route.travelDate,
      }, `${testCase.name}: preserve the prefilled route and date`);
    } else {
      assert.equal(body.action, undefined, `${testCase.name}: no action before clarification`);
    }
    console.log(`PASS assistant: ${testCase.name}`);
  }
  assert.equal(modelCalls, cases.length, 'Each request uses its own canned interpretation');
  assert.equal(unexpectedNetworkCalls, 0, 'No database, geocoding or other network requests');
  console.log(`Assistant route regression suite: ${cases.length} passed; zero live network requests`);
} finally {
  await app.close();
  globalThis.fetch = originalFetch;
}

// Batch 2: run the conversational contract alongside the legacy assistant tests.
await import('./test_conversation_suite.js');

// Batch 3B: real HTTP submission/scan handlers with all service calls isolated.
await import('./test_shipment_submission_suite.js');
await import('./test_carpool_alternatives_suite.js');
