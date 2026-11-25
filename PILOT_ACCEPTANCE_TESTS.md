# ClassSync pilot acceptance tests

Run these after deploying the site and applying SQL migrations 01–06. Use two separate Google accounts (Student A and Student B) plus an admin account. Do not use demo accounts for these checks.

## Authentication and roles
- [ ] A new Google account is created as `student` only.
- [ ] A student cannot edit their own `role`, `batch`, or `teacher_code` through the browser/API.
- [ ] A student without an administrator-assigned batch is not admitted into the timetable app.
- [ ] Sign-out clears the Supabase session; refreshing after sign-out does not restore the app session.

## Shared room holds
- [ ] Student A creates a hold from the Shared room holds panel.
- [ ] Student B refreshes the panel and sees the same hold.
- [ ] Student B cannot reserve an overlapping period in the same room; the database returns a conflict.
- [ ] Student B can reserve a non-overlapping slot.
- [ ] Student B cannot release Student A's hold.
- [ ] Student A can release their own hold.
- [ ] A hold cannot cross the lunch break or extend outside P1–P6.
- [ ] A hold cannot overlap an imported class, room event, blocked room, or shift-request hold.

## Messenger and safety
- [ ] Two authenticated users can enter the random queue and be matched.
- [ ] Only the two room members can read/send messages in that room.
- [ ] A user can end a chat.
- [ ] A user can report a partner; the report is recorded and the pair is blocked/ended.
- [ ] A user can block a partner without submitting a report.
- [ ] A blocked pair is not matched again in either direction.
- [ ] Non-admin accounts cannot read `chat_reports`; an admin can.
- [ ] Ended or blocked chats cannot accept new messages.

## Privacy and operations
- [ ] Privacy notice and contact/moderator details are visible before inviting students.
- [ ] Retention/deletion schedule is approved by the university and configured operationally.
- [ ] A moderator has an incident-response procedure for reports.
- [ ] No service-role key, Google client secret, or model key appears in browser source, browser storage, or Git history.
- [ ] AI provider outage leaves sign-in, timetable and messenger usable.
- [ ] Backup/restore and account removal procedure are tested.

Passing these checks is a prerequisite for describing the service as a live pilot. Passing static JavaScript tests alone is not sufficient.
