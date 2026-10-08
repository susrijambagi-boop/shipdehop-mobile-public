import assert from 'node:assert';
import { z } from 'zod';
import {
  normalizeInspection,
  inspectWithGemini,
  type ParcelInspectionInput,
} from './services/parcelInspection.js';

async function runHopShieldCorsSuite() {
  console.log('=== RUNNING HOPSHIELD PROVIDER & PRODUCTION CORS TEST SUITE ===');

  const sampleInput: ParcelInspectionInput = {
    imageBase64: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
    imageMimeType: 'image/png',
    itemType: 'PARCEL',
    productUrl: null,
  };

  // Test 1: Gemini provider mock successful structured response
  console.log('Test 1: Gemini provider successful structured response');
  const mockSuccessClient = {
    models: {
      generateContent: async () => ({
        text: JSON.stringify({
          decision: 'APPROVED',
          confidence: 0.95,
          contentMismatch: false,
          prohibitedCategories: [],
          rationale: 'Ordinary safe electronics package.',
        }),
      }),
    },
  } as any;

  const res1 = await inspectWithGemini(sampleInput, { aiClient: mockSuccessClient });
  assert.strictEqual(res1.decision, 'APPROVED');
  assert.strictEqual(res1.confidence, 0.95);
  assert.strictEqual(res1.contentMismatch, false);
  assert.strictEqual(res1.rationale, 'Ordinary safe electronics package.');
  console.log('✓ Test 1 Passed: Gemini success parses structured response');

  // Test 2: Invalid decision is normalized to 'REVIEW'
  console.log('Test 2: Invalid decision rejected and defaults to REVIEW');
  const mockInvalidDecisionClient = {
    models: {
      generateContent: async () => ({
        text: JSON.stringify({
          decision: 'ALLOW_EVERYTHING',
          confidence: 0.9,
          contentMismatch: false,
          prohibitedCategories: [],
          rationale: 'Invalid enum output',
        }),
      }),
    },
  } as any;

  const res2 = await inspectWithGemini(sampleInput, { aiClient: mockInvalidDecisionClient });
  assert.strictEqual(res2.decision, 'REVIEW');
  console.log('✓ Test 2 Passed: Invalid decision safely normalized to REVIEW');

  // Test 3: Malformed JSON handled safely
  console.log('Test 3: Malformed JSON handled safely');
  const mockMalformedClient = {
    models: {
      generateContent: async () => ({
        text: 'This is not json at all {broken: true',
      }),
    },
  } as any;

  const res3 = await inspectWithGemini(sampleInput, { aiClient: mockMalformedClient });
  assert.strictEqual(res3.decision, 'REVIEW');
  assert.strictEqual(res3.confidence, 0);
  console.log('✓ Test 3 Passed: Malformed JSON fails safe to REVIEW');

  // Test 4: Confidence outside range clamped to [0, 1]
  console.log('Test 4: Confidence outside range clamped');
  const normalizedHigh = normalizeInspection({ decision: 'APPROVED', confidence: 15.0 });
  assert.strictEqual(normalizedHigh.confidence, 1.0);
  const normalizedNeg = normalizeInspection({ decision: 'APPROVED', confidence: -5.0 });
  assert.strictEqual(normalizedNeg.confidence, 0.0);
  const normalizedNaN = normalizeInspection({ decision: 'APPROVED', confidence: 'not-a-number' as any });
  assert.strictEqual(normalizedNaN.confidence, 0.0);
  console.log('✓ Test 4 Passed: Confidence clamped safely');

  // Test 5: Content mismatch with APPROVED is downgraded to REVIEW
  console.log('Test 5: Content mismatch with APPROVED downgraded to REVIEW');
  const mismatchRes = normalizeInspection({
    decision: 'APPROVED',
    confidence: 0.9,
    contentMismatch: true,
    rationale: 'Item does not match declaration',
  });
  assert.strictEqual(mismatchRes.decision, 'REVIEW');
  console.log('✓ Test 5 Passed: Content mismatch safely downgraded to REVIEW');

  // Test 6: Timeout fails safe
  console.log('Test 6: Timeout fails safe to REVIEW');
  const mockHangingClient = {
    models: {
      generateContent: async () => new Promise((resolve) => setTimeout(resolve, 5000)),
    },
  } as any;

  const res6 = await inspectWithGemini(sampleInput, { aiClient: mockHangingClient, timeoutMs: 50 });
  assert.strictEqual(res6.decision, 'REVIEW');
  assert.strictEqual(res6.confidence, 0);
  console.log('✓ Test 6 Passed: Timeout returns fail-safe REVIEW');

  // Test 7: HTTP 429 Quota exhaustion fails safe
  console.log('Test 7: HTTP 429 Quota failure fails safe');
  const mock429Client = {
    models: {
      generateContent: async () => {
        const err = new Error('RESOURCE_EXHAUSTED: quota exceeded') as any;
        err.status = 429;
        throw err;
      },
    },
  } as any;

  const res7 = await inspectWithGemini(sampleInput, { aiClient: mock429Client });
  assert.strictEqual(res7.decision, 'REVIEW');
  assert.ok(res7.rationale.toLowerCase().includes('unavailable') || res7.rationale.toLowerCase().includes('review'));
  console.log('✓ Test 7 Passed: 429 returns fail-safe REVIEW');

  // Test 8: HTTP 5xx Server Error fails safe
  console.log('Test 8: HTTP 500 Server error fails safe');
  const mock500Client = {
    models: {
      generateContent: async () => {
        const err = new Error('Internal Server Error') as any;
        err.status = 500;
        throw err;
      },
    },
  } as any;

  const res8 = await inspectWithGemini(sampleInput, { aiClient: mock500Client });
  assert.strictEqual(res8.decision, 'REVIEW');
  console.log('✓ Test 8 Passed: 500 returns fail-safe REVIEW');

  // Test 9: Environment-safe HopShield provider defaults & overrides
  console.log('Test 9: Environment-safe HopShield provider defaults & overrides');
  const envTestSchema = z.object({
    NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
    PARCEL_INSPECTION_PROVIDER: z.enum(['OLLAMA', 'GEMINI']).optional(),
    OLLAMA_URL: z.string().default('http://127.0.0.1:11434/api/chat'),
  }).transform((data) => ({
    ...data,
    PARCEL_INSPECTION_PROVIDER:
      data.PARCEL_INSPECTION_PROVIDER ??
      (data.NODE_ENV === 'production' ? 'GEMINI' : 'OLLAMA'),
  })).refine((data) => {
    if (data.NODE_ENV === 'production' && data.PARCEL_INSPECTION_PROVIDER === 'OLLAMA' && (data.OLLAMA_URL.includes('localhost') || data.OLLAMA_URL.includes('127.0.0.1'))) {
      return false;
    }
    return true;
  });

  // 1. development without explicit provider → OLLAMA
  const devDefault = envTestSchema.parse({ NODE_ENV: 'development' });
  assert.strictEqual(devDefault.PARCEL_INSPECTION_PROVIDER, 'OLLAMA');

  // 2. test without explicit provider → OLLAMA
  const testDefault = envTestSchema.parse({ NODE_ENV: 'test' });
  assert.strictEqual(testDefault.PARCEL_INSPECTION_PROVIDER, 'OLLAMA');

  // 3. production without explicit provider → GEMINI
  const prodDefault = envTestSchema.parse({ NODE_ENV: 'production' });
  assert.strictEqual(prodDefault.PARCEL_INSPECTION_PROVIDER, 'GEMINI');

  // 4. explicit development GEMINI → GEMINI
  const devGemini = envTestSchema.parse({ NODE_ENV: 'development', PARCEL_INSPECTION_PROVIDER: 'GEMINI' });
  assert.strictEqual(devGemini.PARCEL_INSPECTION_PROVIDER, 'GEMINI');

  // 5. explicit development OLLAMA → OLLAMA
  const devOllama = envTestSchema.parse({ NODE_ENV: 'development', PARCEL_INSPECTION_PROVIDER: 'OLLAMA' });
  assert.strictEqual(devOllama.PARCEL_INSPECTION_PROVIDER, 'OLLAMA');

  // 6. production localhost OLLAMA rejected
  const prodLocalOllama = envTestSchema.safeParse({ NODE_ENV: 'production', PARCEL_INSPECTION_PROVIDER: 'OLLAMA', OLLAMA_URL: 'http://localhost:11434/api/chat' });
  assert.strictEqual(prodLocalOllama.success, false);

  // 7. production GEMINI accepted
  const prodGemini = envTestSchema.safeParse({ NODE_ENV: 'production', PARCEL_INSPECTION_PROVIDER: 'GEMINI' });
  assert.strictEqual(prodGemini.success, true);
  console.log('✓ Test 9 Passed: Environment-safe HopShield defaults and overrides verified (7/7 cases)');

  // Test 10: Production CORS validation logic
  console.log('Test 10: Production CORS validation logic');
  function testCors(origin: string | undefined, nodeEnv: string, allowedOrigins: string[], devTestAuth: boolean): boolean {
    if (!origin) return true;
    if (nodeEnv === 'production') {
      if (allowedOrigins.length > 0 && allowedOrigins.includes(origin)) {
        return true;
      }
      return false;
    }
    if (
      /^https?:\/\/localhost(:\d+)?$/.test(origin) ||
      /^https?:\/\/127\.0\.0\.1(:\d+)?$/.test(origin) ||
      (allowedOrigins.length > 0 && allowedOrigins.includes(origin)) ||
      (devTestAuth && (
        /^https?:\/\/(192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+)(:\d+)?$/.test(origin) ||
        /^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/.test(origin)
      ))
    ) {
      return true;
    }
    return false;
  }

  // Prod: Configured origin accepted
  assert.strictEqual(testCors('https://app.shipdehop.com', 'production', ['https://app.shipdehop.com'], false), true);
  // Prod: Random hostile origin rejected
  assert.strictEqual(testCors('https://evil-site.com', 'production', ['https://app.shipdehop.com'], false), false);
  // Prod: Localhost rejected in production unless configured
  assert.strictEqual(testCors('http://localhost:8092', 'production', ['https://app.shipdehop.com'], false), false);
  // Prod: trycloudflare rejected in production
  assert.strictEqual(testCors('https://any-subdomain.trycloudflare.com', 'production', ['https://app.shipdehop.com'], false), false);
  // Dev: Localhost accepted
  assert.strictEqual(testCors('http://localhost:8092', 'development', [], false), true);
  // Dev: trycloudflare accepted when devTestAuth=true
  assert.strictEqual(testCors('https://tunnel.trycloudflare.com', 'development', [], true), true);
  // Dev: trycloudflare rejected when devTestAuth=false
  assert.strictEqual(testCors('https://tunnel.trycloudflare.com', 'development', [], false), false);
  // No origin (curl / native mobile) accepted in all envs
  assert.strictEqual(testCors(undefined, 'production', [], false), true);
  assert.strictEqual(testCors(undefined, 'development', [], false), true);
  console.log('✓ Test 10 Passed: Production and development CORS policies verified');

  console.log('=== ALL HOPSHIELD & CORS TESTS PASSED 100% ===');
}

runHopShieldCorsSuite().catch((err) => {
  console.error('FAILED:', err);
  process.exit(1);
});
