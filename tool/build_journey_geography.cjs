// Reproducible offline build from downloaded source files. Never fabricates DEM.
// Source downloads and license notes: assets/journey/SOURCES.md.
const fs = require('node:fs'), zlib = require('node:zlib');
const source = '.dart_tool/journey_sources/';
function png(path) {
  const b = fs.readFileSync(path); let at = 8, width, height, channels, blocks = [];
  while (at < b.length) {
    const n = b.readUInt32BE(at), type = b.toString('ascii', at + 4, at + 8), body = b.subarray(at + 8, at + 8 + n);
    if (type === 'IHDR') { width = body.readUInt32BE(0); height = body.readUInt32BE(4); if (body[8] !== 8 || ![2,6].includes(body[9])) throw Error('Unsupported DEM PNG'); channels = body[9] === 6 ? 4 : 3; }
    if (type === 'IDAT') blocks.push(body); at += n + 12;
  }
  const raw = zlib.inflateSync(Buffer.concat(blocks)), stride = width * channels, pixels = Buffer.alloc(height * stride);
  for (let y = 0; y < height; y++) for (let x = 0; x < stride; x++) {
    const filter = raw[y * (stride + 1)], value = raw[y * (stride + 1) + x + 1];
    const a = x >= channels ? pixels[y * stride + x - channels] : 0, up = y ? pixels[(y-1)*stride+x] : 0;
    const corner = y && x >= channels ? pixels[(y-1)*stride+x-channels] : 0;
    let predictor = 0;
    if (filter === 1) predictor = a;
    if (filter === 2) predictor = up;
    if (filter === 3) predictor = Math.floor((a+up)/2);
    if (filter === 4) { const p=a+up-corner, pa=Math.abs(p-a), pb=Math.abs(p-up), pc=Math.abs(p-corner); predictor=pa<=pb&&pa<=pc?a:pb<=pc?up:corner; }
    if (filter > 4) throw Error('PNG filter'); pixels[y*stride+x]=(value+predictor)&255;
  }
  return (x,y) => { const i=(y*width+x)*channels; return pixels[i]*256+pixels[i+1]+pixels[i+2]/256-32768; };
}
const tiles = new Map();
function sample(lon, lat, z) {
  const n=2**z, x=(lon+180)/360*n, y=(1-Math.asinh(Math.tan(lat*Math.PI/180))/Math.PI)/2*n;
  const key=`${z}_${Math.floor(x)}_${Math.floor(y)}`;
  if (!tiles.has(key)) tiles.set(key,png(source+`dem_${key}.png`));
  return Math.round(tiles.get(key)(Math.min(255,Math.floor((x%1)*256)),Math.min(255,Math.floor((y%1)*256))));
}
function grid(bounds, width, height, z) {
  const values=[];
  for(let y=0;y<height;y++)for(let x=0;x<width;x++)values.push(sample(bounds[0]+x/(width-1)*(bounds[2]-bounds[0]),bounds[1]+y/(height-1)*(bounds[3]-bounds[1]),z));
  return {bounds,width,height,values,source:'Mapzen/Terrarium DEM',zoom:z};
}
const countries=JSON.parse(fs.readFileSync(source+'countries'));
const turkey=countries.features.find(f=>f.properties.ADM0_A3==='TUR');
const names='Adana|Adıyaman|Afyonkarahisar|Ağrı|Amasya|Ankara|Antalya|Artvin|Aydın|Balıkesir|Bilecik|Bingöl|Bitlis|Bolu|Burdur|Bursa|Çanakkale|Çankırı|Çorum|Denizli|Diyarbakır|Edirne|Elazığ|Erzincan|Erzurum|Eskişehir|Gaziantep|Giresun|Gümüşhane|Hakkâri|Hatay|Isparta|Mersin|İstanbul|İzmir|Kars|Kastamonu|Kayseri|Kırklareli|Kırşehir|Kocaeli|Konya|Kütahya|Malatya|Manisa|Kahramanmaraş|Mardin|Muğla|Muş|Nevşehir|Niğde|Ordu|Rize|Sakarya|Samsun|Siirt|Sinop|Sivas|Tekirdağ|Tokat|Trabzon|Tunceli|Şanlıurfa|Uşak|Van|Yozgat|Zonguldak|Aksaray|Bayburt|Karaman|Kırıkkale|Batman|Şırnak|Bartın|Ardahan|Iğdır|Yalova|Karabük|Kilis|Osmaniye|Düzce'.split('|');
const provinces=JSON.parse(fs.readFileSync(source+'provinces'));
const cities=provinces.map(p=>{const i=Number(p.id.slice(3))-1;return {id:p.id,name:names[i],lon:Number(p.geo.lon),lat:Number(p.geo.lat),scene:i===33?'istanbul':null,priority:[5,33,34,6,15,26,60,64].includes(i)?2:1};}).sort((a,b)=>a.id.localeCompare(b.id));
if(cities.length!==81||cities[33].name!=='İstanbul')throw Error('Province schema');
// The dataset supplies province centroids; Istanbul entry explicitly anchors
// the historic city, not the province centroid. Other cities stay unopened.
Object.assign(cities[33],{lon:28.9784,lat:41.0082,priority:10});
const country={polygons:turkey.geometry.coordinates,dem:grid([25.5,35.5,45,42.5],241,101,5),cities};
function clip(ring,bounds) {
  let points=ring.slice(0,-1);
  for(const [axis,edge,greater] of [[0,bounds[0],true],[0,bounds[2],false],[1,bounds[1],true],[1,bounds[3],false]]){
    const output=[];
    for(let i=0;i<points.length;i++){
      const a=points[i],b=points[(i+1)%points.length],ai=greater?a[axis]>=edge:a[axis]<=edge,bi=greater?b[axis]>=edge:b[axis]<=edge;
      if(ai)output.push(a);
      if(ai!==bi){const t=(edge-a[axis])/(b[axis]-a[axis]);output.push([a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])]);}
    } points=output;
  }
  return points.length>2?[...points,points[0]]:[];
}
const cityBounds=[28.86,40.92,29.16,41.15];
country.context=countries.features.filter(f=>['GRC','BGR','GEO','ARM','AZE','IRN','IRQ','SYR','CYP'].includes(f.properties.ADM0_A3)).flatMap(f=>{
  const polygons=f.geometry.type==='Polygon'?[f.geometry.coordinates]:f.geometry.coordinates;
  return polygons.map(p=>clip(p[0],[23,34,47,44])).filter(r=>r.length>3).map(r=>[r]);
});
let cityRings=turkey.geometry.coordinates.map(p=>clip(p[0],cityBounds)).filter(r=>r.length>3);
// Explicitly hand-simplified Golden Horn inlet: Natural Earth's 1:10m outline
// omits this inlet. This is an illustrative correction, NOT survey/OSM data.
const horn=[[28.987,41.025],[28.976,41.024],[28.963,41.032],[28.952,41.041],[28.943,41.05],[28.936,41.055],[28.932,41.055],[28.936,41.048],[28.943,41.039],[28.953,41.031],[28.966,41.023],[28.978,41.017],[28.987,41.016]];
cityRings=cityRings.map(r=>{
  const at=r.findIndex(p=>p[0]===28.989513&&p[1]===41.031073);
  if(at<0)return r;
  const end=r.findIndex((p,i)=>i>at&&p[1]===41.017076);
  return end>at?[...r.slice(0,at+1),...horn,...r.slice(end)]:r;
});
const city={bounds:cityBounds,polygons:cityRings.map(r=>[r]),dem:grid(cityBounds,121,121,11),coastSource:'Natural Earth 1:10m + explicitly hand-simplified Golden Horn inlet'};
fs.writeFileSync('assets/journey/geography.js','/* Derived offline geographic data. See SOURCES.md. */\nwindow.JourneyGeography='+JSON.stringify({country,istanbul:city})+';\n');
fs.copyFileSync(source+'provinceLicense','assets/journey/PROVINCES-LICENSE.txt');
fs.copyFileSync(source+'demAttribution','assets/journey/TERRAIN-ATTRIBUTION.txt');
console.log('Geography:',country.polygons.length,'country polygons;',cityRings.length,'city polygons;',cities.length,'provinces; DEM sampled, no synthetic heights.');
