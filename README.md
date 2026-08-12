# Space Z

A **2D space-themed roguelite** for phones and PC — a vertical-ascent space shooter where a lone rocket climbs from Earth out through the solar system to the Void, fighting swarms of space monsters and drafting power-ups along the way. Designed to be **simple but deep**: one-thumb controls and auto-fire on the surface, ARPG-style build synergies and evolutions underneath.

## At a glance

| | |
|---|---|
| **Genre** | Vertical-ascent space-shooter roguelite (survivors-like / bullet-heaven) |
| **Platforms** | Android, iOS, PC (Windows/macOS/Linux) |
| **Engine** | [LÖVE (Love2D)](https://love2d.org) 11.x — Lua, open source (zlib) |
| **Art** | Neon-vector, generated procedurally in code (no external art assets) |
| **Controls** | One thumb — 1:1 relative drag from anywhere on screen / mouse or WASD on PC; weapons auto-fire |
| **Modes** | Standard (HP + regen) · **Black Hole** — secret hardcore mode (one-hit death, tankier enemies), unlocked by a flawless no-damage run |

## Status

**Content-complete (M0–M5).** Seven zones with distinct environments (meteor showers,
Mars dust storms, a live asteroid belt, Jupiter's gravity, Saturn's crossing ice, the Void)
each ending in a unique boss; 11 weapons with 8 evolutions and 11 passives; fully
procedural retro audio (synthesized SFX + generative per-zone chiptune); Star-Map tech
tree, 8 unlockable ships, achievements, daily-seed runs, and the secret Black Hole
hardcore mode. Scripted build pipeline for Windows/Android. See
[docs/PROGRESS.md](docs/PROGRESS.md) for live status and open items.

## Download a build

Grab the latest **Android APK**, Windows standalone, or universal `.love` from the
[Releases](https://github.com/subhaneetshrestha/space-z/releases) page — permanent,
public download links, no GitHub account needed.

Every push to `main` runs the tests, builds all three, bumps the patch version and
publishes a new release automatically (put `#minor` or `#major` in the commit message
for a bigger bump). Pull-request builds land in the **Actions** tab → `build` run →
**Artifacts** instead. See
[docs/BUILD.md](docs/BUILD.md#continuous-builds-github-actions) for details.

## Run it

```
# install LÖVE 11.x from https://love2d.org, then from the repo root:
love .               # play (lovec.exe on Windows shows console output)
lua tests/run.lua    # headless logic tests (any Lua 5.1 / LuaJIT)
lovec . --smoke      # autopiloted smoke test + screenshots (add `god` for a full clear)
```

Prebuilt artifacts land in `dist/` (`space-z.love` runs anywhere LÖVE does — including
the Android LÖVE player app; `windows/SpaceZ.exe` is standalone). Build scripts and the
Android/iOS shipping guide live in [docs/BUILD.md](docs/BUILD.md).

Controls: drag anywhere to steer — the ship moves exactly as far as your finger (or the
mouse) does, so you can drag from any corner of the screen and lift and re-place your
thumb without the ship jumping. WASD/arrows also work. `S` toggles sound, `Q` toggles FX
quality. Weapons auto-fire; Esc pauses; pick cards with tap/click or `1/2/3`.

## Documentation

- **[docs/PLAN.md](docs/PLAN.md)** — the full, code-ready specification: gameplay loop, controls & UI, engine rationale, rendering approach, architecture & file layout, full content catalog (ships, weapons, upgrades, evolutions, zones, bosses, meta-progression), milestones M0–M5, testing plan, and cited research.
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — the binding module/API contract (world & entity model, events, content schemas, update/draw order). Keep it in sync with code changes.
- **[docs/PROGRESS.md](docs/PROGRESS.md)** — living status: what's done, how to run/test, known issues, next steps.

## Implementation notes

The spec is **data-driven**: build the core systems once, then express ships / weapons / upgrades / enemies / zones as Lua tables under `src/content/`. Follow the milestones in order (start at **M0 — core feel**), and generate all 2D art procedurally. See `docs/PLAN.md` for details.
