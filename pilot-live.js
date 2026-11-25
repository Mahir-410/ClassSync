/* ClassSync shared room holds + chat safety UI. Requires the Supabase client
   initialized by index.html and the 06_live_pilot_hardening.sql migration. */
(() => {
  const client = window.classSyncSupabase;
  if (!client) return;
  const $ = id => document.getElementById(id);
  const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const DAYS = ['Monday','Tuesday','Wednesday','Thursday'];
  const PERIODS = ['P1','P2','P3','P4','P5','P6'];
  const cfg = window.CLASSSYNC_CONFIG || {};
  const semester = cfg.semester || 'Fall 2026';
  let activeHoldPanel = false;

  function installHoldUI() {
    if (!$('cs-live-holds-launch')) {
      const b = document.createElement('button'); b.id='cs-live-holds-launch'; b.textContent='🏫 Shared room holds';
      Object.assign(b.style,{position:'fixed',right:'22px',bottom:'78px',zIndex:9997,border:0,borderRadius:'24px',padding:'12px 16px',background:'#244e83',color:'#fff',fontWeight:700,cursor:'pointer',boxShadow:'0 5px 20px #0003'});
      b.onclick=()=>{ const p=$('cs-live-holds'); p.style.display=p.style.display==='block'?'none':'block'; if(p.style.display==='block')loadHolds(); };
      document.body.appendChild(b);
      const panel=document.createElement('section');panel.id='cs-live-holds';
      Object.assign(panel.style,{display:'none',position:'fixed',right:'18px',bottom:'132px',zIndex:9999,width:'min(390px,calc(100vw - 28px))',maxHeight:'70vh',overflow:'auto',background:'#fff',color:'#17232b',border:'1px solid #d8e2e9',borderRadius:'14px',boxShadow:'0 8px 32px #0003',padding:'14px'});
      panel.innerHTML=`<div style="display:flex;justify-content:space-between;align-items:center"><b>Shared room availability</b><button id="cs-holds-close" type="button">×</button></div><p style="font-size:12px;color:#5d6971">Reservations are shared by signed-in pilot users. ${esc(semester)}</p><div id="cs-hold-status" role="status" style="font-size:13px;margin:8px 0"></div><form id="cs-hold-form" style="display:grid;gap:8px"><label>Room<select id="cs-hold-room" required style="width:100%;padding:8px"></select></label><label>Day<select id="cs-hold-day" style="width:100%;padding:8px">${DAYS.map((d,i)=>`<option value="${i}">${d}</option>`).join('')}</select></label><div style="display:flex;gap:8px"><label style="flex:1">From<select id="cs-hold-from" style="width:100%;padding:8px">${PERIODS.map((p,i)=>`<option value="${i}">${p}</option>`).join('')}</select></label><label style="flex:1">Until (exclusive)<select id="cs-hold-to" style="width:100%;padding:8px">${PERIODS.map((p,i)=>`<option value="${i+1}" ${i===0?'selected':''}>After ${p}</option>`).join('')}<option value="6">After P6</option></select></label></div><label>Purpose (optional)<input id="cs-hold-note" maxlength="120" placeholder="Study group" style="width:100%;padding:8px;box-sizing:border-box"></label><button type="submit" style="padding:10px;background:#176b55;color:white;border:0;border-radius:8px">Reserve this slot</button></form><h4 style="margin:14px 0 6px">Current shared holds</h4><div id="cs-hold-list" style="font-size:13px"></div>`;
      document.body.appendChild(panel);
      $('cs-holds-close').onclick=()=>panel.style.display='none';
      $('cs-hold-form').onsubmit=createHold;
      loadRooms();
    }
  }
  async function loadRooms(){
    const {data,error}=await client.from('rooms').select('name').order('name');
    const select=$('cs-hold-room'); if(!select)return;
    if(error){$('cs-hold-status').textContent='Room list unavailable. Check the database migration.';return;}
    select.innerHTML=(data||[]).map(r=>`<option value="${esc(r.name)}">${esc(r.name)}</option>`).join('');
  }
  async function loadHolds(){
    const status=$('cs-hold-status');if(!status)return;
    const {data,error}=await client.from('room_holds').select('id,room,day,from_period,to_period,note,created_by,request_id').eq('semester',semester).order('day').order('from_period');
    if(error){status.textContent='Could not load shared holds. Confirm migration 06 and RLS permissions.';$('cs-hold-list').textContent='';return;}
    status.textContent='Live shared reservations';
    $('cs-hold-list').innerHTML=(data||[]).length?(data||[]).map(h=>`<div style="padding:8px 0;border-bottom:1px solid #e7ecef"><b>${esc(h.room)}</b> · ${esc(DAYS[h.day]||'Day')} · ${esc(PERIODS[h.from_period]||'')}–${esc(PERIODS[h.to_period-1]||'')}<div style="color:#667">${esc(h.note||'Reserved')}${h.request_id?' · Pending shift':''}</div>${h.created_by===window.__csLiveUser?.id&&!h.request_id?`<button data-release-hold="${h.id}" style="margin-top:4px">Release</button>`:''}</div>`).join(''):'No shared room holds currently.';
    $('cs-hold-list').querySelectorAll('[data-release-hold]').forEach(b=>b.onclick=()=>releaseHold(Number(b.dataset.releaseHold)));
  }
  async function createHold(e){
    e.preventDefault();const status=$('cs-hold-status');status.textContent='Checking availability…';
    const args={p_semester:semester,p_room:$('cs-hold-room').value,p_day:Number($('cs-hold-day').value),p_from_period:Number($('cs-hold-from').value),p_to_period:Number($('cs-hold-to').value),p_note:$('cs-hold-note').value.trim()||'Study session'};
    const {error}=await client.rpc('create_room_hold',args);
    if(error){status.textContent=error.message.includes('already occupied')?'That slot was just taken. Refresh and choose another.':error.message;return;}
    $('cs-hold-note').value='';status.textContent='Room reserved for the pilot.';await loadHolds();
  }
  async function releaseHold(id){const {error}=await client.rpc('release_room_hold',{p_hold_id:id});$('cs-hold-status').textContent=error?error.message:'Reservation released.';await loadHolds();}

  function addChatSafety(){
    const panel=$('cs-random-chat');if(!panel||$('cs-chat-safety'))return;
    const row=document.createElement('div');row.id='cs-chat-safety';row.style.cssText='display:flex;gap:8px;padding:0 10px 10px';
    row.innerHTML='<button id="cs-chat-report" type="button" style="background:#9b3434;color:white;border:0;border-radius:7px;padding:7px 9px">Report partner</button><button id="cs-chat-block" type="button" style="background:#5d6870;color:white;border:0;border-radius:7px;padding:7px 9px">Block partner</button>';
    $('cs-chat-compose')?.insertAdjacentElement('afterend',row);
    $('cs-chat-report').onclick=()=>reportPartner();$('cs-chat-block').onclick=()=>blockPartner();
  }
  async function partnerId(){
    const room=window.__csCurrentChatRoom;if(!room)return null;
    const {data,error}=await client.from('random_chat_rooms').select('user_a,user_b,status').eq('id',room).single();
    if(error||!data||data.status!=='active')return null;
    return data.user_a===window.__csLiveUser?.id?data.user_b:data.user_a;
  }
  async function reportPartner(){
    const room=window.__csCurrentChatRoom;if(!room){alert('Connect to a chat partner first.');return;}
    const reason=prompt('Why are you reporting this user? Please provide at least 3 characters.');if(!reason)return;
    const {error}=await client.rpc('report_chat_user',{p_room_id:room,p_reason:reason.trim()});
    if(error){alert('Report could not be submitted: '+error.message);return;}
    alert('Report submitted. This partner has also been blocked.');window.__csCurrentChatRoom=null;
    $('cs-chat-state').textContent='Chat ended after report. You can find another partner.';$('cs-chat-messages').innerHTML='';
  }
  async function blockPartner(){
    const id=await partnerId();if(!id){alert('Connect to a chat partner first.');return;}
    if(!confirm('Block this user? You will not be matched with them again.'))return;
    const {error}=await client.rpc('block_chat_user',{p_user_id:id});if(error){alert('Could not block user: '+error.message);return;}
    window.__csCurrentChatRoom=null;$('cs-chat-state').textContent='User blocked. You can find another partner.';$('cs-chat-messages').innerHTML='';
  }
  const observer=new MutationObserver(()=>{if(window.__csLiveUser){installHoldUI();addChatSafety();}});
  observer.observe(document.body,{childList:true,subtree:true});
  if(window.__csLiveUser){installHoldUI();addChatSafety();}
})();
