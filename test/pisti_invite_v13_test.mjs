import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import {webcrypto} from 'node:crypto';
const baseline=fs.readFileSync('test/fixtures/send_table_invite_push_v13.ts','utf8');
const candidate=fs.readFileSync('supabase/functions/send_table_invite_push/index.ts','utf8');
const pair=await webcrypto.subtle.generateKey({name:'RSASSA-PKCS1-v1_5',modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:'SHA-256'},true,['sign','verify']);
const pem='-----BEGIN PRIVATE KEY-----\n'+Buffer.from(await webcrypto.subtle.exportKey('pkcs8',pair.privateKey)).toString('base64')+'\n-----END PRIVATE KEY-----';
async function run(source,{game='okey',disabled=false,tokens=['device-token','device-token'],fallback=[],expired=false,claim=true,identity='sender',options=false}={}){
 const sent=[],calls=[],env={SUPABASE_URL:'https://local.invalid',SUPABASE_SERVICE_ROLE_KEY:'test-only',FIREBASE_PROJECT_ID:'test-project',FIREBASE_SERVICE_ACCOUNT_JSON:JSON.stringify({client_email:'test@example.invalid',private_key:pem,project_id:'test-project'})};
 const db={auth:{getUser:async()=>({data:{user:{id:identity}},error:null})},rpc:async(name)=>{calls.push(name);return {data:claim,error:null};},from(table){
  let selection='',update=false;
  const b={select(s){selection=s;return b;},eq(){return b;},not(){return b;},limit(){return b;},update(){update=true;return b;},
   async maybeSingle(){return {data:table==='okeyix_pisti_invites'?{id:'invite',status:'pending',expires_at:new Date(Date.now()+(expired?-60000:60000)).toISOString()}:selection==='username'?{username:'Deniz'}:{allow_game_invites:!disabled}};},
   then(resolve,reject){return Promise.resolve({data:update?[]:(table==='user_devices'?tokens:fallback).map(push_token=>({push_token}))}).then(resolve,reject);}};return b;
 }};
 let handler;
 const context={createClient:()=>db,Deno:{env:{get:key=>env[key]},serve:fn=>handler=fn},crypto:webcrypto,TextEncoder,Uint8Array,URLSearchParams,Response,Request,Date,atob,btoa,
  fetch:async(url,init)=>{if(String(url).includes('oauth2.googleapis.com'))return new Response(JSON.stringify({access_token:'oauth-test'}));sent.push({url,headers:init.headers,payload:JSON.parse(init.body)});return new Response(JSON.stringify({name:'projects/test/messages/1'}));}};
 const js=stripTypeScriptTypes(source,{mode:'strip'}).replace(/^import .*;\r?\n/gm,'');
 vm.runInNewContext(js,context);
 const response=await handler(new Request('https://local/invite',{method:options?'OPTIONS':'POST',headers:{Authorization:'Bearer test-jwt'},...(options?{}:{body:JSON.stringify({table_id:'table',from_user:'sender',to_user:'recipient',...(game==='pisti'?{game_type:'pisti',invite_id:'invite'}:{})})})}));
 return JSON.parse(JSON.stringify({status:response.status,body:options?await response.text():await response.json(),sent,calls}));
}
test('Okey FCM v1 payload, Android channel, APNs badge and response exactly match live v13',async()=>{
 assert.deepEqual(await run(candidate),await run(baseline));
 assert.equal(candidate.includes('FCM_SERVER_KEY'),false);assert.equal(candidate.includes('fcm.googleapis.com/fcm/send'),false);
});
test('v13 token fallback, preference, no-token and OPTIONS behavior remain identical',async()=>{
 for(const args of [{tokens:[],fallback:['fallback-device']},{disabled:true},{tokens:[],fallback:[]},{options:true}])assert.deepEqual(await run(candidate,args),await run(baseline,args));
});
test('Pisti uses v1 with explicit game and invite routing, preserving provider settings',async()=>{
 const result=await run(candidate,{game:'pisti'});assert.equal(result.status,200);assert.equal(result.sent.length,1);
 const message=result.sent[0].payload.message;
 assert.equal(message.data.type,'pisti_invite');assert.equal(message.data.game_type,'pisti');assert.equal(message.data.invite_id,'invite');
 assert.equal(message.android.notification.channel_id,'invite_channel');assert.equal(message.apns.payload.aps.badge,1);
 assert.ok(result.calls.includes('okeyix_pisti_claim_push'));
});
test('Pisti refuses forged sender, expired invitation and repeated push claim',async()=>{
 assert.equal((await run(candidate,{game:'pisti',identity:'other'})).status,401);
 assert.equal((await run(candidate,{game:'pisti',expired:true})).status,409);
 assert.equal((await run(candidate,{game:'pisti',claim:false})).sent.length,0);
});
test('gateway JWT stays enabled; client routes Pisti before the existing Okey branch',()=>{
 const config=fs.readFileSync('supabase/config.toml','utf8');assert.match(config,/\[functions\.send_table_invite_push\]\s*verify_jwt\s*=\s*true/);
 const main=fs.readFileSync('lib/main.dart','utf8');const start=main.indexOf('Future<void> _handlePushTapData');const routing=main.slice(start,main.indexOf('Widget build',start));
 assert.match(routing,/game_type.*pisti/);assert.match(routing,/PistiLobbyScreen/);assert.ok(routing.indexOf('PistiLobbyScreen')<routing.indexOf('OkeyGameScreen'));
 assert.match(routing,/return;\s*}\s*await Navigator/);
});
