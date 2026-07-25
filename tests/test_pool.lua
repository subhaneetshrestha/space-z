-- tests/test_pool.lua — pool reuse identity + sweep semantics.
local Pool = require("src.core.pool")

local T = {}

function T.acquire_returns_wiped_table(t)
  local p = Pool.new()
  local a = p:acquire()
  a.x = 5
  a.name = "foo"
  p:release(a)
  local b = p:acquire()
  t.eq(b, a, "released table is reused (identity)")
  t.eq(next(b), nil, "reused table has no keys")
end

function T.double_release_guard(t)
  local p = Pool.new()
  local a = p:acquire()
  p:release(a)
  p:release(a) -- must not enqueue twice
  local b = p:acquire()
  local c = p:acquire()
  t.ok(b ~= c, "double release must not hand the same table out twice")
end

function T.sweep_removes_dead_and_releases(t)
  local p = Pool.new()
  local list = {}
  for i = 1, 6 do
    local e = p:acquire()
    e.id = i
    e.dead = (i % 2 == 0)
    list[i] = e
  end
  Pool.sweep(list, p)
  t.eq(#list, 3, "3 live entries remain")
  for i = 1, #list do
    t.ok(not list[i].dead, "no dead entries remain")
  end
  -- released tables come back from the pool
  local reused = p:acquire()
  t.eq(next(reused), nil, "swept tables were wiped into the pool")
end

function T.sweep_handles_adjacent_dead(t)
  local p = Pool.new()
  local list = {}
  for i = 1, 5 do
    list[i] = { id = i, dead = (i >= 2 and i <= 4) } -- 3 dead in a row
  end
  Pool.sweep(list, p)
  t.eq(#list, 2, "adjacent dead entries all removed")
  local seen = {}
  for i = 1, #list do seen[list[i].id] = true end
  t.ok(seen[1] and seen[5], "survivors are 1 and 5")
end

function T.sweep_all_dead(t)
  local p = Pool.new()
  local list = { { dead = true }, { dead = true } }
  Pool.sweep(list, p)
  t.eq(#list, 0, "everything swept")
end

return T
