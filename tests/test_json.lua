-- tests/test_json.lua — encode/decode round-trips + malformed input errors.
local json = require("lib.json")

local T = {}

function T.roundtrip_nested(t)
  local data = {
    version = 1,
    stardust = 1234,
    nested = { a = { b = { c = "deep" } }, flag = true },
    list = { 1, 2, 3, "four" },
    pi = 3.14159,
  }
  local decoded = json.decode(json.encode(data))
  t.eq(decoded.version, 1)
  t.eq(decoded.stardust, 1234)
  t.eq(decoded.nested.a.b.c, "deep")
  t.eq(decoded.nested.flag, true)
  t.eq(#decoded.list, 4)
  t.eq(decoded.list[4], "four")
  t.near(decoded.pi, 3.14159, 1e-9)
end

function T.arrays_vs_objects(t)
  local s = json.encode({ 10, 20, 30 })
  t.ok(s:sub(1, 1) == "[", "consecutive int keys encode as array: " .. s)
  local o = json.encode({ name = "x" })
  t.ok(o:sub(1, 1) == "{", "string keys encode as object: " .. o)
end

function T.string_escapes(t)
  local s = 'quote " backslash \\ newline \n tab \t'
  local decoded = json.decode(json.encode({ v = s }))
  t.eq(decoded.v, s, "escaped string round-trips")
end

function T.unicode_escape_decode(t)
  local decoded = json.decode('{"v":"\\u0041\\u00e9"}')
  t.eq(decoded.v, "A\195\169", "\\uXXXX decodes to UTF-8")
end

function T.booleans_null(t)
  local decoded = json.decode('{"a":true,"b":false,"c":null}')
  t.eq(decoded.a, true)
  t.eq(decoded.b, false)
  t.eq(decoded.c, nil, "null becomes nil/absent")
end

function T.malformed_errors(t)
  for _, bad in ipairs({ "{", '{"a":}', "[1,2,", '"unterminated', "nope", "{'single':1}" }) do
    local ok = pcall(json.decode, bad)
    t.ok(not ok, "malformed input must error: " .. bad)
  end
end

function T.whitespace_tolerant(t)
  local decoded = json.decode('  {  "a" :  [ 1 , 2 ]  }  ')
  t.eq(decoded.a[2], 2)
end

return T
