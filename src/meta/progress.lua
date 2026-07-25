-- src/meta/progress.lua — run-end accounting. The stardust formula lives HERE only.
local Save = require("src.meta.save")
local Achievements = require("src.meta.achievements")

local M = {}

local floor, max = math.floor, math.max

-- Progress.endRun(world, won) -> summary
-- NOT idempotent: awards stardust and bumps totalRuns every call, so the caller
-- (game.lua) must guard and call this exactly once per run.
function M.endRun(world, won)
  won = won and true or false
  local kills = world.kills or 0
  local distance = world.distance or 0
  local blackhole = world.mode == "blackhole"
  local stardust = kills
    + 5 * floor(distance / 1000)
    + 40 * (world.bossKills or 0)
    + (world.stardustEarned or 0) -- in-run bonuses from fallback cards

  -- Star-Map refinery bonus, then the Black Hole 2x multiplier
  local stardustMult = (world.stats and world.stats.stardustMult) or 1
  stardust = floor(stardust * stardustMult * (blackhole and 2 or 1))

  world.stardustEarned = stardust -- final total, for gameover display

  local data = Save.data()
  data.stardust = (data.stardust or 0) + stardust
  data.totalRuns = (data.totalRuns or 0) + 1
  data.bestLevel = max(data.bestLevel or 0, world.level or 1)
  if blackhole then
    data.bestDistanceBH = max(data.bestDistanceBH or 0, distance)
  else
    data.bestDistance = max(data.bestDistance or 0, distance)
  end

  -- lifetime stats feed achievements
  data.stats = data.stats or { kills = 0, wins = 0, bhWins = 0, stardust = 0 }
  local stats = data.stats
  stats.kills = (stats.kills or 0) + kills
  stats.stardust = (stats.stardust or 0) + stardust
  if won then
    stats.wins = (stats.wins or 0) + 1
    if blackhole then stats.bhWins = (stats.bhWins or 0) + 1 end
  end

  if type(data.unlocked) ~= "table" then
    data.unlocked = { blackhole = false, ships = { pathfinder = true } }
  end
  local unlockedBlackhole = false
  if won and world.mode == "standard" and world.noDamage
      and not data.unlocked.blackhole then
    data.unlocked.blackhole = true
    unlockedBlackhole = true
  end

  -- daily-seed run: local best board for today (resets when the date rolls)
  local dailyBest = nil
  if world.daily then
    local today = os.date("%Y%m%d")
    if not data.daily or data.daily.date ~= today then
      data.daily = { date = today, bestStardust = 0, bestDistance = 0, runs = 0 }
    end
    data.daily.runs = data.daily.runs + 1
    data.daily.bestStardust = max(data.daily.bestStardust, stardust)
    data.daily.bestDistance = max(data.daily.bestDistance, distance)
    dailyBest = data.daily
  end

  local newAchievements = Achievements.evaluateEndRun(world, won)

  Save.write()

  return {
    stardust = stardust,
    won = won,
    unlockedBlackhole = unlockedBlackhole,
    newAchievements = newAchievements,
    dailyBest = dailyBest,
    zoneIndex = world.zoneIndex or 1,
    level = world.level or 1,
    kills = kills,
    time = world.time or 0,
    distance = distance,
    blackhole = blackhole,
  }
end

return M
