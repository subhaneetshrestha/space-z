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
local Spawner = require("src.systems.spawner")
local Damage = require("src.systems.damage")
local Pool = require("src.core.pool")
local json = require("lib.json")
local Support = require("tests.support")
local H = require("tests.game_harness")

local T = {}
local test = H.guarded(T)

local STEP = H.STEP

-- State a later task has not started saving, so the identity checks leave it out.
-- Each task deletes what it now covers (A3: ebullets and bullets, A4: pickups, drones).
local SKIP = { ebullets = true, bullets = true, pickups = true, drones = true }

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

return T
