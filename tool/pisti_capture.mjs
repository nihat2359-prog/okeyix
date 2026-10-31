// Captures the actual Flutter debug web build. No production service is started.
// flutter build web --debug -t lib/main_pisti_demo.dart -o build/pisti_demo_web
import { createServer } from 'node:http';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
const root = resolve('build/pisti_demo_web'), out = resolve('build/pisti_demo_captures');
await mkdir(out, { recursive: true });
const server = createServer(async (req, res) => {
  try {
    const path = resolve(root, '.' + decodeURIComponent(new URL(req.url, 'http://localhost').pathname).replace(/\/$/, '/index.html'));
    if (!path.startsWith(root + sep)) { res.writeHead(403).end(); return; }
    res.setHeader('Content-Type', ({ '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.html': 'text/html', '.png': 'image/png', '.css': 'text/css', '.ttf': 'font/ttf' })[extname(path)] || 'application/octet-stream');
    res.end(await readFile(path));
  } catch { res.writeHead(404).end(); }
});
await new Promise((ok) => server.listen(0, '127.0.0.1', ok));
const browser = spawn(process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', '--no-sandbox', '--disable-gpu-sandbox', '--enable-unsafe-swiftshader',
  '--use-angle=swiftshader', '--no-first-run', '--disable-background-networking',
  '--remote-debugging-port=0', `--user-data-dir=${out}/chrome-profile`, 'about:blank',
], { stdio: ['ignore', 'ignore', 'pipe'] });
let ws, send;
try {
  const endpoint = await new Promise((ok, fail) => {
    const timer = setTimeout(() => fail(Error('Chrome startup timeout')), 15000);
    browser.stderr.on('data', (d) => { const m = String(d).match(/DevTools listening on (ws:\/\/[^\s]+)/); if (m) { clearTimeout(timer); ok(m[1]); } });
    browser.once('error', fail);
  });
  ws = new WebSocket(endpoint); await new Promise((ok) => ws.addEventListener('open', ok, { once: true }));
  let serial = 0; const pending = new Map(), errors = [];
  ws.addEventListener('message', ({ data }) => {
    const m = JSON.parse(data);
    if (m.id) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p?.reject(Error(JSON.stringify(m.error))) : p?.resolve(m.result); }
    if (m.method === 'Runtime.exceptionThrown') errors.push(m.params.exceptionDetails);
    if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') errors.push(m.params.args.map((a) => a.value || a.description));
  });
  send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    const id = ++serial, timer = setTimeout(() => reject(Error(method + ' timed out')), 45000);
    pending.set(id, { resolve: (v) => { clearTimeout(timer); resolve(v); }, reject: (e) => { clearTimeout(timer); reject(e); } });
    ws.send(JSON.stringify({ id, method, params, sessionId }));
  });
  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  const call = (m, p) => send(m, p, sessionId);
  const wait = (ms) => new Promise((ok) => setTimeout(ok, ms));
  const evaluate = async (expression) => {
    const r = await call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw Error(JSON.stringify(r.exceptionDetails)); return r.result.value;
  };
  await call('Runtime.enable'); await call('Page.enable');
  async function capture(name) {
    const { data } = await call('Page.captureScreenshot', { format: 'png' });
    await writeFile(`${out}/${name}.png`, Buffer.from(data, 'base64'));
    console.log(`Captured ${name}`); return data;
  }
  async function tap(x, y) {
    for (const type of ['mousePressed', 'mouseReleased']) await call('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
  }
  async function open(width, height, scenario = 'normal') {
    await call('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
    await call('Page.navigate', { url: `http://127.0.0.1:${server.address().port}/?scenario=${scenario}` });
    let ready = false;
    for (let i = 0; i < 70; i++) {
      await wait(350);
      const rendered = await evaluate("document.querySelector('flutter-view') !== null");
      if (rendered) { await wait(1800); ready = true; break; }
    }
    assert(ready, 'Flutter must mount');
  }
  await open(844, 390); await capture('normal_844x390');
  const firstX = 844 * .535 - 1.5 * (Math.min(132, 390 * .315) * .70 + 10);
  await tap(firstX, 305); await wait(250); await capture('selection_844x390');
  await tap(784, 26); await wait(200); await capture('scenario_menu');
  await open(844, 390, 'pisti'); await capture('pisti_fixture');
  await tap(firstX, 305); await wait(240); await tap(firstX, 290);
  await wait(650); await capture('pisti_moment'); await wait(1800); await capture('after_pisti');
  await open(844, 390, 'finish');
  await tap(844 * .535, 305); await wait(220); await tap(844 * .535, 290);
  await wait(3400); await capture('result_844x390');
  await open(568, 280, 'pisti'); await capture('small_568x280');
  await open(1024, 600); await capture('tablet_1024x600');
  assert.equal(errors.length, 0, JSON.stringify(errors));
  console.log('PASS: real Chrome/Flutter captures and interactions; no runtime errors.');
} finally {
  if (ws?.readyState === WebSocket.OPEN && send) { try { await send('Browser.close'); } catch {} }
  ws?.close(); if (browser.exitCode === null) browser.kill();
  await new Promise((ok) => server.close(ok));
}
