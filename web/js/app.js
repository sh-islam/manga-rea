// Kumo web app: views + hash router. Vanilla JS, no build.
(() => {
  const { cfg, q, fs, img } = Kumo;
  const view = document.getElementById('view');
  const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const el = (html) => { const t = document.createElement('template'); t.innerHTML = html.trim(); return t.content.firstElementChild; };
  const toast = (m, ms = 2200) => { const t = document.getElementById('toast'); t.textContent = m; t.classList.add('show'); clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove('show'), ms); };
  const date = (ms) => { let n = Number(ms); if (!n) return ''; if (n < 1e11) n *= 1000; const d = new Date(n); const diff = (Date.now() - n) / 864e5; return diff < 1 ? 'today' : diff < 2 ? 'yesterday' : diff < 7 ? Math.floor(diff) + ' days ago' : d.toLocaleDateString(); };
  const bytes = (n) => n < 1024 ? n + ' B' : n < 1048576 ? (n / 1024).toFixed(0) + ' KB' : n < 1073741824 ? (n / 1048576).toFixed(1) + ' MB' : (n / 1073741824).toFixed(2) + ' GB';
  const busy = (msg) => { view.innerHTML = `<p class="muted">${esc(msg || 'Loading…')}</p>`; };
  const fail = (e) => { console.error(e); view.innerHTML = `<div class="card"><b>Error</b><div class="muted">${esc(e.message || e)}</div><p><a href="#/settings">Settings</a></p></div>`; };
  const sheet = (html) => { const s = el(`<div class="sheet"><div>${html}</div></div>`); s.addEventListener('click', e => { if (e.target === s) s.remove(); }); document.body.appendChild(s); return s; };
  const coverCard = (m) => `<a class="cover ${m.inLibrary ? 'inlib' : ''}" href="#/manga/${m.id}"><img loading="lazy" src="${esc(img(m.thumbnailUrl))}" alt=""><div class="b">${m.unreadCount ? `<i>${m.unreadCount}</i>` : ''}${m.downloadCount ? `<i class="d">${m.downloadCount}</i>` : ''}</div><div class="t">${esc(m.title)}</div></a>`;
  const nav = (r) => document.querySelectorAll('[data-r]').forEach(a => a.classList.toggle('active', a.dataset.r === r || (r === 'more' && ['files', 'extensions', 'settings', 'history'].includes(a.dataset.r)) || (a.dataset.r === 'more' && ['files', 'extensions', 'settings', 'history'].includes(r))));

  // ---------------- login
  function loginView(next) {
    nav('');
    view.innerHTML = `<form class="login"><h1>Kumo</h1><p class="muted">Sign in to your server.</p>
      <input id="u" placeholder="username" autocomplete="username" value="${esc(cfg.user)}"><input id="p" type="password" placeholder="password" autocomplete="current-password">
      <input id="s" placeholder="server https://…" value="${esc(cfg.api)}"><button class="primary">Sign in</button><div id="err" class="muted"></div></form>`;
    view.querySelector('form').onsubmit = async (e) => {
      e.preventDefault(); cfg.api = view.querySelector('#s').value.trim(); cfg.files = cfg.api + '/files';
      try { await Kumo.login(view.querySelector('#u').value.trim(), view.querySelector('#p').value); location.hash = next || '#/library'; }
      catch (err) { view.querySelector('#err').textContent = 'Sign-in failed: ' + err.message; }
    };
  }

  // ---------------- library
  async function libraryView() {
    nav('library'); busy();
    const [cats, all] = await Promise.all([q.categories(), q.library()]);
    const state = { cat: Number(sessionStorage.getItem('lib.cat') || -1), filter: '', sort: sessionStorage.getItem('lib.sort') || 'title', only: sessionStorage.getItem('lib.only') || '' };
    const render = () => {
      let list = all.filter(m => state.cat < 0 || m.categories.nodes.some(c => c.id === state.cat));
      if (state.filter) list = list.filter(m => (m.title + ' ' + (m.author || '')).toLowerCase().includes(state.filter));
      if (state.only === 'unread') list = list.filter(m => m.unreadCount > 0);
      if (state.only === 'downloaded') list = list.filter(m => m.downloadCount > 0);
      list.sort((a, b) => state.sort === 'title' ? a.title.localeCompare(b.title) : state.sort === 'unread' ? b.unreadCount - a.unreadCount : Number(b.latestUploadedChapter?.uploadDate || 0) - Number(a.latestUploadedChapter?.uploadDate || 0));
      view.querySelector('#grid').innerHTML = list.length ? list.map(coverCard).join('') : `<p class="muted">Nothing here yet. <a href="#/browse">Browse sources</a> and add manga to your library.</p>`;
      view.querySelector('#count').textContent = list.length + ' titles';
    };
    view.innerHTML = `<div class="row between"><h1>Library</h1><span class="muted small" id="count"></span></div>
      <div class="toolbar"><div class="row"><input id="f" placeholder="Filter library…" style="flex:1;min-width:140px">
        <select id="sort"><option value="title">Title</option><option value="unread">Unread</option><option value="latest">Latest chapter</option></select>
        <select id="only"><option value="">All</option><option value="unread">Unread</option><option value="downloaded">Downloaded</option></select>
        <button id="upd" title="Check all sources for new chapters">↻ Update</button><button id="cats" title="Manage categories">Categories</button></div>
        <div class="chips" id="chips" style="margin-top:8px"></div></div><div class="grid" id="grid"></div>`;
    const chips = view.querySelector('#chips');
    chips.innerHTML = [`<span class="chip ${state.cat < 0 ? 'on' : ''}" data-c="-1">All (${all.length})</span>`].concat(cats.map(c => `<span class="chip ${state.cat === c.id ? 'on' : ''}" data-c="${c.id}">${esc(c.name)} (${c.mangas.totalCount})</span>`)).join('');
    chips.onclick = e => { const c = e.target.closest('.chip'); if (!c) return; state.cat = Number(c.dataset.c); sessionStorage.setItem('lib.cat', state.cat); chips.querySelectorAll('.chip').forEach(x => x.classList.toggle('on', x === c)); render(); };
    view.querySelector('#f').oninput = e => { state.filter = e.target.value.toLowerCase(); render(); };
    view.querySelector('#sort').value = state.sort; view.querySelector('#sort').onchange = e => { state.sort = e.target.value; sessionStorage.setItem('lib.sort', state.sort); render(); };
    view.querySelector('#only').value = state.only; view.querySelector('#only').onchange = e => { state.only = e.target.value; sessionStorage.setItem('lib.only', state.only); render(); };
    view.querySelector('#upd').onclick = async () => { await q.updateLibrary(); toast('Library update started'); };
    view.querySelector('#cats').onclick = () => categoriesSheet(cats, () => libraryView());
    render();
  }
  function categoriesSheet(cats, done) {
    const s = sheet(`<h2>Categories</h2><div class="list" id="cl"></div><form class="row" id="add"><input placeholder="New category" style="flex:1"><button class="primary">Add</button></form>`);
    const list = s.querySelector('#cl');
    list.innerHTML = cats.map(c => `<div class="it"><div class="m"><div>${esc(c.name)}</div><div class="muted small">${c.mangas.totalCount} titles</div></div>${c.default ? '' : `<button class="ic" data-del="${c.id}" title="Delete">🗑</button>`}</div>`).join('') || '<p class="muted">No categories yet.</p>';
    list.onclick = async e => { const b = e.target.closest('[data-del]'); if (b && confirm('Delete this category? Manga stay in the library.')) { await q.deleteCategory(Number(b.dataset.del)); s.remove(); done(); } };
    s.querySelector('#add').onsubmit = async e => { e.preventDefault(); const n = e.target.querySelector('input').value.trim(); if (n) { await q.createCategory(n); s.remove(); done(); } };
  }

  // ---------------- browse (sources + global search)
  const visibleSources = (srcs) => srcs.filter(s => (cfg.nsfw() || s.contentWarning !== 'NSFW') && (cfg.langs().includes(s.lang) || s.lang === 'localsourcelang' || cfg.langs().includes('*')));
  async function browseView() {
    nav('browse'); busy();
    const srcs = visibleSources(await q.sources());
    view.innerHTML = `<h1>Browse</h1><form class="row" id="gs"><input id="gq" placeholder="Search every source…" style="flex:1;min-width:160px" value="${esc(sessionStorage.getItem('gs.q') || '')}"><button class="primary">Search</button></form>
      <div id="gres"></div><h2>Sources <span class="muted small">(${srcs.length}; languages in <a href="#/settings">Settings</a>)</span></h2><div class="list" id="sl"></div>`;
    view.querySelector('#sl').innerHTML = srcs.map(s => `<a class="it" href="#/source/${s.id}"><img class="thumb" style="height:46px;width:46px" src="${esc(img(s.iconUrl))}" alt=""><div class="m"><div>${esc(s.displayName)}</div><div class="muted small">${s.lang === 'localsourcelang' ? 'files on the server (local/)' : esc(s.lang)}${s.contentWarning === 'NSFW' ? ' · 18+' : s.contentWarning === 'MIXED' ? ' · may contain 18+' : ''}</div></div><span class="muted">›</span></a>`).join('') || '<p class="muted">No sources. Install extensions first.</p>';
    const run = async (query) => {
      if (!query) return; sessionStorage.setItem('gs.q', query);
      const box = view.querySelector('#gres'); box.innerHTML = '<p class="muted">Searching all sources…</p>';
      const res = await q.globalSearch(query, srcs.filter(s => s.lang !== 'localsourcelang'));
      box.innerHTML = res.length ? res.map(r => `<h3>${esc(r.source.displayName)} <span class="muted small">${esc(r.source.lang)}</span></h3><div class="grid">${r.mangas.slice(0, 8).map(coverCard).join('')}</div>`).join('') : '<p class="muted">No results.</p>';
    };
    view.querySelector('#gs').onsubmit = e => { e.preventDefault(); run(view.querySelector('#gq').value.trim()); };
    if (sessionStorage.getItem('gs.q')) run(sessionStorage.getItem('gs.q'));
  }

  // ---------------- one source: popular / latest / search + filters
  async function sourceView(id) {
    nav('browse'); busy();
    const src = await q.source(id);
    const st = { type: src.supportsLatest ? 'LATEST' : 'POPULAR', query: '', page: 1, filters: null, items: [], more: false, loading: false };
    view.innerHTML = `<div class="row between"><h1>${esc(src.displayName)} <span class="muted small">${esc(src.lang)}</span></h1><a class="btn" href="#/browse">‹ Sources</a></div>
      <div class="toolbar"><form class="row" id="sf"><input id="sq" placeholder="Search ${esc(src.displayName)}…" style="flex:1;min-width:140px"><button class="primary">Search</button>
      <div class="chips"><span class="chip" data-t="POPULAR">Popular</span>${src.supportsLatest ? '<span class="chip" data-t="LATEST">Latest</span>' : ''}${src.filters.length ? '<span class="chip" id="flt">Filters</span>' : ''}</div></form></div>
      <div class="grid" id="grid"></div><p id="more" style="text-align:center"></p>`;
    const grid = view.querySelector('#grid');
    const load = async (reset) => {
      if (st.loading || !grid.isConnected) return; st.loading = true;
      if (reset) { st.page = 1; st.items = []; grid.innerHTML = '<p class="muted">Loading…</p>'; }
      view.querySelector('#more').innerHTML = '<span class="muted">Loading…</span>';
      try {
        const r = await q.sourceManga(src.id, st.type, st.page, st.type === 'SEARCH' ? st.query : null, st.filters);
        st.items = st.items.concat(r.mangas); st.more = r.hasNextPage;
        grid.innerHTML = st.items.map(coverCard).join('') || '<p class="muted">Nothing found.</p>';
        view.querySelector('#more').innerHTML = st.more ? '<button id="lm">Load more</button>' : '';
        const b = view.querySelector('#lm'); if (b) b.onclick = () => { st.page++; load(false); };
      } catch (e) { grid.innerHTML = `<p class="muted">${esc(e.message)}</p>`; view.querySelector('#more').innerHTML = ''; }
      st.loading = false;
      view.querySelectorAll('.chip[data-t]').forEach(c => c.classList.toggle('on', c.dataset.t === st.type));
    };
    view.querySelector('#sf').onsubmit = e => { e.preventDefault(); st.query = view.querySelector('#sq').value.trim(); st.type = st.query ? 'SEARCH' : (src.supportsLatest ? 'LATEST' : 'POPULAR'); load(true); };
    view.querySelectorAll('.chip[data-t]').forEach(c => c.onclick = () => { st.type = c.dataset.t; load(true); });
    const f = view.querySelector('#flt'); if (f) f.onclick = () => filterSheet(src.filters, st, () => { st.type = 'SEARCH'; load(true); });
    window.addEventListener('scroll', () => { if (st.more && !st.loading && innerHeight + scrollY > document.body.offsetHeight - 600) { st.page++; load(false); } }, { passive: true });
    load(true);
  }
  // Build FilterChangeInput[] from the source's filter list (position = index in the list).
  function filterSheet(filters, st, apply) {
    const row = (f, i, parentPos) => {
      const n = esc(f.name); const t = f.__typename; const key = parentPos == null ? `${i}` : `${parentPos}.${i}`;
      if (t === 'HeaderFilter') return `<h3>${n}</h3>`;
      if (t === 'SeparatorFilter') return '<hr>';
      if (t === 'CheckBoxFilter') return `<label><input type="checkbox" data-k="${key}" data-t="cb" ${f.cbDefault ? 'checked' : ''}>${n}</label>`;
      if (t === 'TriStateFilter') return `<label>${n} <select data-k="${key}" data-t="tri"><option value="IGNORE" ${f.triDefault === 'IGNORE' ? 'selected' : ''}>—</option><option value="INCLUDE" ${f.triDefault === 'INCLUDE' ? 'selected' : ''}>include</option><option value="EXCLUDE" ${f.triDefault === 'EXCLUDE' ? 'selected' : ''}>exclude</option></select></label>`;
      if (t === 'SelectFilter') return `<label>${n} <select data-k="${key}" data-t="sel">${f.values.map((v, j) => `<option value="${j}" ${j === f.selDefault ? 'selected' : ''}>${esc(v)}</option>`).join('')}</select></label>`;
      if (t === 'TextFilter') return `<label>${n} <input data-k="${key}" data-t="txt" value="${esc(f.textDefault)}"></label>`;
      if (t === 'SortFilter') return `<label>${n} <select data-k="${key}" data-t="sort">${f.values.map((v, j) => `<option value="${j}" ${f.sortDefault && j === f.sortDefault.index ? 'selected' : ''}>${esc(v)}</option>`).join('')}</select><select data-k="${key}" data-t="sortdir"><option value="1">↑</option><option value="0" ${f.sortDefault && !f.sortDefault.ascending ? 'selected' : ''}>↓</option></select></label>`;
      if (t === 'GroupFilter') return `<details><summary>${n}</summary>${f.filters.map((g, j) => row(g, j, i)).join('')}</details>`;
      return '';
    };
    const s = sheet(`<h2>Filters</h2>${filters.map((f, i) => row(f, i)).join('')}<p class="row"><button class="primary" id="ap">Apply</button><button id="rs">Reset</button></p>`);
    s.querySelector('#rs').onclick = () => { st.filters = null; s.remove(); apply(); };
    s.querySelector('#ap').onclick = () => {
      const changes = [];
      s.querySelectorAll('[data-k]').forEach(inp => {
        const [p, c] = inp.dataset.k.split('.').map(Number); const t = inp.dataset.t;
        let ch = null;
        if (t === 'cb' && inp.checked) ch = { checkBoxState: true };
        if (t === 'tri' && inp.value !== 'IGNORE') ch = { triState: inp.value };
        if (t === 'sel') ch = { selectState: Number(inp.value) };
        if (t === 'txt' && inp.value) ch = { textState: inp.value };
        if (t === 'sort') { const dir = s.querySelector(`[data-k="${inp.dataset.k}"][data-t="sortdir"]`); ch = { sortState: { index: Number(inp.value), ascending: dir.value === '1' } }; }
        if (!ch) return;
        changes.push(c == null ? { position: p, ...ch } : { position: p, groupChange: { position: c, ...ch } });
      });
      st.filters = changes.length ? changes : null; s.remove(); apply();
    };
  }

  // ---------------- manga details + chapters
  async function mangaView(id, refresh) {
    nav('browse'); busy();
    let data;
    try { data = refresh ? await q.manga(id, true) : await q.mangaCached(id); } catch (e) { return fail(e); }
    if (!data.chapters.length && !refresh) { try { data = await q.manga(id, true); } catch (e) { /* source may be down; show what we have */ } }
    const m = data.manga; const chapters = data.chapters.slice().sort((a, b) => a.sourceOrder - b.sourceOrder);
    const sel = new Set(); let selecting = false;
    const unread = chapters.filter(c => !c.isRead); const notDl = chapters.filter(c => !c.isDownloaded);
    const resume = m.lastReadChapter && chapters.find(c => c.id === m.lastReadChapter.id) ? m.lastReadChapter : (unread.length ? unread[unread.length - 1] : chapters[chapters.length - 1]);
    view.innerHTML = `<div class="detail"><div><a class="cover" href="${esc(img(m.thumbnailUrl))}" target="_blank"><img src="${esc(img(m.thumbnailUrl))}" alt=""></a></div>
      <div><h1 style="margin-top:0">${esc(m.title)}</h1><div class="muted">${esc(m.author || '')}${m.artist && m.artist !== m.author ? ' · ' + esc(m.artist) : ''}</div>
      <div class="muted small">${esc(m.status)} · ${esc(m.source ? m.source.displayName : '')}${m.realUrl ? ` · <a href="${esc(m.realUrl)}" target="_blank">open on site</a>` : ''}</div>
      <p class="row"><button id="lib" class="${m.inLibrary ? '' : 'primary'}">${m.inLibrary ? '✓ In library' : '+ Add to library'}</button><button id="cat" ${m.inLibrary ? '' : 'disabled'}>Categories</button><button id="ref">↻ Refresh</button>
      ${resume ? `<a class="btn primary" href="#/read/${m.id}/${resume.id}">▶ ${m.lastReadChapter ? 'Resume' : 'Start'}</a>` : ''}</p>
      <div class="desc" id="desc">${esc(m.description || '')}</div>${(m.description || '').length > 300 ? '<a id="more" href="javascript:void 0" class="small">more</a>' : ''}
      <div class="chips" style="margin-top:8px">${(m.genre || []).map(g => `<span class="chip">${esc(g)}</span>`).join('')}</div></div></div>
      <div class="row between" style="margin-top:16px"><h2 style="margin:0">${chapters.length} chapters <span class="muted small">${unread.length} unread · ${chapters.length - notDl.length} on server</span></h2>
      <div class="row"><button id="dl">⇣ Download</button><button id="selm">Select</button></div></div>
      <div id="selbar" class="row card" style="display:none"><span id="selc"></span><button data-a="dl">Download</button><button data-a="deldl">Delete download</button><button data-a="read">Mark read</button><button data-a="unread">Mark unread</button><button data-a="all">All</button><button data-a="none">None</button></div>
      <div class="list" id="chs"></div>`;
    const chs = view.querySelector('#chs');
    const renderCh = () => { chs.innerHTML = chapters.slice().reverse().map(c => `<div class="it ${c.isRead ? 'read' : ''}" data-id="${c.id}">${selecting ? `<input type="checkbox" ${sel.has(c.id) ? 'checked' : ''}>` : ''}
      <a class="m" href="#/read/${m.id}/${c.id}"><div>${c.isBookmarked ? '🔖 ' : ''}${esc(c.name)}</div><div class="muted small">${date(c.uploadDate)}${c.scanlator ? ' · ' + esc(c.scanlator) : ''}${!c.isRead && c.lastPageRead ? ` · page ${c.lastPageRead + 1}` : ''}</div></a>
      <button class="ic ${c.isDownloaded ? 'on' : ''}" data-dl="${c.id}" title="${c.isDownloaded ? 'On server (click to delete)' : 'Download to server'}">${c.isDownloaded ? '✓' : '⇣'}</button>
      <button class="ic" data-menu="${c.id}" title="More">⋯</button></div>`).join(''); };
    renderCh();
    chs.onclick = async (e) => {
      const it = e.target.closest('.it'); if (!it) return; const id = Number(it.dataset.id); const c = chapters.find(x => x.id === id);
      if (e.target.matches('input[type=checkbox]') || (selecting && !e.target.closest('button'))) { e.preventDefault(); sel.has(id) ? sel.delete(id) : sel.add(id); it.querySelector('input').checked = sel.has(id); view.querySelector('#selc').textContent = sel.size + ' selected'; return; }
      if (e.target.dataset.dl) { if (c.isDownloaded) { if (confirm('Delete this chapter from the server?')) { await q.deleteDownloads([id]); c.isDownloaded = false; renderCh(); } } else { await q.download([id]); c.isDownloaded = true; toast('Queued on server'); renderCh(); } }
      if (e.target.dataset.menu) chapterMenu(c, chapters, () => renderCh());
    };
    view.querySelector('#lib').onclick = async () => { await q.setLibrary(m.id, !m.inLibrary); mangaView(id); toast(m.inLibrary ? 'Removed from library' : 'Added to library'); };
    view.querySelector('#ref').onclick = () => mangaView(id, true);
    view.querySelector('#cat').onclick = async () => {
      const cats = await q.categories(); const mine = new Set(m.categories.nodes.map(c => c.id));
      const s = sheet(`<h2>Categories</h2>${cats.map(c => `<label><input type="checkbox" value="${c.id}" ${mine.has(c.id) ? 'checked' : ''}>${esc(c.name)}</label>`).join('') || '<p class="muted">No categories. Create them in Library.</p>'}<p><button class="primary" id="ok">Save</button></p>`);
      s.querySelector('#ok').onclick = async () => { const on = [...s.querySelectorAll('input:checked')].map(i => Number(i.value)); await q.setCategories(m.id, on.filter(x => !mine.has(x)), [...mine].filter(x => !on.includes(x))); s.remove(); toast('Saved'); mangaView(id); };
    };
    const more = view.querySelector('#more'); if (more) more.onclick = () => { view.querySelector('#desc').classList.toggle('open'); more.textContent = view.querySelector('#desc').classList.contains('open') ? 'less' : 'more'; };
    view.querySelector('#dl').onclick = () => {
      const s = sheet(`<h2>Download to server</h2><p class="row"><button data-n="1">Next 1</button><button data-n="5">Next 5</button><button data-n="10">Next 10</button><button data-n="25">Next 25</button></p><p class="row"><button data-n="unread">All unread (${unread.length})</button><button data-n="all" class="primary">Everything not on server (${notDl.length})</button></p>`);
      s.onclick = async e => { const n = e.target.dataset.n; if (!n) return; let ids;
        if (n === 'all') ids = notDl.map(c => c.id); else if (n === 'unread') ids = unread.filter(c => !c.isDownloaded).map(c => c.id); else ids = unread.filter(c => !c.isDownloaded).slice(0, Number(n)).map(c => c.id);
        if (ids.length) await q.download(ids); s.remove(); toast(ids.length + ' chapters queued'); setTimeout(() => mangaView(id), 800); };
    };
    view.querySelector('#selm').onclick = () => { selecting = !selecting; sel.clear(); view.querySelector('#selbar').style.display = selecting ? '' : 'none'; view.querySelector('#selc').textContent = '0 selected'; renderCh(); };
    view.querySelector('#selbar').onclick = async e => { const a = e.target.dataset.a; if (!a) return; const ids = [...sel];
      if (a === 'all') { chapters.forEach(c => sel.add(c.id)); renderCh(); view.querySelector('#selc').textContent = sel.size + ' selected'; return; }
      if (a === 'none') { sel.clear(); renderCh(); view.querySelector('#selc').textContent = '0 selected'; return; }
      if (!ids.length) return toast('Select chapters first');
      if (a === 'dl') await q.download(ids); if (a === 'deldl') await q.deleteDownloads(ids); if (a === 'read') await q.markRead(ids, true); if (a === 'unread') await q.markRead(ids, false, 0);
      toast('Done'); mangaView(id); };
  }
  function chapterMenu(c, chapters, done) {
    const s = sheet(`<h3>${esc(c.name)}</h3><p class="row"><button data-a="read">Mark ${c.isRead ? 'unread' : 'read'}</button><button data-a="below">Mark previous as read</button><button data-a="bm">${c.isBookmarked ? 'Remove bookmark' : 'Bookmark'}</button>${c.isDownloaded ? '<button data-a="deldl">Delete from server</button>' : '<button data-a="dl">Download to server</button>'}</p>`);
    s.onclick = async e => { const a = e.target.dataset.a; if (!a) return;
      if (a === 'read') { await q.markRead([c.id], !c.isRead, c.isRead ? 0 : undefined); c.isRead = !c.isRead; }
      if (a === 'below') { const ids = chapters.filter(x => x.sourceOrder > c.sourceOrder || (x.chapterNumber < c.chapterNumber && x.chapterNumber >= 0)).map(x => x.id); if (ids.length) { await q.markRead(ids, true); chapters.forEach(x => { if (ids.includes(x.id)) x.isRead = true; }); } }
      if (a === 'bm') { await q.bookmark([c.id], !c.isBookmarked); c.isBookmarked = !c.isBookmarked; }
      if (a === 'dl') { await q.download([c.id]); c.isDownloaded = true; } if (a === 'deldl') { await q.deleteDownloads([c.id]); c.isDownloaded = false; }
      s.remove(); done(); };
  }

  // ---------------- reader
  async function readerView(mangaId, chapterId) {
    nav(''); document.body.classList.add('reading'); busy('Loading chapter…');
    let data; try { data = await q.mangaCached(mangaId); } catch (e) { document.body.classList.remove('reading'); return fail(e); }
    const chapters = data.chapters.slice().sort((a, b) => a.sourceOrder - b.sourceOrder).reverse(); // reading order: first → last
    const idx = chapters.findIndex(c => c.id === chapterId); const ch = chapters[idx]; if (!ch) return fail(new Error('chapter not found'));
    const prev = chapters[idx - 1], next = chapters[idx + 1];
    let pages; try { pages = await q.pages(chapterId); } catch (e) { document.body.classList.remove('reading'); return fail(e); }
    const mode = localStorage.getItem('reader.mode') || 'webtoon'; const fitw = localStorage.getItem('reader.fitw') !== '0'; const rtl = localStorage.getItem('reader.rtl') === '1';
    let page = Math.min(ch.lastPageRead || 0, pages.length - 1);
    view.innerHTML = `<div class="reader ${mode} ${fitw ? 'fitw' : ''}">
      <div class="hud top"><a href="#/manga/${mangaId}" title="Back">‹</a><div style="flex:1;min-width:0"><div style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(data.manga.title)}</div><div class="small" style="opacity:.8">${esc(ch.name)}</div></div>
        <button id="mode" title="Reading mode">${mode === 'webtoon' ? '⇅ Webtoon' : rtl ? '⇆ Paged RTL' : '⇄ Paged'}</button><button id="fit" title="Fit width">${fitw ? '⤢' : '⤡'}</button></div>
      <div class="pages" id="pages"></div>
      <div class="hud bottom">${prev ? `<a class="btn" href="#/read/${mangaId}/${prev.id}">‹ Prev</a>` : '<span></span>'}<span style="flex:1;text-align:center" id="pn"></span>${next ? `<a class="btn" href="#/read/${mangaId}/${next.id}">Next ›</a>` : `<a class="btn" href="#/manga/${mangaId}">Done</a>`}</div></div>`;
    const r = view.querySelector('.reader'); const box = view.querySelector('#pages'); const pn = view.querySelector('#pn');
    const src = (i) => img(pages[i]);
    let saveT = null; const save = (final) => { clearTimeout(saveT); saveT = setTimeout(() => q.markRead([chapterId], final ? true : null, page).catch(() => { }), final ? 0 : 1500); };
    const show = () => { pn.textContent = `${page + 1} / ${pages.length}`; if (page >= pages.length - 1) save(true); else save(false); };
    if (mode === 'webtoon') {
      box.innerHTML = pages.map((_, i) => `<img data-i="${i}" loading="lazy" src="${esc(src(i))}" alt=""><div class="gap"></div>`).join('');
      const io = new IntersectionObserver(es => es.forEach(e => { if (e.isIntersecting) { page = Number(e.target.dataset.i); show(); } }), { threshold: 0.4 });
      box.querySelectorAll('img').forEach(i => io.observe(i));
      if (page > 0) setTimeout(() => box.querySelector(`img[data-i="${page}"]`)?.scrollIntoView(), 200);
      box.onclick = () => r.classList.toggle('hidehud');
    } else {
      const render = () => { box.innerHTML = `<img src="${esc(src(page))}" alt="">`; [page + 1, page + 2].forEach(i => { if (pages[i]) new Image().src = src(i); }); show(); window.scrollTo(0, 0); };
      const go = (d) => { const n = page + d; if (n < 0) { if (prev) location.hash = `#/read/${mangaId}/${prev.id}`; return; } if (n >= pages.length) { if (next) location.hash = `#/read/${mangaId}/${next.id}`; else location.hash = `#/manga/${mangaId}`; return; } page = n; render(); };
      box.onclick = (e) => { const x = e.clientX / innerWidth; if (x > 0.35 && x < 0.65) return r.classList.toggle('hidehud'); const fwd = x >= 0.65; go((fwd !== rtl) ? 1 : -1); };
      window._readerKeys = (e) => { if (e.key === 'ArrowRight' || e.key === ' ') go(rtl ? -1 : 1); if (e.key === 'ArrowLeft') go(rtl ? 1 : -1); };
      document.addEventListener('keydown', window._readerKeys);
      render();
    }
    r.classList.add('hidehud');
    view.querySelector('#mode').onclick = () => { const order = ['webtoon', 'paged', 'paged-rtl']; const cur = mode === 'webtoon' ? 0 : rtl ? 2 : 1; const nx = order[(cur + 1) % 3]; localStorage.setItem('reader.mode', nx === 'webtoon' ? 'webtoon' : 'paged'); localStorage.setItem('reader.rtl', nx === 'paged-rtl' ? '1' : '0'); readerView(mangaId, chapterId); };
    view.querySelector('#fit').onclick = () => { localStorage.setItem('reader.fitw', fitw ? '0' : '1'); readerView(mangaId, chapterId); };
    show();
  }

  // ---------------- updates / history
  async function updatesView() {
    nav('updates'); busy();
    const [list, st] = await Promise.all([q.updates(), q.updateStatus()]);
    view.innerHTML = `<div class="row between"><h1>Updates</h1><button id="upd">${st.isRunning ? '… updating' : '↻ Update library'}</button></div><div class="list" id="l"></div>`;
    view.querySelector('#upd').onclick = async () => { await q.updateLibrary(); toast('Update started; come back in a minute'); };
    let last = '';
    view.querySelector('#l').innerHTML = list.map(c => { const d = date(c.fetchedAt); const h = d !== last ? `<h3>${esc(d)}</h3>` : ''; last = d;
      return h + `<a class="it ${c.isRead ? 'read' : ''}" href="#/read/${c.manga.id}/${c.id}"><img class="thumb" loading="lazy" src="${esc(img(c.manga.thumbnailUrl))}" alt=""><div class="m"><div>${esc(c.manga.title)}</div><div class="muted small">${esc(c.name)}${c.isDownloaded ? ' · ✓ on server' : ''}</div></div></a>`; }).join('') || '<p class="muted">No new chapters yet. Add manga to your library, then update.</p>';
  }
  async function historyView() {
    nav('history'); busy();
    const list = await q.history();
    view.innerHTML = `<h1>History</h1><div class="list">${list.map(c => `<a class="it" href="#/read/${c.manga.id}/${c.id}"><img class="thumb" loading="lazy" src="${esc(img(c.manga.thumbnailUrl))}" alt=""><div class="m"><div>${esc(c.manga.title)}</div><div class="muted small">${esc(c.name)} · ${date(c.lastReadAt)}${!c.isRead ? ` · page ${c.lastPageRead + 1}` : ''}</div></div></a>`).join('') || '<p class="muted">Nothing read yet.</p>'}</div>`;
  }

  // ---------------- downloads queue
  let dlTimer = null;
  async function downloadsView() {
    nav('downloads'); clearInterval(dlTimer);
    const render = async () => {
      const s = await q.downloadStatus();
      if (location.hash !== '#/downloads') return clearInterval(dlTimer);
      view.innerHTML = `<div class="row between"><h1>Downloads <span class="muted small">server queue · ${esc(s.state.toLowerCase())}</span></h1><div class="row"><button id="tg">${s.state === 'STARTED' ? '⏸ Pause' : '▶ Resume'}</button><button id="clr" ${s.queue.length ? '' : 'disabled'}>Clear</button></div></div>
        <div class="list">${s.queue.map(d => `<div class="it"><div class="m"><div>${esc(d.manga.title)}</div><div class="muted small">${esc(d.chapter.name)} · ${esc(d.state.toLowerCase())}${d.tries ? ` · try ${d.tries}` : ''}</div><div class="bar" style="margin-top:4px"><i style="width:${Math.round(d.progress * 100)}%"></i></div></div><button class="ic" data-rm="${d.chapter.id}">✕</button></div>`).join('') || '<p class="muted">Queue is empty. Downloads land in the server\'s manga folder as CBZ files and show as ✓ on chapters.</p>'}</div>`;
      view.querySelector('#tg').onclick = async () => { await q.downloader(s.state !== 'STARTED'); render(); };
      view.querySelector('#clr').onclick = async () => { if (confirm('Remove everything from the queue?')) { await q.dequeue(s.queue.map(d => d.chapter.id)); render(); } };
      view.querySelectorAll('[data-rm]').forEach(b => b.onclick = async () => { await q.dequeue([Number(b.dataset.rm)]); render(); });
    };
    busy(); await render(); dlTimer = setInterval(render, 2500);
  }

  // ---------------- files (Panels-style web server)
  async function filesView(path) {
    nav('files'); path = (path || '').replace(/^\/+|\/+$/g, '');
    let d; try { d = await fs.list(path); } catch (e) { return fail(e); }
    const crumbs = path ? path.split('/') : [];
    view.innerHTML = `<h1>Files</h1><p class="muted small"><b>local/</b> is yours: drop <b>CBZ/ZIP</b> files into <b>local/&lt;Manga name&gt;/</b> and they appear in Browse → Local source (and can be added to the library). <b>manga/</b> holds what the server downloaded (read-only here; delete via the chapter list).</p>
      <div class="row small" id="crumbs"><a href="#/files">root</a>${crumbs.map((c, i) => ` / <a href="#/files/${esc(crumbs.slice(0, i + 1).join('/'))}">${esc(c)}</a>`).join('')}</div>
      ${d.writable ? `<div class="row" style="margin:10px 0"><button id="nf">+ Folder</button><label class="btn primary">⇡ Upload <input type="file" multiple hidden id="up"></label></div><div class="drop" id="drop">…or drop files here</div><div id="prog"></div>` : ''}
      <div class="list" id="fl"></div>`;
    const list = view.querySelector('#fl');
    list.innerHTML = d.entries.map(e => { const p = (path ? path + '/' : '') + e.name;
      return `<div class="it fileentry">${e.dir ? `<a class="name" href="#/files/${esc(p)}">📁 ${esc(e.name)}</a>` : `<a class="name" href="${esc(fs.fileUrl(p))}">📄 ${esc(e.name)}</a>`}<span class="muted small">${e.dir ? (e.writable === false ? 'read-only' : '') : bytes(e.size)}</span>
      ${d.writable && path ? `<button class="ic" data-mv="${esc(p)}" title="Rename / move">✎</button><button class="ic" data-del="${esc(p)}" title="Delete">🗑</button>` : ''}</div>`; }).join('') || '<p class="muted">Empty folder.</p>';
    list.onclick = async e => {
      const mv = e.target.dataset.mv, del = e.target.dataset.del;
      if (mv) { const to = prompt('New path (inside local/)', mv); if (to && to !== mv) { await fs.move(mv, to); filesView(path); } }
      if (del && confirm('Delete ' + del + '?')) { await fs.remove(del); filesView(path); }
    };
    if (d.writable) {
      view.querySelector('#nf').onclick = async () => { const n = prompt('Folder name (use the manga title)'); if (n) { await fs.mkdir((path ? path + '/' : '') + n); filesView(path); } };
      const upload = async (files) => { const prog = view.querySelector('#prog');
        for (const f of files) { const row = el(`<div class="small">${esc(f.name)} <div class="bar"><i style="width:0"></i></div></div>`); prog.appendChild(row);
          try { await fs.upload((path ? path + '/' : '') + f.name, f, p => row.querySelector('i').style.width = Math.round(p * 100) + '%'); } catch (err) { row.append(' failed: ' + err.message); } }
        toast('Upload done'); filesView(path); };
      view.querySelector('#up').onchange = e => upload([...e.target.files]);
      const drop = view.querySelector('#drop');
      drop.ondragover = e => { e.preventDefault(); drop.classList.add('over'); }; drop.ondragleave = () => drop.classList.remove('over');
      drop.ondrop = e => { e.preventDefault(); drop.classList.remove('over'); upload([...e.dataTransfer.files]); };
    }
  }

  // ---------------- extensions + repos
  async function extensionsView() {
    nav('extensions'); busy();
    let [exts, stores] = await Promise.all([q.extensions(), q.stores()]);
    const st = { tab: sessionStorage.getItem('ext.tab') || 'installed', q: '' };
    const langs = [...new Set(exts.map(e => e.lang))].sort();
    view.innerHTML = `<h1>Extensions</h1>
      <div class="card"><h3 style="margin-top:0">Repositories</h3><div id="stores"></div><form class="row" id="addst"><input placeholder="https://…/index.pb or index.min.json" style="flex:1;min-width:200px"><button class="primary">Add repo</button><button type="button" id="refetch">↻ Refresh list</button></form></div>
      <div class="toolbar"><div class="row"><div class="chips"><span class="chip" data-t="installed">Installed</span><span class="chip" data-t="available">Available</span><span class="chip" data-t="updates">Updates</span></div><input id="eq" placeholder="Filter…" style="flex:1;min-width:120px"><label class="small"><input type="checkbox" id="nsfw" ${cfg.nsfw() ? 'checked' : ''}> 18+</label></div>
      <div class="chips small" id="langs" style="margin-top:6px"></div></div><div class="list" id="el"></div>`;
    const renderStores = () => { view.querySelector('#stores').innerHTML = stores.map(s => `<div class="row between" style="padding:4px 0"><div><b>${esc(s.name)}</b> <span class="muted small">${esc(s.indexUrl)}</span></div><button class="ic" data-rm="${esc(s.indexUrl)}">🗑</button></div>`).join('') || '<p class="muted">No repos. Add one (keiyoushi is the usual default).</p>'; };
    renderStores();
    view.querySelector('#stores').onclick = async e => { const u = e.target.dataset.rm; if (u && confirm('Remove this repo?')) { await q.removeStore(u); stores = await q.stores(); renderStores(); } };
    view.querySelector('#addst').onsubmit = async e => { e.preventDefault(); const u = e.target.querySelector('input').value.trim(); if (!u) return; try { await q.addStore(u); await q.fetchExtensions(); toast('Repo added'); extensionsView(); } catch (err) { toast('Failed: ' + err.message, 4000); } };
    view.querySelector('#refetch').onclick = async () => { await q.fetchExtensions(); toast('Refreshed'); extensionsView(); };
    const langBox = view.querySelector('#langs'); const on = new Set(cfg.langs());
    langBox.innerHTML = ['*'].concat(langs).map(l => `<span class="chip ${on.has(l) ? 'on' : ''}" data-l="${esc(l)}">${l === '*' ? 'any' : esc(l)}</span>`).join('');
    langBox.onclick = e => { const c = e.target.closest('.chip'); if (!c) return; const l = c.dataset.l; on.has(l) ? on.delete(l) : on.add(l); localStorage.setItem('kumo.langs', JSON.stringify([...on])); c.classList.toggle('on'); render(); };
    view.querySelector('#nsfw').onchange = e => { localStorage.setItem('kumo.nsfw', e.target.checked ? '1' : '0'); render(); };
    view.querySelector('#eq').oninput = e => { st.q = e.target.value.toLowerCase(); render(); };
    view.querySelectorAll('.chip[data-t]').forEach(c => c.onclick = () => { st.tab = c.dataset.t; sessionStorage.setItem('ext.tab', st.tab); render(); });
    const list = view.querySelector('#el');
    const render = () => {
      view.querySelectorAll('.chip[data-t]').forEach(c => c.classList.toggle('on', c.dataset.t === st.tab));
      let l = exts.filter(e => st.tab === 'installed' ? e.isInstalled : st.tab === 'updates' ? e.hasUpdate : !e.isInstalled);
      if (st.tab !== 'installed') l = l.filter(e => (cfg.nsfw() || e.contentWarning !== 'NSFW') && (on.has('*') || on.has(e.lang)));
      if (st.q) l = l.filter(e => (e.name + ' ' + e.pkgName).toLowerCase().includes(st.q));
      l.sort((a, b) => a.lang.localeCompare(b.lang) || a.name.localeCompare(b.name));
      list.innerHTML = l.slice(0, 400).map(e => `<div class="it"><img class="thumb" style="height:40px;width:40px" loading="lazy" src="${esc(img(e.iconUrl))}" alt=""><div class="m"><div>${esc(e.name)} <span class="muted small">${esc(e.versionName)}${e.contentWarning === 'NSFW' ? ' · 18+' : e.contentWarning === 'MIXED' ? ' · mixed' : ''}${e.isObsolete ? ' · obsolete' : ''}</span></div><div class="muted small">${esc(e.lang)} · ${esc(e.pkgName)}</div></div>
        ${e.hasUpdate ? `<button class="primary" data-up="${esc(e.pkgName)}">Update</button>` : ''}${e.isInstalled ? `<button data-un="${esc(e.pkgName)}">Uninstall</button>` : `<button class="primary" data-in="${esc(e.pkgName)}">Install</button>`}</div>`).join('') || '<p class="muted">Nothing matches.</p>';
      if (l.length > 400) list.append(el(`<p class="muted small">${l.length - 400} more — narrow the filter.</p>`));
    };
    list.onclick = async e => { const b = e.target.closest('button'); if (!b) return; const pkg = b.dataset.in || b.dataset.un || b.dataset.up; b.disabled = true; b.textContent = '…';
      try { await q.extension(pkg, b.dataset.in ? { install: true } : b.dataset.un ? { uninstall: true } : { update: true }); exts = await q.extensions(); render(); toast('Done'); } catch (err) { toast('Failed: ' + err.message, 4000); render(); } };
    render();
  }

  // ---------------- more / settings
  function moreView() {
    nav('more');
    view.innerHTML = `<h1>More</h1><div class="list"><a class="it" href="#/history"><div class="m">History</div>›</a><a class="it" href="#/files"><div class="m">Files <span class="muted small">upload CBZ/ZIP, folders</span></div>›</a><a class="it" href="#/extensions"><div class="m">Extensions &amp; repos</div>›</a><a class="it" href="#/settings"><div class="m">Settings</div>›</a></div>`;
  }
  async function settingsView() {
    nav('settings'); busy();
    let about = null; try { about = await q.about(); } catch (e) { /* offline */ }
    view.innerHTML = `<h1>Settings</h1>
      <div class="card"><h3 style="margin-top:0">Server</h3><label class="small">Backend URL</label><input id="api" value="${esc(cfg.api)}" style="width:100%"><label class="small">File service URL</label><input id="files" value="${esc(cfg.files)}" style="width:100%">
        <p class="row"><button class="primary" id="save">Save</button><button id="logout">Sign out (${esc(cfg.user)})</button></p>
        ${about ? `<div class="muted small">${esc(about.aboutServer.name)} ${esc(about.aboutServer.version)} (${esc(about.aboutServer.revision)}) · downloads: ${esc(about.settings.downloadsPath)} · uploads: ${esc(about.settings.localSourcePath)}</div>` : '<div class="muted small">Server not reachable.</div>'}</div>
      ${about ? `<div class="card"><h3 style="margin-top:0">Downloads &amp; updates</h3><label><input type="checkbox" id="cbz" ${about.settings.downloadAsCbz ? 'checked' : ''}> Save chapters as CBZ (one file per chapter)</label><br><label><input type="checkbox" id="auto" ${about.settings.autoDownloadNewChapters ? 'checked' : ''}> Auto-download new chapters of library manga</label><br>
        <label>Check for new chapters every <input id="int" type="number" min="6" step="1" value="${Number(about.settings.globalUpdateInterval)}" style="width:70px"> hours (0 = off)</label><p><button id="ss">Apply</button></p></div>` : ''}
      <div class="card"><h3 style="margin-top:0">Reader</h3><div class="muted small">Mode, fit and direction are set inside the reader (top bar) and remembered. Keys: <kbd>←</kbd> <kbd>→</kbd> <kbd>space</kbd>; tap edges to turn, middle to hide the bar.</div></div>
      <div class="card"><h3 style="margin-top:0">About</h3><div class="muted small">Kumo — Tachiyomi-style sources through your own server, Panels-style files. The server runs the extensions; this page and the iPhone app only talk to it.</div></div>`;
    view.querySelector('#save').onclick = () => { cfg.api = view.querySelector('#api').value.trim(); cfg.files = view.querySelector('#files').value.trim(); toast('Saved'); };
    view.querySelector('#logout').onclick = () => { Kumo.logout(); location.hash = '#/login'; };
    const ss = view.querySelector('#ss'); if (ss) ss.onclick = async () => { await q.setSettings({ downloadAsCbz: view.querySelector('#cbz').checked, autoDownloadNewChapters: view.querySelector('#auto').checked, globalUpdateInterval: Number(view.querySelector('#int').value) }); toast('Applied'); };
  }

  // ---------------- router
  async function route() {
    document.body.classList.remove('reading'); if (window._readerKeys) { document.removeEventListener('keydown', window._readerKeys); window._readerKeys = null; } clearInterval(dlTimer);
    const h = location.hash.replace(/^#\/?/, ''); const [r, a, b] = h.split('/');
    if (!Kumo.loggedIn() && r !== 'login') return loginView(location.hash);
    try {
      switch (r) {
        case 'login': return loginView();
        case '': case 'library': return await libraryView();
        case 'browse': return await browseView();
        case 'source': return await sourceView(a);
        case 'manga': return await mangaView(Number(a));
        case 'read': return await readerView(Number(a), Number(b));
        case 'updates': return await updatesView();
        case 'history': return await historyView();
        case 'downloads': return await downloadsView();
        case 'files': return await filesView(decodeURIComponent(h.slice(5)));
        case 'extensions': return await extensionsView();
        case 'more': return moreView();
        case 'settings': return await settingsView();
        default: location.hash = '#/library';
      }
    } catch (e) { if (e.code === 401) return loginView(location.hash); fail(e); }
  }
  window.addEventListener('hashchange', route);
  route();
})();
