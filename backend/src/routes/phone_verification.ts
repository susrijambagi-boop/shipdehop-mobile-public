import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { getPhoneVerificationProvider, normalizePhoneNumber } from '../services/phone_verification.js';
import { JwtSessionManager } from '../services/jwt_session.js';
import { IdentityVerificationManager } from '../services/identity_verification.js';
import { config } from '../config.js';

function parseCookie(cookieHeader: string | undefined, name: string): string | undefined {
  if (!cookieHeader) return undefined;
  const match = cookieHeader.match(new RegExp(`(?:^|;\\s*)${name}=([^;]*)`));
  return match && match[1] ? decodeURIComponent(match[1]) : undefined;
}

export function isValidAllowedOrigin(origin: string | undefined): boolean {
  if (!origin) return true; // Server-to-server or native mobile non-browser calls
  try {
    const url = new URL(origin);
    const originNormalized = `${url.protocol}//${url.host}`.toLowerCase();

    const allowed = config.ALLOWED_ORIGINS && config.ALLOWED_ORIGINS.length > 0
      ? config.ALLOWED_ORIGINS.map((o: string) => o.toLowerCase())
      : ['https://shipdehop-app.pages.dev'];

    if (allowed.includes(originNormalized)) {
      return true;
    }

    if (config.NODE_ENV !== 'production') {
      const hostname = url.hostname;
      if (hostname === 'localhost' || hostname === '127.0.0.1') {
        return true;
      }
    }

    return false;
  } catch {
    return false;
  }
}

export const phoneVerificationRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  // 1. Start phone verification session
  fastify.post('/auth/phone/start', async (request, reply) => {
    if (!config.PHONE_VERIFICATION_ENABLED && config.NODE_ENV === 'production') {
      return reply.code(503).send({ error: 'Phone verification is currently disabled in production.' });
    }

    const bodySchema = z.object({
      phoneNumber: z.string().min(5),
      countryCode: z.string().default('+91'),
    });

    const parsed = bodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid phone number or country code' });
    }

    try {
      const normalized = normalizePhoneNumber(parsed.data.phoneNumber, parsed.data.countryCode);
      const provider = getPhoneVerificationProvider();
      const result = await provider.startVerification(normalized);

      return reply.send({
        sessionId: result.sessionId,
        challenge: result.challenge,
        whatsappUrl: result.whatsappUrl,
        expiresAt: result.expiresAt,
        phoneE164: normalized,
      });
    } catch (e: any) {
      const msg = e.message || 'Failed to start phone verification';
      const isRateLimit = msg.includes('Please wait 30 seconds') || msg.includes('Too many active verification');
      return reply.code(isRateLimit ? 429 : 400).send({ error: msg });
    }
  });

  // 2. Read-only phone verification status check (Does NOT mint tokens or set cookies)
  fastify.get('/auth/phone/status/:sessionId', async (request, reply) => {
    const paramsSchema = z.object({
      sessionId: z.string().uuid(),
    });

    const parsed = paramsSchema.safeParse(request.params);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid session ID' });
    }

    try {
      const provider = getPhoneVerificationProvider();
      const status = await provider.getSessionStatus(parsed.data.sessionId);
      return reply.send(status);
    } catch (e: any) {
      return reply.code(404).send({ error: e.message || 'Session not found' });
    }
  });

  // 3. Single-Use Exchange: Atomically consumes verified session and mints JWT + HttpOnly refresh cookie
  fastify.post('/auth/phone/exchange', async (request, reply) => {
    if (!config.PHONE_VERIFICATION_ENABLED && config.NODE_ENV === 'production') {
      return reply.code(503).send({ error: 'Phone verification is currently disabled in production.' });
    }

    const origin = request.headers.origin || request.headers.referer;
    if (!isValidAllowedOrigin(origin)) {
      return reply.code(403).send({ error: 'Forbidden origin for session exchange' });
    }

    const bodySchema = z.object({
      sessionId: z.string().uuid(),
    });

    const parsed = bodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid exchange payload. Valid sessionId is required.' });
    }

    try {
      const provider = getPhoneVerificationProvider();
      // Atomically consume verification session (fails if already consumed, unverified, or expired)
      const { phoneE164 } = await provider.consumeSession(parsed.data.sessionId);

      // Locate or create canonical Supabase auth.users UUID
      const canonicalUserId = await JwtSessionManager.getOrCreateCanonicalUserByPhone(phoneE164);
      // Mint short-lived access JWT (15-min TTL)
      const accessToken = JwtSessionManager.mintUserAccessJwt(canonicalUserId, phoneE164);
      // Create single-use refresh token session
      const { refreshToken, expiresAt } = await JwtSessionManager.createRefreshSession(canonicalUserId);

      // Issue HttpOnly, Secure cookie at /api/auth/session
      reply.header('Set-Cookie', `shipdehop_refresh_token=${refreshToken}; Path=/api/auth/session; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000`);

      const identity = await IdentityVerificationManager.getIdentity(canonicalUserId);
      const identityStatus = identity?.verificationStatus || 'NOT_STARTED';

      return reply.send({
        id: parsed.data.sessionId,
        userId: canonicalUserId,
        phoneE164,
        accessToken,
        identityStatus,
        isIdentityVerified: identityStatus === 'VERIFIED',
        sessionExpiresAt: expiresAt.toISOString(),
      });
    } catch (e: any) {
      return reply.code(400).send({ error: e.message || 'Failed to exchange verification session' });
    }
  });

  // 4. Refresh Token Rotation (Supports HttpOnly Cookie & Body Token)
  fastify.post('/auth/session/refresh', async (request, reply) => {
    const origin = request.headers.origin || request.headers.referer;
    if (!isValidAllowedOrigin(origin)) {
      return reply.code(403).send({ error: 'Forbidden origin for session refresh' });
    }

    const cookieToken = parseCookie(request.headers.cookie, 'shipdehop_refresh_token');
    const bodyToken = (request.body as any)?.refreshToken;
    const token = cookieToken || bodyToken;

    if (!token || typeof token !== 'string' || token.length < 10) {
      return reply.code(401).send({ error: 'Missing or invalid refresh session token' });
    }

    try {
      const deviceId = (request.body as any)?.deviceId;
      const result = await JwtSessionManager.rotateRefreshSession(token, deviceId);

      // Set rotated HttpOnly cookie at /api/auth/session
      reply.header('Set-Cookie', `shipdehop_refresh_token=${result.newRefreshToken}; Path=/api/auth/session; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000`);

      const identity = await IdentityVerificationManager.getIdentity(result.userId);
      const identityStatus = identity?.verificationStatus || 'NOT_STARTED';

      return reply.send({
        accessToken: result.accessToken,
        userId: result.userId,
        identityStatus,
        isIdentityVerified: identityStatus === 'VERIFIED',
        expiresAt: result.expiresAt.toISOString(),
      });
    } catch (e: any) {
      return reply.code(401).send({ error: e.message || 'Refresh failed' });
    }
  });

  // 5. Logout / Session Revocation
  fastify.post('/auth/session/logout', async (request, reply) => {
    const origin = request.headers.origin || request.headers.referer;
    if (!isValidAllowedOrigin(origin)) {
      return reply.code(403).send({ error: 'Forbidden origin for logout' });
    }

    const cookieToken = parseCookie(request.headers.cookie, 'shipdehop_refresh_token');
    const bodyToken = (request.body as any)?.refreshToken;
    const token = cookieToken || bodyToken;

    if (token) {
      await JwtSessionManager.revokeSession(token);
    }

    // Clear refresh cookie at /api/auth/session
    reply.header('Set-Cookie', 'shipdehop_refresh_token=; Path=/api/auth/session; HttpOnly; Secure; SameSite=Lax; Max-Age=0');

    return reply.send({ success: true, message: 'Session logged out' });
  });

  // 6. Inbound WhatsApp Cloud API Webhook (Verification handshake)
  fastify.get('/webhooks/whatsapp', async (request, reply) => {
    if (config.PHONE_VERIFICATION_PROVIDER !== 'WHATSAPP_INBOUND') {
      return reply.code(403).send({ error: 'WhatsApp webhooks disabled under MANUAL_BETA provider mode.' });
    }

    const query = request.query as Record<string, string>;
    const mode = query['hub.mode'];
    const token = query['hub.verify_token'];
    const challenge = query['hub.challenge'];

    if (mode === 'subscribe' && token === config.WHATSAPP_WEBHOOK_VERIFY_TOKEN) {
      return reply.code(200).send(challenge);
    }
    return reply.code(403).send({ error: 'Forbidden webhook verification' });
  });

  // 7. Inbound WhatsApp Cloud API Webhook (Event Notification)
  fastify.post('/webhooks/whatsapp', async (request, reply) => {
    if (config.PHONE_VERIFICATION_PROVIDER !== 'WHATSAPP_INBOUND') {
      return reply.code(403).send({ error: 'WhatsApp webhooks disabled under MANUAL_BETA provider mode.' });
    }

    try {
      const body = request.body as any;
      if (body?.entry) {
        for (const entry of body.entry) {
          if (entry.changes) {
            for (const change of entry.changes) {
              const value = change.value;
              if (value?.messages) {
                for (const msg of value.messages) {
                  const senderPhone = '+' + msg.from;
                  const textBody = msg.text?.body || '';
                  const provider = getPhoneVerificationProvider();
                  await provider.processInboundMessage(senderPhone, textBody);
                }
              }
            }
          }
        }
      }
      return reply.code(200).send({ status: 'ok' });
    } catch (e: any) {
      fastify.log.error(e);
      return reply.code(200).send({ status: 'error_logged' });
    }
  });

  // 8. Development/Test simulated inbound verification (Disabled in production)
  fastify.post('/auth/phone/dev-simulate-inbound', async (request, reply) => {
    if (config.NODE_ENV === 'production') {
      return reply.code(403).send({ error: 'Endpoint forbidden in production.' });
    }

    const bodySchema = z.object({
      senderPhone: z.string(),
      messageText: z.string(),
    });

    const parsed = bodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid input' });
    }

    const provider = getPhoneVerificationProvider();
    const result = await provider.processInboundMessage(parsed.data.senderPhone, parsed.data.messageText);
    return reply.send(result);
  });
};
