local function ascii_range(first, last)
    local bytes = {}
    for code = first, last do bytes[#bytes + 1] = string.char(code) end
    return table.concat(bytes)
end

function update()
    ui.palset(1, 0x7fff)
    ui.palset(2, 0x7c00)
    ui.palset(3, 0x03e0)
    ui.palset(4, 0x001f)
    ui.cls(0)

    -- Bresenham octants, reversed endpoints, and a single-pixel line.
    local cx, cy = 54, 44
    local endpoints = {
        { 78, 52 }, { 62, 68 }, { 46, 68 }, { 30, 52 },
        { 30, 36 }, { 46, 20 }, { 62, 20 }, { 78, 36 },
    }
    for index, point in ipairs(endpoints) do
        if index % 2 == 0 then ui.line(point[1], point[2], cx, cy, 1)
        else ui.line(cx, cy, point[1], point[2], 1) end
    end
    ui.line(54, 44, 54, 44, 2)

    ui.draw_rect(92, 18, 26, 18, false, 2)
    ui.draw_rect(124, 18, 26, 18, true, 3)
    ui.rect(156, 18, 180, 34, 4)
    ui.rectfill(186, 18, 210, 34, 2)
    ui.draw_rect(216, 18, 0, 5, false, 3)

    ui.draw_circle(110, 66, 0, false, 2, true, 3)
    ui.draw_circle(134, 66, 8, false, 2, true, 3)
    ui.draw_circle(164, 66, 9, true, 4, false, 1)
    ui.circfill(196, 66, 10, 2)

    -- Vertex permutations, flat top/bottom, and horizontal degeneration.
    ui.trisfill(230, 80, 246, 46, 262, 80, 3)
    ui.trisfill(300, 80, 268, 80, 284, 46, 4)
    ui.trisfill(310, 46, 342, 64, 318, 82, 2)
    ui.trisfill(354, 64, 370, 64, 386, 64, 1)

    -- Pattern coordinates are screen-space after camera transformation.
    ui.fillp(0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55)
    ui.camera(7, 5)
    ui.clip(394, 18, 58, 64)
    ui.rectfill(396, 20, 462, 88, 3)
    ui.line(390, 16, 468, 92, 4)
    ui.camera()
    ui.clip()
    ui.fillp()

    -- Every glyph supported by upstream, split to stay inside 480 pixels.
    ui.print(ascii_range(32, 78), 8, 112, 1)
    ui.print(ascii_range(79, 126), 8, 124, 1)
end
