const fs=require('fs');
const crypto=require('crypto');
const root='output/avatar-presets-v2';
const plan=JSON.parse(fs.readFileSync(`${root}/manifest.json`,'utf8'));
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const registry=fs.readFileSync('lib/ui/avatar_preset.dart','utf8');
const registered=new Map([...registry.matchAll(/AvatarPreset\(\s*id: '([^']+)',\s*label: '([^']+)',\s*imageUrl: '([^']+)',\s*gender: '([^']+)'([\s\S]*?)\),/g)]
  .map(([,id,label,target,gender,options])=>[id,{label,target,gender,premium:options.includes('isPremium: true'),cost:Number(options.match(/unlockCost:\s*(\d+)/)?.[1]??0)}]));
// Additional presets are allowed; existing selections and purchases must remain compatible.
for(const entry of plan.entries){
  const current=registered.get(entry.id);
  if(!current || current.label!==entry.label || current.target!==entry.target || current.gender!==entry.gender || current.premium!==entry.premium || current.cost!==(entry.premium?2500:0))throw Error(`Existing preset contract changed: ${entry.id}`);
}
const seen=new Set();
const files=plan.entries.map(entry=>{
  const bytes=fs.readFileSync(entry.target);
  if(bytes.subarray(0,8).toString('hex')!=='89504e470d0a1a0a')throw Error(`Not PNG: ${entry.id}`);
  if(bytes.readUInt32BE(16)!==256 || bytes.readUInt32BE(20)!==256)throw Error(`Wrong dimensions: ${entry.id}`);
  if(bytes[24]!==8 || bytes[25]!==2)throw Error(`Expected 8-bit true-color RGB PNG: ${entry.id}`);
  if(bytes.length>200000)throw Error(`Oversized preset: ${entry.id}`);
  const sha256=hash(bytes);
  if(sha256===entry.original_sha256)throw Error(`Not refreshed: ${entry.id}`);
  if(seen.has(sha256))throw Error(`Duplicate avatar: ${entry.id}`);
  seen.add(sha256);
  return {id:entry.id,path:entry.target,sha256,bytes:bytes.length};
});
for(const entry of plan.untouched_bot_assets){
  if(hash(fs.readFileSync(entry.target))!==entry.sha256)throw Error(`Bot image changed: ${entry.target}`);
}
const report={count:files.length,dimensions:'256x256',originalBytes:plan.entries.reduce((n,x)=>n+x.original_bytes,0),totalBytes:files.reduce((n,x)=>n+x.bytes,0),maximumBytes:Math.max(...files.map(x=>x.bytes)),presetRegistryUnchanged:true,botImagesUnchanged:true,files};
fs.writeFileSync(`${root}/verification.json`,JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({...report,files:undefined}));
