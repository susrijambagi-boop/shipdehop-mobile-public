-- ============================================================================
-- SHIPDEHOP MIGRATION 008: ZERO-COST IDENTITY BETA HARDENING & AUDIT LOGGING
-- ============================================================================

-- 1. APPEND-ONLY TO CLIENTS / BACKEND-CONTROLLED AUDIT LOG
CREATE TABLE IF NOT EXISTS public.identity_verification_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    previous_status TEXT NOT NULL,
    new_status TEXT NOT NULL,
    review_method TEXT NOT NULL 
        CHECK (review_method IN ('MANUAL_REVIEW_CLI', 'OFFLINE_AADHAAR_QR', 'AUTOMATED_SYSTEM')),
    reviewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reviewer_identifier TEXT NOT NULL,
    reason_code TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_id_audit_user_id ON public.identity_verification_audit (user_id);
CREATE INDEX IF NOT EXISTS idx_id_audit_reviewed_at ON public.identity_verification_audit (reviewed_at);

-- 2. ROW LEVEL SECURITY (RLS) POLICIES FOR AUDIT TRAIL
ALTER TABLE public.identity_verification_audit ENABLE ROW LEVEL SECURITY;

-- Authenticated users can view only their own audit trail
DROP POLICY IF EXISTS "Users can read own identity audit trail" ON public.identity_verification_audit;
CREATE POLICY "Users can read own identity audit trail" 
    ON public.identity_verification_audit 
    FOR SELECT 
    TO authenticated 
    USING (auth.uid() = user_id);

-- Direct client insert/update/delete denied; all audit records inserted by trusted backend service role
DROP POLICY IF EXISTS "Deny client insert on identity_verification_audit" ON public.identity_verification_audit;
CREATE POLICY "Deny client insert on identity_verification_audit" 
    ON public.identity_verification_audit 
    FOR INSERT 
    TO authenticated, anon 
    WITH CHECK (false);

DROP POLICY IF EXISTS "Deny client update on identity_verification_audit" ON public.identity_verification_audit;
CREATE POLICY "Deny client update on identity_verification_audit" 
    ON public.identity_verification_audit 
    FOR UPDATE 
    TO authenticated, anon 
    USING (false);

DROP POLICY IF EXISTS "Deny client delete on identity_verification_audit" ON public.identity_verification_audit;
CREATE POLICY "Deny client delete on identity_verification_audit" 
    ON public.identity_verification_audit 
    FOR DELETE 
    TO authenticated, anon 
    USING (false);

-- 3. EXPLICIT DELETE DENIAL ON USER IDENTITIES
DROP POLICY IF EXISTS "Deny client delete on user_identities" ON public.user_identities;
CREATE POLICY "Deny client delete on user_identities" 
    ON public.user_identities 
    FOR DELETE 
    TO authenticated, anon 
    USING (false);
