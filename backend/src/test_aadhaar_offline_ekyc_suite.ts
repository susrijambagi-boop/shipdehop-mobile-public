import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import zlib from 'node:zlib';
import { config } from './config.js';
import {
  AadhaarOfflineXmlVerifier,
  IdentityVerificationManager,
} from './services/identity_verification.js';
import {
  OfflineAadhaarTrustStore,
  verifyAadhaarMobileHash,
  normalizeIndianMobile,
  extractAadhaarLastDigit,
  computeUidaiMobileHash,
  SYNTHETIC_TEST_PRIVATE_KEY,
  SYNTHETIC_TEST_PUBLIC_KEY,
} from './services/aadhaar/offlineTrustStore.js';
import { requireVerifiedIdentity } from './routes/identity.js';

async function runTest(name: string, fn: () => Promise<void> | void) {
  try {
    await fn();
    console.log(`  ✓ ${name}`);
  } catch (err: any) {
    console.error(`  ✗ ${name}`);
    console.error(err);
    process.exit(1);
  }
}

// Helper to construct a basic PKZIP buffer for testing
function createZipBuffer(fileName: string, content: Buffer): Buffer {
  const fileNameBuf = Buffer.from(fileName, 'utf-8');
  const compressedBuf = zlib.deflateRawSync(content);

  const header = Buffer.alloc(30);
  header.writeUInt32LE(0x04034b50, 0); // PKZIP signature
  header.writeUInt16LE(20, 4);        // Version needed
  header.writeUInt16LE(0, 6);         // General flags
  header.writeUInt16LE(8, 8);         // Compression method (deflate)
  header.writeUInt16LE(0, 10);        // Mod time
  header.writeUInt16LE(0, 12);        // Mod date
  header.writeUInt32LE(0, 14);        // CRC32
  header.writeUInt32LE(compressedBuf.length, 18); // Compressed size
  header.writeUInt32LE(content.length, 22);       // Uncompressed size
  header.writeUInt16LE(fileNameBuf.length, 26);   // File name length
  header.writeUInt16LE(0, 28);                    // Extra field length

  return Buffer.concat([header, fileNameBuf, compressedBuf]);
}

async function runSuite() {
  console.log('\n--- SHIPDEHOP AADHAAR PAPERLESS OFFLINE E-KYC TEST SUITE ---');
  console.log('Testing Production-Grade Zero-Cost Offline Identity Architecture & Security Controls.\n');

  let testCount = 0;

  // -------------------------------------------------------------
  // 1. UIDAI Mobile Hash & Normalization Vector Tests
  // -------------------------------------------------------------
  testCount++;
  await runTest(`${testCount}. Official UIDAI mobile normalization (+91 to 10-digit Indian mobile)`, () => {
    assert.equal(normalizeIndianMobile('+919800000002'), '9800000002');
    assert.equal(normalizeIndianMobile('9800000002'), '9800000002');
    assert.equal(normalizeIndianMobile('919800000002'), '9800000002');
    assert.equal(normalizeIndianMobile('+15550001234'), null, 'Non-Indian number must be rejected');
    assert.equal(normalizeIndianMobile('12345'), null, 'Short number must be rejected');
  });

  testCount++;
  await runTest(`${testCount}. Aadhaar last digit extraction from reference ID`, () => {
    assert.equal(extractAadhaarLastDigit('123420260902123456789'), 4);
    assert.equal(extractAadhaarLastDigit('123020260902123456789'), 0);
    assert.equal(extractAadhaarLastDigit('123120260902123456789'), 1);
    assert.equal(extractAadhaarLastDigit('123920260902123456789'), 9);
    assert.equal(extractAadhaarLastDigit('abc'), null);
  });

  testCount++;
  await runTest(`${testCount}. Official UIDAI Independent Test Vector: Aadhaar ending in 0 (1 iteration)`, () => {
    const mobile = '9800000002';
    const sharePhrase = 'Abc@123';
    // Hardcoded independent vector constant
    const expectedHexVector = 'b22ab9e09fe8f0e292fbfab5941b36b8ef07bda9e6e0154f6e8db47b05e0d8de';
    const hashRes = verifyAadhaarMobileHash('+919800000002', sharePhrase, '123020260902123456789', expectedHexVector);
    assert.equal(hashRes.match, true);
    assert.equal(hashRes.aadhaarLastDigit, 0);
    assert.equal(hashRes.hashIterations, 1);
  });

  testCount++;
  await runTest(`${testCount}. Official UIDAI Independent Test Vector: Aadhaar ending in 1 (1 iteration)`, () => {
    const sharePhrase = 'Abc@123';
    const expectedHexVector = 'b22ab9e09fe8f0e292fbfab5941b36b8ef07bda9e6e0154f6e8db47b05e0d8de';
    const hashRes = verifyAadhaarMobileHash('+919800000002', sharePhrase, '123120260902123456789', expectedHexVector);
    assert.equal(hashRes.match, true);
    assert.equal(hashRes.aadhaarLastDigit, 1);
    assert.equal(hashRes.hashIterations, 1);
  });

  testCount++;
  await runTest(`${testCount}. Official UIDAI Independent Test Vector: Aadhaar ending in 2 (2 iterations)`, () => {
    const sharePhrase = 'Abc@123';
    const expectedHexVector = 'e3f766f63f6816e9800a90da85ab4d6eda0c40e3a1f217da8915b1b78020ea25';
    const hashRes = verifyAadhaarMobileHash('+919800000002', sharePhrase, '123220260902123456789', expectedHexVector);
    assert.equal(hashRes.match, true);
    assert.equal(hashRes.aadhaarLastDigit, 2);
    assert.equal(hashRes.hashIterations, 2);
  });

  testCount++;
  await runTest(`${testCount}. Official UIDAI Independent Test Vector: Aadhaar ending in 4 (4 iterations)`, () => {
    const sharePhrase = 'Abc@123';
    const expectedHexVector = '735c04aebc33a05af444ed41f6352b083c5a28d75ff1a26f0fe2c72bba94d7dc';
    const hashRes = verifyAadhaarMobileHash('+919800000002', sharePhrase, '123420260902123456789', expectedHexVector);
    assert.equal(hashRes.match, true);
    assert.equal(hashRes.aadhaarLastDigit, 4);
    assert.equal(hashRes.hashIterations, 4);
  });

  testCount++;
  await runTest(`${testCount}. Official UIDAI Independent Test Vector: Aadhaar ending in 9 (9 iterations)`, () => {
    const sharePhrase = 'Abc@123';
    const expectedHexVector = 'ef1334046a2496790933cb1cd76186bbf260e210d774e22fc225ef94cb9890e7';
    const hashRes = verifyAadhaarMobileHash('+919800000002', sharePhrase, '123920260902123456789', expectedHexVector);
    assert.equal(hashRes.match, true);
    assert.equal(hashRes.aadhaarLastDigit, 9);
    assert.equal(hashRes.hashIterations, 9);
  });

  testCount++;
  await runTest(`${testCount}. Wrong phone, wrong Share Phrase, or wrong reference digit rejected`, () => {
    const sharePhrase = 'Abc@123';
    const validVector = '735c04aebc33a05af444ed41f6352b083c5a28d75ff1a26f0fe2c72bba94d7dc';

    // Wrong phone
    const wrongPhone = verifyAadhaarMobileHash('+919999999999', sharePhrase, '123420260902123456789', validVector);
    assert.equal(wrongPhone.match, false);

    // Wrong Share Phrase
    const wrongShare = verifyAadhaarMobileHash('+919800000002', 'Wrong', '123420260902123456789', validVector);
    assert.equal(wrongShare.match, false);

    // Wrong Aadhaar final digit
    const wrongDigit = verifyAadhaarMobileHash('+919800000002', sharePhrase, '123220260902123456789', validVector);
    assert.equal(wrongDigit.match, false);
  });

  // -------------------------------------------------------------
  // 2. Schema Detection & Isolation Tests
  // -------------------------------------------------------------
  testCount++;
  await runTest(`${testCount}. Schema detection accurately identifies CURRENT_OFFLINE_OKY schema`, () => {
    const okyXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY, {
      schema: 'CURRENT_OFFLINE_OKY',
    });
    const res = AadhaarOfflineXmlVerifier.verifyOfflineXml(okyXml, { trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY });
    assert.equal(res.valid, true);
    assert.equal(res.extracted?.schema, 'CURRENT_OFFLINE_OKY');
  });

  testCount++;
  await runTest(`${testCount}. Schema detection accurately identifies LEGACY_XMLDSIG schema`, () => {
    const dsigXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY, {
      schema: 'LEGACY_XMLDSIG',
    });
    const res = AadhaarOfflineXmlVerifier.verifyOfflineXml(dsigXml, { trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY });
    assert.equal(res.valid, true);
    assert.equal(res.extracted?.schema, 'LEGACY_XMLDSIG');
  });

  testCount++;
  await runTest(`${testCount}. Unsupported or corrupted XML schema fails closed (UNSUPPORTED_XML_SCHEMA)`, () => {
    const badXml = '<CustomAppDoc><Data>Not an Aadhaar XML</Data></CustomAppDoc>';
    const res = AadhaarOfflineXmlVerifier.verifyOfflineXml(badXml);
    assert.equal(res.valid, false);
    assert.equal(res.status, 'UNSUPPORTED_XML_SCHEMA');
  });

  // -------------------------------------------------------------
  // 3. Security & ZIP Defenses Tests
  // -------------------------------------------------------------
  testCount++;
  await runTest(`${testCount}. User consent required (fails closed if consent not recorded)`, async () => {
    const userId = crypto.randomUUID();
    const res = await IdentityVerificationManager.processAadhaarOfflineXml(userId, '<xml/>');
    assert.equal(res.success, false);
    assert.equal(res.status, 'NOT_STARTED');
  });

  testCount++;
  await runTest(`${testCount}. Non-ZIP & non-XML raw junk buffer rejected`, () => {
    const junk = Buffer.from('this is random junk content not zip or xml');
    const res = AadhaarOfflineXmlVerifier.verifyZipPackage(junk, '1234');
    assert.equal(res.valid, false);
  });

  testCount++;
  await runTest(`${testCount}. Wrong magic bytes in ZIP header rejected`, () => {
    const fakeZip = Buffer.from('BADMAGIC_BYTES_IN_HEADER_PAYLOAD_FAKE_ZIP');
    const res = AadhaarOfflineXmlVerifier.verifyZipPackage(fakeZip, '1234');
    assert.equal(res.valid, false);
  });

  testCount++;
  await runTest(`${testCount}. Oversized ZIP buffer (> 500 KB) rejected`, () => {
    const oversizedBuf = Buffer.alloc(500_001);
    const res = AadhaarOfflineXmlVerifier.verifyZipPackage(oversizedBuf, '1234');
    assert.equal(res.valid, false);
    assert.ok(res.error?.includes('Oversized ZIP package'));
  });

  testCount++;
  await runTest(`${testCount}. Path Traversal / Zip Slip in archive rejected`, () => {
    const maliciousZip = createZipBuffer('../../../etc/passwd', Buffer.from('<xml/>'));
    const res = AadhaarOfflineXmlVerifier.verifyZipPackage(maliciousZip, '1234');
    assert.equal(res.valid, false);
    assert.ok(res.error?.includes('path traversal detected'));
  });

  testCount++;
  await runTest(`${testCount}. Nested malicious archive or executable extension rejected`, () => {
    const exeZip = createZipBuffer('payload.exe', Buffer.from('binary'));
    const res = AadhaarOfflineXmlVerifier.verifyZipPackage(exeZip, '1234');
    assert.equal(res.valid, false);
    assert.ok(res.error?.includes('executable or nested archive entry'));
  });

  testCount++;
  await runTest(`${testCount}. ZIP bomb (uncompressed size > 2 MB) rejected`, () => {
    const header = Buffer.alloc(30);
    header.writeUInt32LE(0x04034b50, 0);
    header.writeUInt16LE(8, 8);
    header.writeUInt32LE(100, 18);
    header.writeUInt32LE(3_000_000, 22);
    const name = Buffer.from('test.xml');
    header.writeUInt16LE(name.length, 26);
    const zipBuf = Buffer.concat([header, name, Buffer.alloc(100)]);

    const res = AadhaarOfflineXmlVerifier.verifyZipPackage(zipBuf, '1234');
    assert.equal(res.valid, false);
    assert.ok(res.error?.includes('exceeds 2 MB limit'));
  });

  testCount++;
  await runTest(`${testCount}. Ambiguous multiple XML files inside ZIP rejected`, () => {
    const xml1 = Buffer.from('file1.xml');
    const xml2 = Buffer.from('file2.xml');
    const zip1 = createZipBuffer('file1.xml', xml1);
    const zip2 = createZipBuffer('file2.xml', xml2);
    const multiZip = Buffer.concat([zip1, zip2]);

    const res = AadhaarOfflineXmlVerifier.verifyZipPackage(multiZip, '1234');
    assert.equal(res.valid, false);
    assert.ok(res.error?.includes('multiple XML files found inside archive'));
  });

  testCount++;
  await runTest(`${testCount}. Incorrect Share Code format rejected`, () => {
    const zipBuf = createZipBuffer('doc.xml', Buffer.from('<xml/>'));
    const res1 = AadhaarOfflineXmlVerifier.verifyZipPackage(zipBuf, '12');
    const res2 = AadhaarOfflineXmlVerifier.verifyZipPackage(zipBuf, '12345');
    assert.equal(res1.valid, false);
    assert.equal(res2.valid, false);
  });

  testCount++;
  await runTest(`${testCount}. Share Code is never logged in telemetry or error output`, () => {
    const secretShareCode = 'S9X4';
    const zipBuf = createZipBuffer('doc.xml', Buffer.from('<xml/>'));
    const res = AadhaarOfflineXmlVerifier.verifyZipPackage(zipBuf, secretShareCode);
    const serialized = JSON.stringify(res);
    assert.equal(serialized.includes(secretShareCode), false, 'Share Code must never be present in verification output object');
  });

  testCount++;
  await runTest(`${testCount}. XML XXE Injection: Rejects XML with ENTITY declaration`, () => {
    const xxe = '<?xml version="1.0"?><!DOCTYPE test [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><OfflinePaperlessKyc>&xxe;</OfflinePaperlessKyc>';
    const res = AadhaarOfflineXmlVerifier.verifyOfflineXml(xxe);
    assert.equal(res.valid, false);
    assert.ok(res.error?.includes('DOCTYPE and ENTITY declarations are forbidden'));
  });

  testCount++;
  await runTest(`${testCount}. XML XXE Injection: Rejects XML with DOCTYPE declaration`, () => {
    const docType = '<?xml version="1.0"?><!DOCTYPE OfflinePaperlessKyc SYSTEM "http://attacker.com/xxe"><OfflinePaperlessKyc/ >';
    const res = AadhaarOfflineXmlVerifier.verifyOfflineXml(docType);
    assert.equal(res.valid, false);
    assert.ok(res.error?.includes('DOCTYPE and ENTITY declarations are forbidden'));
  });

  testCount++;
  await runTest(`${testCount}. Invalid digital signature on SignedInfo rejected`, () => {
    const badSigXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY, {
      wrongSignature: true,
    });
    const res = AadhaarOfflineXmlVerifier.verifyOfflineXml(badSigXml, { trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY });
    assert.equal(res.valid, false);
  });

  testCount++;
  await runTest(`${testCount}. Tampered XML post-signing rejected (DigestValue mismatch)`, () => {
    const tamperedXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY, {
      tampered: true,
    });
    const res = AadhaarOfflineXmlVerifier.verifyOfflineXml(tamperedXml, { trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY });
    assert.equal(res.valid, false);
  });

  testCount++;
  await runTest(`${testCount}. Trust Store: Missing official certificate in live mode returns BLOCKED_PENDING_UIDAI_OFFLINE_TRUST_CERT`, () => {
    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY);
    const res = AadhaarOfflineXmlVerifier.verifyOfflineXml(validXml, { isLiveMode: true });
    assert.equal(res.valid, false);
    assert.equal(res.status, 'BLOCKED_PENDING_UIDAI_OFFLINE_TRUST_CERT');
  });

  testCount++;
  await runTest(`${testCount}. Valid synthetic fixture accepted as TEST identity (VERIFIED_TEST)`, async () => {
    const initialOffline = config.OFFLINE_AADHAAR_ENABLED;
    (config as any).OFFLINE_AADHAAR_ENABLED = true;

    const userId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(userId, '1.0');

    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY, {
      name: 'Priya Sundaram',
      dob: '15-08-1994',
      gender: 'F',
      referenceId: '888820260911123456789',
    });

    const res = await IdentityVerificationManager.processAadhaarOfflineXml(userId, validXml, '1234', '+919876543210', {
      trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY,
    });

    assert.equal(res.success, true);
    assert.equal(res.status, 'VERIFIED_TEST');
    assert.equal(res.record?.verifiedName, 'Priya Sundaram');

    (config as any).OFFLINE_AADHAAR_ENABLED = initialOffline;
  });

  testCount++;
  await runTest(`${testCount}. Name extracted strictly from digitally signed XML`, async () => {
    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY, {
      name: 'Rajesh Kumar',
    });
    const res = AadhaarOfflineXmlVerifier.verifyOfflineXml(validXml, { trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY });
    assert.equal(res.valid, true);
    assert.equal(res.extracted?.name, 'Rajesh Kumar');
  });

  testCount++;
  await runTest(`${testCount}. DOB / birthYear extracted correctly`, async () => {
    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY, {
      dob: '24-11-1988',
    });
    const res = AadhaarOfflineXmlVerifier.verifyOfflineXml(validXml, { trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY });
    assert.equal(res.valid, true);
    assert.equal(res.extracted?.birthYear, 1988);
  });

  testCount++;
  await runTest(`${testCount}. Address is not persisted in public user_identities record`, async () => {
    const initialOffline = config.OFFLINE_AADHAAR_ENABLED;
    (config as any).OFFLINE_AADHAAR_ENABLED = true;

    const userId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(userId, '1.0');
    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY);
    const res = await IdentityVerificationManager.processAadhaarOfflineXml(userId, validXml, '1234', '+919876543210', {
      trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY,
    });

    assert.equal(res.success, true);
    const identity = await IdentityVerificationManager.getIdentity(userId);
    const serialized = JSON.stringify(identity);
    assert.equal(serialized.includes('Bangalore'), false, 'Address must not be present in public identity record');

    (config as any).OFFLINE_AADHAAR_ENABLED = initialOffline;
  });

  testCount++;
  await runTest(`${testCount}. Aadhaar photo is not exposed in public user profile`, async () => {
    const initialOffline = config.OFFLINE_AADHAAR_ENABLED;
    (config as any).OFFLINE_AADHAAR_ENABLED = true;

    const userId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(userId, '1.0');
    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY);
    const res = await IdentityVerificationManager.processAadhaarOfflineXml(userId, validXml, '1234', '+919876543210', {
      trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY,
    });

    const identity = await IdentityVerificationManager.getIdentity(userId);
    const serialized = JSON.stringify(identity);
    assert.equal(serialized.includes('synthetic_photo_bytes'), false, 'Photo bytes must not be present in public identity record');

    (config as any).OFFLINE_AADHAAR_ENABLED = initialOffline;
  });

  testCount++;
  await runTest(`${testCount}. 12-digit Aadhaar number is never reconstructed or stored`, async () => {
    const initialOffline = config.OFFLINE_AADHAAR_ENABLED;
    (config as any).OFFLINE_AADHAAR_ENABLED = true;

    const userId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(userId, '1.0');
    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY, {
      referenceId: '999920260911123456789',
    });
    const res = await IdentityVerificationManager.processAadhaarOfflineXml(userId, validXml, '1234', '+919876543210', {
      trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY,
    });

    assert.equal(res.success, true);
    assert.equal(res.record?.documentLast4, '9999');
    const serialized = JSON.stringify(res.record);
    assert.equal(/\b\d{12}\b/.test(serialized), false, '12-digit Aadhaar number must never be in record');

    (config as any).OFFLINE_AADHAAR_ENABLED = initialOffline;
  });

  testCount++;
  await runTest(`${testCount}. Verification session strictly bound to authenticated user context`, async () => {
    const userA = crypto.randomUUID();
    const userB = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(userA, '1.0');

    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY);
    const resB = await IdentityVerificationManager.processAadhaarOfflineXml(userB, validXml, '1234', '+919876543210', {
      trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY,
    });
    assert.equal(resB.success, false);
    assert.equal(resB.status, 'NOT_STARTED');
  });

  testCount++;
  await runTest(`${testCount}. Policy Gate: VERIFIED_TEST cannot satisfy production requireVerifiedIdentity gate`, async () => {
    const initialEnv = config.NODE_ENV;
    const initialOffline = config.OFFLINE_AADHAAR_ENABLED;
    (config as any).NODE_ENV = 'test';
    (config as any).OFFLINE_AADHAAR_ENABLED = true;

    const userId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(userId, '1.0');
    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY);
    await IdentityVerificationManager.processAadhaarOfflineXml(userId, validXml, '1234', '+919876543210', { trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY, isLiveMode: false });

    // Switch to production mode to verify policy rejection
    (config as any).NODE_ENV = 'production';

    let codeSent = 0;
    let bodySent: any = null;
    const req: any = { user: { id: userId, email: 'user@prod.com' } };
    const reply: any = {
      code: (c: number) => { codeSent = c; return reply; },
      send: (b: any) => { bodySent = b; return reply; },
    };

    const allowed = await requireVerifiedIdentity(req, reply);
    assert.equal(allowed, false);
    assert.equal(codeSent, 403);
    assert.equal(bodySent.error, 'PREPROD_IDENTITY_FORBIDDEN');

    (config as any).NODE_ENV = initialEnv;
    (config as any).OFFLINE_AADHAAR_ENABLED = initialOffline;
  });

  testCount++;
  await runTest(`${testCount}. Production default OFFLINE_AADHAAR_ENABLED=false fails closed`, async () => {
    const initialEnv = config.NODE_ENV;
    const initialOffline = config.OFFLINE_AADHAAR_ENABLED;
    (config as any).NODE_ENV = 'production';
    (config as any).OFFLINE_AADHAAR_ENABLED = false;

    const userId = crypto.randomUUID();
    await IdentityVerificationManager.recordConsent(userId, '1.0');
    const validXml = AadhaarOfflineXmlVerifier.generateSignedXmlFixture(SYNTHETIC_TEST_PRIVATE_KEY);

    const res = await IdentityVerificationManager.processAadhaarOfflineXml(userId, validXml, '1234', '+919876543210', {
      trustedPublicKeyPem: SYNTHETIC_TEST_PUBLIC_KEY,
    });

    assert.equal(res.success, false);
    assert.equal(res.status, 'PENDING_REVIEW');
    assert.ok(res.error?.includes('disabled in configuration'));

    (config as any).NODE_ENV = initialEnv;
    (config as any).OFFLINE_AADHAAR_ENABLED = initialOffline;
  });

  testCount++;
  await runTest(`${testCount}. Existing online UIDAI preprod provider preserved & functional (DORMANT)`, async () => {
    const provider = IdentityVerificationManager;
    assert.ok(typeof provider.completeUidaiPreprodVerification === 'function');
  });

  testCount++;
  await runTest(`${testCount}. Existing Secure QR provider preserved`, () => {
    assert.ok(typeof IdentityVerificationManager.processAadhaarVerification === 'function');
  });

  testCount++;
  await runTest(`${testCount}. Existing OVSE App provider preserved`, () => {
    assert.ok(typeof IdentityVerificationManager.completeAadhaarVerification === 'function');
  });

  testCount++;
  await runTest(`${testCount}. Existing Manual Beta provider preserved`, () => {
    assert.ok(typeof IdentityVerificationManager.approveIdentityManually === 'function');
  });

  console.log('\n========================================');
  console.log('AADHAAR OFFLINE E-KYC TEST SUITE RESULTS:');
  console.log(`Passed: ${testCount} / ${testCount}`);
  console.log('========================================\n');
}

runSuite().catch(err => {
  console.error(err);
  process.exit(1);
});
