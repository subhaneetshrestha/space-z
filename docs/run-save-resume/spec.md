# Spec: Run Save & Continue (with 3-2-1 resume countdown)

## Objective

Today a run lives only in memory. Quitting to the menu, closing the app, or Android killing the
process throws the run away. `save.json` only holds meta progress (stardust, unlocks, settings).

Add a **single-slot run save** so a player can leave mid-run and later press **CONTINUE** to pick
up where they were, with their build and **current health** intact. Resuming (from a saved run)
shows a **3 - 2 - 1 countdown** with the world frozen before control returns.

Users: mobile (Android, touch, app gets backgrounded or killed often) and desktop players.

### Decisions already made (from the clarifying questions)

| Topic | Decision |
|---|---|
| Fidelity | **Run-state snapshot.** Saves the progression and build. Enemies, bullets, pickups, drones, particles and the active boss are NOT saved. |
| Timing | **Autosave + on pause / quit / app-background.** One slot. Cleared when the run ends. |
| Scope | **Menu CONTINUE row, standard and Black Hole modes.** **Daily Run is NOT resumable** (it never autosaves or writes a run save; quitting a daily run discards it as today). |
| Countdown | Runs on resume-from-save **and** on pause's RESUME. |
| Grace period | **None.** No invulnerability after the countdown. |
| Boss fight | Saved mid-boss resumes with the boss re-entering at full HP. |

### What a snapshot contains

Everything needed to rebuild the run from `game.lua:enter`:

- Identity: `mode` (`standard` or `blackhole` only), `seed`, ship id (the run's own ship, not whatever `settings.ship` is now).
- Clocks: `time`, `distance`, `zoneIndex`, `zoneTime`, `zoneStartDistance`.
- Progression: `level`, `xp`, `xpNext`, `pendingLevelUps`, `kills`, `bossKills`, `noDamage`, `stardustEarned`.
- Build: weapons `{ id, level }[]`, passives `{ id, level }[]` (looked up by id on restore; evolved weapons are registry ids too).
- Health: `player.hp`. `maxhp` is **recomputed** by `Leveling.recomputeStats`, never stored.
- Determinism: the four RNG stream states (`spawn`, `drops`, `cards`, `misc`) and `spawnerState.timers`.

Not saved: transient timers (`shieldT`, `invulnT`, `freezeT`, flashes), cooldowns (reset to 0), player position (reset to the spawn point), starfield position (cosmetic).

### Phase rules (what "where you were" means)

| Phase when saved | Resume point |
|---|---|
| `waves` | Same zone, same `zoneTime`. Field starts empty; the spawner refills it from its saved timers. |
| `boss` (boss alive) | **Rewound to the boss's arrival**: `phase = "waves"`, `zoneTime = zone.duration`. The field is empty, so the spawner brings the boss in immediately. Boss HP is back to full. |
| `warp` (boss just died) | Start of the **next zone** (`zoneIndex + 1`, `zoneTime = 0`). The boss kill and `bossKills` are kept. If it was the last zone, the run is already won: no save is written. |
| `over` / player dead | **Never saved. Any existing save is cleared** the moment `player_died` fires. |
| Level-up draft open | `pendingLevelUps` is saved **including** the open draft, so a draft is shown again on resume. The cards may differ (the RNG has already advanced). |

## Acceptance Criteria

1. **Save data.** `save.json` gains an optional `run` table (`nil` = no saved run). Old saves load unchanged. `Save.reset()` clears it.
2. **Round trip.** Snapshot a world, restore it into a fresh world: every field under "What a snapshot contains" is equal (HP exactly, including fractional values; clamped to `[1, maxhp]`).
3. **Determinism.** Restoring the RNG states and spawner timers makes the next N spawns identical to a run that never paused.
4. **Autosave triggers.** The run is written: every 10 s of unpaused play, on entering pause, on QUIT TO MENU, on `love.focus(false)`, and on `love.quit`. Never while `phase == "over"`, the player is dead, or `world.daily` is true.
5. **Clearing.** The save is cleared on `player_died` and when the run is won. It is not cleared by QUIT TO MENU.
6. **CONTINUE row.** Menu shows `CONTINUE` as the first row **only when a valid `run` exists**; it is the default selection. It resumes in the saved run's own mode and ship. Daily runs are never saved, so they never produce a CONTINUE row.
7. **Overwrite guard.** With a save present, LAUNCH and DAILY RUN (either starts a new run) need a confirming second press ("ABANDON SAVED RUN? TAP AGAIN") before they start a new run and discard the save. Navigating away cancels the confirmation.
8. **Countdown.** After a saved run is restored, **and after pause's RESUME**, a translucent `countdown` state shows **3, 2, 1** at 1 s each (about 3 s total), then control returns. During it: the world does not update (nothing moves, no damage, no spawns, no timers advance), the HUD is visible, and touch/keys do not steer. The steering input is reset on exit (`game:resume` already does this) so a finger already down does not cause a jump.
9. **Quit to menu.** In standard and Black Hole runs, pause's QUIT TO MENU saves, then goes to the menu, and its label reads `SAVE & QUIT`. In a Daily run it keeps the label `QUIT TO MENU` and discards the run as today.
10. **Corrupt or stale data is harmless.** Wrong types, missing fields, unknown weapon/passive ids, or an unknown ship id means the save is treated as absent: no CONTINUE row, no crash, no partial restore.
11. **No behaviour change to normal runs.** A run that is never resumed plays and scores exactly as before. Autopilot and `--smoke` runs never write a run save.
12. **Stats stay honest.** Resuming does not count as a new run: `totalRuns` and stardust change only when the run actually ends (`Progress.endRun`, still called exactly once).

## Commands

```
Test (all):        lua tests/run.lua
Test (in engine):  love . --test
Smoke (headless):  love . --smoke            # must still pass, and must not write a run save
Run:               love .
Build .love:       pwsh build/make-love.ps1
```

## Project Structure

```
src/meta/runsave.lua       -> NEW: snapshot(world), validate(run), restore params; pure, headless-safe
src/meta/save.lua          -> add run default (nil), Save.setRun / Save.clearRun helpers
src/core/rng.lua           -> add RNG:getState() / RNG:setState(s)
src/states/countdown.lua   -> NEW: translucent 3-2-1 overlay state
src/states/game.lua        -> enter(params.resume), autosave timer, clear on death/win
src/states/pause.lua       -> SAVE & QUIT row, snapshot on enter
src/states/menu.lua        -> CONTINUE row, overwrite confirmation
main.lua                   -> register "countdown"; love.focus / love.quit hooks
tests/test_runsave.lua     -> NEW
tests/test_countdown.lua   -> NEW
docs/run-save-resume/      -> spec.md, plan.md, todo.md
```

Check how `tests/run.lua` discovers test files before adding the new ones.

## Code Style

Match the existing Lua: 2-space indent, `local` helpers at the top, short comments that explain why, headless-safe (guard `love.*`). Pure data modules take and return plain tables. Example of the intended shape:

```lua
-- src/meta/runsave.lua — snapshot/restore of an in-progress run. Pure data:
-- no love.* calls, so it runs headless under tests/run.lua.
local M = {}

local RUN_VERSION = 1

function M.snapshot(world)
  if world.phase == "over" or world.player.dead then return nil end
  local run = {
    version = RUN_VERSION,
    mode = world.mode, daily = world.daily, seed = world.seed,
    ship = world.player.shipDef.id,
    time = world.time, distance = world.distance,
    -- ...
  }
  if world.phase == "boss" then -- rewind to the boss's arrival (field restarts empty)
    run.phase, run.zoneTime = "waves", world.zone.duration
  end
  return run
end
```

## Testing Strategy

- **Prove-It / TDD.** Write failing tests first. `tests/test_runsave.lua` is table-driven and runs headless with `fakeWorld`-style tables (see `tests/test_save.lua`).
- **Unit (headless):**
  - snapshot -> JSON encode -> decode -> restore round trip (criterion 2), covering HP fractions and each phase row of the table above.
  - RNG `getState`/`setState`: restoring yields the same next 100 draws (criterion 3).
  - `validate` rejects each malformed case in criterion 10, one test per case.
  - `Save.reset()` clears `run`; an old save with no `run` key loads cleanly.
  - Clearing: `player_died` clears; QUIT TO MENU does not (stub `Save`).
- **Countdown:** drive `countdown:update(dt)` with fixed steps. Assert it ends after 3.0 s +/- one step, shows 3 then 2 then 1, pops exactly once, and never calls the game's update.
- **Regression:** existing `test_save`, `test_spawner`, `test_zones`, `test_damage`, `test_leveling` unchanged and passing.
- **Smoke:** `love . --smoke` still finishes; assert no `run` is written (criterion 11).
- **Manual (desktop, then Android):**
  1. Take damage, level up, reach zone 2, press Esc, then SAVE & QUIT, then CONTINUE: same HP, build and zone; 3-2-1; play resumes.
  2. Force-close (kill the process) mid-run, relaunch, CONTINUE: resumes within about 10 s of the loss.
  3. Background the app on Android during a level-up draft, return, CONTINUE: draft is offered again.
  4. Die, then relaunch: no CONTINUE row.
  5. Save mid-boss: resumes with the boss re-entering at full HP.

## Boundaries

- **Always:**
  - Write the failing test first; run `lua tests/run.lua` before each commit.
  - Treat the save file as untrusted input: validate before use, fall back to "no save".
  - Keep restore code on the same path as a normal run start (`game:enter`), so a resumed run cannot diverge from a fresh one.
  - Keep `Progress.endRun` called exactly once per run.
- **Ask first:**
  - Bumping `CURRENT_VERSION` or changing the existing `save.json` schema beyond adding `run`.
  - Saving entities (enemies, bullets, boss) or boss HP, which is the "Full snapshot" option we declined.
  - Adding multiple save slots, cloud save, or any new dependency.
  - Changing `main.lua`'s timestep or the state machine in `core/state.lua`.
- **Never:**
  - Save while dead or in `over`, or keep a save that lets a dead run be resurrected.
  - Let a corrupt `run` block the game from starting or crash the menu.
  - Award stardust or count a run twice because of resume.
  - Delete or weaken existing tests.
  - Commit to `main` directly. Use a branch and PR.

## Assumptions (correct me if wrong)

1. `love.focus(false)` and `love.quit` are enough to catch Android backgrounding. The 10 s autosave covers the case where the process is killed without either firing.
2. Hangar and Star Map stay usable while a save exists. A resumed run recomputes stats from **current** Star Map tech, so tech bought in between applies on resume. The run's ship is the saved one, not the hangar's current selection.
3. Losing on-screen enemies and uncollected XP gems on resume is acceptable ("run-state snapshot").
4. One saved run at a time; starting a new one discards it only after confirmation.

## Open Questions

None. The four earlier questions are resolved (see the Decisions table).

## Next Step

On approval I will write `docs/run-save-resume/plan.md` and `todo.md`. No code until then.
