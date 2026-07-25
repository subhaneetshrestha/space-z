-- tests/test_effects.lua — slow, coolant, shield capacitor, AoE splash.
local Damage = require("src.systems.damage")
local Movement = require("src.systems.movement")
local Collision = require("src.systems.collision")
local Events = require("src.core.events")
local Enemies = require("src.content.enemies")

local T = {}

local neverCrit = { chance = function() return false end }

local function fakeWorld(over)
  local w = {
    mode = "standard",
    events = Events.new(),
    rng = { misc = neverCrit },
    stats = { damageMult = 1, critChance = 0, critMult = 2, slowBonus = 0, shieldLevel = 0 },
    player = { hp = 100, maxhp = 100, invulnT = 0, dead = false, x = 240, y = 600, vx = 0, vy = 0, t = 0 },
    kills = 0, bossKills = 0, noDamage = true, shake = 0,
    phase = "waves", boss = nil, shieldT = 0,
    enemies = {}, bullets = {}, ebullets = {}, pickups = {},
    time = 0, zone = {},
  }
  for k, v in pairs(over or {}) do w[k] = v end
  return w
end

function T.cryo_bullet_applies_slow(t)
  local w = fakeWorld()
  local e = { hp = 100, maxhp = 100, x = 0, y = 0, flashT = 0 }
  Damage.hitEnemy(w, e, { damage = 5, x = 0, y = 0, slowT = 1.5, slowMult = 0.5 })
  t.near(e.slowT, 1.5, 1e-9, "slow applied")
  t.near(e.slowMult, 0.5, 1e-9, "slow multiplier stored")
end

function T.bosses_resist_slow(t)
  local w = fakeWorld()
  local e = { hp = 1000, maxhp = 1000, x = 0, y = 0, flashT = 0, isBoss = true }
  Damage.hitEnemy(w, e, { damage = 5, x = 0, y = 0, slowT = 1.5, slowMult = 0.5 })
  t.eq(e.slowT, nil, "bosses are never slowed")
end

function T.coolant_bonus_vs_slowed(t)
  local w = fakeWorld()
  w.stats.slowBonus = 0.30
  local e = { hp = 100, maxhp = 100, x = 0, y = 0, flashT = 0, slowT = 1, slowMult = 0.5 }
  Damage.direct(w, e, 10, false)
  t.near(e.hp, 87, 1e-9, "10 * 1.3 = 13 damage vs slowed")
  local e2 = { hp = 100, maxhp = 100, x = 0, y = 0, flashT = 0 }
  Damage.direct(w, e2, 10, false)
  t.near(e2.hp, 90, 1e-9, "no bonus vs unslowed")
end

function T.slow_dilates_enemy_time(t)
  local w = fakeWorld()
  local mk = function(slow)
    local e = { kind = "enemy", def = Enemies.shard, x = 100, y = 100,
                vx = 0, vy = 0, r = 10, rot = 0, t = 0, scale = 1, flashT = 0 }
    if slow then e.slowT, e.slowMult = 5, 0.5 end
    return e
  end
  local fast, slow = mk(false), mk(true)
  w.enemies = { fast, slow }
  for _ = 1, 60 do Movement.update(w, 1 / 60) end -- 1 second
  local fastMoved = fast.y - 100
  local slowMoved = slow.y - 100
  t.near(slowMoved, fastMoved * 0.5, 1.0, "slowed enemy covers half the distance")
end

function T.shield_blocks_then_recharges(t)
  local w = fakeWorld()
  w.stats.shieldLevel = 2
  local blocked, damaged = 0, 0
  w.events:on("shield_blocked", function() blocked = blocked + 1 end)
  w.events:on("player_damaged", function() damaged = damaged + 1 end)

  Damage.hitPlayer(w, 30, nil)
  t.eq(w.player.hp, 100, "shield ate the hit")
  t.eq(w.noDamage, true, "no-damage flag survives a shielded hit")
  t.near(w.shieldT, 10, 1e-9, "level 2 recharge = 10s")
  t.eq(blocked, 1, "shield_blocked emitted")
  t.eq(damaged, 0, "player_damaged not emitted")

  w.player.invulnT = 0 -- clear block i-frames
  Damage.hitPlayer(w, 30, nil)
  t.eq(w.player.hp, 70, "second hit lands while recharging")
  t.eq(w.noDamage, false, "real damage flips the flag")

  w.player.invulnT = 0
  w.shieldT = 0 -- recharged
  Damage.hitPlayer(w, 30, nil)
  t.eq(w.player.hp, 70, "recharged shield blocks again")
  t.eq(blocked, 2)
end

function T.aoe_splash_hits_neighbours(t)
  local w = fakeWorld()
  local hit = { hp = 100, maxhp = 100, x = 240, y = 300, r = 10, flashT = 0 }
  local near_ = { hp = 100, maxhp = 100, x = 300, y = 300, r = 10, flashT = 0 }
  local far = { hp = 100, maxhp = 100, x = 240, y = 700, r = 10, flashT = 0 }
  w.enemies = { hit, near_, far }
  w.player.invulnT = 1 -- keep the player out of the interaction
  local blast = nil
  w.events:on("aoe_blast", function(x, y, r) blast = r end)
  w.bullets = { { x = 240, y = 300, r = 6, damage = 50, pierce = 0, aoe = 90,
                  kind = "bullet", dead = false } }
  Collision.update(w, 1 / 60)
  t.near(hit.hp, 50, 1e-9, "direct hit takes full damage")
  t.near(near_.hp, 70, 1e-9, "neighbour takes 60% splash")
  t.eq(far.hp, 100, "outside the radius: untouched")
  t.eq(w.bullets[1].dead, true, "warhead consumed")
  t.eq(blast, 90, "aoe_blast emitted with the radius")
end

return T
