-- src/render/cards.lua — level-up draft card rendering + hit-testing.
-- Layout and hit tests share one rect function so taps always match pixels.
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")

local M = {}

local VW, VH = Viewport.VW, Viewport.VH

local CARD_W = 140
local CARD_H = 216
local GAP = 12

local FRAME = {
  weapon = { 0.2, 0.95, 1.0 },
  passive = { 1.0, 0.3, 0.9 },
  fallback = { 0.3, 1.0, 0.45 },
}

local rects = {} -- reused scratch

function M.layout(offer)
  local n = #offer
  local totalW = n * CARD_W + (n - 1) * GAP
  local x0 = (VW - totalW) * 0.5
  local y = (VH - CARD_H) * 0.5
  for i = 1, n do
    local r = rects[i]
    if not r then
      r = {}
      rects[i] = r
    end
    r.x = x0 + (i - 1) * (CARD_W + GAP)
    r.y = y
    r.w = CARD_W
    r.h = CARD_H
  end
  for i = n + 1, #rects do rects[i] = nil end
  return rects
end

function M.hit(offer, x, y)
  local rs = M.layout(offer)
  for i = 1, #offer do
    local r = rs[i]
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
      return i
    end
  end
  return nil
end

local GOLD = { 1, 0.85, 0.2 }

local function frameColor(card)
  if card.isEvolution then return GOLD end
  local kind = card.def and card.def.kind or "fallback"
  return FRAME[kind] or FRAME.fallback
end

local function neonRect(lg, x, y, w, h, c, bright)
  lg.setColor(c[1], c[2], c[3], 0.10 * bright)
  lg.setLineWidth(6)
  lg.rectangle("line", x, y, w, h, 8, 8)
  lg.setColor(c[1], c[2], c[3], 0.35 * bright)
  lg.setLineWidth(2.5)
  lg.rectangle("line", x, y, w, h, 8, 8)
  local r = c[1] + (1 - c[1]) * 0.6
  local g = c[2] + (1 - c[2]) * 0.6
  local b = c[3] + (1 - c[3]) * 0.6
  lg.setColor(r, g, b, 0.9 * bright)
  lg.setLineWidth(1.2)
  lg.rectangle("line", x, y, w, h, 8, 8)
  lg.setLineWidth(1)
end

-- t: seconds since the draft opened (entry animation, staggered per card)
function M.draw(offer, selectedIndex, t)
  local lg = love.graphics
  local rs = M.layout(offer)

  for i = 1, #offer do
    local card = offer[i]
    local r = rs[i]
    -- staggered slide-up + fade over ~0.25s
    local at = (t or 1) - (i - 1) * 0.06
    local f = at / 0.22
    if f > 1 then f = 1 end
    if f < 0 then f = 0 end
    local ease = 1 - (1 - f) * (1 - f)
    local dy = (1 - ease) * 40
    local alpha = ease
    if alpha <= 0 then break end

    local selected = (i == selectedIndex)
    local scale = selected and 1.05 or 1
    local cw, ch = r.w * scale, r.h * scale
    local cx = r.x - (cw - r.w) * 0.5
    local cy = r.y - (ch - r.h) * 0.5 + dy

    local c = frameColor(card)

    lg.setColor(0.01, 0.03, 0.06, 0.92 * alpha)
    lg.rectangle("fill", cx, cy, cw, ch, 8, 8)
    neonRect(lg, cx, cy, cw, ch, c, (selected and 1.5 or 0.85) * alpha)

    local def = card.def
    local pad = 10

    -- title
    lg.setFont(Util.font(14))
    lg.setColor(1, 1, 1, 0.95 * alpha)
    lg.printf(def.name, cx + pad, cy + 14, cw - pad * 2, "center")

    -- NEW! / EVOLUTION! badge or level pips
    if card.isEvolution then
      lg.setFont(Util.font(11))
      lg.setColor(1, 0.85, 0.2, (0.7 + 0.3 * math.sin((t or 0) * 6)) * alpha)
      lg.printf("EVOLUTION!", cx + pad, cy + 52, cw - pad * 2, "center")
    elseif card.isNew then
      lg.setFont(Util.font(11))
      lg.setColor(c[1], c[2], c[3], 0.95 * alpha)
      lg.printf("NEW!", cx + pad, cy + 52, cw - pad * 2, "center")
    elseif card.fallback then
      lg.setFont(Util.font(11))
      lg.setColor(c[1], c[2], c[3], 0.8 * alpha)
      lg.printf("INSTANT", cx + pad, cy + 52, cw - pad * 2, "center")
    else
      local maxLv = def.maxLevel or 5
      local pipR = 3
      local spacing = 11
      local totalW = (maxLv - 1) * spacing
      local px0 = cx + cw * 0.5 - totalW * 0.5
      local py = cy + 57
      for p = 1, maxLv do
        if p <= card.newLevel then
          lg.setColor(c[1], c[2], c[3], 0.95 * alpha)
          lg.circle("fill", px0 + (p - 1) * spacing, py, pipR)
        else
          lg.setColor(c[1], c[2], c[3], 0.25 * alpha)
          lg.circle("line", px0 + (p - 1) * spacing, py, pipR)
        end
      end
    end

    -- kind tag
    lg.setFont(Util.font(10))
    lg.setColor(0.5, 0.65, 0.75, 0.7 * alpha)
    local tag = def.kind == "weapon" and "WEAPON"
      or def.kind == "passive" and "PASSIVE" or "BONUS"
    lg.printf(tag, cx + pad, cy + 74, cw - pad * 2, "center")

    -- description (levelDesc for the incoming level when present)
    local desc = def.desc
    if def.levelDesc and card.newLevel and def.levelDesc[card.newLevel] then
      desc = def.levelDesc[card.newLevel]
    end
    lg.setFont(Util.font(12))
    lg.setColor(0.8, 0.9, 0.95, 0.9 * alpha)
    lg.printf(desc or "", cx + pad, cy + 100, cw - pad * 2, "center")

    -- key hint
    lg.setFont(Util.font(11))
    lg.setColor(0.4, 0.55, 0.65, 0.6 * alpha)
    lg.printf(tostring(i), cx + pad, cy + ch - 24, cw - pad * 2, "center")
  end

  lg.setColor(1, 1, 1, 1)
end

return M
