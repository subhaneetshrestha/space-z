-- Ship definitions. `price` in Stardust (pathfinder is free / always owned).
-- `bonuses` fold into stats exactly like passives (mult stats add onto 1.0).
-- Order here = display order in the hangar (see M.order).
local M = {}

M.pathfinder = {
  id = "pathfinder", name = "Pathfinder",
  desc = "Balanced scout. Where it goes, the fleet follows.",
  sprite = "ship_pathfinder", price = 0,
  maxhp = 100, speed = 300,
  startingWeapon = "blaster",
}

M.aegis = {
  id = "aegis", name = "Aegis",
  desc = "A flying bulkhead. Ships a factory-fitted shield.",
  sprite = "ship_aegis", price = 800,
  maxhp = 150, speed = 255,
  startingWeapon = "flak",
  bonuses = { shieldLevel = 1 },
}

M.falcon = {
  id = "falcon", name = "Falcon",
  desc = "Paper hull, surgical aim. Every shot matters.",
  sprite = "ship_falcon", price = 1200,
  maxhp = 70, speed = 350,
  startingWeapon = "railgun",
  bonuses = { critChance = 0.12 },
}

M.barrage = {
  id = "barrage", name = "Barrage",
  desc = "A missile rack with a cockpit bolted on.",
  sprite = "ship_barrage", price = 1500,
  maxhp = 100, speed = 280,
  startingWeapon = "missiles",
  bonuses = { damageMult = 0.10 },
}

M.halo = {
  id = "halo", name = "Halo",
  desc = "Carrier core. Its drones do the arguing.",
  sprite = "ship_halo", price = 1800,
  maxhp = 90, speed = 300,
  startingWeapon = "drones",
  bonuses = { magnetRadius = 40 },
}

M.warden = {
  id = "warden", name = "Warden",
  desc = "Gravity specialist. Nothing outruns the pull.",
  sprite = "ship_warden", price = 2200,
  maxhp = 115, speed = 275,
  startingWeapon = "graviton",
  bonuses = { slowBonus = 0.25 },
}

M.nova = {
  id = "nova", name = "Nova",
  desc = "Glass cannon. Burns twice as bright, half as long.",
  sprite = "ship_nova", price = 2600,
  maxhp = 60, speed = 315,
  startingWeapon = "laser",
  bonuses = { damageMult = 0.30 },
}

M.zephyr = {
  id = "zephyr", name = "Zephyr",
  desc = "Cryo glider. Learns something from every kill.",
  sprite = "ship_zephyr", price = 3000,
  maxhp = 85, speed = 335,
  startingWeapon = "cryo",
  bonuses = { xpMult = 0.15 },
}

M.order = {
  "pathfinder", "aegis", "falcon", "barrage", "halo", "warden", "nova", "zephyr",
}

return M
