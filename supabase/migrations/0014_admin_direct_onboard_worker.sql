-- Migration 0014: Admin Direct Staff Onboarding RPC
-- Allows municipal admins to directly provision/onboard field staff or administrators

CREATE OR REPLACE FUNCTION public.admin_direct_onboard_worker(
  p_display_name text,
  p_email text DEFAULT NULL,
  p_phone text DEFAULT NULL,
  p_role text DEFAULT 'worker',
  p_department text DEFAULT 'road',
  p_city text DEFAULT NULL,
  p_ward text DEFAULT NULL,
  p_existing_user_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, extensions
AS $$
DECLARE
  v_caller uuid;
  v_user_id uuid;
  v_worker_num integer;
  v_profile user_profiles%ROWTYPE;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Verify caller is admin or superadmin
  IF NOT EXISTS (
    SELECT 1 FROM user_profiles
    WHERE id = v_caller AND role IN ('admin', 'superadmin')
  ) THEN
    RAISE EXCEPTION 'Permission denied: only municipal administrators can onboard staff';
  END IF;

  -- 1. Determine user ID
  IF p_existing_user_id IS NOT NULL THEN
    v_user_id := p_existing_user_id;
  ELSE
    -- Check if auth user exists by email
    IF p_email IS NOT NULL AND trim(p_email) <> '' THEN
      SELECT id INTO v_user_id FROM auth.users WHERE lower(email) = lower(trim(p_email)) LIMIT 1;
    END IF;

    -- If still null, create an auth user
    IF v_user_id IS NULL THEN
      v_user_id := gen_random_uuid();
      INSERT INTO auth.users (
        id,
        instance_id,
        aud,
        role,
        email,
        encrypted_password,
        email_confirmed_at,
        created_at,
        updated_at,
        raw_app_meta_data,
        raw_user_meta_data
      ) VALUES (
        v_user_id,
        '00000000-0000-0000-0000-000000000000',
        'authenticated',
        'authenticated',
        COALESCE(trim(p_email), 'worker_' || substr(v_user_id::text, 1, 8) || '@nivara.internal'),
        crypt('NivaraStaff@2026', gen_salt('bf')),
        now(),
        now(),
        now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('display_name', p_display_name, 'phone', p_phone)
      );
    END IF;
  END IF;

  -- 2. Calculate next worker number if role is worker
  IF p_role = 'worker' THEN
    SELECT COALESCE(MAX(worker_number), 0) + 1 INTO v_worker_num FROM user_profiles;
  ELSE
    v_worker_num := NULL;
  END IF;

  -- 3. Upsert user_profiles
  INSERT INTO user_profiles (
    id,
    display_name,
    phone,
    role,
    department,
    city,
    ward,
    worker_number,
    is_on_leave,
    resigned_at,
    updated_at
  ) VALUES (
    v_user_id,
    p_display_name,
    p_phone,
    p_role::user_role,
    CASE WHEN p_department IS NOT NULL AND trim(p_department) <> '' THEN p_department::admin_department ELSE NULL END,
    p_city,
    p_ward,
    v_worker_num,
    false,
    NULL,
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    phone = COALESCE(EXCLUDED.phone, user_profiles.phone),
    role = EXCLUDED.role,
    department = EXCLUDED.department,
    city = COALESCE(EXCLUDED.city, user_profiles.city),
    ward = COALESCE(EXCLUDED.ward, user_profiles.ward),
    worker_number = COALESCE(user_profiles.worker_number, EXCLUDED.worker_number),
    is_on_leave = false,
    resigned_at = NULL,
    updated_at = now()
  RETURNING * INTO v_profile;

  -- 4. Record approved application for paper trail
  INSERT INTO worker_applications (
    id,
    user_id,
    status,
    reviewed_by,
    reviewed_at,
    created_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id,
    'APPROVED',
    v_caller,
    now(),
    now()
  )
  ON CONFLICT DO NOTHING;

  RETURN to_jsonb(v_profile);
END;
$$;
