// Offline, reproducible static glTF baker. Run after prepare_maiden_textures.ps1.
// No remeshing: source triangles/UVs/PBR channels are retained. Only transforms,
// material batching and texture resolution/encoding change. CC BY credit retained.
const fs=require('node:fs'),path=require('node:path'),T=require('../assets/journey/vendor/three.min.js');
const source=process.argv[2]||'.dart_tool/maiden_source';
const input=JSON.parse(fs.readFileSync(path.join(source,'scene.gltf')));
if(input.animations?.length||input.skins?.length)throw Error('Only static models supported');
const raw=fs.readFileSync(path.join(source,'scene.bin'));
const components={5126:[4,'getFloat32'],5125:[4,'getUint32'],5123:[2,'getUint16'],5121:[1,'getUint8']};
const widths={SCALAR:1,VEC2:2,VEC3:3,VEC4:4};
function read(id){const a=input.accessors[id],v=input.bufferViews[a.bufferView];
 if(a.sparse||a.normalized)throw Error('Unsupported accessor');
 const [size,method]=components[a.componentType],n=widths[a.type],stride=v.byteStride||size*n;
 const view=new DataView(raw.buffer,raw.byteOffset,raw.byteLength),out=[];
 for(let i=0;i<a.count;i++)for(let j=0;j<n;j++)out.push(view[method]((v.byteOffset||0)+(a.byteOffset||0)+i*stride+j*size,true));return out;}
const groups=new Map(),bounds=new T.Box3(),point=new T.Vector3();let triangles=0;
function visit(id,parent){const node=input.nodes[id],local=node.matrix?new T.Matrix4().fromArray(node.matrix):new T.Matrix4().compose(new T.Vector3().fromArray(node.translation||[0,0,0]),new T.Quaternion().fromArray(node.rotation||[0,0,0,1]),new T.Vector3().fromArray(node.scale||[1,1,1]));
 const world=parent.clone().multiply(local),normal=new T.Matrix3().getNormalMatrix(world);
 if(node.mesh!==undefined)for(const p of input.meshes[node.mesh].primitives){
  // Replace the author's flat sea plane with the dedicated animated water.
  if(input.materials[p.material]?.name==='Material_sea')continue;
  if(p.mode!==undefined&&p.mode!==4)throw Error('Expected triangles');
  const key=p.material+'|'+Object.keys(p.attributes).sort().join(',');
  if(!groups.has(key))groups.set(key,{material:p.material,position:[],normal:[],uv:[],indices:[]});const g=groups.get(key),offset=g.position.length/3;
  const pos=read(p.attributes.POSITION),norm=read(p.attributes.NORMAL),uv=p.attributes.TEXCOORD_0===undefined?null:read(p.attributes.TEXCOORD_0);
  for(let i=0;i<pos.length;i+=3){point.fromArray(pos,i).applyMatrix4(world);bounds.expandByPoint(point);g.position.push(point.x,point.y,point.z);point.fromArray(norm,i).applyMatrix3(normal).normalize();g.normal.push(point.x,point.y,point.z);}
  if(uv)for(const value of uv)g.uv.push(value);
  const indices=p.indices===undefined?Array.from({length:pos.length/3},(_,i)=>i):read(p.indices);
  if(world.determinant()<0)for(let i=0;i<indices.length;i+=3)[indices[i+1],indices[i+2]]=[indices[i+2],indices[i+1]];
  for(const i of indices)g.indices.push(i+offset);triangles+=indices.length/3;
 }for(const c of node.children||[])visit(c,world);}
for(const id of input.scenes[input.scene||0].nodes)visit(id,new T.Matrix4());
const size=bounds.getSize(new T.Vector3()),center=bounds.getCenter(new T.Vector3()),scale=30/size.y;
const doc={asset:{version:'2.0',extras:input.asset.extras},scene:0,scenes:[{nodes:[0]}],nodes:[{mesh:0}],meshes:[{primitives:[]}],materials:input.materials,textures:input.textures,samplers:input.samplers,images:[],extensionsUsed:input.extensionsUsed,accessors:[],bufferViews:[],buffers:[{byteLength:0}]};
let length=0;const chunks=[];
function buffer(bytes){const pad=(4-bytes.length%4)%4;const id=doc.bufferViews.length;doc.bufferViews.push({buffer:0,byteOffset:length,byteLength:bytes.length});chunks.push(bytes,Buffer.alloc(pad));length+=bytes.length+pad;return id;}
function accessor(data,n,type){const typed=type===5125?new Uint32Array(data):new Float32Array(data);const a={bufferView:buffer(Buffer.from(typed.buffer)),componentType:type,count:data.length/n,type:Object.keys(widths).find(k=>widths[k]===n)};
 if(n===3){a.min=[Infinity,Infinity,Infinity];a.max=[-Infinity,-Infinity,-Infinity];for(let i=0;i<data.length;i++) {let j=i%3;a.min[j]=Math.min(a.min[j],data[i]);a.max[j]=Math.max(a.max[j],data[i]);}}
 doc.accessors.push(a);return doc.accessors.length-1;}
for(const g of groups.values()){for(let i=0;i<g.position.length;i+=3){g.position[i]=(g.position[i]-center.x)*scale;g.position[i+1]=(g.position[i+1]-bounds.min.y)*scale;g.position[i+2]=(g.position[i+2]-center.z)*scale;}
 const attributes={POSITION:accessor(g.position,3,5126),NORMAL:accessor(g.normal,3,5126)};if(g.uv.length)attributes.TEXCOORD_0=accessor(g.uv,2,5126);
 doc.meshes[0].primitives.push({attributes,indices:accessor(g.indices,1,5125),material:g.material,mode:4});}
for(const image of input.images){const file=path.basename(image.uri,'.png')+'.jpg';doc.images.push({name:image.name,bufferView:buffer(fs.readFileSync(path.join('.dart_tool/maiden_textures',file))),mimeType:'image/jpeg'});}
doc.buffers[0].byteLength=length;
const json=Buffer.from(JSON.stringify(doc)),jp=Buffer.alloc((4-json.length%4)%4,32),bin=Buffer.concat(chunks),header=Buffer.alloc(20),bh=Buffer.alloc(8);
header.writeUInt32LE(0x46546c67,0);header.writeUInt32LE(2,4);header.writeUInt32LE(28+json.length+jp.length+bin.length,8);header.writeUInt32LE(json.length+jp.length,12);header.writeUInt32LE(0x4e4f534a,16);bh.writeUInt32LE(bin.length,0);bh.writeUInt32LE(0x004e4942,4);
const glb=Buffer.concat([header,json,jp,bh,bin]);
// Embedded GLB avoids fetch(file:) restrictions in Android/iOS asset WebViews.
fs.writeFileSync('assets/journey/maiden-model.js','/* oblo.3d, CC BY 4.0; see MAIDEN-LICENSE.txt. Optimized static GLB. */\nwindow.MAIDEN_GLB="'+glb.toString('base64')+'";\n');
fs.copyFileSync(path.join(source,'license.txt'),'assets/journey/MAIDEN-LICENSE.txt');
let loader=fs.readFileSync(path.join(source,'GLTFLoader.source.js'),'utf8');
loader=loader.replace(/import \{([\s\S]*?)\} from 'three';/,(_,names)=>'const {'+names+'}=THREE;').replace(/import \{ toTrianglesDrawMode \}[^;]+;/,'').replace(/export \{ GLTFLoader \};/,'window.GLTFLoader=GLTFLoader;');
const utils=fs.readFileSync(path.join(source,'BufferGeometryUtils.source.js'),'utf8');
const start=utils.indexOf('function toTrianglesDrawMode('),end=utils.indexOf('\nfunction ',start+10);
fs.writeFileSync('assets/journey/vendor/GLTFLoader.js','/* Three.js r160, MIT. Official loader wrapped for existing offline UMD runtime. */\n(()=>{\n'+loader+'\n'+utils.slice(start,end)+'\n})();');
console.log(JSON.stringify({triangles,batches:groups.size,sourceMeshes:input.meshes.length,sourceSize:size.toArray(),height:30,width:size.x*scale,depth:size.z*scale,glbMB:glb.length/1048576},null,2));
