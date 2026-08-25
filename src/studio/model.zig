const std = @import("std");

pub const schema_version: u16 = 1;
pub const layer_count: usize = 4;
pub const max_dimension: u16 = 64;
pub const empty_tile: u16 = std.math.maxInt(u16);
pub const max_tile_id: u16 = 1023;
pub const max_issues: usize = 16;
pub const max_history: usize = 128;
const magic = "ELISWRLD";
const checksum_len = 4;
const max_file_bytes: usize = 256 * 1024;
const no_point: u32 = std.math.maxInt(u32);

pub const layer_names = [_][]const u8{ "background", "terrain", "objects", "foreground" };

pub const Point = struct {
    x: u16,
    y: u16,
};

pub const Project = struct {
    allocator: std.mem.Allocator,
    width: u16,
    height: u16,
    tile_size: u16,
    tileset: [128]u8 = .{0} ** 128,
    tileset_len: u8 = 0,
    tiles: []u16,
    solid: []u8,
    spawn: ?Point = null,
    goal: ?Point = null,
    revision: u64 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        width: u16,
        height: u16,
        tile_size: u16,
        tileset_name: []const u8,
    ) !Project {
        try validateDimensions(width, height, tile_size);
        if (tileset_name.len == 0 or tileset_name.len > 127) return error.InvalidTilesetName;
        const cells = @as(usize, width) * height;
        const tiles = try allocator.alloc(u16, cells * layer_count);
        errdefer allocator.free(tiles);
        const solid = try allocator.alloc(u8, cells);
        @memset(tiles, empty_tile);
        @memset(solid, 0);
        var result = Project{
            .allocator = allocator,
            .width = width,
            .height = height,
            .tile_size = tile_size,
            .tiles = tiles,
            .solid = solid,
        };
        result.setTilesetName(tileset_name);
        return result;
    }

    pub fn initStarter(
        allocator: std.mem.Allocator,
        width: u16,
        height: u16,
        tile_size: u16,
        tileset_name: []const u8,
    ) !Project {
        var result = try Project.init(allocator, width, height, tile_size, tileset_name);
        const cells = result.cellCount();
        @memset(result.tiles[0..cells], 0);
        for (0..height) |y| {
            for (0..width) |x| {
                if (x == 0 or y == 0 or x + 1 == width or y + 1 == height) {
                    result.solid[result.cellIndex(@intCast(x), @intCast(y))] = 1;
                }
            }
        }
        result.spawn = .{ .x = 1, .y = height / 2 };
        result.goal = .{ .x = width - 2, .y = height / 2 };
        return result;
    }

    pub fn deinit(self: *Project) void {
        self.allocator.free(self.tiles);
        self.allocator.free(self.solid);
        self.* = undefined;
    }

    pub fn cellCount(self: Project) usize {
        return @as(usize, self.width) * self.height;
    }

    pub fn cellIndex(self: Project, x: u16, y: u16) usize {
        std.debug.assert(x < self.width and y < self.height);
        return @as(usize, y) * self.width + x;
    }

    pub fn layerCells(self: Project, layer: usize) []u16 {
        std.debug.assert(layer < layer_count);
        const cells = self.cellCount();
        return self.tiles[layer * cells ..][0..cells];
    }

    pub fn tilesetName(self: *const Project) []const u8 {
        return self.tileset[0..self.tileset_len];
    }

    pub fn setTilesetName(self: *Project, name: []const u8) void {
        std.debug.assert(name.len > 0 and name.len <= self.tileset.len - 1);
        @memset(&self.tileset, 0);
        @memcpy(self.tileset[0..name.len], name);
        self.tileset_len = @intCast(name.len);
    }
};

pub const ChangeKind = enum(u8) { tile, solid, spawn, goal };

pub const Change = struct {
    kind: ChangeKind,
    layer: u8 = 0,
    index: u32 = 0,
    before: u32,
    after: u32,

    fn sameTarget(a: Change, b: Change) bool {
        return a.kind == b.kind and a.layer == b.layer and a.index == b.index;
    }
};

pub const Command = struct {
    allocator: std.mem.Allocator,
    changes: []Change,

    pub fn deinit(self: *Command) void {
        self.allocator.free(self.changes);
        self.* = undefined;
    }

    pub fn applyBefore(self: Command, project: *Project) void {
        var index = self.changes.len;
        while (index > 0) {
            index -= 1;
            applyValue(project, self.changes[index], self.changes[index].before);
        }
    }

    pub fn applyAfter(self: Command, project: *Project) void {
        for (self.changes) |change| applyValue(project, change, change.after);
    }
};

pub const CommandBuilder = struct {
    allocator: std.mem.Allocator,
    changes: std.ArrayList(Change) = .empty,

    pub fn init(allocator: std.mem.Allocator) CommandBuilder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *CommandBuilder) void {
        self.changes.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn empty(self: CommandBuilder) bool {
        return self.changes.items.len == 0;
    }

    pub fn setTile(self: *CommandBuilder, project: *Project, layer: u8, index: usize, tile: u16) !void {
        if (layer >= layer_count or index >= project.cellCount() or tile > max_tile_id and tile != empty_tile) {
            return error.InvalidEditorChange;
        }
        const offset = @as(usize, layer) * project.cellCount() + index;
        try self.record(project, .{
            .kind = .tile,
            .layer = layer,
            .index = @intCast(index),
            .before = project.tiles[offset],
            .after = tile,
        });
    }

    pub fn setSolid(self: *CommandBuilder, project: *Project, index: usize, solid: bool) !void {
        if (index >= project.cellCount()) return error.InvalidEditorChange;
        try self.record(project, .{
            .kind = .solid,
            .index = @intCast(index),
            .before = project.solid[index],
            .after = @intFromBool(solid),
        });
    }

    pub fn setSpawn(self: *CommandBuilder, project: *Project, point: ?Point) !void {
        if (point) |value| if (!pointInBounds(project.*, value)) return error.InvalidEditorChange;
        try self.record(project, .{
            .kind = .spawn,
            .before = encodePoint(project.*, project.spawn),
            .after = encodePoint(project.*, point),
        });
    }

    pub fn setGoal(self: *CommandBuilder, project: *Project, point: ?Point) !void {
        if (point) |value| if (!pointInBounds(project.*, value)) return error.InvalidEditorChange;
        try self.record(project, .{
            .kind = .goal,
            .before = encodePoint(project.*, project.goal),
            .after = encodePoint(project.*, point),
        });
    }

    pub fn floodFill(
        self: *CommandBuilder,
        project: *Project,
        layer: u8,
        start: usize,
        replacement: u16,
    ) !void {
        if (layer >= layer_count or start >= project.cellCount()) return error.InvalidEditorChange;
        const cells = project.layerCells(layer);
        const target = cells[start];
        if (target == replacement) return;
        var queue: [@as(usize, max_dimension) * max_dimension]u16 = undefined;
        var visited: [@as(usize, max_dimension) * max_dimension]bool = .{false} ** (@as(usize, max_dimension) * max_dimension);
        var read: usize = 0;
        var write: usize = 1;
        queue[0] = @intCast(start);
        visited[start] = true;
        while (read < write) : (read += 1) {
            const index: usize = queue[read];
            if (cells[index] != target) continue;
            try self.setTile(project, layer, index, replacement);
            const x = index % project.width;
            const y = index / project.width;
            const neighbors = [_]?usize{
                if (x > 0) index - 1 else null,
                if (x + 1 < project.width) index + 1 else null,
                if (y > 0) index - project.width else null,
                if (y + 1 < project.height) index + project.width else null,
            };
            for (neighbors) |maybe_next| if (maybe_next) |next| {
                if (!visited[next] and cells[next] == target) {
                    visited[next] = true;
                    queue[write] = @intCast(next);
                    write += 1;
                }
            };
        }
    }

    pub fn finish(self: *CommandBuilder) !?Command {
        if (self.empty()) return null;
        const owned = try self.changes.toOwnedSlice(self.allocator);
        return .{ .allocator = self.allocator, .changes = owned };
    }

    fn record(self: *CommandBuilder, project: *Project, change: Change) !void {
        if (change.before == change.after) return;
        for (self.changes.items) |*existing| {
            if (existing.sameTarget(change)) {
                existing.after = change.after;
                applyValue(project, change, change.after);
                project.revision +%= 1;
                return;
            }
        }
        try self.changes.append(self.allocator, change);
        applyValue(project, change, change.after);
        project.revision +%= 1;
    }
};

pub const History = struct {
    allocator: std.mem.Allocator,
    undo_stack: std.ArrayList(Command) = .empty,
    redo_stack: std.ArrayList(Command) = .empty,

    pub fn init(allocator: std.mem.Allocator) History {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *History) void {
        self.clearCommands(&self.undo_stack);
        self.clearCommands(&self.redo_stack);
        self.undo_stack.deinit(self.allocator);
        self.redo_stack.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn commit(self: *History, command: Command) !void {
        self.clearCommands(&self.redo_stack);
        while (self.undo_stack.items.len >= max_history) {
            var oldest = self.undo_stack.orderedRemove(0);
            oldest.deinit();
        }
        try self.undo_stack.append(self.allocator, command);
    }

    pub fn undo(self: *History, project: *Project) !bool {
        var command = self.undo_stack.pop() orelse return false;
        errdefer command.deinit();
        try self.redo_stack.ensureUnusedCapacity(self.allocator, 1);
        command.applyBefore(project);
        project.revision +%= 1;
        self.redo_stack.appendAssumeCapacity(command);
        return true;
    }

    pub fn redo(self: *History, project: *Project) !bool {
        var command = self.redo_stack.pop() orelse return false;
        errdefer command.deinit();
        try self.undo_stack.ensureUnusedCapacity(self.allocator, 1);
        command.applyAfter(project);
        project.revision +%= 1;
        self.undo_stack.appendAssumeCapacity(command);
        return true;
    }

    fn clearCommands(self: *History, list: *std.ArrayList(Command)) void {
        _ = self;
        for (list.items) |*command| command.deinit();
        list.clearRetainingCapacity();
    }
};

pub const Severity = enum { warning, @"error" };
pub const IssueKind = enum {
    missing_spawn,
    missing_goal,
    spawn_blocked,
    goal_blocked,
    goal_unreachable,
    empty_background,
};
pub const Issue = struct { severity: Severity, kind: IssueKind };

pub const ValidationReport = struct {
    issues: [max_issues]Issue = undefined,
    count: u8 = 0,
    error_count: u8 = 0,
    warning_count: u8 = 0,
    reachable_cells: u16 = 0,

    pub fn valid(self: ValidationReport) bool {
        return self.error_count == 0;
    }

    fn add(self: *ValidationReport, issue: Issue) void {
        if (issue.severity == .@"error") self.error_count +|= 1 else self.warning_count +|= 1;
        if (self.count < self.issues.len) {
            self.issues[self.count] = issue;
            self.count += 1;
        }
    }
};

pub fn validate(project: Project) ValidationReport {
    var report = ValidationReport{};
    if (project.spawn == null) report.add(.{ .severity = .@"error", .kind = .missing_spawn });
    if (project.goal == null) report.add(.{ .severity = .@"error", .kind = .missing_goal });
    var has_background = false;
    for (project.layerCells(0)) |tile| if (tile != empty_tile) {
        has_background = true;
        break;
    };
    if (!has_background) report.add(.{ .severity = .warning, .kind = .empty_background });
    if (project.spawn) |spawn| {
        if (project.solid[project.cellIndex(spawn.x, spawn.y)] != 0) {
            report.add(.{ .severity = .@"error", .kind = .spawn_blocked });
        }
    }
    if (project.goal) |goal| {
        if (project.solid[project.cellIndex(goal.x, goal.y)] != 0) {
            report.add(.{ .severity = .@"error", .kind = .goal_blocked });
        }
    }
    if (project.spawn) |spawn| if (project.goal) |goal| {
        var visited: [@as(usize, max_dimension) * max_dimension]bool = .{false} ** (@as(usize, max_dimension) * max_dimension);
        var queue: [@as(usize, max_dimension) * max_dimension]u16 = undefined;
        const start = project.cellIndex(spawn.x, spawn.y);
        const target = project.cellIndex(goal.x, goal.y);
        var read: usize = 0;
        var write: usize = 0;
        if (project.solid[start] == 0) {
            visited[start] = true;
            queue[write] = @intCast(start);
            write += 1;
        }
        while (read < write) : (read += 1) {
            const index: usize = queue[read];
            const x = index % project.width;
            const y = index / project.width;
            const neighbors = [_]?usize{
                if (x > 0) index - 1 else null,
                if (x + 1 < project.width) index + 1 else null,
                if (y > 0) index - project.width else null,
                if (y + 1 < project.height) index + project.width else null,
            };
            for (neighbors) |maybe_next| if (maybe_next) |next| {
                if (!visited[next] and project.solid[next] == 0) {
                    visited[next] = true;
                    queue[write] = @intCast(next);
                    write += 1;
                }
            };
        }
        report.reachable_cells = @intCast(write);
        if (!visited[target]) report.add(.{ .severity = .@"error", .kind = .goal_unreachable });
    };
    return report;
}

pub fn encode(allocator: std.mem.Allocator, project: Project) ![]u8 {
    const cell_count = project.cellCount();
    const payload_len = project.tileset_len + project.tiles.len * 2 + project.solid.len;
    const fixed_len = magic.len + 2 + 2 + 2 + 2 + 1 + 4 + 4 + 8;
    const total_len = fixed_len + payload_len + checksum_len;
    if (total_len > max_file_bytes) return error.ProjectTooLarge;
    const bytes = try allocator.alloc(u8, total_len);
    errdefer allocator.free(bytes);
    var cursor: usize = 0;
    putBytes(bytes, &cursor, magic);
    putU16(bytes, &cursor, schema_version);
    putU16(bytes, &cursor, project.width);
    putU16(bytes, &cursor, project.height);
    putU16(bytes, &cursor, project.tile_size);
    putU8(bytes, &cursor, project.tileset_len);
    putU32(bytes, &cursor, encodePoint(project, project.spawn));
    putU32(bytes, &cursor, encodePoint(project, project.goal));
    putU64(bytes, &cursor, project.revision);
    putBytes(bytes, &cursor, project.tilesetName());
    for (project.tiles) |tile| putU16(bytes, &cursor, tile);
    putBytes(bytes, &cursor, project.solid[0..cell_count]);
    putU32(bytes, &cursor, checksum(bytes[0..cursor]));
    std.debug.assert(cursor == bytes.len);
    return bytes;
}

pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !Project {
    if (bytes.len < magic.len + 29 or bytes.len > max_file_bytes) return error.InvalidWorldProject;
    if (!std.mem.eql(u8, bytes[0..magic.len], magic)) return error.InvalidWorldProject;
    if (checksum(bytes[0 .. bytes.len - checksum_len]) != readU32At(bytes, bytes.len - checksum_len)) {
        return error.InvalidWorldChecksum;
    }
    var cursor: usize = magic.len;
    if (try takeU16(bytes, &cursor) != schema_version) return error.UnsupportedWorldVersion;
    const width = try takeU16(bytes, &cursor);
    const height = try takeU16(bytes, &cursor);
    const tile_size = try takeU16(bytes, &cursor);
    try validateDimensions(width, height, tile_size);
    const tileset_len = try takeU8(bytes, &cursor);
    if (tileset_len == 0 or tileset_len > 127) return error.InvalidWorldProject;
    const spawn_value = try takeU32(bytes, &cursor);
    const goal_value = try takeU32(bytes, &cursor);
    const revision = try takeU64(bytes, &cursor);
    const cell_count = @as(usize, width) * height;
    const expected = cursor + tileset_len + cell_count * layer_count * 2 + cell_count + checksum_len;
    if (expected != bytes.len) return error.InvalidWorldProject;
    const tileset_name = try takeBytes(bytes, &cursor, tileset_len);
    var project = try Project.init(allocator, width, height, tile_size, tileset_name);
    errdefer project.deinit();
    for (project.tiles) |*tile| {
        tile.* = try takeU16(bytes, &cursor);
        if (tile.* > max_tile_id and tile.* != empty_tile) return error.InvalidWorldProject;
    }
    for (project.solid) |*value| {
        value.* = try takeU8(bytes, &cursor);
        if (value.* > 1) return error.InvalidWorldProject;
    }
    project.spawn = try decodePoint(project, spawn_value);
    project.goal = try decodePoint(project, goal_value);
    project.revision = revision;
    if (cursor != bytes.len - checksum_len) return error.InvalidWorldProject;
    return project;
}

pub fn exportLua(allocator: std.mem.Allocator, project: Project) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;
    try writer.print("-- Generated by ELIS Studio. Edit the .elisworld source, not this file.\nreturn {{\n  metadata = {{ width = {}, height = {}, tile_size = {} }},\n", .{
        project.width,
        project.height,
        project.tile_size,
    });
    try writer.writeAll("  lupi_metadata = { editor = \"ELIS Studio\", schema = 1");
    if (project.spawn) |spawn| try writer.print(", spawn = {{ x = {}, y = {} }}", .{ spawn.x, spawn.y });
    if (project.goal) |goal| try writer.print(", goal = {{ x = {}, y = {} }}", .{ goal.x, goal.y });
    try writer.writeAll(", solid = {");
    for (project.solid, 0..) |value, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.print("{}", .{value});
    }
    try writer.writeAll("} },\n  tilesets = {");
    for (layer_names, 0..) |name, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s} = ", .{name});
        try writeLuaString(writer, project.tilesetName());
    }
    try writer.writeAll(" },\n  layers = { ");
    for (layer_names, 0..) |name, index| {
        if (index != 0) try writer.writeAll(", ");
        try writeLuaString(writer, name);
    }
    try writer.writeAll(" },\n");
    for (layer_names, 0..) |name, layer| {
        try writer.print("  {s} = {{", .{name});
        for (project.layerCells(layer), 0..) |tile, index| {
            if (index != 0) try writer.writeByte(',');
            if (tile == empty_tile) try writer.writeAll("-1") else try writer.print("{}", .{tile});
        }
        try writer.writeAll("},\n");
    }
    try writer.writeAll("}\n");
    return output.toOwnedSlice();
}

pub fn save(path: []const u8, project: Project) !void {
    const bytes = try encode(std.heap.page_allocator, project);
    defer std.heap.page_allocator.free(bytes);
    try atomicWrite(path, bytes);
}

pub fn exportLuaFile(path: []const u8, project: Project) !void {
    const bytes = try exportLua(std.heap.page_allocator, project);
    defer std.heap.page_allocator.free(bytes);
    try atomicWrite(path, bytes);
}

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Project {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_file_bytes));
    defer allocator.free(bytes);
    return decode(allocator, bytes);
}

fn atomicWrite(path: []const u8, bytes: []const u8) !void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, std.fs.path.dirname(path) orelse ".");
    var temporary_buffer: [1024]u8 = undefined;
    const temporary = try std.fmt.bufPrint(&temporary_buffer, "{s}.tmp", .{path});
    {
        const file = try cwd.createFile(io, temporary, .{ .truncate = true });
        errdefer file.close(io);
        try file.writeStreamingAll(io, bytes);
        try file.sync(io);
        file.close(io);
    }
    try cwd.rename(temporary, cwd, path, io);
}

fn validateDimensions(width: u16, height: u16, tile_size: u16) !void {
    if (width < 4 or height < 4 or width > max_dimension or height > max_dimension or
        tile_size == 0 or tile_size > 64) return error.InvalidWorldDimensions;
}

fn pointInBounds(project: Project, point: Point) bool {
    return point.x < project.width and point.y < project.height;
}

fn encodePoint(project: Project, point: ?Point) u32 {
    const value = point orelse return no_point;
    return @intCast(project.cellIndex(value.x, value.y));
}

fn decodePoint(project: Project, value: u32) !?Point {
    if (value == no_point) return null;
    if (value >= project.cellCount()) return error.InvalidWorldProject;
    return .{ .x = @intCast(value % project.width), .y = @intCast(value / project.width) };
}

fn applyValue(project: *Project, change: Change, value: u32) void {
    switch (change.kind) {
        .tile => project.tiles[@as(usize, change.layer) * project.cellCount() + change.index] = @intCast(value),
        .solid => project.solid[change.index] = @intCast(value),
        .spawn => project.spawn = decodeKnownPoint(project.*, value),
        .goal => project.goal = decodeKnownPoint(project.*, value),
    }
}

fn decodeKnownPoint(project: Project, value: u32) ?Point {
    if (value == no_point) return null;
    std.debug.assert(value < project.cellCount());
    return .{ .x = @intCast(value % project.width), .y = @intCast(value / project.width) };
}

fn writeLuaString(writer: *std.Io.Writer, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| switch (byte) {
        '"', '\\' => {
            try writer.writeByte('\\');
            try writer.writeByte(byte);
        },
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('"');
}

fn checksum(bytes: []const u8) u32 {
    var hash: u32 = 2166136261;
    for (bytes) |byte| {
        hash ^= byte;
        hash *%= 16777619;
    }
    return hash;
}

fn putBytes(bytes: []u8, cursor: *usize, value: []const u8) void {
    @memcpy(bytes[cursor.*..][0..value.len], value);
    cursor.* += value.len;
}
fn putU8(bytes: []u8, cursor: *usize, value: u8) void {
    bytes[cursor.*] = value;
    cursor.* += 1;
}
fn putU16(bytes: []u8, cursor: *usize, value: u16) void {
    bytes[cursor.*] = @truncate(value);
    bytes[cursor.* + 1] = @truncate(value >> 8);
    cursor.* += 2;
}
fn putU32(bytes: []u8, cursor: *usize, value: u32) void {
    inline for (0..4) |index| bytes[cursor.* + index] = @truncate(value >> (index * 8));
    cursor.* += 4;
}
fn putU64(bytes: []u8, cursor: *usize, value: u64) void {
    inline for (0..8) |index| bytes[cursor.* + index] = @truncate(value >> (index * 8));
    cursor.* += 8;
}
fn takeBytes(bytes: []const u8, cursor: *usize, count: usize) ![]const u8 {
    if (cursor.* + count > bytes.len) return error.InvalidWorldProject;
    const value = bytes[cursor.*..][0..count];
    cursor.* += count;
    return value;
}
fn takeU8(bytes: []const u8, cursor: *usize) !u8 {
    if (cursor.* >= bytes.len) return error.InvalidWorldProject;
    const value = bytes[cursor.*];
    cursor.* += 1;
    return value;
}
fn takeU16(bytes: []const u8, cursor: *usize) !u16 {
    if (cursor.* + 2 > bytes.len) return error.InvalidWorldProject;
    const value = @as(u16, bytes[cursor.*]) | (@as(u16, bytes[cursor.* + 1]) << 8);
    cursor.* += 2;
    return value;
}
fn takeU32(bytes: []const u8, cursor: *usize) !u32 {
    if (cursor.* + 4 > bytes.len) return error.InvalidWorldProject;
    const value = readU32At(bytes, cursor.*);
    cursor.* += 4;
    return value;
}
fn takeU64(bytes: []const u8, cursor: *usize) !u64 {
    if (cursor.* + 8 > bytes.len) return error.InvalidWorldProject;
    var value: u64 = 0;
    inline for (0..8) |index| value |= @as(u64, bytes[cursor.* + index]) << (index * 8);
    cursor.* += 8;
    return value;
}
fn readU32At(bytes: []const u8, index: usize) u32 {
    return @as(u32, bytes[index]) |
        (@as(u32, bytes[index + 1]) << 8) |
        (@as(u32, bytes[index + 2]) << 16) |
        (@as(u32, bytes[index + 3]) << 24);
}

test "starter project validates and blocked critical path is rejected" {
    var project = try Project.initStarter(std.testing.allocator, 12, 8, 16, "tiles/world");
    defer project.deinit();
    try std.testing.expect(validate(project).valid());
    const wall_x: u16 = project.width / 2;
    for (1..project.height - 1) |y| project.solid[project.cellIndex(wall_x, @intCast(y))] = 1;
    const report = validate(project);
    try std.testing.expect(!report.valid());
    try std.testing.expectEqual(IssueKind.goal_unreachable, report.issues[report.count - 1].kind);
}

test "paint fill marker and history commands are reversible" {
    var project = try Project.initStarter(std.testing.allocator, 8, 6, 16, "tiles/world");
    defer project.deinit();
    var history = History.init(std.testing.allocator);
    defer history.deinit();
    var builder = CommandBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.setTile(&project, 1, project.cellIndex(2, 2), 7);
    try builder.setTile(&project, 1, project.cellIndex(3, 2), 7);
    try builder.setSpawn(&project, .{ .x = 2, .y = 2 });
    try history.commit((try builder.finish()).?);
    try std.testing.expectEqual(@as(u16, 7), project.layerCells(1)[project.cellIndex(2, 2)]);
    try std.testing.expect((try history.undo(&project)));
    try std.testing.expectEqual(empty_tile, project.layerCells(1)[project.cellIndex(2, 2)]);
    try std.testing.expectEqual(@as(u16, 1), project.spawn.?.x);
    try std.testing.expect((try history.redo(&project)));
    try std.testing.expectEqual(@as(u16, 2), project.spawn.?.x);
}

test "project encoding round trips and rejects corruption" {
    var project = try Project.initStarter(std.testing.allocator, 10, 7, 8, "maps/forest");
    defer project.deinit();
    project.layerCells(2)[project.cellIndex(4, 3)] = 19;
    const bytes = try encode(std.testing.allocator, project);
    defer std.testing.allocator.free(bytes);
    var decoded = try decode(std.testing.allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqualStrings(project.tilesetName(), decoded.tilesetName());
    try std.testing.expectEqual(@as(u16, 19), decoded.layerCells(2)[decoded.cellIndex(4, 3)]);
    bytes[bytes.len - 5] ^= 1;
    try std.testing.expectError(error.InvalidWorldChecksum, decode(std.testing.allocator, bytes));
}

test "Lua export preserves strict layer order and editor metadata" {
    var project = try Project.initStarter(std.testing.allocator, 6, 4, 8, "tiles/castle");
    defer project.deinit();
    const output = try exportLua(std.testing.allocator, project);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "layers = { \"background\", \"terrain\", \"objects\", \"foreground\" }") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "lupi_metadata = { editor = \"ELIS Studio\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "tiles/castle") != null);
}
