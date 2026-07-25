-- src/audio/music.lua — procedural chiptune sequencer. Every theme is generated
-- at runtime from a seeded pattern (unique to this game, no external assets):
-- bass + lead + hats + kick/snare over a 8-bar minor-pentatonic loop.
-- Themes: "menu", "zone" (per zone index, each with its own root/tempo/color), "boss".
local Synth = require("src.audio.synth")
local RNG = require("src.core.rng")
local Save = require("src.meta.save")

local M = {}

local floor = math.floor

local RATE = Synth.RATE
local BARS = 8
local BEATS = 4 -- per bar

-- minor pentatonic; degree offsets in semitones
local SCALE = { 0, 3, 5, 7, 10 }
-- bar-root progression in semitones relative to the theme root (i, VI, III, VII feel)
local PROG = { 0, -4, 3, -2, 0, -4, 5, 7 }

-- per-zone flavor: root MIDI note, tempo, lead wave, busyness
local ZONE_THEMES = {
  { root = 45, tempo = 112, wave = "square", busy = 0.55 }, -- LEO
  { root = 43, tempo = 116, wave = "tri",    busy = 0.50 }, -- Moon (colder)
  { root = 41, tempo = 122, wave = "square", busy = 0.60 }, -- Mars (martial)
  { root = 46, tempo = 126, wave = "saw",    busy = 0.65 }, -- Belt (gritty)
  { root = 40, tempo = 120, wave = "square", busy = 0.60 }, -- Jupiter (heavy)
  { root = 48, tempo = 128, wave = "tri",    busy = 0.65 }, -- Saturn (glassy)
  { root = 38, tempo = 134, wave = "saw",    busy = 0.75 }, -- Void (menacing)
}
local MENU_THEME = { root = 45, tempo = 84, wave = "tri", busy = 0.35 }
local BOSS_THEME = { root = 39, tempo = 150, wave = "square", busy = 0.85 }

local cache = {}    -- key -> Source
local current = nil -- currently playing Source
local currentKey = nil

local function degreeToSemis(deg)
  -- deg may exceed the scale: wrap into octaves
  local oct = floor((deg - 1) / #SCALE)
  local idx = (deg - 1) % #SCALE + 1
  return SCALE[idx] + oct * 12
end

local function generate(theme, seed)
  local rng = RNG.new(seed)
  local spb = 60 / theme.tempo          -- seconds per beat
  local eighth = spb / 2
  local total = BARS * BEATS * spb
  local n = floor(total * RATE)
  local buf = {}
  local write = Synth.writeNote
  local midi = Synth.midiToFreq

  local slots = BARS * BEATS * 2        -- eighth-note grid

  -- bass: root of the bar on every 8th, octave hop on the off-beats sometimes
  for s = 0, slots - 1 do
    local bar = floor(s / (BEATS * 2)) % #PROG + 1
    local root = theme.root - 12 + PROG[bar]
    local note = root
    if s % 2 == 1 and rng:chance(0.3) then note = root + 12 end
    write(buf, RATE, floor(s * eighth * RATE), eighth * 0.85,
      midi(note), "square", 0.16, 0.5)
  end

  -- lead: seeded random walk over two octaves of the scale; rests keep it airy
  local deg = 6
  local s = 0
  while s < slots do
    local bar = floor(s / (BEATS * 2)) % #PROG + 1
    if rng:chance(theme.busy) then
      deg = deg + rng:random(-2, 2)
      if deg < 1 then deg = 1 elseif deg > 11 then deg = 11 end
      local len = rng:chance(0.3) and 2 or 1
      local note = theme.root + 12 + PROG[bar] + degreeToSemis(deg)
      write(buf, RATE, floor(s * eighth * RATE), eighth * len * 0.9,
        midi(note), theme.wave, 0.13, 0.4)
      s = s + len
    else
      s = s + 1
    end
  end

  -- hats on every 8th (accented off-beats), kick on 1/3, snare on 2/4
  for s = 0, slots - 1 do
    local startS = floor(s * eighth * RATE)
    write(buf, RATE, startS, 0.025, 6000, "noise",
      s % 2 == 1 and 0.055 or 0.035)
    local beatInBar = floor(s / 2) % BEATS
    if s % 2 == 0 then
      if beatInBar == 0 or beatInBar == 2 then
        write(buf, RATE, startS, 0.1, 95, "sine", 0.30)
      else
        write(buf, RATE, startS, 0.07, 1800, "noise", 0.14)
      end
    end
  end

  local sd = love.sound.newSoundData(n, RATE, 16, 1)
  for i = 0, n - 1 do
    local v = (buf[i] or 0)
    if v > 1 then v = 1 elseif v < -1 then v = -1 end
    sd:setSample(i, v)
  end
  local src = love.audio.newSource(sd, "static")
  src:setLooping(true)
  src:setVolume(0.55)
  return src
end

local function themeFor(key, zoneIndex)
  if key == "menu" then return MENU_THEME, 1000 end
  if key == "boss" then return BOSS_THEME, 2000 + (zoneIndex or 1) end
  local i = ((zoneIndex or 1) - 1) % #ZONE_THEMES + 1
  return ZONE_THEMES[i], 3000 + i
end

local function enabled()
  return Save.data().settings.sound ~= false
end

-- Music.play("menu") / Music.play("zone", zoneIndex) / Music.play("boss", zoneIndex)
function M.play(key, zoneIndex)
  local cacheKey = key .. (key == "zone" and ("_" .. (zoneIndex or 1)) or "")
  if currentKey == cacheKey and current and current:isPlaying() then return end
  M.stop()
  if not enabled() then
    currentKey = cacheKey -- remember intent so a toggle can resume
    return
  end
  local src = cache[cacheKey]
  if not src then
    local theme, seed = themeFor(key, zoneIndex)
    src = generate(theme, seed)
    cache[cacheKey] = src
  end
  current = src
  currentKey = cacheKey
  src:play()
end

function M.stop()
  if current then
    current:stop()
    current = nil
  end
end

-- called when the sound setting flips
function M.refresh()
  if not enabled() then
    if current then current:stop() end
    current = nil
  elseif currentKey and not current then
    local key = currentKey
    currentKey = nil
    local zone = tonumber(key:match("^zone_(%d+)$"))
    if zone then
      M.play("zone", zone)
    else
      M.play(key)
    end
  end
end

return M
