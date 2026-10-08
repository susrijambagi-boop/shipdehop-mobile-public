import { FastifyInstance, FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import { config } from '../config.js';
import {
  AadhaarOfflineXmlVerifier,
  AadhaarOvseSessionManager,
  BiometricLivenessService,
  IdentityVerificationManager,
} from '../services/identity_verification.js';
import { getAadhaarProvider } from '../services/aadhaar/provider.js';

export async function requireVerifiedIdentity(request: FastifyRequest, reply: FastifyReply): Promise<boolean> {
  const user = (request as any).authUser || (request as any).user;
  if (!user || !user.id) {
    reply.code(401).send({ error: 'Unauthorized: Authentication required.' });
    return false;
  }

  // Under DEV_TEST_AUTH, allow explicit dev bypass for test fixtures
  if (config.DEV_TEST_AUTH && (user.email?.includes('test') || user.email?.includes('dev'))) {
    return true;
  }

  const identity = await IdentityVerificationManager.getIdentity(user.id);

  // Reject pre-production test identity in production mode
  if (identity && identity.verificationStatus === 'VERIFIED_TEST') {
    if (config.NODE_ENV === 'production') {
      reply.code(403).send({
        error: 'PREPROD_IDENTITY_FORBIDDEN',
        message: 'Pre-production UIDAI identity verification test results cannot be used for production transactions.',
        status: 'VERIFIED_TEST',
      });
      return false;
    }
    // In isolated developer/test mode, VERIFIED_TEST is accepted for feature testing
    return true;
  }

  if (!identity || identity.verificationStatus !== 'VERIFIED') {
    reply.code(403).send({
      error: 'IDENTITY_VERIFICATION_REQUIRED',
      message: 'Identity verification is required before performing this transaction.',
      status: identity?.verificationStatus || 'NOT_STARTED',
    });
    return false;
  }

  // When BETA1_REQUIRE_AADHAAR is enabled, require cryptographic Aadhaar verification assurance
  if (config.BETA1_REQUIRE_AADHAAR) {
    const isAadhaarMethod = ['AADHAAR_OVSE_APP', 'AADHAAR_OFFLINE_XML', 'AADHAAR_SECURE_QR', 'AADHAAR_UIDAI_PREPROD'].includes(identity.identityMethod);
    if (!isAadhaarMethod) {
      reply.code(403).send({
        error: 'AADHAAR_VERIFICATION_REQUIRED',
        message: 'Aadhaar cryptographic verification is required to participate in Beta 1 transactions.',
        currentMethod: identity.identityMethod,
      });
      return false;
    }
  }

  return true;
}


export const identityRoutes: FastifyPluginAsync = async (fastify: FastifyInstance) => {
  // Record user consent
  fastify.post('/identity/consent', async (request, reply) => {
    const user = (request as any).authUser || (request as any).user;
    if (!user?.id) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    const bodySchema = z.object({
      consentVersion: z.string().default('1.0'),
    });

    const parsed = bodySchema.safeParse(request.body || {});
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid consent parameters' });
    }

    const record = await IdentityVerificationManager.recordConsent(user.id, parsed.data.consentVersion);
    return reply.send({
      success: true,
      status: record.verificationStatus,
      consentedAt: record.consentedAt,
      consentVersion: record.consentVersion,
    });
  });

  // Start Aadhaar OVSE Verification Session (App-to-App / QR)
  fastify.post('/identity/aadhaar/session', async (request, reply) => {
    const user = (request as any).authUser || (request as any).user;
    if (!user?.id) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    if (!config.AADHAAR_VERIFICATION_ENABLED && config.NODE_ENV === 'production') {
      return reply.code(503).send({
        error: 'AADHAAR_VERIFICATION_DORMANT',
        message: 'Aadhaar production verification is currently dormant pending UIDAI OVSE registration onboarding.',
      });
    }

    const session = AadhaarOvseSessionManager.createSession(user.id);
    return reply.send({
      success: true,
      sessionId: session.sessionId,
      requestId: session.requestId,
      nonce: session.nonce,
      qrPayload: session.qrPayload,
      deepLink: session.deepLink,
      expiresAt: session.expiresAt,
    });
  });

  // Verify Aadhaar QR Code
  fastify.post('/identity/aadhaar/verify-qr', async (request, reply) => {
    const user = (request as any).authUser || (request as any).user;
    if (!user?.id) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    const bodySchema = z.object({
      qrPayload: z.string().min(10),
      phoneE164: z.string().optional(),
    });

    const parsed = bodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid QR payload' });
    }

    const result = await IdentityVerificationManager.processAadhaarVerification(
      user.id,
      parsed.data.qrPayload,
      parsed.data.phoneE164
    );

    if (!result.success) {
      return reply.code(400).send({ error: result.error, status: result.status });
    }

    return reply.send({
      success: true,
      status: result.status,
      message: 'Aadhaar Secure QR cryptographically verified',
    });
  });

  // Verify Aadhaar Paperless Offline e-KYC (XML or ZIP with Share Code)
  fastify.post('/identity/aadhaar/verify-offline-xml', async (request, reply) => {
    const user = (request as any).authUser || (request as any).user;
    if (!user?.id) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    if (config.NODE_ENV === 'production' && (!config.AADHAAR_VERIFICATION_ENABLED || !config.OFFLINE_AADHAAR_ENABLED)) {
      return reply.code(503).send({
        error: 'AADHAAR_VERIFICATION_DORMANT',
        message: 'Aadhaar verification is currently dormant in production.',
      });
    }

    if (config.NODE_ENV === 'production' && config.OFFLINE_AADHAAR_ENABLED && !config.OVSE_PRODUCTION_APPROVED) {
      return reply.code(503).send({
        error: 'OVSE_REGISTRATION_REQUIRED',
        status: 'PENDING_REVIEW',
        message: 'Production Aadhaar verification requires official UIDAI OVSE registration approval (OVSE_PRODUCTION_APPROVED=true).',
      });
    }

    const bodySchema = z.object({
      xmlContent: z.string().optional(),
      zipBase64: z.string().optional(),
      shareCode: z.string().length(4).optional(),
    }).refine(data => data.xmlContent || (data.zipBase64 && data.shareCode), {
      message: 'Either xmlContent or both zipBase64 and shareCode must be provided',
    });

    const parsed = bodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid payload: ' + parsed.error.message });
    }

    const userPhone = user.phone || user.phoneE164;

    let result;
    if (parsed.data.zipBase64 && parsed.data.shareCode) {
      const zipBuffer = Buffer.from(parsed.data.zipBase64, 'base64');
      result = await IdentityVerificationManager.processAadhaarOfflineXml(user.id, zipBuffer, parsed.data.shareCode, userPhone);
    } else if (parsed.data.xmlContent) {
      result = await IdentityVerificationManager.processAadhaarOfflineXml(user.id, parsed.data.xmlContent, parsed.data.shareCode, userPhone);
    } else {
      return reply.code(400).send({ error: 'No verification payload provided' });
    }

    if (!result.success) {
      return reply.code(400).send({ error: result.error || 'Aadhaar XML verification failed', status: result.status });
    }

    return reply.send({
      success: true,
      status: result.status,
      identityMethod: 'AADHAAR_OFFLINE_XML',
      verifiedAt: result.record?.verifiedAt,
      message: 'Aadhaar Paperless Offline e-KYC digitally verified with UIDAI signature',
    });
  });

  // UIDAI / Aadhaar App OVSE Callback Receiver Handler
  const handleOvseCallback = async (request: FastifyRequest, reply: FastifyReply) => {
    if (!config.AADHAAR_VERIFICATION_ENABLED && config.NODE_ENV === 'production') {
      return reply.code(503).send({
        error: 'AADHAAR_VERIFICATION_DORMANT',
        message: 'Aadhaar callback receiver is currently dormant pending UIDAI OVSE registration onboarding.',
      });
    }

    const bodySchema = z.object({
      requestId: z.string().min(10),
      nonce: z.string().min(16),
      signature: z.string().min(10),
      payload: z.object({
        name: z.string().min(2),
        last4: z.string().regex(/^\d{4}$/),
        birthYear: z.number().int().min(1900).max(2050).optional(),
        gender: z.enum(['M', 'F', 'T']).optional(),
      }),
    });

    const parsed = bodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid OVSE callback structure' });
    }

    const { requestId, nonce, signature, payload } = parsed.data;
    const payloadData: { name: string; last4: string; birthYear?: number | undefined; gender?: string | undefined } = {
      name: payload.name,
      last4: payload.last4,
      birthYear: payload.birthYear !== undefined ? payload.birthYear : undefined,
      gender: payload.gender !== undefined ? payload.gender : undefined,
    };
    const sessionRes = AadhaarOvseSessionManager.verifyAndConsumeCallback(requestId, nonce, signature, payloadData);

    if (!sessionRes.ok) {
      return reply.code(400).send({ error: sessionRes.error || 'Verification callback rejected' });
    }

    if (sessionRes.idempotent) {
      return reply.send({ ok: true, verified: true, idempotent: true });
    }

    if (!sessionRes.userId) {
      return reply.code(400).send({ error: 'Session has no associated user context' });
    }

    const record = await IdentityVerificationManager.completeAadhaarVerification(sessionRes.userId, 'AADHAAR_OVSE_APP', payloadData);

    return reply.send({
      ok: true,
      verified: true,
      identityMethod: 'AADHAAR_OVSE_APP',
      status: record.verificationStatus,
    });
  };

  fastify.post('/identity/aadhaar/ovse-callback', handleOvseCallback);
  fastify.post('/identity/aadhaar/ovse/callback', handleOvseCallback);
  fastify.post('/api/identity/aadhaar/ovse/callback', handleOvseCallback);
  fastify.post('/api/identity/aadhaar/ovse-callback', handleOvseCallback);

  // Verify Active Biometric Liveness
  fastify.post('/identity/liveness/verify', async (request, reply) => {
    const user = (request as any).authUser || (request as any).user;
    if (!user?.id) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    const bodySchema = z.object({
      blinkDetected: z.boolean(),
      turnLeftDetected: z.boolean(),
      turnRightDetected: z.boolean(),
      centerDetected: z.boolean(),
      singleFaceOnly: z.boolean(),
      durationSeconds: z.number().min(0.5).max(60),
    });

    const parsed = bodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid liveness telemetry' });
    }

    const livenessStatus = BiometricLivenessService.evaluateLiveness(parsed.data);
    return reply.send({
      livenessStatus,
      passed: livenessStatus === 'PASS',
    });
  });

  // Complete Biometric Face Matching & Final Verification
  fastify.post('/identity/face-match/complete', async (request, reply) => {
    const user = (request as any).authUser || (request as any).user;
    if (!user?.id) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    const bodySchema = z.object({
      livenessStatus: z.enum(['PASS', 'REVIEW', 'FAIL']),
      selfieEmbedding: z.array(z.number()).min(8),
      idPhotoEmbedding: z.array(z.number()).min(8),
    });

    const parsed = bodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid face match vectors' });
    }

    const matchResult = BiometricLivenessService.compareFaceEmbeddings(
      parsed.data.selfieEmbedding,
      parsed.data.idPhotoEmbedding
    );

    const record = await IdentityVerificationManager.completeBiometrics(
      user.id,
      parsed.data.livenessStatus,
      matchResult.status
    );

    return reply.send({
      verificationStatus: record.verificationStatus,
      livenessStatus: record.livenessStatus,
      faceMatchStatus: record.faceMatchStatus,
      verified: record.verificationStatus === 'VERIFIED',
      verifiedAt: record.verifiedAt,
      // Minimal safe badge details — zero raw PII returned
      badge: {
        phoneVerified: !!record.phoneE164,
        governmentIdVerified: record.signatureValid,
        faceVerified: record.faceMatchStatus === 'PASS',
      },
    });
  });

  // Request UIDAI Aadhaar OTP (Pre-Production API 2.5)
  const handleAadhaarOtpRequest = async (request: FastifyRequest, reply: FastifyReply) => {
    const user = (request as any).authUser || (request as any).user;
    if (!user?.id) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    const bodySchema = z.object({
      aadhaarNumber: z.string().min(12),
      consent: z.boolean(),
    });

    const parsed = bodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid request: 12-digit Aadhaar number and explicit consent required.' });
    }

    const provider = getAadhaarProvider();
    const result = await provider.requestOtp({
      userId: user.id,
      aadhaarNumber: parsed.data.aadhaarNumber,
      consent: parsed.data.consent,
    });

    if (!result.success) {
      return reply.code(400).send({
        error: result.error || 'Aadhaar OTP request failed.',
        errorCode: result.errorCode,
        status: result.status,
      });
    }

    return reply.send({
      success: true,
      sessionId: result.sessionId,
      maskedAadhaar: result.maskedAadhaar,
      expiresAt: result.expiresAt,
      cooldownSeconds: result.cooldownSeconds,
      status: result.status,
    });
  };

  fastify.post('/identity/aadhaar/otp/request', handleAadhaarOtpRequest);
  fastify.post('/api/identity/aadhaar/otp/request', handleAadhaarOtpRequest);

  // Verify UIDAI Aadhaar OTP & Fetch e-KYC (Pre-Production API 2.5)
  const handleAadhaarOtpVerify = async (request: FastifyRequest, reply: FastifyReply) => {
    const user = (request as any).authUser || (request as any).user;
    if (!user?.id) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    const bodySchema = z.object({
      verificationSessionId: z.string().min(5),
      otp: z.string().length(6),
    });

    const parsed = bodySchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: 'Invalid verification payload: 6-digit OTP required.' });
    }

    const provider = getAadhaarProvider();
    const result = await provider.verifyOtpAndFetchKyc({
      userId: user.id,
      verificationSessionId: parsed.data.verificationSessionId,
      otp: parsed.data.otp,
    });

    if (!result.success || !result.extracted) {
      return reply.code(400).send({
        error: result.error || 'Aadhaar OTP verification failed.',
        errorCode: result.errorCode,
        status: result.status,
      });
    }

    const record = await IdentityVerificationManager.completeUidaiPreprodVerification(user.id, {
      name: result.extracted.name,
      documentLast4: result.extracted.documentLast4,
      birthYear: result.extracted.birthYear,
      gender: result.extracted.gender,
    });

    return reply.send({
      success: true,
      status: record.verificationStatus,
      verificationProvider: 'AADHAAR_UIDAI_PREPROD',
      verificationEnvironment: 'PREPRODUCTION',
      verifiedAt: record.verifiedAt,
      message: 'UIDAI e-KYC pre-production verification successful',
    });
  };

  fastify.post('/identity/aadhaar/otp/verify', handleAadhaarOtpVerify);
  fastify.post('/api/identity/aadhaar/otp/verify', handleAadhaarOtpVerify);

  // Get current user identity status badge
  fastify.get('/identity/status', async (request, reply) => {
    const user = (request as any).authUser || (request as any).user;
    if (!user?.id) {
      return reply.code(401).send({ error: 'Authentication required' });
    }

    const record = await IdentityVerificationManager.getIdentity(user.id);
    if (!record) {
      return reply.send({
        verificationStatus: 'NOT_STARTED',
        identityMethod: 'OTHER_GOV_ID',
        badge: {
          label: 'Unverified',
          type: 'NONE',
          phoneVerified: false,
          governmentIdVerified: false,
          isAadhaarVerified: false,
          faceVerified: false,
        },
      });
    }

    const isAadhaar = ['AADHAAR_OVSE_APP', 'AADHAAR_OFFLINE_XML', 'AADHAAR_SECURE_QR'].includes(record.identityMethod);
    const isPreprod = record.identityMethod === 'AADHAAR_UIDAI_PREPROD' || record.verificationStatus === 'VERIFIED_TEST';
    const isManual = record.identityMethod === 'MANUAL_BETA';
    const isVerified = record.verificationStatus === 'VERIFIED';
    const isVerifiedTest = record.verificationStatus === 'VERIFIED_TEST';

    let badgeLabel = 'Unverified';
    let badgeType = 'NONE';
    if (isVerified) {
      if (isAadhaar) {
        badgeLabel = 'Aadhaar Verified';
        badgeType = 'AADHAAR';
      } else if (isManual) {
        badgeLabel = 'ShipdeHop Verified';
        badgeType = 'MANUAL_BETA';
      } else {
        badgeLabel = 'Identity Verified';
        badgeType = 'GOV_ID';
      }
    } else if (isVerifiedTest && isPreprod) {
      badgeLabel = config.NODE_ENV === 'production'
        ? 'UIDAI Test Environment'
        : 'UIDAI e-KYC Test Passed';
      badgeType = 'AADHAAR_PREPROD';
    }

    return reply.send({
      verificationStatus: record.verificationStatus,
      identityMethod: record.identityMethod,
      documentLast4: record.documentLast4,
      verifiedAt: record.verifiedAt,
      badge: {
        label: badgeLabel,
        type: badgeType,
        isAadhaarVerified: isVerified && isAadhaar,
        isPreprodTestVerified: isVerifiedTest,
        phoneVerified: !!record.phoneE164,
        governmentIdVerified: (isVerified || isVerifiedTest) && (record.signatureValid || isManual),
        faceVerified: record.faceMatchStatus === 'PASS',
      },
    });
  });
};
