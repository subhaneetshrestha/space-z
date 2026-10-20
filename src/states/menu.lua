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

local ABANDON_LABEL = "ABANDON SAVE? TAP AGAIN"

-- Rows are rebuilt on each call: the MODE row's text changes when it is toggled.
-- CONTINUE leads only while a valid saved run exists (self.run, read on enter).
function M.rows(self)
  local data = Save.data()
  local list = {}
  if self.run then list[1] = "CONTINUE" end
  list[#list + 1] = "LAUNCH"
  list[#list + 1] = "DAILY RUN"
  list[#list + 1] = "HANGAR"
  list[#list + 1] = "STAR MAP"
  if data.unlocked.blackhole then
    list[#list + 1] = "MODE: " .. (data.settings.mode == "blackhole" and "BLACK HOLE" or "STANDARD")
  end
  return list
end

-- What a row shows: its name, or the abandon prompt while it is armed. Pass the
-- current `list` when it is already built (draw does) to avoid rebuilding it.
function M.label(self, i, list)
  local label = (list or M.rows(self))[i]
  if label and label == self.armed then return ABANDON_LABEL end
  return label
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
  self.run = Save.run() -- nil unless a valid saved run exists
  self.armed = nil      -- row waiting for a confirming second press
  Audio.load()
  Music.play("menu")
end

-- A new run replaces the saved one, so with a save present the first press only
-- arms the row; the second press on the same row goes through. Returns true when
-- the run may start (clearing the old save, valid or not).
local function confirmNewRun(self, label)
  if self.run and self.armed ~= label then
    self.armed = label
    Audio.play("tick")
    return false
  end
  self.armed = nil
  Save.clearRun()
  return true
end

local function activate(self, i)
  local list = M.rows(self)
  local label = list[i]
  if not label then return end
  if self.armed ~= label then self.armed = nil end -- any other row disarms
  local data = Save.data()
  if label == "CONTINUE" then
    Audio.play("confirm")
    local run = self.run
    StateM.switch("game", { resume = run, mode = run.mode, seed = run.seed })
  elseif label == "LAUNCH" then
    if not confirmNewRun(self, label) then return end
    Audio.play("confirm")
    StateM.switch("game", { mode = data.settings.mode or "standard" })
  elseif label == "DAILY RUN" then
    if not confirmNewRun(self, label) then return end
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
  local list = M.rows(self)
  lg.setFont(Util.font(16))
  for i = 1, #list do
    local x, y, w, h = rowRect(i)
    local sel = i == self.selected
    local isMode = list[i]:sub(1, 5) == "MODE:"
    local cr, cg, cb = 0.2, 0.9, 1
    if isMode and data.settings.mode == "blackhole" then cr, cg, cb = 1, 0.25, 0.45 end
    if list[i] == self.armed then cr, cg, cb = 1, 0.6, 0.25 end -- abandon prompt
    lg.setColor(cr, cg, cb, sel and 0.55 or 0.15)
    lg.rectangle("line", x, y, w, h, 6, 6)
    lg.setColor(1, 1, 1, sel and 0.95 or 0.6)
    lg.printf(M.label(self, i, list), x, y + h * 0.5 - 9, w, "center")
  end

  -- footer toggles
  lg.setFont(Util.font(11))
  lg.setColor(0.4, 0.55, 0.65, 0.8)
  lg.printf("DRAG ANYWHERE TO STEER  /  WASD / ARROWS", 0, VH - 58, VW, "center")
  lg.printf("[S] SOUND: " .. (data.settings.sound ~= false and "ON" or "OFF")
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
  local n = #M.rows(self)
  if key == "space" or key == "return" then
    activate(self, self.selected)
  elseif key == "up" then
    self.selected = self.selected > 1 and self.selected - 1 or n
    self.armed = nil
    Audio.play("tick")
  elseif key == "down" then
    self.selected = self.selected < n and self.selected + 1 or 1
    self.armed = nil
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
      activate(self, #M.rows(self))
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
  local i = hitRow(x, y, #M.rows(self))
  if i then
    self.selected = i
    activate(self, i)
  end
end

function M:mousemoved(x, y)
  local i = hitRow(x, y, #M.rows(self))
  if i and i ~= self.selected then
    self.selected = i
    self.armed = nil
    Audio.play("tick")
  end
end

function M:touchpressed(id, x, y)
  local i = hitRow(x, y, #M.rows(self))
  if i then
    self.selected = i
    activate(self, i)
  end
end

return M
