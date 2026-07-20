# Iron Corridor 2D — design reference

A 2D side-view lane battler in the style of Black Navy War, replacing the Godot 3D
version as the main game (the 3D build lives on at `/3d/`).

## Stat provenance

Unit HP / speed / detection radius / stand-off distance, weapon reload times and
per-hit damage weights, boss roster (Dreadnought → Yamato), the boss gate rule
(enemy base invincible at 50% until the flagship is sunk), and the timer-based
enemy spawner design were extracted from the *Black Navy War: Re* (heppocogne)
Godot pack for fidelity. All art, audio, and code here are original; the economy
(gold income, unit costs, the six installation upgrades) is our own design since
those live in BNW:Re's compiled C# and were not recoverable.

## Files

- `sim2d.js` — pure deterministic sim (UMD: browser + node), all data tables inline
- `index.html` — canvas renderer, UI, Web Audio synth SFX; zero dependencies
- `test_headless.js` — balance oracle (run: `node test_headless.js`), also in CI

## Oracle conditions

1. Idle player genuinely loses stage 1 (enemy pressure is real)
2. Scripted auto-player wins stages 1–4 on multiple seeds inside 30 sim-minutes
3. Won games show sustained enemy-base HP progress across match thirds
4. Late stages (6, 9) survive past 5 minutes; no NaN / entity runaway

## URL flags

`?auto=1` autoplay demo · `?stage=N` pick stage (with auto) · `?seed=N` fix RNG
