-- ═══════════════════════════════════════════════════════════════════
-- Nivara — Staff / Field-worker side + report Assignment (M2)
-- Run in the Supabase SQL editor AFTER 0001_init.sql.
--
-- Adds a WORKER role, staff helpers, and two SECURITY DEFINER RPCs:
--   • admin_assign_report      — an official hands a report to a worker
--   • worker_set_report_status — the assigned worker advances it with proof
--
-- `reports.assigned_to` already exists in 0001, so no column change needed.
-- All role checks compare role::text (never the bare 'WORKER' enum literal)
-- so this file is safe to run in one transaction even though it also ADDs
-- that enum value — a literal would trip "unsafe use of new value".
-- ═══════════════════════════════════════════════════════════════════

-- New role for municipal field staff who only see work assigned to them.
ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'WORKER';

-- ─────────────────────── ROLE HELPERS ─────────────────────────────
-- Any municipal account (office or field). SECURITY DEFINER to read the
-- role without tripping user_profiles' own RLS. Text compare avoids the
-- new-enum-value validation hazard described in the header.
CREATE OR REPLACE FUNCTION is_staff(uid UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_profiles
    WHERE id = uid AND role::text IN ('ADMIN', 'SUPERADMIN', 'WORKER')
  );
$$;

CREATE OR REPLACE FUNCTION is_worker(uid UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_profiles
    WHERE id = uid AND role::text = 'WORKER'
  );
$$;

-- ─────────── RPC: official assigns a report to a worker ────────────
-- Officials (ADMIN/SUPERADMIN) only. Sets assigned_to, routes the report
-- to the worker's department, nudges a still-new report to ACKNOWLEDGED,
-- and records the hand-off in the audit trail.
CREATE OR REPLACE FUNCTION admin_assign_report(
  p_report_id UUID,
  p_worker_id UUID,
  p_note TEXT DEFAULT NULL
) RETURNS reports LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_row        reports;
  v_old        report_status;
  v_worker     user_profiles;
  v_new_status report_status;
BEGIN
  IF NOT is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only officials can assign reports';
  END IF;

  SELECT * INTO v_worker FROM user_profiles WHERE id = p_worker_id;
  IF NOT FOUND OR v_worker.role::text <> 'WORKER' THEN
    RAISE EXCEPTION 'Assignee must be a field worker';
  END IF;

  SELECT status INTO v_old FROM reports WHERE id = p_report_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Report % not found', p_report_id;
  END IF;

  -- A brand-new report becomes ACKNOWLEDGED the moment it is assigned.
  v_new_status := CASE WHEN v_old = 'SUBMITTED' THEN 'ACKNOWLEDGED'::report_status
                       ELSE v_old END;

  UPDATE reports SET
    assigned_to         = p_worker_id,
    assigned_department = COALESCE(v_worker.department, assigned_department),
    status              = v_new_status,
    acknowledged_at     = COALESCE(acknowledged_at, NOW()),
    acknowledged_by     = COALESCE(acknowledged_by, auth.uid())
  WHERE id = p_report_id
  RETURNING * INTO v_row;

  INSERT INTO report_status_history (report_id, changed_by, old_status, new_status, note)
  VALUES (
    p_report_id, auth.uid(), v_old, v_new_status,
    COALESCE(p_note, 'Assigned to ' || COALESCE(v_worker.display_name, 'a worker'))
  );

  RETURN v_row;
END;
$$;

-- ─────────── RPC: assigned worker advances their report ────────────
-- The worker the report is assigned to (and only them) may move it to
-- IN_PROGRESS or RESOLVED, attaching a resolution note + proof photo.
-- Mirrors admin_set_report_status' stamping + audit trail.
CREATE OR REPLACE FUNCTION worker_set_report_status(
  p_report_id  UUID,
  p_new_status report_status,
  p_note       TEXT DEFAULT NULL,
  p_photo_url  TEXT DEFAULT NULL
) RETURNS reports LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_row reports;
  v_old report_status;
  v_assignee UUID;
BEGIN
  IF p_new_status NOT IN ('IN_PROGRESS'::report_status, 'RESOLVED'::report_status) THEN
    RAISE EXCEPTION 'Workers may only start or resolve a task';
  END IF;

  SELECT status, assigned_to INTO v_old, v_assignee
  FROM reports WHERE id = p_report_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Report % not found', p_report_id;
  END IF;
  IF v_assignee IS NULL OR v_assignee <> auth.uid() THEN
    RAISE EXCEPTION 'This task is not assigned to you';
  END IF;

  UPDATE reports SET
    status           = p_new_status,
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

GRANT EXECUTE ON FUNCTION is_staff(UUID)            TO authenticated;
GRANT EXECUTE ON FUNCTION is_worker(UUID)           TO authenticated;
GRANT EXECUTE ON FUNCTION admin_assign_report(UUID, UUID, TEXT)                 TO authenticated;
GRANT EXECUTE ON FUNCTION worker_set_report_status(UUID, report_status, TEXT, TEXT) TO authenticated;

-- ═══════════════════════════ END 0006 ═════════════════════════════
