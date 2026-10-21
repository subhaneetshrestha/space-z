-- src/compat.lua — the one place where LÖVE 11 and LÖVE 12 differ, plus the parser
-- for LOVE_VERSION. No other file checks the engine version.
local M = {}

-- Parse LOVE_VERSION: `key=value` lines, `#` comments and blank lines ignored.
-- Returns a table of strings (an empty value is kept as "").
function M.parseVersionFile(text)
  local out = {}
  for line in tostring(text):gmatch("[^\r\n]+") do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key then out[key] = value end
  end
  return out
end

-- Texture -> ImageData. LÖVE 12 deprecates Texture:newImageData (it prints a warning
-- over the game) in favour of love.graphics.readbackTexture; 11 only has the method.
-- `lg` is love.graphics (a parameter so tests can stand in for it).
function M.readbackImageData(texture, lg)
  if lg.readbackTexture then return lg.readbackTexture(texture) end
  return texture:newImageData()
end

-- True in the browser build (love.js reports its OS as "Web").
function M.isWeb()
  return love ~= nil and love.system ~= nil and love.system.getOS() == "Web"
end

-- The sprite atlas: a canvas drawn with premultiplied alpha -> a texture holding straight
-- alpha, which is what the batches draw with. Normally that goes through ImageData
-- (readback, then `unpremultiply` per pixel). In the browser (WebGL 1) Canvas:newImageData
-- returns all zeros, which left every sprite invisible, so there a shader does the same
-- division on the GPU into a second canvas. Either way the premultiplied canvas is freed.
-- `lg` is love.graphics, `web` says which path (parameters so tests can stand in).
function M.atlasTexture(canvas, lg, web, unpremultiply)
  local texture
  if web then
    local shader = lg.newShader([[
      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
        vec4 c = Texel(tex, uv);
        if (c.a > 0.0) { c.rgb = min(c.rgb / c.a, vec3(1.0)); }
        return c;
      }
    ]])
    local w, h = canvas:getDimensions()
    texture = lg.newCanvas(w, h)
    lg.push("all")
    lg.setCanvas(texture)
    lg.clear(0, 0, 0, 0)
    lg.setShader(shader)
    lg.setBlendMode("replace")
    lg.setColor(1, 1, 1, 1)
    lg.draw(canvas)
    lg.pop()
  else
    local data = M.readbackImageData(canvas, lg)
    data:mapPixel(unpremultiply)
    texture = lg.newImage(data)
    data:release()
  end
  texture:setFilter("linear", "linear")
  canvas:release()
  return texture
end

-- Contents of a file in the save / game folder, or nil if it is not there. LÖVE's own
-- love.filesystem.read returns nil for a missing file, but the browser runtime (love.js)
-- raises a fatal error for it that even pcall does not contain, and a first visit has no
-- save yet: so ask getInfo first. `fs` is love.filesystem (a parameter so tests can pass one).
function M.readFile(path, fs)
  fs = fs or love.filesystem
  if not fs.getInfo(path) then return nil end
  return fs.read(path)
end

return M
