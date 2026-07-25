# Space Z — Architecture Contract (M0–M1)

> Binding API contract for implementation. Every module listed here MUST expose exactly the API
> documented. Written against **LÖVE 11.5** (LuaJIT / Lua 5.1). See `docs/PLAN.md` for design intent.
> Scope of this contract: milestones **M0 + M1** (core feel + one full roguelite run through Zone 1).

## Global conventions

- **Lua 5.1 / LuaJIT.** No `goto`. Module pattern: `local M = {} ... return M`.
- `require` paths use dots: `require("src.core.pool")`. All requires at top of file.
- **No globals** except `love`. Singletons are modules (require returns the same table).
- Two-space indent. `snake_case` for content ids, `camelCase` for functions/fields, `PascalCase` for module tables.
- **Performance:** no per-frame table allocation in hot loops (pool everything spawned at runtime;
  reuse scratch tables; hoist `local` refs). Target: 60 FPS at ~1000 live entities.
- **Determinism:** all gameplay randomness goes through `world.rng.*` streams (never `math.random`,
  never `love.math.random`). Cosmetic-only randomness (particle jitter, star twinkle) may use `love.math.random`.
- Angles in radians. `rot = 0` means the sprite's authored "up" orientation; rotation is applied clockwise.
- Coordinate system: **virtual screen space**, origin top-left, y grows downward.

## Virtual resolution

- Design space: **VW = 480, VH = 854** (portrait 9:16). Constants live in `src/core/viewport.lua`.
- The window may be any size; the viewport uniformly scales the virtual canvas to fit, centered,
  with black letterbox bars. All game/UI code works purely in virtual coordinates.
- Scrolling is cosmetic: entities live in screen space; the starfield/backdrop scroll downward to
  convey ascent. `world.scrollSpeed = 120` (px/s virtual) baseline; `world.distance` accumulates it.

## Boot & control flow

```
conf.lua          -- window config
main.lua          -- love callbacks, fixed timestep, arg parsing (--test / --smoke)
```

- `conf.lua`: `t.window.title = "Space Z"`, `t.window.width = 480`, `t.window.height = 854`,
  `t.window.resizable = true`, `t.window.vsync = 1`, `t.identity = "space-z"`, `t.version = "11.5"`.
  Disable unused modules (joystick, physics, video) for startup speed.
- `main.lua` responsibilities:
  1. `love.load(args)`: if `args` contains `"--test"` → `require("tests.run").runAll()` then
     `love.event.quit(failures == 0 and 0 or 1)`; print results with `print()`.
     If `args` contains `"--smoke"` → smoke mode (below). Otherwise: build sprite atlas
     (`Sprites.build()`), load save (`Save.load()`), register all five states with the state
     machine, `StateM.switch("menu")`.
  2. **Fixed timestep:** accumulator in `love.update(dt)`; clamp raw `dt` to `0.1`; step
     `STEP = 1/60`; call `StateM.update(STEP)` per step (max 5 steps/frame, drop the rest).
  3. `love.draw()`: `Viewport.apply()` → `StateM.draw()` → `Viewport.unapply()`.
  4. Forward `love.resize(w,h)` → `Viewport.resize`; forward `keypressed`, `mousepressed`,
     `mousemoved`, `mousereleased`, `touchpressed`, `touchmoved`, `touchreleased` to `StateM`
     (translating screen→virtual coords via `Viewport.toVirtual(x, y)` for all pointer events —
     pass virtual coords to states).
  5. **Smoke mode** (`--smoke`): seed fixed (`12345`), settings default, skip menu — go straight to
     `StateM.switch("game", {autopilot = true, seed = 12345})`. Run the simulation at **8× speed**
     (call up to 8 fixed steps per real frame regardless of accumulator). At sim times ~5s, ~40s,
     ~100s and on entering `levelup` / `gameover` states (first time each), capture a screenshot:
     draw one frame to a `love.graphics.newCanvas(480, 854)` via the normal draw path, then
     `canvas:newImageData():encode("png", "smoke_<label>.png")` (lands in the save directory).
     When the run ends (or at sim time 240s, whichever first) write `smoke_report.txt` to the save
     directory: one line per captured screenshot, final sim time, player level, kills, max live
     entity count, whether boss spawned/died, and `RESULT: OK` or `RESULT: <error>`. Then quit.
     Wrap the whole smoke update in `xpcall` so a crash still writes the report with the traceback.
     Also `print()` the report to stdout. Variant **`--smoke god`**: grants a durable strong
     build (beefed ship copy + permanent regen passive + leveled weapons — survives stat
     recomputes) and raises the sim limit so the bot covers **all 7 zones and bosses**,
     capturing `smoke_zoneN.png` / `smoke_bossN.png` per zone. The plain run is the honest
     balance signal; the god run is the coverage harness.

## src/core/

### state.lua — stack state machine (singleton)

```lua
StateM.register(name, stateTable)
StateM.switch(name, params)   -- clears stack, enters state
StateM.push(name, params)     -- overlay (pauses the one below; below still draws if .translucent)
StateM.pop(result)            -- calls resume(result) on the newly exposed state if present
StateM.update(dt)             -- top state only
StateM.draw()                 -- draws from the lowest visible state up: a state with
                              -- .translucent == true lets the state below it draw first
StateM.current()              -- top state table (or nil)
-- input forwarding (top state only, all optional on states):
StateM.keypressed(key) / mousepressed(x,y,button) / mousemoved(x,y,dx,dy) / mousereleased(x,y,button)
StateM.touchpressed(id,x,y) / touchmoved(id,x,y) / touchreleased(id,x,y)
StateM.resize()
```

State table optional callbacks: `enter(params)`, `leave()`, `resume(result)`, `update(dt)`,
`draw()`, plus the input names above. Field `translucent = true` marks overlays.

### viewport.lua

```lua
Viewport.VW, Viewport.VH               -- 480, 854
Viewport.resize(w, h)                  -- recompute scale/offsets (also called once at load)
Viewport.apply() / Viewport.unapply()  -- push/pop the letterboxed transform, draw black bars
Viewport.toVirtual(sx, sy) -> vx, vy   -- screen → virtual coords
```

### rng.lua — deterministic, pure-Lua PRNG (no love.math dependency → testable headless)

```lua
local RNG = require("src.core.rng")
local r = RNG.new(seed)        -- 32-bit LCG or xorshift; deterministic across platforms
r:random() -> [0,1)            -- float
r:random(n) -> 1..n            -- integer
r:random(a, b) -> a..b         -- integer
r:range(a, b) -> [a,b)         -- float
r:chance(p) -> bool            -- p in [0,1]
r:pick(list) -> element
r:shuffle(list)                -- in place, Fisher-Yates
```

### pool.lua

```lua
local Pool = require("src.core.pool")
local p = Pool.new()
p:acquire() -> t     -- reused table, wiped of all keys
p:release(t)
Pool.sweep(list, pool)  -- removes entries with e.dead == true (swap-remove), releasing each
```

### events.lua — per-world event bus (NOT a singleton: `Events.new()`)

```lua
local bus = Events.new()
bus:on(name, fn)
bus:emit(name, a, b, c)
bus:clear()
```

**Event names & payloads** (only these; emit from the module noted):

| event | payload | emitted by |
|---|---|---|
| `enemy_killed` | (enemy) | damage.lua |
| `enemy_hit` | (enemy, dmg, isCrit, x, y) | damage.lua |
| `player_damaged` | (amount, source) | damage.lua |
| `player_died` | () | damage.lua |
| `level_up` | (newLevel) | pickups.lua (xp application) |
| `pickup_collected` | (pickup) | pickups.lua |
| `boss_spawned` | (bossEntity) | spawner.lua |
| `boss_killed` | (bossEntity) | damage.lua |
| `zone_completed` | (zoneIndex) | game.lua |
| `run_ended` | (won:boolean) | game.lua |
| `weapon_fired` | (weaponDef) | weapons.lua (once per volley; game.lua maps to sfx) |
| `boss_pulse` | (bossEntity) | boss.lua (storm gravity pulse; sets world.pulseT) |
| `boss_dash` | (bossEntity) | boss.lua (storm dash arrival) |
| `boss_wall` | (bossEntity) | boss.lua (guardian/overlord bullet wall) |
| `weapon_evolved` | (evolvedDef) | leveling.lua (evolution card applied) |
| `shield_blocked` | (source) | damage.lua (shield capacitor ate a hit) |
| `aoe_blast` | (x, y, radius) | collision.lua (nuclear splash resolved) |

### util.lua

```lua
Util.clamp(v, lo, hi)  Util.lerp(a, b, t)  Util.dist2(x1,y1,x2,y2)  Util.len(x, y)
Util.norm(x, y) -> nx, ny (0,0 safe)      Util.angleTo(x1,y1,x2,y2)
Util.font(size) -> Font                    -- cached love.graphics.newFont(size)
Util.wipe(t)                               -- remove all keys
Util.weightedPick(rng, entries)            -- entries: array of {weight=n, ...}; returns entry
Util.approach(v, target, maxDelta)
Util.printf(fmt, ...)                      -- print(string.format(...))
```

## The world table (owned by src/states/game.lua)

Systems are **stateless modules** operating on a `world` table:

```lua
world = {
  mode = "standard",            -- or "blackhole" (M3; field exists now)
  seed = 12345,
  rng = { spawn = RNG, drops = RNG, cards = RNG, misc = RNG },  -- derived from seed (+1,+2,+3)
  events = Events.new(),
  time = 0, distance = 0, scrollSpeed = 120,
  zoneIndex = 1, zone = <zoneDef>, zoneTime = 0,
  phase = "waves",              -- "waves" | "boss" | "warp" | "over"
  warpT = 0,                    -- countdown while phase == "warp"

  player = <player entity>,
  enemies = {}, bullets = {}, ebullets = {}, pickups = {}, drones = {}, particles = {},
  boss = nil,                   -- also present in enemies list while alive
  pools = { enemies=Pool, bullets=Pool, ebullets=Pool, pickups=Pool, drones=Pool, particles=Pool },
  grid = <collision grid>,

  stats = <computed stats table>,            -- see Leveling.recomputeStats
  weapons = { {def=, level=, cooldown=, ...} },   -- max 6
  passives = { {def=, level=} },                  -- max 6
  level = 1, xp = 0, xpNext = 8, pendingLevelUps = 0,

  kills = 0, bossKills = 0, noDamage = true, stardustEarned = 0,
  shake = 0,                    -- screenshake magnitude (px), decays in game.lua
  arcs = {},                    -- transient beam segments {x1,y1,x2,y2,t,life} for ion arc rendering
  autopilot = false,
}
```

### Entity field conventions (plain pooled tables)

All spawned entities: `x, y, vx, vy, r` (collision radius), `sprite` (atlas quad name), `rot`,
`scale = 1`, `t = 0` (age), `dead = false/nil`, `kind`.

- **player** (not pooled): `kind="player"`, `hp, maxhp, r = 7` (forgiving hitbox; visual is ~34px),
  `invulnT = 0` (i-frames timer, 0.7s after a hit), `sprite = shipDef.sprite`, `shipDef`.
- **enemy**: `kind="enemy"`, `def` (enemyDef), `hp, maxhp, touchDamage, xp, elite, flashT = 0`,
  `fireT` (shooter cooldown), movement scratch: `phase, baseX, spd`. Boss adds `isBoss = true`,
  `bossDef`, `bossPhase = 1`, plus whatever scratch `systems/boss.lua` needs.
- **bullet** (player): `kind="bullet"`, `damage, pierce` (remaining hits), `life` (seconds left),
  `homing` (nil or turn rate rad/s), `target` (enemy ref or nil), `weaponId`.
- **ebullet**: `kind="ebullet"`, `damage, life`.
- **pickup**: `kind="pickup"`, `ptype = "xp"`, `value`, `magnet = false`.
- **drone**: `kind="drone"`, `damage, orbitR, angVel, angle, hitCd = {}`
  (map enemy→cooldown time, wiped periodically).
- **particle**: `kind="particle"`, `life, maxlife, size, drag`, `cr,cg,cb,ca` (color), `additive=true`.

Spawn helpers (in the owning system) must fully initialize every field they read later —
pooled tables come back **empty**.

## src/systems/  (all: `System.update(world, dt)` unless noted)

### movement.lua
Integrates player (input already set `player.vx/vy`), clamps player inside
`x ∈ [20, VW-20], y ∈ [80, VH-30]`. Integrates bullets/ebullets/pickups (plain `x += vx*dt`),
ticks `life`/marks `dead` when expired or > 60px off-screen (bullets) / below screen (enemies,
pickups). Enemy movement patterns by `def.movement`:

- `"drift"`: constant vy (`def.speed`), slow spin, slight vx wobble.
- `"sine"`: vy = speed; `x = baseX + sin(t * 2.2) * 70`.
- `"chaser"`: accelerates toward player at `def.accel` (default 180), max speed `def.speed * 1.6`.
- `"shooter"`: descends to `y = def.holdY or 180`, then holds and strafes (sine on x),
  fires at player every `def.fire.cooldown` (spawns ebullet aimed at player, speed `def.fire.speed`).
- `"lunge"`: descends slowly; every ~2.5s dashes toward player's current position.
- `"ballistic"`: keeps its spawn velocity (asteroids/meteors/ring ice); tumbles at
  `def.spin` rad/s (spin >= 3 → sprite locked to travel direction instead); side-culled
  once past the far edge.

Boss entities are skipped here (handled by boss.lua). Drones handled by weapons.lua.

**Zone environment modifiers** (from `world.zone.modifiers`, applied to the PLAYER here):
`gravity` (px/s constant downward drift — Jupiter), `wind = {amp, period}` (sinusoidal
lateral push — Mars), `playerSpeedMult` (steering feel multiplier — Jupiter). The storm
boss's gravity pulse uses `world.pulseT > 0` → +150 px/s downward (boss.lua sets it,
game.lua decays it).

### collision.lua
Owns the uniform grid (`cell = 64`): exposes `Collision.update(world, dt)` which rebuilds the grid
from live enemies each frame, then resolves:
1. player bullets → enemies (incl. boss): on overlap `Damage.hitEnemy(world, enemy, bullet)`;
   decrement `pierce`, kill bullet when < 0.
2. enemies → player: if overlap and `player.invulnT <= 0` → `Damage.hitPlayer(world, e.touchDamage, e)`.
3. ebullets → player: same, kill the ebullet.
Grid API (internal but reusable): `grid:clear()`, `grid:insert(e)`, `grid:queryCircle(x, y, r, out)`.
Nothing else may keep references into `out` across frames.

### damage.lua  (not an update-loop system; pure functions)
```lua
Damage.hitEnemy(world, enemy, bullet)   -- rolls crit: world.stats.critChance / critMult;
                                        -- dmg = bullet.damage * stats.damageMult (crit multiplies);
                                        -- flashT; emits enemy_hit; on death: dead=true, kills++,
                                        -- emits enemy_killed (and boss_killed if isBoss)
Damage.direct(world, enemy, dmg, canCrit)  -- for drones / ion arc / auras
Damage.hitPlayer(world, amount, source)  -- respects invulnT (sets to 0.7), hp-=, noDamage=false,
                                        -- shake += 6, emits player_damaged; at hp<=0: player_died
```

### spawner.lua
Data-driven from `world.zone.waves` (schema under Content). Each wave entry is an independent
stream: active while `zoneTime ∈ [t, until_]`, spawns `count` enemies every `interval` seconds.
Spawn position: just above the top edge (`y = -30`), x from `world.rng.spawn` within margins
(shooters pick a lane). Difficulty scaling: `hpMult = 1 + 0.5 * (zoneTime / 60)` applied to
enemy hp at spawn (round up). Elites: after `zoneTime > 45`, each spawn has 6% chance
(`rng.spawn`) to be elite → `hp × 4`, `scale × 1.4`, `touchDamage × 1.5`, `xp × 5`, tinted.
When `zoneTime >= zone.duration` and `world.phase == "waves"`: stop streams, wait until live
enemies < 6, then set `world.phase = "boss"`, spawn the boss via `Boss.spawn(world, zone.boss)`,
emit `boss_spawned`.
`Spawner.spawnEnemy(world, enemyId, x, y, opts) -> enemy` is public (boss adds, tests).

### boss.lua
```lua
Boss.spawn(world, bossId) -> entity   -- from content/bosses.lua; inserts into world.enemies, world.boss
Boss.update(world, dt)                -- per-boss behavior keyed on bossDef.behavior
```
All bosses enter from the top to their `arenaY` (invulnerable + harmless while
`entering = true`; damage.lua and collision.lua check the flag), then run a small state
machine; phase 2 triggers at hp < 50% (overlord uses hp thirds instead). One behavior per
zone, all sharing radial/fan/wall/add helpers:

| behavior | zone | signature moves |
|---|---|---|
| `kessler` | LEO | radial debris + aimed fans; P2 sheds drifter adds |
| `leviathan` | Moon | hovers dropping meteors → telegraph → drill-dive at player column |
| `warmachine` | Mars | rotating spiral barrages alternating with aimed 5-fans; P2 dual spiral |
| `titan` | Belt | heavy radial rock bursts + sheds live asteroid adds |
| `storm` | Jupiter | lightning dashes (ring on arrival); every 3rd attack = gravity pulse (`world.pulseT`) |
| `guardian` | Saturn | full-width descending ice walls with dodge gaps + shard fans |
| `overlord` | Void | 3 phases by hp thirds: fans+darts → spiral+radial → walls+dense radial+adds |

On death boss.lua does nothing special (damage.lua emits `boss_killed`).

### weapons.lua
Maintains firing timers for `world.weapons`; spawns bullets/drones; updates drones and homing.
Weapon **behaviors** (from `def.behavior`):
- `"beam"` (laser/death ray): continuous — damage-ticks (`lv.tick`, fireRateMult-scaled) every
  enemy in the vertical column (`lv.width`) above the ship; pushes a per-frame visual into
  `world.beams` (`{x, y2, width, t, life, kind="laser"}`).
- `"rail"` (railgun): cooldown-fired hitscan column, same hit test, `kind="rail"` visual.
- `"pulse"` (graviton/singularity): cooldown-fired radial blast — damage + slow
  (`lv.slowT`, `lv.slowMult`; bosses resist) inside `lv.radius`; pushes `world.pulses`
  (`{x, y, r, t, life}`) for the expanding-ring visual.
- `"aura"` (solar flare): damage-ticks all enemies within `lv.radius` every `lv.tick`;
  declares `world.auraR = max(radius)` each frame (game.lua zeroes it, draws the halo).
Bullets may carry `slowT/slowMult` (cryo: chill on hit) and `aoe` (nuclear: splash radius —
resolved in collision.lua at 60% damage, consumes the bullet, emits `aoe_blast`).
**Evolutions:** base defs carry `evolvesWith` (catalyst passive id) + `evolvesTo` (evolved
weapon id); evolved defs are `evolution = true, maxLevel = 1` and never appear as normal
drafts. leveling.buildOffer GUARANTEES an available evolution a slot (maxed weapon +
catalyst owned + target not owned); apply replaces the base weapon in-slot and emits
`weapon_evolved`. Original behaviors:
- `"forward"`: `count` bullets straight up from ship nose, spread across `spreadDeg` evenly,
  side-by-side x offsets when count > 1.
- `"spread"`: shotgun fan aimed up, `count` bullets across `spreadDeg`, shorter `life`.
- `"homing"`: missile bullets, `homing = turnRad` (≈3.5), pick nearest enemy as `target` at fire
  time; retarget when target dies; slight initial outward angle for feel.
- `"orbital"`: keeps exactly `count` drone entities alive in `world.drones` (create/remove on
  level change), orbiting at `orbitR` with `angVel`; contact damage with 0.5s per-enemy cooldown
  (`Damage.direct`).
- `"arc"`: every cooldown, zap nearest enemy within `range` (LOS ignored): instant
  `Damage.direct`, then chain to up to `chains` nearest other enemies within 120px of the last;
  pushes `{x1,y1,x2,y2,t=0,life=0.15}` segments into `world.arcs` for rendering.
Stats per level come from `def.levels[level]` (table, see Content). Fire cooldown scales by
`1 / stats.fireRateMult`; `count` gets `+ stats.projectileBonus` (forward/spread only);
damage passed to bullets is the raw per-level damage (damageMult applied in damage.lua).

### pickups.lua
Magnet: pickups within `stats.magnetRadius` of player set `magnet=true`, then accelerate toward
player (max speed 700). Collect within 18px: xp pickups add `value * stats.xpMult` to `world.xp`;
while `world.xp >= world.xpNext`: subtract, `level += 1`, `pendingLevelUps += 1`,
`xpNext = math.floor(8 + 6 * (world.level - 1) ^ 1.35)`, emit `level_up`.
Public: `Pickups.dropXp(world, x, y, value)` — merges into gem tiers (value 1/5/25 sprites scale).

### leveling.lua — draft + stats
```lua
Leveling.recomputeStats(world)  -- builds world.stats from ship base + passives:
-- stats = { damageMult=1, fireRateMult=1, projectileBonus=0, critChance=0.05, critMult=2.0,
--           maxhp=100, regen=0, speed=300, magnetRadius=70, xpMult=1 }
-- each passive: stats[def.stat] = base + def.perLevel * level  (additive; mult fields add to the 1)
-- maxhp changes preserve damage taken (keep hp/maxhp delta, don't heal)
Leveling.buildOffer(world) -> offer   -- 3 distinct cards using world.rng.cards:
-- candidates: upgrade owned weapon/passive below maxLevel (weight 10);
--             new weapon if #weapons < 6 (weight 8); new passive if #passives < 6 (weight 8);
--             pool from content/weapons + content/upgrades (ship's starting weapon excluded from "new")
-- fallback when < 3 candidates: {fallback="heal"} (restore 30% maxhp), {fallback="stardust"} (+25)
-- card: { def=, isNew=bool, newLevel=n, fallback=nil|"heal"|"stardust" }
Leveling.apply(world, card)           -- grants it (add/level up, recompute stats, weapon drone sync
                                      -- happens next weapons.update)
Leveling.addWeapon(world, def) / Leveling.addPassive(world, def)  -- used by ship init & apply
```

## src/render/

### sprites.lua — procedural neon atlas (built once at load)
```lua
Sprites.build()                        -- renders all sprites into one canvas atlas (≤1024²)
Sprites.batch() -> SpriteBatch         -- new batch bound to the atlas texture
Sprites.add(batch, name, x, y, rot, scale, r, g, b, a)  -- centered add with setColor; returns nothing
Sprites.info(name) -> {w, h}           -- sprite pixel size
Sprites.image() -> Image/Canvas        -- atlas texture (for raw draws)
Sprites.quad(name) -> Quad
```
Style: neon-vector on transparent: each sprite drawn as bright core stroke (white-ish, ~2px) over
2–3 wider, low-alpha passes of its hue (baked glow). Padding ≥ 4px between cells. **Required
sprite names** (referenced by content/systems):
`ship_pathfinder`, `enemy_drifter`, `enemy_shard`, `enemy_stinger`, `enemy_sentry`,
`boss_kessler_core`, `boss_kessler_node`, `bullet_blaster`, `bullet_missile`, `bullet_flak`,
`bullet_enemy`, `drone`, `pickup_xp1`, `pickup_xp2`, `pickup_xp3`, `star`, `dot` (8px filled
circle w/ soft edge), `glow` (64px radial gradient), `ring` (thin circle outline, 48px).
Ships/enemies point **up** at rot 0. Suggested hues: player cyan `#3ff`, enemies magenta/orange,
xp green, enemy bullets red, drones yellow.

### starfield.lua — instance, owned by game state
```lua
local sf = Starfield.new(rngSeed)
sf:update(dt, scrollSpeed)     -- 3 layers (speed factors .25/.5/1), wrap vertically
sf:draw(batch)                 -- adds `star` quads with per-layer alpha/scale (batch already bound)
sf:drawBackdrop(zoneDef, distance)  -- direct draws (no batch): zone backdrop, e.g. Earth horizon
                                    -- circle that sinks as distance grows; zoneDef.tint colors it
```

### particles.lua — pooled custom particles (in render/ because it's cosmetic; updated by game)
```lua
Particles.update(world, dt)    -- integrate, drag, fade (ca *= ...), mark dead
Particles.draw(world, batch)   -- adds `dot`/`glow` quads (additive batch)
Particles.burst(world, x, y, spec)   -- spec: {n=, speed=, life=, size=, color={r,g,b}, spread=2π}
Particles.explosion(world, x, y, size, color)  -- convenience (ring flash + burst)
Particles.trail(world, x, y, color)            -- 1 engine-trail puff
```
Hard cap: ≤ 600 live particles; `burst` silently truncates. Cosmetic RNG allowed.

### hud.lua
`HUD.draw(world)` — minimal per plan: 3px XP bar across the very top (+ `LV n` right of it),
zone name small-caps top-center (fades after 4s of zone time), boss HP bar (top, 8px, only while
`world.boss` alive), player HP as a thin arc ring around the ship (green→red), kills / distance
tiny in a corner. Also `HUD.drawBanner(world, text)` — big centered neon text (used for
`WARP`, zone intro, `GET READY`).

### cards.lua — draft UI rendering + hit-testing (used by levelup state)
```lua
Cards.layout(offer) -> rects        -- 3 vertical cards centered, virtual coords
Cards.draw(offer, selectedIndex, t) -- neon frames, name, "NEW!"/"LV n" pip row, desc; t for entry anim
Cards.hit(offer, x, y) -> index|nil
```
Card desc comes from `def.desc`; for leveled stats show `def.levelDesc and def.levelDesc[newLevel]`
if present, else desc.

## src/ui/

### input.lua — steering (instance)
```lua
local input = Input.new(settings)   -- settings: { steerMode = "floating"|"absolute" }
input:update(world, dt)             -- sets world.player.vx/vy (movement.lua integrates)
input:keypressed(key) / touchpressed(id,x,y) / touchmoved(id,x,y) / touchreleased(id,x,y)
input:mousepressed(x,y,b) / mousemoved(x,y,dx,dy) / mousereleased(x,y,b)
```
Priority per frame: keyboard (WASD/arrows, normalized, `* stats.speed`) → touch → mouse.
- **Touch floating** (default): anchor at touch start; ship velocity = (finger − anchor) × 3.0
  clamped to `stats.speed * 1.15`; **re-anchor on every new touch without zeroing velocity**;
  slowly re-center anchor toward finger when finger stops (anti-drift, per plan).
- **Touch absolute**: ship eases toward (finger x, finger y − 90) at up to `stats.speed * 1.6`.
- **Mouse** (desktop): held left button drags like absolute mode (button not held → no motion).
- No input → decelerate to rest fast (`Util.approach` vx,vy → 0, 2400 px/s²).

### autopilot.lua — smoke-test bot
`Autopilot.update(world, dt)` — sets player.vx/vy: weave on a sine, bias toward nearest xp pickup,
steer away from nearest enemy/ebullet within 120px. Deterministic (uses `world.rng.misc`).
Used when `world.autopilot`; also auto-picks card 1 is handled by levelup state (below).

## src/states/  (registered in main.lua under these names)

### menu.lua — `"menu"`
Neon title, starfield behind, "TAP / CLICK / SPACE TO LAUNCH", total Stardust from save,
steering-mode toggle hint (`M` key / tap gear: flips setting, persists via Save). Any
launch input → `StateM.switch("game", { mode = "standard" })`.

### game.lua — `"game"` (the hub; owns world creation & orchestration)
`enter(params)`: params `{ mode, seed, autopilot }`. Build world (seed default
`os.time()`), init player from `content/ships.lua` `"pathfinder"` (grants starting weapon via
Leveling), wire event listeners:
- `enemy_killed` → `Pickups.dropXp` at enemy pos (value `enemy.xp`), explosion particles, `shake += 1` (cap 10)
- `enemy_hit` → small spark burst (skip if > 300 particles)
- `player_damaged` → red flash overlay timer, shake
- `player_died` → `world.phase = "over"`, after 1.2s death-pause → `StateM.push("gameover", {won=false, world=world})`
- `boss_killed` → big explosion, `world.phase = "warp"`, `warpT = 2.5`, emit `zone_completed`
`update(dt)` order (exactly):
```
1  time/distance/zoneTime accumulation (zoneTime frozen during "boss" fight? NO — keeps running; boss uses own timers)
2  input:update OR Autopilot.update
3  Movement.update      4  Boss.update       5  Spawner.update (only in phase "waves")
6  Weapons.update       7  Collision.update  8  Pickups.update
9  Particles.update     10 starfield:update  11 arcs aging, shake decay, invulnT/regen tick
12 if pendingLevelUps > 0 and phase ~= "over": consume one → StateM.push("levelup", {world=world})
13 phase "warp": warpT -= dt; at 0 → next zone if exists (reset zoneTime, phase="waves", zone banner)
   or no next zone → phase="over", run won → award stardust, Save, StateM.push("gameover", {won=true, world=world})
```
Run-end accounting (both win & loss paths, exactly once): `stardustEarned =
kills + 5 * math.floor(distance / 1000) + 40 * bossKills`; add into save data
(`data.stardust`), update `data.bestDistance/bestLevel/totalRuns`, persist `noDamage` victory →
`data.unlocked.blackhole = true` (only on won standard runs), `Save.write`.
`draw()` order: starfield backdrop → batch(normal): pickups → **batch(additive)**: stars? NO —
single additive batch for everything glowy is fine on black: order within batch: pickups,
drones, enemies, boss, player (engine trail via particles), bullets, ebullets → draw batch →
arcs as `love.graphics.line` (additive, 2 passes) → particles (own batch add) → damage-flash
overlay → HUD. Screenshake: translate by `rng`-jittered `world.shake` before world drawing,
never applied to HUD. `keypressed "escape"` → push `"pause"`.

### levelup.lua — `"levelup"` (translucent overlay)
`enter({world})`: `offer = Leveling.buildOffer(world)`; dim game 70%; cards animate in (~0.25s).
Input: click/tap on a card, or keys `1/2/3`, ←/→ + space/enter. On pick:
`Leveling.apply(world, card)` → `StateM.pop()`. If `world.autopilot`: auto-pick index 1 after 0.3s.

### pause.lua — `"pause"` (translucent)
"PAUSED" + Resume / Quit-to-menu rows (tap or ↑↓+enter, esc resumes). Quit → run counts as loss
(no stardust award — just `StateM.switch("menu")`).

### gameover.lua — `"gameover"` (translucent over frozen game)
Shows `VICTORY` (won) or `SHIP LOST`; stats rows: zone reached, level, kills, time, distance,
`+N STARDUST`; if this run just unlocked Black Hole → extra secret reveal line. Any input after
0.8s → `StateM.switch("menu")`. Autopilot: auto-continue → quit love after smoke report.

## src/content/ — pure data (no logic beyond tiny format strings)

### ships.lua — map id → def
```lua
pathfinder = { id="pathfinder", name="Pathfinder", sprite="ship_pathfinder",
  maxhp=100, speed=300, startingWeapon="blaster" }
```

### weapons.lua — map id → def. **M1 set:**
| id | behavior | maxLevel | notes |
|---|---|---|---|
| `blaster` | forward | 8 | starter; L1 dmg 8 cd 0.32 count 1 → grows count/dmg/rate |
| `missiles` | homing | 5 | L1 dmg 20 cd 1.6 count 1 speed 260 |
| `flak` | spread | 5 | L1 dmg 6 cd 1.1 count 5 spreadDeg 55 life 0.5 |
| `ion_arc` | arc | 5 | L1 dmg 14 cd 1.4 range 240 chains 1 |
| `drones` | orbital | 5 | L1 dmg 10 count 1 orbitR 60 angVel 2.6 |

```lua
blaster = { id="blaster", name="Blaster", desc="Twin-linked forward cannon.",
  kind="weapon", behavior="forward", sprite="bullet_blaster", maxLevel=8,
  levels = { {damage=8, cooldown=0.32, count=1, speed=520, pierce=0, spreadDeg=0}, ...×8 } }
```
Every `levels[n]` entry is **complete** (no inheritance). Bullet `life` default 1.6 if absent.
Optional evolution fields reserved (unused M1): `evolvesWith`, `evolvesTo`.

### upgrades.lua — passives, map id → def
```lua
crit_systems = { id="crit_systems", name="Critical Systems", kind="passive",
  desc="+5% critical chance per level", stat="critChance", perLevel=0.05, maxLevel=5 }
```
M1 set: `crit_systems` (critChance +0.05), `warhead_yield` (critMult +0.25),
`hull_plating` (maxhp +15), `nanorepair` (regen +0.6), `thrusters` (speed +24),
`reactor_core` (xpMult +0.10), `tractor_beam` (magnetRadius +26), `ammo_feed`
(projectileBonus +1, maxLevel 2, rare: weight 3).
`stat` names MUST match the stats table keys in leveling.lua.

### enemies.lua — map id → def (zone-1 set)
```lua
drifter = { id="drifter", name="Debris Drifter", sprite="enemy_drifter", movement="drift",
  hp=18, speed=70, touchDamage=8, r=14, xp=1, score=10 }
shard   = { sine,    hp=10, speed=110, touchDamage=6,  r=10, xp=1 }
stinger = { chaser,  hp=14, speed=95,  touchDamage=10, r=11, xp=2, accel=200 }
sentry  = { shooter, hp=40, speed=80,  touchDamage=10, r=15, xp=4,
            fire={cooldown=2.4, speed=150, damage=7}, holdY=170 }
```

### bosses.lua
```lua
kessler_swarm = { id="kessler_swarm", name="KESSLER SWARM", behavior="kessler",
  sprite="boss_kessler_core", hp=1400, r=42, touchDamage=20, xpReward=40, scale=1 }
```

### zones.lua — array (order = run order); **M2 ships all seven zones**
```lua
{ id="leo", name="LOW EARTH ORBIT", duration=150, backdrop="earth",
  tint={0.3,0.7,1.0}, boss="kessler_swarm",
  subtitle=nil,                      -- optional environment hint on the intro banner
  modifiers=nil,                     -- optional: {gravity=, wind={amp=,period=}, playerSpeedMult=}
  waves = {
    { t=0, until_=40, enemy="drifter", interval=1.5, count=1 },
    { t=0, until_=150, enemy="ice_shard", interval=1.4, count=1, from="sides" }, -- crossing hazards
    ...
  } }
```
Run order: LEO → Moon (`meteor` showers) → Mars (`wind` dust storms) → Asteroid Belt
(ballistic rocks, incl. side-crossers) → Jupiter (`gravity` + `playerSpeedMult`) →
Saturn's Rings (side-crossing ice) → The Void (hive). After the last zone's boss → victory.
`from="sides"` streams spawn at a screen edge with inward vx (spawner rolls it).
Backdrops (starfield.lua): earth/moon/mars/jupiter/saturn planet limbs that sink over the
zone's first ~100s (zone-relative distance /12000), belt = drifting rock silhouettes,
void = breathing nebula blobs. game.lua passes `distance - world.zoneStartDistance`.
Difficulty: spawner scales enemy hp ×(1 + 0.35·(zoneIndex−1)) and touchDamage
×(1 + 0.1·(zoneIndex−1)) on top of the in-zone time ramp.

## M3 additions (meta layer)

- **Stats** (leveling.recomputeStats) gained `slowBonus` (Coolant: bonus vs slowed),
  `shieldLevel` (Shield Capacitor: blocks a hit, recharge 16−3·level s via `world.shieldT`;
  a blocked hit preserves `noDamage`), `stardustMult` (Refinery). Fold order: base ←
  `ship.bonuses` ← `Tech.bonuses(Save.data())` ← passives (all additive; mult stats onto 1.0).
- **`src/meta/tech.lua`** — Star-Map: 9 nodes (`{id, name, stat, perRank, maxRank, baseCost}`),
  cost = `floor(baseCost · 1.7^(rank))`; ranks in `save.tech`; `Tech.bonuses(data)` folds in.
- **`src/content/ships.lua`** — 8 ships (`Ships.order` = hangar order), each `price` (Stardust),
  base `maxhp/speed`, `startingWeapon`, and a `bonuses` stat table. Owned set:
  `save.unlocked.ships`; active: `save.settings.ship`.
- **`src/meta/achievements.lua`** — 10 defs; lifetime counters in `save.stats`
  (kills/wins/bhWins/stardust, updated by progress.endRun). Live unlocks (veteran/evolved/
  zone-reach) toast via `world.toasts` (`{text, t, life}` drawn by game.lua); the rest are
  evaluated in `Progress.endRun` → `summary.newAchievements` (gameover screen).
- **Black Hole mode:** `save.settings.mode`; menu row (+`B` key) once `unlocked.blackhole`.
  In-run: one-hit death (damage.lua), spawner hp ×1.5, stardust ×2 (progress.lua),
  `save.bestDistanceBH` tracked separately. Winning one → `event_horizon` achievement.
- **States** `"hangar"` (buy/select ships) and `"starmap"` (buy tech) — menu is now a hub
  (LAUNCH / HANGAR / STAR MAP / MODE row). Smoke mode tours menu→hangar→starmap before
  launching, capturing each.

## src/audio/ — fully procedural retro audio (no external assets, all synthesized)

### synth.lua — chiptune DSP (22050 Hz mono 16-bit)
`Synth.render(spec) -> SoundData` — spec is a layer or `{layers={...}}`; each layer:
`{wave="square"|"saw"|"tri"|"sine"|"noise", dur, f0, f1 (exp sweep), vol, duty, attack,
curve (release exponent), vibHz/vibDepth, arp={steps={semis}, rate}, delay, seed}`.
Noise is pitched sample-and-hold (held one wave period). Also `Synth.writeNote(buf, rate,
startSample, dur, freq, wave, vol, duty)` (music voice writer) and `Synth.midiToFreq(m)`.

### audio.lua — SFX registry + playback facade
`Audio.load()` (synthesizes all sounds once), `Audio.play(name, {pitch=, vol=})`.
Per-sound 4-source pools + a 35 ms anti-stack window. Honors `settings.sound`.
Sound names: shoot, missile, flak, zap, hit, boom_s, boom_b, pickup, levelup, confirm,
hurt, death, alarm, warp, jingle_win, jingle_lose, tick, pulse. game.lua maps
`weapon_fired` behaviors → shoot/flak/missile/zap; pickup pitch climbs with rapid chains.

### music.lua — procedural chiptune sequencer
8-bar minor-pentatonic loops, 4 voices (bass square, seeded random-walk lead, noise hats,
kick/snare), one theme per zone (distinct root/tempo/lead wave) + "menu" + "boss".
`Music.play("menu") / Music.play("zone", i) / Music.play("boss", i)`, `Music.stop()`,
`Music.refresh()` (after the sound setting flips). Generated lazily per theme, cached.
game.lua: zone theme on enter/warp, boss theme on `boss_spawned`, stop on death/gameover.

## src/meta/

### lib/json.lua — minimal JSON encode/decode (MIT-style, self-written, no deps)
`json.encode(t) -> s`, `json.decode(s) -> t`. Handles nested tables, arrays vs objects
(consecutive integer keys 1..n → array), strings w/ escapes, numbers, booleans, null→nil.
Errors via `error()` on malformed input.

### save.lua
```lua
Save.load() -> data      -- read "save.json" via love.filesystem (or defaults); validates/migrates
Save.data() -> data      -- cached table (load() memoizes)
Save.write()             -- serialize cached data
Save.reset()
-- defaults: { version=1, stardust=0, totalRuns=0, bestDistance=0, bestLevel=0,
--   unlocked={ blackhole=false }, settings={ steerMode="floating", sound=true } }
```
Headless-safe: if `love.filesystem` is nil (tests), keep data in memory only.

### progress.lua
`Progress.endRun(world, won) -> summary` — computes stardust per the formula in game.lua §,
mutates Save.data(), calls Save.write(), returns `{ stardust=, unlockedBlackhole=bool, ... }`.
(game.lua delegates run-end accounting here; the formula lives HERE only.)

## tests/ — headless, no LÖVE required

`tests/run.lua` exposes `runAll() -> failures` and, when executed directly
(`lua tests/run.lua` with cwd = repo root), runs and `os.exit(failures)`. Tiny harness:
`t.eq(a,b,msg)`, `t.ok(v,msg)`, `t.near(a,b,eps,msg)`; each test file returns
`{ name = fn, ... }`. package.path must include repo root (`package.path = "./?.lua;./?/init.lua;" ...`).
Test files (minimum): `test_rng.lua` (determinism, ranges, shuffle), `test_pool.lua`
(reuse + sweep), `test_damage.lua` (crit math via stubbed stats/rng), `test_leveling.lua`
(stat recompute, offer validity: 3 distinct, respects caps/maxLevel), `test_pickups.lua`
(xp→level curve incl. multi-level), `test_spawner.lua` (wave timeline counts vs simulated time,
seeded determinism), `test_save.lua` (round-trip encode/decode, defaults, corrupt file → defaults),
`test_json.lua`. Tests construct minimal fake worlds (plain tables) — systems must not require
love APIs at module load time (render/* and ui/* excluded from tests; they may use love freely.
`core/util.lua` guards its font cache behind `love ~= nil`).

## Draw/update ownership summary (who calls what)

`main.lua` → StateM → `game.lua` → systems (update) and render modules (draw). Systems never call
`love.graphics`. Render modules never mutate gameplay state (exception: particles list).
Content files never `require` systems. `game.lua` is the only place that wires events to effects.
