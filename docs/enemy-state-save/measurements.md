# Run save: measured sizes and costs (task A6)

How big a run save gets and what an autosave costs in the worst case the game can produce.
Reproduce with `luajit tests/measure_runsave.lua` (about 100 s) or `... quick` (one zone, 6 s).
Measured on 2026-10-20, Windows desktop, LuaJIT (the engine LÖVE 12 uses), commit `beca99c` plus A6.

## Method

Stress builds are played through the **real game state**, every zone and its boss fight, and an
actual autosave is sampled throughout (and at every new peak of total entities):
`RunSave.snapshot`, `json.encode`, `json.decode`, `RunSave.validate`. Each sample asserts the snapshot
validates, so a real run that produced an invalid save would stop the tool (it did, twice: see below).

| Scenario | What it stresses |
|---|---|
| `maxed_base` / `all_evolved`, standard, all 7 zones | six weapons at top level (base set, or all evolved), plus fire-rate and bullet-count passives: the most bullets. The magnet is off, so gems pile up instead of being collected |
| the same two builds, Black Hole, zone 7 | enemies with 1.5x health live longer |
| `flood`, all 7 zones | nothing shoots, so every wave stays alive until it flies off screen: the most enemies |
| every boss fight, 90 s, weapons silenced | the boss keeps its full barrage and sheds adds |

## Most alive at once

| Kind | Peak | Where | Cap | Headroom |
|---|---|---|---|---|
| enemies (incl. boss and adds) | 172 | flood, zone 7 | 700 | 4.1x |
| player bullets | 131 | all-evolved build, zone 5 | 800 | 6.1x |
| enemy bullets | 93 | flood, zone 3 boss | 1000 | 10.8x |
| gems | 129 | all-evolved build, zone 5 | 800 | 6.2x |
| drones | 6 | any zone | 16 | 2.7x (the biggest weapon level has 6) |
| all lists together | 269 | all-evolved build, zone 5 | | |

A cap only rejects a corrupt or edited file and bounds what restoring one can cost. It must never be
tight: a real run that hits a cap is thrown away. So each cap sits at least 4x above the peak
(`tests/test_runsave_limits.lua` enforces that, and the drone cap at twice the biggest weapon level).

## Cost of one autosave (milliseconds on the game thread)

| | worst | median | 95th percentile |
|---|---|---|---|
| `RunSave.snapshot` | 1.95 | | |
| `json.encode` | 2.90 | | |
| **snapshot + encode** (what an autosave pays) | **4.10** | 1.00 | 2.05 |
| decode (at resume only) | 7.00 | | |
| validate (at resume only) | 0.70 | | |

2064 autosaves sampled. **Size: 57,347 bytes at worst** (flood, zone 7).

Against the spec's budget (under 5 ms of snapshot work, `run.json` under 256 KB): **met**, with
4.1 ms worst and 57 KB worst. Autosave still runs every 10 s.

Caveats to check on the phone (task V1):
- These are desktop numbers. A phone CPU is several times slower, so the worst case could cost on
  the order of 10 to 20 ms once every 10 s. If that shows as a visible hitch, the cheapest fix is
  in `lib/json.lua`'s number encoder (it formats floats up to three times to stay bit-exact), then
  moving the write off the update.
- The file write itself is not measured here (no filesystem under the headless harness).

## What the measurement found

Playing real runs and requiring every sampled save to validate caught two bugs in the validation
that no hand-made fixture had hit, both the same mistake: an invented lower bound on a value the
game only keeps above zero.

| Found | Why a real run produces it | Fixed |
|---|---|---|
| A flak bullet with `life = 1.04e-16` was rejected | `life - dt` repeated leaves float residue; the game kills a bullet at `life <= 0`, so any amount above zero is live | strictly `> 0`, no epsilon |
| A drone cooldown ending a hair after the save time would have been rejected | same: `expiry > time` can hold by 1e-14 | strictly `> time` |

(A5 found the same family: countdown timers sit a fraction below zero after they run out.)
`tests/test_runsave_limits.lua` now samples every autosave of real play (a strong build through a
boss fight, the warp and the next zone; zone 7 crowded; four boss barrages) and fails on the first
save the game writes that its own validation rejects.

## Fuzzing

`tests/test_runsave_fuzz.lua` mutates every field of four rich real saves (a busy field with one of
every entity, a leviathan fight in its dive, a storm fight in its telegraph, a warp) in up to 13 hostile
ways each (removed, NaN, infinities, strings, tables, +-1e9, 0, negated, shifted, scaled, lists emptied,
first entry removed or duplicated): about 5,900 mutants. Entity lists mutate one entry per distinct shape.
Each mutant must be rejected, or, if validation lets it through, resume through the real `game:enter`,
play on (40 to 480 frames, enough for a boss pattern to cycle through its states or a warp to run out)
with no error, no NaN or infinity in the world, and a consistent boss and phase. A hang is stopped by
an instruction budget (30M; the heaviest legitimate mutant uses about 1M).

Roughly 77% of mutants are rejected; of the rest, every extreme one and one in six of the ordinary ones
are played (about 560 resumes). `FUZZ_VERBOSE=1 luajit tests/run.lua` prints the tallies,
`FUZZ_TRACE=<text>` the outcome of the mutants whose description contains `<text>`.

Proof the fuzz bites: with each of these validation checks removed, it fails (and for most of them the
unit tests fail too): spawner timers (the original ~666 million pass spawn loop), any enemy entry
accepted, boss pattern fields not required, boss link not checked, warp clock not checked, drone
cooldown slots not checked.
