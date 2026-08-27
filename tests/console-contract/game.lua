assert(_VERSION == "Lua 5.4")
assert(ui.stat(0) < 4 * 1024 * 1024)
assert(ui.stat(1) >= 0 and ui.stat(1) <= 100)
require("sprites")

ui.palset(0, 0x0000)
ui.palset(1, 0x7fff)
ui.palset(2, 0x001f)
ui.palset(3, 0x03e0)
ui.palset(4, 0x7c00)

function update(frame)
  assert(frame >= 0)
  ui.clip(0, 0, 1, 1)
  ui.cls(1)
  ui.rectfill(10, 10, 13, 13, 2)
  ui.tile(Sprites.probe, 0, 20, 10, false, true)
end
