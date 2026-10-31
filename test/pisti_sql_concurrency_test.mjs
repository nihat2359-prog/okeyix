import test from 'node:test';
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
const exec=promisify(execFile);
const sql=async query=>(await exec('C:\\Program Files\\PostgreSQL\\16\\bin\\psql.exe',
 ['-X','-w','-At','-h','127.0.0.1','-p','56519','-U','postgres','-d','okeyix_pisti_test','-v','ON_ERROR_STOP=1','-c',query])).stdout.trim();
test('two simultaneous requests create one seat/session, replay one receipt',{skip:process.env.PISTI_LOCAL_TEST!=='1'},async()=>{
 const uid='00000000-0000-0000-0000-000000000003',request='10000000-0000-0000-0000-000000000001';
 const query=`SELECT public.okeyix_pisti_command('${uid}','${request}','create','{"entry_coin":1000}')`;
 const result=await Promise.all([sql(query),sql(query)]);assert.equal(result[0],result[1]);
 assert.equal(await sql(`SELECT count(*) FROM public.okeyix_pisti_rooms WHERE owner_id='${uid}'`),'1');
});
test('concurrent contenders cannot occupy the same second seat',{skip:process.env.PISTI_LOCAL_TEST!=='1'},async()=>{
 const id=JSON.parse(await sql(`SELECT public.okeyix_pisti_command('00000000-0000-0000-0000-000000000004',gen_random_uuid(),'create','{}')`)).room_id;
 const results=await Promise.allSettled([5,6].map(i=>sql(`SELECT public.okeyix_pisti_command('00000000-0000-0000-0000-00000000000${i}',gen_random_uuid(),'join','{"room_id":"${id}"}')`)));
 assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
 assert.equal(await sql(`SELECT jsonb_array_length(seats) FROM public.okeyix_pisti_rooms WHERE id='${id}'`),'2');
});
