-- src/core/viewport.lua — virtual 480x854 portrait space, uniformly scaled and
-- letterboxed into the real window. Headless-safe: love is only touched inside
-- functions the game calls, never at module load.
local M = {}

M.VW = 480
M.VH = 854

local scale = 1
local ox, oy = 0, 0
local winW, winH = M.VW, M.VH

function M.resize(w, h)
  winW, winH = w, h
  local sx = w / M.VW
  local sy = h / M.VH
  scale = sx < sy and sx or sy
  ox = (w - M.VW * scale) * 0.5
  oy = (h - M.VH * scale) * 0.5
end

function M.scale()
  return scale
end

function M.apply()
  local lg = love.graphics
  lg.push()
  lg.translate(ox, oy)
  lg.scale(scale, scale)
  -- clip to the virtual rect so nothing bleeds into the letterbox bars
  lg.setScissor(ox, oy, M.VW * scale, M.VH * scale)
end

function M.unapply()
  local lg = love.graphics
  lg.setScissor()
  lg.pop()
  -- letterbox bars (drawn opaque over anything outside the virtual rect)
  lg.setColor(0, 0, 0, 1)
  if ox > 0 then
    lg.rectangle("fill", 0, 0, ox, winH)
    lg.rectangle("fill", winW - ox, 0, ox, winH)
  end
  if oy > 0 then
    lg.rectangle("fill", 0, 0, winW, oy)
    lg.rectangle("fill", 0, winH - oy, winW, oy)
  end
  lg.setColor(1, 1, 1, 1)
end

function M.toVirtual(sx, sy)
  return (sx - ox) / scale, (sy - oy) / scale
end

-- Extra top inset (virtual px) the HUD should respect when the scaled view
-- extends under a notch/cutout. 0 on desktop and when the letterbox bar
-- already clears the safe area.
function M.safeTop()
  if love and love.window and love.window.getSafeArea then
    local _, sy = love.window.getSafeArea()
    local inset = (sy - oy) / scale
    if inset > 0 then return inset end
  end
  return 0
end

return M
