-- src/meta/tech.lua — the Star-Map: bounded permanent boosts bought with Stardust.
-- Ranks live in Save.data().tech (map id -> rank). Bonuses fold into
-- Leveling.recomputeStats exactly like passives (mult stats add onto 1.0).
local M = {}

local floor = math.floor

-- perRank uses the same stat keys as passives/stats table
M.nodes = {
  { id = "hull", name = "Hull Lattice", stat = "maxhp", perRank = 12,
    maxRank = 5, baseCost = 150, desc = "+12 max hull per rank" },
  { id = "cannons", name = "Cannon Forge", stat = "damageMult", perRank = 0.04,
    maxRank = 5, baseCost = 200, desc = "+4% damage per rank" },
  { id = "reactor", name = "Reactor Tuning", stat = "fireRateMult", perRank = 0.03,
    maxRank = 5, baseCost = 200, desc = "+3% fire rate per rank" },
  { id = "engines", name = "Engine Gimbal", stat = "speed", perRank = 10,
    maxRank = 5, baseCost = 150, desc = "+10 thrust speed per rank" },
  { id = "magnet", name = "Tractor Array", stat = "magnetRadius", perRank = 14,
    maxRank = 5, baseCost = 120, desc = "+14 pickup range per rank" },
  { id = "lab", name = "Energy Lab", stat = "xpMult", perRank = 0.05,
    maxRank = 5, baseCost = 180, desc = "+5% XP per rank" },
  { id = "foundry", name = "Nano Foundry", stat = "regen", perRank = 0.25,
    maxRank = 3, baseCost = 300, desc = "+0.25 hull/s regen per rank" },
  { id = "optics", name = "Targeting Optics", stat = "critChance", perRank = 0.015,
    maxRank = 4, baseCost = 250, desc = "+1.5% crit chance per rank" },
  { id = "refinery", name = "Stardust Refinery", stat = "stardustMult", perRank = 0.06,
    maxRank = 5, baseCost = 220, desc = "+6% Stardust earned per rank" },
}

local byId = {}
for i = 1, #M.nodes do byId[M.nodes[i].id] = M.nodes[i] end

function M.node(id)
  return byId[id]
end

function M.rank(data, id)
  return (data.tech and data.tech[id]) or 0
end

-- cost of buying rank `nextRank` (1-based)
function M.cost(node, nextRank)
  return floor(node.baseCost * 1.7 ^ (nextRank - 1))
end

-- nil when affordable+available, else a reason string
function M.blocked(data, id)
  local node = byId[id]
  if not node then return "unknown node" end
  local rank = M.rank(data, id)
  if rank >= node.maxRank then return "maxed" end
  if (data.stardust or 0) < M.cost(node, rank + 1) then return "poor" end
  return nil
end

-- Deducts stardust and raises the rank. Caller persists via Save.write().
function M.buy(data, id)
  if M.blocked(data, id) then return false end
  local node = byId[id]
  local rank = M.rank(data, id)
  data.stardust = data.stardust - M.cost(node, rank + 1)
  data.tech = data.tech or {}
  data.tech[id] = rank + 1
  return true
end

-- stat -> total permanent bonus (additive, same semantics as passives)
function M.bonuses(data)
  local out = {}
  local tech = data.tech
  if not tech then return out end
  for i = 1, #M.nodes do
    local node = M.nodes[i]
    local rank = tech[node.id] or 0
    if rank > 0 then
      out[node.stat] = (out[node.stat] or 0) + node.perRank * rank
    end
  end
  return out
end

return M
