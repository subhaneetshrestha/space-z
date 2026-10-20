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
local Boss = require("src.systems.boss")
local Bosses = require("src.content.bosses")
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
    player = {
      hp = 37.5, maxhp = 100, dead = false, shipDef = Ships.aegis,
      x = 210.5, y = 500.25, vx = 12.5, vy = -30, invulnT = 0.4,
    },
    freezeT = 0.05, shieldT = 3.5, pulseT = 0, hpRingT = 1.25,
    weapons = {
      { def = Weapons.blaster, level = 4, cooldown = 0.2, side = -1 },
      { def = Weapons.plasma_storm, level = 1, cooldown = 0.1, tickT = 0.03 }, -- an evolved weapon
    },
    passives = { { def = Upgrades.ammo_feed, level = 2 } },
    rng = rng,
    spawnerState = { timers = { [1] = 0.4, [3] = 1.2 } },
  }
  for k, v in pairs(over or {}) do w[k] = v end
  return w
end

-- defined further down; the snapshot tests need them too
local playedWorld, freshWorld

local function roundTrip(run)
  return json.decode(json.encode(run))
end

-- ---------------------------------------------------------------- snapshot

function T.snapshot_captures_identity_and_clocks(t)
  local run = RunSave.snapshot(fakeWorld())
  t.eq(run.version, 2, "new saves are version 2 (version 1 still loads, see validate)")
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

function T.snapshot_captures_the_player_exactly(t)
  local p = RunSave.snapshot(fakeWorld()).player
  t.eq(p.x, 210.5)
  t.eq(p.y, 500.25)
  t.eq(p.vx, 12.5)
  t.eq(p.vy, -30)
  t.eq(p.invulnT, 0.4, "i-frames carry over: a save must not strip them or grant them")
end

function T.snapshot_captures_the_running_timers(t)
  local tm = RunSave.snapshot(fakeWorld()).timers
  t.eq(tm.freezeT, 0.05, "hit-stop")
  t.eq(tm.shieldT, 3.5, "shield recharge")
  t.eq(tm.pulseT, 0)
  t.eq(tm.hpRingT, 1.25)
end

function T.snapshot_captures_weapon_cooldowns_and_scratch(t)
  local w = RunSave.snapshot(fakeWorld()).weapons
  t.eq(w[1].cooldown, 0.2, "a save must not refill a weapon")
  t.eq(w[1].side, -1, "homing launch side")
  t.eq(w[1].tickT, nil, "scratch a weapon never set is not invented")
  t.eq(w[2].cooldown, 0.1)
  t.eq(w[2].tickT, 0.03, "beam / aura tick timer")
  t.eq(w[2].side, nil)
end

function T.snapshot_without_spawner_state_has_no_timers(t)
  local run = RunSave.snapshot(fakeWorld({ spawnerState = false }))
  t.eq(#run.spawnerTimers, 0)
end

function T.snapshot_blackhole_mode_kept(t)
  t.eq(RunSave.snapshot(fakeWorld({ mode = "blackhole" })).mode, "blackhole")
end

-- The boss and warp phases used to be rewound (boss: back to its arrival with full
-- health and an empty field; warp: on to the next zone), which let a player escape any
-- fight by saving. They are saved as they are now.

-- the world in the boss fight of its zone: the boss in the enemy list, linked as
-- world.boss, 12 s into the fight so its pattern has initialised
local function indexOfBoss(w)
  for i = 1, #w.enemies do
    if w.enemies[i] == w.boss then return i end
  end
end

local function inBossFight(w)
  w.phase = "boss"
  w.zoneTime = w.zone.duration + 12.5
  w.pools = w.pools or {}
  w.pools.enemies = w.pools.enemies or Pool.new()
  w.enemies = w.enemies or {}
  Boss.spawn(w, w.zone.boss)
  for _ = 1, 60 * 12 do Boss.update(w, 1 / 60) end
  return w
end

function T.snapshot_in_the_boss_phase_keeps_the_phase_and_the_clock(t)
  local w = inBossFight(playedWorld(41))
  local run = RunSave.snapshot(w)
  t.eq(run.phase, "boss")
  t.eq(run.zoneIndex, w.zoneIndex)
  t.near(run.zoneTime, w.zoneTime, 1e-12, "no rewind to the boss's arrival")
  t.eq(run.zoneStartDistance, w.zoneStartDistance)
  t.eq(run.warpT, 0)
end

function T.snapshot_saves_the_boss_and_links_it(t)
  local w = inBossFight(playedWorld(42))
  w.boss.hp = 321.5
  local run = RunSave.snapshot(w)
  t.ok(run.boss, "world.boss is saved as a slot")
  local s = run.enemies[run.boss]
  t.eq(s.boss, w.zone.boss)
  t.eq(s.def, nil, "a boss has a boss id, not an enemy def")
  t.eq(s.hp, 321.5, "no heal back to full health")
  t.eq(s.maxhp, w.boss.maxhp)
  t.eq(s.entering, false)
  t.eq(s.bt, w.boss.bt)
end

function T.snapshot_in_the_boss_phase_without_a_boss_is_nil(t)
  local w = inBossFight(playedWorld(43))
  w.boss.dead = true
  w.boss = nil
  t.eq(RunSave.snapshot(w), nil, "nothing a resume could rebuild the fight from")
end

function T.snapshot_in_the_warp_phase_keeps_the_warp(t)
  local w = playedWorld(44)
  w.phase, w.warpT, w.bossKills, w.zoneTime = "warp", 1.25, 2, w.zone.duration + 30
  local run = RunSave.snapshot(w)
  t.eq(run.phase, "warp")
  t.eq(run.warpT, 1.25)
  t.eq(run.zoneIndex, w.zoneIndex, "still the zone whose boss just died")
  t.eq(run.zoneTime, w.zoneTime)
  t.eq(run.bossKills, 2, "the boss kill is kept")
  t.eq(run.boss, nil)
end

function T.snapshot_in_the_warp_after_the_last_boss_is_saved_too(t)
  local last = #Zones
  local w = playedWorld(45)
  w.zoneIndex, w.zone = last, Zones[last]
  w.phase, w.warpT, w.zoneTime = "warp", 0.5, w.zone.duration + 40
  w.spawnerState = { timers = {} }
  local run = RunSave.snapshot(w)
  t.ok(run, "resuming it plays out the win; it used to be refused")
  t.eq(run.phase, "warp")
  t.eq(RunSave.validate(roundTrip(run)), true)
end

function T.snapshot_of_a_waves_run_says_so(t)
  local run = RunSave.snapshot(fakeWorld())
  t.eq(run.phase, "waves")
  t.eq(run.warpT, 0)
  t.eq(run.boss, nil)
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
  version_unknown_future = function() local r = good(); r.version = 3; return r end,
  version_zero = function() local r = good(); r.version = 0; return r end,
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
  -- Spawner.update runs `while timer <= 0 do spawn; timer += interval end`: a
  -- non-positive timer from a corrupt file would spawn for ~forever on resume.
  timers_value_zero = function() local r = good(); r.spawnerTimers[1][2] = 0; return r end,
  timers_value_hugely_negative = function() local r = good(); r.spawnerTimers[1][2] = -1e9; return r end,
  timers_value_above_the_waves_interval = function()
    local r = good(); r.spawnerTimers[1][2] = Zones[2].waves[1].interval * 1.01; return r
  end,
  timers_more_entries_than_waves = function()
    local r = good()
    r.spawnerTimers = {}
    for i = 1, #Zones[2].waves + 1 do r.spawnerTimers[i] = { 1, 0.5 } end
    return r
  end,
  -- one level-up draft opens per frame while this is > 0
  pending_level_ups_above_the_level = function()
    local r = good(); r.pendingLevelUps = r.level + 1; return r
  end,
  pending_level_ups_huge = function() local r = good(); r.pendingLevelUps = 1e9; return r end,
  -- version 2: the player, the running timers and the weapon cooldowns are required
  player_missing = function() local r = good(); r.player = nil; return r end,
  player_wrong_type = function() local r = good(); r.player = 5; return r end,
  player_x_missing = function() local r = good(); r.player.x = nil; return r end,
  player_x_wrong_type = function() local r = good(); r.player.x = "210"; return r end,
  player_x_nan = function() local r = good(); r.player.x = NAN; return r end,
  player_x_off_screen = function() local r = good(); r.player.x = -50; return r end,
  player_y_off_screen = function() local r = good(); r.player.y = 99999; return r end,
  player_vx_absurd = function() local r = good(); r.player.vx = 1e6; return r end,
  player_vy_infinite = function() local r = good(); r.player.vy = math.huge; return r end,
  player_invuln_far_below_zero = function() local r = good(); r.player.invulnT = -5; return r end,
  player_invuln_nan = function() local r = good(); r.player.invulnT = NAN; return r end,
  timers_block_missing = function() local r = good(); r.timers = nil; return r end,
  timer_freeze_missing = function() local r = good(); r.timers.freezeT = nil; return r end,
  timer_freeze_far_below_zero = function() local r = good(); r.timers.freezeT = -5; return r end,
  timer_shield_nan = function() local r = good(); r.timers.shieldT = NAN; return r end,
  timer_pulse_wrong_type = function() local r = good(); r.timers.pulseT = "1"; return r end,
  timer_hpring_infinite = function() local r = good(); r.timers.hpRingT = math.huge; return r end,
  weapon_cooldown_missing = function() local r = good(); r.weapons[1].cooldown = nil; return r end,
  weapon_cooldown_negative = function() local r = good(); r.weapons[1].cooldown = -1; return r end,
  weapon_cooldown_nan = function() local r = good(); r.weapons[1].cooldown = NAN; return r end,
  weapon_cooldown_would_silence_it_for_good = function()
    local r = good(); r.weapons[1].cooldown = 1e9; return r
  end,
  weapon_side_not_a_side = function() local r = good(); r.weapons[1].side = 2; return r end,
  weapon_tick_wrong_type = function() local r = good(); r.weapons[2].tickT = "0.03"; return r end,
  weapon_tick_would_silence_it_for_good = function()
    local r = good(); r.weapons[2].tickT = 1e9; return r
  end,
}

for name, mutate in pairs(REJECTS) do
  T["validate_rejects_" .. name] = function(t)
    t.eq(RunSave.validate(mutate()), false, name)
  end
end

function T.validate_accepts_a_timer_at_the_interval_even_after_json_rounding(t)
  local interval = Zones[2].waves[1].interval
  local r = good()
  r.spawnerTimers[1][2] = interval
  t.eq(RunSave.validate(r), true, "exactly the interval")
  r.spawnerTimers[1][2] = interval * (1 + 1e-12) -- 14-digit JSON round-trip noise
  t.eq(RunSave.validate(r), true, "interval plus rounding noise")
  r.spawnerTimers[1][2] = 1e-9
  t.eq(RunSave.validate(r), true, "about to fire")
end

function T.validate_accepts_pending_level_ups_up_to_the_level(t)
  local r = good()
  r.pendingLevelUps = r.level
  t.eq(RunSave.validate(r), true)
end

-- Saves written before the exact snapshot (version 1) carry no player, timers or
-- cooldowns. They must keep loading; they resume as they always did (spawn point,
-- cooldowns ready), which is a one-time degradation, not an error.
local function legacy(run)
  run.version = 1
  run.player, run.timers = nil, nil
  for i = 1, #run.weapons do
    run.weapons[i].cooldown, run.weapons[i].side, run.weapons[i].tickT = nil, nil, nil
  end
  return run
end

function T.validate_accepts_a_version_1_save_without_the_new_blocks(t)
  t.eq(RunSave.validate(legacy(good())), true)
  t.eq(RunSave.validate(Support.validRun()), true, "the shared v1 fixture")
end

function T.validate_ignores_version_2_fields_on_a_version_1_save(t)
  local r = good()
  r.version = 1 -- extras are simply not read
  t.eq(RunSave.validate(r), true)
end

-- The game counts these down only while they are above zero, so one that has just run
-- out sits a fraction below zero until it is set again: normal play, not corruption.
function T.validate_accepts_timers_that_have_just_run_out(t)
  local r = good()
  r.player.invulnT = -0.006
  r.timers.freezeT, r.timers.shieldT = -0.016, -0.001
  r.timers.pulseT, r.timers.hpRingT = -0.0004, -0.012
  t.eq(RunSave.validate(r), true)
end

function T.validate_accepts_a_huge_invuln_timer(t)
  -- the test harness (and a debug build) hold i-frames at 1e9; only NaN/negative are corrupt
  local r = good()
  r.player.invulnT = 1e9
  t.eq(RunSave.validate(r), true)
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
function freshWorld(seed, shipId)
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
    player = { x = 240, y = 518, vx = 0, vy = 0, invulnT = 0,
               hp = ship.maxhp, maxhp = ship.maxhp,
               dead = false, shipDef = ship, sprite = ship.sprite },
    enemies = {}, bullets = {}, ebullets = {}, pickups = {}, drones = {},
    pools = { enemies = Pool.new(), bullets = Pool.new(), ebullets = Pool.new(),
              pickups = Pool.new(), drones = Pool.new() },
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
function playedWorld(seed)
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

function T.apply_restores_cooldowns_and_running_timers(t)
  local a = playedWorld(10)
  a.freezeT, a.pulseT = 0.04, 0.7
  local b = freshWorld(10)
  b.shieldT, b.hpRingT, b.freezeT, b.pulseT = 2, 2, 2, 2 -- stale values must go
  b.weapons[1].cooldown = 0.3
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  t.eq(b.weapons[1].cooldown, 0.2, "weapon 1 cooldown as saved")
  t.eq(b.weapons[2].cooldown, 0.9, "weapon 2 cooldown as saved")
  t.near(b.shieldT, a.shieldT, 1e-9, "shieldT")
  t.near(b.hpRingT, a.hpRingT, 1e-9, "hpRingT")
  t.eq(b.freezeT, 0.04)
  t.eq(b.pulseT, 0.7)
end

function T.apply_restores_weapon_scratch(t)
  local a = playedWorld(10)
  a.weapons[1].side, a.weapons[2].tickT = 1, 0.05
  local b = freshWorld(10)
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  t.eq(b.weapons[1].side, 1)
  t.eq(b.weapons[2].tickT, 0.05)
  t.eq(b.weapons[2].side, nil, "scratch the weapon never had stays absent")
end

function T.apply_restores_the_player_where_it_was_flying(t)
  local a = playedWorld(11)
  a.player.x, a.player.y, a.player.vx, a.player.vy, a.player.invulnT = 301.25, 410.5, -44, 12, 0.6
  local b = freshWorld(11)
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  t.eq(b.player.x, 301.25)
  t.eq(b.player.y, 410.5)
  t.eq(b.player.vx, -44)
  t.eq(b.player.vy, 12)
  t.eq(b.player.invulnT, 0.6)
end

function T.apply_of_a_version_1_save_zeroes_cooldowns_and_timers_and_uses_the_spawn_point(t)
  local run = legacy(roundTrip(RunSave.snapshot(playedWorld(10))))
  local b = freshWorld(10)
  b.shieldT, b.hpRingT, b.freezeT, b.pulseT = 2, 2, 2, 2
  b.player.invulnT = 3
  b.weapons[1].cooldown = 0.3
  t.eq(RunSave.apply(b, run), true)
  for i = 1, #b.weapons do
    t.eq(b.weapons[i].cooldown, 0, "weapon " .. i .. " cooldown")
  end
  t.eq(b.shieldT, 0)
  t.eq(b.hpRingT, 0)
  t.eq(b.freezeT, 0)
  t.eq(b.pulseT, 0)
  t.eq(b.player.x, 240, "spawn point")
  t.eq(b.player.y, 518)
  t.eq(b.player.invulnT, 0)
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

function T.apply_boss_phase_save_resumes_the_fight_with_the_same_boss(t)
  local a = inBossFight(playedWorld(14))
  a.boss.hp = 777.25
  local b = freshWorld(14)
  t.eq(RunSave.apply(b, roundTrip(RunSave.snapshot(a))), true)
  t.eq(b.phase, "boss")
  t.near(b.zoneTime, a.zoneTime, 1e-12)
  t.ok(b.boss, "world.boss is back")
  t.ok(b.boss == b.enemies[indexOfBoss(a)], "and it is the restored enemy, not a copy")
  t.eq(b.boss.hp, 777.25, "no heal")
  t.eq(b.boss.isBoss, true)
  t.ok(b.boss.bossDef == Bosses[a.zone.boss], "the registry's def")
  t.eq(b.boss.def, nil)
  t.eq(b.boss.sprite, Bosses[a.zone.boss].sprite)
  t.eq(b.boss.bt, a.boss.bt)
end

function T.apply_warp_save_resumes_in_the_warp_with_its_clock(t)
  local a = playedWorld(15)
  a.phase, a.warpT, a.bossKills, a.zoneTime = "warp", 1.75, 1, a.zone.duration + 30
  local b = freshWorld(15)
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  t.eq(b.phase, "warp")
  t.eq(b.warpT, 1.75)
  t.eq(b.zoneIndex, a.zoneIndex, "the zone is advanced by the warp ending, as in the original")
  t.ok(b.zone == Zones[a.zoneIndex])
  t.eq(b.zoneTime, a.zoneTime)
  t.eq(b.bossKills, 1)
  t.eq(b.boss, nil)
end

function T.apply_of_a_version_1_save_always_resumes_in_waves(t)
  local b = freshWorld(16)
  b.phase, b.warpT = "warp", 1
  RunSave.apply(b, legacy(roundTrip(RunSave.snapshot(playedWorld(16)))))
  t.eq(b.phase, "waves")
  t.eq(b.warpT, 0)
  t.eq(b.boss, nil)
end

-- a boss fight is only ever saved with the boss in the list
function T.warp_time_matches_what_the_game_starts_a_dead_boss_with(t)
  t.eq(RunSave.WARP_TIME, 2.5, "game.lua sets warpT = 2.5 in boss_killed; keep them equal")
end

function T.apply_resumed_spawns_match_a_run_that_never_paused(t)
  local a = playedWorld(31337)
  local run = roundTrip(RunSave.snapshot(a))
  local before = #a.enemies

  local b = freshWorld(31337)
  RunSave.apply(b, run)
  t.eq(#b.enemies, before, "the enemies on screen at the save come back (they used to be dropped)")
  simulate(a, 12) -- the original keeps playing...
  simulate(b, 12) -- ...the resumed copy plays the same 12 s from the save

  t.eq(#b.enemies, #a.enemies, "same number of enemies in the end")
  t.ok(#b.enemies > before, "fixture must actually spawn something")
  for i = before + 1, #b.enemies do
    local ea, eb = a.enemies[i], b.enemies[i]
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

-- --------------------------------------------------------------- worldDiff
-- The helper the behavioural-identity tests (A2 onwards) lean on: it must see every
-- piece of simulation state, and nothing cosmetic.

function T.worlddiff_is_nil_for_a_world_and_its_restored_copy(t)
  local a = playedWorld(21)
  a.enemies = {} -- entities are saved from A2 on; until then worldDiff rightly sees them
  local b = freshWorld(21)
  RunSave.apply(b, roundTrip(RunSave.snapshot(a)))
  t.eq(Support.worldDiff(a, b), nil)
end

function T.worlddiff_sees_a_moved_player(t)
  local a, b = playedWorld(22), playedWorld(22)
  b.player.x = b.player.x + 0.5
  t.ok(Support.worldDiff(a, b):find("player"), Support.worldDiff(a, b))
end

function T.worlddiff_sees_a_weapon_cooldown_and_a_running_timer(t)
  local a, b = playedWorld(23), playedWorld(23)
  b.weapons[2].cooldown = b.weapons[2].cooldown + 0.1
  t.ok(Support.worldDiff(a, b):find("weapons"), "cooldown")
  local c, d = playedWorld(23), playedWorld(23)
  d.freezeT = 0.2
  t.ok(Support.worldDiff(c, d):find("freezeT"), "hit-stop")
end

function T.worlddiff_sees_the_rng_and_spawner_timers(t)
  local a, b = playedWorld(24), playedWorld(24)
  b.rng.cards:random()
  t.ok(Support.worldDiff(a, b):find("rng"), "rng")
  local c, d = playedWorld(24), playedWorld(24)
  d.spawnerState.timers[1] = d.spawnerState.timers[1] + 0.25
  t.ok(Support.worldDiff(c, d):find("spawnerTimers"), "spawner timers")
end

function T.worlddiff_sees_entities_in_the_lists_and_their_order(t)
  local a, b = playedWorld(25), playedWorld(25)
  a.enemies[1] = { kind = "enemy", x = 10, y = 20, hp = 5, def = { id = "drifter" } }
  a.enemies[2] = { kind = "enemy", x = 30, y = 40, hp = 6, def = { id = "darter" } }
  b.enemies[1] = { kind = "enemy", x = 10, y = 20, hp = 5, def = { id = "drifter" } }
  b.enemies[2] = { kind = "enemy", x = 30, y = 40, hp = 6, def = { id = "darter" } }
  t.eq(Support.worldDiff(a, b), nil, "equal lists")
  b.enemies[1], b.enemies[2] = b.enemies[2], b.enemies[1]
  t.ok(Support.worldDiff(a, b):find("enemies"), "same entities, different order, is a difference")
end

function T.worlddiff_ignores_cosmetic_state(t)
  local a, b = playedWorld(26), playedWorld(26)
  b.shake, b.particles, b.toasts = 9, { { x = 1 } }, { { text = "x" } }
  t.eq(Support.worldDiff(a, b), nil)
end

-- ------------------------------------------------------------ Save helpers

function T.save_run_defaults_to_nil(t)
  Save.reset()
  t.eq(Save.run(), nil)
  t.eq(Save.rawRun(), nil)
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
  Save.setRun({ version = 1, mode = "standard" }) -- truncated / hand-edited
  t.eq(Save.run(), nil)
end

function T.save_clearrun_removes_the_run(t)
  Save.reset()
  Save.setRun(good())
  Save.clearRun()
  t.eq(Save.run(), nil)
  t.eq(Save.rawRun(), nil)
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
