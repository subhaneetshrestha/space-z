-- lib/json.lua — minimal, self-contained JSON encoder/decoder (Lua 5.1 / LuaJIT).
-- Encode: tables with consecutive 1..n integer keys become arrays, otherwise
-- objects (string keys only). Decode: full JSON incl. \uXXXX -> UTF-8.
local M = {}

local type, pairs, tostring, tonumber, error = type, pairs, tostring, tonumber, error
local floor, huge = math.floor, math.huge
local format, byte, char = string.format, string.byte, string.char
local sub, find, gsub = string.sub, string.find, string.gsub
local concat = table.concat

-- ------------------------------------------------------------------ encode

local escapeMap = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function escapeChar(c)
  return escapeMap[c] or format("\\u%04x", byte(c))
end

local function encodeString(s)
  return '"' .. gsub(s, '[%z\1-\31"\\]', escapeChar) .. '"'
end

local function encodeNumber(n)
  if n ~= n then error("json.encode: cannot encode NaN") end
  if n == huge or n == -huge then error("json.encode: cannot encode infinity") end
  return format("%.14g", n)
end

local encodeValue

-- `seen` detects cycles only for the current path, so shared subtables are fine.
local function encodeTable(t, seen)
  if seen[t] then error("json.encode: circular reference") end
  seen[t] = true
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  local out
  if n == 0 then
    out = "[]"
  else
    -- n distinct integer keys all within [1, n] <=> exactly the keys 1..n.
    local isArray = true
    for k in pairs(t) do
      if type(k) ~= "number" or k < 1 or k > n or k ~= floor(k) then
        isArray = false
        break
      end
    end
    local buf = {}
    if isArray then
      for i = 1, n do
        buf[i] = encodeValue(t[i], seen)
      end
      out = "[" .. concat(buf, ",") .. "]"
    else
      local bi = 0
      for k, v in pairs(t) do
        if type(k) ~= "string" then
          error("json.encode: object keys must be strings (got "
            .. type(k) .. ": " .. tostring(k) .. ")")
        end
        bi = bi + 1
        buf[bi] = encodeString(k) .. ":" .. encodeValue(v, seen)
      end
      out = "{" .. concat(buf, ",") .. "}"
    end
  end
  seen[t] = nil
  return out
end

encodeValue = function(v, seen)
  local tv = type(v)
  if tv == "nil" then
    return "null"
  elseif tv == "boolean" then
    return v and "true" or "false"
  elseif tv == "number" then
    return encodeNumber(v)
  elseif tv == "string" then
    return encodeString(v)
  elseif tv == "table" then
    return encodeTable(v, seen)
  else
    error("json.encode: cannot encode value of type " .. tv)
  end
end

function M.encode(v)
  return encodeValue(v, {})
end

-- ------------------------------------------------------------------ decode

local function decodeError(pos, msg)
  error(format("json.decode: %s at position %d", msg, pos))
end

local function skipWs(str, pos)
  local s = find(str, "[^ \t\r\n]", pos)
  return s or #str + 1
end

local function utf8Encode(cp)
  if cp < 0x80 then
    return char(cp)
  elseif cp < 0x800 then
    return char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return char(0xE0 + floor(cp / 0x1000),
      0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  else
    return char(0xF0 + floor(cp / 0x40000), 0x80 + floor(cp / 0x1000) % 0x40,
      0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
end

local escapeDecode = {
  ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
  b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
}

local function parseHex4(str, pos)
  local hex = sub(str, pos, pos + 3)
  if not find(hex, "^%x%x%x%x$") then
    decodeError(pos, "invalid \\u escape")
  end
  return tonumber(hex, 16)
end

-- pos points at the opening quote; returns string, position after closing quote.
local function parseString(str, pos)
  local buf, bi = {}, 0
  local i = pos + 1
  while true do
    local c = byte(str, i)
    if not c then
      decodeError(pos, "unterminated string")
    elseif c == 34 then -- '"'
      return concat(buf), i + 1
    elseif c == 92 then -- '\'
      local esc = sub(str, i + 1, i + 1)
      if esc == "u" then
        local cp = parseHex4(str, i + 2)
        i = i + 6
        if cp >= 0xD800 and cp <= 0xDBFF then -- high surrogate: pair required
          if sub(str, i, i + 1) ~= "\\u" then
            decodeError(i, "missing low surrogate")
          end
          local lo = parseHex4(str, i + 2)
          if lo < 0xDC00 or lo > 0xDFFF then
            decodeError(i, "invalid low surrogate")
          end
          cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
          i = i + 6
        elseif cp >= 0xDC00 and cp <= 0xDFFF then
          decodeError(i - 6, "unexpected low surrogate")
        end
        bi = bi + 1
        buf[bi] = utf8Encode(cp)
      else
        local ch = escapeDecode[esc]
        if not ch then
          decodeError(i, "invalid escape '\\" .. esc .. "'")
        end
        bi = bi + 1
        buf[bi] = ch
        i = i + 2
      end
    elseif c < 32 then
      decodeError(i, "control character in string")
    else
      -- consume a run of plain characters in one slice
      local j = i
      repeat
        j = j + 1
        local cj = byte(str, j)
        if not cj or cj == 34 or cj == 92 or cj < 32 then break end
      until false
      bi = bi + 1
      buf[bi] = sub(str, i, j - 1)
      i = j
    end
  end
end

local function parseNumber(str, pos)
  local _, e = find(str, "^%-?%d+%.?%d*", pos)
  if not e then decodeError(pos, "invalid number") end
  local _, e2 = find(str, "^[eE][%-+]?%d+", e + 1)
  if e2 then e = e2 end
  local n = tonumber(sub(str, pos, e))
  if not n then decodeError(pos, "invalid number") end
  return n, e + 1
end

local parseValue

local function parseArray(str, pos)
  local arr, n = {}, 0
  pos = skipWs(str, pos + 1)
  if sub(str, pos, pos) == "]" then return arr, pos + 1 end
  while true do
    local v
    v, pos = parseValue(str, pos)
    n = n + 1
    arr[n] = v
    pos = skipWs(str, pos)
    local c = sub(str, pos, pos)
    if c == "]" then return arr, pos + 1 end
    if c ~= "," then decodeError(pos, "expected ',' or ']'") end
    pos = skipWs(str, pos + 1)
  end
end

local function parseObject(str, pos)
  local obj = {}
  pos = skipWs(str, pos + 1)
  if sub(str, pos, pos) == "}" then return obj, pos + 1 end
  while true do
    if sub(str, pos, pos) ~= '"' then
      decodeError(pos, "expected string key")
    end
    local key, v
    key, pos = parseString(str, pos)
    pos = skipWs(str, pos)
    if sub(str, pos, pos) ~= ":" then decodeError(pos, "expected ':'") end
    v, pos = parseValue(str, skipWs(str, pos + 1))
    obj[key] = v -- JSON null -> nil (key absent)
    pos = skipWs(str, pos)
    local c = sub(str, pos, pos)
    if c == "}" then return obj, pos + 1 end
    if c ~= "," then decodeError(pos, "expected ',' or '}'") end
    pos = skipWs(str, pos + 1)
  end
end

parseValue = function(str, pos)
  local c = sub(str, pos, pos)
  if c == "{" then
    return parseObject(str, pos)
  elseif c == "[" then
    return parseArray(str, pos)
  elseif c == '"' then
    return parseString(str, pos)
  elseif c == "t" then
    if sub(str, pos, pos + 3) == "true" then return true, pos + 4 end
    decodeError(pos, "invalid literal")
  elseif c == "f" then
    if sub(str, pos, pos + 4) == "false" then return false, pos + 5 end
    decodeError(pos, "invalid literal")
  elseif c == "n" then
    if sub(str, pos, pos + 3) == "null" then return nil, pos + 4 end
    decodeError(pos, "invalid literal")
  elseif c == "-" or find(c, "^%d") then
    return parseNumber(str, pos)
  elseif c == "" then
    decodeError(pos, "unexpected end of input")
  else
    decodeError(pos, "unexpected character '" .. c .. "'")
  end
end

function M.decode(str)
  if type(str) ~= "string" then
    error("json.decode: expected string, got " .. type(str))
  end
  local v, pos = parseValue(str, skipWs(str, 1))
  pos = skipWs(str, pos)
  if pos <= #str then
    decodeError(pos, "trailing garbage")
  end
  return v
end

return M
