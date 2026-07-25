-- src/core/pool.lua — table pools + swap-remove sweep for entity lists.

local M = {}

local Pool = {}
Pool.__index = Pool

function M.new()
  return setmetatable({ _free = {}, _n = 0 }, Pool)
end

-- Returns a table wiped of all keys (spawn helpers must fully re-initialize it).
function Pool:acquire()
  local n = self._n
  if n > 0 then
    local t = self._free[n]
    self._free[n] = nil
    self._n = n - 1
    t.__pooled = nil
    return t
  end
  return {}
end

function Pool:release(t)
  -- __pooled marker guards against double-release handing the same table out twice;
  -- it is removed on acquire so acquired tables really are key-free.
  if t == nil or t.__pooled then return end
  for k in pairs(t) do t[k] = nil end
  t.__pooled = true
  local n = self._n + 1
  self._n = n
  self._free[n] = t
end

-- Removes entries with e.dead == true via swap-remove (order not preserved),
-- releasing each removed entry into `pool` (optional).
function M.sweep(list, pool)
  local n = #list
  local i = 1
  while i <= n do
    local e = list[i]
    if e == nil or e.dead then
      list[i] = list[n]
      list[n] = nil
      n = n - 1
      if e ~= nil and pool then pool:release(e) end
      -- do not advance i: the swapped-in entry must be checked too
    else
      i = i + 1
    end
  end
end

return M
