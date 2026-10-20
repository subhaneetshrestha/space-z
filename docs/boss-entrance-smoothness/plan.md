# Implementation Plan: Smooth Boss Entrance (Stage 1)

Source of truth: `docs/boss-entrance-smoothness/spec.md` (approved). This plan covers **Stage 1 only**: the confirmed bugs. Stage 2 (Android frame-time probe) happens only if stutter remains after Stage 1, and needs its own approval.

## Overview

Two independent problems, fixed as four small vertical slices plus a final verification:

1. **Motion (`src/systems/boss.lua`):** bosses snap 90-160 px on the first step after arrival, and the leviathan snaps 228-244 px after every dive. Fix with a behavior clock that starts at arrival, an eased return to hover, and a decelerating entrance.
2. **Audio (`src/audio/music.lua`):** the boss theme is synthesized in one frame when the boss spawns (7-8 ms on desktop, worse on a phone). Fix by building it in small time slices earlier in the zone.

## Dependency Graph

```
tests/test_boss.lua scaffold ──┬─ T1 behavior clock (arrival continuity)
   (created inside T1)         │        │
                               │        ├─ T2 leviathan hover-return easing
                               │        └─ T3 eased entrance
                               │
Music job stepper (T4) ───────────── T5 wire prewarm into the game loop
```

- T2 and T3 depend on T1 only for the shared test scaffold and the `e.bt` field. They are independent of each other.
- T4 and T5 (audio) share no files with T1-T3 except `tests/run.lua`, so the two phases could run in parallel. I recommend sequential order anyway: the motion phase is the user-visible fix and is the riskier one.

## Architecture Decisions

- **`e.bt` (behavior time) instead of `e.t` for positions.** `e.t` keeps running during the entrance (about 3 s), so absolute sine positions start at a random phase. `e.bt` starts at 0 on arrival, and `sin(0) = 0` puts every boss at centre x and `arenaY` on its first behavior step. `e.t` stays for non-positional use.
  - Rejected: lerping to the sine position after arrival. It adds a state and hides the cause.
- **Offset decay for leviathan hover-return (decision 2: easing).** On entering `hover`, record `xOff = e.x - hoverX(bt)` and `yOff = e.y - hoverY(bt)`, then each step set `e.x = hoverX(bt) + xOff * (1 - s)` with `s` a smoothstep over a named constant `HOVER_BLEND = 0.6 s`. This is exactly continuous at the transition and converges to the normal path. Peak speed for a 244 px offset is about 12 px/step, a deliberate trade-off (see Risks).
  - Only leviathan has an absolute-position state that follows a free-moving state, so the blend lives in that behavior, not in shared code.
- **Entrance speed `clamp(K * (arenaY - y), FLOOR, 95)`.** Starts at the current 95 px/s, decelerates exponentially, never goes below `FLOOR` so it always terminates, and the final step snaps to `arenaY`. Starting values `K = 2.2`, `FLOOR = 20` give about 3.7 s for kessler (the longest, `arenaY` 200). Constants are tuned against the spec limit: entrance at most 4 s.
- **Music: time-sliced prewarm, no threads.** `generate()` becomes a resumable job: `Music.prewarm(key, zoneIndex)` starts it, `Music.pump(budgetSeconds)` advances it a little each frame, and `Music.play` uses the cached source, or **finishes the job synchronously** if the boss arrives early. That keeps the worst case equal to today's behavior. This combines spec options 1 (pre-generate at an idle point) and 2 (spread over frames), and avoids option 3 (`love.thread`), which needs approval. A single-frame prewarm would only move the hitch from the boss arrival to mid-wave.
  - Cache key stays `"boss"` (one theme shared by all bosses), and the seed stays `2000 + zoneIndex` of the first request, so the audible result is unchanged.
- **Testability.** Tests run under plain Lua with no `love`. Music tests use a minimal `love` stub (`sound.newSoundData`, `audio.newSource`) installed and removed inside the test file. Boss tests use a fake world in the style of `tests/test_spawner.lua`.

## Task List

### Phase 1: Boss motion

- [ ] Task 1: Bosses arrive without a position snap (all 7)
- [ ] Task 2: Leviathan eases back to hover after each dive
- [ ] Task 3: Boss entrance decelerates into position

### Checkpoint: Motion complete
- [ ] `lua tests/run.lua` passes, new boss tests included
- [ ] Re-run the desktop harness (see T6): arrival snap at most 3 px for all 7 bosses, leviathan return at most about 14 px per step
- [ ] Human watches a boss arrive in `love .` and judges the feel

### Phase 2: Boss music

- [ ] Task 4: Boss theme can be built in time slices
- [ ] Task 5: Prewarm the boss theme during the zone

### Checkpoint: Audio complete
- [ ] `lua tests/run.lua` passes
- [ ] `Music.play("boss")` at spawn takes under 1 ms in the harness for a normal run
- [ ] Early-boss fallback (boss arrives before prewarm finishes) still plays music

### Phase 3: Ship

- [ ] Task 6: Verify end to end and open the PR

### Checkpoint: Complete
- [ ] All spec success criteria checked off with measured values
- [ ] PR open, not merged (merging to `main` auto-publishes a release)

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Leviathan blend moves up to about 12 px/step, which may itself look like a skip | Med | Constant `HOVER_BLEND` is one number. T2's test uses a named per-step bound, so tuning is cheap. If it still looks fast, raise it to about 0.9 s. Needs your eye, because I can't judge feel from numbers. |
| Slower entrance changes fight pacing (boss is invulnerable longer) | Low | Entrance capped at 4 s versus about 3 s today, asserted in T3. |
| `e.bt` swap misses a position formula | Med | The T1 test is table-driven over every boss in `src/content/bosses.lua`, so a missed formula shows up as a snap. |
| Time-sliced generation changes the audio output | Med | Same seed and same note-writing calls, only chunked. T4 compares the sliced result to the one-shot result sample for sample. |
| Prewarm hasn't finished when the boss spawns | Low | `Music.play` finishes the job synchronously, which equals today's cost. Not worse than now. |
| Desktop numbers don't prove it's fixed on your phone | Med | Said plainly in the PR. Stage 2 (APK probe) is the follow-up if stutter remains. |
| Merge to `main` auto-versions and publishes a GitHub Release | Med | Work on a branch, open a PR, and leave the merge to you. |

## Parallelization

Phases 1 and 2 touch different source files and could be built in parallel. Within a phase the tasks share `tests/test_boss.lua` (T1-T3) or `src/audio/music.lua` (T4-T5), so they run in order.

## Decisions (approved)

- Time-sliced prewarm with a synchronous fallback is the accepted reading of spec options 1+2.
- Branch name: `fix/boss-entrance-smoothness`.
- Plan approved by the human. Next step is `/agent-skills:build`.
