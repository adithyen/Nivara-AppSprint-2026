-- ═══════════════════════════════════════════════════════════════════
-- Nivara — Re-seed pothole_worker1 (Roads Department)
-- Run this in your Supabase SQL Editor if pothole_worker1 got deleted.
--
-- Email    : pothole_worker1@nivara.app
-- Password : worker123
-- Role     : WORKER
-- Dept     : ROADS
-- ═══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  _pass  TEXT := crypt('worker123', gen_salt('bf'));
  _uid   UUID := gen_random_uuid();
  _now   TIMESTAMPTZ := NOW();
  _email TEXT := 'pothole_worker1@nivara.app';
  _name  TEXT := 'Pothole Worker 1';
BEGIN
  -- 1. Remove any orphaned user_profile row with this email if present
  DELETE FROM user_profiles WHERE id IN (SELECT id FROM auth.users WHERE email = _email);
  DELETE FROM auth.identities WHERE user_id IN (SELECT id FROM auth.users WHERE email = _email);
  DELETE FROM auth.users WHERE email = _email;

  -- 2. Create the auth.users row
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, last_sign_in_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, created_at, updated_at,
    confirmation_token, recovery_token,
    email_change_token_new, email_change,
    is_sso_user, deleted_at
  ) VALUES (
    _uid,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    _email, _pass,
    _now, _now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    json_build_object('display_name', _name)::jsonb,
    FALSE, _now, _now,
    '', '', '', '',
    FALSE, NULL
  );

  -- 3. Create the auth.identities row (Required for password login in Supabase)
  INSERT INTO auth.identities (
    id, provider_id, user_id, identity_data,
    provider, last_sign_in_at, created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    _email,
    _uid,
    json_build_object('sub', _uid::text, 'email', _email)::jsonb,
    'email',
    _now, _now, _now
  );

  -- 4. Create the public.user_profiles row with active worker status
  INSERT INTO user_profiles (
    id, display_name, role, department, worker_number, is_on_leave, created_at, updated_at
  ) VALUES (
    _uid, _name, 'WORKER'::user_role,
    'ROADS'::admin_department,
    1, FALSE, _now, _now
  )
  ON CONFLICT (id) DO UPDATE
    SET display_name  = EXCLUDED.display_name,
        role          = EXCLUDED.role,
        department    = EXCLUDED.department,
        worker_number = EXCLUDED.worker_number,
        is_on_leave   = FALSE;

  RAISE NOTICE 'Successfully re-seeded pothole_worker1@nivara.app (UID: %)', _uid;
END;
$$;

-- Verify result:
SELECT 
  u.email,
  p.display_name,
  p.role,
  p.department,
  p.worker_number,
  p.is_on_leave,
  EXISTS(SELECT 1 FROM auth.identities i WHERE i.user_id = u.id) AS has_identity
FROM auth.users u
JOIN user_profiles p ON p.id = u.id
WHERE u.email = 'pothole_worker1@nivara.app';
