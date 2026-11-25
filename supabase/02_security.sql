-- Row Level Security. Run after 01_schema.sql.
alter table profiles enable row level security;
alter table rooms enable row level security;
alter table classes enable row level security;
alter table shift_requests enable row level security;
alter table room_holds enable row level security;
alter table room_events enable row level security;
alter table reviews enable row level security;
alter table knowledge enable row level security;
alter table ai_usage enable row level security;

drop policy if exists p_read on profiles;
create policy p_read on profiles for select to authenticated using (id = auth.uid() or my_role() = 'admin');
drop policy if exists p_upd on profiles;
create policy p_upd on profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
revoke update on profiles from authenticated;
grant update (full_name) on profiles to authenticated;

drop policy if exists r_read on rooms;    create policy r_read on rooms for select to authenticated using (true);
drop policy if exists r_admin on rooms;   create policy r_admin on rooms for all to authenticated using (my_role()='admin') with check (my_role()='admin');
drop policy if exists c_read on classes;  create policy c_read on classes for select to authenticated using (true);
drop policy if exists c_admin on classes; create policy c_admin on classes for all to authenticated using (my_role()='admin') with check (my_role()='admin');

drop policy if exists q_read on shift_requests;
create policy q_read on shift_requests for select to authenticated using (
  my_role() in ('coord','admin')
  or (my_role() in ('student','cr') and batch = my_batch())
  or (my_role() = 'teacher' and teacher_code = my_teacher()));

drop policy if exists h_read on room_holds;  create policy h_read on room_holds for select to authenticated using (true);
drop policy if exists h_del on room_holds;   create policy h_del on room_holds for delete to authenticated using (request_id is null and (created_by = auth.uid() or my_role()='admin'));
drop policy if exists e_read on room_events; create policy e_read on room_events for select to authenticated using (true);
drop policy if exists e_del on room_events;  create policy e_del on room_events for delete to authenticated using (created_by = auth.uid() or my_role()='admin');

drop policy if exists v_read on reviews; create policy v_read on reviews for select to anon, authenticated using (true);
drop policy if exists v_ins on reviews;  create policy v_ins on reviews for insert to authenticated with check (user_id = auth.uid());
drop policy if exists v_del on reviews;  create policy v_del on reviews for delete to authenticated using (my_role()='admin');

drop policy if exists k_read on knowledge;  create policy k_read on knowledge for select to authenticated using (true);
drop policy if exists k_admin on knowledge; create policy k_admin on knowledge for all to authenticated using (my_role()='admin') with check (my_role()='admin');

revoke execute on all functions in schema public from public, anon;
grant execute on function my_role(), my_batch(), my_teacher() to authenticated;
grant execute on function request_shift(bigint,int,text), decide_request(bigint,boolean), cancel_request(bigint), mark_request_seen(bigint) to authenticated;
grant execute on function book_room(text,text,text,int,int,int,text), free_rooms(text,int,int,int,boolean), room_usage(text), search_knowledge(text), ai_take_quota(int) to authenticated;
