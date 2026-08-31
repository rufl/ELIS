require "sprites"

local map_flips = {
    metadata = { width = 2, height = 1, tile_size = 2 },
    layers = { "sheet" },
    sheet = { [1] = 2048, [2] = 1025 },
}

function update()
    local colors = {
        0x7c00, 0x03e0, 0x001f, 0x7fff,
        0x4210, 0x7fe0, 0x03ff,
    }
    for index, value in ipairs(colors) do ui.palset(index, value) end
    ui.cls(0)

    -- Transparent zero in the first tile must preserve this underlay.
    ui.draw_rect(10, 10, 2, 2, true, 7)
    ui.spr(Sprites.sheet, 10, 10)
    ui.spr(Sprites.sheet, 20, 10, true)
    ui.tile(Sprites.sheet, 1, 30, 10)
    ui.tile(Sprites.sheet, 1025, 40, 10)
    ui.map(map_flips, 50, 10)

    -- Drawing is immediate: later opaque sprite pixels replace earlier ones,
    -- while palette index zero reveals the earlier call at that pixel.
    ui.tile(Sprites.sheet, 0, 70, 10)
    ui.tile(Sprites.sheet, 1, 70, 10)
    ui.tile(Sprites.sheet, 1, 80, 10)
    ui.tile(Sprites.sheet, 0, 80, 10)

    -- Ordering is shared across draw categories, not sorted by primitive type.
    ui.spr(Sprites.sheet, 90, 10)
    ui.rectfill(90, 10, 91, 11, 7)

    ui.camera(3, 4)
    ui.clip(60, 20, 1, 1)
    ui.spr(Sprites.sheet, 63, 24)
    ui.camera()
    ui.clip()
end
