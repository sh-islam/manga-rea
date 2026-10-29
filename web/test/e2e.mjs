// Headless-Chrome walk through the web app over CDP (Node 22+, no deps). Password comes from the
// environment (KUMO_USER / KUMO_PASS, see server/.env) and never reaches stdout.
//   node web/test/e2e.mjs http://127.0.0.1:8787 <chrome.exe> <outdir>
import { spawn } from 'node:child_process';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const [base, chrome, out] = process.argv.slice(2);
const SERVER = process.env.KUMO_SERVER || 'http://127.0.0.1:4567';
const FILES = process.env.KUMO_FILES || SERVER + '/files';
mkdirSync(out, { recursive: true });
const port = 9333;
const proc = spawn(chrome, [...(process.env.KUMO_CHROME_FLAGS || '').split(' ').filter(Boolean), `--remote-debugging-port=${port}`, '--headless=new', '--no-first-run', '--no-default-browser-check', `--user-data-dir=${join(out, 'profile')}`, '--window-size=1280,900', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
let ws, id = 0; const pending = new Map(); const events = [];
async function connect() {
  for (let i = 0; i < 40; i++) {
    try { const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); const t = list.find(x => x.type === 'page'); if (t) { ws = new WebSocket(t.webSocketDebuggerUrl); break; } } catch (_) { }
    await sleep(250);
  }
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } else if (d.method) events.push(d); };
}
const send = (method, params) => new Promise(res => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params: params || {} })); });
const evaluate = async (expr) => { const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }); if (r.result.exceptionDetails) throw new Error(r.result.exceptionDetails.text + ' ' + (r.result.exceptionDetails.exception?.description || '')); return r.result.result.value; };
const shot = async (name) => { const r = await send('Page.captureScreenshot', { format: 'png' }); writeFileSync(join(out, name + '.png'), Buffer.from(r.result.data, 'base64')); };
const text = () => evaluate('document.getElementById("view").innerText.slice(0, 600)');
const go = async (hash) => { await evaluate(`location.hash = ${JSON.stringify(hash)}`); await sleep(1500); };
const errors = () => events.filter(e => e.method === 'Runtime.exceptionThrown' || (e.method === 'Runtime.consoleAPICalled' && e.params.type === 'error')).map(e => e.method === 'Runtime.exceptionThrown' ? e.params.exceptionDetails.exception?.description || e.params.exceptionDetails.text : e.params.args.map(a => a.value || a.description).join(' '));

try {
  await connect();
  await send('Runtime.enable'); await send('Page.enable');
  await send('Page.navigate', { url: base + '/index.html#/login' }); await sleep(1500);
  console.log('login page:', (await text()).split('\n')[0]);
  await evaluate(`document.querySelector('#u').value = ${JSON.stringify(process.env.KUMO_USER)}; document.querySelector('#p').value = ${JSON.stringify(process.env.KUMO_PASS)}; document.querySelector('#s').value = ${JSON.stringify(SERVER)}; document.querySelector('form').requestSubmit();`);
  await sleep(2500);
  await evaluate(`localStorage.setItem('kumo.files', ${JSON.stringify(FILES)}); Kumo.login(${JSON.stringify(process.env.KUMO_USER)}, ${JSON.stringify(process.env.KUMO_PASS)})`); await sleep(1500);
  console.log('api sources:', JSON.stringify(await evaluate(`Kumo.q.sources().then(s => [s.length, s.slice(0,3).map(x => [x.displayName, x.lang, x.isNsfw])])`)), 'installed exts:', JSON.stringify(await evaluate(`Kumo.q.extensions().then(e => e.filter(x => x.isInstalled).map(x => x.pkgName))`)));
  console.log('after login hash:', await evaluate('location.hash'), '| token stored:', await evaluate('!!localStorage.getItem("kumo.token")'));
  for (const [hash, name] of [['#/library', 'library'], ['#/browse', 'browse'], ['#/extensions', 'extensions'], ['#/downloads', 'downloads'], ['#/files', 'files'], ['#/files/local', 'files-local'], ['#/updates', 'updates'], ['#/settings', 'settings']]) {
    await go(hash); await shot(name); console.log(`\n== ${name}\n` + (await text()).split('\n').slice(0, 8).join(' | '));
  }
  // source page: first source in the list → search → first result → manga → reader
  await go('#/browse');
  const srcHref = await evaluate(`(document.querySelector('#sl a[href^="#/source/"]') || {}).getAttribute?.('href') || ''`);
  const srcs = await evaluate(`[...document.querySelectorAll('#sl a[href^="#/source/"]')].map(a => a.innerText.split('\\n')[0])`);
  console.log('\nsources:', srcs.slice(0, 5));
  const dex = await evaluate(`([...document.querySelectorAll('#sl a[href^="#/source/"]')].find(a => a.innerText.includes('MangaDex') && a.innerText.includes('en')) || {}).getAttribute?.('href') || ''`);
  await go(dex || srcHref); await sleep(3000); await shot('source'); console.log('\n== source\n' + (await text()).split('\n').slice(0, 6).join(' | '));
  await evaluate(`document.querySelector('#sq').value = 'komi'; document.querySelector('#sf').requestSubmit()`); await sleep(5000); await shot('source-search');
  console.log('search results:', await evaluate(`document.querySelectorAll('#grid .cover').length`));
  const hrefs = await evaluate(`[...document.querySelectorAll('#grid .cover')].slice(0, 6).map(a => a.getAttribute('href'))`);
  let mh = '';
  for (const h of hrefs) { await go(h); await sleep(3500); if (await evaluate(`document.querySelectorAll('#chs .it').length`) > 0) { mh = h; break; } }
  await shot('manga'); console.log('\n== manga', mh, '\n' + (await text()).split('\n').slice(0, 10).join(' | '));
  const rh = await evaluate(`(document.querySelector('#chs .it:last-child a') || {}).getAttribute?.('href') || ''`);
  await go(rh); await sleep(5000); await shot('reader'); console.log('\n== reader body class:', await evaluate('document.body.className'), 'pages:', await evaluate(`document.querySelectorAll('#pages img').length`), 'hud:', await evaluate(`document.querySelector('.reader .hud')?.innerText.replace(/\\n/g,' | ')`));
  await evaluate(`document.querySelector('#mode').click()`); await sleep(2500); await shot('reader-paged'); console.log('mode →', await evaluate(`document.querySelector('#mode')?.innerText`), 'imgs:', await evaluate(`document.querySelectorAll('#pages img').length`));
  await go('#/history'); console.log('\n== history\n' + (await text()).split('\n').slice(0, 4).join(' | '));
  console.log('\nJS errors:', errors().length ? errors() : 'none');
} catch (e) { console.error('E2E FAILED:', e.message); console.log('JS errors:', errors()); process.exitCode = 1; }
finally { try { ws.close(); } catch (_) { } proc.kill(); }
