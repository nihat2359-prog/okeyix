// No npm dependencies. Local Chrome WebGL smoke test; never contacts Supabase.
import {spawn} from 'node:child_process';
import {mkdir, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import assert from 'node:assert/strict';
const out = resolve('.dart_tool/journey');
const mapOnly = process.argv.includes('--map-only');
const maiden = process.argv.includes('--maiden');
const world = process.argv.includes('--world') || mapOnly;
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
    if (message.method === 'Runtime.consoleAPICalled' && message.params.type === 'error') errors.push(message.params.args.map(a=>a.value||a.description).join(' '));
  });
  const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
    const id = ++serial,timer=setTimeout(()=>{waiting.delete(id);reject(Error(`CDP timeout: ${method}`));},60000);
    waiting.set(id, {resolve:value=>{clearTimeout(timer);resolve(value);}, reject:error=>{clearTimeout(timer);reject(error);}}); ws.send(JSON.stringify({id, method, params, sessionId}));
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
  await call('Page.navigate', {url: pathToFileURL(resolve(`assets/journey/${maiden ? 'maiden' : world ? 'index' : 'demo'}.html`)).href});
  for (let i = 0; i < 100; i++) {
    if (await evaluate('!!window.journeyDiagnostics')) break;
    await new Promise(ok => setTimeout(ok, 100));
  }
  await new Promise(ok => setTimeout(ok, 2500));
  if (maiden) {
    for(let i=0;i<300;i++) {
      if(await evaluate('window.journeyDiagnostics?.().loaded'))break;
      if(errors.length)throw Error(JSON.stringify(errors));
      await new Promise(ok=>setTimeout(ok,100));
    }
    assert(await evaluate('window.journeyDiagnostics().loaded'),'Textured architecture must load');
    await new Promise(ok=>setTimeout(ok,1500));
    const d=await evaluate('window.journeyDiagnostics()');console.log(d);
    assert(d.triangles>260000);assert(d.calls<100,'Static architecture must be batched');
    for(const [width,height]of [[1000,560],[480,270],[844,390]]){
      await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
      await evaluate('window.dispatchEvent(new Event("resize"))');await new Promise(ok=>setTimeout(ok,400));
      const {data}=await call('Page.captureScreenshot',{format:'png'});await writeFile(`${out}/premium_maiden_${width}x${height}.png`,Buffer.from(data,'base64'));
      assert(await evaluate('document.documentElement.scrollWidth===innerWidth&&document.documentElement.scrollHeight===innerHeight'));
    }
    await call('Input.dispatchMouseEvent',{type:'mouseWheel',x:250,y:150,deltaX:0,deltaY:-100000});
    await new Promise(ok=>setTimeout(ok,800));
    assert.equal(await evaluate('window.journeyDiagnostics().wantedRadius'),48);
    await call('Input.dispatchMouseEvent',{type:'mousePressed',x:300,y:150,button:'left',clickCount:1});
    await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:500,y:-200,button:'left',buttons:1});
    await call('Input.dispatchMouseEvent',{type:'mouseReleased',x:500,y:10,button:'left',clickCount:1});
    assert(await evaluate('window.journeyDiagnostics().wantedPitch>=.08'));
    await evaluate('window.journey.pause(true)');const before=await evaluate('window.journeyDiagnostics().elapsed');
    await new Promise(ok=>setTimeout(ok,200));assert.equal(await evaluate('window.journeyDiagnostics().elapsed'),before);
    await evaluate('window.journey.pause(false);window.journey.reset();window.journey.back()');
    assert(await evaluate('window.journeyMessages.includes("exit")'));
    await evaluate('window.journey.dispose()');assert(await evaluate('window.journeyDiagnostics().disposed'));
    assert.equal(errors.length,0,JSON.stringify(errors));console.log('PASS: premium model, batching, landscape sizes, camera bounds, pause, exit and disposal.');
  } else if (world) {
    const wait = async predicate => {
      for (let i=0;i<240;i++) {
        if(await evaluate(predicate))return;
        if(errors.length)throw Error(JSON.stringify(errors));
        await new Promise(ok=>setTimeout(ok,100));
      }
      throw Error('Scene timed out: '+predicate+' '+JSON.stringify(await evaluate('window.journeyDiagnostics()')));
    };
    const click = async id => {
      const label=await evaluate(`window.journeyDiagnostics().labels.find(l=>l.id===${JSON.stringify(id)})`);
      assert(label, `Visible touch label required: ${id}`);
      for(const type of ['mousePressed','mouseReleased'])await call('Input.dispatchMouseEvent',{type,x:label.x,y:label.y,button:'left',clickCount:1});
    };
    const capture=async name=>{const {data}=await call('Page.captureScreenshot',{format:'png'});await writeFile(`${out}/${name}.png`,Buffer.from(data,'base64'));};
    assert.equal(await evaluate('window.journeyDiagnostics().cityCount'),81);
    await capture('turkey_1000x560');
    if(mapOnly){await evaluate('window.journey.dispose()');assert.equal(errors.length,0,JSON.stringify(errors));console.log('PASS: country terrain and neutral neighbouring land WebGL render.');}else{
    await click('TUR034');
    await wait('window.journeyDiagnostics().level==="city"&&!window.journeyDiagnostics().transitioning');
    await new Promise(ok=>setTimeout(ok,600));
    const overview=await evaluate('window.journeyDiagnostics()');
    console.log(`Istanbul overview: ${overview.triangles} triangles / ${overview.calls} draws, ${overview.geometries} geometries`);
    assert.equal(overview.labels.filter(l=>l.kind==='place').length,6,'All six places must be visible');
    assert(overview.triangles>20000);
    await capture('istanbul_1000x560');
    for(const [width,height] of [[480,270],[844,390]]){
      await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
      await evaluate('window.dispatchEvent(new Event("resize"))');
      await new Promise(ok=>setTimeout(ok,1600));
      const d=await evaluate('window.journeyDiagnostics()');
      assert.equal(d.labels.filter(l=>l.kind==='place').length,6,`Six place labels at ${width}x${height}: ${JSON.stringify(d.labels)}`);
      await capture(`istanbul_${width}x${height}`);
    }
    await click('kiz');
    await wait('window.journeyDiagnostics().level==="place"&&!window.journeyDiagnostics().transitioning');
    assert(await evaluate('window.journeyDiagnostics().detail'),'Close detail tier must be created');
    await capture('maiden_close_1000x560');
    for(const [width,height] of [[480,270],[844,390]]){
      await call('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:false});
      await evaluate('window.dispatchEvent(new Event("resize"))');await new Promise(ok=>setTimeout(ok,250));
      await capture(`maiden_close_${width}x${height}`);
    }
    const before=await evaluate('window.journeyDiagnostics().yaw');
    await call('Input.dispatchMouseEvent',{type:'mousePressed',x:300,y:170,button:'left',clickCount:1});
    await call('Input.dispatchMouseEvent',{type:'mouseMoved',x:370,y:190,button:'left',buttons:1});
    await call('Input.dispatchMouseEvent',{type:'mouseReleased',x:370,y:190,button:'left',clickCount:1});
    await new Promise(ok=>setTimeout(ok,300));
    assert.notEqual(await evaluate('window.journeyDiagnostics().yaw'),before);
    await evaluate('window.journey.back()');
    await wait('window.journeyDiagnostics().level==="city"&&!window.journeyDiagnostics().transitioning');
    for(const id of ['galata','ortakoy','loti','haydarpasa','hisar']){
      await click(id);await wait('window.journeyDiagnostics().level==="place"&&!window.journeyDiagnostics().transitioning');
      assert.equal(await evaluate('window.journeyDiagnostics().place'),id);
      await capture(`place_${id}`);
      await evaluate('window.journey.back()');await wait('window.journeyDiagnostics().level==="city"&&!window.journeyDiagnostics().transitioning');
    }
    const cityMemory=await evaluate('window.journeyDiagnostics().geometries');
    await evaluate('window.journey.back()');
    await wait('window.journeyDiagnostics().level==="turkey"&&!window.journeyDiagnostics().transitioning');
    const mapMemory=await evaluate('window.journeyDiagnostics().geometries');
    assert(mapMemory<cityMemory,'City GPU geometry must be released');
    await evaluate('window.journey.back()');
    assert(await evaluate('window.journeyMessages.includes("exit")'));
    await evaluate('window.journey.pause(true)');assert(await evaluate('window.journeyDiagnostics().paused'));
    await evaluate('window.journey.pause(false);window.journey.dispose()');
    assert(await evaluate('window.journeyDiagnostics().destroyed'));
    assert.equal(errors.length,0,JSON.stringify(errors));
    console.log(`PASS: Turkey → Istanbul → Maiden close → Istanbul → Turkey → exit; 81 provinces, detail tier, drag, resize, pause, GPU cleanup (${cityMemory} → ${mapMemory} geometries).`);
    }
  } else {
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
  }
} finally {
  if(ws?.readyState===WebSocket.OPEN){ws.send(JSON.stringify({id:999999,method:'Browser.close'}));await new Promise(ok=>setTimeout(ok,250));}
  ws?.close(); browser.kill();
}
