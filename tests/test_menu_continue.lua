-- tests/test_menu_continue.lua — the CONTINUE row and the "abandon saved run?"
-- guard, through the real menu state and state stack. Only rendering and audio
-- modules are stubbed.
local StateM = require("src.core.state")
local Save = require("src.meta.save")

local T = {}

local function noop() end
local function catchAll()
  return setmetatable({}, { __index = function() return noop end })
end

local STUBBED = {
  "src.render.sprites", "src.render.starfield", "src.audio.audio", "src.audio.music",
}

-- Private copy of states/menu.lua against stubbed render/audio modules.
local function loadMenu()
  local saved = {}
  for _, name in ipairs(STUBBED) do saved[name] = package.loaded[name] end
  for _, name in ipairs(STUBBED) do package.loaded[name] = catchAll() end
  package.loaded["src.render.starfield"] = { new = function() return catchAll() end }
  package.loaded["src.render.sprites"] = { batch = function() return catchAll() end, add = noop }
  package.loaded["src.states.menu"] = nil
  local Menu = require("src.states.menu")
  for _, name in ipairs(STUBBED) do package.loaded[name] = saved[name] end
  package.loaded["src.states.menu"] = nil
  return Menu
end

local Menu
local started -- params of the last StateM.switch("game", ...)

local function validRun(over)
  local run = {
    version = 1, mode = "standard", seed = 5, ship = "pathfinder",
    time = 61.5, distance = 7400.5, zoneIndex = 2, zoneTime = 20, zoneStartDistance = 5000,
    level = 5, xp = 3, xpNext = 30, pendingLevelUps = 0, kills = 30, bossKills = 1,
    noDamage = false, stardustEarned = 0, hp = 42.5,
    weapons = { { id = "blaster", level = 2 } }, passives = {},
    rng = { spawn = 1234, drops = 2345, cards = 3456, misc = 4567 },
    spawnerTimers = {},
  }
  for k, v in pairs(over or {}) do run[k] = v end
  return run
end

local function setup(run)
  Menu = Menu or loadMenu()
  while StateM.current() do StateM.pop() end
  started = nil
  StateM.register("menu", Menu)
  StateM.register("game", { enter = function(_, p) started = p or {} end })
  StateM.register("hangar", {})
  StateM.register("starmap", {})
  Save.reset()
  if run then Save.setRun(run) end
  StateM.switch("menu")
end

local function teardown()
  while StateM.current() do StateM.pop() end
end

-- the menu's current rows (rebuilt on every call, like the menu itself does)
local function list() return Menu.rows(Menu) end

local function indexOf(label)
  for i, l in ipairs(list()) do
    if l == label then return i end
  end
end

local function press(key) StateM.keypressed(key) end

local function select(label)
  Menu.selected = indexOf(label)
end

-- -------------------------------------------------------------- the rows

function T.without_a_save_the_menu_is_unchanged(t)
  setup()
  t.eq(table.concat(list(), "|"), "LAUNCH|DAILY RUN|HANGAR|STAR MAP")
  t.eq(Menu.selected, 1)
  press("return")
  t.ok(started, "LAUNCH starts straight away")
  t.eq(started.resume, nil)
  teardown()
end

function T.a_saved_run_adds_continue_as_the_first_selected_row(t)
  setup(validRun())
  t.eq(table.concat(list(), "|"), "CONTINUE|LAUNCH|DAILY RUN|HANGAR|STAR MAP")
  t.eq(Menu.selected, 1)
  teardown()
end

function T.continue_resumes_with_the_saved_run(t)
  setup(validRun({ mode = "blackhole", seed = 99 }))
  press("return")
  t.ok(started, "the game started")
  t.eq(started.resume.seed, 99)
  t.eq(started.resume.hp, 42.5)
  t.eq(started.mode, "blackhole", "the run's own mode, not settings.mode")
  t.eq(started.seed, 99)
  t.ok(Save.run(), "continuing keeps the save until the run ends")
  teardown()
end

function T.tapping_the_continue_row_resumes(t)
  setup(validRun())
  StateM.mousepressed(240, 427 + 20, 1) -- centre of row 1 (rows start at VH * 0.5)
  t.ok(started and started.resume, "mouse on CONTINUE resumes")
  teardown()
end

function T.a_corrupt_save_shows_no_continue_and_does_not_block_launch(t)
  setup()
  Save.data().run = { version = 1, mode = "standard" } -- truncated / hand-edited
  StateM.switch("menu")
  t.eq(table.concat(list(), "|"), "LAUNCH|DAILY RUN|HANGAR|STAR MAP")
  press("return")
  t.ok(started, "LAUNCH starts without a confirmation")
  t.eq(Save.data().run, nil, "the unusable save is cleared")
  teardown()
end

function T.the_mode_hotkey_still_targets_the_last_row(t)
  setup(validRun())
  Save.data().unlocked.blackhole = true
  StateM.switch("menu")
  t.eq(list()[#list()], "MODE: STANDARD")
  press("b")
  t.eq(Save.data().settings.mode, "blackhole")
  teardown()
end

-- ----------------------------------------------------------- the guard

function T.launch_with_a_save_needs_a_second_press(t)
  setup(validRun())
  select("LAUNCH")
  press("return")
  t.eq(started, nil, "first press only arms the confirmation")
  t.ok(Save.run(), "the save is still there")
  t.eq(Menu.armed, "LAUNCH")
  press("return")
  t.ok(started, "second press starts the new run")
  t.eq(started.resume, nil)
  t.eq(Save.run(), nil, "and the old save is discarded")
  teardown()
end

function T.daily_run_with_a_save_needs_a_second_press(t)
  setup(validRun())
  select("DAILY RUN")
  press("return")
  t.eq(started, nil)
  press("return")
  t.ok(started and started.daily, "daily run started")
  t.eq(Save.run(), nil)
  teardown()
end

function T.moving_the_selection_cancels_the_confirmation(t)
  setup(validRun())
  select("LAUNCH")
  press("return")
  t.eq(Menu.armed, "LAUNCH")
  press("down")
  t.eq(Menu.armed, nil, "navigating away disarms")
  press("up")
  press("return")
  t.eq(started, nil, "back on LAUNCH it must be confirmed again")
  t.ok(Save.run())
  teardown()
end

function T.pressing_a_different_row_does_not_inherit_the_confirmation(t)
  setup(validRun())
  select("LAUNCH")
  press("return") -- arms LAUNCH
  select("DAILY RUN")
  press("return") -- must arm DAILY, not start it
  t.eq(started, nil)
  t.eq(Menu.armed, "DAILY RUN")
  t.ok(Save.run())
  teardown()
end

function T.opening_hangar_cancels_the_confirmation(t)
  setup(validRun())
  select("LAUNCH")
  press("return")
  select("HANGAR")
  press("return")
  t.eq(Menu.armed, nil)
  t.ok(Save.run(), "visiting the hangar never touches the save")
  teardown()
end

function T.the_armed_row_says_what_a_second_press_does(t)
  setup(validRun())
  select("LAUNCH")
  t.eq(Menu.label(Menu, indexOf("LAUNCH")), "LAUNCH")
  press("return")
  t.eq(Menu.label(Menu, indexOf("LAUNCH")), "ABANDON SAVE? TAP AGAIN")
  t.eq(Menu.label(Menu, indexOf("CONTINUE")), "CONTINUE")
  teardown()
end

return T
