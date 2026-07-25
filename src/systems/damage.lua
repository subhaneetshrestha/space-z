-- Damage resolution: pure functions, no update loop. Emits combat events.
local M = {}

local min = math.min

local function killEnemy(world, enemy)
  enemy.dead = true
  world.kills = world.kills + 1
  world.events:emit("enemy_killed", enemy)
  if enemy.isBoss then
    world.bossKills = world.bossKills + 1
    world.boss = nil
    world.events:emit("boss_killed", enemy)
  end
end

-- Shared core: applies multipliers, crit roll, flash, hit/death events.
local function applyHit(world, enemy, baseDmg, canCrit, hx, hy)
  if enemy.dead or enemy.entering then return end
  local stats = world.stats
  local dmg = baseDmg * stats.damageMult
  -- Coolant: bonus damage against chilled/slowed targets
  if enemy.slowT and enemy.slowT > 0 and (stats.slowBonus or 0) > 0 then
    dmg = dmg * (1 + stats.slowBonus)
  end
  local isCrit = false
  if canCrit and world.rng.misc:chance(stats.critChance) then
    isCrit = true
    dmg = dmg * stats.critMult
  end
  enemy.hp = enemy.hp - dmg
  enemy.flashT = 0.08
  world.events:emit("enemy_hit", enemy, dmg, isCrit, hx, hy)
  if enemy.hp <= 0 then
    killEnemy(world, enemy)
  end
end

function M.hitEnemy(world, enemy, bullet)
  applyHit(world, enemy, bullet.damage, true, bullet.x, bullet.y)
  -- cryo shards chill on contact (bosses resist slow)
  if bullet.slowT and not enemy.dead and not enemy.isBoss then
    if not enemy.slowT or enemy.slowT < bullet.slowT then
      enemy.slowT = bullet.slowT
    end
    enemy.slowMult = bullet.slowMult
  end
end

-- For drones / ion arc / auras: no bullet involved.
function M.direct(world, enemy, dmg, canCrit)
  applyHit(world, enemy, dmg, canCrit, enemy.x, enemy.y)
end

function M.hitPlayer(world, amount, source)
  local player = world.player
  if player.dead or player.invulnT > 0 or world.phase == "over" then return end
  -- Shield Capacitor: a ready shield eats the hit outright (no-damage flag survives)
  local shieldLv = world.stats.shieldLevel or 0
  if shieldLv > 0 and (world.shieldT or 0) <= 0 then
    world.shieldT = 16 - 3 * shieldLv -- recharge: 13s / 10s / 7s
    player.invulnT = 0.7
    world.events:emit("shield_blocked", source)
    return
  end
  player.invulnT = 0.7
  world.noDamage = false
  world.shake = min(world.shake + 6, 12)
  if world.mode == "blackhole" then
    amount = player.hp -- hardcore mode: any hit is lethal
  end
  player.hp = player.hp - amount
  world.events:emit("player_damaged", amount, source)
  if player.hp <= 0 then
    player.hp = 0
    player.dead = true
    world.events:emit("player_died")
  end
end

return M
