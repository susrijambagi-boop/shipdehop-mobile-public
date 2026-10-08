import assert from 'node:assert/strict';
import fastify from 'fastify';
import sensible from '@fastify/sensible';
import { phoneVerificationRoutes } from './routes/phone_verification.js';
import { locationRoutes } from './routes/location.js';
import { config } from './config.js';
import { getGeoapifyCache, setGeoapifyCache } from './services/geoapifyCache.js';

console.log('=== CLOUDFLARE STABILIZATION SUITE ===');

async function testLegacyWhatsAppWebhookIsRemoved() {
  console.log('\n--- 1. Legacy WhatsApp Webhook Removal Test ---');
  const app = fastify();
  await app.register(sensible);
  await app.register(phoneVerificationRoutes);

  const responseGet = await app.inject({
    method: 'GET',
    url: '/webhooks/whatsapp?hub.mode=subscribe&hub.verify_token=shipdehop_wa_verify_token&hub.challenge=12345',
  });
  assert.equal(responseGet.statusCode, 404, 'Legacy GET /webhooks/whatsapp must not exist under outbound OTP auth');

  const responsePost = await app.inject({
    method: 'POST',
    url: '/webhooks/whatsapp',
    payload: {
      entry: [{
        changes: [{
          value: {
            messages: [{ from: '919876543210', text: { body: 'VERIFY SHIPDEHOP ABC123' } }],
          },
        }],
      }],
    },
  });
  assert.equal(responsePost.statusCode, 404, 'Legacy POST /webhooks/whatsapp must not exist under outbound OTP auth');
  console.log('  ✓ Legacy inbound WhatsApp webhooks are absent under outbound OTP auth');
}

async function testGeoapifyCacheKeySafety() {
  console.log('\n--- 2. Geoapify Cache Key Safety Test ---');
  // Confirm cache operations return null / no-op in Node without error
  const cacheVal = await getGeoapifyCache('https://cache.shipdehop.internal/test');
  assert.equal(cacheVal, null, 'Node environment without caches.default returns null');

  await setGeoapifyCache('https://cache.shipdehop.internal/test', { ok: true }, 60);
  console.log('  ✓ Cache API operates safely and gracefully in Node environments');
}

async function testRouteRegistration() {
  console.log('\n--- 3. Location Routes Registration Test ---');
  const app = fastify();
  await app.register(sensible);
  await app.register(locationRoutes);

  const resSearch = await app.inject({
    method: 'GET',
    url: '/location/search?q=Bengaluru',
  });
  assert.equal(resSearch.statusCode, 200, 'Search route operates correctly');
  console.log('  ✓ Location search route registered and returning HTTP 200');
}

async function runAll() {
  await testLegacyWhatsAppWebhookIsRemoved();
  await testGeoapifyCacheKeySafety();
  await testRouteRegistration();
  console.log('\n🎉 ALL CLOUDFLARE STABILIZATION SUITE TESTS PASSED!\n');
}

runAll().catch((err) => {
  console.error('❌ CLOUDFLARE STABILIZATION SUITE FAILED:', err);
  process.exit(1);
});
