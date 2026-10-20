-- tests/support.lua — helpers shared by several test files (not a test file:
-- it is not in tests/run.lua's FILES list).
local M = {}

-- Path of the first difference between two plain tables, or nil when equal.
-- Numbers compare within 1e-9: json.lua writes floats with 14 significant
-- digits, so accumulated clocks (20 s of 1/60 steps) come back a hair off.
function M.firstDiff(a, b, path)
  path = path or "run"
  if type(a) ~= type(b) then return path .. " (type " .. type(a) .. " vs " .. type(b) .. ")" end
  if type(a) == "number" then
    if math.abs(a - b) > 1e-9 * math.max(1, math.abs(a)) then
      return path .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")"
    end
    return nil
  end
  if type(a) ~= "table" then
    if a ~= b then return path .. " (" .. tostring(a) .. " vs " .. tostring(b) .. ")" end
    return nil
  end
  for k, v in pairs(a) do
    local d = M.firstDiff(v, b[k], path .. "." .. tostring(k))
    if d then return d end
  end
  for k in pairs(b) do
    if a[k] == nil then return path .. "." .. tostring(k) .. " (missing in first)" end
  end
  return nil
end

return M
