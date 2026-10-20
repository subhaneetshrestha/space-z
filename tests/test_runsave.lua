-- tests/test_runsave.lua — run snapshots: what is captured, the phase rewinds,
-- JSON survival, validation of untrusted data, and the Save.run helpers.
local RNG = require("src.core.rng")
local json = require("lib.json")
local Save = require("src.meta.save")
local RunSave = require("src.meta.runsave")
local Ships = require("src.content.ships")
local Weapons = require("src.content.weapons")
local Upgrades = require("src.content.upgrades")
local Zones = require("src.content.zones")
local Leveling = require("src.systems.leveling")
local Spawner = require("src.systems.spawner")
local Pool = require("src.core.pool")
local Events = require("src.core.events")
local Support = require("tests.support")

local T = {}

-- A mid-run world in zone 2: two weapons (one upgraded), one passive, damaged
-- hull, two open wave streams. Overrides replace top-level fields.
local function fakeWorld(over)
  local rng = {
    spawn = RNG.new(1001), drops = RNG.new(1002),
    cards = RNG.new(1003), misc = RNG.new(1004),
  }
  for _ = 1, 9 do rng.spawn:random() end -- mid-stream, not a fresh seed
  local w = {
    mode = "standard", seed = 1000, daily = false, autopilot = false,
    phase = "waves",
    time = 123.5, distance = 14800.25,
    zoneIndex = 2, zone = Zones[2], zoneTime = 47.5, zoneStartDistance = 9000.5,
    level = 7, xp = 12.5, xpNext = 40, pendingLevelUps = 0,
    kills = 88, bossKills = 1, noDamage = false, stardustEarned = 25,
    player = { hp = 37.5, maxhp = 100, dead = false, shipDef = Ships.aegis },
    weapons = {
      { def = Weapons.blaster, level = 4, cooldown = 0.2 },
      { def = Weapons.plasma_storm, level = 1, cooldown = 0.1 }, -- an evolved weapon
    },
    passives = { { def = Upgrades.ammo_feed, level = 2 } },
    rng = rng,
    spawnerState = { timers = { [1] = 0.4, [3] = 1.2 } },
  }
  for k, v in pairs(over or {}) do w[k] = v end
  return w
end

local function roundTrip(run)
  return json.decode(json.encode(run))
end

-- ---------------------------------------------------------------- snapshot

function T.snapshot_captures_identity_and_clocks(t)
  local run = RunSave.snapshot(fakeWorld())
  t.eq(run.version, 1)
  t.eq(run.mode, "standard")
  t.eq(run.seed, 1000)
  t.eq(run.ship, "aegis", "the run's own ship, not settings.ship")
  t.eq(run.time, 123.5)
  t.eq(run.distance, 14800.25)
  t.eq(run.zoneIndex, 2)
  t.eq(run.zoneTime, 47.5)
  t.eq(run.zoneStartDistance, 9000.5)
end

function T.snapshot_captures_progression(t)
  local run = RunSave.snapshot(fakeWorld())
  t.eq(run.level, 7)
  t.eq(run.xp, 12.5)
  t.eq(run.xpNext, 40)
  t.eq(run.pendingLevelUps, 0)
  t.eq(run.kills, 88)
  t.eq(run.bossKills, 1)
  t.eq(run.noDamage, false)
  t.eq(run.stardustEarned, 25)
end

function T.snapshot_keeps_fractional_hp(t)
  local run = RunSave.snapshot(fakeWorld())
  t.eq(run.hp, 37.5)
end

function T.snapshot_captures_build_by_id(t)
  local run = RunSave.snapshot(fakeWorld())
  t.eq(#run.weapons, 2)
  t.eq(run.weapons[1].id, "blaster")
  t.eq(run.weapons[1].level, 4)
  t.eq(run.weapons[2].id, "plasma_storm", "evolved weapons are saved by id too")
  t.eq(#run.passives, 1)
  t.eq(run.passives[1].id, "ammo_feed")
  t.eq(run.passives[1].level, 2)
end

function T.snapshot_captures_rng_and_spawner_timers(t)
  local w = fakeWorld()
  local run = RunSave.snapshot(w)
  t.eq(run.rng.spawn, w.rng.spawn:getState())
  t.eq(run.rng.drops, w.rng.drops:getState())
  t.eq(run.rng.cards, w.rng.cards:getState())
  t.eq(run.rng.misc, w.rng.misc:getState())
  t.eq(#run.spawnerTimers, 2)
  t.eq(run.spawnerTimers[1][1], 1)
  t.eq(run.spawnerTimers[1][2], 0.4)
  t.eq(run.spawnerTimers[2][1], 3)
  t.eq(run.spawnerTimers[2][2], 1.2)
end

function T.snapshot_without_spawner_state_has_no_timers(t)
  local run = RunSave.snapshot(fakeWorld({ spawnerState = false }))
  t.eq(#run.spawnerTimers, 0)
end

function T.snapshot_blackhole_mode_kept(t)
  t.eq(RunSave.snapshot(fakeWorld({ mode = "blackhole" })).mode, "blackhole")
end

function T.snapshot_boss_phase_rewinds_to_boss_arrival(t)
  local run = RunSave.snapshot(fakeWorld({
    phase = "boss", zoneTime = Zones[2].duration + 30, boss = { hp = 5 },
  }))
  t.eq(run.zoneIndex, 2)
  t.eq(run.zoneTime, Zones[2].duration, "field restarts empty at the boss trigger")
  t.eq(run.zoneStartDistance, 9000.5)
  t.eq(#run.spawnerTimers, 0)
end

function T.snapshot_warp_phase_resumes_at_next_zone_start(t)
  local run = RunSave.snapshot(fakeWorld({
    phase = "warp", bossKills = 2, distance = 20000.5,
  }))
  t.eq(run.zoneIndex, 3)
  t.eq(run.zoneTime, 0)
  t.eq(run.zoneStartDistance, 20000.5)
  t.eq(run.bossKills, 2, "the boss kill is kept")
  t.eq(#run.spawnerTimers, 0)
end

function T.snapshot_warp_after_last_zone_is_nil(t)
  local last = #Zones
  t.eq(RunSave.snapshot(fakeWorld({
    phase = "warp", zoneIndex = last, zone = Zones[last],
  })), nil, "the run is already won")
end

function T.snapshot_nil_when_run_is_over(t)
  t.eq(RunSave.snapshot(fakeWorld({ phase = "over" })), nil)
end

function T.snapshot_nil_when_player_dead(t)
  local w = fakeWorld()
  w.player.dead = true
  t.eq(RunSave.snapshot(w), nil)
end

function T.snapshot_nil_for_daily_run(t)
  t.eq(RunSave.snapshot(fakeWorld({ daily = true })), nil)
end

function T.snapshot_nil_for_autopilot_run(t)
  t.eq(RunSave.snapshot(fakeWorld({ autopilot = true })), nil)
end

function T.snapshot_counts_open_draft_as_pending(t)
  local w = fakeWorld({ pendingLevelUps = 1 })
  t.eq(RunSave.snapshot(w).pendingLevelUps, 1, "no draft open: unchanged")
  t.eq(RunSave.snapshot(w, { draftOpen = true }).pendingLevelUps, 2)
end

function T.snapshot_does_not_mutate_the_world(t)
  local w = fakeWorld({ phase = "boss" })
  RunSave.snapshot(w, { draftOpen = true })
  t.eq(w.zoneTime, 47.5)
  t.eq(w.pendingLevelUps, 0)
  t.eq(w.phase, "boss")
end

function T.snapshot_passes_validate(t)
  t.eq(RunSave.validate(RunSave.snapshot(fakeWorld())), true)
end

function T.snapshot_survives_json_and_still_validates(t)
  local run = RunSave.snapshot(fakeWorld())
  local back = roundTrip(run)
  t.eq(RunSave.validate(back), true)
  t.eq(back.hp, 37.5)
  t.eq(back.distance, 14800.25)
  t.eq(back.weapons[2].id, "plasma_storm")
  t.eq(back.spawnerTimers[2][2], 1.2)
  t.eq(back.rng.spawn, run.rng.spawn)
  t.eq(back.noDamage, false)
end

-- ---------------------------------------------------------------- validate

local function good()
  return RunSave.snapshot(fakeWorld())
end

function T.validate_accepts_a_good_run(t)
  t.eq(RunSave.validate(good()), true)
end

local NAN = 0 / 0

-- One test per malformed case: a bad save must never be partially trusted.
local REJECTS = {
  not_a_table_nil = function() return nil end,
  not_a_table_string = function() return "run" end,
  not_a_table_number = function() return 5 end,
  version_mismatch = function() local r = good(); r.version = 2; return r end,
  version_missing = function() local r = good(); r.version = nil; return r end,
  mode_unknown = function() local r = good(); r.mode = "arcade"; return r end,
  mode_daily_not_resumable = function() local r = good(); r.mode = "daily"; return r end,
  mode_wrong_type = function() local r = good(); r.mode = 3; return r end,
  seed_wrong_type = function() local r = good(); r.seed = "1000"; return r end,
  seed_missing = function() local r = good(); r.seed = nil; return r end,
  ship_unknown = function() local r = good(); r.ship = "deathstar"; return r end,
  ship_wrong_type = function() local r = good(); r.ship = 7; return r end,
  time_negative = function() local r = good(); r.time = -1; return r end,
  time_nan = function() local r = good(); r.time = NAN; return r end,
  time_infinite = function() local r = good(); r.time = math.huge; return r end,
  time_wrong_type = function() local r = good(); r.time = "9"; return r end,
  distance_negative = function() local r = good(); r.distance = -5; return r end,
  zone_index_zero = function() local r = good(); r.zoneIndex = 0; return r end,
  zone_index_too_high = function() local r = good(); r.zoneIndex = #Zones + 1; return r end,
  zone_index_fractional = function() local r = good(); r.zoneIndex = 1.5; return r end,
  zone_time_negative = function() local r = good(); r.zoneTime = -0.1; return r end,
  zone_start_distance_negative = function() local r = good(); r.zoneStartDistance = -1; return r end,
  level_zero = function() local r = good(); r.level = 0; return r end,
  level_fractional = function() local r = good(); r.level = 2.5; return r end,
  xp_negative = function() local r = good(); r.xp = -1; return r end,
  xp_next_zero = function() local r = good(); r.xpNext = 0; return r end,
  pending_negative = function() local r = good(); r.pendingLevelUps = -1; return r end,
  kills_negative = function() local r = good(); r.kills = -3; return r end,
  boss_kills_fractional = function() local r = good(); r.bossKills = 0.5; return r end,
  no_damage_wrong_type = function() local r = good(); r.noDamage = "yes"; return r end,
  stardust_negative = function() local r = good(); r.stardustEarned = -1; return r end,
  hp_zero = function() local r = good(); r.hp = 0; return r end,
  hp_negative = function() local r = good(); r.hp = -4; return r end,
  hp_nan = function() local r = good(); r.hp = NAN; return r end,
  weapons_missing = function() local r = good(); r.weapons = nil; return r end,
  weapons_empty = function() local r = good(); r.weapons = {}; return r end,
  weapons_too_many = function()
    local r = good()
    r.weapons = {}
    for _, id in ipairs({ "blaster", "missiles", "flak", "laser", "graviton", "railgun", "drones" }) do
      r.weapons[#r.weapons + 1] = { id = id, level = 1 }
    end
    return r
  end,
  weapon_unknown_id = function() local r = good(); r.weapons[1].id = "bfg"; return r end,
  weapon_is_a_passive_id = function() local r = good(); r.weapons[1].id = "ammo_feed"; return r end,
  weapon_level_zero = function() local r = good(); r.weapons[1].level = 0; return r end,
  weapon_level_above_max = function()
    local r = good(); r.weapons[1].level = Weapons.blaster.maxLevel + 1; return r
  end,
  weapon_duplicate = function() local r = good(); r.weapons[2].id = "blaster"; return r end,
  weapon_entry_wrong_type = function() local r = good(); r.weapons[1] = "blaster"; return r end,
  passives_missing = function() local r = good(); r.passives = nil; return r end,
  passive_unknown_id = function() local r = good(); r.passives[1].id = "magic"; return r end,
  passive_is_a_weapon_id = function() local r = good(); r.passives[1].id = "blaster"; return r end,
  passive_level_above_max = function()
    local r = good(); r.passives[1].level = Upgrades.ammo_feed.maxLevel + 1; return r
  end,
  passive_duplicate = function()
    local r = good()
    r.passives[2] = { id = "ammo_feed", level = 1 }
    return r
  end,
  rng_missing = function() local r = good(); r.rng = nil; return r end,
  rng_stream_missing = function() local r = good(); r.rng.cards = nil; return r end,
  rng_state_zero = function() local r = good(); r.rng.spawn = 0; return r end,
  rng_state_out_of_range = function() local r = good(); r.rng.misc = 2147483647; return r end,
  rng_state_wrong_type = function() local r = good(); r.rng.drops = "5"; return r end,
  timers_missing = function() local r = good(); r.spawnerTimers = nil; return r end,
  timers_entry_wrong_shape = function() local r = good(); r.spawnerTimers[1] = 0.4; return r end,
  timers_index_beyond_zone_waves = function()
    local r = good(); r.spawnerTimers[1][1] = #Zones[2].waves + 1; return r
  end,
  timers_value_nan = function() local r = good(); r.spawnerTimers[1][2] = NAN; return r end,
}

for name, mutate in pairs(REJECTS) do
  T["validate_rejects_" .. name] = function(t)
    t.eq(RunSave.validate(mutate()), false, name)
  end
end

function T.validate_never_throws_on_hostile_input(t)
  local hostile = { {}, { weapons = 5 }, { weapons = { {} }, passives = { {} } },
    { rng = 5 }, { spawnerTimers = { {} } }, { version = 1, rng = {}, weapons = {} } }
  for i = 1, #hostile do
    local ok, result = pcall(RunSave.validate, hostile[i])
    t.ok(ok, "case " .. i .. " must not throw")
    t.eq(result, false, "case " .. i)
  end
end

-- ------------------------------------------------------------------- apply

-- A brand-new run exactly as game:enter builds it (headless subset): starting
-- weapon, computed stats, full hull, spawn-point player, empty field.
local function freshWorld(seed, shipId)
  local ship = Ships[shipId or "pathfinder"]
  local world = {
    mode = "standard", seed = seed, daily = false,
    rng = {
      spawn = RNG.new(seed), drops = RNG.new(seed + 1),
      cards = RNG.new(seed + 2), misc = RNG.new(seed + 3),
    },
    events = Events.new(),
    time = 0, distance = 0, scrollSpeed = 120,
    zoneIndex = 1, zone = Zones[1], zoneTime = 0, zoneStartDistance = 0,
    phase = "waves", warpT = 0,
    player = { x = 240, y = 518, hp = ship.maxhp, maxhp = ship.maxhp,
               dead = false, shipDef = ship, sprite = ship.sprite },
    enemies = {}, ebullets = {},
    pools = { enemies = Pool.new(), ebullets = Pool.new() },
    boss = nil,
    weapons = {}, passives = {},
    level = 1, xp = 0, xpNext = 8, pendingLevelUps = 0,
    kills = 0, bossKills = 0, noDamage = true, stardustEarned = 0,
    shieldT = 0, freezeT = 0, hpRingT = 0, pulseT = 0,
  }
  Leveling.addWeapon(world, Weapons[ship.startingWeapon])
  Leveling.recomputeStats(world)
  world.player.hp = world.player.maxhp
  return world
end

local function simulate(world, seconds)
  local dt = 1 / 60
  for _ = 1, math.floor(seconds / dt + 0.5) do
    world.time = world.time + dt
    world.zoneTime = world.zoneTime + dt
    Spawner.update(world, dt)
  end
end

-- A run that has been played for a while: bigger build, damaged, 20 s into zone 1.
local function playedWorld(seed)
  local w = freshWorld(seed, "aegis")
  Leveling.addWeapon(w, Weapons.missiles)
  w.weapons[2].level = 3
  w.weapons[2].cooldown = 0.9
  w.weapons[1].cooldown = 0.2
  Leveling.addPassive(w, Upgrades.hull_plating)
  w.passives[1].level = 3
  Leveling.recomputeStats(w)
  w.level, w.xp, w.xpNext, w.pendingLevelUps = 6, 14.5, 40, 1
  w.kills, w.bossKills, w.noDamage, w.stardustEarned = 52, 0, false, 25
  w.distance, w.zoneStartDistance = 2400.75, 0
  w.shieldT, w.hpRingT = 1.5, 1.0
  simulate(w, 20)
  w.player.hp = 37.5
  return w
end

local firstDiff = Support.firstDiff

local function deepEqual(a, b)
  return firstDiff(a, b) == nil
end

function T.apply_restores_a_run_so_its_snapshot_is_identical(t)
  local a = playedWorld(2024)
  t.ok(a.player.maxhp >= 38, "fixture needs room for 37.5 hp")
  local run = roundTrip(RunSave.snapshot(a))

  local b = freshWorld(2024, "pathfinder") -- default ship: the run's must win
  t.eq(RunSave.apply(b, run), true)

  t.eq(firstDiff(RunSave.snapshot(b), RunSave.snapshot(a)), nil,
    "snapshot(restored) must equal snapshot(original), every field")
end

function T.apply_sets_the_runs_ship_and_recomputes_stats(t)
  local a = playedWorld(7)
  local b = freshWorld(7, "pathfinder")
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  t.eq(b.player.shipDef.id, "aegis")
  t.eq(b.player.sprite, Ships.aegis.sprite)
  t.eq(b.stats.maxhp, a.stats.maxhp, "maxhp rebuilt from ship + passives")
  t.eq(b.player.maxhp, a.player.maxhp)
  t.eq(b.stats.shieldLevel, a.stats.shieldLevel, "ship bonuses applied")
end

function T.apply_restores_fractional_hp_exactly(t)
  local a = playedWorld(8)
  local b = freshWorld(8)
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  t.eq(b.player.hp, 37.5)
end

function T.apply_clamps_hp_to_one_through_maxhp(t)
  local a = playedWorld(9)
  local run = roundTrip(RunSave.snapshot(a))

  run.hp = 0.2
  local low = freshWorld(9)
  RunSave.apply(low, run)
  t.eq(low.player.hp, 1)

  run.hp = 99999
  local high = freshWorld(9)
  RunSave.apply(high, run)
  t.eq(high.player.hp, high.player.maxhp)
end

function T.apply_zeroes_cooldowns_and_transient_timers(t)
  local a = playedWorld(10)
  local b = freshWorld(10)
  b.shieldT, b.hpRingT, b.freezeT, b.pulseT = 2, 2, 2, 2 -- stale values must go
  b.weapons[1].cooldown = 0.3
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  for i = 1, #b.weapons do
    t.eq(b.weapons[i].cooldown, 0, "weapon " .. i .. " cooldown")
  end
  t.eq(b.shieldT, 0)
  t.eq(b.hpRingT, 0)
  t.eq(b.freezeT, 0)
  t.eq(b.pulseT, 0)
end

function T.apply_leaves_player_at_the_spawn_point(t)
  local b = freshWorld(11)
  RunSave.apply(b, roundTrip(RunSave.snapshot(playedWorld(11))))
  t.eq(b.player.x, 240)
  t.eq(b.player.y, 518)
end

function T.apply_keeps_the_weapon_and_passive_tables(t)
  local b = freshWorld(12)
  local weapons, passives = b.weapons, b.passives
  RunSave.apply(b, roundTrip(RunSave.snapshot(playedWorld(12))))
  t.ok(b.weapons == weapons, "same weapons table (other code may hold it)")
  t.ok(b.passives == passives, "same passives table")
  t.eq(#b.weapons, 2)
  t.eq(b.weapons[2].def.id, "missiles")
  t.eq(b.weapons[2].level, 3)
end

function T.apply_restores_evolved_weapons(t)
  local a = playedWorld(13)
  a.weapons[1].def = Weapons.plasma_storm
  a.weapons[1].level = 1
  local b = freshWorld(13)
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  t.eq(b.weapons[1].def, Weapons.plasma_storm)
end

function T.apply_boss_phase_save_resumes_in_waves_with_no_boss(t)
  local a = playedWorld(14)
  a.phase, a.zoneTime, a.boss = "boss", Zones[1].duration + 20, { hp = 3 }
  local b = freshWorld(14)
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  t.eq(b.phase, "waves")
  t.eq(b.zoneTime, Zones[1].duration)
  t.eq(b.boss, nil)
end

function T.apply_warp_save_resumes_at_next_zone(t)
  local a = playedWorld(15)
  a.phase, a.bossKills = "warp", 1
  local b = freshWorld(15)
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  t.eq(b.phase, "waves")
  t.eq(b.zoneIndex, 2)
  t.ok(b.zone == Zones[2], "zone table follows zoneIndex")
  t.eq(b.zoneTime, 0)
  t.eq(b.zoneStartDistance, a.distance)
  t.eq(b.bossKills, 1)
end

function T.apply_resumed_spawns_match_a_run_that_never_paused(t)
  local a = playedWorld(31337)
  local run = roundTrip(RunSave.snapshot(a))
  local before = #a.enemies

  local b = freshWorld(31337)
  RunSave.apply(b, run)
  simulate(a, 12) -- the original keeps playing...
  simulate(b, 12) -- ...the resumed copy plays the same 12 s from the save

  t.eq(#b.enemies, #a.enemies - before, "same number of new spawns")
  t.ok(#b.enemies > 0, "fixture must actually spawn something")
  for i = 1, #b.enemies do
    local ea, eb = a.enemies[before + i], b.enemies[i]
    t.eq(eb.x, ea.x, "x of spawn " .. i)
    t.eq(eb.y, ea.y, "y of spawn " .. i)
    t.eq(eb.def.id, ea.def.id, "type of spawn " .. i)
    t.eq(eb.elite, ea.elite, "elite flag of spawn " .. i)
  end
end

function T.apply_resumed_card_offer_matches_the_original(t)
  local a = playedWorld(555)
  local b = freshWorld(555)
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  local offerA = Leveling.buildOffer(a)
  local offerB = Leveling.buildOffer(b)
  t.eq(#offerB, 3)
  for i = 1, 3 do
    t.eq(offerB[i].def.id, offerA[i].def.id, "card " .. i)
    t.eq(offerB[i].newLevel, offerA[i].newLevel, "card " .. i .. " level")
  end
end

function T.apply_rejects_an_invalid_run_without_touching_the_world(t)
  local b = freshWorld(16)
  local before = RunSave.snapshot(b)
  local run = roundTrip(RunSave.snapshot(playedWorld(16)))
  run.weapons[1].id = "bfg"
  t.eq(RunSave.apply(b, run), false)
  t.eq(RunSave.apply(b, nil), false)
  t.ok(deepEqual(RunSave.snapshot(b), before), "world unchanged")
  t.eq(b.player.shipDef.id, "pathfinder")
end

-- ------------------------------------------------------------ Save helpers

function T.save_run_defaults_to_nil(t)
  Save.reset()
  t.eq(Save.run(), nil)
  t.eq(Save.data().run, nil)
end

function T.save_setrun_then_run_returns_it(t)
  Save.reset()
  local run = good()
  t.ok(Save.setRun(run), "write succeeds")
  t.eq(Save.run().zoneIndex, 2)
  t.eq(Save.run().hp, 37.5)
end

function T.save_run_returns_nil_for_an_invalid_stored_run(t)
  Save.reset()
  Save.data().run = { version = 1, mode = "standard" } -- truncated / hand-edited
  t.eq(Save.run(), nil)
end

function T.save_clearrun_removes_the_run(t)
  Save.reset()
  Save.setRun(good())
  Save.clearRun()
  t.eq(Save.run(), nil)
  t.eq(Save.data().run, nil)
end

function T.save_reset_clears_the_run(t)
  Save.setRun(good())
  Save.reset()
  t.eq(Save.run(), nil)
end

function T.save_clearrun_without_a_run_is_a_noop(t)
  Save.reset()
  Save.clearRun()
  t.eq(Save.run(), nil)
end

return T
