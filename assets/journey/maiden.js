/* Kız Kulesi quality study. Architecture: oblo.3d, CC BY 4.0.
   Metres, Y up; independent of maps, café, auth and all game services. */
(()=>{'use strict';
const T=THREE,tell=m=>window.Journey?.postMessage(m);
let disposed=false,paused=false,loaded=false,frame=0,elapsed=0,last=performance.now(),intro=0;
const fail=()=>{if(!disposed){tell('error');document.getElementById('failure').style.display='block';}};
window.addEventListener('error',fail);
const scene=new T.Scene(),renderer=new T.WebGLRenderer({antialias:true,powerPreference:'high-performance'});
renderer.setPixelRatio(Math.min(devicePixelRatio||1,1.5));renderer.setSize(innerWidth,innerHeight);
renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1;
renderer.shadowMap.enabled=true;renderer.shadowMap.type=T.PCFSoftShadowMap;document.body.appendChild(renderer.domElement);
scene.fog=new T.FogExp2('#c6ac90',.00064);
const camera=new T.PerspectiveCamera(43,innerWidth/innerHeight,.25,5000);
const target=new T.Vector3(0,10,0),sunDirection=new T.Vector3(-.75,.24,.35).normalize();
const sun=new T.DirectionalLight('#ffd1a0',3.5);sun.position.copy(sunDirection).multiplyScalar(160);sun.castShadow=true;
Object.assign(sun.shadow.camera,{left:-35,right:35,top:40,bottom:-25,near:1,far:260});sun.shadow.mapSize.set(1024,1024);sun.shadow.normalBias=.035;sun.target.position.set(0,10,0);
const fill=new T.DirectionalLight(0xb8d4e5,.8);fill.position.set(60,40,80);scene.add(fill);
scene.add(sun,sun.target,new T.HemisphereLight('#bcccd9','#84755e',2.1));
const skyMaterial=new T.ShaderMaterial({side:T.BackSide,depthWrite:false,uniforms:{sun:{value:sunDirection}},vertexShader:`varying vec3 direction;void main(){direction=position;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}`,fragmentShader:`varying vec3 direction;uniform vec3 sun;void main(){vec3 d=normalize(direction);float h=max(d.y,0.);vec3 c=mix(vec3(.83,.64,.44),vec3(.16,.29,.43),pow(h,.24));float a=max(dot(d,sun),0.);c+=vec3(1.,.55,.19)*pow(a,28.)*.4;c+=vec3(5.,3.1,1.5)*smoothstep(.99982,.99994,a);gl_FragColor=vec4(c,1.);}`});
const sky=new T.Mesh(new T.SphereGeometry(2200,48,24),skyMaterial);sky.frustumCulled=false;scene.add(sky);
// Small generated environment map supplies coherent sky/ground reflections.
const envScene=new T.Scene();envScene.add(new T.Mesh(new T.SphereGeometry(10,32,16),skyMaterial));
const pmrem=new T.PMREMGenerator(renderer),environment=pmrem.fromScene(envScene,.06,.1,30);scene.environment=environment.texture;pmrem.dispose();envScene.children[0].geometry.dispose();
const waterUniforms={time:{value:0},sun:{value:sunDirection},eye:{value:camera.position},light:{value:new T.Color('#ffcb8c')}};
const water=new T.Mesh(new T.PlaneGeometry(4500,4500),new T.ShaderMaterial({uniforms:waterUniforms,vertexShader:`varying vec3 world;void main(){world=(modelMatrix*vec4(position,1.)).xyz;gl_Position=projectionMatrix*viewMatrix*vec4(world,1.);}`,fragmentShader:`varying vec3 world;uniform float time;uniform vec3 sun,eye,light;
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
float wave(vec2 p){float distanceFade=exp(-length(eye-world)*.004);float swell=sin(p.x*.23+p.y*.17+noise(p*.045+time*.017)*5.+time*.65)*.42;return swell+(noise(p*.7+vec2(time*.14,-time*.1))-.5)*.22*distanceFade+(noise(p*1.7-time*.11)-.5)*.07*distanceFade;}
void main(){vec2 p=world.xz;float e=.06;vec3 n=normalize(vec3((wave(p-vec2(e,0.))-wave(p+vec2(e,0.)))/(2.*e),1.,(wave(p-vec2(0.,e))-wave(p+vec2(0.,e)))/(2.*e)));vec3 v=normalize(eye-world);float f=pow(1.-max(dot(n,v),0.),4.);vec3 r=reflect(-v,n);float spec=pow(max(dot(r,sun),0.),130.);float glint=pow(max(dot(r,sun),0.),18.);vec3 c=mix(vec3(.025,.105,.13),vec3(.43,.52,.56),f*.8)+light*(spec*2.6+glint*.07);float farHaze=1.-exp(-length(eye-world)*.0007);c=mix(c,vec3(.64,.60,.52),farHaze*.75);gl_FragColor=vec4(c,1.);}` }));
water.rotation.x=-Math.PI/2;water.position.y=.55;scene.add(water);
// Distant, representative Istanbul urban shoreline; not a surveyed city model.
let seed=167;const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)|0;return(seed>>>0)/4294967296;};
const city=new T.Group();scene.add(city);
const hillGeometry=new T.BufferGeometry(),vertices=[],indices=[];
for(let i=0;i<=100;i++){const x=-1400+i*28,h=25+32*Math.sin(i*.052)**2+12*Math.sin(i*.17);vertices.push(x,-1,-780,x,h,-850,x,-1,-1050);if(i<100){let a=i*3;indices.push(a,a+3,a+1,a+1,a+3,a+4,a+1,a+4,a+2,a+2,a+4,a+5);}}
hillGeometry.setAttribute('position',new T.Float32BufferAttribute(vertices,3));hillGeometry.setIndex(indices);hillGeometry.computeVertexNormals();city.add(new T.Mesh(hillGeometry,new T.MeshStandardMaterial({color:'#596667',roughness:1,side:T.DoubleSide})));
const buildings=new T.InstancedMesh(new T.BoxGeometry(1,1,1),new T.MeshStandardMaterial({color:'#8c9390',roughness:.92}),650),dummy=new T.Object3D();
for(let i=0;i<650;i++){const x=(random()-.5)*2700,z=-830-random()*170,h=4+random()*18;dummy.position.set(x,h/2+30+24*Math.sin((x+1400)/28*.052)**2,z);dummy.scale.set(5+random()*12,h,5+random()*10);dummy.updateMatrix();buildings.setMatrixAt(i,dummy.matrix);buildings.setColorAt(i,new T.Color().setHSL(.075+random()*.04,.08,.29+random()*.18));}city.add(buildings);
// Far silhouettes, kept deliberately outside close inspection range.
function mosque(x,z){const group=new T.Group(),m=new T.MeshStandardMaterial({color:'#677373',roughness:.9});
 const base=new T.Mesh(new T.BoxGeometry(26,12,22),m);base.position.y=16;group.add(base);const dome=new T.Mesh(new T.SphereGeometry(12,20,12,0,Math.PI*2,0,Math.PI/2),m);dome.position.y=22;group.add(dome);
 for(const dx of [-19,19]){const shaft=new T.Mesh(new T.CylinderGeometry(.9,1.4,48,8),m);shaft.position.set(dx,25,0);group.add(shaft);const cap=new T.Mesh(new T.ConeGeometry(1.6,7,8),m);cap.position.set(dx,52,0);group.add(cap);}group.position.set(x,42,z);city.add(group);}
mosque(-210,-860);mosque(250,-950);
// Auxiliary ferries: distant scale cues, no substitute for primary architecture.
const boats=[];function ferry(x,z,speed){const g=new T.Group(),hull=new T.Mesh(new T.BoxGeometry(18,1.8,5),new T.MeshStandardMaterial({color:'#34434b',roughness:.5}));hull.position.y=1;g.add(hull);
 const cabin=new T.Mesh(new T.BoxGeometry(12,2.2,4),new T.MeshStandardMaterial({color:'#d9d2bd',roughness:.7}));cabin.position.y=2.7;g.add(cabin);const glass=new T.Mesh(new T.BoxGeometry(11,.7,4.05),new T.MeshStandardMaterial({color:'#344f5c',roughness:.2,metalness:.3}));glass.position.y=3;g.add(glass);g.position.set(x,.2,z);scene.add(g);boats.push({g,x,z,speed});}
ferry(-100,-160,1.5);ferry(180,-320,-2);
let yaw=.74,pitch=.21,radius=76,wantedYaw=yaw,wantedPitch=pitch,wantedRadius=radius;
function reset(){wantedYaw=.74;wantedPitch=.21;wantedRadius=Math.max(76,innerHeight/innerWidth*100);intro=0;}
function resize(){renderer.setSize(innerWidth,innerHeight);camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();wantedRadius=Math.max(wantedRadius,innerHeight/innerWidth*100);}
function placeCamera(dt){const f=1-Math.exp(-dt*8);yaw+=(wantedYaw-yaw)*f;pitch+=(wantedPitch-pitch)*f;radius+=(wantedRadius-radius)*f;const a=yaw+(loaded?Math.max(0,1-intro/3)*.12:0);camera.position.set(target.x+Math.sin(a)*Math.cos(pitch)*radius,target.y+Math.sin(pitch)*radius,target.z+Math.cos(a)*Math.cos(pitch)*radius);camera.lookAt(target);}
const pointers=new Map();let previousPinch=0;
function down(e){renderer.domElement.setPointerCapture(e.pointerId);pointers.set(e.pointerId,[e.clientX,e.clientY]);previousPinch=0;intro=3;}
function move(e){const old=pointers.get(e.pointerId);if(!old)return;const dx=e.clientX-old[0],dy=e.clientY-old[1];pointers.set(e.pointerId,[e.clientX,e.clientY]);
 if(pointers.size===1){wantedYaw-=dx*.006;wantedPitch=T.MathUtils.clamp(wantedPitch+dy*.004,.08,.77);}else{const [a,b]=[...pointers.values()],d=Math.hypot(a[0]-b[0],a[1]-b[1]);if(previousPinch)wantedRadius=T.MathUtils.clamp(wantedRadius*previousPinch/d,48,160);previousPinch=d;}}
function up(e){pointers.delete(e.pointerId);previousPinch=0;}
function wheel(e){e.preventDefault();intro=3;wantedRadius=T.MathUtils.clamp(wantedRadius*Math.exp(e.deltaY*.001),48,160);}
const canvas=renderer.domElement;canvas.addEventListener('pointerdown',down);canvas.addEventListener('pointermove',move);canvas.addEventListener('pointerup',up);canvas.addEventListener('pointercancel',up);canvas.addEventListener('wheel',wheel,{passive:false});window.addEventListener('resize',resize);
const manager=new T.LoadingManager();manager.onProgress=(_,done,total)=>tell('progress:'+Math.round(35+done/total*60));manager.onError=fail;
tell('progress:10');
try{const text=atob(window.MAIDEN_GLB),bytes=new Uint8Array(text.length);for(let i=0;i<text.length;i++)bytes[i]=text.charCodeAt(i);delete window.MAIDEN_GLB;tell('progress:35');
new window.GLTFLoader(manager).parse(bytes.buffer,'',gltf=>{if(disposed){release(gltf.scene);return;}gltf.scene.traverse(o=>{if(o.isMesh){o.castShadow=o.receiveShadow=true;for(const m of [].concat(o.material)){for(const k of ['map','normalMap','roughnessMap','metalnessMap','aoMap'])if(m[k])m[k].anisotropy=Math.min(4,renderer.capabilities.getMaxAnisotropy());}}});scene.add(gltf.scene);loaded=true;intro=0;tell('ready');},fail);
}catch(e){console.error(e);fail();}
function release(root){const geometries=new Set(),materials=new Set(),textures=new Set();root.traverse(o=>{if(o.geometry)geometries.add(o.geometry);for(const m of [].concat(o.material||[])){materials.add(m);for(const value of Object.values(m))if(value?.isTexture)textures.add(value);}});for(const x of textures){x.source?.data?.close?.();x.dispose();}for(const x of materials)x.dispose();for(const x of geometries)x.dispose();}
function pause(value){paused=value;last=performance.now();if(value){cancelAnimationFrame(frame);pointers.clear();previousPinch=0;}else if(!disposed){cancelAnimationFrame(frame);frame=requestAnimationFrame(render);}}
function render(now){if(disposed||paused)return;const dt=Math.min((now-last)/1000,.05);last=now;elapsed+=dt;if(loaded)intro+=dt;waterUniforms.time.value=elapsed;for(const b of boats){b.g.position.x=b.x+Math.sin(elapsed*.008)*b.speed*45;b.g.position.y=.2+Math.sin(elapsed+b.x)*.08;}placeCamera(dt);renderer.render(scene,camera);frame=requestAnimationFrame(render);}
window.journey={reset,back:()=>tell('exit'),pause,dispose(){if(disposed)return;disposed=true;cancelAnimationFrame(frame);window.removeEventListener('resize',resize);window.removeEventListener('error',fail);for(const [event,handler]of [['pointerdown',down],['pointermove',move],['pointerup',up],['pointercancel',up],['wheel',wheel]])canvas.removeEventListener(event,handler);pointers.clear();release(scene);environment.dispose();renderer.dispose();renderer.forceContextLoss();canvas.remove();}};
window.journeyDiagnostics=()=>({loaded,disposed,paused,triangles:renderer.info.render.triangles,calls:renderer.info.render.calls,geometries:renderer.info.memory.geometries,textures:renderer.info.memory.textures,camera:camera.position.toArray(),radius,wantedRadius,pitch,wantedPitch,elapsed});
reset();placeCamera(1);frame=requestAnimationFrame(render);
})();
