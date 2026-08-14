-- ═══════════════════════════════════════════════════════════════════
-- Nivara — Workers, Progress Tracking & Applications (M3)
-- Run in the Supabase SQL editor AFTER 0006_staff_worker.sql.
--
-- Adds:
--   • Worker profile metadata  (is_on_leave, worker_number, resigned_at)
--   • Worker progress notes table
--   • Worker applications table (citizen → worker request)
--   • Admin progress-request field on reports
--   • New RPCs: admin_request_progress, worker_send_progress,
--               worker_go_on_leave, worker_mark_available,
--               worker_resign, admin_create_worker, admin_remove_worker,
--               submit_worker_application, admin_review_application
--   • Admin can delete community posts (new RPC)
-- ═══════════════════════════════════════════════════════════════════

-- ─── Worker profile extensions ──────────────────────────────────────
ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS is_on_leave    BOOLEAN   DEFAULT FALSE NOT NULL,
  ADD COLUMN IF NOT EXISTS worker_number  INT,
  ADD COLUMN IF NOT EXISTS resigned_at    TIMESTAMPTZ;

-- ─── Progress request on reports ────────────────────────────────────
ALTER TABLE reports
  ADD COLUMN IF NOT EXISTS progress_requested_at TIMESTAMPTZ;

-- ─── Worker progress notes ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS worker_progress_notes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  report_id   UUID NOT NULL REFERENCES reports(id) ON DELETE CASCADE,
  worker_id   UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  note        TEXT,
  photo_url   TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

ALTER TABLE worker_progress_notes ENABLE ROW LEVEL SECURITY;

-- Workers can insert/read their own notes; admins read all
CREATE POLICY "worker_own_notes" ON worker_progress_notes
  FOR ALL TO authenticated
  USING (
    worker_id = auth.uid()
    OR is_admin(auth.uid())
  )
  WITH CHECK (worker_id = auth.uid());

-- ─── Worker applications ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS worker_applications (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  message     TEXT,
  status      TEXT DEFAULT 'PENDING' NOT NULL,  -- PENDING | APPROVED | REJECTED
  reviewed_by UUID REFERENCES user_profiles(id),
  reviewed_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

ALTER TABLE worker_applications ENABLE ROW LEVEL SECURITY;

-- Citizens can insert and read their own; admins read all
CREATE POLICY "application_access" ON worker_applications
  FOR ALL TO authenticated
  USING (
    user_id = auth.uid()
    OR is_admin(auth.uid())
  )
  WITH CHECK (user_id = auth.uid());

-- ─── RPC: admin requests progress update ─────────────────────────────
CREATE OR REPLACE FUNCTION admin_request_progress(
  p_report_id UUID
) RETURNS reports LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_row reports;
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only officials can request progress';
  END IF;
  UPDATE reports
    SET progress_requested_at = NOW()
    WHERE id = p_report_id
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Report % not found', p_report_id;
  END IF;
  RETURN v_row;
END;
$$;

-- ─── RPC: worker sends a custom progress note ────────────────────────
CREATE OR REPLACE FUNCTION worker_send_progress(
  p_report_id UUID,
  p_note      TEXT DEFAULT NULL,
  p_photo_url TEXT DEFAULT NULL
) RETURNS worker_progress_notes LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_row      worker_progress_notes;
  v_assignee UUID;
BEGIN
  SELECT assigned_to INTO v_assignee FROM reports WHERE id = p_report_id;
  IF v_assignee IS NULL OR v_assignee <> auth.uid() THEN
    RAISE EXCEPTION 'This task is not assigned to you';
  END IF;
  INSERT INTO worker_progress_notes (report_id, worker_id, note, photo_url)
  VALUES (p_report_id, auth.uid(), p_note, p_photo_url)
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- ─── RPC: worker marks themselves on leave ────────────────────────────
CREATE OR REPLACE FUNCTION worker_go_on_leave()
RETURNS user_profiles LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_row user_profiles;
BEGIN
  IF NOT is_worker(auth.uid()) THEN
    RAISE EXCEPTION 'Only field workers can set leave status';
  END IF;
  UPDATE user_profiles SET is_on_leave = TRUE WHERE id = auth.uid()
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- ─── RPC: worker marks themselves available again ─────────────────────
CREATE OR REPLACE FUNCTION worker_mark_available()
RETURNS user_profiles LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_row user_profiles;
BEGIN
  IF NOT is_worker(auth.uid()) THEN
    RAISE EXCEPTION 'Only field workers can set availability';
  END IF;
  UPDATE user_profiles SET is_on_leave = FALSE WHERE id = auth.uid()
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- ─── RPC: worker resigns ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION worker_resign()
RETURNS user_profiles LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_row user_profiles;
BEGIN
  IF NOT is_worker(auth.uid()) THEN
    RAISE EXCEPTION 'Only field workers can resign';
  END IF;
  UPDATE user_profiles
    SET resigned_at = NOW(), role = 'CITIZEN'::user_role
    WHERE id = auth.uid()
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- ─── RPC: admin soft-removes a worker ────────────────────────────────
CREATE OR REPLACE FUNCTION admin_remove_worker(
  p_worker_id UUID
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only officials can remove workers';
  END IF;
  UPDATE user_profiles
    SET resigned_at = NOW(), role = 'CITIZEN'::user_role
    WHERE id = p_worker_id AND role::text = 'WORKER';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Worker % not found', p_worker_id;
  END IF;
END;
$$;

-- ─── RPC: citizen submits a worker application ────────────────────────
CREATE OR REPLACE FUNCTION submit_worker_application(
  p_message TEXT DEFAULT NULL
) RETURNS worker_applications LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_row worker_applications;
  v_existing UUID;
BEGIN
  -- Prevent duplicate pending applications
  SELECT id INTO v_existing
    FROM worker_applications
    WHERE user_id = auth.uid() AND status = 'PENDING';
  IF FOUND THEN
    RAISE EXCEPTION 'You already have a pending application';
  END IF;
  INSERT INTO worker_applications (user_id, message)
  VALUES (auth.uid(), p_message)
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- ─── RPC: admin reviews application (approve/reject) ─────────────────
CREATE OR REPLACE FUNCTION admin_review_application(
  p_application_id UUID,
  p_status         TEXT  -- 'APPROVED' or 'REJECTED'
) RETURNS worker_applications LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE v_row worker_applications;
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only officials can review applications';
  END IF;
  IF p_status NOT IN ('APPROVED', 'REJECTED') THEN
    RAISE EXCEPTION 'Status must be APPROVED or REJECTED';
  END IF;
  UPDATE worker_applications
    SET status = p_status, reviewed_by = auth.uid(), reviewed_at = NOW()
    WHERE id = p_application_id
  RETURNING * INTO v_row;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Application % not found', p_application_id;
  END IF;
  RETURN v_row;
END;
$$;

-- ─── RPC: admin deletes a community post ─────────────────────────────
CREATE OR REPLACE FUNCTION admin_delete_community_post(
  p_post_id UUID
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only officials can delete any community post';
  END IF;
  DELETE FROM community_posts WHERE id = p_post_id;
END;
$$;

-- ─── Grants ───────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION admin_request_progress(UUID)                      TO authenticated;
GRANT EXECUTE ON FUNCTION worker_send_progress(UUID, TEXT, TEXT)            TO authenticated;
GRANT EXECUTE ON FUNCTION worker_go_on_leave()                              TO authenticated;
GRANT EXECUTE ON FUNCTION worker_mark_available()                           TO authenticated;
GRANT EXECUTE ON FUNCTION worker_resign()                                   TO authenticated;
GRANT EXECUTE ON FUNCTION admin_remove_worker(UUID)                         TO authenticated;
GRANT EXECUTE ON FUNCTION submit_worker_application(TEXT)                   TO authenticated;
GRANT EXECUTE ON FUNCTION admin_review_application(UUID, TEXT)              TO authenticated;
GRANT EXECUTE ON FUNCTION admin_delete_community_post(UUID)                 TO authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- Realtime for progress notes (optional — enable in Supabase dashboard)
-- ALTER PUBLICATION supabase_realtime ADD TABLE worker_progress_notes;
-- ALTER PUBLICATION supabase_realtime ADD TABLE worker_applications;
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════ END 0007 ═════════════════
