-- tests/test_runsave_entities.lua — the live field in a run save: enemies (this
-- file's first section). Three kinds of test:
--   * behavioural identity: a world and its resumed twin, stepped through the REAL
--     game state, stay equal frame after frame (the "cheat-proof" check);
--   * completeness: every key a live entity ever grows is saved or declared derived;
--   * validation: a hostile entity entry rejects the whole save, never crashes it.
local StateM = require("src.core.state")
local RunSave = require("src.meta.runsave")
local Entities = require("src.meta.runsave_entities")
local Enemies = require("src.content.enemies")
local Weapons = require("src.content.weapons")
local Leveling = require("src.systems.leveling")
local Spawner = require("src.systems.spawner")
local Damage = require("src.systems.damage")
local Pool = require("src.core.pool")
local json = require("lib.json")
local Support = require("tests.support")
local H = require("tests.game_harness")

local T = {}
local test = H.guarded(T)

local STEP = H.STEP

-- Every list the world holds is saved now, so the identity checks compare all of them.
local SKIP = nil

local function roundTrip(run)
  return json.decode(json.encode(run))
end

-- sorted ids, so a fixture is the same on every run
local function idsWhere(pred)
  local ids = {}
  for id, def in pairs(Enemies) do
    if pred(def) then ids[#ids + 1] = id end
  end
  table.sort(ids)
  return ids
end

local function updateGame(n)
  for _ = 1, n or 1 do H.Game:update(STEP) end
end

-- A run with one enemy of each id in `ids` on screen and every weapon silenced, so
-- nothing the player does changes the enemies (bullets are saved from A3 on).
local function arena(ids, opts)
  local w = H.start({ seed = 424 })
  for i = 1, #w.weapons do w.weapons[i].cooldown = 3000 end
  for i, id in ipairs(ids) do
    Spawner.spawnEnemy(w, id, 50 + (i * 53) % 380, 60 + (i * 37) % 160, opts and opts[id])
  end
  return w
end

-- The resumed copy, built by the real game:enter. It lives beside the original
-- (the original is H.Game itself), so both can be stepped with the same call.
local function resumeTwin(run)
  local twin = setmetatable({}, { __index = H.Game })
  twin:enter({ resume = run, seed = run.seed })
  while StateM.current() ~= H.Game do StateM.pop() end -- drop the 3-2-1
  return twin
end

-- Step both for `frames`; returns the frame and path of the first difference.
local function stepBoth(twin, frames)
  for f = 1, frames do
    H.Game:update(STEP)
    twin:update(STEP)
    local d = Support.worldDiff(H.Game.world, twin.world, SKIP)
    if d then return f, d end
  end
end

local function identical(t, w, frames)
  local run = roundTrip(RunSave.snapshot(w))
  local twin = resumeTwin(run)
  t.eq(Support.worldDiff(w, twin.world, SKIP), nil, "the resumed world starts equal")
  local f, d = stepBoth(twin, frames)
  t.eq(d, nil, "diverged at frame " .. tostring(f))
end

-- --------------------------------------------------------- capture / restore

test("snapshot_saves_live_enemies_in_list_order", function(t)
  local w = arena({ "drifter", "sentry", "lunar_hopper" })
  updateGame(40)
  local run = RunSave.snapshot(w)
  t.eq(#run.enemies, #w.enemies)
  for i = 1, #w.enemies do
    t.eq(run.enemies[i].def, w.enemies[i].def.id, "def of " .. i)
    t.eq(run.enemies[i].x, w.enemies[i].x, "x of " .. i)
    t.eq(run.enemies[i].hp, w.enemies[i].hp, "hp of " .. i)
  end
end)

test("snapshot_skips_dead_enemies", function(t)
  local w = arena({ "drifter", "shard", "stinger" })
  w.enemies[2].dead = true
  local run = RunSave.snapshot(w)
  t.eq(#run.enemies, #w.enemies - 1)
  for i = 1, #run.enemies do t.ok(run.enemies[i].def ~= "shard" or w.enemies[2].def.id ~= "shard") end
end)

test("restore_rebuilds_enemies_with_their_def_and_sprite", function(t)
  local w = arena({ "sentry", "lunar_hopper" })
  updateGame(30)
  local twin = resumeTwin(roundTrip(RunSave.snapshot(w)))
  local list = twin.world.enemies
  t.eq(#list, #w.enemies)
  for i = 1, #list do
    t.ok(list[i].def == Enemies[w.enemies[i].def.id], "def is the registry table, not a copy")
    t.eq(list[i].sprite, w.enemies[i].sprite)
    t.eq(list[i].kind, "enemy")
    t.eq(list[i].dead, false)
    t.ok(list[i] ~= w.enemies[i], "a new table")
  end
end)

test("restore_keeps_list_order_after_swap_removals", function(t)
  local w = arena({ "drifter", "shard", "stinger", "sentry", "meteor" })
  w.enemies[2].dead = true
  Pool.sweep(w.enemies, w.pools.enemies) -- swap-remove: the last one jumps into slot 2
  local before = {}
  for i = 1, #w.enemies do before[i] = w.enemies[i].def.id end
  local twin = resumeTwin(roundTrip(RunSave.snapshot(w)))
  for i = 1, #before do
    t.eq(twin.world.enemies[i].def.id, before[i], "slot " .. i)
  end
end)

test("an_elite_and_a_chilled_enemy_keep_their_state", function(t)
  local w = arena({ "drifter", "stinger" }, { drifter = { elite = true } })
  Damage.hitEnemy(w, w.enemies[2], { damage = 0, x = 0, y = 0, slowT = 2, slowMult = 0.4 })
  updateGame(20)
  local twin = resumeTwin(roundTrip(RunSave.snapshot(w)))
  t.eq(twin.world.enemies[1].elite, true)
  t.eq(twin.world.enemies[1].maxhp, w.enemies[1].maxhp, "elite hp pool")
  t.eq(twin.world.enemies[2].slowMult, 0.4)
  t.near(twin.world.enemies[2].slowT, w.enemies[2].slowT, 1e-9)
end)

test("boss_and_warp_phases_still_rewind_with_an_empty_field_until_A5", function(t)
  local w = arena({ "drifter", "shard" })
  w.phase = "boss"
  t.eq(#RunSave.snapshot(w).enemies, 0)
  w.phase = "warp"
  t.eq(#RunSave.snapshot(w).enemies, 0)
end)

test("a_version_1_save_resumes_with_an_empty_field", function(t)
  local w = arena({ "drifter" })
  local run = roundTrip(RunSave.snapshot(w))
  run.version, run.enemies, run.player, run.timers = 1, nil, nil, nil
  for i = 1, #run.weapons do run.weapons[i].cooldown = nil end
  local twin = resumeTwin(run)
  t.eq(#twin.world.enemies, 0)
end)

-- --------------------------------------------------- behavioural identity (2)

local MOVEMENTS = { "drift", "sine", "chaser", "shooter", "lunge", "ballistic" }

for _, movement in ipairs(MOVEMENTS) do
  test("identity_" .. movement .. "_enemies_play_out_the_same_after_a_resume", function(t)
    local ids = idsWhere(function(def) return def.movement == movement end)
    t.ok(#ids >= 1, "fixture: this movement has enemies")
    local w = arena(ids)
    updateGame(170) -- long enough for every pattern to have initialised and moved on
    t.ok(#w.enemies >= #ids, "fixture: they are all still on screen")
    identical(t, w, 600)
  end)
end

test("identity_a_crowded_field_with_elites_and_chilled_enemies", function(t)
  local all = idsWhere(function() return true end)
  local w = arena(all, { drifter = { elite = true }, sentry = { elite = true } })
  Damage.hitEnemy(w, w.enemies[3], { damage = 0, x = 0, y = 0, slowT = 3, slowMult = 0.5 })
  updateGame(150)
  identical(t, w, 600)
end)

test("identity_holds_after_a_long_run_with_the_spawner_and_the_players_weapons", function(t)
  local w = H.start({ seed = 9 })
  updateGame(60 * 25)
  t.ok(#w.enemies > 0, "fixture: enemies are on screen")
  identical(t, w, 300)
end)

-- --------------------------------------------------------------- completeness

test("every_key_a_live_enemy_grows_is_saved_or_derived", function(t)
  local all = idsWhere(function() return true end)
  local w = arena(all, { drifter = { elite = true } })
  for i = 1, #w.weapons do w.weapons[i].cooldown = 0 end -- let the player fight: flashT, slow, kills
  Damage.hitEnemy(w, w.enemies[4], { damage = 0, x = 0, y = 0, slowT = 2, slowMult = 0.5 })
  local unknown = {}
  for _ = 1, 60 * 25 do
    updateGame(1)
    for i = 1, #w.enemies do
      local e = w.enemies[i]
      if not e.dead and not e.isBoss then
        for _, key in ipairs(Entities.unclassifiedEnemyKeys(e)) do unknown[key] = true end
      end
    end
  end
  local names = {}
  for k in pairs(unknown) do names[#names + 1] = k end
  table.sort(names)
  t.eq(table.concat(names, ","), "", "a new enemy field must be saved or listed as derived")
end)

test("the_completeness_check_catches_a_new_field", function(t)
  t.eq(#Entities.unclassifiedEnemyKeys({ x = 1, hp = 2, def = {}, sprite = "s", kind = "enemy", dead = false }), 0)
  local keys = Entities.unclassifiedEnemyKeys({ x = 1, mystery = 3, other = true })
  table.sort(keys)
  t.eq(table.concat(keys, ","), "mystery,other")
end)

-- ---------------------------------------------------------------- validation

local function enemy(def, over)
  local e = {
    def = def or "drifter", x = 100, y = 200, vx = 0, vy = 70, r = 14, rot = 0,
    scale = 1, t = 1.5, hp = 18, maxhp = 18, touchDamage = 8, xp = 1,
    elite = false, flashT = 0,
  }
  for k, v in pairs(over or {}) do e[k] = v end
  return e
end

-- a valid entry per movement type, with the scratch that movement grows
local VALID = {
  drift = enemy("drifter", { phase = 1.2, baseX = 100, spin = 0.9 }),
  sine = enemy("shard", { baseX = 100 }),
  chaser = enemy("stinger", { spd = 152 }),
  shooter = enemy("sentry", { phase = "hold", baseX = 100, fireT = 1.1 }),
  lunge = enemy("lunar_hopper", { phase = "dash", lungeT = 0.3 }),
  ballistic = enemy("meteor", { spin = 4 }),
}

local function runWith(list)
  return Support.validRun2({ enemies = list })
end

for _, movement in ipairs(MOVEMENTS) do
  T["validate_accepts_a_" .. movement .. "_enemy"] = function(t)
    t.eq(RunSave.validate(runWith({ VALID[movement] })), true)
  end
end

function T.validate_accepts_an_enemy_that_has_not_initialised_its_pattern_yet(t)
  for _, def in ipairs({ "drifter", "shard", "stinger", "sentry", "meteor", "lunar_hopper" }) do
    t.eq(RunSave.validate(runWith({ enemy(def) })), true, def)
  end
end

function T.validate_accepts_a_chilled_enemy_whose_timer_ran_just_out(t)
  t.eq(RunSave.validate(runWith({ enemy("drifter", { slowT = -0.01, slowMult = 0.5 }) })), true)
end

function T.validate_accepts_a_version_1_save_with_no_enemies_key(t)
  t.eq(RunSave.validate(Support.validRun()), true)
end

local NAN = 0 / 0

local function with(movement, over)
  local e = {}
  for k, v in pairs(VALID[movement]) do e[k] = v end
  for k, v in pairs(over) do e[k] = v end
  return e
end

local function without(movement, key)
  local e = with(movement, {})
  e[key] = nil
  return e
end

local REJECTS = {
  enemies_missing = function() local r = runWith({}); r.enemies = nil; return r end,
  enemies_wrong_type = function() return runWith(5) end,
  enemies_with_a_gap = function() return runWith({ [1] = enemy(), [3] = enemy() }) end,
  enemies_with_a_named_key = function() return runWith({ boss = enemy() }) end,
  entry_wrong_type = function() return runWith({ "drifter" }) end,
  def_missing = function() return runWith({ without("drift", "def") }) end,
  def_unknown = function() return runWith({ with("drift", { def = "mothership" }) }) end,
  def_is_a_boss = function() return runWith({ with("drift", { def = "kessler" }) }) end,
  def_wrong_type = function() return runWith({ with("drift", { def = 7 }) }) end,
  unknown_key = function() return runWith({ with("drift", { mystery = 1 }) }) end,
  boss_key_on_a_plain_enemy = function() return runWith({ with("drift", { isBoss = true }) }) end,
  sprite_key_is_not_saved = function() return runWith({ with("drift", { sprite = "enemy_drifter" }) }) end,
  x_missing = function() return runWith({ without("drift", "x") }) end,
  x_wrong_type = function() return runWith({ with("drift", { x = "100" }) }) end,
  x_nan = function() return runWith({ with("drift", { x = NAN }) }) end,
  x_infinite = function() return runWith({ with("drift", { x = math.huge }) }) end,
  x_far_off_screen = function() return runWith({ with("drift", { x = 5000 }) }) end,
  y_far_off_screen = function() return runWith({ with("drift", { y = -5000 }) }) end,
  vx_absurd = function() return runWith({ with("drift", { vx = 1e7 }) }) end,
  r_zero = function() return runWith({ with("drift", { r = 0 }) }) end,
  r_huge = function() return runWith({ with("drift", { r = 1e6 }) }) end,
  scale_zero = function() return runWith({ with("drift", { scale = 0 }) }) end,
  scale_huge = function() return runWith({ with("drift", { scale = 1e3 }) }) end,
  t_negative = function() return runWith({ with("drift", { t = -1 }) }) end,
  hp_zero = function() return runWith({ with("drift", { hp = 0 }) }) end,
  hp_negative = function() return runWith({ with("drift", { hp = -3 }) }) end,
  hp_above_max = function() return runWith({ with("drift", { hp = 19 }) }) end,
  hp_nan = function() return runWith({ with("drift", { hp = NAN }) }) end,
  maxhp_zero = function() return runWith({ with("drift", { maxhp = 0, hp = 0 }) }) end,
  touch_damage_negative = function() return runWith({ with("drift", { touchDamage = -1 }) }) end,
  xp_negative = function() return runWith({ with("drift", { xp = -1 }) }) end,
  elite_not_a_boolean = function() return runWith({ with("drift", { elite = 1 }) }) end,
  elite_missing = function() return runWith({ without("drift", "elite") }) end,
  flash_negative = function() return runWith({ with("drift", { flashT = -1 }) }) end,
  slow_timer_huge = function() return runWith({ with("drift", { slowT = 1e9, slowMult = 0.5 }) }) end,
  slow_mult_zero = function() return runWith({ with("drift", { slowT = 1, slowMult = 0 }) }) end,
  slow_mult_above_one = function() return runWith({ with("drift", { slowT = 1, slowMult = 5 }) }) end,
  -- the movement code reads these after a lazy init: a half-initialised entry would
  -- index nil on the first frame after the resume
  drift_scratch_partial = function() return runWith({ without("drift", "spin") }) end,
  drift_phase_is_a_string = function() return runWith({ with("drift", { phase = "hold" }) }) end,
  shooter_hold_without_base_x = function() return runWith({ without("shooter", "baseX") }) end,
  shooter_hold_without_fire_timer = function() return runWith({ without("shooter", "fireT") }) end,
  shooter_phase_unknown = function() return runWith({ with("shooter", { phase = "dash" }) }) end,
  shooter_phase_is_a_number = function() return runWith({ with("shooter", { phase = 3 }) }) end,
  shooter_fire_timer_runaway = function() return runWith({ with("shooter", { fireT = 1e9 }) }) end,
  shooter_fire_timer_far_negative = function() return runWith({ with("shooter", { fireT = -1e9 }) }) end,
  lunge_without_its_timer = function() return runWith({ without("lunge", "lungeT") }) end,
  lunge_phase_unknown = function() return runWith({ with("lunge", { phase = "hold" }) }) end,
  lunge_timer_runaway = function() return runWith({ with("lunge", { lungeT = 1e9 }) }) end,
  chaser_speed_zero = function() return runWith({ with("chaser", { spd = 0 }) }) end,
  ballistic_spin_absurd = function() return runWith({ with("ballistic", { spin = 1e9 }) }) end,
  scratch_of_another_movement = function() return runWith({ with("drift", { fireT = 1 }) }) end,
  too_many_enemies = function()
    local list = {}
    for i = 1, Entities.MAX_ENEMIES + 1 do list[i] = enemy() end
    return runWith(list)
  end,
}

for name, build in pairs(REJECTS) do
  T["validate_rejects_" .. name] = function(t)
    t.eq(RunSave.validate(build()), false, name)
  end
end

function T.validate_accepts_exactly_the_enemy_cap(t)
  local list = {}
  for i = 1, Entities.MAX_ENEMIES do list[i] = enemy() end
  t.eq(RunSave.validate(runWith(list)), true)
end

function T.validate_never_throws_on_hostile_enemy_entries(t)
  local hostile = { { {} }, { 5 }, { { def = {} } }, { { def = "drifter" } },
    { { def = "drifter", x = {} } }, { enemy("drifter", { phase = {} }) }, { false } }
  for i = 1, #hostile do
    local ok, result = pcall(RunSave.validate, runWith(hostile[i]))
    t.ok(ok, "case " .. i .. " must not throw")
    t.eq(result, false, "case " .. i)
  end
end

-- ============================================================ bullets (A3)
-- Player bullets (with a homing missile's target) and enemy bullets.

-- Enemies that take hits but never die: kills drop pickups, which are not saved until
-- A4, and collecting them would change the xp. Wraps Spawner.spawnEnemy, which the
-- spawner and the boss adds call through the module table, so every enemy is covered.
local function withDurableEnemies(fn)
  local original = Spawner.spawnEnemy
  Spawner.spawnEnemy = function(...)
    local e = original(...)
    e.hp, e.maxhp = 1e8, 1e8
    return e
  end
  local ok, err = pcall(fn)
  Spawner.spawnEnemy = original
  if not ok then error(err, 0) end
end

-- A run with the extra weapons, targets right above the ship, and 10 s of fighting.
local function firefight(weaponIds, seed)
  local w = H.start({ seed = seed or 515 })
  for _, id in ipairs(weaponIds) do Leveling.addWeapon(w, Weapons[id]) end
  for i = 1, #w.weapons do w.weapons[i].level = w.weapons[i].def.maxLevel end
  Leveling.recomputeStats(w)
  for i = 0, 5 do
    Spawner.spawnEnemy(w, i % 2 == 0 and "drifter" or "stinger", 190 + i * 20, 90 + i * 12)
  end
  updateGame(600)
  return w
end

local function damaged(w)
  for i = 1, #w.enemies do
    if w.enemies[i].hp < w.enemies[i].maxhp then return true end
  end
  return false
end

local function indexOf(list, item)
  for i = 1, #list do if list[i] == item then return i end end
end

-- keep playing until pred() holds (or `limit` frames pass)
local function stepUntil(pred, limit)
  for _ = 1, limit or 900 do
    if pred() then return true end
    updateGame(1)
  end
  return pred()
end

-- homing missiles in flight that have a live enemy locked on
local function lockedMissiles(w)
  local n = 0
  for i = 1, #w.bullets do
    local b = w.bullets[i]
    if b.homing and b.target and indexOf(w.enemies, b.target) then n = n + 1 end
  end
  return n
end

-- Per scenario: the weapons to add, and the bullet that must be in flight at the
-- snapshot (`flying` is its weapon id, `field` the part of it being proven: the chill
-- of a cryo shard, the splash of a nuclear missile). Immortal enemies soak bullets up
-- the moment they are fired, so the fixture waits for that bullet instead of hoping
-- one is in the air at a fixed frame.
local BULLET_WEAPONS = {
  forward_spread_and_cryo = { weapons = { "flak", "cryo" }, flying = "cryo", field = "slowT" },
  homing_missiles = { weapons = { "missiles" }, flying = "missiles", field = "homing" },
  evolved_forward = { weapons = { "plasma_storm" }, flying = "plasma_storm" },
  evolved_homing_with_splash = { weapons = { "nuclear_barrage" }, flying = "nuclear_barrage", field = "aoe" },
  evolved_spread = { weapons = { "buckshot_nova" }, flying = "buckshot_nova" },
  evolved_cryo = { weapons = { "absolute_zero" }, flying = "absolute_zero", field = "slowT" },
}

local function flying(w, spec)
  for i = 1, #w.bullets do
    local b = w.bullets[i]
    if b.weaponId == spec.flying and (not spec.field or b[spec.field]) then return true end
  end
  return false
end

-- the fight, then play on until the bullet under test is in the air
local function fightUntilFlying(t, spec)
  local w = firefight(spec.weapons)
  t.ok(stepUntil(function() return flying(w, spec) end, 1800),
    "fixture: a " .. spec.flying .. " bullet is in flight")
  return w
end

-- An enemy just ahead of each bullet in flight, so the first frames after the resume
-- are hits: that is what makes a lost chill, splash or pierce count show up.
local function ambush(w)
  local placed = {}
  for i = 1, math.min(#w.bullets, 12) do
    local b = w.bullets[i]
    placed[#placed + 1] = Spawner.spawnEnemy(w, "drifter", b.x + b.vx * 0.03, b.y + b.vy * 0.03)
  end
  return placed
end

for name, spec in pairs(BULLET_WEAPONS) do
  test("identity_bullets_" .. name .. "_keep_flying_and_hitting_after_a_resume", function(t)
    withDurableEnemies(function()
      local w = fightUntilFlying(t, spec)
      t.ok(damaged(w), "fixture: the bullets have been hitting something")
      identical(t, w, 600)
    end)
  end)

  test("identity_bullets_" .. name .. "_land_their_hits_on_the_first_frames_after_a_resume", function(t)
    withDurableEnemies(function()
      local w = fightUntilFlying(t, spec)
      local placed = ambush(w)
      identical(t, w, 120)
      local hit = false
      for i = 1, #placed do
        if placed[i].hp < placed[i].maxhp then hit = true end
      end
      t.ok(hit, "fixture: the ambush produced hits to compare")
    end)
  end)
end

test("identity_enemy_bullets_from_shooters_keep_flying_after_a_resume", function(t)
  local w = arena({ "sentry", "war_drone", "volt_sentinel", "hive_spitter" })
  updateGame(400)
  t.ok(#w.ebullets > 0, "fixture: enemy bullets are in flight")
  identical(t, w, 600)
end)

test("a_bullet_one_frame_from_the_player_still_hits_when_it_resumes", function(t)
  local w = arena({ "sentry" })
  w.player.invulnT = 0
  local hp = w.player.hp
  -- an enemy bullet just above the ship, moving down at 300 px/s: it touches next frame
  local b = w.pools.ebullets:acquire()
  b.kind, b.x, b.y, b.vx, b.vy, b.r = "ebullet", w.player.x, w.player.y - 6, 0, 300, 6
  b.sprite, b.rot, b.scale, b.t, b.dead, b.damage, b.life = "bullet_enemy", 0, 1, 0, false, 9, 5
  w.ebullets[#w.ebullets + 1] = b
  local twin = resumeTwin(roundTrip(RunSave.snapshot(w)))
  t.eq(#twin.world.ebullets, #w.ebullets, "the bullet came along")
  twin:update(STEP)
  t.eq(twin.world.player.hp, hp - 9, "the hit lands on the first frame after the resume")
end)

-- ---------------------------------------------------------- capture / restore

test("snapshot_saves_player_and_enemy_bullets_in_list_order", function(t)
  local w
  withDurableEnemies(function() w = firefight({ "flak" }) end)
  local run = RunSave.snapshot(w)
  t.eq(#run.bullets, #w.bullets)
  t.eq(#run.ebullets, #w.ebullets)
  t.ok(#run.bullets > 0, "fixture")
  for i = 1, #w.bullets do
    t.eq(run.bullets[i].weaponId, w.bullets[i].weaponId, "weapon of " .. i)
    t.eq(run.bullets[i].x, w.bullets[i].x, "x of " .. i)
    t.eq(run.bullets[i].pierce, w.bullets[i].pierce, "pierce of " .. i)
  end
end)

test("restore_rebuilds_bullets_with_the_sprite_of_their_weapon", function(t)
  local w
  withDurableEnemies(function() w = firefight({ "missiles", "cryo" }) end)
  local twin = resumeTwin(roundTrip(RunSave.snapshot(w)))
  t.eq(#twin.world.bullets, #w.bullets)
  for i = 1, #w.bullets do
    local b = twin.world.bullets[i]
    t.eq(b.kind, "bullet")
    t.eq(b.dead, false)
    t.eq(b.sprite, w.bullets[i].sprite, "sprite of " .. i)
    t.ok(b ~= w.bullets[i], "a new table")
  end
  for i = 1, #w.ebullets do t.eq(twin.world.ebullets[i].sprite, "bullet_enemy") end
end)

test("a_missile_keeps_chasing_the_enemy_it_was_chasing", function(t)
  local w
  withDurableEnemies(function()
    w = firefight({ "missiles" })
    t.ok(stepUntil(function() return lockedMissiles(w) >= 1 end), "fixture: a missile has a live target")
  end)
  local twin = resumeTwin(roundTrip(RunSave.snapshot(w)))
  for i = 1, #w.bullets do
    local b, saved = w.bullets[i], twin.world.bullets[i]
    local idx = b.target and indexOf(w.enemies, b.target)
    if idx then
      t.ok(saved.target == twin.world.enemies[idx],
        "missile " .. i .. " is linked to the restored enemy, not to a copy or a stale table")
    end
  end
end)

test("identity_a_missile_locked_on_a_far_enemy_still_chases_it_after_a_resume", function(t)
  local w
  withDurableEnemies(function()
    w = firefight({ "missiles" })
    t.ok(stepUntil(function() return lockedMissiles(w) >= 2 end), "fixture: two locked missiles")
    -- lock every missile onto the enemy farthest from it. A save that dropped the lock
    -- would send each one to the nearest enemy instead, and the paths would split.
    for i = 1, #w.bullets do
      local b = w.bullets[i]
      if b.homing then
        local far, farD = nil, -1
        for j = 1, #w.enemies do
          local e = w.enemies[j]
          local d = (e.x - b.x) ^ 2 + (e.y - b.y) ^ 2
          if not e.dead and d > farD then far, farD = e, d end
        end
        b.target = far
      end
    end
    identical(t, w, 90)
  end)
end)

test("a_target_that_is_dead_or_gone_is_saved_as_no_target", function(t)
  local w
  withDurableEnemies(function()
    w = firefight({ "missiles" })
    local function homingCount()
      local n = 0
      for i = 1, #w.bullets do if w.bullets[i].homing then n = n + 1 end end
      return n
    end
    t.ok(stepUntil(function() return homingCount() >= 2 end), "fixture: two homing missiles")
  end)
  local homing = {}
  for i = 1, #w.bullets do if w.bullets[i].homing then homing[#homing + 1] = i end end
  w.bullets[homing[1]].target = { kind = "enemy", dead = true }  -- killed, not swept yet
  w.bullets[homing[2]].target = {}                                -- swept: a wiped pool table
  local run = RunSave.snapshot(w)
  t.eq(run.bullets[homing[1]].target, nil, "dead target: it retargets, as the original does")
  t.eq(run.bullets[homing[2]].target, nil, "wiped target")
end)

test("a_target_table_recycled_into_a_new_enemy_stays_that_enemy", function(t)
  local w
  withDurableEnemies(function()
    w = firefight({ "missiles" })
    t.ok(stepUntil(function() return lockedMissiles(w) >= 1 end), "fixture: a homing missile")
  end)
  local i = 1
  while not w.bullets[i].homing do i = i + 1 end
  -- the original's quirk: a pooled table reused for a new enemy is still "an enemy"
  w.bullets[i].target = w.enemies[#w.enemies]
  local run = RunSave.snapshot(w)
  t.eq(run.bullets[i].target, #run.enemies, "saved as that enemy's slot")
end)

test("boss_and_warp_phases_still_rewind_with_no_bullets_until_A5", function(t)
  local w = arena({ "sentry" })
  updateGame(400)
  w.phase = "boss"
  t.eq(#RunSave.snapshot(w).ebullets, 0)
  t.eq(#RunSave.snapshot(w).bullets, 0)
end)

-- ------------------------------------------------------------- completeness

test("every_key_a_live_bullet_grows_is_saved_or_derived", function(t)
  withDurableEnemies(function()
    local w = firefight({ "flak", "cryo", "missiles", "nuclear_barrage" })
    local unknown = {}
    for _ = 1, 60 * 12 do
      updateGame(1)
      for i = 1, #w.bullets do
        for _, k in ipairs(Entities.unclassifiedBulletKeys(w.bullets[i])) do unknown["bullet." .. k] = true end
      end
      for i = 1, #w.ebullets do
        for _, k in ipairs(Entities.unclassifiedEbulletKeys(w.ebullets[i])) do unknown["ebullet." .. k] = true end
      end
    end
    local names = {}
    for k in pairs(unknown) do names[#names + 1] = k end
    table.sort(names)
    t.eq(table.concat(names, ","), "", "a new bullet field must be saved or listed as derived")
  end)
end)

test("the_bullet_completeness_check_catches_a_new_field", function(t)
  t.eq(#Entities.unclassifiedBulletKeys({ x = 1, damage = 2, kind = "bullet", sprite = "s", dead = false,
    weaponId = "blaster", target = {}, homing = 3 }), 0)
  t.eq(Entities.unclassifiedBulletKeys({ x = 1, mystery = 3 })[1], "mystery")
  t.eq(#Entities.unclassifiedEbulletKeys({ x = 1, life = 2, kind = "ebullet", sprite = "s", dead = false }), 0)
  t.eq(Entities.unclassifiedEbulletKeys({ x = 1, mystery = 3 })[1], "mystery")
end)

-- ---------------------------------------------------------------- validation

local function bullet(over)
  local b = {
    weaponId = "blaster", x = 240, y = 300, vx = 0, vy = -600, r = 5, rot = 0,
    scale = 1, t = 0.2, damage = 10, pierce = 0, life = 1.4,
  }
  for k, v in pairs(over or {}) do b[k] = v end
  return b
end

local function ebullet(over)
  local b = { x = 240, y = 100, vx = 0, vy = 150, r = 6, rot = 0, scale = 1, t = 0.5, damage = 10, life = 8 }
  for k, v in pairs(over or {}) do b[k] = v end
  return b
end

local function runWithBullets(bullets, ebullets, enemies)
  return Support.validRun2({
    bullets = bullets or {}, ebullets = ebullets or {}, enemies = enemies or {},
  })
end

function T.validate_accepts_player_and_enemy_bullets(t)
  t.eq(RunSave.validate(runWithBullets({ bullet() }, { ebullet() })), true)
end

function T.validate_accepts_a_homing_missile_with_and_without_a_target(t)
  local live = { VALID.drift }
  local m = bullet({ weaponId = "missiles", r = 6, homing = 3.5, target = 1 })
  t.eq(RunSave.validate(runWithBullets({ m }, {}, live)), true, "with a live target")
  m.target = nil
  t.eq(RunSave.validate(runWithBullets({ m }, {}, live)), true, "retargeting next frame")
end

function T.validate_accepts_cryo_and_nuclear_bullet_extras(t)
  local b = bullet({ weaponId = "cryo", slowT = 1.5, slowMult = 0.5, pierce = 2 })
  local n = bullet({ weaponId = "nuclear_barrage", homing = 3.5, aoe = 90 })
  t.eq(RunSave.validate(runWithBullets({ b, n })), true)
end

function T.validate_accepts_a_version_1_save_with_no_bullet_keys(t)
  t.eq(RunSave.validate(Support.validRun()), true)
end

local BULLET_REJECTS = {
  bullets_missing = function() local r = runWithBullets(); r.bullets = nil; return r end,
  bullets_wrong_type = function() return runWithBullets(5) end,
  bullets_with_a_gap = function() return runWithBullets({ [1] = bullet(), [3] = bullet() }) end,
  ebullets_missing = function() local r = runWithBullets(); r.ebullets = nil; return r end,
  ebullets_wrong_type = function() return runWithBullets({}, "x") end,
  entry_wrong_type = function() return runWithBullets({ "blaster" }) end,
  weapon_missing = function() local b = bullet(); b.weaponId = nil; return runWithBullets({ b }) end,
  weapon_unknown = function() return runWithBullets({ bullet({ weaponId = "bfg" }) }) end,
  weapon_makes_no_bullets = function() return runWithBullets({ bullet({ weaponId = "laser" }) }) end,
  weapon_is_a_passive = function() return runWithBullets({ bullet({ weaponId = "ammo_feed" }) }) end,
  weapon_wrong_type = function() return runWithBullets({ bullet({ weaponId = 3 }) }) end,
  unknown_key = function() return runWithBullets({ bullet({ mystery = 1 }) }) end,
  sprite_is_not_saved = function() return runWithBullets({ bullet({ sprite = "bullet_blaster" }) }) end,
  x_nan = function() return runWithBullets({ bullet({ x = NAN }) }) end,
  x_far_off_screen = function() return runWithBullets({ bullet({ x = 9000 }) }) end,
  y_missing = function() local b = bullet(); b.y = nil; return runWithBullets({ b }) end,
  vy_absurd = function() return runWithBullets({ bullet({ vy = 1e7 }) }) end,
  r_zero = function() return runWithBullets({ bullet({ r = 0 }) }) end,
  damage_negative = function() return runWithBullets({ bullet({ damage = -1 }) }) end,
  damage_nan = function() return runWithBullets({ bullet({ damage = NAN }) }) end,
  pierce_negative = function() return runWithBullets({ bullet({ pierce = -1 }) }) end,
  pierce_fractional = function() return runWithBullets({ bullet({ pierce = 0.5 }) }) end,
  pierce_huge = function() return runWithBullets({ bullet({ pierce = 1e6 }) }) end,
  life_zero = function() return runWithBullets({ bullet({ life = 0 }) }) end,
  life_runaway = function() return runWithBullets({ bullet({ life = 1e9 }) }) end,
  t_negative = function() return runWithBullets({ bullet({ t = -1 }) }) end,
  aoe_negative = function() return runWithBullets({ bullet({ weaponId = "nuclear_barrage", homing = 3.5, aoe = -5 }) }) end,
  slow_mult_zero = function() return runWithBullets({ bullet({ slowT = 1, slowMult = 0 }) }) end,
  slow_timer_huge = function() return runWithBullets({ bullet({ slowT = 1e9, slowMult = 0.5 }) }) end,
  -- steering reads `homing` and `target`: a bullet that does not match its weapon
  homing_on_a_straight_bullet = function() return runWithBullets({ bullet({ homing = 3.5 }) }) end,
  missile_without_homing = function() return runWithBullets({ bullet({ weaponId = "missiles", r = 6 }) }) end,
  homing_turn_rate_zero = function() return runWithBullets({ bullet({ weaponId = "missiles", homing = 0 }) }) end,
  homing_turn_rate_absurd = function() return runWithBullets({ bullet({ weaponId = "missiles", homing = 1e6 }) }) end,
  target_on_a_straight_bullet = function() return runWithBullets({ bullet({ target = 1 }) }, {}, { VALID.drift }) end,
  target_beyond_the_enemies = function()
    return runWithBullets({ bullet({ weaponId = "missiles", homing = 3.5, target = 2 }) }, {}, { VALID.drift })
  end,
  target_with_no_enemies = function()
    return runWithBullets({ bullet({ weaponId = "missiles", homing = 3.5, target = 1 }) })
  end,
  target_zero = function()
    return runWithBullets({ bullet({ weaponId = "missiles", homing = 3.5, target = 0 }) }, {}, { VALID.drift })
  end,
  target_fractional = function()
    return runWithBullets({ bullet({ weaponId = "missiles", homing = 3.5, target = 1.5 }) }, {}, { VALID.drift })
  end,
  target_wrong_type = function()
    return runWithBullets({ bullet({ weaponId = "missiles", homing = 3.5, target = "1" }) }, {}, { VALID.drift })
  end,
  too_many_bullets = function()
    local list = {}
    for i = 1, Entities.MAX_BULLETS + 1 do list[i] = bullet() end
    return runWithBullets(list)
  end,
  ebullet_entry_wrong_type = function() return runWithBullets({}, { 5 }) end,
  ebullet_x_nan = function() return runWithBullets({}, { ebullet({ x = NAN }) }) end,
  ebullet_life_zero = function() return runWithBullets({}, { ebullet({ life = 0 }) }) end,
  ebullet_life_runaway = function() return runWithBullets({}, { ebullet({ life = 1e9 }) }) end,
  ebullet_damage_negative = function() return runWithBullets({}, { ebullet({ damage = -2 }) }) end,
  ebullet_unknown_key = function() return runWithBullets({}, { ebullet({ homing = 3 }) }) end,
  ebullet_speed_absurd = function() return runWithBullets({}, { ebullet({ vx = 1e8 }) }) end,
  too_many_ebullets = function()
    local list = {}
    for i = 1, Entities.MAX_EBULLETS + 1 do list[i] = ebullet() end
    return runWithBullets({}, list)
  end,
}

for name, build in pairs(BULLET_REJECTS) do
  T["validate_rejects_" .. name] = function(t)
    t.eq(RunSave.validate(build()), false, name)
  end
end

function T.validate_accepts_exactly_the_bullet_caps(t)
  local a, b = {}, {}
  for i = 1, Entities.MAX_BULLETS do a[i] = bullet() end
  for i = 1, Entities.MAX_EBULLETS do b[i] = ebullet() end
  t.eq(RunSave.validate(runWithBullets(a, b)), true)
end

function T.validate_never_throws_on_hostile_bullet_entries(t)
  local hostile = { { {} }, { 5 }, { { weaponId = {} } }, { { weaponId = "blaster" } },
    { bullet({ x = {} }) }, { bullet({ target = {} }) }, { false } }
  for i = 1, #hostile do
    local ok, result = pcall(RunSave.validate, runWithBullets(hostile[i], hostile[i]))
    t.ok(ok, "case " .. i .. " must not throw")
    t.eq(result, false, "case " .. i)
  end
end

-- ================================================== pickups and drones (A4)
-- XP gems on the field, and the orbiting drones with the hit cooldowns they keep per
-- enemy (saved as slots in the enemy list, like a missile's target).

local Pickups = require("src.systems.pickups")
local WeaponSystem = require("src.systems.weapons")

local function dropGems(w)
  local p = w.player
  Pickups.dropXp(w, p.x + 150, p.y - 260, 1)   -- far: drifts down, tier 1
  Pickups.dropXp(w, p.x - 150, p.y - 300, 7)   -- tier 2
  Pickups.dropXp(w, p.x + 40, p.y - 30, 30)    -- tier 3, inside the magnet radius (70 px)
  Pickups.dropXp(w, p.x - 25, p.y - 20, 2)     -- inside the magnet radius
end

-- weapons silenced, no enemies of its own: only the gems move
local function gemField()
  local w = arena({})
  dropGems(w)
  return w
end

test("snapshot_saves_pickups_in_list_order_and_skips_dead_ones", function(t)
  local w = gemField()
  w.pickups[2].dead = true
  updateGame(20)
  local run = RunSave.snapshot(w)
  local live = {}
  for i = 1, #w.pickups do if not w.pickups[i].dead then live[#live + 1] = w.pickups[i] end end
  t.eq(#run.pickups, #live)
  for i = 1, #live do
    t.eq(run.pickups[i].value, live[i].value, "value of " .. i)
    t.eq(run.pickups[i].x, live[i].x, "x of " .. i)
    t.eq(run.pickups[i].magnet, live[i].magnet, "magnet of " .. i)
    t.eq(run.pickups[i].ptype, "xp")
  end
end)

test("restore_rebuilds_gems_with_the_sprite_of_their_tier", function(t)
  local w = gemField()
  Pickups.dropXp(w, 100, 100, 130)
  local twin = resumeTwin(roundTrip(RunSave.snapshot(w)))
  t.eq(#twin.world.pickups, #w.pickups)
  for i = 1, #w.pickups do
    local p = twin.world.pickups[i]
    t.eq(p.sprite, w.pickups[i].sprite, "sprite of " .. i)
    t.eq(p.sprite, Pickups.tierSprite(p.value))
    t.eq(p.kind, "pickup")
    t.eq(p.dead, false)
  end
end)

test("identity_gems_keep_drifting_get_pulled_in_and_collected_after_a_resume", function(t)
  local w = gemField()
  updateGame(4) -- the near gems are locked on and accelerating, not yet collected
  local pulled = false
  for i = 1, #w.pickups do if w.pickups[i].magnet then pulled = true end end
  t.ok(pulled, "fixture: a gem is being pulled toward the ship")
  local xp, level = w.xp, w.level
  identical(t, w, 300)
  t.ok(w.xp ~= xp or w.level ~= level, "fixture: gems were collected, so the xp is part of the comparison")
end)

local DRONE_WEAPONS = {
  orbital_drones = "drones",
  evolved_constellation = "battle_constellation",
}

-- Drones, with enemies on the ring they sweep so they hit something right away.
local function droneField(weaponId)
  local w = H.start({ seed = 616 })
  for i = 1, #w.weapons do w.weapons[i].cooldown = 3000 end -- only the drones act
  Leveling.addWeapon(w, Weapons[weaponId])
  local drones = w.weapons[#w.weapons]
  drones.level = drones.def.maxLevel
  Leveling.recomputeStats(w)
  local R = drones.def.levels[drones.level].orbitR
  for i = 0, 7 do
    local a = i * math.pi / 4
    Spawner.spawnEnemy(w, "drifter", w.player.x + math.cos(a) * R, w.player.y + math.sin(a) * R)
  end
  return w
end

local function coolingDown(w)
  for i = 1, #w.drones do
    for enemy, expiry in pairs(w.drones[i].hitCd) do
      if not enemy.dead and expiry > w.time then return true end
    end
  end
  return false
end

for name, weaponId in pairs(DRONE_WEAPONS) do
  test("identity_" .. name .. "_keep_orbiting_and_do_not_re_hit_a_cooling_enemy", function(t)
    withDurableEnemies(function()
      local w = droneField(weaponId)
      t.ok(stepUntil(function() return #w.drones > 0 and coolingDown(w) end, 600),
        "fixture: a drone has just hit an enemy and is cooling down on it")
      identical(t, w, 240)
    end)
  end)
end

test("restore_rebuilds_drones_and_links_their_cooldowns_to_the_restored_enemies", function(t)
  local w
  withDurableEnemies(function()
    w = droneField("drones")
    t.ok(stepUntil(function() return #w.drones > 0 and coolingDown(w) end, 600), "fixture")
  end)
  local run = roundTrip(RunSave.snapshot(w))
  local twin = resumeTwin(run)
  t.eq(#twin.world.drones, #w.drones)
  local checked = 0
  for i = 1, #w.drones do
    local d, restored = w.drones[i], twin.world.drones[i]
    t.eq(restored.kind, "drone")
    t.eq(restored.sprite, "drone")
    t.near(restored.angle, d.angle, 1e-12, "orbit angle of " .. i)
    for enemy, expiry in pairs(d.hitCd) do
      local slot = indexOf(w.enemies, enemy)
      if slot and expiry > w.time then
        checked = checked + 1
        t.eq(restored.hitCd[twin.world.enemies[slot]], expiry,
          "drone " .. i .. " is still cooling down on the restored enemy " .. slot)
      end
    end
  end
  t.ok(checked > 0, "fixture: there were cooldowns to check")
end)

test("expired_drone_cooldowns_are_not_saved", function(t)
  local w
  withDurableEnemies(function()
    w = droneField("drones")
    t.ok(stepUntil(function() return #w.drones > 0 and coolingDown(w) end, 600), "fixture")
  end)
  for _, d in ipairs(w.drones) do
    for enemy in pairs(d.hitCd) do d.hitCd[enemy] = w.time - 1 end -- all expired
  end
  local run = RunSave.snapshot(w)
  for i = 1, #run.drones do t.eq(#run.drones[i].hitCd, 0, "drone " .. i) end
end)

test("boss_and_warp_phases_still_rewind_with_no_pickups_or_drones_until_A5", function(t)
  local w = gemField()
  w.phase = "boss"
  t.eq(#RunSave.snapshot(w).pickups, 0)
  t.eq(#RunSave.snapshot(w).drones, 0)
end)

test("a_version_1_save_resumes_with_no_gems_or_drones", function(t)
  local w = gemField()
  local run = roundTrip(RunSave.snapshot(w))
  run.version, run.enemies, run.bullets, run.ebullets = 1, nil, nil, nil
  run.pickups, run.drones, run.player, run.timers = nil, nil, nil, nil
  for i = 1, #run.weapons do run.weapons[i].cooldown = nil end
  local twin = resumeTwin(run)
  t.eq(#twin.world.pickups, 0)
  t.eq(#twin.world.drones, 0)
end)

-- ------------------------------------------------------------- completeness

test("every_key_a_live_gem_or_drone_grows_is_saved_or_derived", function(t)
  withDurableEnemies(function()
    local w = droneField("drones")
    dropGems(w)
    local unknown = {}
    for _ = 1, 60 * 12 do
      updateGame(1)
      for i = 1, #w.pickups do
        for _, k in ipairs(Entities.unclassifiedPickupKeys(w.pickups[i])) do unknown["pickup." .. k] = true end
      end
      for i = 1, #w.drones do
        for _, k in ipairs(Entities.unclassifiedDroneKeys(w.drones[i])) do unknown["drone." .. k] = true end
      end
    end
    local names = {}
    for k in pairs(unknown) do names[#names + 1] = k end
    table.sort(names)
    t.eq(table.concat(names, ","), "", "a new gem or drone field must be saved or listed as derived")
  end)
end)

test("the_gem_and_drone_completeness_check_catches_a_new_field", function(t)
  t.eq(#Entities.unclassifiedPickupKeys({ x = 1, value = 2, kind = "pickup", sprite = "s", dead = false, ptype = "xp" }), 0)
  t.eq(Entities.unclassifiedPickupKeys({ x = 1, mystery = 3 })[1], "mystery")
  t.eq(#Entities.unclassifiedDroneKeys({ x = 1, angle = 2, kind = "drone", sprite = "s", dead = false,
    hitCd = {}, hitCdN = 0 }), 0)
  t.eq(Entities.unclassifiedDroneKeys({ x = 1, mystery = 3 })[1], "mystery")
end)

-- ---------------------------------------------------------------- validation

local function gem(over)
  local g = {
    ptype = "xp", x = 240, y = 300, vx = 0, vy = 30, r = 8, rot = 0, scale = 1,
    t = 2.5, value = 3, magnet = false,
  }
  for k, v in pairs(over or {}) do g[k] = v end
  return g
end

local function drone(over)
  local d = {
    x = 300, y = 518, vx = 0, vy = 0, r = 8, rot = 1.5, scale = 1, t = 3,
    angle = 1.2, damage = 10, orbitR = 60, angVel = 2.6, hitCd = {},
  }
  for k, v in pairs(over or {}) do d[k] = v end
  return d
end

-- a save that owns the drone weapon, with the given field entries (time is 61.5)
local function runWithField(over)
  local run = Support.validRun2({
    weapons = {
      { id = "blaster", level = 2, cooldown = 0.15 },
      { id = "drones", level = 3, cooldown = 0 },
    },
  })
  for k, v in pairs(over) do run[k] = v end
  return run
end

function T.validate_accepts_gems_and_drones(t)
  t.eq(RunSave.validate(runWithField({ pickups = { gem(), gem({ magnet = true, vy = 400, value = 40 }) },
    drones = { drone(), drone({ angle = 4.2 }) } })), true)
end

function T.validate_accepts_a_drone_cooldown_on_a_live_enemy(t)
  local d = drone({ hitCd = { { 1, 61.9 } } }) -- time 61.5, cooldown 0.5
  t.eq(RunSave.validate(runWithField({ enemies = { VALID.drift }, drones = { d } })), true)
end

function T.validate_accepts_a_version_1_save_with_no_gem_or_drone_keys(t)
  t.eq(RunSave.validate(Support.validRun()), true)
end

local FIELD_REJECTS = {
  pickups_missing = function() local r = runWithField({}); r.pickups = nil; return r end,
  pickups_wrong_type = function() return runWithField({ pickups = 5 }) end,
  pickups_with_a_gap = function() return runWithField({ pickups = { [1] = gem(), [3] = gem() } }) end,
  drones_missing = function() local r = runWithField({}); r.drones = nil; return r end,
  drones_wrong_type = function() return runWithField({ drones = "x" }) end,
  gem_entry_wrong_type = function() return runWithField({ pickups = { 5 } }) end,
  gem_unknown_type = function() return runWithField({ pickups = { gem({ ptype = "health" }) } }) end,
  gem_type_missing = function() local g = gem(); g.ptype = nil; return runWithField({ pickups = { g } }) end,
  gem_unknown_key = function() return runWithField({ pickups = { gem({ mystery = 1 }) } }) end,
  gem_sprite_is_not_saved = function() return runWithField({ pickups = { gem({ sprite = "pickup_xp1" }) } }) end,
  gem_x_nan = function() return runWithField({ pickups = { gem({ x = NAN }) } }) end,
  gem_y_far_below = function() return runWithField({ pickups = { gem({ y = 9000 }) } }) end,
  gem_speed_absurd = function() return runWithField({ pickups = { gem({ vy = 1e7 }) } }) end,
  gem_value_zero = function() return runWithField({ pickups = { gem({ value = 0 }) } }) end,
  gem_value_negative = function() return runWithField({ pickups = { gem({ value = -5 }) } }) end,
  gem_value_huge = function() return runWithField({ pickups = { gem({ value = 1e12 }) } }) end,
  gem_magnet_not_a_boolean = function() return runWithField({ pickups = { gem({ magnet = 1 }) } }) end,
  gem_magnet_missing = function() local g = gem(); g.magnet = nil; return runWithField({ pickups = { g } }) end,
  gem_age_negative = function() return runWithField({ pickups = { gem({ t = -1 }) } }) end,
  too_many_gems = function()
    local list = {}
    for i = 1, Entities.MAX_PICKUPS + 1 do list[i] = gem() end
    return runWithField({ pickups = list })
  end,
  drone_entry_wrong_type = function() return runWithField({ drones = { 5 } }) end,
  drone_unknown_key = function() return runWithField({ drones = { drone({ mystery = 1 }) } }) end,
  drone_x_nan = function() return runWithField({ drones = { drone({ x = NAN }) } }) end,
  drone_orbit_radius_zero = function() return runWithField({ drones = { drone({ orbitR = 0 }) } }) end,
  drone_orbit_radius_huge = function() return runWithField({ drones = { drone({ orbitR = 1e6 }) } }) end,
  drone_angle_negative = function() return runWithField({ drones = { drone({ angle = -1 }) } }) end,
  drone_angle_beyond_a_turn = function() return runWithField({ drones = { drone({ angle = 7 }) } }) end,
  drone_spin_absurd = function() return runWithField({ drones = { drone({ angVel = 1e6 }) } }) end,
  drone_damage_negative = function() return runWithField({ drones = { drone({ damage = -1 }) } }) end,
  drone_hit_cooldowns_missing = function() local d = drone(); d.hitCd = nil; return runWithField({ drones = { d } }) end,
  drone_hit_cooldowns_wrong_type = function() return runWithField({ drones = { drone({ hitCd = 5 }) } }) end,
  drones_without_the_weapon = function()
    local r = Support.validRun2({ drones = { drone() } })
    return r
  end,
  too_many_drones = function()
    local list = {}
    for i = 1, Entities.MAX_DRONES + 1 do list[i] = drone() end
    return runWithField({ drones = list })
  end,
  -- a cooldown is { enemy slot, expiry }; expiry lies in (time, time + 0.5]
  cooldown_entry_wrong_shape = function()
    return runWithField({ enemies = { VALID.drift }, drones = { drone({ hitCd = { 1 } }) } })
  end,
  cooldown_slot_beyond_the_enemies = function()
    return runWithField({ enemies = { VALID.drift }, drones = { drone({ hitCd = { { 2, 61.9 } } }) } })
  end,
  cooldown_slot_with_no_enemies = function()
    return runWithField({ drones = { drone({ hitCd = { { 1, 61.9 } } }) } })
  end,
  cooldown_slot_fractional = function()
    return runWithField({ enemies = { VALID.drift }, drones = { drone({ hitCd = { { 1.5, 61.9 } } }) } })
  end,
  cooldown_slot_duplicated = function()
    return runWithField({ enemies = { VALID.drift },
      drones = { drone({ hitCd = { { 1, 61.9 }, { 1, 61.8 } } }) } })
  end,
  cooldown_already_expired = function()
    return runWithField({ enemies = { VALID.drift }, drones = { drone({ hitCd = { { 1, 61.0 } } }) } })
  end,
  cooldown_far_in_the_future = function()
    return runWithField({ enemies = { VALID.drift }, drones = { drone({ hitCd = { { 1, 9999 } } }) } })
  end,
  cooldown_expiry_nan = function()
    return runWithField({ enemies = { VALID.drift }, drones = { drone({ hitCd = { { 1, NAN } } }) } })
  end,
}

for name, build in pairs(FIELD_REJECTS) do
  T["validate_rejects_" .. name] = function(t)
    t.eq(RunSave.validate(build()), false, name)
  end
end

function T.validate_accepts_exactly_the_gem_and_drone_caps(t)
  local g, d = {}, {}
  for i = 1, Entities.MAX_PICKUPS do g[i] = gem() end
  for i = 1, Entities.MAX_DRONES do d[i] = drone() end
  t.eq(RunSave.validate(runWithField({ pickups = g, drones = d })), true)
end

function T.validate_never_throws_on_hostile_gem_and_drone_entries(t)
  local hostile = { { {} }, { 5 }, { { ptype = {} } }, { gem({ x = {} }) }, { drone({ hitCd = { {} } }) }, { false } }
  for i = 1, #hostile do
    local ok, result = pcall(RunSave.validate, runWithField({ pickups = hostile[i], drones = hostile[i] }))
    t.ok(ok, "case " .. i .. " must not throw")
    t.eq(result, false, "case " .. i)
  end
end

return T
