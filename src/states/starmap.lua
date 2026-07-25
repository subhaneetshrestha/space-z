-- src/states/starmap.lua — permanent tech tree bought with Stardust.
local StateM = require("src.core.state")
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")
local Tech = require("src.meta.tech")
local Save = require("src.meta.save")
local Audio = require("src.audio.audio")

local VW, VH = Viewport.VW, Viewport.VH

local M = {}

local ROW_H = 64
local TOP = 96

local function rowRect(i)
  return 20, TOP + (i - 1) * (ROW_H + 6), VW - 40, ROW_H
end

function M:enter()
  self.selected = 1
end

local function activate(self, i)
  local data = Save.data()
  local node = Tech.nodes[i]
  if Tech.buy(data, node.id) then
    Save.write()
    Audio.play("levelup", { pitch = 1.2 })
  else
    Audio.play("tick", { pitch = 0.6 })
  end
end

function M:draw()
  local lg = love.graphics
  lg.setColor(0.004, 0.008, 0.02, 1)
  lg.rectangle("fill", 0, 0, VW, VH)

  lg.setFont(Util.font(24))
  lg.setColor(0.3, 1, 1, 0.25)
  lg.printf("STAR MAP", 0, 26, VW, "center")
  lg.setColor(0.9, 1, 1, 0.95)
  lg.printf("STAR MAP", 0, 24, VW, "center")

  local data = Save.data()
  lg.setFont(Util.font(13))
  lg.setColor(1, 0.85, 0.4, 0.9)
  lg.printf("STARDUST  " .. data.stardust, 0, 58, VW, "center")

  for i, node in ipairs(Tech.nodes) do
    local x, y, w, h = rowRect(i)
    local sel = i == self.selected
    local rank = Tech.rank(data, node.id)
    local maxed = rank >= node.maxRank

    lg.setColor(1, 0.3, 0.9, sel and 0.55 or 0.12)
    lg.rectangle("line", x, y, w, h, 6, 6)

    lg.setFont(Util.font(14))
    lg.setColor(1, 1, 1, 0.95)
    lg.print(node.name, x + 14, y + 8)

    -- rank pips
    local px0 = x + 14
    local py = y + 36
    for p = 1, node.maxRank do
      if p <= rank then
        lg.setColor(1, 0.3, 0.9, 0.95)
        lg.circle("fill", px0 + (p - 1) * 14, py, 4)
      else
        lg.setColor(1, 0.3, 0.9, 0.25)
        lg.circle("line", px0 + (p - 1) * 14, py, 4)
      end
    end

    lg.setFont(Util.font(11))
    lg.setColor(0.5, 0.7, 0.8, 0.85)
    lg.print(node.desc, x + 14 + node.maxRank * 14 + 12, y + 30)

    lg.setFont(Util.font(12))
    if maxed then
      lg.setColor(0.3, 1, 0.5, 0.9)
      lg.printf("MAX", x, y + 8, w - 12, "right")
    else
      local cost = Tech.cost(node, rank + 1)
      local afford = data.stardust >= cost
      lg.setColor(1, 0.85, 0.4, afford and 0.95 or 0.45)
      lg.printf(cost .. " SD", x, y + 8, w - 12, "right")
    end
  end

  lg.setFont(Util.font(11))
  lg.setColor(0.4, 0.55, 0.65, 0.8)
  lg.printf("ENTER / TAP: RESEARCH    ·    ESC: BACK", 0, VH - 30, VW, "center")
  lg.setColor(1, 1, 1, 1)
end

function M:keypressed(key)
  if key == "escape" then
    StateM.switch("menu")
  elseif key == "up" or key == "w" then
    self.selected = self.selected > 1 and self.selected - 1 or #Tech.nodes
    Audio.play("tick")
  elseif key == "down" or key == "s" then
    self.selected = self.selected < #Tech.nodes and self.selected + 1 or 1
    Audio.play("tick")
  elseif key == "return" or key == "space" then
    activate(self, self.selected)
  end
end

local function hitRow(x, y)
  for i = 1, #Tech.nodes do
    local rx, ry, rw, rh = rowRect(i)
    if x >= rx and x <= rx + rw and y >= ry and y <= ry + rh then return i end
  end
  return nil
end

function M:mousepressed(x, y, b)
  if b ~= 1 then return end
  local i = hitRow(x, y)
  if i then
    self.selected = i
    activate(self, i)
  end
end

function M:mousemoved(x, y)
  local i = hitRow(x, y)
  if i and i ~= self.selected then
    self.selected = i
    Audio.play("tick")
  end
end

function M:touchpressed(id, x, y)
  local i = hitRow(x, y)
  if i then
    self.selected = i
    activate(self, i)
  end
end

return M
