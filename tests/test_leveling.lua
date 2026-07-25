-- tests/test_leveling.lua — stat recompute + draft offer validity, against the
-- REAL content tables so schema mismatches get caught here.
local Leveling = require("src.systems.leveling")
local RNG = require("src.core.rng")
local Weapons = require("src.content.weapons")
local Upgrades = require("src.content.upgrades")
local Ships = require("src.content.ships")

local T = {}

local function fakeWorld()
  return {
    rng = { cards = RNG.new(99) },
    player = { hp = 100, maxhp = 100, shipDef = Ships.pathfinder },
    weapons = {}, passives = {},
    stats = nil,
    stardustEarned = 0,
  }
end

function T.base_stats(t)
  local w = fakeWorld()
  Leveling.recomputeStats(w)
  t.eq(w.stats.maxhp, 100)
  t.eq(w.stats.speed, 300)
  t.eq(w.stats.damageMult, 1)
  t.near(w.stats.critChance, 0.05, 1e-9)
  t.eq(w.player.hp, 100, "first recompute fills hp")
end

function T.passive_folding(t)
  local w = fakeWorld()
  Leveling.recomputeStats(w)
  w.passives = {
    { def = Upgrades.crit_systems, level = 3 },  -- +0.15 crit
    { def = Upgrades.reactor_core, level = 2 },  -- +0.20 xpMult (adds onto 1.0)
    { def = Upgrades.thrusters, level = 1 },     -- +24 speed
  }
  Leveling.recomputeStats(w)
  t.near(w.stats.critChance, 0.20, 1e-9, "crit adds")
  t.near(w.stats.xpMult, 1.20, 1e-9, "mult stat adds onto its 1.0 base")
  t.eq(w.stats.speed, 324, "flat stat adds")
end

function T.maxhp_preserves_damage_taken(t)
  local w = fakeWorld()
  Leveling.recomputeStats(w)
  w.player.hp = 60 -- took 40 damage
  w.passives = { { def = Upgrades.hull_plating, level = 2 } } -- +30 maxhp
  Leveling.recomputeStats(w)
  t.eq(w.stats.maxhp, 130)
  t.eq(w.player.hp, 90, "damage taken (40) preserved: 130 - 40")
end

function T.offer_three_distinct(t)
  local w = fakeWorld()
  Leveling.recomputeStats(w)
  Leveling.addWeapon(w, Weapons.blaster)
  local offer = Leveling.buildOffer(w)
  t.eq(#offer, 3, "always 3 cards")
  local seen = {}
  for i = 1, 3 do
    local id = offer[i].def.id
    t.ok(not seen[id], "distinct ids: " .. id)
    seen[id] = true
  end
end

function T.offer_respects_max_level(t)
  local w = fakeWorld()
  Leveling.recomputeStats(w)
  Leveling.addWeapon(w, Weapons.blaster)
  w.weapons[1].level = Weapons.blaster.maxLevel
  for _ = 1, 20 do
    local offer = Leveling.buildOffer(w)
    for i = 1, #offer do
      if offer[i].def.id == "blaster" then
        t.ok(false, "maxed weapon must not be offered")
      end
    end
  end
end

function T.offer_respects_slot_caps(t)
  local w = fakeWorld()
  Leveling.recomputeStats(w)
  -- fill 6 weapon slots (5 real + 1 dummy maxed) — no new weapons may appear
  local dummy = { id = "dummy", kind = "weapon", maxLevel = 1, name = "D", desc = "", levels = {{}} }
  Leveling.addWeapon(w, Weapons.blaster)
  Leveling.addWeapon(w, Weapons.missiles)
  Leveling.addWeapon(w, Weapons.flak)
  Leveling.addWeapon(w, Weapons.ion_arc)
  Leveling.addWeapon(w, Weapons.drones)
  Leveling.addWeapon(w, dummy)
  for _ = 1, 20 do
    local offer = Leveling.buildOffer(w)
    for i = 1, #offer do
      local c = offer[i]
      if c.def.kind == "weapon" and c.isNew then
        t.ok(false, "no new weapons at the 6-slot cap")
      end
    end
  end
end

function T.fallbacks_when_pool_dry(t)
  local w = fakeWorld()
  Leveling.recomputeStats(w)
  -- max out everything ownable
  for _, def in pairs(Weapons) do
    Leveling.addWeapon(w, def)
    w.weapons[#w.weapons].level = def.maxLevel
  end
  for _, def in pairs(Upgrades) do
    Leveling.addPassive(w, def)
    w.passives[#w.passives].level = def.maxLevel
  end
  local offer = Leveling.buildOffer(w)
  t.eq(#offer, 3, "fallbacks fill to 3")
  local anyFallback = false
  for i = 1, 3 do
    if offer[i].fallback then anyFallback = true end
  end
  t.ok(anyFallback, "dry pool produces fallback cards")
end

function T.apply_levels_and_caps(t)
  local w = fakeWorld()
  Leveling.recomputeStats(w)
  Leveling.addWeapon(w, Weapons.blaster)
  Leveling.apply(w, { def = Weapons.blaster, isNew = false, newLevel = 2 })
  t.eq(w.weapons[1].level, 2, "weapon leveled")
  Leveling.apply(w, { def = Upgrades.thrusters, isNew = true, newLevel = 1 })
  t.eq(#w.passives, 1, "passive added")
  t.eq(w.stats.speed, 324, "stats recomputed on passive add")
end

function T.apply_fallbacks(t)
  local w = fakeWorld()
  Leveling.recomputeStats(w)
  w.player.hp = 50
  Leveling.apply(w, { fallback = "heal", def = { id = "f", kind = "fallback" } })
  t.eq(w.player.hp, 80, "heal restores 30% of maxhp")
  Leveling.apply(w, { fallback = "stardust", def = { id = "f2", kind = "fallback" } })
  t.eq(w.stardustEarned, 25, "stardust banks")
end

function T.offer_deterministic_by_seed(t)
  local function offerIds(seed)
    local w = fakeWorld()
    w.rng.cards = RNG.new(seed)
    Leveling.recomputeStats(w)
    Leveling.addWeapon(w, Weapons.blaster)
    local offer = Leveling.buildOffer(w)
    local ids = {}
    for i = 1, #offer do ids[i] = offer[i].def.id end
    return table.concat(ids, ",")
  end
  t.eq(offerIds(1234), offerIds(1234), "same seed, same offer")
end

return T
