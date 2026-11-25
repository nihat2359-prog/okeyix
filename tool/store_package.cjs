const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),zlib=require('node:zlib');
const root=path.resolve('artifacts');
const crcTable=Array.from({length:256},(_,n)=>{for(let k=0;k<8;k++)n=n&1?0xedb88320^(n>>>1):n>>>1;return n>>>0;});
function chunk(type,data){const t=Buffer.from(type);const out=Buffer.alloc(data.length+12);out.writeUInt32BE(data.length);t.copy(out,4);data.copy(out,8);let crc=0xffffffff;for(const v of Buffer.concat([t,data]))crc=crcTable[(crc^v)&255]^(crc>>>8);out.writeUInt32BE((crc^0xffffffff)>>>0,out.length-4);return out;}
// PNG filters operate on each channel independently. Removing the opaque alpha
// channel from filtered RGBA scanlines preserves the RGB pixels exactly.
function opaqueRgb(b){
 if(b[25]===2)return b;
 if(b[24]!==8||b[25]!==6||b[28]!==0)throw Error('Unsupported PNG encoding');
 const w=b.readUInt32BE(16),h=b.readUInt32BE(20),idats=[];
 for(let p=8;p<b.length;){const n=b.readUInt32BE(p),t=b.toString('ascii',p+4,p+8);if(t==='IDAT')idats.push(b.subarray(p+8,p+8+n));p+=n+12;}
 const raw=zlib.inflateSync(Buffer.concat(idats)),rgb=Buffer.alloc((w*3+1)*h);
 for(let y=0;y<h;y++){
  const p=y*(w*4+1),q=y*(w*3+1),filter=raw[p];rgb[q]=filter;
  for(let x=0;x<w;x++){
   const a=x?255:0,up=y?255:0,ul=x&&y?255:0;let predictor=0;
   if(filter===1)predictor=a;else if(filter===2)predictor=up;else if(filter===3)predictor=Math.floor((a+up)/2);else if(filter===4){const v=a+up-ul,pa=Math.abs(v-a),pb=Math.abs(v-up),pc=Math.abs(v-ul);predictor=pa<=pb&&pa<=pc?a:pb<=pc?up:ul;}else if(filter!==0)throw Error('Invalid PNG filter');
   if(((raw[p+1+x*4+3]+predictor)&255)!==255)throw Error('Transparent pixel in final artwork');
   raw.copy(rgb,q+1+x*3,p+1+x*4,p+1+x*4+3);
  }
 }
 const header=Buffer.from(b.subarray(16,29));header[9]=2;
 return Buffer.concat([b.subarray(0,8),chunk('IHDR',header),chunk('IDAT',zlib.deflateSync(rgb)),chunk('IEND',Buffer.alloc(0))]);
}
(async()=>{
 const manifest=JSON.parse(fs.readFileSync(path.join(root,'manifest.json')));
 for(const f of manifest.files){const dest=path.join(root,f.path),b=opaqueRgb(fs.readFileSync(dest));fs.writeFileSync(dest,b);f.sha256=crypto.createHash('sha256').update(b).digest('hex');}
 fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify(manifest,null,2));
 const errors=[];
 for(const f of manifest.files){
  const b=fs.readFileSync(path.join(root,f.path));
  if(b.readUInt32BE(16)!==f.width||b.readUInt32BE(20)!==f.height)errors.push(f.path+': dimensions');
  if(b[25]!==2)errors.push(f.path+': not RGB opaque PNG');
  if(f.width<=f.height)errors.push(f.path+': not landscape');
  if(f.path.startsWith('google_play/') && b.length>8*1024*1024)errors.push(f.path+': over 8 MiB');
  if(crypto.createHash('sha256').update(b).digest('hex')!==f.sha256)errors.push(f.path+': hash');
  const idats=[];for(let p=8;p<b.length;){const n=b.readUInt32BE(p),type=b.toString('ascii',p+4,p+8);if(type==='IDAT')idats.push(b.subarray(p+8,p+8+n));p+=n+12;}
  try{const decoded=zlib.inflateSync(Buffer.concat(idats));if(decoded.length!==(f.width*3+1)*f.height)errors.push(f.path+': pixel data length');}catch{errors.push(f.path+': PNG decode');}
 }
 for(const store of ['app_store','google_play'])for(const lang of ['tr','en']){
  for(const device of store==='app_store'?['iphone','ipad']:['phone','tablet-7','tablet-10']){
   const n=manifest.files.filter(f=>f.path.startsWith(`${store}/${lang}/${device}/`)).length;
   if(n!==6)errors.push(`${store}/${lang}/${device}: expected 6, got ${n}`);
  }
 }
 if(manifest.files.length!==62)errors.push('Expected 62 exports');
 fs.writeFileSync(path.join(root,'validation.json'),JSON.stringify({passed:errors.length===0,exportCount:manifest.files.length,checks:['PNG decode','exact dimensions','opaque RGB','landscape','SHA256','six per device and locale'],errors},null,2));
 if(errors.length)throw Error(errors.join('\n'));
 const tabs=await(await fetch('http://127.0.0.1:56681/json')).json();const ws=new WebSocket(tabs.find(t=>t.url==='about:blank').webSocketDebuggerUrl);await new Promise(r=>ws.onopen=r);
 let id=0;const pending=new Map();ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id){pending.get(m.id)(m.result);pending.delete(m.id);}};
 const ev=async expression=>{const r=await new Promise(resolve=>{pending.set(++id,resolve);ws.send(JSON.stringify({id,method:'Runtime.evaluate',params:{expression,awaitPromise:true,returnByValue:true}}));});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
 try{
  for(const lang of ['tr','en']){
   const files=manifest.files.filter(f=>f.path.startsWith(`google_play/${lang}/phone/`));
   const images=files.map(f=>'data:image/png;base64,'+fs.readFileSync(path.join(root,f.path)).toString('base64'));
   const data=await ev(`(async()=>{const c=document.querySelector('canvas');c.width=1800;c.height=1770;const x=c.getContext('2d',{alpha:false});x.fillStyle='#071612';x.fillRect(0,0,c.width,c.height);x.fillStyle='#f2ce82';x.font='700 46px Store';x.fillText('OKEYIX / ${lang.toUpperCase()} STORE COLLECTION',60,80);const arr=${JSON.stringify(images)};for(let i=0;i<arr.length;i++){const im=new Image();im.src=arr[i];await im.decode();const xx=60+(i%2)*860,yy=130+Math.floor(i/2)*530;x.drawImage(im,xx,yy,820,461.25);x.fillStyle='#c8d4c8';x.font='600 20px Store';x.fillText(String(i+1).padStart(2,'0')+' / 06',xx,yy+494);}return c.toDataURL('image/png')})()`);
   fs.writeFileSync(path.join(root,lang==='tr'?'preview.png':'preview-en.png'),Buffer.from(data.split(',')[1],'base64'));
  }
 }finally{ws.close();}
 fs.appendFileSync(path.join(root,'UPLOAD-GUIDE.txt'),'\nThe opening table detail is a promotional fixture rendered with the real Stage, TileComponent, RackSlotGenerator and table artwork. It is not a live multiplayer session screenshot.\nFinalize RGB conversion, validation and contact sheets: node tool/store_package.cjs\nCreate ZIPs: powershell -ExecutionPolicy Bypass -File tool/store_zip.ps1\n');
 console.log('Validated 62 exports; created Turkish and English contact sheets.');
})().catch(e=>{console.error(e);process.exitCode=1;});
