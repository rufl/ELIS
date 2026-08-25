require "sprites"

local metadata = { width = 1, height = 1, tile_size = 2 }
local tilesets = { lower = "bottom", upper = "top" }

-- Explicit arrays are a complete bottom-to-top contract.
local explicit_red_on_top = {
    metadata = metadata,
    tilesets = tilesets,
    layers = { "upper", "lower" },
    lower = { [1] = 0 },
    upper = { [1] = 0 },
}

local explicit_blue_on_top = {
    metadata = metadata,
    tilesets = tilesets,
    layers = { "lower", "upper" },
    lower = { [1] = 0 },
    upper = { [1] = 0 },
}

-- Legacy maps without `layers` are sorted by key: lower, then upper.
local deterministic_legacy = {
    metadata = metadata,
    tilesets = tilesets,
    lower = { [1] = 0 },
    upper = { [1] = 0 },
}

local invalid_order_checked = false

local function expect_map_error(map, fragment)
    local ok, message = pcall(ui.map, map)
    assert(not ok)
    assert(string.find(message, fragment, 1, true))
end

function update()
    if not invalid_order_checked then
        expect_map_error({
            metadata = metadata,
            layers = { "lower" },
            lower = { [1] = 0 },
            upper = { [1] = 0 },
        }, "must list every map layer exactly once")
        expect_map_error({
            metadata = metadata,
            layers = { "lower", "lower" },
            lower = { [1] = 0 },
            upper = { [1] = 0 },
        }, "unknown or duplicate layer")
        expect_map_error({
            metadata = metadata,
            layers = { "lower", "missing" },
            lower = { [1] = 0 },
            upper = { [1] = 0 },
        }, "unknown or duplicate layer")
        expect_map_error({
            metadata = metadata,
            layers = { "lower", 42 },
            lower = { [1] = 0 },
            upper = { [1] = 0 },
        }, "every 'layers' entry must be a string")
        expect_map_error({
            metadata = metadata,
            layers = "lower,upper",
            lower = { [1] = 0 },
            upper = { [1] = 0 },
        }, "must be an array of layer names")

        -- Exercise the heap fallback beyond the 64-layer inline fast path.
        local many_layers = { metadata = metadata, layers = {} }
        for index = 1, 65 do
            local name = string.format("layer-%02d", index)
            many_layers.layers[index] = name
            many_layers[name] = {}
        end
        local many_ok, many_error = pcall(ui.map, many_layers)
        assert(many_ok, many_error)
        invalid_order_checked = true
    end

    ui.palset(0, 0x0000)
    ui.palset(65, 0x7c00)
    ui.palset(66, 0x03e0)
    ui.palset(67, 0x001f)
    ui.palset(68, 0x7fff)
    ui.cls(0)
    ui.map(explicit_red_on_top, 10, 10)
    ui.map(explicit_blue_on_top, 20, 10)
    ui.map(deterministic_legacy, 30, 10)
end
