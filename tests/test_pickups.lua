-- tests/test_pickups.lua — XP drop/merge tiers, magnet-collect leveling curve.
local Pickups = require("src.systems.pickups")
local Pool = require("src.core.pool")
local Events = require("src.core.events")

local T = {}

local function fakeWorld()
  return {
    events = Events.new(),
    player = { x = 240, y = 600, dead = false },
    pickups = {},
    pools = { pickups = Pool.new() },
    stats = { magnetRadius = 70, xpMult = 1 },
    xp = 0, xpNext = Pickups.xpForLevel(1), level = 1, pendingLevelUps = 0,
  }
end

function T.level_curve_formula(t)
  t.eq(Pickups.xpForLevel(1), 8, "level 1 needs 8")
  for level = 1, 30 do
    t.eq(Pickups.xpForLevel(level), math.floor(8 + 6 * (level - 1) ^ 1.35),
      "curve at level " .. level)
  end
end

function T.drop_tier_sprites(t)
  local w = fakeWorld()
  local p1 = Pickups.dropXp(w, 100, 100, 1)
  t.eq(p1.sprite, "pickup_xp1", "tier 1")
  local p2 = Pickups.dropXp(w, 200, 200, 5)
  t.eq(p2.sprite, "pickup_xp2", "tier 2")
  local p3 = Pickups.dropXp(w, 300, 300, 25)
  t.eq(p3.sprite, "pickup_xp3", "tier 3")
end

function T.drop_merges_nearby(t)
  local w = fakeWorld()
  local a = Pickups.dropXp(w, 100, 100, 3)
  local b = Pickups.dropXp(w, 110, 100, 3) -- within 24px
  t.eq(a, b, "merged into the existing gem")
  t.eq(#w.pickups, 1, "no second pickup spawned")
  t.eq(a.value, 6, "values merged")
  t.eq(a.sprite, "pickup_xp2", "tier upgraded on merge")
end

function T.no_merge_when_far(t)
  local w = fakeWorld()
  Pickups.dropXp(w, 100, 100, 1)
  Pickups.dropXp(w, 200, 100, 1)
  t.eq(#w.pickups, 2, "distant gems stay separate")
end

function T.collect_grants_xp_with_mult(t)
  local w = fakeWorld()
  w.stats.xpMult = 1.5
  Pickups.dropXp(w, w.player.x, w.player.y, 4) -- on top of the player
  Pickups.update(w, 1 / 60)
  t.near(w.xp, 6, 1e-9, "4 xp * 1.5 mult")
  t.eq(w.pickups[1].dead, true, "pickup consumed")
end

function T.level_up_and_multi_level(t)
  local w = fakeWorld()
  local levelsSeen = {}
  w.events:on("level_up", function(lv) levelsSeen[#levelsSeen + 1] = lv end)
  -- xpNext(1)=8, xpNext(2)=14: one 25-value gem should grant 2 levels
  Pickups.dropXp(w, w.player.x, w.player.y, 25)
  Pickups.update(w, 1 / 60)
  t.eq(w.level, 3, "two levels from one gem")
  t.eq(w.pendingLevelUps, 2, "both drafts queued")
  t.eq(levelsSeen[1], 2)
  t.eq(levelsSeen[2], 3)
  t.near(w.xp, 25 - 8 - 14, 1e-9, "leftover xp carried")
end

function T.magnet_pull(t)
  local w = fakeWorld()
  local p = Pickups.dropXp(w, w.player.x + 60, w.player.y, 1) -- inside 70px magnet
  Pickups.update(w, 1 / 60)
  t.eq(p.magnet, true, "magnetized inside range")
  local vx0 = p.vx
  t.ok(vx0 < 0, "accelerates toward the player")
  local far = Pickups.dropXp(w, w.player.x + 300, w.player.y, 1)
  Pickups.update(w, 1 / 60)
  t.eq(far.magnet, false, "far gem not magnetized")
end

return T
