-- Weapon definitions. Every levels[n] entry is complete (no inheritance).
-- Bullet life defaults to 1.6 when absent (see contract).
-- Evolution: a weapon at maxLevel whose `evolvesWith` passive is owned may evolve
-- into `evolvesTo` (defs marked `evolution = true` never appear as normal drafts).
local M = {}

M.blaster = {
  id = "blaster", name = "Blaster", kind = "weapon",
  desc = "Twin-linked forward cannon. The spine of every run.",
  behavior = "forward", sprite = "bullet_blaster", maxLevel = 8,
  evolvesWith = "ammo_feed", evolvesTo = "plasma_storm",
  levels = {
    { damage = 8,  cooldown = 0.32, count = 1, speed = 520, pierce = 0, spreadDeg = 0 },
    { damage = 10, cooldown = 0.30, count = 1, speed = 535, pierce = 0, spreadDeg = 0 },
    { damage = 10, cooldown = 0.29, count = 2, speed = 550, pierce = 0, spreadDeg = 0 },
    { damage = 11, cooldown = 0.27, count = 2, speed = 570, pierce = 0, spreadDeg = 0 },
    { damage = 11, cooldown = 0.26, count = 3, speed = 590, pierce = 0, spreadDeg = 6 },
    { damage = 12, cooldown = 0.25, count = 3, speed = 605, pierce = 0, spreadDeg = 7 },
    { damage = 13, cooldown = 0.24, count = 3, speed = 620, pierce = 0, spreadDeg = 8 },
    { damage = 13, cooldown = 0.22, count = 4, speed = 640, pierce = 1, spreadDeg = 10 },
  },
  levelDesc = {
    "Rapid forward cannon.",
    "+2 damage, faster cycling.",
    "+1 projectile.",
    "+1 damage, faster cycling.",
    "+1 projectile, slight fan.",
    "+1 damage, faster cycling.",
    "+1 damage, faster cycling.",
    "+1 projectile, shots pierce one target.",
  },
}

M.missiles = {
  id = "missiles", name = "Missile Bay", kind = "weapon",
  desc = "Seeker warheads that hunt the nearest hostile.",
  behavior = "homing", sprite = "bullet_missile", maxLevel = 5,
  evolvesWith = "warhead_yield", evolvesTo = "nuclear_barrage",
  levels = {
    { damage = 20, cooldown = 1.60, count = 1, speed = 260, pierce = 0, spreadDeg = 0, life = 3, homing = 3.5 },
    { damage = 26, cooldown = 1.45, count = 1, speed = 275, pierce = 0, spreadDeg = 0, life = 3, homing = 3.6 },
    { damage = 30, cooldown = 1.30, count = 2, speed = 290, pierce = 0, spreadDeg = 0, life = 3, homing = 3.7 },
    { damage = 36, cooldown = 1.20, count = 2, speed = 310, pierce = 0, spreadDeg = 0, life = 3, homing = 3.9 },
    { damage = 44, cooldown = 1.05, count = 3, speed = 330, pierce = 0, spreadDeg = 0, life = 3, homing = 4.1 },
  },
  levelDesc = {
    "One homing warhead per volley.",
    "Bigger payload, faster reload.",
    "+1 missile per volley.",
    "Bigger payload, faster reload.",
    "+1 missile, sharper tracking.",
  },
}

M.flak = {
  id = "flak", name = "Flak Spread", kind = "weapon",
  desc = "A shotgun wall of white-hot shrapnel. Brutal up close.",
  behavior = "spread", sprite = "bullet_flak", maxLevel = 5,
  evolvesWith = "ammo_feed", evolvesTo = "buckshot_nova",
  levels = {
    { damage = 6,  cooldown = 1.10, count = 5, speed = 380, pierce = 0, spreadDeg = 55, life = 0.5 },
    { damage = 7,  cooldown = 1.05, count = 6, speed = 380, pierce = 0, spreadDeg = 58, life = 0.5 },
    { damage = 8,  cooldown = 1.00, count = 7, speed = 380, pierce = 0, spreadDeg = 62, life = 0.5 },
    { damage = 9,  cooldown = 0.90, count = 8, speed = 380, pierce = 0, spreadDeg = 66, life = 0.5 },
    { damage = 11, cooldown = 0.85, count = 9, speed = 380, pierce = 0, spreadDeg = 70, life = 0.5 },
  },
  levelDesc = {
    "Five-pellet close-range burst.",
    "+1 pellet, wider fan.",
    "+1 pellet, wider fan.",
    "+1 pellet, faster reload.",
    "+1 pellet, maximum saturation.",
  },
}

M.ion_arc = {
  id = "ion_arc", name = "Ion Arc", kind = "weapon",
  desc = "Lightning that leaps between packed hostiles.",
  behavior = "arc", sprite = "dot", maxLevel = 5,
  evolvesWith = "crit_systems", evolvesTo = "ion_storm",
  levels = {
    { damage = 14, cooldown = 1.40, range = 240, chains = 1 },
    { damage = 17, cooldown = 1.25, range = 255, chains = 1 },
    { damage = 20, cooldown = 1.10, range = 270, chains = 2 },
    { damage = 24, cooldown = 1.00, range = 285, chains = 2 },
    { damage = 30, cooldown = 0.90, range = 300, chains = 3 },
  },
  levelDesc = {
    "Zaps the nearest enemy, chains once.",
    "Hotter arc, longer reach.",
    "+1 chain jump.",
    "Hotter arc, faster discharge.",
    "+1 chain jump, maximum voltage.",
  },
}

M.drones = {
  id = "drones", name = "Orbital Drones", kind = "weapon",
  desc = "Autonomous orbiters that shred anything they touch.",
  behavior = "orbital", sprite = "drone", maxLevel = 5,
  evolvesWith = "overclock", evolvesTo = "battle_constellation",
  levels = {
    { damage = 10, cooldown = 0.5, count = 1, orbitR = 60, angVel = 2.6 },
    { damage = 12, cooldown = 0.5, count = 2, orbitR = 63, angVel = 2.8 },
    { damage = 15, cooldown = 0.5, count = 2, orbitR = 66, angVel = 3.0 },
    { damage = 17, cooldown = 0.5, count = 3, orbitR = 70, angVel = 3.2 },
    { damage = 20, cooldown = 0.5, count = 4, orbitR = 74, angVel = 3.4 },
  },
  levelDesc = {
    "One orbiting attack drone.",
    "+1 drone.",
    "Sharper blades, faster orbit.",
    "+1 drone, wider orbit.",
    "+1 drone, full constellation.",
  },
}

M.laser = {
  id = "laser", name = "Laser Beam", kind = "weapon",
  desc = "A continuous cutting beam. Everything in the column burns.",
  behavior = "beam", sprite = "dot", maxLevel = 5,
  evolvesWith = "overclock", evolvesTo = "death_ray",
  levels = {
    { damage = 4, tick = 0.12, width = 10 },
    { damage = 5, tick = 0.12, width = 11 },
    { damage = 6, tick = 0.11, width = 12 },
    { damage = 7, tick = 0.11, width = 13 },
    { damage = 9, tick = 0.10, width = 14 },
  },
  levelDesc = {
    "Constant beam straight ahead.",
    "Hotter focus.",
    "Wider aperture, faster pulses.",
    "Hotter focus.",
    "Maximum output lens.",
  },
}

M.graviton = {
  id = "graviton", name = "Graviton Pulse", kind = "weapon",
  desc = "Expanding wave that crushes and SLOWS everything it touches.",
  behavior = "pulse", sprite = "ring", maxLevel = 5,
  evolvesWith = "reactor_core", evolvesTo = "singularity",
  levels = {
    { damage = 8,  cooldown = 3.2, radius = 130, slowT = 2.2, slowMult = 0.50 },
    { damage = 10, cooldown = 3.0, radius = 145, slowT = 2.4, slowMult = 0.50 },
    { damage = 13, cooldown = 2.7, radius = 160, slowT = 2.6, slowMult = 0.45 },
    { damage = 15, cooldown = 2.4, radius = 175, slowT = 2.8, slowMult = 0.45 },
    { damage = 18, cooldown = 2.2, radius = 190, slowT = 3.0, slowMult = 0.40 },
  },
  levelDesc = {
    "Slowing shockwave around the ship.",
    "Wider wave.",
    "Heavier drag, wider wave.",
    "Faster recharge.",
    "Maximum compression.",
  },
}

M.cryo = {
  id = "cryo", name = "Cryo Shards", kind = "weapon",
  desc = "Freezing crystal volley — chilled targets fly slow.",
  behavior = "spread", sprite = "bullet_cryo", maxLevel = 5,
  evolvesWith = "coolant", evolvesTo = "absolute_zero",
  levels = {
    { damage = 5,  cooldown = 1.30, count = 3, speed = 430, pierce = 0, spreadDeg = 26, life = 0.6, slowT = 1.4, slowMult = 0.55 },
    { damage = 6,  cooldown = 1.20, count = 3, speed = 430, pierce = 0, spreadDeg = 28, life = 0.6, slowT = 1.5, slowMult = 0.55 },
    { damage = 7,  cooldown = 1.10, count = 4, speed = 430, pierce = 0, spreadDeg = 30, life = 0.6, slowT = 1.6, slowMult = 0.50 },
    { damage = 8,  cooldown = 1.00, count = 4, speed = 430, pierce = 0, spreadDeg = 32, life = 0.6, slowT = 1.7, slowMult = 0.50 },
    { damage = 10, cooldown = 0.95, count = 5, speed = 430, pierce = 0, spreadDeg = 34, life = 0.6, slowT = 1.8, slowMult = 0.45 },
  },
  levelDesc = {
    "Three chilling shards.",
    "Deeper freeze.",
    "+1 shard.",
    "Deeper freeze, faster volley.",
    "+1 shard, hard frost.",
  },
}

M.railgun = {
  id = "railgun", name = "Railgun", kind = "weapon",
  desc = "Hypervelocity slug — one instant line through EVERYTHING.",
  behavior = "rail", sprite = "dot", maxLevel = 5,
  levels = {
    { damage = 55,  cooldown = 2.6, width = 12 },
    { damage = 70,  cooldown = 2.4, width = 12 },
    { damage = 85,  cooldown = 2.2, width = 13 },
    { damage = 100, cooldown = 2.0, width = 13 },
    { damage = 120, cooldown = 1.9, width = 14 },
  },
  levelDesc = {
    "Piercing column shot.",
    "Heavier slug.",
    "Heavier slug, faster charge.",
    "Heavier slug.",
    "Maximum acceleration.",
  },
}

M.solar_aura = {
  id = "solar_aura", name = "Solar Flare Aura", kind = "weapon",
  desc = "A corona of burning plasma around the hull.",
  behavior = "aura", sprite = "glow", maxLevel = 5,
  levels = {
    { damage = 6,  tick = 0.5, radius = 70 },
    { damage = 8,  tick = 0.5, radius = 80 },
    { damage = 9,  tick = 0.5, radius = 90 },
    { damage = 11, tick = 0.5, radius = 100 },
    { damage = 13, tick = 0.5, radius = 110 },
  },
  levelDesc = {
    "Burning halo around the ship.",
    "Wider corona.",
    "Hotter flare.",
    "Wider corona.",
    "A pocket star.",
  },
}

-- Evolutions ------------------------------------------------------------
-- maxLevel 1, marked evolution = true (never offered as normal new weapons).

M.plasma_storm = {
  id = "plasma_storm", name = "PLASMA STORM", kind = "weapon", evolution = true,
  desc = "The Blaster, unchained. A hurricane of piercing plasma.",
  behavior = "forward", sprite = "bullet_blaster", maxLevel = 1,
  levels = { { damage = 14, cooldown = 0.16, count = 6, speed = 700, pierce = 2, spreadDeg = 24 } },
}

M.nuclear_barrage = {
  id = "nuclear_barrage", name = "NUCLEAR BARRAGE", kind = "weapon", evolution = true,
  desc = "Seeker warheads with fission payloads. Everything nearby burns.",
  behavior = "homing", sprite = "bullet_missile", maxLevel = 1,
  levels = { { damage = 80, cooldown = 1.5, count = 3, speed = 340, pierce = 0, spreadDeg = 0, life = 3, homing = 4.0, aoe = 90 } },
}

M.buckshot_nova = {
  id = "buckshot_nova", name = "BUCKSHOT NOVA", kind = "weapon", evolution = true,
  desc = "The whole sky becomes shrapnel. All directions. At once.",
  behavior = "spread", sprite = "bullet_flak", maxLevel = 1,
  levels = { { damage = 12, cooldown = 0.9, count = 16, speed = 420, pierce = 0, spreadDeg = 360, life = 0.6 } },
}

M.ion_storm = {
  id = "ion_storm", name = "ION STORM", kind = "weapon", evolution = true,
  desc = "A living thunderhead that never stops chaining.",
  behavior = "arc", sprite = "dot", maxLevel = 1,
  levels = { { damage = 34, cooldown = 0.55, range = 330, chains = 5 } },
}

M.battle_constellation = {
  id = "battle_constellation", name = "BATTLE CONSTELLATION", kind = "weapon", evolution = true,
  desc = "Six blades of light in furious orbit.",
  behavior = "orbital", sprite = "drone", maxLevel = 1,
  levels = { { damage = 28, cooldown = 0.5, count = 6, orbitR = 78, angVel = 4.4 } },
}

M.death_ray = {
  id = "death_ray", name = "DEATH RAY", kind = "weapon", evolution = true,
  desc = "A pillar of annihilation. Point ship at problem.",
  behavior = "beam", sprite = "dot", maxLevel = 1,
  levels = { { damage = 26, tick = 0.10, width = 26 } },
}

M.singularity = {
  id = "singularity", name = "SINGULARITY", kind = "weapon", evolution = true,
  desc = "A captive black hole. Space itself refuses to cooperate.",
  behavior = "pulse", sprite = "ring", maxLevel = 1,
  levels = { { damage = 45, cooldown = 1.8, radius = 240, slowT = 3.5, slowMult = 0.25 } },
}

M.absolute_zero = {
  id = "absolute_zero", name = "ABSOLUTE ZERO", kind = "weapon", evolution = true,
  desc = "The heat death of everything nearby.",
  behavior = "spread", sprite = "bullet_cryo", maxLevel = 1,
  levels = { { damage = 16, cooldown = 1.5, count = 14, speed = 380, pierce = 0, spreadDeg = 360, life = 0.8, slowT = 2.2, slowMult = 0.20 } },
}

return M
