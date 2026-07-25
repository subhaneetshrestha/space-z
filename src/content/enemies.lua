-- Enemy definitions, grouped by the zone that introduces them (any zone may
-- reuse earlier enemies — later zones scale them up via the spawner).
-- movement: drift | sine | chaser | shooter | lunge | ballistic
-- optional: tint = {r,g,b} (multiplied over the sprite), fire (shooters),
-- accel (chasers), holdY (shooters).
local M = {}

-- Zone 1 — Low Earth Orbit ---------------------------------------------------

M.drifter = {
  id = "drifter", name = "Debris Drifter", sprite = "enemy_drifter",
  movement = "drift",
  hp = 18, speed = 70, touchDamage = 8, r = 14, xp = 1, score = 10,
}

M.shard = {
  id = "shard", name = "Glass Shard", sprite = "enemy_shard",
  movement = "sine",
  hp = 10, speed = 110, touchDamage = 6, r = 10, xp = 1, score = 10,
}

M.stinger = {
  id = "stinger", name = "Stinger", sprite = "enemy_stinger",
  movement = "chaser",
  hp = 14, speed = 95, touchDamage = 10, r = 11, xp = 2, score = 15, accel = 200,
}

M.sentry = {
  id = "sentry", name = "Orbital Sentry", sprite = "enemy_sentry",
  movement = "shooter",
  hp = 40, speed = 80, touchDamage = 10, r = 15, xp = 4, score = 30,
  fire = { cooldown = 2.4, speed = 150, damage = 7 },
  holdY = 170,
}

-- Zone 2 — The Moon ----------------------------------------------------------

M.meteor = {
  id = "meteor", name = "Meteor", sprite = "meteor",
  movement = "ballistic", spin = 4,
  hp = 8, speed = 300, touchDamage = 11, r = 8, xp = 1, score = 15,
}

M.lunar_hopper = {
  id = "lunar_hopper", name = "Lunar Hopper", sprite = "enemy_stinger",
  movement = "lunge", tint = { 0.8, 0.85, 1.0 },
  hp = 30, speed = 90, touchDamage = 12, r = 12, xp = 3, score = 25,
}

-- Zone 3 — Mars --------------------------------------------------------------

M.war_drone = {
  id = "war_drone", name = "War Drone", sprite = "enemy_sentry",
  movement = "shooter", tint = { 1.0, 0.45, 0.35 },
  hp = 60, speed = 95, touchDamage = 12, r = 15, xp = 5, score = 40,
  fire = { cooldown = 1.9, speed = 175, damage = 9 },
  holdY = 200,
}

M.dust_devil = {
  id = "dust_devil", name = "Dust Devil", sprite = "enemy_drifter",
  movement = "sine", tint = { 1.0, 0.6, 0.4 },
  hp = 34, speed = 130, touchDamage = 10, r = 13, xp = 3, score = 25,
}

-- Zone 4 — Asteroid Belt -----------------------------------------------------

M.asteroid_s = {
  id = "asteroid_s", name = "Asteroid", sprite = "asteroid",
  movement = "ballistic", spin = 1.2,
  hp = 34, speed = 95, touchDamage = 12, r = 12, xp = 2, score = 20,
}

M.asteroid_l = {
  id = "asteroid_l", name = "Heavy Asteroid", sprite = "asteroid",
  movement = "ballistic", spin = 0.6, scale = 1.8,
  hp = 110, speed = 65, touchDamage = 18, r = 21, xp = 6, score = 50,
}

M.pirate = {
  id = "pirate", name = "Belt Pirate", sprite = "pirate",
  movement = "lunge",
  hp = 70, speed = 105, touchDamage = 14, r = 13, xp = 6, score = 60,
}

-- Zone 5 — Jupiter -----------------------------------------------------------

M.storm_wisp = {
  id = "storm_wisp", name = "Storm Wisp", sprite = "enemy_shard",
  movement = "sine", tint = { 1.0, 0.9, 0.4 },
  hp = 40, speed = 160, touchDamage = 12, r = 11, xp = 4, score = 35,
}

M.volt_sentinel = {
  id = "volt_sentinel", name = "Volt Sentinel", sprite = "enemy_sentry",
  movement = "shooter", tint = { 1.0, 0.9, 0.3 },
  hp = 90, speed = 100, touchDamage = 14, r = 16, xp = 7, score = 60,
  fire = { cooldown = 1.6, speed = 190, damage = 11 },
  holdY = 230,
}

-- Zone 6 — Saturn's Rings ----------------------------------------------------

M.ice_shard = {
  id = "ice_shard", name = "Ring Ice", sprite = "ice_shard",
  movement = "ballistic", spin = 2.2,
  hp = 26, speed = 140, touchDamage = 12, r = 10, xp = 3, score = 25,
}

M.ring_reaver = {
  id = "ring_reaver", name = "Ring Reaver", sprite = "pirate",
  movement = "chaser", tint = { 0.6, 0.9, 1.0 },
  hp = 85, speed = 120, touchDamage = 15, r = 13, xp = 7, score = 70, accel = 260,
}

-- Zone 7 — The Void ----------------------------------------------------------

M.hive_dart = {
  id = "hive_dart", name = "Hive Dart", sprite = "hive_dart",
  movement = "chaser",
  hp = 55, speed = 150, touchDamage = 16, r = 11, xp = 6, score = 60, accel = 320,
}

M.hive_spitter = {
  id = "hive_spitter", name = "Hive Spitter", sprite = "hive_dart",
  movement = "shooter", tint = { 1.0, 0.4, 1.0 }, scale = 1.4,
  hp = 130, speed = 110, touchDamage = 18, r = 16, xp = 9, score = 90,
  fire = { cooldown = 1.4, speed = 210, damage = 13 },
  holdY = 260,
}

return M
