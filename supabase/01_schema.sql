-- ClassSync database. Run once in Supabase: SQL Editor > New query > paste > Run.
-- Order: 01_schema.sql, 02_security.sql, 03_seed_routine.sql, 04_seed_knowledge.sql.
-- Periods are numbered 0..5 (P1..P6). A class takes `periods` slots. Days: 0=Mon .. 3=Thu.

create table if not exists profiles(
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'student' check (role in ('student','cr','teacher','coord','admin')),
  batch text,
  teacher_code text,
  created_at timestamptz not null default now());

create table if not exists rooms(
  name text primary key,
  floor text not null,
  is_lab boolean not null default false,
  capacity int not null default 60,
  is_spare boolean not null default false);

create table if not exists classes(
  id bigint generated always as identity primary key,
  semester text not null,
  batch text not null,
  day smallint not null check (day between 0 and 3),
  period smallint not null check (period between 0 and 5),
  periods smallint not null default 1 check (periods in (1,2)),
  course text not null,
  teacher_code text not null,
  room text not null references rooms(name),
  check (period + periods <= 6),
  check (not (period < 3 and period + periods > 3)));
create index if not exists classes_slot on classes(semester, day, room);
create index if not exists classes_batch on classes(semester, batch);
create index if not exists classes_teacher on classes(semester, teacher_code);

create table if not exists shift_requests(
  id bigint generated always as identity primary key,
  semester text not null,
  class_id bigint not null references classes(id) on delete cascade,
  batch text not null,
  course text not null,
  teacher_code text not null,
  day smallint not null,
  periods smallint not null,
  from_period smallint not null,
  from_room text not null,
  to_period smallint not null,
  to_room text not null references rooms(name),
  status text not null default 'pending' check (status in ('pending','coord','approved','declined','cancelled')),
  requested_by uuid references auth.users(id),
  requested_by_role text,
  seen boolean not null default false,
  created_at timestamptz not null default now(),
  decided_at timestamptz);

create table if not exists room_holds(
  id bigint generated always as identity primary key,
  semester text not null,
  room text not null references rooms(name),
  day smallint not null,
  from_period smallint not null,
  to_period smallint not null,
  batch text,
  note text,
  request_id bigint references shift_requests(id) on delete cascade,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now());

create table if not exists room_events(
  id bigint generated always as identity primary key,
  semester text not null,
  room text not null references rooms(name),
  day smallint not null,
  from_period smallint not null,
  to_period smallint not null,
  kind text not null check (kind in ('event','block')),
  title text not null,
  batch text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now());

create table if not exists reviews(
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  role text not null,
  stars smallint not null check (stars between 1 and 5),
  body text not null check (char_length(body) between 5 and 300),
  created_at timestamptz not null default now());

create table if not exists knowledge(
  id bigint generated always as identity primary key,
  title text not null,
  body text not null,
  tsv tsvector generated always as (to_tsvector('english', title || ' ' || body)) stored);
create index if not exists knowledge_tsv on knowledge using gin(tsv);

create table if not exists ai_usage(
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null,
  n int not null default 0,
  primary key (user_id, day));

create or replace function my_role() returns text language sql stable security definer set search_path=public as
$$ select role from profiles where id = auth.uid() $$;
create or replace function my_batch() returns text language sql stable security definer set search_path=public as
$$ select batch from profiles where id = auth.uid() $$;
create or replace function my_teacher() returns text language sql stable security definer set search_path=public as
$$ select teacher_code from profiles where id = auth.uid() $$;

create or replace function room_free(p_sem text, p_room text, p_day int, p_a int, p_b int, p_ign_class bigint default null, p_ign_req bigint default null)
returns boolean language sql stable security definer set search_path=public as $$
  select not exists (select 1 from classes where semester=p_sem and room=p_room and day=p_day and (p_ign_class is null or id<>p_ign_class) and period < p_b and p_a < period+periods)
     and not exists (select 1 from room_holds where semester=p_sem and room=p_room and day=p_day and (p_ign_req is null or request_id is null or request_id<>p_ign_req) and from_period < p_b and p_a < to_period)
     and not exists (select 1 from room_events where semester=p_sem and room=p_room and day=p_day and from_period < p_b and p_a < to_period)
$$;

create or replace function teacher_free(p_sem text, p_teacher text, p_day int, p_a int, p_b int, p_ign_class bigint default null)
returns boolean language sql stable security definer set search_path=public as $$
  select not exists (select 1 from classes where semester=p_sem and teacher_code=p_teacher and day=p_day and (p_ign_class is null or id<>p_ign_class) and period < p_b and p_a < period+periods)
$$;

create or replace function batch_free(p_sem text, p_batch text, p_day int, p_a int, p_b int, p_ign_class bigint default null)
returns boolean language sql stable security definer set search_path=public as $$
  select not exists (select 1 from classes where semester=p_sem and batch=p_batch and day=p_day and (p_ign_class is null or id<>p_ign_class) and period < p_b and p_a < period+periods)
$$;

-- Single source of truth: can this class move there? (room, batch, teacher, lunch, lab/lecture)
create or replace function check_move(p_class bigint, p_to_period int, p_to_room text, p_ign_req bigint default null)
returns text language plpgsql security definer set search_path=public as $$
declare c classes; r rooms; fr rooms; b int;
begin
  select * into c from classes where id = p_class;
  if not found then return 'Class not found.'; end if;
  select * into r from rooms where name = p_to_room;
  if not found then return 'Room not found.'; end if;
  select * into fr from rooms where name = c.room;
  b := p_to_period + c.periods;
  if p_to_period < 0 or b > 6 then return 'Invalid period.'; end if;
  if p_to_period < 3 and b > 3 then return 'A class cannot run across the lunch break.'; end if;
  if r.is_lab <> fr.is_lab then return 'Labs move only to labs, lectures only to lecture rooms.'; end if;
  if not room_free(c.semester, p_to_room, c.day, p_to_period, b, p_class, p_ign_req) then return 'That room is not free then.'; end if;
  if not teacher_free(c.semester, c.teacher_code, c.day, p_to_period, b, p_class) then return 'The teacher has another class then.'; end if;
  if not batch_free(c.semester, c.batch, c.day, p_to_period, b, p_class) then return 'The batch has another class then.'; end if;
  return null;
end $$;

create or replace function request_shift(p_class bigint, p_to_period int, p_to_room text)
returns bigint language plpgsql security definer set search_path=public as $$
declare c classes; v_role text := my_role(); v_status text; v_err text; v_id bigint;
begin
  select * into c from classes where id = p_class;
  if not found then raise exception 'Class not found'; end if;
  perform pg_advisory_xact_lock(hashtext(c.semester || ':' || p_to_room || ':' || c.day)::bigint);
  if v_role in ('student','cr') and c.batch = my_batch() then v_status := 'pending';
  elsif v_role = 'teacher' and c.teacher_code = my_teacher() then v_status := 'coord';
  else raise exception 'You cannot request a shift for this class'; end if;
  if exists (select 1 from shift_requests where class_id = p_class and status in ('pending','coord')) then
    raise exception 'This class already has an open request'; end if;
  v_err := check_move(p_class, p_to_period, p_to_room);
  if v_err is not null then raise exception '%', v_err; end if;
  insert into shift_requests(semester,class_id,batch,course,teacher_code,day,periods,from_period,from_room,to_period,to_room,status,requested_by,requested_by_role)
    values (c.semester,c.id,c.batch,c.course,c.teacher_code,c.day,c.periods,c.period,c.room,p_to_period,p_to_room,v_status,auth.uid(),v_role) returning id into v_id;
  insert into room_holds(semester,room,day,from_period,to_period,batch,note,request_id,created_by)
    values (c.semester,p_to_room,c.day,p_to_period,p_to_period + c.periods,c.batch,c.course || ' (request)',v_id,auth.uid());
  return v_id;
end $$;

create or replace function decide_request(p_id bigint, p_approve boolean)
returns text language plpgsql security definer set search_path=public as $$
declare q shift_requests; v_role text := my_role(); v_err text;
begin
  select * into q from shift_requests where id = p_id for update;
  if not found then raise exception 'Request not found'; end if;
  perform pg_advisory_xact_lock(hashtext(q.semester || ':' || q.to_room || ':' || q.day)::bigint);
  if q.status = 'pending' and (v_role = 'admin' or (v_role = 'teacher' and q.teacher_code = my_teacher())) then null;
  elsif q.status = 'coord' and v_role in ('coord','admin') then null;
  else raise exception 'This request is not waiting for you'; end if;
  if not p_approve then
    update shift_requests set status='declined', seen=false, decided_at=now() where id = p_id;
    delete from room_holds where request_id = p_id; return 'declined';
  end if;
  v_err := check_move(q.class_id, q.to_period, q.to_room, p_id);
  if v_err is not null then
    update shift_requests set status='declined', seen=false, decided_at=now() where id = p_id;
    delete from room_holds where request_id = p_id; return 'declined: ' || v_err;
  end if;
  if q.status = 'pending' then
    update shift_requests set status='coord' where id = p_id; return 'coord';
  end if;
  update classes set period = q.to_period, room = q.to_room where id = q.class_id;
  delete from room_holds where request_id = p_id;
  update shift_requests set status='approved', seen=false, decided_at=now() where id = p_id;
  return 'approved';
end $$;

create or replace function cancel_request(p_id bigint)
returns void language plpgsql security definer set search_path=public as $$
declare q shift_requests;
begin
  select * into q from shift_requests where id = p_id for update;
  if not found or q.status not in ('pending','coord') then raise exception 'Nothing to cancel'; end if;
  if q.requested_by is distinct from auth.uid() and my_role() <> 'admin' then raise exception 'Not your request'; end if;
  update shift_requests set status='cancelled' where id = p_id;
  delete from room_holds where request_id = p_id;
end $$;

create or replace function mark_request_seen(p_id bigint)
returns void language sql security definer set search_path=public as
$$ update shift_requests set seen = true where id = p_id and requested_by = auth.uid() $$;

create or replace function book_room(p_kind text, p_sem text, p_room text, p_day int, p_a int, p_b int, p_title text default null)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_role text := my_role(); v_id bigint;
begin
  if p_kind not in ('hold','event','block') then raise exception 'Unknown kind'; end if;
  if p_a < 0 or p_b > 6 or p_b <= p_a or p_day not between 0 and 3 then raise exception 'Invalid time'; end if;
  if p_a < 3 and p_b > 3 then raise exception 'A booking cannot cross the lunch break'; end if;
  if p_kind = 'hold' and v_role not in ('student','cr') then raise exception 'Not allowed'; end if;
  if p_kind = 'event' and v_role not in ('cr','admin') then raise exception 'Only CRs and admins can book events'; end if;
  if p_kind = 'block' and v_role is distinct from 'admin' then raise exception 'Only admins can block rooms'; end if;
  if not exists (select 1 from rooms where name = p_room) then raise exception 'Room not found'; end if;
  perform pg_advisory_xact_lock(hashtext(p_sem || ':' || p_room || ':' || p_day)::bigint);
  if not room_free(p_sem, p_room, p_day, p_a, p_b) then raise exception 'That room is not free then'; end if;
  if p_kind = 'hold' then
    insert into room_holds(semester,room,day,from_period,to_period,batch,note,created_by)
      values (p_sem,p_room,p_day,p_a,p_b,my_batch(),coalesce(nullif(p_title,''),'Study group'),auth.uid()) returning id into v_id;
  else
    insert into room_events(semester,room,day,from_period,to_period,kind,title,batch,created_by)
      values (p_sem,p_room,p_day,p_a,p_b,p_kind,coalesce(nullif(p_title,''),case when p_kind='block' then 'Unavailable' else 'Event' end),coalesce(my_batch(),'Admin'),auth.uid()) returning id into v_id;
  end if;
  return v_id;
end $$;

create or replace function free_rooms(p_sem text, p_day int, p_a int, p_b int, p_lab boolean default null)
returns table(name text, floor text, is_lab boolean, capacity int) language sql stable security definer set search_path=public as $$
  select r.name, r.floor, r.is_lab, r.capacity from rooms r
  where auth.uid() is not null and (p_lab is null or r.is_lab = p_lab) and room_free(p_sem, r.name, p_day, p_a, p_b)
  order by r.floor, r.is_lab, r.name
$$;

create or replace function room_usage(p_sem text)
returns table(room text, periods_used bigint) language plpgsql stable security definer set search_path=public as $$
begin
  if my_role() is distinct from 'admin' then raise exception 'Admins only'; end if;
  return query select c.room, sum(c.periods)::bigint from classes c where c.semester = p_sem group by c.room order by 2 desc limit 10;
end $$;

create or replace function search_knowledge(q text)
returns table(title text, body text) language sql stable security definer set search_path=public as $$
  select k.title, k.body from knowledge k
  where auth.uid() is not null and k.tsv @@ websearch_to_tsquery('english', q)
  order by ts_rank(k.tsv, websearch_to_tsquery('english', q)) desc limit 3
$$;

create or replace function ai_take_quota(p_limit int)
returns boolean language plpgsql security definer set search_path=public as $$
declare v int;
begin
  if auth.uid() is null then return false; end if;
  insert into ai_usage(user_id, day, n) values (auth.uid(), current_date, 1)
    on conflict (user_id, day) do update set n = ai_usage.n + 1 returning n into v;
  return v <= p_limit;
end $$;

create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id, full_name, role, batch)
  values (new.id, nullif(left(coalesce(new.raw_user_meta_data->>'full_name',''),60),''), 'student', nullif(left(coalesce(new.raw_user_meta_data->>'batch',''),10),''))
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();
