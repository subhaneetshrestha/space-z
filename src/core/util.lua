-- src/core/util.lua — small math/table helpers (headless-safe: no love required at load).

local M = {}

local sqrt, atan2 = math.sqrt, math.atan2

function M.clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function M.lerp(a, b, t)
  return a + (b - a) * t
end

function M.dist2(x1, y1, x2, y2)
  local dx, dy = x2 - x1, y2 - y1
  return dx * dx + dy * dy
end

function M.len(x, y)
  return sqrt(x * x + y * y)
end

-- Zero-vector safe: returns 0,0 for (0,0).
function M.norm(x, y)
  local l = sqrt(x * x + y * y)
  if l == 0 then return 0, 0 end
  return x / l, y / l
end

function M.angleTo(x1, y1, x2, y2)
  return atan2(y2 - y1, x2 - x1)
end

-- Font cache guarded behind love so headless tests can require this module.
local fonts = {}
function M.font(size)
  local f = fonts[size]
  if not f then
    if not (love and love.graphics) then return nil end
    f = love.graphics.newFont(size)
    fonts[size] = f
  end
  return f
end

function M.wipe(t)
  for k in pairs(t) do t[k] = nil end
  return t
end

-- entries: array of { weight = n, ... }; missing weight counts as 1. Returns entry (nil if empty).
function M.weightedPick(rng, entries)
  local n = entries and #entries or 0
  if n == 0 then return nil end
  local total = 0
  for i = 1, n do
    total = total + (entries[i].weight or 1)
  end
  if total <= 0 then return entries[1] end
  local roll = rng:random() * total
  for i = 1, n do
    roll = roll - (entries[i].weight or 1)
    if roll < 0 then return entries[i] end
  end
  return entries[n] -- float round-off fallback
end

function M.approach(v, target, maxDelta)
  if v < target then
    v = v + maxDelta
    if v > target then v = target end
  elseif v > target then
    v = v - maxDelta
    if v < target then v = target end
  end
  return v
end

function M.printf(fmt, ...)
  print(string.format(fmt, ...))
end

return M
