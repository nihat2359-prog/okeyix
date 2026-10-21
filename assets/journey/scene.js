/* Okeyix Journey — original procedural scene, Three.js r160 (MIT).
   Metres, Y up. Local assets only; no credentials, network or game state. */
(() => {
  'use strict';
  const tell = message => window.Journey?.postMessage(message);
  window.addEventListener('error', () => { tell('error'); document.getElementById('failure').style.display = 'block'; });
  const T = THREE, scene = new T.Scene();
  const renderer = new T.WebGLRenderer({antialias: true, powerPreference: 'high-performance'});
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.5));
  renderer.setSize(innerWidth, innerHeight);
  renderer.outputColorSpace = T.SRGBColorSpace;
  renderer.toneMapping = T.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.15;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = T.PCFSoftShadowMap;
  document.body.appendChild(renderer.domElement);
  scene.fog = new T.FogExp2('#79929b', .008);
  const camera = new T.PerspectiveCamera(44, innerWidth / innerHeight, .15, 260);
  const sun = new T.DirectionalLight('#ffdb9b', 3.1);
  sun.position.set(-20, 36, 16); sun.castShadow = true;
  Object.assign(sun.shadow.camera, {left: -28, right: 28, top: 28, bottom: -28, near: 1, far: 100});
  sun.shadow.mapSize.set(1024, 1024); sun.shadow.normalBias = .045;
  scene.add(sun, new T.HemisphereLight('#b9dbea', '#77604a', 2));
  let rng = 173;
  function random() { rng = (Math.imul(rng, 1664525) + 1013904223) | 0; return (rng >>> 0) / 4294967296; }
  const materials = [];
  function mat(color, roughness = .75, metalness = 0, extra = {}) {
    const m = new T.MeshStandardMaterial({color, roughness, metalness, ...extra}); materials.push(m); return m;
  }
  function texture(kind) {
    const c = document.createElement('canvas'); c.width = c.height = 256;
    const g = c.getContext('2d');
    g.fillStyle = kind === 'wood' ? '#8c6344' : kind === 'stone' ? '#bbb1a0' : '#d3bfa0'; g.fillRect(0, 0, 256, 256);
    for (let i = 0; i < 2200; i++) {
      const x = random() * 256, y = random() * 256;
      g.fillStyle = `rgba(${random() > .5 ? '255,242,216' : '39,29,23'},${random() * .14})`;
      g.fillRect(x, y, kind === 'wood' ? 30 + random() * 100 : 1 + random() * 5, 1 + random() * 2);
    }
    if (kind === 'stone') {
      g.strokeStyle = '#8f887b'; g.lineWidth = 2;
      for (let row = 0; row < 8; row++) {
        g.beginPath(); g.moveTo(0, row * 32); g.lineTo(256, row * 32); g.stroke();
        for (let col = 0; col < 5; col++) { const x = col * 64 + (row % 2) * 32; g.strokeRect(x, row * 32, 64, 32); }
      }
    }
    const t = new T.CanvasTexture(c); t.colorSpace = T.SRGBColorSpace; t.wrapS = t.wrapT = T.RepeatWrapping;
    t.repeat.set(kind === 'stone' ? 5 : 2, kind === 'stone' ? 5 : 2); t.anisotropy = 4; return t;
  }
  const plaster = mat('#ead9bc', .95, 0, {map: texture('plaster')});
  const stone = mat('#c0b6a5', .92, 0, {map: texture('stone')});
  const wood = mat('#b58a5d', .68, 0, {map: texture('wood')});
  const darkWood = mat('#3a3229'), gold = mat('#d8b36e', .3, .65), green = mat('#14554b');
  const roof = mat('#a15d49'), iron = mat('#243a3b', .45, .6), leaf = mat('#486d40');
  const ivory = mat('#f4e8cd', .4), soil = mat('#4b3d31'), terra = mat('#b87857');
  const glow = mat('#ffcd7c', .5, 0, {emissive: '#ffc57e', emissiveIntensity: 1.6});
  const glass = mat('#244e58', .17, .45);
  function mesh(geometry, material, x = 0, y = 0, z = 0, parent = scene) {
    const o = new T.Mesh(geometry, material); o.position.set(x, y, z); o.castShadow = true; o.receiveShadow = true; parent.add(o); return o;
  }
  function box(w, h, d, m, x, y, z, p) { return mesh(new T.BoxGeometry(w, h, d), m, x, y, z, p); }
  function cyl(r1, r2, h, m, x, y, z, p, n = 12) { return mesh(new T.CylinderGeometry(r1, r2, h, n), m, x, y, z, p); }
  function sphere(r, m, x, y, z, p) { return mesh(new T.SphereGeometry(r, 12, 8), m, x, y, z, p); }
  function beam(a, b, radius, material, parent = scene) {
    const start = new T.Vector3(...a), end = new T.Vector3(...b), diff = end.clone().sub(start);
    const o = cyl(radius, radius, diff.length(), material, 0, 0, 0, parent, 8);
    o.position.copy(start.add(end).multiplyScalar(.5)); o.quaternion.setFromUnitVectors(new T.Vector3(0, 1, 0), diff.normalize()); return o;
  }
  function sign(text, w, h, x, y, z, parent = scene, color = '#edcc85', bg = '#173e38') {
    const c = document.createElement('canvas'); c.width = 1024; c.height = 256;
    const g = c.getContext('2d'); g.fillStyle = bg; g.fillRect(0, 0, 1024, 256);
    g.strokeStyle = color; g.lineWidth = 5; g.strokeRect(13, 13, 998, 230);
    g.fillStyle = color; g.textAlign = 'center'; g.textBaseline = 'middle'; g.font = 'bold 66px Georgia'; g.fillText(text, 512, 132, 940);
    const t = new T.CanvasTexture(c); t.colorSpace = T.SRGBColorSpace;
    return mesh(new T.PlaneGeometry(w, h), new T.MeshBasicMaterial({map: t}), x, y, z, parent);
  }
  // Procedural sky dome: no photographic backdrop. Warm horizon, blue zenith.
  mesh(new T.SphereGeometry(180, 32, 16), new T.ShaderMaterial({side: T.BackSide,
    vertexShader: 'varying vec3 p; void main(){p=position;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}',
    fragmentShader: 'varying vec3 p;void main(){float h=clamp(normalize(p).y,0.,1.);vec3 c=mix(vec3(.94,.76,.57),vec3(.16,.40,.59),pow(h,.22));gl_FragColor=vec4(c,1.);}'
  }));
  // Shore terrace, stone quay and wood decking.
  box(48, 1.3, 25, stone, 0, -.6, 7);
  box(24, .16, 12, wood, -1, .12, 4);
  box(48, .45, .65, plaster, 0, .3, -5.5);
  for (let x = -23; x < 24; x += 2.4) {
    cyl(.07, .07, 1.25, iron, x, 1.05, -5.4);
    sphere(.11, gold, x, 1.7, -5.4);
    if (x < 22) beam([x, 1.15, -5.4], [x + 2.4, 1.15, -5.4], .035, iron);
  }
  for (let z = -.5; z < 9; z += .34) box(23.7, .012, .012, darkWood, -1, .207, z);
  // Animated normal-displaced water with specular sunlight and distance haze.
  const sea = new T.ShaderMaterial({uniforms: {time: {value: 0}},
    vertexShader: 'varying vec3 p;uniform float time;void main(){p=position;vec3 q=position;q.z+=sin(q.x*.7+time)*.09+sin(q.y*.9+time*1.3)*.07;gl_Position=projectionMatrix*modelViewMatrix*vec4(q,1.);}',
    fragmentShader: `varying vec3 p;uniform float time;
      float hash(vec2 q){return fract(sin(dot(q,vec2(127.1,311.7)))*43758.5453);}
      float noise(vec2 q){vec2 i=floor(q),f=fract(q);f=f*f*(3.-2.*f);
        return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+1.),f.x),f.y);}
      void main(){vec2 q=vec2(p.x*.65,p.y*2.8)+vec2(time*.18,time*.12);
      float n=noise(q)*.55+noise(q*2.1)*.3+noise(q*4.)*.15;
      float ripple=sin(p.y*4.+p.x*.4+time+n*5.);
      float trail=exp(-pow((p.x+18.+p.y*.18)/9.,2.));
      vec3 c=mix(vec3(.035,.20,.25),vec3(.17,.37,.41),n);
      c+=pow(max(0.,ripple),24.)*(.035+trail*.23)*vec3(1.,.85,.62);
      c=mix(c,vec3(.28,.43,.47),smoothstep(35.,160.,abs(p.y))*.6);gl_FragColor=vec4(c,1.);}`,
  });
  const water = mesh(new T.PlaneGeometry(240, 340, 90, 110), sea, 0, -.35, 0);
  water.rotation.x = -Math.PI / 2; water.castShadow = false;
  // Cafe pavilion: timber framing, glazed arch bays, tiled pitched roof.
  const cafe = new T.Group(); scene.add(cafe); cafe.position.set(-3, 0, 8);
  box(12, 4.6, 6, plaster, 0, 2.5, 0, cafe);
  box(12.3, .3, 6.3, stone, 0, .35, 0, cafe);
  for (const x of [-4.3, -1.5, 1.5, 4.3]) {
    box(2.25, 2.7, .12, glass, x, 2, -3.07, cafe);
    const arch = new T.Shape(); arch.moveTo(-1.18, 0); arch.lineTo(-1.18, 2.05);
    arch.absarc(0, 2.05, 1.18, Math.PI, 0, true); arch.lineTo(1.18, 0); arch.closePath();
    const hole = new T.Path(); hole.moveTo(-.97, .16); hole.lineTo(.97, .16); hole.lineTo(.97, 2.05);
    hole.absarc(0, 2.05, .97, 0, Math.PI, false); hole.lineTo(-.97, .16); arch.holes.push(hole);
    mesh(new T.ExtrudeGeometry(arch, {depth: .16, bevelEnabled: false}), wood, x, .6, -3.25, cafe);
    box(.06, 2.65, .14, gold, x, 1.95, -3.24, cafe);
    box(2.1, .07, .14, wood, x, 2, -3.24, cafe);
    box(1.9, .12, .12, glow, x, 3.2, -2.99, cafe);
  }
  for (const x of [-6, -2.9, 0, 2.9, 6]) box(.16, 4.7, 6.15, darkWood, x, 2.5, 0, cafe);
  box(12.5, .24, 6.5, darkWood, 0, 4.82, 0, cafe);
  for (const side of [-1, 1]) {
    const slab = box(13, .18, 4, roof, 0, 5.45, side * 1.75, cafe); slab.rotation.x = side * .34;
    for (let x = -6.4; x < 6.5; x += .28) {
      beam([x, 6.1, 0], [x, 4.83, side * 3.65], .052, roof, cafe);
    }
  }
  sign('BOĞAZ KAHVESİ', 6.5, .85, 0, 4.22, -3.4, cafe);
  sign('OKEY  ·  ÇAY  ·  MUHABBET', 4, .38, 0, .86, -3.3, cafe);
  for (const x of [-5.7, 5.7]) {
    box(.16, .6, .18, iron, x, 2.8, -3.32, cafe);
    box(.22, .3, .2, glow, x, 2.83, -3.45, cafe);
    box(1.4, .28, .45, terra, x, 1.1, -3.45, cafe);
    for (let i = 0; i < 9; i++) {
      sphere(.14, leaf, x - .5 + i * .12, 1.32, -3.55, cafe);
      sphere(.085, i % 2 ? mat('#d08a93') : ivory, x - .5 + i * .12, 1.5, -3.55, cafe);
    }
  }
  // Striped retractable awning with scalloped valance.
  for (let x = -6; x < 6; x += .6) {
    const fabric = (Math.round((x + 6) / .6) % 2) ? ivory : green;
    const awning = box(.6, .06, 2.7, fabric, x + .3, 3.55, -4.2, cafe); awning.rotation.x = -.13;
    cyl(.18, .18, .55, fabric, x + .3, 3.24, -5.51, cafe).rotation.z = Math.PI / 2;
  }
  for (const x of [-5.8, 5.8]) cyl(.06, .06, 3.35, iron, x, 1.85, -5.5, cafe);
  // Overhead festoon bulbs, individually modelled. Warm light without a costly
  // dynamic point light per bulb; the sun provides the actual shadow lighting.
  for (let i = 0; i < 16; i++) {
    const x = -5.7 + i * .76, y = 3.22 - .3 * Math.sin(i / 15 * Math.PI);
    if (i) beam([x - .76, 3.22 - .3 * Math.sin((i - 1) / 15 * Math.PI), -5.5], [x, y, -5.5], .012, iron, cafe);
    sphere(.055, glow, x, y - .08, -5.5, cafe);
  }
  // Okey tables, turned pedestals, chairs, racks, actual individual tiles.
  function chair(x, z, angle, parent) {
    const g = new T.Group(); parent.add(g); g.position.set(x, 0, z); g.rotation.y = angle;
    box(.68, .13, .65, wood, 0, .73, 0, g);
    for (const a of [-.27, .27]) for (const b of [-.24, .24]) cyl(.035, .045, .74, darkWood, a, .38, b, g, 6);
    for (const a of [-.28, .28]) cyl(.035, .035, .8, wood, a, 1.04, .27, g, 6);
    for (const y of [.97, 1.17, 1.37]) box(.57, .09, .06, wood, 0, y, .28, g);
  }
  function table(x, z, featured = false) {
    const g = new T.Group(); scene.add(g); g.position.set(x, .22, z);
    cyl(.2, .44, 1.05, iron, 0, .55, 0, g);
    box(1.9, .14, 1.9, wood, 0, 1.15, 0, g);
    box(1.72, .025, 1.72, green, 0, 1.235, 0, g);
    for (const a of [-1, 1]) {
      box(1.4, .16, .13, wood, 0, 1.33, a * .66, g);
      for (let i = 0; i < 10; i++) {
        box(.105, .19, .065, ivory, -.57 + i * .125, 1.44, a * .66, g);
        sphere(.018, i % 3 ? green : roof, -.57 + i * .125, 1.47, a * .70, g);
      }
      chair(0, a * 1.5, a > 0 ? 0 : Math.PI, g);
    }
    // Turkish tea glasses and saucers.
    for (const a of [-1, 1]) {
      cyl(.14, .14, .025, ivory, a * .72, 1.27, -.25, g);
      cyl(.065, .05, .18, mat('#8d3721', .22, .1), a * .72, 1.37, -.25, g);
      cyl(.073, .06, .03, gold, a * .72, 1.47, -.25, g);
    }
    if (featured) g.userData.focusTable = true;
    return g;
  }
  table(-3, .4, true); table(-8.2, 1); table(3, 1); table(7.4, 4.5);
  // Planters, spherical trained olives, irregular canopies and garden lamps.
  for (const [x, z, scale] of [[-12, 2, 1.2], [10, 0, 1], [-12, 11, 1.3], [10, 12, 1.2]]) {
    cyl(.65, .48, .9, terra, x, .65, z);
    cyl(.56, .56, .05, soil, x, 1.1, z);
    beam([x, 1, z], [x + .15, 3.7, z], .13, darkWood);
    for (let j = 0; j < 8; j++) {
      const a = j * 2.4, r = .5 + random() * .7;
      const crown = sphere(.85 * scale, leaf, x + Math.sin(a) * r, 3.8 + random() * 1.1, z + Math.cos(a) * r);
      crown.scale.y = .75;
    }
  }
  for (const x of [-15, -9, 9, 15]) {
    cyl(.08, .15, 3.4, iron, x, 1.85, -3);
    box(.48, .65, .48, iron, x, 3.8, -3);
    box(.35, .48, .35, glow, x, 3.8, -3.01);
    cyl(.4, .02, .24, iron, x, 4.22, -3, scene, 4);
  }
  for (const x of [-6, 0, 6]) {
    box(1.4, .45, .6, stone, x, .45, -4.1);
    for (let i = 0; i < 7; i++) sphere(.24, leaf, x - .55 + i * .18, .84 + random() * .15, -4.1);
  }
  // Seafront benches and a stepped promenade; a proper place rather than a
  // building alone on a plane. Small geometry shares the existing materials.
  for (const x of [-16, 14]) {
    for (let i = 0; i < 5; i++) box(2.7, .08, .12, wood, x, .8, 1 + i * .16);
    for (let i = 0; i < 4; i++) box(2.7, .12, .08, wood, x, 1.05 + i * .16, 1.76);
    for (const s of [-1, 1]) {
      box(.12, .7, .65, iron, x + s * 1.02, .48, 1.32);
      beam([x + s * 1.02, .6, 1.76], [x + s * 1.02, 1.58, 1.76], .045, iron);
    }
  }
  for (let i = 0; i < 3; i++) box(3.8, .12, .5, stone, -3, .06 + i * .06, -2.3 + i * .5);
  cyl(.04, .06, 7.4, iron, -9.5, 3.9, 9);
  const flagCanvas = document.createElement('canvas'); flagCanvas.width = 256; flagCanvas.height = 160;
  const flagInk = flagCanvas.getContext('2d'); flagInk.fillStyle = '#b83435'; flagInk.fillRect(0, 0, 256, 160);
  flagInk.fillStyle = '#fff1df'; flagInk.beginPath(); flagInk.arc(100, 80, 43, 0, Math.PI * 2); flagInk.fill();
  flagInk.fillStyle = '#b83435'; flagInk.beginPath(); flagInk.arc(113, 76, 35, 0, Math.PI * 2); flagInk.fill();
  flagInk.fillStyle = '#fff1df'; flagInk.font = '52px sans-serif'; flagInk.fillText('★', 140, 98);
  const flagTexture = new T.CanvasTexture(flagCanvas); flagTexture.colorSpace = T.SRGBColorSpace;
  const flag = mesh(new T.PlaneGeometry(1.8, 1.12, 12, 4), mat('#ffffff', .9, 0,
    {map: flagTexture, side: T.DoubleSide}), -8.6, 6.65, 9);
  const flagBase = flag.geometry.attributes.position.array.slice();
  // Opponent: articulated stylised human with jacket, hands, moustache and fez.
  const champion = new T.Group(); champion.position.set(-.4, .23, -.8); champion.scale.setScalar(1.15); scene.add(champion);
  const suit = mat('#233f48'), skin = mat('#d8a677'), hair = mat('#382d29'), shirt = mat('#e2cfab');
  for (const x of [-.18, .18]) {
    cyl(.12, .13, .8, suit, x, .48, 0, champion);
    const shoe = sphere(.15, hair, x, .13, -.09, champion); shoe.scale.set(1, .55, 1.65);
  }
  cyl(.29, .23, .76, suit, 0, 1.23, 0, champion);
  box(.18, .5, .025, shirt, 0, 1.32, -.262, champion);
  beam([-.3, 1.5, 0], [-.46, 1.02, -.1], .1, suit, champion);
  beam([.3, 1.5, 0], [.47, 1.1, -.15], .1, suit, champion);
  sphere(.105, skin, -.46, .99, -.1, champion); sphere(.105, skin, .47, 1.06, -.15, champion);
  cyl(.11, .12, .18, skin, 0, 1.7, 0, champion);
  const face = sphere(.255, skin, 0, 1.98, 0, champion); face.scale.set(.84, 1.15, .85);
  sphere(.055, skin, 0, 1.97, -.22, champion);
  for (const x of [-.09, .09]) sphere(.026, hair, x, 2.05, -.199, champion);
  const moustache = sphere(.1, hair, 0, 1.89, -.205, champion); moustache.scale.set(1, .28, .25);
  cyl(.16, .23, .24, mat('#8e3831'), 0, 2.28, 0, champion);
  beam([.12, 2.42, 0], [.25, 2.18, 0], .018, gold, champion);
  sign('ŞAMPİYON · OKEY USTASI', 3, .65, -.3, 2.9, -1.4);
  // Trophy plinth beside the cafe — 3D cup and handles.
  cyl(.48, .62, .9, stone, 5.3, .7, 3);
  cyl(.32, .18, .48, gold, 5.3, 1.55, 3);
  cyl(.08, .1, .25, gold, 5.3, 1.22, 3);
  for (const s of [-1, 1]) {
    const handle = mesh(new T.TorusGeometry(.2, .035, 8, 16), gold, 5.3 + s * .29, 1.59, 3); handle.scale.x = .8;
  }
  // Asian shore, layered hills and waterfront houses. All real geometry.
  for (let i = 0; i < 22; i++) {
    const x = -110 + i * 11, h = 12 + random() * 12;
    const hill = sphere(17, mat(i % 2 ? '#5c7e7b' : '#688780'), x, -8, 125 + random() * 16);
    hill.scale.set(1.5, h / 17, .8); hill.castShadow = false;
  }
  const distantMats = ['#9eaa9f', '#c1b4a2', '#a99b88', '#d1c1a1'].map(c => mat(c));
  for (let i = 0; i < 95; i++) {
    const x = -106 + i * 2.3, h = 1.4 + random() * 4;
    const z = 99 + random() * 12, width = 1.5 + random();
    box(width, h, 2, distantMats[i % 4], x, h / 2 -.4, z).castShadow = false;
    const cap = cyl(0, width * .8, .8, roof, x, h, z, scene, 4); cap.rotation.y = Math.PI / 4; cap.castShadow = false;
    for (const offset of [-.4, .4]) box(.3, .55, .02, glass, x + offset, h * .65, z - 1.02).castShadow = false;
  }
  // Bosphorus suspension bridge with curved main cables and vertical hangers.
  const bridge = new T.Group(); scene.add(bridge); bridge.position.set(34, 0, 68); bridge.rotation.y = -.25;
  box(105, .45, 2.2, iron, 0, 9, 0, bridge);
  for (const x of [-25, 25]) {
    for (const z of [-1.6, 1.6]) box(.65, 24, .65, stone, x, 11, z, bridge);
    box(.7, .7, 3.8, stone, x, 21, 0, bridge);
  }
  for (const z of [-1.4, 1.4]) for (let x = -49; x < 50; x += 2) {
    const height = q => Math.abs(q) <= 25 ? 12 + 9 * (q / 25) ** 2 : 21 - (Math.abs(q) - 25) * .4;
    beam([x, height(x), z], [x + 2, height(x + 2), z], .035, ivory, bridge);
    beam([x, 9, z], [x, height(x), z], .022, ivory, bridge);
  }
  // Ferry with decks, funnel and open railings; slow environmental motion.
  const ferry = new T.Group(); scene.add(ferry);
  const hull = cyl(1, 1, 9, ivory, 0, .7, 0, ferry); hull.rotation.z = Math.PI / 2; hull.scale.z = .9;
  box(6.8, .85, 1.65, ivory, 0, 1.2, 0, ferry);
  box(5.5, .08, 2, darkWood, 0, 1.68, 0, ferry);
  box(4.5, .7, 1.4, ivory, 0, 2.05, 0, ferry);
  box(5.2, .1, 1.8, ivory, 0, 2.45, 0, ferry);
  cyl(.23, .23, .9, gold, -.6, 2.75, 0, ferry);
  for (let x = -2.7; x < 3; x += .55) for (const z of [-.84, .84]) box(.35, .35, .025, glass, x, 1.32, z, ferry);
  const birds = [];
  for (let i = 0; i < 6; i++) {
    const b = new T.Group(); scene.add(b);
    const wings = [-1, 1].map(s => { const w = box(.55, .035, .16, ivory, s * .27, 0, 0, b); return w; });
    birds.push({b, wings});
  }
  // Batch static architecture by material: retain true mesh picking on cafe,
  // leave the character, ferry and birds articulated. No extra engine/plugin.
  function batch(root, excluded = new Set()) {
    root.updateMatrixWorld(true);
    const inverse = root.matrixWorld.clone().invert(), groups = new Map();
    function collect(node) {
      if (excluded.has(node)) return;
      if (node.isMesh && node.material.isMeshStandardMaterial) {
        const key = `${node.material.uuid}/${node.castShadow}/${node.receiveShadow}`;
        if (!groups.has(key)) groups.set(key, []);
        groups.get(key).push(node);
      }
      [...node.children].forEach(collect);
    }
    [...root.children].forEach(collect);
    for (const objects of groups.values()) {
      if (objects.length < 2) continue;
      const positions = [], normals = [], uvs = [];
      for (const o of objects) {
        const g = o.geometry.index ? o.geometry.toNonIndexed() : o.geometry.clone();
        g.applyMatrix4(inverse.clone().multiply(o.matrixWorld));
        for (const [name, buffer] of [['position', positions], ['normal', normals], ['uv', uvs]]) {
          const a = g.getAttribute(name); if (a) for (const value of a.array) buffer.push(value);
        }
        g.dispose(); o.removeFromParent(); o.geometry.dispose();
      }
      const geometry = new T.BufferGeometry();
      geometry.setAttribute('position', new T.Float32BufferAttribute(positions, 3));
      geometry.setAttribute('normal', new T.Float32BufferAttribute(normals, 3));
      geometry.setAttribute('uv', new T.Float32BufferAttribute(uvs, 2));
      const merged = new T.Mesh(geometry, objects[0].material);
      merged.castShadow = objects[0].castShadow; merged.receiveShadow = objects[0].receiveShadow;
      root.add(merged);
    }
  }
  batch(cafe);
  batch(scene, new Set([cafe, champion, ferry, flag, ...birds.map(b => b.b)]));
  // Ray picking uses actual geometry; no screen-space fake hotspots.
  const raycaster = new T.Raycaster(), pointer = new T.Vector2();
  const orbit = {yaw: -.38, pitch: .28, radius: 24}, target = new T.Vector3(-2, 2.2, 3);
  let intro = 0, focused = false, paused = false, destroyed = false, frame = 0, elapsed = 0, previous = 0;
  let desired = {...orbit}, desiredTarget = target.clone();
  const clamp = T.MathUtils.clamp;
  function reset() { focused = false; desired = {yaw: -.38, pitch: .28, radius: 24}; desiredTarget.set(-2, 2.2, 3); }
  function focus() { focused = true; desired = {yaw: -.15, pitch: .28, radius: 16}; desiredTarget.set(-3, 1.6, 4); }
  const pointers = new Map(); let moved = 0, down = null, pinch = 0;
  const canvas = renderer.domElement;
  canvas.addEventListener('pointerdown', e => {
    canvas.setPointerCapture(e.pointerId); pointers.set(e.pointerId, [e.clientX, e.clientY]);
    down = [e.clientX, e.clientY]; moved = 0; pinch = 0; intro = 2;
  });
  canvas.addEventListener('pointermove', e => {
    if (!pointers.has(e.pointerId)) return;
    const old = pointers.get(e.pointerId), dx = e.clientX - old[0], dy = e.clientY - old[1];
    pointers.set(e.pointerId, [e.clientX, e.clientY]); moved += Math.abs(dx) + Math.abs(dy);
    if (pointers.size === 2) {
      const [a, b] = [...pointers.values()], distance = Math.hypot(a[0] - b[0], a[1] - b[1]);
      if (pinch) desired.radius = clamp(desired.radius * pinch / Math.max(distance, 1), focused ? 16 : 22, 37);
      pinch = distance;
    } else {
      desired.yaw = clamp(desired.yaw - dx * .004, -.95, .65);
      desired.pitch = clamp(desired.pitch + dy * .003, .25, .8);
    }
  });
  function release(e) {
    if (down && moved < 9 && pointers.size === 1) {
      pointer.set(e.clientX / innerWidth * 2 - 1, 1 - e.clientY / innerHeight * 2);
      raycaster.setFromCamera(pointer, camera);
      const personHit = raycaster.intersectObject(champion, true);
      const cafeHit = raycaster.intersectObject(cafe, true);
      if (personHit.length) { tell('champion'); focus(); }
      else if (cafeHit.length) focus();
    }
    pointers.delete(e.pointerId); pinch = 0; down = null;
  }
  canvas.addEventListener('pointerup', release);
  canvas.addEventListener('pointercancel', e => { pointers.delete(e.pointerId); down = null; pinch = 0; });
  canvas.addEventListener('wheel', e => { e.preventDefault(); desired.radius = clamp(desired.radius + e.deltaY * .015, focused ? 16 : 22, 37); }, {passive: false});
  addEventListener('resize', () => { camera.aspect = innerWidth / innerHeight; camera.updateProjectionMatrix(); renderer.setSize(innerWidth, innerHeight); });
  canvas.addEventListener('webglcontextlost', e => { if (destroyed) return; e.preventDefault(); pause(true); tell('error'); });
  function animate(now) {
    if (paused || destroyed) return;
    frame = requestAnimationFrame(animate);
    const dt = Math.min((now - (previous || now)) / 1000, .05); previous = now; elapsed += dt; intro += dt;
    const ease = 1 - Math.exp(-dt * 4);
    orbit.yaw += (desired.yaw - orbit.yaw) * ease;
    orbit.pitch += (desired.pitch - orbit.pitch) * ease;
    orbit.radius += (desired.radius - orbit.radius) * ease;
    target.lerp(desiredTarget, ease);
    const entrance = Math.max(0, 1 - intro / 2);
    const radius = orbit.radius + entrance * entrance * 9;
    camera.position.set(target.x + Math.sin(orbit.yaw) * Math.cos(orbit.pitch) * radius,
      target.y + Math.sin(orbit.pitch) * radius,
      target.z - Math.cos(orbit.yaw) * Math.cos(orbit.pitch) * radius);
    camera.lookAt(target); sea.uniforms.time.value = elapsed;
    const flagPositions = flag.geometry.attributes.position;
    for (let i = 0; i < flagPositions.count; i++) {
      const x = flagBase[i * 3];
      flagPositions.setZ(i, Math.sin(x * 4 - elapsed * 2.5) * .12 * (x + .9));
    }
    flagPositions.needsUpdate = true; flag.geometry.computeVertexNormals();
    ferry.position.set(-22 + Math.sin(elapsed * .018) * 26, Math.sin(elapsed * .8) * .06, 28);
    ferry.rotation.z = Math.sin(elapsed) * .008;
    birds.forEach(({b, wings}, i) => {
      b.position.set(Math.sin(elapsed * .08 + i) * 19, 10 + i * .6, 20 + i * 4);
      b.rotation.y = elapsed * .08 + i;
      wings[0].rotation.z = Math.sin(elapsed * 3 + i) * .25;
      wings[1].rotation.z = -wings[0].rotation.z;
    });
    renderer.render(scene, camera);
  }
  function pause(value) {
    paused = value; cancelAnimationFrame(frame); previous = 0;
    if (!paused && !destroyed) frame = requestAnimationFrame(animate);
  }
  function dispose() {
    destroyed = true; cancelAnimationFrame(frame);
    const geometries = new Set(), mats = new Set(), textures = new Set();
    scene.traverse(o => { if (o.geometry) geometries.add(o.geometry); if (o.material) {
      const list = Array.isArray(o.material) ? o.material : [o.material]; list.forEach(m => {
        mats.add(m); Object.values(m).forEach(v => { if (v?.isTexture) textures.add(v); });
      });
    }});
    geometries.forEach(g => g.dispose()); textures.forEach(t => t.dispose()); mats.forEach(m => m.dispose());
    renderer.dispose(); renderer.forceContextLoss();
  }
  document.addEventListener('visibilitychange', () => pause(document.hidden));
  window.journey = {reset, pause, dispose};
  // Diagnostics reveal no application/user data; used by local rendering test.
  const screenPoint = point => { const p = point.project(camera); return {x: (p.x + 1) * innerWidth / 2, y: (1 - p.y) * innerHeight / 2}; };
  window.journeyDiagnostics = () => ({revision: T.REVISION, calls: renderer.info.render.calls,
    triangles: renderer.info.render.triangles, meshes: scene.children.length,
    width: canvas.width, height: canvas.height, yaw: orbit.yaw, focused, paused, destroyed,
    champion: screenPoint(new T.Vector3(-.4, 1.65, -.8)), cafe: screenPoint(new T.Vector3(-3, 4.2, 4.6))});
  animate(performance.now()); tell('ready');
})();
