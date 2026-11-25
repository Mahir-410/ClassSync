# ClassSync pilot: privacy, safety and ownership plan

## Scope and data basis
- The supplied UU Fall 2026 routine is used as sample timetable data. The seed SQL contains 436 CSE class rows and 70 room records, as documented in the project README. This is a sample-data pilot, not an official university timetable service.
- Confirm the university's permission covers public display, transformation into database rows, and pilot testing. Keep the permission email/letter with the project records.
- Timetable visibility is limited to authenticated users in the pilot. Do not upload student IDs, phone numbers, personal addresses, grades, or other unnecessary student records.

## Authentication and account governance
- Google OAuth is handled by Google and Supabase Auth. ClassSync must never ask for or store a Google password.
- Configure the exact production origin and callback URL in Supabase and Google Cloud OAuth settings. Do not use wildcard redirect URLs.
- New accounts receive the `student` role by database trigger. Staff roles and student batch assignments must be assigned by the pilot administrator in Supabase SQL; never allow a user to self-select a privileged role.
- Require an institutional Google account by configuring the allowed provider/domain policy where available, and manually verify pilot participants before assigning batches or staff roles.
- Use a Supabase publishable/anon key in the browser only. Never expose the Supabase service-role key, Google client secret, or Gemini key in HTML, JavaScript, Git, or a public issue.

## Messenger privacy and safety
- Random chat is opt-in and available only to authenticated pilot users. It pairs two users; it is not a public directory or a direct-message inbox.
- Message reads and sends are restricted by Row Level Security to the two members of an active chat room. A user can end the current chat.
- Migration `06_live_pilot_hardening.sql` adds user blocking, partner reporting, block-aware random matching, and admin-only report visibility. Reports and blocks are stored in the database. A report also blocks the reported account and ends that pair’s active chat.
- A named human moderator, response-time target, escalation route, and administrator contact must still be assigned by the pilot team. Software controls do not replace moderation.
- Tell participants not to share passwords, phone numbers, student IDs, addresses, financial information, or other sensitive information.
- Establish a retention period with the university before launch. Until then, treat chat messages and reports as retained in the database and periodically review/delete them under an approved policy. Do not promise ephemeral or end-to-end encrypted messaging.

## AI fallback and data minimisation
- AI is optional. If the Netlify function, model provider, network, or quota is unavailable, the UI should show an unavailable message and leave timetable and messenger features usable.
- Keep model credentials in Netlify environment variables. The existing AI function uses the user's Supabase access token and is designed to avoid sending names and email addresses to the model.
- Review the provider's current data-use terms before enabling AI for real students. Disable AI by leaving the model key unset or removing the AI entry point.

## Ownership and attribution
- The team states that it created the ClassSync logo. Keep the original editable artwork, source files, dated exports, and contributor records as evidence of authorship.
- Add a project notice such as: `© 2026 ClassSync project team. Original logo and original project materials are owned by their respective creators/contributors.`
- Confirm ownership and assignment of rights among all team members before commercial licensing or transfer. Third-party libraries, fonts, and hosted services remain subject to their own licences and terms.
- Do not claim ownership of the UU timetable, university name, or other third-party materials. Attribute and use them only within the permission granted.

## Pilot launch checklist
- [ ] Written UU permission is retained and its scope covers this use.
- [ ] Supabase production project has backups and restricted administrator access.
- [ ] Google OAuth consent screen, authorized domains, and redirect URLs are configured.
- [ ] Only verified pilot users are invited; batch and staff roles are assigned by an administrator.
- [ ] SQL migrations are run and RLS is tested with two separate student accounts and a staff account.
- [ ] Netlify secrets are set; no service-role key or provider secret is in the browser.
- [ ] Chat moderation/reporting and a retention policy are in place before expanding beyond a small supervised pilot.
- [ ] Privacy notice and contact details are visible before account creation.
- [ ] Test logout, account deletion requests, access revocation, and backup/restore.

## Important current limitations
This package adds live Google OAuth and authenticated random chat integration, but it does not convert every existing localStorage timetable action (holds, shift requests, reviews, and room changes) into shared database operations. The supplied frontend still contains demo-era local state for those workflows. Do not represent those workflows as multi-user live functionality until they are migrated to the Supabase tables/RPCs and tested. Random chat currently uses polling and does not include moderation, reporting, blocking, or end-to-end encryption.
