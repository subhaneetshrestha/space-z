-- src/states/menu.lua — hub: launch, hangar, star map, mode toggle (when the
-- Black Hole is unlocked), stardust & achievement tallies.
local StateM = require("src.core.state")
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")
local Sprites = require("src.render.sprites")
local Starfield = require("src.render.starfield")
local Ships = require("src.content.ships")
local Save = require("src.meta.save")
local Achievements = require("src.meta.achievements")
local Audio = require("src.audio.audio")
local Music = require("src.audio.music")

local VW, VH = Viewport.VW, Viewport.VH

local M = {}

local ROW_W, ROW_H = 260, 44
local ROWS_Y = VH * 0.50

local function rows()
  local data = Save.data()
  local list = { "LAUNCH", "DAILY RUN", "HANGAR", "STAR MAP" }
  if data.unlocked.blackhole then
    list[5] = "MODE: " .. (data.settings.mode == "blackhole" and "BLACK HOLE" or "STANDARD")
  end
  return list
end

local function rowRect(i)
  local x = (VW - ROW_W) * 0.5
  local y = ROWS_Y + (i - 1) * (ROW_H + 10)
  return x, y, ROW_W, ROW_H
end

function M:enter()
  self.starfield = Starfield.new(1, Save.data().settings.quality)
  self.batch = Sprites.batch()
  self.t = 0
  self.selected = 1
  Audio.load()
  Music.play("menu")
end

local function activate(self, i)
  local list = rows()
  local label = list[i]
  if not label then return end
  local data = Save.data()
  if label == "LAUNCH" then
    Audio.play("confirm")
    StateM.switch("game", { mode = data.settings.mode or "standard" })
  elseif label == "DAILY RUN" then
    -- same seed for everyone today; standard rules
    Audio.play("confirm")
    StateM.switch("game", {
      mode = "standard", daily = true,
      seed = tonumber(os.date("%Y%m%d")),
    })
  elseif label == "HANGAR" then
    Audio.play("confirm")
    StateM.switch("hangar")
  elseif label == "STAR MAP" then
    Audio.play("confirm")
    StateM.switch("starmap")
  else -- mode toggle
    data.settings.mode = data.settings.mode == "blackhole" and "standard" or "blackhole"
    Save.write()
    Audio.play("pulse", { pitch = data.settings.mode == "blackhole" and 0.8 or 1.4 })
  end
end

function M:update(dt)
  self.t = self.t + dt
  self.starfield:update(dt, 60)
end

function M:draw()
  local lg = love.graphics
  local data = Save.data()
  local blackhole = data.settings.mode == "blackhole" and data.unlocked.blackhole

  lg.setColor(0.004, 0.008, 0.02, 1)
  lg.rectangle("fill", 0, 0, VW, VH)

  local batch = self.batch
  batch:clear()
  self.starfield:draw(batch)
  local ship = Ships[data.settings.ship] or Ships.pathfinder
  local shipY = VH * 0.385 + math.sin(self.t * 1.3) * 5
  Sprites.add(batch, ship.sprite, VW * 0.5, shipY, 0, 1.3, 1, 1, 1, 1)
  lg.setColor(1, 1, 1, 1)
  lg.setBlendMode("add")
  lg.draw(batch)
  lg.setBlendMode("alpha")

  -- neon title (reddened in Black Hole mode)
  local title = "SPACE Z"
  local ty = VH * 0.16
  local tr, tg, tb = 0.2, 0.9, 1
  if blackhole then tr, tg, tb = 1, 0.25, 0.45 end
  lg.setFont(Util.font(52))
  local pulse = 0.8 + 0.2 * math.sin(self.t * 2)
  lg.setColor(tr, tg, tb, 0.12 * pulse)
  for dx = -3, 3, 3 do
    for dy = -3, 3, 3 do
      if dx ~= 0 or dy ~= 0 then lg.printf(title, dx, ty + dy, VW, "center") end
    end
  end
  lg.setColor(tr, tg, tb, 0.5 * pulse)
  lg.printf(title, 0, ty + 1, VW, "center")
  lg.setColor(1, 1, 1, 0.95)
  lg.printf(title, 0, ty, VW, "center")

  lg.setFont(Util.font(13))
  lg.setColor(0.5, 0.8, 0.9, 0.8)
  lg.printf("A VERTICAL-ASCENT ROGUELITE", 0, ty + 62, VW, "center")

  -- tallies
  lg.setFont(Util.font(13))
  lg.setColor(1, 0.85, 0.4, 0.9)
  lg.printf("STARDUST  " .. (data.stardust or 0), 0, VH * 0.30, VW, "center")
  local have, total = Achievements.count()
  lg.setColor(0.6, 0.75, 0.85, 0.8)
  lg.printf(ship.name:upper() .. "    ·    ACHIEVEMENTS " .. have .. "/" .. total,
    0, VH * 0.30 + 20, VW, "center")

  -- option rows
  local list = rows()
  lg.setFont(Util.font(16))
  for i = 1, #list do
    local x, y, w, h = rowRect(i)
    local sel = i == self.selected
    local isMode = list[i]:sub(1, 5) == "MODE:"
    local cr, cg, cb = 0.2, 0.9, 1
    if isMode and data.settings.mode == "blackhole" then cr, cg, cb = 1, 0.25, 0.45 end
    lg.setColor(cr, cg, cb, sel and 0.55 or 0.15)
    lg.rectangle("line", x, y, w, h, 6, 6)
    lg.setColor(1, 1, 1, sel and 0.95 or 0.6)
    lg.printf(list[i], x, y + h * 0.5 - 9, w, "center")
  end

  -- footer toggles
  lg.setFont(Util.font(11))
  lg.setColor(0.4, 0.55, 0.65, 0.8)
  lg.printf("WASD / ARROWS / MOUSE-DRAG / ONE THUMB", 0, VH - 58, VW, "center")
  lg.printf("[M] STEERING: " .. string.upper(data.settings.steerMode)
    .. "    [S] SOUND: " .. (data.settings.sound ~= false and "ON" or "OFF")
    .. "    [Q] FX: " .. string.upper(data.settings.quality or "high"),
    0, VH - 40, VW, "center")
  if data.daily and data.daily.date == os.date("%Y%m%d") then
    lg.setColor(0.6, 0.75, 0.85, 0.7)
    lg.printf("TODAY'S DAILY BEST: " .. data.daily.bestStardust .. " SD",
      0, VH - 76, VW, "center")
  end
  lg.setColor(1, 1, 1, 1)
end

function M:keypressed(key)
  local n = #rows()
  if key == "space" or key == "return" then
    activate(self, self.selected)
  elseif key == "up" then
    self.selected = self.selected > 1 and self.selected - 1 or n
    Audio.play("tick")
  elseif key == "down" then
    self.selected = self.selected < n and self.selected + 1 or 1
    Audio.play("tick")
  elseif key == "m" then
    local settings = Save.data().settings
    settings.steerMode = settings.steerMode == "floating" and "absolute" or "floating"
    Save.write()
    Audio.play("tick")
  elseif key == "s" then
    local settings = Save.data().settings
    settings.sound = not (settings.sound ~= false)
    Save.write()
    Music.refresh()
    Audio.play("tick")
  elseif key == "q" then
    local settings = Save.data().settings
    settings.quality = settings.quality == "low" and "high" or "low"
    Save.write()
    Audio.play("tick")
  elseif key == "b" then
    -- shortcut for the mode toggle when unlocked (always the last row)
    if Save.data().unlocked.blackhole then
      activate(self, #rows())
    end
  end
end

local function hitRow(x, y, n)
  for i = 1, n do
    local rx, ry, rw, rh = rowRect(i)
    if x >= rx and x <= rx + rw and y >= ry and y <= ry + rh then return i end
  end
  return nil
end

function M:mousepressed(x, y, b)
  if b ~= 1 then return end
  local i = hitRow(x, y, #rows())
  if i then
    self.selected = i
    activate(self, i)
  end
end

function M:mousemoved(x, y)
  local i = hitRow(x, y, #rows())
  if i and i ~= self.selected then
    self.selected = i
    Audio.play("tick")
  end
end

function M:touchpressed(id, x, y)
  local i = hitRow(x, y, #rows())
  if i then
    self.selected = i
    activate(self, i)
  end
end

return M
