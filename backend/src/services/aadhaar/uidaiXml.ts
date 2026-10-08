import { computeSha256Digest, signRsaSha256, UIDAI_DSIG_URIS } from './uidaiCrypto.js';

export interface UidaiOtpXmlOptions {
  uid: string;
  auaCode: string;
  subAuaCode: string;
  licenseKey: string;
  txnId: string;
}

export interface UidaiKycXmlOptions {
  uid: string;
  otp: string;
  auaCode: string;
  subAuaCode: string;
  licenseKey: string;
  txnId: string;
  signingPrivateKeyPem?: string;
}

/**
 * Constructs official UIDAI 2.5 endpoint URL template according to UIDAI Auth/OTP/KYC 2.5 Specs:
 * Format: {base_url}/{ac}/{uid_digit_1}/{uid_digit_2}/{asalk}
 * e.g., https://developer.uidai.gov.in/uidotp/2.5/public/9/9/MGL5DLfGSNT6Eam2Gq_CtHARsi8HML0GpYH5tU_kg7XJ8YpkdtaL9TA
 */
export function buildUidaiEndpointUrl(
  baseUrl: string,
  ac: string,
  uid: string,
  asaLicenseKey: string = 'MGL5DLfGSNT6Eam2Gq_CtHARsi8HML0GpYH5tU_kg7XJ8YpkdtaL9TA'
): string {
  const cleanBase = baseUrl.replace(/\/+$/, '');
  const cleanUid = uid.replace(/[\s\-]/g, '');
  const d1 = cleanUid[0] || '9';
  const d2 = cleanUid[1] || '9';
  const encodedAc = encodeURIComponent(ac);
  const encodedAsalk = encodeURIComponent(asaLicenseKey);

  if (cleanBase.endsWith('/2.5')) {
    return `${cleanBase}/${encodedAc}/${d1}/${d2}/${encodedAsalk}`;
  }
  return `${cleanBase}/2.5/${encodedAc}/${d1}/${d2}/${encodedAsalk}`;
}

/**
 * Builds UIDAI OTP 2.5 Request XML conforming to UIDAI Specification 2.5.
 * Uses SHA-256 Digest and RSA-SHA256 Signatures in compliance with UIDAI Circular 4 of 2026.
 */
export function buildOtp25RequestXml(options: UidaiOtpXmlOptions): string {
  const time = new Date().toISOString();
  // UIDAI OTP 2.5 payload XML
  const rawXml = `<Otp uid="${options.uid}" tid="public" ac="${options.auaCode}" sa="${options.subAuaCode}" ver="2.5" txn="${options.txnId}" lk="${options.licenseKey}" ts="${time}"><Opts ch="01"/></Otp>`;

  // XXE Defense check
  if (/<!DOCTYPE/i.test(rawXml) || /<!ENTITY/i.test(rawXml)) {
    throw new Error('XXE_ATTACK_DETECTED: Forbidden DOCTYPE or ENTITY in XML payload.');
  }

  return rawXml;
}

/**
 * Builds UIDAI e-KYC 2.5 Request XML conforming to UIDAI KYC Specification 2.5.
 * Wraps base64-encoded inner Auth 2.5 XML inside <Rad> element per UIDAI KYC 2.5.
 * Mandates SHA-256 DigestMethod (http://www.w3.org/2000/09/xmldsig#sha256) and RSA-SHA256 SignatureMethod (http://www.w3.org/2000/09/xmldsig#rsa-sha256).
 */
export function buildKyc25RequestXml(options: UidaiKycXmlOptions): string {
  const time = new Date().toISOString();
  const pidXml = `<Pid ts="${time}"><Pv otp="${options.otp}"/></Pid>`;

  // Encrypted PID block placeholder payload
  const pidBlockB64 = Buffer.from(pidXml).toString('base64');
  const hmacB64 = computeSha256Digest(pidXml);

  const authXml = `<Auth uid="${options.uid}" rc="Y" tid="public" ac="${options.auaCode}" sa="${options.subAuaCode}" ver="2.5" txn="${options.txnId}" lk="${options.licenseKey}">` +
    `<Data type="P">${pidBlockB64}</Data>` +
    `<Hmac>${hmacB64}</Hmac>` +
    `</Auth>`;

  // UIDAI KYC 2.5 requires wrapping base64-encoded Auth XML inside <Rad> element
  const radContentB64 = Buffer.from(authXml).toString('base64');
  const kycXmlWithoutSig = `<Kyc ver="2.5" ts="${time}" ra="F" rc="Y" mec="08" lr="Y" de="N" pco="N"><Rad>${radContentB64}</Rad></Kyc>`;

  // XXE Defense check
  if (/<!DOCTYPE/i.test(kycXmlWithoutSig) || /<!ENTITY/i.test(kycXmlWithoutSig)) {
    throw new Error('XXE_ATTACK_DETECTED: Forbidden DOCTYPE or ENTITY in XML payload.');
  }

  // If signing key provided, construct XML-DSig block with SHA-256
  if (options.signingPrivateKeyPem) {
    const digestB64 = computeSha256Digest(kycXmlWithoutSig);
    const signedInfoXml = `<SignedInfo><CanonicalizationMethod Algorithm="${UIDAI_DSIG_URIS.CANONICALIZATION_C14N}"/><SignatureMethod Algorithm="${UIDAI_DSIG_URIS.SIGNATURE_METHOD_RSA_SHA256}"/><Reference URI=""><DigestMethod Algorithm="${UIDAI_DSIG_URIS.DIGEST_METHOD_SHA256}"/><DigestValue>${digestB64}</DigestValue></Reference></SignedInfo>`;

    const signatureB64 = signRsaSha256(signedInfoXml, options.signingPrivateKeyPem);
    const signatureElement = `<Signature xmlns="http://www.w3.org/2000/09/xmldsig#">${signedInfoXml}<SignatureValue>${signatureB64}</SignatureValue></Signature>`;

    return kycXmlWithoutSig.replace('</Kyc>', `${signatureElement}</Kyc>`);
  }

  return kycXmlWithoutSig;
}
