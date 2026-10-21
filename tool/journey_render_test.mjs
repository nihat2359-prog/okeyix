// No npm dependencies. Local Chrome WebGL smoke test; never contacts Supabase.
import {spawn} from 'node:child_process';
import {mkdir, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const out = resolve('.dart_tool/journey');
await mkdir(out, {recursive: true});
const browser = spawn(process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe', [
  '--headless=new', '--no-sandbox', '--disable-gpu-sandbox', '--enable-unsafe-swiftshader',
  '--use-angle=swiftshader', '--no-first-run', '--no-default-browser-check', '--disable-background-networking',
  '--remote-debugging-port=0', `--user-data-dir=${out}/chrome`, 'about:blank',
], {stdio: ['ignore', 'ignore', 'pipe']});
let ws;
try {
  const endpoint = await new Promise((ok, fail) => {
    const timeout = setTimeout(() => fail(Error('Chrome startup timed out')), 15000);
    browser.stderr.on('data', data => {
      const match = String(data).match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (match) { clearTimeout(timeout); ok(match[1]); }
    });
    browser.once('error', fail);
  });
  ws = new WebSocket(endpoint);
  await new Promise(ok => ws.addEventListener('open', ok, {once: true}));
  let serial = 0;
  const waiting = new Map(), errors = [];
  ws.addEventListener('message', ({data}) => {
    const message = JSON.parse(data);
    if (message.id) {
      const pending = waiting.get(message.id); waiting.delete(message.id);
      if (message.error) pending?.reject(Error(JSON.stringify(message.error))); else pending?.resolve(message.result);
    }
    if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails);
  });
  const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    const id = ++serial; waiting.set(id, {resolve, reject}); ws.send(JSON.stringify({id, method, params, sessionId}));
  });
  const {targetId} = await send('Target.createTarget', {url: 'about:blank'});
  const {sessionId} = await send('Target.attachToTarget', {targetId, flatten: true});
  const call = (method, params) => send(method, params, sessionId);
  const evaluate = async expression => {
    const value = await call('Runtime.evaluate', {expression, returnByValue: true, awaitPromise: true});
    if (value.exceptionDetails) throw Error(JSON.stringify(value.exceptionDetails));
    return value.result.value;
  };
  await call('Runtime.enable'); await call('Page.enable');
  await call('Page.addScriptToEvaluateOnNewDocument', {source: 'window.journeyMessages=[];window.Journey={postMessage:m=>window.journeyMessages.push(m)};'});
  await call('Emulation.setDeviceMetricsOverride', {width: 1000, height: 560, deviceScaleFactor: 1, mobile: false});
  await call('Page.navigate', {url: pathToFileURL(resolve('assets/journey/index.html')).href});
  for (let i = 0; i < 100; i++) {
    if (await evaluate('!!window.journeyDiagnostics')) break;
    await new Promise(ok => setTimeout(ok, 100));
  }
  await new Promise(ok => setTimeout(ok, 2500));
  for (const [width, height] of [[1000, 560], [480, 270], [844, 390]]) {
    await call('Emulation.setDeviceMetricsOverride', {width, height, deviceScaleFactor: 1, mobile: false});
    await evaluate('window.dispatchEvent(new Event("resize"))');
    await new Promise(ok => setTimeout(ok, 300));
    const d = await evaluate('window.journeyDiagnostics()');
    assert(d.triangles > 10000 && d.calls > 0, 'Real geometry must render');
    assert(d.width === width && d.height === height, `Canvas must resize: ${JSON.stringify(d)}`);
    const {data} = await call('Page.captureScreenshot', {format: 'png'});
    await writeFile(`${out}/scene_${width}x${height}.png`, Buffer.from(data, 'base64'));
    console.log(`${width}x${height}: ${d.triangles} triangles / ${d.calls} draw calls`);
  }
  const before = await evaluate('window.journeyDiagnostics().yaw');
  await call('Input.dispatchMouseEvent', {type: 'mousePressed', x: 400, y: 200, button: 'left', clickCount: 1});
  await call('Input.dispatchMouseEvent', {type: 'mouseMoved', x: 490, y: 220, button: 'left', buttons: 1});
  await call('Input.dispatchMouseEvent', {type: 'mouseReleased', x: 490, y: 220, button: 'left', clickCount: 1});
  await new Promise(ok => setTimeout(ok, 300));
  assert.notEqual(await evaluate('window.journeyDiagnostics().yaw'), before, 'Drag must orbit camera');
  await evaluate('window.journey.pause(true)');
  assert(await evaluate('window.journeyDiagnostics().paused'));
  await evaluate('window.journey.pause(false);window.journey.reset()');
  assert(!(await evaluate('window.journeyDiagnostics().paused')));
  await new Promise(ok => setTimeout(ok, 1300));
  const hit = await evaluate('window.journeyDiagnostics().champion');
  await call('Input.dispatchMouseEvent', {type: 'mousePressed', ...hit, button: 'left', clickCount: 1});
  await call('Input.dispatchMouseEvent', {type: 'mouseReleased', ...hit, button: 'left', clickCount: 1});
  assert(await evaluate('window.journeyMessages.includes("champion")'), '3D character tap must open native panel');
  assert(await evaluate('window.journeyDiagnostics().focused'), 'Tap must focus camera');
  const {data: focusImage} = await call('Page.captureScreenshot', {format: 'png'});
  await writeFile(`${out}/character_focus.png`, Buffer.from(focusImage, 'base64'));
  await evaluate('window.journey.dispose()');
  assert(await evaluate('window.journeyDiagnostics().destroyed'));
  assert.equal(errors.length, 0, JSON.stringify(errors));
  console.log('PASS: WebGL rendering, resize, orbit, character ray picking/bridge, focus, pause/resume, disposal; no JS exceptions.');
} finally {
  ws?.close(); browser.kill();
}
