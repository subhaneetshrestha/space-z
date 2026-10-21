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

return M
