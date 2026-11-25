-- ClassSync pilot: private, authenticated random chat.
-- Run after 01_schema.sql and 02_security.sql.
create table if not exists public.random_chat_queue (
  user_id uuid primary key references auth.users(id) on delete cascade,
  queued_at timestamptz not null default now()
);
create table if not exists public.random_chat_rooms (
  id uuid primary key default gen_random_uuid(),
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active','ended')),
  created_at timestamptz not null default now(),
  check (user_a <> user_b)
);
create table if not exists public.random_chat_messages (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.random_chat_rooms(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);
alter table public.random_chat_queue enable row level security;
alter table public.random_chat_rooms enable row level security;
alter table public.random_chat_messages enable row level security;
drop policy if exists chat_room_read on public.random_chat_rooms;
create policy chat_room_read on public.random_chat_rooms for select to authenticated
using (auth.uid() in (user_a,user_b));
drop policy if exists chat_message_read on public.random_chat_messages;
create policy chat_message_read on public.random_chat_messages for select to authenticated
using (exists(select 1 from public.random_chat_rooms r where r.id=room_id and auth.uid() in (r.user_a,r.user_b)));
drop policy if exists chat_message_send on public.random_chat_messages;
create policy chat_message_send on public.random_chat_messages for insert to authenticated
with check (sender_id=auth.uid() and exists(select 1 from public.random_chat_rooms r where r.id=room_id and r.status='active' and auth.uid() in (r.user_a,r.user_b)));
revoke all on public.random_chat_queue, public.random_chat_rooms, public.random_chat_messages from anon;
grant select on public.random_chat_rooms, public.random_chat_messages to authenticated;
grant insert on public.random_chat_messages to authenticated;

create or replace function public.find_random_chat()
returns table(room_id uuid, matched boolean)
language plpgsql security definer set search_path=public
as $$
declare me uuid := auth.uid(); other_user uuid; new_room uuid;
begin
  if me is null then raise exception 'Login required'; end if;
  if exists(select 1 from public.random_chat_rooms r where r.status='active' and me in (r.user_a,r.user_b)) then
    return query select r.id, true from public.random_chat_rooms r where r.status='active' and me in (r.user_a,r.user_b) order by r.created_at desc limit 1;
    return;
  end if;
  insert into public.random_chat_queue(user_id) values(me) on conflict(user_id) do nothing;
  select q.user_id into other_user from public.random_chat_queue q
    where q.user_id <> me order by q.queued_at for update skip locked limit 1;
  if other_user is null then
    return query select null::uuid, false;
    return;
  end if;
  delete from public.random_chat_queue where user_id in (me,other_user);
  insert into public.random_chat_rooms(user_a,user_b) values(me,other_user) returning id into new_room;
  return query select new_room, true;
end $$;
create or replace function public.leave_random_chat(p_room uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
  update public.random_chat_rooms set status='ended'
  where id=p_room and auth.uid() in (user_a,user_b);
  delete from public.random_chat_queue where user_id=auth.uid();
end $$;
grant execute on function public.find_random_chat() to authenticated;
grant execute on function public.leave_random_chat(uuid) to authenticated;
