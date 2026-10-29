// Kumo web app: talks to the Kumo backend (Suwayomi GraphQL) and the Kumo file service.
// Static site, no build step. Settings (server URL, tokens) live in localStorage.
const Kumo = (() => {
  const LS = window.localStorage;
  const cfg = {
    get api() { return LS.getItem('kumo.api') || 'https://shad-server.elf-tarpon.ts.net:8443'; },
    set api(v) { LS.setItem('kumo.api', v.replace(/\/+$/, '')); },
    get files() { return LS.getItem('kumo.files') || (this.api + '/files'); },
    set files(v) { LS.setItem('kumo.files', v.replace(/\/+$/, '')); },
    get token() { return LS.getItem('kumo.token') || ''; },
    get refresh() { return LS.getItem('kumo.refresh') || ''; },
    get filesToken() { return LS.getItem('kumo.filesToken') || ''; },
    get user() { return LS.getItem('kumo.user') || ''; },
    nsfw: () => LS.getItem('kumo.nsfw') === '1',
    langs: () => JSON.parse(LS.getItem('kumo.langs') || '["en","all"]'),
  };

  async function gqlRaw(query, variables, token) {
    const r = await fetch(cfg.api + '/api/graphql', {
      method: 'POST',
      headers: { 'content-type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
      body: JSON.stringify({ query, variables: variables || {} }),
    });
    if (r.status === 401) throw Object.assign(new Error('unauthorized'), { code: 401 });
    const d = await r.json();
    if (d.errors && d.errors.length) throw new Error(d.errors.map(e => e.message.split('\n')[0]).join('; '));
    return d.data;
  }

  let refreshing = null;
  async function gql(query, variables) {
    try {
      return await gqlRaw(query, variables, cfg.token);
    } catch (e) {
      if (e.code !== 401 || !cfg.refresh) throw e;
      refreshing = refreshing || gqlRaw('mutation($t:String!){ refreshToken(input:{refreshToken:$t}) { accessToken } }', { t: cfg.refresh })
        .then(d => { LS.setItem('kumo.token', d.refreshToken.accessToken); })
        .catch(() => { logout(); throw e; })
        .finally(() => { refreshing = null; });
      await refreshing;
      return gqlRaw(query, variables, cfg.token);
    }
  }

  async function login(user, pass) {
    const d = await gqlRaw('mutation($u:String!,$p:String!){ login(input:{username:$u,password:$p}) { accessToken refreshToken } }', { u: user, p: pass });
    LS.setItem('kumo.token', d.login.accessToken);
    LS.setItem('kumo.refresh', d.login.refreshToken);
    LS.setItem('kumo.user', user);
    try {
      const r = await fetch(cfg.files + '/auth/login', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: user, password: pass }) });
      if (r.ok) LS.setItem('kumo.filesToken', (await r.json()).token);
    } catch (_) { /* file service optional */ }
  }
  function logout() { ['kumo.token', 'kumo.refresh', 'kumo.filesToken'].forEach(k => LS.removeItem(k)); }
  const loggedIn = () => !!cfg.token;

  // images: Suwayomi accepts the JWT as ?token= on /api/v1/... image routes
  const img = (path) => path ? (path.startsWith('http') ? path : cfg.api + path) + (path.includes('?') ? '&' : '?') + 'token=' + encodeURIComponent(cfg.token) : '';

  // ---- file service
  async function files(path, opts) {
    const r = await fetch(cfg.files + path, { ...(opts || {}), headers: { Authorization: 'Bearer ' + cfg.filesToken, ...((opts && opts.headers) || {}) } });
    if (r.status === 401) throw new Error('file service: login again');
    const ct = r.headers.get('content-type') || '';
    return ct.includes('json') ? r.json() : r;
  }
  const fs = {
    list: (p) => files('/fs?path=' + encodeURIComponent(p || '')),
    mkdir: (p) => files('/fs/mkdir', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ path: p }) }),
    move: (from, to) => files('/fs/move', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ from, to }) }),
    remove: (p) => files('/fs/delete', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ path: p }) }),
    upload: (p, file, onProgress) => new Promise((res, rej) => {
      const x = new XMLHttpRequest();
      x.open('PUT', cfg.files + '/fs/upload?path=' + encodeURIComponent(p));
      x.setRequestHeader('Authorization', 'Bearer ' + cfg.filesToken);
      x.upload.onprogress = e => onProgress && onProgress(e.loaded / (e.total || 1));
      x.onload = () => x.status < 300 ? res(JSON.parse(x.responseText)) : rej(new Error(x.responseText));
      x.onerror = () => rej(new Error('upload failed'));
      x.send(file);
    }),
    fileUrl: (p) => cfg.files + '/fs/file?path=' + encodeURIComponent(p) + '&token=' + encodeURIComponent(cfg.filesToken),
  };

  // ---- GraphQL fragments & calls (shapes mirror what the iOS app uses too)
  const MANGA = 'id title thumbnailUrl inLibrary unreadCount downloadCount author status sourceId source { displayName lang } latestUploadedChapter { uploadDate } lastReadChapter { id name }';
  const CHAPTER = 'id name chapterNumber scanlator uploadDate isRead isDownloaded isBookmarked pageCount lastPageRead sourceOrder';
  const q = {
    library: (categoryId) => gql(`query($f:MangaFilterInput){ mangas(filter:$f, order:[{by:TITLE}]) { nodes { ${MANGA} categories { nodes { id } } } } }`,
      { f: categoryId == null ? { inLibrary: { equalTo: true } } : { inLibrary: { equalTo: true }, categoryId: { equalTo: categoryId } } }).then(d => d.mangas.nodes),
    categories: () => gql('{ categories(order:[{by:ORDER}]) { nodes { id name order default mangas { totalCount } } } }').then(d => d.categories.nodes),
    sources: () => gql('{ sources { nodes { id name displayName lang iconUrl isNsfw supportsLatest isConfigurable extension { pkgName } } } }').then(d => d.sources.nodes),
    source: (id) => gql('query($id:LongString!){ source(id:$id) { id displayName lang supportsLatest isConfigurable filters { __typename ... on CheckBoxFilter { name default } ... on TriStateFilter { name default } ... on SelectFilter { name default values } ... on SortFilter { name values default { index ascending } } ... on TextFilter { name default } ... on HeaderFilter { name } ... on SeparatorFilter { name } ... on GroupFilter { name filters { __typename ... on CheckBoxFilter { name default } ... on TriStateFilter { name default } ... on SelectFilter { name default values } ... on TextFilter { name default } } } } } }', { id }).then(d => d.source),
    sourceManga: (source, type, page, query, filters) => gql(`mutation($i:FetchSourceMangaInput!){ fetchSourceManga(input:$i) { hasNextPage mangas { ${MANGA} } } }`,
      { i: { source, type, page, query: query || null, filters: filters || null } }).then(d => d.fetchSourceManga),
    manga: (id, refresh) => gql(`mutation($id:Int!,$r:Boolean!){ fetchMangaAndChapters(input:{id:$id, fetchManga:$r, fetchChapters:$r}) { manga { ${MANGA} description genre artist url realUrl categories { nodes { id name } } } chapters { ${CHAPTER} } } }`, { id, r: !!refresh }).then(d => d.fetchMangaAndChapters),
    mangaCached: (id) => gql(`query($id:Int!){ manga(id:$id) { ${MANGA} description genre artist url realUrl categories { nodes { id name } } chapters { nodes { ${CHAPTER} } } } }`, { id }).then(d => ({ manga: d.manga, chapters: d.manga.chapters.nodes })),
    pages: (chapterId) => gql('mutation($id:Int!){ fetchChapterPages(input:{chapterId:$id}) { pages } }', { id: chapterId }).then(d => d.fetchChapterPages.pages),
    setLibrary: (id, inLibrary) => gql('mutation($id:Int!,$v:Boolean!){ updateManga(input:{id:$id, patch:{inLibrary:$v}}) { manga { inLibrary } } }', { id, v: inLibrary }),
    setCategories: (id, add, remove) => gql('mutation($id:Int!,$a:[Int!],$r:[Int!]){ updateMangaCategories(input:{id:$id, patch:{addToCategories:$a, removeFromCategories:$r}}) { manga { id } } }', { id, a: add, r: remove }),
    createCategory: (name) => gql('mutation($n:String!){ createCategory(input:{name:$n}) { category { id } } }', { n: name }),
    deleteCategory: (id) => gql('mutation($id:Int!){ deleteCategory(input:{categoryId:$id}) { category { id } } }', { id }),
    download: (ids) => gql('mutation($ids:[Int!]!){ enqueueChapterDownloads(input:{ids:$ids}) { downloadStatus { state } } }', { ids }),
    deleteDownloads: (ids) => gql('mutation($ids:[Int!]!){ deleteDownloadedChapters(input:{ids:$ids}) { chapters { id isDownloaded } } }', { ids }),
    dequeue: (ids) => gql('mutation($ids:[Int!]!){ dequeueChapterDownloads(input:{ids:$ids}) { downloadStatus { state } } }', { ids }),
    downloadStatus: () => gql(`{ downloadStatus { state queue { position progress state tries chapter { id name } manga { id title } } } }`).then(d => d.downloadStatus),
    downloader: (start) => gql(start ? 'mutation{ startDownloader(input:{}) { downloadStatus { state } } }' : 'mutation{ stopDownloader(input:{}) { downloadStatus { state } } }'),
    markRead: (ids, read, lastPage) => gql('mutation($ids:[Int!]!,$p:UpdateChapterPatchInput!){ updateChapters(input:{ids:$ids, patch:$p}) { chapters { id } } }', { ids, p: read == null ? { lastPageRead: lastPage } : { isRead: read, lastPageRead: lastPage == null ? undefined : lastPage } }),
    bookmark: (ids, v) => gql('mutation($ids:[Int!]!,$v:Boolean!){ updateChapters(input:{ids:$ids, patch:{isBookmarked:$v}}) { chapters { id } } }', { ids, v }),
    updates: () => gql(`{ chapters(filter:{inLibrary:{equalTo:true}}, order:[{by:FETCHED_AT, byType:DESC}], first:100) { nodes { ${CHAPTER} fetchedAt manga { id title thumbnailUrl } } } }`).then(d => d.chapters.nodes),
    history: () => gql(`{ chapters(filter:{lastReadAt:{greaterThan:"0"}}, order:[{by:LAST_READ_AT, byType:DESC}], first:60) { nodes { ${CHAPTER} lastReadAt manga { id title thumbnailUrl } } } }`).then(d => d.chapters.nodes),
    updateLibrary: () => gql('mutation{ updateLibrary(input:{}) { updateStatus { isRunning } } }'),
    updateStatus: () => gql('{ updateStatus { isRunning runningJobs { mangas { totalCount } } pendingJobs { mangas { totalCount } } completeJobs { mangas { totalCount } } } }').then(d => d.updateStatus),
    extensions: () => gql('{ extensions { nodes { pkgName name lang versionName isInstalled hasUpdate isNsfw isObsolete iconUrl repo storeIndexUrl } } }').then(d => d.extensions.nodes),
    fetchExtensions: () => gql('mutation{ fetchExtensions(input:{}) { extensions { pkgName } } }'),
    extension: (id, patch) => gql('mutation($id:String!,$p:UpdateExtensionPatchInput!){ updateExtension(input:{id:$id, patch:$p}) { extension { pkgName isInstalled } } }', { id, p: patch }),
    stores: () => gql('{ extensionStores { nodes { indexUrl name badgeLabel isLegacy contactWebsite } } }').then(d => d.extensionStores.nodes),
    addStore: (url) => gql('mutation($u:String!){ addExtensionStore(input:{indexUrl:$u}) { extensionStore { name } } }', { u: url }),
    removeStore: (url) => gql('mutation($u:String!){ removeExtensionStore(input:{indexUrl:$u}) { extensionStore { name } } }', { u: url }),
    about: () => gql('{ aboutServer { name version revision buildType } settings { downloadsPath localSourcePath downloadAsCbz globalUpdateInterval autoDownloadNewChapters } }'),
    setSettings: (s) => gql('mutation($s:PartialSettingsTypeInput!){ setSettings(input:{settings:$s}) { settings { downloadAsCbz } } }', { s }),
    globalSearch: async (query, sources) => {
      const out = [];
      await Promise.all(sources.map(async s => {
        try { const r = await q.sourceManga(s.id, 'SEARCH', 1, query); if (r.mangas.length) out.push({ source: s, mangas: r.mangas }); } catch (_) { }
      }));
      return out;
    },
  };

  return { cfg, gql, login, logout, loggedIn, img, fs, q };
})();
