-- tests/test_music.lua — the boss theme can be built in small time slices
-- without changing what it sounds like. Runs headless: a tiny stand-in for
-- love.sound / love.audio is installed for each test and removed afterwards.
local T = {}

-- Loads a fresh copy of the music module against a stubbed love + save.
-- Returns the module and a record of what the stub saw.
local function freshMusic()
  local seen = { sources = {}, samplesWritten = 0 }
  local savedLove, savedSave = _G.love, package.loaded["src.meta.save"]
  local savedMusic = package.loaded["src.audio.music"]
  _G.love = {
    sound = {
      newSoundData = function(n)
        local sd = { n = n, samples = {} }
        function sd:setSample(i, v)
          self.samples[i] = v
          seen.samplesWritten = seen.samplesWritten + 1
        end
        return sd
      end,
    },
    audio = {
      newSource = function(sd)
        local src = { sd = sd, playing = false, plays = 0 }
        function src:setLooping() end
        function src:setVolume() end
        function src:play() self.playing = true; self.plays = self.plays + 1 end
        function src:stop() self.playing = false end
        function src:isPlaying() return self.playing end
        seen.sources[#seen.sources + 1] = src
        return src
      end,
    },
  }
  package.loaded["src.meta.save"] = { data = function() return { settings = { sound = true } } end }
  package.loaded["src.audio.music"] = nil
  local Music = require("src.audio.music")
  local function restore()
    _G.love, package.loaded["src.meta.save"] = savedLove, savedSave
    package.loaded["src.audio.music"] = savedMusic
  end
  return Music, seen, restore
end

local function sameSamples(a, b)
  if a.n ~= b.n then return false, "lengths differ: " .. a.n .. " vs " .. b.n end
  for i = 0, a.n - 1 do
    if a.samples[i] ~= b.samples[i] then
      return false, "first difference at sample " .. i
    end
  end
  return true
end

function T.prewarm_in_slices_matches_one_shot_generation(t)
  local Music, seen, restore = freshMusic()
  local ok, err = pcall(function()
    -- one-shot: no prewarm, play builds everything inside the call
    Music.play("boss", 1)
    local oneShot = seen.sources[1]
    t.ok(oneShot ~= nil, "one-shot play created a source")

    -- sliced: a fresh module, built a sliver at a time
    local Music2, seen2, restore2 = freshMusic()
    local ok2, err2 = pcall(function()
      Music2.prewarm("boss", 1)
      local slices = 0
      while Music2.pump(0) do slices = slices + 1 end
      t.ok(slices > 10, "pump(0) should need many slices, got " .. slices)
      Music2.play("boss", 1)
      local sliced = seen2.sources[1]
      t.ok(sliced ~= nil, "sliced build created a source")
      local same, why = sameSamples(oneShot.sd, sliced.sd)
      t.ok(same, "sliced theme differs from one-shot: " .. tostring(why))
    end)
    restore2()
    if not ok2 then error(err2, 0) end
  end)
  restore()
  if not ok then error(err, 0) end
end

function T.play_after_finished_prewarm_does_no_synthesis(t)
  local Music, seen, restore = freshMusic()
  local ok, err = pcall(function()
    Music.prewarm("boss", 1)
    while Music.pump(0.05) do end
    local before = seen.samplesWritten
    Music.play("boss", 1)
    t.eq(seen.samplesWritten, before, "play wrote samples after a finished prewarm")
    t.eq(#seen.sources, 1, "play must reuse the prewarmed source")
    t.ok(seen.sources[1].playing, "boss theme is playing")
  end)
  restore()
  if not ok then error(err, 0) end
end

function T.play_finishes_a_half_built_prewarm(t)
  local Music, seen, restore = freshMusic()
  local ok, err = pcall(function()
    Music.prewarm("boss", 1)
    for _ = 1, 3 do Music.pump(0) end
    t.eq(#seen.sources, 0, "source must not exist until the build completes")
    Music.play("boss", 1)
    t.eq(#seen.sources, 1, "play completed the build")
    t.ok(seen.sources[1].playing, "boss theme is playing")
    t.eq(Music.pump(0), false, "nothing left to pump afterwards")
  end)
  restore()
  if not ok then error(err, 0) end
end

function T.pump_without_a_job_is_a_no_op(t)
  local Music, _, restore = freshMusic()
  local ok, err = pcall(function()
    t.eq(Music.pump(0.002), false, "pump with nothing pending")
  end)
  restore()
  if not ok then error(err, 0) end
end

function T.menu_and_zone_themes_still_play(t)
  local Music, seen, restore = freshMusic()
  local ok, err = pcall(function()
    Music.play("menu")
    t.ok(seen.sources[1] and seen.sources[1].playing, "menu theme plays")
    Music.play("zone", 2)
    t.eq(#seen.sources, 2, "zone theme is its own source")
    t.ok(seen.sources[2].playing and not seen.sources[1].playing, "zone replaced menu")
  end)
  restore()
  if not ok then error(err, 0) end
end

return T
