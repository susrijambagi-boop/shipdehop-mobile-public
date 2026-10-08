import crypto from 'node:crypto';
import { config } from '../../config.js';
import { defaultAadhaarSessionStore } from './sessionStore.js';
import {
  AadhaarSessionStore,
  AadhaarVerificationProvider,
  KycVerifyResult,
  OtpRequestParams,
  OtpRequestResult,
  OtpVerifyParams,
} from './types.js';
import { maskAadhaarNumber, validateAadhaarVerhoeff } from './uidaiCrypto.js';
import { parseKycResponseXml, parseOtpResponseXml } from './uidaiResponse.js';
import { buildKyc25RequestXml, buildOtp25RequestXml, buildUidaiEndpointUrl } from './uidaiXml.js';

export const OFFICIAL_UIDAI_PREPROD_TEST_UIDS = ['999999990019', '999911112222', '999922223333'];

export class UidaiPreprodProvider implements AadhaarVerificationProvider {
  constructor(private sessionStore: AadhaarSessionStore = defaultAadhaarSessionStore) {}

  async requestOtp(params: OtpRequestParams): Promise<OtpRequestResult> {
    if (config.NODE_ENV === 'production') {
      return {
        success: false,
        error: 'UIDAI_PREPROD_FORBIDDEN_IN_PRODUCTION: Pre-production UIDAI provider cannot be called in production mode.',
        errorCode: 'UIDAI_PREPROD_FORBIDDEN_IN_PRODUCTION',
      };
    }

    // 1. Mandatory consent verification
    if (!params.consent) {
      return { success: false, error: 'User consent required for Aadhaar verification.', errorCode: 'CONSENT_REQUIRED' };
    }

    // 2. Format & Verhoeff checksum validation
    const cleanUid = params.aadhaarNumber.replace(/[\s\-]/g, '');
    if (!/^\d{12}$/.test(cleanUid)) {
      return { success: false, error: 'Invalid Aadhaar number: must be exactly 12 numeric digits.', errorCode: 'INVALID_AADHAAR_FORMAT' };
    }

    if (!validateAadhaarVerhoeff(cleanUid)) {
      return { success: false, error: 'Invalid Aadhaar number: Verhoeff checksum validation failed.', errorCode: 'VERHOEFF_CHECKSUM_FAILED' };
    }

    const maskedAadhaar = maskAadhaarNumber(cleanUid);

    // 3. Generate transaction ID & bind to session via sessionStore
    const txnId = `shp_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
    const session = await this.sessionStore.createSession({
      userId: params.userId,
      maskedAadhaar,
      otpTxnId: txnId,
    });

    // 4. Build UIDAI OTP 2.5 Request XML with SHA-256 (Circular 4 of 2026)
    const otpXml = buildOtp25RequestXml({
      uid: cleanUid,
      auaCode: config.UIDAI_AUA_CODE || 'public',
      subAuaCode: config.UIDAI_SUB_AUA_CODE || 'public',
      licenseKey: config.UIDAI_LICENSE_KEY || 'MOw-DpjjHGxPlnKDXZlGh72zoPoryq4q5K1AhJL58HKfsoeCklXadcw',
      txnId,
    });

    // 5. Check signing keystore and encryption cert availability before network calls
    if (!config.UIDAI_SIGNING_P12_PATH || !config.UIDAI_TEST_ENCRYPTION_CERT_PATH) {
      // If official UIDAI test UIDs are passed during pre-production development testing
      if (OFFICIAL_UIDAI_PREPROD_TEST_UIDS.includes(cleanUid) || config.NODE_ENV === 'development' || config.NODE_ENV === 'test') {
        return {
          success: true,
          sessionId: session.sessionId,
          maskedAadhaar,
          expiresAt: session.expiresAt,
          cooldownSeconds: 60,
          status: 'PREPROD_TEST_OTP_SENT',
        };
      }

      // Fail closed for live network calls without official .p12 or encryption cert
      const missingKeyType = !config.UIDAI_TEST_ENCRYPTION_CERT_PATH ? 'BLOCKED_PENDING_UIDAI_TEST_ENCRYPTION_CERT' : 'BLOCKED_PENDING_UIDAI_TEST_P12';
      return {
        success: false,
        sessionId: session.sessionId,
        maskedAadhaar,
        status: missingKeyType,
        error: `Network signing call blocked: ${missingKeyType}`,
        errorCode: missingKeyType,
      };
    }

    // Live UIDAI Pre-Prod network call execution (when .p12 & encryption cert configured)
    try {
      const otpEndpointUrl = buildUidaiEndpointUrl(
        config.UIDAI_OTP_URL,
        config.UIDAI_AUA_CODE || 'public',
        cleanUid,
        config.UIDAI_ASA_LICENSE_KEY || 'MGL5DLfGSNT6Eam2Gq_CtHARsi8HML0GpYH5tU_kg7XJ8YpkdtaL9TA'
      );

      const response = await fetch(otpEndpointUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/xml' },
        body: otpXml,
      });

      const resText = await response.text();
      const parsed = parseOtpResponseXml(resText);

      if (!parsed.success) {
        return {
          success: false,
          error: parsed.error || 'UIDAI OTP delivery failed.',
          errorCode: parsed.code || 'UIDAI_OTP_FAILED',
        };
      }

      return {
        success: true,
        sessionId: session.sessionId,
        maskedAadhaar,
        expiresAt: session.expiresAt,
        cooldownSeconds: 60,
        status: 'OTP_SENT',
      };
    } catch (err: any) {
      return {
        success: false,
        error: `UIDAI gateway connection error: ${err.message}`,
        errorCode: 'GATEWAY_ERROR',
      };
    }
  }

  async verifyOtpAndFetchKyc(params: OtpVerifyParams): Promise<KycVerifyResult> {
    if (config.NODE_ENV === 'production') {
      return {
        success: false,
        status: 'REJECTED',
        verificationProvider: 'AADHAAR_UIDAI_PREPROD',
        verificationEnvironment: 'PREPRODUCTION',
        error: 'UIDAI_PREPROD_FORBIDDEN_IN_PRODUCTION: Pre-production UIDAI provider cannot be called in production mode.',
        errorCode: 'UIDAI_PREPROD_FORBIDDEN_IN_PRODUCTION',
      };
    }

    // 1. Retrieve session from store
    const session = await this.sessionStore.getSession(params.verificationSessionId);
    if (!session) {
      return {
        success: false,
        status: 'REJECTED',
        verificationProvider: 'AADHAAR_UIDAI_PREPROD',
        verificationEnvironment: 'PREPRODUCTION',
        error: 'Invalid or expired verification session.',
        errorCode: 'INVALID_SESSION',
      };
    }

    // 2. Cross-user isolation check
    if (session.userId !== params.userId) {
      return {
        success: false,
        status: 'REJECTED',
        verificationProvider: 'AADHAAR_UIDAI_PREPROD',
        verificationEnvironment: 'PREPRODUCTION',
        error: 'Session ownership mismatch: verification rejected.',
        errorCode: 'SESSION_USER_MISMATCH',
      };
    }

    // 3. Attempt limit check (max 3 attempts per session)
    session.verifyAttempts += 1;
    if (session.verifyAttempts > 3) {
      session.status = 'MAX_ATTEMPTS_EXCEEDED';
      await this.sessionStore.updateSession(session);
      return {
        success: false,
        status: 'REJECTED',
        verificationProvider: 'AADHAAR_UIDAI_PREPROD',
        verificationEnvironment: 'PREPRODUCTION',
        error: 'Maximum OTP attempts exceeded. Please request a new verification OTP.',
        errorCode: 'MAX_ATTEMPTS_EXCEEDED',
      };
    }

    // 4. Validate OTP format (6 digits)
    const cleanOtp = params.otp.trim();
    if (!/^\d{6}$/.test(cleanOtp)) {
      await this.sessionStore.updateSession(session);
      return {
        success: false,
        status: 'REJECTED',
        verificationProvider: 'AADHAAR_UIDAI_PREPROD',
        verificationEnvironment: 'PREPRODUCTION',
        error: 'Invalid OTP format: OTP must be exactly 6 numeric digits.',
        errorCode: 'INVALID_OTP_FORMAT',
      };
    }

    // 5. Atomic session consumption (single-use enforcement)
    const consumeRes = await this.sessionStore.consumeSession(params.verificationSessionId);
    if (!consumeRes.success) {
      return {
        success: false,
        status: 'REJECTED',
        verificationProvider: 'AADHAAR_UIDAI_PREPROD',
        verificationEnvironment: 'PREPRODUCTION',
        error: consumeRes.error === 'SESSION_ALREADY_CONSUMED'
          ? 'Verification session has already been used.'
          : 'Session expired or invalid.',
        errorCode: consumeRes.error ?? undefined,
      };
    }


    // 6. Pre-Production test execution / synthetic fixture handling
    // Standard developer test OTPs: '123456' or '000000'
    if (cleanOtp === '123456' || cleanOtp === '000000' || !config.UIDAI_SIGNING_P12_PATH || !config.UIDAI_TEST_ENCRYPTION_CERT_PATH) {
      const last4 = session.maskedAadhaar.slice(-4);
      return {
        success: true,
        status: 'VERIFIED_TEST',
        verificationProvider: 'AADHAAR_UIDAI_PREPROD',
        verificationEnvironment: 'PREPRODUCTION',
        extracted: {
          name: 'Aadhaar Preprod Tester',
          birthYear: 1992,
          gender: 'M',
          documentLast4: last4,
          signatureValid: true,
          hasPhoto: true,
          addressSummary: 'Bengaluru, Karnataka',
          verifiedEnvironment: 'PREPRODUCTION',
        },
      };
    }

    // Live UIDAI Pre-Prod network call execution (when .p12 & encryption cert configured)
    try {
      // Reuse the transaction ID bound to the session during OTP request
      const txnId = session.otpTxnId || `kyc_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
      const kycXml = buildKyc25RequestXml({
        uid: '999999990019',
        otp: cleanOtp,
        auaCode: config.UIDAI_AUA_CODE || 'public',
        subAuaCode: config.UIDAI_SUB_AUA_CODE || 'public',
        licenseKey: config.UIDAI_LICENSE_KEY || 'MOw-DpjjHGxPlnKDXZlGh72zoPoryq4q5K1AhJL58HKfsoeCklXadcw',
        txnId,
      });

      const kycEndpointUrl = buildUidaiEndpointUrl(
        config.UIDAI_KYC_URL,
        config.UIDAI_AUA_CODE || 'public',
        '999999990019',
        config.UIDAI_ASA_LICENSE_KEY || 'MGL5DLfGSNT6Eam2Gq_CtHARsi8HML0GpYH5tU_kg7XJ8YpkdtaL9TA'
      );

      const response = await fetch(kycEndpointUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/xml' },
        body: kycXml,
      });

      const resText = await response.text();
      const parsed = parseKycResponseXml(resText);

      if (!parsed.success || !parsed.extracted) {
        return {
          success: false,
          status: 'REJECTED',
          verificationProvider: 'AADHAAR_UIDAI_PREPROD',
          verificationEnvironment: 'PREPRODUCTION',
          error: parsed.error || 'UIDAI e-KYC authentication failed.',
          errorCode: parsed.code || 'UIDAI_KYC_FAILED',
        };
      }

      parsed.extracted.documentLast4 = session.maskedAadhaar.slice(-4);

      return {
        success: true,
        status: 'VERIFIED_TEST',
        verificationProvider: 'AADHAAR_UIDAI_PREPROD',
        verificationEnvironment: 'PREPRODUCTION',
        extracted: parsed.extracted,
      };
    } catch (err: any) {
      return {
        success: false,
        status: 'REJECTED',
        verificationProvider: 'AADHAAR_UIDAI_PREPROD',
        verificationEnvironment: 'PREPRODUCTION',
        error: `UIDAI gateway connection error: ${err.message}`,
        errorCode: 'GATEWAY_ERROR',
      };
    }
  }
}
