require "sprites"

assert(Sprites.find("unique") == Sprites.unique)
assert(Sprites.find("a/shared") == Sprites.a.shared)
assert(Sprites.find("b/shared") == Sprites.b.shared)

local ambiguous_ok, ambiguous_message = pcall(__lupi_find, Sprites, "shared")
assert(not ambiguous_ok)
assert(string.find(ambiguous_message, "ambiguous sprite 'shared'", 1, true))
assert(string.find(ambiguous_message, "a/shared, b/shared", 1, true))

local exact_map = {
    metadata = { width = 1, height = 1, tile_size = 1 },
    tilesets = { layer = "a/shared" },
    layers = { "layer" },
    layer = { [1] = 0 },
}

function update()
    ui.palset(65, 0x7c00)
    ui.palset(67, 0x001f)
    ui.cls(0)
    ui.map(exact_map, 10, 10)
    ui.spr(Sprites.find("unique"), 20, 10)
end
