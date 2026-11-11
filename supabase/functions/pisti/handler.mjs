import {newMatch, play, botCard, forfeit, publicState} from './core.mjs';

const cors = {'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info, x-pisti-worker'};
const json = (status, body) => new Response(JSON.stringify(body),
  {status, headers:{...cors,'Content-Type':'application/json'}});
const uuid = (s) => typeof s==='string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(s);

export function createHandler({createClient, env, log=console}) { return async req => {
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors});
  if(req.method!=='POST') return json(405,{error:'METHOD_NOT_ALLOWED'});
  const db=createClient(env.get('SUPABASE_URL'),env.get('SUPABASE_SERVICE_ROLE_KEY'),
    {auth:{persistSession:false,autoRefreshToken:false}});
  async function rpc(name,args) {
    const {data,error}=await db.rpc(name,args); if(error) throw new Error(error.message); return data;
  }
  async function load(id) {
    const row=await rpc('okeyix_pisti_load',{p_room:id});
    if(!row) throw new Error('TABLE_NOT_FOUND'); return row;
  }
  // Every transition uses the room version CAS. Concurrent workers/humans can
  // compute speculatively; exactly one state and settlement commits.
  async function progress(id) {
    for(let n=0;n<4;n++) {
      const {room:r,session:s,now}=await load(id);
      let next;
      if(r.status==='waiting' && r.seats.length===2 && r.seats.every((p)=>p.ready)) {
        next=newMatch({target:s.settings.target});
      } else if(r.status==='playing') {
        const state=s.state, seat=state.turn, current=r.seats[seat];
        const allowed=current.bot || await rpc('okeyix_pisti_player_allowed',{p_user:current.id});
        const serverTime=Date.parse(now);
        const away=r.seats.findIndex((p)=>!p.bot &&
          serverTime-Date.parse(s.last_seen[p.id] ?? r.updated_at)>s.settings.disconnect_seconds*1000);
        if(!allowed) next=forfeit(state,seat,'moderation');
        else if(away>=0) next=forfeit(state,away,'disconnect');
        else if(serverTime>=Date.parse(r.deadline)) {
          if(!current.bot) {
            const count=await rpc('okeyix_pisti_timeout',{p_room:id,p_version:r.version,p_seat:seat});
            if(count===null) continue;
            if(count>=s.settings.timeout_limit) next=forfeit(state,seat,'timeout');
          }
          if(!next) next=play(state,seat,botCard(state.hands[seat],state.pile.at(-1),state.pile.length));
        }
      }
      if(!next) return;
      const ok=await rpc('okeyix_pisti_commit',{p_room:id,p_version:r.version,p_state:next,
        p_user:null,p_request:null,p_initial:r.status==='waiting'});
      if(ok) return;
    }
  }
  try {
    const raw=await req.text();
    if(raw.length>8192) return json(413,{error:'REQUEST_TOO_LARGE'});
    let body;
    try { body=JSON.parse(raw); } catch { return json(400,{error:'INVALID_REQUEST'}); }
    if(!body || !['tick','snapshot','create','quick','join','accept','reject','heartbeat','ready','bot','leave','rematch','invite','play','forfeit','text','voice','gift','buy_pass'].includes(body.action)) return json(400,{error:'INVALID_ACTION'});
    const workerSecret=env.get('PISTI_WORKER_SECRET');
    if(body.action==='tick') {
      if(!workerSecret || req.headers.get('x-pisti-worker')!==workerSecret) return json(401,{error:'AUTH_REQUIRED'});
      const lease=crypto.randomUUID();
      if(!await rpc('okeyix_pisti_worker_lease',{p_token:lease})) return json(200,{processed:0,failed:0,busy:true});
      try {
      await rpc('okeyix_pisti_maintenance',{});
      const {data:rooms,error}=await db.from('okeyix_pisti_rooms').select('id')
        .in('status',['waiting','playing']).order('updated_at').limit(200);
      if(error) throw error;
      let failed=0;
      for(const r of rooms ?? []) { try { await progress(r.id); } catch { failed++; } }
      return json(200,{processed:rooms?.length ?? 0,failed});
      } finally { await rpc('okeyix_pisti_worker_lease',{p_token:lease,p_release:true}); }
    }
    const token=req.headers.get('authorization')?.replace(/^Bearer /i,'');
    if(!token) return json(401,{error:'AUTH_REQUIRED'});
    const {data:{user},error}=await db.auth.getUser(token);
    if(error||!user) return json(401,{error:'AUTH_REQUIRED'});
    const uid=user.id;
    if(body.action!=='snapshot' && !await rpc('okeyix_pisti_player_allowed',{p_user:uid})) return json(403,{error:'PLAYER_BANNED'});
    if(!uuid(body.room_id) && !['create','quick','accept','reject'].includes(body.action)) return json(400,{error:'INVALID_ROOM'});
    if(body.action==='snapshot') {
      const initial=await load(body.room_id);
      const member=initial.room.seats.findIndex((p)=>p.id===uid);
      if(member<0 && (initial.room.private || !initial.room.spectators_enabled)) return json(403,{error:'VIEW_DENIED'});
      if(member<0 && !await rpc('okeyix_pisti_view_allowed',{p_room:body.room_id,p_user:uid})) return json(403,{error:'SPECTATOR_PASS_REQUIRED'});
      // Snapshot is read-only: an unauthorized viewer can never drive a game.
      const {room,session,now}=initial;
      return json(200,{room,now,viewer:member,
        game:session.state?publicState(session.state,member):null,
        rematch:session.rematch, settings:session.settings});
    }
    if(!uuid(body.request_id)) return json(400,{error:'REQUEST_ID_REQUIRED'});
    if(body.action==='play'||body.action==='forfeit') {
      for(let n=0;n<4;n++) {
        const {room:r,session:s,now}=await load(body.room_id);
        const seat=r.seats.findIndex((p)=>p.id===uid && !p.bot);
        if(seat<0) return json(403,{error:'NOT_A_MEMBER'});
        const receipt=await rpc('okeyix_pisti_receipt',{p_user:uid,p_request:body.request_id});
        if(receipt) {
          if(receipt.args.room_id!==body.room_id || receipt.args.card!==(body.card ?? null)) return json(409,{error:'REQUEST_CONFLICT'});
          return json(200,{room_id:r.id,replayed:true});
        }
        if(body.match_id!==r.match_id) return json(409,{error:'STALE_MATCH'});
        if(body.version!==r.version) return json(409,{error:'STALE_VERSION'});
        if(Date.parse(now)>=Date.parse(r.deadline) && body.action==='play') return json(409,{error:'TURN_EXPIRED'});
        const next=body.action==='forfeit'?forfeit(s.state,seat,'leave'):play(s.state,seat,body.card);
        const ok=await rpc('okeyix_pisti_commit',{p_room:r.id,p_version:r.version,p_state:next,
          p_user:uid,p_request:body.request_id,p_card:body.card ?? null});
        if(ok) return json(200,{room_id:r.id});
      }
      return json(409,{error:'STALE_VERSION'});
    }
    if(['text','voice','gift'].includes(body.action)) {
      const result=await rpc('okeyix_pisti_social',{p_user:uid,p_request:body.request_id,
        p_room:body.room_id,p_kind:body.action,p_body:body.body});
      return json(200,result);
    }
    const args={...body}; delete args.action; delete args.request_id;
    const result=await rpc('okeyix_pisti_command',{p_user:uid,p_request:body.request_id,p_action:body.action,p_args:args});
    if(result.room_id) await progress(result.room_id);
    if(body.action==='invite' && result.invite_id) {
      try {
        await fetch(env.get('SUPABASE_URL')+'/functions/v1/send_table_invite_push',{
          method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+token},
          body:JSON.stringify({game_type:'pisti',invite_id:result.invite_id,table_id:result.room_id,from_user:uid,to_user:body.to_user}),
          signal:AbortSignal.timeout(3000),
        });
      } catch { log.warn('pisti_invite_push_unavailable'); }
    }
    return json(200,result);
  } catch(e) {
    // No state, card IDs, JWTs or raw database errors in logs or responses.
    const message=e instanceof Error?e.message:'';
    const known=['NOT_ENOUGH_COINS','TABLE_FULL','INVITE_EXPIRED','INVITE_REQUIRED','NOT_A_MEMBER','PLAYER_BANNED','INVITES_DISABLED',
      'ALREADY_SEATED_OKEY','NO_BOT_AVAILABLE','PISTI_DISABLED','NOT_YOUR_TURN','CARD_NOT_OWNED',
      'MATCH_FINISHED','REQUEST_CONFLICT','TABLE_NOT_FOUND','FRIEND_REQUIRED','CHAT_DISABLED','RATE_LIMITED',
      'INVALID_STAKES','GIFT_NOT_AVAILABLE','VOICE_INVALID','REMATCH_UNAVAILABLE','TABLE_NOT_WAITING',
      'FORFEIT_REQUIRED','INVALID_MESSAGE','AUTH_REQUIRED','VIEW_DENIED'];
    const code=known.find(c=>message.includes(c));
    if(!code) log.error('pisti_command_failed');
    return json(code?409:500,{error:code ?? 'SERVER_ERROR'});
  }
};
}

