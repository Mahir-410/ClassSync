-- ClassSync live pilot hardening. Run AFTER 01_schema.sql through 05_pilot_chat.sql.
-- Adds atomic shared room holds, chat blocking/reporting, and safer matching.

create extension if not exists pgcrypto;

create table if not exists public.chat_user_blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table if not exists public.chat_reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_id uuid not null references auth.users(id) on delete cascade,
  room_id uuid references public.random_chat_rooms(id) on delete set null,
  reason text not null check (char_length(reason) between 3 and 500),
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  check (reporter_id <> reported_id)
);
create index if not exists chat_reports_status_created on public.chat_reports(status, created_at desc);

alter table public.chat_user_blocks enable row level security;
alter table public.chat_reports enable row level security;

-- No direct client reads/writes of block lists or reports. Use the RPCs below.
revoke all on public.chat_user_blocks, public.chat_reports from anon, authenticated;
grant select on public.chat_reports to authenticated;

drop policy if exists chat_report_admin_read on public.chat_reports;
create policy chat_report_admin_read on public.chat_reports for select to authenticated
  using (public.my_role() = 'admin');

create or replace function public.create_room_hold(
  p_semester text, p_room text, p_day integer, p_from_period integer,
  p_to_period integer, p_note text default 'Study session'
) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_id bigint; v_batch text;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if public.my_role() not in ('student','cr','teacher','coord','admin') then raise exception 'Pilot account required'; end if;
  if p_semester is null or length(trim(p_semester)) = 0 then raise exception 'Semester is required'; end if;
  if p_day not between 0 and 3 or p_from_period not between 0 and 5 or p_to_period not between 1 and 6 or p_from_period >= p_to_period then
    raise exception 'Choose a valid day and period range';
  end if;
  if p_from_period < 3 and p_to_period > 3 then raise exception 'A hold cannot cross the lunch break'; end if;
  if char_length(coalesce(p_note,'')) > 120 then raise exception 'Note must be 120 characters or fewer'; end if;
  -- Serialize requests for the same room/day so simultaneous users cannot double-book.
  perform pg_advisory_xact_lock(hashtext(p_semester || ':' || p_room || ':' || p_day)::bigint);
  if not exists(select 1 from public.rooms where name = p_room) then raise exception 'Unknown room'; end if;
  if not public.room_free(p_semester,p_room,p_day,p_from_period,p_to_period,null,null) then
    raise exception 'That room is already occupied or held for this time';
  end if;
  v_batch := coalesce(public.my_batch(),'Pilot');
  insert into public.room_holds(semester,room,day,from_period,to_period,batch,note,created_by)
    values(p_semester,p_room,p_day,p_from_period,p_to_period,v_batch,coalesce(nullif(trim(p_note),''),'Study session'),auth.uid())
    returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.release_room_hold(p_hold_id bigint) returns boolean
language plpgsql security definer set search_path = public
as $$
declare v_count integer;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  delete from public.room_holds
    where id=p_hold_id and request_id is null
      and (created_by=auth.uid() or public.my_role()='admin');
  get diagnostics v_count = row_count;
  if v_count=0 then raise exception 'Hold not found or you are not allowed to release it'; end if;
  return true;
end;
$$;

create or replace function public.block_chat_user(p_user_id uuid) returns void
language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if p_user_id is null or p_user_id=auth.uid() then raise exception 'Invalid user'; end if;
  insert into public.chat_user_blocks(blocker_id,blocked_id) values(auth.uid(),p_user_id) on conflict do nothing;
  delete from public.random_chat_queue where user_id in (auth.uid(),p_user_id);
  update public.random_chat_rooms set status='ended'
   where status='active' and ((user_a=auth.uid() and user_b=p_user_id) or (user_a=p_user_id and user_b=auth.uid()));
end;
$$;

create or replace function public.report_chat_user(p_room_id uuid, p_reason text) returns bigint
language plpgsql security definer set search_path = public
as $$
declare v_other uuid; v_id bigint;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  if char_length(trim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'Please provide a reason (3–500 characters)'; end if;
  select case when user_a=auth.uid() then user_b else user_a end into v_other
    from public.random_chat_rooms where id=p_room_id and auth.uid() in (user_a,user_b);
  if v_other is null then raise exception 'Chat not found'; end if;
  insert into public.chat_reports(reporter_id,reported_id,room_id,reason)
    values(auth.uid(),v_other,p_room_id,trim(p_reason)) returning id into v_id;
  perform public.block_chat_user(v_other);
  return v_id;
end;
$$;

-- Replace matching so blocked pairs are never matched, including blocks in either direction.
create or replace function public.find_random_chat()
returns table(room_id uuid, matched boolean)
language plpgsql security definer set search_path=public
as $$
declare me uuid := auth.uid(); other_user uuid; new_room uuid;
begin
  if me is null then raise exception 'Login required'; end if;
  perform pg_advisory_xact_lock(hashtext('classsync-random-chat-match')::bigint);
  if exists(select 1 from public.random_chat_rooms r where r.status='active' and me in (r.user_a,r.user_b)) then
    return query select r.id,true from public.random_chat_rooms r where r.status='active' and me in (r.user_a,r.user_b) order by r.created_at desc limit 1;
    return;
  end if;
  delete from public.random_chat_queue where queued_at < now() - interval '15 minutes';
  insert into public.random_chat_queue(user_id) values(me) on conflict(user_id) do nothing;
  select q.user_id into other_user from public.random_chat_queue q
   where q.user_id<>me
    and not exists(select 1 from public.chat_user_blocks b where (b.blocker_id=me and b.blocked_id=q.user_id) or (b.blocker_id=q.user_id and b.blocked_id=me))
   order by q.queued_at for update skip locked limit 1;
  if other_user is null then return query select null::uuid,false; return; end if;
  delete from public.random_chat_queue where user_id in (me,other_user);
  insert into public.random_chat_rooms(user_a,user_b) values(me,other_user) returning id into new_room;
  return query select new_room,true;
end;
$$;

-- Ensure ended/blocked conversations cannot be used to send messages.
drop policy if exists chat_message_send on public.random_chat_messages;
create policy chat_message_send on public.random_chat_messages for insert to authenticated
with check (
 sender_id=auth.uid() and exists(
  select 1 from public.random_chat_rooms r where r.id=room_id and r.status='active'
   and auth.uid() in (r.user_a,r.user_b)
   and not exists(select 1 from public.chat_user_blocks b where
     (b.blocker_id=r.user_a and b.blocked_id=r.user_b) or (b.blocker_id=r.user_b and b.blocked_id=r.user_a))
 )
);

-- Restrict direct queue access; matching is via the security-definer function only.
revoke all on public.random_chat_queue from anon, authenticated;
revoke all on function public.create_room_hold(text,text,integer,integer,integer,text) from public;
revoke all on function public.release_room_hold(bigint) from public;
revoke all on function public.block_chat_user(uuid) from public;
revoke all on function public.report_chat_user(uuid,text) from public;
revoke all on function public.find_random_chat() from public;
grant execute on function public.create_room_hold(text,text,integer,integer,integer,text) to authenticated;
grant execute on function public.release_room_hold(bigint) to authenticated;
grant execute on function public.block_chat_user(uuid) to authenticated;
grant execute on function public.report_chat_user(uuid,text) to authenticated;
grant execute on function public.find_random_chat() to authenticated;

-- Clients can see shared holds, but may only delete their own non-request holds via release_room_hold.
drop policy if exists h_del on public.room_holds;
create policy h_del on public.room_holds for delete to authenticated
 using (request_id is null and (created_by=auth.uid() or public.my_role()='admin'));


-- Remove message-history visibility once either participant blocks the other.
drop policy if exists chat_message_read on public.random_chat_messages;
create policy chat_message_read on public.random_chat_messages for select to authenticated
using (exists(
  select 1 from public.random_chat_rooms r where r.id=room_id
   and auth.uid() in (r.user_a,r.user_b)
   and not exists(select 1 from public.chat_user_blocks b where
     (b.blocker_id=r.user_a and b.blocked_id=r.user_b) or (b.blocker_id=r.user_b and b.blocked_id=r.user_a))
));
revoke all on function public.leave_random_chat(uuid) from public, anon;
grant execute on function public.leave_random_chat(uuid) to authenticated;
