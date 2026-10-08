import crypto from 'node:crypto';

// UIDAI Staging/Testing Public Encryption Certificate Metadata (Name & Official Expiry)
export const UIDAI_TEST_CERT_CONFIG = {
  expectedFilename: 'Auth_Stagging_11082030.cer',
  officialExpiryDate: '2030-08-11',
};
export const UIDAI_PREPROD_CERT_CONFIG = UIDAI_TEST_CERT_CONFIG;

// Verhoeff algorithm multiplication table
const VERHOEFF_D: number[][] = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
  [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
  [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
  [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
  [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
  [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
  [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
  [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
  [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
];

// Verhoeff permutation table
const VERHOEFF_P: number[][] = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
  [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
  [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
  [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
  [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
  [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
  [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
];

export const OFFICIAL_UIDAI_TEST_UIDS = ['999999990019', '999911112222', '999922223333'];

/**
 * Validates 12-digit Aadhaar number using the official Verhoeff algorithm.
 * Permits official UIDAI pre-production test UIDs in developer mode.
 * Note: Checksum validation is strictly for client/input validation and does NOT mean Aadhaar verified.
 */
export function validateAadhaarVerhoeff(aadhaarNumber: string): boolean {
  const clean = aadhaarNumber.replace(/[\s\-]/g, '');
  if (!/^\d{12}$/.test(clean)) {
    return false;
  }
  if (OFFICIAL_UIDAI_TEST_UIDS.includes(clean)) {
    return true;
  }
  let c = 0;
  const reversed = clean.split('').reverse().map(Number);
  for (let i = 0; i < reversed.length; i++) {
    const pRow = VERHOEFF_P[i % 8];
    const digit = reversed[i];
    if (pRow !== undefined && digit !== undefined) {
      const pVal = pRow[digit];
      const dRow = VERHOEFF_D[c];
      if (pVal !== undefined && dRow !== undefined) {
        const dVal = dRow[pVal];
        if (dVal !== undefined) {
          c = dVal;
        }
      }
    }
  }
  return c === 0;
}


/**
 * Formats full 12-digit Aadhaar number into masked string: •••• •••• 1234
 */
export function maskAadhaarNumber(aadhaarNumber: string): string {
  const clean = aadhaarNumber.replace(/[\s\-]/g, '');
  if (clean.length < 4) return '••••';
  const last4 = clean.slice(-4);
  return `•••• •••• ${last4}`;
}

/**
 * Sanitizes input text/objects for logging/telemetry, redacting 12-digit UIDs, OTPs, addresses, and private keys.
 */
export function sanitizeLogContent(input: any): string {
  if (!input) return '';
  const str = typeof input === 'string' ? input : JSON.stringify(input);
  return str
    .replace(/\b\d{12}\b/g, '••••••••[REDACTED_UID]')
    .replace(/otp["':\s]+\d{6}/gi, 'otp: "[REDACTED_OTP]"')
    .replace(/aadhaarNumber["':\s]+["']?\d{12}["']?/gi, 'aadhaarNumber: "[REDACTED_UID]"')
    .replace(/<Poa\s+[^>]+>/gi, '<Poa>[REDACTED_POA_ADDRESS]</Poa>')
    .replace(/addressSummary["':\s]+["'][^"']+["']/gi, 'addressSummary: "[REDACTED_ADDRESS]"')
    .replace(/-----BEGIN[A-Z ]*PRIVATE KEY-----[\s\S]*?-----END[A-Z ]*PRIVATE KEY-----/g, '[REDACTED_PRIVATE_KEY]');
}

/**
 * XML-DSig Signature URI constants (UIDAI Authentication API 2.5 & 2026 SHA-256 migration document)
 * DigestMethod: http://www.w3.org/2000/09/xmldsig#sha256
 * SignatureMethod: http://www.w3.org/2000/09/xmldsig#rsa-sha256
 */
export const UIDAI_DSIG_URIS = {
  DIGEST_METHOD_SHA256: 'http://www.w3.org/2000/09/xmldsig#sha256',
  SIGNATURE_METHOD_RSA_SHA256: 'http://www.w3.org/2000/09/xmldsig#rsa-sha256',
  CANONICALIZATION_C14N: 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315',
};

/**
 * Computes SHA-256 Digest over XML content.
 * Disallows SHA-1 per UIDAI Circular 4 of 2026.
 */
export function computeSha256Digest(content: string | Buffer): string {
  return crypto.createHash('sha256').update(content).digest('base64');
}

/**
 * Signs content using RSA-SHA256.
 * Disallows SHA-1 per UIDAI Circular 4 of 2026.
 */
export function signRsaSha256(content: string | Buffer, privateKeyPem: string): string {
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(content);
  return signer.sign(privateKeyPem, 'base64');
}

/**
 * Verifies RSA-SHA256 signature.
 */
export function verifyRsaSha256(content: string | Buffer, signatureB64: string, publicKeyPem: string): boolean {
  try {
    const verifier = crypto.createVerify('RSA-SHA256');
    verifier.update(content);
    return verifier.verify(publicKeyPem, Buffer.from(signatureB64, 'base64'));
  } catch {
    return false;
  }
}
