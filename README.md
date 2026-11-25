# ClassSync — shared-data pilot package

This package preserves the original ClassSync interface and adds a Supabase-backed pilot layer. It is **deployment-ready source code**, not an already deployed service: the project owner must create/configure Supabase, Google OAuth, and Netlify credentials before real users can use it.

## What is included

| Area | Included implementation | Important status |
|---|---|---|
| Timetable | UU Fall 2026 sample timetable seed (436 CSE class rows; 70 rooms, as imported from the supplied sample) | Must be checked against the permission and authoritative routine before public use |
| Authentication | Google OAuth through Supabase Auth | Requires Google Cloud + Supabase OAuth setup |
| Roles | Student/CR/teacher/coordinator/admin profiles | Admin must verify and assign roles/batches |
| Shift workflow | SQL request/approval RPCs and conflict checks | Existing legacy timetable screens still include browser-local demo state; use database workflow only after UI migration/testing |
| Shared room holds | Atomic `create_room_hold` / `release_room_hold` RPCs plus a shared holds panel | Enabled by migration 06; authoritative for reservations made through the new panel |
| Messenger | Random matching and authenticated private messages | Requires migration 05; polling-based, not end-to-end encrypted |
| Chat safety | Block user, report partner, admin-only report visibility, block-aware matching | Enabled by migration 06; human moderation process/contact still needs to be staffed |
| AI | Netlify function with server-side model key and fallback response | Optional; requires Netlify environment variables and real-provider testing |
| Privacy/ownership | Pilot policy and launch checklist | Team must confirm contributor rights and university permission scope |

## Setup sequence

1. Create a Supabase project.
2. In Supabase SQL Editor, run `01_schema.sql`, `02_security.sql`, `03_seed_routine.sql`, `04_seed_knowledge.sql`, `05_pilot_chat.sql`, then `06_live_pilot_hardening.sql`, in that order.
3. Configure Google OAuth in Google Cloud Console. Add the Supabase callback URL shown in Supabase Authentication > Providers > Google to the Google OAuth client's authorized redirect URIs. Add the exact production site origin to Supabase Auth URL Configuration. Do not use wildcard production redirects.
4. Edit `classsync-config.js` with the Supabase project URL and publishable/anon key. These are browser-public values; never place a service-role key or Google client secret here.
5. In Supabase Auth, verify the pilot users. Assign each user's `batch`, `role`, and `teacher_code` from an administrator-controlled SQL session. Never let users choose staff roles themselves.
6. Deploy the whole folder to Netlify (not just `index.html`). Set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `GEMINI_API_KEY`, and optionally `GEMINI_MODEL`, `CURRENT_SEMESTER`, and `AI_DAILY_LIMIT` in Netlify environment variables. AI can remain disabled by leaving the model key unset.
7. Test using at least two student accounts and one administrator account. Verify that one student's hold appears in the other student's shared holds panel, conflicting holds are rejected, a user can release only their own hold, chat messages are private, blocked users are not rematched, and reports are visible only to admins.

## Shared holds

The `Shared room holds` control uses database RPCs, not localStorage. The database checks the selected room/time against the imported classes, holds, and room events, then inserts the hold in a transaction protected by a room/day advisory lock. The shared holds panel lists reservations for the configured semester. Existing timetable screens retain legacy local state for some demo-era operations; do not claim those older hold/request/admin controls are multi-user synchronized until they are migrated and verified.

## Chat safety and operations

- Chat is restricted to authenticated accounts. The database only permits messages from members of an active room.
- Users can report or block their current partner. A report also ends the chat and blocks that pair. Matching excludes pairs blocked in either direction.
- Admins can inspect reports through the `chat_reports` table in Supabase. Establish a named moderator, response-time target, escalation path, and retention schedule before inviting a broad audience.
- Messages are stored in the database. This is not ephemeral or end-to-end encrypted messaging. Do not promise either property.

## Privacy and data handling

See `PILOT_PRIVACY_AND_OWNERSHIP.md`. Use only the minimum data required. Do not collect student IDs, phone numbers, addresses, grades, or personal records for this pilot unless the university has approved a specific need and retention period.

## Validation

Run `node test/ai.test.js` for the existing AI endpoint tests. Check JavaScript syntax with `node --check pilot-live.js`. SQL must be executed and tested in the actual Supabase project's PostgreSQL environment; static inspection is not proof of a successful migration or correct production RLS behavior.

## Known deployment prerequisites

This repository cannot supply your private Supabase project, Google OAuth client secret, Netlify site, model API key, verified UU user list, or university-approved moderation/retention policy. Until you configure those items and pass the multi-account checks, call this a **deployment-ready pilot build**, not a live production service.

---

## Merged project — ER-diagram features (additive)

This build merges the two student projects. Apon's ClassSync visual design, Supabase configuration (`classsync-config.js`), pilot layer (`pilot-live.js`, migrations `05`/`06`), AI function, tests and audit documents are **unchanged**. The only edits to `index.html` are three `<script>` tags near the end of the file that load `er-features.js` and `section-office.js`. All features from the second (multi-university ER-diagram) project were added **additively**: new database tables/policies plus a new UI layer that plugs into the existing nav bar. No existing screen, table, column, function or policy was redesigned or overwritten.

**Live-testing build:** the CR login has been removed, and all bundled demo data was deleted (`demo-data.js`, `demo-showcase.html`). ER feature tabs now read/write only the configured Supabase project — run migrations `07`/`08` before using those tabs.

### What was added

| File | Contents |
|---|---|
| `supabase/07_er_features.sql` | 17 new ER tables (including `lost_found.photo_url` for item photos): `universities`, `departments`, `programs`, `courses`, `buildings`, `memberships`, `subscriptions`, `enrollments`, `events`, `event_registrations`, `announcements`, `notifications`, `lost_found`, `item_match`, `resources`, `maintenance_reports`, `class_cancellations` — plus additive columns on `profiles` (`email`, `phone`, `avatar_url`, `uni_id`, `dept_id`, `program_id`) and `rooms` (`building_id`, `is_active`, generated `room_number`), a read-only `timetable` view over the pilot's `classes`, and RLS policies for every new table. |
| `supabase/08_er_seed.sql` | Re-runnable sample data: one university, 3 departments, 2 programs, 2 buildings, 10 courses, announcements, notifications, lost & found items, resources, a calendar event, a maintenance report, a class cancellation, and help-centre articles for the new features. |
| `section-office.js` | **Section Office routine + PDF export.** Adds a "Section Office" demo role (and gives Coordinator/Admin the same tool) plus a *Download routine PDF* button on the existing *Add routine* screen. Exports every batch of the current semester as bordered tables in a valid multi-page PDF, generated entirely in-browser (no external library, works offline). |
| `er-features.js` | **The user-visible feature layer.** Adds seven tabs to Apon's existing nav bar — Overview, Announcements, Notifications, Lost & Found, Resources, Events, Profile — rendered with Apon's own CSS classes so his visual design is unchanged. **The original "Today" screen now lives inside Overview, and "My requests" lives inside Profile**; those two standalone nav tabs were removed, all other tabs remain as they were. Working controls: post announcement, report item **with a photo** (grid cards with image thumbnails + click-to-enlarge), claim item, add resource, create event, mark notifications read. Reads/writes only the live Supabase project — no demo/offline data. Run migrations `07`/`08` before using these tabs. |

### Setup order (full merged build)

1. Create/configure Supabase, Google OAuth and Netlify as described above.
2. In SQL Editor run, in order: `01_schema.sql`, `02_security.sql`, `03_seed_routine.sql`, `04_seed_knowledge.sql`, `05_pilot_chat.sql`, `06_live_pilot_hardening.sql`, **`07_er_features.sql`**, **`08_er_seed.sql`**.
3. Run `supabase/00_read_only_audit.sql` first on any pre-existing/production database and follow `SUPABASE_CONNECTION_AUDIT.md` — those new tables use `CREATE TABLE IF NOT EXISTS`, so existing legacy tables are never altered.

### Design notes / safety

- The pilot's canonical identities are preserved: `profiles.id` (uuid), `rooms.name` (text PK), `classes.id` (bigint). The ER `timetable` is a **view**, not a second timetable table, so no data is duplicated.
- No existing function signature (`request_shift`, `book_room`, `create_room_hold`, `mark_request_seen`, `room_usage`, chat RPCs) was changed — the merged UI and `pilot-live.js` continue to work unchanged.
- The pilot's stricter security is preserved: students still see all requests in their batch, profile self-update remains restricted to `full_name`, `room_events` still has no direct insert policy, and `reviews`/`ai_usage` policies are untouched.
- `08_er_seed.sql` resolves user ids from existing profiles at run time and guards every insert, so it is safe to run more than once and needs no hard-coded auth ids.
