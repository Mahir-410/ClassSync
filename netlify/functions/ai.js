'use strict';
/* ClassSync AI endpoint (Netlify Function).
   - The browser sends the user's Supabase login token. Every database read uses THAT token, so Row Level Security decides what the user may see.
   - Simple questions (free rooms, next class, pending requests) are answered straight from the database with no AI call.
   - Other questions: the database facts are given to a hosted model that only phrases them. It cannot approve, send or change anything.
   - The model key lives only in Netlify environment variables. */

const DAYN = ['Mon', 'Tue', 'Wed', 'Thu'];
const ST = [510, 590, 670, 780, 860, 940], EN = [590, 670, 750, 860, 940, 1020];   // period start/end in minutes
const hm = m => `${Math.floor(m / 60)}:${String(m % 60).padStart(2, '0')}`;
const slot = (d, a, b) => `${DAYN[d]} ${hm(ST[a])}-${hm(EN[b - 1])}`;
const json = (s, o) => ({ statusCode: s, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }, body: JSON.stringify(o) });
const enc = encodeURIComponent;

/* ---------- time helpers (Dhaka time) ---------- */
function dhaka(now) {
  const p = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Dhaka', weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(now);
  const g = t => p.find(x => x.type === t).value;
  return { wd: g('weekday'), min: +g('hour') * 60 + +g('minute') };
}
const periodFrom = min => { if (min < ST[0]) return 0; for (let i = 0; i < 6; i++) if (min < EN[i]) return i; return -1; };
function slotNow(now) {
  const { wd, min } = dhaka(now), d = DAYN.indexOf(wd);
  if (d < 0) return { day: 0, a: 0 };
  const p = periodFrom(min);
  return p < 0 ? { day: (d + 1) % 4, a: 0 } : { day: d, a: p };
}
function parseWhen(text, now) {
  const t = text.toLowerCase(), cur = slotNow(now);
  let { day, a } = cur;
  const dm = t.match(/\b(mon|tue|wed|thu)/);
  if (dm) day = DAYN.findIndex(x => x.toLowerCase() === dm[1]);
  if (/tomorrow/.test(t)) { const d0 = DAYN.indexOf(dhaka(now).wd); day = d0 < 0 ? 0 : (d0 + 1) % 4; a = 0; }
  const pm = t.match(/\bp(?:eriod)?\s*([1-6])\b/);
  const tm = t.match(/\b(\d{1,2})(?::(\d{2}))?\s?(am|pm)\b|\b(\d{1,2}):(\d{2})\b/);
  if (pm) a = +pm[1] - 1;
  else if (tm) {
    let h = +(tm[1] || tm[4]), mi = +(tm[2] || tm[5] || 0); const ap = tm[3];
    if (ap === 'pm' && h < 12) h += 12; if (ap === 'am' && h === 12) h = 0; if (!ap && h < 8) h += 12;
    const p = periodFrom(h * 60 + mi); a = p < 0 ? 5 : p;
  }
  const lab = /\blabs?\b/.test(t);
  let b = a + 1;
  if (lab) { b = Math.min(6, a + 2); if (a < 3 && b > 3) b = 3; }
  return { day, a, b, lab };
}
function intent(text, role) {
  const t = text.toLowerCase();
  if (role === 'admin' && /busiest|most (used|occupied)|usage|statistic|stats/.test(t)) return 'usage';
  if (/\b(pending|waiting)\b|my requests?|request status|status of (my )?request/.test(t)) return 'pending';
  if (/(free|empty|available|vacant)\b.*\b(room|lab|class)|\b(room|lab)s?\b.*\b(free|available|empty)|where can i (sit|study)/.test(t)) return 'rooms';
  if (/next class|my class(es)?|timetable|schedule|\bbreak\b|\bgap\b|free time|what do i have/.test(t)) return 'timetable';
  return 'faq';
}

/* ---------- Supabase (always with the user's own token) ---------- */
async function sb(path, token, init = {}) {
  const r = await fetch(process.env.SUPABASE_URL + path, { ...init, headers: { apikey: process.env.SUPABASE_ANON_KEY, authorization: 'Bearer ' + token, 'content-type': 'application/json', ...(init.headers || {}) } });
  if (!r.ok) return null;
  return r.json();
}
const rpc = (name, args, token) => sb('/rest/v1/rpc/' + name, token, { method: 'POST', body: JSON.stringify(args) });
async function getProfile(token) {
  const u = await sb('/auth/v1/user', token);
  if (!u || !u.id) return null;
  const rows = await sb(`/rest/v1/profiles?id=eq.${enc(u.id)}&select=role,batch,teacher_code`, token);
  return rows && rows[0] ? rows[0] : null;
}
async function myClasses(p, sem, day, token) {
  const f = p.role === 'teacher' ? `teacher_code=eq.${enc(p.teacher_code || '')}` : p.batch ? `batch=eq.${enc(p.batch)}` : null;
  if (!f) return null;
  return (await sb(`/rest/v1/classes?semester=eq.${enc(sem)}&${f}&day=eq.${day}&select=batch,period,periods,course,room&order=period`, token)) || [];
}
const openRequests = (sem, token) => sb(`/rest/v1/shift_requests?semester=eq.${enc(sem)}&status=in.(pending,coord)&select=batch,course,day,to_period,to_room,status&order=created_at.desc&limit=10`, token);

/* ---------- plain answers from database rows (no AI) ---------- */
function roomsText(rows, s) {
  if (!rows.length) return `No room is free ${s}. Try another time.`;
  const by = {};
  rows.forEach(r => { (by[r.floor] ??= { l: [], b: [] })[r.is_lab ? 'b' : 'l'].push(r.name); });
  const lines = Object.keys(by).sort().map(f => `${f === 'G' ? 'Ground' : 'Floor ' + f}: ${by[f].l.slice(0, 6).join(', ') || 'no lecture rooms'}${by[f].b.length ? ' | labs ' + by[f].b.slice(0, 4).join(', ') : ''}`);
  return `${rows.length} rooms are free ${s}:\n${lines.join('\n')}\nTo ask for one, open Find a room and tap it.`;
}
function ttText(rows, d, now) {
  if (!rows.length) return `No classes on ${DAYN[d]}.`;
  const line = r => `${hm(ST[r.period])}-${hm(EN[r.period + r.periods - 1])} ${r.batch ? r.batch + ' ' : ''}${r.course} (room ${r.room})`;
  let out = `Classes on ${DAYN[d]}:\n${rows.map(line).join('\n')}`;
  const cur = dhaka(now);
  if (DAYN.indexOf(cur.wd) === d) {
    const nx = rows.find(r => EN[r.period + r.periods - 1] > cur.min);
    out += `\nNext: ${nx ? line(nx) : 'no more classes today'}`;
  }
  let best = null;
  for (let i = 1; i < rows.length; i++) {
    const from = EN[rows[i - 1].period + rows[i - 1].periods - 1], to = ST[rows[i].period], g = to - from;
    if (rows[i].period > rows[i - 1].period + rows[i - 1].periods && (!best || g > best.g)) best = { g, from, to };
  }
  return out + (best ? `\nLongest break: ${Math.floor(best.g / 60)}h ${best.g % 60}m (${hm(best.from)}-${hm(best.to)}). Tap it in Today to look for a room.` : '\nNo break between your classes.');
}
function pendText(rows) {
  if (!rows || !rows.length) return 'No requests are waiting.';
  return `${rows.length} request${rows.length > 1 ? 's' : ''} waiting:\n` + rows.map(r => `${r.batch} ${r.course}, ${DAYN[r.day]} to ${hm(ST[r.to_period])} in room ${r.to_room}: ${r.status === 'pending' ? 'waiting for the teacher' : 'waiting for the coordinator'}`).join('\n');
}

/* ---------- model call (optional) ---------- */
const SYSTEM = `You are ClassSync AI, a short, friendly assistant inside a university room-and-timetable app.
Rules: use ONLY the FACTS given. If the facts do not contain the answer, say you do not know and point to the right ClassSync page. Never invent rooms, times, names or policies.
You cannot approve, send, cancel or change anything. To send a request the user must press the Send request button themselves.
Answer in at most 5 short lines, plain text, no markdown tables. Times use the 24-hour format shown in the facts.`;
async function ask(history, user) {
  const model = process.env.GEMINI_MODEL, key = process.env.GEMINI_API_KEY;
  if (!model || !key) return null;
  const ctl = new AbortController(), timer = setTimeout(() => ctl.abort(), 8000);
  try {
    const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${enc(model)}:generateContent`, {
      method: 'POST', signal: ctl.signal, headers: { 'content-type': 'application/json', 'x-goog-api-key': key },
      body: JSON.stringify({ systemInstruction: { parts: [{ text: SYSTEM }] }, contents: [...history, { role: 'user', parts: [{ text: user }] }], generationConfig: { maxOutputTokens: 350, temperature: 0.2 } }) });
    if (!r.ok) return null;
    const j = await r.json();
    const t = ((j.candidates && j.candidates[0] && j.candidates[0].content && j.candidates[0].content.parts) || []).map(p => p.text || '').join('').trim();
    return t || null;
  } catch (e) { return null; } finally { clearTimeout(timer); }
}
function cleanHistory(h) {
  const out = (Array.isArray(h) ? h : []).slice(-6).map(x => ({ role: x && x.role === 'ai' ? 'model' : 'user', parts: [{ text: String((x && x.text) || '').slice(0, 300) }] }));
  while (out.length && out[0].role !== 'user') out.shift();
  return out;
}

const cache = new Map();   // short-lived answers for general (non-personal) questions
const TTL = 10 * 60 * 1000;

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') return json(405, { error: 'POST only.' });
  if (!process.env.SUPABASE_URL || !process.env.SUPABASE_ANON_KEY) return json(500, { error: 'The server is not configured yet (Supabase settings missing).' });
  const token = String((event.headers && (event.headers.authorization || event.headers.Authorization)) || '').replace(/^Bearer\s+/i, '');
  if (!token) return json(401, { error: 'Please log in first.' });
  let body; try { body = JSON.parse(event.body || '{}'); } catch (e) { return json(400, { error: 'Bad request.' }); }
  const message = String(body.message || '').trim().slice(0, 500);
  if (!message) return json(400, { error: 'Type a question first.' });

  const now = event._now ? new Date(event._now) : new Date();
  const sem = process.env.CURRENT_SEMESTER || 'Fall 2026';
  const p = await getProfile(token);
  if (!p) return json(401, { error: 'Your session expired. Please log in again.' });
  const kind = intent(message, p.role), w = parseWhen(message, now);

  /* 1. answers straight from the database: no AI call, no cost */
  if (kind === 'rooms') {
    const rows = await rpc('free_rooms', { p_sem: sem, p_day: w.day, p_a: w.a, p_b: w.b, p_lab: w.lab ? true : null }, token);
    if (rows) return json(200, { reply: roomsText(rows, slot(w.day, w.a, w.b)), via: 'database' });
  }
  if (kind === 'timetable') {
    const rows = await myClasses(p, sem, w.day, token);
    if (rows === null) return json(200, { reply: p.role === 'student' || p.role === 'cr' ? 'Your profile has no batch yet. Ask an admin to set it.' : 'I can show timetables for students and teachers.', via: 'database' });
    return json(200, { reply: ttText(rows, w.day, now), via: 'database' });
  }
  if (kind === 'pending') return json(200, { reply: pendText(await openRequests(sem, token)), via: 'database' });
  if (kind === 'usage') {
    const rows = await rpc('room_usage', { p_sem: sem }, token);
    if (rows) return json(200, { reply: 'Busiest rooms (periods used per week):\n' + rows.slice(0, 8).map(r => `${r.room}: ${r.periods_used}`).join('\n'), via: 'database' });
  }

  /* 2. general questions: help-centre text, optionally phrased by the model */
  const kn = (await rpc('search_knowledge', { q: message }, token)) || [];
  const fallback = kn.length ? kn[0].body : 'I could not find that. Try asking about free rooms, your next class, requests, or how ClassSync works.';
  const personal = /\b(my|me|i|gap|break|compare)\b|which room|best room/i.test(message);   // personal questions get the user's own facts and are never cached
  const key = p.role + '|' + message.toLowerCase().replace(/\s+/g, ' ');
  const hit = !personal && cache.get(key);
  if (hit && Date.now() - hit.t < TTL) return json(200, { reply: hit.reply, via: 'cache' });
  if ((!kn.length && !personal) || !process.env.GEMINI_MODEL || !process.env.GEMINI_API_KEY) return json(200, { reply: fallback, via: 'database' });
  const okQuota = await rpc('ai_take_quota', { p_limit: +process.env.AI_DAILY_LIMIT || 30 }, token);
  if (okQuota !== true) return json(200, { reply: fallback + '\n(AI daily limit reached, showing the help text.)', via: 'database' });
  let facts = `Role: ${p.role}\n` + kn.map(k => `- ${k.title}: ${k.body}`).join('\n');
  if (personal) {
    const [cl, fr, pr] = await Promise.all([myClasses(p, sem, w.day, token), rpc('free_rooms', { p_sem: sem, p_day: w.day, p_a: w.a, p_b: w.b, p_lab: w.lab ? true : null }, token), openRequests(sem, token)]);
    facts += `\nSlot assumed: ${slot(w.day, w.a, w.b)}\nUser's classes that day:\n${cl && cl.length ? ttText(cl, w.day, now).slice(0, 500) : 'none or unknown'}\nFree rooms in that slot:\n${fr ? roomsText(fr, slot(w.day, w.a, w.b)).slice(0, 600) : 'unknown'}\nOpen requests:\n${pendText(pr).slice(0, 400)}`;
  }
  const text = await ask(cleanHistory(body.history), `FACTS (from the ClassSync database and help centre):\n${facts}\n\nQUESTION: ${message}`);
  if (!text) return json(200, { reply: fallback, via: 'database' });
  const reply = text.slice(0, 1200);
  if (!personal) { cache.set(key, { t: Date.now(), reply }); if (cache.size > 200) cache.delete(cache.keys().next().value); }
  return json(200, { reply, via: 'ai' });
};
exports._t = { parseWhen, intent, slotNow, ttText, roomsText, cleanHistory };
