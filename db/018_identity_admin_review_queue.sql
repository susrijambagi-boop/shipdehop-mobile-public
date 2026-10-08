-- ============================================================================
-- SHIPDEHOP MIGRATION 018: ADMIN IDENTITY REVIEW QUEUE
-- ============================================================================

-- Align the audit constraint with the review methods the trusted identity
-- service actually emits, and add the browser-admin review method.
ALTER TABLE public.identity_verification_audit
  DROP CONSTRAINT IF EXISTS identity_verification_audit_review_method_check;

ALTER TABLE public.identity_verification_audit
  ADD CONSTRAINT identity_verification_audit_review_method_check
  CHECK (review_method IN (
    'MANUAL_REVIEW_CLI',
    'MANUAL_REVIEW_ADMIN',
    'MANUAL_BETA',
    'OFFLINE_AADHAAR_QR',
    'AUTOMATED_SYSTEM',
    'AADHAAR_OVSE_APP',
    'AADHAAR_OFFLINE_XML',
    'AADHAAR_SECURE_QR',
    'AADHAAR_UIDAI_PREPROD'
  ));

-- Admins need visibility and tightly scoped mutation rights. Grants establish
-- which operations authenticated clients can attempt; RLS still decides which
-- rows they may touch.
GRANT SELECT, UPDATE ON public.user_identities TO authenticated;
GRANT SELECT, INSERT ON public.identity_verification_audit TO authenticated;

DROP POLICY IF EXISTS "Admins can read identity review queue" ON public.user_identities;
CREATE POLICY "Admins can read identity review queue"
  ON public.user_identities
  FOR SELECT
  TO authenticated
  USING ((select public.is_admin()));

DROP POLICY IF EXISTS "Admins can update identity review queue" ON public.user_identities;
CREATE POLICY "Admins can update identity review queue"
  ON public.user_identities
  FOR UPDATE
  TO authenticated
  USING ((select public.is_admin()))
  WITH CHECK ((select public.is_admin()));

DROP POLICY IF EXISTS "Admins can read identity audit trail" ON public.identity_verification_audit;
CREATE POLICY "Admins can read identity audit trail"
  ON public.identity_verification_audit
  FOR SELECT
  TO authenticated
  USING ((select public.is_admin()));

DROP POLICY IF EXISTS "Admins can append identity audit trail" ON public.identity_verification_audit;
CREATE POLICY "Admins can append identity audit trail"
  ON public.identity_verification_audit
  FOR INSERT
  TO authenticated
  WITH CHECK ((select public.is_admin()) AND reviewer_identifier = (select auth.uid())::text);

-- The RPC is SECURITY INVOKER (the default). Its UPDATE/INSERT therefore remain
-- subject to the grants and admin-only RLS policies above.
CREATE OR REPLACE FUNCTION public.admin_review_identity(
  p_user_id uuid,
  p_decision text,
  p_note text DEFAULT ''
)
RETURNS public.user_identities
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_identity public.user_identities;
  v_previous text;
  v_decision text := upper(trim(coalesce(p_decision, '')));
  v_note text := left(trim(coalesce(p_note, '')), 1000);
  v_now timestamptz := now();
  v_reviewer uuid := auth.uid();
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Admin required';
  END IF;

  IF v_reviewer IS NULL THEN
    RAISE EXCEPTION 'Authenticated admin required';
  END IF;

  IF v_decision NOT IN ('APPROVE', 'REJECT') THEN
    RAISE EXCEPTION 'Decision must be APPROVE or REJECT';
  END IF;

  IF length(v_note) < 10 THEN
    RAISE EXCEPTION 'A review note of at least 10 characters is required';
  END IF;

  SELECT *
    INTO v_identity
    FROM public.user_identities
   WHERE user_id = p_user_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Identity review request not found';
  END IF;

  IF v_identity.verification_status <> 'PENDING_REVIEW' THEN
    RAISE EXCEPTION 'Only PENDING_REVIEW identities can be reviewed; current status is %',
      v_identity.verification_status;
  END IF;

  v_previous := v_identity.verification_status;

  UPDATE public.user_identities
     SET verification_status = CASE WHEN v_decision = 'APPROVE' THEN 'VERIFIED' ELSE 'REJECTED' END,
         -- MANUAL_BETA is represented in review_notes because the original
         -- identity_method database enum/check intentionally stores OTHER_GOV_ID.
         identity_method = 'OTHER_GOV_ID',
         verified_at = CASE WHEN v_decision = 'APPROVE' THEN v_now ELSE NULL END,
         reviewer_id = v_reviewer,
         review_notes = CASE
           WHEN v_decision = 'APPROVE'
             THEN 'MANUAL_BETA: ' || coalesce(nullif(v_note, ''), 'Approved in ShipdeHop Ops')
           ELSE 'MANUAL_REVIEW_REJECTED: ' || coalesce(nullif(v_note, ''), 'Rejected in ShipdeHop Ops')
         END,
         updated_at = v_now
   WHERE user_id = p_user_id
   RETURNING * INTO v_identity;

  INSERT INTO public.identity_verification_audit(
    user_id,
    previous_status,
    new_status,
    review_method,
    reviewed_at,
    reviewer_identifier,
    reason_code,
    metadata
  ) VALUES (
    p_user_id,
    v_previous,
    v_identity.verification_status,
    'MANUAL_REVIEW_ADMIN',
    v_now,
    v_reviewer::text,
    CASE WHEN v_decision = 'APPROVE'
      THEN 'MANUAL_BETA_APPROVAL'
      ELSE 'MANUAL_BETA_REJECTION'
    END,
    jsonb_build_object('note', v_note, 'source', 'SHIPDEHOP_OPS')
  );

  RETURN v_identity;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.admin_review_identity(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_review_identity(uuid, text, text) TO authenticated;
