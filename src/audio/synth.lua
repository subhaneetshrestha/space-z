-- src/audio/synth.lua — tiny chiptune DSP: renders retro SFX into SoundData.
-- sfxr-style: one or more layers of square/saw/tri/sine/pitched-noise with
-- exponential frequency sweeps, arpeggios, vibrato and simple envelopes.
-- 22050 Hz mono 16-bit — authentically crunchy and cheap to generate.
local M = {}

local sin, floor, abs, min = math.sin, math.floor, math.abs, math.min
local TWO_PI = math.pi * 2

M.RATE = 22050

-- Deterministic noise for reproducible sounds (seeded per layer).
local function noiseGen(seed)
  local s = seed
  return function()
    s = (s * 48271) % 2147483647
    return ((s - 1) / 2147483646) * 2 - 1
  end
end

-- layer spec:
-- { wave="square"|"saw"|"tri"|"sine"|"noise", dur, f0, f1, vol=1, duty=0.5,
--   attack=0.004, curve=1 (release exponent), vibHz, vibDepth,
--   arp={steps={semitones...}, rate=hz}, delay=0 (start offset s) }
local function renderLayer(buf, n, rate, L)
  local dur = L.dur
  local f0 = L.f0 or 440
  local f1 = L.f1 or f0
  local ratio = f1 / f0
  local vol = L.vol or 1
  local duty = L.duty or 0.5
  local attack = L.attack or 0.004
  local curve = L.curve or 1
  local wave = L.wave or "square"
  local arp = L.arp
  local start = floor((L.delay or 0) * rate)
  local count = min(floor(dur * rate), n - start)
  local noise = noiseGen(L.seed or 12345)
  local nv = noise()
  local phase = 0

  for i = 0, count - 1 do
    local t = i / rate
    local k = t / dur
    local f = f0 * ratio ^ k
    if arp then
      local step = arp.steps[1 + floor(t * arp.rate) % #arp.steps]
      f = f * 2 ^ (step / 12)
    end
    if L.vibHz then
      f = f * (1 + (L.vibDepth or 0.01) * sin(TWO_PI * L.vibHz * t))
    end

    phase = phase + f / rate
    if phase >= 1 then
      phase = phase - floor(phase)
      nv = noise()
    end

    local v
    if wave == "square" then
      v = phase < duty and 1 or -1
    elseif wave == "saw" then
      v = 2 * phase - 1
    elseif wave == "tri" then
      v = 4 * abs(phase - 0.5) - 1
    elseif wave == "sine" then
      v = sin(TWO_PI * phase)
    else -- pitched noise: value held for one wave period (retro crunch)
      v = nv
    end

    local env = min(t / attack, 1) * (1 - k) ^ curve
    local idx = start + i
    buf[idx] = (buf[idx] or 0) + v * env * vol
  end
end

-- spec: a single layer table, or { layers = {layer, ...} }. Returns SoundData.
function M.render(spec)
  local layers = spec.layers or { spec }
  local rate = M.RATE
  local total = 0
  for i = 1, #layers do
    local L = layers[i]
    local dur = (L.delay or 0) + L.dur
    if dur > total then total = dur end
  end
  local n = floor(total * rate)
  local buf = {}
  for i = 1, #layers do
    renderLayer(buf, n, rate, layers[i])
  end
  local sd = love.sound.newSoundData(n, rate, 16, 1)
  for i = 0, n - 1 do
    local s = (buf[i] or 0) * 0.72
    if s > 1 then s = 1 elseif s < -1 then s = -1 end
    sd:setSample(i, s)
  end
  return sd
end

-- Music helpers: write a single note into a float buffer (shared by music.lua).
-- buf is 0-indexed array; returns nothing.
function M.writeNote(buf, rate, startS, dur, freq, wave, vol, duty)
  local n = floor(dur * rate)
  local phase = 0
  local noise = noiseGen(floor(freq) + 7)
  local nv = noise()
  duty = duty or 0.5
  local attack = 0.004
  for i = 0, n - 1 do
    local t = i / rate
    local k = t / dur
    phase = phase + freq / rate
    if phase >= 1 then
      phase = phase - floor(phase)
      nv = noise()
    end
    local v
    if wave == "square" then
      v = phase < duty and 1 or -1
    elseif wave == "tri" then
      v = 4 * abs(phase - 0.5) - 1
    elseif wave == "sine" then
      v = sin(TWO_PI * phase)
    elseif wave == "saw" then
      v = 2 * phase - 1
    else
      v = nv
    end
    local env = min(t / attack, 1) * (1 - k)
    local idx = startS + i
    buf[idx] = (buf[idx] or 0) + v * env * vol
  end
end

function M.midiToFreq(m)
  return 440 * 2 ^ ((m - 69) / 12)
end

return M
