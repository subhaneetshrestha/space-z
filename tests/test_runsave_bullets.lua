-- tests/test_runsave_bullets.lua — the live field in a run save: player and enemy bullets. Three kinds of test:
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
local Pool = require("src.core.pool")
local Support = require("tests.support")
local H = require("tests.game_harness")
local S = require("tests.support_runsave")

local roundTrip, updateGame, arena, resumeTwin, identical, withDurableEnemies, indexOf, stepUntil = S.roundTrip, S.updateGame, S.arena, S.resumeTwin, S.identical, S.withDurableEnemies, S.indexOf, S.stepUntil

local enemy, VALID, NAN, with = S.enemy, S.VALID, S.NAN, S.with
local ebullet = S.ebullet
local T = {}
local test = H.guarded(T)

local STEP = H.STEP

-- ============================================================ bullets (A3)
-- Player bullets (with a homing missile's target) and enemy bullets.

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

-- The game kills a bullet when its life is <= 0 and a gem or drone cooldown when it is
-- over, so a live one can hold a value a hair above zero: float residue of
-- `life - dt` repeated. A real run produced life = 1.04e-16; a lower bound of its own
-- (the first version used 1e-9) rejects a save the game wrote itself.
function T.validate_accepts_a_bullet_whose_life_is_a_hair_above_zero(t)
  t.eq(RunSave.validate(runWithBullets({ bullet({ life = 1.0408340855860843e-16 }) })), true)
  t.eq(RunSave.validate(runWithBullets({}, { ebullet({ life = 5e-17 }) })), true)
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

return T
