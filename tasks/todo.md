# Task List: Smooth Boss Entrance (Stage 1)

Plan: `tasks/plan.md`. Spec: `SPEC.md`. Tests: `lua tests/run.lua`. Work on a branch, one commit per task.

## Phase 1: Boss motion

- [x] **Task 1: Bosses arrive without a position snap (all 7)**
  - Description: Add a behavior clock `e.bt` that starts at 0 on arrival and use it in every position formula, so each boss continues smoothly from where the entrance leaves it. Written test-first: the new table-driven test fails on current code (snaps of 90-160 px), then passes.
  - Acceptance:
    - [ ] For every boss in `src/content/bosses.lua`, the per-step displacement over the first 1.5 s after `entering` becomes false is at most 3 px (current: 21-160 px).
    - [ ] On the first behavior step `e.x` is within 1 px of `VW/2` and `e.y` within 1 px of `arenaY` (storm and leviathan included).
    - [ ] `b.init` still runs once at arrival, and attack timers behave as before.
  - Verify:
    - [ ] Write the test first and confirm it fails on current code for the expected bosses: `lua tests/run.lua`
    - [ ] After the fix `lua tests/run.lua` passes, existing tests included
  - Dependencies: none
  - Files: `tests/test_boss.lua` (new), `tests/run.lua` (register file), `src/systems/boss.lua`
  - Scope: S-M (3 files)

- [ ] **Task 2: Leviathan eases back to hover after each dive**
  - Description: When the leviathan returns from `rise` to `hover`, blend from its current position to the hover path over `HOVER_BLEND` (0.6 s, smoothstep) instead of snapping.
  - Acceptance:
    - [ ] With the player at a far-off column, every step of a 15 s simulation moves the leviathan at most 14 px outside `dive` and `rise` states (current: 228 and 244 px snaps).
    - [ ] After `HOVER_BLEND` the position is within 1 px of the plain hover path.
    - [ ] Dive speed, telegraph timing and meteor drops are unchanged.
  - Verify:
    - [ ] Test fails first, then passes: `lua tests/run.lua`
  - Dependencies: Task 1
  - Files: `src/systems/boss.lua`, `tests/test_boss.lua`
  - Scope: S (2 files)

- [ ] **Task 3: Boss entrance decelerates into position**
  - Description: Replace the constant 95 px/s descent with `clamp(K * (arenaY - y), FLOOR, 95)`, ending with a snap to `arenaY`. Tune `K` and `FLOOR` against the limits below.
  - Acceptance:
    - [ ] First-second speed is still 95 px/s, and speed never rises, never goes below `FLOOR` (except the final snap step), and never overshoots `arenaY`.
    - [ ] Every boss arrives in at most 4.0 s (current about 2.4-3.0 s).
    - [ ] The final speed before arrival is at most `FLOOR`, so the stop reads as slowing down.
  - Verify:
    - [ ] Test fails first, then passes: `lua tests/run.lua`
  - Dependencies: Task 1
  - Files: `src/systems/boss.lua`, `tests/test_boss.lua`
  - Scope: S (2 files)

### Checkpoint: Motion complete
- [ ] `lua tests/run.lua` passes
- [ ] `lovec . --test` passes (same suite through LÖVE)
- [ ] Desktop harness shows arrival snap at most 3 px for all 7 bosses
- [ ] Review with human: watch a boss arrive in `love .`, judge leviathan return feel

## Phase 2: Boss music

- [ ] **Task 4: Boss theme can be built in time slices**
  - Description: Turn the theme generator into a resumable job. Add `Music.prewarm(key, zoneIndex)`, `Music.pump(budgetSeconds)`, and make `Music.play` use the cached source or finish an unfinished job synchronously. Same seed, same notes, same output.
  - Acceptance:
    - [ ] A job advanced in small slices produces a sample buffer identical to the one-shot result for the same theme and seed.
    - [ ] `Music.pump(0.002)` never builds more than one slice per call and reports when the job is done.
    - [ ] `Music.play("boss")` after a finished prewarm does no synthesis. After a partial prewarm it finishes the job and plays. With no prewarm it behaves as today.
    - [ ] `Music.play("zone", n)` and `Music.play("menu")` behave as before.
  - Verify:
    - [ ] Tests (with a minimal `love.sound`/`love.audio` stub inside the test file): `lua tests/run.lua`
    - [ ] Check that `src.meta.save` loads under plain Lua. If not, stub it in the test only.
  - Dependencies: none (independent of Phase 1)
  - Files: `src/audio/music.lua`, `tests/test_music.lua` (new), `tests/run.lua`
  - Scope: M (3 files)

- [ ] **Task 5: Prewarm the boss theme during the zone**
  - Description: Start `Music.prewarm("boss", zoneIndex)` when the zone timeline is near its end (`zoneTime >= duration - 25`) and call `Music.pump(0.002)` each game update, so synthesis finishes during the waves and the boss spawn only calls `src.play()`.
  - Acceptance:
    - [ ] Prewarm starts once per run and never during the boss fight.
    - [ ] In the desktop harness, `Music.play("boss")` at spawn takes under 1 ms on a normal run, and no single frame in the prewarm window exceeds about 3 ms from music work.
    - [ ] If the boss arrives before the job finishes (forced in the harness), music still starts.
    - [ ] Pause, levelup and gameover do not leave a half-built job that breaks later playback.
  - Verify:
    - [ ] `lua tests/run.lua`
    - [ ] Harness timing run over all 7 zones
    - [ ] Manual: play a zone to its boss, music starts with the boss
  - Dependencies: Task 4
  - Files: `src/states/game.lua`, `src/audio/music.lua` (only if the API needs a small tweak)
  - Scope: S (1-2 files)

### Checkpoint: Audio complete
- [ ] `lua tests/run.lua` and `lovec . --test` pass
- [ ] Harness: `Music.play("boss")` at spawn under 1 ms; early-boss fallback tested
- [ ] Review with human

## Phase 3: Ship

- [ ] **Task 6: Verify end to end and open the PR**
  - Description: Re-run the desktop measurements from the spec against the fixed code, run the smoke test, and open a PR with before/after numbers. Do not merge.
  - Acceptance:
    - [ ] Spec criteria 1-5, 7 and 8 checked with measured values (criterion 6, the on-phone stutter target, is Stage 2 and stays open).
    - [ ] `lovec . --smoke god` completes with no error and captures `boss1` to `boss7`.
    - [ ] PR description states plainly what is verified on desktop and what is not verified on Android.
  - Verify:
    - [ ] `lua tests/run.lua`; `lovec . --smoke god`
    - [ ] CI on the PR is green (`test` job gates all builds)
  - Dependencies: Tasks 1-5
  - Files: PR only; `docs/PROGRESS.md` if the project logs fixes there (check first)
  - Scope: XS

### Checkpoint: Complete
- [ ] All acceptance criteria met
- [ ] PR open for review; merge left to the human (merging to `main` publishes a release)
