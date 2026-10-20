# Space Z — Implementation Progress

> Living status document. **Update this file whenever meaningful work lands** so any future
> session (human or Claude) can continue without re-deriving context. Newest entries first
> within each section.

## Current status

**Phase:** **ALL MILESTONES M0–M5 COMPLETE** (2026-07-19), within what a single Windows
machine can deliver. The game is content-complete per PLAN.md: 7 zones/bosses, 11 weapons +
8 evolutions + 11 passives, procedural audio, tech tree, 8 ships, achievements, Black Hole
mode, quality tiers, tutorial, daily-seed runs, and a scripted build pipeline (the packaged
`dist/windows/SpaceZ.exe` and `dist/space-z.love` are smoke-verified). 276 headless tests as of
the run save & Continue feature (the original M0-M5 count was 92).

**Known open items** (need resources this machine lacks — see docs/BUILD.md):
- Android APK: pipeline fully scripted (`build/build-android.ps1`) but not executed —
  needs the one-time JDK 17 + Android SDK setup (~multi-GB).
- iOS: docs only (needs a Mac + Apple Developer account).
- Online daily leaderboards: daily seed + local bests shipped; a server/backend is
  owner infrastructure (PLAN.md defers it).
- Balance beyond the smoke bot: human playtests will want tuning passes (all knobs are
  data tables in src/content/).

**Read first:** `docs/PLAN.md` (design spec) → `docs/ARCHITECTURE.md` (binding module/API
contract, kept current) → this file. **Any code change that alters an API must update
ARCHITECTURE.md in the same change.**

## How to run

- **Game:** `love .` from the repo root (install LÖVE 11.x from https://love2d.org).
  On Windows use `lovec.exe .` to see console output.
- **Headless logic tests:** `lua tests/run.lua` (any Lua 5.1/LuaJIT) or `lovec . --test`.
- **Automated smoke test:** `lovec . --smoke` — autopiloted full run at 8× speed with a fixed
  seed (12345); saves screenshots (`smoke_*.png`) + `smoke_report.txt` to the LÖVE save
  directory (`%APPDATA%\LOVE\space-z` on Windows), prints the report to stdout, quits with
  exit code 0 on success. It beats the boss and reaches VICTORY as of 2026-07-19.
- Dev note: no system-wide LÖVE/Lua on the original dev machine; portable LÖVE 11.5 and
  Lua 5.1.5 binaries were used from the session scratchpad (temp dir — re-download if gone).

## Milestone checklist (from docs/PLAN.md)

- [x] **M0 — Feel:** LÖVE skeleton, stack state machine, 480×854 portrait viewport (letterboxed),
      3-layer parallax starfield + procedural Earth backdrop, steering (1:1 relative drag for
      touch + mouse, plus WASD), auto-fire, 4 enemy types, pooling everywhere,
      uniform-grid collision, HP/i-frames/death, minimal HUD (XP bar, HP ring, boss bar)
- [x] **M1 — Roguelite loop:** XP gems w/ merge+magnet, level curve, card-draft UI (3 cards,
      tap/keys, level pips, fallbacks), 5 weapons (blaster/missiles/flak/ion arc/drones) ×
      5–8 levels, 8 passives, elites (45s+, ×4 HP), Zone 1 + Kessler Swarm boss (2 phases,
      radial bursts, aimed fans, adds), warp/victory flow, Stardust economy + versioned JSON
      save, secret Black Hole unlock flag (flawless standard win), 60 headless tests, smoke bot
- [x] **M2 — Content & depth:** all 7 zones + 7 bosses + environment modifiers, 15 enemy
      types, full launch arsenal (blaster + 10 secondaries: missiles/flak/ion arc/drones/
      laser/graviton/cryo/railgun/solar aura), **8 evolutions** (guaranteed draft slot when
      ready), 11 passives incl. Overclock/Coolant/Shield Capacitor, slow + AoE + shield mechanics
- [x] **M3 — Meta & modes:** Star-Map tech tree (9 nodes, escalating costs), 8 ships +
      hangar screen (buy with Stardust, select), 10 achievements (live toasts + run-end
      reveals + lifetime stats), **Black Hole mode playable** (menu toggle once unlocked:
      one-hit death, ×1.5 enemy HP, ×2 Stardust, separate leaderboard-ready best distance),
      audio done (procedural chiptune SFX + music); settings = menu toggles (M/S) for now
- [x] **M4 — Juice & polish:** hit-stop on boss/elite kills, low-hull heartbeat + vignette,
      quality tiers (high/low: particle cap + starfield density, [Q] on menu), first-run
      tutorial hints, **daily-seed run** (same seed for everyone per date, local bests on
      menu + gameover; online boards = owner infra), screenshake/flash/sfx/music from M2/M3
- [x] **M5 — Ship pipeline:** `build/make-love.ps1` (.love), `build/build-windows.ps1`
      (fused SpaceZ.exe — **built & smoke-verified**), `build/build-android.ps1` (full
      love-android automation: clone, embed, identity, icons, gradle — needs one-time SDK
      setup to execute), procedural launcher icons (`lovec . --icons` → assets/icons/),
      HUD safe-area inset for notches, docs/BUILD.md (incl. iOS + store checklist)

## Work log

### 2026-10-20 — Run save & Continue (branch `feature/run-save-resume`)
- **Feature:** one saved run (stored in its own `run.json`) with a menu **CONTINUE** row, a 3-2-1 **countdown** after
  resuming and after pause Resume, and pause row 2 = **SAVE & QUIT**. Spec/plan/tasks:
  `docs/run-save-resume/`. Run-state snapshot (progression, build, HP, RNG, spawner timers); enemies,
  bullets and the boss are not saved, so a boss-fight save resumes with the boss re-entering at full HP.
  Daily runs are not resumable. Autosave every 10 s, plus pause, quit-to-menu, app background
  (`love.focus(false)`) and `love.quit`. Cleared on death and win. API: ARCHITECTURE.md (runsave.lua).
- **Code review fixes:** saved spawner timers and pending level-ups are range-checked (a corrupt `-1e9`
  timer would have looped the spawner ~666M times on resume); the run moved from a key in `save.json` to its
  own `run.json` so the 10 s autosave can never tear the file holding permanent progress; shared test
  helpers; `lovec . --test` now runs on an in-memory filesystem and no longer touches real save files.
- **Verified (desktop):** 276 tests pass (`luajit tests/run.lua` and `lovec . --test`). `lovec . --smoke`
  gives the identical final line to `main` (t=320s zone=2 level=11 kills=381 distance=37630) and writes no
  run. `run.json` handling (create, reload, torn file, delete, `save.json` untouched) also checked against
  the real `love.filesystem` in a scratch LÖVE project. Autosave cost, desktop, worst-case full build:
  snapshot ~0.005 ms, JSON encode ~0.06-0.14 ms, encode + file write ~0.9 ms (1.15 KB), once per 10 s
  (measured before the split; the file write is now run.json only).
- **Not verified:** the look of the countdown overlay, the menu's abandon prompt and the 6-row menu layout
  (no one has seen them on screen yet); anything on an Android device (backgrounding mid-draft, process
  kill, flash write time).

### 2026-07-19 — Session 4 (Claude): M4 polish + M5 ship pipeline
- **M4**: hit-stop (`world.freezeT` — sim freezes, drawing continues; 0.15s boss /
  0.06s elite kills), low-hull heartbeat sfx + pulsing red vignette below 25% HP,
  quality tiers (`settings.quality`: low = 220-particle cap + thinned starfield;
  [Q] menu toggle), staged first-run tutorial hints (marks `save.tutorialDone` once
  level 2 or 30s), **DAILY RUN** menu row (seed = YYYYMMDD → identical world for
  everyone that day; `save.daily` local bests shown on menu + gameover).
- **M5**: `Viewport.safeTop()` + HUD notch inset; `lovec . --icons` renders launcher
  icons procedurally (512/192/144/96/48 → `assets/icons/`); `build/make-love.ps1`,
  `build/build-windows.ps1` (fused exe **verified**: `dist/windows/SpaceZ.exe` passes
  the smoke run), `build/build-android.ps1` (prereq checks → clone love-android →
  embed game.love → patch gradle.properties identity/portrait → install icons →
  gradle assembleEmbedNoRecord{Debug,Release}); `docs/BUILD.md` covers Android
  one-time setup, signing, iOS-on-Mac, and the store checklist.
- Verified: 92/92 tests; god run still full-clears (t grew ~17s = hit-stop working);
  honest run unchanged; packaged .love + fused exe both smoke-pass.

### 2026-07-19 — Session 3 (Claude): M2 arsenal + evolutions, full M3 meta
- **5 new weapons / 4 new behaviors**: Laser Beam (`beam` — continuous column DPS),
  Graviton Pulse (`pulse` — radial damage + slow), Cryo Shards (spread + chill-on-hit),
  Railgun (`rail` — hitscan piercing column), Solar Flare Aura (`aura`). New mechanics:
  enemy **slow** (time-dilated movement, ice tint, bosses resist), **AoE splash**
  (nuclear), **Shield Capacitor** (blocks a hit, preserves the no-damage flag, recharges).
- **8 evolutions** (maxed weapon + catalyst passive → gold EVOLUTION! card, guaranteed a
  draft slot): Plasma Storm, Nuclear Barrage, Buckshot Nova, Ion Storm, Battle
  Constellation, Death Ray, Singularity, Absolute Zero. +3 passives (Overclock, Coolant,
  Shield Capacitor) → 11 total.
- **M3 meta**: `meta/tech.lua` Star-Map (9 permanent nodes, cost = base·1.7^rank) +
  starmap screen; 8 ships in `content/ships.lua` (stat bonuses + unique starting weapons,
  7 new ship sprites) + hangar screen; `meta/achievements.lua` (10, live toasts via
  world.toasts + run-end reveals, lifetime stats in save.stats); **Black Hole mode**
  playable via menu MODE row / [B] (spawner ×1.5 HP, stardust ×2, bestDistanceBH).
- Menu reworked into a hub (LAUNCH/HANGAR/STAR MAP/MODE); smoke harness now tours
  menu→hangar→starmap with screenshots before launching; god build exercises
  beam/pulse/rail/homing + a guaranteed first-draft evolution.
- Verified: 90/90 tests; god run full-clears all 7 zones/bosses (~20 sim-min, VICTORY);
  honest run clears Z1 → dies Z2 (intended curve); hangar/starmap screenshots checked.

### 2026-07-19 — Session 2 (Claude): audio + all 7 zones
- **Procedural retro audio** (`src/audio/`): chiptune synth DSP (`synth.lua` — square/saw/
  tri/sine/pitched-noise layers, sweeps, arps), 18 synthesized SFX (`audio.lua` — pooled
  sources, rate-limited, `weapon_fired` event → per-weapon sounds, pickup combo pitch),
  and a **generative music sequencer** (`music.lua` — unique seeded 8-bar chiptune theme
  per zone + menu + boss themes; lazily generated, cached). `[S]` on the menu toggles sound.
- **All 7 zones** with distinct environments (user request confirmed + implemented):
  Moon (meteor showers), Mars (sinusoidal **wind** dust storms + haze bands), **Asteroid
  Belt** (ballistic tumbling rocks incl. side-crossers, pirates), **Jupiter** (constant
  downward **gravity** + sluggish steering, storm wisps), Saturn (side-crossing ring ice,
  ring-plane backdrop), Void (breathing nebula, hive). New `ballistic` movement pattern,
  zone `modifiers` (gravity/wind/playerSpeedMult), side spawns, per-zone difficulty scaling,
  banner subtitles ("HIGH GRAVITY", ...), per-zone planet-limb/nebula backdrops.
- **6 new bosses** (7 total, one per zone, all with phase-2 escalations): Mining Leviathan
  (drill dives), War Machine (spiral barrages), Asteroid Titan (rock bursts + live adds),
  The Great Storm (lightning dashes + gravity pulses that drag the ship down), Ring
  Guardian (descending ice walls with dodge gaps), Space Z Overlord (3-phase finale).
- New sprites: asteroid, meteor, pirate, ice shard, hive dart + 6 boss designs (atlas → 1024).
- Smoke harness: `--smoke god` coverage variant (durable strong build) — verified full
  7-zone clear; honest `--smoke` remains the balance signal (clears Z1, dies ~Z2-3 ✓).
- Bugs fixed: spawner side-spawn used un-localized VH (crash entering Belt); god build was
  wiped by stat recomputes (now lives in shipDef + a permanent passive); planet backdrops
  sank off-screen in ~20s (limb geometry retuned to ~100s).

### 2026-07-19 — Session 1 (Claude)
- Wrote `docs/ARCHITECTURE.md` (binding contract), then implemented all of M0+M1 (~30 files).
  Implementation was seeded by a 9-agent parallel workflow (2 completed, 7 cut off by session
  limits but most had already written their files — all recovered code was complete and used);
  the remaining 19 files were written inline.
- Test suite: 60 tests across rng/pool/json/save/damage/leveling/pickups/spawner — all passing
  on plain Lua 5.1 headless.
- Smoke harness (`--smoke`): autopiloted bot (weave, XP-chase, threat-dodge, boss-park) that
  wins a full run; auto-screenshots at menu/early/levelup/mid/late/boss/gameover.
- Bugs found & fixed during integration:
  1. Homing missiles crashed on stale target refs (pooled enemy table recycled → fields wiped).
     Fix: treat `target.kind ~= "enemy"` as dead in `weapons.lua`.
  2. World rendered near-black beyond distance 12000: `lg.draw(batch)` is modulated by the
     current graphics color, and `starfield:drawBackdrop` early-returns (Earth fully sunk)
     without resetting it. Fix: explicit `setColor(1,1,1,1)` before batch draws (game + menu).
  3. Level-up header drew mismatched glow/text strings overlapping. Fixed.
- Balance: Kessler Swarm HP 1400 → 1150 (bot boss fight was ~110s; human should land ~30–60s).
- Inline correctness review of hot paths (pool recycling, event wiring, phase transitions,
  grid collision vs boss radius, run-end idempotence guard) — no further issues found.

## Known issues / TODO (short-term)

- Balance across zones 2–7 and Black Hole mode is tuned only against the smoke bot;
  human playtests will want passes over `src/content/*.lua` numbers.
- `world.arcs`/`world.beams`/`world.pulses` allocate small tables per event (minor churn;
  pool if profiling ever flags it).
- Drone per-enemy hit-cooldown keys can briefly carry over to a recycled enemy table (≤0.5s
  of unearned immunity — cosmetic-level impact).
- A deeper multi-agent adversarial review pass is worth running when subagent capacity allows.
- Android APK build not yet executed (pipeline scripted; needs one-time SDK setup — BUILD.md).
- Fancy settings screen deferred (menu [S]/[Q] toggles cover sound/quality; steering has no
  setting any more — 1:1 relative drag is the only scheme).
- Both remaining menu toggles are keyboard-only, so they are unreachable on a phone.
- No on-screen pause control; pause is `escape` only (Android maps the back button to it).
- Seeded runs are no longer bit-reproducible *across devices* now that the sim steps by real
  elapsed time (`--smoke` keeps its own fixed 1/60 loop and stays deterministic).

## Decisions made during implementation (deltas vs PLAN.md)

- M1 arsenal: weapons `blaster, missiles, flak, ion_arc, drones`; passives `crit_systems,
  warhead_yield, hull_plating, nanorepair, thrusters, reactor_core, tractor_beam, ammo_feed`.
  Evolutions deferred to M2 (schema fields reserved).
- Smoke screenshots use `love.graphics.captureScreenshot` (simpler than canvas re-render).
- Steering rewritten to 1:1 relative drag (positional), replacing the floating/absolute rate
  controls; `settings.steerMode` and the `[M]` toggle are gone and stripped from old saves.
  Fixed alongside: pushed overlays used to strand the steering touch id (`game:resume()` now
  calls `input:reset()`), and `love.update` steps by real elapsed time so the ship no longer
  stair-steps on 90/120 Hz displays. That last change means anything added *per step* rather
  than scaled by `dt` is now refresh-rate dependent — the two that existed (laser beam visual
  in `weapons.lua`, drill-boss telegraph shudder in `boss.lua`) were fixed.
- Tests are pure-Lua headless (gameplay systems never touch `love.*` at module load);
  render/ui modules are exempt and verified via the smoke run instead.
- Stardust formula (lives in `src/meta/progress.lua` ONLY):
  `kills + 5*floor(distance/1000) + 40*bossKills + in-run bonuses`.
