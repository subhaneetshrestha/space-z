-- src/states/levelup.lua — translucent draft overlay: pick 1 of 3 cards.
local StateM = require("src.core.state")
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")
local Leveling = require("src.systems.leveling")
local Cards = require("src.render.cards")
local Audio = require("src.audio.audio")

local VW, VH = Viewport.VW, Viewport.VH

local M = { translucent = true }

function M:enter(params)
  self.world = params.world
  self.offer = Leveling.buildOffer(self.world)
  self.selected = 1
  self.t = 0
  if #self.offer == 0 then
    StateM.pop()
    return
  end
  Audio.play("levelup")
end

local function pick(self, index)
  local card = self.offer[index]
  if not card then return end
  Leveling.apply(self.world, card)
  Audio.play("confirm")
  StateM.pop()
end

function M:update(dt)
  self.t = self.t + dt
  if self.world.autopilot and self.t > 0.3 then
    pick(self, 1)
  end
end

function M:draw()
  local lg = love.graphics
  lg.setColor(0, 0, 0, 0.7)
  lg.rectangle("fill", 0, 0, VW, VH)

  local header = "LEVEL " .. self.world.level
  lg.setFont(Util.font(22))
  lg.setColor(0.3, 1, 1, 0.25)
  lg.printf(header, 0, VH * 0.5 - 168, VW, "center")
  lg.setColor(0.9, 1, 1, 0.95)
  lg.printf(header, 0, VH * 0.5 - 166, VW, "center")

  Cards.draw(self.offer, self.selected, self.t)

  lg.setFont(Util.font(12))
  lg.setColor(0.5, 0.7, 0.8, 0.7)
  lg.printf("TAP A CARD  ·  1/2/3  ·  ARROWS + ENTER", 0, VH * 0.5 + 132, VW, "center")
  lg.setColor(1, 1, 1, 1)
end

function M:keypressed(key)
  if key == "1" then pick(self, 1)
  elseif key == "2" then pick(self, 2)
  elseif key == "3" then pick(self, 3)
  elseif key == "left" or key == "a" then
    self.selected = self.selected > 1 and self.selected - 1 or #self.offer
    Audio.play("tick")
  elseif key == "right" or key == "d" then
    self.selected = self.selected < #self.offer and self.selected + 1 or 1
    Audio.play("tick")
  elseif key == "return" or key == "space" then
    pick(self, self.selected)
  end
end

function M:mousepressed(x, y, b)
  if b ~= 1 then return end
  local i = Cards.hit(self.offer, x, y)
  if i then pick(self, i) end
end

function M:mousemoved(x, y)
  local i = Cards.hit(self.offer, x, y)
  if i then self.selected = i end
end

function M:touchpressed(id, x, y)
  local i = Cards.hit(self.offer, x, y)
  if i then pick(self, i) end
end

return M
