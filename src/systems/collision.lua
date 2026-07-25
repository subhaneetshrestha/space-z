-- src/systems/collision.lua — uniform-grid spatial hash + collision resolution.
-- Enemies are inserted each frame; bullets/ebullets/player query the grid.
-- Buckets are reused across frames (reset via a stored count, never re-allocated).
local Damage = require("src.systems.damage")

local M = {}

local floor = math.floor

local CELL = 64
local INV_CELL = 1 / CELL
local KEY_STRIDE = 4096 -- world is tiny (<4096 cells wide after offset), keys never collide

local buckets = {}   -- key -> { n = count, [1..n] = enemies }
local usedKeys = {}  -- numeric list of keys touched this frame
local usedN = 0

local queryOut = {}  -- scratch for internal queries

local function key(cx, cy)
  -- +32 offset keeps cell coords positive for entities slightly off-screen
  return (cx + 32) + (cy + 32) * KEY_STRIDE
end

local function clearGrid()
  for i = 1, usedN do
    buckets[usedKeys[i]].n = 0
  end
  usedN = 0
end

local function insert(e)
  -- an entity spans up to 4 cells when its radius crosses cell borders
  local r = e.r
  local x0 = floor((e.x - r) * INV_CELL)
  local x1 = floor((e.x + r) * INV_CELL)
  local y0 = floor((e.y - r) * INV_CELL)
  local y1 = floor((e.y + r) * INV_CELL)
  for cy = y0, y1 do
    for cx = x0, x1 do
      local k = key(cx, cy)
      local b = buckets[k]
      if not b then
        b = { n = 0 }
        buckets[k] = b
      end
      if b.n == 0 then
        usedN = usedN + 1
        usedKeys[usedN] = k
      end
      local n = b.n + 1
      b.n = n
      b[n] = e
    end
  end
end

-- Fills `out` with candidate enemies near the circle (may contain duplicates for
-- multi-cell entities and non-overlapping candidates — callers must distance-test).
-- Returns the candidate count. `out` is only valid until the next query.
local function queryCircle(x, y, r, out)
  local x0 = floor((x - r) * INV_CELL)
  local x1 = floor((x + r) * INV_CELL)
  local y0 = floor((y - r) * INV_CELL)
  local y1 = floor((y + r) * INV_CELL)
  local n = 0
  for cy = y0, y1 do
    for cx = x0, x1 do
      local b = buckets[key(cx, cy)]
      if b then
        for i = 1, b.n do
          n = n + 1
          out[n] = b[i]
        end
      end
    end
  end
  return n
end

M.queryCircle = queryCircle -- exposed for other systems / tests

function M.update(world, dt)
  clearGrid()
  local enemies = world.enemies
  for i = 1, #enemies do
    local e = enemies[i]
    if not e.dead then insert(e) end
  end

  -- player bullets -> enemies
  local bullets = world.bullets
  for i = 1, #bullets do
    local b = bullets[i]
    if not b.dead then
      local n = queryCircle(b.x, b.y, b.r, queryOut)
      for j = 1, n do
        local e = queryOut[j]
        if not e.dead and not e.entering then
          local dx, dy = e.x - b.x, e.y - b.y
          local rr = e.r + b.r
          if dx * dx + dy * dy <= rr * rr then
            Damage.hitEnemy(world, e, b)
            if b.aoe then
              -- nuclear warhead: splash 60% damage to everything in the radius
              local enemies2 = world.enemies
              local aoeR = b.aoe
              local splash = b.damage * 0.6
              for k = 1, #enemies2 do
                local e2 = enemies2[k]
                if not e2.dead and not e2.entering and e2 ~= e then
                  local ddx, ddy = e2.x - b.x, e2.y - b.y
                  local arr = aoeR + e2.r
                  if ddx * ddx + ddy * ddy <= arr * arr then
                    Damage.direct(world, e2, splash, false)
                  end
                end
              end
              world.events:emit("aoe_blast", b.x, b.y, aoeR)
              b.dead = true
              break
            end
            b.pierce = b.pierce - 1
            if b.pierce < 0 then
              b.dead = true
              break
            end
          end
        end
      end
    end
  end

  local player = world.player
  if not player or player.dead then return end

  -- enemies -> player (touch damage)
  if player.invulnT <= 0 then
    local n = queryCircle(player.x, player.y, player.r, queryOut)
    for j = 1, n do
      local e = queryOut[j]
      if not e.dead and not e.entering then
        local dx, dy = e.x - player.x, e.y - player.y
        local rr = e.r + player.r
        if dx * dx + dy * dy <= rr * rr then
          Damage.hitPlayer(world, e.touchDamage or 8, e)
          break
        end
      end
    end
  end

  -- enemy bullets -> player (few vs one: plain loop, no grid)
  local ebullets = world.ebullets
  local px, py, pr = player.x, player.y, player.r
  for i = 1, #ebullets do
    local b = ebullets[i]
    if not b.dead then
      local dx, dy = b.x - px, b.y - py
      local rr = b.r + pr
      if dx * dx + dy * dy <= rr * rr then
        b.dead = true
        if player.invulnT <= 0 then
          Damage.hitPlayer(world, b.damage, b)
        end
      end
    end
  end
end

return M
