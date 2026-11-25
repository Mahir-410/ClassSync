-- =============================================================================
-- ClasSync — ADDITIVE ER-Diagram feature layer (merge of the two student projects)
-- =============================================================================
-- Run this AFTER 01_schema.sql ... 06_live_pilot_hardening.sql.
-- This file ONLY ADDS new tables/columns/policies. It never changes, replaces or
-- removes any existing table, column, function, policy or row from the pilot.
-- Apon's UI, config, pilot SQL, pilot-live.js and the AI function are untouched.
--
-- Source of these features: the "multi-university ER diagram" project
-- ( universities, departments, programs, courses, buildings, memberships,
--   subscriptions, enrollments, calendar events + event registrations,
--   announcements, notifications, lost & found + item match, resources,
--   maintenance reports, class cancellations ).
--
-- Canonical identities in this merged project remain the pilot's:
--   profiles.id (uuid), rooms.name (text PK), classes.id (bigint).
-- The ER `timetable` entity is exposed as a READ-ONLY VIEW over `classes`
-- instead of a second competing timetable table.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. New reference tables
-- -----------------------------------------------------------------------------

create table if not exists universities(
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  location text,
  email text,
  phone text,
  website text,
  created_at timestamptz not null default now()
);

create table if not exists departments(
  id uuid primary key default gen_random_uuid(),
  uni_id uuid not null references universities(id) on delete cascade,
  name text not null,
  code text not null,
  head text,
  created_at timestamptz not null default now(),
  unique (uni_id, code)
);

create table if not exists programs(
  id uuid primary key default gen_random_uuid(),
  dept_id uuid not null references departments(id) on delete cascade,
  name text not null,
  code text not null,
  degree_type text check (degree_type in ('bachelors','masters','phd','diploma')),
  created_at timestamptz not null default now(),
  unique (dept_id, code)
);

create table if not exists courses(
  code text primary key,
  dept_id uuid references departments(id) on delete set null,
  name text not null,
  credits smallint not null default 3 check (credits > 0),
  capacity smallint not null default 60 check (capacity > 0),
  is_lab boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists buildings(
  id uuid primary key default gen_random_uuid(),
  uni_id uuid not null references universities(id) on delete cascade,
  name text not null,
  code text not null,
  blocks text,
  created_at timestamptz not null default now(),
  unique (uni_id, code)
);

-- -----------------------------------------------------------------------------
-- 2. Additive columns on existing tables (safe: all nullable / defaulted)
-- -----------------------------------------------------------------------------

alter table profiles add column if not exists email text;
alter table profiles add column if not exists phone text;
alter table profiles add column if not exists avatar_url text;
alter table profiles add column if not exists uni_id uuid references universities(id) on delete set null;
alter table profiles add column if not exists dept_id uuid references departments(id) on delete set null;
alter table profiles add column if not exists program_id uuid references programs(id) on delete set null;

-- Rooms keep their canonical text PK `name`. These columns only add ER metadata.
alter table rooms add column if not exists building_id uuid references buildings(id) on delete set null;
alter table rooms add column if not exists is_active boolean not null default true;
-- `room_number` is the ER name for the room identifier; expose it as a generated alias.
alter table rooms add column if not exists room_number text generated always as (name) stored;

-- -----------------------------------------------------------------------------
-- 3. People / access tables
-- -----------------------------------------------------------------------------

create table if not exists memberships(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  program_id uuid not null references programs(id) on delete cascade,
  role text not null default 'member' check (role in ('member','leader')),
  verified boolean not null default false,
  joined_at timestamptz not null default now(),
  unique (user_id, program_id)
);

create table if not exists subscriptions(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  plan_type text not null check (plan_type in ('free','premium','institution')),
  start_date date not null default current_date,
  end_date date,
  price numeric(10,2) not null default 0,
  status text not null default 'active' check (status in ('active','expired','cancelled')),
  created_at timestamptz not null default now()
);

create table if not exists enrollments(
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references profiles(id) on delete cascade,
  course_code text not null references courses(code) on delete cascade,
  semester text not null,
  enrollment_date date not null default current_date,
  status text not null default 'active' check (status in ('active','dropped','completed')),
  unique (student_id, course_code, semester)
);

-- ER TIMETABLE entity as a read-only view over the pilot's authoritative classes table
create or replace view timetable as
select
  c.id::text as id,
  c.course as course_code,
  c.teacher_code,
  c.room as room_number,
  c.day as day_of_week,
  c.period as start_period,
  c.periods,
  c.semester,
  c.batch
from classes c;

-- -----------------------------------------------------------------------------
-- 4. Calendar events and registrations
-- -----------------------------------------------------------------------------

create table if not exists events(
  id uuid primary key default gen_random_uuid(),
  organizer_id uuid not null references profiles(id) on delete cascade,
  title text not null,
  description text,
  event_date date not null,
  start_time time not null,
  end_time time not null,
  location text,
  capacity int,
  created_at timestamptz not null default now()
);

create table if not exists event_registrations(
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references events(id) on delete cascade,
  student_id uuid not null references profiles(id) on delete cascade,
  registration_date timestamptz not null default now(),
  status text not null default 'registered' check (status in ('registered','attended','cancelled')),
  unique (event_id, student_id)
);

-- -----------------------------------------------------------------------------
-- 5. Announcements and notifications
-- -----------------------------------------------------------------------------

create table if not exists announcements(
  id uuid primary key default gen_random_uuid(),
  posted_by uuid not null references profiles(id) on delete cascade,
  title text not null,
  content text not null,
  posted_at timestamptz not null default now(),
  expiry timestamptz,
  target_roles text[] check (target_roles is null or target_roles && array['student','cr','teacher','coord','admin'])
);

create table if not exists notifications(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles(id) on delete cascade,
  title text not null,
  message text not null,
  notification_type text not null default 'info'
    check (notification_type in ('info','success','warning','error','approval','reminder')),
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 6. Lost & found, resources, maintenance, cancellations
-- -----------------------------------------------------------------------------

create table if not exists lost_found(
  id uuid primary key default gen_random_uuid(),
  item_name text not null,
  description text,
  location text,
  status text not null default 'lost' check (status in ('lost','found','claimed','returned')),
  reporter_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
-- Photo attached to a reported item (data URL for small images; swap to Storage URL later).
alter table lost_found add column if not exists photo_url text;

create table if not exists item_match(
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references lost_found(id) on delete cascade,
  claimed_by uuid not null references profiles(id) on delete cascade,
  match_date timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending','matched','rejected')),
  notes text
);

create table if not exists resources(
  id uuid primary key default gen_random_uuid(),
  title text not null,
  type text not null check (type in ('document','link','video','other')),
  url text,
  uploaded_by uuid not null references profiles(id) on delete cascade,
  uploaded_at timestamptz not null default now()
);

create table if not exists maintenance_reports(
  id uuid primary key default gen_random_uuid(),
  room text references rooms(name) on delete cascade,
  reported_by uuid not null references profiles(id) on delete cascade,
  issue_type text not null,
  description text not null,
  status text not null default 'open' check (status in ('open','in_progress','resolved','closed')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table if not exists class_cancellations(
  id uuid primary key default gen_random_uuid(),
  course_code text not null references courses(code) on delete cascade,
  class_date date not null,
  reason text not null,
  notified_by uuid not null references profiles(id) on delete cascade,
  notified_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 7. Row Level Security for the new tables (pilot conventions preserved)
-- -----------------------------------------------------------------------------

alter table universities enable row level security;
alter table departments enable row level security;
alter table programs enable row level security;
alter table courses enable row level security;
alter table buildings enable row level security;
alter table memberships enable row level security;
alter table subscriptions enable row level security;
alter table enrollments enable row level security;
alter table events enable row level security;
alter table event_registrations enable row level security;
alter table announcements enable row level security;
alter table notifications enable row level security;
alter table lost_found enable row level security;
alter table item_match enable row level security;
alter table resources enable row level security;
alter table maintenance_reports enable row level security;
alter table class_cancellations enable row level security;

-- Reference data: readable by all signed-in users, writable by admins only
drop policy if exists er_ref_read on universities; create policy er_ref_read on universities for select to authenticated using (true);
drop policy if exists er_ref_read on departments;  create policy er_ref_read on departments  for select to authenticated using (true);
drop policy if exists er_ref_read on programs;     create policy er_ref_read on programs     for select to authenticated using (true);
drop policy if exists er_ref_read on courses;      create policy er_ref_read on courses      for select to authenticated using (true);
drop policy if exists er_ref_read on buildings;    create policy er_ref_read on buildings    for select to authenticated using (true);
drop policy if exists er_ref_admin on universities; create policy er_ref_admin on universities for all to authenticated using (my_role()='admin') with check (my_role()='admin');
drop policy if exists er_ref_admin on departments;  create policy er_ref_admin on departments  for all to authenticated using (my_role()='admin') with check (my_role()='admin');
drop policy if exists er_ref_admin on programs;     create policy er_ref_admin on programs     for all to authenticated using (my_role()='admin') with check (my_role()='admin');
drop policy if exists er_ref_admin on courses;      create policy er_ref_admin on courses      for all to authenticated using (my_role()='admin') with check (my_role()='admin');
drop policy if exists er_ref_admin on buildings;    create policy er_ref_admin on buildings    for all to authenticated using (my_role()='admin') with check (my_role()='admin');

-- Memberships and subscriptions
drop policy if exists er_mem_read on memberships; create policy er_mem_read on memberships for select to authenticated using (user_id = auth.uid() or my_role() in ('admin','coord'));
drop policy if exists er_mem_ins on memberships;  create policy er_mem_ins on memberships for insert to authenticated with check (user_id = auth.uid() or my_role()='admin');
drop policy if exists er_sub_read on subscriptions; create policy er_sub_read on subscriptions for select to authenticated using (user_id = auth.uid() or my_role()='admin');

-- Enrollments
drop policy if exists er_enrol_read on enrollments; create policy er_enrol_read on enrollments for select to authenticated using (student_id = auth.uid() or my_role() in ('admin','teacher','coord'));
drop policy if exists er_enrol_ins on enrollments;  create policy er_enrol_ins on enrollments for insert to authenticated with check (student_id = auth.uid() or my_role()='admin');

-- Events
drop policy if exists er_ev_read on events; create policy er_ev_read on events for select to authenticated using (true);
drop policy if exists er_ev_ins on events;  create policy er_ev_ins on events for insert to authenticated with check (organizer_id = auth.uid() or my_role()='admin');
drop policy if exists er_ev_upd on events;  create policy er_ev_upd on events for update to authenticated using (organizer_id = auth.uid() or my_role()='admin') with check (organizer_id = auth.uid() or my_role()='admin');
drop policy if exists er_ev_del on events;  create policy er_ev_del on events for delete to authenticated using (organizer_id = auth.uid() or my_role()='admin');

-- Event registrations
drop policy if exists er_er_read on event_registrations; create policy er_er_read on event_registrations for select to authenticated using (student_id = auth.uid() or my_role() in ('admin','coord'));
drop policy if exists er_er_ins on event_registrations;  create policy er_er_ins on event_registrations for insert to authenticated with check (student_id = auth.uid());

-- Announcements (role-targeted, but readable so clients can filter)
drop policy if exists er_ann_read on announcements; create policy er_ann_read on announcements for select to authenticated using (true);
drop policy if exists er_ann_ins on announcements;  create policy er_ann_ins on announcements for insert to authenticated with check (posted_by = auth.uid() or my_role() in ('admin','coord'));

-- Notifications
drop policy if exists er_notif_read on notifications; create policy er_notif_read on notifications for select to authenticated using (user_id = auth.uid() or my_role()='admin');
drop policy if exists er_notif_ins on notifications;  create policy er_notif_ins on notifications for insert to authenticated with check (user_id = auth.uid() or my_role() in ('admin','coord'));
drop policy if exists er_notif_upd on notifications;  create policy er_notif_upd on notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Lost & found and claims
drop policy if exists er_lf_read on lost_found; create policy er_lf_read on lost_found for select to authenticated using (true);
drop policy if exists er_lf_ins on lost_found;  create policy er_lf_ins on lost_found for insert to authenticated with check (reporter_id = auth.uid());
drop policy if exists er_lf_upd on lost_found;  create policy er_lf_upd on lost_found for update to authenticated using (reporter_id = auth.uid() or my_role()='admin') with check (reporter_id = auth.uid() or my_role()='admin');
drop policy if exists er_im_read on item_match; create policy er_im_read on item_match for select to authenticated using (claimed_by = auth.uid() or my_role()='admin');
drop policy if exists er_im_ins on item_match;  create policy er_im_ins on item_match for insert to authenticated with check (claimed_by = auth.uid());

-- Resources
drop policy if exists er_res_read on resources; create policy er_res_read on resources for select to authenticated using (true);
drop policy if exists er_res_ins on resources;  create policy er_res_ins on resources for insert to authenticated with check (uploaded_by = auth.uid() or my_role() in ('admin','teacher'));

-- Maintenance and cancellations
drop policy if exists er_mr_read on maintenance_reports; create policy er_mr_read on maintenance_reports for select to authenticated using (true);
drop policy if exists er_mr_ins on maintenance_reports;  create policy er_mr_ins on maintenance_reports for insert to authenticated with check (reported_by = auth.uid());
drop policy if exists er_mr_upd on maintenance_reports;  create policy er_mr_upd on maintenance_reports for update to authenticated using (my_role()='admin') with check (my_role()='admin');
drop policy if exists er_cc_read on class_cancellations; create policy er_cc_read on class_cancellations for select to authenticated using (true);
drop policy if exists er_cc_ins on class_cancellations;  create policy er_cc_ins on class_cancellations for insert to authenticated with check (notified_by = auth.uid() or my_role() in ('admin','teacher'));

-- =============================================================================
-- End of additive ER feature layer. Continue with 08_er_seed.sql for sample data.
-- =============================================================================