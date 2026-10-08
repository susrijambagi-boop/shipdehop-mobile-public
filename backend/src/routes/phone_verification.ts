import { FastifyInstance, FastifyPluginAsync } from 'fastify';
import { z } from 'zod';

import { config } from '../config.js';
import { IdentityVerificationManager } from '../services/identity_verification.js';
import { JwtSessionManager } from '../services/jwt_session.js';
import {
  consumeWhatsAppOtpSession,
  getWhatsAppOtpStatus,
  startWhatsAppOtp,
  verifyWhatsAppOtp,
} from '../services/whatsapp_otp.js';
import { whatsappOtpBridge } from '../services/whatsapp_otp_bridge.js';

function parseCookie(cookieHeader: string | undefined, name: string): string | undefined {
  if (!cookieHeader) return undefined;
  const match = cookieHeader.match(new RegExp(`(?:^|;\\s*)${name}=([^;]*)`));
  return match && match[1] ? decodeURIComponent(match[1]) : undefined;
}

function errorStatus(error: any, fallback = 400): number {
  const status = Number(error?.statusCode);
  return Number.isInteger(status) && status >= 400 && status <= 599 ? status : fallback;
}

function isAdmin(request: any): boolean {
  return request?.authUser?.app_metadata?.role?.toString().trim().toLowerCase() === 'admin';
}

export function isValidAllowedOrigin(origin: string | undefined): boolean {
  if (!origin) return true;

  try {
    const url = new URL(origin);
    const normalized = `${url.protocol}//${url.host}`.toLowerCase();

    const allowed = config.ALLOWED_ORIGINS && config.ALLOWED_ORIGINS.length > 0
      ? config.ALLOWED_ORIGINS.map((item: string) => item.toLowerCase())
      : ['https://shipdehop-app.pages.dev'];

    if (allowed.includes(normalized)) return true;

    if (config.NODE_ENV !== 'production') {
      return url.hostname === 'localhost' || url.hostname === '127.0.0.1';
    }

    return false;
  } catch {
    return false;
  }
}

export const phoneVerificationRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  // 1. Generate + deliver a 6-digit OTP to the user's WhatsApp number.
  fastify.post('/auth/phone/start', async (request, reply) => {
    if (!config.PHONE_VERIFICATION_ENABLED && config.NODE_ENV === 'production') {
      return reply.code(503).send({
        error: 'PHONE_VERIFICATION_DISABLED',
        message: 'Phone verification is currently unavailable.',
      });
    }

    const parsed = z.object({
      phoneNumber: z.string().min(5),
      countryCode: z.string().default('+91'),
    }).safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: 'INVALID_PHONE',
        message: 'Enter a valid Indian mobile number.',
      });
    }

    try {
      const result = await startWhatsAppOtp(parsed.data.phoneNumber, parsed.data.countryCode);
      return reply.send(result);
    } catch (error: any) {
      return reply.code(errorStatus(error, 503)).send({
        error: errorStatus(error) === 429 ? 'OTP_RATE_LIMITED' : 'WHATSAPP_OTP_SEND_FAILED',
        message: error?.message || 'Could not send WhatsApp OTP.',
      });
    }
  });

  // 2. Verify the 6-digit OTP. Verification itself never creates a login token.
  fastify.post('/auth/phone/verify', async (request, reply) => {
    const parsed = z.object({
      sessionId: z.string().uuid(),
      otp: z.string().regex(/^\d{6}$/),
    }).safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: 'INVALID_OTP_PAYLOAD',
        message: 'Enter the 6-digit WhatsApp OTP.',
      });
    }

    try {
      return reply.send(await verifyWhatsAppOtp(parsed.data.sessionId, parsed.data.otp));
    } catch (error: any) {
      return reply.code(errorStatus(error)).send({
        error: 'OTP_VERIFICATION_FAILED',
        message: error?.message || 'OTP verification failed.',
      });
    }
  });

  // 3. Read-only status for session restore / expiry handling.
  fastify.get('/auth/phone/status/:sessionId', async (request, reply) => {
    const parsed = z.object({ sessionId: z.string().uuid() }).safeParse(request.params);

    if (!parsed.success) {
      return reply.code(400).send({
        error: 'INVALID_SESSION_ID',
        message: 'Invalid OTP session.',
      });
    }

    try {
      return reply.send(await getWhatsAppOtpStatus(parsed.data.sessionId));
    } catch (error: any) {
      return reply.code(errorStatus(error, 404)).send({
        error: 'OTP_SESSION_NOT_FOUND',
        message: error?.message || 'OTP session not found.',
      });
    }
  });

  // 4. Single-use exchange of a verified OTP session for the ShipdeHop session.
  fastify.post('/auth/phone/exchange', async (request, reply) => {
    if (!config.PHONE_VERIFICATION_ENABLED && config.NODE_ENV === 'production') {
      return reply.code(503).send({
        error: 'PHONE_VERIFICATION_DISABLED',
        message: 'Phone verification is currently unavailable.',
      });
    }

    const origin = request.headers.origin || request.headers.referer;
    const nativeMobile = !origin && request.headers['x-shipdehop-client'] === 'mobile';
    if (!nativeMobile && !isValidAllowedOrigin(origin)) {
      return reply.code(403).send({
        error: 'FORBIDDEN_ORIGIN',
        message: 'Forbidden origin for session exchange.',
      });
    }

    const parsed = z.object({ sessionId: z.string().uuid() }).safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        error: 'INVALID_EXCHANGE_PAYLOAD',
        message: 'A valid verified OTP session is required.',
      });
    }

    try {
      const { phoneE164 } = await consumeWhatsAppOtpSession(parsed.data.sessionId);

      const canonicalUserId = await JwtSessionManager.getOrCreateCanonicalUserByPhone(phoneE164);
      const accessToken = JwtSessionManager.mintUserAccessJwt(canonicalUserId, phoneE164);
      const { refreshToken, expiresAt } = await JwtSessionManager.createRefreshSession(canonicalUserId);

      reply.header(
        'Set-Cookie',
        `shipdehop_refresh_token=${refreshToken}; Path=/auth/session; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000`,
      );

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
        ...(nativeMobile ? { refreshToken } : {}),
      });
    } catch (error: any) {
      return reply.code(errorStatus(error)).send({
        error: 'SESSION_EXCHANGE_FAILED',
        message: error?.message || 'Failed to create ShipdeHop session.',
      });
    }
  });

  // Session rotation.
  fastify.post('/auth/session/refresh', async (request, reply) => {
    const origin = request.headers.origin || request.headers.referer;
    const nativeMobile = !origin && request.headers['x-shipdehop-client'] === 'mobile';
    if (!nativeMobile && !isValidAllowedOrigin(origin)) {
      return reply.code(403).send({
        error: 'FORBIDDEN_ORIGIN',
        message: 'Forbidden origin for session refresh.',
      });
    }

    const cookieToken = parseCookie(request.headers.cookie, 'shipdehop_refresh_token');
    const bodyToken = (request.body as any)?.refreshToken;
    const token = cookieToken || bodyToken;

    if (!token || typeof token !== 'string' || token.length < 10) {
      return reply.code(401).send({
        error: 'MISSING_REFRESH_TOKEN',
        message: 'Missing or invalid refresh session token.',
      });
    }

    try {
      const deviceId = (request.body as any)?.deviceId;
      const result = await JwtSessionManager.rotateRefreshSession(token, deviceId);

      reply.header(
        'Set-Cookie',
        `shipdehop_refresh_token=${result.newRefreshToken}; Path=/auth/session; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000`,
      );

      const identity = await IdentityVerificationManager.getIdentity(result.userId);
      const identityStatus = identity?.verificationStatus || 'NOT_STARTED';

      return reply.send({
        accessToken: result.accessToken,
        userId: result.userId,
        identityStatus,
        isIdentityVerified: identityStatus === 'VERIFIED',
        expiresAt: result.expiresAt.toISOString(),
        ...(nativeMobile ? { refreshToken: result.newRefreshToken } : {}),
      });
    } catch (error: any) {
      return reply.code(401).send({
        error: 'REFRESH_FAILED',
        message: error?.message || 'Refresh failed.',
      });
    }
  });

  fastify.post('/auth/session/logout', async (request, reply) => {
    const origin = request.headers.origin || request.headers.referer;
    const nativeMobile = !origin && request.headers['x-shipdehop-client'] === 'mobile';
    if (!nativeMobile && !isValidAllowedOrigin(origin)) {
      return reply.code(403).send({
        error: 'FORBIDDEN_ORIGIN',
        message: 'Forbidden origin for logout.',
      });
    }

    const cookieToken = parseCookie(request.headers.cookie, 'shipdehop_refresh_token');
    const bodyToken = (request.body as any)?.refreshToken;
    const token = cookieToken || bodyToken;
    if (token) await JwtSessionManager.revokeSession(token);

    reply.header(
      'Set-Cookie',
      'shipdehop_refresh_token=; Path=/auth/session; HttpOnly; Secure; SameSite=Lax; Max-Age=0',
    );

    return reply.send({ success: true });
  });

  // Admin-only linked-device controls.
  fastify.get('/admin/whatsapp/status', async (request, reply) => {
    if (!isAdmin(request)) {
      return reply.code(403).send({
        error: 'ADMIN_REQUIRED',
        message: 'Admin access required.',
      });
    }

    return reply.send(whatsappOtpBridge.getStatus());
  });

  fastify.post('/admin/whatsapp/pairing-code', async (request, reply) => {
    if (!isAdmin(request)) {
      return reply.code(403).send({
        error: 'ADMIN_REQUIRED',
        message: 'Admin access required.',
      });
    }

    const parsed = z.object({
      phoneNumber: z.string().min(10).max(20),
    }).safeParse(request.body);

    if (!parsed.success) {
      return reply.code(400).send({
        error: 'INVALID_SENDER_PHONE',
        message: 'Enter the WhatsApp sender number with country code.',
      });
    }

    try {
      const pairingCode = await whatsappOtpBridge.requestPairingCode(parsed.data.phoneNumber);
      return reply.send({
        pairingCode,
        instructions: 'WhatsApp > Settings > Linked Devices > Link a Device > Link with phone number instead.',
      });
    } catch (error: any) {
      return reply.code(503).send({
        error: 'PAIRING_CODE_FAILED',
        message: error?.message || 'Could not generate WhatsApp pairing code.',
      });
    }
  });
};
