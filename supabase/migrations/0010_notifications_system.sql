-- ═══════════════════════════════════════════════════════════════════
-- Nivara — 0010 Comprehensive Real-Time Notification System
-- Handles citizen, worker, and municipal official notifications.
-- ═══════════════════════════════════════════════════════════════════

-- 1. Create notifications table
CREATE TABLE IF NOT EXISTS notifications (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title       TEXT NOT NULL,
  body        TEXT NOT NULL,
  type        TEXT NOT NULL,
  payload     JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_read     BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at     TIMESTAMPTZ
);

-- 2. Indexes for fast retrieval
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON notifications (user_id, is_read, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_created
  ON notifications (created_at DESC);

-- 3. Row Level Security
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notifications_owner_select" ON notifications;
CREATE POLICY "notifications_owner_select" ON notifications
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "notifications_owner_update" ON notifications;
CREATE POLICY "notifications_owner_update" ON notifications
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "notifications_owner_delete" ON notifications;
CREATE POLICY "notifications_owner_delete" ON notifications
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "notifications_system_insert" ON notifications;
CREATE POLICY "notifications_system_insert" ON notifications
  FOR INSERT TO authenticated
  WITH CHECK (true);

-- 4. Enable Supabase Realtime for notifications table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
  END IF;
END $$;

-- 5. Helper functions to broadcast notifications
CREATE OR REPLACE FUNCTION notify_admins(
  p_title TEXT,
  p_body TEXT,
  p_type TEXT,
  p_payload JSONB DEFAULT '{}'::jsonb
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO notifications (user_id, title, body, type, payload)
  SELECT id, p_title, p_body, p_type, p_payload
  FROM user_profiles
  WHERE role::text IN ('ADMIN', 'SUPERADMIN');
END;
$$;

CREATE OR REPLACE FUNCTION notify_all_users(
  p_title TEXT,
  p_body TEXT,
  p_type TEXT,
  p_payload JSONB DEFAULT '{}'::jsonb
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO notifications (user_id, title, body, type, payload)
  SELECT id, p_title, p_body, p_type, p_payload
  FROM user_profiles;
END;
$$;

-- ───────────────────────────────────────────────────────────────────
-- 6. Trigger: Reports (Citizen & Worker & Admin notifications)
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_fn_reports_notifications()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- ON INSERT: Notify officials of newly submitted civic report
  IF TG_OP = 'INSERT' THEN
    PERFORM notify_admins(
      'New Civic Issue Reported',
      'A new ' || COALESCE(NEW.category::text, 'hazard') || ' report was submitted: "' || SUBSTRING(COALESCE(NEW.title, 'Civic Issue') FROM 1 FOR 50) || '"',
      'NEW_REPORT_SUBMITTED',
      jsonb_build_object('report_id', NEW.id, 'category', NEW.category::text, 'route', '/admin/report')
    );
    RETURN NEW;
  END IF;

  -- ON UPDATE:
  IF TG_OP = 'UPDATE' THEN
    -- Status progression notifications for citizen
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      IF NEW.status::text = 'ACKNOWLEDGED' AND NEW.user_id IS NOT NULL THEN
        INSERT INTO notifications (user_id, title, body, type, payload)
        VALUES (
          NEW.user_id,
          'Report Acknowledged',
          'Your report "' || SUBSTRING(COALESCE(NEW.title, 'Civic Issue') FROM 1 FOR 45) || '" has been officially acknowledged by municipal authorities.',
          'REPORT_ACKNOWLEDGED',
          jsonb_build_object('report_id', NEW.id, 'route', '/report/detail')
        );
      ELSIF NEW.status::text = 'IN_PROGRESS' AND NEW.user_id IS NOT NULL THEN
        INSERT INTO notifications (user_id, title, body, type, payload)
        VALUES (
          NEW.user_id,
          'Work In Progress',
          'A municipal crew is actively addressing your report: "' || SUBSTRING(COALESCE(NEW.title, 'Civic Issue') FROM 1 FOR 45) || '".',
          'REPORT_IN_PROGRESS',
          jsonb_build_object('report_id', NEW.id, 'route', '/report/detail')
        );
      ELSIF NEW.status::text = 'RESOLVED' AND NEW.user_id IS NOT NULL THEN
        INSERT INTO notifications (user_id, title, body, type, payload)
        VALUES (
          NEW.user_id,
          'Issue Resolved & Work Finished!',
          'Work is complete for "' || SUBSTRING(COALESCE(NEW.title, 'Civic Issue') FROM 1 FOR 45) || '". Tap to view the resolution details and proof.',
          'WORK_FINISHED',
          jsonb_build_object('report_id', NEW.id, 'route', '/report/detail')
        );
      ELSIF NEW.status::text = 'REJECTED' AND NEW.user_id IS NOT NULL THEN
        INSERT INTO notifications (user_id, title, body, type, payload)
        VALUES (
          NEW.user_id,
          'Report Status Update',
          'Your report "' || SUBSTRING(COALESCE(NEW.title, 'Civic Issue') FROM 1 FOR 45) || '" could not be processed at this time.',
          'REPORT_REJECTED',
          jsonb_build_object('report_id', NEW.id, 'route', '/report/detail')
        );
      END IF;
    END IF;

    -- Worker assignment: notify worker AND notify citizen
    IF NEW.assigned_to IS DISTINCT FROM OLD.assigned_to AND NEW.assigned_to IS NOT NULL THEN
      -- 1. Notify the assigned worker
      INSERT INTO notifications (user_id, title, body, type, payload)
      VALUES (
        NEW.assigned_to,
        'New Task Assigned to You',
        'You have been assigned to ' || COALESCE(NEW.category::text, 'civic task') || ': "' || SUBSTRING(COALESCE(NEW.title, 'Field Task') FROM 1 FOR 45) || '".',
        'WORK_ASSIGNED',
        jsonb_build_object('report_id', NEW.id, 'route', '/worker/task')
      );

      -- 2. Notify the citizen creator
      IF NEW.user_id IS NOT NULL AND NEW.user_id <> NEW.assigned_to THEN
        INSERT INTO notifications (user_id, title, body, type, payload)
        VALUES (
          NEW.user_id,
          'Worker Dispatched',
          'A field worker has been assigned to address your report "' || SUBSTRING(COALESCE(NEW.title, 'Civic Issue') FROM 1 FOR 45) || '".',
          'WORKER_ASSIGNED',
          jsonb_build_object('report_id', NEW.id, 'route', '/report/detail')
        );
      END IF;
    END IF;

    -- Admin requests progress update from worker
    IF NEW.progress_requested_at IS DISTINCT FROM OLD.progress_requested_at
       AND NEW.progress_requested_at IS NOT NULL
       AND NEW.assigned_to IS NOT NULL THEN
      INSERT INTO notifications (user_id, title, body, type, payload)
      VALUES (
        NEW.assigned_to,
        'Admin Requested Progress Update',
        'Municipal officials requested an update on task: "' || SUBSTRING(COALESCE(NEW.title, 'Field Task') FROM 1 FOR 45) || '".',
        'ADMIN_PROGRESS_REQUEST',
        jsonb_build_object('report_id', NEW.id, 'route', '/worker/task')
      );
    END IF;

    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_reports_notifications ON reports;
CREATE TRIGGER trg_reports_notifications
  AFTER INSERT OR UPDATE ON reports
  FOR EACH ROW
  EXECUTE FUNCTION trg_fn_reports_notifications();

-- ───────────────────────────────────────────────────────────────────
-- 7. Trigger: Worker Progress Notes (Citizen & Admin notifications)
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_fn_worker_progress_notifications()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_report_owner UUID;
  v_report_title TEXT;
BEGIN
  SELECT user_id, title INTO v_report_owner, v_report_title
  FROM reports WHERE id = NEW.report_id;

  -- 1. Notify the citizen author
  IF v_report_owner IS NOT NULL THEN
    INSERT INTO notifications (user_id, title, body, type, payload)
    VALUES (
      v_report_owner,
      'Field Progress Update',
      'Worker update on "' || SUBSTRING(COALESCE(v_report_title, 'Report') FROM 1 FOR 40) || '": ' || COALESCE(SUBSTRING(NEW.note FROM 1 FOR 65), 'New proof photo logged.'),
      'WORKER_PROGRESS',
      jsonb_build_object('report_id', NEW.report_id, 'note_id', NEW.id, 'route', '/report/detail')
    );
  END IF;

  -- 2. Notify municipal admins
  PERFORM notify_admins(
    'Field Worker Progress Note',
    'Progress update logged on "' || SUBSTRING(COALESCE(v_report_title, 'Report') FROM 1 FOR 40) || '": ' || COALESCE(SUBSTRING(NEW.note FROM 1 FOR 60), 'Photo attached.'),
    'WORKER_PROGRESS_ADMIN',
    jsonb_build_object('report_id', NEW.report_id, 'note_id', NEW.id, 'route', '/admin/report')
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_worker_progress_notifications ON worker_progress_notes;
CREATE TRIGGER trg_worker_progress_notifications
  AFTER INSERT ON worker_progress_notes
  FOR EACH ROW
  EXECUTE FUNCTION trg_fn_worker_progress_notifications();

-- ───────────────────────────────────────────────────────────────────
-- 8. Trigger: Lost & Found Matches
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_fn_lf_matches_notifications()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_lost_owner  UUID;
  v_lost_title  TEXT;
  v_found_owner UUID;
  v_found_title TEXT;
BEGIN
  SELECT user_id, title INTO v_lost_owner, v_lost_title FROM lf_items WHERE id = NEW.lost_id;
  SELECT user_id, title INTO v_found_owner, v_found_title FROM lf_items WHERE id = NEW.found_id;

  -- 1. Notify lost item owner
  IF v_lost_owner IS NOT NULL THEN
    INSERT INTO notifications (user_id, title, body, type, payload)
    VALUES (
      v_lost_owner,
      'Potential Match for Your Lost Item!',
      'A found item matches your "' || SUBSTRING(COALESCE(v_lost_title, 'Lost Item') FROM 1 FOR 40) || '" (' || ROUND(COALESCE(NEW.score, 0.85) * 100) || '% similarity).',
      'LF_MATCH',
      jsonb_build_object('match_id', NEW.id, 'lost_id', NEW.lost_id, 'found_id', NEW.found_id, 'route', '/lostfound/match')
    );
  END IF;

  -- 2. Notify found item owner
  IF v_found_owner IS NOT NULL AND v_found_owner <> v_lost_owner THEN
    INSERT INTO notifications (user_id, title, body, type, payload)
    VALUES (
      v_found_owner,
      'Lost & Found Match Detected',
      'An item reported lost closely matches your found listing: "' || SUBSTRING(COALESCE(v_found_title, 'Found Item') FROM 1 FOR 40) || '".',
      'LF_MATCH',
      jsonb_build_object('match_id', NEW.id, 'lost_id', NEW.lost_id, 'found_id', NEW.found_id, 'route', '/lostfound/match')
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lf_matches_notifications ON lf_matches;
CREATE TRIGGER trg_lf_matches_notifications
  AFTER INSERT ON lf_matches
  FOR EACH ROW
  EXECUTE FUNCTION trg_fn_lf_matches_notifications();

-- ───────────────────────────────────────────────────────────────────
-- 9. Trigger: Lost & Found Claims & Handover Intent
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_fn_lf_claims_notifications()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_item_title TEXT;
BEGIN
  SELECT title INTO v_item_title FROM lf_items WHERE id = NEW.item_id;

  -- ON INSERT: notify item owner that someone claimed it
  IF TG_OP = 'INSERT' THEN
    IF NEW.owner_id IS NOT NULL AND NEW.owner_id <> NEW.claimant_id THEN
      INSERT INTO notifications (user_id, title, body, type, payload)
      VALUES (
        NEW.owner_id,
        'Claim Received for Your Listing',
        'Someone claimed your listing "' || SUBSTRING(COALESCE(v_item_title, 'Item') FROM 1 FOR 40) || '": "' || COALESCE(SUBSTRING(NEW.message FROM 1 FOR 55), 'Claim verification requested.') || '"',
        'LF_CLAIM_RECEIVED',
        jsonb_build_object('claim_id', NEW.id, 'item_id', NEW.item_id, 'route', '/lostfound/mine')
      );
    END IF;
    RETURN NEW;
  END IF;

  -- ON UPDATE:
  IF TG_OP = 'UPDATE' THEN
    -- Handover intent (handover OTP / QR token generated)
    IF NEW.handover_otp IS DISTINCT FROM OLD.handover_otp AND NEW.handover_otp IS NOT NULL THEN
      -- Notify claimant
      IF NEW.claimant_id IS NOT NULL THEN
        INSERT INTO notifications (user_id, title, body, type, payload)
        VALUES (
          NEW.claimant_id,
          'Handover Pass Ready',
          'A secure verification pass has been generated for "' || SUBSTRING(COALESCE(v_item_title, 'Item') FROM 1 FOR 40) || '". Meet safely to complete verification.',
          'LF_HANDOVER_INTENT',
          jsonb_build_object('claim_id', NEW.id, 'item_id', NEW.item_id, 'route', '/lostfound/detail')
        );
      END IF;
      -- Notify owner
      IF NEW.owner_id IS NOT NULL AND NEW.owner_id <> NEW.claimant_id THEN
        INSERT INTO notifications (user_id, title, body, type, payload)
        VALUES (
          NEW.owner_id,
          'Handover Pass Active',
          'Verification pass generated for "' || SUBSTRING(COALESCE(v_item_title, 'Item') FROM 1 FOR 40) || '". Scan QR or enter 6-digit PIN during handover.',
          'LF_HANDOVER_INTENT',
          jsonb_build_object('claim_id', NEW.id, 'item_id', NEW.item_id, 'route', '/lostfound/detail')
        );
      END IF;
    END IF;

    -- Handover completion
    IF NEW.status::text = 'COMPLETED' AND OLD.status::text <> 'COMPLETED' THEN
      IF NEW.claimant_id IS NOT NULL THEN
        INSERT INTO notifications (user_id, title, body, type, payload)
        VALUES (
          NEW.claimant_id,
          'Item Handover Confirmed!',
          'Your claim for "' || SUBSTRING(COALESCE(v_item_title, 'Item') FROM 1 FOR 40) || '" has been successfully verified and completed.',
          'LF_HANDOVER_COMPLETED',
          jsonb_build_object('claim_id', NEW.id, 'item_id', NEW.item_id, 'route', '/lostfound/mine')
        );
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_lf_claims_notifications ON lf_claims;
CREATE TRIGGER trg_lf_claims_notifications
  AFTER INSERT OR UPDATE ON lf_claims
  FOR EACH ROW
  EXECUTE FUNCTION trg_fn_lf_claims_notifications();

-- ───────────────────────────────────────────────────────────────────
-- 10. Trigger: Community Posts (Announcements to all, posts to admins)
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_fn_community_posts_notifications()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.post_type::text = 'ANNOUNCEMENT' THEN
    -- Broadcast official announcement to all citizens
    PERFORM notify_all_users(
      '📢 City Announcement: ' || SUBSTRING(COALESCE(NEW.title, 'Notice') FROM 1 FOR 45),
      COALESCE(SUBSTRING(NEW.body FROM 1 FOR 80), 'New municipal announcement posted.'),
      'COMMUNITY_ANNOUNCEMENT',
      jsonb_build_object('post_id', NEW.id, 'route', '/home')
    );
  ELSE
    -- General community post: notify officials for awareness & moderation
    PERFORM notify_admins(
      'New Community Post',
      COALESCE(NEW.author_name, 'Citizen') || ' posted: "' || SUBSTRING(COALESCE(NEW.title, 'Post') FROM 1 FOR 50) || '"',
      'NEW_COMMUNITY_POST',
      jsonb_build_object('post_id', NEW.id, 'route', '/home')
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_community_posts_notifications ON community_posts;
CREATE TRIGGER trg_community_posts_notifications
  AFTER INSERT ON community_posts
  FOR EACH ROW
  EXECUTE FUNCTION trg_fn_community_posts_notifications();

-- ───────────────────────────────────────────────────────────────────
-- 11. Trigger: Worker Applications (Admin notification & status update)
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_fn_worker_applications_notifications()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM notify_admins(
      'New Field Worker Application',
      'A citizen has submitted an application to join the municipal field workforce.',
      'NEW_WORKER_APPLICATION',
      jsonb_build_object('application_id', NEW.id, 'route', '/admin')
    );
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.status IS DISTINCT FROM OLD.status AND NEW.user_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, title, body, type, payload)
      VALUES (
        NEW.user_id,
        'Worker Application ' || NEW.status,
        CASE
          WHEN NEW.status = 'APPROVED' THEN 'Congratulations! Your field worker application has been APPROVED. You now have field worker privileges.'
          ELSE 'Your field worker application was reviewed and not accepted at this time.'
        END,
        'WORKER_APPLICATION_STATUS',
        jsonb_build_object('application_id', NEW.id, 'status', NEW.status, 'route', '/profile')
      );
    END IF;
    RETURN NEW;
  END IF;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_worker_applications_notifications ON worker_applications;
CREATE TRIGGER trg_worker_applications_notifications
  AFTER INSERT OR UPDATE ON worker_applications
  FOR EACH ROW
  EXECUTE FUNCTION trg_fn_worker_applications_notifications();

-- ───────────────────────────────────────────────────────────────────
-- 12. Trigger: Worker On Leave & Resignation (Admin notification)
-- ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trg_fn_user_profiles_notifications()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Worker marked on leave
  IF NEW.is_on_leave = TRUE AND (OLD.is_on_leave = FALSE OR OLD.is_on_leave IS NULL) THEN
    PERFORM notify_admins(
      'Worker On Leave',
      COALESCE(NEW.display_name, 'Field Worker') || ' has marked themselves on leave.',
      'WORKER_ON_LEAVE',
      jsonb_build_object('worker_id', NEW.id, 'route', '/admin')
    );
  END IF;

  -- Worker resigned
  IF NEW.resigned_at IS NOT NULL AND OLD.resigned_at IS NULL THEN
    PERFORM notify_admins(
      'Worker Resigned',
      COALESCE(NEW.display_name, 'Field Worker') || ' has submitted their resignation.',
      'WORKER_RESIGNED',
      jsonb_build_object('worker_id', NEW.id, 'route', '/admin')
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_profiles_notifications ON user_profiles;
CREATE TRIGGER trg_user_profiles_notifications
  AFTER UPDATE ON user_profiles
  FOR EACH ROW
  EXECUTE FUNCTION trg_fn_user_profiles_notifications();

-- ═══════════════════════════════════════ END 0010 ═════════════════
