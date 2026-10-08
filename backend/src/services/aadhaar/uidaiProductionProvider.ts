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

export const AADHAAR_UIDAI_PRODUCTION_STATUS = 'BLOCKED_PENDING_UIDAI_PRODUCTION_ONBOARDING';

export class UidaiProductionProvider implements AadhaarVerificationProvider {
  constructor(private sessionStore: AadhaarSessionStore = defaultAadhaarSessionStore) {}

  async requestOtp(params: OtpRequestParams): Promise<OtpRequestResult> {
    // 1. Mandatory consent check
    if (!params.consent) {
      return { success: false, error: 'User consent required for Aadhaar verification.', errorCode: 'CONSENT_REQUIRED' };
    }

    // 2. Production authorization gate check
    if (
      config.NODE_ENV !== 'production' ||
      !config.AADHAAR_ONLINE_ENABLED ||
      !config.UIDAI_ONLINE_PRODUCTION_APPROVED
    ) {
      return {
        success: false,
        status: 'BLOCKED_PENDING_UIDAI_PRODUCTION_ONBOARDING',
        error: 'Identity verification is temporarily unavailable. Please try again later.',
        errorCode: 'BLOCKED_PENDING_UIDAI_PRODUCTION_ONBOARDING',
      };
    }

    // 3. Fail closed if production credentials or signing materials are missing
    if (
      !config.UIDAI_SIGNING_P12_PATH ||
      !config.UIDAI_TEST_ENCRYPTION_CERT_PATH ||
      config.UIDAI_AUA_CODE === 'public' ||
      config.UIDAI_SUB_AUA_CODE === 'public'
    ) {
      return {
        success: false,
        status: 'UIDAI_PRODUCTION_NOT_CONFIGURED',
        error: 'Identity verification is temporarily unavailable. Please try again later.',
        errorCode: 'UIDAI_PRODUCTION_NOT_CONFIGURED',
      };
    }

    // Production provider implementation will execute live UIDAI requesting-entity authentication
    // once production onboarding & credentials are explicitly supplied.
    return {
      success: false,
      status: 'BLOCKED_PENDING_UIDAI_PRODUCTION_ONBOARDING',
      error: 'Identity verification is temporarily unavailable. Please try again later.',
      errorCode: 'BLOCKED_PENDING_UIDAI_PRODUCTION_ONBOARDING',
    };
  }

  async verifyOtpAndFetchKyc(params: OtpVerifyParams): Promise<KycVerifyResult> {
    if (
      config.NODE_ENV !== 'production' ||
      !config.AADHAAR_ONLINE_ENABLED ||
      !config.UIDAI_ONLINE_PRODUCTION_APPROVED
    ) {
      return {
        success: false,
        status: 'REJECTED',
        verificationProvider: 'AADHAAR_UIDAI_PRODUCTION',
        verificationEnvironment: 'PRODUCTION',
        error: 'Identity verification is temporarily unavailable. Please try again later.',
        errorCode: 'BLOCKED_PENDING_UIDAI_PRODUCTION_ONBOARDING',
      };
    }

    return {
      success: false,
      status: 'REJECTED',
      verificationProvider: 'AADHAAR_UIDAI_PRODUCTION',
      verificationEnvironment: 'PRODUCTION',
      error: 'Identity verification is temporarily unavailable. Please try again later.',
      errorCode: 'BLOCKED_PENDING_UIDAI_PRODUCTION_ONBOARDING',
    };
  }
}
