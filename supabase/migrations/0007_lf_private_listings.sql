-- ─────────────────────────────────────────────────────────────────────────
-- 0007_lf_private_listings.sql — Confidential Radar-Only Lost & Found Mode
--
-- Run in the Supabase SQL editor (or `supabase db push`). Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────

-- 1. Add `is_private` flag to lf_items (defaults to false / public).
ALTER TABLE lf_items ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX IF NOT EXISTS idx_lf_items_private ON lf_items (is_private);

-- 2. Update find_nearby_items to include `is_private` in returned fields.
DROP FUNCTION IF EXISTS find_nearby_items(
  DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION,
  lf_category, lf_item_type, INTEGER
);

CREATE OR REPLACE FUNCTION find_nearby_items(
  p_lat DOUBLE PRECISION, p_lng DOUBLE PRECISION,
  p_radius_km DOUBLE PRECISION, p_category lf_category,
  p_item_type lf_item_type, p_within_days INTEGER
) RETURNS TABLE (
  id UUID, user_id UUID, item_type lf_item_type, category lf_category,
  title TEXT, description TEXT, photo_urls TEXT[],
  lat DOUBLE PRECISION, lng DOUBLE PRECISION, location_label TEXT,
  event_date DATE, contact_method TEXT, contact_value TEXT,
  contact_phone TEXT, reward_amount INTEGER, is_private BOOLEAN,
  created_at TIMESTAMPTZ, distance_km DOUBLE PRECISION
) LANGUAGE plpgsql STABLE AS $$
BEGIN
  RETURN QUERY
  SELECT i.id, i.user_id, i.item_type, i.category,
         i.title, i.description, i.photo_urls,
         i.lat, i.lng, i.location_label,
         i.event_date, i.contact_method, i.contact_value,
         i.contact_phone, i.reward_amount, i.is_private, i.created_at,
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
