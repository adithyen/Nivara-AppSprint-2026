-- ─────────────────────────────────────────────────────────────────────────
-- 0005_lf_claims.sql — Lost & Found claim / hand-over flow.
--
-- Run in the Supabase SQL editor (or `supabase db push`). Safe to re-run.
--
-- WHY:
--   A poster can now *close the loop* on a Lost & Found listing in two ways:
--     1. Self-close — they got the item back on their own. That is a plain
--        owner update of their own row (status → RESOLVED), already allowed by
--        the lf_update_own RLS policy, so it needs no server code.
--     2. Claim hand-over — a person spots their item in someone else's listing,
--        sends a CLAIM, and the listing's owner presses "Complete claim". That
--        resolves BOTH listings (the owner's and, if linked, the claimant's own
--        opposite listing) and drops them from the public feed.
--
--   Case (2) requires a claimant to trigger a change on the OWNER's row and the
--   owner to trigger a change on the CLAIMANT's row — cross-user writes that
--   lf_update_own (own rows only) forbids. So the write path lives entirely in
--   SECURITY DEFINER RPCs; direct table writes stay locked down. Clients only
--   ever SELECT lf_claims (to render pending claims + claim state) and call the
--   RPCs.
-- ─────────────────────────────────────────────────────────────────────────

-- 1. Claim lifecycle.
DO $$ BEGIN
  CREATE TYPE lf_claim_status AS ENUM ('PENDING', 'COMPLETED', 'REJECTED', 'CANCELLED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 2. The claims table.
--    item_id           the listing being claimed (belongs to owner_id, someone else)
--    claimant_item_id  the claimant's OWN opposite listing, if they had one (optional)
CREATE TABLE IF NOT EXISTS lf_claims (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id           UUID NOT NULL REFERENCES lf_items(id) ON DELETE CASCADE,
  owner_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  claimant_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  claimant_item_id  UUID REFERENCES lf_items(id) ON DELETE SET NULL,
  message           TEXT,
  status            lf_claim_status NOT NULL DEFAULT 'PENDING',
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (item_id, claimant_id)
);

CREATE INDEX IF NOT EXISTS idx_lf_claims_item ON lf_claims (item_id, status);
CREATE INDEX IF NOT EXISTS idx_lf_claims_owner ON lf_claims (owner_id, status);
CREATE INDEX IF NOT EXISTS idx_lf_claims_claimant ON lf_claims (claimant_id, status);

-- 3. RLS: a claim is visible to the two parties (and admins). All writes go
--    through the RPCs below, so there are deliberately NO insert/update policies.
ALTER TABLE lf_claims ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS lf_claims_read ON lf_claims;
CREATE POLICY lf_claims_read ON lf_claims
  FOR SELECT
  USING (
    claimant_id = auth.uid()
    OR owner_id = auth.uid()
    OR is_admin(auth.uid())
  );

-- 4. RPC — a claimant sends a claim on someone else's ACTIVE listing.
--    Optionally links the claimant's own opposite listing so completing the
--    claim can resolve both. Idempotent: re-claiming re-opens a prior
--    rejected/cancelled claim rather than erroring.
CREATE OR REPLACE FUNCTION lf_create_claim(
  p_item_id UUID,
  p_claimant_item_id UUID DEFAULT NULL,
  p_message TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_owner    UUID;
  v_status   TEXT;
  v_claim_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT user_id, status INTO v_owner, v_status FROM lf_items WHERE id = p_item_id;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Item not found';
  END IF;
  IF v_owner = v_uid THEN
    RAISE EXCEPTION 'You cannot claim your own listing';
  END IF;
  IF v_status <> 'ACTIVE' THEN
    RAISE EXCEPTION 'This item is no longer available';
  END IF;

  -- A linked listing, if given, must belong to the claimant.
  IF p_claimant_item_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM lf_items WHERE id = p_claimant_item_id AND user_id = v_uid
    ) THEN
      RAISE EXCEPTION 'Linked listing is not yours';
    END IF;
  END IF;

  INSERT INTO lf_claims (item_id, owner_id, claimant_id, claimant_item_id, message, status)
  VALUES (
    p_item_id, v_owner, v_uid, p_claimant_item_id,
    NULLIF(BTRIM(COALESCE(p_message, '')), ''), 'PENDING'
  )
  ON CONFLICT (item_id, claimant_id) DO UPDATE
    SET status           = 'PENDING',
        claimant_item_id = EXCLUDED.claimant_item_id,
        message          = EXCLUDED.message,
        updated_at       = NOW()
  RETURNING id INTO v_claim_id;

  RETURN v_claim_id;
END;
$$;

-- 5. RPC — the listing owner completes a claim. Resolves BOTH listings and
--    rejects any sibling pending claims on the same listing.
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

  UPDATE lf_claims SET status = 'COMPLETED', updated_at = NOW() WHERE id = p_claim_id;

  -- Resolve the owner's listing.
  UPDATE lf_items SET status = 'RESOLVED', updated_at = NOW() WHERE id = v_item;

  -- Resolve the claimant's linked listing too (cross-user → needs DEFINER).
  IF v_claimant_item IS NOT NULL THEN
    UPDATE lf_items SET status = 'RESOLVED', updated_at = NOW() WHERE id = v_claimant_item;
  END IF;

  -- Anyone else who had a pending claim on this item is now out of luck.
  UPDATE lf_claims
    SET status = 'REJECTED', updated_at = NOW()
    WHERE item_id = v_item AND id <> p_claim_id AND status = 'PENDING';
END;
$$;

-- 6. RPC — decline / withdraw a pending claim. The owner rejects; the claimant
--    cancels. Either way the claim leaves PENDING and both listings stay active.
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
    SET status = CASE WHEN v_uid = v_claimant THEN 'CANCELLED' ELSE 'REJECTED' END,
        updated_at = NOW()
    WHERE id = p_claim_id AND status = 'PENDING';
END;
$$;

GRANT EXECUTE ON FUNCTION lf_create_claim(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION lf_complete_claim(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION lf_reject_claim(UUID) TO authenticated;

-- 7. Realtime so a claimant sees "completed" and an owner sees a new claim live.
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE lf_claims;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
