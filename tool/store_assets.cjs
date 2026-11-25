// Deterministic store artwork from real Flutter UI captures and project assets.
// Run captures: flutter test tool/store_capture_test.dart --no-pub
// Run export: node tool/store_assets.cjs (Chrome CDP port 56681).
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve('artifacts');
const b64 = p => fs.readFileSync(p).toString('base64');
const names = ['01-take-your-seat','02-rise-through-leagues','03-your-table-your-rules','04-friends-at-the-table','05-daily-rewards','06-play-in-your-style'];
const copy = {
  tr: [
    ['MASA SENİ BEKLİYOR', 'Bir el daha.', 'Bir heyecan daha.', 'Okey keyfi, İstanbul gecelerinin atmosferiyle.', 'Masaya katıl. Oyuna başla.'],
    ['BEŞ LİG · TEK HEDEF', 'İlk elden', 'şampiyonluğa.', 'Acemilerden Şampiyonlara uzanan rekabete katıl.', 'Ligini seç. Yerini al.'],
    ['OYUNUN RİTMİ SENDE', 'Senin masan.', 'Senin kuralların.', 'Giriş miktarını, süreyi ve sohbeti sen seç.', 'Masanı kur. Rekabeti başlat.'],
    ['OYUNUN SOSYAL TARAFI', 'Sohbet koyu.', 'Rekabet tatlı.', 'Arkadaşlarını bul, mesajlaş, oyunlarını izle.', 'Okey keyfi birlikte güzel.'],
    ['HER GÜN YENİ BİR NEDEN', 'Bugünün', 'hediyesi hazır.', 'Günlük coin bonusunu al, masaya geri dön.', 'Serini sürdür. Ödülleri topla.'],
    ['ALTI FARKLI TAŞ TEMASI', 'Taşlar aynı.', 'Tarzın başka.', 'Klasik porselenden gece mavisine, rengini seç.', 'Oyununa kendi imzanı at.'],
  ],
  en: [
    ['YOUR SEAT IS WAITING', 'One more round.', 'One more thrill.', 'Classic Okey with the atmosphere of Istanbul nights.', 'Take a seat. Let’s play.'],
    ['FIVE LEAGUES · ONE GOAL', 'From first hand', 'to champion.', 'Find your league and make every round count.', 'Choose your league. Join the table.'],
    ['SET YOUR OWN PACE', 'Your table.', 'Your rules.', 'Choose the entry, turn timer and chat settings.', 'Create your table. Start the rivalry.'],
    ['BETTER TOGETHER', 'Good company.', 'Great rivalry.', 'Find friends, send messages and watch their games.', 'Share the joy of Okey.'],
    ['A REASON TO RETURN', 'A new day.', 'A new reward.', 'Claim your daily coin bonus and return to the table.', 'Keep your streak. Collect your rewards.'],
    ['SIX TILE THEMES', 'Classic game.', 'Your signature.', 'From porcelain to midnight blue. Find your color.', 'Make every hand your own.'],
  ],
};

async function compose(s) {
  const c = document.querySelector('canvas'); c.width = s.w; c.height = s.h;
  const x = c.getContext('2d', {alpha:false});
  const W = 2160, H = s.h / s.w * W; x.scale(s.w/W,s.w/W);
  const compact = s.w/s.h < 1.7, i = s.i, t = s.text;
  const load = async data => {const im=new Image();im.src='data:image/png;base64,'+data;await im.decode();return im;};
  const [bg,logo,shot,object] = await Promise.all([s.bg,s.logo,s.source,s.object].map(load));
  const cover = (im,xx,yy,ww,hh) => { const z=Math.max(ww/im.width,hh/im.height);x.drawImage(im,xx+(ww-im.width*z)/2,yy+(hh-im.height*z)/2,im.width*z,im.height*z); };
  x.fillStyle='#041512';x.fillRect(0,0,W,H);
  x.save();x.globalAlpha=.52;cover(bg,0,0,W,H);x.restore();
  let g=x.createLinearGradient(0,0,W,H);g.addColorStop(0,'#041a17fa');g.addColorStop(.42,'#051a17d9');g.addColorStop(1,'#06111640');x.fillStyle=g;x.fillRect(0,0,W,H);
  const gl=x.createRadialGradient(W*.72,H*.56,20,W*.72,H*.56,W*.65);gl.addColorStop(0,'#cfa24c30');gl.addColorStop(.5,'#137a5520');gl.addColorStop(1,'#09151100');x.fillStyle=gl;x.fillRect(0,0,W,H);
  // Quiet architectural curves and warm particles continue the lounge atmosphere.
  x.strokeStyle='#cfa55c22';x.lineWidth=2;
  for(let k=0;k<3;k++){x.beginPath();x.ellipse(W*.92,H*.84,W*(.5+k*.06),H*(.72+k*.1),-.24,0,Math.PI*2);x.stroke();}
  for(let k=0;k<45;k++){const xx=(Math.sin(k*37.1)*.5+.5)*W,yy=(Math.sin(k*21.4)*.5+.5)*H;x.fillStyle=k%3?'#e3ba6833':'#fff0c688';x.beginPath();x.arc(xx,yy,k%4===0?2:1,0,7);x.fill();}
  const left=106, top=compact?64:56;
  x.save();x.shadowColor='#f9b94730';x.shadowBlur=24;x.drawImage(logo,left,top,370,370*logo.height/logo.width);x.restore();
  x.fillStyle='#c7b890';x.font='600 19px Store';x.textAlign='right';x.fillText(s.lang==='tr'?'OKEY KEYFİ. HER ELDE.':'THE JOY OF EVERY HAND.',W-106,top+43);x.textAlign='left';
  const yy=compact?235:245;
  x.fillStyle='#e5be70';x.font='700 24px Store';x.letterSpacing='3px';x.fillText(t[0],left,yy);x.letterSpacing='0px';
  const maxText=compact?1900:790;
  let font=compact?104:97;
  while(font>60){x.font=`700 ${font}px Store`;if(Math.max(x.measureText(t[1]).width,x.measureText(t[2]).width)<=maxText)break;font-=2;}
  const headline=yy+48;
  x.textBaseline='top';x.fillStyle='#fff5df';x.fillText(t[1],left,headline);const gold=x.createLinearGradient(0,headline+font,0,headline+font*2.4);gold.addColorStop(0,'#fff1b0');gold.addColorStop(.55,'#eac06a');gold.addColorStop(1,'#b88631');x.fillStyle=gold;x.fillText(t[2],left,headline+font*1.13);
  const sub=compact?headline+font*2.5:headline+font*2.65;
  x.fillStyle='#c6d3c9';x.font=`400 ${compact?30:28}px Store`;
  const words=t[3].split(' ');let line='',lines=[];
  for(const w of words){if(x.measureText(line+w).width>maxText-30){lines.push(line.trim());line='';}line+=w+' ';}lines.push(line.trim());
  lines.forEach((l,j)=>x.fillText(l,left,sub+j*43));
  x.textBaseline='alphabetic';
  // The image stays uncropped and in landscape; tablet exports get a larger lower scene.
  let box;
  if(compact) box={x:106,y:sub+lines.length*43+74,w:1948,h:0};
  else box={x:925,y:H*.31,w:1135,h:0};
  let sw=shot.width,sh=shot.height,sx=0,sy=0;
  if(i===2){sx=177;sw=2487;sh=1227;}
  if(i===1){sx=70;sy=185;sw=1210;sh=800; box=compact?{x:775,y:sub+lines.length*43+75,w:1230,h:0}:{x:1230,y:235,w:810,h:0};}
  box.h=box.w*sh/sw;
  const available=H-110-box.y;
  if(box.h>available){const ratio=available/box.h;box.w*=ratio;box.h=available;box.x=compact?(W-box.w)/2:W-106-box.w;}
  x.save();x.shadowColor='#000b';x.shadowBlur=65;x.shadowOffsetY=30;
  const rim=x.createLinearGradient(box.x,box.y,box.x,box.y+box.h);rim.addColorStop(0,'#f3d994');rim.addColorStop(.35,'#a67b3c');rim.addColorStop(1,'#2a352d');
  x.fillStyle=rim;x.beginPath();x.roundRect(box.x-8,box.y-8,box.w+16,box.h+16,28);x.fill();x.restore();
  x.save();x.beginPath();x.roundRect(box.x,box.y,box.w,box.h,21);x.clip();x.drawImage(shot,sx,sy,sw,sh,box.x,box.y,box.w,box.h);x.restore();
  // Existing 3D game objects, never generated replicas of the interface.
  if(i===1){const ow=compact?560:265,ox=compact?145:935,oy=compact?box.y+box.h*.12:box.y+box.h*.27;x.save();x.shadowColor='#56dca655';x.shadowBlur=48;x.drawImage(object,ox,oy,ow,ow*object.height/object.width);x.restore();}
  else if(!compact && i>0){const ow=i===4?270:200,ox=left+(i===4?465:495),oy=Math.max(sub+lines.length*43+8,H-330);x.save();x.globalAlpha=.95;x.shadowColor='#e6bd6a33';x.shadowBlur=35;x.drawImage(object,ox,oy,ow,ow*object.height/object.width);x.restore();}
  // Bottom line acts as an editorial sign-off, not a fake in-game button.
  x.strokeStyle='#b38c4e66';x.lineWidth=1;x.beginPath();x.moveTo(left,H-84);x.lineTo(W-106,H-84);x.stroke();
  x.fillStyle='#e9ce8f';x.font='600 23px Store';x.fillText(t[4],left,H-42);
  x.textAlign='right';x.font='400 21px Store';x.fillStyle='#bdc6b7';x.fillText(`${String(i+1).padStart(2,'0')} / 06`,W-106,H-42);x.textAlign='left';
  return c.toDataURL('image/png');
}

(async()=>{
  const tabs=await (await fetch('http://127.0.0.1:56681/json')).json();
  const tab=tabs.find(t=>t.type==='page'&&t.url==='about:blank');
  if(!tab)throw Error('Start headless Chrome with --remote-debugging-port=56681 on about:blank.');
  const ws=new WebSocket(tab.webSocketDebuggerUrl);await new Promise(r=>ws.onopen=r);
  let id=0;const pending=new Map();ws.onmessage=e=>{const m=JSON.parse(e.data);if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(Error(m.error.message)):p.resolve(m.result);}};
  const call=(method,params={})=>new Promise((resolve,reject)=>{pending.set(++id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
  const ev=async expression=>{const r=await call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
  try {
    await ev(`document.body.innerHTML='<canvas></canvas>'`);
    for(const [weight,file]of [[400,'Regular'],[600,'SemiBold'],[700,'Bold']]){
      const font=b64(`assets/fonts/Montserrat-${file}.ttf`);
      await ev(`(async()=>{const f=new FontFace('Store','url(data:font/ttf;base64,${font})',{weight:'${weight}'});document.fonts.add(await f.load())})()`);
    }
    const shared={bg:b64('assets/images/lobby/lobby.png'),logo:b64('assets/images/logo/okeyix_log_1000.png')};
    const sourceNames=['game','lobby','create','friends','rewards','themes'];
    const objects=['assets/images/lobby/leagues/acemiler_kupa.png','assets/images/lobby/leagues/sampiyonlar_kupa.png','assets/images/coins/coins_small.png','assets/images/avatars/avatar1.png','assets/images/coins/coins_huge.png','assets/images/lobby/leagues/ustalar_kupa.png'];
    const formats=[['app_store','iphone',2622,1206],['app_store','ipad',2752,2064],['google_play','phone',1920,1080],['google_play','tablet-7',1920,1200],['google_play','tablet-10',2560,1600]];
    const onlyArg=process.argv.find(a=>a.startsWith('--index='));
    const only=onlyArg?Number(onlyArg.split('=')[1]):null;
    const manifest=only===null?[]:JSON.parse(fs.readFileSync(path.join(root,'manifest.json'))).files.filter(f=>!f.path.endsWith(names[only]+'.png'));
    async function write(file,data,w,h){const dest=path.join(root,file);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.writeFileSync(dest,Buffer.from(data.split(',')[1],'base64'));manifest.push({path:file,width:w,height:h,sha256:crypto.createHash('sha256').update(fs.readFileSync(dest)).digest('hex')});}
    for(const lang of ['tr','en']) for(let i=0;i<6;i++){
      if(only!==null && i!==only)continue;
      const spec={...shared,i,lang,text:copy[lang][i],source:b64(`artifacts/sources/${sourceNames[i]}.png`),object:b64(objects[i])};
      for(const [store,device,w,h]of formats){
        const data=await ev(`(${compose.toString()})(${JSON.stringify({...spec,w,h})})`);
        await write(`${store}/${lang}/${device}/${names[i]}.png`,data,w,h);
      }
      if(i===0){const w=1024,h=500;const data=await ev(`(${compose.toString()})(${JSON.stringify({...spec,w,h})})`);await write(`google_play/${lang}/feature-graphic-1024x500.png`,data,w,h);}
      console.log('Exported',lang,names[i]);
    }
    fs.writeFileSync(path.join(root,'manifest.json'),JSON.stringify({brand:'OKEYIX',languages:['tr','en'],orientation:'landscape',screenshotsPerDevice:6,source:'Real Flutter widget fixtures; English marketing copy with Turkish in-app UI',files:manifest},null,2));
    fs.writeFileSync(path.join(root,'copy.json'),JSON.stringify(copy,null,2));
    const rows=lang=>names.map((n,i)=>`<a href="google_play/${lang}/phone/${n}.png"><img loading="lazy" src="google_play/${lang}/phone/${n}.png" alt="${copy[lang][i][1]} ${copy[lang][i][2]}"><span>${copy[lang][i][1]} ${copy[lang][i][2]}</span></a>`).join('');
    fs.writeFileSync(path.join(root,'index.html'),`<!doctype html><html lang="tr"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>OKEYIX · Mağaza koleksiyonu</title><style>body{margin:0;background:#071612;color:#f7efd9;font:16px system-ui;padding:52px 5vw}h1{font-size:44px;margin:14px 0}p{color:#b8cabe;line-height:1.6}small{color:#e9bd6a;letter-spacing:3px}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:28px}a{color:#e8c47c;text-decoration:none}img{width:100%;border:1px solid #826735;border-radius:14px;display:block;margin-bottom:10px}h2{margin-top:48px}@media(max-width:700px){.grid{grid-template-columns:1fr}h1{font-size:32px}}nav{display:flex;gap:24px;flex-wrap:wrap;margin:24px 0}</style><small>OKEYIX / STORE COLLECTION</small><h1>Bir el daha. Bir heyecan daha.</h1><p>Altı hikâye · Türkçe / English · Yatay telefon ve tablet kompozisyonları.<br>Gerçek Flutter arayüzlerinden çekimler. İngilizce sette uygulama içi ekranlar Türkçedir.</p><nav><a href="OKEYIX-Google-Play-TR-EN.zip">Google Play ZIP ↓</a><a href="OKEYIX-App-Store-TR-EN.zip">App Store ZIP ↓</a><a href="UPLOAD-GUIDE.txt">Boyutlar ve kullanım notları</a></nav><h2>Türkçe</h2><div class="grid">${rows('tr')}</div><h2>English</h2><div class="grid">${rows('en')}</div></html>`);
    fs.writeFileSync(path.join(root,'UPLOAD-GUIDE.txt'),`OKEYIX STORE ASSETS — 2026-11-25\n\nAll screenshots are LANDSCAPE RGB PNG (no transparency).\nTR and EN: six promotional screenshots per device.\napp_store/tr|en/iphone: 2622x1206\napp_store/tr|en/ipad: 2752x2064\ngoogle_play/tr|en/phone: 1920x1080\ngoogle_play/tr|en/tablet-7: 1920x1200\ngoogle_play/tr|en/tablet-10: 2560x1600\ngoogle_play/tr|en/feature-graphic-1024x500.png\n\nEnglish artwork has English headlines and Turkish in-app UI. The app is not represented as fully English-localized.\nSources are offline Flutter widget fixtures with sample player names, balances and table data. No real accounts or chats used. Lobby capture is a component fixture, not a complete production-session capture. League detail uses a crop preserving the 2-2-1 arrangement. Existing game trophies and coins are promotional foreground objects.\n\nCapture: flutter test tool/store_capture_test.dart --no-pub\nExport: node tool/store_assets.cjs\nRequires headless Chrome at CDP port 56681.\nCopy: copy.json; dimensions and SHA256: manifest.json; validation: validation.json.\nNo store upload performed.\n\nVerified sizing references:\nhttps://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications\nhttps://support.google.com/googleplay/android-developer/answer/9866151\n`);
  }finally{ws.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
