const std = @import("std");

pub const frame_width: u32 = 480;
pub const frame_height: u32 = 270;
pub const frame_rate_target_hz: u32 = 60;
pub const flash_bytes: usize = 16 * 1024 * 1024;
pub const psram_bytes: usize = 8 * 1024 * 1024;
/// Half of PSRAM remains reserved for engine, bitmap, archive, and audio data.
pub const lua_heap_bytes_max: usize = psram_bytes / 2;
pub const tileset_pixels_max: usize = 512 * 96;
pub const workshop_visual_layers: u32 = 4;
pub const tile_sample_pixels_max: u32 =
    frame_width * frame_height * workshop_visual_layers;
pub const lua_data_entries_max: u32 = 4096;
pub const lua_source_bytes_max: usize = 128 * 1024;

comptime {
    std.debug.assert(lua_heap_bytes_max < psram_bytes);
    std.debug.assert(tile_sample_pixels_max == 518_400);
    std.debug.assert(lua_source_bytes_max < lua_heap_bytes_max);
}
