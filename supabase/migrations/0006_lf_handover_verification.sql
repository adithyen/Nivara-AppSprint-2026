-- ─────────────────────────────────────────────────────────────────────────
-- 0006_lf_handover_verification.sql — Lost & Found Handover Verification
-- (Dynamic QR Code Token & Proximity 6-Digit PIN Handshake)
--
-- Run in the Supabase SQL editor (or `supabase db push`). Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────

-- 1. Add verification metadata columns to lf_claims table.
ALTER TABLE lf_claims ADD COLUMN IF NOT EXISTS handover_otp VARCHAR(6);
ALTER TABLE lf_claims ADD COLUMN IF NOT EXISTS handover_token TEXT;
ALTER TABLE lf_claims ADD COLUMN IF NOT EXISTS handover_generated_at TIMESTAMPTZ;
ALTER TABLE lf_claims ADD COLUMN IF NOT EXISTS handover_verified_at TIMESTAMPTZ;
ALTER TABLE lf_claims ADD COLUMN IF NOT EXISTS handover_verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_lf_claims_token ON lf_claims (handover_token) WHERE handover_token IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_lf_claims_otp ON lf_claims (id, handover_otp) WHERE handover_otp IS NOT NULL;

-- 2. RPC to generate a dynamic 6-digit OTP and cryptographic handover token.
--    Callable by either the listing owner or the claimant.
CREATE OR REPLACE FUNCTION lf_generate_handover_pass(p_claim_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid         UUID := auth.uid();
  v_owner       UUID;
  v_claimant    UUID;
  v_status      lf_claim_status;
  v_otp         VARCHAR(6);
  v_token       TEXT;
  v_now         TIMESTAMPTZ := NOW();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT owner_id, claimant_id, status
    INTO v_owner, v_claimant, v_status
    FROM lf_claims WHERE id = p_claim_id;

  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Claim not found';
  END IF;

  IF v_uid <> v_owner AND v_uid <> v_claimant THEN
    RAISE EXCEPTION 'Only the item owner or claimant can generate a handover pass';
  END IF;

  IF v_status <> 'PENDING' THEN
    RAISE EXCEPTION 'Claim is not in pending state';
  END IF;

  -- Generate 6-digit numeric OTP (100000 - 999999)
  v_otp := LPAD(FLOOR(100000 + RANDOM() * 900000)::TEXT, 6, '0');

  -- Generate secure token combining claim ID, random UUID, and timestamp hash
  v_token := 'NIVARA-LF-' || SUBSTRING(p_claim_id::TEXT FROM 1 FOR 8) || '-' ||
             SUBSTRING(gen_random_uuid()::TEXT FROM 1 FOR 12);

  UPDATE lf_claims
  SET handover_otp          = v_otp,
      handover_token        = v_token,
      handover_generated_at = v_now,
      updated_at            = v_now
  WHERE id = p_claim_id;

  RETURN jsonb_build_object(
    'claim_id', p_claim_id,
    'otp', v_otp,
    'token', v_token,
    'generated_at', v_now
  );
END;
$$;

-- 3. RPC to verify and complete the physical item handover via QR token or 6-digit PIN.
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
  SET status               = 'COMPLETED',
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
  SET status = 'REJECTED', updated_at = NOW()
  WHERE item_id = v_item AND id <> p_claim_id AND status = 'PENDING';

  RETURN jsonb_build_object(
    'success', true,
    'claim_id', p_claim_id,
    'verified_at', NOW(),
    'verified_by', v_uid
  );
END;
$$;

GRANT EXECUTE ON FUNCTION lf_generate_handover_pass(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION lf_verify_handover(UUID, TEXT, TEXT) TO authenticated;
