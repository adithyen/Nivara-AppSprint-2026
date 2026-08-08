-- ═══════════════════════════ 0002 STORAGE ═════════════════════════
-- Public bucket for CivicReport complaint photos. Photos are attached to
-- reports filed manually; SensorWatch reports are photo-free (evidence is the
-- sensor package). Reports themselves are world-readable for the civic map, so
-- their photos are public-read too. Writes are restricted to the owner's own
-- folder (path prefix = auth uid), matching report_form_screen.dart which
-- uploads to `<uid>/<timestamp>_<i>.jpg`.

-- Create the bucket (idempotent). public = true so getPublicUrl() resolves
-- without a signed URL.
INSERT INTO storage.buckets (id, name, public)
VALUES ('complaint-photos', 'complaint-photos', true)
ON CONFLICT (id) DO UPDATE SET public = EXCLUDED.public;

-- READ: anyone (including anon) may view complaint photos.
DROP POLICY IF EXISTS complaint_photos_read ON storage.objects;
CREATE POLICY complaint_photos_read ON storage.objects FOR SELECT
  USING (bucket_id = 'complaint-photos');

-- INSERT: a signed-in user may upload only into their own top-level folder,
-- i.e. the first path segment must equal their auth uid.
DROP POLICY IF EXISTS complaint_photos_insert_own ON storage.objects;
CREATE POLICY complaint_photos_insert_own ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'complaint-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- UPDATE/DELETE: owner-only (supports upsert overwrites and cleanup).
DROP POLICY IF EXISTS complaint_photos_modify_own ON storage.objects;
CREATE POLICY complaint_photos_modify_own ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'complaint-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'complaint-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS complaint_photos_delete_own ON storage.objects;
CREATE POLICY complaint_photos_delete_own ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'complaint-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ═══════════════════════════ END 0002 ═════════════════════════════
