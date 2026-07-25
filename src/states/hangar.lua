-- src/states/hangar.lua — ship roster: buy with Stardust, select the active ship.
local StateM = require("src.core.state")
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")
local Sprites = require("src.render.sprites")
local Ships = require("src.content.ships")
local Weapons = require("src.content.weapons")
local Save = require("src.meta.save")
local Audio = require("src.audio.audio")

local VW, VH = Viewport.VW, Viewport.VH

local M = {}

local ROW_H = 78
local TOP = 96

local function rowRect(i)
  return 20, TOP + (i - 1) * (ROW_H + 6), VW - 40, ROW_H
end

function M:enter()
  self.selected = 1
  local ship = Save.data().settings.ship
  for i, id in ipairs(Ships.order) do
    if id == ship then self.selected = i end
  end
end

local function owned(id)
  local ships = Save.data().unlocked.ships
  return ships and ships[id]
end

local function activate(self, i)
  local data = Save.data()
  local id = Ships.order[i]
  local ship = Ships[id]
  if owned(id) then
    data.settings.ship = id
    Save.write()
    Audio.play("confirm")
  elseif data.stardust >= ship.price then
    data.stardust = data.stardust - ship.price
    data.unlocked.ships[id] = true
    data.settings.ship = id
    Save.write()
    Audio.play("levelup")
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
  lg.printf("HANGAR", 0, 26, VW, "center")
  lg.setColor(0.9, 1, 1, 0.95)
  lg.printf("HANGAR", 0, 24, VW, "center")

  local data = Save.data()
  lg.setFont(Util.font(13))
  lg.setColor(1, 0.85, 0.4, 0.9)
  lg.printf("STARDUST  " .. data.stardust, 0, 58, VW, "center")

  local batch = Sprites.batch()
  batch:clear()

  for i, id in ipairs(Ships.order) do
    local ship = Ships[id]
    local x, y, w, h = rowRect(i)
    local sel = i == self.selected
    local isOwned = owned(id)
    local active = data.settings.ship == id

    lg.setColor(0.2, 0.9, 1, sel and 0.55 or 0.12)
    lg.rectangle("line", x, y, w, h, 6, 6)
    if active then
      lg.setColor(0.2, 0.9, 1, 0.08)
      lg.rectangle("fill", x, y, w, h, 6, 6)
    end

    Sprites.add(batch, ship.sprite, x + 34, y + h * 0.5, 0, 1,
      1, 1, 1, isOwned and 1 or 0.35)

    lg.setFont(Util.font(15))
    lg.setColor(1, 1, 1, isOwned and 0.95 or 0.55)
    lg.print(ship.name, x + 68, y + 8)

    lg.setFont(Util.font(11))
    lg.setColor(0.5, 0.7, 0.8, 0.85)
    lg.print(string.format("HULL %d   SPD %d   %s",
      ship.maxhp, ship.speed, Weapons[ship.startingWeapon].name), x + 68, y + 30)
    lg.setColor(0.45, 0.6, 0.7, 0.7)
    lg.printf(ship.desc, x + 68, y + 46, w - 80, "left")

    lg.setFont(Util.font(12))
    if active then
      lg.setColor(0.3, 1, 0.5, 0.95)
      lg.printf("ACTIVE", x, y + 8, w - 12, "right")
    elseif isOwned then
      lg.setColor(0.6, 0.9, 1, 0.8)
      lg.printf("OWNED", x, y + 8, w - 12, "right")
    else
      local afford = data.stardust >= ship.price
      lg.setColor(1, 0.85, 0.4, afford and 0.95 or 0.45)
      lg.printf(ship.price .. " SD", x, y + 8, w - 12, "right")
    end
  end

  lg.setColor(1, 1, 1, 1)
  lg.setBlendMode("add")
  lg.draw(batch)
  lg.setBlendMode("alpha")

  lg.setFont(Util.font(11))
  lg.setColor(0.4, 0.55, 0.65, 0.8)
  lg.printf("ENTER / TAP: SELECT OR BUY    ·    ESC: BACK", 0, VH - 30, VW, "center")
  lg.setColor(1, 1, 1, 1)
end

function M:keypressed(key)
  if key == "escape" then
    StateM.switch("menu")
  elseif key == "up" or key == "w" then
    self.selected = self.selected > 1 and self.selected - 1 or #Ships.order
    Audio.play("tick")
  elseif key == "down" or key == "s" then
    self.selected = self.selected < #Ships.order and self.selected + 1 or 1
    Audio.play("tick")
  elseif key == "return" or key == "space" then
    activate(self, self.selected)
  end
end

local function hitRow(x, y)
  for i = 1, #Ships.order do
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
