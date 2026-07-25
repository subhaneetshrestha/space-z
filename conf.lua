function love.conf(t)
  t.identity = "space-z"
  t.version = "11.5"

  t.window.title = "Space Z"
  t.window.width = 480
  t.window.height = 854
  t.window.resizable = true
  t.window.vsync = 1

  -- unused modules off for startup speed
  t.modules.joystick = false
  t.modules.physics = false
  t.modules.video = false
end
