// Real PostgreSQL RPCs + real HTTP handler; auth/scheduler adapters are local
// doubles. This does not claim Supabase Gateway/Realtime/FCM device validation.
import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {randomUUID} from 'node:crypto';
import {createHandler} from '../supabase/functions/pisti/handler.mjs';
import {botCard} from '../supabase/functions/pisti/core.mjs';
const exec=promisify(execFile);
const sql=async query=>(await exec('C:\\Program Files\\PostgreSQL\\16\\bin\\psql.exe',
 ['-X','-w','-At','-h','127.0.0.1','-p','56519','-U','postgres','-d','okeyix_pisti_test','-v','ON_ERROR_STOP=1','-c',query])).stdout.trim();
const quote=s=>"'"+s.replaceAll("'","''")+"'";
const value=v=>v==null?'NULL':typeof v==='object'?quote(JSON.stringify(v))+'::jsonb':typeof v==='string'?quote(v):String(v);
const uid=n=>'00000000-0000-0000-0000-'+String(n).padStart(12,'0');
const db={
 auth:{getUser:async token=>({data:{user:/^local-\d+$/.test(token)?{id:uid(Number(token.slice(6)))}:null},error:null})},
 rpc:async(name,args)=>{
  assert.match(name,/^okeyix_pisti_[a-z_]+$/);
  try {
   const result=await sql(`SELECT to_jsonb(public.${name}(${Object.entries(args).map(([k,v])=>`${k}=>${value(v)}`).join(',')}));`);
   return {data:result?JSON.parse(result):null,error:null};
  } catch(e){console.error(name,(e.stderr ?? '').split(/\r?\n/).find(line=>line.includes('ERROR:')));return {data:null,error:{message:e.stderr}};}
 },
 from:table=>{assert.equal(table,'okeyix_pisti_rooms');const builder={select:()=>builder,in:()=>builder,order:()=>builder,
  limit:async()=>({data:JSON.parse(await sql("SELECT coalesce(jsonb_agg(jsonb_build_object('id',id)),'[]') FROM public.okeyix_pisti_rooms WHERE status IN ('waiting','playing')")),error:null})};return builder;},
};
const handler=createHandler({createClient:()=>db,env:{get:k=>k==='PISTI_WORKER_SECRET'?'local-worker':k==='SUPABASE_URL'?'http://invalid.local':'test'},log:{error:()=>{},warn:()=>{}}});
async function call(n,body,headers={}){
 const response=await handler(new Request('http://local/pisti',{method:'POST',headers:{'Content-Type':'application/json',...(n?{Authorization:'Bearer local-'+n}:{}),...headers},body:JSON.stringify(body)}));
 return {status:response.status,body:await response.json()};
}
const command=(n,action,args={})=>call(n,{action,request_id:randomUUID(),...args});
test('two authenticated sessions complete a full server match, replay, reject hidden access and invalid moves',
 {skip:process.env.PISTI_LOCAL_TEST!=='1'},async()=>{
 await sql('UPDATE public.okeyix_pisti_settings SET target=1');
 assert.equal((await call(null,{action:'snapshot',room_id:randomUUID()})).status,401);
 let response=await command(7,'create',{private:true});assert.equal(response.status,200);
 const room=response.body.room_id;
 await sql(`INSERT INTO public.friends VALUES('${uid(7)}','${uid(8)}','accepted')`);
 // Invite creation is tested in SQL; insert a local invitation to avoid sending push.
 const invitation=await sql(`INSERT INTO public.okeyix_pisti_invites(table_id,from_user,to_user) VALUES('${room}','${uid(7)}','${uid(8)}') RETURNING id`);
 const invite=invitation.split(/\r?\n/)[0].trim();
 assert.equal((await command(8,'accept',{invite_id:invite})).status,200);
 await command(7,'ready',{room_id:room});assert.equal((await command(8,'ready',{room_id:room})).status,200);
 assert.equal((await call(9,{action:'snapshot',room_id:room})).status,403);
 let final, moves=0,last;
 while(++moves<200){
  const a=(await call(7,{action:'snapshot',room_id:room})).body;
  const b=(await call(8,{action:'snapshot',room_id:room})).body;
  assert.ok(a.game);assert.ok(b.game);assert.equal(a.game.seq,b.game.seq);
  for(const p of [a,b])for(const key of ['hands','deck','pile','won'])assert.equal(key in p.game,false);
  assert.equal(a.game.hand.length,a.game.hand_counts[0]);assert.equal(b.game.hand.length,b.game.hand_counts[1]);
  if(a.room.status==='finished'){final=a;break;}
  const n=a.game.turn===0?7:8,p=n===7?a:b;
  if(moves===1){
   const invalid=await command(n,'play',{room_id:room,version:p.room.version,match_id:p.room.match_id,card:99});
   assert.equal(invalid.body.error,'CARD_NOT_OWNED');
  }
  const card=botCard(p.game.hand,p.game.top,p.game.pile_count);
  const body={action:'play',room_id:room,request_id:randomUUID(),match_id:p.room.match_id,version:p.room.version,card};
  response=await call(n,body);assert.equal(response.status,200,JSON.stringify(response));
  if(moves===1||moves%10===0){const duplicate=await call(n,body);assert.equal(duplicate.body.replayed,true);}
  last={n,body};
 }
 assert.ok(final,'full match finished');assert.equal(final.game.reason,'normal');
 assert.equal((await call(last.n,last.body)).body.replayed,true);
 assert.equal(await sql(`SELECT count(*) FROM public.wallet_transactions WHERE note='${final.room.match_id}'`),'3');
});
test('independent worker drives bot and server timeouts with no open client',
 {skip:process.env.PISTI_LOCAL_TEST!=='1'},async()=>{
 const created=await command(9,'create');assert.equal(created.status,200);
 const room=created.body.room_id;
 assert.equal((await command(9,'bot',{room_id:room})).status,200);
 assert.equal((await command(9,'ready',{room_id:room})).status,200);
 assert.equal((await call(null,{action:'tick'})).status,401);
 for(let i=0;i<8;i++){
  await sql(`UPDATE public.okeyix_pisti_rooms SET deadline=clock_timestamp()-interval '1 second' WHERE id='${room}' AND status='playing'`);
  const result=await call(null,{action:'tick'},{'x-pisti-worker':'local-worker'});assert.equal(result.status,200);assert.equal(result.body.failed,0);
  const snapshot=(await call(9,{action:'snapshot',room_id:room})).body;
  if(snapshot.room.status==='finished'){
   assert.equal(snapshot.game.reason,'timeout');assert.equal(snapshot.game.winner,1);
   const denied=await call(10,{action:'snapshot',room_id:room});assert.equal(denied.body.error,'SPECTATOR_PASS_REQUIRED');
   const passRequest={action:'buy_pass',request_id:randomUUID(),room_id:room};
   assert.equal((await call(10,passRequest)).status,200);assert.equal((await call(10,passRequest)).status,200);
   assert.equal(await sql(`SELECT count(*) FROM public.wallet_transactions WHERE user_id='${uid(10)}' AND reason='spectator_pass_purchase'`),'1');
   const spectator=(await call(10,{action:'snapshot',room_id:room})).body;
   assert.equal(spectator.viewer,-1);assert.deepEqual(spectator.game.hand,[]);
   assert.equal((await command(9,'rematch',{room_id:room})).status,200);
   await sql(`UPDATE okeyix_pisti_private.sessions SET last_seen=jsonb_set(last_seen,ARRAY['${uid(9)}'],to_jsonb((clock_timestamp()-interval '100 seconds')::text)) WHERE room_id='${room}'`);
   const tick=await call(null,{action:'tick'},{'x-pisti-worker':'local-worker'});assert.equal(tick.body.failed,0);
   const disconnected=(await call(9,{action:'snapshot',room_id:room})).body;
   assert.equal(disconnected.game.reason,'disconnect');return;
  }
 }
 assert.fail('three human timeouts should finish the match');
});
