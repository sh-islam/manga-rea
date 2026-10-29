// Diagnose a failing fetch from the public web app to the backend: capture Chrome's network error.
import { spawn } from 'node:child_process';
const [base, chrome, server] = process.argv.slice(2);
const port = 9334;
const proc = spawn(chrome, [`--remote-debugging-port=${port}`, '--headless=new', '--no-first-run', `--user-data-dir=${process.env.TEMP}\kumo-diag-profile`, 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise(r => setTimeout(r, ms));
let ws, id = 0; const pending = new Map(); const events = [];
for (let i = 0; i < 40 && !ws; i++) { try { const l = await (await fetch(`http://127.0.0.1:${port}/json`)).json(); const t = l.find(x => x.type === 'page'); if (t) ws = new WebSocket(t.webSocketDebuggerUrl); } catch (_) { } await sleep(250); }
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
ws.onmessage = (m) => { const d = JSON.parse(m.data); if (d.id && pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } else if (d.method) events.push(d); };
const send = (method, params) => new Promise(res => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params: params || {} })); });
await send('Network.enable'); await send('Runtime.enable'); await send('Page.enable');
await send('Page.navigate', { url: base + '/index.html#/login' }); await sleep(2000);
const r = await send('Runtime.evaluate', { expression: `Promise.race([new Promise(r => setTimeout(() => r('TIMEOUT 15s'), 15000)), fetch(${JSON.stringify(server)} + '/api/graphql', {method:'POST', headers:{'content-type':'application/json'}, body:'{"query":"{__typename}"}'}).then(r => r.text()).catch(e => 'ERR ' + e.message)])`, awaitPromise: true, returnByValue: true });
console.log('fetch result:', r.result.result.value);
await sleep(1000);
for (const e of events) {
  if (e.method === 'Network.loadingFailed') console.log('loadingFailed:', JSON.stringify(e.params).slice(0, 400));
  if (e.method === 'Network.requestWillBeSent' && e.params.request.url.includes('graphql')) console.log('request:', e.params.request.method, e.params.request.url);
  if (e.method === 'Network.responseReceived' && e.params.response.url.includes('graphql')) console.log('response:', e.params.response.status, 'remote', e.params.response.remoteIPAddress, JSON.stringify(e.params.response.headers).slice(0, 300));
  if (e.method === 'Runtime.consoleAPICalled') console.log('console:', e.params.args.map(a => a.value || a.description).join(' ').slice(0, 300));
}
ws.close(); proc.kill(); setTimeout(() => process.exit(0), 500);
