# ClassSync Supabase connection and local validation report

## Configuration

- `classsync-config.js` now points at the supplied Supabase project URL and contains the supplied `sb_publishable_` key.
- The publishable key is designed for browser use. Do not put a Supabase secret/service-role key in this file.
- The configured URL and key are not proof that the remote database accepts requests.

## Local checks completed

- Both inline JavaScript blocks in `index.html`: syntax check passed.
- `pilot-live.js`: `node --check` passed.
- `netlify/functions/ai.js`: `node --check` passed.
- `node test/ai.test.js`: all 19 tests passed.
- Local static HTTP smoke test: `index.html`, `classsync-config.js`, `pilot-live.js`, and the Netlify function source all returned HTTP 200.
- Compared against the original ZIP: only `classsync-config.js` had changed before this report was added.

## Important compatibility findings from the screenshots supplied

The existing Supabase schema visibly contains legacy tables/columns including:

- `class_schedules` with UUID `id`, `room_id`, `course_code`, `course_name`, `day_of_week`, `start_time`, and `end_time`.
- `messages` with UUID `id`, `sender_id`, `recipient_id`, and `content`.
- `reservations` with UUID `id`, `user_id`, and `room_id`.
- `profiles` with visible `full_name`, `avatar_url`, and `created_at` columns.
- RLS was shown enabled for `class_schedules`, `messages`, `profiles`, `reservations`, and `rooms`.

The supplied ClassSync pilot SQL expects a different model, including `classes` (bigint IDs and period-based fields), `room_holds`, `shift_requests`, `room_events`, `random_chat_rooms`, and `random_chat_messages`. Its `profiles` table also expects `role`, `batch`, and `teacher_code`.

These are not interchangeable table names or column types. In particular, `CREATE TABLE IF NOT EXISTS` will not add the missing columns to an already-existing `profiles` table. Do not run the README's full setup sequence against the production project yet. A data-preserving migration needs a confirmed mapping from legacy room UUIDs and schedule/time fields to the new room/period model.

## What could not be verified from this environment

- The environment could not resolve/reach the Supabase host (DNS/network access unavailable), so no live REST/Auth request was completed.
- Google OAuth provider settings and redirect URLs were not verified.
- No SQL migration was run and no remote database object was changed.
- No browser-based sign-in or authenticated RLS test was possible.

## Next required action

Run `supabase/00_read_only_audit.sql` in the Supabase SQL Editor and export all four result sets (columns, RLS status, policies, and foreign keys). These results are required to design a safe additive migration. Keep the current production database unchanged until that migration is reviewed.
