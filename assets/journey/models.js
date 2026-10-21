/* Original procedural architecture. No photographic billboards or paid assets.
   The other five models are lightweight approximations; Maiden's Tower has a
   separately built close-detail tier. See SOURCES.md for references/limits. */
(() => {
  const T=THREE;
  function palette() {
    const textures=[];
    function surface(color,kind) {
      const c=document.createElement('canvas'); c.width=c.height=512;const g=c.getContext('2d');
      g.fillStyle=color;g.fillRect(0,0,512,512);let seed=43;
      const r=()=>{seed=(Math.imul(seed,1664525)+1013904223)|0;return(seed>>>0)/4294967296;};
      for(let i=0;i<9000;i++){g.fillStyle=`rgba(${r()>.5?'255,249,233':'53,45,37'},${r()*.12})`;g.fillRect(r()*512,r()*512,kind==='wood'?r()*100+8:2+r()*5,1+r()*2);}
      if(kind==='stone')for(let y=0;y<512;y+=32)for(let x=-32;x<512;x+=64){g.strokeStyle='rgba(76,70,59,.32)';g.lineWidth=2;g.strokeRect(x+(y%64?32:0),y,64,32);}
      const map=new T.CanvasTexture(c);map.colorSpace=T.SRGBColorSpace;map.wrapS=map.wrapT=T.RepeatWrapping;map.anisotropy=4;textures.push(map);
      return new T.MeshStandardMaterial({map,color:'#ffffff',bumpMap:map,bumpScale:kind==='stone'?.12:.045,roughness:.86});
    }
    const p={stone:surface('#bfb5a1','stone'),light:surface('#e1d8c3','stone'),wood:surface('#806248','wood'),
      slate:new T.MeshStandardMaterial({color:'#47545a',roughness:.57,metalness:.25}),
      roof:new T.MeshStandardMaterial({color:'#935a44',roughness:.88}),
      bronze:new T.MeshStandardMaterial({color:'#9d8455',roughness:.32,metalness:.7}),
      dark:new T.MeshStandardMaterial({color:'#293b3b',roughness:.6}),
      glass:new T.MeshStandardMaterial({color:'#456c76',roughness:.15,metalness:.65}),
      leaf:new T.MeshStandardMaterial({color:'#456248',roughness:.95}),
      red:new T.MeshStandardMaterial({color:'#a42c31',roughness:.78,side:T.DoubleSide}),
      white:new T.MeshStandardMaterial({color:'#f7e8ca',roughness:.7}),textures};
    return p;
  }
  function create(type,p) {
    const group=new T.Group(),detail=new T.Group();group.add(detail);
    function mesh(g,m,x=0,y=0,z=0,parent=group){const o=new T.Mesh(g,m);o.position.set(x,y,z);o.castShadow=o.receiveShadow=true;parent.add(o);return o;}
    const box=(w,h,d,m,x,y,z,parent)=>mesh(new T.BoxGeometry(w,h,d),m,x,y,z,parent);
    const cyl=(a,b,h,m,x,y,z,parent,n=24)=>mesh(new T.CylinderGeometry(a,b,h,n),m,x,y,z,parent);
    const sphere=(r,m,x,y,z,parent)=>mesh(new T.SphereGeometry(r,12,8),m,x,y,z,parent);
    function beam(a,b,r,m,parent){const av=new T.Vector3(...a),bv=new T.Vector3(...b),d=bv.clone().sub(av);const o=cyl(r,r,d.length(),m,0,0,0,parent,6);o.position.copy(av.add(bv).multiplyScalar(.5));o.quaternion.setFromUnitVectors(new T.Vector3(0,1,0),d.normalize());return o;}
    function arch(w,h,depth,x,y,z,parent=group){
      box(w,h,depth,p.dark,x,y+h/2,z,parent);
      const curve=new T.Shape();curve.moveTo(-w*.58,0);curve.lineTo(-w*.58,h-w*.4);curve.absarc(0,h-w*.4,w*.58,Math.PI,0,true);curve.lineTo(w*.58,0);curve.closePath();
      const hole=new T.Path();hole.moveTo(-w*.43,.1);hole.lineTo(w*.43,.1);hole.lineTo(w*.43,h-w*.4);hole.absarc(0,h-w*.4,w*.43,0,Math.PI,false);hole.lineTo(-w*.43,.1);curve.holes.push(hole);
      mesh(new T.ExtrudeGeometry(curve,{depth:.2,bevelEnabled:false}),p.light,x,y,z-depth/2-.15,parent);
    }
    function railing(radius,y,parent=group,n=32){
      for(let i=0;i<n;i++){const a=i/n*Math.PI*2,b=(i+1)/n*Math.PI*2;beam([Math.sin(a)*radius,y,Math.cos(a)*radius],[Math.sin(a)*radius,y+1.05,Math.cos(a)*radius],.045,p.bronze,parent);beam([Math.sin(a)*radius,y+1.05,Math.cos(a)*radius],[Math.sin(b)*radius,y+1.05,Math.cos(b)*radius],.05,p.bronze,parent);}
    }
    function conicRoof(radius,height,y,parent=group,n=32){cyl(0,radius,height,p.slate,0,y+height/2,0,parent,n);}
    function flag(x,y,z,parent=group){
      cyl(.07,.09,7,p.bronze,x,y+3.5,z,parent,8);
      const cloth=mesh(new T.PlaneGeometry(2.7,1.65,10,4),p.red,x+1.35,y+5.9,z,parent);
      const pos=cloth.geometry.attributes.position;for(let i=0;i<pos.count;i++)pos.setZ(i,Math.sin(pos.getX(i)*3)*.13*(pos.getX(i)+1.35));pos.needsUpdate=true;cloth.geometry.computeVertexNormals();
      const moon=mesh(new T.RingGeometry(.3,.42,24,1,.5,Math.PI*1.65),p.white,x+1.05,y+5.9,z+.12,parent);moon.rotation.z=.25;
      sphere(.12,p.white,x+1.65,y+5.9,z+.12,parent);
    }
    function tree(x,y,z,height,parent=group){
      cyl(.16,.4,height*.7,p.wood,x,y+height*.35,z,parent,7);
      // Branching, irregular olive canopy, no stacked cartoon spheres.
      for(let i=0;i<9;i++){const a=i*2.399,r=height*(.12+(i%3)*.04);beam([x,y+height*.45,z],[x+Math.sin(a)*r,y+height*(.7+i%3*.07),z+Math.cos(a)*r],.09,p.wood,parent);const crown=mesh(new T.IcosahedronGeometry(height*.19,1),p.leaf,x+Math.sin(a)*r,y+height*(.72+i%3*.07),z+Math.cos(a)*r,parent);crown.scale.set(1.3,.7,1);}
    }
    let buildDetail=()=>{};
    if(type==='maiden'){
      const island=box(44,1.8,36,p.stone,0,.3,0);island.rotation.y=-.12;
      box(39,.35,32,p.light,0,1.35,0);
      for(const z of [-16,16]){box(38,2.2,1,p.stone,0,2.4,z);for(let x=-18;x<=18;x+=2.6)box(1.3,.8,1.2,p.light,x,3.8,z);}
      for(const x of [-19,19])box(1,2.2,32,p.stone,x,2.4,0);
      box(22,5.5,12,p.light,0,4.3,7);
      const roof=box(23,.5,8,p.roof,0,8,5);roof.rotation.x=-.35;
      const roof2=box(23,.5,8,p.roof,0,8,9);roof2.rotation.x=.35;
      box(9,13,9,p.light,-3,8,-3);
      for(const y of [3,7,12.8,14.2])box(9.5,.35,9.5,p.stone,-3,y,-3);
      box(11,.6,11,p.light,-3,14.8,-3);
      const lantern=new T.Group();lantern.position.set(-3,0,-3);group.add(lantern);
      cyl(3.65,3.65,4.1,p.light,0,17.1,0,lantern,8);
      cyl(4.25,4.25,.4,p.stone,0,19.3,0,lantern,8);
      // Historic bell-shaped lead cap: lathed profile rather than a cone.
      const profile=[[0,4.1],[.7,4],[1.6,2.8],[2.6,2.1],[3.6,1.9],[4.5,1.4],[5.2,.6],[6.1,.12]].map(([y,r])=>new T.Vector2(r,y));
      mesh(new T.LatheGeometry(profile,40),p.slate,0,19.5,0,lantern);
      cyl(.07,.14,2,p.bronze,0,26,0,lantern,8);sphere(.25,p.bronze,0,25.7,0,lantern);
      flag(-3,26.5,-3);
      for(let i=0;i<8;i++){const a=i*Math.PI/4;const window=box(1.3,2.1,.13,p.glass,Math.sin(a)*3.69,17.2,Math.cos(a)*3.69,lantern);window.rotation.y=a;}
      arch(1.6,3,.15,-3,8,-7.55);arch(1.6,3,.15,-3,3.2,-7.55);
      for(const x of [-7,-3,1,5,9])arch(1.1,2.4,.15,x,3.6,13.1);
      buildDetail=()=>{
        function faceWindow(x,y,z,rotation,w=1.25,h=2.4){const f=new T.Group();f.position.set(x,y,z);f.rotation.y=rotation;detail.add(f);arch(w,h,.15,0,0,0,f);}
        for(const y of [3.2,8.2,11.8]){
          faceWindow(1.57,y,-3,-Math.PI/2);
          faceWindow(-7.57,y,-3,Math.PI/2);
          faceWindow(-3,y,1.57,Math.PI);
        }
        for(const x of [4,8])faceWindow(x,3.2,.9,0,1.1,2.6);
        for(const z of [4,8,11])faceWindow(11.1,3.2,z,-Math.PI/2,1.1,2.6);
        for(const y of [2,4,6,8,10,12])for(const z of [-7.53,1.53])box(8.9,.045,.04,p.stone,-3,y,z,detail);
        for(const x of [-7.55,1.55])for(let y=2;y<14;y+=.85){box(.22,.27,9.1,p.stone,x,y,-3,detail);}
        for(const z of [-8.5,2.5])for(let x=-8.3;x<2.5;x+=.7){cyl(.035,.035,1.05,p.bronze,x,15.65,z,detail,6);}
        for(const z of [-8.5,2.5])box(11,.07,.07,p.bronze,-3,16.2,z,detail);
        for(const x of [-8.5,2.5])box(.07,.07,11,p.bronze,x,16.2,-3,detail);
        for(let i=0;i<8;i++){const a=i*Math.PI/4;const post=box(.13,3.7,.15,p.bronze,-3+Math.sin(a)*3.77,17.15,-3+Math.cos(a)*3.77,detail);post.rotation.y=a;}
        for(let i=0;i<22;i++)box(.16,.05,7,p.wood,21+i*.32,1.8,7,detail);
        for(const x of [22,27])for(const z of [4,10])cyl(.14,.18,3.3,p.wood,x,.4,z,detail,8);
        for(let i=0;i<7;i++)box(3.5,.2,.6,p.stone,12,1.5+i*.18,12-i*.5,detail);
        for(let x=-15;x<16;x+=3)for(const z of [-13,13]){cyl(.12,.12,.65,p.bronze,x,2.2,z,detail,8);}
        for(const z of [-13,13])beam([-15,2.52,z],[15,2.52,z],.04,p.bronze,detail);
        const life=mesh(new T.TorusGeometry(.6,.15,8,24),p.red,19.6,2.8,6,detail);life.rotation.y=Math.PI/2;
        // Reserved champion space: physical plinth, no fabricated player title.
        cyl(1.5,1.8,.6,p.stone,11,1.8,-8,detail);cyl(.3,.7,1.4,p.bronze,11,2.7,-8,detail);
        cyl(.9,.45,1.2,p.bronze,11,3.8,-8,detail); 
      };
    } else if(type==='galata'){
      cyl(8.1,8.5,42,p.stone,0,21,0,group,40);cyl(9.1,9.1,1.8,p.light,0,43,0,group,40);
      cyl(7.3,7.6,9,p.light,0,48,0,group,32);conicRoof(9.5,14,52);
      railing(9,44);
      for(let i=0;i<12;i++){const a=i*Math.PI/6;const win=box(1.5,3,.2,p.dark,Math.sin(a)*8.12,33,Math.cos(a)*8.12);win.rotation.y=a;}
      buildDetail=()=>{for(let i=0;i<12;i++){const a=i*Math.PI/6;const w=box(1.1,4,.1,p.glass,Math.sin(a)*7.58,48,Math.cos(a)*7.58,detail);w.rotation.y=a;}for(const y of [8,18,28,38])cyl(8.2,8.2,.25,p.light,0,y,0,detail,40);};
    } else if(type==='mosque'){
      box(27,17,24,p.light,0,8.5,0);cyl(11.5,12,2,p.light,0,18,0);
      const dome=mesh(new T.SphereGeometry(11,32,16,0,Math.PI*2,0,Math.PI/2),p.slate,0,19,0);
      for(const x of [-17,17]){cyl(1.05,1.8,36,p.light,x,18,4);cyl(2.3,2.3,.65,p.light,x,26,4);cyl(0,1.5,8,p.slate,x,40,4);}
      for(const x of [-9,0,9])arch(4,8,.2,x,3,-12.2);
      box(48,.8,38,p.stone,0,-.2,0);
      buildDetail=()=>{for(const x of [-11,11])for(const z of [-10,10])box(1.2,18,1.2,p.stone,x,9,z,detail);for(const x of [-9,0,9])arch(3,4,.2,x,11,-12.4,detail);};
    } else if(type==='station'){
      box(110,23,22,p.light,0,11.5,0);for(const x of [-46,46])box(18,22,55,p.light,x,11,17);
      const r=box(113,.8,16,p.slate,0,26,-5);r.rotation.x=-.5;const r2=box(113,.8,16,p.slate,0,26,5);r2.rotation.x=.5;
      for(const x of [-49,49]){cyl(6,7,27,p.stone,x,13.5,-8);cyl(0,8,14,p.slate,x,34,-8);}
      for(let x=-40;x<=40;x+=6)for(const y of [6,13,20])box(2,3,.2,p.dark,x,y,-11.1);
      buildDetail=()=>{for(let x=-42;x<=42;x+=6)box(.6,23,.5,p.stone,x,11.5,-11.4,detail);for(const y of [9,17,23])box(96,.4,.8,p.stone,0,y,-11.3,detail);arch(5,8,.3,0,1,-11.8,detail);};
    } else if(type==='fortress'){
      const points=[[-38,0,-25],[-25,5,30],[25,1,26],[40,-4,-30]];
      for(let i=0;i<points.length;i++){const a=points[i],b=points[(i+1)%points.length],len=Math.hypot(b[0]-a[0],b[2]-a[2]);const wall=box(len,15,3.5,p.stone,(a[0]+b[0])/2,7.5+(a[1]+b[1])/2,(a[2]+b[2])/2);wall.rotation.y=-Math.atan2(b[2]-a[2],b[0]-a[0]);for(let j=0;j<len;j+=4){const t=j/len;box(2,2,4,p.light,a[0]+(b[0]-a[0])*t,16+a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t);}}
      // Three major towers, with a smaller wall turret (not four equal towers).
      points.forEach(([x,y,z],index)=>{const radius=index===1?2.8:[8,0,9,7][index],h=index===1?17:[28,0,33,24][index];cyl(radius,radius+.7,h,p.stone,x,y+h/2,z);const n=index===1?8:14;for(let i=0;i<n;i++){const a=i*Math.PI*2/n;box(index===1?.8:1.5,1.7,index===1?.8:1.5,p.light,x+Math.sin(a)*radius,y+h+.7,z+Math.cos(a)*radius);}});
      buildDetail=()=>{for(let i=0;i<14;i++)tree(Math.sin(i*2.4)*26,0,Math.cos(i*2.4)*20,6+(i%3),detail);};
    } else if(type==='terrace'){
      cyl(37,43,4,p.stone,0,-2,0,group,40);box(28,7,13,p.light,-8,3.5,-8);
      const r=box(30,.6,9,p.roof,-8,8,-10);r.rotation.x=-.35;const r2=box(30,.6,9,p.roof,-8,8,-6);r2.rotation.x=.35;
      railing(35,.3,group,60);
      for(let i=0;i<10;i++){const a=i*2.4;tree(Math.sin(a)*27,0,Math.cos(a)*27,8+i%3);}
      buildDetail=()=>{for(let i=0;i<8;i++){const x=(i%4)*5-8,z=Math.floor(i/4)*5+6;cyl(1,1,.2,p.wood,x,1.5,z,detail);cyl(.15,.4,1.5,p.dark,x,.7,z,detail);for(const s of [-1,1])box(.8,.15,.8,p.wood,x+s*1.6,.8,z,detail);}};
    }
    let detailed=false;
    return {group,detail,enableDetail(){if(!detailed){buildDetail();detailed=true;}detail.visible=true;},disableDetail(){detail.traverse(o=>{if(o.geometry)o.geometry.dispose();});detail.clear();detail.visible=false;detailed=false;},type};
  }
  window.JourneyModels={palette,create};
})();
