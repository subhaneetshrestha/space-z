-- src/render/hud.lua — minimal anti-clutter HUD per the plan: thin XP bar, zone
-- name, boss bar, HP ring around the ship, tiny run stats. Drawn unshaken.
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")

local M = {}

local pi = math.pi
local floor = math.floor

local VW, VH = Viewport.VW, Viewport.VH

function M.draw(world)
  local lg = love.graphics
  local top = Viewport.safeTop() -- clears notches/cutouts on mobile

  -- XP bar: 3px across the very top
  lg.setColor(0.08, 0.12, 0.16, 0.9)
  lg.rectangle("fill", 0, top, VW, 3)
  local frac = world.xpNext > 0 and (world.xp / world.xpNext) or 0
  if frac > 1 then frac = 1 end
  lg.setColor(0.2, 0.9, 1.0, 0.95)
  lg.rectangle("fill", 0, top, VW * frac, 3)
  lg.setColor(0.6, 1.0, 1.0, 0.9)
  lg.rectangle("fill", 0, top, VW * frac, 1)

  -- level tag, right-aligned under the bar
  lg.setFont(Util.font(12))
  lg.setColor(0.5, 0.9, 1.0, 0.85)
  lg.printf("LV " .. world.level, VW - 80, top + 8, 72, "right")

  -- zone name, fades out over zoneTime 3..4s
  local zt = world.zoneTime
  if zt < 4 and world.zone then
    local a = zt < 3 and 1 or (4 - zt)
    lg.setFont(Util.font(14))
    lg.setColor(world.zone.tint[1], world.zone.tint[2], world.zone.tint[3], 0.9 * a)
    lg.printf(world.zone.name, 0, top + 26, VW, "center")
  end

  -- boss bar
  local boss = world.boss
  if boss and not boss.dead then
    local bw = 300
    local bx = (VW - bw) * 0.5
    lg.setFont(Util.font(11))
    lg.setColor(1, 0.35, 0.2, 0.9)
    lg.printf(boss.bossDef.name, bx, top + 44, bw, "center")
    lg.setColor(0.15, 0.05, 0.05, 0.9)
    lg.rectangle("fill", bx, top + 58, bw, 8)
    local bf = boss.hp / boss.maxhp
    if bf < 0 then bf = 0 end
    lg.setColor(1, 0.25, 0.15, 0.95)
    lg.rectangle("fill", bx, top + 58, bw * bf, 8)
    lg.setColor(1, 0.6, 0.4, 0.5)
    lg.rectangle("line", bx + 0.5, top + 58.5, bw - 1, 7)
  end

  -- player HP ring: visible when hurt or recently damaged
  local player = world.player
  if player and not player.dead then
    local hpFrac = player.hp / player.maxhp
    local show = hpFrac < 1 and 1 or 0
    if world.hpRingT and world.hpRingT > 0 then show = 1 end
    if show > 0 then
      local r, g
      if hpFrac > 0.5 then
        r, g = (1 - hpFrac) * 2, 1
      else
        r, g = 1, hpFrac * 2
      end
      lg.setLineWidth(2.5)
      lg.setColor(0.1, 0.1, 0.1, 0.5)
      lg.circle("line", player.x, player.y, 26)
      lg.setColor(r, g, 0.15, 0.85)
      lg.arc("line", "open", player.x, player.y, 26,
        -pi * 0.5, -pi * 0.5 + pi * 2 * hpFrac, 32)
      lg.setLineWidth(1)
    end
  end

  -- tiny run stats, bottom-left
  lg.setFont(Util.font(11))
  lg.setColor(0.45, 0.6, 0.7, 0.7)
  lg.print("KILLS " .. world.kills, 8, VH - 34)
  lg.print(string.format("KM %.1f", world.distance / 100), 8, VH - 20)

  lg.setColor(1, 1, 1, 1)
end

-- Big centered neon banner (zone intro, WARP >>>). Layered draws fake the glow.
-- Optional subtitle: the zone's environment hint ("HIGH GRAVITY", ...).
function M.drawBanner(world, text, alpha, subtitle)
  local lg = love.graphics
  local a = alpha or 1
  local y = VH * 0.40
  local tint = (world.zone and world.zone.tint) or { 0.3, 0.8, 1.0 }
  lg.setFont(Util.font(28))
  lg.setColor(tint[1], tint[2], tint[3], 0.18 * a)
  for dx = -2, 2, 2 do
    for dy = -2, 2, 2 do
      if dx ~= 0 or dy ~= 0 then
        lg.printf(text, dx, y + dy, VW, "center")
      end
    end
  end
  lg.setColor(tint[1], tint[2], tint[3], 0.55 * a)
  lg.printf(text, 0, y + 1, VW, "center")
  lg.setColor(1, 1, 1, 0.95 * a)
  lg.printf(text, 0, y, VW, "center")
  if subtitle then
    lg.setFont(Util.font(13))
    lg.setColor(tint[1], tint[2], tint[3], 0.85 * a)
    lg.printf(subtitle, 0, y + 40, VW, "center")
  end
  lg.setColor(1, 1, 1, 1)
end

return M
