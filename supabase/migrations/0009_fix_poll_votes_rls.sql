-- Migration: Fix community poll votes RLS to allow direct insert/delete if needed
-- and ensure community_vote RPC works seamlessly.

DROP POLICY IF EXISTS poll_votes_insert_own ON community_poll_votes;
CREATE POLICY poll_votes_insert_own ON community_poll_votes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS poll_votes_delete_own ON community_poll_votes;
CREATE POLICY poll_votes_delete_own ON community_poll_votes FOR DELETE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS poll_votes_update_own ON community_poll_votes;
CREATE POLICY poll_votes_update_own ON community_poll_votes FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
