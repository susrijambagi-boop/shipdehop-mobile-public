-- ============================================================================
-- SHIPDEHOP MIGRATION 019: WHATSAPP OTP BRIDGE
-- ============================================================================

-- Server-only persisted linked-device authentication state for the self-hosted
-- WhatsApp OTP bridge. Client roles must never be able to read Signal/WhatsApp
-- device credentials.
CREATE TABLE IF NOT EXISTS public.whatsapp_bridge_auth (
  storage_key text PRIMARY KEY,
  value jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.whatsapp_bridge_auth ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.whatsapp_bridge_auth FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.whatsapp_bridge_auth TO service_role;

-- OTP delivery observability. Plaintext OTPs are never stored; challenge_hash
-- contains only the keyed OTP hash used by the backend verifier.
ALTER TABLE public.phone_verification_sessions
  ADD COLUMN IF NOT EXISTS otp_send_attempts integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS otp_sent_at timestamptz,
  ADD COLUMN IF NOT EXISTS otp_message_id text,
  ADD COLUMN IF NOT EXISTS otp_last_error text,
  ADD COLUMN IF NOT EXISTS delivery_provider text;

CREATE INDEX IF NOT EXISTS idx_phone_verif_sessions_delivery
  ON public.phone_verification_sessions (phone_e164, created_at DESC);

COMMENT ON TABLE public.whatsapp_bridge_auth IS
  'Server-only persisted WhatsApp linked-device authentication state. Never exposed to app clients.';
