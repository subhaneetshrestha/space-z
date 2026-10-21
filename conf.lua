function love.conf(t)
  t.identity = "space-z"

  -- Declare the LÖVE version from LOVE_VERSION, so the runtime never shows its
  -- "made for another version" dialog (it blocks launch, and CI would hang on it).
  -- If the file cannot be read, t.version stays unset: LÖVE then assumes its own.
  local ok, text = pcall(love.filesystem.read, "LOVE_VERSION")
  if ok and text then
    local version = require("src.compat").parseVersionFile(text).love
    if version and version ~= "" then t.version = version end
  end

  t.window.title = "Space Z"
  t.window.width = 480
  t.window.height = 854
  t.window.resizable = true
  t.window.vsync = 1

  -- LÖVE 12 defaults to Vulkan, which on the Windows desktop paces frames unevenly (7 ms,
  -- then 26 ms; worst 64 ms) where OpenGL holds a steady frame time. Only Windows is
  -- pinned; a runtime without the field ignores it. `love._os` exists before the modules load.
  if love._os == "Windows" then t.renderers = { "opengl" } end

  -- unused modules off for startup speed
  t.modules.joystick = false
  t.modules.physics = false
  t.modules.video = false
end
