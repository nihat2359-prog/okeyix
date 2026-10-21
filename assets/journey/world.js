/* Offline country → city → place scene manager. Geographic coordinates in km.
   Terrain: sampled DEM, not procedural mountains. Labels are 3D sprites picked
   in world space, with screen-size/collision control for small touch screens. */
(() => {
  'use strict';
  const T=THREE,G=JourneyGeography,P=JourneyPlaces;
  const tell=m=>window.Journey?.postMessage(m);
  let destroyed=false,paused=false,raf=0,last=0,clock=0,level='turkey',place=null,transition=null;
  let scene,root,water,sun,palette,models=[],labels=[],pickables=[],retired=0,buildSerial=0;
  let activeCity=null,cityData=null,sceneResources=new Set(),environmentTarget=null,vessel=null;
  const renderer=new T.WebGLRenderer({antialias:true,powerPreference:'high-performance'});
  const maxDpr=Math.min(devicePixelRatio||1,1.5);renderer.setPixelRatio(maxDpr);renderer.setSize(innerWidth,innerHeight);
  renderer.outputColorSpace=T.SRGBColorSpace;renderer.toneMapping=T.ACESFilmicToneMapping;renderer.toneMappingExposure=1.1;
  renderer.shadowMap.enabled=true;renderer.shadowMap.type=T.PCFSoftShadowMap;document.body.appendChild(renderer.domElement);
  const camera=new T.PerspectiveCamera(42,innerWidth/innerHeight,.1,10000);
  const current={target:new T.Vector3(),radius:2200,yaw:-.15,pitch:1.05};let desired={...current,target:current.target.clone()};
  const canvas=renderer.domElement,ray=new T.Raycaster(),pointer=new T.Vector2(),pointers=new Map();
  const veil=document.createElement('div');Object.assign(veil.style,{position:'fixed',inset:'0',background:'#c8d4d7',opacity:'0',pointerEvents:'none',zIndex:'2'});document.body.appendChild(veil);let veilOpacity=0;
  let dragging=0,pinch=0,slowFrames=0,reduced=false;
  function state(){tell('state:'+JSON.stringify({level,title:place?.name||(level==='city'?activeCity.name:'Türkiye'),
    cityName:activeCity?.name||null,venue:place?.id||null,district:place?.district||null,transitioning:!!transition}));}
  function project(lon,lat,origin){return[(lon-origin[0])*111.32*Math.cos(origin[1]*Math.PI/180),-(lat-origin[1])*111.32];}
  function height(data,lon,lat){
    const {bounds:b,width:w,height:h,values:v}=data;
    const x=T.MathUtils.clamp((lon-b[0])/(b[2]-b[0])*(w-1),0,w-1),y=T.MathUtils.clamp((lat-b[1])/(b[3]-b[1])*(h-1),0,h-1);
    const i=Math.min(w-2,Math.floor(x)),j=Math.min(h-2,Math.floor(y)),a=x-i,c=y-j;
    return T.MathUtils.lerp(T.MathUtils.lerp(v[j*w+i],v[j*w+i+1],a),T.MathUtils.lerp(v[(j+1)*w+i],v[(j+1)*w+i+1],a),c);
  }
  function inside(lon,lat,polygons){
    function ring(r){let hit=false;for(let i=0,j=r.length-1;i<r.length;j=i++){const a=r[i],b=r[j];if((a[1]>lat)!==(b[1]>lat)&&lon<(b[0]-a[0])*(lat-a[1])/(b[1]-a[1])+a[0])hit=!hit;}return hit;}
    return polygons.some(p=>ring(p[0])&&!p.slice(1).some(ring));
  }
  function disposeScene(){
    if(!scene)return;
    const geometries=new Set(),materials=new Set(),textures=new Set();
    scene.traverse(o=>{if(o.geometry)geometries.add(o.geometry);if(o.isInstancedMesh)o.dispose();if(o.material)(Array.isArray(o.material)?o.material:[o.material]).forEach(m=>{materials.add(m);Object.values(m).forEach(v=>{if(v?.isTexture)textures.add(v);});});if(o.isLight&&o.shadow)o.shadow.dispose();});
    sceneResources.forEach(t=>textures.add(t));sceneResources.clear();
    geometries.forEach(g=>g.dispose());materials.forEach(m=>m.dispose());textures.forEach(t=>t.dispose());
    environmentTarget?.dispose();environmentTarget=null;
    renderer.renderLists.dispose();retired++;models=[];labels=[];pickables=[];palette=null;vessel=null;scene.clear();
  }
  function base(city){
    disposeScene();buildSerial++;scene=new T.Scene();scene.background=new T.Color(city?'#aab9bc':'#153845');
    scene.fog=new T.FogExp2(city?'#aab9bc':'#537a88',city?.015:.00017);
    root=new T.Group();scene.add(root);
    sun=new T.DirectionalLight('#fff0d5',2.4);sun.position.set(city?-8:-650,city?18:850,city?10:900);
    sun.castShadow=true;sun.shadow.mapSize.set(1024,1024);sun.shadow.normalBias=city?.002:.08;
    const radius=city?16:1300;Object.assign(sun.shadow.camera,{left:-radius,right:radius,top:radius,bottom:-radius,near:city?.01:1,far:city?90:5000});
    scene.add(sun,sun.target,new T.HemisphereLight('#c5dded','#7b775d',1.1));
    if(city){
      const skyMaterial=new T.ShaderMaterial({side:T.BackSide,depthWrite:false,
        vertexShader:'varying vec3 p;void main(){p=position;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}',
        fragmentShader:'varying vec3 p;void main(){float h=max(0.,normalize(p).y);gl_FragColor=vec4(mix(vec3(.62,.72,.75),vec3(.12,.32,.52),pow(h,.5)),1.);}'});
      const sky=new T.Mesh(new T.SphereGeometry(65,24,12),skyMaterial);sky.renderOrder=-10;scene.add(sky);
      const environment=new T.Scene();environment.add(new T.Mesh(new T.SphereGeometry(5,16,8),skyMaterial));
      const pmrem=new T.PMREMGenerator(renderer);environmentTarget=pmrem.fromScene(environment,.04,.1,20);scene.environment=environmentTarget.texture;pmrem.dispose();environment.children[0].geometry.dispose();
    }
    // Rendered geometry water, analytic normals/specular. No backdrop image.
    const geo=new T.PlaneGeometry(city?100:7000,city?100:7000,1,1);
    const material=new T.ShaderMaterial({extensions:{derivatives:true},uniforms:{time:{value:0},scale:{value:city?1:180}},
      vertexShader:'varying vec3 p;void main(){p=position;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}',
      fragmentShader:`varying vec3 p;uniform float time;uniform float scale;
        float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
        float noise(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);}
        void main(){vec2 q=p.xy/scale;float detail=1.-smoothstep(.002,.025,length(fwidth(q)));
        float n=noise(q*vec2(18.,65.)+time*.06)*.65+noise(q*vec2(64.,210.)-time*.09)*.35;
        float crest=pow(max(0.,sin(q.y*1900.+q.x*90.+time+n*6.)),22.)*detail;
        vec3 c=mix(vec3(.035,.17,.215),vec3(.09,.29,.34),mix(.48,n,detail));c+=crest*.045*vec3(1.,.9,.68);gl_FragColor=vec4(c,1.);}`});
    water=new T.Mesh(geo,material);water.rotation.x=-Math.PI/2;water.position.y=-.001;scene.add(water);
  }
  function terrain(data,origin,city){
    const positions=[],normals=[],colors=[],walls=[];
    const exaggeration=city?1.5:12;
    const vertex=(ll,boundary=false)=>{
      const [x,z]=project(...ll,origin),metres=Math.max(0,height(data.dem,...ll)),y=metres/1000*exaggeration+.002;
      const step=city?.0007:.03,dx=111.32*Math.cos(origin[1]*Math.PI/180)*step*2,dz=111.32*step*2;
      const nx=-(height(data.dem,ll[0]+step,ll[1])-height(data.dem,ll[0]-step,ll[1]))/1000*exaggeration/dx;
      const nz=(height(data.dem,ll[0],ll[1]+step)-height(data.dem,ll[0],ll[1]-step))/1000*exaggeration/dz;
      const normal=new T.Vector3(nx,1,nz).normalize();
      let color=new T.Color('#66795a');
      if(!city){color.lerp(new T.Color('#aa9876'),T.MathUtils.clamp((metres-500)/2600,0,1));if(metres>3000)color.lerp(new T.Color('#e6e7de'),(metres-3000)/1500);}
      else color.lerp(new T.Color('#8a8b75'),.4);
      positions.push(x,y,z);normals.push(...normal.toArray());colors.push(color.r,color.g,color.b);
    };
    const maxEdge=city?.17:15;
    function subdivide(a,b,c,depth=0){
      const ab=project(b[0],b[1],a),bc=project(c[0],c[1],b),ca=project(a[0],a[1],c);
      const lengths=[Math.hypot(...ab),Math.hypot(...bc),Math.hypot(...ca)],longest=Math.max(...lengths);
      if(longest<maxEdge||depth>18){vertex(a);vertex(b);vertex(c);return;}
      const middle=(a,b)=>[(a[0]+b[0])/2,(a[1]+b[1])/2];
      if(lengths[0]===longest){const m=middle(a,b);subdivide(a,m,c,depth+1);subdivide(m,b,c,depth+1);}
      else if(lengths[1]===longest){const m=middle(b,c);subdivide(a,b,m,depth+1);subdivide(a,m,c,depth+1);}
      else {const m=middle(c,a);subdivide(a,b,m,depth+1);subdivide(m,b,c,depth+1);}
    }
    for(const polygon of data.polygons){
      const contour=polygon[0].slice(0,-1).map(p=>new T.Vector2(...p)),holes=polygon.slice(1).map(r=>r.slice(0,-1).map(p=>new T.Vector2(...p)));
      const all=[...contour,...holes.flat()],triangles=T.ShapeUtils.triangulateShape(contour,holes);
      for(const indices of triangles)subdivide(...indices.map(i=>all[i].toArray()));
      for(const ring of polygon)for(let i=0;i<ring.length-1;i++){
        const a=ring[i],b=ring[i+1],[x,z]=project(...a,origin),[xx,zz]=project(...b,origin);
        const y=Math.max(0,height(data.dem,...a))/1000*exaggeration+.002,yy=Math.max(0,height(data.dem,...b))/1000*exaggeration+.002;
        walls.push(x,0,z,xx,0,zz,x,y,z,x,y,z,xx,0,zz,xx,yy,zz);
      }
    }
    const geo=new T.BufferGeometry();geo.setAttribute('position',new T.Float32BufferAttribute(positions,3));geo.setAttribute('normal',new T.Float32BufferAttribute(normals,3));geo.setAttribute('color',new T.Float32BufferAttribute(colors,3));
    const land=new T.Mesh(geo,new T.MeshStandardMaterial({vertexColors:true,roughness:.97,side:T.DoubleSide}));land.castShadow=!city;land.receiveShadow=true;root.add(land);
    const side=new T.BufferGeometry();side.setAttribute('position',new T.Float32BufferAttribute(walls,3));side.computeVertexNormals();root.add(new T.Mesh(side,new T.MeshStandardMaterial({color:'#988a72',roughness:1,side:T.DoubleSide})));
  }
  function sprite(text,kind,id,anchor,priority=1){
    const c=document.createElement('canvas');c.width=512;c.height=128;const g=c.getContext('2d');
    const active=kind==='place'||id==='TUR034';g.lineWidth=3;
    if(active){
      const gradient=g.createLinearGradient(0,7,0,110);gradient.addColorStop(0,'rgba(30,53,51,.97)');gradient.addColorStop(1,'rgba(10,29,31,.96)');g.fillStyle=gradient;g.strokeStyle='#ccb17a';
      // Engraved world plaque with a small anchor notch, not a DOM button.
      g.beginPath();g.moveTo(28,8);g.lineTo(484,8);g.quadraticCurveTo(505,8,505,28);g.lineTo(505,88);g.quadraticCurveTo(505,108,484,108);g.lineTo(272,108);g.lineTo(256,123);g.lineTo(240,108);g.lineTo(28,108);g.quadraticCurveTo(7,108,7,88);g.lineTo(7,28);g.quadraticCurveTo(7,8,28,8);g.fill();g.stroke();
      g.fillStyle='#eed298';g.fillRect(28,29,3,59);g.fillRect(481,29,3,59);
    }
    g.shadowColor='#041319';g.shadowBlur=active?0:8;g.shadowOffsetY=2;
    g.fillStyle=active?'#efd59b':kind==='sea'?'#abc8cf':'#e2e7d9';g.font=kind==='place'?'600 51px Georgia':'600 51px sans-serif';g.textAlign='center';g.textBaseline='middle';g.fillText(text,256,61,450);
    const texture=new T.CanvasTexture(c);texture.colorSpace=T.SRGBColorSpace;
    const o=new T.Sprite(new T.SpriteMaterial({map:texture,transparent:true,depthTest:false,depthWrite:false}));o.renderOrder=10;scene.add(o);
    const lineGeo=new T.BufferGeometry().setFromPoints([anchor,anchor]);const line=new T.Line(lineGeo,new T.LineBasicMaterial({color:active?'#d8bd7f':'#8ca39c',transparent:true,opacity:.65,depthTest:false}));line.renderOrder=9;scene.add(line);
    const item={id,kind,anchor:anchor.clone(),sprite:o,line,priority,width:kind==='sea'?90:kind==='place'?112:84,height:kind==='place'?29:24,screen:null};labels.push(item);return item;
  }
  function setDesired(settings,instant=false){
    desired={target:new T.Vector3(...settings.target),radius:settings.radius,yaw:settings.yaw,pitch:settings.pitch};
    if(instant){current.target.copy(desired.target);current.radius=desired.radius*1.14;current.yaw=desired.yaw-.045;current.pitch=desired.pitch+.03;}
  }
  function country(){
    level='turkey';place=null;activeCity=null;base(false);camera.near=1;camera.far=10000;camera.updateProjectionMatrix();
    const origin=[35.25,39];terrain(G.country,origin,false);
    // Neutral neighbouring land avoids falsely depicting land borders as sea.
    const contextMaterial=new T.MeshStandardMaterial({color:'#5c6d61',roughness:1,side:T.DoubleSide,depthTest:false,depthWrite:false});
    for(const polygon of G.country.context||[]){const shape=new T.Shape(polygon[0].slice(0,-1).map(ll=>{const [x,z]=project(...ll,origin);return new T.Vector2(x,-z);}));const geometry=new T.ShapeGeometry(shape);geometry.rotateX(-Math.PI/2);const land=new T.Mesh(geometry,contextMaterial);land.position.y=.001;land.renderOrder=1;scene.add(land);}
    batch(scene,new Set([root]));
    root.renderOrder=2; // Neutral flat context is a map layer, not sea-depth geometry.
    for(const city of G.country.cities){const [x,z]=project(city.lon,city.lat,origin),y=Math.max(0,height(G.country.dem,city.lon,city.lat))/1000*12+5;sprite(city.name,'city',city.id,new T.Vector3(x,y,z),city.priority);}
    for(const [name,lon,lat] of [['KARADENİZ',35,43],['MARMARA',28.2,40.5],['EGE',25,38.5],['AKDENİZ',32.5,35.6]]){const [x,z]=project(lon,lat,origin);sprite(name,'sea',name,new T.Vector3(x,2,z),-1);}
    const fit=Math.max(1750,900/camera.aspect+800);setDesired({target:[0,0,0],radius:fit,yaw:-.12,pitch:1.02},true);state();
  }
  function addBridge(a,b){
    const A=new T.Vector3(...a),B=new T.Vector3(...b),length=A.distanceTo(B),mid=A.clone().add(B).multiplyScalar(.5),group=new T.Group();group.position.copy(mid);group.rotation.y=-Math.atan2(B.z-A.z,B.x-A.x);root.add(group);
    function box(w,h,d,x,y,z){const o=new T.Mesh(new T.BoxGeometry(w,h,d),palette.light);o.position.set(x,y,z);o.castShadow=true;group.add(o);}
    function beam(a,b,r){const d=b.clone().sub(a),o=new T.Mesh(new T.CylinderGeometry(r,r,d.length(),6),palette.bronze);o.position.copy(a.clone().add(b).multiplyScalar(.5));o.quaternion.setFromUnitVectors(new T.Vector3(0,1,0),d.normalize());group.add(o);}
    box(length,.008,.033,0,.064,0);
    for(const x of [-length*.32,length*.32]){for(const z of [-.023,.023])box(.009,.165,.009,x,.083,z);box(.014,.009,.057,x,.153,0);}
    const cable=x=>.082+.073*Math.min(1,(x/(length*.32))**2);
    for(const z of [-.021,.021])for(let x=-length*.48;x<length*.48;x+=length/52){const next=x+length/52;beam(new T.Vector3(x,cable(x),z),new T.Vector3(next,cable(next),z),.001);beam(new T.Vector3(x,.064,z),new T.Vector3(x,cable(x),z),.00045);}
  }
  function city(id='istanbul'){
    const definition=P.cities[id],geography=G[id];if(!definition||!geography)throw Error('City scene assets missing: '+id);
    level='city';place=null;activeCity=definition;cityData=geography;base(true);palette=JourneyModels.palette();palette.textures.forEach(t=>sceneResources.add(t));Object.values(palette).filter(m=>m?.isMaterial).forEach(m=>m.envMapIntensity=.35);
    camera.near=.004;camera.far=180;camera.updateProjectionMatrix();terrain(cityData,activeCity.origin,true);
    // Repeated urban context uses instancing. Placement follows land polygons;
    // these blocks are illustrative urban grain, not individual surveyed houses.
    let seed=91;const rnd=()=>{seed=(Math.imul(seed,1664525)+1013904223)|0;return(seed>>>0)/4294967296;};
    const matrices=[],roofMatrices=[],dummy=new T.Object3D(),bounds=cityData.bounds;
    for(let i=0;i<8500;i++){
      const lon=bounds[0]+rnd()*(bounds[2]-bounds[0]),lat=bounds[1]+rnd()*(bounds[3]-bounds[1]);if(!inside(lon,lat,cityData.polygons))continue;
      const [x,z]=project(lon,lat,activeCity.origin);
      if(activeCity.places.some(p=>Math.hypot(...project(lon,lat,[p.lon,p.lat]))<.19))continue;
      const y=Math.max(0,height(cityData.dem,lon,lat))/1000*1.5,h=.018+rnd()*.045,w=.035+rnd()*.055;
      dummy.position.set(x,y+h/2,z);dummy.scale.set(w,h,w*.8);dummy.rotation.y=Math.floor(rnd()*4)*Math.PI/4;dummy.updateMatrix();matrices.push(dummy.matrix.clone());
      dummy.position.y=y+h+.003;dummy.scale.set(w*1.03,.006,w*.83);dummy.updateMatrix();roofMatrices.push(dummy.matrix.clone());
    }
    const instanced=new T.InstancedMesh(new T.BoxGeometry(1,1,1),palette.light,matrices.length);matrices.forEach((m,i)=>{instanced.setMatrixAt(i,m);instanced.setColorAt(i,new T.Color().setHSL(.09,.07,.51+(i%7)*.025));});root.add(instanced);
    const roofs=new T.InstancedMesh(new T.ConeGeometry(.71,1,4),palette.roof,roofMatrices.length);roofMatrices.forEach((m,i)=>roofs.setMatrixAt(i,m));root.add(roofs);
    for(const definition of activeCity.places){
      const model=JourneyModels.create(definition.model,palette),[x,z]=project(definition.lon,definition.lat,activeCity.origin);
      const altitude=definition.altitude===0?0:Math.max(definition.altitude/1000,Math.max(0,height(cityData.dem,definition.lon,definition.lat))/1000*1.5)+.003;
      model.group.position.set(x,altitude,z);model.group.scale.setScalar(.012);root.add(model.group);model.definition=definition;model.anchor=new T.Vector3(x,altitude,z);models.push(model);pickables.push(model.group);
      model.height=(new T.Box3().setFromObject(model.group).max.y-altitude)/.012;
      sprite(definition.name,'place',definition.id,model.anchor.clone().add(new T.Vector3(0,model.height*.012,0)),10);
    }
    for(const bridge of activeCity.bridges||[]){const point=([lon,lat])=>{const [x,z]=project(lon,lat,activeCity.origin);return[x,0,z];};addBridge(point(bridge[0]),point(bridge[1]));}
    // A small moving Bosphorus ferry provides scale in the close view. Its
    // path stays in the channel west of Maiden's Tower; no game simulation.
    if(activeCity.ferry){vessel=new T.Group();root.add(vessel);
    function boatBox(w,h,d,mat,x,y,z){const o=new T.Mesh(new T.BoxGeometry(w,h,d),mat);o.position.set(x/1000,y/1000,z/1000);o.scale.setScalar(.001);vessel.add(o);}
    const hull=new T.Shape();hull.moveTo(-18,-3.5);hull.lineTo(13,-3.5);hull.quadraticCurveTo(21,0,13,3.5);hull.lineTo(-18,3.5);hull.closePath();
    const hullMesh=new T.Mesh(new T.ExtrudeGeometry(hull,{depth:1.9,bevelEnabled:true,bevelSize:.35,bevelThickness:.3,bevelSegments:2}),palette.light);hullMesh.rotation.x=-Math.PI/2;hullMesh.scale.setScalar(.001);vessel.add(hullMesh);
    boatBox(27,2.6,6.4,palette.light,-1,3.4,0);boatBox(29,.25,7.3,palette.slate,-1,4.8,0);
    boatBox(19,2.3,5.5,palette.light,-2,6,0);boatBox(22,.3,6.5,palette.light,-2,7.3,0);
    boatBox(1.6,3,1.6,palette.bronze,-5,8,0);boatBox(1.7,.7,1.7,palette.dark,-5,9.6,0);
    for(let x=-12;x<11;x+=2)for(const z of [-3.23,3.23])boatBox(1.25,1.1,.08,palette.glass,x,3.6,z);
    batch(vessel);}
    batch(root,new Set([...models.map(m=>m.group),...(vessel?[vessel]:[])]));models.forEach(m=>batch(m.group,new Set([m.detail])));
    setDesired(cityCamera(),true);state();
  }
  function cityCamera(){return {...activeCity.camera,radius:activeCity.camera.radius*Math.max(1,440/innerHeight)};}
  // Static batching keeps detailed architecture inexpensive on mobile.
  function batch(parent,excluded=new Set()){
    parent.updateMatrixWorld(true);const inverse=parent.matrixWorld.clone().invert(),groups=new Map();
    function walk(o){if(excluded.has(o)||o.isInstancedMesh)return;if(o.isMesh&&o.material.isMeshStandardMaterial&&!o.material.vertexColors){const key=o.material.uuid+'/'+o.castShadow;if(!groups.has(key))groups.set(key,[]);groups.get(key).push(o);}[...o.children].forEach(walk);}
    [...parent.children].forEach(walk);
    for(const objects of groups.values()){
      if(objects.length<2)continue;const p=[],n=[],uv=[];
      for(const o of objects){const g=o.geometry.index?o.geometry.toNonIndexed():o.geometry.clone();g.applyMatrix4(inverse.clone().multiply(o.matrixWorld));for(const [name,array] of [['position',p],['normal',n],['uv',uv]]){const a=g.getAttribute(name);if(a)for(const v of a.array)array.push(v);}g.dispose();o.geometry.dispose();o.removeFromParent();}
      const g=new T.BufferGeometry();g.setAttribute('position',new T.Float32BufferAttribute(p,3));g.setAttribute('normal',new T.Float32BufferAttribute(n,3));g.setAttribute('uv',new T.Float32BufferAttribute(uv,2));const o=new T.Mesh(g,objects[0].material);o.castShadow=objects[0].castShadow;o.receiveShadow=true;o.renderOrder=objects[0].renderOrder;parent.add(o);
    }
  }
  function fly(destination,onComplete,duration=1.4,swap=false){
    if(transition)return;transition={elapsed:0,duration,from:{target:current.target.clone(),radius:current.radius,yaw:current.yaw,pitch:current.pitch},to:destination,onComplete,swap};state();
  }
  function selectCity(id){
    if(transition)return;const def=G.country.cities.find(c=>c.id===id);if(!def)return;
    if(!def.scene||!P.cities[def.scene]||!G[def.scene]){tell('notice:'+def.name+' henüz keşfe açılmadı.');return;}
    const [x,z]=project(def.lon,def.lat,[35.25,39]);fly({target:new T.Vector3(x,0,z),radius:26,yaw:-.1,pitch:1.02},()=>{city(def.scene);},1.65,true);
  }
  function selectPlace(id){
    if(transition||level==='turkey')return;const model=models.find(m=>m.definition.id===id);if(!model)return;
    place=model.definition;level='place';model.enableDetail();batch(model.detail);models.filter(m=>m!==model).forEach(m=>m.disableDetail());
    const anchor=model.anchor.clone();anchor.y+=.015;anchor.add(new T.Vector3(Math.cos(place.yaw),0,-Math.sin(place.yaw)).multiplyScalar(place.radius*.23));
    fly({target:anchor,radius:place.radius,yaw:place.yaw,pitch:place.pitch},()=>state(),1.65);
    const r=.35;sun.position.copy(anchor).add(new T.Vector3(-.15,.3,.2));sun.target.position.copy(anchor);
    Object.assign(sun.shadow.camera,{left:-r,right:r,top:r,bottom:-r,near:.005,far:2});sun.shadow.camera.updateProjectionMatrix();sun.shadow.normalBias=.00008;
    camera.near=.0003;camera.updateProjectionMatrix();
  }
  function back(){
    if(transition)return;
    if(level==='place'){
      place=null;level='city';
      fly({...cityCamera(),target:new T.Vector3(...activeCity.camera.target)},()=>{models.forEach(m=>m.disableDetail());sun.position.set(-8,18,10);sun.target.position.set(0,0,0);Object.assign(sun.shadow.camera,{left:-16,right:16,top:16,bottom:-16,near:.01,far:90});sun.shadow.camera.updateProjectionMatrix();sun.shadow.normalBias=.002;state();});
    }else if(level==='city')fly({target:new T.Vector3(),radius:55,yaw:-.25,pitch:1.02},country,1.2,true);
    else tell('exit');
  }
  function limits(){return level==='turkey'?{min:500,max:3200,pitch:[.65,1.35]}:level==='city'?{min:9,max:34,pitch:[.55,1.3]}:{min:place.radius*.7,max:place.radius*1.7,pitch:[.2,.9]};}
  function reset(){if(transition)return;if(level==='turkey')setDesired({target:[0,0,0],radius:Math.max(1750,900/camera.aspect+800),yaw:-.12,pitch:1.02});else if(level==='city')setDesired(cityCamera());else {const target=models.find(m=>m.definition.id===place.id).anchor.clone().add(new T.Vector3(0,.015,0));target.add(new T.Vector3(Math.cos(place.yaw),0,-Math.sin(place.yaw)).multiplyScalar(place.radius*.23));setDesired({target:target.toArray(),radius:place.radius,yaw:place.yaw,pitch:place.pitch});}}
  function labelLayout(){
    const occupied=[],worldPerPixel=2*Math.tan(camera.fov*Math.PI/360)*current.radius/innerHeight;
    const sorted=labels.slice().sort((a,b)=>b.priority-a.priority);
    for(const label of sorted){
      if(label.kind==='place'){const m=models.find(m=>m.definition.id===label.id);label.anchor.y=m.anchor.y+m.height*m.group.scale.x;}
      const projected=label.anchor.clone().project(camera);let x=(projected.x+1)*innerWidth/2,y=(1-projected.y)*innerHeight/2;
      if(label.kind==='place')y-=20;
      let visible=projected.z<1&&projected.z>-1&&x>4&&x<innerWidth-4&&y>(label.kind==='place'?0:58)&&y<innerHeight-30;
      if(level==='place')visible=visible&&label.id===place.id;
      if(label.kind==='city'&&label.priority<2&&current.radius>1350)visible=false;
      const w=label.width,h=label.height;
      x=T.MathUtils.clamp(x,w/2+10,innerWidth-w/2-10);
      if(visible){
        let found=false;
        search: for(const offsetX of label.kind==='place'?[0,-120,120,-240,240]:[0])for(const offset of label.kind==='place'?[0,-38,38,-76,76,-114,114]:[0]){
          const xx=T.MathUtils.clamp(x+offsetX,w/2+10,innerWidth-w/2-10),yy=label.kind==='place'?T.MathUtils.clamp(y+offset,85,innerHeight-54):y+offset;
          const box={left:xx-w/2-3,right:xx+w/2+3,top:yy-h/2-4,bottom:yy+h/2+4};
          if(yy>70&&yy<innerHeight-36&&!occupied.some(o=>box.left<o.right&&box.right>o.left&&box.top<o.bottom&&box.bottom>o.top)){occupied.push(box);x=xx;y=yy;found=true;break search;}
        }visible=found;
      }
      label.sprite.visible=label.line.visible=visible;label.screen=visible?{x,y,w,h}:null;if(!visible)continue;
      const location=new T.Vector3(x/innerWidth*2-1,1-y/innerHeight*2,projected.z).unproject(camera);
      label.sprite.position.copy(location);const depth=location.distanceTo(camera.position),scale=2*Math.tan(camera.fov*Math.PI/360)*depth/innerHeight;
      label.sprite.scale.set(w*scale,h*scale,1);
      const a=label.line.geometry.attributes.position;a.setXYZ(0,...label.anchor.toArray());a.setXYZ(1,...location.toArray());a.needsUpdate=true;
    }
  }
  canvas.addEventListener('pointerdown',e=>{canvas.setPointerCapture(e.pointerId);pointers.set(e.pointerId,[e.clientX,e.clientY]);dragging=0;pinch=0;});
  canvas.addEventListener('pointermove',e=>{
    if(!pointers.has(e.pointerId)||transition)return;const old=pointers.get(e.pointerId),dx=e.clientX-old[0],dy=e.clientY-old[1];pointers.set(e.pointerId,[e.clientX,e.clientY]);dragging+=Math.abs(dx)+Math.abs(dy);const l=limits();
    if(pointers.size===2){const [a,b]=[...pointers.values()],distance=Math.hypot(a[0]-b[0],a[1]-b[1]);if(pinch)desired.radius=T.MathUtils.clamp(desired.radius*pinch/Math.max(1,distance),l.min,l.max);pinch=distance;}
    else {desired.yaw=T.MathUtils.clamp(desired.yaw-dx*.003,-Math.PI,Math.PI);desired.pitch=T.MathUtils.clamp(desired.pitch+dy*.003,...l.pitch);}
  });
  canvas.addEventListener('pointerup',e=>{
    if(pointers.size===1&&dragging<10&&!transition){
      const hit=labels.filter(l=>l.screen&&l.kind!=='sea').find(l=>Math.abs(e.clientX-l.screen.x)<l.screen.w/2+6&&Math.abs(e.clientY-l.screen.y)<22);
      if(hit){if(hit.kind==='city')selectCity(hit.id);else selectPlace(hit.id);}
      else if(level!=='turkey'){pointer.set(e.clientX/innerWidth*2-1,1-e.clientY/innerHeight*2);ray.setFromCamera(pointer,camera);const hits=ray.intersectObjects(pickables,true);if(hits.length){let object=hits[0].object;while(object.parent&&!models.find(m=>m.group===object))object=object.parent;const m=models.find(m=>m.group===object);if(m)selectPlace(m.definition.id);}}
    }pointers.delete(e.pointerId);pinch=0;
  });
  canvas.addEventListener('pointercancel',e=>{pointers.delete(e.pointerId);pinch=0;});
  canvas.addEventListener('wheel',e=>{e.preventDefault();if(transition)return;const l=limits();desired.radius=T.MathUtils.clamp(desired.radius*Math.exp(e.deltaY*.001),l.min,l.max);},{passive:false});
  function resize(){camera.aspect=innerWidth/innerHeight;camera.updateProjectionMatrix();renderer.setSize(innerWidth,innerHeight);if(level==='city'&&!transition)setDesired(cityCamera());}
  addEventListener('resize',resize);
  function animate(now){
    if(paused||destroyed)return;raf=requestAnimationFrame(animate);const realDt=(now-(last||now))/1000,dt=Math.min(realDt,.06);last=now;clock+=dt;
    if(realDt>.045)slowFrames++;else slowFrames=Math.max(0,slowFrames-1);
    if(slowFrames>100&&!reduced){renderer.setPixelRatio(1);renderer.setSize(innerWidth,innerHeight);reduced=true;}
    if(transition){const t=transition;t.elapsed+=dt;const a=T.MathUtils.clamp(t.elapsed/t.duration,0,1),e=a*a*a*(a*(a*6-15)+10);if(t.swap)veilOpacity=T.MathUtils.smoothstep(a,.7,1);current.target.lerpVectors(t.from.target,t.to.target,e);current.radius=T.MathUtils.lerp(t.from.radius,t.to.radius,e);current.yaw=T.MathUtils.lerp(t.from.yaw,t.to.yaw,e);current.pitch=T.MathUtils.lerp(t.from.pitch,t.to.pitch,e);desired={...current,target:current.target.clone()};if(a===1){transition=null;t.onComplete?.();state();}}
    else {const a=1-Math.exp(-dt*5);current.target.lerp(desired.target,a);current.radius=T.MathUtils.lerp(current.radius,desired.radius,a);current.yaw=T.MathUtils.lerp(current.yaw,desired.yaw,a);current.pitch=T.MathUtils.lerp(current.pitch,desired.pitch,a);}
    if(!transition)veilOpacity=Math.max(0,veilOpacity-dt*2.3);veil.style.opacity=String(veilOpacity);
    // Match depth precision to kilometre-scale maps and metre-scale closeups.
    // A fixed tiny near plane makes distant coastline and sea z-fight.
    const near=level==='turkey'?current.radius/8:Math.max(.0003,current.radius/1500);if(Math.abs(camera.near-near)>.00001){camera.near=near;camera.updateProjectionMatrix();}
    camera.position.set(current.target.x+Math.sin(current.yaw)*Math.cos(current.pitch)*current.radius,current.target.y+Math.sin(current.pitch)*current.radius,current.target.z+Math.cos(current.yaw)*Math.cos(current.pitch)*current.radius);
    if(level==='place'){
      const lon=activeCity.origin[0]+camera.position.x/(111.32*Math.cos(activeCity.origin[1]*Math.PI/180)),lat=activeCity.origin[1]-camera.position.z/111.32;
      const floor=inside(lon,lat,cityData.polygons)?Math.max(0,height(cityData.dem,lon,lat))/1000*1.5:0;
      camera.position.y=Math.max(camera.position.y,floor+.005);
    }
    camera.lookAt(current.target);camera.updateMatrixWorld();
    models.forEach(m=>{const t=T.MathUtils.smoothstep(camera.position.distanceTo(m.anchor),.5,3),scale=T.MathUtils.lerp(.001,.012,t);m.group.scale.setScalar(scale);});
    if(vessel){const [x,z]=project(...activeCity.ferry.anchor,activeCity.origin);vessel.position.set(x,.0002+Math.sin(clock*1.3)*.0001,z+Math.sin(clock*.025)*activeCity.ferry.range);vessel.rotation.y=Math.PI/2;vessel.rotation.z=Math.sin(clock*.8)*.004;}
    water.material.uniforms.time.value=clock;labelLayout();renderer.render(scene,camera);
  }
  function pause(value){paused=value;cancelAnimationFrame(raf);last=0;if(!paused&&!destroyed)raf=requestAnimationFrame(animate);}
  function dispose(){if(destroyed)return;destroyed=true;cancelAnimationFrame(raf);disposeScene();renderer.dispose();renderer.forceContextLoss();removeEventListener('resize',resize);}
  document.addEventListener('visibilitychange',()=>pause(document.hidden));
  canvas.addEventListener('webglcontextlost',e=>{if(destroyed)return;e.preventDefault();pause(true);tell('error');});
  addEventListener('error',()=>{tell('error');document.getElementById('failure').style.display='block';});
  window.journey={pause,dispose,reset,back};
  window.journeyDiagnostics=()=>({level,place:place?.id||null,transitioning:!!transition,triangles:renderer.info.render.triangles,calls:renderer.info.render.calls,geometries:renderer.info.memory.geometries,textures:renderer.info.memory.textures,retired,buildSerial,paused,destroyed,yaw:current.yaw,radius:current.radius,width:canvas.width,height:canvas.height,cityCount:G.country.cities.length,detail:models.find(m=>m.definition.id===place?.id)?.detail.visible||false,labels:labels.filter(l=>l.screen).map(l=>({id:l.id,kind:l.kind,...l.screen}))});
  country();animate(performance.now());tell('ready');
})();
