const std = @import("std");

pub const target_simulation_hz: f64 = 60.0;
pub const layer_count_max: usize = 256;
const layer_name_size_max: usize = 64;

pub const RenderOptions = struct {
    maps: bool = true,
    sprites: bool = true,
    primitives: bool = true,
    text: bool = true,
    patterns: bool = true,
    clipping: bool = true,
    camera: bool = true,
};

pub const DrawCounters = struct {
    clears: u32 = 0,
    primitives: u32 = 0,
    sprites: u32 = 0,
    maps: u32 = 0,
    map_layers_drawn: u32 = 0,
    map_layers_hidden: u32 = 0,
    text: u32 = 0,
};

const Layer = struct {
    name: [layer_name_size_max]u8 = .{0} ** layer_name_size_max,
    name_length: u8 = 0,
    source_length: usize = 0,
    hash: u64 = 0,
    enabled: bool = true,

    fn set(self: *Layer, source: []const u8, source_hash: u64) void {
        const copied = @min(source.len, self.name.len);
        @memcpy(self.name[0..copied], source[0..copied]);
        self.name_length = @intCast(copied);
        self.source_length = source.len;
        self.hash = source_hash;
        self.enabled = true;
    }

    pub fn displayName(self: *const Layer) []const u8 {
        return self.name[0..self.name_length];
    }

    fn matches(self: *const Layer, source: []const u8, source_hash: u64) bool {
        if (self.source_length != source.len) return false;
        if (self.hash != source_hash) return false;
        return std.mem.eql(u8, self.displayName(), source[0..self.name_length]);
    }
};

pub const State = struct {
    show_stats: bool = false,
    show_commands: bool = false,
    render: RenderOptions = .{},
    draw_current: DrawCounters = .{},
    draw_last: DrawCounters = .{},

    frames_total: u64 = 0,
    simulation_updates_total: u64 = 0,
    fps: f64 = 0,
    simulation_hz: f64 = 0,
    frame_ms_average: f64 = 0,
    frame_ms_max: f64 = 0,
    work_ms_average: f64 = 0,
    update_ms_average: f64 = 0,
    lua_memory_bytes: u64 = 0,
    output_width: i32 = 0,
    output_height: i32 = 0,
    viewport_scale: i32 = 1,

    layers: [layer_count_max]Layer = .{Layer{}} ** layer_count_max,
    layer_count: usize = 0,
    selected_layer: usize = 0,

    sample_start_counter: u64 = 0,
    sample_frames: u64 = 0,
    sample_updates: u64 = 0,
    sample_frame_counts: u64 = 0,
    sample_frame_counts_max: u64 = 0,
    sample_work_counts: u64 = 0,
    sample_update_counts: u64 = 0,

    pub fn resetGame(self: *State) void {
        const show_stats = self.show_stats;
        const show_commands = self.show_commands;
        const render = self.render;
        self.* = .{
            .show_stats = show_stats,
            .show_commands = show_commands,
            .render = render,
        };
    }

    pub fn resetRendering(self: *State) void {
        self.render = .{};
        for (self.layers[0..self.layer_count]) |*layer| layer.enabled = true;
    }

    pub fn beginFrame(self: *State) void {
        self.draw_current = .{};
    }

    pub fn captureDrawCounters(self: *State) void {
        self.draw_last = self.draw_current;
    }

    pub fn finishFrame(
        self: *State,
        frame_start: u64,
        work_end: u64,
        frame_end: u64,
        update_counts: u64,
        simulation_updated: bool,
        performance_frequency: u64,
    ) bool {
        std.debug.assert(performance_frequency > 0);
        std.debug.assert(work_end >= frame_start);
        std.debug.assert(frame_end >= frame_start);

        const frame_counts = frame_end - frame_start;
        const work_counts = work_end - frame_start;
        self.frames_total += 1;
        self.sample_frames += 1;
        self.sample_frame_counts += frame_counts;
        self.sample_frame_counts_max = @max(self.sample_frame_counts_max, frame_counts);
        self.sample_work_counts += work_counts;
        if (simulation_updated) {
            self.simulation_updates_total += 1;
            self.sample_updates += 1;
            self.sample_update_counts += update_counts;
        }

        if (self.sample_start_counter == 0) self.sample_start_counter = frame_start;
        const sample_counts = frame_end - self.sample_start_counter;
        const sample_interval_counts = @max(performance_frequency / 2, 1);
        if (sample_counts < sample_interval_counts) return false;

        const frequency: f64 = @floatFromInt(performance_frequency);
        const elapsed_seconds = @as(f64, @floatFromInt(sample_counts)) / frequency;
        const frame_count: f64 = @floatFromInt(self.sample_frames);
        self.fps = frame_count / elapsed_seconds;
        self.simulation_hz = @as(f64, @floatFromInt(self.sample_updates)) / elapsed_seconds;
        self.frame_ms_average = @as(f64, @floatFromInt(self.sample_frame_counts)) * 1000.0 /
            frequency / frame_count;
        self.frame_ms_max = @as(f64, @floatFromInt(self.sample_frame_counts_max)) * 1000.0 /
            frequency;
        self.work_ms_average = @as(f64, @floatFromInt(self.sample_work_counts)) * 1000.0 /
            frequency / frame_count;
        self.update_ms_average = if (self.sample_updates > 0)
            @as(f64, @floatFromInt(self.sample_update_counts)) * 1000.0 / frequency /
                @as(f64, @floatFromInt(self.sample_updates))
        else
            0;

        self.sample_start_counter = frame_end;
        self.sample_frames = 0;
        self.sample_updates = 0;
        self.sample_frame_counts = 0;
        self.sample_frame_counts_max = 0;
        self.sample_work_counts = 0;
        self.sample_update_counts = 0;
        return true;
    }

    pub fn setViewport(self: *State, output_width: i32, output_height: i32) void {
        self.output_width = output_width;
        self.output_height = output_height;
        const horizontal_scale = @divTrunc(output_width, 480);
        const vertical_scale = @divTrunc(output_height, 270);
        self.viewport_scale = @max(@min(horizontal_scale, vertical_scale), 1);
    }

    pub fn shouldDrawMapLayer(self: *State, name: []const u8) bool {
        self.draw_current.map_layers_drawn += 1;
        const layer_index = self.trackLayer(name);
        const enabled = self.render.maps and
            (layer_index == null or self.layers[layer_index.?].enabled);
        if (!enabled) {
            self.draw_current.map_layers_drawn -= 1;
            self.draw_current.map_layers_hidden += 1;
        }
        return enabled;
    }

    pub fn selectNextLayer(self: *State) void {
        if (self.layer_count == 0) return;
        self.selected_layer = (self.selected_layer + 1) % self.layer_count;
    }

    pub fn toggleSelectedLayer(self: *State) void {
        if (self.layer_count == 0) return;
        self.layers[self.selected_layer].enabled = !self.layers[self.selected_layer].enabled;
    }

    pub fn selectedLayer(self: *const State) ?*const Layer {
        if (self.layer_count == 0) return null;
        return &self.layers[self.selected_layer];
    }

    fn trackLayer(self: *State, name: []const u8) ?usize {
        const name_hash = std.hash.Wyhash.hash(0, name);
        for (self.layers[0..self.layer_count], 0..) |*layer, index| {
            if (layer.matches(name, name_hash)) return index;
        }
        if (self.layer_count == self.layers.len) return null;
        const index = self.layer_count;
        self.layers[index].set(name, name_hash);
        self.layer_count += 1;
        return index;
    }
};

test "map layers are tracked and toggled without allocation" {
    var state = State{};
    try std.testing.expect(state.shouldDrawMapLayer("background"));
    try std.testing.expectEqual(@as(usize, 1), state.layer_count);
    state.toggleSelectedLayer();
    try std.testing.expect(!state.shouldDrawMapLayer("background"));
    try std.testing.expectEqual(@as(u32, 1), state.draw_current.map_layers_hidden);

    try std.testing.expect(state.shouldDrawMapLayer("foreground"));
    state.selectNextLayer();
    try std.testing.expectEqualStrings("foreground", state.selectedLayer().?.displayName());
    state.resetRendering();
    try std.testing.expect(state.shouldDrawMapLayer("background"));
}

test "frame sampler reports presentation and simulation frequencies" {
    var state = State{};
    try std.testing.expect(!state.finishFrame(100, 105, 116, 3, true, 1000));
    try std.testing.expect(state.finishFrame(116, 121, 616, 4, false, 1000));
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 0.516), state.fps, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / 0.516), state.simulation_hz, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), state.update_ms_average, 0.001);
}
