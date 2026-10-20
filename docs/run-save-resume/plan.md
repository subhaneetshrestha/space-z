# Implementation Plan: Run Save & Continue

Spec: `docs/run-save-resume/spec.md`. Task list: `docs/run-save-resume/todo.md`. Tests: `lua tests/run.lua`.

## Overview

Add a single-slot, run-state save (stored in its own `run.json`; originally planned as a `run` key in `save.json`, changed after review, see the spec's "Changes after code review"), a CONTINUE menu row, autosave and
lifecycle saves, and a 3-2-1 countdown state used after resume-from-save and after pause RESUME.
Daily runs are excluded. All data logic lives in one pure module so it is unit-tested headless;
the LÖVE-facing states stay thin.

## What the code looks like today (verified)

- `src/meta/save.lua` merges unknown keys over defaults, so an absent `run` loads fine and needs no migration or version bump.
- `src/states/game.lua:enter(params)` builds the whole world from `params` + `Save.settings.ship`. Weapons/passives are `{ def, level, cooldown }` / `{ def, level }`; `Leveling.recomputeStats` rebuilds stats and, with no prior stats, sets `hp = maxhp` (restore must set HP afterwards).
- `world.rng.*` are `RNG` objects with one field, `_s`. No get/set API yet.
- Spawner state is `world.spawnerState.timers` (plain numbers). A nil state makes every open wave stream fire immediately, so timers must be saved.
- `core/state.lua` delivers `update` and input to the **top state only**. A pushed `countdown` therefore freezes the world with no extra code, and `translucent = true` keeps the game drawn beneath it.
- `pause.lua` RESUME is `StateM.pop()`. QUIT TO MENU is a bare `StateM.switch("menu")` (the run is simply dropped).
- `main.lua` has `love.quit` but no `love.focus`. Neither can reach the world today, since it is `game.world` inside the game state.
- `tests/run.lua` has an **explicit `FILES` list**: new test files must be added to it.

## Architecture Decisions

- **One pure module, `src/meta/runsave.lua`**, with `snapshot(world)`, `validate(run)` and `apply(world, run)`. No `love.*` calls. Everything the spec's criteria 2, 3 and 10 check is tested here.
- **Restore goes through the normal `game:enter` path.** `enter` builds a fresh world exactly as for a new run, then `RunSave.apply` overwrites progression fields. A resumed run cannot drift from a fresh one (spec Boundary).
- **`Game.saveRun()` is the single entry point** for every trigger (autosave, pause, quit-to-menu, focus loss, `love.quit`). It reads `game.world`, applies the exclusions (dead, `over`, daily, autopilot) and, if the `levelup` state is on top, adds the open draft to `pendingLevelUps`. States and `main.lua` just call it.
- **The game state pushes `countdown` at the end of `enter` when `params.resume` is set.** Pause RESUME does `pop()` then `push("countdown")`. The countdown pops itself, which re-triggers `game:resume` (input reset); that is idempotent.
- **Boss and warp rewinds happen in `snapshot`**, per the spec's phase table, so `apply` stays a dumb field copy.
- **Validation is strict and total**: on any malformed field the whole run is treated as absent. `Save.run()` returns only a validated table.
- **Daily runs never save** (`world.daily`), so the daily path needs only the exclusion plus keeping the existing `QUIT TO MENU` label.
- Clear on death at the `player_died` event, not at `endRun`, so a dead run can never be resurrected (spec: stardust in the ~1.2 s death window is forfeited if the app is killed there).

## Dependency Graph

```
RNG get/setState (T1)
        |
runsave snapshot/validate + Save.run helpers (T2) --> runsave.apply (T3)
        |                                                  |
        |                                  game: resume, autosave, clear (T5)
        |                                     /        |            \
countdown state (T4) -> pause RESUME      pause SAVE&QUIT (T6)   menu CONTINUE (T7)   main.lua hooks (T8)
        \________________________ verify + PR (T9) ______________________/
```

T4 (countdown) is independent of T1-T3 and can be built in parallel; T5 depends on it for the `push("countdown")` after a resume.

## Task List

### Phase 1: Save data (pure, headless)
- [ ] T1: RNG `getState` / `setState`
- [ ] T2: `runsave.snapshot` + `validate` + `Save.run` helpers
- [ ] T3: `runsave.apply` restores a world from a run

### Checkpoint: Data layer
- [ ] `lua tests/run.lua` passes; round trip, determinism and validation criteria (2, 3, 10) proven by tests

### Phase 2: Countdown
- [ ] T4: `countdown` state, wired to pause RESUME

### Phase 3: Game integration
- [ ] T5: Game resume path, autosave, clearing
- [ ] T6: Pause SAVE & QUIT
- [ ] T7: Menu CONTINUE + overwrite guard
- [ ] T8: `love.focus` / `love.quit` hooks

### Checkpoint: Playable
- [ ] `lua tests/run.lua`, `love . --test` and `love . --smoke` pass
- [ ] Manual desktop run of the spec's manual checks 1, 4, 5
- [ ] Review with human

### Phase 4: Ship
- [ ] T9: Verify end to end, update docs, open PR

(T4 sits in Phase 2 because it is independent and cheap; build it right after the data layer.)

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Restored run feels different from the original (some state not captured) | High | Round-trip test per field; restore through `game:enter`; manual comparison on the checks above |
| Level-up draft open during save / focus loss | Med | `saveRun` counts the open draft into `pendingLevelUps`; explicit test and manual check |
| Autosave stutter on Android (JSON encode + file write every 10 s) | Med | Snapshot is a few hundred bytes; measure once on desktop, confirm on device in T9; interval is a single constant |
| Android kills the process without `focus`/`quit` | Med | 10 s autosave bounds the loss; documented in spec assumptions |
| `love.focus(false)` firing on desktop alt-tab causes needless writes | Low | Harmless: one small write per alt-tab |
| Save written while dead, resurrecting a dead run | High | `snapshot` returns nil when dead/over; clear on `player_died`; tested |
| Corrupt/hand-edited `run` crashes menu or `enter` | High | `Save.run()` validates before anything reads it; one test per malformed case |
| Tech bought in Star Map between save and resume changes stats | Low | Accepted in spec assumptions; HP clamped to `[1, maxhp]` |
| Achievements' live listeners hold run-local counters not in the snapshot | Low-Med | Check `src/meta/achievements.lua` `live()` in T4; if it keeps per-run counters, either snapshot them or document the loss and ask |
| Pushing a state inside `enter` during `StateM.switch` | Low | Stack is already set before `enter` runs; covered by a test of the state stack order |

## Open Questions

- None blocking. T5 includes a short check of `Achievements.live` (above) and will report back before changing scope.
