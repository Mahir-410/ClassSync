/* =============================================================================
 * ClassSync — ER feature layer (merged from the multi-university project)
 * =============================================================================
 * Adds the features from the second project into Apon's ClassSync UI WITHOUT
 * redesigning it: new tabs appear in the existing nav bar, and every panel is
 * rendered with Apon's existing CSS classes (card, row, btn b, tag, table...).
 *
 * Data: reads/writes ONLY the tables created by supabase/07_er_features.sql
 * through the configured Supabase client. No demo/offline data is bundled.
 *
 * Load after pilot-live.js.
 * ============================================================================= */
(function(){
  'use strict';

  var ER_TABS = [
    ['er_dash', 'Overview'],
    ['er_ann', 'Announcements'],
    ['er_notif', 'Notifications'],
    ['er_lf', 'Lost & Found'],
    ['er_res', 'Resources'],
    ['er_ev', 'Events'],
    ['er_prof', 'Profile']
  ];
  var TAB_KEYS = ER_TABS.map(function(t){ return t[0]; });
  // Live build: all ER features read/write the configured Supabase project only.
  // No bundled demo data is used anywhere in this build.

  /* ---------------- data layer (Supabase only) ---------------- */
  function supabaseOK(){
    if (!window.classSyncSupabase) return false;
    var c = window.CLASSSYNC_CONFIG || {};
    return !!c.supabaseUrl && c.supabaseUrl.indexOf('YOUR-PROJECT') < 0;
  }
  function list(table, filters, cb){
    filters = filters || {};
    if (!supabaseOK()){ cb([]); return; }
    try {
      var q = window.classSyncSupabase.from(table).select('*');
      Object.keys(filters).forEach(function(k){ q = q.eq(k, filters[k]); });
      q.then(function(res){ cb(res && !res.error && res.data ? res.data : []); })
       .catch(function(){ cb([]); });
    } catch(e){ cb([]); }
  }
  function insert(table, row, cb){
    if (!supabaseOK()){ cb(false, 'Supabase is not configured.'); return; }
    try {
      window.classSyncSupabase.from(table).insert(row).then(function(res){
        cb(!(res && res.error), res && res.error && res.error.message);
      }).catch(function(e){ cb(false, e && e.message); });
    } catch(e){ cb(false, e && e.message); }
  }
  function update(table, id, patch, cb){
    if (!supabaseOK()){ cb(false, 'Supabase is not configured.'); return; }
    try {
      window.classSyncSupabase.from(table).update(patch).eq('id', id).then(function(res){
        cb(!(res && res.error), res && res.error && res.error.message);
      }).catch(function(e){ cb(false, e && e.message); });
    } catch(e){ cb(false, e && e.message); }
  }
  function nameOf(id){ return id ? String(id).slice(0, 8) : '—'; }
  function esc(t){
    return String(t == null ? '' : t).replace(/[&<>"]/g, function(c){
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];
    });
  }
  function now(){ return new Date().toISOString(); }
  function role(){ return (U && U.role) || 'student'; }
  function isAdmin(){ return role() === 'admin'; }
  function isStaff(){ return role() === 'admin' || role() === 'coord'; }

  /* ---------------- view helpers ---------------- */
  function show(html){ var v = document.getElementById('view'); if (v) v.innerHTML = html; }
  /* Panel placed above #view so an existing ClassSync screen can live inside
     an ER tab (Today inside Overview, My requests inside Profile). */
  function showTop(html){
    var v = document.getElementById('view'); if (!v) return;
    var top = document.getElementById('er-top');
    if (!top){
      top = document.createElement('div');
      top.id = 'er-top';
      v.parentNode.insertBefore(top, v);
    }
    top.innerHTML = html;
  }
  function clearTop(){ var top = document.getElementById('er-top'); if (top) top.remove(); }
  function erLightbox(src, caption){
    var old = document.getElementById('er-lightbox'); if (old) old.remove();
    var box = document.createElement('div');
    box.id = 'er-lightbox';
    box.style.cssText = 'position:fixed;inset:0;z-index:999;background:rgba(0,0,0,.8);display:flex;flex-direction:column;align-items:center;justify-content:center;padding:20px';
    box.innerHTML = '<div style="color:#fff;font-weight:700;margin-bottom:12px">' + esc(caption || 'Photo') + '</div>' +
      '<img src="' + esc(src) + '" style="max-width:90vw;max-height:78vh;border-radius:10px;box-shadow:0 8px 24px rgba(0,0,0,.5)">' +
      '<button class="b" style="margin-top:14px">Close</button>';
    document.body.appendChild(box);
    box.querySelector('button').onclick = function(){ box.remove(); };
    box.onclick = function(e){ if (e.target === box) box.remove(); };
  }
  function banner(title, sub){
    return '<div class="card" style="margin-bottom:12px"><h2 style="margin-bottom:4px">' + esc(title) +
      '</h2><p class="sub">' + esc(sub || '') + '</p></div>';
  }
  function erFlash(){
    try { return flash(); } catch(e){ return ''; }
  }
  function reload(){ try { render(); } catch(e){ /* noop */ } }
  function erToast(t){ try { toast(t); } catch(e){ alert(t); } }

  /* ---------------- Overview ---------------- */
  function renderOverview(){
    showTop(banner('Overview', 'Features merged from the multi-university ER project — now including the Today screen.') + '<div class="stats" id="erStats"></div>' + erFlash() +
      '<div class="card"><h3 class="h3">Quick actions</h3><div class="row">' +
      ER_TABS.filter(function(t){ return t[0] !== 'er_dash' && t[0] !== 'er_prof'; }).map(function(t){
        return '<button class="b alt" data-go="' + t[0] + '">' + esc(t[1]) + '</button>';
      }).join('') + '</div></div><div class="card"><h3 class="h3">Latest announcements</h3><div id="erRecent" class="empty">Loading…</div></div>' +
      '<div class="card" style="border-color:var(--gold);border-width:2px"><h3 class="h3">Today</h3><p class="sub">Your timetable and free-period planner appear below.</p></div>');
    bindGo();
    var counts = {};
    var tables = ['announcements','notifications','lost_found','resources','events'];
    var pending = tables.length;
    tables.forEach(function(t){
      list(t, {}, function(rows){ counts[t] = rows.length; if (--pending === 0) drawCounts(counts); });
    });
    list('announcements', {}, function(rows){
      var el = document.getElementById('erRecent');
      if (!el) return;
      if (!rows.length){ el.innerHTML = '<div class="empty">No announcements yet.</div>'; return; }
      el.innerHTML = rows.slice(0,4).map(function(a){
        return '<div class="cls" style="margin-bottom:6px"><span><b>' + esc(a.title) + '</b><br><span class="sub">' +
          esc((a.body || a.content || '').slice(0,110)) + '</span></span></div>';
      }).join('');
    });
  }
  function drawCounts(c){
    var el = document.getElementById('erStats'); if (!el) return;
    el.innerHTML =
      '<div class="stat"><strong>' + (c.announcements||0) + '</strong><span>announcements</span></div>' +
      '<div class="stat m"><strong>' + (c.notifications||0) + '</strong><span>notifications</span></div>' +
      '<div class="stat b"><strong>' + (c.lost_found||0) + '</strong><span>lost &amp; found</span></div>' +
      '<div class="stat"><strong>' + (c.resources||0) + '</strong><span>resources</span></div>' +
      '<div class="stat b"><strong>' + (c.events||0) + '</strong><span>calendar events</span></div>';
  }

  /* ---------------- Announcements ---------------- */
  function renderAnnouncements(){
    show(banner('Announcements', 'Posted by coordinators and admins; targeted by role.') + erFlash() +
      (isStaff() ? '<div class="card"><h3 class="h3">Post an announcement</h3><div class="row">' +
        '<input id="erAnnTitle" placeholder="Title" style="flex:1">' +
        '<button class="b" id="erAnnPost">Post</button></div>' +
        '<textarea id="erAnnBody" rows="2" placeholder="Message" style="margin-top:8px"></textarea></div>' : '') +
      '<div id="erAnnList"></div>');
    var post = document.getElementById('erAnnPost');
    if (post) post.onclick = function(){
      var title = document.getElementById('erAnnTitle').value.trim();
      var body = document.getElementById('erAnnBody').value.trim();
      if (!title){ erToast('Enter a title.'); return; }
      insert('announcements', { posted_by: (U && U.id) || 'demo-user', title: title,
        body: body, content: body, posted_at: now(),
        target_roles: ['student','cr','teacher','coord','admin'] }, function(ok, err){
        if (!ok){ erToast(err || 'Could not post.'); return; }
        erToast('Announcement posted.'); reload();
      });
    };
    list('announcements', {}, function(rows){
      var el = document.getElementById('erAnnList'); if (!el) return;
      if (!rows.length){ el.innerHTML = '<div class="empty">No announcements.</div>'; return; }
      el.innerHTML = rows.map(function(a){
        var roles = (a.target_roles || []).join(', ') || 'everyone';
        return '<div class="card ann-card" style="margin-bottom:8px"><h3 class="h3" style="font-size:15px">' + esc(a.title) +
          '</h3><div style="white-space:pre-line">' + esc(a.body || a.content || '') + '</div>' +
          '<p class="sub">By ' + esc(nameOf(a.posted_by)) + ' · ' + esc(roles) + '</p></div>';
      }).join('');
    });
  }

  /* ---------------- Notifications ---------------- */
  function renderNotifications(){
    show(banner('Notifications', 'Your alerts from the merged feature layer.') + erFlash() +
      '<div class="card"><button class="b alt" id="erNotifAll">Mark all as read</button></div><div id="erNotifList"></div>');
    document.getElementById('erNotifAll').onclick = function(){
      list('notifications', {}, function(rows){
        var n = 0;
        rows.forEach(function(r){
          if (!r.is_read){ n++; update('notifications', r.id, {is_read:true}, function(){}); }
        });
        setTimeout(function(){ erToast(n + ' marked as read.'); reload(); }, 60);
      });
    };
    list('notifications', {}, function(rows){
      var el = document.getElementById('erNotifList'); if (!el) return;
      if (!rows.length){ el.innerHTML = '<div class="empty">No notifications.</div>'; return; }
      el.innerHTML = rows.map(function(n){
        return '<div class="card" style="margin-bottom:8px"><h3 class="h3" style="font-size:14px">' + esc(n.title) +
          ' <span class="tag ' + (n.is_read ? 'i' : 'w') + '">' + (n.is_read ? 'read' : 'new') + '</span></h3>' +
          '<div>' + esc(n.message) + '</div></div>';
      }).join('');
    });
  }

  /* ---------------- Lost & Found ---------------- */
  function renderLostFound(){
    show(banner('Lost & Found', 'Report an item with a photo and claim a matching report.') + erFlash() +
      '<div class="card"><h3 class="h3">Report an item</h3>' +
      '<div class="row"><input id="erLfName" placeholder="Item name" style="flex:1">' +
      '<select id="erLfStatus"><option value="lost">Lost</option><option value="found">Found</option></select>' +
      '<input id="erLfLoc" placeholder="Location" style="flex:1"></div>' +
      '<div class="row" style="margin-top:8px"><label class="label" style="margin:0">Photo of the item</label>' +
      '<input type="file" id="erLfPhoto" accept="image/*" style="flex:1">' +
      '<button class="b" id="erLfAdd">Report</button></div>' +
      '<p class="sub" style="margin-top:6px">JPG or PNG, up to 2 MB. The photo appears on the item card.</p></div>' +
      '<div id="erLfList"></div>');
    document.getElementById('erLfAdd').onclick = function(){
      var name = document.getElementById('erLfName').value.trim();
      if (!name){ erToast('Enter an item name.'); return; }
      var file = (document.getElementById('erLfPhoto').files || [])[0];
      function save(photo){
        insert('lost_found', { item_name: name, status: document.getElementById('erLfStatus').value,
          location: document.getElementById('erLfLoc').value || null,
          description: file ? file.name : '', photo_url: photo || null, photo: photo || null,
          reporter_id: (U && U.id) || 'demo-user', created_at: now() }, function(ok, err){
          if (!ok){ erToast(err || 'Could not report.'); return; }
          erToast('Item reported.'); reload();
        });
      }
      if (!file){ save(null); return; }
      if (file.size > 2 * 1024 * 1024){ erToast('Photo must be under 2 MB.'); return; }
      var reader = new FileReader();
      reader.onload = function(){ save(reader.result); };
      reader.onerror = function(){ erToast('Could not read that photo.'); };
      reader.readAsDataURL(file);
    };
    list('lost_found', {}, function(rows){
      var el = document.getElementById('erLfList'); if (!el) return;
      if (!rows.length){ el.innerHTML = '<div class="empty">No reported items.</div>'; return; }
      el.innerHTML = '<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:12px">' +
        rows.map(function(i){
          var cls = i.status === 'found' ? 'ok' : i.status === 'lost' ? 'w' : 'i';
          var photo = i.photo_url || i.photo;
          var thumb = photo
            ? '<img src="' + esc(photo) + '" alt="' + esc(i.item_name) + '" data-photo="' + esc(photo) + '" style="width:100%;height:150px;object-fit:cover;border-radius:8px;cursor:zoom-in;border:1px solid var(--line)">'
            : '<div data-nophoto="1" style="width:100%;height:150px;border-radius:8px;display:grid;place-items:center;background:var(--gr);color:var(--mute);border:1px dashed var(--line)">No photo attached</div>';
          return '<div class="card" style="padding:12px">' + thumb +
            '<div style="margin-top:10px"><b>' + esc(i.item_name) + '</b> <span class="tag ' + cls + '">' + esc(i.status) + '</span></div>' +
            '<p class="sub" style="margin-top:4px">' + esc(i.location || 'Unknown location') + '</p>' +
            '<p class="sub">Reported by ' + esc(nameOf(i.reporter_id)) + '</p>' +
            (i.description ? '<p class="sub">' + esc(i.description) + '</p>' : '') +
            (i.status === 'found' ? '<button class="b alt" data-claim="' + esc(i.id) + '">Claim this item</button>' : '') + '</div>';
        }).join('') + '</div>';
      var btns = el.querySelectorAll('[data-claim]');
      Array.prototype.forEach.call(btns, function(b){
        b.onclick = function(){
          insert('item_match', { item_id: b.getAttribute('data-claim'),
            claimed_by: (U && U.id) || 'demo-user', status: 'pending', match_date: now() },
            function(){ erToast('Claim sent.'); });
        };
      });
      Array.prototype.forEach.call(el.querySelectorAll('[data-photo]'), function(img){
        img.onclick = function(){ erLightbox(img.getAttribute('data-photo'), img.alt); };
      });
    });
  }

  /* ---------------- Resources ---------------- */
  function renderResources(){
    show(banner('Resources', 'Shared documents, links and videos.') + erFlash() +
      (isStaff() || role() === 'teacher' ? '<div class="card"><h3 class="h3">Add a resource</h3><div class="row">' +
        '<input id="erResTitle" placeholder="Title" style="flex:1">' +
        '<select id="erResType"><option>document</option><option>link</option><option>video</option><option>other</option></select>' +
        '<input id="erResUrl" placeholder="URL (optional)" style="flex:1">' +
        '<button class="b" id="erResAdd">Add</button></div></div>' : '') + '<div id="erResList"></div>');
    var add = document.getElementById('erResAdd');
    if (add) add.onclick = function(){
      var t = document.getElementById('erResTitle').value.trim();
      if (!t){ erToast('Enter a title.'); return; }
      insert('resources', { title: t, type: document.getElementById('erResType').value,
        url: document.getElementById('erResUrl').value || null,
        uploaded_by: (U && U.id) || 'demo-user', uploaded_at: now() },
        function(ok, err){ if (!ok){ erToast(err || 'Could not add.'); return; } erToast('Resource added.'); reload(); });
    };
    list('resources', {}, function(rows){
      var el = document.getElementById('erResList'); if (!el) return;
      if (!rows.length){ el.innerHTML = '<div class="empty">No resources yet.</div>'; return; }
      el.innerHTML = rows.map(function(r){
        return '<div class="cls" style="margin-bottom:6px"><span><b>' + esc(r.title) + '</b> <span class="tag i">' +
          esc(r.type) + '</span><br><span class="sub">Uploaded by ' + esc(nameOf(r.uploaded_by)) + '</span></span>' +
          (r.url ? '<a class="b alt" href="' + esc(r.url) + '" target="_blank">Open</a>' : '') + '</div>';
      }).join('');
    });
  }

  /* ---------------- Calendar Events ---------------- */
  function renderEvents(){
    show(banner('Events', 'Calendar events with date, time and capacity (separate from room bookings).') + erFlash() +
      (isStaff() || role() === 'cr' ? '<div class="card"><h3 class="h3">Create an event</h3><div class="row">' +
        '<input id="erEvTitle" placeholder="Title" style="flex:1">' +
        '<input id="erEvDate" type="date">' +
        '<input id="erEvStart" type="time" value="14:00">' +
        '<input id="erEvEnd" type="time" value="15:00">' +
        '<button class="b" id="erEvAdd">Create</button></div></div>' : '') + '<div id="erEvList"></div>');
    var add = document.getElementById('erEvAdd');
    if (add) add.onclick = function(){
      var t = document.getElementById('erEvTitle').value.trim();
      var d = document.getElementById('erEvDate').value;
      if (!t || !d){ erToast('Enter a title and date.'); return; }
      insert('events', { organizer_id: (U && U.id) || 'demo-user', title: t,
        event_date: d, start_time: document.getElementById('erEvStart').value,
        end_time: document.getElementById('erEvEnd').value, location: '', capacity: null,
        created_at: now() }, function(ok, err){ if (!ok){ erToast(err || 'Could not create.'); return; } erToast('Event created.'); reload(); });
    };
    list('events', {}, function(rows){
      var el = document.getElementById('erEvList'); if (!el) return;
      if (!rows.length){ el.innerHTML = '<div class="empty">No calendar events.</div>'; return; }
      el.innerHTML = rows.map(function(e){
        return '<div class="event-card"><h4>' + esc(e.title) + '</h4><div class="meta">' +
          esc(e.event_date) + ' · ' + esc(e.start_time || '') + '–' + esc(e.end_time || '') +
          (e.location ? ' · ' + esc(e.location) : '') + '</div>' +
          '<div class="meta">Organizer: ' + esc(nameOf(e.organizer_id)) + (e.capacity ? ' · ' + esc(e.capacity) + ' seats' : '') + '</div></div>';
      }).join('');
    });
  }

  /* ---------------- Profile ---------------- */
  function renderProfile(){
    var u = U || {};
    showTop(banner('Profile', 'Your merged ClassSync identity — now including My requests.') + erFlash() +
      '<div class="card" style="max-width:560px"><h3 class="h3">' + esc(u.name || u.full_name || 'User') + '</h3>' +
      '<p class="sub">Role: ' + esc(u.role || 'student') + '</p>' +
      (u.bid ? '<p class="sub">Batch: ' + esc(u.bid) + '</p>' : '') +
      (u.code ? '<p class="sub">Teacher code: ' + esc(u.code) + '</p>' : '') +
      '<p class="sub">Extra features available: announcements, notifications, lost &amp; found, resources, calendar events, memberships, subscriptions and enrolments.</p></div>' +
      '<div class="card" style="border-color:var(--gold);border-width:2px"><h3 class="h3">My requests</h3><p class="sub">Your shift request history appears below.</p></div>');
  }

  var RENDERERS = {
    er_dash: renderOverview, er_ann: renderAnnouncements, er_notif: renderNotifications,
    er_lf: renderLostFound, er_res: renderResources, er_ev: renderEvents, er_prof: renderProfile
  };

  function bindGo(){
    var bs = document.querySelectorAll('#view [data-go], #er-top [data-go]');
    Array.prototype.forEach.call(bs, function(b){
      b.onclick = function(){ try { tab = b.getAttribute('data-go'); render(); } catch(e){} };
    });
  }

  /* ---------------- integrate into Apon's shell ---------------- */
  function install(){
    if (typeof window.appRender !== 'function'){ setTimeout(install, 200); return; }
    var original = window.appRender;
    window.appRender = function(){
      clearTop();
      var mine = (TAB_KEYS.indexOf(tab) >= 0) ? tab : null;
      var allowed = (ROLETABS && ROLETABS[role()]) || ['today'];
      // Nest the original screens inside the ER tabs:
      //   Today      -> Overview
      //   My requests -> Profile
      var embed = null;
      if (mine === 'er_dash' && allowed.indexOf('today') >= 0) embed = 'today';
      if (mine === 'er_prof' && allowed.indexOf('req') >= 0) embed = 'req';
      if (mine){
        var saved = tab;
        tab = embed || allowed[0] || 'today';
        original();
        tab = saved;
      } else {
        original();
      }
      var nav = document.getElementById('nav');
      if (nav){
        // Remove the two standalone tabs — their screens now live inside ER tabs.
        Array.prototype.forEach.call(nav.querySelectorAll('button'), function(b){
          var t = b.getAttribute('data-t');
          if (t === 'today' || t === 'req'){ b.remove(); return; }
          // Keep the highlight on the active original tab (e.g. Find a room).
          b.classList.toggle('on', t === tab && TAB_KEYS.indexOf(tab) < 0);
        });
        // Add the merged feature tabs in the same nav style.
        ER_TABS.forEach(function(t){
          var b = document.createElement('button');
          b.className = t[0] === tab ? 'on' : '';
          b.setAttribute('data-t', t[0]);
          b.textContent = t[1];
          b.onclick = function(){ tab = t[0]; msg = ''; render(); };
          nav.appendChild(b);
        });
      }
      if (mine){
        try { (RENDERERS[mine] || renderOverview)(); } catch(e){
          show('<div class="card"><h2>Feature error</h2><p class="sub">' + esc(e && e.message) + '</p></div>');
        }
      }
    };
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install);
  else install();

  window.ER_FEATURES = { tabs: ER_TABS, list: list, insert: insert, update: update };
})();