-- =============================================================================
-- ClasSync — seed data for the additive ER feature layer (07_er_features.sql)
-- =============================================================================
-- Run AFTER 01..06 and 07_er_features.sql.
-- Re-runnable: every insert is guarded so running it twice is safe.
-- Uses the pilot's canonical room names (rooms.name) and resolves profile ids
-- from existing profiles at run time, so no auth.uid values are hard-coded.
-- =============================================================================

-- 1. University structure
insert into universities(id, name, code, location, email, phone, website)
select '11111111-1111-1111-1111-111111111111', 'Demo University', 'DU', 'Campus City', 'info@demo.edu', '+1-555-0100', 'https://demo.edu'
where not exists (select 1 from universities where id = '11111111-1111-1111-1111-111111111111');

insert into departments(id, uni_id, name, code, head)
select '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'Computer Science', 'CSE', 'Dr. Smith'
where not exists (select 1 from departments where id = '22222222-2222-2222-2222-222222222222');
insert into departments(id, uni_id, name, code, head)
select '33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'Mathematics', 'MAT', 'Dr. Lee'
where not exists (select 1 from departments where id = '33333333-3333-3333-3333-333333333333');
insert into departments(id, uni_id, name, code, head)
select '44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 'English', 'ENG', 'Dr. Patel'
where not exists (select 1 from departments where id = '44444444-4444-4444-4444-444444444444');

insert into programs(id, dept_id, name, code, degree_type)
select '55555555-5555-5555-5555-555555555555', '22222222-2222-2222-2222-222222222222', 'Computer Science & Engineering', 'CSE', 'bachelors'
where not exists (select 1 from programs where id = '55555555-5555-5555-5555-555555555555');
insert into programs(id, dept_id, name, code, degree_type)
select '66666666-6666-6666-6666-666666666666', '33333333-3333-3333-3333-333333333333', 'Mathematics', 'MAT', 'bachelors'
where not exists (select 1 from programs where id = '66666666-6666-6666-6666-666666666666');

insert into buildings(id, uni_id, name, code, blocks)
select '77777777-7777-7777-7777-777777777777', '11111111-1111-1111-1111-111111111111', 'Science Block', 'SCI', 'A,B,C'
where not exists (select 1 from buildings where id = '77777777-7777-7777-7777-777777777777');
insert into buildings(id, uni_id, name, code, blocks)
select '88888888-8888-8888-8888-888888888888', '11111111-1111-1111-1111-111111111111', 'Engineering Block', 'ENG', 'A,B'
where not exists (select 1 from buildings where id = '88888888-8888-8888-8888-888888888888');

-- Link the existing 70 rooms to a building (additive metadata only)
update rooms set building_id = '77777777-7777-7777-7777-777777777777'
where building_id is null and (name ~ '^[0-9]{3}$' or name in ('0005','0006','A004','B103','B104','B106/1','B106/2','B108','B109','B111','B112','B113','B114','B115'));
update rooms set building_id = '88888888-8888-8888-8888-888888888888'
where building_id is null;

-- 2. Courses
insert into courses(code, dept_id, name, credits, capacity, is_lab)
select 'CSE0613101','22222222-2222-2222-2222-222222222222','Data Structures',3,60,false
where not exists (select 1 from courses where code='CSE0613101');
insert into courses(code, dept_id, name, credits, capacity, is_lab)
select 'CSE0613102','22222222-2222-2222-2222-222222222222','Data Structures Lab',2,40,true
where not exists (select 1 from courses where code='CSE0613102');
insert into courses(code, dept_id, name, credits, capacity, is_lab)
select 'MAT0541101','33333333-3333-3333-3333-333333333333','Calculus I',3,60,false
where not exists (select 1 from courses where code='MAT0541101');
insert into courses(code, dept_id, name, credits, capacity, is_lab)
select 'ENG0232101','44444444-4444-4444-4444-444444444444','English Composition',3,60,false
where not exists (select 1 from courses where code='ENG0232101');
insert into courses(code, dept_id, name, credits, capacity, is_lab)
select 'ENG0232102','44444444-4444-4444-4444-444444444444','English Composition Lab',2,40,true
where not exists (select 1 from courses where code='ENG0232102');
insert into courses(code, dept_id, name, credits, capacity, is_lab)
select 'GED0222101','22222222-2222-2222-2222-222222222222','Bangladesh Studies',3,60,false
where not exists (select 1 from courses where code='GED0222101');
insert into courses(code, dept_id, name, credits, capacity, is_lab)
select 'PHY0533101','22222222-2222-2222-2222-222222222222','Physics I',3,60,false
where not exists (select 1 from courses where code='PHY0533101');
insert into courses(code, dept_id, name, credits, capacity, is_lab)
select 'PHY0533102','22222222-2222-2222-2222-222222222222','Physics I Lab',2,40,true
where not exists (select 1 from courses where code='PHY0533102');
insert into courses(code, dept_id, name, credits, capacity, is_lab)
select 'ECO0311101','22222222-2222-2222-2222-222222222222','Microeconomics',3,60,false
where not exists (select 1 from courses where code='ECO0311101');
insert into courses(code, dept_id, name, credits, capacity, is_lab)
select 'CSE0611201','22222222-2222-2222-2222-222222222222','Discrete Mathematics',3,60,false
where not exists (select 1 from courses where code='CSE0611201');

-- 3. Announcements (posted by an existing admin, if one exists)
insert into announcements(posted_by, title, content, target_roles)
select p.id, 'Welcome to the merged ClassSync pilot',
       'The ER features (announcements, notifications, lost & found, resources, maintenance, cancellations) are now available in the schema.',
       array['student','cr','teacher','coord','admin']::text[]
from profiles p
where p.role = 'admin'
  and not exists (select 1 from announcements where title = 'Welcome to the merged ClassSync pilot')
limit 1;

-- 4. Notifications (one per student, if students exist)
insert into notifications(user_id, title, message, notification_type)
select p.id, 'New ClassSync features',
       'Announcements, resources and lost & found are now available.', 'info'
from profiles p
where p.role = 'student'
  and not exists (select 1 from notifications n where n.user_id = p.id and n.title = 'New ClassSync features');

-- 5. Lost & found sample (reporter = first available student or admin)
insert into lost_found(item_name, description, location, status, reporter_id)
select 'Student ID card', 'Blue lanyard, Computer Science', 'Science Block, floor 2', 'lost', p.id
from profiles p
where p.role in ('student','cr')
  and not exists (select 1 from lost_found where item_name = 'Student ID card')
order by p.id limit 1;

insert into lost_found(item_name, description, location, status, reporter_id)
select 'Umbrella', 'Black umbrella, wooden handle', 'Engineering Block lobby', 'found', p.id
from profiles p
where p.role in ('student','cr')
  and not exists (select 1 from lost_found where item_name = 'Umbrella')
order by p.id limit 1;

-- 6. Resources (uploader = first teacher or admin)
insert into resources(title, type, url, uploaded_by)
select 'Class Shift Policy', 'document', null, p.id
from profiles p
where p.role in ('teacher','admin')
  and not exists (select 1 from resources where title = 'Class Shift Policy')
order by p.id limit 1;

insert into resources(title, type, url, uploaded_by)
select 'Room Booking Guide', 'link', 'https://demo.edu/rooms', p.id
from profiles p
where p.role in ('teacher','admin')
  and not exists (select 1 from resources where title = 'Room Booking Guide')
order by p.id limit 1;

-- 7. Calendar event (organizer = first CR or admin)
insert into events(organizer_id, title, description, event_date, start_time, end_time, location, capacity)
select p.id, 'Welcome Seminar', 'Intro to the merged ClassSync features', current_date + 7, '14:00', '15:00', 'Room 607', 50
from profiles p
where p.role in ('cr','admin')
  and not exists (select 1 from events where title = 'Welcome Seminar')
order by p.id limit 1;

-- 8. Maintenance report (uses canonical room name)
insert into maintenance_reports(room, reported_by, issue_type, description, status)
select '313', p.id, 'Projector', 'Projector not displaying image', 'open'
from profiles p
where p.role in ('student','cr')
  and not exists (select 1 from maintenance_reports where issue_type='Projector' and room='313')
order by p.id limit 1;

-- 9. Class cancellation (courses code is the FK; notifier = first teacher/admin)
insert into class_cancellations(course_code, class_date, reason, notified_by)
select 'PHY0533101', current_date + 3, 'Instructor on leave', p.id
from profiles p
where p.role in ('teacher','admin')
  and not exists (select 1 from class_cancellations where course_code='PHY0533101' and reason='Instructor on leave')
order by p.id limit 1;

-- 10. Extra help-centre articles unique to the merged features
-- (guarded by title so re-running never duplicates rows)
insert into knowledge(title, body)
select 'Lost & Found', 'Report a lost or found item, browse reported items, and claim a match. Claims are reviewed by the reporter or an admin.'
where not exists (select 1 from knowledge where title='Lost & Found');
insert into knowledge(title, body)
select 'Resources', 'Teachers and admins can share documents, links, videos and other resources with the campus community.'
where not exists (select 1 from knowledge where title='Resources');
insert into knowledge(title, body)
select 'Reading announcements', 'Announcements are posted by coordinators and admins and may be targeted at specific roles such as students, teachers or admins.'
where not exists (select 1 from knowledge where title='Reading announcements');
insert into knowledge(title, body)
select 'Maintenance reports', 'Report room problems such as a broken projector, lights or furniture. Admins can review and resolve reports.'
where not exists (select 1 from knowledge where title='Maintenance reports');
insert into knowledge(title, body)
select 'Class cancellations', 'A cancelled class appears here with its date and reason, posted by a teacher or an admin.'
where not exists (select 1 from knowledge where title='Class cancellations');
insert into knowledge(title, body)
select 'Calendar events and registration', 'CRs and admins can create calendar events with a date, time and capacity. Students can register for events.'
where not exists (select 1 from knowledge where title='Calendar events and registration');
insert into knowledge(title, body)
select 'Memberships and subscriptions', 'Memberships link a user to a program with a verification flag. Subscriptions record a user plan and its status.'
where not exists (select 1 from knowledge where title='Memberships and subscriptions');
insert into knowledge(title, body)
select 'Multi-university structure', 'The schema supports universities, departments, programs, courses and buildings so the pilot can be extended beyond one campus.'
where not exists (select 1 from knowledge where title='Multi-university structure');

-- =============================================================================
-- End of additive ER seed data.
-- =============================================================================