-- tests/test_game_resume.lua — states/game.lua's save integration, through the REAL
-- game state (see tests/game_harness.lua): the resume path, Game.saveRun gating,
-- autosave, and clearing the save on death / win.
local StateM = require("src.core.state")
local Save = require("src.meta.save")
local RunSave = require("src.meta.runsave")
local Zones = require("src.content.zones")
local json = require("lib.json")
local Support = require("tests.support")
local H = require("tests.game_harness")

local T = {}
local test = H.guarded(T)

local STEP = H.STEP
local start, step, seconds, played = H.start, H.step, H.seconds, H.played

-- ------------------------------------------------------------------- resume

test("a_new_run_has_no_countdown", function(t)
  start()
  t.eq(StateM.current(), H.Game)
end)

test("resume_restores_the_run_and_shows_the_countdown", function(t)
  local old = played("aegis")
  local run = json.decode(json.encode(RunSave.snapshot(old)))

  Save.data().settings.ship = "pathfinder" -- hangar changed since: the run's ship wins
  StateM.switch("game", { resume = run, mode = run.mode, seed = run.seed })

  t.eq(StateM.current(), H.Countdown, "3-2-1 is up")
  local w = H.Game.world
  t.ok(w ~= old, "a new world was built")
  t.eq(w.player.shipDef.id, "aegis")
  t.eq(Support.firstDiff(RunSave.snapshot(w), RunSave.snapshot(old)), nil,
    "restored world matches the saved one field for field")
end)

test("resumed_world_is_frozen_until_the_countdown_ends", function(t)
  local run = RunSave.snapshot(played())
  StateM.switch("game", { resume = run, seed = run.seed })
  local w = H.Game.world
  local time0 = w.time
  seconds(2.5)
  t.eq(StateM.current(), H.Countdown, "still counting")
  t.eq(w.time, time0, "no simulation during 3-2-1")
  seconds(0.6)
  t.eq(StateM.current(), H.Game, "control returned")
  step(10)
  t.ok(w.time > time0, "the run advances again")
end)

-- Saving mid-boss used to rewind the fight: the boss came back at full health and the
-- field was cleared, so quitting was a way out of any attack. The fight resumes as it was.
test("a_boss_fight_save_resumes_the_same_boss_at_the_health_it_had", function(t)
  local w = start({ seed = 31 })
  w.zoneTime = w.zone.duration - 0.05
  local n = 0
  while w.phase ~= "boss" and n < 600 do step(); n = n + 1 end
  t.eq(w.phase, "boss", "fixture: the boss was triggered")
  w.boss.hp = 1 -- nearly dead when the player quits
  t.eq(H.Game.saveRun(), true)

  local run = Save.run()
  t.ok(run, "a boss fight is a valid save")
  StateM.switch("game", { resume = run, seed = run.seed })
  local w2 = H.Game.world
  t.eq(StateM.current(), H.Countdown, "3-2-1 first")
  t.eq(w2.phase, "boss", "resumed inside the fight, not rewound to its arrival")
  t.ok(w2.boss, "the boss is back")
  t.eq(w2.boss.hp, 1, "with the health it had: saving is not a heal")
  t.eq(w2.boss.maxhp, w.boss.maxhp)
end)

test("resuming_does_not_count_as_a_new_run", function(t)
  local run = RunSave.snapshot(played())
  local runsBefore = Save.data().totalRuns
  StateM.switch("game", { resume = run, seed = run.seed })
  t.eq(Save.data().totalRuns, runsBefore)
end)

test("an_invalid_resume_falls_back_to_a_plain_new_run", function(t)
  local run = RunSave.snapshot(played())
  run.weapons[1].id = "bfg"
  StateM.switch("game", { resume = run, seed = 5 })
  t.eq(StateM.current(), H.Game, "no countdown for a run that was not restored")
  t.eq(H.Game.world.level, 1)
end)

-- ------------------------------------------------------------------ saveRun

test("saverun_writes_the_active_run", function(t)
  local w = played()
  t.eq(H.Game.saveRun(), true)
  local run = Save.run()
  t.ok(run, "a valid run is stored")
  t.eq(run.hp, 37.5)
  t.eq(run.level, 6)
  t.eq(run.zoneTime, w.zoneTime)
end)

test("saverun_counts_an_open_level_up_draft", function(t)
  played()
  H.Game.world.pendingLevelUps = 0
  StateM.push("levelup") -- the draft is on screen; it was already taken off the count
  t.eq(H.Game.saveRun(), true)
  t.eq(Save.run().pendingLevelUps, 1)
end)

test("saverun_does_nothing_once_the_game_state_is_left", function(t)
  played()
  StateM.switch("menu") -- Game.world is still around, but the run is over
  Save.clearRun()
  t.eq(H.Game.saveRun(), false)
  t.eq(Save.run(), nil, "a stale world must never be written")
end)

test("saverun_skips_daily_runs", function(t)
  start({ daily = true, mode = "standard" })
  seconds(12)
  t.eq(H.Game.saveRun(), false)
  t.eq(Save.run(), nil)
end)

test("saverun_skips_autopilot_runs_even_through_autosave", function(t)
  start({ autopilot = true })
  seconds(25)
  t.eq(H.Game.saveRun(), false)
  t.eq(Save.run(), nil, "smoke runs write no run")
end)

-- ----------------------------------------------------------------- autosave

test("autosave_writes_about_every_ten_seconds", function(t)
  start()
  seconds(9.5)
  t.eq(Save.run(), nil, "not yet")
  seconds(1.0)
  local first = Save.run()
  t.ok(first, "written at ~10 s")
  seconds(10.0)
  t.ok(Save.run().time > first.time + 5, "and refreshed ~10 s later")
end)

-- ----------------------------------------------------------------- clearing

test("player_death_clears_the_save", function(t)
  local w = played()
  H.Game.saveRun()
  t.ok(Save.run(), "precondition: a save exists")
  w.player.dead = true
  w.events:emit("player_died")
  t.eq(Save.run(), nil)
  t.eq(H.Game.saveRun(), false, "and a dead run can not be saved again")
  t.eq(Save.run(), nil)
end)

-- ------------------------------------------------- no way out of an attack (the point)
-- Saving and continuing used to clear the field. These go through the real flow a
-- player would use: Esc, SAVE & QUIT, then CONTINUE (the menu does exactly this switch).

local Spawner = require("src.systems.spawner")

-- Esc, SAVE & QUIT, then what the menu's CONTINUE row does; returns the resumed world
local function pauseQuitContinue()
  StateM.keypressed("escape")
  H.Pause.selected = 2
  StateM.keypressed("return")
  local run = Save.run()
  StateM.switch("game", { resume = run, mode = run.mode, seed = run.seed })
  return H.Game.world
end

-- the countdown, played out through the real state stack
local function throughTheCountdown()
  local n = 0
  while StateM.current() == H.Countdown and n < 600 do step(); n = n + 1 end
end

test("an_enemy_bullet_one_frame_from_the_ship_still_lands_after_save_quit_and_continue", function(t)
  local w = start({ seed = 12 })
  w.player.invulnT = 0
  local hp = w.player.hp
  local b = w.pools.ebullets:acquire()
  b.kind, b.x, b.y, b.vx, b.vy, b.r = "ebullet", w.player.x, w.player.y - 16, 0, 300, 6
  b.sprite, b.rot, b.scale, b.t, b.dead, b.damage, b.life = "bullet_enemy", 0, 1, 0, false, 9, 5
  w.ebullets[#w.ebullets + 1] = b

  local w2 = pauseQuitContinue()
  t.eq(#w2.ebullets, 1, "the bullet came along")
  throughTheCountdown()
  t.eq(StateM.current(), H.Game, "control is back")
  t.eq(w2.player.hp, hp, "nothing happened during the 3-2-1")
  step(2)
  t.eq(w2.player.hp, hp - 9, "and the hit lands on the first frames after it: the save was no escape")
end)

test("the_whole_field_is_frozen_during_the_countdown", function(t)
  local w = start({ seed = 14 })
  for i = 1, #w.weapons do w.weapons[i].cooldown = 3000 end
  for i, id in ipairs({ "drifter", "sentry", "stinger", "lunar_hopper", "meteor" }) do
    Spawner.spawnEnemy(w, id, 60 + i * 70, 90 + i * 15)
  end
  seconds(6)
  t.ok(#w.enemies >= 5 and #w.ebullets > 0, "fixture: enemies and enemy bullets on screen")

  Save.data().tutorialDone = true
  H.Game.saveRun()
  local run = Save.run()
  StateM.switch("game", { resume = run, mode = run.mode, seed = run.seed })
  local w2 = H.Game.world
  local before = Support.worldView(w2)
  seconds(2.8)
  t.eq(StateM.current(), H.Countdown, "still counting")
  t.eq(Support.firstDiff(Support.worldView(w2), before), nil,
    "nothing moved, spawned, fired or ticked while the 3-2-1 ran")
  throughTheCountdown()
  step(30)
  t.ok(Support.firstDiff(Support.worldView(w2), before) ~= nil, "and then the run goes on")
end)

test("steering_is_reset_when_the_countdown_hands_control_back", function(t)
  -- a finger down when the pause opens never reports its release to the game (the pause
  -- is on top), so its latch must be dropped on the way back or the ship would jump
  start({ seed = 15 })
  local input = H.Game.input
  local resets = 0
  local original = input.reset
  input.reset = function(self, ...)
    resets = resets + 1
    return original(self, ...)
  end
  StateM.touchpressed(1, 240, 600)
  StateM.keypressed("escape")   -- pause
  StateM.keypressed("escape")   -- RESUME: through the 3-2-1
  t.eq(StateM.current(), H.Countdown)
  local before = resets
  throughTheCountdown()
  t.eq(StateM.current(), H.Game)
  t.ok(resets > before, "game:resume ran as the countdown ended and cleared the steering")
end)

test("a_resume_from_a_save_starts_with_fresh_steering", function(t)
  local w = start({ seed = 16 })
  StateM.touchpressed(1, 240, 600)
  local old = H.Game.input
  pauseQuitContinue()
  t.ok(H.Game.input ~= old, "the resumed run has its own input state, no latched finger from before")
end)

test("a_boss_wall_row_one_frame_from_the_ship_still_hits_after_a_resume", function(t)
  local w = H.bossFight(6) -- the Ring Guardian: rows of ice with gaps
  local wall
  H.stepUntil(function()
    for i = 1, #w.ebullets do
      if w.ebullets[i].vx == 0 and w.ebullets[i].vy >= 140 and w.ebullets[i].y > 40 then
        wall = w.ebullets[i]
        return true
      end
    end
  end, 3000)
  t.ok(wall, "fixture: a wall of ice is falling")
  -- put the ship just below that block: it touches on the next frames
  w.player.invulnT = 0
  w.player.x, w.player.y = wall.x, wall.y + 16
  local hp = w.player.hp
  local damage = wall.damage

  local w2 = pauseQuitContinue()
  throughTheCountdown()
  step(3)
  t.eq(w2.player.hp, hp - damage, "the block lands: quitting did not clear the wall")
end)

test("a_boss_dash_across_the_ship_still_connects_after_a_resume", function(t)
  local w = H.bossFight(5) -- the Great Storm dashes across the sky
  t.ok(H.stepUntil(function() return w.boss.state == "dash" end, 3600), "fixture: the boss is dashing")
  w.player.invulnT = 0
  local b = w.boss
  w.player.x, w.player.y = (b.x + b.dashX) / 2, b.y -- in the middle of its path
  local run = RunSave.snapshot(w)
  t.ok(run, "fixture: saveable")
  local hp = w.player.hp

  local twin = H.resumeTwin(json.decode(json.encode(run)))
  for _ = 1, 40 do
    H.Game:update(STEP)
    twin:update(STEP)
  end
  t.ok(w.player.hp < hp, "fixture: the dash hit the ship in the original")
  t.eq(twin.world.player.hp, w.player.hp, "and the resumed copy took exactly the same damage")
  t.eq(Support.worldDiff(w, twin.world), nil)
end)

test("a_resumed_run_autosaves_run_json_and_never_touches_save_json", function(t)
  local w = H.played()
  Save.data().tutorialDone = true
  H.Game.saveRun()
  local run = Save.run()
  Support.withMemoryFs(function(fs)
    StateM.switch("game", { resume = run, mode = run.mode, seed = run.seed })
    throughTheCountdown()
    seconds(25) -- two autosaves
    t.ok(#fs.writes >= 2, "autosaved while playing")
    for _, name in ipairs(fs.writes) do
      t.eq(name, "run.json", "only the run is rewritten, never the permanent progress")
    end
  end)
end)

-- ------------------------------------------- a hit deletes the save (SPEC.md Part C)
-- Killing the app just before a lethal hit used to resume the autosave from up to 10 s
-- earlier. Death already deletes the save the same frame; now so does every hit, so a
-- hit that has landed cannot be undone by reloading.

local Damage = require("src.systems.damage")

-- an enemy bullet already on the ship: the next frame's collision hits it
local function bulletOnTheShip(w, damage)
  local b = w.pools.ebullets:acquire()
  b.kind, b.x, b.y, b.vx, b.vy, b.r = "ebullet", w.player.x, w.player.y, 0, 0, 6
  b.sprite, b.rot, b.scale, b.t, b.dead, b.damage, b.life = "bullet_enemy", 0, 1, 0, false, damage, 5
  w.ebullets[#w.ebullets + 1] = b
end

test("a_hit_that_costs_hull_deletes_the_save", function(t)
  local w = start({ seed = 21 })
  w.player.invulnT = 0
  H.Game.saveRun()
  t.ok(Save.run(), "fixture: a save exists before the hit")
  local hp = w.player.hp
  Damage.hitPlayer(w, 5, {})
  t.eq(w.player.hp, hp - 5, "fixture: the hit cost hull")
  t.eq(Save.run(), nil, "the save from before the hit is gone")
  t.eq(Save.rawRun(), nil, "from disk too")
end)

test("a_hit_a_shield_absorbs_deletes_the_save_too", function(t)
  local w = start({ seed = 22 })
  w.player.invulnT = 0
  w.stats.shieldLevel, w.shieldT = 1, 0
  H.Game.saveRun()
  local hp = w.player.hp
  Damage.hitPlayer(w, 5, {})
  t.eq(w.player.hp, hp, "fixture: the shield took it")
  t.ok(w.shieldT > 0, "fixture: and is now recharging")
  t.eq(Save.run(), nil, "reloading would hand the shield back, so that save is gone as well")
end)

test("a_hit_while_invulnerable_changes_nothing_and_deletes_nothing", function(t)
  local w = start({ seed = 23 }) -- the harness keeps the ship invulnerable
  H.Game.saveRun()
  local hp = w.player.hp
  Damage.hitPlayer(w, 5, {})
  t.eq(w.player.hp, hp)
  t.ok(Save.run(), "nothing happened to the ship, so the save is still true")
end)

test("a_real_bullet_collision_deletes_the_save", function(t)
  local w = start({ seed = 24 })
  w.player.invulnT = 0
  H.Game.saveRun()
  bulletOnTheShip(w, 9)
  local hp = w.player.hp
  step(1)
  t.eq(w.player.hp, hp - 9, "fixture: the bullet hit")
  t.eq(Save.run(), nil)
end)

test("an_autosave_on_the_frame_of_the_hit_writes_the_state_after_it", function(t)
  local w = start({ seed = 25 })
  w.player.invulnT = 0
  H.Game.saveRun()
  bulletOnTheShip(w, 9)
  H.Game.saveT = STEP / 2 -- the autosave falls due in the very same update as the collision
  local hp = w.player.hp
  step(1)
  t.eq(w.player.hp, hp - 9, "fixture: the bullet hit")
  local run = Save.run()
  t.ok(run, "the autosave came after the deletion and wrote a fresh save")
  t.eq(run.hp, hp - 9, "of the moment after the hit, never the one before it")
end)

test("after_a_hit_the_next_autosave_and_a_pause_write_fresh_saves", function(t)
  local w = start({ seed = 26 })
  w.player.invulnT = 0
  H.Game.saveRun()
  Damage.hitPlayer(w, 5, {})
  t.eq(Save.run(), nil, "fixture: deleted by the hit")
  w.player.invulnT = 1e9 -- no further hits while the clock runs
  seconds(11)
  local run = Save.run()
  t.ok(run, "the autosave wrote a save again")
  t.near(run.hp, w.player.hp, 1, "of the post-hit hull")

  Save.clearRun()
  StateM.keypressed("escape")
  t.ok(Save.run(), "and so does the pause menu")
  t.eq(Save.run().hp, w.player.hp)
end)

test("the_first_hit_after_a_resume_deletes_the_save_it_resumed_from", function(t)
  start({ seed = 27 })
  local w2 = pauseQuitContinue()
  t.ok(Save.run(), "fixture: the save the run came from is still on disk")
  w2.player.invulnT = 0
  Damage.hitPlayer(w2, 5, {})
  t.eq(Save.run(), nil, "one hit and the pre-hit state is no longer loadable")
end)

test("death_still_deletes_the_save_at_once", function(t)
  local w = start({ seed = 28 })
  w.player.invulnT = 0
  H.Game.saveRun()
  Damage.hitPlayer(w, 1e6, {})
  t.eq(w.player.dead, true)
  t.eq(Save.run(), nil)
end)

-- A run that can never be saved (autopilot, which is what `--smoke` plays, or a daily run)
-- must never delete the saved run of another session either. Deleting on a hit once did, and
-- one `--smoke` run on a developer machine erased the real run.json.
for _, kind in ipairs({ "autopilot", "daily" }) do
  local function unsaveable(seed)
    local w = start({ seed = seed, autopilot = kind == "autopilot", daily = kind == "daily" })
    w.player.invulnT = 0
    Save.setRun(Support.validRun2()) -- the saved run of some earlier, separate session
    return w
  end

  test("a_" .. kind .. "_run_taking_a_hull_hit_leaves_the_saved_run_alone", function(t)
    local w = unsaveable(31)
    Damage.hitPlayer(w, 5, {})
    t.ok(Save.run(), "the other session's save survives")
  end)

  test("a_" .. kind .. "_run_having_a_shield_absorb_a_hit_leaves_the_saved_run_alone", function(t)
    local w = unsaveable(32)
    w.stats.shieldLevel, w.shieldT = 1, 0
    Damage.hitPlayer(w, 5, {})
    t.ok(w.shieldT > 0, "fixture: the shield took it")
    t.ok(Save.run(), "the other session's save survives")
  end)

  test("a_" .. kind .. "_run_dying_leaves_the_saved_run_alone", function(t)
    local w = unsaveable(33)
    Damage.hitPlayer(w, 1e6, {})
    t.eq(w.player.dead, true, "fixture: the ship died")
    t.ok(Save.run(), "the other session's save survives")
  end)

  test("a_" .. kind .. "_run_finishing_leaves_the_saved_run_alone", function(t)
    local w = unsaveable(34)
    w.phase, w.zoneIndex, w.zone = "warp", #Zones, Zones[#Zones]
    w.warpT = STEP / 2
    step(3)
    t.eq(w.phase, "over", "fixture: the run ended")
    t.ok(Save.run(), "the other session's save survives")
  end)
end

test("a_win_clears_the_save_and_counts_the_run_once", function(t)
  local w = played()
  H.Game.saveRun()
  t.ok(Save.run(), "precondition: a save exists")
  local runsBefore = Save.data().totalRuns
  w.phase, w.zoneIndex, w.zone = "warp", #Zones, Zones[#Zones]
  w.warpT = STEP / 2
  step(2)
  t.eq(Save.run(), nil, "winning clears the save")
  t.eq(Save.data().totalRuns, runsBefore + 1, "endRun ran exactly once")
  t.ok(H.gameoverParams() and H.gameoverParams().won, "game-over screen got a win")
end)

return T
