-- Passive upgrades. `stat` names must match the stats table keys in leveling.lua.
-- Only ammo_feed carries an explicit rarity weight; others use leveling's default.
local M = {}

M.crit_systems = {
  id = "crit_systems", name = "Critical Systems", kind = "passive",
  desc = "+5% critical chance per level.",
  stat = "critChance", perLevel = 0.05, maxLevel = 5,
}

M.warhead_yield = {
  id = "warhead_yield", name = "Warhead Yield", kind = "passive",
  desc = "Crits hit +25% harder per level.",
  stat = "critMult", perLevel = 0.25, maxLevel = 5,
}

M.hull_plating = {
  id = "hull_plating", name = "Hull Plating", kind = "passive",
  desc = "+15 max hull per level.",
  stat = "maxhp", perLevel = 15, maxLevel = 5,
}

M.nanorepair = {
  id = "nanorepair", name = "Nanorepair", kind = "passive",
  desc = "Regenerates +0.6 hull per second per level.",
  stat = "regen", perLevel = 0.6, maxLevel = 5,
}

M.thrusters = {
  id = "thrusters", name = "Thrusters", kind = "passive",
  desc = "+24 thrust speed per level.",
  stat = "speed", perLevel = 24, maxLevel = 5,
}

M.reactor_core = {
  id = "reactor_core", name = "Reactor Core", kind = "passive",
  desc = "+10% XP from energy cells per level.",
  stat = "xpMult", perLevel = 0.10, maxLevel = 5,
}

M.tractor_beam = {
  id = "tractor_beam", name = "Tractor Beam", kind = "passive",
  desc = "+26 pickup magnet radius per level.",
  stat = "magnetRadius", perLevel = 26, maxLevel = 5,
}

M.ammo_feed = {
  id = "ammo_feed", name = "Ammo Feed", kind = "passive",
  desc = "Feeds +1 projectile to volley weapons.",
  stat = "projectileBonus", perLevel = 1, maxLevel = 2, weight = 3,
}

M.overclock = {
  id = "overclock", name = "Overclock", kind = "passive",
  desc = "+8% fire rate per level. Warranty void.",
  stat = "fireRateMult", perLevel = 0.08, maxLevel = 5,
}

M.coolant = {
  id = "coolant", name = "Coolant Injectors", kind = "passive",
  desc = "+15% damage to SLOWED targets per level.",
  stat = "slowBonus", perLevel = 0.15, maxLevel = 5,
}

M.shield_capacitor = {
  id = "shield_capacitor", name = "Shield Capacitor", kind = "passive",
  desc = "Blocks one hit, then recharges. Levels charge it faster.",
  stat = "shieldLevel", perLevel = 1, maxLevel = 3, weight = 4,
}

return M
