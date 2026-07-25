-- tests/test_zones.lua — content integrity across all 7 zones + environment
-- modifier behavior (gravity/wind/ballistic) in movement.
local Zones = require("src.content.zones")
local Enemies = require("src.content.enemies")
local Bosses = require("src.content.bosses")
local Movement = require("src.systems.movement")

local T = {}

function T.seven_zones_in_order(t)
  t.eq(#Zones, 7, "seven zones ship in M2")
  local expect = { "leo", "moon", "mars", "belt", "jupiter", "saturn", "void" }
  for i = 1, 7 do
    t.eq(Zones[i].id, expect[i], "zone order at " .. i)
  end
end

function T.zone_schema_valid(t)
  local movements = {
    drift = true, sine = true, chaser = true, shooter = true,
    lunge = true, ballistic = true,
  }
  for zi, zone in ipairs(Zones) do
    t.ok(zone.name and #zone.name > 0, zone.id .. ": name")
    t.ok(zone.duration and zone.duration > 60, zone.id .. ": duration sane")
    t.ok(zone.backdrop, zone.id .. ": backdrop")
    t.ok(type(zone.tint) == "table" and #zone.tint == 3, zone.id .. ": tint")
    t.ok(Bosses[zone.boss], zone.id .. ": boss '" .. tostring(zone.boss) .. "' exists")
    t.ok(#zone.waves >= 5, zone.id .. ": enough wave streams")
    for wi, wave in ipairs(zone.waves) do
      local tag = zone.id .. " wave " .. wi
      local def = Enemies[wave.enemy]
      t.ok(def, tag .. ": enemy '" .. tostring(wave.enemy) .. "' exists")
      t.ok(movements[def.movement], tag .. ": known movement '" .. tostring(def.movement) .. "'")
      t.ok(wave.interval and wave.interval > 0, tag .. ": interval")
      t.ok(wave.count and wave.count >= 1, tag .. ": count")
      t.ok(wave.t ~= nil and wave.until_ ~= nil and wave.until_ > wave.t, tag .. ": window")
      t.ok(wave.until_ <= zone.duration, tag .. ": window inside zone")
      if wave.from then
        t.ok(wave.from == "sides" or wave.from == "top", tag .. ": from value")
      end
    end
  end
end

function T.every_boss_has_unique_behavior(t)
  local seen = {}
  for _, zone in ipairs(Zones) do
    local b = Bosses[zone.boss]
    t.ok(b.behavior, zone.id .. ": boss behavior key")
    t.ok(not seen[b.behavior], zone.id .. ": behavior '" .. b.behavior .. "' unique")
    seen[b.behavior] = true
    t.ok(b.hp > 500, zone.id .. ": boss hp")
    t.ok(b.sprite, zone.id .. ": boss sprite")
  end
end

function T.boss_hp_escalates(t)
  local prev = 0
  for _, zone in ipairs(Zones) do
    local hp = Bosses[zone.boss].hp
    t.ok(hp > prev, zone.id .. ": boss hp escalates (" .. hp .. " > " .. prev .. ")")
    prev = hp
  end
end

local function worldWithMods(mods)
  return {
    time = 0,
    zone = { modifiers = mods },
    player = { x = 240, y = 400, vx = 0, vy = 0, t = 0 },
    enemies = {}, bullets = {}, ebullets = {}, pickups = {},
  }
end

function T.gravity_drags_player_down(t)
  local w = worldWithMods({ gravity = 60 })
  for _ = 1, 60 do Movement.update(w, 1 / 60) end -- 1 second, no input
  t.near(w.player.y, 460, 1, "gravity 60 px/s drift over 1s")
end

function T.speed_mult_slows_steering(t)
  local w = worldWithMods({ playerSpeedMult = 0.5 })
  w.player.vx = 100
  Movement.update(w, 1)
  t.near(w.player.x, 290, 1e-6, "vx halved by playerSpeedMult")
end

function T.wind_pushes_sideways(t)
  local w = worldWithMods({ wind = { amp = 70, period = 9 } })
  local x0 = w.player.x
  w.time = 9 / 4 -- sin peak of the wind cycle
  Movement.update(w, 1 / 60)
  t.ok(w.player.x > x0, "wind pushed the ship at the gust peak")
end

function T.ballistic_keeps_spawn_velocity(t)
  local w = worldWithMods(nil)
  local e = {
    kind = "enemy", def = Enemies.ice_shard,
    x = 0, y = 100, vx = 120, vy = 40, r = 10, rot = 0, t = 0, scale = 1, flashT = 0,
  }
  w.enemies[1] = e
  Movement.update(w, 1)
  t.near(e.x, 120, 1e-6, "vx held")
  t.near(e.y, 140, 1e-6, "vy held")
  -- crossing rock culls once past the far edge
  e.x = 560
  Movement.update(w, 1 / 60)
  t.eq(e.dead, true, "culled past the far edge")
end

return T
