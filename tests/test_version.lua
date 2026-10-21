-- tests/test_version.lua — the LÖVE version lives in one file (LOVE_VERSION) and
-- conf.lua declares exactly that, so LÖVE never shows its "made for another version"
-- dialog. Also covers src/compat.lua, the one place LÖVE 11 / 12 differences live.
local Compat = require("src.compat")

local T = {}

-- plain file read that works under `lua tests/run.lua` and under `lovec . --test`
local function readFile(path)
  local f = io.open(path, "rb")
  if f then
    local s = f:read("*a")
    f:close()
    return s
  end
  if love and love.filesystem and love.filesystem.read then
    return (love.filesystem.read(path))
  end
end

-- ------------------------------------------------------------- version file

function T.parse_reads_key_value_lines(t)
  local v = Compat.parseVersionFile("love=12.0\nlove_commit=abc123\n")
  t.eq(v.love, "12.0")
  t.eq(v.love_commit, "abc123")
end

function T.parse_skips_comments_blank_lines_and_whitespace(t)
  local v = Compat.parseVersionFile("# pinned\r\n\r\n  love = 12.0  \r\nlove_android_commit=\r\n")
  t.eq(v.love, "12.0")
  t.eq(v.love_android_commit, "", "an empty value is kept as an empty string")
  t.eq(v["# pinned"], nil)
end

function T.the_version_file_pins_a_love_version(t)
  local v = Compat.parseVersionFile(readFile("LOVE_VERSION") or "")
  t.ok(v.love and v.love:match("^%d+%.%d+$"), "LOVE_VERSION needs love=MAJOR.MINOR")
  t.ok(v.love_commit and v.love_commit:match("^%x+$") and #v.love_commit == 40,
    "LOVE_VERSION needs the full 40-character love_commit")
end

-- conf.lua is run in a sandbox: its love.conf must not replace the live one, and
-- love.filesystem.read is served from disk the way LÖVE serves it from the game folder.
local function runConf(readFn, os)
  local chunk = assert(loadfile("conf.lua"))
  local stubLove = { filesystem = { read = readFn }, _os = os }
  setfenv(chunk, setmetatable({ love = stubLove }, { __index = _G }))
  chunk()
  local t = { window = {}, modules = {} }
  stubLove.conf(t)
  return t
end

function T.conf_declares_the_pinned_love_version(t)
  local v = Compat.parseVersionFile(readFile("LOVE_VERSION") or "")
  local conf = runConf(readFile)
  t.eq(conf.version, v.love, "conf.lua t.version must equal LOVE_VERSION")
end

function T.conf_leaves_the_version_unset_when_the_file_cannot_be_read(t)
  -- unset means LÖVE assumes its own version: no dialog, and the game still starts
  local conf = runConf(function() return nil end)
  t.eq(conf.version, nil)
  t.eq(conf.identity, "space-z", "the rest of the config is unaffected")
end

-- LÖVE 12 draws through Vulkan by default. On the Windows desktop that paced frames
-- unevenly (about 7 ms then 26 ms, worst frame 64 ms, at an average of 75 fps) where OpenGL
-- holds a steady 13.3 ms (docs/enemy-state-save/love12-findings.md), so Windows asks for
-- OpenGL. Other platforms keep LÖVE's own choice: the Android phone check was fine as is.
-- The list is the set LÖVE may pick from, not an order: { "opengl", "vulkan" } still picks
-- Vulkan (tried against LÖVE 12), so OpenGL has to be the only entry. The field is
-- t.graphics.renderers: LÖVE 12 prints a warning at every launch for the old t.renderers.
function T.conf_allows_only_opengl_on_windows(t)
  local conf = runConf(readFile, "Windows")
  local list = conf.graphics and conf.graphics.renderers
  t.ok(type(list) == "table", "t.graphics.renderers must be set")
  t.eq(#(list or {}), 1, "OpenGL alone: any second entry lets LÖVE choose Vulkan again")
  t.eq((list or {})[1], "opengl")
  t.eq(conf.renderers, nil, "not the deprecated t.renderers")
end

function T.conf_leaves_the_renderer_to_love_everywhere_else(t)
  for _, os in ipairs({ "Android", "OS X", "Linux" }) do
    local conf = runConf(readFile, os)
    t.eq(conf.graphics and conf.graphics.renderers, nil, os)
    t.eq(conf.renderers, nil, os)
  end
  local unknown = runConf(readFile, nil)
  t.eq(unknown.graphics and unknown.graphics.renderers, nil, "a runtime that does not say")
end

-- ------------------------------------------------------------------- compat

function T.readback_uses_readbackTexture_when_the_engine_has_it(t)
  local image = {}
  local calledWith
  local lg = { readbackTexture = function(tex) calledWith = tex; return image end }
  local canvas = { newImageData = function() error("deprecated path used") end }
  t.eq(Compat.readbackImageData(canvas, lg), image)
  t.eq(calledWith, canvas)
end

-- ------------------------------------------------- one source of truth, no leftovers
-- LOVE_VERSION is the only place the LÖVE version lives. A file that still says "LÖVE 11.5" is
-- a second copy that will quietly rot (conf.lua's own declaration is read from LOVE_VERSION;
-- the scripts and docs point at it). The browser build is the one documented exception: it
-- runs an 11.x runtime, so the files and the doc section that belong to it are not scanned.

local SCANNED = {
  "README.md", "conf.lua", "main.lua",
  "docs/BUILD.md", "docs/ARCHITECTURE.md", "docs/PLAN.md",
  ".github/workflows/build.yml",
  "build/build-windows.ps1", "build/build-android.ps1", "build/get-love.ps1", "build/love-version.ps1",
  "build/mirror-love.ps1",
}
local OLD_VERSION = { "11%.5", "11%.x", "LÖVE 11", "LOVE 11", "love%-11" }

-- the text of a doc without its "## Web" section (the exception)
local function withoutTheWebSection(text)
  local first = text:find("\n## Web", 1, true)
  if not first then return text end
  local nextSection = text:find("\n## ", first + 1, true)
  return text:sub(1, first) .. (nextSection and text:sub(nextSection) or "")
end

function T.no_scanned_file_names_an_old_love_version(t)
  for _, path in ipairs(SCANNED) do
    local text = readFile(path)
    t.ok(text, path .. " should exist")
    text = text:gsub("\r\n", "\n")
    if path == "docs/BUILD.md" then text = withoutTheWebSection(text) end
    for _, pattern in ipairs(OLD_VERSION) do
      local at = text:find(pattern)
      if at then
        local line = select(2, text:sub(1, at):gsub("\n", "\n")) + 1
        t.ok(false, path .. ":" .. line .. " still names an old LÖVE version (" .. pattern:gsub("%%", "") ..
          "); say what LOVE_VERSION says, or point at it")
      end
    end
  end
end

-- Moving to a newer LÖVE must be a documented routine, not a rewrite.
function T.the_upgrade_procedure_is_documented(t)
  local docs = (readFile("docs/BUILD.md") or ""):gsub("\r\n", "\n")
  local first = docs:find("\n## Moving to a newer LÖVE", 1, true)
  t.ok(first, "docs/BUILD.md needs a 'Moving to a newer LÖVE' section (LOVE_VERSION points there)")
  local nextSection = docs:find("\n## ", first + 1, true)
  local section = docs:sub(first, nextSection or #docs)
  for _, needle in ipairs({ "LOVE_VERSION", "love_commit", "love_android_commit", "get-love.ps1",
      "lua tests/run.lua", "--smoke", "web_love" }) do
    t.ok(section:find(needle, 1, true), "the upgrade section should mention " .. needle)
  end
end

-- the architecture contract must name the modules this work added
function T.the_architecture_doc_names_the_modules_it_describes(t)
  local docs = (readFile("docs/ARCHITECTURE.md") or ""):gsub("\r\n", "\n")
  for _, name in ipairs({ "runsave_entities.lua", "compat.lua", "LOVE_VERSION", "dropSavedRun" }) do
    t.ok(docs:find(name, 1, true), "docs/ARCHITECTURE.md should describe " .. name)
  end
  t.ok(not docs:find("Not saved: enemies", 1, true), "the old 'enemies are not saved' description is gone")
  t.ok(not docs:find("rewound to `zoneTime = zone.duration`", 1, true), "and so is the boss rewind")
end

function T.readback_falls_back_to_newImageData_on_older_engines(t)
  local image = {}
  local canvas = { newImageData = function(self) return image end }
  t.eq(Compat.readbackImageData(canvas, {}), image)
end

return T
