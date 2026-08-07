-- ═══════════════════════════════════════════════════════════════════
-- Nivara — Demo admin seed (hackathon convenience)
-- Run ONCE in the Supabase SQL editor, AFTER 0001_init.sql.
--
-- Creates a ready-to-use administrator so judges/testers can sign in via
-- the login screen's "Admin" toggle:
--     username: admin   (the app maps this to admin@nivara.app)
--     password: admin123
--
-- Safe to re-run: if the user already exists it just re-asserts the role.
-- ═══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_email    TEXT := 'admin@nivara.app';
  v_password TEXT := 'admin123';
  v_uid      UUID;
BEGIN
  -- Reuse the existing auth user if this seed already ran.
  SELECT id INTO v_uid FROM auth.users WHERE email = v_email;

  IF v_uid IS NULL THEN
    v_uid := gen_random_uuid();

    -- Minimal, confirmed email/password identity in Supabase's auth schema.
    INSERT INTO auth.users (
      id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at
    ) VALUES (
      v_uid,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      v_email,
      crypt(v_password, gen_salt('bf')),
      NOW(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"display_name":"City Admin"}'::jsonb,
      NOW(), NOW()
    );

    -- Matching identities row so email/password sign-in resolves.
    INSERT INTO auth.identities (
      id, user_id, provider_id, provider, identity_data,
      last_sign_in_at, created_at, updated_at
    ) VALUES (
      gen_random_uuid(),
      v_uid,
      v_uid::text,
      'email',
      jsonb_build_object('sub', v_uid::text, 'email', v_email),
      NOW(), NOW(), NOW()
    );
  END IF;

  -- The handle_new_user trigger creates the profile; ensure it exists, then
  -- elevate it to SUPERADMIN (GENERAL department = sees every report).
  INSERT INTO public.user_profiles (id, display_name, role, department)
  VALUES (v_uid, 'City Admin', 'SUPERADMIN', 'GENERAL')
  ON CONFLICT (id) DO UPDATE
    SET role = 'SUPERADMIN', department = 'GENERAL', display_name = 'City Admin';

  RAISE NOTICE 'Demo admin ready: % (uid %)', v_email, v_uid;
END $$;
