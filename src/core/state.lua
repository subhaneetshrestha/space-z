-- src/core/state.lua — stack-based state machine (singleton module).
-- States are plain tables with optional callbacks: enter(params), leave(),
-- resume(result), update(dt), draw(), input handlers, resize().
-- A state with .translucent == true lets the state below it draw first.
local M = {}

local registry = {}
local stack = {}

function M.register(name, state)
  registry[name] = state
  state.__name = name
end

local function get(name)
  local s = registry[name]
  if not s then error("unknown state: " .. tostring(name)) end
  return s
end

function M.switch(name, params)
  for i = #stack, 1, -1 do
    local s = stack[i]
    stack[i] = nil
    if s.leave then s:leave() end
  end
  local s = get(name)
  stack[1] = s
  if s.enter then s:enter(params) end
end

function M.push(name, params)
  local s = get(name)
  stack[#stack + 1] = s
  if s.enter then s:enter(params) end
end

function M.pop(result)
  local n = #stack
  if n == 0 then return end
  local s = stack[n]
  stack[n] = nil
  if s.leave then s:leave() end
  local below = stack[n - 1]
  if below and below.resume then below:resume(result) end
end

function M.current()
  return stack[#stack]
end

function M.update(dt)
  local s = stack[#stack]
  if s and s.update then s:update(dt) end
end

function M.draw()
  local n = #stack
  if n == 0 then return end
  -- walk down while states are translucent, then draw from there upward
  local first = n
  while first > 1 and stack[first].translucent do
    first = first - 1
  end
  for i = first, n do
    local s = stack[i]
    if s.draw then s:draw() end
  end
end

function M.resize()
  for i = 1, #stack do
    local s = stack[i]
    if s.resize then s:resize() end
  end
end

-- input goes to the top state only
local function forward(fname)
  return function(a, b, c, d)
    local s = stack[#stack]
    local fn = s and s[fname]
    if fn then fn(s, a, b, c, d) end
  end
end

M.keypressed = forward("keypressed")
M.mousepressed = forward("mousepressed")
M.mousemoved = forward("mousemoved")
M.mousereleased = forward("mousereleased")
M.touchpressed = forward("touchpressed")
M.touchmoved = forward("touchmoved")
M.touchreleased = forward("touchreleased")

return M
