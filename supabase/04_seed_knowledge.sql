-- Help-centre text the AI assistant can quote. These describe how ClassSync works.
-- Add your university's real policy documents as more rows (title + body) once you have them.
insert into knowledge(title, body) values
('How to request an earlier class', 'Open Find a room, set the day and the time slot, and tap a green room. In the panel that opens, choose which of your classes should start then and press Send request to teacher. The slot must be as long as your class: a lecture is usually 1 period and a lab 2.'),
('Who approves a class shift', 'A student or CR request goes to the class teacher first. After the teacher agrees, the department coordinator gives final permission. Only then does the class move. A teacher request goes straight to the coordinator.'),
('Request statuses', 'Waiting for teacher, Teacher agreed and waiting for coordinator, Approved (class moved), Declined, or Cancelled. You can cancel a request while it is waiting, which frees the room.'),
('Why a room cannot be chosen', 'ClassSync checks that the room is free, that your batch has no other class then, that the teacher is not teaching then, that the class does not run across the lunch break, and that labs move only to labs and lectures only to lecture rooms.'),
('Lunch break', 'There is a lunch break between period 3 (ends 12:30) and period 4 (starts 13:00). A class cannot run across it.'),
('Period times', 'Period 1 08:30-09:50, period 2 09:50-11:10, period 3 11:10-12:30, period 4 13:00-14:20, period 5 14:20-15:40, period 6 15:40-17:00.'),
('Holding a room', 'A student can hold a free room for a study group. Other batches and departments then see it as taken. Release it when you no longer need it. A room held for a pending request is released if the request is declined or cancelled.'),
('Booking a room for an event or CR meeting', 'CRs can book a free room for a CR meeting, club event or seminar. Booked rooms show as unavailable to everyone. Admins can also block a room, for example for maintenance.'),
('Rooms and floors', 'Each floor has 8 lecture rooms and 6 computer labs. Room availability comes from the class routine plus holds, events and blocked rooms.'),
('Roles', 'Students see their timetable and can request shifts. CRs can also book events. Teachers approve requests for their own classes and can request a room for their class. Coordinators give final permission. Admins manage rooms, routines and blocked rooms.'),
('What ClassSync AI can and cannot do', 'ClassSync AI answers questions using the real timetable and room data you are allowed to see. It never approves or sends a request for you. To send a request, use the Send request button yourself.')
on conflict do nothing;
