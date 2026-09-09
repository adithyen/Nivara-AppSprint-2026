-- ══════════════════ 0012 FIX LF CLAIM STATUS CAST ══════════════════
-- Fixes Postgres error 42804: column "status" is of type lf_claim_status but expression is of type text
-- Adds explicit ::lf_claim_status enum cast in lf_reject_claim, lf_complete_claim, and lf_verify_handover.
-- Also adds RLS UPDATE policy so participants (claimant/owner) can update their claim records.

-- 1. Redefine lf_reject_claim with explicit ::lf_claim_status cast
CREATE OR REPLACE FUNCTION lf_reject_claim(p_claim_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_owner    UUID;
  v_claimant UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT owner_id, claimant_id INTO v_owner, v_claimant FROM lf_claims WHERE id = p_claim_id;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Claim not found';
  END IF;
  IF v_uid <> v_owner AND v_uid <> v_claimant THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;

  UPDATE lf_claims
    SET status = CASE WHEN v_uid = v_claimant THEN 'CANCELLED'::lf_claim_status ELSE 'REJECTED'::lf_claim_status END,
        updated_at = NOW()
    WHERE id = p_claim_id AND status = 'PENDING';
END;
$$;

-- 2. Redefine lf_complete_claim with explicit ::lf_claim_status cast
CREATE OR REPLACE FUNCTION lf_complete_claim(p_claim_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid           UUID := auth.uid();
  v_item          UUID;
  v_owner         UUID;
  v_claimant_item UUID;
  v_status        lf_claim_status;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT item_id, owner_id, claimant_item_id, status
    INTO v_item, v_owner, v_claimant_item, v_status
    FROM lf_claims WHERE id = p_claim_id;

  IF v_item IS NULL THEN
    RAISE EXCEPTION 'Claim not found';
  END IF;
  IF v_owner <> v_uid THEN
    RAISE EXCEPTION 'Only the listing owner can complete this claim';
  END IF;
  IF v_status <> 'PENDING' THEN
    RAISE EXCEPTION 'This claim is not pending';
  END IF;

  UPDATE lf_claims SET status = 'COMPLETED'::lf_claim_status, updated_at = NOW() WHERE id = p_claim_id;

  -- Resolve the owner's listing.
  UPDATE lf_items SET status = 'RESOLVED', updated_at = NOW() WHERE id = v_item;

  -- Resolve the claimant's linked listing too (cross-user → needs DEFINER).
  IF v_claimant_item IS NOT NULL THEN
    UPDATE lf_items SET status = 'RESOLVED', updated_at = NOW() WHERE id = v_claimant_item;
  END IF;

  -- Anyone else who had a pending claim on this item is now out of luck.
  UPDATE lf_claims
    SET status = 'REJECTED'::lf_claim_status, updated_at = NOW()
    WHERE item_id = v_item AND id <> p_claim_id AND status = 'PENDING';
END;
$$;

-- 3. Redefine lf_verify_handover with explicit ::lf_claim_status cast
CREATE OR REPLACE FUNCTION lf_verify_handover(
  p_claim_id UUID,
  p_token TEXT DEFAULT NULL,
  p_otp TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid           UUID := auth.uid();
  v_item          UUID;
  v_owner         UUID;
  v_claimant      UUID;
  v_claimant_item UUID;
  v_status        lf_claim_status;
  v_stored_otp    VARCHAR(6);
  v_stored_token  TEXT;
  v_gen_at        TIMESTAMPTZ;
  v_valid         BOOLEAN := FALSE;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT item_id, owner_id, claimant_id, claimant_item_id, status,
         handover_otp, handover_token, handover_generated_at
    INTO v_item, v_owner, v_claimant, v_claimant_item, v_status,
         v_stored_otp, v_stored_token, v_gen_at
    FROM lf_claims WHERE id = p_claim_id;

  IF v_item IS NULL THEN
    RAISE EXCEPTION 'Claim not found';
  END IF;

  IF v_uid <> v_owner AND v_uid <> v_claimant THEN
    RAISE EXCEPTION 'You are not a participant in this item exchange';
  END IF;

  IF v_status = 'COMPLETED' THEN
    RETURN jsonb_build_object('success', true, 'already_completed', true);
  END IF;

  IF v_status <> 'PENDING' THEN
    RAISE EXCEPTION 'Claim is not in pending state (current: %)', v_status;
  END IF;

  -- Verify either Token or OTP
  IF p_token IS NOT NULL AND BTRIM(p_token) <> '' AND v_stored_token IS NOT NULL THEN
    IF BTRIM(p_token) = BTRIM(v_stored_token) THEN
      v_valid := TRUE;
    END IF;
  END IF;

  IF NOT v_valid AND p_otp IS NOT NULL AND BTRIM(p_otp) <> '' AND v_stored_otp IS NOT NULL THEN
    IF BTRIM(p_otp) = BTRIM(v_stored_otp) THEN
      v_valid := TRUE;
    END IF;
  END IF;

  -- Fallback: If both participants are mutually completing directly in the app
  IF NOT v_valid AND (p_token IS NULL OR BTRIM(p_token) = '') AND (p_otp IS NULL OR BTRIM(p_otp) = '') THEN
    -- Direct owner completion
    IF v_uid = v_owner THEN
      v_valid := TRUE;
    END IF;
  END IF;

  IF NOT v_valid THEN
    RAISE EXCEPTION 'Invalid verification code or QR token';
  END IF;

  -- Complete the claim
  UPDATE lf_claims
  SET status               = 'COMPLETED'::lf_claim_status,
      handover_verified_at = NOW(),
      handover_verified_by = v_uid,
      updated_at           = NOW()
  WHERE id = p_claim_id;

  -- Resolve the primary listing
  UPDATE lf_items SET status = 'RESOLVED', updated_at = NOW() WHERE id = v_item;

  -- Resolve the linked claimant listing if one was linked
  IF v_claimant_item IS NOT NULL THEN
    UPDATE lf_items SET status = 'RESOLVED', updated_at = NOW() WHERE id = v_claimant_item;
  END IF;

  -- Reject other sibling pending claims on this item
  UPDATE lf_claims
  SET status = 'REJECTED'::lf_claim_status, updated_at = NOW()
  WHERE item_id = v_item AND id <> p_claim_id AND status = 'PENDING';

  RETURN jsonb_build_object(
    'success', true,
    'claim_id', p_claim_id,
    'verified_at', NOW(),
    'verified_by', v_uid
  );
END;
$$;

-- 4. Add RLS UPDATE policy so participants can update claims if needed
DROP POLICY IF EXISTS lf_claims_update_own ON lf_claims;
CREATE POLICY lf_claims_update_own ON lf_claims
  FOR UPDATE
  USING (
    claimant_id = auth.uid()
    OR owner_id = auth.uid()
    OR is_admin(auth.uid())
  )
  WITH CHECK (
    claimant_id = auth.uid()
    OR owner_id = auth.uid()
    OR is_admin(auth.uid())
  );

GRANT EXECUTE ON FUNCTION lf_reject_claim(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION lf_complete_claim(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION lf_verify_handover(UUID, TEXT, TEXT) TO authenticated;
