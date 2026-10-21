const fs=require('node:fs'),assert=require('node:assert/strict');
global.window={};require('../assets/journey/geography.js');require('../assets/journey/places.js');
const {country,istanbul}=window.JourneyGeography,city=window.JourneyPlaces.cities.istanbul;
assert.equal(country.cities.length,81);assert.equal(new Set(country.cities.map(c=>c.id)).size,81);
const names={'TUR006':'Ankara','TUR034':'İstanbul','TUR035':'İzmir','TUR065':'Van','TUR081':'Düzce'};
for(const [id,name] of Object.entries(names))assert.equal(country.cities.find(c=>c.id===id)?.name,name,'ID/name mapping must not depend on source array order');
assert(country.cities.find(c=>c.id==='TUR035').lon<28,'Izmir must be on western coast');
assert(country.cities.find(c=>c.id==='TUR065').lon>43,'Van must be in eastern Turkey');
for(const data of [country,istanbul]){
  assert.equal(data.dem.values.length,data.dem.width*data.dem.height);
  assert(data.dem.values.every(Number.isFinite));assert.equal(data.dem.source,'Mapzen/Terrarium DEM');
  for(const polygon of data.polygons)for(const ring of polygon)assert.deepEqual(ring[0],ring.at(-1),'Closed real boundary rings');
}
assert(Math.max(...country.dem.values)>3000,'Measured mountain relief must exist');
assert.equal(city.places.length,6);assert.equal(city.places.find(p=>p.id==='kiz').model,'maiden');
assert(city.places.find(p=>p.id==='hisar').lat>city.places.find(p=>p.id==='kiz').lat);
assert(city.places.find(p=>p.id==='galata').lon<city.places.find(p=>p.id==='kiz').lon);
assert(city.places.find(p=>p.id==='haydarpasa').lat<city.places.find(p=>p.id==='kiz').lat);
assert(fs.readFileSync('assets/journey/SOURCES.md','utf8').includes('hand-simplified'));
console.log('PASS: 81 distinct province IDs and name/coordinate mapping, measured DEM bounds, closed boundaries, six relative landmark locations, explicit approximation attribution.');
