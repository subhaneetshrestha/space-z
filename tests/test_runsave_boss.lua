-- tests/test_runsave_boss.lua — the live field in a run save: the boss, the phase and the warp. Three kinds of test:
--   * behavioural identity: a world and its resumed twin, stepped through the REAL
--     game state, stay equal frame after frame (the "cheat-proof" check);
--   * completeness: every key a live entity ever grows is saved or declared derived;
--   * validation: a hostile entity entry rejects the whole save, never crashes it.
local RunSave = require("src.meta.runsave")
local Entities = require("src.meta.runsave_entities")
local Enemies = require("src.content.enemies")
local Weapons = require("src.content.weapons")
local Bosses = require("src.content.bosses")
local Zones = require("src.content.zones")
local Save = require("src.meta.save")
local Spawner = require("src.systems.spawner")
local Damage = require("src.systems.damage")
local Support = require("tests.support")
local H = require("tests.game_harness")
local S = require("tests.support_runsave")

local roundTrip, updateGame, arena, resumeTwin, identical, indexOf, stepUntil, dropGems = S.roundTrip, S.updateGame, S.arena, S.resumeTwin, S.identical, S.indexOf, S.stepUntil, S.dropGems

local enemy, VALID, NAN, with = S.enemy, S.VALID, S.NAN, S.with
local ebullet = S.ebullet
local T = {}
local test = H.guarded(T)

local STEP = H.STEP

-- ===================================================== the boss and phases (A5)
-- A boss fight and the warp after it are saved as they stand. Before, saving mid-boss
-- put the boss back at full health with an empty field, which made quitting a way out
-- of any attack.

local function zoneOf(bossId)
  for i = 1, #Zones do
    if Zones[i].boss == bossId then return i end
  end
end

-- Into the boss fight of a zone: the real spawner brings the boss in. Weapons are
-- silenced so nothing hurts it, and the player cannot die.
local function bossFight(zoneIndex)
  local w = H.start({ seed = 700 + zoneIndex })
  for i = 1, #w.weapons do w.weapons[i].cooldown = 3000 end
  w.zoneIndex, w.zone = zoneIndex, Zones[zoneIndex]
  -- exactly the end of the timeline: no wave stream spawns another enemy first, so
  -- the field is clear and the spawner brings the boss in on the next frame
  w.zoneTime = w.zone.duration
  w.spawnerState = { timers = {} }
  stepUntil(function() return w.phase == "boss" end, 600)
  return w
end

-- past the entrance and into the pattern
local function intoThePattern(t, w, bt)
  t.ok(stepUntil(function() return w.boss and not w.boss.entering and w.boss.bt >= (bt or 9) end, 3000),
    "fixture: the boss is past its entrance")
end

local function killTheBoss(w)
  w.boss.hp = 1
  Damage.direct(w, w.boss, 1e6, false)
end

-- The sequence that broke the first version of the timer check: a countdown that ran
-- out is left a hair below zero, and the next autosave must still be a valid save.
test("a_save_stays_valid_after_hit_stop_and_i_frames_have_run_out", function(t)
  local w = arena({ "drifter" })
  w.freezeT = 0.05          -- hit-stop, as after an elite or boss kill
  w.player.invulnT = 0.2    -- i-frames, as after a hit
  w.shieldT, w.hpRingT, w.pulseT = 0.1, 0.1, 0.1
  updateGame(60)
  local t0 = { w.freezeT, w.player.invulnT, w.shieldT, w.hpRingT, w.pulseT }
  local below = 0
  for i = 1, #t0 do if t0[i] < 0 then below = below + 1 end end
  t.ok(below > 0, "fixture: the game really leaves these timers below zero")
  local run = roundTrip(RunSave.snapshot(w))
  t.eq(RunSave.validate(run), true, "such a save is valid")
  local twin = resumeTwin(run)
  t.eq(Support.worldDiff(w, twin.world), nil, "and it resumes into the same world")
end)

test("the_whole_field_is_saved_in_the_warp_phase_too", function(t)
  local w = arena({ "drifter", "sentry" })
  dropGems(w)
  updateGame(300)
  w.phase, w.warpT = "warp", 1.5
  local run = RunSave.snapshot(w)
  t.eq(#run.enemies, #w.enemies)
  t.eq(#run.ebullets, #w.ebullets)
  t.eq(#run.pickups, #w.pickups)
  t.ok(#run.enemies > 0 and #run.ebullets > 0 and #run.pickups > 0, "fixture: each list has something")
end)

for i = 1, #Zones do
  local bossId = Zones[i].boss
  test("identity_boss_" .. bossId .. "_fights_the_same_after_a_resume", function(t)
    local w = bossFight(i)
    t.eq(w.phase, "boss", "fixture: the fight began")
    intoThePattern(t, w, 9)
    w.boss.hp = w.boss.maxhp * 0.4 -- second phase
    updateGame(60)
    t.ok(bossId == "mining_leviathan" or #w.ebullets > 0, "fixture: the boss has been shooting")
    identical(t, w, 600)
  end)
end

test("identity_a_boss_saved_during_its_entrance_enters_and_fights_the_same", function(t)
  local w = bossFight(1)
  t.eq(w.boss.entering, true, "fixture: still coming in")
  identical(t, w, 600)
end)

-- the patterns with several states: snapshot inside each one
local BOSS_STATES = {
  mining_leviathan = { "telegraph", "dive", "rise" },
  storm_entity = { "telegraph", "dash", "pulse" },
  war_machine = { "fans", "spiral" },
}
for bossId, states in pairs(BOSS_STATES) do
  for _, state in ipairs(states) do
    test("identity_boss_" .. bossId .. "_saved_in_its_" .. state .. "_state", function(t)
      local w = bossFight(zoneOf(bossId))
      t.ok(stepUntil(function() return w.boss and not w.boss.entering and w.boss.state == state end, 3600),
        "fixture: the boss reaches " .. state)
      identical(t, w, 300)
    end)
  end
end

for _, fraction in ipairs({ 0.9, 0.5, 0.2 }) do
  test("identity_overlord_at_" .. math.floor(fraction * 100) .. "_percent_health", function(t)
    local w = bossFight(#Zones)
    intoThePattern(t, w, 3)
    w.boss.hp = w.boss.maxhp * fraction
    updateGame(30)
    identical(t, w, 600)
  end)
end

test("identity_the_warp_runs_out_and_starts_the_next_zone_the_same", function(t)
  local w = bossFight(1)
  intoThePattern(t, w, 3)
  killTheBoss(w)
  t.eq(w.phase, "warp", "fixture: the boss died")
  t.eq(w.warpT, RunSave.WARP_TIME, "a boss kill starts the warp clock at WARP_TIME")
  updateGame(60)
  identical(t, w, 240) -- 5 s in all: crosses the end of the warp
  t.eq(w.zoneIndex, 2, "fixture: the warp ended and the next zone began")
end)

test("a_warp_saved_after_the_last_boss_plays_out_the_win_once", function(t)
  local w = bossFight(#Zones)
  intoThePattern(t, w, 3)
  killTheBoss(w)
  updateGame(30)
  local run = roundTrip(RunSave.snapshot(w))
  t.ok(run, "the last warp can be saved")
  local runs = Save.data().totalRuns
  local twin = resumeTwin(run)
  for _ = 1, 240 do twin:update(STEP) end
  t.eq(twin.world.phase, "over")
  t.ok(H.gameoverParams() and H.gameoverParams().won, "the game-over screen got a win")
  t.eq(Save.data().totalRuns, runs + 1, "endRun ran exactly once")
  t.eq(Save.run(), nil, "and the finished run left no save")
end)

-- ------------------------------------------------------------ links and events

test("the_resumed_boss_is_world_boss_and_keeps_its_nature", function(t)
  local w = bossFight(3)
  intoThePattern(t, w, 5)
  local twin = resumeTwin(roundTrip(RunSave.snapshot(w)))
  local b = twin.world.boss
  t.ok(b, "world.boss is set")
  t.ok(b == twin.world.enemies[indexOf(w.enemies, w.boss)], "and it is the restored enemy, not a second one")
  t.eq(b.isBoss, true)
  t.ok(b.bossDef == Bosses.war_machine, "the registry's def")
  t.eq(b.def, nil)
  t.eq(b.kind, "enemy")
  t.eq(b.sprite, Bosses.war_machine.sprite)
  local bosses = 0
  for i = 1, #twin.world.enemies do if twin.world.enemies[i].isBoss then bosses = bosses + 1 end end
  t.eq(bosses, 1, "exactly one boss")
end)

test("resuming_a_boss_fight_fires_no_boss_or_zone_events_and_changes_no_counts", function(t)
  local w = bossFight(2)
  intoThePattern(t, w, 5)
  local twin = resumeTwin(roundTrip(RunSave.snapshot(w)))
  local seen = {}
  for _, name in ipairs({ "boss_spawned", "boss_killed", "zone_completed" }) do
    twin.world.events:on(name, function() seen[name] = (seen[name] or 0) + 1 end)
  end
  for _ = 1, 180 do twin:update(STEP) end
  t.eq(seen.boss_spawned, nil, "the boss does not make another entrance")
  t.eq(seen.boss_killed, nil)
  t.eq(seen.zone_completed, nil)
  t.eq(twin.world.bossKills, w.bossKills)
  t.eq(twin.world.kills, w.kills)
end)

test("resuming_a_warp_does_not_complete_the_zone_again", function(t)
  local w = bossFight(1)
  intoThePattern(t, w, 3)
  killTheBoss(w)
  updateGame(40)
  local twin = resumeTwin(roundTrip(RunSave.snapshot(w)))
  t.eq(twin.world.phase, "warp")
  t.eq(twin.world.bossKills, 1)
  local zoneCompleted = 0
  twin.world.events:on("zone_completed", function() zoneCompleted = zoneCompleted + 1 end)
  for _ = 1, 240 do twin:update(STEP) end
  t.eq(zoneCompleted, 0, "it fired when the boss died, before the save")
  t.eq(twin.world.bossKills, 1)
  t.eq(twin.world.zoneIndex, 2)
end)

-- ----------------------------------------------------------------- the music

local function resumeMusic(w)
  local before = #H.music
  resumeTwin(roundTrip(RunSave.snapshot(w)))
  return H.music[before + 1], #H.music - before
end

test("resuming_in_waves_plays_the_zone_music", function(t)
  local w = arena({ "drifter" })
  local call, n = resumeMusic(w)
  t.eq(n, 1)
  t.eq(call[1], "play")
  t.eq(call[2], "zone")
  t.eq(call[3], w.zoneIndex)
end)

test("resuming_a_boss_fight_plays_the_boss_music", function(t)
  local w = bossFight(4)
  intoThePattern(t, w, 3)
  local call, n = resumeMusic(w)
  t.eq(n, 1)
  t.eq(call[1], "play")
  t.eq(call[2], "boss")
  t.eq(call[3], 4)
end)

test("resuming_a_warp_plays_no_music", function(t)
  local w = bossFight(1)
  intoThePattern(t, w, 3)
  killTheBoss(w)
  local call, n = resumeMusic(w)
  t.eq(n, 1)
  t.eq(call[1], "stop", "the boss theme stops when the boss dies")
end)

-- ------------------------------------------------------------- completeness

test("every_key_a_live_boss_grows_is_saved_or_derived", function(t)
  local unknown = {}
  for i = 1, #Zones do
    local w = bossFight(i)
    intoThePattern(t, w, 2)
    w.boss.hp = w.boss.maxhp * 0.4
    for _ = 1, 60 * 30 do -- 30 s: every state of every pattern, both phases
      updateGame(1)
      if w.boss then
        for _, key in ipairs(Entities.unclassifiedBossKeys(w.boss)) do
          unknown[Zones[i].boss .. "." .. key] = true
        end
      end
    end
    -- the next fight starts from a fresh world
    H.teardown()
    H.setup()
  end
  local names = {}
  for k in pairs(unknown) do names[#names + 1] = k end
  table.sort(names)
  t.eq(table.concat(names, ","), "", "a new boss field must be saved or listed as derived")
end)

test("the_boss_completeness_check_catches_a_new_field", function(t)
  local ok = { isBoss = true, bossDef = { behavior = "kessler" }, kind = "enemy", sprite = "s",
    dead = false, x = 1, hp = 2, bt = 3, entering = false, burstT = 1 }
  t.eq(#Entities.unclassifiedBossKeys(ok), 0, "nothing wrong with a plain kessler")
  t.eq(Entities.unclassifiedBossKeys({ isBoss = true, bossDef = { behavior = "kessler" }, mystery = 1 })[1], "mystery")
  -- a field another pattern owns is not this boss's
  local foreign = Entities.unclassifiedBossKeys({ isBoss = true, bossDef = { behavior = "kessler" }, dashX = 1 })
  t.eq(foreign[1], "dashX")
end)

-- ---------------------------------------------------------------- validation

-- what each pattern holds once its init has run
local BOSS_SCRATCH = {
  kessler_swarm = { burstT = 1.1, fanT = 0.4, addT = 3 },
  mining_leviathan = { state = "hover", stateT = 2.5, meteorT = 1.0, baseX = 240,
    hoverOffX = 0, hoverOffY = 0, hoverT = 1.2 },
  war_machine = { state = "fans", stateT = 1.5, shotT = 0.2, spiralA = 3.1, fanShots = 1 },
  asteroid_titan = { burstT = 1.5, addT = 4 },
  storm_entity = { state = "drift", stateT = 1.0, dashes = 2 },
  ring_guardian = { wallT = 1.2, fanT = 0.7, wallFlip = true },
  overlord = { fanT = 1.0, spiralT = 0.05, spiralA = 1.5, radialT = 2.1, addT = 3.3, wallT = 1.9 },
}

-- a valid boss that has finished entering
local function bossEntry(id, over)
  local def = Bosses[id]
  local e = {
    boss = id, x = 240, y = 190, vx = 0, vy = 0, r = def.r, rot = 0, scale = 1, t = 12, bt = 9.5,
    hp = def.hp, maxhp = def.hp, touchDamage = def.touchDamage, xp = def.xpReward,
    flashT = 0, elite = false, entering = false, bossPhase = 1,
  }
  for k, v in pairs(BOSS_SCRATCH[id]) do e[k] = v end
  for k, v in pairs(over or {}) do e[k] = v end
  return e
end

-- a valid save in that boss's zone, mid-fight, with the entry as the only enemy
local function bossRun(id, runOver, entry)
  local z = zoneOf(id)
  local run = Support.validRun2({
    phase = "boss", zoneIndex = z, zoneTime = Zones[z].duration + 10,
    enemies = { entry or bossEntry(id) }, boss = 1,
  })
  for k, v in pairs(runOver or {}) do run[k] = v end
  return run
end

local function warpRun(zoneIndex, over)
  local run = Support.validRun2({
    phase = "warp", warpT = 1.3, zoneIndex = zoneIndex,
    zoneTime = Zones[zoneIndex].duration + 30,
  })
  for k, v in pairs(over or {}) do run[k] = v end
  return run
end

for id in pairs(BOSS_SCRATCH) do
  T["validate_accepts_a_" .. id .. "_fight"] = function(t)
    t.eq(RunSave.validate(bossRun(id)), true)
  end
end

function T.validate_accepts_a_boss_still_making_its_entrance(t)
  local e = bossEntry("kessler_swarm")
  for k in pairs(BOSS_SCRATCH.kessler_swarm) do e[k] = nil end -- init has not run yet
  e.entering, e.y = true, -40
  t.eq(RunSave.validate(bossRun("kessler_swarm", nil, e)), true)
end

function T.validate_accepts_the_two_states_that_carry_a_target(t)
  local lev = bossEntry("mining_leviathan", { state = "dive", diveX = 200 })
  t.eq(RunSave.validate(bossRun("mining_leviathan", nil, lev)), true, "a dive at its column")
  local storm = bossEntry("storm_entity", { state = "dash", dashX = 100 })
  t.eq(RunSave.validate(bossRun("storm_entity", nil, storm)), true, "a dash to its mark")
end

function T.validate_accepts_a_warp_in_any_zone_including_the_last(t)
  for i = 1, #Zones do t.eq(RunSave.validate(warpRun(i)), true, "zone " .. i) end
end

function T.validate_accepts_a_warp_with_the_leftover_field(t)
  local run = warpRun(1, { enemies = { VALID.drift }, ebullets = { ebullet() } })
  t.eq(RunSave.validate(run), true)
end

local BOSS_REJECTS = {
  phase_missing = function() local r = bossRun("kessler_swarm"); r.phase = nil; return r end,
  phase_unknown = function() return bossRun("kessler_swarm", { phase = "over" }) end,
  phase_wrong_type = function() return bossRun("kessler_swarm", { phase = 3 }) end,
  warp_time_missing = function() local r = warpRun(1); r.warpT = nil; return r end,
  warp_time_nan = function() return warpRun(1, { warpT = NAN }) end,
  warp_time_negative = function() return warpRun(1, { warpT = -1 }) end,
  warp_time_above_the_warp = function() return warpRun(1, { warpT = RunSave.WARP_TIME + 1 }) end,
  warp_phase_with_a_spent_clock = function() return warpRun(1, { warpT = 0 }) end,
  warp_time_outside_a_warp = function() return Support.validRun2({ warpT = 1 }) end,
  boss_slot_missing_in_the_boss_phase = function() return bossRun("kessler_swarm", { boss = false }) end,
  boss_slot_wrong_type = function() return bossRun("kessler_swarm", { boss = "1" }) end,
  boss_slot_out_of_range = function() return bossRun("kessler_swarm", { boss = 2 }) end,
  boss_slot_at_a_plain_enemy = function()
    return bossRun("kessler_swarm", { enemies = { VALID.drift, bossEntry("kessler_swarm") }, boss = 1 })
  end,
  boss_phase_with_no_boss_entry = function() return bossRun("kessler_swarm", { enemies = {}, boss = 1 }) end,
  boss_in_the_waves_phase = function() return bossRun("kessler_swarm", { phase = "waves" }) end,
  boss_in_the_warp_phase = function() return bossRun("kessler_swarm", { phase = "warp", warpT = 1 }) end,
  two_bosses = function()
    return bossRun("kessler_swarm", { enemies = { bossEntry("kessler_swarm"), bossEntry("kessler_swarm") } })
  end,
  boss_of_another_zone = function()
    return bossRun("kessler_swarm", { zoneIndex = zoneOf("overlord"), zoneTime = Zones[zoneOf("overlord")].duration + 5 })
  end,
  boss_phase_before_the_zone_timeline_ended = function()
    return bossRun("kessler_swarm", { zoneTime = Zones[zoneOf("kessler_swarm")].duration - 20 })
  end,
  warp_before_the_zone_timeline_ended = function() return warpRun(1, { zoneTime = 3 }) end,
  boss_id_unknown = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { boss = "deathstar" })) end,
  boss_id_is_an_enemy = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { boss = "drifter" })) end,
  boss_id_wrong_type = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { boss = 4 })) end,
  boss_with_an_enemy_def_too = function()
    return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { def = "drifter" }))
  end,
  boss_unknown_key = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { mystery = 1 })) end,
  boss_sprite_is_not_saved = function()
    return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { sprite = "boss_kessler_core" }))
  end,
  boss_is_elite = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { elite = true })) end,
  boss_hp_missing = function()
    local e = bossEntry("kessler_swarm"); e.hp = nil
    return bossRun("kessler_swarm", nil, e)
  end,
  boss_hp_zero = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { hp = 0 })) end,
  boss_hp_above_max = function()
    return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { hp = Bosses.kessler_swarm.hp + 5 }))
  end,
  boss_hp_nan = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { hp = NAN })) end,
  boss_x_off_screen = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { x = 5000 })) end,
  boss_clock_negative = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { bt = -1 })) end,
  boss_entering_not_a_boolean = function()
    return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { entering = 1 }))
  end,
  boss_entering_missing = function()
    local e = bossEntry("kessler_swarm"); e.entering = nil
    return bossRun("kessler_swarm", nil, e)
  end,
  boss_phase_number_unknown = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { bossPhase = 3 })) end,
  boss_phase_number_fractional = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { bossPhase = 1.5 })) end,
  -- the pattern code reads these every frame, so a pattern with a field missing, or with
  -- another pattern's field, would index nil or misbehave on the first frame
  entrance_with_pattern_state = function()
    return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { entering = true, y = -40 }))
  end,
  kessler_with_another_patterns_field = function()
    return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { state = "hover" }))
  end,
  leviathan_state_unknown = function()
    return bossRun("mining_leviathan", nil, bossEntry("mining_leviathan", { state = "fans" }))
  end,
  leviathan_diving_without_a_column = function()
    return bossRun("mining_leviathan", nil, bossEntry("mining_leviathan", { state = "dive" }))
  end,
  leviathan_telegraph_without_a_column = function()
    return bossRun("mining_leviathan", nil, bossEntry("mining_leviathan", { state = "telegraph" }))
  end,
  storm_dashing_without_a_mark = function()
    return bossRun("storm_entity", nil, bossEntry("storm_entity", { state = "dash" }))
  end,
  storm_state_unknown = function()
    return bossRun("storm_entity", nil, bossEntry("storm_entity", { state = "dive" }))
  end,
  storm_dashes_negative = function() return bossRun("storm_entity", nil, bossEntry("storm_entity", { dashes = -1 })) end,
  warmachine_state_unknown = function()
    return bossRun("war_machine", nil, bossEntry("war_machine", { state = "hover" }))
  end,
  warmachine_shots_fractional = function()
    return bossRun("war_machine", nil, bossEntry("war_machine", { fanShots = 1.5 }))
  end,
  guardian_flip_not_a_boolean = function()
    return bossRun("ring_guardian", nil, bossEntry("ring_guardian", { wallFlip = 1 }))
  end,
  timer_runaway = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { burstT = 1e9 })) end,
  timer_far_negative = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { burstT = -1e9 })) end,
  timer_nan = function() return bossRun("kessler_swarm", nil, bossEntry("kessler_swarm", { fanT = NAN })) end,
  spiral_angle_absurd = function() return bossRun("overlord", nil, bossEntry("overlord", { spiralA = 1e30 })) end,
  hover_offset_absurd = function()
    return bossRun("mining_leviathan", nil, bossEntry("mining_leviathan", { hoverOffX = 1e9 }))
  end,
}

-- every field a finished entrance gives a pattern is required, one case each
for id, scratch in pairs(BOSS_SCRATCH) do
  for key in pairs(scratch) do
    BOSS_REJECTS["scratch_" .. id .. "_without_" .. key] = function()
      local e = bossEntry(id)
      e[key] = nil
      return bossRun(id, nil, e)
    end
  end
end

for name, build in pairs(BOSS_REJECTS) do
  T["validate_rejects_" .. name] = function(t)
    t.eq(RunSave.validate(build()), false, name)
  end
end

function T.validate_never_throws_on_hostile_boss_entries(t)
  local bad = { boss = {}, 5, false, { boss = "kessler_swarm" }, bossEntry("kessler_swarm", { hp = {} }) }
  for i = 1, #bad do
    local ok, result = pcall(RunSave.validate, bossRun("kessler_swarm", { enemies = { bad[i] } }))
    t.ok(ok, "case " .. i .. " must not throw")
    t.eq(result, false, "case " .. i)
  end
end


return T
