-- src/render/sprites.lua — procedural neon-vector sprite atlas, built once at load.
-- Every sprite is stroked 3 times (wide faint / medium / near-white core) so the
-- glow is baked into the texture; runtime rendering is plain batched quads.
local Compat = require("src.compat")

local M = {}

local lg = love and love.graphics

local PAD = 4        -- padding between atlas cells (>= 4 per contract)
local ATLAS_W = 1024

local sprites = {}   -- name -> { quad, w, h, ox, oy, info }
local atlasImage     -- straight-alpha atlas texture (Compat.atlasTexture)
local atlasH = 0

-- palette (neon hues)
local CYAN       = {0.20, 1.00, 1.00}
local CYAN_PALE  = {0.60, 1.00, 1.00}
local ORANGE     = {1.00, 0.55, 0.15}
local ORANGE_RED = {1.00, 0.40, 0.15}
local RED_ORANGE = {1.00, 0.32, 0.10}
local MAGENTA    = {1.00, 0.25, 0.90}
local RED_MAG    = {1.00, 0.20, 0.45}
local RED        = {1.00, 0.22, 0.18}
local AMBER      = {1.00, 0.75, 0.20}
local FLAME      = {1.00, 0.55, 0.15}
local YELLOW     = {1.00, 0.85, 0.25}
local GREEN      = {0.30, 1.00, 0.40}
local TEAL       = {0.20, 1.00, 0.80}
local WARM       = {1.00, 0.85, 0.60}
local HOT_RED    = {1.00, 0.28, 0.12}
local WHITE      = {1.00, 1.00, 1.00}

-- 70% white mixed into the hue: the bright core stroke color
local function coreOf(c)
  local r, g, b = c[1], c[2], c[3]
  return r + (1 - r) * 0.7, g + (1 - g) * 0.7, b + (1 - b) * 0.7
end

local function neonPoly(c, pts)
  lg.setColor(c[1], c[2], c[3], 0.12); lg.setLineWidth(7);   lg.polygon("line", pts)
  lg.setColor(c[1], c[2], c[3], 0.30); lg.setLineWidth(3.5); lg.polygon("line", pts)
  local r, g, b = coreOf(c)
  lg.setColor(r, g, b, 0.95); lg.setLineWidth(1.7); lg.polygon("line", pts)
end

-- tighter widths for tiny sprites (gems, drones) so glow doesn't swallow the shape
local function neonPolyS(c, pts)
  lg.setColor(c[1], c[2], c[3], 0.14); lg.setLineWidth(4.5); lg.polygon("line", pts)
  lg.setColor(c[1], c[2], c[3], 0.34); lg.setLineWidth(2.2); lg.polygon("line", pts)
  local r, g, b = coreOf(c)
  lg.setColor(r, g, b, 0.98); lg.setLineWidth(1.2); lg.polygon("line", pts)
end

local function neonLine(c, pts)
  lg.setColor(c[1], c[2], c[3], 0.12); lg.setLineWidth(7);   lg.line(pts)
  lg.setColor(c[1], c[2], c[3], 0.30); lg.setLineWidth(3.5); lg.line(pts)
  local r, g, b = coreOf(c)
  lg.setColor(r, g, b, 0.95); lg.setLineWidth(1.7); lg.line(pts)
end

local function neonCircle(c, x, y, rad)
  lg.setColor(c[1], c[2], c[3], 0.12); lg.setLineWidth(7);   lg.circle("line", x, y, rad)
  lg.setColor(c[1], c[2], c[3], 0.30); lg.setLineWidth(3.5); lg.circle("line", x, y, rad)
  local r, g, b = coreOf(c)
  lg.setColor(r, g, b, 0.95); lg.setLineWidth(1.7); lg.circle("line", x, y, rad)
end

local function neonCircleS(c, x, y, rad)
  lg.setColor(c[1], c[2], c[3], 0.14); lg.setLineWidth(4);   lg.circle("line", x, y, rad)
  lg.setColor(c[1], c[2], c[3], 0.34); lg.setLineWidth(2);   lg.circle("line", x, y, rad)
  local r, g, b = coreOf(c)
  lg.setColor(r, g, b, 0.98); lg.setLineWidth(1.2); lg.circle("line", x, y, rad)
end

-- single thin accent stroke in the hue (panel lines, cracks, struts)
local function detail(c, alpha, width, pts)
  lg.setColor(c[1], c[2], c[3], alpha)
  lg.setLineWidth(width)
  lg.line(pts)
end

-- filled radial glow: nested discs, brighter near-white center
local function glowDot(c, x, y, rad, coreAlpha)
  lg.setColor(c[1], c[2], c[3], 0.10); lg.circle("fill", x, y, rad)
  lg.setColor(c[1], c[2], c[3], 0.22); lg.circle("fill", x, y, rad * 0.70)
  lg.setColor(c[1], c[2], c[3], 0.45); lg.circle("fill", x, y, rad * 0.48)
  local r, g, b = coreOf(c)
  lg.setColor(r, g, b, coreAlpha or 0.95); lg.circle("fill", x, y, rad * 0.28)
end

-- faint interior fill; triangulated because most hulls are concave
local function fillPoly(c, alpha, pts)
  lg.setColor(c[1], c[2], c[3], alpha)
  local ok, tris = pcall(love.math.triangulate, pts)
  if ok then
    for i = 1, #tris do lg.polygon("fill", tris[i]) end
  end
end

-- Cell sizes include room for the baked glow margins, so they are larger than the
-- nominal shape size. All ships/enemies point UP at rot = 0.
local defs = {
  { name = "boss_kessler_core", w = 96, h = 96, draw = function()
    local C = RED_ORANGE
    -- girder struts out to the strapped-on modules
    detail(C, 0.55, 2, {-26, 0, -34, 0})
    detail(C, 0.55, 2, {26, -6, 34, -6})
    detail(C, 0.55, 2, {14, 22, 29, 20})
    -- antennae + menacing spikes
    neonLine(C, {0, -30, 0, -43})
    detail(C, 0.7, 1.5, {10, -27, 19, -39})
    detail(C, 0.7, 1.5, {-16, -25, -25, -35})
    neonLine(C, {14, 26, 21, 39})
    neonLine(C, {-14, 26, -21, 39})
    detail(C, 0.7, 1.5, {5, 27, 8, 38})
    detail(C, 0.7, 1.5, {-5, 27, -8, 38})
    -- main core
    local core = {0,-30, 16,-24, 26,-8, 26,10, 14,26, -14,26, -26,10, -26,-8, -16,-24}
    fillPoly(C, 0.08, core)
    neonPoly(C, core)
    -- bolted-on side modules
    local ml = {-42,-8, -30,-8, -30,10, -42,10}
    local mr = {30,-14, 42,-14, 42,2, 30,2}
    fillPoly(C, 0.08, ml); neonPoly(C, ml)
    fillPoly(C, 0.08, mr); neonPoly(C, mr)
    detail(C, 0.5, 1.5, {-42, 0, -30, 0})
    detail(C, 0.5, 1.5, {36, -14, 36, 2})
    -- comms dish (top-left) and broken solar panel (bottom-right)
    neonCircleS(C, -20, -31, 6)
    detail(C, 0.7, 1.5, {-16, -27, -11, -21})
    neonPoly(C, {30,16, 42,22, 37,32, 26,25})
    -- hull cracks
    detail(C, 0.6, 1.5, {-10,-14, -2,-4, -12,8})
    detail(C, 0.6, 1.5, {8, 2, 17, 13})
    -- menacing central eye + running lights
    neonCircleS(C, 0, -4, 10)
    glowDot(HOT_RED, 0, -4, 7, 1.0)
    glowDot(WARM, -20, 18, 2.4, 1.0)
    glowDot(WARM, 20, 18, 2.4, 1.0)
  end },

  { name = "glow", w = 64, h = 64, draw = function()
    -- radial gradient, white center -> transparent; radii packed toward center
    lg.setColor(1, 1, 1, 0.07)
    local steps = 24
    for i = 1, steps do
      local f = i / steps
      lg.circle("fill", 0, 0, 30 * (f ^ 1.6), 48)
    end
    lg.setColor(1, 1, 1, 0.85)
    lg.circle("fill", 0, 0, 2)
  end },

  { name = "ring", w = 60, h = 60, draw = function()
    neonCircle(WHITE, 0, 0, 24)
  end },

  { name = "enemy_sentry", w = 48, h = 46, draw = function()
    local C = ORANGE_RED
    -- panel struts
    detail(C, 0.6, 2, {-9, 0, -7, 0})
    detail(C, 0.6, 2, {7, 0, 9, 0})
    -- solar panels with grid lines
    local pl = {-20,-5, -9,-5, -9,5, -20,5}
    local pr = {9,-5, 20,-5, 20,5, 9,5}
    fillPoly(C, 0.10, pl); neonPolyS(C, pl)
    fillPoly(C, 0.10, pr); neonPolyS(C, pr)
    detail(C, 0.45, 1.2, {-16.3, -5, -16.3, 5})
    detail(C, 0.45, 1.2, {-12.6, -5, -12.6, 5})
    detail(C, 0.45, 1.2, {12.6, -5, 12.6, 5})
    detail(C, 0.45, 1.2, {16.3, -5, 16.3, 5})
    -- boxy body
    local body = {-7,-8, 7,-8, 7,8, -7,8}
    fillPoly(C, 0.08, body)
    neonPoly(C, body)
    -- dish up top, antenna below
    detail(C, 0.7, 1.5, {0, -8, 0, -11})
    neonCircleS(C, 0, -14.5, 3.5)
    detail(C, 0.7, 1.5, {0, 8, 0, 14})
    glowDot(WARM, 4, -4, 1.8, 1.0)
  end },

  { name = "ship_pathfinder", w = 40, h = 48, draw = function()
    local C = CYAN
    local hull = {0,-17, 4,-9, 6,-1, 13,9, 13,12, 5,10, 3,15,
                  -3,15, -5,10, -13,12, -13,9, -6,-1, -4,-9}
    fillPoly(C, 0.07, hull)
    -- wing creases + spine
    detail(C, 0.40, 1.5, {2, -3, 10, 9})
    detail(C, 0.40, 1.5, {-2, -3, -10, 9})
    detail(C, 0.55, 1.5, {0, -13, 0, 2})
    neonPoly(C, hull)
    -- engine nozzle (open path so it reads as a bell) + exhaust glow
    neonLine(C, {-4,18, -3,15, 3,15, 4,18})
    glowDot(CYAN_PALE, 0, 18, 3.2, 1.0)
    -- canopy
    glowDot(CYAN_PALE, 0, -7, 2.6, 1.0)
  end },

  { name = "enemy_drifter", w = 40, h = 40, draw = function()
    local C = ORANGE
    local p = {0,-14, 9,-10, 13,-2, 10,5, 12,11, 3,13, -6,12, -12,6, -13,-4, -7,-9}
    fillPoly(C, 0.08, p)
    neonPoly(C, p)
    -- cracks + a dim ember inside
    detail(C, 0.55, 1.5, {-6,-8, 2,0, -2,9})
    detail(C, 0.55, 1.5, {3, -6, 8, 2})
    glowDot(C, 1, 1, 4, 0.55)
  end },

  { name = "enemy_stinger", w = 32, h = 32, draw = function()
    local C = RED_MAG
    local p = {0,-11, 3,-4, 8,3, 3,2, 4,11, 0,6, -4,11, -3,2, -8,3, -3,-4}
    fillPoly(C, 0.10, p)
    neonPoly(C, p)
    glowDot(C, 0, -3, 2.6, 0.9)
  end },

  { name = "boss_kessler_node", w = 32, h = 32, draw = function()
    local C = RED_ORANGE
    local body = {-5,-5, 5,-5, 5,5, -5,5}
    fillPoly(C, 0.10, body)
    neonPoly(C, body)
    detail(C, 0.7, 2, {-11, 0, -5, 0})
    detail(C, 0.7, 2, {5, 0, 11, 0})
    detail(C, 0.7, 1.2, {0, -5, 0, -11})
    glowDot(HOT_RED, 0, 0, 3, 1.0)
  end },

  { name = "enemy_shard", w = 28, h = 32, draw = function()
    local C = MAGENTA
    local p = {0,-10, 4,-3, 2,10, -1,6, -4,-4}
    fillPoly(C, 0.10, p)
    neonPoly(C, p)
    detail(C, 0.6, 1.2, {0, -7, 0, 6})
  end },

  { name = "drone", w = 20, h = 20, draw = function()
    local C = YELLOW
    local p = {0,-6, 5.5,4, -5.5,4}
    fillPoly(C, 0.10, p)
    neonPolyS(C, p)
    lg.setColor(1, 1, 1, 0.95)
    lg.circle("fill", 0, 0.5, 1.5)
  end },

  { name = "bullet_missile", w = 16, h = 24, draw = function()
    local C = AMBER
    local body = {0,-7, 3,-3, 3,4, -3,4, -3,-3}
    fillPoly(C, 0.12, body)
    neonPolyS(C, body)
    detail(C, 0.8, 1.5, {3, 3, 5.5, 6.5})
    detail(C, 0.8, 1.5, {-3, 3, -5.5, 6.5})
    glowDot(FLAME, 0, 7.5, 3, 1.0)   -- exhaust tail
    lg.setColor(1, 1, 1, 0.9)
    lg.circle("fill", 0, -5.5, 1.3)
  end },

  { name = "bullet_blaster", w = 12, h = 20, draw = function()
    neonLine(CYAN, {0, -6, 0, 6})
    lg.setColor(1, 1, 1, 0.9)
    lg.circle("fill", 0, -5, 1.6)   -- hot head
  end },

  { name = "bullet_enemy", w = 16, h = 16, draw = function()
    lg.setColor(RED[1], RED[2], RED[3], 0.08)
    lg.circle("fill", 0, 0, 6.5)
    glowDot(RED, 0, 0, 4, 1.0)
  end },

  { name = "bullet_flak", w = 14, h = 14, draw = function()
    local C = CYAN
    lg.setColor(C[1], C[2], C[3], 0.5)
    lg.setLineWidth(1.2)
    lg.circle("line", 0, 0, 3.2)
    glowDot(C, 0, 0, 3.4, 1.0)
  end },

  { name = "pickup_xp3", w = 24, h = 24, draw = function()
    local C = CYAN_PALE
    local d = {0,-7, 7,0, 0,7, -7,0}
    fillPoly(C, 0.20, d)
    neonPolyS(C, d)
    detail(WHITE, 0.9, 1.2, {0,-3.2, 3.2,0, 0,3.2, -3.2,0, 0,-3.2})
  end },

  { name = "pickup_xp2", w = 20, h = 20, draw = function()
    local C = TEAL
    local d = {0,-5.5, 5.5,0, 0,5.5, -5.5,0}
    fillPoly(C, 0.18, d)
    neonPolyS(C, d)
    lg.setColor(1, 1, 1, 0.9)
    lg.circle("fill", 0, 0, 1)
  end },

  { name = "pickup_xp1", w = 16, h = 16, draw = function()
    local C = GREEN
    local d = {0,-4, 4,0, 0,4, -4,0}
    fillPoly(C, 0.18, d)
    neonPolyS(C, d)
    lg.setColor(1, 1, 1, 0.85)
    lg.circle("fill", 0, 0, 0.8)
  end },

  { name = "dot", w = 12, h = 12, draw = function()
    lg.setColor(1, 1, 1, 0.20); lg.circle("fill", 0, 0, 4.2)
    lg.setColor(1, 1, 1, 0.50); lg.circle("fill", 0, 0, 3.0)
    lg.setColor(1, 1, 1, 0.85); lg.circle("fill", 0, 0, 2.0)
    lg.setColor(1, 1, 1, 1.00); lg.circle("fill", 0, 0, 1.1)
  end },

  { name = "star", w = 8, h = 8, draw = function()
    lg.setColor(1, 1, 1, 0.18); lg.circle("fill", 0, 0, 2.7)
    lg.setColor(1, 1, 1, 0.45); lg.circle("fill", 0, 0, 1.7)
    lg.setColor(1, 1, 1, 0.95); lg.circle("fill", 0, 0, 0.9)
  end },

  -- M3 ships -------------------------------------------------------------

  { name = "ship_aegis", w = 44, h = 46, draw = function()
    local C = {0.35, 1.0, 0.75}
    -- broad wedge with a shield prow
    local hull = {0,-15, 9,-8, 15,4, 15,12, 6,14, 0,11, -6,14, -15,12, -15,4, -9,-8}
    fillPoly(C, 0.08, hull)
    neonPoly(C, hull)
    detail(C, 0.5, 1.5, {-9, 2, 9, 2})
    -- shield arc up front
    lg.setLineWidth(2)
    lg.setColor(C[1], C[2], C[3], 0.6)
    lg.arc("line", "open", 0, -8, 13, -math.pi * 0.85, -math.pi * 0.15, 24)
    glowDot(CYAN_PALE, 0, 16, 3, 1.0)
    glowDot(C, 0, -4, 2.4, 1.0)
  end },

  { name = "ship_falcon", w = 36, h = 48, draw = function()
    local C = {0.85, 0.95, 1.0}
    -- razor dart
    local hull = {0,-19, 3,-6, 10,13, 3,10, 0,16, -3,10, -10,13, -3,-6}
    fillPoly(C, 0.07, hull)
    neonPoly(C, hull)
    detail(C, 0.55, 1.4, {0, -15, 0, 8})
    glowDot(CYAN_PALE, 0, 18, 2.6, 1.0)
    glowDot(C, 0, -8, 2, 1.0)
  end },

  { name = "ship_barrage", w = 44, h = 44, draw = function()
    local C = {1.0, 0.7, 0.3}
    -- boxy gunship with missile pods
    local hull = {0,-14, 6,-8, 8,8, 4,13, -4,13, -8,8, -6,-8}
    fillPoly(C, 0.08, hull)
    neonPoly(C, hull)
    local pl = {-16,-4, -9,-4, -9,9, -16,9}
    local pr = {9,-4, 16,-4, 16,9, 9,9}
    fillPoly(C, 0.10, pl); neonPolyS(C, pl)
    fillPoly(C, 0.10, pr); neonPolyS(C, pr)
    detail(C, 0.6, 1.2, {-12.5, -4, -12.5, 9})
    detail(C, 0.6, 1.2, {12.5, -4, 12.5, 9})
    glowDot(CYAN_PALE, 0, 15, 2.8, 1.0)
    glowDot(C, 0, -5, 2, 1.0)
  end },

  { name = "ship_halo", w = 42, h = 46, draw = function()
    local C = {1.0, 0.85, 0.3}
    -- round carrier core inside a halo ring
    neonCircleS(C, 0, 0, 15)
    local hull = {0,-10, 6,-3, 5,7, -5,7, -6,-3}
    fillPoly(C, 0.10, hull)
    neonPolyS(C, hull)
    glowDot(CYAN_PALE, 0, 11, 2.4, 1.0)
    glowDot(C, 0, -2, 2.6, 1.0)
  end },

  { name = "ship_warden", w = 42, h = 46, draw = function()
    local C = {0.75, 0.45, 1.0}
    -- graviton prongs reaching forward
    local hull = {0,-8, 6,-2, 7,10, 0,14, -7,10, -6,-2}
    fillPoly(C, 0.09, hull)
    neonPoly(C, hull)
    neonLine(C, {-6, -4, -12, -17})
    neonLine(C, {6, -4, 12, -17})
    glowDot(C, -12, -17, 2, 1.0)
    glowDot(C, 12, -17, 2, 1.0)
    glowDot(CYAN_PALE, 0, 16, 2.6, 1.0)
  end },

  { name = "ship_nova", w = 34, h = 48, draw = function()
    local C = {1.0, 0.4, 0.9}
    -- narrow blade, oversized engine
    local hull = {0,-18, 4,-2, 6,12, 0,9, -6,12, -4,-2}
    fillPoly(C, 0.08, hull)
    neonPoly(C, hull)
    detail(C, 0.6, 1.3, {0, -14, 0, 6})
    glowDot(CYAN_PALE, 0, 15, 3.6, 1.0)
    glowDot(WHITE, 0, -8, 1.8, 1.0)
  end },

  { name = "ship_zephyr", w = 46, h = 42, draw = function()
    local C = {0.5, 1.0, 0.9}
    -- curved glider wings
    local hull = {0,-12, 5,-4, 17,6, 12,11, 4,8, 0,12, -4,8, -12,11, -17,6, -5,-4}
    fillPoly(C, 0.08, hull)
    neonPoly(C, hull)
    detail(C, 0.45, 1.3, {4, -1, 13, 7})
    detail(C, 0.45, 1.3, {-4, -1, -13, 7})
    glowDot(CYAN_PALE, 0, 13, 2.6, 1.0)
    glowDot(C, 0, -4, 2, 1.0)
  end },

  { name = "bullet_cryo", w = 12, h = 16, draw = function()
    local C = {0.6, 0.95, 1.0}
    local p = {0,-5, 3,0, 0,5, -3,0}
    fillPoly(C, 0.18, p)
    neonPolyS(C, p)
    lg.setColor(1, 1, 1, 0.9)
    lg.circle("fill", 0, 0, 1)
  end },

  -- M2 enemies -----------------------------------------------------------

  { name = "asteroid", w = 34, h = 34, draw = function()
    local C = { 0.85, 0.62, 0.40 }
    local p = {0,-12, 8,-9, 12,-2, 11,6, 4,12, -5,11, -11,5, -12,-5, -6,-10}
    fillPoly(C, 0.10, p)
    neonPoly(C, p)
    -- craters + cracks
    neonCircleS(C, -3, 2, 3)
    detail(C, 0.5, 1.3, {4, -6, 8, 0})
    detail(C, 0.5, 1.3, {-7, -4, -2, -7})
  end },

  { name = "meteor", w = 18, h = 30, draw = function()
    local C = { 1.0, 0.7, 0.35 }
    local p = {0,7, 4,3, 3,-3, 0,-6, -3,-3, -4,3}
    fillPoly(C, 0.14, p)
    neonPolyS(C, p)
    -- burning tail (points up: travel direction handled by rotation)
    detail(C, 0.5, 2.2, {0, -6, 0, -12})
    detail(C, 0.3, 3.2, {-1.5, -5, -2.5, -10})
    glowDot(C, 0, 5, 3, 0.9)
  end },

  { name = "pirate", w = 34, h = 32, draw = function()
    local C = { 1.0, 0.35, 0.25 }
    -- jagged raider: swept-forward blades
    local hull = {0,-12, 5,-4, 14,-8, 9,4, 4,10, -4,10, -9,4, -14,-8, -5,-4}
    fillPoly(C, 0.10, hull)
    neonPoly(C, hull)
    detail(C, 0.55, 1.4, {0, -9, 0, 6})
    glowDot({1, 0.5, 0.2}, 0, 0, 2.6, 1.0)
    glowDot({1, 0.6, 0.3}, -3.5, 8, 1.6, 0.9)
    glowDot({1, 0.6, 0.3}, 3.5, 8, 1.6, 0.9)
  end },

  { name = "ice_shard", w = 24, h = 28, draw = function()
    local C = { 0.65, 0.9, 1.0 }
    local p = {0,-10, 5,-3, 3,9, 0,5, -4,8, -5,-4}
    fillPoly(C, 0.14, p)
    neonPolyS(C, p)
    detail(WHITE, 0.6, 1.1, {-1, -7, 1, 5})
  end },

  { name = "hive_dart", w = 26, h = 30, draw = function()
    local C = { 0.85, 0.35, 1.0 }
    -- organic dart: mandible fork + swept body
    local p = {0,-11, 4,-5, 8,-8, 6,2, 0,11, -6,2, -8,-8, -4,-5}
    fillPoly(C, 0.12, p)
    neonPoly(C, p)
    glowDot({1, 0.4, 0.9}, 0, -2, 2.6, 1.0)
    detail(C, 0.5, 1.2, {0, 3, 0, 9})
  end },

  -- M2 bosses ------------------------------------------------------------

  { name = "boss_leviathan", w = 96, h = 100, draw = function()
    local C = { 0.85, 0.8, 0.7 }
    -- drill head pointing DOWN (it bores toward the player)
    local drill = {0,44, -12,26, 12,26}
    fillPoly(C, 0.12, drill); neonPoly(C, drill)
    detail(C, 0.6, 1.4, {-8, 30, 8, 30})
    detail(C, 0.6, 1.4, {-5, 36, 5, 36})
    -- segmented body plates
    for i = 0, 2 do
      local y = 18 - i * 18
      local w = 22 - i * 2
      local seg = {-w, y - 14, w, y - 14, w + 4, y - 2, -w - 4, y - 2}
      fillPoly(C, 0.08, seg); neonPoly(C, seg)
    end
    -- side grinders
    neonCircleS(C, -26, 6, 7)
    neonCircleS(C, 26, 6, 7)
    detail(C, 0.6, 1.4, {-26, 0, -26, 12})
    detail(C, 0.6, 1.4, {26, 0, 26, 12})
    -- menacing eye
    glowDot(HOT_RED, 0, -22, 6, 1.0)
    glowDot(WARM, -14, 12, 2, 1.0)
    glowDot(WARM, 14, 12, 2, 1.0)
  end },

  { name = "boss_warmachine", w = 96, h = 92, draw = function()
    local C = { 1.0, 0.42, 0.30 }
    -- fortress hull
    local hull = {-30,-26, 30,-26, 40,-6, 34,22, -34,22, -40,-6}
    fillPoly(C, 0.08, hull); neonPoly(C, hull)
    -- twin cannon pods aiming down
    local pl = {-30,22, -18,22, -18,38, -30,38}
    local pr = {18,22, 30,22, 30,38, 18,38}
    fillPoly(C, 0.10, pl); neonPoly(C, pl)
    fillPoly(C, 0.10, pr); neonPoly(C, pr)
    detail(C, 0.7, 2, {-24, 38, -24, 44})
    detail(C, 0.7, 2, {24, 38, 24, 44})
    -- armor seams + core
    detail(C, 0.5, 1.4, {-30, -6, 30, -6})
    detail(C, 0.5, 1.4, {-20, 8, 20, 8})
    neonCircleS(C, 0, 2, 9)
    glowDot(HOT_RED, 0, 2, 6, 1.0)
    glowDot(WARM, -34, -16, 2.2, 1.0)
    glowDot(WARM, 34, -16, 2.2, 1.0)
  end },

  { name = "boss_titan", w = 104, h = 104, draw = function()
    local C = { 0.95, 0.68, 0.42 }
    local p = {0,-44, 22,-36, 40,-16, 44,8, 30,32, 8,44, -18,40, -38,24, -44,-6, -30,-32}
    fillPoly(C, 0.08, p)
    neonPoly(C, p)
    -- deep cracks radiating from the molten core
    detail(C, 0.6, 1.8, {-20, -18, -4, -4, -14, 16})
    detail(C, 0.6, 1.8, {16, -22, 6, -4, 22, 12})
    detail(C, 0.6, 1.8, {-2, -4, 2, 24})
    neonCircleS(C, -22, 8, 5)
    neonCircleS(C, 18, -26, 4)
    glowDot(HOT_RED, 0, -2, 8, 1.0)
    glowDot({1, 0.5, 0.2}, -8, 10, 3, 0.8)
    glowDot({1, 0.5, 0.2}, 10, -12, 3, 0.8)
  end },

  { name = "boss_storm", w = 100, h = 96, draw = function()
    local C = { 1.0, 0.85, 0.35 }
    -- storm vortex: three offset swirl arcs
    lg.setLineWidth(6); lg.setColor(C[1], C[2], C[3], 0.10)
    lg.arc("line", "open", 0, 0, 38, 0.3, 3.6, 32)
    lg.arc("line", "open", 0, 0, 28, 2.4, 5.8, 32)
    lg.setLineWidth(3); lg.setColor(C[1], C[2], C[3], 0.30)
    lg.arc("line", "open", 0, 0, 38, 0.3, 3.6, 32)
    lg.arc("line", "open", 0, 0, 28, 2.4, 5.8, 32)
    lg.arc("line", "open", 0, 0, 18, 4.2, 7.6, 32)
    lg.setLineWidth(1.6)
    local r, g, b = coreOf(C)
    lg.setColor(r, g, b, 0.9)
    lg.arc("line", "open", 0, 0, 38, 0.3, 3.6, 32)
    lg.arc("line", "open", 0, 0, 28, 2.4, 5.8, 32)
    lg.arc("line", "open", 0, 0, 18, 4.2, 7.6, 32)
    -- lightning forks
    neonLine(C, {-10, -6, -2, 2, -8, 12})
    neonLine(C, {12, -12, 4, -2, 12, 6})
    -- the eye of the storm
    glowDot(WHITE, 0, 0, 7, 1.0)
    glowDot(C, 0, 0, 12, 0.5)
  end },

  { name = "boss_guardian", w = 100, h = 92, draw = function()
    local C = { 0.6, 0.9, 1.0 }
    -- crescent ring construct, horns down
    lg.setLineWidth(7); lg.setColor(C[1], C[2], C[3], 0.10)
    lg.arc("line", "open", 0, 8, 40, math.pi * 0.15, math.pi * 0.85, 32)
    lg.setLineWidth(3.5); lg.setColor(C[1], C[2], C[3], 0.30)
    lg.arc("line", "open", 0, 8, 40, math.pi * 0.15, math.pi * 0.85, 32)
    local r, g, b = coreOf(C)
    lg.setLineWidth(1.7); lg.setColor(r, g, b, 0.95)
    lg.arc("line", "open", 0, 8, 40, math.pi * 0.15, math.pi * 0.85, 32)
    -- crown body
    local body = {-16,-30, 16,-30, 24,-8, 12,10, -12,10, -24,-8}
    fillPoly(C, 0.10, body); neonPoly(C, body)
    -- ice prisms hanging from the arc
    local p1 = {-34, 26, -30, 38, -26, 26}
    local p2 = {34, 26, 30, 38, 26, 26}
    fillPoly(C, 0.14, p1); neonPolyS(C, p1)
    fillPoly(C, 0.14, p2); neonPolyS(C, p2)
    detail(C, 0.5, 1.4, {-10, -18, 10, -18})
    glowDot(WHITE, 0, -6, 5, 1.0)
  end },

  { name = "boss_overlord", w = 108, h = 104, draw = function()
    local C = { 0.8, 0.35, 1.0 }
    -- alien crown-head with a Z-scar
    local head = {0,-46, 26,-34, 40,-10, 34,20, 16,36, -16,36, -34,20, -40,-10, -26,-34}
    fillPoly(C, 0.08, head)
    neonPoly(C, head)
    -- mandibles reaching down
    neonLine(C, {-20, 34, -28, 48})
    neonLine(C, {20, 34, 28, 48})
    neonLine(C, {-8, 38, -10, 50})
    neonLine(C, {8, 38, 10, 50})
    -- the Z sigil, burned bright
    neonLine({1, 0.5, 1}, {-12, -22, 12, -22, -12, 2, 12, 2})
    -- triple eyes
    glowDot(HOT_RED, -14, 14, 4, 1.0)
    glowDot(HOT_RED, 14, 14, 4, 1.0)
    glowDot(WHITE, 0, 20, 5, 1.0)
    -- crown spikes
    detail(C, 0.7, 1.6, {-26, -34, -34, -46})
    detail(C, 0.7, 1.6, {26, -34, 34, -46})
    detail(C, 0.7, 1.6, {0, -46, 0, -56})
  end },
}

-- Alpha-blending onto a transparent canvas leaves premultiplied pixels; convert
-- back to straight alpha so the final Image is correct under both "alpha" and
-- "add" blend modes.
local function unpremultiply(_, _, r, g, b, a)
  if a > 0 then
    local inv = 1 / a
    r = r * inv; if r > 1 then r = 1 end
    g = g * inv; if g > 1 then g = 1 end
    b = b * inv; if b > 1 then b = 1 end
    return r, g, b, a
  end
  return 0, 0, 0, 0
end

local function pow2(n)
  local p = 1
  while p < n do p = p * 2 end
  return p
end

function M.build()
  -- shelf-pack cells
  local x, y, rowH = PAD, PAD, 0
  for i = 1, #defs do
    local d = defs[i]
    if x + d.w + PAD > ATLAS_W then
      x = PAD
      y = y + rowH + PAD
      rowH = 0
    end
    d.cx, d.cy = x, y
    x = x + d.w + PAD
    if d.h > rowH then rowH = d.h end
  end
  atlasH = pow2(y + rowH + PAD)   -- POT height for mobile GPU safety
  assert(ATLAS_W <= 1024 and atlasH <= 1024, "sprite atlas overflow")

  local canvas = lg.newCanvas(ATLAS_W, atlasH)
  lg.push("all")
  lg.setCanvas(canvas)
  lg.clear(0, 0, 0, 0)
  lg.setBlendMode("alpha")
  lg.setLineStyle("smooth")
  lg.setLineJoin("bevel")
  for i = 1, #defs do
    local d = defs[i]
    lg.push()
    lg.translate(d.cx + d.w * 0.5, d.cy + d.h * 0.5)
    d.draw()
    lg.pop()
  end
  lg.setCanvas()
  lg.pop()

  atlasImage = Compat.atlasTexture(canvas, lg, Compat.isWeb(), unpremultiply)

  for i = 1, #defs do
    local d = defs[i]
    sprites[d.name] = {
      quad = lg.newQuad(d.cx, d.cy, d.w, d.h, ATLAS_W, atlasH),
      w = d.w, h = d.h,
      ox = d.w * 0.5, oy = d.h * 0.5,
      info = { w = d.w, h = d.h },
    }
  end
end

function M.batch()
  assert(atlasImage, "Sprites.build() must be called before Sprites.batch()")
  return lg.newSpriteBatch(atlasImage, 2048, "stream")
end

function M.image()
  return atlasImage
end

function M.quad(name)
  local s = sprites[name]
  if not s then error("unknown sprite: " .. tostring(name)) end
  return s.quad
end

function M.info(name)
  local s = sprites[name]
  if not s then error("unknown sprite: " .. tostring(name)) end
  return s.info
end

-- Centered batched add; hot path — no allocations.
function M.add(batch, name, x, y, rot, scale, r, g, b, a)
  local s = sprites[name]
  if not s then error("unknown sprite: " .. tostring(name)) end
  local sc = scale or 1
  batch:setColor(r or 1, g or 1, b or 1, a or 1)
  batch:add(s.quad, x, y, rot or 0, sc, sc, s.ox, s.oy)
end

return M
