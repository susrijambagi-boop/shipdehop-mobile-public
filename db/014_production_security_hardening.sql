-- Migration 014: Production Security Hardening
-- Restrict service-role-only administrative RPCs and sensitive verification table access

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'phone_verification_sessions') THEN
    REVOKE ALL ON TABLE public.phone_verification_sessions FROM PUBLIC, anon, authenticated;
    GRANT ALL ON TABLE public.phone_verification_sessions TO service_role;
  END IF;

  IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'identity_verification') THEN
    REVOKE ALL ON TABLE public.identity_verification FROM PUBLIC, anon, authenticated;
    GRANT SELECT, INSERT, UPDATE ON TABLE public.identity_verification TO authenticated;
    GRANT ALL ON TABLE public.identity_verification TO service_role;
  END IF;
END $$;
