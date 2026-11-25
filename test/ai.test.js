// Run: node test/ai.test.js   (no installs needed). Uses fake Supabase and fake Gemini servers via a mocked fetch.
const assert = require('assert');
process.env.SUPABASE_URL = 'https://x.supabase.co'; process.env.SUPABASE_ANON_KEY = 'anon';
process.env.GEMINI_API_KEY = 'SECRET-KEY-123'; process.env.GEMINI_MODEL = 'test-model'; process.env.AI_DAILY_LIMIT = '3';
const { handler, _t } = require('../netlify/functions/ai.js');

let calls, state;
const reset = (role = 'student') => { calls = { gemini: 0, quota: 0, geminiBody: null, geminiHeaders: null, paths: [] };
  state = { role, quota: true, gemini: 'ok', kn: [{ title: 'Who approves', body: 'Teacher first, then the coordinator.' }], tokenOk: true }; };
const ok = (b) => ({ ok: true, status: 200, json: async () => b });
global.fetch = async (url, init = {}) => {
  const u = String(url);
  if (u.includes('generativelanguage')) { calls.gemini++; calls.geminiBody = init.body; calls.geminiHeaders = init.headers;
    return state.gemini === 'ok' ? ok({ candidates: [{ content: { parts: [{ text: 'Teacher agrees first, then the coordinator.' }] } }] }) : { ok: false, status: 500, json: async () => ({}) }; }
  calls.paths.push(u.replace('https://x.supabase.co', ''));
  if (u.endsWith('/auth/v1/user')) return state.tokenOk ? ok({ id: 'u1' }) : { ok: false, status: 401, json: async () => ({}) };
  if (u.includes('/rest/v1/profiles')) return ok([{ role: state.role, batch: '68A', teacher_code: 'DNS' }]);
  if (u.includes('rpc/free_rooms')) return ok([{ name: '501', floor: '5', is_lab: false, capacity: 60 }, { name: '509', floor: '5', is_lab: true, capacity: 40 }, { name: '312', floor: '3', is_lab: false, capacity: 60 }]);
  if (u.includes('rpc/ai_take_quota')) { calls.quota++; return ok(state.quota); }
  if (u.includes('rpc/search_knowledge')) return ok(state.kn);
  if (u.includes('rpc/room_usage')) return state.role === 'admin' ? ok([{ room: '502', periods_used: 9 }]) : { ok: false, status: 400, json: async () => ({}) };
  if (u.includes('/rest/v1/classes')) return ok([{ period: 0, periods: 1, course: 'CSE0613101', room: '514', batch: '68A' }, { period: 2, periods: 1, course: 'MAT0541101', room: '512', batch: '68A' }]);
  if (u.includes('/rest/v1/shift_requests')) return ok([{ batch: '68A', course: 'CSE0613101', day: 1, to_period: 1, to_room: '501', status: 'pending' }]);
  return { ok: false, status: 404, json: async () => ({}) };
};
const NOW = '2026-11-23T05:00:00Z';   // Monday 11:00 in Dhaka
const call = (msg, extra = {}) => handler({ httpMethod: 'POST', headers: { authorization: 'Bearer tok' }, body: JSON.stringify({ message: msg, ...extra }), _now: NOW });
const out = async (msg, extra) => { const r = await call(msg, extra); return { code: r.statusCode, ...JSON.parse(r.body) }; };
let n = 0; const t = async (name, fn) => { reset(); try { await fn(); n++; console.log('ok  ', name); } catch (e) { console.log('FAIL', name, '\n    ', e.message); process.exitCode = 1; } };

(async () => {
  await t('rejects GET, missing login, empty question', async () => {
    assert.strictEqual((await handler({ httpMethod: 'GET', headers: {} })).statusCode, 405);
    assert.strictEqual((await handler({ httpMethod: 'POST', headers: {}, body: '{}' })).statusCode, 401);
    assert.strictEqual((await out('   ')).code, 400);
  });
  await t('expired login is refused', async () => { state.tokenOk = false; assert.strictEqual((await out('free room')).code, 401); });
  await t('free rooms come from the database, no AI call, no quota used', async () => {
    const r = await out('Is any free room available now?');
    assert.strictEqual(r.via, 'database'); assert.match(r.reply, /501/); assert.match(r.reply, /509/); assert.strictEqual(calls.gemini, 0); assert.strictEqual(calls.quota, 0);
  });
  await t('timetable answer shows next class and longest break', async () => {
    const r = await out('what is my next class and longest break'); assert.match(r.reply, /Next: 11:10-12:30 68A MAT0541101/); assert.match(r.reply, /Longest break: 1h 20m \(9:50-11:10\)/); assert.strictEqual(calls.gemini, 0);
  });
  await t('pending requests answered from database', async () => { const r = await out('any pending requests?'); assert.match(r.reply, /waiting for the teacher/); assert.strictEqual(calls.gemini, 0); });
  await t('general question uses the model, key only in header, never in the reply', async () => {
    const r = await out('who approves a class shift'); assert.strictEqual(r.via, 'ai'); assert.strictEqual(calls.gemini, 1);
    assert.strictEqual(calls.geminiHeaders['x-goog-api-key'], 'SECRET-KEY-123'); assert.ok(!JSON.stringify(r).includes('SECRET')); assert.ok(!calls.geminiBody.includes('SECRET'));
    assert.match(calls.geminiBody, /FACTS/); assert.match(calls.geminiBody, /Teacher first/);
  });
  await t('repeat general question is served from cache', async () => { const first = await out('what happens after the teacher agrees'); const r = await out('what happens after the teacher agrees'); assert.strictEqual(first.via, 'ai'); assert.strictEqual(r.via, 'cache'); assert.strictEqual(calls.gemini, 1); });
  await t('model failure falls back to the help text', async () => { state.gemini = 'fail'; const r = await out('how does approval work'); assert.strictEqual(r.via, 'database'); assert.match(r.reply, /Teacher first/); });
  await t('daily limit reached: no model call, help text instead', async () => { state.quota = false; const r = await out('explain the approval steps please'); assert.strictEqual(calls.gemini, 0); assert.match(r.reply, /limit reached/); });
  await t('personal question sends the user\'s own facts and is not cached', async () => {
    const r = await out('compare room 501 and 312 for me'); assert.strictEqual(r.via, 'ai'); assert.match(calls.geminiBody, /User's classes that day/); assert.match(calls.geminiBody, /Free rooms in that slot/);
    await out('compare room 501 and 312 for me'); assert.strictEqual(calls.gemini, 2);
  });
  await t('no personal names or emails are sent to the model', async () => { await out('compare room 501 and 312 for me'); assert.ok(!/@|full_name|email/i.test(calls.geminiBody)); });
  await t('students cannot use the admin usage query', async () => { const r = await out('show room usage statistics'); assert.ok(!/502: 9/.test(r.reply)); });
  reset('admin'); await t('admin usage summary works', async () => { state.role = 'admin'; const r = await out('which are the busiest rooms?'); assert.match(r.reply, /502: 9/); });
  await t('long message and long history are trimmed', async () => {
    const hist = Array.from({ length: 12 }, (_, i) => ({ role: i % 2 ? 'ai' : 'user', text: 'x'.repeat(900) }));
    await out('who approves ' + 'y'.repeat(900) + ' ?', { history: hist });
    const body = JSON.parse(calls.geminiBody); assert.ok(body.contents.length <= 7); assert.ok(body.contents.every(c => c.parts[0].text.length < 900));
  });
  await t('unconfigured server says so', async () => { const s = process.env.SUPABASE_URL; delete process.env.SUPABASE_URL; assert.strictEqual((await out('hi')).code, 500); process.env.SUPABASE_URL = s; });

  // time parsing
  const W = (s) => _t.parseWhen(s, new Date(NOW));
  await t('parse: period 3 on tuesday', () => assert.deepStrictEqual([W('free room period 3 on tue').day, W('free room period 3 on tue').a], [1, 2]));
  await t('parse: 2pm is period 4, 9am lab is two periods from period 1', () => { assert.strictEqual(W('room at 2pm').a, 3); const l = W('free lab at 9am'); assert.deepStrictEqual([l.a, l.b, l.lab], [0, 2, true]); });
  await t('parse: now (Monday 11:00 Dhaka) is period 2', () => assert.strictEqual(W('free room now').a, 1));
  await t('parse: lab never spans lunch', () => { const l = W('free lab period 3'); assert.strictEqual(l.b, 3); });
  console.log(`\n${n} checks passed`);
})();
