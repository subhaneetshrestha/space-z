-- Boss definitions — one per zone; behavior keys implemented in systems/boss.lua.
local M = {}

M.kessler_swarm = {
  id = "kessler_swarm", name = "KESSLER SWARM",
  behavior = "kessler",
  sprite = "boss_kessler_core",
  hp = 1150, r = 42, touchDamage = 20, xpReward = 40, scale = 1,
}

M.mining_leviathan = {
  id = "mining_leviathan", name = "MINING LEVIATHAN",
  behavior = "leviathan",
  sprite = "boss_leviathan",
  hp = 1700, r = 44, touchDamage = 24, xpReward = 50, scale = 1,
}

M.war_machine = {
  id = "war_machine", name = "WAR MACHINE",
  behavior = "warmachine",
  sprite = "boss_warmachine",
  hp = 2300, r = 44, touchDamage = 26, xpReward = 60, scale = 1,
}

M.asteroid_titan = {
  id = "asteroid_titan", name = "ASTEROID TITAN",
  behavior = "titan",
  sprite = "boss_titan",
  hp = 3000, r = 48, touchDamage = 28, xpReward = 70, scale = 1,
}

M.storm_entity = {
  id = "storm_entity", name = "THE GREAT STORM",
  behavior = "storm",
  sprite = "boss_storm",
  hp = 3700, r = 45, touchDamage = 30, xpReward = 80, scale = 1,
}

M.ring_guardian = {
  id = "ring_guardian", name = "RING GUARDIAN",
  behavior = "guardian",
  sprite = "boss_guardian",
  hp = 4500, r = 45, touchDamage = 32, xpReward = 90, scale = 1,
}

M.overlord = {
  id = "overlord", name = "THE SPACE Z OVERLORD",
  behavior = "overlord",
  sprite = "boss_overlord",
  hp = 6000, r = 50, touchDamage = 36, xpReward = 120, scale = 1,
}

return M
