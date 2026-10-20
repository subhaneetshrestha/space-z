# Task List: Run Save & Continue

Plan: `docs/run-save-resume/plan.md`. Spec: `docs/run-save-resume/spec.md`. Tests: `lua tests/run.lua`. Work on a branch, one commit per task, test first. Every new test file must be added to the `FILES` list in `tests/run.lua`.

## Phase 1: Save data (pure, headless)

- [x] **Task 1: RNG state can be saved and restored**
  - Description: Add `RNG:getState()` and `RNG:setState(s)` so a stream can be captured and resumed exactly.
  - Acceptance:
    - [ ] After `setState(getState())` on a fresh RNG, the next 100 draws equal those of the original.
    - [ ] `setState` rejects non-numbers and out-of-range values (falls back to leaving the state unchanged and returns false).
  - Verify:
    - [ ] Test first (fails: methods missing), then passes: `lua tests/run.lua`
  - Dependencies: none
  - Files: `src/core/rng.lua`, `tests/test_rng.lua`
  - Scope: XS

- [x] **Task 2: Snapshot, validate, and store a run**
  - Description: New pure module `src/meta/runsave.lua` with `snapshot(world)` and `validate(run)`, plus `Save.run()` (validated or nil), `Save.setRun(run)`, `Save.clearRun()`. `run` defaults to nil, `Save.reset()` clears it.
  - Acceptance:
    - [ ] `snapshot` captures every field listed in the spec ("What a snapshot contains"), HP unrounded, and applies the phase table: `boss` -> `waves` at `zoneTime = zone.duration`; `warp` -> next zone start (nil when it was the last zone); dead / `over` / `daily` -> nil.
    - [ ] `validate` rejects each malformed case (wrong type, missing field, unknown weapon/passive/ship id, bad mode, version mismatch, negative or NaN numbers), one test per case.
    - [ ] `Save.run()` returns nil for an invalid stored run and never errors; an old save without `run` loads unchanged.
    - [ ] JSON encode -> decode of a snapshot still validates.
  - Verify:
    - [ ] Tests first, then pass: `lua tests/run.lua`
  - Dependencies: Task 1 (RNG state shape)
  - Files: `src/meta/runsave.lua` (new), `src/meta/save.lua`, `tests/test_runsave.lua` (new), `tests/test_save.lua`, `tests/run.lua`
  - Scope: M (5 files)

- [x] **Task 3: Apply a run to a fresh world**
  - Description: `runsave.apply(world, run)` copies progression fields onto a freshly built world, rebuilds weapons/passives from ids, restores RNG states and spawner timers, calls `Leveling.recomputeStats`, then sets `player.hp` (clamped to `[1, maxhp]`).
  - Acceptance:
    - [ ] Snapshot -> JSON -> validate -> apply into a fresh world: all snapshot fields are equal (spec criterion 2), including evolved weapons and fractional HP.
    - [ ] The next 50 spawner draws and the next card offer match a world that never paused (criterion 3).
    - [ ] Cooldowns and transient timers are zeroed; player is at the spawn point.
  - Verify:
    - [ ] Tests first, then pass: `lua tests/run.lua`
  - Dependencies: Tasks 1, 2
  - Files: `src/meta/runsave.lua`, `tests/test_runsave.lua`
  - Scope: S

### Checkpoint: Data layer
- [x] `lua tests/run.lua` passes (run as `luajit tests/run.lua`; also `lovec . --test`)
- [x] Criteria 1, 2, 3, 10 proven by tests
- [ ] Review with human

## Phase 2: Countdown

- [x] **Task 4: 3-2-1 countdown state, used by pause RESUME** (look of the overlay not yet seen on screen: needs a manual `love .` check)
  - Description: New translucent `countdown` state (drawn over the game, big centered 3, 2, 1, one second each, then pops). Register it in `main.lua`. Pause's RESUME and Esc now `pop()` then `push("countdown")`.
  - Acceptance:
    - [ ] The state ends after 3.0 s +/- one step, shows 3, then 2, then 1, and pops exactly once.
    - [ ] While it is on top the game state's `update` is never called and input does not steer.
    - [ ] Pausing then pressing RESUME or Esc shows the countdown, then play continues with a reset steering input.
    - [ ] Visual style matches pause/levelup overlays (font, colors via `Util`).
  - Verify:
    - [ ] Test first (drives `countdown:update` with fixed steps; stubs `StateM`): `lua tests/run.lua`
    - [ ] Manual: pause and resume in `love .`
  - Dependencies: none
  - Files: `src/states/countdown.lua` (new), `src/states/pause.lua`, `main.lua`, `tests/test_countdown.lua` (new), `tests/run.lua`
  - Scope: M (5 files)

## Phase 3: Game integration

- [x] **Task 5: Game resume path, autosave, and clearing** (`Achievements.live` checked: its listeners keep no per-run state, nothing extra to save)
  - Description: `game:enter` accepts `params.resume` (a validated run): builds the world as normal, applies the run, then pushes `countdown`. Add `Game.saveRun()` (the single save entry point) and a 10 s autosave timer in `update`. Clear the save on `player_died` and on a win. Autopilot and daily runs never save. Before changing scope, check `Achievements.live` for per-run counters that need saving.
  - Acceptance:
    - [ ] `Game.saveRun()` writes via `Save.setRun` using the spec's exclusions (dead, `over`, daily, autopilot) and counts an open level-up draft into `pendingLevelUps`.
    - [ ] Autosave fires about every 10 s of unpaused play; `--smoke` writes no `run`.
    - [ ] `player_died` clears the run; a won run clears it; `Progress.endRun` is still called exactly once and resume does not change `totalRuns`.
    - [ ] Resume of a `boss`-phase save brings the boss back at full HP after the countdown.
  - Verify:
    - [ ] Headless tests for the pure parts; `lua tests/run.lua` and `love . --test`
    - [ ] `love . --smoke` completes and `smoke_report.txt` shows no error
    - [ ] Manual: spec manual check 1
  - Dependencies: Tasks 3, 4
  - Files: `src/states/game.lua`, `tests/test_runsave.lua` (Game-free assertions only)
  - Scope: M (2 files)

- [x] **Task 6: Pause SAVE & QUIT** (pause is opened with `{ save, daily }` params from the game state so it never requires the game module)
  - Description: On pause `enter`, call `Game.saveRun()`. Row 2 reads `SAVE & QUIT` for standard/Black Hole and saves then switches to the menu. For daily runs it stays `QUIT TO MENU` and discards.
  - Acceptance:
    - [ ] Standard/Black Hole: quitting keeps the run; menu shows CONTINUE (after Task 7).
    - [ ] Daily: label unchanged, no run written, run discarded as today.
  - Verify:
    - [ ] `lua tests/run.lua`; manual in `love .`
  - Dependencies: Task 5
  - Files: `src/states/pause.lua`
  - Scope: XS

- [ ] **Task 7: Menu CONTINUE row and overwrite guard**
  - Description: When `Save.run()` is valid, `CONTINUE` is the first row and default selection; activating it does `StateM.switch("game", { resume = run, mode = run.mode, seed = run.seed })`. With a save present, LAUNCH and DAILY RUN need a second press ("ABANDON SAVED RUN? TAP AGAIN"); moving the selection or leaving cancels it. A confirmed new run calls `Save.clearRun()`.
  - Acceptance:
    - [ ] No saved run: menu is identical to today.
    - [ ] Saved run: CONTINUE first and selected; resumes with the 3-2-1 countdown.
    - [ ] First press on LAUNCH/DAILY RUN only arms the confirmation; second press discards the save and starts.
    - [ ] Corrupt `run` in `save.json`: no CONTINUE row, no error.
  - Verify:
    - [ ] `lua tests/run.lua`; manual in `love .`, including a hand-edited bad `save.json`
  - Dependencies: Tasks 5, 6
  - Files: `src/states/menu.lua`
  - Scope: S

- [ ] **Task 8: Save on app background and quit**
  - Description: Add `love.focus(f)` (on `false`) and extend `love.quit` to call `Game.saveRun()`. The existing smoke finalization in `love.quit` is untouched.
  - Acceptance:
    - [ ] Losing focus or closing the window mid-run writes the run; with no active run it does nothing.
    - [ ] Backgrounding during a level-up draft resumes with the draft offered again.
    - [ ] `--smoke` and `--test` behaviour unchanged.
  - Verify:
    - [ ] `love . --test`, `love . --smoke`; manual spec checks 2 and 3 (check 3 on Android in Task 9)
  - Dependencies: Task 5
  - Files: `main.lua`
  - Scope: XS

### Checkpoint: Playable
- [ ] `lua tests/run.lua`, `love . --test`, `love . --smoke` all pass
- [ ] Manual desktop checks 1, 4, 5 from the spec pass
- [ ] Review with human

## Phase 4: Ship

- [ ] **Task 9: Verify end to end and open the PR**
  - Description: Run every acceptance criterion from the spec, measure autosave cost, update `docs/ARCHITECTURE.md` and `docs/PROGRESS.md` (check how they are organised first), and open a PR. Do not merge.
  - Acceptance:
    - [ ] Spec criteria 1-12 each checked with a stated result.
    - [ ] Autosave write time measured on desktop and reported.
    - [ ] PR description states plainly what is verified on desktop and what is NOT verified on Android (manual checks 2 and 3).
  - Verify:
    - [ ] `lua tests/run.lua`; `love . --smoke`; CI `test` job green on the PR
  - Dependencies: Tasks 1-8
  - Files: PR; `docs/ARCHITECTURE.md`, `docs/PROGRESS.md`
  - Scope: XS-S

### Checkpoint: Complete
- [ ] All acceptance criteria met
- [ ] PR open for review; merge left to the human (merging to `main` publishes a release)
