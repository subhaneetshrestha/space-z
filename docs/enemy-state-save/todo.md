# Task List: Frozen-Moment Run Save + LÖVE 12

Plan: `docs/enemy-state-save/plan.md`. Spec: `SPEC.md`. Tests: `lua tests/run.lua` (also `lovec . --test`).
Work on a new branch from `feature/run-save-resume`, one commit per task, test first. Every new test file must be added to
the `FILES` list in `tests/run.lua`. Criterion numbers refer to `SPEC.md`.

## Phase 0: Learn what LÖVE 12 breaks

- [x] **B1: Get a LÖVE 12 desktop build and record what fails** (findings: `love12-findings.md`; the only failure is the compatibility dialog from `t.version = "11.5"`, plus one deprecation warning)
  - Description: Download the `love2d/love` Actions artifact (Windows x64) for the current `main` commit with `gh`, unpack it to `dist/love12/` (gitignored), and run `lovec . --test` and `lovec . --smoke` on it. Add `build/get-love.ps1` that does the download for a given commit, so CI and local use share it. Write the findings (errors, warnings, the compatibility dialog) to `docs/enemy-state-save/love12-findings.md`. No game code changes here.
  - Acceptance:
    - [ ] `build/get-love.ps1 -Commit <sha> -Out dist/love12` produces a runnable `lovec.exe` that reports version 12.0.
    - [ ] `love12-findings.md` lists every failure or warning from `--test` and `--smoke`, or states that there are none, with the exact output.
    - [ ] The pinned commit and artifact name are recorded in the findings file.
  - Verify:
    - [ ] `dist/love12/lovec.exe --version`
    - [ ] `dist/love12/lovec.exe . --test` and `--smoke` run to completion (pass or fail) and the output is captured
  - Dependencies: none
  - Files: `build/get-love.ps1` (new), `.gitignore`, `docs/enemy-state-save/love12-findings.md` (new)
  - Scope: S

## Phase 1: Version foundation

- [x] **B2: `LOVE_VERSION`, `conf.lua`, compat fixes** (verified on the LÖVE 12 build: `--test` 283/0, `--smoke` OK, no dialog, no warnings; a packaged `.love` declaring 11.5 hangs on the dialog, so the file is read from inside the archive. Android dialog is checked in B5.)
  - Description: Add `LOVE_VERSION` (`love=12.0`, `love_commit=`, `love_android_commit=`). `conf.lua` reads it through a small parser so `t.version` matches the runtime. Fix whatever B1 found, with any API difference behind a single `src/compat.lua`. Include `LOVE_VERSION` in `make-love.ps1`'s package list so the `.love` can read it.
  - Acceptance:
    - [ ] Criterion 10 (partial): `lovec . --test` and `--smoke` pass on the LÖVE 12 build.
    - [ ] "No compatibility warning": no dialog on desktop 12; the Android check comes in B5.
    - [ ] A headless test fails if `conf.lua`'s `t.version` differs from `LOVE_VERSION`.
    - [ ] Every fix from B1 is behind `src/compat.lua` or is a plain bug fix, with a test where one can run headless.
  - Verify:
    - [ ] Test first (fails: no file), then passes: `lua tests/run.lua`
    - [ ] `dist/love12/lovec.exe . --test` and `--smoke`
    - [ ] Manual: `love .` on 12: menu, run, boss, pause, continue, game over, hangar
  - Dependencies: B1
  - Files: `LOVE_VERSION` (new), `conf.lua`, `src/compat.lua` (only if needed), `build/make-love.ps1`, `tests/test_version.lua` (new), `tests/run.lua`
  - Scope: M

### Checkpoint: Version foundation
- [ ] `lua tests/run.lua` passes; `--test` and `--smoke` pass on the LÖVE 12 build
- [ ] Review with human

## Phase 2: Exact snapshot

- [x] **A1: Version 2 envelope, player, world state, diff helper** (headless 322/0 and `--test` 322/0 on LÖVE 12. Deviation: `phase` and `warpT` move to A5, since until the boss rewind is removed they would always be `"waves"` / `0`. `Support.worldDiff` also covers the entity lists already, so A2 only adds capture. Tests that asserted the old reset behaviour were replaced by version-1 (legacy) and version-2 versions.)
  - Description: Bump `RUN_VERSION` to 2 and add `player` (position, velocity, `invulnT`, `shieldT`, `pulseT`, `hpRingT`), `world` extras (`freezeT`, `phase`, `warpT`), and each weapon's `cooldown`, `side`, `tickT`. `validate` accepts version 1 (no entities) and version 2. Add `Support.worldDiff(a, b)` to `tests/support.lua`: compares two worlds' simulation state (player, lists, scalars) with the 14-digit tolerance, returning the first difference. Keep the `boss`/`warp` rewind for now (removed in A5).
  - Acceptance:
    - [ ] Criterion 1 for the new player/world fields: snapshot, JSON, validate, apply gives equal values (fractional HP included).
    - [ ] Criterion 7: a version-1 run still validates and applies as before.
    - [ ] `worldDiff` reports a difference when any player or world field differs, and nil for a restored copy.
    - [ ] Weapon `cooldown` is restored, not zeroed.
  - Verify:
    - [ ] Tests first (fail), then pass: `lua tests/run.lua`
  - Dependencies: B2 (so tests also run on 12; A tasks need not wait for it if time is short)
  - Files: `src/meta/runsave.lua`, `tests/test_runsave.lua`, `tests/support.lua`
  - Scope: S

- [x] **A2: Enemies and the reference table** (404/0 headless and on LÖVE 12; negative controls: dropping a saved field and restoring in reverse order both fail the suite. Additions beyond the plan: `lib/json.lua` now writes numbers that 14 digits would change with 17, because a shooter's fire timer sits exactly on zero and 14-digit rounding moved it one frame; per-movement scratch consistency is validated, since a half-initialised shooter would index nil on the first frame. The "reference table" itself lands with A3/A4, which are the first entities that point at others.)
  - Description: Capture and restore live enemies in list order, for all movement types (`drift, sine, chaser, shooter, lunge, ballistic`), including elites and chilled (`slowT`) ones. Introduce the index table used by later tasks. Add the completeness test (plan decision 2): long deterministic sims over every enemy type; any live key that is neither whitelisted nor on the `DERIVED` list fails the test. New module `src/meta/runsave_entities.lua` holds the field lists and (de)serializers.
  - Acceptance:
    - [ ] Criterion 1 for enemies; criterion 2 (behavioural identity) holds for 600 frames per movement type with the same seed.
    - [ ] List order is preserved, proven with a list that has swap-remove gaps.
    - [ ] Completeness test passes and fails when a field is removed from the whitelist.
    - [ ] Validation rejects: unknown enemy id, non-finite number, non-boolean `elite`, wrong type for each scratch field.
  - Verify:
    - [ ] Tests first (the behavioural-identity test fails against today's code), then pass: `lua tests/run.lua`
  - Dependencies: A1
  - Files: `src/meta/runsave.lua`, `src/meta/runsave_entities.lua` (new), `tests/test_runsave_entities.lua` (new), `tests/support.lua`, `tests/run.lua`
  - Scope: M (5 files)

- [x] **A3: Enemy and player bullets** (473/0 headless and on LÖVE 12, smoke OK. Negative controls: dropping `slowT`/`aoe`, losing a missile's lock, reversing bullet order and skipping enemy bullets each fail the suite. `captureEnemies` now also returns the enemy-to-slot map, which is the "reference table" the plan described. The identity fixtures wait for the specific bullet under test, because immortal enemies soak bullets the instant they are fired.)
  - Description: Capture and restore `ebullets` and `bullets`, including pierce counts, `aoe`, chill, and the homing `target` (saved as an enemy index; nil when the target is gone). Sprites are derived.
  - Acceptance:
    - [ ] Criterion 1 and 2 for bullets, over a fight with every weapon behaviour (forward, spread, homing, pierce, nuclear aoe, cryo).
    - [ ] A homing missile resumes chasing the same enemy (reference re-linked, not copied).
    - [ ] Validation rejects: target index out of range, negative `life`, non-finite velocity.
  - Verify:
    - [ ] Tests first, then pass: `lua tests/run.lua`
  - Dependencies: A2
  - Files: `src/meta/runsave_entities.lua`, `src/meta/runsave.lua`, `tests/test_runsave_entities.lua`
  - Scope: S

- [x] **A4: Pickups and drones** (530/0 headless and on LÖVE 12, smoke OK. Negative controls: losing drone cooldowns, the orbit angle, a gem's magnet state, or gem order each fail the suite. Drone `hitCd` is saved as `{ enemy slot, expiry }` pairs, only for cooldowns still running. `Support.worldView` now compares a missile's target and a drone's cooldowns by slot, which also hardens the A3 tests. Two one-line exports in production code: `Pickups.tierSprite`, `Weapons.DRONE_HIT_CD`. Left as is: the original lets a stale cooldown key follow a recycled pool table onto a new enemy; saves drop such entries, which only removes a ≤0.5 s accidental delay.)
  - Description: Capture and restore XP gems (`value`, `magnet`, velocity, `t`) and orbit drones (`angle`, `t`, `hitCdN`, `hitCd` as `{ enemyIndex, expiry }` pairs).
  - Acceptance:
    - [ ] Criterion 1 and 2 for pickups and drones: the orbit continues without a jump, and a drone does not re-hit an enemy that was on cooldown.
    - [ ] A magnetized gem keeps flying to the player.
    - [ ] Validation rejects: unknown `ptype`, `hitCd` index out of range, expiry not finite.
  - Verify:
    - [ ] Tests first, then pass: `lua tests/run.lua`
  - Dependencies: A2
  - Files: `src/meta/runsave_entities.lua`, `src/meta/runsave.lua`, `tests/test_runsave_entities.lua`
  - Scope: S

- [x] **A5: Boss and phase rules** (658/0 headless and on LÖVE 12, smoke OK. The rewind is gone: a boss fight resumes with the same boss at the same health and pattern state, a warp resumes as a warp with its clock, the last zone's warp resumes into the win. Music follows the resumed phase. Negative controls: wrong timer floor, unlinked `world.boss`, phase or warp clock not restored, lost pattern state and a healed boss each fail the suite. **Bug found and fixed in A1's validation:** the game counts timers (`freezeT`, `invulnT`, `shieldT`, `pulseT`, `hpRingT`) down only while above zero, so after any elite or boss kill or any hit they sit a fraction below zero; the `>= 0` check rejected such saves, so autosave silently produced nothing after the first elite kill. The floor is now -1, with a test that plays that exact sequence. Replaced tests that asserted the rewind: `snapshot_boss_phase_rewinds…`, `snapshot_warp_phase_resumes_at_next_zone_start`, `snapshot_warp_after_last_zone_is_nil`, `apply_boss_phase_save_resumes_in_waves…`, `apply_warp_save_resumes_at_next_zone`, `a_boss_fight_save_resumes_with_the_boss_coming_back_at_full_health` and the three `…still_rewind…until_A5` tests.)
  - Description: Capture the boss as part of the enemy list (all behaviour scratch for the seven behaviours) and restore `world.boss` as a reference into it. Add `phase` and `warpT` to the snapshot (moved here from A1). Delete the `boss` and `warp` rewind code from `snapshot`. `warp` resumes as `warp` with the remaining `warpT`, including the last zone. When the restored phase is `boss`, `game:enter` plays the boss music and does not emit `boss_spawned`. Replace the old tests that encode the rewind (see below).
  - Acceptance:
    - [ ] Criterion 2 for each of the seven bosses, from a mid-barrage moment (and `entering` for one), 600 frames.
    - [ ] Criterion 4: no heal, no rewind, no duplicate boss, `bossKills` unchanged, no extra `zone_completed`.
    - [ ] Saving in the last zone's `warp` resumes into the win; `endRun` is still called once.
    - [ ] Replaced tests: `a_boss_fight_save_resumes_with_the_boss_coming_back_at_full_health` and the rewind cases in `test_runsave.lua` now assert the opposite (same HP, same attack state). This is an intentional behaviour change from the spec, not a weakened test.
    - [ ] Validation rejects a boss entry in a non-`boss` phase, two bosses, and `world.boss` pointing at a non-boss.
  - Verify:
    - [ ] Tests first, then pass: `lua tests/run.lua`
  - Dependencies: A2, A3, A4
  - Files: `src/meta/runsave.lua`, `src/meta/runsave_entities.lua`, `src/states/game.lua`, `tests/test_runsave_entities.lua`, `tests/test_game_resume.lua`
  - Scope: M (5 files; `test_runsave.lua` updates may make it 6, so split the test replacement into a second commit)

- [x] **A6: Validation fuzz, caps, autosave cost** (672/0 headless and on LÖVE 12, smoke identical to the first baseline. Results in `measurements.md`. Caps now 700 / 800 / 1000 / 800 / 16, each at least 4x the measured peak; autosave 4.1 ms worst, 57 KB worst: within the spec's 5 ms and 256 KB, so no need to stop and ask. **Two more validation bugs found by sampling real runs** (a bullet `life` of 1.04e-16 and a drone cooldown a hair past the save time were rejected because of an invented epsilon); both fixed, with a test that samples every autosave of real play. The fuzz found a bug in its own first version (a path-copy that dropped all but the first key, found by the negative controls). Phone check of the 10 to 20 ms projected autosave hitch is left for V1.)
  - Description: Measure the worst-case entity counts and the autosave cost, then set the validation caps and the budget. Add a fuzz test that mutates every field of a valid version-2 snapshot (wrong type, NaN, huge, negative, missing, out-of-range index) and requires "rejected, or restored without a hang or error".
  - Acceptance:
    - [ ] Criterion 6: every mutation is rejected or harmless, and no mutation loops (each case runs under a step limit).
    - [ ] Criterion 8: measured snapshot time and `run.json` size for the worst-case world are recorded in `docs/enemy-state-save/measurements.md`, with the caps set well above them. Budget: under 5 ms of snapshot work and under 256 KB, unless the measurement says otherwise; if it does, stop and ask.
    - [ ] Entity counts above a cap reject the save.
  - Verify:
    - [ ] Tests first, then pass: `lua tests/run.lua`
    - [ ] Measurement script output recorded
  - Dependencies: A5
  - Files: `src/meta/runsave.lua`, `src/meta/runsave_entities.lua`, `tests/test_runsave_fuzz.lua` (new), `tests/run.lua`, `docs/enemy-state-save/measurements.md` (new)
  - Scope: M

- [x] **A7: Game integration and the no-dodge test** (685/0 headless and on LÖVE 12; smoke OK in 33 s and, with `--test`, left the `run.json` in the save folder untouched. No source change was needed: the earlier tasks had already wired `game:enter`, so this task is the proof through the real flows: Esc, SAVE & QUIT, CONTINUE for a bullet one frame away, a boss wall row and a boss dash; the whole field frozen through the countdown; pause then RESUME changing nothing; steering reset on the way back; a resumed run autosaving only `run.json`; the boss fight, the warp and the last warp saved from the pause menu and from focus loss and quit. Controls: bullets not restored, no countdown, no steering reset, autosave also writing `save.json`, a lost boss dash target, the old "no save in the last warp" rule and a pause that does not save each fail the suite. A real version 1 `run.json` from the player's save folder validates under the new code. **Not done here, needs a person:** the manual desktop and Android checks from `SPEC.md` (they are in V1).)
  - Description: `game:enter` rebuilds the lists and `world.boss` through `RunSave.apply`, then pushes `countdown`. Verify the whole path through the real game state: Esc, SAVE & QUIT, CONTINUE with entities on screen.
  - Acceptance:
    - [ ] Criterion 3: a bullet one frame from the player at save time hits on the first unfrozen frame; the same for a boss dash and a boss wall.
    - [ ] Criterion 5: during the countdown nothing moves and no timer advances with entities present; steering resets on exit.
    - [ ] Criterion 9: normal runs unchanged; `endRun` once; daily and autopilot never saved; `save.json` untouched.
    - [ ] `lovec . --smoke` writes no run.
  - Verify:
    - [ ] Tests first, then pass: `lua tests/run.lua`
    - [ ] `dist/love12/lovec.exe . --test` and `--smoke`
    - [ ] Manual (desktop): spec manual checks 1 to 3 (boss mid-barrage; kill the app mid-boss; swarm of chasers and shooters)
  - Dependencies: A6
  - Files: `src/states/game.lua`, `tests/test_game_resume.lua`, `tests/test_pause_save.lua`, `tests/test_app_lifecycle.lua`
  - Scope: M

- [x] **A8: A hit deletes the save** (added after A7; `SPEC.md` Part C, criteria 17 and 18. 693/0 headless and on LÖVE 12, smoke identical (`kills=381`). Controls: removing the deletion from either handler fails the matching tests. The user chose this fix over exact-saves-only, a recovery slot and a replay journal; it does NOT close a kill before the first hit after a save, and the spec says so. Open follow-up if wanted: after a hit there is no save for up to 10 s, so a crash in that window loses the run; re-saving about 1 s after each hit would shorten it, at the cost of more writes.)
  - Description: In `game.lua`'s `player_damaged` and `shield_blocked` handlers call `Save.clearRun()` first, so a save written before a hit cannot be loaded after it. The next autosave, pause, background or quit writes a fresh exact save. Not a rewrite at the hit: a mid-collision snapshot is not exact.
  - Acceptance:
    - [ ] A hit that costs hull deletes the saved run, both through `Damage.hitPlayer` and through a real bullet collision.
    - [ ] A hit absorbed by the shield deletes it too; a hit while invulnerable deletes nothing.
    - [ ] The next autosave writes a fresh save of the post-hit state, including when the autosave falls on the same frame as the hit; pause writes one too.
    - [ ] Death still deletes at once (existing test unchanged).
    - [ ] After a resume, the first hit deletes the save the run was resumed from.
  - Verify:
    - [ ] Tests first, then pass: `lua tests/run.lua`; `lovec . --test`
  - Dependencies: A7
  - Files: `src/states/game.lua`, `tests/test_game_resume.lua`
  - Scope: XS

### Checkpoint: Cheat closed
- [ ] Behavioural identity passes for all seven bosses and all six enemy movement types
- [ ] No-dodge test passes; the suite and the engine tests are green on LÖVE 12
- [ ] Review with human

## Phase 3: Builds on 12

- [ ] **B3: Build scripts read `LOVE_VERSION`; Windows exe on 12**
  - Description: `build-windows.ps1` takes its LÖVE folder from `get-love.ps1` (default: the pinned commit) and fails with a clear message otherwise. `build.yml`'s `windows` job downloads the pinned artifact with `GITHUB_TOKEN` instead of `love-11.5-win64.zip`. The `.dll` set is checked against what the 12 build ships.
  - Acceptance:
    - [ ] Criterion 13 (Windows part): the fused `SpaceZ.exe` reports 12.0 and starts the game.
    - [ ] No `11.5` left in `build-windows.ps1` or the `windows` job.
    - [ ] The artifact is cached in CI keyed on the pinned commit.
  - Verify:
    - [ ] `pwsh build/build-windows.ps1`, then run `dist/windows/SpaceZ.exe --test`
    - [ ] CI `windows` job green on a PR
  - Dependencies: B2
  - Files: `build/build-windows.ps1`, `build/get-love.ps1`, `.github/workflows/build.yml`
  - Scope: S

- [ ] **B4: Engine tests in CI**
  - Description: New CI job runs `lovec . --test` and `--smoke` on the pinned LÖVE 12 build and gates the release jobs next to the Lua 5.1 suite. Try Linux first (`xvfb-run`, Mesa software GL); if LÖVE 12's graphics floor blocks it, run the job on `windows-latest`.
  - Acceptance:
    - [ ] Criterion 13: the job fails when `--test` or `--smoke` fails (checked by a deliberately broken run on the PR branch, then reverted).
    - [ ] `release` depends on the new job.
  - Verify:
    - [ ] CI run on a PR shows the job green; broken-run check shows it red
  - Dependencies: B3
  - Files: `.github/workflows/build.yml`
  - Scope: S

- [ ] **B5: Android pinned**
  - Description: `build-android.ps1` checks out the `love_android_commit` from `LOVE_VERSION` instead of default-branch HEAD (clone, then `git checkout <sha>` with submodules). Remove the stale "LÖVE 11.5" comment. The CI cache key uses the pinned commit, not a `git ls-remote` of HEAD. Choose the pin by building the APK in CI.
  - Acceptance:
    - [ ] Criterion 12: two builds a day apart use the same `love-android` commit; the pin is printed in the build log.
    - [ ] The APK installs and shows **no** compatibility dialog on the phone (criterion "No compatibility warning").
    - [ ] CI `android` job green.
  - Verify:
    - [ ] CI `android` job; install the APK on the device and start the game
  - Dependencies: B2
  - Files: `build/build-android.ps1`, `.github/workflows/build.yml`, `LOVE_VERSION`
  - Scope: S

- [ ] **B6: Web build decision**
  - Description: `build-web.ps1` uses `love.js`, which ships a LÖVE 11.x runtime. Check whether a LÖVE 12 `love.js` exists. **Stop and ask the user**: (a) stay on the 11.x runtime with a documented exception (the game must still run there, so keep `src/compat.lua` honest), or (b) drop the web build from the pipeline. Implement the choice.
  - Acceptance:
    - [ ] The decision is recorded in `docs/BUILD.md` and the script header.
    - [ ] If kept, `build-web.ps1` runs and the game starts in a browser; if dropped, nothing references it.
  - Verify:
    - [ ] `pwsh build/build-web.ps1 -Serve` and play, or confirm removal
  - Dependencies: B2 (and the user's decision)
  - Files: `build/build-web.ps1`, `docs/BUILD.md`
  - Scope: XS to S

## Phase 4: Ship

- [ ] **B7: Docs, upgrade procedure, leftovers gate**
  - Description: Update `docs/BUILD.md`, `docs/ARCHITECTURE.md` (runsave v2: formats, references, caps; LÖVE 12), `docs/PROGRESS.md` and `README.md`. Add the "move to a newer LÖVE" procedure. Add a headless test that fails if `11.5` appears in tracked build files or docs outside `LOVE_VERSION`, history files and the plan.
  - Acceptance:
    - [ ] Criteria 11, 14 and 15: one source of truth, a documented upgrade step, and no leftover 11.x workarounds.
    - [ ] The ARCHITECTURE run-save section matches the code (version 2, entity blocks, reference tables, validation caps).
  - Verify:
    - [ ] `lua tests/run.lua`
  - Dependencies: A7, B3, B4, B5, B6
  - Files: `docs/BUILD.md`, `docs/ARCHITECTURE.md`, `docs/PROGRESS.md`, `README.md`, `tests/test_version.lua`
  - Scope: M

- [ ] **V1: End-to-end verification and PR**
  - Description: Run every spec criterion and manual check, on desktop and on the phone. Ask whether `feature/run-save-resume` should merge into `main` first, then open the PR.
  - Acceptance:
    - [ ] All 16 criteria pass; the manual checks in `SPEC.md` are done on desktop and Android.
    - [ ] The PR description links `SPEC.md` and lists the intentional behaviour change (boss no longer rewinds).
  - Verify:
    - [ ] `lua tests/run.lua`; `lovec . --test`; `lovec . --smoke`; CI green
  - Dependencies: B7
  - Files: none
  - Scope: S

### Checkpoint: Complete
- [ ] All acceptance criteria met
- [ ] Ready for review
