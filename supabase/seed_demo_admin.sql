-- ═══════════════════════════════════════════════════════════════════
-- Nivara — Demo admin seed (hackathon convenience)
-- Run in the Supabase SQL editor, AFTER 0001_init.sql.
--
-- Creates a ready-to-use administrator so judges/testers can sign in via
-- the login screen's "Admin" toggle:
--     username: admin   (the app maps this to admin@nivara.app)
--     password: admin123
--
-- SAFE + IDEMPOTENT — re-run any time. If the auth user is missing it is
-- created; if it already exists it is REPAIRED (see the note below) and the
-- profile is re-asserted as SUPERADMIN.
--
-- Why the repair branch exists
-- ────────────────────────────
-- GoTrue (Supabase Auth) scans several auth.users text columns
-- (confirmation_token, recovery_token, email_change*, phone_change*,
-- reauthentication_token) into non-nullable strings on every sign-in. A row
-- inserted by hand that leaves them NULL makes that scan fail, and the login
-- request returns HTTP 500:
--     {"code":"unexpected_failure","message":"Database error querying schema"}
-- Normal (app) sign-ups never hit this because GoTrue writes '' there. We set
-- those columns to '' on insert and COALESCE them to '' on repair.
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

    -- Minimal, confirmed email/password identity. The empty-string token
    -- columns are REQUIRED — see the header note (NULL there breaks login).
    INSERT INTO auth.users (
      id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, recovery_token,
      email_change, email_change_token_new, email_change_token_current,
      phone_change, phone_change_token, reauthentication_token
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
      NOW(), NOW(),
      '', '', '', '', '', '', '', ''
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
      jsonb_build_object(
        'sub', v_uid::text, 'email', v_email, 'email_verified', true
      ),
      NOW(), NOW(), NOW()
    );
  ELSE
    -- REPAIR a previously-seeded row: re-assert the password, confirm the
    -- email, and null-proof every string column GoTrue scans on login.
    UPDATE auth.users SET
      encrypted_password         = crypt(v_password, gen_salt('bf')),
      email_confirmed_at         = COALESCE(email_confirmed_at, NOW()),
      confirmation_token         = COALESCE(confirmation_token, ''),
      recovery_token             = COALESCE(recovery_token, ''),
      email_change               = COALESCE(email_change, ''),
      email_change_token_new     = COALESCE(email_change_token_new, ''),
      email_change_token_current = COALESCE(email_change_token_current, ''),
      phone_change               = COALESCE(phone_change, ''),
      phone_change_token         = COALESCE(phone_change_token, ''),
      reauthentication_token     = COALESCE(reauthentication_token, ''),
      updated_at                 = NOW()
    WHERE id = v_uid;

    -- Ensure the email identity exists (older seeds may have skipped it).
    INSERT INTO auth.identities (
      id, user_id, provider_id, provider, identity_data,
      last_sign_in_at, created_at, updated_at
    )
    SELECT
      gen_random_uuid(), v_uid, v_uid::text, 'email',
      jsonb_build_object(
        'sub', v_uid::text, 'email', v_email, 'email_verified', true
      ),
      NOW(), NOW(), NOW()
    WHERE NOT EXISTS (
      SELECT 1 FROM auth.identities
      WHERE user_id = v_uid AND provider = 'email'
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
