-- tests/test_evolutions.lua — evolution gating, guaranteed offer slot, apply.
local Leveling = require("src.systems.leveling")
local RNG = require("src.core.rng")
local Events = require("src.core.events")
local Weapons = require("src.content.weapons")
local Upgrades = require("src.content.upgrades")
local Ships = require("src.content.ships")

local T = {}

local function fakeWorld()
  local w = {
    rng = { cards = RNG.new(5) },
    events = Events.new(),
    player = { hp = 100, maxhp = 100, shipDef = Ships.pathfinder },
    weapons = {}, passives = {},
    stats = nil,
    stardustEarned = 0,
  }
  Leveling.recomputeStats(w)
  return w
end

local function hasEvolution(offer, id)
  for i = 1, #offer do
    if offer[i].isEvolution and offer[i].def.id == id then return offer[i] end
  end
  return nil
end

function T.every_evolution_target_exists(t)
  for id, def in pairs(Weapons) do
    if def.evolvesTo then
      local evo = Weapons[def.evolvesTo]
      t.ok(evo, id .. ": evolvesTo '" .. def.evolvesTo .. "' exists")
      t.ok(evo.evolution, def.evolvesTo .. " marked evolution")
      t.eq(evo.maxLevel, 1, def.evolvesTo .. " has a single level")
      t.ok(Upgrades[def.evolvesWith], id .. ": catalyst '" .. tostring(def.evolvesWith) .. "' exists")
    end
    if def.evolution then
      t.ok(#def.levels == 1, id .. ": evolution defines exactly one level")
    end
  end
end

function T.not_offered_below_max_level(t)
  local w = fakeWorld()
  Leveling.addWeapon(w, Weapons.missiles) -- level 1 of 5
  Leveling.addPassive(w, Upgrades.warhead_yield)
  for _ = 1, 10 do
    t.ok(not hasEvolution(Leveling.buildOffer(w), "nuclear_barrage"),
      "no evolution before max level")
  end
end

function T.not_offered_without_catalyst(t)
  local w = fakeWorld()
  Leveling.addWeapon(w, Weapons.missiles)
  w.weapons[1].level = Weapons.missiles.maxLevel
  for _ = 1, 10 do
    t.ok(not hasEvolution(Leveling.buildOffer(w), "nuclear_barrage"),
      "no evolution without the catalyst passive")
  end
end

function T.guaranteed_when_ready(t)
  local w = fakeWorld()
  Leveling.addWeapon(w, Weapons.missiles)
  w.weapons[1].level = Weapons.missiles.maxLevel
  Leveling.addPassive(w, Upgrades.warhead_yield)
  for _ = 1, 10 do
    local offer = Leveling.buildOffer(w)
    t.ok(hasEvolution(offer, "nuclear_barrage"), "ready evolution is guaranteed a slot")
  end
end

function T.apply_replaces_and_emits(t)
  local w = fakeWorld()
  Leveling.addWeapon(w, Weapons.missiles)
  w.weapons[1].level = Weapons.missiles.maxLevel
  Leveling.addPassive(w, Upgrades.warhead_yield)
  local evolved = nil
  w.events:on("weapon_evolved", function(def) evolved = def end)
  local card = hasEvolution(Leveling.buildOffer(w), "nuclear_barrage")
  Leveling.apply(w, card)
  t.eq(#w.weapons, 1, "still one weapon slot used")
  t.eq(w.weapons[1].def.id, "nuclear_barrage", "weapon replaced by evolved form")
  t.eq(w.weapons[1].level, 1, "evolved weapon at level 1")
  t.ok(evolved ~= nil, "weapon_evolved emitted")
  -- and it never gets offered again
  for _ = 1, 10 do
    t.ok(not hasEvolution(Leveling.buildOffer(w), "nuclear_barrage"),
      "evolved weapon not re-offered")
  end
end

function T.evolutions_never_appear_as_new_weapons(t)
  local w = fakeWorld()
  Leveling.addWeapon(w, Weapons.blaster)
  for _ = 1, 30 do
    local offer = Leveling.buildOffer(w)
    for i = 1, #offer do
      t.ok(not (offer[i].def.evolution and not offer[i].isEvolution),
        "evolution def leaked into the normal pool: " .. offer[i].def.id)
    end
  end
end

return T
