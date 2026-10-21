// Optional asset rebuild only; runtime never downloads these files.
import {mkdir,writeFile,readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const dir='.dart_tool/journey_sources/';await mkdir(dir,{recursive:true});
async function download(name,url,hash){
  let bytes;
  try{bytes=await readFile(dir+name);}catch{}
  if(!bytes){const response=await fetch(url);if(!response.ok)throw Error(`${response.status} ${url}`);bytes=Buffer.from(await response.arrayBuffer());}
  if(hash&&createHash('sha256').update(bytes).digest('hex')!==hash)throw Error(`Upstream ${name} changed. Review source/license before rebuilding.`);
  await writeFile(dir+name,bytes);console.log(name,bytes.length);
}
await download('countries','https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_admin_0_countries.geojson','239eec57ac17f100a11e2536cffc56752c318b50ae765b0918ff7aab4ce8f255');
await download('provinces','https://raw.githubusercontent.com/open-admin-data/turkey-administrative-divisions/master/data/all-province.json','cee5cb4a29308ebea950400d3667d061096a6ff3f35ec0ec47d3231c4fd2c949');
await download('provinceLicense','https://raw.githubusercontent.com/open-admin-data/turkey-administrative-divisions/master/LICENSE','c3479e413d67b5e12c11d3917349e3f1cb418e167302b907722f189881cbc306');
await download('demAttribution','https://raw.githubusercontent.com/tilezen/joerd/master/docs/attribution.md');
for(const [z,xs,ys] of [[5,[18,19,20],[11,12]],[11,[1188,1189],[766,767,768]]])
  for(const x of xs)for(const y of ys)await download(`dem_${z}_${x}_${y}.png`,`https://s3.amazonaws.com/elevation-tiles-prod/terrarium/${z}/${x}/${y}.png`);
