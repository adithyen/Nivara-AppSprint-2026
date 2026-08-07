> ⚠️ **SUPERSEDED — HISTORICAL REFERENCE (2026-08-08).**
> This is the original schema **before** role-based access (no `user_role`, no
> admin "mark fixed" flow, no status-history audit, no admin RLS). The **source of
> truth is the migration**
> [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql), which
> adds roles/admin, `admin_set_report_status`, `set_user_role`,
> `report_status_history`, full RLS, and the Realtime publication. See also
> [`09_ADMIN_AND_AUTH.md`](09_ADMIN_AND_AUTH.md). **Do not build from this file.**

# Nivara — Database Schema
**Engine:** PostgreSQL (Supabase) with PostGIS extension

> ⚠️ **SUPERSEDED BY THE MIGRATION (2026-08-08).** The authoritative, runnable
> schema now lives in **`supabase/migrations/0001_init.sql`**. It extends the
> SQL below with the **role-based user/admin model**: a `user_role`
> (CITIZEN/ADMIN/SUPERADMIN) and `admin_department` enum, admin/jurisdiction
> columns + auto-department routing on `reports`, a `report_status_history`
> audit table, `is_admin()/is_superadmin()` helpers, the
> `admin_set_report_status()` and `set_user_role()` RPCs, an auto profile-creation
> trigger, admin RLS policies, and a safe `public_profiles` view. See
> **`09_ADMIN_AND_AUTH.md`** for the design. The listing below is kept for
> narrative context; run the migration, not this.

---

## Full SQL Schema

```sql
-- ─────────────────────────────────────────────────────────────────
-- EXTENSIONS
-- ─────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS postgis;      -- spatial queries
CREATE EXTENSION IF NOT EXISTS pg_trgm;     -- text similarity for matching

-- ─────────────────────────────────────────────────────────────────
-- ENUMS
-- ─────────────────────────────────────────────────────────────────
CREATE TYPE report_category AS ENUM (
  'POTHOLE', 'BROKEN_FOOTPATH', 'OPEN_MANHOLE', 'FALLEN_TREE',
  'WATERLOGGING', 'ROAD_SIGN', 'GARBAGE', 'BLOCKED_DRAIN',
  'SEWAGE', 'STREET_LIGHT', 'DAMAGED_POLE', 'POWER_ISSUE',
  'WATER_SUPPLY', 'PIPE_LEAK', 'ENCROACHMENT', 'BROKEN_PROPERTY',
  'STRAY_ANIMALS', 'NOISE', 'OTHER'
);

CREATE TYPE report_status AS ENUM (
  'SUBMITTED', 'ACKNOWLEDGED', 'IN_PROGRESS', 'RESOLVED', 'CLOSED', 'DUPLICATE'
);

CREATE TYPE severity AS ENUM ('LOW', 'MEDIUM', 'HIGH', 'EMERGENCY');

CREATE TYPE detection_type AS ENUM ('POTHOLE', 'SPEED_BREAKER', 'BAD_ROAD', 'MANUAL');

CREATE TYPE lf_category AS ENUM (
  'AADHAAR', 'PAN_CARD', 'DRIVING_LICENCE', 'PASSPORT', 'OTHER_DOCUMENT',
  'MOBILE_PHONE', 'WALLET', 'KEYS', 'BAG', 'JEWELLERY', 'PET', 'VEHICLE', 'OTHER'
);

CREATE TYPE lf_item_type AS ENUM ('LOST', 'FOUND');

CREATE TYPE match_status AS ENUM ('PENDING', 'CONFIRMED_BY_FINDER', 'CONFIRMED_BY_BOTH', 'REJECTED', 'RESOLVED');

-- ─────────────────────────────────────────────────────────────────
-- USER PROFILES
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE user_profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name  TEXT NOT NULL,
  avatar_url    TEXT,
  phone         TEXT,
  city          TEXT,                          -- "Thiruvananthapuram"
  ward          TEXT,                          -- "Ward 45"
  civic_score   INTEGER DEFAULT 0,
  reports_count INTEGER DEFAULT 0,
  finds_count   INTEGER DEFAULT 0,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────
-- CIVIC REPORTS (complaints)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE reports (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES user_profiles(id) ON DELETE SET NULL,
  category          report_category NOT NULL,
  status            report_status DEFAULT 'SUBMITTED',
  severity          severity DEFAULT 'MEDIUM',
  title             TEXT,                        -- auto-generated or user-provided
  description       TEXT,
  location          GEOGRAPHY(POINT, 4326) NOT NULL,  -- PostGIS point
  lat               DOUBLE PRECISION NOT NULL,
  lng               DOUBLE PRECISION NOT NULL,
  address           TEXT,                        -- reverse geocoded
  city              TEXT,
  ward              TEXT,

  -- Source tracking
  source            TEXT DEFAULT 'MANUAL',       -- 'SENSORWATCH' | 'MANUAL'
  detection_type    detection_type,
  evidence_package  JSONB,                       -- full evidence package with hash
  evidence_hash     TEXT,                        -- SHA-256 hash (redundant for fast lookup)

  -- Photos
  photo_urls        TEXT[],

  -- Community
  confirmation_count INTEGER DEFAULT 0,
  resolved_count    INTEGER DEFAULT 0,
  is_community_verified BOOLEAN DEFAULT FALSE,

  -- Resolution
  resolved_at       TIMESTAMPTZ,
  resolution_notes  TEXT,
  resolution_photo  TEXT,

  created_at        TIMESTAMPTZ DEFAULT NOW(),
  updated_at        TIMESTAMPTZ DEFAULT NOW()
);

-- Spatial index for map queries
CREATE INDEX idx_reports_location ON reports USING GIST (location);
-- Category + status index for filtered map view
CREATE INDEX idx_reports_city_status ON reports (city, status, category);
-- Time-based index for feed
CREATE INDEX idx_reports_created ON reports (created_at DESC);

-- ─────────────────────────────────────────────────────────────────
-- CONFIRMATIONS (community verification)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE confirmations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id   UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES user_profiles(id),
  type        TEXT DEFAULT 'CONFIRM',            -- 'CONFIRM' | 'RESOLVED'
  location    GEOGRAPHY(POINT, 4326),            -- where user was when confirming
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (report_id, user_id, type)              -- one confirmation per user per type
);

-- Trigger: update confirmation_count on reports when confirmation added
CREATE OR REPLACE FUNCTION update_confirmation_count()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE reports
  SET
    confirmation_count = (SELECT COUNT(*) FROM confirmations WHERE report_id = NEW.report_id AND type = 'CONFIRM'),
    resolved_count = (SELECT COUNT(*) FROM confirmations WHERE report_id = NEW.report_id AND type = 'RESOLVED'),
    is_community_verified = (
      SELECT COUNT(*) >= 5 FROM confirmations WHERE report_id = NEW.report_id AND type = 'CONFIRM'
    ),
    status = CASE
      WHEN (SELECT COUNT(*) >= 3 FROM confirmations WHERE report_id = NEW.report_id AND type = 'RESOLVED')
        THEN 'RESOLVED'::report_status
      ELSE status
    END
  WHERE id = NEW.report_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER confirmation_count_trigger
AFTER INSERT ON confirmations
FOR EACH ROW EXECUTE FUNCTION update_confirmation_count();

-- ─────────────────────────────────────────────────────────────────
-- SENSOR DETECTIONS (raw log, even if not reported)
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE sensor_detections (
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

CREATE INDEX idx_detections_location ON sensor_detections USING GIST (location);

-- Road quality: aggregate detections per 50m grid for heatmap
CREATE MATERIALIZED VIEW road_quality_grid AS
SELECT
  ST_SnapToGrid(location::geometry, 0.0005) AS grid_cell,  -- ~50m grid
  AVG(accel_z_peak - accel_z_baseline) AS avg_severity,
  COUNT(*) AS event_count,
  MAX(detected_at) AS last_event
FROM sensor_detections
WHERE detected_at > NOW() - INTERVAL '30 days'
GROUP BY grid_cell;

-- ─────────────────────────────────────────────────────────────────
-- LOST & FOUND ITEMS
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE lf_items (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES user_profiles(id),
  item_type        lf_item_type NOT NULL,          -- LOST | FOUND
  category         lf_category NOT NULL,
  title            TEXT NOT NULL,                   -- "Blue iPhone 14 Pro"
  description      TEXT NOT NULL,
  photo_urls       TEXT[],

  -- For LOST items: where it was last seen
  -- For FOUND items: where it was found (fuzzy-displayed to public)
  lat              DOUBLE PRECISION NOT NULL,
  lng              DOUBLE PRECISION NOT NULL,
  location         GEOGRAPHY(POINT, 4326) NOT NULL,
  location_label   TEXT,                            -- "Near Central Station, Trivandrum"
  event_date       DATE NOT NULL,                   -- when lost/found

  -- Contact
  contact_method   TEXT DEFAULT 'INAPP',            -- 'PHONE' | 'WHATSAPP' | 'INAPP'
  contact_phone    TEXT,
  reward_amount    INTEGER,                          -- ₹ reward offered (for LOST items)

  -- Status
  status           TEXT DEFAULT 'ACTIVE',           -- 'ACTIVE' | 'MATCHED' | 'RESOLVED' | 'EXPIRED'
  expires_at       TIMESTAMPTZ DEFAULT NOW() + INTERVAL '30 days',

  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_lf_location ON lf_items USING GIST (location);
CREATE INDEX idx_lf_category_type ON lf_items (category, item_type, status);
CREATE INDEX idx_lf_city_expires ON lf_items (status, expires_at);

-- Full-text search on description
CREATE INDEX idx_lf_description_fts ON lf_items USING GIN (to_tsvector('english', description));

-- ─────────────────────────────────────────────────────────────────
-- LOST-FOUND MATCHES
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE lf_matches (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lost_item_id  UUID NOT NULL REFERENCES lf_items(id) ON DELETE CASCADE,
  found_item_id UUID NOT NULL REFERENCES lf_items(id) ON DELETE CASCADE,
  match_score   INTEGER NOT NULL,                  -- 0-100
  status        match_status DEFAULT 'PENDING',
  confirmed_at  TIMESTAMPTZ,
  resolved_at   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────
-- CIVIC SCORE LEDGER
-- ─────────────────────────────────────────────────────────────────
CREATE TABLE score_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES user_profiles(id),
  event_type  TEXT NOT NULL,   -- 'REPORT_SUBMITTED', 'CONFIRMED_BY_COMMUNITY', 'ITEM_FOUND_MATCH' etc.
  points      INTEGER NOT NULL,
  reference_id UUID,           -- report_id or lf_match_id
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────
-- SPATIAL FUNCTION: Find nearby lost/found items
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION find_nearby_items(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_radius_km DOUBLE PRECISION,
  p_category lf_category,
  p_item_type lf_item_type,
  p_within_days INTEGER
) RETURNS TABLE (
  id UUID, category lf_category, title TEXT, description TEXT,
  lat DOUBLE PRECISION, lng DOUBLE PRECISION,
  event_date DATE, created_at TIMESTAMPTZ,
  distance_km DOUBLE PRECISION
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    i.id, i.category, i.title, i.description,
    i.lat, i.lng, i.event_date, i.created_at,
    ST_Distance(i.location, ST_Point(p_lng, p_lat)::geography) / 1000.0 AS distance_km
  FROM lf_items i
  WHERE
    i.item_type = p_item_type
    AND i.category = p_category
    AND i.status = 'ACTIVE'
    AND i.event_date >= CURRENT_DATE - p_within_days
    AND ST_DWithin(
      i.location,
      ST_Point(p_lng, p_lat)::geography,
      p_radius_km * 1000
    )
  ORDER BY distance_km ASC
  LIMIT 20;
END;
$$ LANGUAGE plpgsql;

-- ─────────────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────────────────────────────
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE confirmations ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE lf_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensor_detections ENABLE ROW LEVEL SECURITY;

-- Reports: PUBLIC READ (everyone sees civic reports); write only own
CREATE POLICY "public_read_reports" ON reports FOR SELECT USING (true);
CREATE POLICY "own_insert_reports" ON reports FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "own_update_reports" ON reports FOR UPDATE USING (auth.uid() = user_id);

-- Lost & Found: PUBLIC READ for active items
CREATE POLICY "public_read_lf" ON lf_items FOR SELECT USING (status = 'ACTIVE' OR auth.uid() = user_id);
CREATE POLICY "own_insert_lf" ON lf_items FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Sensor detections: PRIVATE (only user sees their own)
CREATE POLICY "own_detections" ON sensor_detections FOR ALL USING (auth.uid() = user_id);

-- Confirmations: public read, own write
CREATE POLICY "public_read_confirmations" ON confirmations FOR SELECT USING (true);
CREATE POLICY "own_insert_confirmations" ON confirmations FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Matches: only the involved users see their match
CREATE POLICY "own_matches" ON lf_matches FOR SELECT
  USING (
    auth.uid() = (SELECT user_id FROM lf_items WHERE id = lost_item_id)
    OR auth.uid() = (SELECT user_id FROM lf_items WHERE id = found_item_id)
  );
```

---

## Supabase Realtime Configuration

Enable Realtime on these tables in Supabase Dashboard → Database → Replication:
- `reports` — for live map pins
- `confirmations` — for live vote counts
- `lf_matches` — for instant match notifications
