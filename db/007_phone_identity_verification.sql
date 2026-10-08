-- ============================================================================
-- SHIPDEHOP MIGRATION 007: ZERO-COST PHONE & IDENTITY VERIFICATION FOUNDATION
-- ============================================================================

-- 1. PHONE VERIFICATION SESSIONS TABLE
CREATE TABLE IF NOT EXISTS public.phone_verification_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    phone_e164 TEXT NOT NULL,
    challenge_hash TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'CREATED' 
        CHECK (status IN ('CREATED', 'WAITING_FOR_WHATSAPP', 'PHONE_VERIFIED', 'EXPIRED', 'CONSUMED', 'BLOCKED')),
    expires_at TIMESTAMPTZ NOT NULL,
    attempt_count INT NOT NULL DEFAULT 0,
    verified_at TIMESTAMPTZ,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_phone_verif_sessions_phone ON public.phone_verification_sessions (phone_e164);
CREATE INDEX IF NOT EXISTS idx_phone_verif_sessions_challenge ON public.phone_verification_sessions (challenge_hash);
CREATE INDEX IF NOT EXISTS idx_phone_verif_sessions_expires ON public.phone_verification_sessions (expires_at);

-- 2. USER IDENTITIES TABLE (Country-extensible identity & biometric state)
CREATE TABLE IF NOT EXISTS public.user_identities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    phone_e164 TEXT,
    identity_method TEXT NOT NULL 
        CHECK (identity_method IN ('AADHAAR_SECURE_QR', 'QATAR_ID', 'EMIRATES_ID', 'PASSPORT', 'OTHER_GOV_ID')),
    document_last4 TEXT,
    signature_valid BOOLEAN NOT NULL DEFAULT false,
    verified_name TEXT,
    verified_birth_year INT,
    gender TEXT,
    liveness_status TEXT NOT NULL DEFAULT 'PENDING' 
        CHECK (liveness_status IN ('PENDING', 'PASS', 'REVIEW', 'FAIL')),
    face_match_status TEXT NOT NULL DEFAULT 'PENDING' 
        CHECK (face_match_status IN ('PENDING', 'PASS', 'REVIEW', 'FAIL')),
    verification_status TEXT NOT NULL DEFAULT 'NOT_STARTED' 
        CHECK (verification_status IN ('NOT_STARTED', 'IN_PROGRESS', 'PENDING_REVIEW', 'VERIFIED', 'REJECTED', 'REVOKED')),
    consent_version TEXT NOT NULL DEFAULT '1.0',
    consented_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    verified_at TIMESTAMPTZ,
    reviewer_id UUID REFERENCES auth.users(id),
    review_notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uq_user_identities_user_id UNIQUE (user_id)
);

CREATE INDEX IF NOT EXISTS idx_user_identities_user_id ON public.user_identities (user_id);
CREATE INDEX IF NOT EXISTS idx_user_identities_status ON public.user_identities (verification_status);

-- 3. ROW LEVEL SECURITY (RLS) POLICIES
ALTER TABLE public.phone_verification_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_identities ENABLE ROW LEVEL SECURITY;

-- Phone sessions: Client direct access disabled; strictly managed by backend service role
DROP POLICY IF EXISTS "Deny all client mutations on phone_verification_sessions" ON public.phone_verification_sessions;
CREATE POLICY "Deny all client mutations on phone_verification_sessions" 
    ON public.phone_verification_sessions 
    FOR ALL 
    TO authenticated, anon 
    USING (false);

-- User identities: Authenticated users can view their own identity record
DROP POLICY IF EXISTS "Users can read own identity record" ON public.user_identities;
CREATE POLICY "Users can read own identity record" 
    ON public.user_identities 
    FOR SELECT 
    TO authenticated 
    USING (auth.uid() = user_id);

-- User identities: Direct client insert/update/delete denied; all state verified via backend service role
DROP POLICY IF EXISTS "Deny client mutations on user_identities" ON public.user_identities;
CREATE POLICY "Deny client mutations on user_identities" 
    ON public.user_identities 
    FOR INSERT 
    TO authenticated, anon 
    WITH CHECK (false);

DROP POLICY IF EXISTS "Deny client update on user_identities" ON public.user_identities;
CREATE POLICY "Deny client update on user_identities" 
    ON public.user_identities 
    FOR UPDATE 
    TO authenticated, anon 
    USING (false);

-- 4. USER REFRESH SESSIONS TABLE (Zero-cost rotating session refresh tokens)
CREATE TABLE IF NOT EXISTS public.user_refresh_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    device_id TEXT,
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_refresh_sessions_user ON public.user_refresh_sessions (user_id);
CREATE INDEX IF NOT EXISTS idx_user_refresh_sessions_hash ON public.user_refresh_sessions (token_hash);

ALTER TABLE public.user_refresh_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Deny direct client access on user_refresh_sessions" ON public.user_refresh_sessions;
CREATE POLICY "Deny direct client access on user_refresh_sessions" 
    ON public.user_refresh_sessions 
    FOR ALL 
    TO authenticated, anon 
    USING (false);

