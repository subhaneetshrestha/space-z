-- src/core/rng.lua — deterministic pure-Lua PRNG (Park–Miller MINSTD LCG).
-- No love.math dependency so it runs headless. All intermediates stay well below 2^53:
-- max state (2^31 - 2) * 48271 ≈ 1.04e14, exact in doubles → identical on every platform.

local M = {}

local floor = math.floor

local MOD = 2147483647       -- 2^31 - 1
local MULT = 48271           -- MINSTD multiplier
local INV = 1 / 2147483646   -- state ∈ [1, MOD-1] → (state - 1) * INV ∈ [0, 1)

local RNG = {}
RNG.__index = RNG

local function nextFloat(self)
  local s = (self._s * MULT) % MOD
  self._s = s
  return (s - 1) * INV
end

function M.new(seed)
  seed = floor(tonumber(seed) or 0)
  if seed < 0 then seed = -seed end
  seed = seed % MOD
  if seed == 0 then seed = 1013904223 end -- LCG state must be nonzero; fixed default for seed 0
  local r = setmetatable({ _s = seed }, RNG)
  -- burn a few outputs so numerically adjacent seeds (world streams use seed+1/+2/+3) decorrelate
  nextFloat(r)
  nextFloat(r)
  nextFloat(r)
  return r
end

-- random() -> [0,1) float; random(n) -> integer 1..n; random(a, b) -> integer a..b.
function RNG:random(a, b)
  local f = nextFloat(self)
  if a == nil then return f end
  local lo, hi
  if b == nil then
    lo, hi = 1, floor(a)
  else
    lo, hi = floor(a), floor(b)
  end
  if hi < lo then lo, hi = hi, lo end
  return lo + floor(f * (hi - lo + 1))
end

-- Float in [a, b).
function RNG:range(a, b)
  return a + nextFloat(self) * (b - a)
end

-- Always consumes exactly one draw regardless of p, so call sites advance the stream uniformly.
function RNG:chance(p)
  return nextFloat(self) < (p or 0)
end

function RNG:pick(list)
  local n = list and #list or 0
  if n == 0 then return nil end
  return list[1 + floor(nextFloat(self) * n)]
end

-- In-place Fisher–Yates; returns the list for convenience.
function RNG:shuffle(list)
  for i = #list, 2, -1 do
    local j = 1 + floor(nextFloat(self) * i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

return M
