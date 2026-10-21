-- tests/test_runsave_fuzz.lua — a run save is untrusted input (a hand-edited, truncated or
-- corrupt run.json). Take rich, real saves, mutate every field in many hostile ways, and
-- require that each result is either REJECTED by validation, or, if validation lets it
-- through, RESUMES safely: no error, no hang, no NaN or infinity in the world.
--
-- Bases (all real, from the game): a busy field with one of every kind of entity, a
-- boss fight in two different pattern states, and a warp. For the lists of entities only
-- one entry per distinct shape is mutated (the rest repeat it); small lists are mutated
-- in full. A hang is caught by an instruction budget (the spawner loop that a
-- corrupt timer used to make spin for ~666 million passes would trip it).
local StateM = require("src.core.state")
local RunSave = require("src.meta.runsave")
local Spawner = require("src.systems.spawner")
local Damage = require("src.systems.damage")
local Leveling = require("src.systems.leveling")
local Pickups = require("src.systems.pickups")
local Weapons = require("src.content.weapons")
local Zones = require("src.content.zones")
local json = require("lib.json")
local H = require("tests.game_harness")

local T = {}
local test = H.guarded(T)

local STEP = H.STEP
local NAN = 0 / 0
local REMOVE = {} -- sentinel: delete the field

-- the instruction budget for one resumed mutant (a hang trips it); how many frames each
-- base is played for is set per base below: a boss pattern only reads some of its
-- fields in some states, so it needs long enough to cycle through them
local BUDGET = 3e7 -- the heaviest legitimate mutant uses about 1M
-- extreme values are all stepped; ordinary ones (v+1, -v, ...) only every STRIDE-th
local STRIDE = 6

-- ------------------------------------------------------------------- bases

local function updateGame(n)
  for _ = 1, n or 1 do H.Game:update(STEP) end
end

local function stepUntil(pred, limit)
  for _ = 1, limit or 900 do
    if pred() then return true end
    updateGame(1)
  end
  return pred()
end

local function snapshotOf(w)
  local run = RunSave.snapshot(w)
  assert(run, "fixture: the world must be saveable")
  return json.decode(json.encode(run))
end

local function withDurableEnemies(fn)
  local original = Spawner.spawnEnemy
  Spawner.spawnEnemy = function(...)
    local e = original(...)
    e.hp, e.maxhp = 1e8, 1e8
    return e
  end
  local ok, err = pcall(fn)
  Spawner.spawnEnemy = original
  if not ok then error(err, 0) end
end

local function indexOf(list, item)
  for i = 1, #list do if list[i] == item then return i end end
end

-- a busy field: one of every enemy movement type, an elite, gems (one being pulled in),
-- a locked missile, a chilling shard, a drone cooling down, enemy bullets
local function busyField(t)
  local base
  withDurableEnemies(function()
    local w = H.start({ seed = 818 })
    for _, id in ipairs({ "missiles", "flak", "cryo", "drones" }) do Leveling.addWeapon(w, Weapons[id]) end
    for i = 1, #w.weapons do w.weapons[i].level = w.weapons[i].def.maxLevel end
    Leveling.recomputeStats(w)
    local p = w.player
    local kinds = { "drifter", "shard", "stinger", "sentry", "meteor", "lunar_hopper" }
    for i, id in ipairs(kinds) do
      Spawner.spawnEnemy(w, id, 70 + i * 55, 100 + i * 12, id == "drifter" and { elite = true } or nil)
    end
    local ring = Weapons.drones.levels[Weapons.drones.maxLevel].orbitR
    for i = 0, 5 do -- enemies on the drones' ring, so they hit something
      local a = i * math.pi / 3
      Spawner.spawnEnemy(w, "drifter", p.x + math.cos(a) * ring, p.y + math.sin(a) * ring)
    end
    Pickups.dropXp(w, p.x + 40, p.y - 30, 30)
    Pickups.dropXp(w, 100, 200, 7)
    Pickups.dropXp(w, 380, 150, 1)
    local function ready()
      local locked, cryo, cooling = false, false, false
      for i = 1, #w.bullets do
        local b = w.bullets[i]
        if b.homing and b.target and indexOf(w.enemies, b.target) then locked = true end
        if b.weaponId == "cryo" and b.slowT then cryo = true end
      end
      for i = 1, #w.drones do
        for enemy, expiry in pairs(w.drones[i].hitCd) do
          if not enemy.dead and expiry > w.time then cooling = true end
        end
      end
      return locked and cryo and cooling and #w.ebullets > 0
    end
    t.ok(stepUntil(ready, 2400), "fixture: the busy field has one of everything")
    base = snapshotOf(w)
  end)
  return base
end

local function bossFight(zoneIndex, state)
  local w = H.start({ seed = 700 + zoneIndex })
  for i = 1, #w.weapons do w.weapons[i].cooldown = 3000 end
  w.zoneIndex, w.zone, w.zoneTime = zoneIndex, Zones[zoneIndex], Zones[zoneIndex].duration
  w.spawnerState = { timers = {} }
  stepUntil(function() return w.phase == "boss" end, 600)
  return w
end

local function bossInState(t, zoneIndex, state)
  local w = bossFight(zoneIndex)
  w.boss.hp = w.boss.maxhp * 0.4 -- second phase
  t.ok(stepUntil(function()
    return w.boss and not w.boss.entering and w.boss.state == state and w.boss.bt > 6
  end, 3600), "fixture: the boss reaches " .. state)
  return snapshotOf(w)
end

local function warp(t)
  local w = bossFight(1)
  t.ok(stepUntil(function() return w.boss and not w.boss.entering and w.boss.bt >= 3 end, 3000), "fixture")
  w.boss.hp = 1
  Damage.direct(w, w.boss, 1e6, false)
  updateGame(30)
  t.eq(w.phase, "warp", "fixture: the boss died")
  return snapshotOf(w)
end

-- ----------------------------------------------------------------- mutations

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = deepCopy(x) end
  return c
end

local function sortedKeys(node)
  local keys = {}
  for k in pairs(node) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) ~= type(b) then return type(a) < type(b) end
    return a < b
  end)
  return keys
end

local ENTITY_LISTS = { enemies = true, bullets = true, ebullets = true, pickups = true, drones = true }

-- Entries of a list that look alike (same keys, same def / weapon / boss, same sizes of
-- the lists inside them) are one shape. The sizes matter: a drone with no cooldowns and
-- one with three have different things to get wrong.
local function shapeOf(entry)
  local parts = {}
  for _, k in ipairs(sortedKeys(entry)) do
    local v = entry[k]
    parts[#parts + 1] = tostring(k) .. (type(v) == "table" and ("#" .. #v) or "")
  end
  return table.concat(parts, ",") .. "|" .. tostring(entry.def or entry.boss or entry.weaponId or entry.ptype or "")
end

-- every place a value lives: { path = { key, key, ... }, value = v }
local function collect(node, path, listName, out)
  local seen = {}
  for _, k in ipairs(sortedKeys(node)) do
    local v = node[k]
    local skip = false
    if listName and type(v) == "table" then -- an entity of a big list: first of each shape only
      local shape = shapeOf(v)
      if seen[shape] then skip = true end
      seen[shape] = true
    end
    if not skip then
      local p = {}
      for i = 1, #path do p[i] = path[i] end
      p[#p + 1] = k
      out[#out + 1] = { path = p, value = v }
      if type(v) == "table" then
        collect(v, p, ENTITY_LISTS[k] and k or nil, out)
      end
    end
  end
  return out
end

-- { name, value, extreme }: extreme values are the ones that break loops and arithmetic
local function mutationsOf(v)
  local list = {}
  local function add(name, value, extreme) list[#list + 1] = { name = name, value = value, extreme = extreme } end
  add("removed", REMOVE, true)
  if type(v) == "number" then
    add("NaN", NAN, true); add("+inf", math.huge, true); add("-inf", -math.huge, true)
    add("1e9", 1e9, true); add("-1e9", -1e9, true); add("0", 0, true)
    add("a string", "1"); add("a table", {}); add("true", true)
    add("negated", -v); add("+1", v + 1); add("x1000", v * 1000); add("+0.5", v + 0.5)
  elseif type(v) == "string" then
    add("a number", 5); add("a table", {}); add("empty", ""); add("junk", "zzz"); add("true", true)
  elseif type(v) == "boolean" then
    add("a number", 0); add("a string", "true"); add("flipped", not v)
  elseif type(v) == "table" then
    add("a number", 5); add("a string", "x"); add("true", true); add("emptied", {}, true)
    if #v > 0 then
      add("first removed", { shift = true })
      add("first duplicated", { dup = true })
    end
  end
  return list
end

local function applyMutation(run, site, m)
  local parent = run
  for i = 1, #site.path - 1 do parent = parent[site.path[i]] end
  local key = site.path[#site.path]
  if m.value == REMOVE then
    parent[key] = nil
  elseif type(m.value) == "table" and m.value.shift then
    table.remove(parent[key], 1)
  elseif type(m.value) == "table" and m.value.dup then
    table.insert(parent[key], 1, deepCopy(parent[key][1]))
  else
    parent[key] = deepCopy(m.value)
  end
end

local function describe(site)
  local parts = {}
  for i = 1, #site.path do parts[i] = tostring(site.path[i]) end
  return table.concat(parts, ".")
end

-- ------------------------------------------------------------------- outcomes

-- the first NaN / infinity found in the simulation state of a world, or nil
local function nonFinite(world)
  local function bad(v) return type(v) == "number" and (v ~= v or v == math.huge or v == -math.huge) end
  local function scan(t, where)
    for k, v in pairs(t) do
      if bad(v) then return where .. "." .. tostring(k) .. " = " .. tostring(v) end
    end
  end
  local found = scan(world, "world") or scan(world.player, "player")
  if found then return found end
  for _, name in ipairs({ "enemies", "bullets", "ebullets", "pickups", "drones" }) do
    local list = world[name]
    for i = 1, #list do
      found = scan(list[i], name .. "[" .. i .. "]")
      if found then return found end
    end
  end
  for i, o in ipairs(world.weapons) do
    found = scan(o, "weapons[" .. i .. "]")
    if found then return found end
  end
end

-- Things that must hold in any world the game can be in, so they must hold after a
-- resume too. A boss phase with no boss never ends (a soft-lock), and a boss outside
-- the boss phase is a second fight nobody asked for.
local function inconsistent(world)
  local boss = world.boss
  if world.phase == "boss" then
    if not boss or boss.dead then return "the boss phase has no live boss" end
    if not boss.isBoss then return "world.boss is not a boss" end
    local inList = false
    for i = 1, #world.enemies do if world.enemies[i] == boss then inList = true end end
    if not inList then return "world.boss is not in the enemy list" end
  elseif boss ~= nil then
    return "world.boss is set in the " .. tostring(world.phase) .. " phase"
  end
  if world.phase == "warp" and not (world.warpT <= RunSave.WARP_TIME) then
    return "the warp clock is " .. tostring(world.warpT)
  end
end

-- resume a save that passed validation through the real game:enter and play on
local function resumeAndPlay(run, frames)
  H.setup()
  local twin = setmetatable({}, { __index = H.Game })
  twin:enter({ resume = run, seed = run.seed })
  if StateM.current() == H.Countdown then StateM.pop() end
  for _ = 1, frames do twin:update(STEP) end
  local found = nonFinite(twin.world)
  if found then error("a non-finite value after the resume: " .. found, 0) end
  local broken = inconsistent(twin.world)
  if broken then error("an inconsistent world after the resume: " .. broken, 0) end
end

-- Runs fn under an instruction budget; a mutant that spins (the spawner loop a corrupt
-- timer used to make run ~666 million passes) trips it. LuaJIT's compiled loops ignore
-- count hooks, so the JIT is switched off while the hook is armed; under plain Lua 5.1
-- (CI) there is no `jit` and the hook just works.
local maxUsed = 0
local function withBudget(fn)
  local STEP_COUNT = 1e4
  local units, limit = 0, BUDGET / STEP_COUNT
  local hadJit = jit and jit.status and jit.status()
  if jit then
    jit.off()
    jit.flush() -- traces already compiled would still run, uncounted
  end
  debug.sethook(function()
    units = units + 1
    if units > limit then error("instruction budget exceeded: a hang", 0) end
  end, "", STEP_COUNT)
  local ok, err = pcall(fn)
  debug.sethook()
  if jit and hadJit then jit.on() end
  maxUsed = math.max(maxUsed, units * STEP_COUNT)
  return ok, err
end

-- run every mutation of every site of `base`; returns the failures and the tallies
local function fuzz(base, frames)
  local failures, tally = {}, { cases = 0, valid = 0, stepped = 0, rejected = 0 }
  local sites = collect(base, {}, nil, {})
  local counter = 0
  for _, site in ipairs(sites) do
    for _, m in ipairs(mutationsOf(site.value)) do
      tally.cases = tally.cases + 1
      local run = deepCopy(base)
      applyMutation(run, site, m)
      local label = describe(site) .. " -> " .. m.name
      local ok, valid = pcall(RunSave.validate, run)
      if not ok then
        failures[#failures + 1] = "validate THREW on " .. label .. ": " .. tostring(valid)
      elseif valid then
        tally.valid = tally.valid + 1
        counter = counter + 1
        if m.extreme or counter % STRIDE == 0 then
          tally.stepped = tally.stepped + 1
          local played, err = withBudget(function() resumeAndPlay(run, frames) end)
          local trace = os.getenv("FUZZ_TRACE")
          if trace and label:find(trace, 1, true) then
            print("[fuzz trace] " .. label .. " => " .. (played and "survived" or tostring(err)))
          end
          if not played then failures[#failures + 1] = label .. ": " .. tostring(err) end
        end
      else
        tally.rejected = tally.rejected + 1
      end
    end
  end
  return failures, tally
end

local function check(t, base, name, frames)
  local failures, tally = fuzz(base, frames)
  if os.getenv("FUZZ_VERBOSE") then
    print(string.format("[fuzz] %-16s %5d mutants: %5d rejected, %4d valid, %4d of those resumed and played %d frames",
      name, tally.cases, tally.rejected, tally.valid, tally.stepped, frames))
    print(string.format("[fuzz]   most instructions one resumed mutant used so far: %.1fM (budget %dM)",
      maxUsed / 1e6, BUDGET / 1e6))
  end
  local shown = {}
  for i = 1, math.min(#failures, 8) do shown[i] = failures[i] end
  t.eq(#failures, 0, string.format("%s: %d of %d mutants got through unsafely (%d valid, %d stepped):\n  %s",
    name, #failures, tally.cases, tally.valid, tally.stepped, table.concat(shown, "\n  ")))
  t.ok(tally.cases > 200, name .. ": the fuzz must really mutate something (" .. tally.cases .. " cases)")
  t.ok(tally.rejected > tally.cases * 0.5, name .. ": most hostile mutants must be rejected")
end

test("fuzz_a_busy_field_with_one_of_every_entity", function(t)
  check(t, busyField(t), "busy field", 40)
end)

test("fuzz_a_leviathan_fight_in_its_dive", function(t)
  check(t, bossInState(t, 2, "dive"), "leviathan dive", 480) -- dive, rise, hover, telegraph, dive
end)

test("fuzz_a_storm_fight_in_its_telegraph", function(t)
  check(t, bossInState(t, 5, "telegraph"), "storm telegraph", 480) -- dash, drift, pulse, ...
end)

test("fuzz_the_warp_after_a_boss", function(t)
  check(t, warp(t), "warp", 200) -- the warp runs out (2.5 s) and the next zone begins
end)

return T
