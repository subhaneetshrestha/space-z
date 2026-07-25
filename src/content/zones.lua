-- Zone list; array order is run order. After the last zone's boss -> victory.
-- Each zone: backdrop + tint (visual identity), waves (timeline streams),
-- optional `modifiers` (environment physics) and `subtitle` (intro hint).
-- Wave stream: { t=, until_=, enemy=, interval=, count=, from="top"|"sides" }.
-- modifiers: gravity (px/s downward drift on the player),
--            wind = { amp = px/s, period = s } (sinusoidal lateral push),
--            playerSpeedMult (movement feel, not a stat change)
local M = {
  {
    id = "leo", name = "LOW EARTH ORBIT", duration = 150, backdrop = "earth",
    tint = { 0.3, 0.7, 1.0 }, boss = "kessler_swarm",
    waves = {
      { t = 0,   until_ = 40,  enemy = "drifter", interval = 1.5, count = 1 },
      { t = 15,  until_ = 70,  enemy = "shard",   interval = 2.2, count = 2 },
      { t = 35,  until_ = 110, enemy = "stinger", interval = 2.8, count = 1 },
      { t = 55,  until_ = 150, enemy = "drifter", interval = 1.0, count = 1 },
      { t = 70,  until_ = 150, enemy = "sentry",  interval = 9.0, count = 1 },
      { t = 90,  until_ = 150, enemy = "shard",   interval = 1.6, count = 3 },
      { t = 120, until_ = 150, enemy = "stinger", interval = 1.8, count = 2 },
    },
  },
  {
    id = "moon", name = "THE MOON", duration = 155, backdrop = "moon",
    tint = { 0.75, 0.78, 0.85 }, boss = "mining_leviathan",
    subtitle = "METEOR SHOWERS",
    waves = {
      { t = 0,   until_ = 155, enemy = "meteor",       interval = 2.6, count = 2 }, -- ambient hazard
      { t = 0,   until_ = 50,  enemy = "drifter",      interval = 1.3, count = 1 },
      { t = 10,  until_ = 80,  enemy = "shard",        interval = 1.9, count = 2 },
      { t = 30,  until_ = 120, enemy = "lunar_hopper", interval = 4.0, count = 1 },
      { t = 55,  until_ = 155, enemy = "sentry",       interval = 8.0, count = 1 },
      { t = 70,  until_ = 155, enemy = "stinger",      interval = 2.0, count = 2 },
      { t = 100, until_ = 155, enemy = "meteor",       interval = 1.2, count = 2 },
      { t = 120, until_ = 155, enemy = "lunar_hopper", interval = 3.2, count = 2 },
    },
  },
  {
    id = "mars", name = "MARS", duration = 160, backdrop = "mars",
    tint = { 1.0, 0.5, 0.3 }, boss = "war_machine",
    subtitle = "DUST STORMS",
    modifiers = { wind = { amp = 70, period = 9 } },
    waves = {
      { t = 0,   until_ = 60,  enemy = "dust_devil", interval = 1.6, count = 1 },
      { t = 10,  until_ = 100, enemy = "shard",      interval = 1.7, count = 2 },
      { t = 25,  until_ = 160, enemy = "war_drone",  interval = 7.0, count = 1 },
      { t = 45,  until_ = 160, enemy = "dust_devil", interval = 1.2, count = 2 },
      { t = 70,  until_ = 160, enemy = "stinger",    interval = 1.8, count = 2 },
      { t = 100, until_ = 160, enemy = "war_drone",  interval = 6.0, count = 2 },
      { t = 130, until_ = 160, enemy = "dust_devil", interval = 0.9, count = 2 },
    },
  },
  {
    id = "belt", name = "ASTEROID BELT", duration = 165, backdrop = "belt",
    tint = { 0.85, 0.65, 0.45 }, boss = "asteroid_titan",
    subtitle = "DENSE ROCK FIELD",
    waves = {
      { t = 0,   until_ = 165, enemy = "asteroid_s", interval = 1.6, count = 1 },               -- ambient
      { t = 0,   until_ = 165, enemy = "asteroid_s", interval = 3.4, count = 1, from = "sides" },
      { t = 15,  until_ = 165, enemy = "asteroid_l", interval = 5.5, count = 1 },
      { t = 30,  until_ = 120, enemy = "pirate",     interval = 5.0, count = 1 },
      { t = 60,  until_ = 165, enemy = "asteroid_l", interval = 4.2, count = 1, from = "sides" },
      { t = 80,  until_ = 165, enemy = "pirate",     interval = 4.0, count = 2 },
      { t = 110, until_ = 165, enemy = "asteroid_s", interval = 1.0, count = 2 },
      { t = 140, until_ = 165, enemy = "stinger",    interval = 1.6, count = 2 },
    },
  },
  {
    id = "jupiter", name = "JUPITER", duration = 165, backdrop = "jupiter",
    tint = { 1.0, 0.75, 0.45 }, boss = "storm_entity",
    subtitle = "HIGH GRAVITY",
    modifiers = { gravity = 60, playerSpeedMult = 0.92 },
    waves = {
      { t = 0,   until_ = 70,  enemy = "storm_wisp",    interval = 1.5, count = 1 },
      { t = 12,  until_ = 165, enemy = "drifter",       interval = 1.4, count = 2 },
      { t = 25,  until_ = 165, enemy = "volt_sentinel", interval = 8.0, count = 1 },
      { t = 50,  until_ = 165, enemy = "storm_wisp",    interval = 1.1, count = 2 },
      { t = 80,  until_ = 165, enemy = "stinger",       interval = 1.7, count = 2 },
      { t = 105, until_ = 165, enemy = "volt_sentinel", interval = 6.5, count = 2 },
      { t = 135, until_ = 165, enemy = "storm_wisp",    interval = 0.8, count = 3 },
    },
  },
  {
    id = "saturn", name = "SATURN'S RINGS", duration = 170, backdrop = "saturn",
    tint = { 0.7, 0.9, 1.0 }, boss = "ring_guardian",
    subtitle = "CROSSING ICE",
    waves = {
      { t = 0,   until_ = 170, enemy = "ice_shard",   interval = 1.4, count = 1, from = "sides" }, -- ambient
      { t = 10,  until_ = 170, enemy = "ice_shard",   interval = 2.4, count = 2 },
      { t = 20,  until_ = 100, enemy = "shard",       interval = 1.5, count = 2 },
      { t = 35,  until_ = 170, enemy = "ring_reaver", interval = 5.5, count = 1 },
      { t = 65,  until_ = 170, enemy = "sentry",      interval = 7.0, count = 2 },
      { t = 95,  until_ = 170, enemy = "ice_shard",   interval = 0.9, count = 2, from = "sides" },
      { t = 125, until_ = 170, enemy = "ring_reaver", interval = 4.0, count = 2 },
    },
  },
  {
    id = "void", name = "THE VOID", duration = 175, backdrop = "void",
    tint = { 0.75, 0.4, 1.0 }, boss = "overlord",
    subtitle = "THE Z HIVE STIRS",
    waves = {
      { t = 0,   until_ = 60,  enemy = "hive_dart",    interval = 2.2, count = 1 },
      { t = 10,  until_ = 175, enemy = "shard",        interval = 1.3, count = 3 },
      { t = 25,  until_ = 175, enemy = "hive_spitter", interval = 8.0, count = 1 },
      { t = 45,  until_ = 175, enemy = "hive_dart",    interval = 1.8, count = 2 },
      { t = 75,  until_ = 175, enemy = "stinger",      interval = 1.4, count = 3 },
      { t = 105, until_ = 175, enemy = "hive_spitter", interval = 6.0, count = 2 },
      { t = 135, until_ = 175, enemy = "hive_dart",    interval = 1.1, count = 3 },
    },
  },
}

return M
