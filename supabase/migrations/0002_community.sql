-- ═══════════════════════════════════════════════════════════════════
-- Nivara — 0002 Community board + radius helpers
-- Adds the neighbourhood "Community" feed (general posts, polls, job /
-- service listings, announcements) with per-post visibility radius, plus
-- two PostGIS radius RPCs used by the Pulse tab and the community feed.
-- Depends on 0001_init.sql (user_profiles, reports, PostGIS, is_admin()).
-- Idempotent-ish: safe to run once on a project that already has 0001.
-- ═══════════════════════════════════════════════════════════════════

-- ─────────────────────────── ENUMS ────────────────────────────────
DO $$ BEGIN
  CREATE TYPE community_post_type AS ENUM ('GENERAL', 'POLL', 'JOB', 'ANNOUNCEMENT');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE community_post_status AS ENUM ('OPEN', 'CLOSED');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────── COMMUNITY POSTS ──────────────────────────
-- A neighbourhood board entry. `location` is OPTIONAL: a post with no
-- location is city-wide (visible to everyone); a located post is only
-- shown to viewers within `visibility_radius_km`. `author_name` is
-- denormalised (public board) so the feed never needs to read another
-- user's profile row (which RLS keeps private).
CREATE TABLE IF NOT EXISTS community_posts (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id          UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  author_name        TEXT NOT NULL DEFAULT 'Citizen',
  post_type          community_post_type NOT NULL DEFAULT 'GENERAL',
  title              TEXT NOT NULL,
  body               TEXT,
  photo_urls         TEXT[],

  -- Optional location + how far it should be visible.
  lat                DOUBLE PRECISION,
  lng                DOUBLE PRECISION,
  location           GEOGRAPHY(POINT, 4326),
  location_label     TEXT,
  visibility_radius_km DOUBLE PRECISION NOT NULL DEFAULT 5,

  -- Optional one-tap contact (reuses the Lost & Found contact wire values).
  contact_method     TEXT,
  contact_value      TEXT,

  status             community_post_status NOT NULL DEFAULT 'OPEN',
  valid_until        TIMESTAMPTZ,           -- announcements / job listings

  created_at         TIMESTAMPTZ DEFAULT NOW(),
  updated_at         TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_community_location ON community_posts USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_community_created  ON community_posts (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_community_author   ON community_posts (author_id, created_at DESC);

-- Fill the PostGIS point from lat/lng (only when both are present) + stamp updated_at.
CREATE OR REPLACE FUNCTION community_posts_before_write()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.lat IS NOT NULL AND NEW.lng IS NOT NULL THEN
    NEW.location := ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)::geography;
  ELSE
    NEW.location := NULL;
  END IF;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS community_posts_biu ON community_posts;
CREATE TRIGGER community_posts_biu
  BEFORE INSERT OR UPDATE ON community_posts
  FOR EACH ROW EXECUTE FUNCTION community_posts_before_write();

-- ─────────────────────── POLL OPTIONS + VOTES ─────────────────────
CREATE TABLE IF NOT EXISTS community_poll_options (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id     UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  label       TEXT NOT NULL,
  position    INTEGER NOT NULL DEFAULT 0,
  vote_count  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_poll_options_post ON community_poll_options (post_id, position);

CREATE TABLE IF NOT EXISTS community_poll_votes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id     UUID NOT NULL REFERENCES community_posts(id) ON DELETE CASCADE,
  option_id   UUID NOT NULL REFERENCES community_poll_options(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (post_id, user_id)          -- one (changeable) vote per user per poll
);

-- Cast / change a vote and recompute the affected poll's tallies. SECURITY
-- DEFINER so the tally UPDATE isn't blocked by RLS; guarded by auth.uid().
CREATE OR REPLACE FUNCTION community_vote(p_post_id UUID, p_option_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Must be signed in to vote';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM community_poll_options WHERE id = p_option_id AND post_id = p_post_id
  ) THEN
    RAISE EXCEPTION 'Option does not belong to this poll';
  END IF;

  DELETE FROM community_poll_votes WHERE post_id = p_post_id AND user_id = auth.uid();
  INSERT INTO community_poll_votes (post_id, option_id, user_id)
  VALUES (p_post_id, p_option_id, auth.uid());

  UPDATE community_poll_options o
  SET vote_count = (SELECT COUNT(*) FROM community_poll_votes v WHERE v.option_id = o.id)
  WHERE o.post_id = p_post_id;
END;
$$;

-- ─────────────────── RPC: community posts near me ─────────────────
-- OPEN posts that are either city-wide (no location) or within their own
-- visibility radius of the viewer. STABLE (not DEFINER) — respects RLS.
CREATE OR REPLACE FUNCTION community_posts_near(
  p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION, p_limit INTEGER DEFAULT 200
) RETURNS SETOF community_posts LANGUAGE sql STABLE AS $$
  SELECT * FROM community_posts
  WHERE status = 'OPEN'
    AND (
      location IS NULL
      OR ST_DWithin(location, ST_MakePoint(p_lng, p_lat)::geography, visibility_radius_km * 1000)
    )
  ORDER BY created_at DESC
  LIMIT p_limit;
$$;

-- ─────────────────── RPC: civic reports near me ──────────────────
-- Reports within p_radius_km of a point — powers the Pulse tab's area
-- stats + "recent in your area" list. RETURNS SETOF reports so the app
-- parses rows with the usual Report.fromMap.
CREATE OR REPLACE FUNCTION reports_near(
  p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION,
  p_radius_km DOUBLE PRECISION, p_limit INTEGER DEFAULT 300
) RETURNS SETOF reports LANGUAGE sql STABLE AS $$
  SELECT * FROM reports
  WHERE ST_DWithin(location, ST_MakePoint(p_lng, p_lat)::geography, p_radius_km * 1000)
  ORDER BY created_at DESC
  LIMIT p_limit;
$$;

-- ═══════════════════════ ROW LEVEL SECURITY ═══════════════════════
ALTER TABLE community_posts        ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_poll_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_poll_votes   ENABLE ROW LEVEL SECURITY;

-- POSTS: public board — everyone reads; author writes own; author OR admin
-- deletes (admin moderation removes any user's post).
DROP POLICY IF EXISTS community_read ON community_posts;
CREATE POLICY community_read ON community_posts FOR SELECT USING (true);
DROP POLICY IF EXISTS community_insert_own ON community_posts;
CREATE POLICY community_insert_own ON community_posts FOR INSERT
  WITH CHECK (auth.uid() = author_id);
DROP POLICY IF EXISTS community_update_own ON community_posts;
CREATE POLICY community_update_own ON community_posts FOR UPDATE
  USING (auth.uid() = author_id) WITH CHECK (auth.uid() = author_id);
DROP POLICY IF EXISTS community_delete_own_or_admin ON community_posts;
CREATE POLICY community_delete_own_or_admin ON community_posts FOR DELETE
  USING (auth.uid() = author_id OR is_admin(auth.uid()));

-- POLL OPTIONS: public read; the post's author inserts them at create time.
-- Tallies (vote_count) are written by community_vote() (SECURITY DEFINER).
DROP POLICY IF EXISTS poll_options_read ON community_poll_options;
CREATE POLICY poll_options_read ON community_poll_options FOR SELECT USING (true);
DROP POLICY IF EXISTS poll_options_insert_author ON community_poll_options;
CREATE POLICY poll_options_insert_author ON community_poll_options FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM community_posts p WHERE p.id = post_id AND p.author_id = auth.uid())
  );

-- POLL VOTES: a user can see their own vote (tallies are public via options);
-- casting happens through the SECURITY DEFINER RPC only.
DROP POLICY IF EXISTS poll_votes_read_own ON community_poll_votes;
CREATE POLICY poll_votes_read_own ON community_poll_votes FOR SELECT
  USING (auth.uid() = user_id);

-- ─────────────────────── REALTIME PUBLICATION ─────────────────────
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE community_posts;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE community_poll_options;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ═══════════════════════════ END 0002 ═════════════════════════════
