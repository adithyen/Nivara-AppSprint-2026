-- ══════════════════ 0011 FIX CONFIRMATION COUNT TRIGGER ══════════════════
-- Ensure the confirmation trigger executes with SECURITY DEFINER so that
-- any authenticated citizen confirming a report can automatically update
-- the target report's confirmation_count and community-verified status
-- without being blocked by RLS policies on reports.

CREATE OR REPLACE FUNCTION update_confirmation_count()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
LANGUAGE plpgsql AS $$
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
