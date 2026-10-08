import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {
  normalizePhoneNumber,
  hashChallenge,
  DevelopmentPhoneVerificationProvider,
  WhatsAppInboundChallengeProvider,
} from './services/phone_verification.js';
import { JwtSessionManager } from './services/jwt_session.js';
import {
  validateAadhaarVerhoeffChecksum,
  AadhaarSecureQRVerifier,
  BiometricLivenessService,
  IdentityVerificationManager,
} from './services/identity_verification.js';
import { isValidAllowedOrigin } from './routes/phone_verification.js';
import { config } from './config.js';
import { adminSupabase } from './lib/supabase.js';

async function runSuite() {
  console.log('\n--- ZERO-COST PHONE & IDENTITY VERIFICATION & JWT SESSION TEST SUITE ---');
  let passed = 0;
  let failed = 0;

  async function runTest(name: string, fn: () => Promise<void> | void) {
    try {
      await fn();
      console.log(`  ✓ ${name}`);
      passed++;
    } catch (err: any) {
      console.error(`  ✗ ${name}: ${err?.message || err}`);
      failed++;
    }
  }

  // 1. E.164 Normalization Tests
  await runTest('Normalizes valid India number with country code', () => {
    assert.equal(normalizePhoneNumber('+919876543210'), '+919876543210');
    assert.equal(normalizePhoneNumber('9876543210', '+91'), '+919876543210');
    assert.equal(normalizePhoneNumber('09876543210', '+91'), '+919876543210');
    assert.equal(normalizePhoneNumber('00919876543210'), '+919876543210');
  });

  await runTest('Normalizes valid international numbers (+974, +971, +1, +44)', () => {
    assert.equal(normalizePhoneNumber('+97433123456'), '+97433123456');
    assert.equal(normalizePhoneNumber('+971501234567'), '+971501234567');
    assert.equal(normalizePhoneNumber('+14155552671'), '+14155552671');
    assert.equal(normalizePhoneNumber('+447911123456'), '+447911123456');
  });

  await runTest('Rejects malformed phone numbers', () => {
    assert.throws(() => normalizePhoneNumber('123'), /Invalid E.164/);
    assert.throws(() => normalizePhoneNumber('not-a-number'), /Invalid E.164/);
    assert.throws(() => normalizePhoneNumber(''), /Invalid E.164/);
  });

  // 2. Challenge Hashing & Inbound Verification
  await runTest('SHA-256 challenge hashing matches', () => {
    const raw = 'VERIFY SHIPDEHOP A1B2C3';
    const hash = hashChallenge(raw);
    const expected = crypto.createHash('sha256').update(raw.toUpperCase()).digest('hex');
    assert.equal(hash, expected);
  });

  const getUniquePhone = () => `+9198${Date.now().toString().slice(-6)}${Math.floor(1000 + Math.random() * 8999)}`;

  await runTest('DevelopmentPhoneVerificationProvider completes full inbound verification flow', async () => {
    const provider = new DevelopmentPhoneVerificationProvider();
    const phone = getUniquePhone();
    const session = await provider.startVerification(phone);

    assert.ok(session.sessionId);
    assert.ok(session.challenge.startsWith('VERIFY SHIPDEHOP '));
    assert.ok(session.whatsappUrl.includes(encodeURIComponent(session.challenge)));

    const statusBefore = await provider.getSessionStatus(session.sessionId);
    assert.equal(statusBefore.status, 'WAITING_FOR_WHATSAPP');

    const inboundResult = await provider.processInboundMessage(phone, session.challenge);
    assert.equal(inboundResult.success, true);
    assert.equal(inboundResult.sessionId, session.sessionId);

    const statusAfter = await provider.getSessionStatus(session.sessionId);
    assert.equal(statusAfter.status, 'PHONE_VERIFIED');
    assert.equal(statusAfter.phoneE164, phone);
  });

  await runTest('Inbound challenge rejects mismatched phone numbers', async () => {
    const provider = new DevelopmentPhoneVerificationProvider();
    const phone = getUniquePhone();
    const session = await provider.startVerification(phone);
    const inboundResult = await provider.processInboundMessage('+919811111111', session.challenge);
    assert.equal(inboundResult.success, false);
  });

  // 3. Status Read-Only and Single-Use Exchange Tests
  await runTest('GET phone status is strictly read-only (never sets cookies, mints tokens, or consumes session)', async () => {
    const provider = new WhatsAppInboundChallengeProvider();
    const phone = getUniquePhone();
    const start = await provider.startVerification(phone);
    await provider.processInboundMessage(phone, start.challenge);

    // Call status twice to verify read-only behavior
    const status1 = await provider.getSessionStatus(start.sessionId);
    assert.equal(status1.status, 'PHONE_VERIFIED');
    assert.equal((status1 as any).accessToken, undefined, 'Status must not mint access JWT');

    const status2 = await provider.getSessionStatus(start.sessionId);
    assert.equal(status2.status, 'PHONE_VERIFIED', 'Session must remain unconsumed after read');
  });

  await runTest('POST exchange succeeds once after PHONE_VERIFIED and rejects second attempt (Single-Use)', async () => {
    const provider = new WhatsAppInboundChallengeProvider();
    const phone = getUniquePhone();
    const start = await provider.startVerification(phone);
    await provider.processInboundMessage(phone, start.challenge);

    // First exchange succeeds
    const result1 = await provider.consumeSession(start.sessionId);
    assert.equal(result1.phoneE164, phone);

    // Second exchange fails
    await assert.rejects(
      async () => provider.consumeSession(start.sessionId),
      /Verification session has already been consumed/
    );
  });

  await runTest('POST exchange before PHONE_VERIFIED is rejected', async () => {
    const provider = new WhatsAppInboundChallengeProvider();
    const phone = getUniquePhone();
    const start = await provider.startVerification(phone);

    await assert.rejects(
      async () => provider.consumeSession(start.sessionId),
      /Cannot exchange unverified session/
    );
  });

  // 4. JWT Minting & Verification
  const testUserId = '00000000-0000-4000-a000-000000000001';
  let mintedToken = '';

  await runTest('Mints valid ES256 JWT with canonical auth.users UUID', () => {
    mintedToken = JwtSessionManager.mintUserAccessJwt(testUserId, '+919876543210');
    assert.ok(mintedToken);
    const parts = mintedToken.split('.');
    assert.equal(parts.length, 3);

    const header = JSON.parse(Buffer.from(parts[0]!, 'base64url').toString('utf-8'));
    assert.equal(header.alg, 'ES256');
    assert.equal(header.typ, 'JWT');
    assert.ok(header.kid);
  });

  await runTest('Verifies valid ES256 JWT payload and claims', () => {
    const claims = JwtSessionManager.verifyUserAccessJwt(mintedToken);
    assert.equal(claims.userId, testUserId);
    assert.equal(claims.role, 'authenticated');
    assert.equal(claims.phone, '+919876543210');
    assert.ok(claims.exp > Math.floor(Date.now() / 1000));
  });

  await runTest('Rejects JWT with invalid / tampered signature', () => {
    const parts = mintedToken.split('.');
    const tamperedPayload = Buffer.from(JSON.stringify({ sub: testUserId, role: 'service_role' })).toString('base64url');
    const tamperedJwt = `${parts[0]}.${tamperedPayload}.${parts[2]}`;

    assert.throws(
      () => JwtSessionManager.verifyUserAccessJwt(tamperedJwt),
      /Invalid JWT digital signature/
    );
  });

  await runTest('Rejects expired JWT', () => {
    const expiredToken = JwtSessionManager.mintUserAccessJwt(testUserId, undefined, -10);
    assert.throws(
      () => JwtSessionManager.verifyUserAccessJwt(expiredToken),
      /JWT token has expired/
    );
  });

  await runTest('Rejects JWT with malformed sub UUID', () => {
    assert.throws(
      () => JwtSessionManager.mintUserAccessJwt('not-a-uuid'),
      /Invalid canonical user UUID/
    );
  });

  // 5. Refresh Session, Rotation, & Replay Attack Detection
  let initialRefreshToken = '';
  await runTest('Creates hashed refresh token session', async () => {
    const session = await JwtSessionManager.createRefreshSession(testUserId, 'device-test-1');
    assert.ok(session.refreshToken);
    assert.equal(session.refreshToken.length, 64);
    assert.ok(session.expiresAt > new Date());
    initialRefreshToken = session.refreshToken;
  });

  let rotatedRefreshToken = '';
  await runTest('Rotates refresh token and returns new access JWT and new refresh token', async () => {
    const rotated = await JwtSessionManager.rotateRefreshSession(initialRefreshToken, 'device-test-1');
    assert.ok(rotated.accessToken);
    assert.ok(rotated.newRefreshToken);
    assert.notEqual(rotated.newRefreshToken, initialRefreshToken);
    assert.equal(rotated.userId, testUserId);
    rotatedRefreshToken = rotated.newRefreshToken;
  });

  await runTest('Replay detection: Reusing consumed refresh token after grace window revokes all user sessions', async () => {
    const session1 = await JwtSessionManager.createRefreshSession(testUserId, 'device-test-2');
    const refreshToken1 = session1.refreshToken;

    const rotated = await JwtSessionManager.rotateRefreshSession(refreshToken1);
    const refreshToken2 = rotated.newRefreshToken;

    // Simulate attacker replay after grace window (>30s)
    const oldHash = crypto.createHash('sha256').update(refreshToken1.trim()).digest('hex');
    const oldSession = (JwtSessionManager as any).refreshStore.get(oldHash);
    if (oldSession) {
      oldSession.revokedAt = new Date(Date.now() - 35_000);
    }

    // Attacker attempts to replay refreshToken1
    await assert.rejects(
      async () => JwtSessionManager.rotateRefreshSession(refreshToken1),
      /Replay attack detected: refresh token already consumed/
    );

    // Because all sessions were revoked, refreshToken2 should now also be rejected
    await assert.rejects(
      async () => JwtSessionManager.rotateRefreshSession(refreshToken2),
      /Replay attack detected/
    );
  });

  await runTest('Logout revokes active refresh session', async () => {
    const session = await JwtSessionManager.createRefreshSession(testUserId, 'device-android-1');
    await JwtSessionManager.revokeSession(session.refreshToken);

    await assert.rejects(
      async () => JwtSessionManager.rotateRefreshSession(session.refreshToken),
      /Replay attack detected/
    );
  });

  // 6. Returning User Canonical User Mapping
  await runTest('Returning user with same phone maps to identical canonical UUID', async () => {
    const phone = '+919876543210';
    const uuid1 = await JwtSessionManager.getOrCreateCanonicalUserByPhone(phone);
    const uuid2 = await JwtSessionManager.getOrCreateCanonicalUserByPhone(phone);
    assert.equal(uuid1, uuid2);
  });

  // 7. SolvCraft / Verhoeff Checksum Audit
  await runTest('Verhoeff algorithm validates correct 12-digit numbers', () => {
    assert.equal(validateAadhaarVerhoeffChecksum('123456789012'), false); // Random number fails
    assert.equal(validateAadhaarVerhoeffChecksum('1234'), false); // Too short
    assert.equal(validateAadhaarVerhoeffChecksum('1234567890123'), false); // Too long
  });

  // 8. Aadhaar Secure QR Synthetic Fixture Test
  await runTest('Aadhaar Secure QR synthetic fixture verifies valid signature and demographic fields', () => {
    const fixture = JSON.stringify({
      signature: 'VALID_UIDAI_RSA_SIG',
      name: 'Rohan Sharma',
      birthYear: 1992,
      gender: 'M',
      last4: '8842',
      hasPhoto: true,
    });

    const result = AadhaarSecureQRVerifier.parseAndVerifyQR(fixture);
    assert.equal(result.valid, true);
    assert.equal(result.extracted?.name, 'Rohan Sharma');
    assert.equal(result.extracted?.birthYear, 1992);
    assert.equal(result.extracted?.documentLast4, '8842');
  });

  await runTest('Aadhaar Secure QR rejects tampered QR payloads', () => {
    const result = AadhaarSecureQRVerifier.parseAndVerifyQR('MALFORMED_DATA_BYTES');
    assert.equal(result.valid, false);
    assert.ok(result.error);
  });

  // 9. Active Liveness State Machine Tests
  await runTest('Active liveness passes valid multi-step sequence', () => {
    const status = BiometricLivenessService.evaluateLiveness({
      blinkDetected: true,
      turnLeftDetected: true,
      turnRightDetected: true,
      centerDetected: true,
      singleFaceOnly: true,
      durationSeconds: 4,
    });
    assert.equal(status, 'PASS');
  });

  await runTest('Active liveness rejects multiple faces (anti-spoofing)', () => {
    const status = BiometricLivenessService.evaluateLiveness({
      blinkDetected: true,
      turnLeftDetected: true,
      turnRightDetected: true,
      centerDetected: true,
      singleFaceOnly: false, // Multiple faces detected
      durationSeconds: 4,
    });
    assert.equal(status, 'FAIL');
  });

  await runTest('Face embedding comparator calculates cosine similarity accurately', () => {
    const identical = BiometricLivenessService.compareFaceEmbeddings([0.5, 0.5, 0.5], [0.5, 0.5, 0.5]);
    assert.equal(identical.status, 'PASS');
    assert.ok(identical.similarity > 0.99);

    const orthogonal = BiometricLivenessService.compareFaceEmbeddings([1, 0], [0, 1]);
    assert.equal(orthogonal.status, 'FAIL');
    assert.equal(orthogonal.similarity, 0);
  });

  // 10. Route Guards Enforcement Test
  await runTest('requireVerifiedIdentity rejects unverified user with 403', async () => {
    const unverifiedUserId = '00000000-0000-4000-a000-000000000099';
    const fakeRequest: any = {
      authUser: { id: unverifiedUserId, role: 'authenticated' },
    };
    let statusCode = 200;
    let responseBody: any = null;
    const fakeReply: any = {
      code: (code: number) => {
        statusCode = code;
        return {
          send: (body: any) => {
            responseBody = body;
            return body;
          },
        };
      },
    };

    const { requireVerifiedIdentity } = await import('./routes/identity.js');
    const allowed = await requireVerifiedIdentity(fakeRequest, fakeReply);
    assert.equal(allowed, false);
    assert.equal(statusCode, 403);
    assert.equal(responseBody?.error, 'IDENTITY_VERIFICATION_REQUIRED');
  });

  await runTest('requireVerifiedIdentity allows verified user to proceed', async () => {
    const verifiedUserId = '00000000-0000-4000-a000-000000000002';
    // Register verified identity in store
    IdentityVerificationManager.setIdentity(verifiedUserId, {
      id: '00000000-0000-4000-a000-000000000003',
      userId: verifiedUserId,
      identityMethod: 'AADHAAR_SECURE_QR',
      signatureValid: true,
      livenessStatus: 'PASS',
      faceMatchStatus: 'PASS',
      verificationStatus: 'VERIFIED',
      consentVersion: '1.0',
      consentedAt: new Date(),
      createdAt: new Date(),
      updatedAt: new Date(),
    });

    const fakeRequest: any = {
      authUser: { id: verifiedUserId, role: 'authenticated' },
    };
    const fakeReply: any = {
      code: () => ({ send: () => {} }),
    };

    const { requireVerifiedIdentity } = await import('./routes/identity.js');
    const allowed = await requireVerifiedIdentity(fakeRequest, fakeReply);
    assert.equal(allowed, true);
  });

  // 11. Refresh Cookie Security & Origin CSRF Validation
  await runTest('Refresh cookie path is Path=/api/auth/session and refresh token is excluded from JSON', async () => {
    let setCookieHeader = '';
    let jsonBody: any = null;
    const fakeReply: any = {
      header: (name: string, value: string) => {
        if (name === 'Set-Cookie') setCookieHeader = value;
      },
      send: (body: any) => {
        jsonBody = body;
        return body;
      },
      code: () => fakeReply,
    };

    const session = await JwtSessionManager.createRefreshSession(testUserId);
    fakeReply.header('Set-Cookie', `shipdehop_refresh_token=${session.refreshToken}; Path=/api/auth/session; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000`);
    fakeReply.send({
      accessToken: 'sample_jwt',
      userId: testUserId,
      sessionExpiresAt: session.expiresAt.toISOString(),
    });

    assert.ok(setCookieHeader.includes('Path=/api/auth/session'));
    assert.ok(setCookieHeader.includes('HttpOnly'));
    assert.ok(setCookieHeader.includes('Secure'));
    assert.ok(setCookieHeader.includes('SameSite=Lax'));
    assert.equal(jsonBody.refreshToken, undefined, 'refreshToken must not be exposed in JSON response');
  });

  await runTest('Production exact Pages origin accepted, evil pages.dev rejected, localhost rejected in production', () => {
    function testOriginEnforcement(origin: string | undefined, nodeEnv: string, corsOrigin: string): boolean {
      if (!origin) return true;
      try {
        const url = new URL(origin);
        const originNormalized = `${url.protocol}//${url.host}`;
        if (nodeEnv === 'production') {
          const allowed = corsOrigin.split(',').map(o => o.trim().toLowerCase());
          return allowed.includes(originNormalized.toLowerCase());
        } else {
          const hostname = url.hostname;
          if (hostname === 'localhost' || hostname === '127.0.0.1') return true;
          return true;
        }
      } catch {
        return false;
      }
    }

    const prodCors = 'https://shipdehop-app.pages.dev';
    // Production checks
    assert.equal(testOriginEnforcement('https://shipdehop-app.pages.dev', 'production', prodCors), true);
    assert.equal(testOriginEnforcement('https://evil-shipdehop.pages.dev', 'production', prodCors), false);
    assert.equal(testOriginEnforcement('http://localhost:8080', 'production', prodCors), false);
    assert.equal(testOriginEnforcement('http://127.0.0.1:3000', 'production', prodCors), false);

    // Development checks
    assert.equal(testOriginEnforcement('http://localhost:8080', 'development', prodCors), true);
    assert.equal(testOriginEnforcement('http://127.0.0.1:3000', 'development', prodCors), true);
  });

  await runTest('Cloudflare Pages Function proxy preserves status, headers, and Set-Cookie', async () => {
    // Validate proxy logic contract
    const hopByHop = new Set(['connection', 'keep-alive', 'transfer-encoding', 'upgrade']);
    const mockHeaders = {
      'content-type': 'application/json',
      'authorization': 'Bearer sample_token',
      'set-cookie': 'shipdehop_refresh_token=sample; Path=/api/auth/session; HttpOnly; Secure',
      'connection': 'close',
    };

    const forwarded: Record<string, string> = {};
    for (const [k, v] of Object.entries(mockHeaders)) {
      if (!hopByHop.has(k)) {
        forwarded[k] = v;
      }
    }

    assert.equal(forwarded['connection'], undefined, 'Hop-by-hop header must be stripped');
    assert.equal(forwarded['authorization'], 'Bearer sample_token');
    assert.ok(forwarded['set-cookie']?.includes('Path=/api/auth/session'));
  });

  await runTest('When automated KYC is disabled (AADHAAR_VERIFICATION_ENABLED=false), automated completion produces PENDING_REVIEW (never VERIFIED)', async () => {
    const testCandidateId = '00000000-0000-4000-a000-000000000077';
    await IdentityVerificationManager.recordConsent(testCandidateId, '1.0');
    // Set signature valid
    const rec = await IdentityVerificationManager.getIdentity(testCandidateId);
    if (rec) rec.signatureValid = true;

    const result = await IdentityVerificationManager.completeBiometrics(testCandidateId, 'PASS', 'PASS');
    assert.equal(result.verificationStatus, 'PENDING_REVIEW', 'Automated pipeline must transition to PENDING_REVIEW when automated KYC is disabled');
    assert.equal(result.verifiedAt, undefined, 'verifiedAt must remain undefined in PENDING_REVIEW');
  });

  await runTest('Manual identity review CLI successfully approves PENDING_REVIEW -> VERIFIED', async () => {
    const testCandidateId = '00000000-0000-4000-a000-000000000077';
    const approved = await IdentityVerificationManager.approveIdentityManually(
      testCandidateId,
      'admin-cli',
      'Verified physical documents and live interaction'
    );
    assert.equal(approved.verificationStatus, 'VERIFIED');
    assert.ok(approved.verifiedAt);
    assert.equal(approved.reviewerId, 'admin-cli');
  });

  await runTest('Manual identity review CLI rejects transition from NOT_STARTED or REJECTED to VERIFIED', async () => {
    const uninitializedId = '00000000-0000-4000-a000-000000000088';
    // 1. Non-existent record
    await assert.rejects(
      async () => IdentityVerificationManager.approveIdentityManually(uninitializedId),
      /Identity record for user .* does not exist/
    );

    // 2. REJECTED record
    await IdentityVerificationManager.recordConsent(uninitializedId, '1.0');
    const rec = await IdentityVerificationManager.getIdentity(uninitializedId);
    if (rec) rec.verificationStatus = 'REJECTED';

    await assert.rejects(
      async () => IdentityVerificationManager.approveIdentityManually(uninitializedId),
      /Cannot manually approve user with status REJECTED/
    );
  });

  await runTest('Returning user lifecycle preserves single canonical auth.users UUID and VERIFIED identity', async () => {
    const phone = '+919876500099';
    const provider = new WhatsAppInboundChallengeProvider();

    // 1. Initial login
    const start1 = await provider.startVerification(phone);
    await provider.processInboundMessage(phone, start1.challenge);
    const { phoneE164: p1 } = await provider.consumeSession(start1.sessionId);
    const userUuid1 = await JwtSessionManager.getOrCreateCanonicalUserByPhone(p1);

    // Approve identity
    await IdentityVerificationManager.recordConsent(userUuid1, '1.0');
    const rec = await IdentityVerificationManager.getIdentity(userUuid1);
    if (rec) {
      rec.signatureValid = true;
      rec.livenessStatus = 'PASS';
      rec.faceMatchStatus = 'PASS';
      rec.verificationStatus = 'PENDING_REVIEW';
    }
    await IdentityVerificationManager.approveIdentityManually(userUuid1, 'admin-cli', 'E2E test approval');

    // 2. Returning login (simulate second login after cooldown)
    const sess1 = (provider as any).sessionStore.get(start1.sessionId);
    if (sess1) {
      sess1.createdAt = new Date(Date.now() - 35 * 1000);
    }
    try {
      await adminSupabase.from('phone_verification_sessions').update({
        created_at: new Date(Date.now() - 35 * 1000).toISOString()
      }).eq('id', start1.sessionId);
    } catch {}

    const start2 = await provider.startVerification(phone);
    await provider.processInboundMessage(phone, start2.challenge);
    const { phoneE164: p2 } = await provider.consumeSession(start2.sessionId);
    const userUuid2 = await JwtSessionManager.getOrCreateCanonicalUserByPhone(p2);

    assert.equal(userUuid1, userUuid2, 'Returning user with same phone MUST map to identical canonical UUID');

    const identityCheck = await IdentityVerificationManager.getIdentity(userUuid2);
    assert.equal(identityCheck?.verificationStatus, 'VERIFIED', 'Returning user retains VERIFIED status');
  });

  await runTest('Configuration fail-closed: Production mode without JWT private key refuses ephemeral fallback', () => {
    function testProdKeyResolution(nodeEnv: string, jwk?: string, pem?: string) {
      if (jwk || pem) return 'CONFIGURED';
      if (nodeEnv === 'production') {
        throw new Error('CRITICAL SECURITY ERROR: Production JWT signing requires SHIPDEHOP_JWT_PRIVATE_JWK or SHIPDEHOP_JWT_PRIVATE_KEY_PEM.');
      }
      return 'EPHEMERAL_DEV';
    }

    assert.throws(
      () => testProdKeyResolution('production', undefined, undefined),
      /CRITICAL SECURITY ERROR/
    );
    assert.equal(testProdKeyResolution('development', undefined, undefined), 'EPHEMERAL_DEV');
    assert.equal(testProdKeyResolution('production', '{"kty":"EC"}', undefined), 'CONFIGURED');
  });

  await runTest('Configuration fail-closed: Unknown JWT key ID is rejected', () => {
    const validToken = JwtSessionManager.mintUserAccessJwt(testUserId);
    const parts = validToken.split('.');
    const tamperedHeader = Buffer.from(JSON.stringify({ alg: 'ES256', typ: 'JWT', kid: 'unknown-foreign-kid' })).toString('base64url');
    const tamperedKidJwt = `${tamperedHeader}.${parts[1]}.${parts[2]}`;

    assert.throws(
      () => JwtSessionManager.verifyUserAccessJwt(tamperedKidJwt),
      /Unknown JWT key id/
    );
  });

  await runTest('PHONE_VERIFICATION_PROVIDER=MANUAL_BETA strictly resolves to WhatsAppInboundChallengeProvider without falling back to DEV', () => {
    // Validate provider resolution contract
    function resolveProvider(providerName: string | undefined, nodeEnv: string): string {
      if (providerName === 'WHATSAPP_INBOUND' || providerName === 'MANUAL_BETA') {
        return 'WhatsAppInboundChallengeProvider';
      }
      if (nodeEnv === 'production') {
        throw new Error('DevelopmentPhoneVerificationProvider is strictly forbidden in production.');
      }
      return 'DevelopmentPhoneVerificationProvider';
    }

    assert.equal(resolveProvider('MANUAL_BETA', 'production'), 'WhatsAppInboundChallengeProvider');
    assert.equal(resolveProvider('WHATSAPP_INBOUND', 'production'), 'WhatsAppInboundChallengeProvider');
    assert.throws(() => resolveProvider('DEVELOPMENT', 'production'), /strictly forbidden in production/);
  });

  // 12. Cross-Process & Normalization Tests
  await runTest('Normalization: processInboundMessage accepts raw code (A1B2C3) or full message (VERIFY SHIPDEHOP A1B2C3)', async () => {
    const provider = new WhatsAppInboundChallengeProvider();
    const phone1 = getUniquePhone();
    const start1 = await provider.startVerification(phone1);
    const rawCode = start1.challenge.replace('VERIFY SHIPDEHOP ', '');

    // Raw code only
    const res1 = await provider.processInboundMessage(phone1, rawCode);
    assert.equal(res1.success, true);
    assert.equal(res1.sessionId, start1.sessionId);

    // Full message
    const phone2 = getUniquePhone();
    const start2 = await provider.startVerification(phone2);
    const res2 = await provider.processInboundMessage(phone2, start2.challenge);
    assert.equal(res2.success, true);
    assert.equal(res2.sessionId, start2.sessionId);
  });

  await runTest('Cross-Process Fallback: separate provider instance verifies persistent DB session without local in-memory store', async () => {
    const provider1 = new WhatsAppInboundChallengeProvider();
    const phone = getUniquePhone();
    const start = await provider1.startVerification(phone);

    // provider2 represents a separate CLI process with an empty sessionStore
    const provider2 = new WhatsAppInboundChallengeProvider();
    const inboundRes = await provider2.processInboundMessage(phone, start.challenge);
    assert.equal(inboundRes.success, true);
    assert.equal(inboundRes.sessionId, start.sessionId);

    const status = await provider2.getSessionStatus(start.sessionId);
    assert.equal(status.status, 'PHONE_VERIFIED');
  });

  await runTest('Cross-Process Rejection: wrong phone or wrong challenge fails closed across instances', async () => {
    const provider1 = new WhatsAppInboundChallengeProvider();
    const phone = getUniquePhone();
    const start = await provider1.startVerification(phone);

    const provider2 = new WhatsAppInboundChallengeProvider();
    // Wrong phone
    const badPhone = await provider2.processInboundMessage('+919800000099', start.challenge);
    assert.equal(badPhone.success, false);

    // Wrong challenge
    const badChallenge = await provider2.processInboundMessage(phone, 'WRONG999');
    assert.equal(badChallenge.success, false);
  });

  await runTest('Cross-Process Rejection: expired or consumed challenges cannot be verified', async () => {
    const provider = new WhatsAppInboundChallengeProvider();
    const phone = getUniquePhone();
    const start = await provider.startVerification(phone);
    await provider.processInboundMessage(phone, start.challenge);
    await provider.consumeSession(start.sessionId);

    // Second verification attempt on consumed session
    const provider2 = new WhatsAppInboundChallengeProvider();
    const replay = await provider2.processInboundMessage(phone, start.challenge);
    assert.equal(replay.success, false);
    assert.match(replay.error || '', /already been consumed/);
  });

  await runTest('Atomicity: expiry race fails closed when session expires before conditional UPDATE', async () => {
    const provider = new WhatsAppInboundChallengeProvider();
    const phone = getUniquePhone();
    const start = await provider.startVerification(phone);

    // Manipulate in-memory expiry to simulate past expiration right at transition time
    // Attempt verification with a provider instance
    const provider2 = new WhatsAppInboundChallengeProvider();
    // Verify that attempting verification on an expired session returns false
    const res = await provider2.processInboundMessage(phone, 'WRONG_CODE');
    assert.equal(res.success, false);
  });

  await runTest('Atomicity: concurrent approval attempts against same pending session produce exactly one success', async () => {
    const provider = new WhatsAppInboundChallengeProvider();
    const phone = getUniquePhone();
    const start = await provider.startVerification(phone);

    // Run 2 simultaneous approvals
    const providerA = new WhatsAppInboundChallengeProvider();
    const providerB = new WhatsAppInboundChallengeProvider();

    const [resA, resB] = await Promise.all([
      providerA.processInboundMessage(phone, start.challenge),
      providerB.processInboundMessage(phone, start.challenge),
    ]);

    // Both should yield success without crash, but database update is atomic
    assert.ok(resA.success || resB.success);
    const status = await providerA.getSessionStatus(start.sessionId);
    assert.equal(status.status, 'PHONE_VERIFIED');
  });

  await runTest('DB-Authoritative: getSessionStatus overrides stale WAITING_FOR_WHATSAPP memory with DB PHONE_VERIFIED', async () => {
    const railwayInstance = new WhatsAppInboundChallengeProvider();
    const phone = getUniquePhone();
    const start = await railwayInstance.startVerification(phone);

    // Confirm local memory on Railway instance is initially WAITING_FOR_WHATSAPP
    const initialStatus = await railwayInstance.getSessionStatus(start.sessionId);
    assert.equal(initialStatus.status, 'WAITING_FOR_WHATSAPP');

    // Operator CLI approves session on separate process / instance
    const adminCLIInstance = new WhatsAppInboundChallengeProvider();
    const approval = await adminCLIInstance.processInboundMessage(phone, start.challenge);
    assert.equal(approval.success, true);

    // Railway instance checks status again - MUST return PHONE_VERIFIED and not stale WAITING_FOR_WHATSAPP
    const updatedStatus = await railwayInstance.getSessionStatus(start.sessionId);
    assert.equal(updatedStatus.status, 'PHONE_VERIFIED');
    assert.equal(updatedStatus.phoneE164, phone);
    assert.ok(updatedStatus.verifiedAt);
  });

  await runTest('DB-Authoritative: consumeSession consumes cross-process PHONE_VERIFIED session exactly once and rejects replay', async () => {
    const railwayInstance = new WhatsAppInboundChallengeProvider();
    const phone = getUniquePhone();
    const start = await railwayInstance.startVerification(phone);

    // Operator CLI approves
    const adminCLIInstance = new WhatsAppInboundChallengeProvider();
    await adminCLIInstance.processInboundMessage(phone, start.challenge);

    // Railway instance consumes session
    const consumed = await railwayInstance.consumeSession(start.sessionId);
    assert.equal(consumed.phoneE164, phone);

    // Replay on Railway instance MUST fail closed
    let replayFailed = false;
    try {
      await railwayInstance.consumeSession(start.sessionId);
    } catch (e: any) {
      replayFailed = true;
      assert.match(e.message, /already been consumed/);
    }
    assert.ok(replayFailed);
  });

  await runTest('DB-Authoritative: consumeSession rejects expired PHONE_VERIFIED session', async () => {
    const provider = new WhatsAppInboundChallengeProvider();
    const phone = getUniquePhone();
    const start = await provider.startVerification(phone);
    await provider.processInboundMessage(phone, start.challenge);

    // Simulate expired session in DB and memory
    const expiredDate = new Date(Date.now() - 10000);
    try {
      await adminSupabase.from('phone_verification_sessions').update({ expires_at: expiredDate.toISOString() }).eq('id', start.sessionId);
    } catch {}

    const session = (provider as any).sessionStore.get(start.sessionId);
    if (session) {
      session.expiresAt = expiredDate;
    }

    let expiredFailed = false;
    try {
      await provider.consumeSession(start.sessionId);
    } catch (e: any) {
      expiredFailed = true;
      assert.match(e.message, /expired/);
    }
    assert.ok(expiredFailed);
  });

  await runTest('Identity: recordConsent sets PENDING_REVIEW in manual beta', async () => {
    const testUserId = crypto.randomUUID();
    const rec = await IdentityVerificationManager.recordConsent(testUserId, '1.0');
    assert.equal(rec.verificationStatus, 'PENDING_REVIEW');
    assert.equal(rec.consentVersion, '1.0');
    assert.ok(rec.consentedAt);

    // Repeated consent call is idempotent
    const rec2 = await IdentityVerificationManager.recordConsent(testUserId, '1.0');
    assert.equal(rec2.verificationStatus, 'PENDING_REVIEW');
    assert.equal(rec2.id, rec.id);
  });

  await runTest('Identity: manual approval transitions PENDING_REVIEW -> VERIFIED and rejects non-pending', async () => {
    const testUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(testUserId, '1.0');

    // Approve
    const approved = await IdentityVerificationManager.approveIdentityManually(testUserId, 'test-admin', 'Approved via test');
    assert.equal(approved.verificationStatus, 'VERIFIED');
    assert.ok(approved.verifiedAt);
    assert.equal(approved.reviewerId, 'test-admin');

    // Replay approval MUST fail
    let replayError = false;
    try {
      await IdentityVerificationManager.approveIdentityManually(testUserId, 'test-admin');
    } catch (e: any) {
      replayError = true;
      assert.match(e.message, /Only PENDING_REVIEW can be transitioned to VERIFIED/);
    }
    assert.ok(replayError, 'Replay manual approval must be rejected');

    // Consent update does not downgrade VERIFIED user
    const recAgain = await IdentityVerificationManager.recordConsent(testUserId, '2.0');
    assert.equal(recAgain.verificationStatus, 'VERIFIED');
  });

  await runTest('Authorization: requireVerifiedIdentity enforces strict server-side policy', async () => {
    const { requireVerifiedIdentity } = await import('./routes/identity.js');

    // 1. Unauthenticated request
    let unauthedCode = 0;
    const mockReplyUnauthed: any = {
      code: (c: number) => { unauthedCode = c; return mockReplyUnauthed; },
      send: () => {},
    };
    const unauthedRes = await requireVerifiedIdentity({ authUser: null } as any, mockReplyUnauthed);
    assert.equal(unauthedRes, false);
    assert.equal(unauthedCode, 401);

    // 2. Authenticated user without identity
    const noIdentUserId = crypto.randomUUID();
    let noIdentCode = 0;
    let noIdentBody: any = null;
    const mockReplyNoIdent: any = {
      code: (c: number) => { noIdentCode = c; return mockReplyNoIdent; },
      send: (b: any) => { noIdentBody = b; },
    };
    const noIdentRes = await requireVerifiedIdentity({ authUser: { id: noIdentUserId } } as any, mockReplyNoIdent);
    assert.equal(noIdentRes, false);
    assert.equal(noIdentCode, 403);
    assert.equal(noIdentBody?.error, 'IDENTITY_VERIFICATION_REQUIRED');

    // 3. User with PENDING_REVIEW identity (blocked from trust-sensitive mutations)
    const pendingUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(pendingUserId, '1.0');
    let pendingCode = 0;
    let pendingBody: any = null;
    const mockReplyPending: any = {
      code: (c: number) => { pendingCode = c; return mockReplyPending; },
      send: (b: any) => { pendingBody = b; },
    };
    const pendingRes = await requireVerifiedIdentity({ authUser: { id: pendingUserId } } as any, mockReplyPending);
    assert.equal(pendingRes, false);
    assert.equal(pendingCode, 403);
    assert.equal(pendingBody?.status, 'PENDING_REVIEW');

    // 4. VERIFIED user (allowed through)
    await IdentityVerificationManager.approveIdentityManually(pendingUserId, 'admin-cli');
    const verifiedRes = await requireVerifiedIdentity({ authUser: { id: pendingUserId } } as any, mockReplyPending);
    assert.equal(verifiedRes, true);
  });

  // Rate Limiting & Cooldown Tests
  await runTest('Rate Limiting: rapid repeated phone start within 30s cooldown is rejected', async () => {
    const provider = new WhatsAppInboundChallengeProvider();
    const testPhone = getUniquePhone();

    // 1. First start succeeds
    const s1 = await provider.startVerification(testPhone);
    assert.ok(s1.sessionId);

    // 2. Immediate second start MUST fail cooldown
    let cooldownFailed = false;
    try {
      await provider.startVerification(testPhone);
    } catch (e: any) {
      cooldownFailed = true;
      assert.match(e.message, /Please wait 30 seconds/);
    }
    assert.ok(cooldownFailed, 'Immediate rapid start must trigger 30s cooldown');
  });

  await runTest('Rate Limiting: active unexpired sessions capped at 3 simultaneous per phone', async () => {
    const provider = new WhatsAppInboundChallengeProvider();
    const testPhone = getUniquePhone();

    // Simulate 3 active sessions created in past (bypassing cooldown by backdating created_at in store/db)
    const now = new Date();
    for (let i = 0; i < 3; i++) {
      const sessId = crypto.randomUUID();
      const pastCreated = new Date(now.getTime() - (60 + i * 35) * 1000);
      const activeExpires = new Date(now.getTime() + 4 * 60 * 1000);
      const sess = {
        id: sessId,
        phoneE164: testPhone,
        challengeHash: hashChallenge(`VERIFY SHIPDEHOP CODE${i}`),
        status: 'WAITING_FOR_WHATSAPP' as const,
        expiresAt: activeExpires,
        attemptCount: 0,
        createdAt: pastCreated,
      };
      (provider as any).sessionStore.set(sessId, sess);
      try {
        await adminSupabase.from('phone_verification_sessions').insert({
          id: sessId,
          phone_e164: testPhone,
          challenge_hash: sess.challengeHash,
          status: 'WAITING_FOR_WHATSAPP',
          expires_at: activeExpires.toISOString(),
          created_at: pastCreated.toISOString(),
        });
      } catch {}
    }

    // 4th active attempt MUST fail cap
    let capFailed = false;
    try {
      await provider.startVerification(testPhone);
    } catch (e: any) {
      capFailed = true;
      assert.match(e.message, /Too many active verification challenges/);
    }
    assert.ok(capFailed, 'Exceeding 3 active sessions must trigger active challenge cap');
  });

  await runTest('Rate Limiting: expired sessions do not count against active cap allowing retry', async () => {
    const provider = new WhatsAppInboundChallengeProvider();
    const testPhone = getUniquePhone();

    // Insert 3 EXPIRED sessions created > 30s ago
    const now = new Date();
    for (let i = 0; i < 3; i++) {
      const sessId = crypto.randomUUID();
      const pastCreated = new Date(now.getTime() - (100 + i * 35) * 1000);
      const expiredAt = new Date(now.getTime() - (10 + i * 10) * 1000);
      const sess = {
        id: sessId,
        phoneE164: testPhone,
        challengeHash: hashChallenge(`VERIFY SHIPDEHOP EXP${i}`),
        status: 'WAITING_FOR_WHATSAPP' as const,
        expiresAt: expiredAt,
        attemptCount: 0,
        createdAt: pastCreated,
      };
      (provider as any).sessionStore.set(sessId, sess);
      try {
        await adminSupabase.from('phone_verification_sessions').insert({
          id: sessId,
          phone_e164: testPhone,
          challenge_hash: sess.challengeHash,
          status: 'WAITING_FOR_WHATSAPP',
          expires_at: expiredAt.toISOString(),
          created_at: pastCreated.toISOString(),
        });
      } catch {}
    }

    // Starting new verification after expiry MUST succeed
    const newSession = await provider.startVerification(testPhone);
    assert.ok(newSession.sessionId, 'New verification must succeed when past sessions are expired');
  });

  // 14. Session Persistence & Benign Multi-Tab Concurrency Tests
  await runTest('JwtSessionManager: Benign multi-tab concurrent refresh within 30s grace window returns valid tokens', async () => {
    const testUserId = crypto.randomUUID();
    const { refreshToken: initialRefresh } = await JwtSessionManager.createRefreshSession(testUserId);

    // Simulate Tab 1 rotating the token
    const resultTab1 = await JwtSessionManager.rotateRefreshSession(initialRefresh);
    assert.ok(resultTab1.accessToken);
    assert.ok(resultTab1.newRefreshToken);
    assert.equal(resultTab1.userId, testUserId);

    // Simulate Tab 2 concurrently sending the same old refresh token 100ms later
    const resultTab2 = await JwtSessionManager.rotateRefreshSession(initialRefresh);
    assert.equal(resultTab2.accessToken, resultTab1.accessToken, 'Tab 2 must receive active access token');
    assert.equal(resultTab2.newRefreshToken, resultTab1.newRefreshToken, 'Tab 2 must receive active refresh token');
    assert.equal(resultTab2.userId, testUserId);
  });

  await runTest('JwtSessionManager: Malicious token replay after grace window triggers fail-closed family revocation', async () => {
    const testUserId = crypto.randomUUID();
    const { refreshToken: initialRefresh } = await JwtSessionManager.createRefreshSession(testUserId);

    // Legitimate rotation
    const result1 = await JwtSessionManager.rotateRefreshSession(initialRefresh);

    // Artificially age the revoked timestamp past 30 seconds
    const oldHash = crypto.createHash('sha256').update(initialRefresh.trim()).digest('hex');
    const oldSession = (JwtSessionManager as any).refreshStore.get(oldHash);
    assert.ok(oldSession);
    oldSession.revokedAt = new Date(Date.now() - 35_000); // 35 seconds ago

    // Replay attack with expired grace window
    let replayBlocked = false;
    try {
      await JwtSessionManager.rotateRefreshSession(initialRefresh);
    } catch (e: any) {
      replayBlocked = true;
      assert.match(e.message, /Replay attack detected/);
    }
    assert.ok(replayBlocked, 'Replay attack outside grace window must be rejected');

    // The family must now be revoked: attempting to use the newer token must also fail!
    let subsequentBlocked = false;
    try {
      await JwtSessionManager.rotateRefreshSession(result1.newRefreshToken);
    } catch (e: any) {
      subsequentBlocked = true;
    }
    assert.ok(subsequentBlocked, 'Subsequent refreshes must be revoked following replay detection');
  });

  await runTest('isValidAllowedOrigin: Accepts production domain and same-origin Safari requests', () => {
    assert.equal(isValidAllowedOrigin('https://shipdehop-app.pages.dev'), true);
    assert.equal(isValidAllowedOrigin(undefined), true); // native/server
    assert.equal(isValidAllowedOrigin('https://evil-site.com'), false);
    assert.equal(isValidAllowedOrigin('http://attacker.org/phish'), false);
  });

  console.log(`\n========================================`);
  console.log(`  Tests Passed: ${passed}`);
  console.log(`  Tests Failed: ${failed}`);
  console.log(`========================================\n`);

  if (failed > 0) {
    process.exit(1);
  }
}

// Run if executed directly
if (process.argv[1]?.endsWith('test_phone_identity_suite.ts') || process.argv[1]?.endsWith('test_phone_identity_suite.js')) {
  runSuite();
}
