const fs = require('fs');
const crypto = require('crypto');
const expected = JSON.parse(fs.readFileSync('output/bot-avatars/v1/assignments.json','utf8'));
let cursor=0;
let verified=0;
let totalBytes=0;
const failures=[];
async function worker() {
  while(cursor<expected.length) {
    const row=expected[cursor++];
    try {
      const response=await fetch(row.url,{signal:AbortSignal.timeout(20000)});
      if(!response.ok) throw Error(`HTTP ${response.status}`);
      if(!response.headers.get('content-type')?.startsWith('image/jpeg')) throw Error('Wrong MIME type');
      const bytes=Buffer.from(await response.arrayBuffer());
      const hash=crypto.createHash('sha256').update(bytes).digest('hex');
      if(bytes.length!==row.bytes || hash!==row.sha256) throw Error('Uploaded content mismatch');
      verified++;
      totalBytes+=bytes.length;
    } catch(error) { failures.push({id:row.id,error:error.message}); }
  }
}
Promise.all(Array.from({length:8},worker)).then(()=>{
  console.log(JSON.stringify({verified,total:expected.length,totalBytes,failures},null,2));
  if(failures.length || verified!==164) process.exitCode=1;
});
