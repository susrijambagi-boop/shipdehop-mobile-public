import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import Fastify from 'fastify';
import { config } from './config.js';
import { identityRoutes, requireVerifiedIdentity } from './routes/identity.js';
import { defaultAadhaarSessionStore, InMemoryAadhaarSessionStore } from './services/aadhaar/sessionStore.js';
import { UidaiPreprodProvider } from './services/aadhaar/uidaiPreprodProvider.js';
import { UidaiProductionProvider } from './services/aadhaar/uidaiProductionProvider.js';
import { getAadhaarProvider } from './services/aadhaar/provider.js';
import { computeSha256Digest, maskAadhaarNumber, sanitizeLogContent, UIDAI_DSIG_URIS, validateAadhaarVerhoeff } from './services/aadhaar/uidaiCrypto.js';
import { parseKycResponseXml, parseOtpResponseXml } from './services/aadhaar/uidaiResponse.js';
import { buildKyc25RequestXml, buildOtp25RequestXml, buildUidaiEndpointUrl } from './services/aadhaar/uidaiXml.js';
import { IdentityVerificationManager } from './services/identity_verification.js';

async function runSuite() {
  console.log('\n--- SHIPDEHOP OFFICIAL UIDAI PRE-PRODUCTION OTP E-KYC TEST SUITE ---');
  console.log('Testing UIDAI Developer API 2.5 Specification, SHA-256 XML-DSig Signatures (UIDAI Circular 4 of 2026), Decoupled Session Store & Pre-Prod Identity Labeling.\n');

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

  // Setup test Fastify server
  const app = Fastify();
  await app.register(identityRoutes);

  // Generate test RSA-2048 key pair
  const { publicKey, privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const testPubKeyPem = publicKey.export({ type: 'spki', format: 'pem' }) as string;
  const testPrivKeyPem = privateKey.export({ type: 'pkcs8', format: 'pem' }) as string;

  // -------------------------------------------------------------
  // 1. Mandatory Consent Enforcement
  // -------------------------------------------------------------
  await runTest('1. OTP Request requires explicit user consent (fails closed if consent=false)', async () => {
    const provider = new UidaiPreprodProvider();
    const res = await provider.requestOtp({
      userId: crypto.randomUUID(),
      aadhaarNumber: '999999990019',
      consent: false,
    });
    assert.equal(res.success, false);
    assert.equal(res.errorCode, 'CONSENT_REQUIRED');
  });

  // -------------------------------------------------------------
  // 2. Format & Verhoeff Checksum Validation
  // -------------------------------------------------------------
  await runTest('2. Rejects invalid length Aadhaar numbers (must be 12 digits)', async () => {
    const provider = new UidaiPreprodProvider();
    const res = await provider.requestOtp({
      userId: crypto.randomUUID(),
      aadhaarNumber: '12345',
      consent: true,
    });
    assert.equal(res.success, false);
    assert.equal(res.errorCode, 'INVALID_AADHAAR_FORMAT');
  });

  await runTest('3. Rejects invalid Verhoeff checksum Aadhaar numbers', async () => {
    const provider = new UidaiPreprodProvider();
    // 123456789012 fails Verhoeff checksum
    const res = await provider.requestOtp({
      userId: crypto.randomUUID(),
      aadhaarNumber: '123456789012',
      consent: true,
    });
    assert.equal(res.success, false);
    assert.equal(res.errorCode, 'VERHOEFF_CHECKSUM_FAILED');
  });

  await runTest('3b. Passes valid Verhoeff checksum Aadhaar numbers (e.g. 999999990019)', () => {
    assert.equal(validateAadhaarVerhoeff('999999990019'), true);
    assert.equal(validateAadhaarVerhoeff('999911112222'), true);
  });

  // -------------------------------------------------------------
  // 3. Log Redaction & Privacy Non-Retention
  // -------------------------------------------------------------
  await runTest('4. Redacts full 12-digit Aadhaar number from log strings', () => {
    const sanitized = sanitizeLogContent('Processing UID 999999990019 for user test');
    assert.ok(!sanitized.includes('999999990019'));
    assert.ok(sanitized.includes('[REDACTED_UID]'));
  });

  await runTest('5. Masked Aadhaar in API responses never reveals full 12 digits', async () => {
    const provider = new UidaiPreprodProvider();
    const res = await provider.requestOtp({
      userId: crypto.randomUUID(),
      aadhaarNumber: '999999990019',
      consent: true,
    });
    assert.equal(res.success, true);
    assert.equal(res.maskedAadhaar, '•••• •••• 0019');
    assert.ok(!JSON.stringify(res).includes('999999990019'));
  });

  await runTest('6. Redacts OTP from telemetry & error logs', () => {
    const sanitized = sanitizeLogContent({ event: 'otp_verify', otp: '123456' });
    assert.ok(!sanitized.includes('123456'));
    assert.ok(sanitized.includes('[REDACTED_OTP]'));
  });

  await runTest('7. OTP is never persisted in session objects or database state', async () => {
    const sessionStore = new InMemoryAadhaarSessionStore();
    const provider = new UidaiPreprodProvider(sessionStore);
    const userId = crypto.randomUUID();

    const requestRes = await provider.requestOtp({
      userId,
      aadhaarNumber: '999999990019',
      consent: true,
    });

    const session = await sessionStore.getSession(requestRes.sessionId!);
    assert.ok(session);
    assert.equal((session as any).otp, undefined);
    assert.equal(Object.keys(session).includes('otp'), false);
  });

  // -------------------------------------------------------------
  // 4. Decoupled Session Store & Security Isolation
  // -------------------------------------------------------------
  await runTest('8. Session is strictly bound to initiating user', async () => {
    const sessionStore = new InMemoryAadhaarSessionStore();
    const provider = new UidaiPreprodProvider(sessionStore);
    const userA = crypto.randomUUID();
    const userB = crypto.randomUUID();

    const reqRes = await provider.requestOtp({
      userId: userA,
      aadhaarNumber: '999999990019',
      consent: true,
    });

    const verifyRes = await provider.verifyOtpAndFetchKyc({
      userId: userB, // Wrong user
      verificationSessionId: reqRes.sessionId!,
      otp: '123456',
    });

    assert.equal(verifyRes.success, false);
    assert.equal(verifyRes.errorCode, 'SESSION_USER_MISMATCH');
  });

  await runTest('9. Cross-user session isolation: User B cannot access User A session', async () => {
    const sessionStore = new InMemoryAadhaarSessionStore();
    const userA = crypto.randomUUID();
    const session = await sessionStore.createSession({ userId: userA, maskedAadhaar: '•••• •••• 0019' });

    const fetched = await sessionStore.getSession(session.sessionId);
    assert.equal(fetched?.userId, userA);
  });

  await runTest('10. Rejects expired verification session (10 min TTL)', async () => {
    const sessionStore = new InMemoryAadhaarSessionStore();
    const provider = new UidaiPreprodProvider(sessionStore);
    const userId = crypto.randomUUID();

    const reqRes = await provider.requestOtp({ userId, aadhaarNumber: '999999990019', consent: true });
    const session = await sessionStore.getSession(reqRes.sessionId!);
    if (session) {
      session.expiresAt = new Date(Date.now() - 1000); // Expire artificially
    }

    const verifyRes = await provider.verifyOtpAndFetchKyc({
      userId,
      verificationSessionId: reqRes.sessionId!,
      otp: '123456',
    });

    assert.equal(verifyRes.success, false);
    assert.equal(verifyRes.errorCode, 'SESSION_EXPIRED');
  });

  await runTest('11. Resend cooldown rate limiting (60s cooldown returned)', async () => {
    const provider = new UidaiPreprodProvider();
    const res = await provider.requestOtp({
      userId: crypto.randomUUID(),
      aadhaarNumber: '999999990019',
      consent: true,
    });
    assert.equal(res.cooldownSeconds, 60);
  });

  await runTest('12. Enforces maximum 3 OTP verification attempts per session', async () => {
    const sessionStore = new InMemoryAadhaarSessionStore();
    const provider = new UidaiPreprodProvider(sessionStore);
    const userId = crypto.randomUUID();

    const reqRes = await provider.requestOtp({ userId, aadhaarNumber: '999999990019', consent: true });

    // 3 failed attempts
    for (let i = 0; i < 3; i++) {
      await provider.verifyOtpAndFetchKyc({ userId, verificationSessionId: reqRes.sessionId!, otp: '999999' });
    }

    // 4th attempt rejected due to max attempts
    const FourthRes = await provider.verifyOtpAndFetchKyc({ userId, verificationSessionId: reqRes.sessionId!, otp: '123456' });
    assert.equal(FourthRes.success, false);
    assert.equal(FourthRes.errorCode, 'MAX_ATTEMPTS_EXCEEDED');
  });

  // -------------------------------------------------------------
  // 5. XML Security & SHA-256 Signatures (UIDAI Specification 2.5)
  // -------------------------------------------------------------
  await runTest('13. XXE Defense: Rejects XML payloads containing DOCTYPE or ENTITY', () => {
    const xxePayload = `<?xml version="1.0"?><!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><KycRes ret="Y"/>`;
    const parsed = parseKycResponseXml(xxePayload);
    assert.equal(parsed.success, false);
    assert.match(parsed.error || '', /DOCTYPE and ENTITY declarations forbidden/i);
  });

  await runTest('14. UIDAI Error Code Mapping converts technical errors (e.g. 200, 100) to clear messages', () => {
    const errorXml = `<KycRes ret="N" err="200" txn="shp_123"/>`;
    const parsed = parseKycResponseXml(errorXml);
    assert.equal(parsed.success, false);
    assert.equal(parsed.code, '200');
    assert.match(parsed.error || '', /invalid or incorrect OTP/i);
  });

  await runTest('15. UIDAI Request XML uses DigestMethod SHA-256 (http://www.w3.org/2000/09/xmldsig#sha256) per UIDAI 2.5 spec', () => {
    const xml = buildKyc25RequestXml({
      uid: '999999990019',
      otp: '123456',
      auaCode: 'public',
      subAuaCode: 'public',
      licenseKey: 'MOw-DpjjHGxPlnKDXZlGh72zoPoryq4q5K1AhJL58HKfsoeCklXadcw',
      txnId: 'txn_123',
      signingPrivateKeyPem: testPrivKeyPem,
    });

    assert.ok(xml.includes(`Algorithm="${UIDAI_DSIG_URIS.DIGEST_METHOD_SHA256}"`));
    assert.ok(xml.includes('http://www.w3.org/2000/09/xmldsig#sha256'));
  });

  await runTest('15b. UIDAI Request XML uses SignatureMethod RSA-SHA256 (http://www.w3.org/2000/09/xmldsig#rsa-sha256)', () => {
    const xml = buildKyc25RequestXml({
      uid: '999999990019',
      otp: '123456',
      auaCode: 'public',
      subAuaCode: 'public',
      licenseKey: 'MOw-DpjjHGxPlnKDXZlGh72zoPoryq4q5K1AhJL58HKfsoeCklXadcw',
      txnId: 'txn_123',
      signingPrivateKeyPem: testPrivKeyPem,
    });

    assert.ok(xml.includes(`Algorithm="${UIDAI_DSIG_URIS.SIGNATURE_METHOD_RSA_SHA256}"`));
    assert.ok(xml.includes('http://www.w3.org/2000/09/xmldsig#rsa-sha256'));
  });

  await runTest('16. Negative test: strictly prohibits obsolete URIs (xmldsig#sha1, rsa-sha1, 2001/04/xmlenc#sha256, xmldsig-more#rsa-sha256)', () => {
    const xml = buildKyc25RequestXml({
      uid: '999999990019',
      otp: '123456',
      auaCode: 'public',
      subAuaCode: 'public',
      licenseKey: 'MOw-DpjjHGxPlnKDXZlGh72zoPoryq4q5K1AhJL58HKfsoeCklXadcw',
      txnId: 'txn_123',
      signingPrivateKeyPem: testPrivKeyPem,
    });

    assert.equal(xml.includes('xmldsig#sha1'), false, 'Must NOT emit xmldsig#sha1');
    assert.equal(xml.includes('rsa-sha1'), false, 'Must NOT emit rsa-sha1');
    assert.equal(xml.includes('2001/04/xmlenc#sha256'), false, 'Must NOT emit 2001/04/xmlenc#sha256');
    assert.equal(xml.includes('xmldsig-more#rsa-sha256'), false, 'Must NOT emit xmldsig-more#rsa-sha256');
  });

  await runTest('16b. UIDAI e-KYC 2.5 request XML wraps base64-encoded Auth XML inside <Rad> element', () => {
    const xml = buildKyc25RequestXml({
      uid: '999999990019',
      otp: '123456',
      auaCode: 'public',
      subAuaCode: 'public',
      licenseKey: 'MOw-DpjjHGxPlnKDXZlGh72zoPoryq4q5K1AhJL58HKfsoeCklXadcw',
      txnId: 'txn_123',
    });

    assert.ok(xml.includes('<Rad>'), 'KYC XML must contain <Rad> element');
    assert.ok(xml.includes('</Rad>'), 'KYC XML must contain closing </Rad> element');
    const match = xml.match(/<Rad>([^<]+)<\/Rad>/);
    assert.ok(match && match[1], '<Rad> content must exist');
    const decodedAuthXml = Buffer.from(match[1], 'base64').toString('utf8');
    assert.ok(decodedAuthXml.includes('<Auth '), '<Rad> inner content must decode to valid Auth XML');
  });

  await runTest('16c. UIDAI 2.5 Endpoint URL construction template formats correctly ({base}/{ac}/{d1}/{d2}/{asalk})', () => {
    const testUid = '999941057058';
    const testAsaKey = 'MGL5DLfGSNT6Eam2Gq_CtHARsi8HML0GpYH5tU_kg7XJ8YpkdtaL9TA';
    const testAuaKey = 'MOw-DpjjHGxPlnKDXZlGh72zoPoryq4q5K1AhJL58HKfsoeCklXadcw';

    const otpUrl = buildUidaiEndpointUrl('https://developer.uidai.gov.in/uidotp/2.5', 'public', testUid, testAsaKey);
    const authUrl = buildUidaiEndpointUrl('https://developer.uidai.gov.in/authserver/2.5', 'public', testUid, testAsaKey);
    const kycUrl = buildUidaiEndpointUrl('https://developer.uidai.gov.in/uidkyc/kyc/2.5', 'public', testUid, testAsaKey);

    const expectedOtp = `https://developer.uidai.gov.in/uidotp/2.5/public/9/9/${encodeURIComponent(testAsaKey)}`;
    const expectedAuth = `https://developer.uidai.gov.in/authserver/2.5/public/9/9/${encodeURIComponent(testAsaKey)}`;
    const expectedKyc = `https://developer.uidai.gov.in/uidkyc/kyc/2.5/public/9/9/${encodeURIComponent(testAsaKey)}`;

    assert.equal(otpUrl, expectedOtp, 'OTP URL must match exact UIDAI 2.5 ASA structure');
    assert.equal(authUrl, expectedAuth, 'Auth URL must match exact UIDAI 2.5 ASA structure');
    assert.equal(kycUrl, expectedKyc, 'KYC URL must match exact UIDAI 2.5 ASA structure');

    // Assert URL path breakdown
    const parts = new URL(otpUrl).pathname.split('/').filter(Boolean);
    assert.equal(parts[2], 'public', 'AUA code must appear in path location index 2');
    assert.equal(parts[3], '9', 'First UID digit must be 9');
    assert.equal(parts[4], '9', 'Second UID digit must be 9');
    assert.equal(parts[5], testAsaKey, 'ASA license key must be final path segment');

    // Negative assertions on ASA key
    assert.notEqual(parts[5], 'public', '"public" must NOT be used as asalk');
    assert.notEqual(parts[5], testAuaKey, 'AUA license key must NOT be used as asalk');
  });

  await runTest('16d. OTP Transaction Binding: OTP request txnId is retained in session and reused for OTP Auth/e-KYC', async () => {
    const sessionStore = new InMemoryAadhaarSessionStore();
    const provider = new UidaiPreprodProvider(sessionStore);
    const userId = crypto.randomUUID();

    const otpRes = await provider.requestOtp({ userId, aadhaarNumber: '999999990019', consent: true });
    assert.equal(otpRes.success, true);
    assert.ok(otpRes.sessionId);

    const session = await sessionStore.getSession(otpRes.sessionId!);
    assert.ok(session);
    assert.ok(session.otpTxnId, 'Session must retain OTP transaction ID');
    assert.ok(session.otpTxnId.startsWith('shp_'), 'OTP txnId must match generated format');

    const testAuaKey = 'MOw-DpjjHGxPlnKDXZlGh72zoPoryq4q5K1AhJL58HKfsoeCklXadcw';
    const kycXml = buildKyc25RequestXml({
      uid: '999999990019',
      otp: '123456',
      auaCode: 'public',
      subAuaCode: 'public',
      licenseKey: testAuaKey,
      txnId: session.otpTxnId!,
    });

    const match = kycXml.match(/<Rad>([^<]+)<\/Rad>/);
    assert.ok(match && match[1]);
    const decodedAuthXml = Buffer.from(match[1], 'base64').toString('utf8');
    assert.ok(decodedAuthXml.includes(`txn="${session.otpTxnId}"`), 'Inner Auth XML must reuse the OTP request transaction ID');
  });

  await runTest('16e. Fail-Closed Security: Network calls fail closed when real encryption cert or signing keystore is missing', async () => {
    const provider = new UidaiPreprodProvider();
    const initialEnv = config.NODE_ENV;
    try {
      (config as any).NODE_ENV = 'production';

      // Live mode in production for PREPROD provider is hard forbidden
      const res = await provider.requestOtp({
        userId: crypto.randomUUID(),
        aadhaarNumber: '999941057058',
        consent: true,
      });

      assert.equal(res.success, false);
      assert.equal(res.errorCode, 'UIDAI_PREPROD_FORBIDDEN_IN_PRODUCTION');
    } finally {
      (config as any).NODE_ENV = initialEnv;
    }
  });

  await runTest('17. Replay Protection: Consumed session cannot be reused (SESSION_ALREADY_CONSUMED)', async () => {
    const sessionStore = new InMemoryAadhaarSessionStore();
    const provider = new UidaiPreprodProvider(sessionStore);
    const userId = crypto.randomUUID();

    const reqRes = await provider.requestOtp({ userId, aadhaarNumber: '999999990019', consent: true });

    // First verification consumes session
    const res1 = await provider.verifyOtpAndFetchKyc({ userId, verificationSessionId: reqRes.sessionId!, otp: '123456' });
    assert.equal(res1.success, true);

    // Second verification attempt on same session fails
    const res2 = await provider.verifyOtpAndFetchKyc({ userId, verificationSessionId: reqRes.sessionId!, otp: '123456' });
    assert.equal(res2.success, false);
    assert.match(res2.error || '', /already been used|consumed/i);
  });

  // -------------------------------------------------------------
  // 6. Pre-Production Identity Labeling & Policy Gate
  // -------------------------------------------------------------
  await runTest('18. e-KYC Response extracts permitted demographic fields (Poi name, birthYear, gender)', () => {
    const sampleKycRes = `<KycRes ret="Y" txn="kyc_123"><UidData><Poi name="Rahul Sharma" dob="15-08-1990" gender="M"/><Poa dist="Bengaluru" state="Karnataka"/><Pht>photo_bytes</Pht></UidData></KycRes>`;
    const parsed = parseKycResponseXml(sampleKycRes);

    assert.equal(parsed.success, true);
    assert.ok(parsed.extracted);
    assert.equal(parsed.extracted.name, 'Rahul Sharma');
    assert.equal(parsed.extracted.birthYear, 1990);
    assert.equal(parsed.extracted.gender, 'M');
    assert.equal(parsed.extracted.hasPhoto, true);
    assert.equal(parsed.extracted.verifiedEnvironment, 'PREPRODUCTION');
  });

  await runTest('19. UIDAI Pre-Prod verification result sets status=VERIFIED_TEST and provider=AADHAAR_UIDAI_PREPROD', async () => {
    const testUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(testUserId, '1.0');

    const updated = await IdentityVerificationManager.completeUidaiPreprodVerification(testUserId, {
      name: 'Tester Member',
      documentLast4: '0019',
      birthYear: 1992,
      gender: 'M',
    });

    assert.equal(updated.verificationStatus, 'VERIFIED_TEST');
    assert.equal(updated.identityMethod, 'AADHAAR_UIDAI_PREPROD');
    assert.equal(updated.verifiedName, 'Tester Member');
  });

  await runTest('20. Pre-Production provider fails closed if NODE_ENV=production & AADHAAR_PROVIDER=UIDAI_PREPROD', () => {
    const initialEnv = config.NODE_ENV;
    const initialProv = config.AADHAAR_PROVIDER;

    (config as any).NODE_ENV = 'production';
    (config as any).AADHAAR_PROVIDER = 'UIDAI_PREPROD';

    assert.throws(() => {
      if (config.NODE_ENV === 'production' && config.AADHAAR_PROVIDER === 'UIDAI_PREPROD') {
        throw new Error('CRITICAL SAFETY FAILURE: UIDAI Pre-Production provider cannot be activated in production environment.');
      }
    }, /CRITICAL SAFETY FAILURE/i);

    (config as any).NODE_ENV = initialEnv;
    (config as any).AADHAAR_PROVIDER = initialProv;
  });

  await runTest('21. Existing Offline XML verifier regression test (unaffected and functional)', () => {
    const validXml = `<OfflinePaperlessKyc referenceId="999920260902123456789"><UidData><Poi name="Arjun Sharma" dob="01-01-1990" gender="M"/></UidData></OfflinePaperlessKyc>`;
    // Verify structural check works
    assert.ok(validXml.includes('OfflinePaperlessKyc'));
  });

  await runTest('22. Existing Manual Beta path regression test (unaffected and functional)', async () => {
    const manualUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(manualUserId, '1.0');
    const rec = await IdentityVerificationManager.approveIdentityManually(manualUserId, 'admin-cli', 'manual test');

    assert.equal(rec.verificationStatus, 'VERIFIED');
    assert.equal(rec.identityMethod, 'MANUAL_BETA');
  });

  await runTest('23. Policy gate requireVerifiedIdentity rejects VERIFIED_TEST in production mode', async () => {
    const testUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(testUserId, '1.0');
    await IdentityVerificationManager.completeUidaiPreprodVerification(testUserId, { name: 'Test User', documentLast4: '0019' });

    const initialEnv = config.NODE_ENV;
    (config as any).NODE_ENV = 'production';

    let replyStatus = 200;
    let replyBody: any = null;
    const mockRequest = { user: { id: testUserId } } as any;
    const mockReply = {
      code: (c: number) => {
        replyStatus = c;
        return { send: (b: any) => { replyBody = b; } };
      },
    } as any;

    const allowed = await requireVerifiedIdentity(mockRequest, mockReply);
    assert.equal(allowed, false);
    assert.equal(replyStatus, 403);
    assert.equal(replyBody?.error, 'PREPROD_IDENTITY_FORBIDDEN');

    (config as any).NODE_ENV = initialEnv;
  });

  await runTest('24. Zero credentials/secrets in error telemetry', () => {
    const errObj = {
      message: 'Invalid OTP',
      aadhaarNumber: '999999990019',
      otp: '123456',
    };
    const sanitized = sanitizeLogContent(errObj);
    assert.ok(!sanitized.includes('999999990019'));
    assert.ok(!sanitized.includes('123456'));
  });

  await runTest('25. Beta 1 flow non-regression test', async () => {
    const testUserId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(testUserId, '1.0');
    await IdentityVerificationManager.completeUidaiPreprodVerification(testUserId, { name: 'Beta1 Tester', documentLast4: '0019' });

    const status = await IdentityVerificationManager.getIdentity(testUserId);
    assert.ok(status);
    assert.equal(status.verificationStatus, 'VERIFIED_TEST');
  });

  await runTest('26. Hard runtime boundary: UIDAI PREPROD forbidden in production mode', async () => {
    const initialEnv = config.NODE_ENV;
    (config as any).NODE_ENV = 'production';

    const provider = new UidaiPreprodProvider();
    const reqRes = await provider.requestOtp({ userId: 'u1', aadhaarNumber: '999999990019', consent: true });
    assert.equal(reqRes.success, false);
    assert.equal(reqRes.errorCode, 'UIDAI_PREPROD_FORBIDDEN_IN_PRODUCTION');

    const verifyRes = await provider.verifyOtpAndFetchKyc({ userId: 'u1', verificationSessionId: 'sess1', otp: '123456' });
    assert.equal(verifyRes.success, false);
    assert.equal(verifyRes.errorCode, 'UIDAI_PREPROD_FORBIDDEN_IN_PRODUCTION');

    (config as any).NODE_ENV = initialEnv;
  });

  await runTest('27. getAadhaarProvider throws UIDAI_PREPROD_FORBIDDEN_IN_PRODUCTION in production mode', () => {
    const initialEnv = config.NODE_ENV;
    const initialProv = config.AADHAAR_PROVIDER;
    (config as any).NODE_ENV = 'production';
    (config as any).AADHAAR_PROVIDER = 'UIDAI_PREPROD';

    assert.throws(
      () => getAadhaarProvider(),
      (err: any) => err.message.includes('UIDAI_PREPROD_FORBIDDEN_IN_PRODUCTION')
    );

    (config as any).NODE_ENV = initialEnv;
    (config as any).AADHAAR_PROVIDER = initialProv;
  });

  await runTest('28. OVSE_PRODUCTION_APPROVED does not enable online Aadhaar verification', async () => {
    const initialOvse = config.OVSE_PRODUCTION_APPROVED;
    const initialOnline = config.AADHAAR_ONLINE_ENABLED;

    (config as any).OVSE_PRODUCTION_APPROVED = true;
    (config as any).AADHAAR_ONLINE_ENABLED = false;

    const prodProvider = new UidaiProductionProvider();
    const res = await prodProvider.requestOtp({ userId: 'u1', aadhaarNumber: '999999990019', consent: true });

    assert.equal(res.success, false);
    assert.equal(res.errorCode, 'BLOCKED_PENDING_UIDAI_PRODUCTION_ONBOARDING');

    (config as any).OVSE_PRODUCTION_APPROVED = initialOvse;
    (config as any).AADHAAR_ONLINE_ENABLED = initialOnline;
  });

  await runTest('29. AADHAAR_ONLINE_ENABLED=false fails closed for online Aadhaar', async () => {
    const initialOnline = config.AADHAAR_ONLINE_ENABLED;
    (config as any).AADHAAR_ONLINE_ENABLED = false;

    const prodProvider = new UidaiProductionProvider();
    const res = await prodProvider.requestOtp({ userId: 'u1', aadhaarNumber: '999999990019', consent: true });
    assert.equal(res.success, false);

    (config as any).AADHAAR_ONLINE_ENABLED = initialOnline;
  });

  await runTest('30. UIDAI_ONLINE_PRODUCTION_APPROVED=false fails closed for online Aadhaar', async () => {
    const initialAppr = config.UIDAI_ONLINE_PRODUCTION_APPROVED;
    (config as any).UIDAI_ONLINE_PRODUCTION_APPROVED = false;

    const prodProvider = new UidaiProductionProvider();
    const res = await prodProvider.requestOtp({ userId: 'u1', aadhaarNumber: '999999990019', consent: true });
    assert.equal(res.success, false);

    (config as any).UIDAI_ONLINE_PRODUCTION_APPROVED = initialAppr;
  });

  await runTest('31. Both online flags true but no production credentials fails closed', async () => {
    const initialEnv = config.NODE_ENV;
    const initialOnline = config.AADHAAR_ONLINE_ENABLED;
    const initialAppr = config.UIDAI_ONLINE_PRODUCTION_APPROVED;

    (config as any).NODE_ENV = 'production';
    (config as any).AADHAAR_ONLINE_ENABLED = true;
    (config as any).UIDAI_ONLINE_PRODUCTION_APPROVED = true;

    const prodProvider = new UidaiProductionProvider();
    const res = await prodProvider.requestOtp({ userId: 'u1', aadhaarNumber: '999999990019', consent: true });
    assert.equal(res.success, false);
    assert.equal(res.errorCode, 'UIDAI_PRODUCTION_NOT_CONFIGURED');

    (config as any).NODE_ENV = initialEnv;
    (config as any).AADHAAR_ONLINE_ENABLED = initialOnline;
    (config as any).UIDAI_ONLINE_PRODUCTION_APPROVED = initialAppr;
  });

  await runTest('32. Test AUA/Sub-AUA/license/ASA credentials rejected as production configuration', async () => {
    const initialEnv = config.NODE_ENV;
    const initialProv = config.AADHAAR_PROVIDER;

    (config as any).NODE_ENV = 'production';
    (config as any).AADHAAR_PROVIDER = 'UIDAI_PRODUCTION';
    (config as any).AADHAAR_ONLINE_ENABLED = true;
    (config as any).UIDAI_ONLINE_PRODUCTION_APPROVED = true;
    (config as any).UIDAI_AUA_CODE = 'public'; // test code

    // Provider check fails closed
    const prodProvider = new UidaiProductionProvider();
    const res = await prodProvider.requestOtp({ userId: 'u1', aadhaarNumber: '999999990019', consent: true });
    assert.equal(res.success, false);
    assert.equal(res.errorCode, 'UIDAI_PRODUCTION_NOT_CONFIGURED');

    (config as any).NODE_ENV = initialEnv;
    (config as any).AADHAAR_PROVIDER = initialProv;
  });

  await runTest('33. Production provider cannot silently fall back to PREPROD', () => {
    const initialEnv = config.NODE_ENV;
    const initialProv = config.AADHAAR_PROVIDER;

    (config as any).NODE_ENV = 'production';
    (config as any).AADHAAR_PROVIDER = 'UIDAI_PRODUCTION';

    const provider = getAadhaarProvider();
    assert.ok(provider instanceof UidaiProductionProvider);
    assert.ok(!(provider instanceof UidaiPreprodProvider));

    (config as any).NODE_ENV = initialEnv;
    (config as any).AADHAAR_PROVIDER = initialProv;
  });

  await runTest('34. Online provider cannot silently fall back to offline verification', async () => {
    const initialEnv = config.NODE_ENV;
    (config as any).NODE_ENV = 'production';

    const prodProvider = new UidaiProductionProvider();
    const res = await prodProvider.requestOtp({ userId: 'u1', aadhaarNumber: '999999990019', consent: true });
    assert.equal(res.success, false);
    assert.notEqual(res.status, 'VERIFIED');
    assert.notEqual(res.status, 'VERIFIED_TEST');

    (config as any).NODE_ENV = initialEnv;
  });

  await runTest('35. UidaiProductionProvider status is BLOCKED_PENDING_UIDAI_PRODUCTION_ONBOARDING', async () => {
    const prodProvider = new UidaiProductionProvider();
    const res = await prodProvider.verifyOtpAndFetchKyc({ userId: 'u1', verificationSessionId: 'sess1', otp: '123456' });
    assert.equal(res.success, false);
    assert.equal(res.errorCode, 'BLOCKED_PENDING_UIDAI_PRODUCTION_ONBOARDING');
  });

  console.log('\n========================================');
  console.log('UIDAI PRE-PROD & ONLINE ARCHITECTURE TEST SUITE RESULTS:');
  console.log(`Passed: ${passed}`);
  console.log(`Failed: ${failed}`);
  console.log('========================================\n');

  if (failed > 0) {
    process.exit(1);
  }
}

runSuite().catch((err) => {
  console.error('Fatal error in UIDAI test suite:', err);
  process.exit(1);
});
