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

    ui.camera(3, 4)
    ui.clip(60, 20, 1, 1)
    ui.spr(Sprites.sheet, 63, 24)
    ui.camera()
    ui.clip()
end
