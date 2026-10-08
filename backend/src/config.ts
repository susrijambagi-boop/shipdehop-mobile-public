import 'dotenv/config';
import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(8080),
  SUPABASE_URL: z.string().url(),
  SUPABASE_PUBLISHABLE_KEY: z.string().min(10),
  SUPABASE_SECRET_KEY: z.string().min(10),
  GEMINI_API_KEY: z.string().min(1),
  GEOAPIFY_API_KEY: z.string().optional(),
  GOOGLE_ROUTES_API_KEY: z.string().optional(),
  GOOGLE_GEOCODING_API_KEY: z.string().optional(),
  GEMINI_SCAM_MODEL: z.string().default('gemini-3.7-flash'),
  PARCEL_INSPECTION_PROVIDER: z.enum(['OLLAMA', 'GEMINI']).optional(),
  GEMINI_VISION_MODEL: z.string().default('gemini-3.6-flash'),
  OLLAMA_URL: z.string().default('http://127.0.0.1:11434/api/chat'),
  OLLAMA_VISION_MODEL: z.string().default('qwen2.5vl:3b'),
  ALLOWED_ORIGINS: z.string().optional().transform((v) =>
    v ? v.split(',').map((s) => s.trim()).filter(Boolean) : [],
  ),
  PAYMENT_PROVIDER: z.enum(['STRIPE', 'RAZORPAY', 'DISABLED', 'MOCK']).default('DISABLED'),
  STRIPE_SECRET_KEY: z.string().optional(),
  STRIPE_WEBHOOK_SECRET: z.string().optional(),
  RAZORPAY_KEY_ID: z.string().optional(),
  RAZORPAY_KEY_SECRET: z.string().optional(),
  PLATFORM_FEE_BPS_RIDE: z.coerce.number().int().min(0).max(3000).default(800),
  PLATFORM_FEE_BPS_MARKETPLACE: z.coerce.number().int().min(0).max(3000).default(600),
  PLATFORM_FEE_BPS_SHIPMENT: z.coerce.number().int().min(0).max(3000).default(1000),
  DEV_TEST_AUTH: z.string().optional().transform(v => v === 'true'),
  STARTUP_DEPENDENCY_PROBE: z.string().optional().transform(v => v === 'true').default(false),
  PHONE_VERIFICATION_PROVIDER: z.enum(['WHATSAPP_OUTBOUND', 'WHATSAPP_INBOUND', 'DEVELOPMENT', 'MANUAL_BETA']).optional(),
  PHONE_VERIFICATION_ENABLED: z.string().optional().transform(v => v === 'true').default(false),
  WHATSAPP_BOT_NUMBER: z.string().optional(),
  WHATSAPP_WEBHOOK_VERIFY_TOKEN: z.string().default('shipdehop_wa_verify_token'),
  AADHAAR_VERIFICATION_ENABLED: z.string().optional().transform(v => v === 'true').default(false),
  AADHAAR_ONLINE_ENABLED: z.string().optional().transform(v => v === 'true').default(false),
  UIDAI_ONLINE_PRODUCTION_APPROVED: z.string().optional().transform(v => v === 'true').default(false),
  OFFLINE_AADHAAR_ENABLED: z.string().optional().transform(v => v === 'true').default(false),
  OVSE_PRODUCTION_APPROVED: z.string().optional().transform(v => v === 'true').default(false),
  UIDAI_OFFLINE_CERT_PATH: z.string().optional(),
  BETA1_REQUIRE_AADHAAR: z.string().optional().transform(v => v === 'true').default(false),
  AADHAAR_PROVIDER: z.enum(['DISABLED', 'OFFLINE_XML', 'OVSE_APP', 'UIDAI_PREPROD', 'UIDAI_PRODUCTION']).default('DISABLED'),
  UIDAI_ENVIRONMENT: z.enum(['PREPRODUCTION', 'PRODUCTION']).default('PREPRODUCTION'),
  UIDAI_AUA_CODE: z.string().default('public'),
  UIDAI_SUB_AUA_CODE: z.string().default('public'),
  UIDAI_LICENSE_KEY: z.string().optional().default('MOw-DpjjHGxPlnKDXZlGh72zoPoryq4q5K1AhJL58HKfsoeCklXadcw'),
  UIDAI_ASA_LICENSE_KEY: z.string().optional().default('MGL5DLfGSNT6Eam2Gq_CtHARsi8HML0GpYH5tU_kg7XJ8YpkdtaL9TA'),
  UIDAI_OTP_URL: z.string().url().default('https://developer.uidai.gov.in/uidotp/2.5'),
  UIDAI_AUTH_URL: z.string().url().default('https://developer.uidai.gov.in/authserver/2.5'),
  UIDAI_KYC_URL: z.string().url().default('https://developer.uidai.gov.in/uidkyc/kyc/2.5'),
  UIDAI_TEST_ENCRYPTION_CERT_PATH: z.string().optional(),
  UIDAI_SIGNING_P12_PATH: z.string().optional(),
  UIDAI_SIGNING_P12_PASSWORD: z.string().optional(),
  SHIPDEHOP_JWT_PRIVATE_JWK: z.string().optional(),
  SHIPDEHOP_JWT_PRIVATE_KEY_PEM: z.string().optional(),
  SHIPDEHOP_JWT_KEY_ID: z.string().optional().default('shipdehop-es256-key-v1'),
}).transform((data) => ({
  ...data,
  PARCEL_INSPECTION_PROVIDER:
    data.PARCEL_INSPECTION_PROVIDER ??
    (data.NODE_ENV === 'production' ? 'GEMINI' : 'OLLAMA'),
  PHONE_VERIFICATION_PROVIDER:
    data.PHONE_VERIFICATION_PROVIDER ??
    (data.NODE_ENV === 'production' ? 'WHATSAPP_OUTBOUND' : 'DEVELOPMENT'),
})).refine(data => {
  if (data.NODE_ENV === 'production') {
    if (data.DEV_TEST_AUTH === true) {
      return false;
    }
    if (data.PAYMENT_PROVIDER === 'MOCK') {
      return false;
    }
    if (data.PAYMENT_PROVIDER === 'STRIPE' && (!data.STRIPE_SECRET_KEY || !data.STRIPE_WEBHOOK_SECRET)) {
      return false;
    }
    if (data.PAYMENT_PROVIDER === 'RAZORPAY' && (!data.RAZORPAY_KEY_ID || !data.RAZORPAY_KEY_SECRET)) {
      return false;
    }
    if (data.PHONE_VERIFICATION_PROVIDER === 'WHATSAPP_INBOUND' && (!data.WHATSAPP_BOT_NUMBER || data.WHATSAPP_BOT_NUMBER === '+15550009427')) {
      return false;
    }
    if (data.PARCEL_INSPECTION_PROVIDER === 'OLLAMA' && (data.OLLAMA_URL.includes('localhost') || data.OLLAMA_URL.includes('127.0.0.1'))) {
      return false;
    }
    if (data.PHONE_VERIFICATION_ENABLED === true && !data.SHIPDEHOP_JWT_PRIVATE_JWK && !data.SHIPDEHOP_JWT_PRIVATE_KEY_PEM) {
      return false;
    }
    // Fail closed: Production mode MUST reject UIDAI Pre-Production provider or Pre-Production environment setting
    if (data.AADHAAR_PROVIDER === 'UIDAI_PREPROD' || (data.AADHAAR_PROVIDER === 'UIDAI_PRODUCTION' && data.UIDAI_ENVIRONMENT === 'PREPRODUCTION')) {
      return false;
    }
    // Fail closed: Production Online Aadhaar requires AADHAAR_ONLINE_ENABLED=true, UIDAI_ONLINE_PRODUCTION_APPROVED=true, and non-test production credentials
    if (data.AADHAAR_PROVIDER === 'UIDAI_PRODUCTION') {
      if (!data.AADHAAR_ONLINE_ENABLED || !data.UIDAI_ONLINE_PRODUCTION_APPROVED) {
        return false;
      }
      if (data.UIDAI_AUA_CODE === 'public' || data.UIDAI_SUB_AUA_CODE === 'public') {
        return false;
      }
      if (!data.UIDAI_SIGNING_P12_PATH || !data.UIDAI_TEST_ENCRYPTION_CERT_PATH) {
        return false;
      }
    }
  }
  return true;
}, {
  message: 'CRITICAL PRODUCTION CONFIGURATION ERROR: Invalid production configuration (DEV_TEST_AUTH=true, MOCK payments, unconfigured STRIPE/RAZORPAY/WHATSAPP_INBOUND, localhost OLLAMA, missing production JWT signing key, or UIDAI Pre-Production provider/environment in production are strictly forbidden).',
});

export const config = envSchema.parse(process.env);
