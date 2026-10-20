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
local function runConf(readFn)
  local chunk = assert(loadfile("conf.lua"))
  local stubLove = { filesystem = { read = readFn } }
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

-- ------------------------------------------------------------------- compat

function T.readback_uses_readbackTexture_when_the_engine_has_it(t)
  local image = {}
  local calledWith
  local lg = { readbackTexture = function(tex) calledWith = tex; return image end }
  local canvas = { newImageData = function() error("deprecated path used") end }
  t.eq(Compat.readbackImageData(canvas, lg), image)
  t.eq(calledWith, canvas)
end

function T.readback_falls_back_to_newImageData_on_older_engines(t)
  local image = {}
  local canvas = { newImageData = function(self) return image end }
  t.eq(Compat.readbackImageData(canvas, {}), image)
end

return T
