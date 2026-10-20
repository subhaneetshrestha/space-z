-- src/states/pause.lua — translucent pause overlay: resume / save & quit.
-- Opened with params { save = fn, daily = bool } by the game state. A standard or
-- Black Hole run is saved when this opens and again on SAVE & QUIT, so it can be
-- continued from the menu. A daily run is not resumable: QUIT TO MENU drops it,
-- with no stardust award, as before.
local StateM = require("src.core.state")
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")
local Audio = require("src.audio.audio")

local VW, VH = Viewport.VW, Viewport.VH

local M = { translucent = true }

local ROW_COUNT = 2 -- RESUME + SAVE & QUIT / QUIT TO MENU (labels set in enter)
local ROW_H = 44
local ROW_W = 240

local function rowRect(i)
  local x = (VW - ROW_W) * 0.5
  local y = VH * 0.46 + (i - 1) * (ROW_H + 12)
  return x, y, ROW_W, ROW_H
end

function M:enter(params)
  self.selected = 1
  self.save = params and params.save
  self.daily = params and params.daily or false
  self.rows = { "RESUME", self.daily and "QUIT TO MENU" or "SAVE & QUIT" }
  if not self.daily and self.save then self.save() end
end

-- Back into the run through a 3-2-1, so unpausing never drops the player into
-- live danger. pop() runs game:resume() first; the countdown's own pop does again.
local function resumeRun()
  StateM.pop()
  StateM.push("countdown")
end

local function activate(self, i)
  Audio.play("confirm")
  if i == 1 then
    resumeRun()
  else
    -- the run is written again so the save is current to this very moment
    if not self.daily and self.save then self.save() end
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
  for i = 1, ROW_COUNT do
    local x, y, w, h = rowRect(i)
    local sel = i == self.selected
    lg.setColor(0.2, 0.9, 1, sel and 0.5 or 0.15)
    lg.rectangle("line", x, y, w, h, 6, 6)
    lg.setColor(1, 1, 1, sel and 0.95 or 0.6)
    lg.printf(self.rows[i], x, y + h * 0.5 - 9, w, "center")
  end
  lg.setColor(1, 1, 1, 1)
end

function M:keypressed(key)
  if key == "escape" then
    resumeRun()
  elseif key == "up" or key == "w" then
    self.selected = self.selected > 1 and self.selected - 1 or ROW_COUNT
  elseif key == "down" or key == "s" then
    self.selected = self.selected < ROW_COUNT and self.selected + 1 or 1
  elseif key == "return" or key == "space" then
    activate(self, self.selected)
  end
end

local function hitRow(x, y)
  for i = 1, ROW_COUNT do
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
