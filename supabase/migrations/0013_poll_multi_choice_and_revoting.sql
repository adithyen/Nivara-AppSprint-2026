-- Migration: 0013_poll_multi_choice_and_revoting.sql
-- Enables multiple-choice polls and vote modification/un-voting.

ALTER TABLE community_posts ADD COLUMN IF NOT EXISTS allows_multiple BOOLEAN NOT NULL DEFAULT FALSE;

-- Relax unique constraint to allow multiple distinct options per user for multi-choice polls
ALTER TABLE community_poll_votes DROP CONSTRAINT IF EXISTS community_poll_votes_post_id_user_id_key;
ALTER TABLE community_poll_votes DROP CONSTRAINT IF EXISTS community_poll_votes_post_user_option_key;
ALTER TABLE community_poll_votes ADD CONSTRAINT community_poll_votes_post_user_option_key UNIQUE (post_id, user_id, option_id);

-- Update community_vote to handle:
-- 1. Modifying vote / switching options on single-choice polls
-- 2. Toggling off / un-voting when tapping an already selected option
-- 3. Selecting multiple options when allows_multiple = true
CREATE OR REPLACE FUNCTION public.community_vote(p_post_id UUID, p_option_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_allows_multiple BOOLEAN := FALSE;
  v_already_voted_this BOOLEAN := FALSE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Must be signed in to vote';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM community_poll_options WHERE id = p_option_id AND post_id = p_post_id
  ) THEN
    RAISE EXCEPTION 'Option does not belong to this poll';
  END IF;

  SELECT COALESCE(allows_multiple, FALSE) INTO v_allows_multiple
  FROM community_posts
  WHERE id = p_post_id;

  SELECT EXISTS (
    SELECT 1 FROM community_poll_votes
    WHERE post_id = p_post_id AND option_id = p_option_id AND user_id = auth.uid()
  ) INTO v_already_voted_this;

  IF v_already_voted_this THEN
    -- Toggle off / un-vote for this option
    DELETE FROM community_poll_votes
    WHERE post_id = p_post_id AND option_id = p_option_id AND user_id = auth.uid();
  ELSE
    -- If single-choice poll, remove any previous vote on this poll so the vote modifies cleanly
    IF NOT v_allows_multiple THEN
      DELETE FROM community_poll_votes
      WHERE post_id = p_post_id AND user_id = auth.uid();
    END IF;

    -- Insert new vote
    INSERT INTO community_poll_votes (post_id, option_id, user_id)
    VALUES (p_post_id, p_option_id, auth.uid())
    ON CONFLICT (post_id, user_id, option_id) DO NOTHING;
  END IF;

  -- Recompute tallies for all options in this poll
  UPDATE community_poll_options o
  SET vote_count = (SELECT COUNT(*) FROM community_poll_votes v WHERE v.option_id = o.id)
  WHERE o.post_id = p_post_id;
END;
$$;

-- Recreate community_posts_near to include the new allows_multiple column in SETOF community_posts
CREATE OR REPLACE FUNCTION public.community_posts_near(p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION, p_limit INTEGER DEFAULT 200)
RETURNS SETOF community_posts
LANGUAGE sql
STABLE
AS $$
  SELECT * FROM community_posts
  WHERE status = 'OPEN'
    AND (
      location IS NULL
      OR ST_DWithin(location, ST_MakePoint(p_lng, p_lat)::geography, visibility_radius_km * 1000)
    )
  ORDER BY created_at DESC
  LIMIT p_limit;
$$;
