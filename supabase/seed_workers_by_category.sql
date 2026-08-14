-- ═══════════════════════════════════════════════════════════════════
-- Nivara — Seed 95 Field Workers (5 per report category × 19 categories)
-- Run AFTER 0007_workers_and_applications.sql.
--
-- Fixed: Creates both auth.users AND auth.identities rows so that
--        password login works correctly in all Supabase versions.
--
-- Worker email pattern : <category_key>_worker<n>@nivara.app
-- Worker password      : worker123  (change after deploy)
-- ═══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  _pass  TEXT := crypt('worker123', gen_salt('bf'));
  _uid   UUID;
  _now   TIMESTAMPTZ := NOW();

  -- (category_key, display_label, department_wire)
  _cats TEXT[][] := ARRAY[
    ARRAY['pothole',          'Pothole',          'ROADS'],
    ARRAY['broken_footpath',  'Broken Footpath',  'ROADS'],
    ARRAY['open_manhole',     'Open Manhole',     'ROADS'],
    ARRAY['road_sign',        'Road Sign',        'ROADS'],
    ARRAY['waterlogging',     'Waterlogging',     'WATER'],
    ARRAY['blocked_drain',    'Blocked Drain',    'WATER'],
    ARRAY['sewage',           'Sewage',           'WATER'],
    ARRAY['pipe_leak',        'Pipe Leak',        'WATER'],
    ARRAY['water_supply',     'Water Supply',     'WATER'],
    ARRAY['garbage',          'Garbage',          'SANITATION'],
    ARRAY['street_light',     'Street Light',     'ELECTRICITY'],
    ARRAY['damaged_pole',     'Damaged Pole',     'ELECTRICITY'],
    ARRAY['power_issue',      'Power Issue',      'ELECTRICITY'],
    ARRAY['fallen_tree',      'Fallen Tree',      'PARKS'],
    ARRAY['stray_animals',    'Stray Animals',    'ANIMALS'],
    ARRAY['encroachment',     'Encroachment',     'ENFORCEMENT'],
    ARRAY['noise',            'Noise',            'ENFORCEMENT'],
    ARRAY['broken_property',  'Broken Property',  'GENERAL'],
    ARRAY['other',            'Other',            'GENERAL']
  ];
  _cat   TEXT[];
  _n     INT;
  _email TEXT;
  _name  TEXT;
BEGIN
  FOREACH _cat SLICE 1 IN ARRAY _cats LOOP
    FOR _n IN 1..5 LOOP
      _email := _cat[1] || '_worker' || _n || '@nivara.app';
      _name  := _cat[2] || ' Worker ' || _n;

      -- ── Only create if not already present ──────────────────────
      IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = _email) THEN

        _uid := gen_random_uuid();

        -- 1. Create the auth.users row (all required columns included)
        INSERT INTO auth.users (
          id,
          instance_id,
          aud,
          role,
          email,
          encrypted_password,
          email_confirmed_at,
          last_sign_in_at,
          raw_app_meta_data,
          raw_user_meta_data,
          is_super_admin,
          created_at,
          updated_at,
          confirmation_token,
          recovery_token,
          email_change_token_new,
          email_change,
          is_sso_user,
          deleted_at
        ) VALUES (
          _uid,
          '00000000-0000-0000-0000-000000000000',
          'authenticated',
          'authenticated',
          _email,
          _pass,
          _now,           -- email_confirmed_at  (pre-confirm so login works)
          _now,           -- last_sign_in_at
          '{"provider":"email","providers":["email"]}'::jsonb,
          json_build_object('display_name', _name)::jsonb,
          FALSE,          -- is_super_admin
          _now,
          _now,
          '',             -- confirmation_token
          '',             -- recovery_token
          '',             -- email_change_token_new
          '',             -- email_change
          FALSE,          -- is_sso_user
          NULL            -- deleted_at
        );

        -- 2. Create the auth.identities row (REQUIRED for password login)
        INSERT INTO auth.identities (
          id,
          provider_id,
          user_id,
          identity_data,
          provider,
          last_sign_in_at,
          created_at,
          updated_at
        ) VALUES (
          gen_random_uuid(),
          _email,         -- provider_id = email for email/password provider
          _uid,
          json_build_object('sub', _uid::text, 'email', _email)::jsonb,
          'email',
          _now,
          _now,
          _now
        );

        -- 3. Create the user_profiles row
        INSERT INTO user_profiles (
          id, display_name, role, department, worker_number, created_at, updated_at
        ) VALUES (
          _uid, _name, 'WORKER'::user_role,
          _cat[3]::admin_department,
          _n,
          _now, _now
        )
        ON CONFLICT (id) DO UPDATE
          SET display_name  = EXCLUDED.display_name,
              role          = EXCLUDED.role,
              department    = EXCLUDED.department,
              worker_number = EXCLUDED.worker_number;

      END IF;
    END LOOP;
  END LOOP;
END;
$$;

-- ══════════════════════════════════════════ END SEED ══════════════
