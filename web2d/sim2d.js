/* Iron Corridor 2D — Black Navy War style lane battle sim.
 * Pure deterministic core: no DOM, runs in browser and node (headless tests).
 * Unit/boss stats extracted from Black Navy War: Re (Godot scenes); economy/costs original.
 */
(function (root, factory) {
  if (typeof module !== 'undefined' && module.exports) module.exports = factory();
  else root.Sim2D = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  var WORLD = 4200;
  var DT = 1 / 30;
  var BASE_HP = 5000;

  // ---- weapons: dmg per hit, reload s, range px, projectile kind, muzzle speed
  var WEAPONS = {
    mg:    { dmg: 10,  reload: 0.5,  range: 270, proj: 'bullet', speed: 500, targets: { air: 1, ship: 1, base: 1 } },
    aa:    { dmg: 20,  reload: 1.6,  range: 340, proj: 'flak',   speed: 350, targets: { air: 1 } },
    g152:  { dmg: 46,  reload: 1.8,  range: 500, proj: 'shell',  speed: 360, targets: { ship: 1, base: 1 } },
    g203:  { dmg: 62,  reload: 2.6,  range: 620, proj: 'shell',  speed: 390, targets: { ship: 1, base: 1 } },
    g280:  { dmg: 80,  reload: 3.0,  range: 640, proj: 'shell',  speed: 400, targets: { ship: 1, base: 1 } },
    g305:  { dmg: 92,  reload: 3.6,  range: 660, proj: 'shell',  speed: 405, targets: { ship: 1, base: 1 } },
    g330:  { dmg: 100, reload: 3.4,  range: 680, proj: 'shell',  speed: 410, targets: { ship: 1, base: 1 } },
    g380:  { dmg: 112, reload: 3.4,  range: 700, proj: 'shell',  speed: 415, targets: { ship: 1, base: 1 } },
    g381:  { dmg: 115, reload: 3.2,  range: 720, proj: 'shell',  speed: 420, targets: { ship: 1, base: 1 } },
    g406:  { dmg: 135, reload: 3.2,  range: 740, proj: 'shell',  speed: 430, targets: { ship: 1, base: 1 } },
    g460:  { dmg: 160, reload: 3.4,  range: 780, proj: 'shell',  speed: 440, targets: { ship: 1, base: 1 } },
    torp:  { dmg: 95,  reload: 7.0,  range: 380, proj: 'torpedo', speed: 100, targets: { ship: 1, sub: 1, base: 1 } },
    atorp: { dmg: 75,  reload: 6.0,  range: 300, proj: 'torpedo', speed: 110, targets: { ship: 1, base: 1 } },
    ntorp: { dmg: 95,  reload: 7.0,  range: 550, proj: 'torpedo', speed: 110, targets: { ship: 1, sub: 1, base: 1 } },
    dc:    { dmg: 24,  reload: 4.0,  range: 250, proj: 'depthcharge', speed: 90, targets: { sub: 1 }, n: 4 },
    msl:   { dmg: 60,  reload: 3.2,  range: 700, proj: 'missile', speed: 210, targets: { ship: 1, air: 1, base: 1 } },
    fort:  { dmg: 90,  reload: 3.0,  range: 680, proj: 'shell',  speed: 620, targets: { ship: 1 }, aoe: 55 },
    btorp: { dmg: 95,  reload: 4.5,  range: 360, proj: 'torpedo', speed: 100, targets: { ship: 1, sub: 1 } },
    lrm:   { dmg: 140, reload: 5.5,  range: 1000, proj: 'missile', speed: 240, targets: { ship: 1, base: 1 } }
  };

  // ---- units (hp/speed/detect/minDist from BNW:Re scene dump; cost/cd original)
  var UNITS = {
    patrol_ship:      { name: 'Patrol Boat',    type: 'ship', hp: 40,   speed: 90,  cost: 60,   cd: 2.6,  detect: 300, minDist: 200, len: 34, weapons: ['mg'] },
    frigate:          { name: 'Frigate',        type: 'ship', hp: 100,  speed: 60,  cost: 130,  cd: 4.5,  detect: 300, minDist: 180, len: 44, weapons: ['mg', 'mg', 'dc'] },
    submarine:        { name: 'Submarine',      type: 'sub',  hp: 100,  speed: 25,  cost: 160,  cd: 5.5,  detect: 400, minDist: 150, len: 46, depth: 55, weapons: ['torp'] },
    fighter:          { name: 'Fighter',        type: 'air',  hp: 60,   speed: 150, cost: 140,  cd: 5,    detect: 250, minDist: 0,   len: 26, alt: -170, weapons: ['mg', 'mg'] },
    torpedo_bomber:   { name: 'Torpedo Bomber', type: 'air',  hp: 100,  speed: 120, cost: 180,  cd: 5.5,  detect: 400, minDist: 0,   len: 30, alt: -130, weapons: ['atorp'] },
    helicopter:       { name: 'Helicopter',     type: 'air',  hp: 80,   speed: 60,  cost: 170,  cd: 5.5,  detect: 400, minDist: 100, len: 26, alt: -100, weapons: ['mg', 'dc'] },
    destroyer:        { name: 'Destroyer',      type: 'ship', hp: 140,  speed: 37,  cost: 220,  cd: 8.5,  detect: 300, minDist: 200, len: 56, weapons: ['torp', 'mg', 'aa', 'aa'] },
    light_cruiser:    { name: 'Light Cruiser',  type: 'ship', hp: 250,  speed: 34,  cost: 330,  cd: 11.5, detect: 480, minDist: 220, len: 66, weapons: ['g152', 'g152', 'g152', 'g152', 'aa', 'aa'] },
    heavy_cruiser:    { name: 'Heavy Cruiser',  type: 'ship', hp: 300,  speed: 32,  cost: 460,  cd: 14,   detect: 750, minDist: 600, len: 74, weapons: ['g203', 'g203', 'g203', 'aa', 'aa', 'msl'] },
    hybrid_cruiser:   { name: 'Hybrid Cruiser', type: 'ship', hp: 275,  speed: 32,  cost: 480,  cd: 14,   detect: 620, minDist: 250, len: 72, weapons: ['g203', 'g203', 'aa', 'aa'], hangar: 1, hangarUnit: 'helicopter', unlock: 4 },
    battleship:       { name: 'Battleship',     type: 'ship', hp: 3400, speed: 29,  cost: 950,  cd: 25,   detect: 620, minDist: 400, len: 110, weapons: ['g381', 'g381', 'g381', 'g152', 'g152', 'mg', 'mg', 'aa', 'aa', 'aa'] },
    hybrid_battleship:{ name: 'Hybrid Battleship', type: 'ship', hp: 2250, speed: 29, cost: 1000, cd: 26, detect: 620, minDist: 400, len: 106, weapons: ['g381', 'g381', 'aa', 'aa', 'aa', 'mg'], hangar: 2, hangarUnit: 'torpedo_bomber', unlock: 6 },
    carrier:          { name: 'Carrier',        type: 'ship', hp: 1800, speed: 30,  cost: 1150, cd: 28,   detect: 800, minDist: 700, len: 120, weapons: ['aa', 'aa', 'aa', 'aa', 'mg', 'mg', 'mg'], hangar: 3, hangarUnit: 'mixed' },
    atomic_submarine: { name: 'Atomic Submarine', type: 'sub', hp: 1200, speed: 24, cost: 1050, cd: 28,  detect: 800, minDist: 500, len: 96, depth: 78, weapons: ['ntorp', 'ntorp', 'msl', 'msl', 'msl'], unlock: 8 },
    // holds at minDist 900 - beyond every weapon range in the game (max is
    // 780, the yamato boss's g460) - so it never takes fire in exchange for
    // a slow, single long-range missile. Player-only: never appears in any
    // stage's spawn list, same pattern as the other unlock-gated units.
    long_range_bomber: { name: 'Long-Range Bomber', type: 'air', hp: 150, speed: 90, cost: 950, cd: 22, detect: 1050, minDist: 900, len: 34, alt: -210, weapons: ['lrm'], unlock: 4 }
  };

  var BOSSES = {
    dreadnought: { name: 'Dreadnought', hp: 4000,  speed: 15,   minDist: 250,  len: 130, weapons: ['g305', 'g305', 'g305', 'g305', 'g305', 'mg', 'mg'] },
    seydlitz:    { name: 'Seydlitz',    hp: 4500,  speed: 17,   minDist: 250,  len: 130, weapons: ['g280', 'g280', 'g280', 'g280', 'aa', 'mg'] },
    dunkerque:   { name: 'Dunkerque',   hp: 5500,  speed: 20,   minDist: 300,  len: 136, weapons: ['g330', 'g330', 'g330', 'g330', 'aa', 'aa'] },
    bismarck:    { name: 'Bismarck',    hp: 6000,  speed: 21,   minDist: 350,  len: 140, weapons: ['g380', 'g380', 'g380', 'g380', 'aa', 'aa', 'mg'] },
    vanguard:    { name: 'Vanguard',    hp: 7000,  speed: 21,   minDist: 350,  len: 140, weapons: ['g381', 'g381', 'g381', 'g381', 'aa', 'aa', 'mg'] },
    richelieu:   { name: 'Richelieu',   hp: 7000,  speed: 21,   minDist: 400,  len: 140, weapons: ['g380', 'g380', 'g380', 'g380', 'aa', 'aa', 'aa'] },
    midway:      { name: 'Midway',      hp: 7500,  speed: 30.5, minDist: 900,  len: 150, weapons: ['aa', 'aa', 'aa', 'aa', 'mg', 'mg'], hangar: 4, hangarUnit: 'mixed' },
    iowa:        { name: 'Iowa',        hp: 8000,  speed: 25,   minDist: 400,  len: 148, weapons: ['g406', 'g406', 'g406', 'aa', 'aa', 'mg'] },
    yamato:      { name: 'Yamato',      hp: 10000, speed: 18,   minDist: 400,  len: 156, weapons: ['g460', 'g460', 'g460', 'g152', 'g152', 'aa', 'aa', 'aa'] }
  };

  // ---- 9 stages: enemy spawn timers (seconds); pool for random extra pressure
  function stg(name, boss, spawns, rnd, fortress) {
    return { name: name, boss: boss, spawns: spawns, random: rnd, fortress: fortress };
  }
  var STAGES = [
    stg('Stage 1 — First Patrol', 'dreadnought',
      [['patrol_ship', 12, 8], ['frigate', 20, 30]], null, 1),
    stg('Stage 2 — Contested Water', 'seydlitz',
      [['patrol_ship', 10, 6], ['frigate', 16, 20], ['submarine', 26, 45]], null, 1),
    stg('Stage 3 — Air Cover', 'dunkerque',
      [['patrol_ship', 9, 6], ['frigate', 13, 15], ['submarine', 20, 40], ['fighter', 22, 50]], null, 1),
    stg('Stage 4 — Wolfpack', 'bismarck',
      [['patrol_ship', 11.7, 6], ['frigate', 15.6, 12], ['submarine', 20.8, 25], ['fighter', 26, 40], ['torpedo_bomber', 33.8, 65], ['destroyer', 41.6, 75]], null, 2),
    stg('Stage 5 — Cruiser Line', 'vanguard',
      [['patrol_ship', 10, 5], ['frigate', 13.8, 10], ['submarine', 18.8, 22], ['fighter', 21.2, 30], ['torpedo_bomber', 25, 50], ['destroyer', 27.5, 60], ['light_cruiser', 42.5, 90]], null, 2),
    stg('Stage 6 — Rotor Storm', 'richelieu',
      [['patrol_ship', 9.6, 5], ['frigate', 12, 8], ['submarine', 16.8, 20], ['fighter', 19.2, 25], ['helicopter', 22.8, 40], ['torpedo_bomber', 22.8, 45], ['destroyer', 24, 50], ['light_cruiser', 36, 80], ['heavy_cruiser', 48, 120]], null, 2),
    stg('Stage 7 — Flattop', 'midway',
      [['patrol_ship', 8, 5], ['frigate', 10.3, 8], ['submarine', 14.9, 18], ['fighter', 20.9, 20], ['helicopter', 26.9, 35], ['torpedo_bomber', 25.4, 40], ['destroyer', 20.7, 45], ['light_cruiser', 29.9, 70], ['heavy_cruiser', 41.4, 100], ['carrier', 92, 180]], null, 3),
    stg('Stage 8 — Battle Line', 'iowa',
      [['patrol_ship', 7.7, 4], ['frigate', 8.8, 7], ['submarine', 12.1, 15], ['fighter', 13.2, 18], ['helicopter', 17.6, 30], ['torpedo_bomber', 16.5, 35], ['destroyer', 17.6, 40], ['light_cruiser', 26.4, 60], ['heavy_cruiser', 33, 90], ['battleship', 66, 150]],
      { interval: 16, jitter: 6, delay: 120, pool: ['patrol_ship', 'frigate', 'submarine', 'fighter'] }, 3),
    stg('Stage 9 — The Corridor', 'yamato',
      [['patrol_ship', 6, 8], ['frigate', 7, 12], ['submarine', 9, 20], ['helicopter', 13, 35], ['torpedo_bomber', 11, 40], ['fighter', 9, 25], ['destroyer', 16, 50], ['light_cruiser', 24, 75], ['heavy_cruiser', 30, 115], ['battleship', 50, 165]],
      { interval: 12, jitter: 5, delay: 120, pool: ['patrol_ship', 'frigate', 'submarine', 'helicopter', 'torpedo_bomber', 'fighter', 'destroyer', 'light_cruiser', 'heavy_cruiser', 'battleship'] }, 3)
  ];

  // ---- upgrades (player): [baseCost, growth, maxLvl]
  var UPGRADES = {
    supply_line: { name: 'Supply Line', cost: 120, growth: 1.4, max: 12 },  // +8 income/s
    salvage:     { name: 'Salvage Team', cost: 150, growth: 1.5, max: 7 },  // +10% kill bounty
    arsenal:     { name: 'Arsenal', cost: 180, growth: 1.45, max: 9 },      // -8% build cooldown
    repair:      { name: 'Repair Dock', cost: 168, growth: 1.45, max: 9 },  // +4 base hp/s
    fortress:    { name: 'Fortress', cost: 210, growth: 1.45, max: 9 }      // +12% base guns, +1 gun @2/4
  };

  function mulberry32(seed) {
    var a = seed >>> 0;
    return function () {
      a |= 0; a = (a + 0x6D2B79F5) | 0;
      var t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  var nextId = 1;

  function spawnUnit(state, side, unitId, opts) {
    var def = UNITS[unitId] || BOSSES[unitId];
    var isBoss = !!BOSSES[unitId];
    var dir = side === 'L' ? 1 : -1;
    var baseX = side === 'L' ? 170 : WORLD - 170;
    var type = isBoss ? 'ship' : def.type;
    var spawnX = baseX + dir * (20 + state.rng() * 30);
    if (type === 'ship' || type === 'sub') {
      // don't materialize on top of a unit still lingering at the spawn
      // point - step further back into the queue until there's clear room
      var guard = 0, blocked = true;
      while (blocked && guard < 40) {
        blocked = false;
        for (var si = 0; si < state.units.length; si++) {
          var o = state.units[si];
          if (o.side !== side || o.dead || o.type !== type) continue;
          if (Math.abs(o.x - spawnX) < def.len / 2 + o.def.len / 2 + 4) { blocked = true; break; }
        }
        if (blocked) {
          spawnX -= dir * 24;
          // never push a spawn behind the unit's own base or past the map
          // edge - it would land in a degenerate position there (tucked
          // past the base, unreachable, unable to find a valid target)
          var ownBaseX = side === 'L' ? state.baseL.x : state.baseR.x;
          spawnX = dir === 1 ? Math.max(ownBaseX - 20, spawnX) : Math.min(ownBaseX + 20, spawnX);
          spawnX = Math.max(60, Math.min(WORLD - 60, spawnX));
          guard++;
        }
      }
    }
    var u = {
      id: nextId++, side: side, unit: unitId, def: def, boss: isBoss,
      type: type,
      x: spawnX,
      y: type === 'air' ? def.alt + (state.rng() * 40 - 20) : (type === 'sub' ? def.depth : 0),
      dir: dir, hp: def.hp, maxHp: def.hp,
      speed: def.speed * (isBoss ? 1 : 0.95 + state.rng() * 0.1),
      weapons: def.weapons.map(function (k) { return { key: k, cool: WEAPONS[k].reload * state.rng() * 0.5 }; }),
      hangarT: 6, children: 0, parent: opts && opts.parent ? opts.parent : 0,
      passT: 0, bobPhase: state.rng() * 6.283, holding: false
    };
    state.units.push(u);
    state.events.push({ type: 'spawn', x: u.x, y: u.y, side: side, unit: unitId });
    return u;
  }

  function createMatch(stageIdx, opts) {
    opts = opts || {};
    var stage = STAGES[Math.max(0, Math.min(STAGES.length - 1, stageIdx))];
    var rng = mulberry32(opts.seed || 12345);
    var state = {
      t: 0, dt: DT, stageIdx: stageIdx, stage: stage, rng: rng,
      units: [], projectiles: [], events: [], result: null,
      gold: 300 + stageIdx * 150, income: 20, // no storage cap - gold accumulates without limit
      upgrades: { supply_line: 0, salvage: 0, arsenal: 0, repair: 0, fortress: 0 },
      buildCd: {},       // unitId -> remaining s
      queue: [],
      baseL: { side: 'L', x: 90, hp: BASE_HP, maxHp: BASE_HP, weapons: baseWeapons(1 + Math.floor(stageIdx / 3), false), invincible: false },
      baseR: { side: 'R', x: WORLD - 90, hp: BASE_HP, maxHp: BASE_HP, weapons: baseWeapons(stage.fortress, true), invincible: false },
      spawnT: stage.spawns.map(function (s) { return s[2]; }),
      randT: stage.random ? stage.random.delay : 0,
      bossSpawned: false, bossId: 0, bossDown: false,
      unlockedStages: opts.unlockedStages || 1,
      stats: { built: 0, kills: 0, losses: 0 },
      // player-manned fortress gun: manual elevation control, no auto-targeting
      playerAim: { range: 900, min: 150, max: WORLD / 2 - 60 },
      playerGunCool: 0,
      // B-52 carpet-bombing strike: player-triggered, long cooldown, sweeps
      // the whole map from the player's base to the enemy's
      b52Cool: 0, b52Queue: []
    };
    return state;
  }

  var B52_COOLDOWN = 120;
  var B52_BOMB_DMG = 900; // ~50% of a carrier's 1800 hp per direct hit
  var B52_BOMB_RADIUS = 85;

  function fireB52(state) {
    if (state.b52Cool > 0) return false;
    state.b52Cool = B52_COOLDOWN;
    var startX = state.baseL.x + 300;
    var endX = state.baseR.x - 100;
    var bombCount = 26;
    var runDuration = 6.0; // seconds for the bomber to cross the whole map
    for (var i = 0; i < bombCount; i++) {
      var frac = i / (bombCount - 1);
      state.b52Queue.push({ x: startX + (endX - startX) * frac, t: state.t + frac * runDuration });
    }
    state.events.push({ type: 'b52launch', startX: startX, endX: endX, duration: runDuration });
    return true;
  }

  function stepB52(state, dt) {
    if (state.b52Cool > 0) state.b52Cool -= dt;
    for (var i = state.b52Queue.length - 1; i >= 0; i--) {
      var q = state.b52Queue[i];
      if (state.t < q.t) continue;
      state.b52Queue.splice(i, 1);
      state.events.push({ type: 'explosion', x: q.x, y: 0, size: 30, water: true });
      for (var j = 0; j < state.units.length; j++) {
        var u = state.units[j];
        if (u.side === 'L' || u.dead || u.type === 'air') continue;
        if (Math.abs(u.x - q.x) < B52_BOMB_RADIUS) damageUnit(state, u, B52_BOMB_DMG, u.x, u.y);
      }
      if (Math.abs(state.baseR.x - q.x) < B52_BOMB_RADIUS) damageBase(state, state.baseR, B52_BOMB_DMG * 0.4, q.x, 0);
    }
  }

  // autoFort: enemy base keeps its old fully-automatic fortress gun; the
  // player's base gets AA/torpedo point-defense automatically but the main
  // fortress gun is hand-aimed (see adjustAim/fireBattery below).
  function baseWeapons(fortLvl, autoFort) {
    var w = [];
    if (autoFort) w.push({ key: 'fort', cool: 2 });
    w.push({ key: 'aa', cool: 1 }, { key: 'aa', cool: 2 }, { key: 'btorp', cool: 3 });
    for (var i = 1; i < fortLvl; i++) {
      if (autoFort) w.push({ key: 'fort', cool: 2 + i });
      if (i % 2 === 0) w.push({ key: 'btorp', cool: 4 + i });
    }
    return w;
  }

  function adjustAim(state, delta) {
    var a = state.playerAim;
    a.range = Math.max(a.min, Math.min(a.max, a.range + delta));
  }

  // Called once per sim tick while the player holds the fire input. No-ops
  // silently if the gun is still cooling down, so callers don't need to
  // track cooldown themselves.
  function fireBattery(state) {
    var b = state.baseL;
    if (b.hp <= 0 || state.playerGunCool > 0) return;
    var wdef = WEAPONS.fort;
    state.playerGunCool = wdef.reload * 0.4; // faster hand-cranked cadence than the AI's fort gun
    var targetX = b.x + state.playerAim.range;
    var fortMult = 1 + 0.12 * state.upgrades.fortress;
    fireWeapon(state, { id: 0, side: 'L', x: b.x, y: -24, type: 'ship', def: { len: 10, detect: wdef.range } },
      { key: 'fort', cool: 0 }, { x: targetX, y: 0, type: 'ship', dir: 0, speed: 0, id: 0 });
    var lastP = state.projectiles[state.projectiles.length - 1];
    if (lastP) {
      lastP.dmg = wdef.dmg * fortMult;
      // the angle solve above assumes equal launch/impact height; force an
      // exact match so the shell actually lands on the aimed mark instead of
      // overshooting from the turret's elevated (visual-only) muzzle height
      lastP.y = 0;
    }
  }

  // ---------- queries
  function enemiesOf(state, side) {
    var out = [];
    for (var i = 0; i < state.units.length; i++) if (state.units[i].side !== side) out.push(state.units[i]);
    return out;
  }
  function enemyBase(state, side) { return side === 'L' ? state.baseR : state.baseL; }
  function canTarget(wdef, t) { return t.base ? wdef.targets.base : wdef.targets[t.type]; }

  function nearestTargetFor(state, u, wdef, maxRange) {
    var best = null, bestD = maxRange;
    for (var i = 0; i < state.units.length; i++) {
      var e = state.units[i];
      if (e.side === u.side || !wdef.targets[e.type]) continue;
      var d = Math.abs(e.x - u.x);
      if (d < bestD) { bestD = d; best = e; }
    }
    if (wdef.targets.base) {
      var b = enemyBase(state, u.side);
      var db = Math.abs(b.x - u.x);
      if (db < bestD) { bestD = db; best = { base: true, x: b.x, y: -10, type: 'base', obj: b, dir: 0, speed: 0, len: 120 }; }
    }
    return best;
  }

  // ---------- firing
  function fireWeapon(state, u, w, target) {
    var wdef = WEAPONS[w.key];
    w.cool = wdef.reload * (0.92 + state.rng() * 0.16);
    var p = {
      id: nextId++, kind: wdef.proj, wkey: w.key, side: u.side, dmg: wdef.dmg,
      x: u.x, y: u.y - (u.type === 'ship' ? 8 : 0), tId: target.id || 0, aoe: wdef.aoe || 0
    };
    var dx = target.x - u.x;
    var lead = target.speed ? target.dir * target.speed * Math.abs(dx) / wdef.speed * 0.5 : 0;
    dx += lead;
    if (wdef.proj === 'shell' || wdef.proj === 'flak') {
      var g = 160, v0 = wdef.speed * (0.97 + state.rng() * 0.06);
      var arg = Math.abs(dx) * g / (v0 * v0);
      var ang = arg >= 1 ? Math.PI / 4 : 0.5 * Math.asin(arg);
      p.vx = Math.sign(dx) * v0 * Math.cos(ang);
      p.vy = -v0 * Math.sin(ang) - (u.y < -5 ? 0 : 0);
      p.g = g;
      if (wdef.proj === 'flak') { p.fuseY = target.y; p.aoe = 30; }
    } else if (wdef.proj === 'torpedo') {
      p.vx = Math.sign(dx) * wdef.speed; p.vy = 0;
      p.y = u.type === 'air' ? 0 : (u.type === 'sub' ? u.y : 6);
      p.ty = target.type === 'sub' ? target.y : (target.base ? 0 : Math.max(4, target.y + 4));
      if (u.type === 'air') { p.dropY = u.y; p.y = u.y; p.dropping = true; }
    } else if (wdef.proj === 'missile') {
      p.vx = Math.sign(dx) * wdef.speed * 0.4; p.vy = -120; p.homing = true; p.speed = wdef.speed;
    } else if (wdef.proj === 'depthcharge') {
      var n = wdef.n || 1;
      for (var i = 0; i < n; i++) {
        var q = { id: nextId++, kind: 'depthcharge', wkey: w.key, side: u.side, dmg: wdef.dmg, x: u.x + (state.rng() * 60 - 30) + Math.sign(dx) * 30, y: u.y, vx: Math.sign(dx) * 25, vy: u.type === 'air' ? 60 : 25, fuseY: (target.y || 55) + (state.rng() * 16 - 8), aoe: 42 };
        state.projectiles.push(q);
      }
      state.events.push({ type: 'fire', x: u.x, y: u.y, kind: 'depthcharge' });
      return;
    } else { // bullet
      var d = Math.sqrt(dx * dx + Math.pow(target.y - u.y, 2)) || 1;
      var jit = (state.rng() - 0.5) * 0.08;
      p.vx = wdef.speed * (dx / d); p.vy = wdef.speed * ((target.y - u.y) / d) + jit * wdef.speed;
      p.life = wdef.range / wdef.speed + 0.2;
    }
    state.projectiles.push(p);
    state.events.push({ type: 'fire', x: u.x, y: p.y, kind: wdef.proj, big: wdef.dmg > 80, dir: Math.sign(dx) });
  }

  function damageUnit(state, u, dmg, x, y) {
    u.hp -= dmg;
    state.events.push({ type: 'hit', x: x, y: y, size: Math.min(30, 6 + dmg * 0.15) });
    if (u.hp <= 0 && !u.dead) {
      u.dead = true;
      state.events.push({ type: 'death', x: u.x, y: u.y, unit: u.unit, utype: u.type, side: u.side, len: u.def.len });
      if (u.side === 'R') {
        state.stats.kills++;
        var bounty = (u.def.cost || 300) * (0.13 + 0.09 * state.upgrades.salvage);
        state.gold += bounty;
      } else state.stats.losses++;
      if (u.boss) { state.bossDown = true; state.baseR.invincible = false; state.events.push({ type: 'bossdown' }); }
    }
  }

  function damageBase(state, base, dmg, x, y) {
    if (base.invincible) { state.events.push({ type: 'hit', x: x, y: y, size: 4, deflect: true }); return; }
    // boss gate: enemy base locks at 50% until boss is sunk
    if (base.side === 'R' && !state.bossSpawned && base.hp - dmg <= base.maxHp * 0.5) {
      base.hp = base.maxHp * 0.5;
      state.bossSpawned = true;
      base.invincible = true;
      var b = spawnUnit(state, 'R', state.stage.boss, {});
      state.bossId = b.id;
      state.events.push({ type: 'bosswarn', name: BOSSES[state.stage.boss].name });
      return;
    }
    base.hp -= dmg;
    state.events.push({ type: 'hit', x: x, y: y, size: Math.min(30, 6 + dmg * 0.15) });
    if (base.hp <= 0) {
      base.hp = 0;
      state.result = base.side === 'R' ? 'victory' : 'defeat';
      state.events.push({ type: 'basedown', side: base.side, x: base.x });
    }
  }

  // ---------- projectile step
  function stepProjectiles(state, dt) {
    var ps = state.projectiles;
    for (var i = ps.length - 1; i >= 0; i--) {
      var p = ps[i];
      if (p.kind === 'shell' || p.kind === 'flak') {
        p.vy += p.g * dt;
        p.x += p.vx * dt; p.y += p.vy * dt;
        if (p.kind === 'flak' && p.vy > -20 && p.y > p.fuseY - 14) { explode(state, p); ps.splice(i, 1); continue; }
        if (p.kind === 'shell') {
          var hit = hitScanSurface(state, p);
          if (hit || p.y >= 0) {
            if (hit) explode(state, p);
            else state.events.push({ type: 'splash', x: p.x, y: 0, size: p.dmg > 90 ? 16 : 9 });
            if (!hit && p.aoe) explodeAt(state, p, p.x, 0);
            ps.splice(i, 1); continue;
          }
        } else if (p.y > 10) { ps.splice(i, 1); continue; }
      } else if (p.kind === 'torpedo') {
        if (p.dropping) {
          p.y += 90 * dt; p.x += p.vx * 0.5 * dt;
          if (p.y >= 0) { p.dropping = false; p.y = Math.max(0, p.ty || 0) * 0; state.events.push({ type: 'splash', x: p.x, y: 0, size: 8 }); }
        } else {
          p.x += p.vx * dt;
          var ty = p.ty || 0;
          // rise/dive rate must clear a sub's full depth well within normal
          // engagement range - at the old 14/s, a torpedo fired from the
          // atomic submarine's depth (78) took ~4.4s to surface, during
          // which its 100/s horizontal speed carried it 436 units past any
          // target at typical engagement distance before it could ever hit
          p.y += Math.max(-60 * dt, Math.min(60 * dt, ty - p.y));
          var h = hitScanTorpedo(state, p);
          if (h) { ps.splice(i, 1); continue; }
          state.tw = 0;
        }
        if (p.x < 20 || p.x > WORLD - 20) {
          var b = p.x < WORLD / 2 ? state.baseL : state.baseR;
          if (b.side !== p.side && Math.abs(p.x - b.x) < 70) { damageBase(state, b, p.dmg, p.x, 0); state.events.push({ type: 'explosion', x: p.x, y: 0, size: 22 }); }
          ps.splice(i, 1); continue;
        }
      } else if (p.kind === 'missile') {
        var t = findById(state, p.tId);
        if (p.homing && t && !t.dead) {
          var mdx = t.x - p.x, mdy = t.y - 6 - p.y;
          var md = Math.sqrt(mdx * mdx + mdy * mdy) || 1;
          p.vx += (mdx / md * p.speed - p.vx) * 3 * dt;
          p.vy += (mdy / md * p.speed - p.vy) * 3 * dt;
        } else p.vy += 30 * dt;
        p.x += p.vx * dt; p.y += p.vy * dt;
        var hm = hitScanSurface(state, p, true);
        if (hm || p.y >= 4) { if (hm) explode(state, p); else state.events.push({ type: 'splash', x: p.x, y: 0, size: 8 }); ps.splice(i, 1); continue; }
      } else if (p.kind === 'depthcharge') {
        p.x += p.vx * dt; p.vy = Math.min(p.vy + (p.y < 0 ? 100 : -20) * dt + 40 * dt, 80); p.y += p.vy * dt;
        if (p.y >= p.fuseY) { explodeAt(state, p, p.x, p.y); ps.splice(i, 1); continue; }
      } else { // bullet
        p.x += p.vx * dt; p.y += p.vy * dt; p.life -= dt;
        var hb = hitScanBullet(state, p);
        if (hb || p.life <= 0 || p.y > 2) { ps.splice(i, 1); continue; }
      }
      if (p.x < -50 || p.x > WORLD + 50 || p.y < -600) ps.splice(i, 1);
    }
  }

  function findById(state, id) {
    for (var i = 0; i < state.units.length; i++) if (state.units[i].id === id) return state.units[i];
    return null;
  }

  function hitScanSurface(state, p, missileMode) {
    for (var i = 0; i < state.units.length; i++) {
      var u = state.units[i];
      if (u.side === p.side || u.dead) continue;
      if (u.type === 'sub' && !missileMode) continue;
      if (u.type === 'air' && !missileMode) continue;
      var half = u.def.len / 2 + 4;
      var band = u.type === 'ship' ? (p.y > -26 && p.y < 6) : Math.abs(p.y - u.y) < 14;
      if (Math.abs(p.x - u.x) < half && band) { damageUnit(state, u, p.dmg, p.x, p.y); return true; }
    }
    var b = enemyBase(state, p.side);
    if (Math.abs(p.x - b.x) < 80 && p.y > -70) { damageBase(state, b, p.dmg, p.x, p.y); state.events.push({ type: 'explosion', x: p.x, y: p.y, size: 14 }); return true; }
    return false;
  }

  function hitScanTorpedo(state, p) {
    for (var i = 0; i < state.units.length; i++) {
      var u = state.units[i];
      if (u.side === p.side || u.dead || u.type === 'air') continue;
      var half = u.def.len / 2 + 3;
      var dy = u.type === 'ship' ? Math.abs(p.y - 5) : Math.abs(p.y - u.y);
      if (Math.abs(p.x - u.x) < half && dy < 12) {
        damageUnit(state, u, p.dmg, p.x, p.y);
        state.events.push({ type: 'explosion', x: p.x, y: p.y, size: 20, water: true });
        return true;
      }
    }
    return false;
  }

  function hitScanBullet(state, p) {
    for (var i = 0; i < state.units.length; i++) {
      var u = state.units[i];
      if (u.side === p.side || u.dead || u.type === 'sub') continue;
      var half = u.def.len / 2 + 3;
      var band = u.type === 'ship' ? (p.y > -24 && p.y < 4) : Math.abs(p.y - u.y) < 16;
      if (Math.abs(p.x - u.x) < half && band) { damageUnit(state, u, p.dmg, p.x, p.y); return true; }
    }
    var b = enemyBase(state, p.side);
    if (Math.abs(p.x - b.x) < 70 && p.y > -60) { damageBase(state, b, p.dmg * 0.5, p.x, p.y); return true; }
    return false;
  }

  function explode(state, p) {
    state.events.push({ type: 'explosion', x: p.x, y: p.y, size: Math.min(34, 10 + p.dmg * 0.14) });
    if (p.aoe) explodeAt(state, p, p.x, p.y);
  }

  function explodeAt(state, p, x, y) {
    state.events.push({ type: 'explosion', x: x, y: y, size: p.aoe ? p.aoe * 0.4 : 12, water: y > 0 });
    for (var i = 0; i < state.units.length; i++) {
      var u = state.units[i];
      if (u.side === p.side || u.dead) continue;
      var wdef = WEAPONS[p.wkey];
      if (wdef && !wdef.targets[u.type]) continue;
      var dx = Math.abs(u.x - x), dy = Math.abs(u.y - y);
      var r = (p.aoe || 20) + u.def.len / 2;
      if (dx < r && dy < (p.aoe || 20) + 16) damageUnit(state, u, p.dmg * (1 - dx / (r + 1) * 0.5), u.x, u.y);
    }
  }

  // ---------- unit step
  function stepUnits(state, dt) {
    var units = state.units;
    // same-side spacing map (surface ships hold column)
    for (var i = 0; i < units.length; i++) {
      var u = units[i];
      if (u.dead) continue;
      // weapons cool & fire
      var engaged = false, holdDist = Infinity;
      for (var w = 0; w < u.weapons.length; w++) {
        var wp = u.weapons[w], wdef = WEAPONS[wp.key];
        wp.cool -= dt;
        var maxR = Math.min(wdef.range, Math.max(u.def.detect, wdef.range * 0.6));
        var tgt = nearestTargetFor(state, u, wdef, u.def.detect + 40);
        if (tgt) {
          var d = Math.abs(tgt.x - u.x);
          if (d <= wdef.range) {
            engaged = true;
            if (wp.cool <= 0) {
              if (tgt.base) fireWeapon(state, u, wp, tgt);
              else fireWeapon(state, u, wp, tgt);
            }
          }
          if (wdef.targets.ship || wdef.targets.base) holdDist = Math.min(holdDist, d);
        }
      }
      // movement
      var minD = u.def.minDist || 0;
      var move = true;
      if (u.type === 'air') {
        // aircraft fly passes; turn around past targets or near enemy base
        u.passT -= dt;
        var ahead = u.dir > 0 ? WORLD - 260 : 260;
        var tgtA = nearestAnyTarget(state, u);
        // long-range standoff aircraft (minDist far beyond any weapon's
        // range) must never fall into the ordinary fighter/bomber "no
        // target found - cruise all the way to the enemy base and back"
        // patrol, or it flies straight through its own safe standoff
        // distance into the heart of enemy defenses and gets shredded.
        // With nothing detected it should just hold instead of advancing.
        var standoff = u.def.minDist >= 700;
        if (tgtA) {
          var rel = (tgtA.x - u.x) * u.dir;
          if (rel < -120 && u.passT <= 0) { u.dir *= -1; u.passT = 2.5; }
        } else if (standoff) {
          // drift toward wherever the fight is, but with nothing detected
          // yet, never advance alone past a safe cap tied to the actual
          // danger zone (max weapon range in the game is 780, so 850 gives
          // a firm buffer) - not an arbitrary map fraction, which left
          // bombers idling far behind a front line that had moved further
          // up than the old cap allowed
          var safeCap = u.side === 'L' ? WORLD - 850 : 850;
          if ((u.side === 'L' && u.x >= safeCap) || (u.side === 'R' && u.x <= safeCap)) move = false;
        } else if ((u.dir > 0 && u.x > ahead) || (u.dir < 0 && u.x < WORLD - ahead)) {
          if (u.side === 'L' && u.dir > 0 && u.x > WORLD - 300) { u.dir = -1; u.passT = 3; }
          else if (u.side === 'R' && u.dir < 0 && u.x < 300) { u.dir = 1; u.passT = 3; }
        }
        // helicopters hover at minDist
        if (u.def.minDist && tgtA && Math.abs(tgtA.x - u.x) < u.def.minDist) move = false;
        if (move) u.x += u.dir * u.speed * dt;
        // safety net: with no target in range, the branches above only
        // catch a plane overshooting into ENEMY territory - a plane flying
        // home (no target found near its own base either) had nothing to
        // turn it around and would fly off the map into the thousands
        // indefinitely, permanently losing that unit for the rest of the
        // match. Hard-bounce well past the intended patrol edge as a backstop.
        if (u.x < -150) { u.x = -150; u.dir = 1; u.passT = 3; }
        else if (u.x > WORLD + 150) { u.x = WORLD + 150; u.dir = -1; u.passT = 3; }
        u.y = (u.def.alt || -120) + Math.sin(state.t * 1.3 + u.bobPhase) * 8;
      } else {
        var combatHold = engaged && holdDist <= Math.max(minD, 60);
        if (combatHold) move = false;
        // avoid overlapping an ally that's still transiting, but flow past
        // one that has stopped to fight - otherwise a single long-range
        // ship parked at its engagement distance permanently bottlenecks
        // every reinforcement spawned behind it into an ever-growing,
        // motionless queue that never reaches its own effective range
        if (move) {
          var aheadAlly = null, aheadD = 1e9;
          for (var j = 0; j < units.length; j++) {
            var a = units[j];
            if (a === u || a.dead || a.side !== u.side || a.type !== u.type) continue;
            var relA = (a.x - u.x) * (u.side === 'L' ? 1 : -1);
            if (relA > 0 && relA < aheadD) { aheadD = relA; aheadAlly = a; }
          }
          if (aheadAlly && !aheadAlly.holding && aheadD < u.def.len / 2 + aheadAlly.def.len / 2 + 6) move = false;
          if (move) u.x += (u.side === 'L' ? 1 : -1) * u.speed * dt;
        }
        u.holding = combatHold;
        u.x = Math.max(60, Math.min(WORLD - 60, u.x));
      }
      // hangar
      var hangar = u.def.hangar;
      if (hangar && !u.dead) {
        u.hangarT -= dt;
        if (u.hangarT <= 0 && u.children < hangar) {
          u.hangarT = 19;
          var kind = u.def.hangarUnit === 'mixed' ? (state.rng() < 0.5 ? 'fighter' : 'torpedo_bomber') : u.def.hangarUnit;
          var c = spawnUnit(state, u.side, kind, { parent: u.id });
          c.x = u.x; c.y = -30; u.children++;
        }
      }
    }
    // cleanup dead, credit parents
    for (var k = units.length - 1; k >= 0; k--) {
      if (units[k].dead) {
        var dd = units[k];
        if (dd.parent) { var par = findById(state, dd.parent); if (par) par.children--; }
        units.splice(k, 1);
      }
    }
  }

  function nearestAnyTarget(state, u) {
    var best = null, bestD = u.def.detect + 60;
    for (var i = 0; i < state.units.length; i++) {
      var e = state.units[i];
      if (e.side === u.side || e.dead) continue;
      var can = false;
      for (var w = 0; w < u.weapons.length; w++) if (WEAPONS[u.weapons[w].key].targets[e.type]) { can = true; break; }
      if (!can) continue;
      var d = Math.abs(e.x - u.x);
      if (d < bestD) { bestD = d; best = e; }
    }
    return best;
  }

  // ---------- bases fire
  function stepBases(state, dt) {
    ['baseL', 'baseR'].forEach(function (bk) {
      var b = state[bk];
      if (b.hp <= 0) return;
      var side = b.side;
      var fortMult = side === 'L' ? 1 + 0.12 * state.upgrades.fortress : 1;
      for (var i = 0; i < b.weapons.length; i++) {
        var wp = b.weapons[i], wdef = WEAPONS[wp.key];
        wp.cool -= dt;
        if (wp.cool > 0) continue;
        var best = null, bestD = wdef.range;
        for (var j = 0; j < state.units.length; j++) {
          var e = state.units[j];
          if (e.side === side || e.dead || !wdef.targets[e.type]) continue;
          var d = Math.abs(e.x - b.x);
          if (d < bestD) { bestD = d; best = e; }
        }
        if (best) {
          var fake = { x: b.x, y: -20, type: 'ship', side: side, def: { len: 10, detect: wdef.range, minDist: 0 }, weapons: [], id: 0 };
          var pseudo = { key: wp.key, cool: 0 };
          fireWeapon(state, { id: 0, side: side, x: b.x, y: -24, type: 'ship', def: { len: 10, detect: wdef.range }, rngHack: 1 }, pseudo, best);
          // apply fortress multiplier to the projectile just pushed
          var lastP = state.projectiles[state.projectiles.length - 1];
          if (lastP) lastP.dmg = wdef.dmg * fortMult;
          wp.cool = pseudo.cool;
        }
      }
    });
    // player repair
    if (state.upgrades.repair > 0 && state.baseL.hp > 0) {
      state.baseL.hp = Math.min(state.baseL.maxHp, state.baseL.hp + 4 * state.upgrades.repair * dt);
    }
  }

  // ---------- enemy spawner (timer-based, faithful to BNW:Re)
  function stepEnemy(state, dt) {
    var st = state.stage;
    // pressure escalates slowly so long games cannot stalemate
    var esc = Math.max(0.72, 1 - Math.min(state.t, 900) * 0.00035);
    for (var i = 0; i < st.spawns.length; i++) {
      state.spawnT[i] -= dt;
      if (state.spawnT[i] <= 0) {
        var unitId = st.spawns[i][0];
        state.spawnT[i] = st.spawns[i][1] * esc;
        // hangar ships (carriers) keep producing escort aircraft the whole
        // time they're alive; stacking several at once compounds into an
        // unmanageable air swarm, so the periodic spawner replaces a fallen
        // one instead of piling up more of the same hangar ship
        var hdef = UNITS[unitId];
        if (hdef && hdef.hangar) {
          var alreadyAlive = false;
          for (var j = 0; j < state.units.length; j++) {
            if (state.units[j].side === 'R' && state.units[j].unit === unitId && !state.units[j].dead) { alreadyAlive = true; break; }
          }
          if (alreadyAlive) continue;
        }
        spawnUnit(state, 'R', unitId, {});
      }
    }
    if (st.random) {
      state.randT -= dt;
      if (state.randT <= 0) {
        state.randT = st.random.interval + (state.rng() * 2 - 1) * st.random.jitter;
        var pool = st.random.pool;
        spawnUnit(state, 'R', pool[Math.floor(state.rng() * pool.length)], {});
      }
    }
  }

  // ---------- player commands
  function upgradeCost(state, key) {
    var u = UPGRADES[key];
    return Math.round(u.cost * Math.pow(u.growth, state.upgrades[key]));
  }
  function tryUpgrade(state, key) {
    var lvl = state.upgrades[key];
    if (lvl >= UPGRADES[key].max) return false;
    var c = upgradeCost(state, key);
    if (state.gold < c) return false;
    state.gold -= c;
    state.upgrades[key]++;
    if (key === 'supply_line') state.income += 10;
    if (key === 'fortress' && (state.upgrades.fortress === 2 || state.upgrades.fortress === 4)) {
      state.baseL.weapons.push({ key: 'fort', cool: 2 });
    }
    state.events.push({ type: 'upgrade', key: key });
    return true;
  }
  function buildCooldown(state, unitId) {
    return UNITS[unitId].cd * (1 - 0.08 * state.upgrades.arsenal);
  }
  function unitUnlocked(state, unitId) {
    var def = UNITS[unitId];
    return !def.unlock || state.unlockedStages > def.unlock;
  }
  function tryBuild(state, unitId) {
    var def = UNITS[unitId];
    if (!def || !unitUnlocked(state, unitId)) return false;
    if ((state.buildCd[unitId] || 0) > 0) return false;
    if (state.gold < def.cost) return false;
    state.gold -= def.cost;
    state.buildCd[unitId] = buildCooldown(state, unitId);
    spawnUnit(state, 'L', unitId, {});
    state.stats.built++;
    return true;
  }

  // ---------- auto player (used by ?auto and headless tests)
  function autoPlay(state) {
    // player-manned fortress gun: track the nearest threat and fire, every
    // tick, so the scripted auto-player stays a fair proxy for a human
    // actually working the manual battery (aim/fire keys).
    var aim = state.playerAim;
    if (aim && state.baseL.hp > 0) {
      var nearest = null, nearestD = aim.max;
      for (var ti = 0; ti < state.units.length; ti++) {
        var tu = state.units[ti];
        if (tu.side === 'L' || tu.dead) continue;
        var td = tu.x - state.baseL.x;
        if (td >= aim.min * 0.5 && td < nearestD) { nearestD = td; nearest = tu; }
      }
      if (nearest) {
        aim.range = Math.max(aim.min, Math.min(aim.max, nearestD));
        fireBattery(state);
      }
    }
    if (state.t % 0.5 > DT) return;
    var counts = { subs: 0, air: 0, surf: 0, big: 0 };
    var mine = { asw: 0, aa: 0, surf: 0, big: 0 };
    for (var i = 0; i < state.units.length; i++) {
      var u = state.units[i];
      if (u.side === 'R') {
        if (u.type === 'sub') counts.subs++;
        else if (u.type === 'air') counts.air++;
        else { counts.surf++; if (u.maxHp > 1000) counts.big++; }
      } else {
        if (u.unit === 'frigate' || u.unit === 'helicopter' || u.unit === 'destroyer' || u.unit === 'submarine') mine.asw++;
        if (u.unit === 'fighter' || u.unit === 'patrol_ship') mine.aa++;
        if (u.type === 'ship') mine.surf++;
        if (u.maxHp > 1000) mine.big++;
        if (u.unit === 'destroyer' || u.unit === 'light_cruiser' || u.unit === 'heavy_cruiser') mine.escort = (mine.escort || 0) + 1;
        if (u.unit === 'long_range_bomber') mine.bombers = (mine.bombers || 0) + 1;
      }
    }
    var baseDamaged = state.baseL.hp < state.baseL.maxHp * 0.97;   // chip damage: buy repair
    var baseCritical = state.baseL.hp < state.baseL.maxHp * 0.85;  // real assault: defensive spam
    // economy first: supply line to max while base is safe (gold has no storage cap)
    if (!baseDamaged || state.upgrades.supply_line < 3) {
      if (state.upgrades.supply_line < UPGRADES.supply_line.max && state.gold >= upgradeCost(state, 'supply_line')) {
        tryUpgrade(state, 'supply_line'); return;
      }
    }
    if (state.upgrades.salvage < 2 && state.t > 200 && state.gold > upgradeCost(state, 'salvage') * 1.8) tryUpgrade(state, 'salvage');
    if (baseDamaged && state.upgrades.repair < 4 && state.gold >= upgradeCost(state, 'repair')) tryUpgrade(state, 'repair');
    if (state.baseL.hp < state.baseL.maxHp * 0.8 && state.upgrades.fortress < 4 && state.gold >= upgradeCost(state, 'fortress')) tryUpgrade(state, 'fortress');
    if (state.stageIdx >= 5 && state.t < 90 && state.upgrades.fortress < (state.stageIdx >= 7 ? 3 : 2) && state.gold >= upgradeCost(state, 'fortress')) { tryUpgrade(state, 'fortress'); return; }
    // counters, capped so they don't eat the savings. Priority is dynamic:
    // whichever threat has the bigger deficit goes first, so a persistent
    // sub presence can't perpetually starve the air response (or vice
    // versa) tick after tick while the other threat quietly snowballs.
    var subDeficit = counts.subs - mine.asw;
    var airDeficit = counts.air - mine.aa;
    var subUrgent = subDeficit > 0 && mine.asw < Math.min(8, counts.subs + 1);
    // destroyer/frigate double as general surface defense, so they stay the
    // default pick under mixed pressure; only divert to fighters when air is
    // a genuine runaway well past what sub pressure alone would explain
    var airCritical = airDeficit > 5 && airDeficit > subDeficit * 2.2;
    if (subUrgent && !airCritical) {
      if (tryBuild(state, 'destroyer') || tryBuild(state, 'frigate') || tryBuild(state, 'helicopter')) return;
    }
    if ((airCritical || counts.air > mine.aa + 1) && tryBuild(state, 'fighter')) return;
    if (subUrgent && (tryBuild(state, 'destroyer') || tryBuild(state, 'frigate') || tryBuild(state, 'helicopter'))) return;
    // capital push: save up, don't drip-feed the meat grinder. Cap how many
    // big ships can be alive at once - without it a strong economy just
    // piles up an ever-growing fleet that holds at the front line instead
    // of ever finishing the fight, since capital ships stop advancing the
    // moment anything is in range, however weak. Past the cap, surplus gold
    // banks toward upgrades instead of more units that would only queue up.
    var bigCap = 14;
    var capital = state.t > 210 ? 'battleship' : (state.t > 90 ? 'light_cruiser' : null);
    // long-range bombers hold well outside the front line's engagement
    // bubble, so unlike capital ships they never add to the congestion
    // that caps the front - but they must never outbid capital-ship/
    // defense spending, only mop up gold that would otherwise sit idle.
    var bomberCap = 24;
    function tryBomber() {
      return unitUnlocked(state, 'long_range_bomber') && (mine.bombers || 0) < bomberCap &&
        state.gold >= UNITS.long_range_bomber.cost && tryBuild(state, 'long_range_bomber');
    }
    if (state.stageIdx >= 6 && state.t > 300 && mine.big > 1 && mine.big < bigCap && state.gold >= UNITS.carrier.cost) {
      if (tryBuild(state, 'carrier')) return;
    }
    if (capital && mine.big < bigCap && state.gold >= UNITS[capital].cost) {
      if (tryBuild(state, capital)) {
        // escort trickle follows automatically on later ticks
        return;
      }
    }
    if (capital === 'battleship' && state.gold > UNITS.battleship.cost * 0.5) {
      // spend a large idle surplus on escorts so battleships never push alone
      if (state.gold > UNITS.battleship.cost * 3 && (mine.escort || 0) < mine.big * 2 + 2) {
        if (tryBuild(state, 'light_cruiser') || tryBuild(state, 'destroyer')) return;
      }
      // otherwise this gold would just sit idle - exactly what a bomber
      // should soak up instead, since it never competes with the capital
      // ship funding above and never congests the front line
      if (tryBomber()) return;
      if (!baseCritical) return;
    }
    // defense only when the base is genuinely threatened (base guns handle campers and chip)
    if (baseCritical) {
      if (counts.subs > 0 && state.gold > UNITS.frigate.cost && (tryBuild(state, 'frigate') || tryBuild(state, 'helicopter'))) return;
      if (state.gold > UNITS.destroyer.cost && tryBuild(state, 'destroyer')) return;
      if (state.gold > UNITS.patrol_ship.cost + 40) { tryBuild(state, 'patrol_ship'); return; }
    }
    // light early skirmish so the enemy doesn't snowball for free
    if (state.t < 90 && mine.surf < 3 && state.gold > UNITS.patrol_ship.cost + 60) { tryBuild(state, 'patrol_ship'); return; }
    tryBomber();
  }

  // ---------- main step
  function step(state, dt) {
    if (state.result) return;
    dt = dt || DT;
    state.t += dt;
    state.gold += state.income * dt;
    for (var k in state.buildCd) if (state.buildCd[k] > 0) state.buildCd[k] -= dt;
    if (state.playerGunCool > 0) state.playerGunCool -= dt;
    stepB52(state, dt);
    stepEnemy(state, dt);
    stepUnits(state, dt);
    stepProjectiles(state, dt);
    stepBases(state, dt);
    if (state.t > 1800 && !state.result) state.result = 'defeat'; // 30 min hard cap
  }

  return {
    WORLD: WORLD, DT: DT, BASE_HP: BASE_HP,
    UNITS: UNITS, WEAPONS: WEAPONS, BOSSES: BOSSES, STAGES: STAGES, UPGRADES: UPGRADES,
    createMatch: createMatch, step: step,
    tryBuild: tryBuild, tryUpgrade: tryUpgrade, upgradeCost: upgradeCost,
    buildCooldown: buildCooldown, unitUnlocked: unitUnlocked, autoPlay: autoPlay,
    adjustAim: adjustAim, fireBattery: fireBattery, fireB52: fireB52, B52_COOLDOWN: B52_COOLDOWN
  };
});
