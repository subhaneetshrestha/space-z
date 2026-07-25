-- src/meta/achievements.lua — definitions + tracking. Lifetime counters live in
-- Save.data().stats; unlocked ids in Save.data().achievements. Live unlocks
-- (mid-run) toast via world.toasts; the rest are evaluated at run end by
-- progress.lua and surfaced on the gameover screen.
local Save = require("src.meta.save")

local M = {}

M.defs = {
  { id = "first_blood", name = "First Blood", desc = "Destroy your first hostile." },
  { id = "exterminator", name = "Exterminator", desc = "2,500 lifetime kills." },
  { id = "scout", name = "Long Way Up", desc = "Reach Mars (zone 3)." },
  { id = "pathbreaker", name = "Pathbreaker", desc = "Reach Jupiter (zone 5)." },
  { id = "edge_of_void", name = "Edge of the Void", desc = "Reach the Void (zone 7)." },
  { id = "veteran", name = "Veteran", desc = "Hit level 20 in a single run." },
  { id = "evolved", name = "Apex Arsenal", desc = "Evolve a weapon." },
  { id = "savior", name = "Savior of Earth", desc = "Beat the Space Z Overlord." },
  { id = "untouchable", name = "Untouchable", desc = "Win a run without taking a scratch.", secret = true },
  { id = "event_horizon", name = "Event Horizon", desc = "Win a Black Hole run.", secret = true },
}

local byId = {}
for i = 1, #M.defs do byId[M.defs[i].id] = M.defs[i] end

function M.has(id)
  local a = Save.data().achievements
  return a and a[id] or false
end

function M.count()
  local n = 0
  for i = 1, #M.defs do
    if M.has(M.defs[i].id) then n = n + 1 end
  end
  return n, #M.defs
end

-- Returns true if newly unlocked (caller decides when to Save.write()).
function M.unlock(id)
  local data = Save.data()
  data.achievements = data.achievements or {}
  if data.achievements[id] then return false end
  data.achievements[id] = true
  return true
end

local function toast(world, id)
  local def = byId[id]
  local toasts = world.toasts
  toasts[#toasts + 1] = { text = "ACHIEVEMENT: " .. def.name, t = 0, life = 3 }
end

-- Wire in-run unlocks (toasted live). Called from game.lua enter.
function M.live(world)
  local events = world.events

  events:on("level_up", function(level)
    if level >= 20 and M.unlock("veteran") then
      toast(world, "veteran")
      Save.write()
    end
  end)

  events:on("weapon_evolved", function()
    if M.unlock("evolved") then
      toast(world, "evolved")
      Save.write()
    end
  end)

  events:on("zone_completed", function(zoneIndex)
    local reached = zoneIndex + 1
    local hit = nil
    if reached >= 3 and M.unlock("scout") then hit = "scout" end
    if reached >= 5 and M.unlock("pathbreaker") then hit = "pathbreaker" end
    if reached >= 7 and M.unlock("edge_of_void") then hit = "edge_of_void" end
    if hit then
      toast(world, hit)
      Save.write()
    end
  end)
end

-- Run-end evaluation. Lifetime stats must already be updated by the caller.
-- Returns an array of newly unlocked defs (for the gameover screen).
function M.evaluateEndRun(world, won)
  local data = Save.data()
  local stats = data.stats
  local new = {}
  local function try(id, cond)
    if cond and M.unlock(id) then new[#new + 1] = byId[id] end
  end
  try("first_blood", stats.kills > 0)
  try("exterminator", stats.kills >= 2500)
  try("savior", won)
  try("untouchable", won and world.mode == "standard" and world.noDamage)
  try("event_horizon", won and world.mode == "blackhole")
  return new
end

return M
