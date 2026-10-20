-- src/systems/leveling.lua — computed player stats + the level-up card draft
-- (upgrades, new gear, evolutions, fallbacks).
local Util = require("src.core.util")
local Weapons = require("src.content.weapons")
local Upgrades = require("src.content.upgrades")
local Tech = require("src.meta.tech")
local Save = require("src.meta.save")

local M = {}

local EVOLUTION_WEIGHT = 30

local MAX_WEAPONS = 6
local MAX_PASSIVES = 6
M.MAX_WEAPONS, M.MAX_PASSIVES = MAX_WEAPONS, MAX_PASSIVES -- run saves validate against these

local UPGRADE_WEIGHT = 10
local NEW_WEIGHT = 8

-- pairs() order is not deterministic; seeded runs need a stable candidate order
local function sortedIds(map)
  local ids = {}
  for id in pairs(map) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end
local WEAPON_IDS = sortedIds(Weapons)
local UPGRADE_IDS = sortedIds(Upgrades)

-- Builds world.stats from ship base + passives. Multiplier stats (damageMult,
-- fireRateMult, xpMult) get passive bonuses added onto their 1.0 base; flat
-- stats add directly. maxhp changes preserve damage already taken.
function M.recomputeStats(world)
  local ship = world.player.shipDef
  local old = world.stats
  local stats = {
    damageMult = 1,
    fireRateMult = 1,
    projectileBonus = 0,
    critChance = 0.05,
    critMult = 2.0,
    maxhp = ship.maxhp,
    regen = 0,
    speed = ship.speed,
    magnetRadius = 70,
    xpMult = 1,
    slowBonus = 0,
    shieldLevel = 0,
    stardustMult = 1,
  }
  -- ship identity bonuses (same additive semantics as passives)
  if ship.bonuses then
    for stat, v in pairs(ship.bonuses) do
      stats[stat] = (stats[stat] or 0) + v
    end
  end
  -- Star-Map permanent tech
  for stat, v in pairs(Tech.bonuses(Save.data())) do
    stats[stat] = (stats[stat] or 0) + v
  end
  local passives = world.passives
  for i = 1, #passives do
    local p = passives[i]
    local stat = p.def.stat
    stats[stat] = (stats[stat] or 0) + p.def.perLevel * p.level
  end
  world.stats = stats

  local player = world.player
  if old then
    local dmgTaken = old.maxhp - player.hp
    player.hp = math.max(1, stats.maxhp - dmgTaken)
  else
    player.hp = stats.maxhp
  end
  player.maxhp = stats.maxhp
end

function M.addWeapon(world, def)
  world.weapons[#world.weapons + 1] = { def = def, level = 1, cooldown = 0 }
end

function M.addPassive(world, def)
  world.passives[#world.passives + 1] = { def = def, level = 1 }
  M.recomputeStats(world)
end

local function findOwned(list, id)
  for i = 1, #list do
    if list[i].def.id == id then return list[i] end
  end
  return nil
end

-- 3 distinct cards: upgrades to owned gear, new weapons/passives (slot-capped),
-- fallbacks (heal / stardust) when the pool runs dry.
function M.buildOffer(world)
  local candidates = {}

  -- evolutions: maxed weapon + its catalyst passive owned -> the evolved form.
  -- An available evolution is GUARANTEED a slot in the draft.
  local evolutions = {}
  for i = 1, #world.weapons do
    local w = world.weapons[i]
    local def = w.def
    if def.evolvesTo and w.level >= def.maxLevel
        and findOwned(world.passives, def.evolvesWith)
        and not findOwned(world.weapons, def.evolvesTo) then
      evolutions[#evolutions + 1] = {
        def = Weapons[def.evolvesTo], isNew = false, newLevel = 1,
        isEvolution = true, evolveFrom = def.id,
        weight = EVOLUTION_WEIGHT,
      }
    end
  end

  for i = 1, #world.weapons do
    local w = world.weapons[i]
    if w.level < w.def.maxLevel then
      candidates[#candidates + 1] = {
        def = w.def, isNew = false, newLevel = w.level + 1,
        weight = UPGRADE_WEIGHT,
      }
    end
  end
  for i = 1, #world.passives do
    local p = world.passives[i]
    if p.level < p.def.maxLevel then
      candidates[#candidates + 1] = {
        def = p.def, isNew = false, newLevel = p.level + 1,
        weight = UPGRADE_WEIGHT,
      }
    end
  end

  if #world.weapons < MAX_WEAPONS then
    for i = 1, #WEAPON_IDS do
      local id = WEAPON_IDS[i]
      if not Weapons[id].evolution and not findOwned(world.weapons, id) then
        candidates[#candidates + 1] = {
          def = Weapons[id], isNew = true, newLevel = 1,
          weight = Weapons[id].weight or NEW_WEIGHT,
        }
      end
    end
  end
  if #world.passives < MAX_PASSIVES then
    for i = 1, #UPGRADE_IDS do
      local id = UPGRADE_IDS[i]
      if not findOwned(world.passives, id) then
        candidates[#candidates + 1] = {
          def = Upgrades[id], isNew = true, newLevel = 1,
          weight = Upgrades[id].weight or NEW_WEIGHT,
        }
      end
    end
  end

  -- weighted draw without replacement, deduped by def id
  local offer = {}
  local rng = world.rng.cards
  if #evolutions > 0 then
    offer[1] = evolutions[rng:random(#evolutions)]
  end
  while #offer < 3 and #candidates > 0 do
    local pick = Util.weightedPick(rng, candidates)
    for i = 1, #candidates do
      if candidates[i] == pick then
        table.remove(candidates, i)
        break
      end
    end
    local dupe = false
    for i = 1, #offer do
      if offer[i].def and pick.def and offer[i].def.id == pick.def.id then
        dupe = true
        break
      end
    end
    if not dupe then offer[#offer + 1] = pick end
  end

  while #offer < 3 do
    if #offer < 2 or offer[#offer].fallback == "stardust" then
      offer[#offer + 1] = {
        fallback = "heal", isNew = false, newLevel = 0,
        def = { id = "fallback_heal", name = "Emergency Repair", kind = "fallback",
                desc = "Restore 30% of max hull integrity." },
      }
    else
      offer[#offer + 1] = {
        fallback = "stardust", isNew = false, newLevel = 0,
        def = { id = "fallback_stardust", name = "Salvage Cache", kind = "fallback",
                desc = "+25 Stardust, banked instantly." },
      }
    end
  end

  return offer
end

function M.apply(world, card)
  if card.fallback == "heal" then
    local player = world.player
    player.hp = math.min(player.maxhp, player.hp + 0.3 * player.maxhp)
    return
  elseif card.fallback == "stardust" then
    world.stardustEarned = world.stardustEarned + 25
    return
  end

  local def = card.def
  if card.isEvolution then
    local base = findOwned(world.weapons, card.evolveFrom)
    if base then
      base.def = def
      base.level = 1
      base.cooldown = 0
      if world.events then world.events:emit("weapon_evolved", def) end
    end
    return
  end
  if def.kind == "weapon" then
    local owned = findOwned(world.weapons, def.id)
    if owned then
      owned.level = math.min(owned.level + 1, def.maxLevel)
    else
      M.addWeapon(world, def)
    end
  else
    local owned = findOwned(world.passives, def.id)
    if owned then
      owned.level = math.min(owned.level + 1, def.maxLevel)
      M.recomputeStats(world)
    else
      M.addPassive(world, def)
    end
  end
end

return M
