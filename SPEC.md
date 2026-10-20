# Spec: Frozen-Moment Run Save + LÖVE 12 Compatibility

Extends `docs/run-save-resume/spec.md` (shipped). That feature saved only progression and build, so
resuming gave the player an empty field. This spec changes that and also fixes the LÖVE version mismatch.

## Objective

**Problem 1: the save is an escape hatch.** Today a snapshot drops enemies, enemy bullets, pickups and
the boss. A player under a heavy barrage can press Esc, then SAVE & QUIT, then CONTINUE. They come back
to an empty field, with the boss rewound to full HP and a free repositioning. The same thing happens
with an app switch on mobile. The save must not be a way to dodge an attack.

**Problem 2: version mismatch.** `conf.lua`, the Windows CI build, `build-windows.ps1` and the docs
all say LÖVE 11.5. But `build/build-android.ps1` clones `love-android` at its newest commit, and that
now bundles **LÖVE 12.0** (verified: `love-android` main pins a `love` submodule whose
`LOVE_VERSION_STRING` is `"12.0"`). So the Android APK already runs on 12, the Windows exe and the local
scoop install run on 11.5, and `conf.lua` claims 11.5. The game has never been checked on 12, and the
Android build isn't pinned, so it can change under us.

### Success in one sentence

Save at any instant, resume, and after the 3-2-1 countdown the world is **exactly as it was**: every
enemy, bullet, pickup, drone and the boss in the same place with the same health and behaviour state,
and the player in the same position. Every build of the game (desktop, Android, tests) runs on the
**latest LÖVE**, which is 12.0 today, and the repo declares that in one place.

### Decisions already made

| Topic | Decision |
|---|---|
| Fidelity | **Exact snapshot.** Everything that affects gameplay is saved as it is, with nothing rewound, rounded or rebuilt: enemies, enemy bullets, the boss (HP and behaviour state), player bullets, pickups, drones (including orbit angle) and the player. |
| Grace period | **None.** The 3-2-1 countdown (world frozen, as today) is the only pause. No invulnerability after it. |
| Save slot | One slot in `run.json`, not consumed on load. Deleted when the ship is hit and when it dies (Part C). |
| LÖVE target | **Always the latest LÖVE through the whole development cycle.** That is 12.0 now. `conf.lua`, CI, Windows, Android, web and local dev all move to it, and track new releases as they come. |

## Part A: Entity-complete run save

### What changes in a snapshot

Everything in the existing snapshot stays (progression, build, clocks, RNG streams, spawner timers). Added:

| Group | Fields |
|---|---|
| Player | `x, y, vx, vy, invulnT, shieldT, pulseT, hpRingT`, and each weapon's `cooldown` (today reset to 0). |
| Enemies | Per live enemy: `def` id (or `bossDef` id for the boss), `x, y, vx, vy, rot, scale, r, t, bt, hp, maxhp, touchDamage, xp, elite, flashT, slowT, slowMult, entering, bossPhase`, plus its behaviour scratch fields (`phase, baseX, spin, spd, fireT, lungeT, state, stateT, burstT, fanT, addT, ...`). |
| Enemy bullets | `x, y, vx, vy, r, rot, scale, t, damage, life, sprite`. |
| Player bullets | `x, y, vx, vy, r, rot, t, damage, pierce, life, weaponId, slowT, slowMult, aoe`. |
| Pickups | Whatever `Pickups` sets per gem and heal drop (type, value, position, velocity, age). |
| Drones | Each drone's `angle`, position and hit cooldown, so the orbit continues without a jump. |
| World | `phase` (including `boss` and `warp`), `warpT`, `freezeT`, and whether `world.boss` points at an entry in the saved enemy list. |

Not saved (cosmetic, no gameplay effect): particles, arcs, beams, pulses, toasts, shake, starfield,
damage-flash timers, music state.

### Phase rules (replaces the old table)

| Phase when saved | Resume point |
|---|---|
| `waves` | Same zone, same `zoneTime`, **same live entities**. |
| `boss` | The boss resumes **with its current HP, behaviour state and bullets in flight**. This replaces the old "rewind to arrival at full HP" rule. |
| `warp` | Resumes in `warp` with the remaining `warpT`, as it was. This includes the last zone, so the old "2.5 s window where the app can be killed and CONTINUE offers the final boss" goes away. |
| `over` / player dead | Never saved. Any existing save is cleared on `player_died`. Unchanged. |
| Level-up draft open | Unchanged: the open draft is counted in `pendingLevelUps` and shown again. The RNG has already advanced, so the cards may differ. This is safe because the world is frozen while a draft is open. |

### Acceptance criteria

1. **Exact round trip.** snapshot, then JSON encode, then decode, then restore into a fresh world. Every
   saved field above is equal. Floats are compared with the tolerance already used for `json.lua`'s
   14-digit round trip (`TIMER_TOLERANCE`).
2. **Behavioural identity (the cheat-proof test).** Take a world mid-fight, snapshot it, resume the
   copy, and step both worlds N fixed frames (N is at least 600). The two worlds stay equal to within
   tolerance: same enemy list, same bullets, same player HP, same kills. This is run for each of the
   seven bosses, at least one mid-barrage moment per boss, and each enemy movement type (`drift, sine,
   chaser, shooter, lunge, ballistic`).
3. **No dodge.** A test that saves while an enemy bullet is one frame from the player and resumes
   shows the player takes that hit on the first unfrozen frame. The same check applies to a boss
   dash or boss wall.
4. **Boss integrity.** Saving mid-boss never rewinds, heals or re-introduces the boss. `world.boss`
   is rebuilt as a reference into the restored enemy list (never a duplicate). `bossKills` and the
   achievement counters are not double-counted.
5. **Countdown freezes everything.** During the 3-2-1, no entity moves and no timer advances (existing
   countdown criterion, now with entities present). The countdown still ends with the existing
   steering reset.
6. **Validation stays strict.** Each entity entry is untrusted. All of these make the whole save "no
   save" (no partial restore, no crash):
   - an unknown enemy, boss or weapon id;
   - a non-finite or wrong-typed number;
   - a non-boolean flag;
   - a count above the cap (caps are set in the plan from measured worst cases);
   - a boss entry that does not match the phase;
   - scratch fields outside a known whitelist, or timers that could loop forever.
   A timer-style field uses the same (0, interval] rule as the spawner timers.
7. **Legacy saves.** A version-1 `run.json` (no entities) still loads and resumes as before. That is a
   one-time degradation for saves made before this change. New saves are version 2.
8. **Autosave cost.** A worst-case world (heaviest zone, boss with a full barrage, a full pickup field)
   serializes and writes within a measured budget. The plan sets the numbers, for example under 5 ms of
   snapshot work per autosave and `run.json` under 256 KB. The autosave interval stays 10 s.
9. **No change to normal play.** A run that is never saved or resumed behaves exactly as before. The
   existing run-save criteria (clear on death, daily and autopilot never saved, `endRun` once, and so
   on) still hold. `save.json` is not touched.

## Part C: Rollback by killing the app (added after A7)

The exact snapshot closes "save, quit, continue to escape an attack". A second route remained: the
game rewrites the save every 10 s, so a player about to be killed can force-kill the app before the
lethal hit lands (no death event ever fires) and Continue from the autosave up to 10 s earlier.
Death already deletes the save the same frame (`player_died`), so dying then killing the app gains nothing.

**Decision (the user's, after being offered three fixes):** delete the save when the ship is hit.

17. **A hit deletes the save.** When the ship takes a hit, whether it loses hull or the hit is absorbed
    by a shield, the saved run is deleted at once (`Save.clearRun`), so no save from before that hit
    can be loaded: a hit cannot be undone by killing the app. The next autosave, pause, background or
    quit writes a fresh, exact save of the moment after the hit. A hit that changes nothing (the ship is
    invulnerable) deletes nothing. The save is deleted, not rewritten, at the hit: a snapshot in the middle
    of collision handling would not be exact.
18. **Death still deletes at once** (unchanged).

**What this does not close, stated plainly.** A kill before the *first* hit after a save still resumes
that save (at most 10 s old, or exactly the pause moment). In Black Hole mode any hit is lethal, so the
first hit is the last. The options that close it completely were declined for now: exact saves only (no
autosave, Continue consumes the save), a recovery slot that forfeits stardust, and a replay journal.
Copying `run.json` aside and putting it back cannot be prevented offline.

**Cost.** After a hit there is no save until the next autosave (up to 10 s), so a crash in that window
loses the run.

## Part B: LÖVE 12 compatibility

### Facts established

- **Android:** `build-android.ps1` clones `love-android` unpinned (`--depth 1`, default branch). Its
  `main` branch (and a `12.x` branch) bundle LÖVE 12.0 (dev), so the APK is already on 12. The
  script's comment ("default branch = LÖVE 11.5") is stale. CI's cache key already follows that
  upstream HEAD.
- **Windows / CI / local:** CI downloads `love-11.5-win64.zip`, `build-windows.ps1` and
  `docs/BUILD.md` use 11.5, and the scoop install is 11.5. `love2d/love` has no 12.x release tag yet,
  so 12 binaries come from CI artifacts or a build from source.
- `conf.lua` says `t.version = "11.5"`. 11.5 appears in `conf.lua`, `build.yml`, `build-windows.ps1`,
  `build-android.ps1`, `build-web.ps1`, `docs/BUILD.md` and `docs/ARCHITECTURE.md`.
- The `love.*` surface is mainly the sprite atlas and SpriteBatch, the audio synth (`newSource`),
  `love.filesystem`, and `love.graphics`. The game has never been run on 12, so what breaks is unknown
  until the first task runs it.

### Acceptance criteria

10. **Runs on the latest LÖVE.** `lovec . --test` and `lovec . --smoke` pass on a LÖVE 12 build, and
    the game plays (menu, run, boss, pause, save and continue, game over, hangar) with no errors and
    no visual or audio regressions. Android and desktop are both checked.
    **No compatibility warning.** `conf.lua` declares the same version the runtime reports (12.0), so
    the "made for 11.5, may not be compatible with 12.0" dialog on the Android app no longer appears.
    Checked on the phone, and in a test that compares `t.version` with the `LOVE_VERSION` file.
11. **One source of truth.** The LÖVE version lives in one file (for example a `LOVE_VERSION` file at
    the repo root, next to `VERSION`). `conf.lua`, `build/*.ps1`, `build.yml` and the docs read it or
    point to it. No other file hard-codes `11.5`.
12. **Android is reproducible.** `build-android.ps1` checks out a **pinned** `love-android` commit
    (recorded in the same version file) instead of upstream HEAD, so an upstream change can't alter a
    build between two pushes. Bumping the pin is a deliberate change that CI verifies.
13. **Windows and CI run 12.** The Windows exe is fused with a LÖVE 12 build, and a CI job runs
    `lovec . --test` and `--smoke` on that same build, not only the Lua 5.1 suite. The test job gates
    releases as before.
14. **Use the latest, deliberately.** A documented step says how to move to a newer LÖVE (change the
    version file, run the tests, rebuild), so "always the latest" is a routine and not a rewrite.
15. **No leftover 11.x workarounds.** Anything in the code or docs that exists only for 11.5 (stale
    comments, API workarounds) is removed once 12 is the baseline. Where an API differs, one small
    shim in `src/compat.lua` handles it, not scattered version checks.
16. **Still passes headless.** `lua tests/run.lua` passes under Lua 5.1 (CI), which is independent of
    the LÖVE version.

## Commands

```
Test (all, headless):  lua tests/run.lua
Test (in engine):      lovec . --test
Smoke (headless):      lovec . --smoke          # must pass and must not write a run save
Run:                   love .
Build .love:           pwsh build/make-love.ps1
Build Windows:         pwsh build/build-windows.ps1 -LoveDir <path to LÖVE folder>
Build Android:         pwsh build/build-android.ps1
Run on LÖVE 12:        <path to the 12 build>\lovec.exe . --test   (and --smoke)
```

The LÖVE 12 desktop build comes from the `love2d/love` CI artifacts (see Open Questions).

## Project Structure

```
src/meta/runsave.lua       -> snapshot / validate / apply: add entities, bump to version 2, accept version 1
src/meta/runsave_entities.lua -> NEW (if runsave.lua gets too large): entity (de)serialization + whitelists
src/meta/save.lua          -> unchanged API (run.json); size/write-cost checks only
src/states/game.lua        -> enter(resume): rebuild lists and world.boss; saveRun unchanged
src/systems/*.lua          -> read-only reference: behaviour scratch fields the snapshot must cover
src/compat.lua             -> NEW: LÖVE 11 / 12 differences behind one shim (only if Part B finds any)
conf.lua                   -> version declaration, read from the single version file
LOVE_VERSION               -> NEW: the one place the LÖVE version and the love-android pin live
tests/test_runsave.lua     -> extend (round trip, validation)
tests/test_runsave_entities.lua -> NEW (behavioural identity, no-dodge, per-boss)
build/*.ps1, .github/workflows/build.yml, docs/BUILD.md, docs/ARCHITECTURE.md -> version handling
docs/enemy-state-save/     -> plan.md, todo.md (feature docs live under docs/<feature>/)
```

## Code Style

Match the existing Lua: 2-space indent, `local` helpers at the top, short comments that explain why,
headless-safe (no `love.*` in pure modules), table-driven tests. Entity capture is whitelist-based and
data-driven, so a new enemy behaviour field cannot be silently dropped:

```lua
-- fields a snapshot keeps per entity kind; anything else is derived or cosmetic
local ENEMY_FIELDS = {
  "x", "y", "vx", "vy", "rot", "scale", "r", "t", "bt", "hp", "maxhp",
  "touchDamage", "xp", "elite", "flashT", "slowT", "slowMult",
  "entering", "bossPhase", "phase", "baseX", "spin", "spd", "fireT", "lungeT",
}

local function captureEnemy(e)
  local out = { def = e.def and e.def.id, boss = e.bossDef and e.bossDef.id }
  for i = 1, #ENEMY_FIELDS do
    local k = ENEMY_FIELDS[i]
    if e[k] ~= nil then out[k] = e[k] end
  end
  return out
end
```

A test fails if a behaviour in `src/systems/` reads or writes an enemy field that is neither on the
whitelist nor on an explicit "derived or cosmetic" list. That test is how the whitelist stays complete.

## Testing Strategy

- **TDD / Prove-It.** Write the failing "no dodge" and "behavioural identity" tests first, against the
  current code, to prove the cheat exists. Then make them pass.
- **Headless unit (`lua tests/run.lua`):** round trip, validation (one test per malformed case in
  criterion 6), legacy v1 load, whitelist completeness, autosave cost measurement.
- **Behavioural identity:** deterministic stepping with fixed `dt`, seeded RNG, comparing full world
  state after N frames. Table-driven over bosses and enemy movement types.
- **Engine (`lovec . --test`, `--smoke`):** on the LÖVE 12 build, in CI and locally.
- **Manual (desktop, then Android):**
  1. Fight a boss mid-barrage, press Esc, SAVE & QUIT, CONTINUE: same bullets, same boss HP, same
     position, then 3-2-1, then the hit lands.
  2. Kill the app during a boss fight, relaunch, CONTINUE: resumes within about 10 s of the loss.
  3. Save during a swarm of chasers and shooters: they resume where they were.
  4. Play a full run on LÖVE 12: menu, run, boss, pause, continue, game over, hangar.

## Boundaries

- **Always:**
  - Write the failing test first; run `lua tests/run.lua` before each commit.
  - Treat `run.json` as untrusted: validate every entity, fall back to "no save".
  - Keep the restore path on top of the normal `game:enter` world build.
  - Keep `Progress.endRun` called exactly once per run, and `save.json` untouched by run saves.
- **Ask first:**
  - Adding a dependency, or any change to `save.json`'s schema or `CURRENT_VERSION`.
  - Bumping the pinned LÖVE or `love-android` version after the initial move to 12.
  - Fusing the Windows exe from a nightly or CI artifact rather than a tagged release.
  - Adding a grace period, save slots, or "consume save on load" behaviour.
  - Changing `main.lua`'s timestep or `core/state.lua`.
- **Never:**
  - Save while dead or in `over`, or keep a save that resurrects a dead run.
  - Let a corrupt entity entry crash the menu, block the game from starting, or partly restore.
  - Delete or weaken existing tests, or loosen validation caps to make a test pass.
  - Commit to `main` directly. Use a branch and PR.
  - Let a build track an unpinned upstream (`love-android` HEAD or a moving nightly).

## Assumptions (correct me if wrong)

1. "Latest version" means LÖVE 12.0 (development branch) today. It is not yet a tagged release, so we
   pin to a specific commit rather than follow a moving branch.
2. Saving the exact player position is acceptable. It is needed so that dodging by repositioning isn't
   a free cheat.
3. A single-slot, non-consumed save is acceptable. A player can still reload an older autosave after a
   death only if the clearing rules fail, and those rules are tested and unchanged.
4. Version-1 saves keep working with an empty field. That is a one-time gap, not worth a migration.
5. Resuming a `warp` as `warp` is safe for achievements and `bossKills`. The plan must verify this
   against `game.lua`'s warp handling before the design is final.

## Open Questions

1. ~~Where the desktop LÖVE 12 binary comes from.~~ **Decided: the recommendation below.** There is no
   tagged 12 release, and scoop has only 11.5. CI downloads the `love2d/love` Actions artifact for a pinned commit with
   the job's `GITHUB_TOKEN`, and locally you download the same artifact once and point
   `-LoveDir` at it. Alternative: build LÖVE from source in CI, which is slower. Which do you prefer?
2. ~~Which LÖVE 12 build is the Android app on?~~ Resolved: the phone reports 12.0 and shows the
   "made for 11.5" compatibility warning, which matches `love-android` main and the stale `conf.lua`.
3. **Entity caps for validation.** Exact snapshots mean caps can't be used to trim a save. They only
   reject corrupt files. I'll measure worst-case counts in the plan and set the caps well above them.

## Next Step

On approval I will write `docs/enemy-state-save/plan.md` and `todo.md`. I won't write any code until you
approve this spec.
