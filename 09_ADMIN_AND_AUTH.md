# Nivara — Admin & Authentication Design
**Version:** 1.0 | **Added:** 2026-08-08 (role-based access for the AppSprint build)

This document defines how citizens and municipal administrators sign in and
what each can do. It is the companion to `04_DATABASE_SCHEMA.md` (which holds
the SQL) and `CLAUDE.md` (the build guardrails).

---

## 1. Why two roles

The original design let complaints be "resolved" only by community votes
(3+ citizens tapping *This is fixed*). There was no municipal side — nobody
official could see the queue or close a report. Nivara now has **one app, two
roles**, gated by a `role` column on `user_profiles`:

| Role         | Who                                   | Sees                                             |
|--------------|---------------------------------------|--------------------------------------------------|
| `CITIZEN`    | Default for every new signup          | Citizen tabs: Home, Map, Report, Lost&Found, Profile |
| `ADMIN`      | Municipal / department staff          | Everything a citizen sees **plus** the Admin dashboard |
| `SUPERADMIN` | Project owner / control account       | All of the above **plus** the ability to assign roles |

There is a single codebase and a single login screen. After sign-in the app
reads the profile's `role` and routes to the correct home. No separate admin
app or portal is built for the hackathon (a web portal is listed as future
scope).

---

## 2. Sign-up / sign-in flow

Authentication is **Supabase Auth (email + password)**. Optional Google OAuth
can be added later; email is enough for the demo.

```
                 ┌─────────────────────────────┐
                 │        Login screen          │
                 │  email · password · [Login]  │
                 │  "New here? Create account"   │
                 └──────────────┬──────────────┘
             sign in            │           sign up
        ┌────────────────────────┴────────────────────────┐
        ▼                                                  ▼
  supabase.auth                                    supabase.auth
  .signInWithPassword                              .signUp
        │                                                  │
        │                              trigger: handle_new_user()
        │                              inserts user_profiles row
        │                              with role = 'CITIZEN'
        ▼                                                  ▼
  load user_profiles.role  ◄───────────────────────────────
        │
        ├─ role = CITIZEN ......► citizen tab shell   (/home)
        └─ role = ADMIN|SUPERADMIN ► admin shell + citizen tabs (/admin)
```

Key points:
- A profile row is created automatically by the `on_auth_user_created`
  trigger (see schema) — the app never inserts profiles directly.
- Everyone starts as `CITIZEN`. There is **no self-service "become admin"**
  path in the UI — that would be a security hole. Elevation is deliberate
  (Section 3).
- The app decides routing purely from `role`; it never trusts a client flag.
  RLS on the database enforces the same rule server-side, so a tampered client
  still cannot perform admin actions.

---

## 3. How an account becomes an admin

Two supported paths:

**A. Bootstrap the first SUPERADMIN (one-time, manual).**
Right after the owner signs up normally in the app, run this once in the
Supabase SQL editor (service role):

```sql
UPDATE user_profiles
SET role = 'SUPERADMIN', department = 'GENERAL'
WHERE id = (SELECT id FROM auth.users WHERE email = 'owner@example.com');
```

**B. Promote everyone else via RPC (SUPERADMIN only).**
Once a superadmin exists, use the guarded RPC (already in the schema) — from a
tiny "Manage staff" screen or the SQL editor:

```sql
SELECT set_user_role(
  p_user_id   => '<the-staff-users-uuid>',
  p_role      => 'ADMIN',
  p_department=> 'ROADS',          -- GENERAL sees all departments
  p_city      => 'Thiruvananthapuram',
  p_ward      => NULL              -- NULL = whole city
);
```

`set_user_role` raises an exception unless the caller `is_superadmin`, so it is
safe to expose in-app.

For the **hackathon demo** you typically create two accounts up front:
`citizen@demo.com` (left as CITIZEN) and `admin@demo.com` (promoted to ADMIN /
ROADS). That gives a clean two-window demo: citizen reports → admin resolves.

---

## 4. What an admin can do

Admins get an extra bottom-nav destination (or drawer) leading to the
**Admin dashboard**:

1. **Report queue** — every report, newest first, with filters:
   category · status · severity · ward. By default an ADMIN sees reports whose
   `assigned_department` matches their `department` (GENERAL/SUPERADMIN see all),
   scoped to their `jurisdiction_city`/`ward` when set.
2. **Report detail** — full evidence package + hash verification, photos, map
   location, community confirmation counts, and the status-change history.
3. **Status actions** — move a report through its lifecycle:
   `SUBMITTED → ACKNOWLEDGED → IN_PROGRESS → RESOLVED` (or `CLOSED` / `DUPLICATE`).
   Marking `RESOLVED` prompts for optional **resolution notes + a proof photo**.
4. **Stats strip** — counts by status for the admin's scope (open / in-progress
   / resolved this week).

All status changes go through **one** database function,
`admin_set_report_status(report_id, new_status, note, photo_url)`, which:
- rejects the call if the caller is not an admin,
- stamps `acknowledged_at/by` and `resolved_at/by`,
- writes an immutable row into `report_status_history` (audit trail),
- returns the updated report.

The citizen who filed the report sees status changes live (Supabase Realtime on
the `reports` table) and in the report's public history timeline.

---

## 5. Permissions matrix

| Action                                   | CITIZEN | ADMIN | SUPERADMIN |
|------------------------------------------|:-------:|:-----:|:----------:|
| Sign up / sign in                        |   ✅    |  ✅   |    ✅      |
| File a report (manual or SensorWatch)    |   ✅    |  ✅   |    ✅      |
| Edit **own** report while `SUBMITTED`    |   ✅    |  ✅   |    ✅      |
| Edit a report after authorities engage   |   ❌    |  ✅   |    ✅      |
| Confirm / mark-fixed (community vote)     |   ✅    |  ✅   |    ✅      |
| View Admin dashboard / queue             |   ❌    |  ✅   |    ✅      |
| Change any report's official status       |   ❌    |  ✅   |    ✅      |
| See private sensor detections            | own only| own only| own only |
| See a Lost&Found match                    |involved only|✅|    ✅      |
| Assign roles to other users              |   ❌    |  ❌   |    ✅      |

Enforced in two layers: the **UI** hides what a role can't do, and **RLS +
SECURITY DEFINER RPCs** in Postgres make it impossible even for a crafted
request. The client is never the source of truth for authorization.

---

## 6. RLS summary (see schema for exact SQL)

- `is_admin(uid)` / `is_superadmin(uid)` — `SECURITY DEFINER` helpers that read
  `user_profiles.role` without recursive-policy issues.
- **reports** — public read; citizen insert/update own but only while
  `SUBMITTED`; admins update any (`reports_update_admin`).
- **report_status_history** — public read (transparency); writes only via the
  `admin_set_report_status` RPC.
- **user_profiles** — read own or (if admin) all; update own; role changes only
  via `set_user_role` RPC.
- **sensor_detections** — strictly private to the owner regardless of role.
- **public_profiles** view — safe columns only (no phone) for author chips /
  leaderboards.

---

## 7. Client responsibilities (Flutter)

- Keep an `AuthController` (Riverpod) exposing `session`, `profile`, and
  `role`; refresh the profile on `onAuthStateChange`.
- A router redirect guard: unauthenticated → `/login`; authenticated citizen →
  `/home`; admin → may access `/admin/*`. Guard admin routes on `role`.
- Never store or trust a local "isAdmin" boolean beyond the current session;
  always derive from the freshly-loaded profile.
- Treat every RPC error (e.g. "Only administrators can change report status")
  as a hard stop and surface it — it means RLS caught something the UI missed.
