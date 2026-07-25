-- src/core/events.lua — per-world event bus (instance via Events.new(), not a singleton).

local M = {}

local Bus = {}
Bus.__index = Bus

function M.new()
  return setmetatable({ _handlers = {} }, Bus)
end

function Bus:on(name, fn)
  local list = self._handlers[name]
  if not list then
    list = {}
    self._handlers[name] = list
  end
  list[#list + 1] = fn
end

function Bus:emit(name, a, b, c)
  local list = self._handlers[name]
  if not list then return end
  -- loop bound is fixed at entry: handlers registered during an emit fire from the next emit on
  for i = 1, #list do
    list[i](a, b, c)
  end
end

function Bus:clear()
  self._handlers = {}
end

return M
