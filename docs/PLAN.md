# Space Z — Design & Implementation Specification

> Code-ready specification. Distilled from user requirements + a fact-checked deep-research pass (104 research agents, 22 verified findings, cited inline). This document is the single source of truth for implementation.

## How to use this document (for the implementer)

Space Z will be implemented in **Lua on LÖVE (Love2D)**. This spec is **data-driven by design**: build the systems once, then express ships / weapons / upgrades / enemies / zones as Lua tables in `src/content/*.lua`. Follow the **Milestones (M0–M5)** in order — each is independently playable and testable. **All 2D art is generated procedurally in code** (no external art assets). Start at **M0 (core feel)** and prove the game is fun before adding content.

## Context

**Space Z** is a 2D space-themed roguelite for **phones and PC**, written in **Lua** on an **open-source engine**, with a design goal of "simple but deep." Graphics are intentionally low-fidelity 2D. The game is built and its 2D assets generated **autonomously from code**, so the whole plan is optimized for a code-and-text-file workflow with no dependency on hand-made art or a GUI editor. Greenfield project at `C:\Users\Subhaneet Shrestha\Projects\space-z` (sibling to `smart-wallet`).

## Locked decisions

- **Core play:** Vertical-ascent space shooter — the rocket climbs from Earth into deep space; one-thumb steering; auto-fire forward.
- **Run shape:** Solar-system journey — Earth orbit → Moon → Mars → Asteroid Belt → Jupiter → Saturn → Deep Space, a boss ending each zone; run ends on death or on beating the final zone.
- **Progression:** Full roguelite — persistent Stardust currency, ship/pilot unlocks, a **multi-track** meta, achievements.
- **Art/performance:** Neon-vector look delivered as **pre-baked, batched procedural sprites** (best mobile performance + fully autonomous).
- **Power-up flow:** **level-up card draft** (pick 1 of 3–4 on level-up), capped at **~6 weapon + ~6 passive** slots.
- **Build depth:** **evolutions + synergies** (weapons evolve when paired with the right passive).
- **Difficulty:** **Standard** (HP bar + regen) is the default; **Black Hole** is a **secret hardcore mode** (one-hit death + tankier enemies), unlocked by completing a Standard run **without taking any damage**.
- **Arsenal scope:** **curate tight for launch** (~10 weapons, ~10 passives, ~6–8 evolutions), expand post-launch.

## What the research changes (and confirms)

The survivors-like/bullet-heaven genre is a **validated top-grossing mobile category** (Survivor.io: ~$75M IAP in 2 months, $500M+ lifetime) — but the decisive lesson is a **warning**: retention collapses (D30 ~4%) when progression is a **single power track**. So the top design risk is meta depth; the mitigation is **multiple independent progression tracks**. [naavik.co, mobilegamer.biz]

Three findings shape the design: (1) **"Simple but deep" is a deliberate formula** — movement-only auto-fire over ARPG stats/items/synergies, a "candy bar" Diablo [Halls of Torment dev talk; fullcleared.com]; (2) **game feel = precise, forgiving, shmup-derived movement with player-favored hitboxes** — a perfect fit for a vertical space shooter [fullcleared.com]; (3) **content benchmarks:** ~11 launch characters each with a unique starting weapon, **6 active + 6 passive** in-run slots, ~15-min runs with a boss ~every 5 min [fullcleared.com; naavik.co].

## Core gameplay loop

1. The rocket auto-climbs; the world scrolls, parallax starfield behind. One-thumb steering; the ship **auto-fires** forward. Small, forgiving player hitbox.
2. Space monsters + hazards (asteroids, debris) stream toward/past you. Dodge; auto-fire + power-ups clear them.
3. Kills drop **Energy Cells (XP)** (auto-collected within magnet range). Fill the bar → **LEVEL UP** → brief pause → draw **3–4 upgrade cards** → pick one. *This is the only moment upgrades are chosen — keeps play uncluttered.*
4. Periodic **elites**, then an end-of-zone **BOSS**. Beat it → warp to the next, harder zone.
5. Run ends on death or after the final zone. Earn **Stardust** (scaled to depth) + **Alien Cores** (bosses).

**Run pacing:** each zone is a ~2–4 min escalating-wave "chapter" ending in a boss. A geared full run is ~20–25 min; early runs end far sooner (die in zone 2–3). Meta-progression extends reachable depth over time — short mobile sessions with a long-term "reach the Void" goal.

## Difficulty modes

- **Standard (default):** HP bar; contact damage + enemy projectiles chip it; some upgrades regen it. Forgiving, survivors-style, good for all skill levels and long mobile runs.
- **Black Hole (secret hardcore):** **any hit ends the run** and **enemies are tankier** (higher HP). Rewards: a **Stardust multiplier** (e.g., 2×), a **separate leaderboard**, and an exclusive cosmetic/skin.
  - **Unlock:** *secret* — complete a full Standard run **without taking any damage** (a flawless clear). The game silently tracks a per-run "no-damage" flag; a flawless clear reveals Black Hole with a special screen. (Exact trigger — full no-hit clear vs. a lesser no-hit feat — is tunable in playtest if a full clear proves unreachable.)
  - Because it demands a strong evolved build to survive, it naturally becomes the endgame mastery goal.

## Controls & anti-clutter UI (a primary requirement)

**Steering (one thumb, no fire button — validated because attacks auto-fire):** [equalentry.com; naavik.co]
- **Mobile:** **1:1 relative drag** — touching down grabs, and the ship then moves by exactly the delta your finger moves (scaled by `stats.speed / 300`, so upgrades cover more ground per finger-pixel). Engages anywhere on screen, so the thumb never covers the ship. This is *positional*, not rate control: the documented **"drift-and-die" pitfall** (finger creeps to the edge, re-centering stalls the ship) cannot occur because there is no anchor to drift from — lifting and re-placing the thumb re-grabs for free, and over-dragging into a wall banks no slack to retrace. Shipped as the single steering scheme; the old floating/absolute modes and their `settings.steerMode` toggle were removed. [equalentry.com; inairspace.com]
- **PC:** mouse-follow or WASD/arrows; auto-fire; one key (Space) for a ship's active ability.
- **At most one** on-screen button, ever — only for ships with a manual special.

**Avoiding power-up-icon clutter (the 6+6 slot cap is the core mechanism):**
- Upgrades chosen via **level-up cards**, never tapped mid-run.
- Hard cap **~6 weapon + ~6 passive** slots — bounds on-screen effects *and* forces build-defining choices. [naavik.co]
- **Passives** are invisible (numbers only, no icons). **Weapons/actives** show as **effects on the ship** (extra cannons, drones, missile pods, auras), not a HUD badge grid.
- **Minimal HUD:** thin XP bar + level + zone name; boss health bar only when present; ship health as an integrated ring/pips; optional collapsed "loadout" chip to review the build between waves.

## Engine & tech stack

**Engine: LÖVE (Love2D)** (the version in use is pinned in `LOVE_VERSION`) — with the one honest trade-off called out.

Why LÖVE: **pure Lua** on **LuaJIT** (speed for thousands of entities); **genuinely open source** (zlib) — whereas Defold is **"source-available," not OSI open source**, cutting against the "open source as much as possible" requirement [defold.com/opensource]; and the **best autonomous-dev loop** (everything is Lua + your game loop; edit `.lua`, run `love .` instantly, no editor). Defold is editor-centric (protobuf scene files) — far less natural for pure code-gen. Strong batched 2D (`SpriteBatch`, `ParticleSystem`, `Canvas`, shaders); ships to desktop + Android + iOS + web; proven by hits (e.g., Balatro).

**Honest trade-off — mobile packaging:** research confirms LÖVE's Android build is **not one-click** (build through the official `love-android` Gradle project; needs SDK/NDK/JDK), while Defold offers easier one-click bundling. [github.com/love2d/love-android] Mitigation: it's a **one-time, command-line-automatable** setup (script it as a build task), and designing mobile-first avoids the late-port pain finished desktop games hit. **Defold is the documented fallback** if it proves too costly.

## Rendering & art/performance (fully autonomous)

- **Procedural neon sprites, baked once:** generators draw each ship/monster/bullet/explosion/background into a **texture atlas** at load. No hand-drawn art → fully autonomous, instantly iterable, crisp at any resolution.
- **Batched rendering** through `SpriteBatch` + atlas → few draw calls at thousands of entities.
- **Cheap glow:** additive blending with glow **baked into textures**, not full-screen bloom (which becomes an optional quality tier low-end devices skip).
- **Particles** via batched `ParticleSystem` with hard per-frame budgets.
- **Targets:** 60 FPS with ~500–1500 entities on mid-range phones, via pooling + spatial-hash collision + batching + capped particles + quality tiers.

## Architecture & project structure

Data-driven throughout — every ship/weapon/upgrade/enemy/zone is a Lua table, added/tuned without engine changes.

```
space-z/
  conf.lua                  -- window (portrait-first), mobile flags, identity
  main.lua                  -- love callbacks: load/update/draw/resize/touch/key
  src/
    core/     -- state machine (menu/game/pause/levelup/gameover/hangar),
                 fixed-timestep loop, seeded RNG, object pools, event bus
    ecs/      -- lightweight, pool-based entity system (perf-first)
    systems/  -- movement, spawn director (difficulty curve), collision
                 (uniform-grid spatial hash), weapons/firing, damage+crit,
                 pickups/XP, boss, particles, camera/parallax
    content/  -- ships.lua, weapons.lua, upgrades.lua, enemies.lua,
                 bosses.lua, zones.lua  (all data tables)
    render/   -- procedural atlas builder, SpriteBatch renderer, shaders,
                 HUD, upgrade-card UI
    meta/     -- save/load (love.filesystem + JSON), currencies, unlocks,
                 achievements, difficulty modes, settings
    ui/       -- touch (1:1 relative drag steering), buttons, menus, scaling
  assets/     -- generated atlases (or generators), fonts, sfx/music (CC0)
  lib/        -- small permissively-licensed helpers (hump, json.lua, flux)
  tests/      -- logic tests (damage/crit math, upgrades, save/load, spawner)
```

Cross-cutting: **portrait-first** orientation; virtual resolution scaled to fit with notch/safe-area handling; **seeded RNG** for dailies/leaderboards/repro tests; **versioned JSON save**; a silent **per-run no-damage flag** feeding the Black Hole secret unlock.

## Content design

**Ships / pilots (target ~8–11 at launch, each with a unique starting weapon):** [fullcleared.com]
Pathfinder (starter, balanced twin blasters) · Aegis (tank: high HP, slow, damage-reduction, frontal flak) · Falcon (interceptor: low HP, fast, high crit, piercing railshot) · Barrage (gunship: interval homing missiles) · Halo (support: orbiting drones) · later: Nova (glass-cannon burst), Warden (graviton/"5G" slow specialist), + 1–2 more.

**Curated launch arsenal** (tight set; more added post-launch):
- *Primary weapon (base, leveled):* **Blaster** with upgrade paths — Overclock (fire rate), Multi-shot, Piercing Rounds, Targeting Computer (damage).
- *Secondary weapons (~9–10, each auto-fires on its own timer):* **Missile Bay**, **Graviton "5G" Pulse** (slows enemies), **Ion Arc**, **Orbital Drones**, **Laser Beam**, **Flak Spread**, **Cryo Beam**, **Railgun**, **Solar Flare Aura**. *(Post-launch: Mine Layer, Singularity Bomb, EMP Burst, Homing Rounds.)*
- *Passives (~10, invisible stat mods):* **Critical Systems** (crit chance), **Warhead Yield** (crit mult), Hull Plating (+HP), Nanorepair (regen), Thrusters (+speed), Reactor Core (+XP), Tractor Beam (+pickup range), Ammo Feed (+projectiles), Shield Capacitor (recharging block), Coolant (+damage vs slowed). *(Post-launch: Lucky Star, Salvage, Ricochet.)*
- *Evolutions (~6–8, max weapon + specific passive → upgraded form):* Missile Bay + Warhead Yield → **Nuclear Barrage**; Graviton Pulse + Reactor Core → **Singularity**; Multi-shot(max) + Ammo Feed → **Plasma Storm**; Laser Beam + Overclock → **Death Ray**; Ion Arc + Critical Systems → **Ion Storm**; Orbital Drones + Overclock → **Battle Constellation**; Cryo Beam + Coolant → **Absolute Zero**; Flak Spread + Ammo Feed → **Buckshot Nova**.
- *Active ability (one optional button, per ship):* Overdrive/Dash, Warp-blink, Bomb, or Shield-burst.

**Zones (each = backdrop + enemy set + hazard + boss):** Low Earth Orbit (debris/satellites; Kessler swarm) → The Moon (meteor showers; mining leviathan) → Mars (dust storms/drones; war machine) → Asteroid Belt (dense asteroids/pirates; asteroid titan) → Jupiter (radiation/storms/gravity wells; storm entity) → Saturn's Rings (ice/ring debris; ring guardian) → Deep Space/The Void (the "Z" alien hive; final boss: the Space Z overlord).

**Meta-progression (multiple tracks, to dodge the single-axis retention trap):** [naavik.co]
1. **Star-Map tech tree** — bounded permanent % boosts.
2. **Ship/pilot unlocks** — horizontal variety, not just power.
3. **Weapon unlocks** — new drafts enter the pool.
4. **Achievements/milestones** — gate unlocks; includes the **secret Black Hole unlock** (flawless Standard clear) and beating Black Hole for exclusive cosmetics.
5. **Codex/Bestiary** + **Daily seed & leaderboards** (Standard + Black Hole).
Currencies: **Stardust** (soft, every run) + **Alien Cores** (bosses).

## "Simple but deep" principles

- **Simple:** one-thumb steering, auto-fire, pick-a-card upgrades, capped slots, readable neon shapes, no icon clutter.
- **Deep (opt-in):** weapon+passive evolutions/synergies, distinct ships, multi-track meta, escalating zones, dailies/seeds, the secret Black Hole hardcore mode. Newcomers just fly and pick cards; veterans chase flawless runs and evolved builds.

## Milestones

- **M0 — Feel:** LÖVE skeleton, state machine, portrait field, parallax starfield, 1:1 relative-drag steering + mouse + WASD, auto-fire, one enemy, pooling, spatial-hash collision, HP/death, minimal HUD. *Goal: the core feels fun.*
- **M1 — Roguelite loop:** XP/leveling, card-draft UI, ~4 weapons + starter passives, enemy variety, Zone 1 + first boss, run-end + Stardust. *Goal: one satisfying full run.*
- **M2 — Content & depth:** all 7 zones + bosses, the **curated launch arsenal** + evolutions/synergies, crit/missile/graviton systems, elite modifiers, 6+6 slot caps.
- **M3 — Meta & modes:** save system, Stardust economy, multi-track meta (tree + ship/weapon unlocks + achievements), ~8–11 ships, **Standard + Black Hole modes** with the secret flawless-clear unlock, settings, audio.
- **M4 — Juice & polish:** procedural neon art pass, particles/screenshake/hit-flash, sfx/music, quality tiers, menus, tutorial, daily seed + leaderboards.
- **M5 — Mobile ship:** scripted Android APK (love-android) + iOS project, touch/safe-area/perf tuning on device, store assets, build pipeline.

## Verification & testing

- **Logic tests (headless):** damage/crit math, upgrade stacking, evolution triggers, no-damage-flag correctness, save/load round-trip + migration, spawner curves, seeded-RNG determinism.
- **Playtest on PC** each milestone (LÖVE runs from CLI): feel, frame time, entity-count stress, upgrade + Black Hole balance.
- **Profiling:** frame-time + draw-call counts under stress; verify 60 FPS at target entity counts across quality tiers.
- **Device pass (M5):** touch responsiveness (incl. drift-and-die mitigation), safe-area/notch, performance on a mid/low-range Android device.

## Risks & open decisions

- **LÖVE mobile packaging** is manual (research-confirmed not one-click; a known pain for late desktop ports). Mitigated by scripting the love-android build + mobile-first design; **Defold is the fallback**. [github.com/love2d/love-android]
- **iOS build/signing** needs a Mac + Xcode + Apple Developer account — not fully automatable; Android is. iOS submission needs the owner's involvement.
- **Store publishing** (Google Play / App Store accounts, fees, review) requires the owner's accounts — prepare builds + assets; the owner handles accounts + submission.
- **Monetization — OPEN (deferrable to M3):** leaning premium/paid on PC + free-with-optional-cosmetics on mobile, no dark patterns; the multi-track meta supports retention without aggressive IAP. Revisit before M3.
- **Black Hole unlock condition** (full no-hit clear vs. a lesser no-hit feat) is tunable in playtest.
- **Audio assets** need CC0 sourcing or generation — minor. **Balance** is iterative — mitigated by data-driven tables + playtests.

## Key research sources

Market/retention: naavik.co (survivorio-archeros-footsteps), mobilegamer.biz, gf.symphonyonline. Design + game feel: Halls of Torment dev talk (youtube WAcCxw64-3I), fullcleared.com. Controls/UI: equalentry.com, inairspace.com, gamepressure.com. Engines: defold.com/opensource, github.com/love2d/love-android.
