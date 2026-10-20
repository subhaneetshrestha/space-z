# Spec: Smooth Boss Entrance (fix boss stutter + teleport)

## Problem & Root Cause

Two separate defects show up when a boss appears.

### Defect A: the boss "appears in another place" (teleport)

`src/systems/boss.lua`
- `M.spawn` places the boss at `x = VW*0.5, y = -80`.
- `M.update` advances `e.t` the whole time the boss is `entering`. That is roughly 3 s of descent at 95 px/s.
- While `entering`, only `e.y` changes. `e.x` stays at screen centre.
- On the first frame after `entering` ends, `b.update` runs. Most behaviors compute `e.x` as an absolute function of `e.t`, for example `VW*0.5 + sin(e.t*0.7) * (VW*0.5 - 90)` (kessler). Because `e.t` is already about 3 s, `e.x` snaps from centre to wherever the sine currently is, up to about 150-300 px in one frame.
- Behaviors affected:
  - kessler, warmachine, titan, guardian, overlord: x snaps.
  - leviathan: x snaps, and y snaps because hover sets `170 + sin(e.t*2.1)*8`.
  - storm: y snaps by up to 22 px (`180 + sin(e.t*1.6)*22`).

**Measured (desktop run of the real game state, all 7 bosses, autopilot, fixed 1/60 steps):** the boss's position change on the first behavior step after arrival:

| Zone / boss | Snap on first step after arrival |
|---|---|
| 1 kessler | 131 px |
| 2 leviathan | 111 px |
| 3 warmachine | 90 px |
| 4 titan | 150 px |
| 5 storm | 21 px (y only) |
| 6 guardian | 160 px |
| 7 overlord | 138 px |

For scale, normal descent is 1.6 px per step. These are confirmed, not estimated.

**New finding, also confirmed: leviathan teleports mid-fight.** After every dive it returns to `hover`, which sets `e.x` from an absolute formula. The boss was at the player's column (`diveX`), so it snaps by **228 px and 244 px** at two consecutive hover returns in the 20 s fight sample, and hover y snaps by up to 8 px. This is the same bug class as the arrival snap, and it recurs every attack cycle, so it counts as "skips and appears in another place" during the fight.

### Defect B1: one-time hitch at boss arrival (first boss only)

`src/states/game.lua` `boss_spawned` handler calls `Music.play("boss", ...)`.
- `src/audio/music.lua` synthesizes the whole boss theme synchronously on the main thread the first time it is requested. The theme is 8 bars at 150 BPM, about 12.8 s of audio, written sample by sample in pure Lua.
- That is hundreds of thousands of samples in one frame, so one very long frame lands when the boss appears. `main.lua` then drops the backlog, so the player sees a freeze and a skip.
- **Measured:** `Music.play("boss")` took **7-8 ms on this desktop** (one 16.6 ms frame budget is about half gone). Phone CPUs are much slower than a desktop for this kind of tight Lua loop. I cannot measure your phone, so a figure for Android would be a guess. At 120 Hz the frame budget is 8.3 ms, so even the desktop number already costs about a frame, and the phone number is probably several frames.
- **Other bosses:** the cache key is `"boss"` and ignores the zone. Only the first boss of a session pays this cost, and later bosses reuse the cached source. This matches your report that you only tested the first boss. Verify on a second boss in the same session, and again after an app restart, since the cache is lost then.
- The same pattern also applies to `zone_N` themes. Each zone's music is synthesized the first time that zone is entered, which is a hitch at zone transitions. It is out of scope unless the measurement shows it is just as bad, but the fix should be reusable.

### Defect B2: stutter *during* the fight (all bosses, Android) — causes not yet confirmed

You report the stutter while fighting the boss, so B1 alone does not explain it. B1 is a one-off. Nothing in the code is boss-specific *per frame*, but a boss fight is the heaviest sustained load in the game, because the boss is huge and always on screen. Every player bullet and every drone or aura tick hits it. Candidates, ranked by how well the code supports them:

1. **GC churn from per-hit allocation (most likely on Android/LuaJIT).**
   - Each `enemy_hit` runs `Particles.burst(world, x, y, { …, color = { … } })` (`src/states/game.lua:145`). That allocates two tables per hit, and `Particles.burst` allocates `{1,1,1}` defaults too.
   - With a strong build against a boss, that is dozens of hits per second. The result is steady garbage and periodic GC pauses that look like skipped frames.
2. **Particle fill-rate / overdraw.** Hit sparks are gated at `#world.particles < 300`, but the cap is 600 (220 on low quality). During a boss fight the particle count sits near the gate. All of it is additive-blended, and the boss gets a second additive hit-flash pass (`game.lua:439`). Overdraw is a common mobile bottleneck.
3. **Audio source churn.** `Audio.play` does `stop()`/`setPitch()`/`play()` on a pooled source. `weapon_fired` and similar SFX fire constantly and `boss_dash`/`boss_wall`/`boss_pulse` add more. The 35 ms per-sound rate limit helps but does not remove this.
4. **Boss entities and bullets.** Bullet counts are modest (for example warmachine spiral about 11-22 per second, `ebullet.life = 9 s`), and the collision grid is fine. This is unlikely to be the main cost. Measure anyway.
5. **Large position jumps read as skipping.** See Defect C. The storm's dash (900 px/s, about 15 px per step) and leviathan's dive (420-540 px/s) are big per-frame moves. On a 90/120 Hz display these look like skips, not stutter.

**Measured on desktop (GC on and GC stopped, full 5-weapon loadout and blaster-only, 20 s fight per boss, vsync off so frame time equals CPU cost):**

| Metric | Waves | Boss fight |
|---|---|---|
| Frame time avg / p99 | about 2.1 / 3.1 ms | about 2.1 / 3.1 ms |
| Sim update avg | 0.03-0.10 ms | 0.03-0.05 ms |
| Draw avg | 0.13-0.20 ms | 0.14-0.22 ms |
| True allocation rate (GC stopped) | 28-129 KB/s | 16-52 KB/s |
| Particles max | up to 105 | up to 68 |
| Boss hits | n/a | about 10-13/s (autopilot) |

**What this means:**
- The boss fight is **cheaper** than normal waves on the desktop. Hypotheses 1 (GC churn) and 2 (particle overdraw) are **not supported** at these hit rates. Allocation is tiny and particles stay far below the cap.
- I could **not reproduce an in-fight frame-time problem on the desktop**. The 8-11 ms spikes that appear are one-off, show up in wave segments as well, and are not boss-specific.
- Limits of this test: it is a desktop CPU, vsync off at about 2 ms per frame, with an autopilot that lands about 10 hits/s, which is likely lower than a human. It cannot show GPU fill-rate, the Android audio stack, or 120 Hz pacing on your phone. Those stay unmeasured.
- So the in-fight stutter you feel on a 120 Hz Android phone has **no confirmed cause yet**. Two things I can already prove would look like in-fight skips: the leviathan snap-backs above, and the fast storm dash (15 px per step) and leviathan dive (7 px per step). The device probe is still needed for anything beyond those.

> Defect A, the leviathan snap-back and B1 are confirmed. B2 beyond those is unresolved until it is measured on the phone.

### Defect C: fast boss moves with no telegraph of travel (design/feel, minor)

`storm` dash and `leviathan` dive move the boss several pixels per step with no trail or afterimage. That reads as "appears somewhere else". Out of scope for the fix unless measurement of B2 shows nothing else. It is listed so the decision is explicit.

### Correction: no duplicate flash decrement

An earlier draft of this spec claimed `e.flashT` was decremented twice for the boss. That was wrong. `movement.lua:41` sits inside `updateEnemy`, which is skipped for bosses (`movement.lua:225`), so the boss flash timer is decremented once, in `boss.lua`. Nothing to fix.

## Objective

When a boss warps in, it descends smoothly from above the screen into its arena position and then starts its pattern **from where it is**. There is no positional discontinuity and no frame-time spike around `boss_spawned`.

Users: players on mobile (Android, touch) and desktop, at 60/90/120 Hz.

## Success Criteria (testable)

1. **No teleport, including leviathan's return from a dive.** For every behavior in `src/content/bosses.lua`, simulating at 60 Hz from `Boss.spawn` through 5 s past `entering = false`, the per-step displacement of `e.x` and `e.y` never exceeds the behavior's intended max speed. Dash and dive states are exempt and are explicitly allow-listed. Concretely, the step on which `entering` flips has `|Δx| <= 2 px` and `|Δy| <= 4 px`.
2. **Entrance ends in a defined pose.** On the frame `entering` becomes false, `e.x`/`e.y` equal the behavior's steady-state position at behavior time 0 (continuous with the entrance).
3. **Pattern timing unchanged.** `b.init` still runs once, at arrival. Attack timers start at arrival, not at spawn. Existing boss tests pass.
4. **Eased arrival.** The descent decelerates into `arenaY`. Speed falls from 95 px/s to a floor of about 15 px/s at the end, with no overshoot. It still arrives in under about 4 s, and the final step lands exactly on `arenaY`.
5. **No spawn hitch (B1).** The longest frame within 1 s of `boss_spawned` is under 25 ms on the reference desktop machine, for the first boss and for later ones.
6. **Smooth fight (B2).** Targets are set after the baseline measurement, which is the plan's first task. Provisional targets, to be agreed:
   - 99th percentile frame time during a boss fight is no worse than 1.25x the same build's 99th percentile in a normal wave.
   - No single frame over 33 ms in a 60 s boss window.
   - Lua heap growth rate during the fight is near zero. There is no steady allocation per hit.
   - Frame-time is measured with a debug probe on a real Android device, not by eye.
7. **Music still plays** at boss start: same theme, same loop, no audible gap longer than about 150 ms. If pre-warming is used, music is ready before the boss spawns.
8. **No change in difficulty or balance numbers** (hp, damage, patterns, timings). Only the entrance speed profile changes, and it must not make the entrance longer than about 4 s.

## Proposed Fix (for review in the Plan phase)

**A: continuous entrance.** Make behaviors position-relative to a per-behavior time that starts at arrival, not at spawn.
- On arrival, set `e.bt = 0` (behavior time) and advance it only in `b.update`.
- Replace `e.t` with `e.bt` in each behavior's sin-based position formulas. Keep `e.t` for non-positional use (the telegraph shudder can keep either).
- Each position formula must be 0-offset at `bt = 0` (`sin(0) = 0`), so x and y are continuous with the entrance, which ends at centre x and `arenaY`. For leviathan and storm, hover y must equal `arenaY` at `bt = 0`.
- Rejected alternative: lerping to the sine position over N frames. It adds a state and hides the cause instead of fixing it.

**A2: eased entrance.** Replace the constant `e.y + 95*dt` with a speed that scales with the remaining distance, clamped to a floor so it always terminates, for example `speed = clamp(1.8 * (arenaY - e.y), 15, 95)`. The final step snaps to `arenaY`. Constants are to be tuned by feel, and the criteria above are the hard limits.

**B1: remove the arrival hitch.** Options in order of preference:
1. Pre-generate the boss theme at an idle point, such as when the zone timeline is nearly exhausted, before `BOSS_CLEAR_COUNT` is met. `Music.prewarm("boss")` fills the cache without playing.
2. Spread synthesis over several frames, with a coroutine pumped from `love.update`. Start playback once it finishes.
3. Move synthesis to a `love.thread` that returns raw samples. Only if 1 and 2 are not enough, because Android thread support adds risk. This needs approval.

**B2: in-fight stutter. Measure first, then fix what the data shows.**
- Step 0 (done in this session, desktop only): the harness described above. It lived in a scratch copy and is not in the repo. A cleaned-up version can be added under `tests/` or `tools/` if you want it kept.
- Step 1: add a debug-flagged probe that logs per-frame `dt`, `collectgarbage("count")`, live particle count, and entity counts. Capture a normal wave, then a boss fight, on the same Android build.
- Step 2: apply fixes only for causes the data supports. Likely fixes, in order:
  - Stop allocating per hit. Use shared preallocated `spec` and `color` tables for the `enemy_hit` sparks. Give `Particles.burst` a no-allocation default colour. Keep behaviour and look identical.
  - Throttle hit sparks while one target is being hit continuously, for example at most N bursts per boss per 50 ms, and lower the particle gate during a boss fight.
  - Drop the extra additive flash pass, or draw it only at a reduced size, if overdraw is the cost.
  - Rate-limit the boss-fight SFX further if audio churn shows up.

## Commands

```
Test (all):        lua tests/run.lua
Test (in engine):  love . --test
Smoke (headless):  love . --smoke god      # captures boss screenshots per zone
Run:               love .
Build .love:       pwsh build/make-love.ps1
```

## Project Structure

```
src/systems/boss.lua     -> boss spawn + behaviors (Defect A lives here)
src/content/bosses.lua   -> boss defs (data only)
src/audio/music.lua      -> procedural music + cache (Defect B)
src/states/game.lua      -> boss_spawned handler
src/systems/spawner.lua  -> boss trigger (BOSS_CLEAR_COUNT)
tests/                   -> lua tests, one file per system (test_spawner.lua, test_zones.lua...)
docs/                    -> ARCHITECTURE.md, PROGRESS.md
```

New tests go in `tests/test_boss.lua`. There is none today. Check how `tests/run.lua` discovers files.

## Code Style

Match the existing Lua: 2-space indent, `local` helpers at the top, short comments that explain why, `e.` scratch fields on the entity.

```lua
if e.entering then
  e.y = e.y + 95 * dt
  if e.y >= b.arenaY then
    e.y = b.arenaY
    e.entering = false
    e.bt = 0 -- behavior clock starts at arrival so sin() offsets begin at 0
    b.init(e)
  end
  return
end
e.bt = e.bt + dt
```

## Testing Strategy

- **Prove-It first.**
  - Write the failing test before the fix. It simulates each behavior at `dt = 1/60` and asserts criteria 1 and 2.
  - Run it against current code to confirm it fails for the expected behaviors.
- **Table-driven.** The test iterates every key in `Bosses`, so new bosses are covered automatically.
- **Regression.** Existing `test_spawner`, `test_zones`, `test_damage` and `test_effects` must still pass.
- **Perf, Defect B1.**
  - Add a temporary timing probe (`love.timer.getTime` around `Music.play`) to confirm the hypothesis before choosing option 1, 2 or 3.
  - Unit test for `Music.prewarm`: after the call, `Music.play("boss")` does not synthesize. Use an injectable `generate` counter, or check cache population.
- **Perf, Defect B2.**
  - Probe described under B2. It is gated behind a debug flag, and the default build logs nothing.
  - Allocation check as a unit test: run N `enemy_hit` events through the game's event wiring and assert that no new tables are created per hit. Use a stub or counter for the `Particles.burst` spec, or compare `collectgarbage("count")` over many hits.
  - Add `--smoke god` frame-time logging (the sim runs at 8x there, so it measures cost per step, not on-device feel).
- **Every boss.** The spawn/entrance test is table-driven over all 7 bosses. The perf checks are run on at least the first boss and one later boss, since the first-boss hitch is a cache effect.
- **Manual on Android.** Play the first boss, then a later boss in the same session, and compare against the baseline numbers.

## Boundaries

- **Always:**
  - Write the failing test first.
  - Keep boss stats and pattern timing identical.
  - Run `lua tests/run.lua` before each commit.
  - Keep the fix per-behavior minimal.
- **Ask first:**
  - Adding `love.thread` or any new dependency.
  - Changing the music theme, its length, or the audio sample rate.
  - Changing `main.lua` timestep or backlog-drop logic.
  - Changing `entering` speed (95 px/s) or arena positions.
- **Never:**
  - Mask the teleport by hiding the boss or adding a fade.
  - Delete or weaken existing tests.
  - Rebalance bosses as part of this fix.
  - Commit to `main` directly. Use a branch and PR, as in earlier work.

## Answers Received

- Stutter happens **during the fight**, not just on arrival. This added B2.
- Tested on **Android** only. Desktop is not yet checked.
- The descent should **slow down** as it arrives. This is criterion 4.
- It happened with **any weapon**, on a **120 Hz** Android phone. You are not sure exactly when in the fight.
- You asked whether I can run the game and check. I did, on desktop (see Defect B2). I cannot run it on your phone.
- Only the **first boss** was tested. The code suggests the arrival hitch is first-boss-only, and the plan includes checking later bosses.

- You watched the desktop test run and saw the same skipping on **other bosses too**. That matches the measured snaps on 6 of 7 bosses at arrival, plus the leviathan's snap-back after each dive.

## Scope Decision

**Stage 1 (this spec, in scope):** fix everything confirmed.
1. Arrival snap on all bosses (Defect A, behavior clock starts on arrival).
2. Leviathan snap-back after each dive (hover continues from where the boss is, not from an absolute formula).
3. Eased arrival (A2).
4. First-boss music hitch (B1, pre-generate the music before the boss appears).
5. Tests that fail on current code and pass after the fix, covering all 7 bosses.

**Stage 2 (conditional, not in this spec):** if the stutter remains on your phone after Stage 1, add the debug-only frame-time probe (B2 Step 1) and fix whatever it shows. It needs a separate approval because it means building and installing an APK.

**Out of scope:** Defect C (dash and dive speed or trails), music for zones other than the boss, any balance or boss-pattern changes.

## Open Questions

1. Is Stage 1 the right scope, with Stage 2 only if the stutter persists on your phone?
2. Is the fix to leviathan's hover return acceptable as "ease back toward the hover sine over about 0.5 s", or do you want it to simply continue from its current x and drift to centre?
