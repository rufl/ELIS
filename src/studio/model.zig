const std = @import("std");
const lupi_profile = @import("lupi_profile.zig");

pub const schema_version: u16 = 4;
pub const layered_schema_version: u16 = 2;
pub const entity_schema_version: u16 = 3;
pub const legacy_schema_version: u16 = 1;
pub const layer_count: usize = 4;
pub const max_dimension: u16 = 64;
pub const empty_tile: u16 = std.math.maxInt(u16);
pub const max_tile_id: u16 = 1023;
pub const max_entity_fields: usize = 4;
pub const max_entity_name_length: usize = 31;
pub const max_entity_field_name_length: usize = 23;
pub const max_issues: usize = 16;
pub const max_history: usize = 128;
pub const lupi_frame_width = lupi_profile.frame_width;
pub const lupi_frame_height = lupi_profile.frame_height;
pub const lupi_tile_sample_pixels_max = lupi_profile.tile_sample_pixels_max;
/// Bounds generated Lua tables well below the simulator's 4 MiB game heap.
pub const lupi_lua_data_entries_max = lupi_profile.lua_data_entries_max;
pub const lupi_lua_source_bytes_max = lupi_profile.lua_source_bytes_max;
const lupi_lua_data_fixed_entries: u32 = 128;
const lupi_entity_entry_cost: u32 = 12;
const magic = "ELISWRLD";
const checksum_len = 4;
const max_file_bytes: usize = 256 * 1024;
const no_point: u32 = std.math.maxInt(u32);
comptime {
    std.debug.assert(layer_count == lupi_profile.workshop_visual_layers);
}

pub const layer_names = [_][]const u8{ "background", "terrain", "objects", "foreground" };

pub const Point = struct {
    x: u16,
    y: u16,
};

pub const ProjectTemplate = enum(u8) {
    blank,
    platformer,
    arena,
    puzzle,
};

pub const project_templates = [_]ProjectTemplate{ .blank, .platformer, .arena, .puzzle };
pub const project_template_labels = [_][]const u8{ "BLANK", "PLATFORMER", "ARENA", "PUZZLE" };
pub const project_template_descriptions = [_][]const u8{
    "OPEN CANVAS WITH START AND GOAL",
    "FLOOR, PLATFORMS, ENEMY, PICKUP",
    "BORDERED ROOM WITH COVER AND FOES",
    "CRATE, SWITCH, DOOR SCHEMA STARTER",
};

pub fn projectTemplateFromName(name: []const u8) !ProjectTemplate {
    for (project_templates) |template| {
        if (std.ascii.eqlIgnoreCase(name, @tagName(template))) return template;
    }
    return error.UnknownProjectTemplate;
}

pub const ResizeAnchor = enum(u8) {
    top_left,
    top,
    top_right,
    left,
    center,
    right,
    bottom_left,
    bottom,
    bottom_right,
};

pub const resize_anchors = [_]ResizeAnchor{
    .top_left,
    .top,
    .top_right,
    .left,
    .center,
    .right,
    .bottom_left,
    .bottom,
    .bottom_right,
};

pub const resize_anchor_labels = [_][]const u8{ "TL", "T", "TR", "L", "C", "R", "BL", "B", "BR" };

pub const ResizeReport = struct {
    changed: bool = false,
    clipped_cells: u16 = 0,
    spawn_clipped: bool = false,
    goal_clipped: bool = false,

    pub fn clipped(self: ResizeReport) bool {
        return self.clipped_cells > 0 or self.spawn_clipped or self.goal_clipped;
    }
};

pub const EntityFieldKind = enum(u8) {
    unsigned,
    toggle,
    tile,
};

pub const EntityKind = enum(u8) {
    none,
    enemy,
    pickup,
    trigger,
    decoration,
};

pub const entity_kinds = [_]EntityKind{ .enemy, .pickup, .trigger, .decoration };
pub const entity_kind_labels = [_][]const u8{ "ENEMY", "PICKUP", "TRIGGER", "DECORATION" };

const default_entity_names = [_][]const u8{ "Enemy", "Pickup", "Trigger", "Decoration" };
const default_field_names = [_][max_entity_fields][]const u8{
    .{
        "speed",
        "patrol",
        "damage",
        "",
    },
    .{
        "item",
        "amount",
        "respawn",
        "",
    },
    .{
        "target",
        "once",
        "delay",
        "",
    },
    .{
        "variant",
        "layer",
        "tint",
        "",
    },
};
const default_field_kinds = [_][max_entity_fields]EntityFieldKind{
    .{ .unsigned, .toggle, .unsigned, .unsigned },
    .{ .unsigned, .unsigned, .toggle, .unsigned },
    .{ .unsigned, .toggle, .unsigned, .unsigned },
    .{ .tile, .unsigned, .unsigned, .unsigned },
};

pub const EntitySchema = struct {
    name: []const u8,
    field_count: u8,
};

pub fn entityKindLabel(kind: EntityKind) []const u8 {
    return switch (kind) {
        .none => "NONE",
        .enemy => "ENEMY",
        .pickup => "PICKUP",
        .trigger => "TRIGGER",
        .decoration => "DECORATION",
    };
}

const stamp_capacity = @as(usize, max_dimension) * max_dimension;

/// A bounded, layer-local tile pattern for copy/paste and Mario Paint-style stamps.
pub const Stamp = struct {
    width: u16 = 0,
    height: u16 = 0,
    tiles: [stamp_capacity]u16 = .{empty_tile} ** stamp_capacity,
    smart: [stamp_capacity]u16 = .{empty_tile} ** stamp_capacity,

    pub fn valid(self: Stamp) bool {
        return self.width > 0 and self.height > 0;
    }

    pub fn capture(project: Project, layer: u8, first: Point, last: Point) !Stamp {
        if (layer >= layer_count or !pointInBounds(project, first) or !pointInBounds(project, last)) {
            return error.InvalidEditorChange;
        }
        const x_min = @min(first.x, last.x);
        const x_max = @max(first.x, last.x);
        const y_min = @min(first.y, last.y);
        const y_max = @max(first.y, last.y);
        var stamp = Stamp{
            .width = x_max - x_min + 1,
            .height = y_max - y_min + 1,
        };
        for (0..stamp.height) |y| {
            for (0..stamp.width) |x| {
                const source = project.cellIndex(x_min + @as(u16, @intCast(x)), y_min + @as(u16, @intCast(y)));
                const destination = y * stamp.width + x;
                stamp.tiles[destination] = project.layerCells(layer)[source];
                stamp.smart[destination] = project.smartCells(layer)[source];
            }
        }
        return stamp;
    }

    pub fn flipHorizontal(self: *Stamp) void {
        if (!self.valid()) return;
        for (0..self.height) |y| {
            for (0..self.width / 2) |x| {
                const left = y * self.width + x;
                const right = y * self.width + (self.width - 1 - @as(u16, @intCast(x)));
                std.mem.swap(u16, &self.tiles[left], &self.tiles[right]);
                std.mem.swap(u16, &self.smart[left], &self.smart[right]);
            }
        }
    }

    pub fn flipVertical(self: *Stamp) void {
        if (!self.valid()) return;
        for (0..self.height / 2) |y| {
            for (0..self.width) |x| {
                const top = y * self.width + x;
                const bottom = (@as(usize, self.height) - 1 - y) * self.width + x;
                std.mem.swap(u16, &self.tiles[top], &self.tiles[bottom]);
                std.mem.swap(u16, &self.smart[top], &self.smart[bottom]);
            }
        }
    }

    pub fn rotateClockwise(self: *Stamp) void {
        if (!self.valid()) return;
        var rotated_tiles: [stamp_capacity]u16 = .{empty_tile} ** stamp_capacity;
        var rotated_smart: [stamp_capacity]u16 = .{empty_tile} ** stamp_capacity;
        for (0..self.height) |y| {
            for (0..self.width) |x| {
                const source = y * self.width + x;
                const destination_x = @as(usize, self.height) - 1 - y;
                const destination_y = x;
                const destination = destination_y * self.height + destination_x;
                rotated_tiles[destination] = self.tiles[source];
                rotated_smart[destination] = self.smart[source];
            }
        }
        const previous_width = self.width;
        self.width = self.height;
        self.height = previous_width;
        self.tiles = rotated_tiles;
        self.smart = rotated_smart;
    }
};

pub const Project = struct {
    allocator: std.mem.Allocator,
    width: u16,
    height: u16,
    tile_size: u16,
    tilesets: [layer_count][128]u8 = .{.{0} ** 128} ** layer_count,
    tileset_lens: [layer_count]u8 = .{0} ** layer_count,
    tiles: []u16,
    smart: []u16,
    solid: []u8,
    entities: []u8,
    entity_fields: []u16,
    entity_schema_names: [entity_kinds.len][max_entity_name_length + 1]u8 = .{.{0} ** (max_entity_name_length + 1)} ** entity_kinds.len,
    entity_schema_name_lens: [entity_kinds.len]u8 = .{0} ** entity_kinds.len,
    entity_field_names: [entity_kinds.len][max_entity_fields][max_entity_field_name_length + 1]u8 = .{.{.{0} ** (max_entity_field_name_length + 1)} ** max_entity_fields} ** entity_kinds.len,
    entity_field_name_lens: [entity_kinds.len][max_entity_fields]u8 = .{.{0} ** max_entity_fields} ** entity_kinds.len,
    entity_field_kinds: [entity_kinds.len][max_entity_fields]EntityFieldKind = .{.{.unsigned} ** max_entity_fields} ** entity_kinds.len,
    entity_field_defaults: [entity_kinds.len][max_entity_fields]u16 = .{.{0} ** max_entity_fields} ** entity_kinds.len,
    entity_field_mins: [entity_kinds.len][max_entity_fields]u16 = .{.{0} ** max_entity_fields} ** entity_kinds.len,
    entity_field_maxes: [entity_kinds.len][max_entity_fields]u16 = .{.{std.math.maxInt(u16)} ** max_entity_fields} ** entity_kinds.len,
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
        const smart = try allocator.alloc(u16, cells * layer_count);
        errdefer allocator.free(smart);
        const solid = try allocator.alloc(u8, cells);
        errdefer allocator.free(solid);
        const entities = try allocator.alloc(u8, cells);
        errdefer allocator.free(entities);
        const entity_fields = try allocator.alloc(u16, cells * max_entity_fields);
        errdefer allocator.free(entity_fields);
        @memset(tiles, empty_tile);
        @memset(smart, empty_tile);
        @memset(solid, 0);
        @memset(entities, @intFromEnum(EntityKind.none));
        @memset(entity_fields, 0);
        var result = Project{
            .allocator = allocator,
            .width = width,
            .height = height,
            .tile_size = tile_size,
            .tiles = tiles,
            .smart = smart,
            .solid = solid,
            .entities = entities,
            .entity_fields = entity_fields,
        };
        result.setTilesetName(tileset_name);
        result.initEntitySchemas();
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
        self.allocator.free(self.smart);
        self.allocator.free(self.solid);
        self.allocator.free(self.entities);
        self.allocator.free(self.entity_fields);
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

    pub fn smartCells(self: Project, layer: usize) []u16 {
        std.debug.assert(layer < layer_count);
        const cells = self.cellCount();
        return self.smart[layer * cells ..][0..cells];
    }

    pub fn entityKindAt(self: Project, index: usize) EntityKind {
        std.debug.assert(index < self.cellCount());
        std.debug.assert(self.entities[index] <= @intFromEnum(EntityKind.decoration));
        return @enumFromInt(self.entities[index]);
    }

    pub fn entityFieldAt(self: Project, index: usize, field: usize) u16 {
        std.debug.assert(index < self.cellCount());
        std.debug.assert(field < max_entity_fields);
        return self.entity_fields[index * max_entity_fields + field];
    }

    pub fn entitySchema(self: *const Project, kind: EntityKind) EntitySchema {
        const schema_index = entitySchemaIndex(kind);
        return .{
            .name = self.entity_schema_names[schema_index][0..self.entity_schema_name_lens[schema_index]],
            .field_count = entitySchemaFieldCount(self, schema_index),
        };
    }

    pub fn entitySchemaName(self: *const Project, kind: EntityKind) []const u8 {
        return self.entitySchema(kind).name;
    }

    pub fn entityFieldCount(self: *const Project, kind: EntityKind) u8 {
        return self.entitySchema(kind).field_count;
    }

    pub fn entityFieldName(self: *const Project, kind: EntityKind, field: usize) []const u8 {
        const schema_index = entitySchemaIndex(kind);
        std.debug.assert(field < max_entity_fields);
        return self.entity_field_names[schema_index][field][0..self.entity_field_name_lens[schema_index][field]];
    }

    pub fn entityFieldKind(self: Project, kind: EntityKind, field: usize) EntityFieldKind {
        std.debug.assert(field < max_entity_fields);
        return self.entity_field_kinds[entitySchemaIndex(kind)][field];
    }

    pub fn entityFieldDefault(self: Project, kind: EntityKind, field: usize) u16 {
        std.debug.assert(field < max_entity_fields);
        return self.entity_field_defaults[entitySchemaIndex(kind)][field];
    }

    pub fn entityFieldMinimum(self: Project, kind: EntityKind, field: usize) u16 {
        std.debug.assert(field < max_entity_fields);
        return self.entity_field_mins[entitySchemaIndex(kind)][field];
    }

    pub fn entityFieldMaximum(self: Project, kind: EntityKind, field: usize) u16 {
        std.debug.assert(field < max_entity_fields);
        return self.entity_field_maxes[entitySchemaIndex(kind)][field];
    }

    pub fn setEntitySchemaName(self: *Project, kind: EntityKind, name: []const u8) !void {
        if (kind == .none or name.len == 0 or name.len > max_entity_name_length or
            !editorNameValid(name)) return error.InvalidEntitySchema;
        const schema_index = entitySchemaIndex(kind);
        @memset(&self.entity_schema_names[schema_index], 0);
        @memcpy(self.entity_schema_names[schema_index][0..name.len], name);
        self.entity_schema_name_lens[schema_index] = @intCast(name.len);
        self.revision +%= 1;
    }

    pub fn setEntityFieldSchema(
        self: *Project,
        kind: EntityKind,
        field: usize,
        name: []const u8,
        field_kind: EntityFieldKind,
        default_value: u16,
        minimum: u16,
        maximum: u16,
    ) !void {
        if (kind == .none or field >= max_entity_fields or
            name.len > max_entity_field_name_length or !editorNameValid(name) or
            minimum > maximum)
        {
            return error.InvalidEntitySchema;
        }
        const schema_index = entitySchemaIndex(kind);
        if (name.len > 0 and field > 0 and self.entity_field_name_lens[schema_index][field - 1] == 0) {
            return error.InvalidEntitySchema;
        }
        if (name.len == 0) {
            for (field + 1..max_entity_fields) |later| {
                if (self.entity_field_name_lens[schema_index][later] != 0) return error.InvalidEntitySchema;
            }
        }
        if (field_kind == .toggle and (default_value > 1 or maximum > 1)) return error.InvalidEntitySchema;
        if (field_kind == .tile and maximum > max_tile_id) return error.InvalidEntitySchema;
        if (default_value < minimum or default_value > maximum) return error.InvalidEntitySchema;
        @memset(&self.entity_field_names[schema_index][field], 0);
        @memcpy(self.entity_field_names[schema_index][field][0..name.len], name);
        self.entity_field_name_lens[schema_index][field] = @intCast(name.len);
        self.entity_field_kinds[schema_index][field] = field_kind;
        self.entity_field_defaults[schema_index][field] = default_value;
        self.entity_field_mins[schema_index][field] = minimum;
        self.entity_field_maxes[schema_index][field] = maximum;
        self.revision +%= 1;
    }

    fn initEntitySchemas(self: *Project) void {
        for (entity_kinds, 0..) |kind, schema_index| {
            self.setEntitySchemaName(kind, default_entity_names[schema_index]) catch unreachable;
            for (0..max_entity_fields) |field| {
                const name = default_field_names[schema_index][field];
                if (name.len == 0) continue;
                self.setEntityFieldSchema(
                    kind,
                    field,
                    name,
                    default_field_kinds[schema_index][field],
                    0,
                    0,
                    if (default_field_kinds[schema_index][field] == .toggle) 1 else if (default_field_kinds[schema_index][field] == .tile) max_tile_id else std.math.maxInt(u16),
                ) catch unreachable;
            }
        }
    }

    pub fn tilesetName(self: *const Project) []const u8 {
        return self.layerTilesetName(0);
    }

    pub fn setTilesetName(self: *Project, name: []const u8) void {
        for (0..layer_count) |layer| self.setLayerTilesetName(layer, name);
    }

    pub fn layerTilesetName(self: *const Project, layer: usize) []const u8 {
        std.debug.assert(layer < layer_count);
        return self.tilesets[layer][0..self.tileset_lens[layer]];
    }

    pub fn setLayerTilesetName(self: *Project, layer: usize, name: []const u8) void {
        std.debug.assert(layer < layer_count);
        std.debug.assert(name.len > 0 and name.len <= self.tilesets[layer].len - 1);
        @memset(&self.tilesets[layer], 0);
        @memcpy(self.tilesets[layer][0..name.len], name);
        self.tileset_lens[layer] = @intCast(name.len);
    }
};

fn editorNameValid(name: []const u8) bool {
    for (name) |byte| {
        if (byte < 32 or byte > 126) return false;
    }
    return true;
}

pub fn initProjectTemplate(
    allocator: std.mem.Allocator,
    width: u16,
    height: u16,
    tile_size: u16,
    tileset_name: []const u8,
    template: ProjectTemplate,
) !Project {
    var base = try Project.init(allocator, width, height, tile_size, tileset_name);
    defer base.deinit();
    return buildProjectTemplate(base, template);
}

fn buildProjectTemplate(project: Project, template: ProjectTemplate) !Project {
    var result = try Project.init(
        project.allocator,
        project.width,
        project.height,
        project.tile_size,
        project.layerTilesetName(0),
    );
    errdefer result.deinit();
    for (1..layer_count) |layer| {
        result.setLayerTilesetName(layer, project.layerTilesetName(layer));
    }
    @memset(result.layerCells(0), 0);
    result.spawn = .{ .x = 1, .y = result.height / 2 };
    result.goal = .{ .x = result.width - 2, .y = result.height / 2 };
    switch (template) {
        .blank => {},
        .platformer => buildPlatformerTemplate(&result),
        .arena => buildArenaTemplate(&result),
        .puzzle => try buildPuzzleTemplate(&result),
    }
    result.revision = project.revision +% 1;
    return result;
}

fn buildPlatformerTemplate(project: *Project) void {
    const floor_y = project.height - 1;
    for (0..project.width) |x| setTemplateWall(project, @intCast(x), floor_y);
    for (0..project.height) |y| {
        setTemplateWall(project, 0, @intCast(y));
        setTemplateWall(project, project.width - 1, @intCast(y));
    }
    if (project.height >= 6 and project.width >= 8) {
        const platform_y = project.height - 4;
        const first_start = project.width / 4;
        const first_end = @min(first_start + 3, project.width - 1);
        for (first_start..first_end) |x| setTemplateWall(project, @intCast(x), platform_y);
        const second_start = project.width / 2 + 1;
        const second_end = @min(second_start + 3, project.width - 1);
        for (second_start..second_end) |x| setTemplateWall(project, @intCast(x), platform_y - 1);
    }
    project.spawn = .{ .x = 1, .y = project.height - 2 };
    project.goal = .{ .x = project.width - 2, .y = project.height - 2 };
    setTemplateEntity(project, project.width / 2, project.height - 2, .enemy);
    setTemplateEntity(project, @max(project.width / 3, 1), @max(project.height - 3, 1), .pickup);
}

fn buildArenaTemplate(project: *Project) void {
    buildTemplateBorder(project);
    if (project.width >= 8 and project.height >= 8) {
        const center_x = project.width / 2;
        const center_y = project.height / 2;
        setTemplateWall(project, center_x - 1, center_y - 1);
        setTemplateWall(project, center_x + 1, center_y - 1);
        setTemplateWall(project, center_x - 1, center_y + 1);
        setTemplateWall(project, center_x + 1, center_y + 1);
    }
    setTemplateEntity(project, project.width / 2, 1, .enemy);
    setTemplateEntity(project, project.width / 2, project.height - 2, .enemy);
    setTemplateEntity(project, project.width / 2, project.height / 2, .pickup);
}

fn buildPuzzleTemplate(project: *Project) !void {
    buildTemplateBorder(project);
    try project.setEntitySchemaName(.enemy, "Crate");
    try project.setEntityFieldSchema(.enemy, 0, "weight", .unsigned, 1, 1, 99);
    try project.setEntityFieldSchema(.enemy, 1, "pushable", .toggle, 1, 0, 1);
    try project.setEntityFieldSchema(.enemy, 2, "sprite", .tile, 0, 0, max_tile_id);
    try project.setEntitySchemaName(.pickup, "Switch");
    try project.setEntityFieldSchema(.pickup, 0, "channel", .unsigned, 0, 0, 255);
    try project.setEntityFieldSchema(.pickup, 1, "latched", .toggle, 0, 0, 1);
    try project.setEntityFieldSchema(.pickup, 2, "", .unsigned, 0, 0, std.math.maxInt(u16));
    try project.setEntitySchemaName(.trigger, "Door");
    try project.setEntityFieldSchema(.trigger, 0, "channel", .unsigned, 0, 0, 255);
    try project.setEntityFieldSchema(.trigger, 1, "open", .toggle, 0, 0, 1);
    try project.setEntityFieldSchema(.trigger, 2, "delay", .unsigned, 0, 0, 999);
    try project.setEntitySchemaName(.decoration, "Accent");
    try project.setEntityFieldSchema(.decoration, 0, "tile", .tile, 0, 0, max_tile_id);
    try project.setEntityFieldSchema(.decoration, 1, "variant", .unsigned, 0, 0, 255);
    try project.setEntityFieldSchema(.decoration, 2, "", .unsigned, 0, 0, std.math.maxInt(u16));
    const center_x = project.width / 2;
    const center_y = project.height / 2;
    setTemplateEntity(project, @max(center_x - 1, 1), center_y, .enemy);
    setTemplateEntity(project, @min(center_x + 1, project.width - 2), center_y, .pickup);
    setTemplateEntity(project, project.width - 2, center_y, .trigger);
}

fn buildTemplateBorder(project: *Project) void {
    for (0..project.width) |x| {
        setTemplateWall(project, @intCast(x), 0);
        setTemplateWall(project, @intCast(x), project.height - 1);
    }
    for (1..project.height - 1) |y| {
        setTemplateWall(project, 0, @intCast(y));
        setTemplateWall(project, project.width - 1, @intCast(y));
    }
}

fn setTemplateWall(project: *Project, x: u16, y: u16) void {
    const index = project.cellIndex(x, y);
    project.solid[index] = 1;
    project.layerCells(1)[index] = 1;
}

fn setTemplateEntity(project: *Project, x: u16, y: u16, kind: EntityKind) void {
    const index = project.cellIndex(x, y);
    if (project.solid[index] != 0) return;
    project.entities[index] = @intFromEnum(kind);
    for (0..max_entity_fields) |field| {
        project.entity_fields[index * max_entity_fields + field] = project.entityFieldDefault(kind, field);
    }
}

fn entitySchemaIndex(kind: EntityKind) usize {
    std.debug.assert(kind != .none);
    return @as(usize, @intFromEnum(kind)) - 1;
}

fn entitySchemaFieldCount(project: *const Project, schema_index: usize) u8 {
    var count: u8 = 0;
    for (project.entity_field_name_lens[schema_index]) |length| {
        if (length > 0) count += 1;
    }
    return count;
}

fn validateEntityFieldValue(project: Project, kind: EntityKind, field: usize, value: u16) !void {
    if (kind == .none or field >= max_entity_fields) return error.InvalidEditorChange;
    const schema_index = entitySchemaIndex(kind);
    if (value < project.entity_field_mins[schema_index][field] or value > project.entity_field_maxes[schema_index][field]) {
        return error.InvalidEditorChange;
    }
}

pub const ChangeKind = enum(u8) { tile, smart, solid, entity_kind, entity_field, spawn, goal };

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

const ChangeCommand = struct {
    allocator: std.mem.Allocator,
    changes: []Change,
};

const ProjectSnapshotCommand = struct {
    allocator: std.mem.Allocator,
    before: []u8,
    after: []u8,
};

pub const Command = union(enum) {
    changes: ChangeCommand,
    snapshot: ProjectSnapshotCommand,

    pub fn deinit(self: *Command) void {
        switch (self.*) {
            .changes => |value| value.allocator.free(value.changes),
            .snapshot => |value| {
                value.allocator.free(value.before);
                value.allocator.free(value.after);
            },
        }
        self.* = undefined;
    }

    pub fn applyBefore(self: Command, project: *Project) !void {
        switch (self) {
            .changes => |value| {
                var index = value.changes.len;
                while (index > 0) {
                    index -= 1;
                    applyValue(project, value.changes[index], value.changes[index].before);
                }
            },
            .snapshot => |value| try replaceProject(project, value.before),
        }
    }

    pub fn applyAfter(self: Command, project: *Project) !void {
        switch (self) {
            .changes => |value| for (value.changes) |change| {
                applyValue(project, change, change.after);
            },
            .snapshot => |value| try replaceProject(project, value.after),
        }
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

    pub fn setRawTile(self: *CommandBuilder, project: *Project, layer: u8, index: usize, tile: u16) !void {
        try self.setSmart(project, layer, index, empty_tile);
        try self.setTile(project, layer, index, tile);
    }

    /// Applies a bounded stamp to the selected layer, preserving semantic smart terrain.
    pub fn stamp(self: *CommandBuilder, project: *Project, layer: u8, origin: Point, pattern: Stamp) !void {
        if (layer >= layer_count or !pattern.valid() or !pointInBounds(project.*, origin)) return error.InvalidEditorChange;
        const width = @min(pattern.width, project.width - origin.x);
        const height = @min(pattern.height, project.height - origin.y);
        var affected: [stamp_capacity]bool = .{false} ** stamp_capacity;
        for (0..height) |y| {
            for (0..width) |x| {
                const source = y * pattern.width + x;
                const target = project.cellIndex(origin.x + @as(u16, @intCast(x)), origin.y + @as(u16, @intCast(y)));
                if (pattern.smart[source] == empty_tile) {
                    try self.setRawTile(project, layer, target, pattern.tiles[source]);
                } else {
                    try self.setSmart(project, layer, target, pattern.smart[source]);
                    try self.setTile(project, layer, target, pattern.tiles[source]);
                }
                markAffected(project.*, &affected, target);
            }
        }
        for (affected[0..project.cellCount()], 0..) |needs_refresh, index| {
            if (needs_refresh and project.smartCells(layer)[index] != empty_tile) {
                try self.refreshSmartCell(project, layer, index);
            }
        }
    }

    pub fn drawLine(
        self: *CommandBuilder,
        project: *Project,
        layer: u8,
        first: Point,
        last: Point,
        tile: u16,
    ) !void {
        if (layer >= layer_count or !pointInBounds(project.*, first) or !pointInBounds(project.*, last)) {
            return error.InvalidEditorChange;
        }
        var x: i32 = first.x;
        var y: i32 = first.y;
        const target_x: i32 = last.x;
        const target_y: i32 = last.y;
        const delta_x: i32 = @intCast(@abs(target_x - x));
        const step_x: i32 = if (x < target_x) 1 else -1;
        const delta_y: i32 = -@as(i32, @intCast(@abs(target_y - y)));
        const step_y: i32 = if (y < target_y) 1 else -1;
        var line_error = delta_x + delta_y;
        for (0..stamp_capacity) |_| {
            try self.setRawTile(project, layer, project.cellIndex(@intCast(x), @intCast(y)), tile);
            if (x == target_x and y == target_y) break;
            const doubled_error = line_error * 2;
            if (doubled_error >= delta_y) {
                line_error += delta_y;
                x += step_x;
            }
            if (doubled_error <= delta_x) {
                line_error += delta_x;
                y += step_y;
            }
        }
    }

    pub fn drawRectangle(
        self: *CommandBuilder,
        project: *Project,
        layer: u8,
        first: Point,
        last: Point,
        tile: u16,
        filled: bool,
    ) !void {
        if (layer >= layer_count or !pointInBounds(project.*, first) or !pointInBounds(project.*, last)) {
            return error.InvalidEditorChange;
        }
        const x_min = @min(first.x, last.x);
        const x_max = @max(first.x, last.x);
        const y_min = @min(first.y, last.y);
        const y_max = @max(first.y, last.y);
        for (y_min..y_max + 1) |y| {
            for (x_min..x_max + 1) |x| {
                if (!filled and x != x_min and x != x_max and y != y_min and y != y_max) continue;
                try self.setRawTile(project, layer, project.cellIndex(@intCast(x), @intCast(y)), tile);
            }
        }
    }

    pub fn paintSmartTerrain(
        self: *CommandBuilder,
        project: *Project,
        layer: u8,
        index: usize,
        material_base: ?u16,
    ) !void {
        if (layer >= layer_count or index >= project.cellCount()) return error.InvalidEditorChange;
        if (material_base) |base| if (base > max_tile_id - 15) return error.InvalidSmartTerrainBase;
        try self.setSmart(project, layer, index, material_base orelse empty_tile);
        var affected: [5]usize = undefined;
        var count: usize = 1;
        affected[0] = index;
        const x = index % project.width;
        const y = index / project.width;
        if (x > 0) {
            affected[count] = index - 1;
            count += 1;
        }
        if (x + 1 < project.width) {
            affected[count] = index + 1;
            count += 1;
        }
        if (y > 0) {
            affected[count] = index - project.width;
            count += 1;
        }
        if (y + 1 < project.height) {
            affected[count] = index + project.width;
            count += 1;
        }
        for (affected[0..count]) |cell| try self.refreshSmartCell(project, layer, cell);
    }

    fn setSmart(self: *CommandBuilder, project: *Project, layer: u8, index: usize, base: u16) !void {
        if (layer >= layer_count or index >= project.cellCount() or base > max_tile_id - 15 and base != empty_tile) {
            return error.InvalidEditorChange;
        }
        const offset = @as(usize, layer) * project.cellCount() + index;
        try self.record(project, .{
            .kind = .smart,
            .layer = layer,
            .index = @intCast(index),
            .before = project.smart[offset],
            .after = base,
        });
    }

    fn refreshSmartCell(self: *CommandBuilder, project: *Project, layer: u8, index: usize) !void {
        const smart = project.smartCells(layer);
        const base = smart[index];
        if (base == empty_tile) {
            try self.setTile(project, layer, index, empty_tile);
            return;
        }
        const x = index % project.width;
        const y = index / project.width;
        var mask: u16 = 0;
        if (y > 0 and smart[index - project.width] == base) mask |= 1;
        if (x + 1 < project.width and smart[index + 1] == base) mask |= 2;
        if (y + 1 < project.height and smart[index + project.width] == base) mask |= 4;
        if (x > 0 and smart[index - 1] == base) mask |= 8;
        try self.setTile(project, layer, index, base + mask);
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

    pub fn setEntity(
        self: *CommandBuilder,
        project: *Project,
        index: usize,
        kind: EntityKind,
        value: u16,
    ) !void {
        if (index >= project.cellCount()) return error.InvalidEditorChange;
        if (kind != .none) try validateEntityFieldValue(project.*, kind, 0, value);
        try self.record(project, .{
            .kind = .entity_kind,
            .index = @intCast(index),
            .before = project.entities[index],
            .after = @intFromEnum(kind),
        });
        for (0..max_entity_fields) |field| {
            const field_value = if (kind == .none) 0 else if (field == 0) value else project.entityFieldDefault(kind, field);
            try self.record(project, .{
                .kind = .entity_field,
                .layer = @intCast(field),
                .index = @intCast(index),
                .before = project.entityFieldAt(index, field),
                .after = field_value,
            });
        }
    }

    pub fn setEntityField(self: *CommandBuilder, project: *Project, index: usize, field: usize, value: u16) !void {
        if (index >= project.cellCount() or field >= max_entity_fields) return error.InvalidEditorChange;
        const kind = project.entityKindAt(index);
        if (kind != .none) try validateEntityFieldValue(project.*, kind, field, value);
        try self.record(project, .{
            .kind = .entity_field,
            .layer = @intCast(field),
            .index = @intCast(index),
            .before = project.entityFieldAt(index, field),
            .after = if (kind == .none) 0 else value,
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
            try self.setRawTile(project, layer, index, replacement);
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
        return .{ .changes = .{ .allocator = self.allocator, .changes = owned } };
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

    pub fn commit(self: *History, command_value: Command) !void {
        var command = command_value;
        errdefer command.deinit();
        if (self.undo_stack.items.len < max_history) {
            try self.undo_stack.ensureUnusedCapacity(self.allocator, 1);
        }
        self.clearCommands(&self.redo_stack);
        while (self.undo_stack.items.len >= max_history) {
            var oldest = self.undo_stack.orderedRemove(0);
            oldest.deinit();
        }
        self.undo_stack.appendAssumeCapacity(command);
    }

    pub fn undo(self: *History, project: *Project) !bool {
        if (self.undo_stack.items.len == 0) return false;
        try self.redo_stack.ensureUnusedCapacity(self.allocator, 1);
        const revision = project.revision;
        try self.undo_stack.items[self.undo_stack.items.len - 1].applyBefore(project);
        project.revision = revision +% 1;
        const command = self.undo_stack.pop().?;
        self.redo_stack.appendAssumeCapacity(command);
        return true;
    }

    pub fn redo(self: *History, project: *Project) !bool {
        if (self.redo_stack.items.len == 0) return false;
        try self.undo_stack.ensureUnusedCapacity(self.allocator, 1);
        const revision = project.revision;
        try self.redo_stack.items[self.redo_stack.items.len - 1].applyAfter(project);
        project.revision = revision +% 1;
        const command = self.redo_stack.pop().?;
        self.undo_stack.appendAssumeCapacity(command);
        return true;
    }

    pub fn setLayerTilesetName(
        self: *History,
        project: *Project,
        layer: usize,
        name: []const u8,
    ) !bool {
        if (layer >= layer_count or name.len == 0 or name.len >= project.tilesets[layer].len) {
            return error.InvalidTilesetName;
        }
        if (std.mem.eql(u8, project.layerTilesetName(layer), name)) return false;
        var changed = try cloneProject(project.*);
        errdefer changed.deinit();
        changed.setLayerTilesetName(layer, name);
        changed.revision +%= 1;
        const command = try buildProjectSnapshotCommand(self.allocator, project.*, changed);
        try self.commit(command);
        replaceProjectOwned(project, changed);
        return true;
    }

    pub fn setEntitySchemaName(
        self: *History,
        project: *Project,
        kind: EntityKind,
        name: []const u8,
    ) !bool {
        if (kind == .none) return error.InvalidEntitySchema;
        if (std.mem.eql(u8, project.entitySchemaName(kind), name)) return false;
        var changed = try cloneProject(project.*);
        errdefer changed.deinit();
        try changed.setEntitySchemaName(kind, name);
        const command = try buildProjectSnapshotCommand(self.allocator, project.*, changed);
        try self.commit(command);
        replaceProjectOwned(project, changed);
        return true;
    }

    pub fn setEntityFieldSchema(
        self: *History,
        project: *Project,
        kind: EntityKind,
        field: usize,
        name: []const u8,
        field_kind: EntityFieldKind,
        default_value: u16,
        minimum: u16,
        maximum: u16,
    ) !bool {
        if (kind == .none or field >= max_entity_fields) return error.InvalidEntitySchema;
        if (std.mem.eql(u8, project.entityFieldName(kind, field), name) and
            project.entityFieldKind(kind, field) == field_kind and
            project.entityFieldDefault(kind, field) == default_value and
            project.entityFieldMinimum(kind, field) == minimum and
            project.entityFieldMaximum(kind, field) == maximum)
        {
            return false;
        }
        const was_enabled = project.entityFieldName(kind, field).len > 0;
        var changed = try cloneProject(project.*);
        errdefer changed.deinit();
        try changed.setEntityFieldSchema(
            kind,
            field,
            name,
            field_kind,
            default_value,
            minimum,
            maximum,
        );
        for (changed.entities, 0..) |raw_kind, index| {
            if (raw_kind != @intFromEnum(kind)) continue;
            const value = &changed.entity_fields[index * max_entity_fields + field];
            if (name.len == 0) {
                value.* = 0;
            } else if (!was_enabled) {
                value.* = default_value;
            } else {
                value.* = std.math.clamp(value.*, minimum, maximum);
            }
        }
        const command = try buildProjectSnapshotCommand(self.allocator, project.*, changed);
        try self.commit(command);
        replaceProjectOwned(project, changed);
        return true;
    }

    pub fn applyProjectTemplate(
        self: *History,
        project: *Project,
        template: ProjectTemplate,
    ) !void {
        var changed = try buildProjectTemplate(project.*, template);
        errdefer changed.deinit();
        const command = try buildProjectSnapshotCommand(self.allocator, project.*, changed);
        try self.commit(command);
        replaceProjectOwned(project, changed);
    }

    pub fn resize(
        self: *History,
        project: *Project,
        width: u16,
        height: u16,
        anchor: ResizeAnchor,
    ) !ResizeReport {
        try validateDimensions(width, height, project.tile_size);
        if (width == project.width and height == project.height) return .{};
        var resized = try buildResizedProject(project.*, width, height, anchor);
        errdefer resized.project.deinit();
        resized.project.revision +%= 1;
        const command = try buildProjectSnapshotCommand(self.allocator, project.*, resized.project);
        try self.commit(command);
        var previous = project.*;
        project.* = resized.project;
        previous.deinit();
        resized.report.changed = true;
        return resized.report;
    }

    fn clearCommands(self: *History, list: *std.ArrayList(Command)) void {
        _ = self;
        for (list.items) |*command| command.deinit();
        list.clearRetainingCapacity();
    }
};

const ResizedProject = struct {
    project: Project,
    report: ResizeReport,
};

fn buildProjectSnapshotCommand(allocator: std.mem.Allocator, before_project: Project, after_project: Project) !Command {
    const before = try encode(allocator, before_project);
    errdefer allocator.free(before);
    const after = try encode(allocator, after_project);
    errdefer allocator.free(after);
    return .{ .snapshot = .{ .allocator = allocator, .before = before, .after = after } };
}

pub fn analyzeResize(project: Project, width: u16, height: u16, anchor: ResizeAnchor) !ResizeReport {
    try validateDimensions(width, height, project.tile_size);
    if (width == project.width and height == project.height) return .{};
    const offset_x = resizeOffset(project.width, width, horizontalAlignment(anchor));
    const offset_y = resizeOffset(project.height, height, verticalAlignment(anchor));
    var report = ResizeReport{ .changed = true };
    for (0..project.height) |source_y| {
        for (0..project.width) |source_x| {
            const target_x = @as(i32, @intCast(source_x)) + offset_x;
            const target_y = @as(i32, @intCast(source_y)) + offset_y;
            if (target_x >= 0 and target_x < width and target_y >= 0 and target_y < height) continue;
            const source = project.cellIndex(@intCast(source_x), @intCast(source_y));
            if (cellHasContent(project, source)) report.clipped_cells +|= 1;
        }
    }
    const resized_spawn = mapResizedPoint(project.spawn, offset_x, offset_y, width, height);
    const resized_goal = mapResizedPoint(project.goal, offset_x, offset_y, width, height);
    report.spawn_clipped = project.spawn != null and resized_spawn == null;
    report.goal_clipped = project.goal != null and resized_goal == null;
    return report;
}

fn buildResizedProject(project: Project, width: u16, height: u16, anchor: ResizeAnchor) !ResizedProject {
    try validateDimensions(width, height, project.tile_size);
    var resized = try Project.init(
        project.allocator,
        width,
        height,
        project.tile_size,
        project.layerTilesetName(0),
    );
    errdefer resized.deinit();
    for (1..layer_count) |layer| {
        resized.setLayerTilesetName(layer, project.layerTilesetName(layer));
    }
    resized.entity_schema_names = project.entity_schema_names;
    resized.entity_schema_name_lens = project.entity_schema_name_lens;
    resized.entity_field_names = project.entity_field_names;
    resized.entity_field_name_lens = project.entity_field_name_lens;
    resized.entity_field_kinds = project.entity_field_kinds;
    resized.entity_field_defaults = project.entity_field_defaults;
    resized.entity_field_mins = project.entity_field_mins;
    resized.entity_field_maxes = project.entity_field_maxes;
    const offset_x = resizeOffset(project.width, width, horizontalAlignment(anchor));
    const offset_y = resizeOffset(project.height, height, verticalAlignment(anchor));
    const report = try analyzeResize(project, width, height, anchor);
    for (0..project.height) |source_y| {
        for (0..project.width) |source_x| {
            const source = project.cellIndex(@intCast(source_x), @intCast(source_y));
            const target_x = @as(i32, @intCast(source_x)) + offset_x;
            const target_y = @as(i32, @intCast(source_y)) + offset_y;
            if (target_x >= 0 and target_x < width and target_y >= 0 and target_y < height) {
                const target = resized.cellIndex(@intCast(target_x), @intCast(target_y));
                for (0..layer_count) |layer| {
                    resized.layerCells(layer)[target] = project.layerCells(layer)[source];
                    resized.smartCells(layer)[target] = project.smartCells(layer)[source];
                }
                resized.solid[target] = project.solid[source];
                resized.entities[target] = project.entities[source];
                for (0..max_entity_fields) |field| {
                    resized.entity_fields[target * max_entity_fields + field] =
                        project.entity_fields[source * max_entity_fields + field];
                }
            }
        }
    }
    resized.spawn = mapResizedPoint(project.spawn, offset_x, offset_y, width, height);
    resized.goal = mapResizedPoint(project.goal, offset_x, offset_y, width, height);
    refreshResizedSmartTerrain(&resized);
    return .{ .project = resized, .report = report };
}

const Alignment = enum { start, center, end };

fn horizontalAlignment(anchor: ResizeAnchor) Alignment {
    return switch (anchor) {
        .top_left, .left, .bottom_left => .start,
        .top, .center, .bottom => .center,
        .top_right, .right, .bottom_right => .end,
    };
}

fn verticalAlignment(anchor: ResizeAnchor) Alignment {
    return switch (anchor) {
        .top_left, .top, .top_right => .start,
        .left, .center, .right => .center,
        .bottom_left, .bottom, .bottom_right => .end,
    };
}

fn resizeOffset(old_dimension: u16, new_dimension: u16, alignment: Alignment) i32 {
    const difference = @as(i32, new_dimension) - @as(i32, old_dimension);
    return switch (alignment) {
        .start => 0,
        .center => @divTrunc(difference, 2),
        .end => difference,
    };
}

fn mapResizedPoint(point: ?Point, offset_x: i32, offset_y: i32, width: u16, height: u16) ?Point {
    const source = point orelse return null;
    const target_x = @as(i32, source.x) + offset_x;
    const target_y = @as(i32, source.y) + offset_y;
    if (target_x < 0 or target_x >= width or target_y < 0 or target_y >= height) return null;
    return .{ .x = @intCast(target_x), .y = @intCast(target_y) };
}

fn cellHasContent(project: Project, index: usize) bool {
    if (project.solid[index] != 0 or project.entityKindAt(index) != .none) return true;
    for (0..layer_count) |layer| {
        if (project.layerCells(layer)[index] != empty_tile) return true;
        if (project.smartCells(layer)[index] != empty_tile) return true;
    }
    return false;
}

fn refreshResizedSmartTerrain(project: *Project) void {
    for (0..layer_count) |layer| {
        const smart = project.smartCells(layer);
        const tiles = project.layerCells(layer);
        for (smart, 0..) |base, index| {
            if (base == empty_tile) continue;
            const x = index % project.width;
            const y = index / project.width;
            var mask: u16 = 0;
            if (y > 0 and smart[index - project.width] == base) mask |= 1;
            if (x + 1 < project.width and smart[index + 1] == base) mask |= 2;
            if (y + 1 < project.height and smart[index + project.width] == base) mask |= 4;
            if (x > 0 and smart[index - 1] == base) mask |= 8;
            tiles[index] = base + mask;
        }
    }
}

fn cloneProject(project: Project) !Project {
    const encoded = try encode(project.allocator, project);
    defer project.allocator.free(encoded);
    return decode(project.allocator, encoded);
}

fn replaceProjectOwned(project: *Project, replacement: Project) void {
    var previous = project.*;
    project.* = replacement;
    previous.deinit();
}

fn replaceProject(project: *Project, encoded: []const u8) !void {
    const replacement = try decode(project.allocator, encoded);
    replaceProjectOwned(project, replacement);
}

pub const Severity = enum { warning, @"error" };
pub const IssueKind = enum {
    missing_spawn,
    missing_goal,
    spawn_blocked,
    goal_blocked,
    goal_unreachable,
    entity_blocked,
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
    for (project.entities, 0..) |raw_kind, index| {
        if (raw_kind > @intFromEnum(EntityKind.decoration)) continue;
        const kind: EntityKind = @enumFromInt(raw_kind);
        if (kind != .none and kind != .decoration and project.solid[index] != 0) {
            report.add(.{ .severity = .warning, .kind = .entity_blocked });
            break;
        }
    }
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
    var tileset_bytes: usize = 0;
    for (project.tileset_lens) |length| tileset_bytes += length;
    const payload_len = tileset_bytes + entitySchemaEncodedSize(project) + project.tiles.len * 2 + project.smart.len * 2 +
        project.solid.len + project.entities.len + project.entity_fields.len * 2;
    const fixed_len = magic.len + 2 + 2 + 2 + 2 + layer_count + 4 + 4 + 8;
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
    for (project.tileset_lens) |length| putU8(bytes, &cursor, length);
    putU32(bytes, &cursor, encodePoint(project, project.spawn));
    putU32(bytes, &cursor, encodePoint(project, project.goal));
    putU64(bytes, &cursor, project.revision);
    for (0..layer_count) |layer| putBytes(bytes, &cursor, project.layerTilesetName(layer));
    encodeEntitySchemas(bytes, &cursor, project);
    for (project.tiles) |tile| putU16(bytes, &cursor, tile);
    for (project.smart) |base| putU16(bytes, &cursor, base);
    putBytes(bytes, &cursor, project.solid[0..cell_count]);
    putBytes(bytes, &cursor, project.entities[0..cell_count]);
    for (project.entity_fields) |value| putU16(bytes, &cursor, value);
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
    const version = try takeU16(bytes, &cursor);
    return switch (version) {
        legacy_schema_version => decodeV1(allocator, bytes, &cursor),
        layered_schema_version => decodeLayered(allocator, bytes, &cursor, false, false),
        entity_schema_version => decodeLayered(allocator, bytes, &cursor, true, false),
        schema_version => decodeLayered(allocator, bytes, &cursor, true, true),
        else => error.UnsupportedWorldVersion,
    };
}

fn decodeLayered(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    cursor: *usize,
    has_entities: bool,
    has_entity_schema: bool,
) !Project {
    const width = try takeU16(bytes, cursor);
    const height = try takeU16(bytes, cursor);
    const tile_size = try takeU16(bytes, cursor);
    try validateDimensions(width, height, tile_size);
    var tileset_lens: [layer_count]u8 = undefined;
    var tileset_bytes: usize = 0;
    for (&tileset_lens) |*length| {
        length.* = try takeU8(bytes, cursor);
        if (length.* == 0 or length.* > 127) return error.InvalidWorldProject;
        tileset_bytes += length.*;
    }
    const spawn_value = try takeU32(bytes, cursor);
    const goal_value = try takeU32(bytes, cursor);
    const revision = try takeU64(bytes, cursor);
    const cell_count = @as(usize, width) * height;
    const entity_bytes = if (has_entities)
        cell_count + if (has_entity_schema) cell_count * max_entity_fields * 2 else cell_count * 2
    else
        0;
    var tileset_names: [layer_count][]const u8 = undefined;
    for (&tileset_names, tileset_lens) |*name, length| name.* = try takeBytes(bytes, cursor, length);
    var project = try Project.init(allocator, width, height, tile_size, tileset_names[0]);
    errdefer project.deinit();
    for (tileset_names, 0..) |name, layer| project.setLayerTilesetName(layer, name);
    if (has_entity_schema) try decodeEntitySchemas(bytes, cursor, &project);
    const expected = cursor.* + cell_count * layer_count * 4 + cell_count + entity_bytes + checksum_len;
    if (expected != bytes.len) return error.InvalidWorldProject;
    for (project.tiles) |*tile| {
        tile.* = try takeU16(bytes, cursor);
        if (tile.* > max_tile_id and tile.* != empty_tile) return error.InvalidWorldProject;
    }
    for (project.smart, 0..) |*base, index| {
        base.* = try takeU16(bytes, cursor);
        if (base.* > max_tile_id - 15 and base.* != empty_tile) return error.InvalidWorldProject;
        if (base.* != empty_tile) {
            const tile = project.tiles[index];
            if (tile < base.* or tile > base.* + 15) return error.InvalidWorldProject;
        }
    }
    for (project.solid) |*value| {
        value.* = try takeU8(bytes, cursor);
        if (value.* > 1) return error.InvalidWorldProject;
    }
    if (has_entities) {
        for (project.entities) |*raw_kind| {
            raw_kind.* = try takeU8(bytes, cursor);
            if (raw_kind.* > @intFromEnum(EntityKind.decoration)) return error.InvalidWorldProject;
        }
        if (has_entity_schema) {
            for (project.entity_fields) |*value| value.* = try takeU16(bytes, cursor);
        } else {
            for (0..project.cellCount()) |index| {
                project.entity_fields[index * max_entity_fields] = try takeU16(bytes, cursor);
            }
        }
    }
    project.spawn = try decodePoint(project, spawn_value);
    project.goal = try decodePoint(project, goal_value);
    project.revision = revision;
    if (cursor.* != bytes.len - checksum_len) return error.InvalidWorldProject;
    return project;
}

fn decodeV1(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) !Project {
    const width = try takeU16(bytes, cursor);
    const height = try takeU16(bytes, cursor);
    const tile_size = try takeU16(bytes, cursor);
    try validateDimensions(width, height, tile_size);
    const tileset_len = try takeU8(bytes, cursor);
    if (tileset_len == 0 or tileset_len > 127) return error.InvalidWorldProject;
    const spawn_value = try takeU32(bytes, cursor);
    const goal_value = try takeU32(bytes, cursor);
    const revision = try takeU64(bytes, cursor);
    const cell_count = @as(usize, width) * height;
    const expected = cursor.* + tileset_len + cell_count * layer_count * 2 + cell_count + checksum_len;
    if (expected != bytes.len) return error.InvalidWorldProject;
    const tileset_name = try takeBytes(bytes, cursor, tileset_len);
    var project = try Project.init(allocator, width, height, tile_size, tileset_name);
    errdefer project.deinit();
    for (project.tiles) |*tile| {
        tile.* = try takeU16(bytes, cursor);
        if (tile.* > max_tile_id and tile.* != empty_tile) return error.InvalidWorldProject;
    }
    for (project.solid) |*value| {
        value.* = try takeU8(bytes, cursor);
        if (value.* > 1) return error.InvalidWorldProject;
    }
    project.spawn = try decodePoint(project, spawn_value);
    project.goal = try decodePoint(project, goal_value);
    project.revision = revision;
    if (cursor.* != bytes.len - checksum_len) return error.InvalidWorldProject;
    return project;
}

fn entitySchemaEncodedSize(project: Project) usize {
    var size: usize = 0;
    for (0..entity_kinds.len) |schema_index| {
        size += 1 + project.entity_schema_name_lens[schema_index];
        for (0..max_entity_fields) |field| {
            size += 1 + project.entity_field_name_lens[schema_index][field] + 1 + 2 + 2 + 2;
        }
    }
    return size;
}

fn encodeEntitySchemas(bytes: []u8, cursor: *usize, project: Project) void {
    for (0..entity_kinds.len) |schema_index| {
        putU8(bytes, cursor, project.entity_schema_name_lens[schema_index]);
        putBytes(bytes, cursor, project.entity_schema_names[schema_index][0..project.entity_schema_name_lens[schema_index]]);
        for (0..max_entity_fields) |field| {
            putU8(bytes, cursor, project.entity_field_name_lens[schema_index][field]);
            putBytes(bytes, cursor, project.entity_field_names[schema_index][field][0..project.entity_field_name_lens[schema_index][field]]);
            putU8(bytes, cursor, @intFromEnum(project.entity_field_kinds[schema_index][field]));
            putU16(bytes, cursor, project.entity_field_defaults[schema_index][field]);
            putU16(bytes, cursor, project.entity_field_mins[schema_index][field]);
            putU16(bytes, cursor, project.entity_field_maxes[schema_index][field]);
        }
    }
}

fn decodeEntitySchemas(bytes: []const u8, cursor: *usize, project: *Project) !void {
    for (0..entity_kinds.len) |schema_index| {
        const kind: EntityKind = @enumFromInt(schema_index + 1);
        const schema_name_length = try takeU8(bytes, cursor);
        if (schema_name_length == 0 or schema_name_length > max_entity_name_length) return error.InvalidWorldProject;
        const schema_name = try takeBytes(bytes, cursor, schema_name_length);
        try project.setEntitySchemaName(kind, schema_name);
        for (0..max_entity_fields) |field| {
            const field_name_length = try takeU8(bytes, cursor);
            if (field_name_length > max_entity_field_name_length) return error.InvalidWorldProject;
            const field_name = try takeBytes(bytes, cursor, field_name_length);
            const raw_field_kind = try takeU8(bytes, cursor);
            if (raw_field_kind > @intFromEnum(EntityFieldKind.tile)) return error.InvalidWorldProject;
            const field_kind: EntityFieldKind = @enumFromInt(raw_field_kind);
            const default_value = try takeU16(bytes, cursor);
            const minimum = try takeU16(bytes, cursor);
            const maximum = try takeU16(bytes, cursor);
            project.setEntityFieldSchema(kind, field, field_name, field_kind, default_value, minimum, maximum) catch {
                return error.InvalidWorldProject;
            };
        }
    }
}

pub fn lupiTileSamplePixels(project: Project) u32 {
    var result: u32 = 0;
    const pixels_per_tile = @as(u32, project.tile_size) * project.tile_size;
    for (0..layer_count) |layer| {
        for (project.layerCells(layer)) |tile| {
            if (tile != empty_tile) result +|= pixels_per_tile;
        }
    }
    return result;
}

pub fn lupiLuaDataEntries(project: Project) u32 {
    var result = lupi_lua_data_fixed_entries;
    for (0..layer_count) |layer| {
        for (project.layerCells(layer)) |tile| {
            if (tile != empty_tile) result +|= 1;
        }
        for (project.smartCells(layer)) |base| {
            if (base != empty_tile) result +|= 1;
        }
    }
    for (project.solid) |value| {
        if (value != 0) result +|= 1;
    }
    for (project.entities) |raw_kind| {
        if (raw_kind != @intFromEnum(EntityKind.none)) result +|= lupi_entity_entry_cost;
    }
    return result;
}

pub fn lupiStaticSafe(project: Project) bool {
    if (lupiTileSamplePixels(project) > lupi_tile_sample_pixels_max) return false;
    return lupiLuaDataEntries(project) <= lupi_lua_data_entries_max;
}

pub fn exportLua(allocator: std.mem.Allocator, project: Project) ![]u8 {
    if (!validate(project).valid()) return error.InvalidProjectForExport;
    if (lupiTileSamplePixels(project) > lupi_tile_sample_pixels_max) {
        return error.LupiMapWorkBudgetExceeded;
    }
    if (lupiLuaDataEntries(project) > lupi_lua_data_entries_max) {
        return error.LupiLuaDataBudgetExceeded;
    }
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;
    try writer.print("-- Generated by ELIS Workshop. Edit the .elisworld source, not this file.\nlocal _project = {{\n  metadata = {{ width = {}, height = {}, tile_size = {} }},\n", .{
        project.width,
        project.height,
        project.tile_size,
    });
    try writer.print("  lupi_metadata = {{ editor = \"ELIS Workshop\", schema = {}", .{schema_version});
    if (project.spawn) |spawn| try writer.print(", spawn = {{ x = {}, y = {} }}", .{ spawn.x, spawn.y });
    if (project.goal) |goal| try writer.print(", goal = {{ x = {}, y = {} }}", .{ goal.x, goal.y });
    try writer.writeAll(", entity_schemas = {");
    for (entity_kinds, 0..) |kind, schema_index| {
        if (schema_index != 0) try writer.writeAll(", ");
        try writer.print("{s} = {{ name = ", .{@tagName(kind)});
        try writeLuaString(writer, project.entitySchemaName(kind));
        try writer.writeAll(", fields = {");
        var field_count: usize = 0;
        for (0..max_entity_fields) |field| {
            if (project.entityFieldName(kind, field).len == 0) continue;
            if (field_count != 0) try writer.writeAll(", ");
            try writer.writeAll("{ name = ");
            try writeLuaString(writer, project.entityFieldName(kind, field));
            try writer.print(", kind = \"{s}\", default = {}, min = {}, max = {} }}", .{
                @tagName(project.entityFieldKind(kind, field)),
                project.entityFieldDefault(kind, field),
                project.entity_field_mins[schema_index][field],
                project.entity_field_maxes[schema_index][field],
            });
            field_count += 1;
        }
        try writer.writeAll(" } }");
    }
    try writer.writeAll("}, solid = {");
    var solid_count: usize = 0;
    for (project.solid, 0..) |value, index| {
        if (value == 0) continue;
        if (solid_count != 0) try writer.writeByte(',');
        try writer.print("[{}]=1", .{index + 1});
        solid_count += 1;
    }
    try writer.writeAll("}, entities = {");
    var entity_count: usize = 0;
    for (project.entities, 0..) |raw_kind, index| {
        if (raw_kind > @intFromEnum(EntityKind.decoration)) continue;
        const kind: EntityKind = @enumFromInt(raw_kind);
        if (kind == .none) continue;
        if (entity_count != 0) try writer.writeAll(", ");
        try writer.print("{{ kind = \"{s}\", x = {}, y = {}, value = {}, fields = {{", .{
            @tagName(kind),
            index % project.width,
            index / project.width,
            project.entityFieldAt(index, 0),
        });
        for (0..max_entity_fields) |field| {
            if (field != 0) try writer.writeByte(',');
            try writer.print("{}", .{project.entity_fields[index * max_entity_fields + field]});
        }
        try writer.writeAll("} }");
        entity_count += 1;
    }
    try writer.writeAll("}, smart_terrain = {");
    for (layer_names, 0..) |name, layer| {
        if (layer != 0) try writer.writeAll(", ");
        try writer.print("{s} = {{", .{name});
        var smart_count: usize = 0;
        for (project.smartCells(layer), 0..) |base, index| {
            if (base == empty_tile) continue;
            if (smart_count != 0) try writer.writeAll(", ");
            try writer.print("[{}]={}", .{ index + 1, base });
            smart_count += 1;
        }
        try writer.writeByte('}');
    }
    try writer.writeAll("} },\n  tilesets = {");
    for (layer_names, 0..) |name, index| {
        if (index != 0) try writer.writeAll(", ");
        try writer.print("{s} = ", .{name});
        try writeLuaString(writer, project.layerTilesetName(index));
    }
    try writer.writeAll(" },\n  layers = { ");
    for (layer_names, 0..) |name, index| {
        if (index != 0) try writer.writeAll(", ");
        try writeLuaString(writer, name);
    }
    try writer.writeAll(" },\n");
    for (layer_names, 0..) |name, layer| {
        try writer.print("  {s} = {{", .{name});
        var emitted: usize = 0;
        for (project.layerCells(layer), 0..) |tile, index| {
            if (tile == empty_tile) continue;
            if (emitted != 0) try writer.writeAll(", ");
            try writer.print("[{}]={}", .{ index + 1, tile });
            emitted += 1;
        }
        try writer.writeAll("},\n");
    }
    try writer.writeAll("}\nlocal _combined = { metadata = _project.metadata, lupi_metadata = _project.lupi_metadata, tilesets = _project.tilesets, layers = _project.layers");
    for (layer_names) |name| try writer.print(", {s} = _project.{s}", .{ name, name });
    try writer.writeAll(" }\n_project.map = _combined\n");
    for (layer_names, 0..) |name, layer| {
        try writer.print("_project.{s} = {{ metadata = _project.metadata, lupi_metadata = _project.lupi_metadata, tilesets = _project.tilesets, [", .{name});
        try writeLuaString(writer, project.layerTilesetName(layer));
        try writer.print("] = _combined.{s} }}\n", .{name});
    }
    try writer.writeAll("return _project\n");
    if (output.written().len > lupi_lua_source_bytes_max) {
        return error.LupiLuaSourceBudgetExceeded;
    }
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
    var atomic_file = try cwd.createFileAtomic(io, path, .{ .replace = true });
    defer atomic_file.deinit(io);
    try atomic_file.file.writeStreamingAll(io, bytes);
    try atomic_file.file.sync(io);
    try atomic_file.replace(io);
}

fn validateDimensions(width: u16, height: u16, tile_size: u16) !void {
    if (width < 4 or height < 4 or width > max_dimension or height > max_dimension or
        tile_size == 0 or tile_size > 64) return error.InvalidWorldDimensions;
}

fn pointInBounds(project: Project, point: Point) bool {
    return point.x < project.width and point.y < project.height;
}

fn markAffected(project: Project, affected: *[stamp_capacity]bool, index: usize) void {
    std.debug.assert(index < project.cellCount());
    affected[index] = true;
    const x = index % project.width;
    const y = index / project.width;
    if (x > 0) affected[index - 1] = true;
    if (x + 1 < project.width) affected[index + 1] = true;
    if (y > 0) affected[index - project.width] = true;
    if (y + 1 < project.height) affected[index + project.width] = true;
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
        .smart => project.smart[@as(usize, change.layer) * project.cellCount() + change.index] = @intCast(value),
        .solid => project.solid[change.index] = @intCast(value),
        .entity_kind => project.entities[change.index] = @intCast(value),
        .entity_field => project.entity_fields[@as(usize, change.index) * max_entity_fields + change.layer] = @intCast(value),
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

fn encodeV2ForTest(allocator: std.mem.Allocator, project: Project) ![]u8 {
    const cell_count = project.cellCount();
    var tileset_bytes: usize = 0;
    for (project.tileset_lens) |length| tileset_bytes += length;
    const payload_len = tileset_bytes + project.tiles.len * 2 + project.smart.len * 2 + project.solid.len;
    const fixed_len = magic.len + 2 + 2 + 2 + 2 + layer_count + 4 + 4 + 8;
    const bytes = try allocator.alloc(u8, fixed_len + payload_len + checksum_len);
    var cursor: usize = 0;
    putBytes(bytes, &cursor, magic);
    putU16(bytes, &cursor, layered_schema_version);
    putU16(bytes, &cursor, project.width);
    putU16(bytes, &cursor, project.height);
    putU16(bytes, &cursor, project.tile_size);
    for (project.tileset_lens) |length| putU8(bytes, &cursor, length);
    putU32(bytes, &cursor, encodePoint(project, project.spawn));
    putU32(bytes, &cursor, encodePoint(project, project.goal));
    putU64(bytes, &cursor, project.revision);
    for (0..layer_count) |layer| putBytes(bytes, &cursor, project.layerTilesetName(layer));
    for (project.tiles) |tile| putU16(bytes, &cursor, tile);
    for (project.smart) |base| putU16(bytes, &cursor, base);
    putBytes(bytes, &cursor, project.solid[0..cell_count]);
    putU32(bytes, &cursor, checksum(bytes[0..cursor]));
    return bytes;
}

fn encodeV3ForTest(allocator: std.mem.Allocator, project: Project) ![]u8 {
    const cell_count = project.cellCount();
    var tileset_bytes: usize = 0;
    for (project.tileset_lens) |length| tileset_bytes += length;
    const payload_len = tileset_bytes + project.tiles.len * 2 + project.smart.len * 2 + project.solid.len +
        project.entities.len + cell_count * 2;
    const fixed_len = magic.len + 2 + 2 + 2 + 2 + layer_count + 4 + 4 + 8;
    const bytes = try allocator.alloc(u8, fixed_len + payload_len + checksum_len);
    var cursor: usize = 0;
    putBytes(bytes, &cursor, magic);
    putU16(bytes, &cursor, entity_schema_version);
    putU16(bytes, &cursor, project.width);
    putU16(bytes, &cursor, project.height);
    putU16(bytes, &cursor, project.tile_size);
    for (project.tileset_lens) |length| putU8(bytes, &cursor, length);
    putU32(bytes, &cursor, encodePoint(project, project.spawn));
    putU32(bytes, &cursor, encodePoint(project, project.goal));
    putU64(bytes, &cursor, project.revision);
    for (0..layer_count) |layer| putBytes(bytes, &cursor, project.layerTilesetName(layer));
    for (project.tiles) |tile| putU16(bytes, &cursor, tile);
    for (project.smart) |base| putU16(bytes, &cursor, base);
    putBytes(bytes, &cursor, project.solid[0..cell_count]);
    putBytes(bytes, &cursor, project.entities[0..cell_count]);
    for (0..cell_count) |index| putU16(bytes, &cursor, project.entityFieldAt(index, 0));
    putU32(bytes, &cursor, checksum(bytes[0..cursor]));
    return bytes;
}

fn encodeV1ForTest(allocator: std.mem.Allocator, project: Project) ![]u8 {
    const cell_count = project.cellCount();
    const fixed_len = magic.len + 2 + 2 + 2 + 2 + 1 + 4 + 4 + 8;
    const total_len = fixed_len + project.tilesetName().len + project.tiles.len * 2 + project.solid.len + checksum_len;
    const bytes = try allocator.alloc(u8, total_len);
    var cursor: usize = 0;
    putBytes(bytes, &cursor, magic);
    putU16(bytes, &cursor, legacy_schema_version);
    putU16(bytes, &cursor, project.width);
    putU16(bytes, &cursor, project.height);
    putU16(bytes, &cursor, project.tile_size);
    putU8(bytes, &cursor, @intCast(project.tilesetName().len));
    putU32(bytes, &cursor, encodePoint(project, project.spawn));
    putU32(bytes, &cursor, encodePoint(project, project.goal));
    putU64(bytes, &cursor, project.revision);
    putBytes(bytes, &cursor, project.tilesetName());
    for (project.tiles) |tile| putU16(bytes, &cursor, tile);
    putBytes(bytes, &cursor, project.solid[0..cell_count]);
    putU32(bytes, &cursor, checksum(bytes[0..cursor]));
    return bytes;
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
    project.setLayerTilesetName(2, "props/castle");
    const entity_index = project.cellIndex(5, 3);
    project.entities[entity_index] = @intFromEnum(EntityKind.enemy);
    project.entity_fields[entity_index * max_entity_fields] = 12;
    const bytes = try encode(std.testing.allocator, project);
    defer std.testing.allocator.free(bytes);
    var decoded = try decode(std.testing.allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqualStrings(project.tilesetName(), decoded.tilesetName());
    try std.testing.expectEqualStrings("props/castle", decoded.layerTilesetName(2));
    try std.testing.expectEqual(@as(u16, 19), decoded.layerCells(2)[decoded.cellIndex(4, 3)]);
    try std.testing.expectEqual(EntityKind.enemy, decoded.entityKindAt(entity_index));
    try std.testing.expectEqual(@as(u16, 12), decoded.entityFieldAt(entity_index, 0));
    bytes[bytes.len - 5] ^= 1;
    try std.testing.expectError(error.InvalidWorldChecksum, decode(std.testing.allocator, bytes));
}

test "version one projects migrate to independent layers without invented smart terrain" {
    var project = try Project.initStarter(std.testing.allocator, 8, 6, 16, "maps/legacy");
    defer project.deinit();
    const bytes = try encodeV1ForTest(std.testing.allocator, project);
    defer std.testing.allocator.free(bytes);
    var migrated = try decode(std.testing.allocator, bytes);
    defer migrated.deinit();
    for (0..layer_count) |layer| {
        try std.testing.expectEqualStrings("maps/legacy", migrated.layerTilesetName(layer));
        for (migrated.smartCells(layer)) |base| try std.testing.expectEqual(empty_tile, base);
    }
}

test "version three projects migrate the old value into field zero" {
    var project = try Project.initStarter(std.testing.allocator, 8, 6, 16, "maps/entities");
    defer project.deinit();
    const index = project.cellIndex(3, 2);
    project.entities[index] = @intFromEnum(EntityKind.enemy);
    project.entity_fields[index * max_entity_fields] = 17;
    const bytes = try encodeV3ForTest(std.testing.allocator, project);
    defer std.testing.allocator.free(bytes);
    var migrated = try decode(std.testing.allocator, bytes);
    defer migrated.deinit();
    try std.testing.expectEqualStrings("Enemy", migrated.entitySchemaName(.enemy));
    try std.testing.expectEqual(@as(u16, 17), migrated.entityFieldAt(index, 0));
    try std.testing.expectEqual(@as(u16, 0), migrated.entityFieldAt(index, 1));
}

test "version two projects migrate with an empty entity layer" {
    var project = try Project.initStarter(std.testing.allocator, 8, 6, 16, "maps/layered");
    defer project.deinit();
    const bytes = try encodeV2ForTest(std.testing.allocator, project);
    defer std.testing.allocator.free(bytes);
    var migrated = try decode(std.testing.allocator, bytes);
    defer migrated.deinit();
    for (migrated.entities) |kind| try std.testing.expectEqual(@as(u8, 0), kind);
    for (migrated.entity_fields) |value| try std.testing.expectEqual(@as(u16, 0), value);
}

test "smart terrain derives cardinal variants and undo restores semantics" {
    var project = try Project.initStarter(std.testing.allocator, 8, 6, 16, "tiles/world");
    defer project.deinit();
    var history = History.init(std.testing.allocator);
    defer history.deinit();
    var builder = CommandBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const center = project.cellIndex(3, 2);
    const east = project.cellIndex(4, 2);
    try builder.paintSmartTerrain(&project, 1, center, 32);
    try builder.paintSmartTerrain(&project, 1, east, 32);
    try history.commit((try builder.finish()).?);
    try std.testing.expectEqual(@as(u16, 34), project.layerCells(1)[center]);
    try std.testing.expectEqual(@as(u16, 40), project.layerCells(1)[east]);
    try std.testing.expectEqual(@as(u16, 32), project.smartCells(1)[center]);
    try std.testing.expect(try history.undo(&project));
    try std.testing.expectEqual(empty_tile, project.layerCells(1)[center]);
    try std.testing.expectEqual(empty_tile, project.smartCells(1)[center]);
    try std.testing.expect(try history.redo(&project));
    try std.testing.expectEqual(@as(u16, 34), project.layerCells(1)[center]);
}

test "anchored resize preserves semantic cells and is reversible" {
    var project = try Project.initStarter(std.testing.allocator, 6, 5, 16, "tiles/world");
    defer project.deinit();
    var history = History.init(std.testing.allocator);
    defer history.deinit();
    const kept = project.cellIndex(5, 4);
    project.layerCells(2)[kept] = 17;
    project.entities[kept] = @intFromEnum(EntityKind.pickup);
    project.entity_fields[kept * max_entity_fields] = 8;
    project.solid[kept] = 1;
    project.layerCells(1)[project.cellIndex(0, 0)] = 23;
    try project.setEntitySchemaName(.pickup, "Loot");
    const report = try history.resize(&project, 4, 4, .bottom_right);
    try std.testing.expect(report.changed);
    try std.testing.expect(report.clipped());
    try std.testing.expect(report.spawn_clipped);
    try std.testing.expectEqual(@as(u16, 4), project.width);
    const rebased = project.cellIndex(3, 3);
    try std.testing.expectEqual(@as(u16, 17), project.layerCells(2)[rebased]);
    try std.testing.expectEqual(EntityKind.pickup, project.entityKindAt(rebased));
    try std.testing.expectEqualStrings("Loot", project.entitySchemaName(.pickup));
    try std.testing.expectEqual(@as(u16, 8), project.entityFieldAt(rebased, 0));
    try std.testing.expectEqual(@as(u8, 1), project.solid[rebased]);
    try std.testing.expect(try history.undo(&project));
    try std.testing.expectEqual(@as(u16, 6), project.width);
    try std.testing.expectEqual(@as(u16, 23), project.layerCells(1)[project.cellIndex(0, 0)]);
    try std.testing.expect(project.spawn != null);
    try std.testing.expect(try history.redo(&project));
    try std.testing.expectEqual(@as(u16, 4), project.width);
    try std.testing.expectEqual(EntityKind.pickup, project.entityKindAt(project.cellIndex(3, 3)));
}

test "resize refreshes smart terrain along a clipped edge" {
    var project = try Project.init(std.testing.allocator, 6, 4, 16, "tiles/world");
    defer project.deinit();
    var history = History.init(std.testing.allocator);
    defer history.deinit();
    const west = project.cellIndex(3, 1);
    const east = project.cellIndex(4, 1);
    project.smartCells(1)[west] = 32;
    project.smartCells(1)[east] = 32;
    project.layerCells(1)[west] = 34;
    project.layerCells(1)[east] = 40;
    const report = try history.resize(&project, 4, 4, .top_left);
    try std.testing.expectEqual(@as(u16, 1), report.clipped_cells);
    try std.testing.expectEqual(@as(u16, 32), project.layerCells(1)[project.cellIndex(3, 1)]);
}

test "line and rectangle tools coalesce into reversible commands" {
    var project = try Project.initStarter(std.testing.allocator, 8, 6, 16, "tiles/world");
    defer project.deinit();
    var history = History.init(std.testing.allocator);
    defer history.deinit();
    var line = CommandBuilder.init(std.testing.allocator);
    defer line.deinit();
    try line.drawLine(&project, 2, .{ .x = 1, .y = 1 }, .{ .x = 4, .y = 3 }, 7);
    try history.commit((try line.finish()).?);
    try std.testing.expectEqual(@as(u16, 7), project.layerCells(2)[project.cellIndex(4, 3)]);
    var rectangle = CommandBuilder.init(std.testing.allocator);
    defer rectangle.deinit();
    try rectangle.drawRectangle(&project, 2, .{ .x = 2, .y = 1 }, .{ .x = 5, .y = 4 }, 9, false);
    try history.commit((try rectangle.finish()).?);
    try std.testing.expectEqual(@as(u16, 9), project.layerCells(2)[project.cellIndex(2, 1)]);
    try std.testing.expectEqual(empty_tile, project.layerCells(2)[project.cellIndex(4, 2)]);
    try std.testing.expect(try history.undo(&project));
    try std.testing.expectEqual(empty_tile, project.layerCells(2)[project.cellIndex(2, 1)]);
    try std.testing.expectEqual(@as(u16, 7), project.layerCells(2)[project.cellIndex(3, 2)]);
    try std.testing.expect(try history.undo(&project));
    try std.testing.expectEqual(empty_tile, project.layerCells(2)[project.cellIndex(3, 2)]);
    try std.testing.expectEqual(empty_tile, project.layerCells(2)[project.cellIndex(4, 3)]);
}

test "filled rectangle paints its interior" {
    var project = try Project.initStarter(std.testing.allocator, 6, 5, 16, "tiles/world");
    defer project.deinit();
    var rectangle = CommandBuilder.init(std.testing.allocator);
    defer rectangle.deinit();
    try rectangle.drawRectangle(&project, 1, .{ .x = 1, .y = 1 }, .{ .x = 3, .y = 3 }, 6, true);
    try std.testing.expectEqual(@as(u16, 6), project.layerCells(1)[project.cellIndex(2, 2)]);
}

test "stamp captures a rectangle and preserves smart terrain through undo" {
    var project = try Project.initStarter(std.testing.allocator, 8, 6, 16, "tiles/world");
    defer project.deinit();
    var history = History.init(std.testing.allocator);
    defer history.deinit();
    var paint = CommandBuilder.init(std.testing.allocator);
    defer paint.deinit();
    try paint.paintSmartTerrain(&project, 1, project.cellIndex(1, 1), 32);
    try paint.paintSmartTerrain(&project, 1, project.cellIndex(2, 1), 32);
    try history.commit((try paint.finish()).?);
    const stamp = try Stamp.capture(project, 1, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 });
    try std.testing.expect(stamp.valid());
    var paste = CommandBuilder.init(std.testing.allocator);
    defer paste.deinit();
    try paste.stamp(&project, 1, .{ .x = 4, .y = 3 }, stamp);
    try history.commit((try paste.finish()).?);
    const copied = project.cellIndex(4, 3);
    try std.testing.expectEqual(@as(u16, 32), project.smartCells(1)[copied]);
    try std.testing.expect(try history.undo(&project));
    try std.testing.expectEqual(empty_tile, project.layerCells(1)[copied]);
    try std.testing.expect(try history.redo(&project));
    try std.testing.expectEqual(@as(u16, 32), project.smartCells(1)[copied]);
}

test "stamp transforms preserve tile and semantic orientation" {
    var stamp = Stamp{ .width = 2, .height = 2 };
    stamp.tiles[0] = 1;
    stamp.tiles[1] = 2;
    stamp.tiles[2] = 3;
    stamp.tiles[3] = 4;
    stamp.smart[0] = 16;
    stamp.flipHorizontal();
    try std.testing.expectEqualSlices(u16, &.{ 2, 1, 4, 3 }, stamp.tiles[0..4]);
    try std.testing.expectEqual(@as(u16, empty_tile), stamp.smart[0]);
    try std.testing.expectEqual(@as(u16, 16), stamp.smart[1]);
    stamp.rotateClockwise();
    try std.testing.expectEqualSlices(u16, &.{ 4, 2, 3, 1 }, stamp.tiles[0..4]);
    stamp.flipVertical();
    try std.testing.expectEqualSlices(u16, &.{ 3, 1, 4, 2 }, stamp.tiles[0..4]);
}

test "stamp clips at the project edge" {
    var project = try Project.initStarter(std.testing.allocator, 6, 4, 16, "tiles/world");
    defer project.deinit();
    var source = CommandBuilder.init(std.testing.allocator);
    defer source.deinit();
    try source.setRawTile(&project, 1, project.cellIndex(1, 1), 7);
    try source.setRawTile(&project, 1, project.cellIndex(2, 1), 8);
    const pattern = try Stamp.capture(project, 1, .{ .x = 1, .y = 1 }, .{ .x = 2, .y = 1 });
    var paste = CommandBuilder.init(std.testing.allocator);
    defer paste.deinit();
    try paste.stamp(&project, 1, .{ .x = 5, .y = 3 }, pattern);
    try std.testing.expectEqual(@as(u16, 7), project.layerCells(1)[project.cellIndex(5, 3)]);
}

test "typed entities are undoable and warn when blocked" {
    var project = try Project.initStarter(std.testing.allocator, 6, 4, 8, "tiles/castle");
    defer project.deinit();
    var history = History.init(std.testing.allocator);
    defer history.deinit();
    var builder = CommandBuilder.init(std.testing.allocator);
    defer builder.deinit();
    const index = project.cellIndex(0, 0);
    try builder.setEntity(&project, index, .trigger, 9);
    try history.commit((try builder.finish()).?);
    try std.testing.expectEqual(EntityKind.trigger, project.entityKindAt(index));
    try std.testing.expectEqual(@as(u16, 9), project.entityFieldAt(index, 0));
    const report = validate(project);
    try std.testing.expect(report.warning_count > 0);
    try std.testing.expect(try history.undo(&project));
    try std.testing.expectEqual(EntityKind.none, project.entityKindAt(index));
    try std.testing.expect(try history.redo(&project));
    try std.testing.expectEqual(EntityKind.trigger, project.entityKindAt(index));
}

test "layer tileset assignments participate in unified history" {
    var project = try Project.initStarter(std.testing.allocator, 8, 6, 16, "tiles/world");
    defer project.deinit();
    var history = History.init(std.testing.allocator);
    defer history.deinit();

    const revision_before = project.revision;
    try std.testing.expect(try history.setLayerTilesetName(&project, 2, "props/castle"));
    try std.testing.expectEqual(revision_before +% 1, project.revision);
    try std.testing.expectEqualStrings("props/castle", project.layerTilesetName(2));
    const saved_revision = project.revision;
    try std.testing.expect(try history.undo(&project));
    try std.testing.expectEqual(saved_revision +% 1, project.revision);
    try std.testing.expectEqualStrings("tiles/world", project.layerTilesetName(2));
    try std.testing.expect(try history.redo(&project));
    try std.testing.expectEqual(saved_revision +% 2, project.revision);
    try std.testing.expectEqualStrings("props/castle", project.layerTilesetName(2));
    try std.testing.expectError(
        error.InvalidTilesetName,
        history.setLayerTilesetName(&project, layer_count, "props/invalid"),
    );
}

test "project templates are valid deterministic and undoable" {
    var project = try Project.initStarter(std.testing.allocator, 16, 10, 16, "tiles/world");
    defer project.deinit();
    project.setLayerTilesetName(2, "props/world");
    const original_spawn = project.spawn.?;
    var history = History.init(std.testing.allocator);
    defer history.deinit();
    for (project_templates) |template| {
        try history.applyProjectTemplate(&project, template);
        try std.testing.expect(validate(project).valid());
        try std.testing.expectEqual(@as(u16, 16), project.width);
        try std.testing.expectEqualStrings("props/world", project.layerTilesetName(2));
        if (template == .puzzle) {
            try std.testing.expectEqualStrings("Crate", project.entitySchemaName(.enemy));
            try std.testing.expectEqualStrings("Switch", project.entitySchemaName(.pickup));
        }
        const first = try encode(std.testing.allocator, project);
        defer std.testing.allocator.free(first);
        var duplicate = try buildProjectTemplate(project, template);
        defer duplicate.deinit();
        duplicate.revision = project.revision;
        const second = try encode(std.testing.allocator, duplicate);
        defer std.testing.allocator.free(second);
        try std.testing.expectEqualSlices(u8, first, second);
        try std.testing.expect(try history.undo(&project));
        try std.testing.expectEqual(original_spawn, project.spawn.?);
    }
}

test "entity schema definitions participate in unified history" {
    var project = try Project.initStarter(std.testing.allocator, 8, 6, 16, "tiles/world");
    defer project.deinit();
    var history = History.init(std.testing.allocator);
    defer history.deinit();
    const entity_index = project.cellIndex(3, 2);
    project.entities[entity_index] = @intFromEnum(EntityKind.enemy);
    try std.testing.expect(try history.setEntitySchemaName(&project, .enemy, "Sentinel"));
    try std.testing.expectEqualStrings("Sentinel", project.entitySchemaName(.enemy));
    try std.testing.expect(try history.setEntityFieldSchema(
        &project,
        .enemy,
        3,
        "alert",
        .toggle,
        1,
        0,
        1,
    ));
    try std.testing.expectEqual(@as(u8, 4), project.entityFieldCount(.enemy));
    try std.testing.expectEqual(@as(u16, 1), project.entityFieldAt(entity_index, 3));
    try std.testing.expect(try history.undo(&project));
    try std.testing.expectEqual(@as(u8, 3), project.entityFieldCount(.enemy));
    try std.testing.expectEqual(@as(u16, 0), project.entityFieldAt(entity_index, 3));
    try std.testing.expect(try history.undo(&project));
    try std.testing.expectEqualStrings("Enemy", project.entitySchemaName(.enemy));
    try std.testing.expect(try history.redo(&project));
    try std.testing.expectEqualStrings("Sentinel", project.entitySchemaName(.enemy));
}

test "entity schema names remain representable in Workshop" {
    var project = try Project.initStarter(std.testing.allocator, 8, 6, 16, "tiles/world");
    defer project.deinit();
    try std.testing.expectError(
        error.InvalidEntitySchema,
        project.setEntitySchemaName(.enemy, "line\nbreak"),
    );
    try std.testing.expectError(
        error.InvalidEntitySchema,
        project.setEntityFieldSchema(.enemy, 0, "caf\xc3\xa9", .unsigned, 0, 0, 1),
    );
    try std.testing.expectEqualStrings("Enemy", project.entitySchemaName(.enemy));
    try std.testing.expectEqualStrings("speed", project.entityFieldName(.enemy, 0));
}

test "project entity schemas persist typed fields and export metadata" {
    var project = try Project.initStarter(std.testing.allocator, 8, 6, 16, "tiles/world");
    defer project.deinit();
    try project.setEntitySchemaName(.enemy, "Guard");
    try project.setEntityFieldSchema(.enemy, 0, "speed", .unsigned, 3, 1, 10);
    try project.setEntityFieldSchema(.enemy, 1, "patrol", .toggle, 0, 0, 1);
    const index = project.cellIndex(3, 2);
    var builder = CommandBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try builder.setEntity(&project, index, .enemy, 4);
    try builder.setEntityField(&project, index, 1, 1);
    try std.testing.expectError(error.InvalidEditorChange, builder.setEntityField(&project, index, 1, 2));
    var history = History.init(std.testing.allocator);
    defer history.deinit();
    try history.commit((try builder.finish()).?);
    const bytes = try encode(std.testing.allocator, project);
    defer std.testing.allocator.free(bytes);
    var decoded = try decode(std.testing.allocator, bytes);
    defer decoded.deinit();
    try std.testing.expectEqualStrings("Guard", decoded.entitySchemaName(.enemy));
    try std.testing.expectEqualStrings("patrol", decoded.entityFieldName(.enemy, 1));
    try std.testing.expectEqual(@as(u16, 4), decoded.entityFieldAt(index, 0));
    try std.testing.expectEqual(@as(u16, 1), decoded.entityFieldAt(index, 1));
    const output = try exportLua(std.testing.allocator, decoded);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "schema = 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "name = \"Guard\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "fields = {4,1,0,0}") != null);
}

test "Lua export enforces bounded Lupi tile sampling work" {
    var project = try Project.initStarter(std.testing.allocator, 64, 64, 16, "tiles/castle");
    defer project.deinit();
    try std.testing.expect(lupiTileSamplePixels(project) > lupi_tile_sample_pixels_max);
    try std.testing.expectError(
        error.LupiMapWorkBudgetExceeded,
        exportLua(std.testing.allocator, project),
    );
    @memset(project.layerCells(0), empty_tile);
    project.layerCells(0)[0] = 0;
    try std.testing.expect(lupiStaticSafe(project));
}

test "Lua export rejects generated data that can exceed the Lupi heap" {
    var project = try Project.initStarter(std.testing.allocator, 64, 64, 16, "tiles/castle");
    defer project.deinit();
    @memset(project.tiles, empty_tile);
    @memset(project.smart, empty_tile);
    for (project.entities) |*raw_kind| raw_kind.* = @intFromEnum(EntityKind.enemy);
    try std.testing.expect(lupiLuaDataEntries(project) > lupi_lua_data_entries_max);
    try std.testing.expectError(
        error.LupiLuaDataBudgetExceeded,
        exportLua(std.testing.allocator, project),
    );
}

test "maximum admitted Lua data profiles remain within generated source budget" {
    var project = try Project.initStarter(std.testing.allocator, 64, 64, 1, "tiles/castle");
    defer project.deinit();
    @memset(project.tiles, empty_tile);
    @memset(project.smart, empty_tile);
    @memset(project.solid, 0);
    @memset(project.entities, @intFromEnum(EntityKind.none));
    @memset(project.entity_fields, 0);

    const raw_tile_count: usize =
        @intCast(lupi_lua_data_entries_max - lupi_lua_data_fixed_entries);
    @memset(project.layerCells(0)[0..raw_tile_count], 0);
    try std.testing.expectEqual(lupi_lua_data_entries_max, lupiLuaDataEntries(project));
    const tile_output = try exportLua(std.testing.allocator, project);
    defer std.testing.allocator.free(tile_output);
    try std.testing.expect(tile_output.len <= lupi_lua_source_bytes_max);

    @memset(project.tiles, empty_tile);
    const entity_count: usize = @intCast(
        (lupi_lua_data_entries_max - lupi_lua_data_fixed_entries) /
            lupi_entity_entry_cost,
    );
    @memset(project.entities[0..entity_count], @intFromEnum(EntityKind.enemy));
    const entity_output = try exportLua(std.testing.allocator, project);
    defer std.testing.allocator.free(entity_output);
    try std.testing.expect(entity_output.len <= lupi_lua_source_bytes_max);
}

test "Lua export fails closed for invalid projects" {
    var project = try Project.initStarter(std.testing.allocator, 6, 4, 8, "tiles/castle");
    defer project.deinit();
    project.spawn = null;
    try std.testing.expectError(
        error.InvalidProjectForExport,
        exportLua(std.testing.allocator, project),
    );
}

test "Lua export preserves strict layer order and editor metadata" {
    var project = try Project.initStarter(std.testing.allocator, 6, 4, 8, "tiles/castle");
    defer project.deinit();
    const entity_index = project.cellIndex(2, 1);
    project.entities[entity_index] = @intFromEnum(EntityKind.pickup);
    project.entity_fields[entity_index * max_entity_fields] = 3;
    const output = try exportLua(std.testing.allocator, project);
    defer std.testing.allocator.free(output);
    try std.testing.expect(std.mem.indexOf(u8, output, "layers = { \"background\", \"terrain\", \"objects\", \"foreground\" }") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "lupi_metadata = { editor = \"ELIS Workshop\", schema = 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "entities = {{ kind = \"pickup\", x = 2, y = 1, value = 3, fields = {3,0,0,0} }") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "smart_terrain = {") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "solid = {[") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "background = {[1]=0") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "foreground = {},") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "_project.map = _combined") != null);
    try std.testing.expect(std.mem.indexOf(
        u8,
        output,
        "_project.background = { metadata = _project.metadata, lupi_metadata = _project.lupi_metadata",
    ) != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "tiles/castle") != null);
}
