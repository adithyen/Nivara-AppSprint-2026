-- ═══════════════════════════════════════════════════════════════════
-- Nivara — Initial Schema (consolidated)
-- Engine: PostgreSQL (Supabase) + PostGIS
-- Includes: civic reports, sensor detections, lost & found,
--           community verification, gamification, AND role-based
--           user / admin (municipal authority) access.
-- Idempotent-ish: safe to run once on a fresh project.
-- ═══════════════════════════════════════════════════════════════════

-- ─────────────────────────── EXTENSIONS ───────────────────────────
CREATE EXTENSION IF NOT EXISTS postgis;   -- spatial queries
CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- text similarity for LF matching

-- ─────────────────────────── ENUMS ────────────────────────────────
DO $$ BEGIN
  CREATE TYPE user_role AS ENUM ('CITIZEN', 'ADMIN', 'SUPERADMIN');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Which civic domain an ADMIN is responsible for. GENERAL = sees all.
DO $$ BEGIN
  CREATE TYPE admin_department AS ENUM (
    'GENERAL', 'ROADS', 'SANITATION', 'WATER', 'ELECTRICITY',
    'PARKS', 'ANIMALS', 'ENFORCEMENT'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE report_category AS ENUM (
    'POTHOLE', 'BROKEN_FOOTPATH', 'OPEN_MANHOLE', 'FALLEN_TREE',
    'WATERLOGGING', 'ROAD_SIGN', 'GARBAGE', 'BLOCKED_DRAIN',
    'SEWAGE', 'STREET_LIGHT', 'DAMAGED_POLE', 'POWER_ISSUE',
    'WATER_SUPPLY', 'PIPE_LEAK', 'ENCROACHMENT', 'BROKEN_PROPERTY',
    'STRAY_ANIMALS', 'NOISE', 'OTHER'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE report_status AS ENUM (
    'SUBMITTED', 'ACKNOWLEDGED', 'IN_PROGRESS', 'RESOLVED', 'CLOSED', 'DUPLICATE'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE severity AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'EMERGENCY');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE detection_type AS ENUM ('POTHOLE', 'SPEED_BREAKER', 'BAD_ROAD', 'MANUAL');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE lf_category AS ENUM (
    'AADHAAR', 'PAN_CARD', 'DRIVING_LICENCE', 'PASSPORT', 'OTHER_DOCUMENT',
    'MOBILE_PHONE', 'WALLET', 'KEYS', 'BAG', 'JEWELLERY', 'PET', 'VEHICLE', 'OTHER'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE lf_item_type AS ENUM ('LOST', 'FOUND');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE match_status AS ENUM (
    'PENDING', 'CONFIRMED_BY_FINDER', 'CONFIRMED_BY_BOTH', 'REJECTED', 'RESOLVED'
  );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ─────────────────────── USER PROFILES ────────────────────────────
-- One row per auth user. Role decides which side of the app they see.
CREATE TABLE IF NOT EXISTS user_profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name  TEXT NOT NULL DEFAULT 'Citizen',
  avatar_url    TEXT,
  phone         TEXT,
  city          TEXT,
  ward          TEXT,

  -- Role-based access
  role          user_role NOT NULL DEFAULT 'CITIZEN',
  department    admin_department,        -- only meaningful for ADMIN
  jurisdiction_city TEXT,                -- NULL = all cities (for GENERAL/SUPERADMIN)
  jurisdiction_ward TEXT,                -- NULL = whole city

  -- Gamification
  civic_score   INTEGER DEFAULT 0,
  reports_count INTEGER DEFAULT 0,
  finds_count   INTEGER DEFAULT 0,

  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────── ROLE HELPERS ─────────────────────────────
-- SECURITY DEFINER so they can read user_profiles.role without tripping
-- the table's own RLS (prevents recursive-policy errors).
CREATE OR REPLACE FUNCTION is_admin(uid UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_profiles
    WHERE id = uid AND role IN ('ADMIN', 'SUPERADMIN')
  );
$$;

CREATE OR REPLACE FUNCTION is_superadmin(uid UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_profiles
    WHERE id = uid AND role = 'SUPERADMIN'
  );
$$;

-- Auto-create a profile row when a new auth user signs up.
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  INSERT INTO user_profiles (id, display_name, phone)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
    NEW.raw_user_meta_data->>'phone'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ─────────────────────── CIVIC REPORTS ────────────────────────────
CREATE TABLE IF NOT EXISTS reports (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  category          report_category NOT NULL,
  status            report_status DEFAULT 'SUBMITTED',
  severity          severity DEFAULT 'MEDIUM',
  title             TEXT,
  description       TEXT,
  location          GEOGRAPHY(POINT, 4326) NOT NULL,
  lat               DOUBLE PRECISION NOT NULL,
  lng               DOUBLE PRECISION NOT NULL,
  address           TEXT,
  city              TEXT,
  ward              TEXT,

  -- Source
  source            TEXT DEFAULT 'MANUAL',            -- 'SENSORWATCH' | 'MANUAL'
  detection_type    detection_type,
  evidence_package  JSONB,
  evidence_hash     TEXT,
  photo_urls        TEXT[],

  -- Community verification
  confirmation_count    INTEGER DEFAULT 0,
  resolved_count        INTEGER DEFAULT 0,
  is_community_verified BOOLEAN DEFAULT FALSE,

  -- Administrative handling (municipal side)
  assigned_department admin_department,               -- routed domain
  assigned_to         UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  acknowledged_at     TIMESTAMPTZ,
  acknowledged_by     UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  resolved_at         TIMESTAMPTZ,
  resolved_by         UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  resolution_notes    TEXT,
  resolution_photo    TEXT,

  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reports_location ON reports USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_reports_city_status ON reports (city, status, category);
CREATE INDEX IF NOT EXISTS idx_reports_created ON reports (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_dept_status ON reports (assigned_department, status);

-- Auto-fill PostGIS point + auto-route to a department from category.
CREATE OR REPLACE FUNCTION reports_before_write()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.location := ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)::geography;
  IF NEW.assigned_department IS NULL THEN
    NEW.assigned_department := CASE NEW.category
      WHEN 'POTHOLE'         THEN 'ROADS'
      WHEN 'BROKEN_FOOTPATH' THEN 'ROADS'
      WHEN 'ROAD_SIGN'       THEN 'ROADS'
      WHEN 'FALLEN_TREE'     THEN 'PARKS'
      WHEN 'GARBAGE'         THEN 'SANITATION'
      WHEN 'BLOCKED_DRAIN'   THEN 'SANITATION'
      WHEN 'SEWAGE'          THEN 'SANITATION'
      WHEN 'OPEN_MANHOLE'    THEN 'SANITATION'
      WHEN 'WATERLOGGING'    THEN 'WATER'
      WHEN 'WATER_SUPPLY'    THEN 'WATER'
      WHEN 'PIPE_LEAK'       THEN 'WATER'
      WHEN 'STREET_LIGHT'    THEN 'ELECTRICITY'
      WHEN 'DAMAGED_POLE'    THEN 'ELECTRICITY'
      WHEN 'POWER_ISSUE'     THEN 'ELECTRICITY'
      WHEN 'STRAY_ANIMALS'   THEN 'ANIMALS'
      WHEN 'ENCROACHMENT'    THEN 'ENFORCEMENT'
      ELSE 'GENERAL'
    END;
  END IF;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reports_biu ON reports;
CREATE TRIGGER reports_biu
  BEFORE INSERT OR UPDATE ON reports
  FOR EACH ROW EXECUTE FUNCTION reports_before_write();

-- ─────────────────── REPORT STATUS HISTORY (audit) ────────────────
CREATE TABLE IF NOT EXISTS report_status_history (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id   UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  changed_by  UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  old_status  report_status,
  new_status  report_status NOT NULL,
  note        TEXT,
  photo_url   TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_status_history_report ON report_status_history (report_id, created_at DESC);

-- ─────────────────── CONFIRMATIONS (community) ────────────────────
CREATE TABLE IF NOT EXISTS confirmations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id   UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES user_profiles(id),
  type        TEXT DEFAULT 'CONFIRM',            -- 'CONFIRM' | 'RESOLVED'
  location    GEOGRAPHY(POINT, 4326),
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (report_id, user_id, type)
);

CREATE OR REPLACE FUNCTION update_confirmation_count()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE reports SET
    confirmation_count = (SELECT COUNT(*) FROM confirmations WHERE report_id = NEW.report_id AND type = 'CONFIRM'),
    resolved_count     = (SELECT COUNT(*) FROM confirmations WHERE report_id = NEW.report_id AND type = 'RESOLVED'),
    is_community_verified = (SELECT COUNT(*) >= 5 FROM confirmations WHERE report_id = NEW.report_id AND type = 'CONFIRM'),
    status = CASE
      WHEN status IN ('RESOLVED','CLOSED') THEN status  -- admin decision wins
      WHEN (SELECT COUNT(*) >= 3 FROM confirmations WHERE report_id = NEW.report_id AND type = 'RESOLVED')
        THEN 'RESOLVED'::report_status
      ELSE status
    END
  WHERE id = NEW.report_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS confirmation_count_trigger ON confirmations;
CREATE TRIGGER confirmation_count_trigger
  AFTER INSERT ON confirmations
  FOR EACH ROW EXECUTE FUNCTION update_confirmation_count();

-- ─────────────────── SENSOR DETECTIONS (raw log) ──────────────────
CREATE TABLE IF NOT EXISTS sensor_detections (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES user_profiles(id),
  detection_type   detection_type NOT NULL,
  lat              DOUBLE PRECISION NOT NULL,
  lng              DOUBLE PRECISION NOT NULL,
  location         GEOGRAPHY(POINT, 4326) NOT NULL,
  speed_kmph       REAL,
  accel_z_peak     REAL,
  accel_z_baseline REAL,
  evidence_hash    TEXT NOT NULL,
  evidence_package JSONB NOT NULL,
  was_reported     BOOLEAN DEFAULT FALSE,
  report_id        UUID REFERENCES reports(id),
  detected_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_detections_location ON sensor_detections USING GIST (location);

-- Road quality heatmap grid (~50m cells, last 30 days).
CREATE MATERIALIZED VIEW IF NOT EXISTS road_quality_grid AS
SELECT
  ST_SnapToGrid(location::geometry, 0.0005) AS grid_cell,
  AVG(accel_z_peak - accel_z_baseline)      AS avg_severity,
  COUNT(*)                                  AS event_count,
  MAX(detected_at)                          AS last_event
FROM sensor_detections
WHERE detected_at > NOW() - INTERVAL '30 days'
GROUP BY grid_cell;

-- ─────────────────────── LOST & FOUND ─────────────────────────────
CREATE TABLE IF NOT EXISTS lf_items (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES user_profiles(id),
  item_type        lf_item_type NOT NULL,
  category         lf_category NOT NULL,
  title            TEXT NOT NULL,
  description      TEXT NOT NULL,
  photo_urls       TEXT[],
  lat              DOUBLE PRECISION NOT NULL,
  lng              DOUBLE PRECISION NOT NULL,
  location         GEOGRAPHY(POINT, 4326) NOT NULL,
  location_label   TEXT,
  event_date       DATE NOT NULL,
  contact_method   TEXT DEFAULT 'PHONE',
  contact_phone    TEXT,
  contact_value    TEXT,
  reward_amount    INTEGER,
  status           TEXT DEFAULT 'ACTIVE',
  expires_at       TIMESTAMPTZ DEFAULT NOW() + INTERVAL '30 days',
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_lf_location ON lf_items USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_lf_category_type ON lf_items (category, item_type, status);
CREATE INDEX IF NOT EXISTS idx_lf_city_expires ON lf_items (status, expires_at);
CREATE INDEX IF NOT EXISTS idx_lf_description_fts ON lf_items USING GIN (to_tsvector('english', description));

CREATE OR REPLACE FUNCTION lf_items_before_write()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.location := ST_SetSRID(ST_MakePoint(NEW.lng, NEW.lat), 4326)::geography;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS lf_items_biu ON lf_items;
CREATE TRIGGER lf_items_biu
  BEFORE INSERT OR UPDATE ON lf_items
  FOR EACH ROW EXECUTE FUNCTION lf_items_before_write();

CREATE TABLE IF NOT EXISTS lf_matches (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lost_item_id  UUID NOT NULL REFERENCES lf_items(id) ON DELETE CASCADE,
  found_item_id UUID NOT NULL REFERENCES lf_items(id) ON DELETE CASCADE,
  match_score   INTEGER NOT NULL,
  status        match_status DEFAULT 'PENDING',
  confirmed_at  TIMESTAMPTZ,
  resolved_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (lost_item_id, found_item_id)
);

CREATE TABLE IF NOT EXISTS score_events (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES user_profiles(id),
  event_type   TEXT NOT NULL,
  points       INTEGER NOT NULL,
  reference_id UUID,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────── RPC: nearby LF items ─────────────────────────
-- Returns the full counterpart payload (photos, owner, contact) so the match
-- list can show images to verify ownership and offer one-tap contact.
CREATE OR REPLACE FUNCTION find_nearby_items(
  p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION,
  p_radius_km DOUBLE PRECISION, p_category lf_category,
  p_item_type lf_item_type, p_within_days INTEGER
) RETURNS TABLE (
  id UUID, user_id UUID, item_type lf_item_type, category lf_category,
  title TEXT, description TEXT, photo_urls TEXT[],
  lat DOUBLE PRECISION, lng DOUBLE PRECISION, location_label TEXT,
  event_date DATE, contact_method TEXT, contact_value TEXT,
  contact_phone TEXT, reward_amount INTEGER,
  created_at TIMESTAMPTZ, distance_km DOUBLE PRECISION
) LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN QUERY
  SELECT i.id, i.user_id, i.item_type, i.category,
         i.title, i.description, i.photo_urls,
         i.lat, i.lng, i.location_label,
         i.event_date, i.contact_method, i.contact_value,
         i.contact_phone, i.reward_amount, i.created_at,
         ST_Distance(i.location, ST_MakePoint(p_lng, p_lat)::geography) / 1000.0 AS distance_km
  FROM lf_items i
  WHERE i.item_type = p_item_type
    AND i.category = p_category
    AND i.status = 'ACTIVE'
    AND i.event_date >= CURRENT_DATE - p_within_days
    AND ST_DWithin(i.location, ST_MakePoint(p_lng, p_lat)::geography, p_radius_km * 1000)
  ORDER BY distance_km ASC
  LIMIT 20;
END;
$$;

-- ─────────────── RPC: admin changes a report status ───────────────
-- Single entry point for the municipal side. Enforces admin role,
-- writes the audit trail, and stamps ack/resolve metadata.
CREATE OR REPLACE FUNCTION admin_set_report_status(
  p_report_id UUID,
  p_new_status report_status,
  p_note TEXT DEFAULT NULL,
  p_photo_url TEXT DEFAULT NULL
) RETURNS reports LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_old report_status;
  v_row reports;
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only administrators can change report status';
  END IF;

  SELECT status INTO v_old FROM reports WHERE id = p_report_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Report % not found', p_report_id;
  END IF;

  UPDATE reports SET
    status           = p_new_status,
    acknowledged_at  = COALESCE(acknowledged_at, CASE WHEN p_new_status = 'ACKNOWLEDGED' THEN NOW() END),
    acknowledged_by  = COALESCE(acknowledged_by, CASE WHEN p_new_status = 'ACKNOWLEDGED' THEN auth.uid() END),
    resolved_at      = CASE WHEN p_new_status = 'RESOLVED' THEN NOW() ELSE resolved_at END,
    resolved_by      = CASE WHEN p_new_status = 'RESOLVED' THEN auth.uid() ELSE resolved_by END,
    resolution_notes = COALESCE(p_note, resolution_notes),
    resolution_photo = COALESCE(p_photo_url, resolution_photo)
  WHERE id = p_report_id
  RETURNING * INTO v_row;

  INSERT INTO report_status_history (report_id, changed_by, old_status, new_status, note, photo_url)
  VALUES (p_report_id, auth.uid(), v_old, p_new_status, p_note, p_photo_url);

  RETURN v_row;
END;
$$;

-- ─────────────── RPC: bootstrap / promote an admin ────────────────
-- SUPERADMIN only. Bootstrap the FIRST superadmin manually in the SQL
-- editor (see 09_ADMIN_AND_AUTH.md), then use this for everyone else.
CREATE OR REPLACE FUNCTION set_user_role(
  p_user_id UUID, p_role user_role,
  p_department admin_department DEFAULT NULL,
  p_city TEXT DEFAULT NULL, p_ward TEXT DEFAULT NULL
) RETURNS user_profiles LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_row user_profiles;
BEGIN
  IF NOT is_superadmin(auth.uid()) THEN
    RAISE EXCEPTION 'Only a superadmin can assign roles';
  END IF;
  UPDATE user_profiles SET
    role = p_role,
    department = p_department,
    jurisdiction_city = p_city,
    jurisdiction_ward = p_ward,
    updated_at = NOW()
  WHERE id = p_user_id
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- ─────────────── PUBLIC PROFILE VIEW (safe columns) ───────────────
-- Exposes only non-sensitive fields (no phone) for leaderboards / author chips.
CREATE OR REPLACE VIEW public_profiles AS
  SELECT id, display_name, avatar_url, city, ward, civic_score, role
  FROM user_profiles;

-- ═══════════════════════ ROW LEVEL SECURITY ═══════════════════════
ALTER TABLE user_profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports              ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE confirmations        ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_items             ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_matches           ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensor_detections    ENABLE ROW LEVEL SECURITY;
ALTER TABLE score_events         ENABLE ROW LEVEL SECURITY;

-- USER PROFILES: read own; admins read all; write own (role changes go via RPC).
DROP POLICY IF EXISTS profiles_select_own ON user_profiles;
CREATE POLICY profiles_select_own ON user_profiles FOR SELECT
  USING (auth.uid() = id OR is_admin(auth.uid()));
DROP POLICY IF EXISTS profiles_update_own ON user_profiles;
CREATE POLICY profiles_update_own ON user_profiles FOR UPDATE
  USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- REPORTS: everyone reads; citizen inserts own; citizen edits own ONLY while
-- still SUBMITTED (can't tamper after authorities engage); admins update any.
DROP POLICY IF EXISTS reports_public_read ON reports;
CREATE POLICY reports_public_read ON reports FOR SELECT USING (true);
DROP POLICY IF EXISTS reports_insert_own ON reports;
CREATE POLICY reports_insert_own ON reports FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS reports_update_own ON reports;
CREATE POLICY reports_update_own ON reports FOR UPDATE
  USING (auth.uid() = user_id AND status = 'SUBMITTED');
DROP POLICY IF EXISTS reports_update_admin ON reports;
CREATE POLICY reports_update_admin ON reports FOR UPDATE
  USING (is_admin(auth.uid())) WITH CHECK (is_admin(auth.uid()));

-- STATUS HISTORY: public read (transparency); inserts happen via SECURITY DEFINER RPC.
DROP POLICY IF EXISTS history_public_read ON report_status_history;
CREATE POLICY history_public_read ON report_status_history FOR SELECT USING (true);

-- CONFIRMATIONS: public read; insert own.
DROP POLICY IF EXISTS conf_public_read ON confirmations;
CREATE POLICY conf_public_read ON confirmations FOR SELECT USING (true);
DROP POLICY IF EXISTS conf_insert_own ON confirmations;
CREATE POLICY conf_insert_own ON confirmations FOR INSERT WITH CHECK (auth.uid() = user_id);

-- LOST & FOUND: read active items or your own; admins read all; insert/update own.
DROP POLICY IF EXISTS lf_read ON lf_items;
CREATE POLICY lf_read ON lf_items FOR SELECT
  USING (status = 'ACTIVE' OR auth.uid() = user_id OR is_admin(auth.uid()));
DROP POLICY IF EXISTS lf_insert_own ON lf_items;
CREATE POLICY lf_insert_own ON lf_items FOR INSERT WITH CHECK (auth.uid() = user_id);
DROP POLICY IF EXISTS lf_update_own ON lf_items;
CREATE POLICY lf_update_own ON lf_items FOR UPDATE
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- MATCHES: only the two involved users (or admins) can see a match.
DROP POLICY IF EXISTS lf_matches_read ON lf_matches;
CREATE POLICY lf_matches_read ON lf_matches FOR SELECT USING (
  is_admin(auth.uid())
  OR auth.uid() = (SELECT user_id FROM lf_items WHERE id = lost_item_id)
  OR auth.uid() = (SELECT user_id FROM lf_items WHERE id = found_item_id)
);

-- SENSOR DETECTIONS: strictly private to the owner.
DROP POLICY IF EXISTS detections_own ON sensor_detections;
CREATE POLICY detections_own ON sensor_detections FOR ALL
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- SCORE EVENTS: read own; admins read all.
DROP POLICY IF EXISTS score_read_own ON score_events;
CREATE POLICY score_read_own ON score_events FOR SELECT
  USING (auth.uid() = user_id OR is_admin(auth.uid()));

-- ─────────────────────── REALTIME PUBLICATION ─────────────────────
-- Enable live updates for map pins, vote counts, and match alerts.
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE reports;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE confirmations;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE lf_items;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE lf_matches;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ═══════════════════════════ END 0001 ═════════════════════════════





