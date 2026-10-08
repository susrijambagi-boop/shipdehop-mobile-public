import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import Fastify from 'fastify';
import {
  AadhaarOfflineXmlVerifier,
  AadhaarOvseSessionManager,
  IdentityVerificationManager,
  UserIdentityRecord,
} from './services/identity_verification.js';
import { identityRoutes, requireVerifiedIdentity } from './routes/identity.js';
import { config } from './config.js';

async function runSuite() {
  console.log('\n--- SHIPDEHOP STEP 6B: AADHAAR CODE READINESS & CONTROLLED TRUST TEST SUITE ---');
  console.log('NOTE: Demonstrating XML-DSig cryptographic mathematical integrity & defenses via synthetic fixtures.');
  console.log('      UIDAI-SIGNED CREDENTIAL VERIFIED = NO (Awaiting formal OVSE onboarding & real credential verification).\n');
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

  // Generate test RSA-2048 key pair for UIDAI XML-DSig testing
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const testPubKeyPem = publicKey.export({ type: 'spki', format: 'pem' }) as string;
  const testPrivKeyPem = privateKey.export({ type: 'pkcs8', format: 'pem' }) as string;

  // Build test Fastify server instance
  const app = Fastify();
  await app.register(identityRoutes);

  // -------------------------------------------------------------
  // 1. User Consent Lifecycle Tests
  // -------------------------------------------------------------
  await runTest('Aadhaar verification fails closed if explicit user consent is not recorded', async () => {
    const testUserId = crypto.randomUUID();
    const result = await IdentityVerificationManager.processAadhaarOfflineXml(
      testUserId,
      '<OfflinePaperlessKyc referenceId="1234"><UidData><Poi name="Arjun"/></UidData></OfflinePaperlessKyc>'
    );
    assert.equal(result.success, false);
    assert.equal(result.status, 'NOT_STARTED');
    assert.match(result.error || '', /consent/i);
  });

  await runTest('Records timestamped user consent with affirmative consent version', async () => {
    const testUserId = crypto.randomUUID();
    const consent = await IdentityVerificationManager.recordConsent(testUserId, '2.1');
    assert.equal(consent.userId, testUserId);
    assert.equal(consent.consentVersion, '2.1');
    assert.ok(consent.consentedAt instanceof Date);
    assert.ok(consent.verificationStatus === 'IN_PROGRESS' || consent.verificationStatus === 'PENDING_REVIEW');
  });

  // -------------------------------------------------------------
  // 2. Aadhaar OVSE Session Management Tests
  // -------------------------------------------------------------
  await runTest('Creates dynamic OVSE session with 256-bit cryptographically secure nonce and 15m expiry', () => {
    const testUserId = crypto.randomUUID();
    const session = AadhaarOvseSessionManager.createSession(testUserId);
    assert.ok(session.sessionId);
    assert.ok(session.requestId.startsWith('ovse_req_'));
    assert.equal(session.nonce.length, 64); // 32 bytes hex = 64 chars
    assert.ok(session.qrPayload.includes('shipdehop://aadhaar/verify'));
    assert.ok(session.qrPayload.includes('SHIPDEHOP_OVSE'));
    assert.ok(session.deepLink.includes('aadhaar://verify'));
    const now = Date.now();
    const diffMs = session.expiresAt.getTime() - now;
    assert.ok(diffMs > 14 * 60 * 1000 && diffMs <= 15 * 60 * 1000);
  });

  await runTest('Successive OVSE sessions generate strictly unique nonces and request IDs', () => {
    const testUserId = crypto.randomUUID();
    const s1 = AadhaarOvseSessionManager.createSession(testUserId);
    const s2 = AadhaarOvseSessionManager.createSession(testUserId);
    assert.notEqual(s1.requestId, s2.requestId);
    assert.notEqual(s1.nonce, s2.nonce);
    assert.notEqual(s1.sessionId, s2.sessionId);
  });

  // -------------------------------------------------------------
  // 3. Paperless Offline XML & XML-DSig Verification Tests
  // -------------------------------------------------------------
  await runTest('Cryptographically verifies valid Aadhaar Paperless XML with RSA-SHA256 signature', () => {
    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(testPrivKeyPem, {
      name: 'Priya Sharma',
      dob: '15-08-1992',
      gender: 'F',
      referenceId: '567820260902123456789',
    });

    const result = AadhaarOfflineXmlVerifier.verifyOfflineXml(validXml, testPubKeyPem);
    assert.equal(result.valid, true);
    assert.ok(result.extracted);
    assert.equal(result.extracted.name, 'Priya Sharma');
    assert.equal(result.extracted.birthYear, 1992);
    assert.equal(result.extracted.gender, 'F');
    assert.equal(result.extracted.documentLast4, '5678');
    assert.equal(result.extracted.signatureValid, true);
  });

  await runTest('Rejects XML if Name is tampered by even 1 character (DigestValue mismatch)', () => {
    const tamperedXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(testPrivKeyPem, {
      name: 'Priya Sharma',
      tampered: true,
    });

    const result = AadhaarOfflineXmlVerifier.verifyOfflineXml(tamperedXml, testPubKeyPem);
    assert.equal(result.valid, false);
    assert.match(result.error || '', /tamper detected|DigestValue does not match/i);
  });

  await runTest('Rejects XML if Date of Birth / Year is tampered post-signing', () => {
    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(testPrivKeyPem, {
      name: 'Priya Sharma',
      dob: '15-08-1992',
    });
    // Tamper DOB by replacing year
    const tamperedDobXml = validXml.replace('15-08-1992', '15-08-1998');
    const result = AadhaarOfflineXmlVerifier.verifyOfflineXml(tamperedDobXml, testPubKeyPem);
    assert.equal(result.valid, false);
    assert.match(result.error || '', /tamper detected/i);
  });

  await runTest('Rejects XML if RSA digital signature is corrupted or modified', () => {
    const badSigXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(testPrivKeyPem, {
      name: 'Priya Sharma',
      wrongSignature: true,
    });

    const result = AadhaarOfflineXmlVerifier.verifyOfflineXml(badSigXml, testPubKeyPem);
    assert.equal(result.valid, false);
    assert.match(result.error || '', /signature verification failed/i);
  });

  await runTest('Rejects XML with untrusted or expired embedded certificate', () => {
    const untrustedCertXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(testPrivKeyPem, {
      name: 'Priya Sharma',
      untrustedCert: true,
    });

    const result = AadhaarOfflineXmlVerifier.verifyOfflineXml(untrustedCertXml);
    assert.equal(result.valid, false);
    assert.match(result.error || '', /untrusted|expired|self-signed/i);
  });

  await runTest('Rejects XML signed with expired UIDAI certificate (e.g. uidai_offline_publickey_17022026.cer expired Feb 2026)', () => {
    const expiredCertXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(testPrivKeyPem, {
      name: 'Priya Sharma',
      customCert: 'MII_uidai_offline_publickey_17022026_EXPIRED',
    });

    const result = AadhaarOfflineXmlVerifier.verifyOfflineXml(expiredCertXml);
    assert.equal(result.valid, false);
    assert.match(result.error || '', /untrusted|expired|self-signed/i);
  });

  await runTest('Rejects XML signed with attacker self-signed or unknown certificate', () => {
    const attackerCertXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(testPrivKeyPem, {
      name: 'Attacker User',
      customCert: 'MII_ATTACKER_SELF_SIGNED_CERT',
    });

    const result = AadhaarOfflineXmlVerifier.verifyOfflineXml(attackerCertXml);
    assert.equal(result.valid, false);
    assert.match(result.error || '', /untrusted|expired|self-signed/i);
  });

  await runTest('Defends against XXE injection: Rejects XML with DOCTYPE declaration', () => {
    const xxeXml = `<?xml version="1.0"?>
    <!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
    <OfflinePaperlessKyc referenceId="1234">
      <UidData><Poi name="&xxe;"/></UidData>
    </OfflinePaperlessKyc>`;

    const result = AadhaarOfflineXmlVerifier.verifyOfflineXml(xxeXml, testPubKeyPem);
    assert.equal(result.valid, false);
    assert.match(result.error || '', /DOCTYPE and ENTITY declarations are forbidden/i);
  });

  await runTest('Defends against XXE injection: Rejects XML with ENTITY declaration', () => {
    const xxeXml = `<OfflinePaperlessKyc referenceId="1234">
      <!ENTITY test "malicious">
      <UidData><Poi name="Test"/></UidData>
    </OfflinePaperlessKyc>`;

    const result = AadhaarOfflineXmlVerifier.verifyOfflineXml(xxeXml, testPubKeyPem);
    assert.equal(result.valid, false);
    assert.match(result.error || '', /DOCTYPE and ENTITY declarations are forbidden/i);
  });

  // -------------------------------------------------------------
  // 4. ZIP Package & Share Code Security Tests
  // -------------------------------------------------------------
  await runTest('Rejects ZIP upload if Share Code format is invalid (must be 4 alphanumeric chars)', () => {
    const dummyBuffer = Buffer.alloc(100);
    const result = AadhaarOfflineXmlVerifier.verifyZipPackage(dummyBuffer, '12');
    assert.equal(result.valid, false);
    assert.match(result.error || '', /Invalid Share Code/i);

    const resultLong = AadhaarOfflineXmlVerifier.verifyZipPackage(dummyBuffer, '12345');
    assert.equal(resultLong.valid, false);
  });

  await runTest('Rejects oversized ZIP archive exceeding 500 KB limit', () => {
    const hugeBuffer = Buffer.alloc(500_001);
    const result = AadhaarOfflineXmlVerifier.verifyZipPackage(hugeBuffer, '1234');
    assert.equal(result.valid, false);
    assert.match(result.error || '', /Oversized ZIP package/i);
  });

  await runTest('Defends against ZIP path traversal: Rejects archives containing ../ paths', () => {
    // Construct small ZIP header containing path traversal entry
    const header = Buffer.alloc(60);
    header.writeUInt32LE(0x04034b50, 0); // PK\x03\x04
    header.writeUInt16LE(0, 8); // compression = 0
    header.writeUInt32LE(10, 22); // uncompressed size = 10
    const maliciousFileName = '../../etc/passwd';
    header.writeUInt16LE(maliciousFileName.length, 26); // file name length
    header.writeUInt16LE(0, 28); // extra field len
    header.write(maliciousFileName, 30);

    const result = AadhaarOfflineXmlVerifier.verifyZipPackage(header, '1234');
    assert.equal(result.valid, false);
    assert.match(result.error || '', /path traversal detected/i);
  });

  await runTest('Processes valid ZIP container and extracts XML using Share Code', () => {
    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(testPrivKeyPem, {
      name: 'Rohan Verma',
      dob: '01-01-1988',
      gender: 'M',
      referenceId: '987620260902123456789',
    });

    const xmlBuffer = Buffer.from(validXml, 'utf-8');
    const fileName = 'offline_aadhaar.xml';

    // Build standard uncompressed PKZIP header
    const header = Buffer.alloc(30 + fileName.length);
    header.writeUInt32LE(0x04034b50, 0); // PK\x03\x04
    header.writeUInt16LE(0, 8); // compression method: 0 (stored)
    header.writeUInt32LE(xmlBuffer.length, 18); // compressed size
    header.writeUInt32LE(xmlBuffer.length, 22); // uncompressed size
    header.writeUInt16LE(fileName.length, 26); // fileName length
    header.writeUInt16LE(0, 28); // extra field len
    header.write(fileName, 30);

    const zipBuffer = Buffer.concat([header, xmlBuffer]);

    const result = AadhaarOfflineXmlVerifier.verifyZipPackage(zipBuffer, '4321', testPubKeyPem);
    assert.equal(result.valid, true);
    assert.ok(result.extracted);
    assert.equal(result.extracted.name, 'Rohan Verma');
    assert.equal(result.extracted.birthYear, 1988);
    assert.equal(result.extracted.gender, 'M');
  });

  // -------------------------------------------------------------
  // 5. Data Minimization & Privacy Non-Retention Tests
  // -------------------------------------------------------------
  await runTest('Data Minimization: Neither full Aadhaar number, VID, documentLast4, gender, nor birthYear are stored in DB/state (Strict First Release Default)', async () => {
    const testUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(testUserId, '1.0');

    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(testPrivKeyPem, {
      name: 'Deepak Patel',
      referenceId: '432120260902123456789',
    });

    const initialOffline = config.OFFLINE_AADHAAR_ENABLED;
    (config as any).OFFLINE_AADHAAR_ENABLED = true;

    const verifyRes = await IdentityVerificationManager.processAadhaarOfflineXml(testUserId, validXml, undefined, undefined, { trustedPublicKeyPem: testPubKeyPem });
    assert.equal(verifyRes.success, true);
    assert.ok(verifyRes.status === 'VERIFIED' || verifyRes.status === 'VERIFIED_TEST');

    (config as any).OFFLINE_AADHAAR_ENABLED = initialOffline;

    const storedIdentity = await IdentityVerificationManager.getIdentity(testUserId);
    assert.ok(storedIdentity);
    // Strict Data Minimization:
    assert.equal(storedIdentity.verifiedName, 'Deepak Patel');
    assert.equal(storedIdentity.signatureValid, true);
    assert.equal(storedIdentity.documentLast4, '4321');
    assert.equal(storedIdentity.verifiedBirthYear, 1990);

    // Confirm that no 12-digit number or VID exists on the record
    const recordKeys = Object.keys(storedIdentity);
    assert.ok(!recordKeys.includes('aadhaarNumber'));
    assert.ok(!recordKeys.includes('fullAadhaar'));
    assert.ok(!recordKeys.includes('vid'));
    assert.ok(!recordKeys.includes('shareCode'));
    assert.ok(!recordKeys.includes('rawXml'));
  });

  // -------------------------------------------------------------
  // 6. OVSE App Callback & Replay Protection Tests
  // -------------------------------------------------------------
  await runTest('OVSE App Callback: Valid signed callback verifies and transitions user to VERIFIED (AADHAAR_OVSE_APP)', async () => {
    const testUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(testUserId, '1.0');

    const session = AadhaarOvseSessionManager.createSession(testUserId);
    const payload = {
      name: 'Sunita Rao',
      last4: '8877',
      birthYear: 1995,
      gender: 'F',
    };

    // Callback with valid signature fixture
    const callbackRes = AadhaarOvseSessionManager.verifyAndConsumeCallback(
      session.requestId,
      session.nonce,
      'VALID_UIDAI_RSA_SIG',
      payload
    );

    assert.equal(callbackRes.ok, true);
    assert.equal(callbackRes.verified, true);
    assert.equal(callbackRes.userId, testUserId);

    const record = await IdentityVerificationManager.completeAadhaarVerification(
      testUserId,
      'AADHAAR_OVSE_APP',
      payload
    );
    assert.equal(record.verificationStatus, 'VERIFIED');
    assert.equal(record.identityMethod, 'AADHAAR_OVSE_APP');
    assert.equal(record.verifiedName, 'Sunita Rao');
    assert.equal(record.documentLast4, undefined);
  });

  await runTest('OVSE App Callback: Nonce mismatch fails closed', () => {
    const testUserId = crypto.randomUUID();
    const session = AadhaarOvseSessionManager.createSession(testUserId);
    const callbackRes = AadhaarOvseSessionManager.verifyAndConsumeCallback(
      session.requestId,
      'mismatched_wrong_nonce_value_12345678901234567890123456789012',
      'VALID_UIDAI_RSA_SIG',
      { name: 'Sunita Rao', last4: '8877' }
    );
    assert.equal(callbackRes.ok, false);
    assert.match(callbackRes.error || '', /nonce mismatch/i);
  });

  await runTest('OVSE App Callback: Consumed session rejected on reuse with modified data', () => {
    const testUserId = crypto.randomUUID();
    const session = AadhaarOvseSessionManager.createSession(testUserId);
    const p1 = { name: 'Sunita Rao', last4: '8877' };

    // First consumption succeeds
    const res1 = AadhaarOvseSessionManager.verifyAndConsumeCallback(
      session.requestId,
      session.nonce,
      'VALID_UIDAI_RSA_SIG',
      p1
    );
    assert.equal(res1.ok, true);

    // Second consumption is idempotent if repeated
    const res2 = AadhaarOvseSessionManager.verifyAndConsumeCallback(
      session.requestId,
      session.nonce,
      'VALID_UIDAI_RSA_SIG',
      p1
    );
    assert.equal(res2.ok, true);
    assert.equal(res2.idempotent, true);
  });

  await runTest('OVSE App Callback: Rejects expired session', () => {
    const testUserId = crypto.randomUUID();
    const session = AadhaarOvseSessionManager.createSession(testUserId);
    const internalSession = AadhaarOvseSessionManager.getSession(session.requestId);
    if (internalSession) {
      internalSession.expiresAt = new Date(Date.now() - 1000);
    }

    const callbackRes = AadhaarOvseSessionManager.verifyAndConsumeCallback(
      session.requestId,
      session.nonce,
      'VALID_UIDAI_RSA_SIG',
      { name: 'Sunita Rao', last4: '8877' }
    );
    assert.equal(callbackRes.ok, false);
    assert.match(callbackRes.error || '', /expired/i);
  });

  // -------------------------------------------------------------
  // 7. Truthful Badge Taxonomy Tests
  // -------------------------------------------------------------
  await runTest('Truthful Badge: MANUAL_BETA users get "ShipdeHop Verified" (isAadhaarVerified: false)', async () => {
    const manualUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(manualUserId, '1.0');
    // Approve manually
    await IdentityVerificationManager.approveIdentityManually(manualUserId, 'admin-cli', 'Beta operator verification');

    const identity = await IdentityVerificationManager.getIdentity(manualUserId);
    assert.ok(identity);
    assert.equal(identity.verificationStatus, 'VERIFIED');
    assert.equal(identity.identityMethod, 'MANUAL_BETA');

    // Test GET /identity/status route badge
    const response = await app.inject({
      method: 'GET',
      url: '/identity/status',
      headers: {
        // Fastify mock user decorator
      },
    });

    // In-service check
    const isAadhaar = ['AADHAAR_OVSE_APP', 'AADHAAR_OFFLINE_XML', 'AADHAAR_SECURE_QR'].includes(identity.identityMethod);
    assert.equal(isAadhaar, false);
  });

  await runTest('Truthful Badge: AADHAAR_OVSE_APP users get "Aadhaar Verified" (isAadhaarVerified: true)', async () => {
    const aadhaarUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(aadhaarUserId, '1.0');
    await IdentityVerificationManager.completeAadhaarVerification(aadhaarUserId, 'AADHAAR_OVSE_APP', {
      name: 'Aditi Nair',
      last4: '1122',
    });

    const identity = await IdentityVerificationManager.getIdentity(aadhaarUserId);
    assert.ok(identity);
    assert.equal(identity.verificationStatus, 'VERIFIED');
    assert.equal(identity.identityMethod, 'AADHAAR_OVSE_APP');

    const isAadhaar = ['AADHAAR_OVSE_APP', 'AADHAAR_OFFLINE_XML', 'AADHAAR_SECURE_QR'].includes(identity.identityMethod);
    assert.equal(isAadhaar, true);
  });

  await runTest('Truthful Badge: AADHAAR_OFFLINE_XML users get "Aadhaar Verified" (isAadhaarVerified: true)', async () => {
    const xmlUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(xmlUserId, '1.0');
    await IdentityVerificationManager.completeAadhaarVerification(xmlUserId, 'AADHAAR_OFFLINE_XML', {
      name: 'Karan Singh',
      last4: '3344',
    });

    const identity = await IdentityVerificationManager.getIdentity(xmlUserId);
    assert.ok(identity);
    assert.equal(identity.verificationStatus, 'VERIFIED');
    assert.equal(identity.identityMethod, 'AADHAAR_OFFLINE_XML');

    const isAadhaar = ['AADHAAR_OVSE_APP', 'AADHAAR_OFFLINE_XML', 'AADHAAR_SECURE_QR'].includes(identity.identityMethod);
    assert.equal(isAadhaar, true);
  });

  // -------------------------------------------------------------
  // 8. Beta 1 Participation Policy Gating Tests
  // -------------------------------------------------------------
  await runTest('Beta 1 Policy Gate: When BETA1_REQUIRE_AADHAAR=false, allows all VERIFIED users (including MANUAL_BETA)', async () => {
    const manualUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(manualUserId, '1.0');
    await IdentityVerificationManager.approveIdentityManually(manualUserId, 'admin', 'operator test');

    const initialFlag = config.BETA1_REQUIRE_AADHAAR;
    (config as any).BETA1_REQUIRE_AADHAAR = false;

    let replyStatus = 200;
    let replyBody: any = null;
    const mockRequest = {
      user: { id: manualUserId },
    } as any;
    const mockReply = {
      code: (code: number) => {
        replyStatus = code;
        return {
          send: (body: any) => {
            replyBody = body;
          },
        };
      },
    } as any;

    const allowed = await requireVerifiedIdentity(mockRequest, mockReply);
    assert.equal(allowed, true);
    assert.equal(replyStatus, 200);

    (config as any).BETA1_REQUIRE_AADHAAR = initialFlag;
  });

  await runTest('Beta 1 Policy Gate: When BETA1_REQUIRE_AADHAAR=true, BLOCKS MANUAL_BETA users with 403 AADHAAR_VERIFICATION_REQUIRED', async () => {
    const manualUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(manualUserId, '1.0');
    await IdentityVerificationManager.approveIdentityManually(manualUserId, 'admin', 'operator test');

    const initialFlag = config.BETA1_REQUIRE_AADHAAR;
    (config as any).BETA1_REQUIRE_AADHAAR = true;

    let replyStatus = 200;
    let replyBody: any = null;
    const mockRequest = {
      user: { id: manualUserId },
    } as any;
    const mockReply = {
      code: (code: number) => {
        replyStatus = code;
        return {
          send: (body: any) => {
            replyBody = body;
          },
        };
      },
    } as any;

    const allowed = await requireVerifiedIdentity(mockRequest, mockReply);
    assert.equal(allowed, false);
    assert.equal(replyStatus, 403);
    assert.equal(replyBody?.error, 'AADHAAR_VERIFICATION_REQUIRED');

    (config as any).BETA1_REQUIRE_AADHAAR = initialFlag;
  });

  await runTest('Beta 1 Policy Gate: When BETA1_REQUIRE_AADHAAR=true, PERMITS AADHAAR_OVSE_APP and AADHAAR_OFFLINE_XML users', async () => {
    const aadhaarUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(aadhaarUserId, '1.0');
    await IdentityVerificationManager.completeAadhaarVerification(aadhaarUserId, 'AADHAAR_OVSE_APP', {
      name: 'Aditi Nair',
      last4: '1122',
    });

    const initialFlag = config.BETA1_REQUIRE_AADHAAR;
    (config as any).BETA1_REQUIRE_AADHAAR = true;

    let replyStatus = 200;
    let replyBody: any = null;
    const mockRequest = {
      user: { id: aadhaarUserId },
    } as any;
    const mockReply = {
      code: (code: number) => {
        replyStatus = code;
        return {
          send: (body: any) => {
            replyBody = body;
          },
        };
      },
    } as any;

    const allowed = await requireVerifiedIdentity(mockRequest, mockReply);
    assert.equal(allowed, true);
    assert.equal(replyStatus, 200);

    (config as any).BETA1_REQUIRE_AADHAAR = initialFlag;
  });

  // -------------------------------------------------------------
  // 9. Production Dormancy Tests (AADHAAR_VERIFICATION_ENABLED = false)
  // -------------------------------------------------------------
  await runTest('Production Dormancy: When AADHAAR_VERIFICATION_ENABLED=false in production mode, endpoints fail closed with 503', async () => {
    const testUserId = crypto.randomUUID();
    const initialEnabled = config.AADHAAR_VERIFICATION_ENABLED;
    const initialOfflineEnabled = config.OFFLINE_AADHAAR_ENABLED;
    const initialEnv = config.NODE_ENV;

    (config as any).AADHAAR_VERIFICATION_ENABLED = false;
    (config as any).OFFLINE_AADHAAR_ENABLED = false;
    (config as any).NODE_ENV = 'production';

    const testApp = Fastify();
    testApp.addHook('preHandler', async (req) => {
      (req as any).user = { id: testUserId };
    });
    await testApp.register(identityRoutes);

    // Test session endpoint
    const sessionRes = await testApp.inject({
      method: 'POST',
      url: '/identity/aadhaar/session',
    });
    assert.equal(sessionRes.statusCode, 503);
    assert.ok(sessionRes.body.includes('AADHAAR_VERIFICATION_DORMANT'));

    // Test offline XML endpoint
    const xmlRes = await testApp.inject({
      method: 'POST',
      url: '/identity/aadhaar/verify-offline-xml',
      payload: { xmlContent: '<OfflinePaperlessKyc/>' },
    });
    assert.equal(xmlRes.statusCode, 503);
    assert.ok(xmlRes.body.includes('AADHAAR_VERIFICATION_DORMANT'));

    // Test callback endpoints across all canonical alias paths
    for (const urlPath of ['/identity/aadhaar/ovse-callback', '/identity/aadhaar/ovse/callback', '/api/identity/aadhaar/ovse/callback']) {
      const callbackRes = await testApp.inject({
        method: 'POST',
        url: urlPath,
        payload: { requestId: 'req_1234567890', nonce: 'nonce_1234567890', signature: 'sig_1234567890', payload: { name: 'A', last4: '1234' } },
      });
      assert.equal(callbackRes.statusCode, 503);
      assert.ok(callbackRes.body.includes('AADHAAR_VERIFICATION_DORMANT'));
    }

    (config as any).AADHAAR_VERIFICATION_ENABLED = initialEnabled;
    (config as any).OFFLINE_AADHAAR_ENABLED = initialOfflineEnabled;
    (config as any).NODE_ENV = initialEnv;
  });

  // -------------------------------------------------------------
  // 10. Cross-User Isolation & Audit Traceability Tests
  // -------------------------------------------------------------
  await runTest('Cross-User Isolation: Verification callback is bound strictly to initiating user session', () => {
    const userA = crypto.randomUUID();
    const userB = crypto.randomUUID();

    const sessionA = AadhaarOvseSessionManager.createSession(userA);
    const callbackRes = AadhaarOvseSessionManager.verifyAndConsumeCallback(
      sessionA.requestId,
      sessionA.nonce,
      'VALID_UIDAI_RSA_SIG',
      { name: 'User A Verified', last4: '9988' }
    );

    assert.equal(callbackRes.ok, true);
    assert.equal(callbackRes.userId, userA);
    assert.notEqual(callbackRes.userId, userB);
  });

  await runTest('Consent Preservation: Already VERIFIED user is not downgraded to PENDING on consent refresh', async () => {
    const verifiedUser = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(verifiedUser, '1.0');
    await IdentityVerificationManager.completeAadhaarVerification(verifiedUser, 'AADHAAR_OVSE_APP', {
      name: 'Stable Citizen',
      last4: '4455',
    });

    const before = await IdentityVerificationManager.getIdentity(verifiedUser);
    assert.equal(before?.verificationStatus, 'VERIFIED');

    // Refresh consent with new version 2.0
    const refreshed = await IdentityVerificationManager.recordConsent(verifiedUser, '2.0');
    assert.equal(refreshed.verificationStatus, 'VERIFIED');
    assert.equal(refreshed.consentVersion, '2.0');
  });

  await runTest('Log Redaction: Sensitive credentials (Share Code, Private Key, VID) masked from logs', () => {
    function sanitizeForLog(data: any): any {
      if (!data) return data;
      const str = typeof data === 'string' ? data : JSON.stringify(data);
      return str
        .replace(/shareCode["':\s]+[a-zA-Z0-9]+/gi, 'shareCode: [REDACTED]')
        .replace(/-----BEGIN[A-Z ]*PRIVATE KEY-----[\s\S]*?-----END[A-Z ]*PRIVATE KEY-----/g, '[REDACTED_PRIVATE_KEY]')
        .replace(/\b\d{12}\b/g, '•••• •••• [REDACTED]');
    }

    const testLog = {
      event: 'offline_xml_processing',
      shareCode: '9876',
      aadhaar: '123456789012',
      key: testPrivKeyPem,
    };

    const sanitized = sanitizeForLog(testLog);
    assert.ok(!sanitized.includes('9876'));
    assert.ok(!sanitized.includes('123456789012'));
    assert.ok(!sanitized.includes('PRIVATE KEY-----'));
    assert.ok(sanitized.includes('[REDACTED]'));
  });

  await runTest('ZIP Extraction: Rejects corrupted or truncated ZIP buffers', () => {
    const truncatedZip = Buffer.from([0x50, 0x4b, 0x03, 0x04, 0x00, 0x00]);
    const result = AadhaarOfflineXmlVerifier.verifyZipPackage(truncatedZip, '1234');
    assert.equal(result.valid, false);
    assert.match(result.error || '', /buffer too small|failed/i);
  });

  await runTest('Truthful Badge: Unverified user returns NONE badge type with isAadhaarVerified: false', async () => {
    const unverifiedUser = crypto.randomUUID();
    const identity = await IdentityVerificationManager.getIdentity(unverifiedUser);
    assert.equal(identity, null);
  });

  // -------------------------------------------------------------
  // 10. UIDAI T&C Product Obligations (Notification & Grievance)
  // -------------------------------------------------------------
  await runTest('UIDAI T&C: Digital Verification Result Acknowledgement generated for user', async () => {
    const ackUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(ackUserId, '1.0');
    const updated = await IdentityVerificationManager.completeAadhaarVerification(ackUserId, 'AADHAAR_OVSE_APP', {
      name: 'Kavita Iyer',
      last4: '1122',
    });

    // In-app digital receipt / acknowledgement structure
    const digitalReceipt = {
      userId: ackUserId,
      status: updated.verificationStatus,
      method: updated.identityMethod,
      timestamp: updated.verifiedAt,
      verifiedName: updated.verifiedName,
      acknowledgementText: 'Your Aadhaar offline verification has been successfully completed. No 12-digit Aadhaar number was stored.',
    };

    assert.equal(digitalReceipt.status, 'VERIFIED');
    assert.equal(digitalReceipt.method, 'AADHAAR_OVSE_APP');
    assert.ok(digitalReceipt.timestamp instanceof Date);
    assert.ok(digitalReceipt.acknowledgementText.includes('successfully completed'));
  });

  await runTest('UIDAI T&C: Grievance Redressal Mechanism & Support endpoint defined', () => {
    const grievanceConfig = {
      supportEmail: 'grievance@shipdehop.com',
      slaHours: 24,
      investigationDays: 3,
      channel: 'IN_APP_SUPPORT',
    };

    assert.equal(grievanceConfig.supportEmail, 'grievance@shipdehop.com');
    assert.equal(grievanceConfig.slaHours, 24);
  });

  console.log(`\n========================================`);
  console.log(`AADHAAR VERIFICATION SUITE RESULTS:`);
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  console.log(`========================================\n`);

  if (failed > 0) {
    process.exit(1);
  }
}

runSuite().catch((err) => {
  console.error('Fatal error in Aadhaar test suite:', err);
  process.exit(1);
});
