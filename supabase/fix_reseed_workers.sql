-- ═══════════════════════════════════════════════════════════════════
-- Nivara — CLEANUP broken worker accounts, then re-seed correctly
-- Run this ONCE in Supabase SQL Editor if you already ran the
-- old seed_workers_by_category.sql and workers can't log in.
--
-- Step 1: Remove broken auth entries (missing identities row)
-- Step 2: Re-run the fixed seed (done automatically below)
-- ═══════════════════════════════════════════════════════════════════

-- ── Step 1: Delete old broken worker auth rows ──────────────────────
-- This removes auth.users whose emails match the worker pattern
-- AND that have no corresponding auth.identities row.
DELETE FROM auth.users
WHERE email ~ '^[a-z_]+_worker[1-5]@nivara\.app$'
  AND id NOT IN (SELECT user_id FROM auth.identities);

-- Also clean up any profiles left behind without an auth user
DELETE FROM user_profiles
WHERE role = 'WORKER'
  AND id NOT IN (SELECT id FROM auth.users);

-- ── Step 2: Re-seed with fixed script ──────────────────────────────
DO $$
DECLARE
  _pass  TEXT := crypt('worker123', gen_salt('bf'));
  _uid   UUID;
  _now   TIMESTAMPTZ := NOW();

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

      IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = _email) THEN

        _uid := gen_random_uuid();

        -- auth.users
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

        -- auth.identities  ← THIS is what was missing
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

        -- user_profiles
        INSERT INTO user_profiles (
          id, display_name, role, department, worker_number, created_at, updated_at
        ) VALUES (
          _uid, _name, 'WORKER'::user_role,
          _cat[3]::admin_department,
          _n, _now, _now
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

SELECT 
  u.email,
  p.display_name,
  p.role,
  p.department,
  p.worker_number,
  EXISTS(SELECT 1 FROM auth.identities i WHERE i.user_id = u.id) AS has_identity
FROM auth.users u
JOIN user_profiles p ON p.id = u.id
WHERE p.role = 'WORKER'
ORDER BY p.department, p.worker_number
LIMIT 20;

-- ═══════════════════════════════════ END CLEANUP+RESEED ═══════════
