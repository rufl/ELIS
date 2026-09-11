//! Bounded Workshop readers for Lupi manifests, palettes, and bitmap metadata.
//!
//! Parsing is intentionally tolerant for editor discovery; export performs the
//! stricter identity, byte-length, geometry, and tile-bound checks.

const std = @import("std");
const lupi_profile = @import("lupi_profile.zig");

pub const max_assets: usize = 96;
pub const max_asset_path: usize = 127;
/// The official lupi-codec rejects tileset images above 512×96 pixels.
pub const lupi_tileset_pixels_max: u32 = lupi_profile.tileset_pixels_max;

pub const BitmapMetadata = struct {
    width: u16,
    height: u16,
    tiles: u16 = 1,
};

/// Decode root bitmap fields without borrowing the input or retaining allocations.
pub fn parseBitmapMetadata(json: []const u8) ?BitmapMetadata {
    var scratch: [64 * 1024]u8 = undefined;
    var buffer_allocator = std.heap.FixedBufferAllocator.init(&scratch);
    const allocator = buffer_allocator.allocator();
    // Parse the complete tree so duplicate keys in unknown metadata are rejected too.
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, json, .{
        .duplicate_field_behavior = .@"error",
    }) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const fields = parsed.value.object;
    const asset_type = fields.get("type") orelse return null;
    if (asset_type != .string or !std.mem.eql(u8, asset_type.string, "bitmap")) return null;
    const width = metadataUnsigned(fields.get("width") orelse return null) orelse return null;
    const height = metadataUnsigned(fields.get("height") orelse return null) orelse return null;
    const tiles = metadataUnsigned(fields.get("tiles") orelse .{ .integer = 1 }) orelse return null;
    if (width == 0 or height == 0 or tiles == 0 or tiles > 1024) return null;
    return .{ .width = width, .height = height, .tiles = tiles };
}

fn metadataUnsigned(value: std.json.Value) ?u16 {
    if (value != .integer) return null;
    return std.math.cast(u16, value.integer);
}

pub const BitmapAsset = struct {
    path: [max_asset_path + 1]u8 = .{0} ** (max_asset_path + 1),
    path_len: u8 = 0,
    width: u16,
    height: u16,
    tiles: u16,
    byte_len: u32,

    pub fn name(self: *const BitmapAsset) []const u8 {
        return self.path[0..self.path_len];
    }

    pub fn lupiCompatible(self: BitmapAsset, tile_size: u16, tile_id_max: u16) bool {
        if (self.width != tile_size or self.height != tile_size) return false;
        const pixels_per_tile = @as(u32, self.width) * self.height;
        if (pixels_per_tile == 0 or self.byte_len % pixels_per_tile != 0) return false;
        if (self.byte_len > lupi_tileset_pixels_max) return false;
        const encoded_tiles = self.byte_len / pixels_per_tile;
        return encoded_tiles > 0 and tile_id_max < encoded_tiles;
    }
};

pub const Catalog = struct {
    items: [max_assets]BitmapAsset = undefined,
    count: u8 = 0,

    pub fn slice(self: *const Catalog) []const BitmapAsset {
        return self.items[0..self.count];
    }

    pub fn find(self: *const Catalog, name: []const u8) ?usize {
        for (self.slice(), 0..) |*asset, index| {
            if (std.mem.eql(u8, asset.name(), name)) return index;
        }
        return null;
    }

    pub fn firstTileSize(self: *const Catalog, tile_size: u16) ?usize {
        for (self.slice(), 0..) |asset, index| {
            if (asset.lupiCompatible(tile_size, 0)) return index;
        }
        return null;
    }
};

pub const Palette = struct {
    colors: [256][3]u8,
    defined: [256]bool = .{false} ** 256,
    defined_count: u16 = 0,

    pub fn diagnostic() Palette {
        var result = Palette{ .colors = undefined };
        for (&result.colors, 0..) |*color, index| color.* = diagnosticColor(@intCast(index));
        return result;
    }

    pub fn exact(self: Palette) bool {
        return self.defined_count != 0;
    }
};

pub fn parseManifest(source: []const u8) Catalog {
    var result = Catalog{};
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (result.count == max_assets) break;
        var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
        _ = tokens.next() orelse continue;
        const byte_text = tokens.next() orelse continue;
        const path = tokens.next() orelse continue;
        const json = tokens.rest();
        if (!safeAssetPath(path) or path.len > max_asset_path or
            result.find(path) != null) continue;
        const metadata = parseBitmapMetadata(json) orelse continue;
        if (metadata.width > 64 or metadata.height > 64) continue;
        const byte_len = std.fmt.parseUnsigned(u32, byte_text, 10) catch continue;
        var asset = BitmapAsset{
            .width = metadata.width,
            .height = metadata.height,
            .tiles = metadata.tiles,
            .byte_len = byte_len,
        };
        @memcpy(asset.path[0..path.len], path);
        asset.path_len = @intCast(path.len);
        result.items[result.count] = asset;
        result.count += 1;
    }
    return result;
}

pub fn parsePaletteLua(source: []const u8) Palette {
    var result = Palette.diagnostic();
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const open = std.mem.indexOfScalar(u8, line, '[') orelse continue;
        const close_relative = std.mem.indexOfScalar(u8, line[open + 1 ..], ']') orelse continue;
        const close = open + 1 + close_relative;
        const lua_index = std.fmt.parseUnsigned(u16, std.mem.trim(u8, line[open + 1 .. close], " \t"), 10) catch continue;
        if (lua_index == 0 or lua_index > 256) continue;
        const hex_relative = std.mem.indexOf(u8, line[close + 1 ..], "0x") orelse
            std.mem.indexOf(u8, line[close + 1 ..], "0X") orelse continue;
        const hex_start = close + 1 + hex_relative + 2;
        var hex_end = hex_start;
        while (hex_end < line.len and std.ascii.isHex(line[hex_end])) : (hex_end += 1) {}
        if (hex_end == hex_start) continue;
        const packed_value = std.fmt.parseUnsigned(u16, line[hex_start..hex_end], 16) catch continue;
        const index = lua_index - 1;
        result.colors[index] = rgb555(packed_value);
        if (!result.defined[index]) {
            result.defined[index] = true;
            result.defined_count += 1;
        }
    }
    return result;
}

pub fn rgb555(value: u16) [3]u8 {
    const blue: u8 = @truncate(value);
    const green: u8 = @truncate(value >> 5);
    const red: u8 = @truncate(value >> 10);
    return .{ expand5(red), expand5(green), expand5(blue) };
}

pub fn diagnosticColor(index: u8) [3]u8 {
    return .{
        @intCast(((index >> 5) & 7) * 36),
        @intCast(((index >> 2) & 7) * 36),
        @intCast((index & 3) * 85),
    };
}

fn expand5(value: u8) u8 {
    const component = value & 31;
    return (component << 3) | (component >> 2);
}

fn safeAssetPath(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or std.mem.indexOfScalar(u8, path, '\\') != null) {
        return false;
    }
    var component_count: usize = 0;
    var components = std.mem.splitScalar(u8, path, '/');
    while (components.next()) |component| {
        if (!@import("package_path.zig").safeComponent(component) or component_count == 32) {
            return false;
        }
        component_count += 1;
    }
    return component_count > 0;
}

test "bitmap metadata uses root fields and decodes escaped strings" {
    const nested = parseBitmapMetadata(
        \\{"custom":{"width":1,"type":"other"},"type":"bitmap","width":2,"height":1}
    ).?;
    try std.testing.expectEqual(@as(u16, 2), nested.width);
    try std.testing.expectEqual(@as(u16, 1), nested.height);
    try std.testing.expectEqual(@as(u16, 1), nested.tiles);
    const escaped = parseBitmapMetadata(
        \\{"ty\u0070e":"bit\u006dap","wi\u0064th":65535,"height":1,"tiles":1024,"custom":"\"width\":1"}
    ).?;
    try std.testing.expectEqual(@as(u16, 65535), escaped.width);
    try std.testing.expectEqual(@as(u16, 1024), escaped.tiles);
    const catalog = parseManifest(
        \\100 2 sprites/root {"custom":{"width":1},"type":"bitmap","width":2,"height":1}
    );
    try std.testing.expectEqual(@as(u8, 1), catalog.count);
    try std.testing.expectEqual(@as(u16, 2), catalog.items[0].width);
}

test "bitmap metadata rejects malformed duplicate and incorrectly typed fields" {
    const invalid = [_][]const u8{
        \\{"type":"bitmap","width":2,"height":1
        ,
        \\{"type":"bitmap","width":2,"height":1} trailing
        ,
        \\{"type":"bitmap","width":2,"height":1,}
        ,
        \\{"type":"bitmap","width":2,"width":3,"height":1}
        ,
        \\{"type":"bitmap","width":2,"wi\u0064th":3,"height":1}
        ,
        \\{"type":"bitmap","width":2,"height":1,"custom":1,"custom":2}
        ,
        \\{"type":"bitmap","width":2,"height":1,"custom":{"x":1,"x":2}}
        ,
        \\{"type":"bitmap","width":"2","height":1}
        ,
        \\{"type":"bitmap","width":2.5,"height":1}
        ,
        \\{"type":"bitmap","width":2,"height":true}
        ,
        \\{"type":"bitmap","width":2,"height":1,"tiles":null}
        ,
        \\{"type":["bitmap"],"width":2,"height":1}
        ,
        \\{"type":"lua_code","width":2,"height":1}
        ,
        \\{"type":"bitmap","height":1,"custom":{"width":2}}
        ,
        \\[{"type":"bitmap","width":2,"height":1}]
        ,
        \\{"type":"bitmap","width":0,"height":1}
        ,
        \\{"type":"bitmap","width":2,"height":-1}
        ,
        \\{"type":"bitmap","width":65536,"height":1}
        ,
        \\{"type":"bitmap","width":2,"height":1,"tiles":0}
        ,
        \\{"type":"bitmap","width":2,"height":1,"tiles":1025}
        ,
    };
    for (invalid) |json| try std.testing.expectEqual(@as(?BitmapMetadata, null), parseBitmapMetadata(json));
}

test "bitmap metadata returns null when bounded scratch is exhausted" {
    const json = "{\"type\":\"bitmap\",\"width\":2,\"height\":1,\"custom\":\"" ++
        ("x" ** (64 * 1024)) ++ "\"}";
    try std.testing.expectEqual(@as(?BitmapMetadata, null), parseBitmapMetadata(json));
}

test "manifest parser keeps bounded bitmap assets and their geometry" {
    const source =
        "100 4096 maps/forest {\"height\":16, \"tiles\":16, \"width\":16, \"type\":\"bitmap\"}\n" ++
        "101 23 game.lua {\"type\":\"lua_code\"}\n" ++
        "102 64 props/tree { \"type\" : \"bitmap\", \"width\" : 8, \"height\" : 8 }\n" ++
        "103 64 ../outside {\"type\":\"bitmap\",\"width\":8,\"height\":8}\n" ++
        "104 64 props/tree {\"type\":\"bitmap\",\"width\":8,\"height\":8}\n" ++
        "105 64 props\\tree {\"type\":\"bitmap\",\"width\":8,\"height\":8}\n" ++
        "106 64 props//tree {\"type\":\"bitmap\",\"width\":8,\"height\":8}\n" ++
        "107 64 props/whitespace {\"type\"\r:\r\"bitmap\",\"width\"\r:\r8,\"height\"\r:\r8}\n";
    const catalog = parseManifest(source);
    try std.testing.expectEqual(@as(u8, 3), catalog.count);
    try std.testing.expectEqualStrings("maps/forest", catalog.items[0].name());
    try std.testing.expectEqual(@as(u16, 16), catalog.items[0].tiles);
    try std.testing.expectEqual(@as(?usize, 0), catalog.find("maps/forest"));
    try std.testing.expectEqual(@as(?usize, 1), catalog.firstTileSize(8));
    try std.testing.expectEqualStrings("props/whitespace", catalog.items[2].name());
}

test "Lupi tileset compatibility enforces official size and tile bounds" {
    const safe = BitmapAsset{
        .width = 16,
        .height = 16,
        .tiles = 16,
        .byte_len = 4096,
    };
    try std.testing.expect(safe.lupiCompatible(16, 15));
    try std.testing.expect(!safe.lupiCompatible(16, 16));
    try std.testing.expect(!safe.lupiCompatible(8, 15));
    var oversized = safe;
    oversized.tiles = 193;
    oversized.byte_len = 16 * 16 * 193;
    try std.testing.expect(!oversized.lupiCompatible(16, 0));
    var truncated = safe;
    truncated.byte_len -= 1;
    try std.testing.expect(!truncated.lupiCompatible(16, 0));
}

test "palette parser honors Lua indexes and Lupi RGB555 order" {
    const palette = parsePaletteLua(
        "Palette = {\n  [1] = 0x7C00,\n  [2] = 0x03E0,\n  [3] = 0x001F,\n}\n",
    );
    try std.testing.expect(palette.exact());
    try std.testing.expectEqual(@as(u16, 3), palette.defined_count);
    try std.testing.expectEqual([3]u8{ 255, 0, 0 }, palette.colors[0]);
    try std.testing.expectEqual([3]u8{ 0, 255, 0 }, palette.colors[1]);
    try std.testing.expectEqual([3]u8{ 0, 0, 255 }, palette.colors[2]);
}
