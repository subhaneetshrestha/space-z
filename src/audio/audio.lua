-- src/audio/audio.lua — retro SFX registry + playback facade.
-- All sounds are synthesized at load (src/audio/synth.lua); nothing external.
-- Honors Save.data().settings.sound. Per-sound source pools + rate limiting.
local Synth = require("src.audio.synth")
local Save = require("src.meta.save")

local M = {}

-- name -> spec (single layer or {layers={...}})
local DEFS = {
  shoot = { wave = "square", dur = 0.09, f0 = 840, f1 = 340, duty = 0.28, vol = 0.30, curve = 1.4 },
  missile = { layers = {
    { wave = "noise", dur = 0.30, f0 = 900, f1 = 200, vol = 0.30, curve = 1.5 },
    { wave = "square", dur = 0.28, f0 = 300, f1 = 90, duty = 0.4, vol = 0.22 },
  } },
  flak = { wave = "noise", dur = 0.16, f0 = 1400, f1 = 300, vol = 0.40, curve = 1.3 },
  zap = { wave = "square", dur = 0.14, f0 = 1500, f1 = 240, duty = 0.2, vol = 0.30,
          arp = { steps = { 0, -5, -10 }, rate = 45 } },
  hit = { wave = "square", dur = 0.045, f0 = 260, f1 = 160, duty = 0.35, vol = 0.20 },
  boom_s = { layers = {
    { wave = "noise", dur = 0.35, f0 = 700, f1 = 70, vol = 0.55, curve = 2 },
    { wave = "sine", dur = 0.22, f0 = 160, f1 = 55, vol = 0.4, curve = 2 },
  } },
  boom_b = { layers = {
    { wave = "noise", dur = 0.85, f0 = 500, f1 = 45, vol = 0.8, curve = 2 },
    { wave = "sine", dur = 0.6, f0 = 130, f1 = 38, vol = 0.55, curve = 2 },
    { wave = "noise", dur = 0.5, f0 = 2200, f1 = 400, vol = 0.2, curve = 3, delay = 0.02 },
  } },
  pickup = { wave = "square", dur = 0.07, f0 = 700, f1 = 1050, duty = 0.5, vol = 0.22, curve = 0.7 },
  levelup = { wave = "square", dur = 0.5, f0 = 523, duty = 0.4, vol = 0.4,
              arp = { steps = { 0, 4, 7, 12 }, rate = 18 }, curve = 0.6 },
  confirm = { wave = "square", dur = 0.11, f0 = 880, f1 = 1245, duty = 0.5, vol = 0.32 },
  hurt = { layers = {
    { wave = "noise", dur = 0.2, f0 = 1000, f1 = 250, vol = 0.45, curve = 1.5 },
    { wave = "square", dur = 0.18, f0 = 160, f1 = 70, duty = 0.5, vol = 0.35 },
  } },
  death = { layers = {
    { wave = "noise", dur = 1.0, f0 = 600, f1 = 45, vol = 0.6, curve = 1.6 },
    { wave = "saw", dur = 1.0, f0 = 420, f1 = 50, vol = 0.4, curve = 1.2 },
  } },
  alarm = { wave = "square", dur = 1.1, f0 = 560, duty = 0.45, vol = 0.35,
            arp = { steps = { 0, 6 }, rate = 5 }, curve = 0.4 },
  warp = { wave = "square", dur = 0.9, f0 = 220, f1 = 1500, duty = 0.4, vol = 0.35,
           vibHz = 22, vibDepth = 0.02, curve = 0.8 },
  jingle_win = { wave = "square", dur = 1.2, f0 = 523, duty = 0.4, vol = 0.4,
                 arp = { steps = { 0, 4, 7, 12, 16, 19 }, rate = 9 }, curve = 0.5 },
  jingle_lose = { wave = "saw", dur = 1.3, f0 = 340, f1 = 65, vol = 0.4,
                  arp = { steps = { 0, -1, -3, -5 }, rate = 4 }, curve = 0.9 },
  tick = { wave = "square", dur = 0.03, f0 = 1250, duty = 0.5, vol = 0.18 },
  pulse = { layers = {
    { wave = "sine", dur = 0.6, f0 = 70, f1 = 40, vol = 0.6, curve = 1 },
    { wave = "square", dur = 0.5, f0 = 300, f1 = 90, duty = 0.3, vol = 0.2 },
  } },
}

local POOL_SIZE = 4
local MIN_INTERVAL = 0.035 -- per-sound anti-stacking window (seconds)

local sounds = {}   -- name -> { sources = {Source...}, next = 1, lastT = -1 }
local loaded = false

function M.load()
  if loaded then return end
  loaded = true
  for name, spec in pairs(DEFS) do
    local data = Synth.render(spec)
    local pool = { sources = {}, next = 1, lastT = -1 }
    for i = 1, POOL_SIZE do
      pool.sources[i] = love.audio.newSource(data, "static")
    end
    sounds[name] = pool
  end
end

function M.enabled()
  local s = Save.data().settings
  return s.sound ~= false
end

-- opts: { pitch = n, vol = n }
function M.play(name, opts)
  if not loaded or not M.enabled() then return end
  local pool = sounds[name]
  if not pool then return end
  local now = love.timer.getTime()
  if now - pool.lastT < MIN_INTERVAL then return end
  pool.lastT = now
  local src = pool.sources[pool.next]
  pool.next = pool.next % POOL_SIZE + 1
  src:stop()
  src:setPitch((opts and opts.pitch) or 1)
  src:setVolume((opts and opts.vol) or 1)
  src:play()
end

return M
