-- 0003_lf_realtime.sql
-- ─────────────────────────────────────────────────────────────────
-- Enable Supabase Realtime for `lf_items`.
--
-- The original 0001_init added `reports`, `confirmations`, and `lf_matches`
-- to the `supabase_realtime` publication but MISSED `lf_items`. As a result
-- the Lost & Found hub feed and the Lost & Found map pins (both of which
-- `.stream()` from lf_items) raised a RealtimeSubscribeException and showed
-- an error/empty state on device.
--
-- 0001 has since been corrected for fresh installs; this standalone migration
-- brings ALREADY-DEPLOYED databases up to date. Safe to run more than once —
-- the duplicate_object guard turns a re-add into a no-op.
--
-- Apply: paste into the Supabase SQL editor and run, or `supabase db push`.
-- ─────────────────────────────────────────────────────────────────

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE lf_items;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
