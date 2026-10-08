export type AadhaarProviderType = 'DISABLED' | 'OFFLINE_XML' | 'OVSE_APP' | 'UIDAI_PREPROD' | 'UIDAI_PRODUCTION';

export interface KycVerifyResult {
  success: boolean;
  status: 'VERIFIED_TEST' | 'VERIFIED' | 'REJECTED' | 'EXPIRED';
  verificationProvider: 'AADHAAR_UIDAI_PREPROD' | 'AADHAAR_UIDAI_PRODUCTION';
  verificationEnvironment: 'PREPRODUCTION' | 'PRODUCTION';
  extracted?: ExtractedKycData | undefined;
  error?: string | undefined;
  errorCode?: string | undefined;
}

export interface AadhaarSession {
  sessionId: string;
  userId: string;
  maskedAadhaar: string;
  // Transaction ID generated during OTP request, bound to session and reused during e-KYC verification
  otpTxnId?: string | undefined;
  // Transient encrypted full UID stored ONLY in memory during verification session
  transientUidEncrypted?: string | undefined;
  createdAt: Date;
  expiresAt: Date;
  lastOtpSentAt: Date;
  resendAttempts: number;
  verifyAttempts: number;
  status: 'PENDING_OTP' | 'VERIFIED_TEST' | 'EXPIRED' | 'MAX_ATTEMPTS_EXCEEDED' | 'CONSUMED';
  consumedAt?: Date | undefined;
}

export interface AadhaarSessionStore {
  createSession(params: { userId: string; maskedAadhaar: string; otpTxnId?: string | undefined; transientUidEncrypted?: string | undefined }): Promise<AadhaarSession>;
  getSession(sessionId: string): Promise<AadhaarSession | null>;
  updateSession(session: AadhaarSession): Promise<void>;
  consumeSession(sessionId: string): Promise<{ success: boolean; session?: AadhaarSession | undefined; error?: string | undefined }>;
  expireSession(sessionId: string): Promise<void>;
}

export interface OtpRequestParams {
  userId: string;
  aadhaarNumber: string;
  consent: boolean;
}

export interface OtpRequestResult {
  success: boolean;
  sessionId?: string | undefined;
  maskedAadhaar?: string | undefined;
  expiresAt?: Date | undefined;
  cooldownSeconds?: number | undefined;
  status?: string | undefined;
  error?: string | undefined;
  errorCode?: string | undefined;
}

export interface OtpVerifyParams {
  userId: string;
  verificationSessionId: string;
  otp: string;
}

export interface ExtractedKycData {
  name: string;
  birthYear?: number | undefined;
  gender?: string | undefined;
  documentLast4: string;
  signatureValid: boolean;
  hasPhoto: boolean;
  addressSummary?: string | undefined;
  verifiedEnvironment: 'PREPRODUCTION' | 'PRODUCTION';
}


export interface UidaiOtpResponseParsed {
  success: boolean;
  code?: string | undefined;
  txnId?: string | undefined;
  ts?: string | undefined;
  error?: string | undefined;
}

export interface UidaiKycResponseParsed {
  success: boolean;
  code?: string | undefined;
  txnId?: string | undefined;
  error?: string | undefined;
  extracted?: ExtractedKycData | undefined;
}

export interface AadhaarVerificationProvider {
  requestOtp(params: OtpRequestParams): Promise<OtpRequestResult>;
  verifyOtpAndFetchKyc(params: OtpVerifyParams): Promise<KycVerifyResult>;
}
