-- src/states/gameover.lua — run-end overlay: VICTORY or SHIP LOST + stats + stardust.
local StateM = require("src.core.state")
local Viewport = require("src.core.viewport")
local Util = require("src.core.util")
local Audio = require("src.audio.audio")
local Music = require("src.audio.music")

local VW, VH = Viewport.VW, Viewport.VH

local M = { translucent = true }

function M:enter(params)
  self.won = params.won
  self.world = params.world
  self.summary = params.summary or {}
  self.t = 0
  self.quitQueued = false
  Music.stop()
  Audio.play(self.won and "jingle_win" or "jingle_lose")
end

function M:update(dt)
  self.t = self.t + dt
  if self.world.autopilot and self.t > 1 and not self.quitQueued then
    -- smoke run: main.lua finalizes its report in love.quit
    self.quitQueued = true
    love.event.quit(0)
  end
end

local function statRow(lg, label, value, y)
  lg.setColor(0.5, 0.7, 0.8, 0.85)
  lg.printf(label, VW * 0.5 - 150, y, 150, "left")
  lg.setColor(0.95, 1, 1, 0.95)
  lg.printf(tostring(value), VW * 0.5, y, 150, "right")
end

function M:draw()
  local lg = love.graphics
  lg.setColor(0, 0, 0, 0.78)
  lg.rectangle("fill", 0, 0, VW, VH)

  local title = self.won and "VICTORY" or "SHIP LOST"
  local tc = self.won and { 0.3, 1, 1 } or { 1, 0.3, 0.25 }
  lg.setFont(Util.font(36))
  lg.setColor(tc[1], tc[2], tc[3], 0.25)
  lg.printf(title, 0, VH * 0.20 + 2, VW, "center")
  lg.setColor(tc[1], tc[2], tc[3], 0.95)
  lg.printf(title, 0, VH * 0.20, VW, "center")

  local world = self.world
  local s = self.summary
  lg.setFont(Util.font(14))
  local y = VH * 0.36
  statRow(lg, "ZONE", world.zone and world.zone.name or "-", y)
  statRow(lg, "LEVEL", world.level, y + 26)
  statRow(lg, "KILLS", world.kills, y + 52)
  statRow(lg, "TIME", string.format("%d:%02d", world.time / 60, world.time % 60), y + 78)
  statRow(lg, "DISTANCE", string.format("%.1f KM", world.distance / 100), y + 104)

  lg.setFont(Util.font(18))
  lg.setColor(1, 0.85, 0.4, 0.95)
  local sdLine = "+" .. (s.stardust or 0) .. " STARDUST"
  if s.blackhole then sdLine = sdLine .. "  (x2)" end
  lg.printf(sdLine, 0, y + 148, VW, "center")

  if s.dailyBest then
    lg.setFont(Util.font(12))
    lg.setColor(0.6, 0.85, 1, 0.9)
    lg.printf("DAILY RUN  ·  TODAY'S BEST: " .. s.dailyBest.bestStardust .. " SD",
      0, y + 176, VW, "center")
  end

  if s.newAchievements and #s.newAchievements > 0 then
    local ay = s.dailyBest and y + 198 or y + 176
    lg.setFont(Util.font(12))
    for i = 1, math.min(#s.newAchievements, 3) do
      lg.setColor(1, 0.9, 0.3, 0.9)
      lg.printf("ACHIEVEMENT: " .. s.newAchievements[i].name,
        0, ay + (i - 1) * 18, VW, "center")
    end
  end

  if s.unlockedBlackhole then
    local pulse = 0.7 + 0.3 * math.sin(self.t * 3)
    lg.setFont(Util.font(14))
    lg.setColor(0.8, 0.4, 1, pulse)
    lg.printf("FLAWLESS.  A DARK DOOR OPENS...", 0, y + 236, VW, "center")
    lg.setColor(0.6, 0.3, 0.8, pulse * 0.9)
    lg.printf("BLACK HOLE MODE UNLOCKED", 0, y + 256, VW, "center")
  end

  if self.t > 0.8 and math.sin(self.t * 4) > -0.3 then
    lg.setFont(Util.font(14))
    lg.setColor(0.9, 1, 1, 0.9)
    lg.printf("TAP / PRESS ANY KEY", 0, VH * 0.82, VW, "center")
  end
  lg.setColor(1, 1, 1, 1)
end

local function leave()
  StateM.switch("menu")
end

function M:keypressed()
  if self.t > 0.8 then leave() end
end

function M:mousepressed(x, y, b)
  if b == 1 and self.t > 0.8 then leave() end
end

function M:touchpressed()
  if self.t > 0.8 then leave() end
end

return M
