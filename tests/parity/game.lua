local helper = require("helper")

local upstream_api = {
  "btn", "btnp", "camera", "circfill", "clip", "cls", "draw_circle",
  "draw_rect", "draw_sprite", "fillp", "line", "log", "map", "mid",
  "palset", "preload_spritesheet", "print", "rect", "rectfill",
  "set_pallet", "spr", "tile", "trisfill",
}
for _, name in ipairs(upstream_api) do
  assert(type(ui[name]) == "function", "missing ui." .. name)
end

assert(_VERSION == "Lua 5.4")
assert(helper.quoted == "0b101")
assert(helper.single == "0B110")
assert(helper.long == "0b111")
assert(helper.escaped == "quote: \"0b1000\"")
assert(helper.value == 5)
assert(helper.upper_value == 6)

-- Binary literals retain Lua integer identity and expression binding at bit 63.
local minimum = 0b1000000000000000000000000000000000000000000000000000000000000000
assert(math.type(minimum) == "integer" and minimum == math.mininteger)
local difference = 1-0b1111111111111111111111111111111111111111111111111111111111111111
assert(difference == 2)
assert(0b1111111111111111111111111111111111111111111111111111111111111111^2 == 1)
assert(0b10000000000000000000000000000000000000000000000000000000000000000 == 0)

-- Core upstream calls reject missing required arguments.
assert(not pcall(ui.cls))
assert(not pcall(ui.line, 1, 2, 3, 4))
assert(not pcall(ui.draw_rect, 1, 2, 3, 4, false))
assert(not pcall(ui.print, "text", 1, 2))
assert(not pcall(ui.mid, 1, 2))
assert(not pcall(ui.spr, {}, 1, 2))
assert(not pcall(ui.tile, {}, 0, 1, 2))
assert(not pcall(ui.map, "not a table"))
assert(not pcall(ui.line, math.huge, 0, 1, 1, 1))
assert(not pcall(ui.line, -math.huge, 0, 1, 1, 1))

ui.palset(0, 0x7fff)
ui.palset(1, 0x7fff)
ui.palset(2, 0x001f)
ui.palset(3, 0x03e0)
ui.palset(4, 0x7c00)

function update()
  ui.cls(0)
  ui.draw_rect(10, 10, 20, 12, false, 1)
  ui.circfill(60, 30, 6, 1)
  ui.trisfill(90, 20, 100, 20, 110, 20, 1)
  ui.print("Aa", 120, 10, 1)
  ui.rectfill(1, 1, 3, 3, 2)
  ui.rectfill(5, 1, 7, 3, 3)
  ui.rectfill(9, 1, 11, 3, 4)
end
