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
