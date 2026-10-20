-- tests/test_rng.lua — determinism + distribution bounds for the pure-Lua PRNG.
local RNG = require("src.core.rng")

local T = {}

function T.same_seed_same_sequence(t)
  local a = RNG.new(42)
  local b = RNG.new(42)
  for i = 1, 100 do
    t.eq(a:random(), b:random(), "draw " .. i)
  end
end

function T.different_seeds_differ(t)
  local a = RNG.new(1)
  local b = RNG.new(2)
  local same = 0
  for _ = 1, 50 do
    if a:random() == b:random() then same = same + 1 end
  end
  t.ok(same < 5, "sequences should diverge (same=" .. same .. ")")
end

function T.seed_zero_ok(t)
  local r = RNG.new(0)
  local v = r:random()
  t.ok(v >= 0 and v < 1, "seed 0 must produce valid draws")
end

function T.random_n_bounds(t)
  local r = RNG.new(7)
  for _ = 1, 1000 do
    local v = r:random(6)
    t.ok(v >= 1 and v <= 6, "random(6) in 1..6, got " .. v)
    t.eq(v, math.floor(v), "integer")
  end
end

function T.random_a_b_bounds(t)
  local r = RNG.new(9)
  for _ = 1, 1000 do
    local v = r:random(-3, 3)
    t.ok(v >= -3 and v <= 3, "random(-3,3) bounds, got " .. v)
  end
end

function T.range_bounds(t)
  local r = RNG.new(11)
  for _ = 1, 1000 do
    local v = r:range(10, 20)
    t.ok(v >= 10 and v < 20, "range(10,20) bounds, got " .. v)
  end
end

function T.chance_extremes(t)
  local r = RNG.new(13)
  for _ = 1, 200 do
    t.eq(r:chance(0), false, "chance(0) never true")
  end
  for _ = 1, 200 do
    t.eq(r:chance(1), true, "chance(1) always true")
  end
end

function T.pick_and_shuffle(t)
  local r = RNG.new(17)
  t.eq(r:pick({}), nil, "pick from empty list")
  local list = { "a", "b", "c" }
  for _ = 1, 50 do
    local v = r:pick(list)
    t.ok(v == "a" or v == "b" or v == "c", "pick returns an element")
  end
  local nums = { 1, 2, 3, 4, 5, 6, 7, 8 }
  r:shuffle(nums)
  t.eq(#nums, 8, "shuffle preserves length")
  local sum = 0
  for _, v in ipairs(nums) do sum = sum + v end
  t.eq(sum, 36, "shuffle preserves multiset")
end

function T.shuffle_deterministic(t)
  local a = RNG.new(23)
  local b = RNG.new(23)
  local la = { 1, 2, 3, 4, 5 }
  local lb = { 1, 2, 3, 4, 5 }
  a:shuffle(la)
  b:shuffle(lb)
  for i = 1, 5 do t.eq(la[i], lb[i], "same shuffle at " .. i) end
end

function T.state_roundtrip_resumes_stream(t)
  local a = RNG.new(31)
  for _ = 1, 17 do a:random() end -- mid-stream, not a fresh seed
  local saved = a:getState()
  local b = RNG.new(999)          -- unrelated stream, overwritten by setState
  t.eq(b:setState(saved), true, "valid state accepted")
  for i = 1, 100 do
    t.eq(b:random(), a:random(), "draw " .. i)
  end
end

function T.state_is_a_plain_number(t)
  local s = RNG.new(5):getState()
  t.eq(type(s), "number", "state must be JSON-friendly")
end

function T.setstate_rejects_bad_values(t)
  local r = RNG.new(41)
  local before = r:getState()
  local bad = { "7", 0, -1, 2147483647, 1.5, 0 / 0, 1 / 0, {}, true }
  for i = 1, #bad do
    t.eq(r:setState(bad[i]), false, "rejects bad value #" .. i)
    t.eq(r:getState(), before, "state unchanged after bad value #" .. i)
  end
  t.eq(r:setState(nil), false, "rejects nil")
  t.eq(r:getState(), before, "state unchanged after nil")
end

return T
