# ⚓ Iron Corridor — 3D Naval Lane Battler

A 1D lane-push naval battler (spiritual successor to *Black Navy War*) with a 3D
presentation layer, built in Godot 4. The defining feature is that **balance is
converged by an automated verification loop, not hand-tuned**: every push runs a
headless simulation suite whose oracle conditions gate the build.

## Layout

| Path | Purpose |
|---|---|
| `sim/` | Pure-logic sim core — deterministic fixed-tick, zero Node dependencies |
| `data/` | All balance as data: units, levels, bosses, economy, weather, eras, skills |
| `harness/` | Headless balance harness + oracle checker (CI gate) |
| `presentation/` | Node3D scene layer — reads sim state, never writes into it |
| `web_shim/` | `coi-serviceworker.js` for SharedArrayBuffer headers on GitHub Pages |

## Verification loop

```sh
godot --headless --path . --editor --quit                     # import (class cache)
godot --headless --path . --script res://harness/run_balance.gd
godot --headless --path . --script res://harness/oracle_check.gd
```

The harness plays 4 scripted strategies (rush / eco / turtle / mixed) 500 times
per level, plus mono-composition runs and a cost-normalized unit matchup matrix,
writing `harness/out/balance_results.json`. The oracle then enforces the 7
level-oracle conditions (winnability, monotonic difficulty, no degenerate
strategy, unlock-free wins, boss killability, bounded weather impact,
determinism) and the 5 unit-balance checks (matchup deviation, dominant-unit,
counter-chain, economy curve, depth-layer relevance). Any failure = red build.

## Builds

- **Web** — `.github/workflows/deploy-pages.yml` exports the `Web` preset and
  deploys to GitHub Pages on every push to `main`.
- **Android** — `.github/workflows/android.yml` exports the `Android` preset as
  a debug-signed arm64 APK on every push and uploads it as the
  `iron-corridor-debug-apk` artifact. Download and sideload
  (`adb install iron-corridor-debug.apk`). Release signing: point the preset's
  `keystore/release*` fields (or `GODOT_ANDROID_KEYSTORE_RELEASE_*` env vars) at
  your own keystore and export with `--export-release "Android"`.

Local export mirrors CI: install export templates for the pinned Godot version
(see `GODOT_VERSION` in the workflows), then
`godot --headless --path . --export-debug "Android" build/android/iron-corridor-debug.apk`.
