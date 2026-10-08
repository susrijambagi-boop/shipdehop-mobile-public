import Fastify from 'fastify';
import sensible from '@fastify/sensible';
import rawBody from 'fastify-raw-body';
import cors from '@fastify/cors';

import { config } from './config.js';
import { adminSupabase } from './lib/supabase.js';
import { interpretConversation, productionConversationDeps, respondToConversation } from './services/conversationAssistant.js';
import { getGeoapifyApiKey, searchGeocodingProvider } from './services/productionGeocoder.js';
import { registerAuth } from './lib/auth.js';

import { chatRoutes } from './routes/chat.js';
import { orderRoutes } from './routes/orders.js';
import { trackingRoutes } from './routes/tracking.js';
import { tripRoutes } from './routes/trips.js';
import { rideRequestRoutes } from './routes/rideRequests.js';
import { webhookRoutes } from './routes/webhooks.js';
import { hopShieldRoutes } from './routes/hopshield.js';
import { devAuthRoutes } from './routes/devAuth.js';
import { notificationRoutes } from './routes/notifications.js';
import { marketplaceRoutes } from './routes/marketplace.js';
import { historyRoutes } from './routes/history.js';
import { profileRoutes } from './routes/profile.js';
import { phoneVerificationRoutes } from './routes/phone_verification.js';
import { identityRoutes } from './routes/identity.js';
import { locationRoutes } from './routes/location.js';
import { policyRoutes } from './routes/policies.js';
import { assistantRoutes } from './routes/assistant.js';
import { whatsappOtpBridge } from './services/whatsapp_otp_bridge.js';

const app = Fastify({
  logger: false,
  pluginTimeout: 0,
});

app.setErrorHandler(
  (error, _request, reply) => {
    const err = error as Error & {
      statusCode?: number;
    };

    if (err.message === 'Not allowed by CORS' || err.statusCode === 403) {
      return reply.code(403).send({
        error: 'CORS_FORBIDDEN',
        message: 'Origin not allowed by CORS policy',
      });
    }

    const status =
      typeof err.statusCode === 'number' &&
        err.statusCode >= 400 &&
        err.statusCode <= 599
        ? err.statusCode
        : 500;

    const message =
      status === 500
        ? 'Internal server error'
        : err.message;

    reply.code(status).send({
      error: err.name || 'Error',
      message,
    });
  },
);

const makeCorsForbiddenError = () => {
  const err = new Error('Not allowed by CORS') as any;
  err.statusCode = 403;
  return err;
};

app.register(cors, {
  origin: (origin, cb) => {
    if (!origin) return cb(null, true);
    if (config.NODE_ENV === 'production') {
      if (config.ALLOWED_ORIGINS.length > 0 && config.ALLOWED_ORIGINS.includes(origin)) {
        return cb(null, true);
      }
      return cb(makeCorsForbiddenError(), false);
    }
    if (
      /^https?:\/\/localhost(:\d+)?$/.test(origin) ||
      /^https?:\/\/127\.0\.0\.1(:\d+)?$/.test(origin) ||
      (config.ALLOWED_ORIGINS.length > 0 && config.ALLOWED_ORIGINS.includes(origin)) ||
      (config.DEV_TEST_AUTH && (
        /^https?:\/\/(192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+)(:\d+)?$/.test(origin) ||
        /^https:\/\/[a-z0-9-]+\.trycloudflare\.com$/.test(origin)
      ))
    ) {
      return cb(null, true);
    }
    return cb(makeCorsForbiddenError(), false);
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type', 'Accept', 'X-Requested-With'],
  credentials: true,
});

app.register(sensible);

app.register(rawBody, {
  field: 'rawBody',
  global: false,
  encoding: false,
  runFirst: true,
});

app.register(registerAuth);

app.get('/health', async () => ({
  ok: true,
}));


app.register(tripRoutes);
app.register(rideRequestRoutes);
app.register(orderRoutes);
app.register(notificationRoutes);
app.register(chatRoutes);
app.register(hopShieldRoutes);
app.register(trackingRoutes);
app.register(webhookRoutes);
app.register(marketplaceRoutes);
app.register(historyRoutes);
app.register(profileRoutes);
app.register(phoneVerificationRoutes);
app.register(identityRoutes);
app.register(locationRoutes);
app.register(policyRoutes);
app.register(assistantRoutes);
app.register(devAuthRoutes);
const runStartupDependencyProbe = async () => {
  if (!config.STARTUP_DEPENDENCY_PROBE) return;

  const timeout = (ms: number) =>
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error('probe timed out')), ms),
    );

  const safeError = (error: unknown, secret?: string): Record<string, unknown> => {
    const err = error as { status?: unknown; code?: unknown; name?: unknown; message?: unknown };
    let message = typeof err?.message === 'string' ? err.message : String(error);
    if (secret) message = message.split(secret).join('[redacted]');
    message = message.replace(/AIza[0-9A-Za-z_-]{20,}/g, '[redacted]');
    return {
      errorName: typeof err?.name === 'string' ? err.name : 'Error',
      ...(typeof err?.status === 'number' ? { status: err.status } : {}),
      ...(typeof err?.code === 'string' || typeof err?.code === 'number' ? { code: err.code } : {}),
      message: message.slice(0, 240),
    };
  };

  console.log(JSON.stringify({
    event: 'startup_dependency_probe',
    dependency: 'probe',
    ok: true,
    state: 'started',
  }));

  try {
    const response = await Promise.race([
      Promise.resolve(
        adminSupabase.from('user_identities').select('id').limit(1),
      ),
      timeout(10000),
    ]);
    const error = (response as { error?: unknown }).error;
    console.log(JSON.stringify({
      event: 'startup_dependency_probe',
      dependency: 'supabase',
      ok: !error,
    }));
  } catch (error) {
    console.log(JSON.stringify({
      event: 'startup_dependency_probe',
      dependency: 'supabase',
      ok: false,
      ...safeError(error),
    }));
  }

  try {
    const raw = await Promise.race([
      interpretConversation(
        { message: 'Hi, what do you do?', context: {}, history: [] },
        new Date(),
      ),
      timeout(18000),
    ]);
    console.log(JSON.stringify({
      event: 'startup_dependency_probe',
      dependency: 'gemini',
      ok: typeof raw === 'string' && raw.length > 0,
    }));
  } catch (error) {
    console.log(JSON.stringify({
      event: 'startup_dependency_probe',
      dependency: 'gemini',
      ok: false,
      ...safeError(error, config.GEMINI_API_KEY),
    }));
  }

  const geoapifyKey = getGeoapifyApiKey();
  try {
    const results = await Promise.race([
      searchGeocodingProvider('Mumbai CSMT'),
      timeout(12000),
    ]);
    console.log(JSON.stringify({
      event: 'startup_dependency_probe',
      dependency: 'location_search',
      ok: results.length > 0,
      provider: results[0]?.provenance ?? 'none',
      geoapifyConfigured: Boolean(geoapifyKey),
    }));
  } catch (error) {
    console.log(JSON.stringify({
      event: 'startup_dependency_probe',
      dependency: 'location_search',
      ok: false,
      geoapifyConfigured: Boolean(geoapifyKey),
      ...safeError(error, geoapifyKey),
    }));
  }

  try {
    const answer = await Promise.race([
      respondToConversation(
        { message: 'Hi, what do you do?', context: {}, history: [] },
        productionConversationDeps(adminSupabase),
        new Date(),
      ),
      timeout(18000),
    ]);
    console.log(JSON.stringify({
      event: 'startup_dependency_probe',
      dependency: 'assistant_resilient',
      ok: typeof answer?.message === 'string' && answer.message.length > 0 &&
        answer.status !== 'UNAVAILABLE',
      status: answer?.status,
    }));
  } catch (error) {
    console.log(JSON.stringify({
      event: 'startup_dependency_probe',
      dependency: 'assistant_resilient',
      ok: false,
      ...safeError(error, config.GEMINI_API_KEY),
    }));
  }

  console.log(JSON.stringify({
    event: 'startup_dependency_probe',
    dependency: 'probe',
    ok: true,
    state: 'finished',
  }));
};

app.listen({
  port: config.PORT,
  host: '0.0.0.0',
}).then(async () => {
  if (config.PHONE_VERIFICATION_ENABLED && config.PHONE_VERIFICATION_PROVIDER === 'WHATSAPP_OUTBOUND') {
    void whatsappOtpBridge.start();
  }
  await runStartupDependencyProbe();
}).catch((error) => {
  app.log.error(error);
  process.exit(1);
});