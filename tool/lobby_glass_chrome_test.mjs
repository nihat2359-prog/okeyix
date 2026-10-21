// Real Chrome + compiled Flutter Web. Tests production surfaces, not a JS imitation.
import {createServer} from 'node:http';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve,extname,sep} from 'node:path';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
const root=resolve('.dart_tool/lobby_glass_web'),out=resolve('.dart_tool/lobby_glass_chrome');
await mkdir(out,{recursive:true});
const server=createServer(async(req,res)=>{
  try{const path=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname).replace(/\/$/,'/index.html'));
    if(!path.startsWith(root+sep)){res.writeHead(403).end();return;}
    const mime={'.js':'text/javascript','.wasm':'application/wasm','.json':'application/json','.html':'text/html','.png':'image/png','.css':'text/css'};
    res.setHeader('Content-Type',mime[extname(path)]||'application/octet-stream');res.end(await readFile(path));
  }catch{res.writeHead(404).end();}
});
await new Promise(ok=>server.listen(0,'127.0.0.1',ok));
const browser=spawn(process.env.CHROME||'C:/Program Files/Google/Chrome/Application/chrome.exe',[
  '--headless=new','--no-sandbox','--disable-gpu-sandbox','--enable-unsafe-swiftshader',
  '--use-angle=swiftshader','--no-first-run','--disable-background-networking',
  '--remote-debugging-port=0',`--user-data-dir=${out}/profile`,'about:blank'],{stdio:['ignore','ignore','pipe']});
let ws,send;
try{
  const endpoint=await new Promise((ok,fail)=>{const timer=setTimeout(()=>fail(Error('Chrome startup timeout')),15000);
    browser.stderr.on('data',d=>{const m=String(d).match(/DevTools listening on (ws:\/\/[^\s]+)/);if(m){clearTimeout(timer);ok(m[1]);}});browser.once('error',fail);});
  ws=new WebSocket(endpoint);await new Promise(ok=>ws.addEventListener('open',ok,{once:true}));
  let serial=0;const pending=new Map(),errors=[];
  ws.addEventListener('message',({data})=>{const m=JSON.parse(data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p?.reject(Error(JSON.stringify(m.error))):p?.resolve(m.result);}
    if(m.method==='Runtime.exceptionThrown')errors.push(m.params.exceptionDetails);});
  send=(method,params={},sessionId)=>new Promise((resolve,reject)=>{const id=++serial,t=setTimeout(()=>reject(Error(method+' timed out')),45000);
    pending.set(id,{resolve:v=>{clearTimeout(t);resolve(v);},reject:e=>{clearTimeout(t);reject(e);}});ws.send(JSON.stringify({id,method,params,sessionId}));});
  const {targetId}=await send('Target.createTarget',{url:'about:blank'}),{sessionId}=await send('Target.attachToTarget',{targetId,flatten:true});
  const call=(m,p)=>send(m,p,sessionId);
  async function evaluate(expression){const r=await call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;}
  await call('Runtime.enable');await call('Page.enable');await call('Emulation.setDeviceMetricsOverride',{width:932,height:600,deviceScaleFactor:1,mobile:false});
  await call('Page.navigate',{url:`http://127.0.0.1:${server.address().port}/`});
  async function pixels(points,name){const{data}=await call('Page.captureScreenshot',{format:'png'});if(name)await writeFile(`${out}/${name}.png`,Buffer.from(data,'base64'));
    return evaluate(`(async()=>{const img=new Image();img.src='data:image/png;base64,${data}';await img.decode();const c=document.createElement('canvas');c.width=img.width;c.height=img.height;const g=c.getContext('2d');g.drawImage(img,0,0);return ${JSON.stringify(points)}.map(([x,y])=>Array.from(g.getImageData(x,y,1,1).data));})()`);}
  let ready=false;
  for(let i=0;i<90;i++){await new Promise(ok=>setTimeout(ok,500));const [p]=await pixels([[40,350]]);if(p[0]>200&&p[2]<30){ready=true;break;}if(errors.length)throw Error(JSON.stringify(errors));}
  assert(ready,'Flutter Web fixture must render its background');
  const samples=await pixels([[100,140],[830,140],[100,560],[830,560]],'nested_and_dock');
  function visible(p,channel,label){assert(p[channel]-p[channel===0?2:0]>50,`${label} hides backdrop: ${p}`);}
  visible(samples[0],0,'Nested panel left');visible(samples[1],2,'Nested panel right');
  visible(samples[2],0,'Bottom dock left');visible(samples[3],2,'Bottom dock right');
  for(const type of ['mousePressed','mouseReleased'])await call('Input.dispatchMouseEvent',{type,x:100,y:250,button:'left',clickCount:1});
  await new Promise(ok=>setTimeout(ok,1500));
  const dialog=await pixels([[80,350],[850,350]],'create_dialog');
  visible(dialog[0],0,'Create dialog left');visible(dialog[1],2,'Create dialog right');
  assert.equal(errors.length,0,JSON.stringify(errors));
  console.log(JSON.stringify({nested:samples.slice(0,2),dock:samples.slice(2),dialog}));
  console.log('PASS: Chrome/CanvasKit nested panels, bottom dock and real showDialog preserve the backdrop.');
}finally{
  if(ws?.readyState===WebSocket.OPEN&&send){try{await send('Browser.close');}catch{}}ws?.close();
  if(browser.exitCode===null)browser.kill();await new Promise(ok=>server.close(ok));
}
