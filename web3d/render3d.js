/* Iron Corridor 3D — Three.js renderer over the untouched 2D sim (sim2d.js).
 * Mirrors the 2D game exactly: same sim, same stats, same balance — only the
 * presentation differs. Sim coords: x 0..4200 (left base -> right base),
 * y negative = up (aircraft alt), positive = down (sub depth), 0 = waterline.
 * Three coords: x same, y = -simY, z = lane depth (camera looks toward -z).
 */
import * as THREE from './three.module.min.js';

var renderer, scene, camera, W = 2, H = 2;
var CAM_FOV = 40, CAM_H = 150, CAM_D = 560, CAM_LOOK_Y = -10;
// the 2D canvas HUD overlay (base bars/minimap/second row) occupies the top
// of the screen; a high-altitude aircraft (e.g. the long-range bomber's
// alt:-210) can project up behind it and render invisibly. Cap the world
// height used for the mesh only - never touches the sim's u.y, which still
// drives hit-detection.
export var AIR_MAX_WORLD_Y = 130;
var sunLight, hemiLight, skyMat, sunSprite, seabed, waterMat, waterMesh;
var clouds = [];
var unitMeshes = {};   // sim unit id -> {group, refs, unit}
var projMeshes = {};   // projectile id -> mesh
var baseGroups = {};   // 'L'/'R' -> {group, refs}
var wrecks = [];       // {mesh, t, dur, kind, len}
var sprites = [];      // active fx sprites {s, t, dur, grow, from, fade}
var aimGroup = null, b52Mesh = null;
var titleShip = null;
var protoCache = {};
var texCache = {};
var simTime = 0;

// ---------------- palette (mirrors web2d skyColors / hull colors)
function lerpC(a, b, t) { return new THREE.Color(a).lerp(new THREE.Color(b), t); }
function stagePalette(i) {
  var t = i / 8;
  return {
    top: lerpC('#26425e', '#2a1c30', t),
    mid: lerpC('#7fa8c9', '#8a5a52', t),
    sea1: lerpC('#274a63', '#2e3a50', t),
    sea2: new THREE.Color('#0c1a28'),
    sun: i >= 6 ? new THREE.Color('#ff7850') : new THREE.Color('#ffebb4'),
    sunI: i >= 6 ? 1.5 : 1.8
  };
}

var MAT = {};
function mat(key, opts) {
  if (!MAT[key]) MAT[key] = new THREE.MeshStandardMaterial(Object.assign({ flatShading: true, roughness: 0.82, metalness: 0.18 }, opts));
  return MAT[key];
}
function sideMats(side, boss) {
  if (boss) return { hull: mat('bossHull', { color: 0x2e2126 }), upper: mat('bossUp', { color: 0x4a3540 }) };
  return side === 'L'
    ? { hull: mat('lHull', { color: 0x33506b }), upper: mat('lUp', { color: 0x4d6f8f }) }
    : { hull: mat('rHull', { color: 0x5c3535 }), upper: mat('rUp', { color: 0x7d4f4f }) };
}
var deckMat = null, darkMat = null;

// ---------------- init
export function init(canvas) {
  renderer = new THREE.WebGLRenderer({ canvas: canvas, antialias: true });
  renderer.setClearColor(0x06090f);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.2;
  scene = new THREE.Scene();
  scene.fog = new THREE.Fog(0x7fa8c9, 1100, 3400);
  camera = new THREE.PerspectiveCamera(CAM_FOV, 1, 2, 9000);

  hemiLight = new THREE.HemisphereLight(0xbdd8ee, 0x24404f, 1.15);
  scene.add(hemiLight);
  sunLight = new THREE.DirectionalLight(0xfff0d0, 1.8);
  sunLight.position.set(0.35, 1, 0.55);
  scene.add(sunLight);

  deckMat = mat('deck', { color: 0x3b4a55 });
  darkMat = mat('dark', { color: 0x222a33 });

  camera.position.set(430, CAM_H, CAM_D);
  camera.lookAt(430, CAM_LOOK_Y, 0);
  camera.updateMatrixWorld();

  buildSky();
  buildWater();
  buildSeabed();
  buildClouds();
  buildParticles();
  buildAimMarker();
  setStage(0);
  return renderer;
}

export function resize(w, h, dpr) {
  W = w; H = h;
  renderer.setPixelRatio(Math.min(2, dpr || 1));
  renderer.setSize(w, h, false);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}

export function setStage(i) {
  var p = stagePalette(i);
  skyMat.uniforms.top.value.copy(p.top);
  skyMat.uniforms.mid.value.copy(p.mid);
  scene.fog.color.copy(p.mid);
  waterMat.uniforms.cNear.value.copy(p.sea1);
  waterMat.uniforms.cDeep.value.copy(p.sea2);
  waterMat.uniforms.fogColor.value.copy(p.mid);
  sunLight.color.copy(p.sun).lerp(new THREE.Color(0xffffff), 0.35);
  sunLight.intensity = p.sunI;
  sunSprite.material.color.copy(p.sun);
}

// ---------------- sky / sun / clouds
function buildSky() {
  skyMat = new THREE.ShaderMaterial({
    uniforms: { top: { value: new THREE.Color('#26425e') }, mid: { value: new THREE.Color('#7fa8c9') } },
    vertexShader: 'varying vec3 vP; void main(){ vP = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
    fragmentShader: 'uniform vec3 top; uniform vec3 mid; varying vec3 vP;' +
      'void main(){ float y = normalize(vP).y;' +
      ' vec3 c = mix(mid, top, clamp(y * 2.2, 0.0, 1.0));' +
      ' c = mix(c, mid * 0.22, smoothstep(0.0, -0.06, y));' + // below horizon: dark, so it never glows through the water
      ' gl_FragColor = vec4(pow(c, vec3(0.4545)), 1.0); }',
    side: THREE.BackSide, depthWrite: false
  });
  var sky = new THREE.Mesh(new THREE.SphereGeometry(6500, 24, 12), skyMat);
  sky.name = 'sky';
  scene.add(sky);

  sunSprite = new THREE.Sprite(new THREE.SpriteMaterial({
    map: radialTex('sun'), color: 0xffebb4, transparent: true, opacity: 0.95,
    blending: THREE.AdditiveBlending, depthWrite: false
  }));
  sunSprite.scale.set(380, 380, 1);
  scene.add(sunSprite);
}

function radialTex(kind) {
  if (texCache[kind]) return texCache[kind];
  var c = document.createElement('canvas'); c.width = c.height = 128;
  var g = c.getContext('2d');
  var grd = g.createRadialGradient(64, 64, 4, 64, 64, 64);
  if (kind === 'sun') { grd.addColorStop(0, 'rgba(255,255,255,1)'); grd.addColorStop(0.25, 'rgba(255,255,230,0.85)'); grd.addColorStop(1, 'rgba(255,240,200,0)'); }
  else if (kind === 'boom') { grd.addColorStop(0, 'rgba(255,245,200,1)'); grd.addColorStop(0.35, 'rgba(255,150,50,0.9)'); grd.addColorStop(1, 'rgba(80,40,20,0)'); }
  else if (kind === 'smoke') { grd.addColorStop(0, 'rgba(70,72,78,0.65)'); grd.addColorStop(1, 'rgba(60,60,66,0)'); }
  else if (kind === 'cloud') { grd.addColorStop(0, 'rgba(255,255,255,0.85)'); grd.addColorStop(0.6, 'rgba(255,255,255,0.35)'); grd.addColorStop(1, 'rgba(255,255,255,0)'); }
  else { grd.addColorStop(0, 'rgba(255,255,255,1)'); grd.addColorStop(1, 'rgba(255,255,255,0)'); }
  g.fillStyle = grd; g.fillRect(0, 0, 128, 128);
  var tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace; // canvas pixels are sRGB; untagged they render far too bright
  texCache[kind] = tex;
  return tex;
}

function buildClouds() {
  var tex = radialTex('cloud');
  for (var i = 0; i < 10; i++) {
    var s = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, opacity: 0.16 + (i % 3) * 0.06, depthWrite: false }));
    var sc = 260 + (i % 4) * 130;
    s.scale.set(sc * 1.9, sc * 0.7, 1);
    s.userData = { baseY: 320 + (i % 5) * 90, z: -700 - (i % 4) * 420, speed: 3 + (i % 3) * 2.2, off: i * 977 };
    clouds.push(s); scene.add(s);
  }
}

// ---------------- water
function buildWater() {
  waterMat = new THREE.ShaderMaterial({
    uniforms: {
      t: { value: 0 },
      cNear: { value: new THREE.Color('#274a63') },
      cDeep: { value: new THREE.Color('#0c1a28') },
      fogColor: { value: new THREE.Color('#7fa8c9') },
      camPos: { value: new THREE.Vector3() }
    },
    vertexShader:
      'uniform float t; varying vec3 vW; varying float vH;\n' +
      'void main(){ vec3 p = position;\n' +
      '  float h = sin(p.x*0.021 + t*1.35) * 2.4 + sin(p.x*0.043 - t*0.9 + p.z*0.05) * 1.5 + sin(p.z*0.06 + t*0.7) * 1.8;\n' +
      '  p.y += h; vH = h;\n' +
      '  vec4 wp = modelMatrix * vec4(p,1.0); vW = wp.xyz;\n' +
      '  gl_Position = projectionMatrix * viewMatrix * wp; }',
    fragmentShader:
      'uniform vec3 cNear; uniform vec3 cDeep; uniform vec3 fogColor; uniform vec3 camPos; uniform float t;\n' +
      'varying vec3 vW; varying float vH;\n' +
      'void main(){\n' +
      '  vec3 vd = normalize(camPos - vW);\n' +
      '  float fr = pow(1.0 - abs(vd.y), 2.5);\n' +
      '  vec3 col = mix(cNear, cDeep, 0.18 + fr * 0.4) * 1.35;\n' +
      '  float sp = sin(vW.x*0.71 + t*1.8) * sin(vW.z*0.93 - t*1.1) * sin(vW.x*0.217 - vW.z*0.31 + t*0.7);\n' +
      '  col += vec3(0.5,0.6,0.65) * pow(max(0.0, sp), 10.0) * 0.22;\n' +
      '  float d = length(camPos - vW);\n' +
      '  vec3 haze = mix(fogColor, cNear * 1.2, 0.3);\n' + // lighter with distance, just under the sky tone at the horizon
      '  col = mix(col, haze, smoothstep(700.0, 2800.0, d));\n' +
      '  gl_FragColor = vec4(pow(col, vec3(0.4545)), 0.86); }',
    transparent: true, depthWrite: false
  });
  waterMesh = new THREE.Mesh(new THREE.PlaneGeometry(9000, 7000, 200, 90), waterMat);
  waterMesh.rotation.x = -Math.PI / 2;
  waterMesh.position.set(2100, 0, -2600);
  waterMesh.renderOrder = 5;
  scene.add(waterMesh);
}

function buildSeabed() {
  seabed = new THREE.Mesh(new THREE.PlaneGeometry(9000, 7000),
    new THREE.MeshStandardMaterial({ color: 0x0a1622, roughness: 1, metalness: 0 }));
  seabed.rotation.x = -Math.PI / 2;
  seabed.position.set(2100, -240, -2600);
  scene.add(seabed);
}

// ---------------- particles (two pools: additive sparks, normal foam/smoke)
var pools = {};
function makePool(name, cap, additive) {
  var geo = new THREE.BufferGeometry();
  var pos = new Float32Array(cap * 3), col = new Float32Array(cap * 3);
  var size = new Float32Array(cap), alp = new Float32Array(cap);
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('pcolor', new THREE.BufferAttribute(col, 3));
  geo.setAttribute('psize', new THREE.BufferAttribute(size, 1));
  geo.setAttribute('palpha', new THREE.BufferAttribute(alp, 1));
  var m = new THREE.ShaderMaterial({
    uniforms: {},
    vertexShader:
      'attribute vec3 pcolor; attribute float psize; attribute float palpha;\n' +
      'varying vec3 vC; varying float vA;\n' +
      'void main(){ vC = pcolor; vA = palpha;\n' +
      '  vec4 mv = modelViewMatrix * vec4(position,1.0);\n' +
      '  gl_PointSize = psize * (620.0 / max(1.0,-mv.z));\n' +
      '  gl_Position = projectionMatrix * mv; }',
    fragmentShader:
      'varying vec3 vC; varying float vA;\n' +
      'void main(){ float d = length(gl_PointCoord - 0.5); if (d > 0.5) discard;\n' +
      '  float m = smoothstep(0.5, 0.1, d);\n' +
      '  gl_FragColor = vec4(pow(vC, vec3(0.4545)), vA * m); }',
    transparent: true, depthWrite: false,
    blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending
  });
  var pts = new THREE.Points(geo, m);
  pts.frustumCulled = false;
  pts.renderOrder = 8;
  scene.add(pts);
  pools[name] = { geo: geo, cap: cap, n: 0, items: [], pos: pos, col: col, size: size, alp: alp };
}
function buildParticles() { makePool('add', 2048, true); makePool('nrm', 2600, false); }

function emit(pool, x, y, z, vx, vy, vz, life, size, color, grav, fade, drag) {
  var P = pools[pool];
  if (P.items.length >= P.cap) P.items.shift();
  P.items.push({ x: x, y: y, z: z, vx: vx, vy: vy, vz: vz, t: 0, life: life, size: size, c: color, g: grav || 0, fade: fade !== undefined ? fade : 1, drag: drag || 0 });
}

function stepParticles(dt) {
  ['add', 'nrm'].forEach(function (name) {
    var P = pools[name];
    var items = P.items;
    for (var i = items.length - 1; i >= 0; i--) {
      var p = items[i];
      p.t += dt;
      if (p.t >= p.life) { items.splice(i, 1); continue; }
      p.vy += p.g * dt;
      if (p.drag) { var dr = Math.max(0, 1 - p.drag * dt); p.vx *= dr; p.vy *= dr; p.vz *= dr; }
      p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
    }
    var n = Math.min(items.length, P.cap);
    for (var j = 0; j < n; j++) {
      var q = items[j], k = j * 3, fr = q.t / q.life;
      P.pos[k] = q.x; P.pos[k + 1] = q.y; P.pos[k + 2] = q.z;
      P.col[k] = q.c.r; P.col[k + 1] = q.c.g; P.col[k + 2] = q.c.b;
      P.size[j] = q.size * (1 + fr * 0.7);
      P.alp[j] = Math.max(0, (1 - fr)) * q.fade;
    }
    P.geo.setDrawRange(0, n);
    P.geo.attributes.position.needsUpdate = true;
    P.geo.attributes.pcolor.needsUpdate = true;
    P.geo.attributes.psize.needsUpdate = true;
    P.geo.attributes.palpha.needsUpdate = true;
  });
}

var C_FOAM = new THREE.Color(0xdceefb), C_SPARK = new THREE.Color(0xffc878),
    C_FIRE = new THREE.Color(0xff9040), C_SMOKE = new THREE.Color(0x3c4048),
    C_BUBBLE = new THREE.Color(0x9fd0e8), C_FLASH = new THREE.Color(0xfff2c0);

// ---------------- fx sprites (explosion cores / muzzle flashes / smoke puffs)
function fxSprite(tex, x, y, z, size, dur, additive, grow, color) {
  var m = new THREE.SpriteMaterial({
    map: radialTex(tex), transparent: true, depthWrite: false,
    blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending
  });
  if (color) m.color.set(color);
  var s = new THREE.Sprite(m);
  s.position.set(x, y, z);
  s.scale.set(size, size, 1);
  s.renderOrder = 9;
  scene.add(s);
  sprites.push({ s: s, t: 0, dur: dur, grow: grow || 1.6, from: size });
}
function stepSprites(dt) {
  for (var i = sprites.length - 1; i >= 0; i--) {
    var e = sprites[i];
    e.t += dt;
    var q = e.t / e.dur;
    if (q >= 1) { scene.remove(e.s); e.s.material.dispose(); sprites.splice(i, 1); continue; }
    var sc = e.from * (1 + q * e.grow);
    e.s.scale.set(sc, sc, 1);
    e.s.material.opacity = 1 - q;
  }
}

// ---------------- procedural geometry helpers
function box(w, h, d, m, x, y, z, ry) {
  var mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), m);
  mesh.position.set(x || 0, y || 0, z || 0);
  if (ry) mesh.rotation.y = ry;
  return mesh;
}
function cyl(r1, r2, h, m, x, y, z, rz) {
  var mesh = new THREE.Mesh(new THREE.CylinderGeometry(r1, r2, h, 8), m);
  mesh.position.set(x || 0, y || 0, z || 0);
  if (rz !== undefined) mesh.rotation.z = rz;
  return mesh;
}

// tapered ship hull: box with bow pinched to a point and stern raked
function hullGeo(len, beam, hgt) {
  var g = new THREE.BoxGeometry(len, hgt, beam, 5, 1, 1);
  var p = g.attributes.position;
  var hl = len / 2;
  for (var i = 0; i < p.count; i++) {
    var x = p.getX(i), y = p.getY(i), z = p.getZ(i);
    var fr = Math.max(0, (x - hl * 0.45) / (hl * 0.55));           // bow taper
    var br = Math.max(0, (-x - hl * 0.62) / (hl * 0.38));          // stern taper
    p.setZ(i, z * (1 - fr * 0.94) * (1 - br * 0.45));
    if (y < 0) {                                                    // keel narrows + rises at ends
      p.setZ(i, p.getZ(i) * 0.55);
      p.setY(i, y + (fr * 0.5 + br * 0.4) * hgt * 0.5);
    }
    if (y > 0 && fr > 0) p.setY(i, y + fr * hgt * 0.22);            // raised bow
  }
  g.computeVertexNormals();
  return g;
}

function turret(m, barrels, blen, scale) {
  scale = scale || 1;
  var g = new THREE.Group();
  g.add(box(7 * scale, 3.4 * scale, 6 * scale, m, 0, 1.4 * scale, 0));
  var n = barrels || 1;
  for (var i = 0; i < n; i++) {
    var b = cyl(0.55 * scale, 0.7 * scale, blen * scale, m, blen * scale * 0.5 + 2, 2 * scale, (i - (n - 1) / 2) * 1.7 * scale, Math.PI / 2);
    b.name = 'barrel';
    g.add(b);
  }
  return g;
}
function funnelMesh(m, s) {
  s = s || 1;
  return cyl(1.6 * s, 2.1 * s, 7 * s, m, 0, 3.5 * s, 0);
}
function mastMesh(m, h) {
  var g = new THREE.Group();
  g.add(cyl(0.35, 0.5, h, m, 0, h / 2, 0));
  g.add(box(6, 0.7, 0.7, m, 0, h * 0.75, 0));
  return g;
}

// ---------------- ship / sub / aircraft prototypes
function protoFor(unitKey, def, side, boss) {
  var key = unitKey + '|' + side + '|' + (boss ? 1 : 0);
  if (protoCache[key]) return protoCache[key];
  var M = sideMats(side, boss);
  var g = new THREE.Group();
  var L = def.len, hl = L / 2;
  var type = boss ? 'ship' : def.type;

  if (type === 'ship') {
    var beam = Math.max(7, L * 0.13), hgt = Math.max(5, L * 0.1);
    g.userData.lift = hgt * 0.32; // waterline sits below the deck, not mid-hull
    g.add(new THREE.Mesh(hullGeo(L, beam, hgt), M.hull));
    var deck = box(L * 0.86, 0.8, beam * 0.8, M.upper, -L * 0.03, hgt * 0.5, 0);
    g.add(deck);
    addSuper(g, unitKey, def, M, L, beam, hgt, boss);
  } else if (type === 'sub') {
    var r = Math.max(2.6, L * 0.062);
    var body = cyl(r, r, L * 0.72, M.hull, 0, 0, 0, Math.PI / 2);
    g.add(body);
    var nose = new THREE.Mesh(new THREE.SphereGeometry(r, 10, 8), M.hull); nose.position.x = L * 0.36; nose.scale.x = 2.2; g.add(nose);
    var tail = new THREE.Mesh(new THREE.SphereGeometry(r, 10, 8), M.hull); tail.position.x = -L * 0.36; tail.scale.x = 2.6; g.add(tail);
    g.add(box(L * 0.16, r * 2.1, r * 0.55, M.upper, L * 0.02, r * 1.6, 0));          // sail
    g.add(cyl(0.3, 0.3, r * 1.6, M.upper, L * 0.05, r * 3.1, 0));                    // periscope
    g.add(box(1.2, r * 2.4, r * 1.9, M.upper, -L * 0.42, 0, 0));                     // tail fin
    g.traverse(function (o) {
      if (o.material) {
        o.material = o.material.clone();
        o.material.transparent = true; o.material.opacity = 0.92;
        // slight self-glow so the hull stays readable through the water tint
        o.material.emissive.copy(o.material.color).multiplyScalar(0.45);
      }
    });
  } else { // air
    buildAircraft(g, unitKey, def, M);
  }
  protoCache[key] = g;
  return g;
}

function addSuper(g, unitKey, def, M, L, beam, hgt, boss) {
  var U = M.upper, y0 = hgt * 0.5;
  function block(w, h, x, tall) { g.add(box(w, h, beam * (tall ? 0.62 : 0.78), U, x, y0 + h / 2, 0)); }
  switch (boss ? 'boss' : unitKey) {
    case 'patrol_ship':
      block(12, 5, 0); g.add(turret(U, 1, 6, 0.55)).children.slice(-1)[0].position.set(9, y0 + 1.5, 0);
      break;
    case 'frigate':
      block(16, 6, -3); g.add(mastMesh(U, 9)).children.slice(-1)[0].position.set(-1, y0 + 6, 0);
      var t1 = turret(U, 1, 6, 0.6); t1.position.set(12, y0, 0); g.add(t1);
      break;
    case 'destroyer':
      block(20, 6, -4); block(8, 4, 0, true);
      var mm = mastMesh(U, 8); mm.position.set(0, y0 + 10, 0); g.add(mm);
      var td = turret(U, 1, 7, 0.7); td.position.set(17, y0, 0); g.add(td);
      var td2 = turret(U, 1, 6, 0.6); td2.position.set(-20, y0, 0); g.add(td2);
      break;
    case 'light_cruiser':
      block(26, 7, -5); block(11, 5, -2, true);
      var mc = mastMesh(U, 10); mc.position.set(-2, y0 + 12, 0); g.add(mc);
      g.add(funnelMesh(U, 1)).children.slice(-1)[0].position.set(-14, y0 + 7, 0);
      [[19, 1], [27, 1], [-26, 1]].forEach(function (tc) {
        var t = turret(U, 2, 8, 0.75); t.position.set(tc[0], y0, 0); g.add(t);
      });
      break;
    case 'heavy_cruiser':
      block(30, 8, -6); block(13, 5, -3, true);
      var mh = mastMesh(U, 11); mh.position.set(-3, y0 + 13, 0); g.add(mh);
      var f1 = funnelMesh(U, 1.1); f1.position.set(-17, y0 + 8, 0); g.add(f1);
      var f2 = funnelMesh(U, 1.0); f2.position.set(-8, y0 + 8, 0); g.add(f2);
      [[21, 2], [30, 2], [-29, 2]].forEach(function (tc) {
        var t = turret(U, tc[1], 10, 0.85); t.position.set(tc[0], y0, 0); g.add(t);
      });
      break;
    case 'hybrid_cruiser':
      block(24, 7, -14);
      var pad = box(L * 0.42, 1, beam * 0.9, deckMat, L * 0.24, y0 + 0.6, 0); g.add(pad);
      var mhc = mastMesh(U, 9); mhc.position.set(-16, y0 + 7, 0); g.add(mhc);
      [[-27, 2], [-17, 2]].forEach(function (tc) {
        var t = turret(U, tc[1], 9, 0.8); t.position.set(tc[0], y0, 0); g.add(t);
      });
      break;
    case 'battleship':
      block(34, 10, -6); block(17, 7, -1, true);
      var mb = mastMesh(U, 14); mb.position.set(-2, y0 + 17, 0); g.add(mb);
      var fb = funnelMesh(U, 1.3); fb.position.set(-19, y0 + 10, 0); g.add(fb);
      [[25, 3, 1.15], [39, 3, 1.05], [-38, 3, 1.15]].forEach(function (tc) {
        var t = turret(U, tc[1], 12, tc[2]); t.position.set(tc[0], y0, 0); g.add(t);
      });
      var ts = turret(U, 2, 7, 0.6); ts.position.set(10, y0 + 7, 0); g.add(ts);
      break;
    case 'hybrid_battleship':
      block(28, 10, -18); block(13, 6, -20, true);
      var mhb = mastMesh(U, 12); mhb.position.set(-14, y0 + 16, 0); g.add(mhb);
      var padb = box(L * 0.4, 1, beam * 0.92, deckMat, L * 0.26, y0 + 0.6, 0); g.add(padb);
      [[-45, 3, 1.1], [-30, 3, 1.0]].forEach(function (tc) {
        var t = turret(U, tc[1], 12, tc[2]); t.position.set(tc[0], y0, 0); g.add(t);
      });
      break;
    case 'carrier':
      var deck = box(L * 0.96, 2, beam * 1.5, deckMat, 0, y0 + 3, 0); g.add(deck);
      // deck stripe
      g.add(box(L * 0.86, 0.4, 1.4, mat('stripe', { color: 0xc8d2da }), 0, y0 + 4.3, 0));
      block(14, 8, 12); g.children.slice(-1)[0].position.z = beam * 0.85;
      var mca = mastMesh(U, 8); mca.position.set(16, y0 + 8, beam * 0.85); g.add(mca);
      break;
    case 'boss':
      var hl = L / 2;
      if (def.hangar) { // midway: carrier boss
        var deckb = box(L * 0.94, 2.4, beam * 1.5, deckMat, 0, y0 + 3.2, 0); g.add(deckb);
        block(16, 9, hl * 0.3); g.children.slice(-1)[0].position.z = beam * 0.85;
      } else {
        block(hl * 0.8, 12, -hl * 0.1); block(hl * 0.35, 9, 0, true);
        var mbs = mastMesh(U, 16); mbs.position.set(0, y0 + 21, 0); g.add(mbs);
        var fbs = funnelMesh(U, 1.5); fbs.position.set(-hl * 0.35, y0 + 12, 0); g.add(fbs);
        [[hl * 0.55, 3, 1.35], [hl * 0.78, 3, 1.2], [-hl * 0.72, 3, 1.35]].forEach(function (tc) {
          var t = turret(U, tc[1], 14, tc[2]); t.position.set(tc[0], y0, 0); g.add(t);
        });
        var tbs = turret(U, 2, 8, 0.7); tbs.position.set(hl * 0.3, y0 + 9, 0); g.add(tbs);
      }
      break;
    default:
      block(16, 6, 0);
  }
}

function buildAircraft(g, unitKey, def, M) {
  if (unitKey === 'helicopter') {
    var body = new THREE.Mesh(new THREE.SphereGeometry(6, 10, 8), M.hull);
    body.scale.set(1.8, 1, 1); g.add(body);
    g.add(box(12, 1.6, 1.6, M.hull, -13, 1, 0));
    g.add(box(1.2, 5, 1.2, M.upper, -18, 3, 0));
    var rotor = box(30, 0.5, 1.6, mat('rotor', { color: 0xdce6f0, transparent: true, opacity: 0.55 }), 0, 7, 0);
    rotor.name = 'rotor'; g.add(rotor);
    g.add(cyl(0.5, 0.5, 3.5, M.upper, 0, 5, 0));
  } else if (unitKey === 'long_range_bomber' || unitKey === 'b52') {
    var big = unitKey === 'b52' ? 1.9 : 1;
    var fus = cyl(2.2 * big, 2.2 * big, 30 * big, M.hull, 0, 0, 0, Math.PI / 2);
    g.add(fus);
    var nose = new THREE.Mesh(new THREE.SphereGeometry(2.2 * big, 8, 6), M.hull); nose.position.x = 15 * big; g.add(nose);
    var wing = box(7 * big, 0.8, 42 * big, M.upper, 1 * big, 1, 0);
    wing.rotation.y = 0.22; g.add(wing);
    for (var e = 0; e < 2; e++) {
      g.add(cyl(1 * big, 1 * big, 4 * big, darkMat, -1, -0.8, (e ? 1 : -1) * 9 * big, Math.PI / 2));
      g.add(cyl(1 * big, 1 * big, 4 * big, darkMat, -3, -0.8, (e ? 1 : -1) * 16 * big, Math.PI / 2));
    }
    g.add(box(1, 6 * big, 1.4, M.upper, -14 * big, 3 * big, 0));
    g.add(box(1, 0.8, 12 * big, M.upper, -14 * big, 5.5 * big, 0));
  } else { // fighter / torpedo_bomber
    var tb = unitKey === 'torpedo_bomber';
    var s = tb ? 1.2 : 1;
    var fus2 = cyl(1.6 * s, 1.0 * s, 13 * s, M.hull, 0, 0, 0, Math.PI / 2);
    g.add(fus2);
    var nose2 = new THREE.Mesh(new THREE.SphereGeometry(1.6 * s, 8, 6), M.hull); nose2.position.x = 6.5 * s; g.add(nose2);
    var wing2 = box(4.5 * s, 0.5, 20 * s, M.upper, 0.5, 0.3, 0); g.add(wing2);
    g.add(box(1, 3.5 * s, 1, M.upper, -6.5 * s, 1.8 * s, 0));
    g.add(box(0.8, 0.5, 6 * s, M.upper, -6.5 * s, 3.2 * s, 0));
    var prop = box(0.5, 9 * s, 0.9, mat('rotor', { color: 0xdce6f0, transparent: true, opacity: 0.55 }), 8.2 * s, 0, 0);
    prop.name = 'rotor'; g.add(prop);
    if (tb) g.add(cyl(0.9, 0.9, 8, darkMat, 0, -2.2, 0, Math.PI / 2));
  }
}

// ---------------- bases
function buildBase(side) {
  var g = new THREE.Group();
  var main = mat(side === 'L' ? 'baseMainL' : 'baseMainR', { color: side === 'L' ? 0x42566b : 0x6b4242 });
  var dark = mat(side === 'L' ? 'baseDarkL' : 'baseDarkR', { color: side === 'L' ? 0x2c3c4d : 0x4d2c2c });
  g.add(box(190, 34, 120, dark, 0, -13, 0));           // breakwater slab
  g.add(box(160, 28, 96, main, -5, 16, 0));            // terraces
  g.add(box(104, 24, 78, main, -8, 42, 0));
  g.add(box(58, 20, 60, main, -3, 64, 0));
  g.add(box(24, 27, 22, dark, 6, 87, 0));              // command tower
  g.add(box(9, 10, 9, dark, 6, 106, 0));
  var radar = box(18, 1.6, 2.4, mat('radar', { color: 0x9fb8cc }), 0, 4, 0);
  var radarPivot = new THREE.Group(); radarPivot.position.set(6, 108, 0); radarPivot.add(radar);
  radarPivot.name = 'radar'; g.add(radarPivot);
  // gun emplacements
  [[40, 56, 1.0], [58, 32, 1.15], [-42, 56, 0.9]].forEach(function (tc) {
    var t = turret(darkMat, 2, 12, tc[2]); t.position.set(tc[0], tc[1], 12); g.add(t);
  });
  // crane
  var crane = new THREE.Group();
  crane.add(cyl(1.4, 1.8, 50, dark, 0, 25, 0));
  var jib = box(38, 2, 2, dark, 15, 48, 0); jib.rotation.z = 0.35; crane.add(jib);
  crane.position.set(-66, 30, -20); g.add(crane);
  // flag
  var flag = box(13, 7, 0.5, mat(side === 'L' ? 'flagL' : 'flagR', { color: side === 'L' ? 0x5aa2e8 : 0xe85a5a }), 8, 0, 0);
  var flagPole = new THREE.Group(); flagPole.position.set(14, 108, 0); flagPole.add(flag);
  flagPole.name = 'flag'; g.add(flagPole);
  // player-manned battery (L only)
  if (side === 'L') {
    var bat = new THREE.Group();
    bat.add(new THREE.Mesh(new THREE.SphereGeometry(7.5, 10, 8), darkMat));
    var barrel = cyl(1.3, 1.7, 30, darkMat, 15, 0, 0, Math.PI / 2);
    barrel.rotation.z = Math.PI / 2; barrel.position.set(15, 0, 0);
    bat.add(barrel);
    bat.position.set(-4, 102, 0);
    bat.name = 'battery';
    g.add(bat);
  }
  if (side === 'R') g.rotation.y = Math.PI;
  scene.add(g);
  return { group: g, smokeT: 0 };
}

// shield dome
var shieldMeshes = {};
function shieldFor(side, bx) {
  if (!shieldMeshes[side]) {
    var m = new THREE.Mesh(new THREE.SphereGeometry(130, 24, 14, 0, Math.PI * 2, 0, Math.PI / 2),
      new THREE.MeshBasicMaterial({ color: 0x78c8ff, transparent: true, opacity: 0.16, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide }));
    m.position.set(bx, 0, 0);
    scene.add(m);
    shieldMeshes[side] = m;
  }
  return shieldMeshes[side];
}

// ---------------- aim marker
function buildAimMarker() {
  aimGroup = new THREE.Group();
  var ring = new THREE.Mesh(new THREE.TorusGeometry(16, 1.6, 8, 32),
    new THREE.MeshBasicMaterial({ color: 0xffb450, transparent: true, opacity: 0.9, depthWrite: false }));
  ring.rotation.x = Math.PI / 2;
  ring.name = 'ring';
  aimGroup.add(ring);
  var beam = new THREE.Mesh(new THREE.CylinderGeometry(0.8, 0.8, 70, 6),
    new THREE.MeshBasicMaterial({ color: 0xffb450, transparent: true, opacity: 0.35, blending: THREE.AdditiveBlending, depthWrite: false }));
  beam.position.y = 35; beam.name = 'beam';
  aimGroup.add(beam);
  aimGroup.renderOrder = 9;
  scene.add(aimGroup);
}

// ---------------- projectiles
function projProto(kind, side) {
  var key = 'p|' + kind + '|' + side;
  if (protoCache[key]) return protoCache[key];
  var g = new THREE.Group();
  if (kind === 'shell') {
    g.add(new THREE.Mesh(new THREE.SphereGeometry(1.7, 6, 5), new THREE.MeshBasicMaterial({ color: 0xffdc96 })));
    var tr = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 1.1, 10, 5),
      new THREE.MeshBasicMaterial({ color: 0xffc878, transparent: true, opacity: 0.5, blending: THREE.AdditiveBlending, depthWrite: false }));
    tr.rotation.z = Math.PI / 2; tr.position.x = -5; tr.name = 'trail';
    g.add(tr);
  } else if (kind === 'torpedo') {
    g.add(cyl(1.6, 1.6, 13, mat('torp', { color: 0x1e2830 }), 0, 0, 0, Math.PI / 2));
    var nose = new THREE.Mesh(new THREE.SphereGeometry(1.6, 6, 5), mat('torp', { color: 0x1e2830 })); nose.position.x = 6.5; g.add(nose);
  } else if (kind === 'missile') {
    g.add(cyl(1.1, 1.1, 10, mat('msl', { color: 0xc8ccd2 }), 0, 0, 0, Math.PI / 2));
    var mn = new THREE.Mesh(new THREE.ConeGeometry(1.1, 3, 6), mat('msl', { color: 0xc8ccd2 }));
    mn.rotation.z = -Math.PI / 2; mn.position.x = 6.5; g.add(mn);
    var fl = new THREE.Mesh(new THREE.SphereGeometry(1.6, 6, 5),
      new THREE.MeshBasicMaterial({ color: 0xffaa3c, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false }));
    fl.position.x = -6; fl.name = 'flame'; g.add(fl);
  } else if (kind === 'depthcharge') {
    g.add(cyl(2, 2, 5, mat('dc', { color: 0x39424c }), 0, 0, 0, Math.PI / 2));
  } else if (kind === 'flak') {
    g.add(new THREE.Mesh(new THREE.SphereGeometry(1.2, 5, 4), new THREE.MeshBasicMaterial({ color: 0xfff0c8 })));
  } else { // bullet tracer
    var b = new THREE.Mesh(new THREE.CylinderGeometry(0.35, 0.35, 8, 4),
      new THREE.MeshBasicMaterial({ color: 0xfff5c8, transparent: true, opacity: 0.85, blending: THREE.AdditiveBlending, depthWrite: false }));
    b.rotation.z = Math.PI / 2;
    g.add(b);
  }
  protoCache[key] = g;
  return g;
}

// ---------------- sync from sim state
export function syncUnits(st, t, zOffsetFn) {
  var seen = {};
  for (var i = 0; i < st.units.length; i++) {
    var u = st.units[i];
    seen[u.id] = true;
    var entry = unitMeshes[u.id];
    if (!entry) {
      var proto = protoFor(u.unit, u.def, u.side, u.boss);
      var gclone = proto.clone();
      scene.add(gclone);
      entry = unitMeshes[u.id] = { group: gclone, unit: u.unit, type: u.type, side: u.side, boss: u.boss, def: u.def };
    }
    var g = entry.group;
    var z = zOffsetFn ? zOffsetFn(u) : 0;
    var bob = u.type === 'ship' ? Math.sin(t * 1.6 + u.id * 1.7) * 1.6 : 0;
    var ay = u.type === 'air' ? Math.min(-u.y, AIR_MAX_WORLD_Y) : -u.y;
    g.position.set(u.x, ay + bob + (u.type === 'ship' ? (g.userData.lift || 0) : 0), z);
    g.rotation.y = u.dir === 1 ? 0 : Math.PI;
    if (u.type === 'ship') g.rotation.x = Math.sin(t * 1.1 + u.id * 2.3) * 0.03;
    if (u.type === 'air') {
      g.rotation.z = Math.sin(t * 1.3 + u.bobPhase) * 0.08;
      var rotor = g.getObjectByName('rotor');
      if (rotor) {
        if (entry.unit === 'helicopter') rotor.rotation.y += 0.9;
        else rotor.rotation.x += 1.1;
      }
    }
    // wake foam for moving surface ships (throttled)
    if (u.type === 'ship' && Math.random() < 0.3) {
      emit('nrm', u.x - u.dir * u.def.len * 0.5, 1.5, z + (Math.random() - 0.5) * 4,
        -u.dir * 6, 2 + Math.random() * 3, (Math.random() - 0.5) * 4, 1.1, 3.2, C_FOAM, -2, 0.5);
    }
    if (u.type === 'sub' && Math.random() < 0.12) {
      emit('nrm', u.x - u.dir * u.def.len * 0.4, -u.y, z, -u.dir * 3, 8, 0, 1.6, 1.6, C_BUBBLE, 6, 0.5);
    }
  }
  for (var id in unitMeshes) {
    if (!seen[id]) { scene.remove(unitMeshes[id].group); delete unitMeshes[id]; }
  }
}

export function syncProjectiles(st) {
  var seen = {};
  for (var i = 0; i < st.projectiles.length; i++) {
    var p = st.projectiles[i];
    seen[p.id] = true;
    var m = projMeshes[p.id];
    if (!m) {
      m = projProto(p.kind, p.side).clone();
      scene.add(m);
      projMeshes[p.id] = m;
    }
    m.position.set(p.x, -p.y, 0);
    if (p.vx !== undefined) {
      var ang = Math.atan2(-(p.vy || 0), p.vx);
      m.rotation.z = ang;
    }
    if (p.kind === 'torpedo' && !p.dropping && Math.random() < 0.5) {
      emit('nrm', p.x - Math.sign(p.vx) * 8, -p.y, 0, -Math.sign(p.vx) * 4, 10, 0, 1.4, 1.5, C_BUBBLE, 8, 0.45);
    }
    if (p.kind === 'missile' && Math.random() < 0.7) {
      emit('nrm', p.x, -p.y, 0, (Math.random() - 0.5) * 4, (Math.random() - 0.5) * 4, 0, 1.8, 3.4, C_SMOKE, 4, 0.5, 1.2);
    }
  }
  for (var id in projMeshes) {
    if (!seen[id]) { scene.remove(projMeshes[id]); delete projMeshes[id]; }
  }
}

export function syncBases(st, t, aim, firing, dt) {
  ['L', 'R'].forEach(function (side) {
    var b = side === 'L' ? st.baseL : st.baseR;
    if (!baseGroups[side]) baseGroups[side] = buildBase(side);
    var e = baseGroups[side];
    e.group.position.set(b.x, 0, 0);
    var radar = e.group.getObjectByName('radar');
    if (radar) radar.rotation.y = Math.sin(t * 1.8) * 1.1 + (side === 'R' ? Math.PI : 0);
    if (side === 'L' && aim) {
      var bat = e.group.getObjectByName('battery');
      if (bat) {
        var fracA = (aim.range - aim.min) / (aim.max - aim.min);
        bat.rotation.z = 0.1 + fracA * 0.62;
      }
    }
    // damage smoke
    var frac = b.hp / b.maxHp;
    if (frac < 0.6) {
      e.smokeT -= dt;
      if (e.smokeT <= 0) {
        e.smokeT = 0.12;
        emit('nrm', b.x + (Math.random() - 0.5) * 70, 60 + Math.random() * 30, (Math.random() - 0.5) * 40,
          (Math.random() - 0.5) * 6, 22 + Math.random() * 10, 0, 2.4, 9, C_SMOKE, 2, 0.55, 0.4);
      }
    }
    // shield
    var sh = shieldFor(side, b.x);
    sh.visible = !!b.invincible;
    if (b.invincible) sh.material.opacity = 0.10 + 0.07 * Math.sin(t * 6);
  });
}

export function updateAimMarker(st, firing, visible) {
  if (!st || !st.playerAim || !visible) { aimGroup.visible = false; return; }
  aimGroup.visible = true;
  var x = st.baseL.x + st.playerAim.range;
  aimGroup.position.set(x, 2, 0);
  var col = firing ? 0xffb450 : 0x78c8ff;
  aimGroup.getObjectByName('ring').material.color.set(col);
  aimGroup.getObjectByName('beam').material.color.set(col);
  aimGroup.rotation.y = simTime * 0.8;
}

// ---------------- events -> 3D fx
export function spawnEffect(e) {
  switch (e.type) {
    case 'fire':
      if (e.kind === 'shell') {
        fxSprite('boom', e.x + (e.dir || 1) * 6, -e.y + 4, 2, e.big ? 16 : 9, 0.14, true, 0.8);
        var n = e.big ? 5 : 3;
        for (var i = 0; i < n; i++) emit('nrm', e.x + (e.dir || 1) * 8, -e.y + 4, (Math.random() - 0.5) * 4, (e.dir || 1) * (20 + Math.random() * 20), 6 + Math.random() * 8, (Math.random() - 0.5) * 8, 0.9, 3.5, C_SMOKE, -3, 0.5, 1.5);
      } else if (e.kind === 'missile') {
        fxSprite('boom', e.x, -e.y, 2, 7, 0.2, true, 1.2);
      }
      break;
    case 'hit':
      if (!e.deflect) fxSprite('boom', e.x, -e.y, 3, (e.size || 6) * 1.1, 0.22, true, 1.0);
      break;
    case 'explosion':
      boom(e.x, -e.y, e.size || 14, e.water);
      break;
    case 'splash':
      splash(e.x, e.size || 8);
      break;
    case 'death':
      spawnWreck(e);
      boom(e.x, -e.y, Math.min(40, 10 + (e.len || 40) * 0.25), false);
      break;
    case 'basedown':
      boom(e.x, 30, 60, false);
      for (var j = 0; j < 24; j++) emit('add', e.x + (Math.random() - 0.5) * 120, 20 + Math.random() * 80, (Math.random() - 0.5) * 80, (Math.random() - 0.5) * 90, 30 + Math.random() * 80, (Math.random() - 0.5) * 60, 2.2, 5, C_FIRE, -60, 1);
      break;
  }
}

function boom(x, y, size, water) {
  fxSprite('boom', x, y, 4, size * 1.6, 0.55, true, 1.7);
  fxSprite('smoke', x, y + size * 0.3, 3, size * 1.3, 1.1, false, 2.0);
  var n = Math.min(16, 4 + Math.floor(size * 0.4));
  for (var i = 0; i < n; i++) {
    var a = Math.random() * Math.PI * 2, sp = 25 + Math.random() * size * 3;
    emit('add', x, y, 3, Math.cos(a) * sp, Math.abs(Math.sin(a)) * sp + 15, (Math.random() - 0.5) * sp * 0.6, 0.7 + Math.random() * 0.5, 2.6, C_SPARK, -110, 1);
  }
  if (water || y <= 4) splash(x, size * 0.8);
}

function splash(x, size) {
  var n = Math.min(14, 4 + Math.floor(size * 0.8));
  for (var i = 0; i < n; i++) {
    emit('nrm', x + (Math.random() - 0.5) * 6, 1, (Math.random() - 0.5) * 6,
      (Math.random() - 0.5) * 16, 35 + Math.random() * size * 5, (Math.random() - 0.5) * 16,
      0.8 + Math.random() * 0.4, 2.8, C_FOAM, -130, 0.85);
  }
  fxSprite('smoke', x, 4, 2, size * 0.8, 0.45, false, 1.5, 0xcfe6f5);
}

// wrecks: dark hull sinking / plane falling
function spawnWreck(e) {
  var m;
  if (e.utype === 'air') {
    m = box(e.len * 0.5, 2, 4, mat('wreck', { color: 0x2a2f36 }), e.x, -e.y, 0);
    wrecks.push({ mesh: m, t: 0, dur: 4, kind: 'air', vy: 0, x: e.x, y: -e.y });
  } else {
    m = new THREE.Mesh(hullGeo(e.len, Math.max(6, e.len * 0.12), Math.max(4, e.len * 0.09)), mat('wreck2', { color: 0x1c242c, transparent: true, opacity: 1 }));
    m.position.set(e.x, -e.y, 0);
    wrecks.push({ mesh: m, t: 0, dur: 6, kind: 'ship', x: e.x });
  }
  scene.add(m);
}
function stepWrecks(dt) {
  for (var i = wrecks.length - 1; i >= 0; i--) {
    var w = wrecks[i];
    w.t += dt;
    if (w.t >= w.dur) { scene.remove(w.mesh); wrecks.splice(i, 1); continue; }
    if (w.kind === 'air') {
      w.vy -= 60 * dt;
      w.mesh.position.y += w.vy * dt;
      w.mesh.rotation.z += 3 * dt; w.mesh.rotation.x += 2 * dt;
      if (Math.random() < 0.5) emit('nrm', w.mesh.position.x, w.mesh.position.y + 3, 0, 0, 6, 0, 1.2, 3.5, C_SMOKE, 2, 0.5);
      if (w.mesh.position.y <= 0) { splash(w.mesh.position.x, 8); scene.remove(w.mesh); wrecks.splice(i, 1); }
    } else {
      var q = w.t / w.dur;
      w.mesh.position.y = -q * 44;
      w.mesh.rotation.z = q * 0.55 * (Math.floor(w.x) % 2 === 0 ? 1 : -1);
      if (Math.random() < 0.35) emit('nrm', w.x + (Math.random() - 0.5) * 30, 1, 0, 0, 10, 0, 1.2, 2, C_BUBBLE, 6, 0.5);
    }
  }
}

// ---------------- B-52 flyover
export function updateB52(run, st) {
  if (!run) { if (b52Mesh) b52Mesh.visible = false; return; }
  if (!b52Mesh) {
    b52Mesh = new THREE.Group();
    buildAircraft(b52Mesh, 'b52', { len: 60 }, { hull: mat('b52', { color: 0x12161c }), upper: mat('b52u', { color: 0x1c222c }) });
    scene.add(b52Mesh);
  }
  b52Mesh.visible = true;
  var prog = Math.max(0, Math.min(1, (st.t - run.startT) / run.duration));
  var x = run.startX + (run.endX - run.startX) * prog;
  b52Mesh.position.set(x, 158, -40);
  b52Mesh.rotation.y = 0;
  if (Math.random() < 0.8) emit('nrm', x - 40, 156, -40, -30, 0, 0, 1.4, 5, new THREE.Color(0xffffff), 0, 0.25, 0.5);
}

// ---------------- title demo ship
export function setTitle(on, t) {
  if (on && !titleShip) {
    var S = window.Sim2D;
    titleShip = protoFor('battleship', S.UNITS.battleship, 'L', false).clone();
    scene.add(titleShip);
  }
  if (titleShip) {
    titleShip.visible = on;
    if (on) {
      var x = (t * 24) % 1600 + 300;
      titleShip.position.set(x, Math.sin(t * 1.4) * 2, 40);
      titleShip.rotation.x = Math.sin(t * 1.1) * 0.04;
      if (Math.random() < 0.4) emit('nrm', x - 55, 1.5, 40, -6, 3, 0, 1.1, 3.5, C_FOAM, -2, 0.5);
    }
  }
}

// ---------------- camera & render
var _v = new THREE.Vector3();
var camState = { x: 0 };

// world x where the ray through NDC (nx, 0) crosses the lane plane z=0
function worldXAtNdc(nx) {
  _v.set(nx, 0, 0.5).unproject(camera);
  var dx = _v.x - camera.position.x, dz = _v.z - camera.position.z;
  if (Math.abs(dz) < 1e-6) return camera.position.x;
  var t = (0 - camera.position.z) / dz;
  return camera.position.x + dx * t;
}
export function viewW() {
  camera.updateMatrixWorld();
  var w = worldXAtNdc(1) - worldXAtNdc(-1);
  return (w > 10 && isFinite(w)) ? w : 800;
}
export function pxPerWorld() { return W / viewW(); }

export function worldToScreen(x, ySim, z) {
  _v.set(x, -(ySim || 0), z || 0);
  _v.project(camera);
  return { x: (_v.x * 0.5 + 0.5) * W, y: (-_v.y * 0.5 + 0.5) * H, behind: _v.z > 1 };
}

export function render(camX, shx, shy, t, dt) {
  simTime = t;
  camState.x += (camX - camState.x) * Math.min(1, dt * 14);
  var cx = camState.x + viewW() / 2;
  camera.position.set(cx + shx * 0.6, CAM_H + shy * 0.8, CAM_D);
  camera.lookAt(cx + shx * 0.6, CAM_LOOK_Y + shy * 0.8, 0);
  // keep big static geometry centred on the camera so edges never show
  waterMesh.position.x = cx; seabed.position.x = cx;
  var skyM = scene.getObjectByName('sky'); if (skyM) skyM.position.x = cx;
  sunSprite.position.set(cx + 900, 500, -3000);
  waterMat.uniforms.t.value = t;
  waterMat.uniforms.camPos.value.copy(camera.position);
  for (var i = 0; i < clouds.length; i++) {
    var c = clouds[i];
    var span = 5200;
    var xx = ((c.userData.off + t * c.userData.speed - cx * 0.12) % span + span) % span;
    c.position.set(cx - span / 2 + xx, c.userData.baseY, c.userData.z);
  }
  stepParticles(dt);
  stepSprites(dt);
  stepWrecks(dt);
  renderer.render(scene, camera);
}

export function clearMatch() {
  for (var id in unitMeshes) { scene.remove(unitMeshes[id].group); }
  for (var pid in projMeshes) { scene.remove(projMeshes[pid]); }
  unitMeshes = {}; projMeshes = {};
  wrecks.forEach(function (w) { scene.remove(w.mesh); }); wrecks = [];
  sprites.forEach(function (s) { scene.remove(s.s); }); sprites = [];
  pools.add.items.length = 0; pools.nrm.items.length = 0;
  if (b52Mesh) b52Mesh.visible = false;
}
