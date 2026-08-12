-- ═══════════════════════════════════════════════════════════════════
-- Nivara — Demo field-worker seed (hackathon convenience)
-- Run in the Supabase SQL editor, AFTER 0001_init.sql AND 0006_staff_worker.sql
-- (the WORKER enum value must exist first).
--
-- Creates ready-to-use field workers so judges/testers can sign in via the
-- login screen's "Worker" toggle and see the assignment round-trip:
--     username: worker    (mapped to worker@nivara.app)   password: worker123
--     username: worker2   (mapped to worker2@nivara.app)  password: worker123
--
-- SAFE + IDEMPOTENT — re-run any time. Same GoTrue null-proofing as the admin
-- seed (empty-string token columns; see seed_demo_admin.sql header for why).
-- ═══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_password TEXT := 'worker123';
  v_uid      UUID;
  w          RECORD;
BEGIN
  FOR w IN
    SELECT * FROM (VALUES
      ('worker@nivara.app',  'Ravi Kumar',  'ROADS'),
      ('worker2@nivara.app', 'Meena Nair',  'SANITATION')
    ) AS t(email, name, dept)
  LOOP
    SELECT id INTO v_uid FROM auth.users WHERE email = w.email;

    IF v_uid IS NULL THEN
      v_uid := gen_random_uuid();
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
        'authenticated', 'authenticated', w.email,
        crypt(v_password, gen_salt('bf')), NOW(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('display_name', w.name),
        NOW(), NOW(),
        '', '', '', '', '', '', '', ''
      );

      INSERT INTO auth.identities (
        id, user_id, provider_id, provider, identity_data,
        last_sign_in_at, created_at, updated_at
      ) VALUES (
        gen_random_uuid(), v_uid, v_uid::text, 'email',
        jsonb_build_object('sub', v_uid::text, 'email', w.email, 'email_verified', true),
        NOW(), NOW(), NOW()
      );
    ELSE
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

      INSERT INTO auth.identities (
        id, user_id, provider_id, provider, identity_data,
        last_sign_in_at, created_at, updated_at
      )
      SELECT gen_random_uuid(), v_uid, v_uid::text, 'email',
             jsonb_build_object('sub', v_uid::text, 'email', w.email, 'email_verified', true),
             NOW(), NOW(), NOW()
      WHERE NOT EXISTS (
        SELECT 1 FROM auth.identities WHERE user_id = v_uid AND provider = 'email'
      );
    END IF;

    -- Profile: WORKER role, scoped to a department so officials can find them.
    INSERT INTO public.user_profiles (id, display_name, role, department)
    VALUES (v_uid, w.name, 'WORKER'::user_role, w.dept::admin_department)
    ON CONFLICT (id) DO UPDATE
      SET role = 'WORKER'::user_role,
          department = EXCLUDED.department,
          display_name = EXCLUDED.display_name;

    RAISE NOTICE 'Demo worker ready: % (%, uid %)', w.email, w.dept, v_uid;
  END LOOP;
END $$;
