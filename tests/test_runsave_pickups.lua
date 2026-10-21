-- tests/test_runsave_pickups.lua — the live field in a run save: gems and drones. Three kinds of test:
--   * behavioural identity: a world and its resumed twin, stepped through the REAL
--     game state, stay equal frame after frame (the "cheat-proof" check);
--   * completeness: every key a live entity ever grows is saved or declared derived;
--   * validation: a hostile entity entry rejects the whole save, never crashes it.
local RunSave = require("src.meta.runsave")
local Entities = require("src.meta.runsave_entities")
local Enemies = require("src.content.enemies")
local Weapons = require("src.content.weapons")
local Save = require("src.meta.save")
local Leveling = require("src.systems.leveling")
local Spawner = require("src.systems.spawner")
local Damage = require("src.systems.damage")
local Support = require("tests.support")
local H = require("tests.game_harness")
local S = require("tests.support_runsave")

local roundTrip, updateGame, arena, resumeTwin, identical, withDurableEnemies, indexOf, stepUntil, dropGems = S.roundTrip, S.updateGame, S.arena, S.resumeTwin, S.identical, S.withDurableEnemies, S.indexOf, S.stepUntil, S.dropGems

local enemy, VALID, NAN, with = S.enemy, S.VALID, S.NAN, S.with
local T = {}
local test = H.guarded(T)

-- ================================================== pickups and drones (A4)
-- XP gems on the field, and the orbiting drones with the hit cooldowns they keep per
-- enemy (saved as slots in the enemy list, like a missile's target).

local Pickups = require("src.systems.pickups")
local WeaponSystem = require("src.systems.weapons")

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

-- a cooldown that ends a hair after the save time is still running (see the bullet
-- life test above: no invented epsilon on the "above zero" side)
function T.validate_accepts_a_drone_cooldown_a_hair_past_the_save_time(t)
  local d = drone({ hitCd = { { 1, 61.5 + 1e-14 } } }) -- run.time is 61.5
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
