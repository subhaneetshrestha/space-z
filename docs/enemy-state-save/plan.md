# Implementation Plan: Frozen-Moment Run Save + LÖVE 12

Spec: `SPEC.md` (project root). Task list: `docs/enemy-state-save/todo.md`. Headless tests: `lua tests/run.lua`
(CI runs `lua5.1`; locally `luajit tests/run.lua` also works). Engine tests: `lovec . --test` and `lovec . --smoke`.

## Overview

Two independent workstreams that meet at the end.

- **Part A, exact snapshot.** Extend `src/meta/runsave.lua` (version 2) to capture the whole live world: player,
  enemies with their behaviour state, the boss, enemy and player bullets, pickups and drones. Resuming restores them
  in the same list order, and the spec's behavioural-identity test proves a resumed world and an uninterrupted one
  stay equal.
- **Part B, LÖVE 12.** One `LOVE_VERSION` file becomes the single source of truth. `conf.lua`, the Windows build, CI and
  the Android build read it. Android stops following upstream `love-android` HEAD. The game is run on 12, and whatever
  breaks is fixed.

## What the code looks like today (verified)

**Save code**
- `RunSave.snapshot` (`src/meta/runsave.lua`) rewinds the `boss` phase to `zoneTime = zone.duration` with an empty
  field, and sets `warp` to the next zone's start. It returns nil for a `warp` in the last zone. Those rewinds are
  exactly the cheat. They go away.
- `RUN_VERSION = 1`. `validate` is strict (every field type-checked, timers bounded). `apply` runs on a world fresh from
  `game:enter` and calls `Leveling.recomputeStats`, then sets HP.
- `Game.saveRun` is the one write entry point, and autosave runs after `Pool.sweep` inside `update`, so a snapshot never sees dead entities
  (the pause, focus and quit triggers also run between frames, where the lists are swept).

**Entities**
- Every entity is a pooled table: `Pool:acquire` returns an empty table and each spawn helper fully re-initializes it.
  `Pool.sweep` is **swap-remove**, so list order is not stable, and collision breaks on the first hit in list order. **Restore must
  keep the saved list order**, or a resumed run can diverge.
- Enemies (`Spawner.spawnEnemy`, `movement.lua`): scalar fields plus lazily created behaviour scratch (`phase`, `baseX`, `spin`,
  `spd`, `fireT`, `lungeT`, `slowT`, `slowMult`). They also hold `def` (a table reference, saved as an id), `sprite` and `tint`
  (derived from `def`).
- Boss (`boss.lua`): same table, plus `isBoss`, `bossDef`, `entering`, `bt`, `bossPhase`, `dashX`, `diveX`, hover offsets and
  per-behaviour timers (`burstT`, `fanT`, `addT`, `wallT`, `spiralA`, `state`, `stateT`, ...). `world.boss` points at it, and
  `damage.lua` sets it to nil on death.
- Enemy bullets: `x, y, vx, vy, r, rot, scale, t, damage, life`, sprite `bullet_enemy`.
- Player bullets: `... pierce, life, weaponId, slowT, slowMult, aoe`; homing missiles also carry `homing` and **`target` (an enemy reference)**.
- Pickups: `ptype, value, magnet, vx, vy, t`; sprite is derived from `value` (`tierSprite`).
- Drones (`weapons.lua`): `angle, angVel, orbitR, damage, t, hitCdN`, and **`hitCd`, a table keyed by enemy reference**.
- Weapon scratch on `world.weapons[i]`: `cooldown` (saved today as reset), `side`, `tickT`; `hit` and `beamVis` are temporary or cosmetic.
- `world.freezeT` (hit-stop) is real simulation state. Particles, arcs, beams, pulses, toasts, shake, starfield and `Game`'s own timers
  (`damageFlashT`, `trailT`, `lowHpT`, `pickupCombo`) are cosmetic and not saved.

**Tests and builds**
- `tests/support.lua` has `firstDiff`, `memoryFilesystem`, `loadWithStubs`; `tests/game_harness.lua` drives the REAL game state headless.
- `tests/run.lua` has an explicit `FILES` list: new test files must be added to it.
- `build-android.ps1` clones `love-android` at default branch HEAD (now bundles LÖVE 12.0). The `11.5` string lives in
  `conf.lua`, `build.yml`, `build-windows.ps1`, `build-android.ps1` (comment), `build-web.ps1` (comment),
  `docs/BUILD.md`, `docs/ARCHITECTURE.md`. `VERSION` (`1.1`) already exists as the app version.
- `gh` is installed and logged in locally, so the LÖVE 12 Actions artifact can be downloaded from this machine.
- Branch state: `feature/run-save-resume` is **14 commits ahead of `main` and not merged**. This work builds on those commits.

## Architecture Decisions

1. **Whitelist capture, derived data recomputed.** Each entity kind has an explicit field list. `def`, `bossDef` and sprites are saved as
   ids or recomputed (`tierSprite`, `weaponDef.sprite`, `"bullet_enemy"`), so a save cannot name an arbitrary sprite. This differs slightly
   from the spec's field table (sprite is not stored for bullets and pickups) and gives the same behaviour.
2. **A completeness test keeps the whitelist honest.** Long deterministic sims over every enemy movement type and every boss; the test fails
   if any live entity has a key that is neither whitelisted nor on an explicit `DERIVED` list. A new behaviour field breaks the build until it is
   classified. This replaces grepping source.
3. **Cross-entity references go through list indexes.** In the save, enemies are numbered by list position. `world.boss` is an index,
   `bullet.target` is an index (or nil if the target is gone), `drone.hitCd` becomes `{ enemyIndex, expiry }` pairs. On restore, all enemies are rebuilt first,
   then references are re-linked. An index outside the list rejects the save.
4. **List order is preserved.** Entities are saved and restored in list order. A test with swap-removed gaps proves it.
5. **Version 2 envelope.** `RUN_VERSION = 2` adds `entities`, `world` and `player` blocks. `validate` accepts version 1 (no entities,
   already-rewound) and version 2. `apply` treats a version-1 run as an empty field, as today. The `boss`/`warp` rewind code is deleted from `snapshot`.
6. **Restore stays on the normal path.** `game:enter` builds the world; `RunSave.apply` overwrites it; then `enter` pushes `countdown`. When the
   restored phase is `boss`, `enter` starts the boss music instead of the zone music (no `boss_spawned` event is re-emitted, so no alarm).
7. **Validation per entity, with measured caps.** Each entry is checked like the existing fields (finite numbers, known ids, booleans, in-range
   timers). Caps are set from measured worst cases (task A6), well above anything reachable, and only reject corrupt files.
8. **LÖVE version file.** `LOVE_VERSION` (key=value text: `love=12.0`, `love_commit=<sha>`, `love_android_commit=<sha>`) is read by `conf.lua`
   (through a tiny parser, with the file packaged into the `.love`), by `build/*.ps1` and by `build.yml`. A headless test fails if `conf.lua`
   and the file disagree, or if `11.5` appears in tracked build files or docs (outside history and this plan).
9. **Pinned, not moving.** Both the `love` commit (desktop artifact) and the `love-android` commit are pinned. Bumping is one edit to `LOVE_VERSION`,
   documented as the upgrade procedure.
10. **Desktop 12 binary comes from the `love2d/love` Actions artifact for the pinned commit**, via `gh` (locally) and `GITHUB_TOKEN` (CI).
    `build/get-love.ps1` does the download and unpack, shared by local and CI use.

## Dependency Graph

```
B1 get a LÖVE 12 desktop build, run --test/--smoke, record findings   (independent, high risk, so first)
 |
 +--> B2 LOVE_VERSION + conf.lua + compat fixes ----+
                                                    |
A1 v2 envelope + player + world state + diff helper |
 +--> A2 enemies (+ reference table + completeness test)
       +--> A3 bullets (enemy + player, homing target)
       +--> A4 pickups + drones (hitCd references)
             +--> A5 boss + phase rules (delete rewinds) + music
                   +--> A6 validation fuzz + caps + autosave cost
                         +--> A7 game integration (enter, no-dodge test, countdown freeze)
                                                    |
B3 build scripts + Windows on 12  <-- B2            |
 +--> B4 engine tests in CI (--test, --smoke on 12)  |
B5 Android pin (independent after B2)               |
B6 web build decision  <-- B2                       |
 +-----------------------------+--------------------+
                               v
                    B7 docs + upgrade procedure + leftovers gate
                               v
                    V1 end-to-end verification, PR
```

A-tasks are sequential (shared file `runsave.lua`). B3 to B6 are independent of Part A and of each other once B2 exists.

## Task List

(Full acceptance criteria and verification steps are in `todo.md`.)

### Phase 0: Learn what LÖVE 12 breaks
- [ ] B1: Get a LÖVE 12 desktop build and record what fails

### Phase 1: Version foundation
- [ ] B2: `LOVE_VERSION`, `conf.lua`, compat fixes

### Checkpoint: Version foundation
- [ ] `lua tests/run.lua` passes; `lovec . --test` and `--smoke` pass on the LÖVE 12 build; no compatibility dialog

### Phase 2: Exact snapshot
- [ ] A1: Version 2 envelope, player, world state, diff helper
- [ ] A2: Enemies and the reference table
- [ ] A3: Enemy and player bullets
- [ ] A4: Pickups and drones
- [ ] A5: Boss and phase rules
- [ ] A6: Validation fuzz, caps, autosave cost
- [ ] A7: Game integration and the no-dodge test
- [ ] A8: A hit deletes the save (rollback fix chosen by the user; `SPEC.md` Part C)

### Checkpoint: Cheat closed
- [ ] Behavioural identity passes for all seven bosses and all enemy movement types
- [ ] No-dodge test passes; suite and engine tests green on 12
- [ ] Review with human

### Phase 3: Builds on 12
- [ ] B3: Build scripts read `LOVE_VERSION`; Windows exe on 12
- [ ] B4: Engine tests in CI
- [ ] B5: Android pinned
- [ ] B6: Web build decision

### Phase 4: Ship
- [ ] B7: Docs, upgrade procedure, leftover-`11.5` gate
- [ ] V1: End-to-end verification and PR

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| A behaviour field is missed and a resumed run drifts | High | Behavioural-identity test for each boss and enemy type, plus the completeness test (decision 2) |
| List order changes on restore, so collision order differs | High | Order preserved (decision 4); test with gaps from swap-remove |
| Dangling references (`target`, `hitCd`, `world.boss`) | High | Index table (decision 3); an out-of-range index rejects the whole save; test each |
| LÖVE 12 breaks things we cannot predict | High | B1 runs first and records findings; B2 fixes them behind `src/compat.lua` |
| LÖVE 12 desktop artifact needs `gh` auth and artifacts expire | Med | Cache the unpacked build in CI keyed on the pinned commit; local copy kept in `dist/love12/` (gitignored); fall back to building from source if artifacts are gone |
| Engine tests in CI need a GL context (Linux, headless) | Med | Try `xvfb-run` with Mesa software GL; if LÖVE 12's GL 3.3 / Vulkan floor blocks it, run the job on `windows-latest` instead (B4 decides) |
| No LÖVE 12 love.js for the web build | Med | B6 decides with the user: stay on the 11.x runtime with a documented exception, or drop web from the pipeline |
| Autosave cost grows with a full field, stutter on Android | Med | A6 measures; budget in the spec; interval is one constant; use compact JSON |
| Old tests encode the rewind behaviour | Med | They are replaced, not weakened, in A5; the replacement asserts the opposite, and the change is called out in the commit and todo |
| Pinned `love-android` commit does not build with our patched `build.gradle` | Med | B5 builds the APK in CI before the pin lands; abort if `abiFilters` patch fails (the script already fails loudly) |
| Resuming a `warp` re-fires or loses achievements | Low | Verified in code: `zone_completed` fires at the boss kill and unlocks are persisted by `Save.write`; resuming `warp` emits nothing, so there is no loss and no double count. Test in A5 |
| Branch is 14 commits ahead of `main` and not merged | Low | Work continues on a new branch from `feature/run-save-resume`; the PR targets that branch's merge order (ask which in V1) |

## Open Questions

- **Web build:** B6 needs a decision once we see whether a LÖVE 12 `love.js` exists.
- **Merge order:** V1 asks whether to merge `feature/run-save-resume` into `main` before this work or after.
