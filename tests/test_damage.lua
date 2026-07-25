-- tests/test_damage.lua — crit math, kill flow, invuln gating, blackhole mode.
local Damage = require("src.systems.damage")
local Events = require("src.core.events")

local T = {}

local alwaysCrit = { chance = function() return true end }
local neverCrit = { chance = function() return false end }

local function fakeWorld(over)
  local w = {
    mode = "standard",
    events = Events.new(),
    rng = { misc = neverCrit },
    stats = { damageMult = 1, critChance = 0.05, critMult = 2.0 },
    player = { hp = 100, maxhp = 100, invulnT = 0, dead = false },
    kills = 0, bossKills = 0, noDamage = true, shake = 0,
    phase = "waves",
    boss = nil,
  }
  for k, v in pairs(over or {}) do w[k] = v end
  return w
end

local function fakeEnemy(hp)
  return { hp = hp or 100, maxhp = hp or 100, x = 0, y = 0, flashT = 0 }
end

function T.plain_hit_math(t)
  local w = fakeWorld()
  local e = fakeEnemy(100)
  Damage.hitEnemy(w, e, { damage = 10, x = 0, y = 0 })
  t.eq(e.hp, 90, "10 damage applied")
  t.ok(e.flashT > 0, "hit flash set")
end

function T.damage_mult_and_crit(t)
  local w = fakeWorld({ rng = { misc = alwaysCrit } })
  w.stats.damageMult = 1.5
  w.stats.critMult = 2.0
  local e = fakeEnemy(100)
  Damage.hitEnemy(w, e, { damage = 10, x = 0, y = 0 })
  -- 10 * 1.5 * 2.0 = 30
  t.eq(e.hp, 70, "damageMult and critMult multiply")
end

function T.kill_emits_and_counts(t)
  local w = fakeWorld()
  local killed = nil
  w.events:on("enemy_killed", function(e) killed = e end)
  local e = fakeEnemy(5)
  Damage.hitEnemy(w, e, { damage = 10, x = 0, y = 0 })
  t.eq(e.dead, true, "enemy dies")
  t.eq(w.kills, 1, "kill counted")
  t.eq(killed, e, "enemy_killed emitted with the enemy")
end

function T.boss_kill_flow(t)
  local w = fakeWorld()
  local bossKilled = false
  w.events:on("boss_killed", function() bossKilled = true end)
  local e = fakeEnemy(5)
  e.isBoss = true
  w.boss = e
  Damage.hitEnemy(w, e, { damage = 10, x = 0, y = 0 })
  t.eq(w.bossKills, 1, "boss kill counted")
  t.eq(w.boss, nil, "world.boss cleared")
  t.ok(bossKilled, "boss_killed emitted")
end

function T.entering_boss_immune(t)
  local w = fakeWorld()
  local e = fakeEnemy(100)
  e.entering = true
  Damage.hitEnemy(w, e, { damage = 10, x = 0, y = 0 })
  t.eq(e.hp, 100, "entering enemies can't be hit")
end

function T.direct_no_crit_flag(t)
  local w = fakeWorld({ rng = { misc = alwaysCrit } })
  local e = fakeEnemy(100)
  Damage.direct(w, e, 10, false)
  t.eq(e.hp, 90, "canCrit=false skips the crit roll")
end

function T.player_hit_and_invuln(t)
  local w = fakeWorld()
  local damaged = 0
  w.events:on("player_damaged", function() damaged = damaged + 1 end)
  Damage.hitPlayer(w, 20, nil)
  t.eq(w.player.hp, 80, "player takes damage")
  t.eq(w.noDamage, false, "no-damage flag flips")
  t.ok(w.player.invulnT > 0, "i-frames granted")
  Damage.hitPlayer(w, 20, nil)
  t.eq(w.player.hp, 80, "invuln gates the second hit")
  t.eq(damaged, 1, "only one player_damaged event")
end

function T.player_death(t)
  local w = fakeWorld()
  local died = false
  w.events:on("player_died", function() died = true end)
  Damage.hitPlayer(w, 200, nil)
  t.eq(w.player.hp, 0, "hp clamps at 0")
  t.eq(w.player.dead, true, "player dead")
  t.ok(died, "player_died emitted")
end

function T.blackhole_one_hit(t)
  local w = fakeWorld({ mode = "blackhole" })
  Damage.hitPlayer(w, 1, nil)
  t.eq(w.player.dead, true, "any hit is lethal in blackhole mode")
end

return T
