-- tests/run.lua — tiny headless test harness. Run from the repo root:
--   lua tests/run.lua        (plain Lua 5.1 / LuaJIT)
--   lovec . --test           (through LÖVE; main.lua calls runAll())
package.path = "./?.lua;./?/init.lua;" .. package.path

local M = {}

local t = {}

function t.eq(a, b, msg)
  if a ~= b then
    error(string.format("%s: expected %s, got %s",
      msg or "eq", tostring(b), tostring(a)), 2)
  end
end

function t.ok(v, msg)
  if not v then
    error((msg or "ok") .. ": expected truthy, got " .. tostring(v), 2)
  end
end

function t.near(a, b, eps, msg)
  eps = eps or 1e-9
  if math.abs(a - b) > eps then
    error(string.format("%s: expected %s ± %s, got %s",
      msg or "near", tostring(b), tostring(eps), tostring(a)), 2)
  end
end

local FILES = {
  "tests.test_rng",
  "tests.test_pool",
  "tests.test_json",
  "tests.test_save",
  "tests.test_damage",
  "tests.test_leveling",
  "tests.test_pickups",
  "tests.test_spawner",
  "tests.test_boss",
  "tests.test_music",
  "tests.test_zones",
  "tests.test_evolutions",
  "tests.test_effects",
  "tests.test_meta",
  "tests.test_input",
}

function M.runAll()
  local passed, failed = 0, 0
  for _, modname in ipairs(FILES) do
    local okLoad, tests = pcall(require, modname)
    if not okLoad then
      failed = failed + 1
      print("FAIL " .. modname .. " (load): " .. tostring(tests))
    else
      -- stable order: sort test names
      local names = {}
      for name in pairs(tests) do names[#names + 1] = name end
      table.sort(names)
      for _, name in ipairs(names) do
        local ok, err = pcall(tests[name], t)
        if ok then
          passed = passed + 1
          print("PASS " .. modname .. "." .. name)
        else
          failed = failed + 1
          print("FAIL " .. modname .. "." .. name .. ": " .. tostring(err))
        end
      end
    end
  end
  print(string.format("%d passed, %d failed", passed, failed))
  return failed
end

-- auto-run when executed directly (not when required by main.lua under LÖVE)
if arg and arg[0] and tostring(arg[0]):find("run%.lua") then
  local failures = M.runAll()
  os.exit(failures > 0 and 1 or 0)
end

return M
