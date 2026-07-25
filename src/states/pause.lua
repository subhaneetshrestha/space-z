-- src/states/pause.lua — translucent pause overlay: resume / quit to menu.
-- Quitting mid-run counts as a loss with no stardust award.
local StateM = require("src.core.state")
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")
local Audio = require("src.audio.audio")

local VW, VH = Viewport.VW, Viewport.VH

local M = { translucent = true }

local ROWS = { "RESUME", "QUIT TO MENU" }
local ROW_H = 44
local ROW_W = 240

local function rowRect(i)
  local x = (VW - ROW_W) * 0.5
  local y = VH * 0.46 + (i - 1) * (ROW_H + 12)
  return x, y, ROW_W, ROW_H
end

function M:enter()
  self.selected = 1
end

local function activate(self, i)
  Audio.play("confirm")
  if i == 1 then
    StateM.pop()
  else
    StateM.switch("menu")
  end
end

function M:draw()
  local lg = love.graphics
  lg.setColor(0, 0, 0, 0.7)
  lg.rectangle("fill", 0, 0, VW, VH)

  lg.setFont(Util.font(28))
  lg.setColor(0.3, 1, 1, 0.25)
  lg.printf("PAUSED", 0, VH * 0.32 + 2, VW, "center")
  lg.setColor(0.9, 1, 1, 0.95)
  lg.printf("PAUSED", 0, VH * 0.32, VW, "center")

  lg.setFont(Util.font(16))
  for i = 1, #ROWS do
    local x, y, w, h = rowRect(i)
    local sel = i == self.selected
    lg.setColor(0.2, 0.9, 1, sel and 0.5 or 0.15)
    lg.rectangle("line", x, y, w, h, 6, 6)
    lg.setColor(1, 1, 1, sel and 0.95 or 0.6)
    lg.printf(ROWS[i], x, y + h * 0.5 - 9, w, "center")
  end
  lg.setColor(1, 1, 1, 1)
end

function M:keypressed(key)
  if key == "escape" then
    StateM.pop()
  elseif key == "up" or key == "w" then
    self.selected = self.selected > 1 and self.selected - 1 or #ROWS
  elseif key == "down" or key == "s" then
    self.selected = self.selected < #ROWS and self.selected + 1 or 1
  elseif key == "return" or key == "space" then
    activate(self, self.selected)
  end
end

local function hitRow(x, y)
  for i = 1, #ROWS do
    local rx, ry, rw, rh = rowRect(i)
    if x >= rx and x <= rx + rw and y >= ry and y <= ry + rh then
      return i
    end
  end
  return nil
end

function M:mousepressed(x, y, b)
  if b ~= 1 then return end
  local i = hitRow(x, y)
  if i then activate(self, i) end
end

function M:mousemoved(x, y)
  local i = hitRow(x, y)
  if i then self.selected = i end
end

function M:touchpressed(id, x, y)
  local i = hitRow(x, y)
  if i then activate(self, i) end
end

return M
