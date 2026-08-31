//! Native SDL Workshop application.
//!
//! `Studio` owns transient interaction state and delegates authoritative map,
//! persistence, validation, and undo behavior to `studio/model.zig`. Rendering
//! reads that state but never mutates exported project data.

const std = @import("std");
const c = @import("native.zig").c;
const font = @import("font.zig");
const model = @import("studio/model.zig");
const assets = @import("studio/assets.zig");

const default_width: u16 = 30;
const default_height: u16 = 16;
const default_tile_size: u16 = 16;
const bar_top: i32 = 58;
const bar_bottom: i32 = 32;

// -----------------------------------------------------------------------------
// Interaction and layout types

const Tool = enum(u8) { brush, smart, erase, fill, pick, collision, spawn, goal, entity, select, stamp, line, rectangle, resize };
const tools = [_]Tool{ .brush, .smart, .erase, .fill, .pick, .collision, .spawn, .goal, .entity, .select, .stamp, .line, .rectangle, .resize };
const tool_labels = [_][]const u8{ "PENCIL", "SMART", "ERASER", "FILL", "PICK", "COLLISION", "START", "GOAL", "ENTITY", "SELECT", "STAMP", "LINE", "RECTANGLE", "RESIZE" };
const tool_columns: usize = 2;
const tool_rows: usize = (tools.len + tool_columns - 1) / tool_columns;
const Notice = enum {
    none,
    saved,
    exported,
    asset_selected,
    asset_incompatible,
    save_failed,
    edit_failed,
    export_failed,
    lupi_export_blocked,
    invalid_preview,
    stamp_captured,
    stamp_missing,
    stamp_transformed,
    entity_changed,
    layer_locked,
    layer_lock_changed,
    layer_visibility,
    shape_applied,
    resize_applied,
    resize_clipped,
    template_applied,
};

const LupiExportStatus = enum {
    safe,
    project_invalid,
    map_budget_exceeded,
    lua_budget_exceeded,
    asset_missing,
    asset_incompatible,
};
const Mode = enum { edit, preview };
const Presentation = enum { playful, studio };
const EntityTextTarget = enum { none, schema_name, field_name };
const EntitySchemaNumber = enum { default_value, minimum, maximum };

const Rect = struct { x: i32, y: i32, w: i32, h: i32 };
const Canvas = struct { rect: Rect, cell: i32, content: Rect };
const Selection = struct {
    first: model.Point,
    last: model.Point,

    fn width(self: Selection) u16 {
        return @max(self.first.x, self.last.x) - @min(self.first.x, self.last.x) + 1;
    }

    fn height(self: Selection) u16 {
        return @max(self.first.y, self.last.y) - @min(self.first.y, self.last.y) + 1;
    }
};
const Layout = struct {
    left: i32,
    right: i32,
    tool_y: i32,
    tool_step: i32,
    layer_y: i32,
    palette_y: i32,
    palette_cell: i32,
};

const Atlas = struct {
    texture: ?*c.SDL_Texture = null,
    columns: i32 = 16,
    rows: i32 = 0,
    tile_width: i32 = 16,
    tile_height: i32 = 16,
    tile_count: u16 = 0,
    asset_name: [128]u8 = .{0} ** 128,
    asset_name_length: u8 = 0,

    fn deinit(self: *Atlas) void {
        if (self.texture) |texture| c.SDL_DestroyTexture(texture);
        self.* = .{};
    }

    fn setAssetName(self: *Atlas, name: []const u8) void {
        std.debug.assert(name.len < self.asset_name.len);
        @memset(&self.asset_name, 0);
        @memcpy(self.asset_name[0..name.len], name);
        self.asset_name_length = @intCast(name.len);
    }
};

const WorkspaceAssets = struct {
    catalog: assets.Catalog = .{},
    asset_file_verified: [assets.max_assets]bool = .{false} ** assets.max_assets,
    palette: assets.Palette = assets.Palette.diagnostic(),
};

// -----------------------------------------------------------------------------
// Authoring session state

/// Session controller for one Workshop window.
///
/// The project and history are authoritative. Selection, visibility, locks,
/// notices, previews, and presentation choices are deliberately session-only.
const Studio = struct {
    allocator: std.mem.Allocator,
    project: model.Project,
    history: model.History,
    stroke: model.CommandBuilder,
    project_path: []const u8,
    export_path: []const u8,
    mode: Mode = .edit,
    tool: Tool = .brush,
    active_layer: u8 = 1,
    selected_tile: u16 = 0,
    palette_page: u16 = 0,
    cursor: model.Point = .{ .x = 1, .y = 1 },
    selection: ?Selection = null,
    shape: ?Selection = null,
    stamp: model.Stamp = .{},
    selected_entity_kind: model.EntityKind = .enemy,
    selected_entity_field: u8 = 0,
    selected_entity_value: u16 = 0,
    entity_schema_editing: bool = false,
    entity_text_target: EntityTextTarget = .none,
    entity_text_buffer: [model.max_entity_name_length]u8 = .{0} ** model.max_entity_name_length,
    entity_text_length: u8 = 0,
    template_panel: bool = false,
    selected_template: model.ProjectTemplate = .platformer,
    quit_dialog: bool = false,
    quit_selection: u1 = 0,
    resize_width: u16,
    resize_height: u16,
    resize_anchor: model.ResizeAnchor = .center,
    resize_report: model.ResizeReport = .{},
    layer_visible: [model.layer_count]bool = .{true} ** model.layer_count,
    layer_locked: [model.layer_count]bool = .{false} ** model.layer_count,
    dragging: bool = false,
    selecting: bool = false,
    shaping: bool = false,
    shape_filled: bool = false,
    erase_drag: bool = false,
    pointer_button: u8 = 0,
    notice: Notice = .none,
    last_saved_revision: u64 = 0,
    presentation: Presentation = .playful,
    asset_page: u8 = 0,
    reduce_motion: bool = false,
    guide_pulse: u16 = 0,

    fn deinit(self: *Studio) void {
        self.stroke.deinit();
        self.history.deinit();
        self.project.deinit();
        self.* = undefined;
    }

    fn dirty(self: Studio) bool {
        return self.project.revision != self.last_saved_revision;
    }

    fn requestQuit(self: *Studio, running: *bool) void {
        if (self.dragging) self.finishStroke() catch {
            self.notice = .edit_failed;
            return;
        };
        if (self.shaping) self.finishShape() catch {
            self.notice = .edit_failed;
            return;
        };
        self.selecting = false;
        self.pointer_button = 0;
        if (self.dirty() or self.entity_text_target != .none) {
            self.quit_dialog = true;
            self.quit_selection = 0;
        } else running.* = false;
    }

    fn confirmQuit(self: *Studio, running: *bool) void {
        if (self.quit_selection == 0) {
            self.finishEntityText(true) catch {
                self.notice = .edit_failed;
                return;
            };
            self.save();
            if (!self.dirty()) running.* = false;
        } else running.* = false;
    }

    fn finishStroke(self: *Studio) !void {
        if (try self.stroke.finish()) |command| try self.history.commit(command);
        self.dragging = false;
        self.erase_drag = false;
        self.pointer_button = 0;
    }

    fn applyAt(self: *Studio, point: model.Point, erase_override: bool, immediate: bool) !void {
        self.cursor = point;
        if (toolWritesLayer(self.tool) and self.layer_locked[self.active_layer]) {
            self.notice = .layer_locked;
            return;
        }
        const index = self.project.cellIndex(point.x, point.y);
        const effective_tool: Tool = if (erase_override and self.tool != .collision and self.tool != .entity) .erase else self.tool;
        switch (effective_tool) {
            .brush => try self.stroke.setRawTile(&self.project, self.active_layer, index, self.selected_tile),
            .smart => {
                self.selected_tile = @min(self.selected_tile, model.max_tile_id - 15);
                try self.stroke.paintSmartTerrain(&self.project, self.active_layer, index, if (erase_override) null else self.selected_tile);
            },
            .erase => try self.stroke.setRawTile(&self.project, self.active_layer, index, model.empty_tile),
            .fill => try self.stroke.floodFill(&self.project, self.active_layer, index, self.selected_tile),
            .pick => {
                const value = self.project.layerCells(self.active_layer)[index];
                if (value != model.empty_tile) self.selected_tile = value;
            },
            .collision => try self.stroke.setSolid(&self.project, index, !erase_override),
            .spawn => try self.stroke.setSpawn(&self.project, point),
            .goal => try self.stroke.setGoal(&self.project, point),
            .entity => try self.placeEntity(index, erase_override),
            .select, .line, .rectangle, .resize => return,
            .stamp => {
                if (!self.stamp.valid()) {
                    self.notice = .stamp_missing;
                    return;
                }
                try self.stroke.stamp(&self.project, self.active_layer, point, self.stamp);
            },
        }
        if (immediate or effective_tool == .fill or effective_tool == .pick or effective_tool == .spawn or effective_tool == .goal or effective_tool == .entity or effective_tool == .stamp) {
            try self.finishStroke();
        }
    }

    fn placeEntity(self: *Studio, index: usize, erase: bool) !void {
        if (erase) {
            try self.stroke.setEntity(&self.project, index, .none, 0);
            return;
        }
        const first_value = if (self.selected_entity_field == 0)
            self.selected_entity_value
        else
            self.project.entityFieldDefault(self.selected_entity_kind, 0);
        try self.stroke.setEntity(&self.project, index, self.selected_entity_kind, first_value);
        if (self.selected_entity_field != 0) {
            try self.stroke.setEntityField(
                &self.project,
                index,
                self.selected_entity_field,
                self.selected_entity_value,
            );
        }
    }

    fn syncSelectedEntityValue(self: *Studio) void {
        const index = self.project.cellIndex(self.cursor.x, self.cursor.y);
        const current_kind = self.project.entityKindAt(index);
        const field_count = self.project.entityFieldCount(self.selected_entity_kind);
        if (self.selected_entity_field >= field_count) self.selected_entity_field = 0;
        if (current_kind == self.selected_entity_kind) {
            self.selected_entity_value = self.project.entityFieldAt(index, self.selected_entity_field);
        } else {
            self.selected_entity_value = self.project.entityFieldDefault(
                self.selected_entity_kind,
                self.selected_entity_field,
            );
        }
    }

    fn selectEntityField(self: *Studio, field: usize) void {
        if (field >= model.max_entity_fields or field >= self.project.entityFieldCount(self.selected_entity_kind)) return;
        self.selected_entity_field = @intCast(field);
        self.syncSelectedEntityValue();
    }

    fn adjustEntityValue(self: *Studio, delta: i32) void {
        const kind = self.selected_entity_kind;
        const field: usize = self.selected_entity_field;
        const minimum = self.project.entityFieldMinimum(kind, field);
        const maximum = self.project.entityFieldMaximum(kind, field);
        self.selected_entity_value = @intCast(std.math.clamp(@as(i32, self.selected_entity_value) + delta, minimum, maximum));
        self.notice = .entity_changed;
    }

    fn beginEntityText(self: *Studio, target: EntityTextTarget) void {
        const source = switch (target) {
            .none => return,
            .schema_name => self.project.entitySchemaName(self.selected_entity_kind),
            .field_name => self.project.entityFieldName(
                self.selected_entity_kind,
                self.selected_entity_field,
            ),
        };
        @memset(&self.entity_text_buffer, 0);
        @memcpy(self.entity_text_buffer[0..source.len], source);
        self.entity_text_length = @intCast(source.len);
        self.entity_text_target = target;
        c.SDL_StartTextInput();
    }

    fn appendEntityText(self: *Studio, text: []const u8) void {
        const maximum: usize = if (self.entity_text_target == .schema_name)
            model.max_entity_name_length
        else
            model.max_entity_field_name_length;
        for (text) |byte| {
            if (byte == 0) break;
            if (byte < 32 or byte > 126 or self.entity_text_length >= maximum) continue;
            self.entity_text_buffer[self.entity_text_length] = byte;
            self.entity_text_length += 1;
        }
    }

    fn finishEntityText(self: *Studio, commit: bool) !void {
        const target = self.entity_text_target;
        if (target == .none) return;
        if (commit and self.entity_text_length > 0) {
            const value = self.entity_text_buffer[0..self.entity_text_length];
            switch (target) {
                .none => unreachable,
                .schema_name => _ = try self.history.setEntitySchemaName(
                    &self.project,
                    self.selected_entity_kind,
                    value,
                ),
                .field_name => _ = try self.history.setEntityFieldSchema(
                    &self.project,
                    self.selected_entity_kind,
                    self.selected_entity_field,
                    value,
                    self.project.entityFieldKind(self.selected_entity_kind, self.selected_entity_field),
                    self.project.entityFieldDefault(self.selected_entity_kind, self.selected_entity_field),
                    self.project.entityFieldMinimum(self.selected_entity_kind, self.selected_entity_field),
                    self.project.entityFieldMaximum(self.selected_entity_kind, self.selected_entity_field),
                ),
            }
            self.notice = .entity_changed;
        }
        c.SDL_StopTextInput();
        self.entity_text_target = .none;
        self.entity_text_length = 0;
    }

    fn updateEntityFieldSchema(
        self: *Studio,
        field_kind: model.EntityFieldKind,
        default_value: u16,
        minimum: u16,
        maximum: u16,
    ) !void {
        _ = try self.history.setEntityFieldSchema(
            &self.project,
            self.selected_entity_kind,
            self.selected_entity_field,
            self.project.entityFieldName(self.selected_entity_kind, self.selected_entity_field),
            field_kind,
            default_value,
            minimum,
            maximum,
        );
        self.syncSelectedEntityValue();
        self.notice = .entity_changed;
    }

    fn cycleEntityFieldKind(self: *Studio) !void {
        const field = self.selected_entity_field;
        const current = self.project.entityFieldKind(self.selected_entity_kind, field);
        const next: model.EntityFieldKind = @enumFromInt((@intFromEnum(current) + 1) % 3);
        const type_maximum: u16 = switch (next) {
            .unsigned => std.math.maxInt(u16),
            .toggle => 1,
            .tile => model.max_tile_id,
        };
        const previous_type_maximum: u16 = switch (current) {
            .unsigned => std.math.maxInt(u16),
            .toggle => 1,
            .tile => model.max_tile_id,
        };
        const minimum = @min(self.project.entityFieldMinimum(self.selected_entity_kind, field), type_maximum);
        const previous_maximum = self.project.entityFieldMaximum(self.selected_entity_kind, field);
        const maximum = @max(
            minimum,
            if (previous_maximum == previous_type_maximum)
                type_maximum
            else
                @min(previous_maximum, type_maximum),
        );
        const default_value = std.math.clamp(
            self.project.entityFieldDefault(self.selected_entity_kind, field),
            minimum,
            maximum,
        );
        try self.updateEntityFieldSchema(next, default_value, minimum, maximum);
    }

    fn adjustEntitySchemaNumber(self: *Studio, number: EntitySchemaNumber, delta: i32) !void {
        const kind = self.selected_entity_kind;
        const field = self.selected_entity_field;
        const field_kind = self.project.entityFieldKind(kind, field);
        var default_value = self.project.entityFieldDefault(kind, field);
        var minimum = self.project.entityFieldMinimum(kind, field);
        var maximum = self.project.entityFieldMaximum(kind, field);
        switch (number) {
            .default_value => default_value = @intCast(std.math.clamp(
                @as(i32, default_value) + delta,
                minimum,
                maximum,
            )),
            .minimum => minimum = @intCast(std.math.clamp(
                @as(i32, minimum) + delta,
                0,
                default_value,
            )),
            .maximum => {
                const type_maximum: u16 = switch (field_kind) {
                    .unsigned => std.math.maxInt(u16),
                    .toggle => 1,
                    .tile => model.max_tile_id,
                };
                maximum = @intCast(std.math.clamp(
                    @as(i32, maximum) + delta,
                    default_value,
                    type_maximum,
                ));
            },
        }
        try self.updateEntityFieldSchema(field_kind, default_value, minimum, maximum);
    }

    fn addEntityField(self: *Studio) !void {
        const field = self.project.entityFieldCount(self.selected_entity_kind);
        if (field >= model.max_entity_fields) return;
        var name_buffer: [model.max_entity_field_name_length]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buffer, "field_{d}", .{field + 1}) catch return;
        self.selected_entity_field = @intCast(field);
        _ = try self.history.setEntityFieldSchema(
            &self.project,
            self.selected_entity_kind,
            field,
            name,
            .unsigned,
            0,
            0,
            std.math.maxInt(u16),
        );
        self.syncSelectedEntityValue();
        self.notice = .entity_changed;
    }

    fn removeEntityField(self: *Studio) !void {
        const count = self.project.entityFieldCount(self.selected_entity_kind);
        if (count <= 1 or self.selected_entity_field + 1 != count) return;
        _ = try self.history.setEntityFieldSchema(
            &self.project,
            self.selected_entity_kind,
            self.selected_entity_field,
            "",
            .unsigned,
            0,
            0,
            std.math.maxInt(u16),
        );
        self.selected_entity_field -= 1;
        self.syncSelectedEntityValue();
        self.notice = .entity_changed;
    }

    fn beginShape(self: *Studio, point: model.Point, erase: bool, filled: bool) void {
        if (self.layer_locked[self.active_layer]) {
            self.notice = .layer_locked;
            return;
        }
        self.cursor = point;
        self.shape = .{ .first = point, .last = point };
        self.shaping = true;
        self.erase_drag = erase;
        self.shape_filled = filled;
    }

    fn finishShape(self: *Studio) !void {
        const shape = self.shape orelse return;
        if (!self.shaping) return;
        const tile = if (self.erase_drag) model.empty_tile else self.selected_tile;
        switch (self.tool) {
            .line => try self.stroke.drawLine(
                &self.project,
                self.active_layer,
                shape.first,
                shape.last,
                tile,
            ),
            .rectangle => try self.stroke.drawRectangle(
                &self.project,
                self.active_layer,
                shape.first,
                shape.last,
                tile,
                self.shape_filled,
            ),
            else => return,
        }
        try self.finishStroke();
        self.shaping = false;
        self.pointer_button = 0;
        self.notice = .shape_applied;
    }

    fn beginOrFinishShape(self: *Studio, point: model.Point, erase: bool, filled: bool) !void {
        if (self.shaping) {
            if (self.shape) |*shape| shape.last = point;
            try self.finishShape();
        } else self.beginShape(point, erase, filled);
    }

    fn finishSelection(self: *Studio) !void {
        const selection = self.selection orelse return;
        self.stamp = try model.Stamp.capture(self.project, self.active_layer, selection.first, selection.last);
        self.cursor = selection.last;
        self.tool = .stamp;
        self.selecting = false;
        self.pointer_button = 0;
        self.notice = .stamp_captured;
    }

    fn finishPointerGesture(self: *Studio) !void {
        if (self.dragging) try self.finishStroke();
        if (self.shaping) try self.finishShape();
        if (self.selecting) try self.finishSelection();
        self.pointer_button = 0;
    }

    fn chooseTool(self: *Studio, tool: Tool) !void {
        try self.finishPointerGesture();
        self.tool = tool;
        if (tool != .entity) self.entity_schema_editing = false;
        self.template_panel = false;
        self.dragging = false;
        self.selecting = false;
        self.shaping = false;
        self.shape = null;
        self.pointer_button = 0;
    }

    fn transformStamp(self: *Studio, transform: enum { horizontal, vertical, clockwise }) void {
        if (!self.stamp.valid()) {
            self.notice = .stamp_missing;
            return;
        }
        switch (transform) {
            .horizontal => self.stamp.flipHorizontal(),
            .vertical => self.stamp.flipVertical(),
            .clockwise => self.stamp.rotateClockwise(),
        }
        self.notice = .stamp_transformed;
    }

    fn moveCursor(self: *Studio, x_delta: i32, y_delta: i32) void {
        self.cursor.x = @intCast(std.math.clamp(@as(i32, self.cursor.x) + x_delta, 0, self.project.width - 1));
        self.cursor.y = @intCast(std.math.clamp(@as(i32, self.cursor.y) + y_delta, 0, self.project.height - 1));
        if (self.tool == .entity) {
            const current_kind = self.project.entityKindAt(
                self.project.cellIndex(self.cursor.x, self.cursor.y),
            );
            if (current_kind != .none) self.selected_entity_kind = current_kind;
            self.syncSelectedEntityValue();
        }
    }

    fn cycleProjectTemplate(self: *Studio, direction: i32) void {
        const current: i32 = @intFromEnum(self.selected_template);
        const next: usize = @intCast(@mod(
            current + direction,
            @as(i32, @intCast(model.project_templates.len)),
        ));
        self.selected_template = model.project_templates[next];
    }

    fn applyProjectTemplate(self: *Studio) !void {
        try self.finishPointerGesture();
        try self.history.applyProjectTemplate(&self.project, self.selected_template);
        self.syncGeometry();
        self.stamp = .{};
        self.template_panel = false;
        self.notice = .template_applied;
    }

    fn adjustResize(self: *Studio, width_delta: i32, height_delta: i32) void {
        self.resize_width = @intCast(std.math.clamp(
            @as(i32, self.resize_width) + width_delta,
            4,
            model.max_dimension,
        ));
        self.resize_height = @intCast(std.math.clamp(
            @as(i32, self.resize_height) + height_delta,
            4,
            model.max_dimension,
        ));
    }

    fn cycleResizeAnchor(self: *Studio, direction: i32) void {
        const current: i32 = @intFromEnum(self.resize_anchor);
        const next: usize = @intCast(@mod(
            current + direction,
            @as(i32, @intCast(model.resize_anchors.len)),
        ));
        self.resize_anchor = model.resize_anchors[next];
    }

    fn syncGeometry(self: *Studio) void {
        self.cursor.x = @min(self.cursor.x, self.project.width - 1);
        self.cursor.y = @min(self.cursor.y, self.project.height - 1);
        self.resize_width = self.project.width;
        self.resize_height = self.project.height;
        self.resize_report = .{};
        self.selection = null;
        self.shape = null;
        self.selecting = false;
        self.shaping = false;
        self.syncSelectedEntityValue();
    }

    fn applyResize(self: *Studio) !void {
        try self.finishPointerGesture();
        const report = try self.history.resize(
            &self.project,
            self.resize_width,
            self.resize_height,
            self.resize_anchor,
        );
        if (!report.changed) return;
        self.syncGeometry();
        self.resize_report = report;
        self.notice = if (report.clipped()) .resize_clipped else .resize_applied;
    }

    fn cycleEntityKind(self: *Studio, direction: i32) void {
        const current = @intFromEnum(self.selected_entity_kind) - 1;
        const next: usize = @intCast(@mod(
            @as(i32, current) + direction,
            @as(i32, @intCast(model.entity_kinds.len)),
        ));
        self.selected_entity_kind = model.entity_kinds[next];
        self.selected_entity_field = 0;
        self.syncSelectedEntityValue();
        self.notice = .entity_changed;
    }

    fn togglePresentation(self: *Studio) !void {
        try self.finishPointerGesture();
        self.presentation = if (self.presentation == .playful) .studio else .playful;
        self.notice = .none;
    }

    fn save(self: *Studio) void {
        model.save(self.project_path, self.project) catch {
            self.notice = .save_failed;
            return;
        };
        self.last_saved_revision = self.project.revision;
        self.notice = .saved;
    }

    fn exportMap(self: *Studio, workspace: *const WorkspaceAssets) void {
        if (lupiExportStatus(self.project, workspace) != .safe) {
            self.notice = .lupi_export_blocked;
            return;
        }
        model.exportLuaFile(self.export_path, self.project) catch {
            self.notice = .export_failed;
            return;
        };
        self.notice = .exported;
    }

    fn togglePreview(self: *Studio) !void {
        try self.finishPointerGesture();
        if (self.mode == .preview) {
            self.mode = .edit;
            return;
        }
        if (!model.validate(self.project).valid()) {
            self.notice = .invalid_preview;
            return;
        }
        self.mode = .preview;
        self.notice = .none;
    }
};

// -----------------------------------------------------------------------------
// SDL application lifecycle

fn verifyAtlasIdentity(allocator: std.mem.Allocator) !void {
    var project = try model.Project.init(allocator, 4, 4, 8, "tiles/first");
    defer project.deinit();
    var atlases: [model.layer_count]Atlas = .{Atlas{}} ** model.layer_count;
    for (&atlases, 0..) |*atlas, layer| {
        atlas.setAssetName(project.layerTilesetName(layer));
    }
    if (atlasesNeedReload(project, atlases)) return error.AtlasIdentityMismatch;

    project.setLayerTilesetName(1, "tiles/second");
    if (!atlasesNeedReload(project, atlases)) return error.AtlasIdentityMismatch;
    atlases[1].setAssetName(project.layerTilesetName(1));
    if (atlasesNeedReload(project, atlases)) return error.AtlasIdentityMismatch;
    std.debug.print("Workshop atlas identity: pass\n", .{});
}

pub fn main(init: std.process.Init) !void {
    var project_path: []const u8 = "save/world.elisworld";
    var export_path: []const u8 = "save/world.lua";
    var tileset_name: []const u8 = "tiles/world";
    var tileset_explicit = false;
    var tileset_file: ?[]const u8 = null;
    var game_root: ?[]const u8 = null;
    var width = default_width;
    var height = default_height;
    var tile_size = default_tile_size;
    var smoke_frames: ?u32 = null;
    var capture_path: ?[]const u8 = null;
    var save_export_on_start = false;
    var presentation: Presentation = .playful;
    var project_template: ?model.ProjectTemplate = null;
    var reduce_motion = false;
    var self_test_atlas_identity = false;
    var window_width: i32 = 1280;
    var window_height: i32 = 760;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    defer args.deinit();
    _ = args.skip();
    while (args.next()) |argument| {
        if (std.mem.startsWith(u8, argument, "--project=")) {
            project_path = argument["--project=".len..];
        } else if (std.mem.startsWith(u8, argument, "--export=")) {
            export_path = argument["--export=".len..];
        } else if (std.mem.startsWith(u8, argument, "--tileset-name=")) {
            tileset_name = argument["--tileset-name=".len..];
            tileset_explicit = true;
        } else if (std.mem.startsWith(u8, argument, "--tileset-file=")) {
            tileset_file = argument["--tileset-file=".len..];
        } else if (std.mem.startsWith(u8, argument, "--game-root=")) {
            game_root = argument["--game-root=".len..];
        } else if (std.mem.startsWith(u8, argument, "--width=")) {
            width = try std.fmt.parseUnsigned(u16, argument["--width=".len..], 10);
        } else if (std.mem.startsWith(u8, argument, "--height=")) {
            height = try std.fmt.parseUnsigned(u16, argument["--height=".len..], 10);
        } else if (std.mem.startsWith(u8, argument, "--tile-size=")) {
            tile_size = try std.fmt.parseUnsigned(u16, argument["--tile-size=".len..], 10);
        } else if (std.mem.eql(u8, argument, "--smoke")) {
            smoke_frames = 12;
        } else if (std.mem.eql(u8, argument, "--save-export")) {
            save_export_on_start = true;
        } else if (std.mem.startsWith(u8, argument, "--capture=")) {
            capture_path = argument["--capture=".len..];
        } else if (std.mem.eql(u8, argument, "--presentation=studio")) {
            presentation = .studio;
        } else if (std.mem.eql(u8, argument, "--presentation=playful")) {
            presentation = .playful;
        } else if (std.mem.eql(u8, argument, "--reduce-motion")) {
            reduce_motion = true;
        } else if (std.mem.eql(u8, argument, "--self-test-atlas-identity")) {
            self_test_atlas_identity = true;
        } else if (std.mem.startsWith(u8, argument, "--template=")) {
            project_template = try model.projectTemplateFromName(argument["--template=".len..]);
        } else if (std.mem.startsWith(u8, argument, "--window-width=")) {
            window_width = try std.fmt.parseInt(i32, argument["--window-width=".len..], 10);
        } else if (std.mem.startsWith(u8, argument, "--window-height=")) {
            window_height = try std.fmt.parseInt(i32, argument["--window-height=".len..], 10);
        } else if (std.mem.eql(u8, argument, "--help") or std.mem.eql(u8, argument, "-h")) {
            std.debug.print(
                "Usage: elis-studio [--project=file] [--export=file] [--tileset-name=name] " ++
                    "[--tileset-file=raw-bitmap] [--game-root=game] [--width=N] [--height=N] [--tile-size=N] " ++
                    "[--presentation=playful|studio] [--template=blank|platformer|arena|puzzle] " ++
                    "[--reduce-motion] [--window-width=N] [--window-height=N] " ++
                    "[--save-export] [--smoke] [--capture=file.bmp]\n",
                .{},
            );
            return;
        } else return error.UnknownStudioArgument;
    }

    const allocator = init.gpa;
    if (self_test_atlas_identity) return verifyAtlasIdentity(allocator);
    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_GAMECONTROLLER | c.SDL_INIT_JOYSTICK) != 0) return error.SdlInit;
    defer c.SDL_Quit();
    const workspace_assets = loadWorkspaceAssets(allocator, game_root);
    if (smoke_frames != null and game_root != null) {
        if (workspace_assets.catalog.count == 0) return error.StudioManifestMissingBitmaps;
        if (!workspace_assets.palette.exact()) return error.StudioPaletteMissing;
    }
    if (window_width < 960 or window_height < 600) return error.StudioWindowTooSmall;
    if (!tileset_explicit) if (workspace_assets.catalog.firstTileSize(tile_size)) |first| {
        tileset_name = workspace_assets.catalog.items[first].name();
    };
    var project = if (fileExists(project_path))
        try model.load(allocator, project_path)
    else if (project_template) |template|
        try model.initProjectTemplate(allocator, width, height, tile_size, tileset_name, template)
    else
        try model.Project.initStarter(allocator, width, height, tile_size, tileset_name);
    errdefer project.deinit();
    var studio = Studio{
        .allocator = allocator,
        .project = project,
        .history = model.History.init(allocator),
        .stroke = model.CommandBuilder.init(allocator),
        .project_path = project_path,
        .export_path = export_path,
        .resize_width = project.width,
        .resize_height = project.height,
        .last_saved_revision = project.revision,
        .presentation = presentation,
        .reduce_motion = reduce_motion,
    };
    defer studio.deinit();
    studio.syncSelectedEntityValue();
    if (save_export_on_start) {
        studio.save();
        studio.exportMap(&workspace_assets);
        if (studio.notice == .save_failed or studio.notice == .export_failed or
            studio.notice == .lupi_export_blocked)
        {
            return error.StudioWriteFailed;
        }
    }

    _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "0");
    const window = c.SDL_CreateWindow(
        "ELIS Workshop  |  Learn, Paint, Build",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        window_width,
        window_height,
        c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI,
    ) orelse return error.SdlWindow;
    defer c.SDL_DestroyWindow(window);
    c.SDL_SetWindowMinimumSize(window, 960, 600);
    const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC) orelse
        c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_SOFTWARE) orelse return error.SdlRenderer;
    defer c.SDL_DestroyRenderer(renderer);
    _ = c.SDL_SetRenderDrawBlendMode(renderer, c.SDL_BLENDMODE_BLEND);

    var atlases = try loadProjectAtlases(allocator, renderer, game_root, &workspace_assets, studio.project, tileset_file);
    defer for (&atlases) |*atlas| atlas.deinit();
    var gamepad = openFirstController();
    defer if (gamepad) |controller| c.SDL_GameControllerClose(controller);
    var previous_buttons = if (gamepad) |controller|
        controllerButtons(controller)
    else
        [_]bool{false} ** c.SDL_CONTROLLER_BUTTON_MAX;
    var window_focused = true;
    var running = true;
    var frame_count: u32 = 0;
    var capture_pending = capture_path != null;
    var event: c.SDL_Event = undefined;
    while (running) {
        var window_w: c_int = 0;
        var window_h: c_int = 0;
        c.SDL_GetWindowSize(window, &window_w, &window_h);
        _ = c.SDL_RenderSetLogicalSize(renderer, window_w, window_h);
        const layout = layoutFor(window_w, window_h, studio.presentation);
        const canvas = canvasLayout(studio.project, window_w, window_h, studio.mode, layout);
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => studio.requestQuit(&running),
                c.SDL_CONTROLLERDEVICEADDED => {
                    if (gamepad == null) {
                        gamepad = openFirstController();
                        previous_buttons = if (gamepad) |controller|
                            controllerButtons(controller)
                        else
                            [_]bool{false} ** c.SDL_CONTROLLER_BUTTON_MAX;
                    }
                },
                c.SDL_CONTROLLERDEVICEREMOVED => if (gamepad) |controller| {
                    const joystick = c.SDL_GameControllerGetJoystick(controller);
                    if (c.SDL_JoystickInstanceID(joystick) == event.cdevice.which) {
                        c.SDL_GameControllerClose(controller);
                        gamepad = openFirstController();
                        previous_buttons = if (gamepad) |replacement|
                            controllerButtons(replacement)
                        else
                            [_]bool{false} ** c.SDL_CONTROLLER_BUTTON_MAX;
                    }
                },
                c.SDL_KEYDOWN => if (event.key.repeat == 0) {
                    if (studio.quit_dialog) {
                        handleQuitDialogKey(&studio, event.key.keysym.sym, &running);
                    } else if (studio.entity_text_target != .none) {
                        switch (event.key.keysym.sym) {
                            c.SDLK_ESCAPE => try studio.finishEntityText(false),
                            c.SDLK_RETURN => try studio.finishEntityText(true),
                            c.SDLK_BACKSPACE => studio.entity_text_length -|= 1,
                            else => {},
                        }
                    } else if (studio.mode == .edit and (event.key.keysym.sym == c.SDLK_COMMA or event.key.keysym.sym == c.SDLK_PERIOD)) {
                        try cycleLayerAsset(allocator, renderer, &studio, &atlases, game_root, &workspace_assets, if (event.key.keysym.sym == c.SDLK_COMMA) -1 else 1);
                    } else try handleKey(
                        allocator,
                        renderer,
                        &studio,
                        &atlases,
                        game_root,
                        &workspace_assets,
                        event.key.keysym.sym,
                        event.key.keysym.mod,
                        &running,
                    );
                },
                c.SDL_TEXTINPUT => if (!studio.quit_dialog and studio.entity_text_target != .none) {
                    studio.appendEntityText(std.mem.sliceTo(&event.text.text, 0));
                },
                c.SDL_MOUSEBUTTONDOWN => if (studio.quit_dialog) {
                    if (event.button.button == c.SDL_BUTTON_LEFT) {
                        handleQuitDialogClick(
                            &studio,
                            &running,
                            event.button.x,
                            event.button.y,
                            window_w,
                            window_h,
                        );
                    }
                } else if (studio.mode == .edit and studio.entity_text_target == .none and
                    (event.button.button == c.SDL_BUTTON_LEFT or
                        event.button.button == c.SDL_BUTTON_RIGHT))
                {
                    const point = canvasPoint(studio.project, canvas, event.button.x, event.button.y);
                    if (point) |value| {
                        if (studio.tool == .select) {
                            if (event.button.button == c.SDL_BUTTON_LEFT) {
                                studio.pointer_button = event.button.button;
                                studio.cursor = value;
                                studio.selection = .{ .first = value, .last = value };
                                studio.selecting = true;
                            }
                        } else if (studio.tool == .line or studio.tool == .rectangle) {
                            studio.pointer_button = event.button.button;
                            studio.beginShape(
                                value,
                                event.button.button == c.SDL_BUTTON_RIGHT,
                                (c.SDL_GetModState() & c.KMOD_SHIFT) != 0,
                            );
                        } else {
                            studio.pointer_button = event.button.button;
                            studio.dragging = true;
                            studio.erase_drag = event.button.button == c.SDL_BUTTON_RIGHT;
                            try studio.applyAt(value, studio.erase_drag, false);
                        }
                    } else if (event.button.button == c.SDL_BUTTON_LEFT) {
                        try handleChromeClick(
                            allocator,
                            renderer,
                            &studio,
                            &atlases,
                            game_root,
                            &workspace_assets,
                            event.button.x,
                            event.button.y,
                            window_w,
                            window_h,
                        );
                    }
                },
                c.SDL_MOUSEMOTION => if (!studio.quit_dialog and studio.mode == .edit) {
                    if (studio.selecting) {
                        if (canvasPoint(studio.project, canvas, event.motion.x, event.motion.y)) |point| {
                            studio.cursor = point;
                            if (studio.selection) |*selection| selection.last = point;
                        }
                    } else if (studio.shaping) {
                        if (canvasPoint(studio.project, canvas, event.motion.x, event.motion.y)) |point| {
                            studio.cursor = point;
                            if (studio.shape) |*shape| shape.last = point;
                        }
                    } else if (studio.dragging) {
                        if (canvasPoint(studio.project, canvas, event.motion.x, event.motion.y)) |point| {
                            try studio.applyAt(point, studio.erase_drag, false);
                        }
                    }
                },
                c.SDL_MOUSEBUTTONUP => if (!studio.quit_dialog and
                    event.button.button == studio.pointer_button)
                {
                    try studio.finishPointerGesture();
                },
                c.SDL_MOUSEWHEEL => if (!studio.quit_dialog and studio.mode == .edit and
                    studio.entity_text_target == .none)
                {
                    if (event.wheel.y > 0) previousTile(&studio) else if (event.wheel.y < 0) nextTile(&studio, atlases[studio.active_layer].tile_count);
                },
                c.SDL_WINDOWEVENT => switch (event.window.event) {
                    c.SDL_WINDOWEVENT_FOCUS_LOST => {
                        try studio.finishPointerGesture();
                        window_focused = false;
                    },
                    c.SDL_WINDOWEVENT_FOCUS_GAINED => {
                        window_focused = true;
                        if (gamepad) |controller| {
                            // A button held while another application had
                            // focus must not become a fresh editor command.
                            previous_buttons = controllerButtons(controller);
                        }
                    },
                    else => {},
                },
                else => {},
            }
        }
        if (window_focused and (studio.quit_dialog or studio.entity_text_target == .none)) {
            if (gamepad) |controller| try handleController(
                allocator,
                renderer,
                &studio,
                &atlases,
                game_root,
                &workspace_assets,
                controller,
                &previous_buttons,
                atlases[studio.active_layer].tile_count,
                &running,
            );
        }

        try render(renderer, &studio, atlases, &workspace_assets, window_w, window_h);
        if (capture_pending) {
            try captureRenderer(renderer, capture_path.?);
            capture_pending = false;
        }
        c.SDL_RenderPresent(renderer);
        studio.guide_pulse +%= 1;
        frame_count += 1;
        if (smoke_frames) |limit| {
            if (frame_count >= limit) running = false;
        }
    }
}

// -----------------------------------------------------------------------------
// Keyboard, pointer, and controller dispatch

fn handleQuitDialogKey(studio: *Studio, key: c.SDL_Keycode, running: *bool) void {
    switch (key) {
        c.SDLK_ESCAPE => studio.quit_dialog = false,
        c.SDLK_UP, c.SDLK_DOWN => studio.quit_selection = 1 - studio.quit_selection,
        c.SDLK_RETURN, c.SDLK_SPACE => studio.confirmQuit(running),
        else => {},
    }
}

fn quitDialogButtonRect(width: i32, height: i32, selection: u1) Rect {
    return .{
        .x = @divTrunc(width - 360, 2),
        .y = @divTrunc(height - 230, 2) + 92 + @as(i32, selection) * 54,
        .w = 360,
        .h = 44,
    };
}

fn handleQuitDialogClick(
    studio: *Studio,
    running: *bool,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
) void {
    for (0..2) |index| {
        const selection: u1 = @intCast(index);
        if (!contains(quitDialogButtonRect(width, height, selection), x, y)) continue;
        studio.quit_selection = selection;
        studio.confirmQuit(running);
        return;
    }
}

fn handleKey(
    allocator: std.mem.Allocator,
    renderer: *c.SDL_Renderer,
    studio: *Studio,
    atlases: *[model.layer_count]Atlas,
    game_root: ?[]const u8,
    workspace: *const WorkspaceAssets,
    key: c.SDL_Keycode,
    modifiers: c.SDL_Keymod,
    running: *bool,
) !void {
    const ctrl = (modifiers & c.KMOD_CTRL) != 0;
    const shift = (modifiers & c.KMOD_SHIFT) != 0;
    const alt = (modifiers & c.KMOD_ALT) != 0;
    if (studio.mode == .preview) {
        if (key == c.SDLK_F7 or key == c.SDLK_ESCAPE or key == c.SDLK_BACKSPACE) studio.mode = .edit;
        return;
    }
    if (studio.template_panel) {
        switch (key) {
            c.SDLK_ESCAPE, c.SDLK_F8 => studio.template_panel = false,
            c.SDLK_UP => studio.cycleProjectTemplate(-1),
            c.SDLK_DOWN => studio.cycleProjectTemplate(1),
            c.SDLK_RETURN, c.SDLK_SPACE => try studio.applyProjectTemplate(),
            else => {},
        }
        if (key == c.SDLK_ESCAPE or key == c.SDLK_F8 or key == c.SDLK_UP or
            key == c.SDLK_DOWN or key == c.SDLK_RETURN or key == c.SDLK_SPACE)
        {
            return;
        }
    }
    switch (key) {
        c.SDLK_ESCAPE => {
            if (studio.entity_schema_editing) {
                studio.entity_schema_editing = false;
            } else if (studio.shaping or studio.selecting) {
                studio.shaping = false;
                studio.selecting = false;
                studio.shape = null;
            } else studio.requestQuit(running);
        },
        c.SDLK_TAB => try studio.togglePresentation(),
        c.SDLK_b => try studio.chooseTool(.brush),
        c.SDLK_t => try studio.chooseTool(.smart),
        c.SDLK_e => try studio.chooseTool(.erase),
        c.SDLK_f => try studio.chooseTool(.fill),
        c.SDLK_p => try studio.chooseTool(.pick),
        c.SDLK_i => {
            try studio.chooseTool(.entity);
            if (shift) studio.entity_schema_editing = true;
        },
        c.SDLK_r => try studio.chooseTool(.select),
        c.SDLK_m => try studio.chooseTool(.stamp),
        c.SDLK_l => try studio.chooseTool(.line),
        c.SDLK_d => try studio.chooseTool(.rectangle),
        c.SDLK_n => try studio.chooseTool(.resize),
        c.SDLK_q => {
            if (studio.tool == .resize) {
                studio.cycleResizeAnchor(1);
            } else if (studio.tool == .entity) studio.cycleEntityKind(1);
        },
        c.SDLK_k => {
            if (studio.tool == .entity and studio.entity_schema_editing) {
                try studio.cycleEntityFieldKind();
            }
        },
        c.SDLK_INSERT => {
            if (studio.tool == .entity and studio.entity_schema_editing) try studio.addEntityField();
        },
        c.SDLK_h => studio.transformStamp(.horizontal),
        c.SDLK_o => studio.transformStamp(.clockwise),
        c.SDLK_MINUS => {
            if (studio.tool == .resize) {
                studio.adjustResize(if (shift) 0 else -1, if (shift) -1 else 0);
            } else if (studio.tool == .entity and studio.entity_schema_editing) {
                try studio.adjustEntitySchemaNumber(
                    if (alt) .maximum else if (shift) .minimum else .default_value,
                    -1,
                );
            } else if (studio.tool == .entity) {
                studio.adjustEntityValue(-1);
            }
        },
        c.SDLK_EQUALS => {
            if (studio.tool == .resize) {
                studio.adjustResize(if (shift) 0 else 1, if (shift) 1 else 0);
            } else if (studio.tool == .entity and studio.entity_schema_editing) {
                try studio.adjustEntitySchemaNumber(
                    if (alt) .maximum else if (shift) .minimum else .default_value,
                    1,
                );
            } else if (studio.tool == .entity) {
                studio.adjustEntityValue(1);
            }
        },
        c.SDLK_c => {
            if (ctrl) {
                try studio.finishSelection();
            } else try studio.chooseTool(.collision);
        },
        c.SDLK_s => {
            if (ctrl) studio.save() else try studio.chooseTool(.spawn);
        },
        c.SDLK_g => try studio.chooseTool(.goal),
        c.SDLK_1, c.SDLK_2, c.SDLK_3, c.SDLK_4 => {
            const layer: usize = @intCast(key - c.SDLK_1);
            if (shift) {
                studio.layer_visible[layer] = !studio.layer_visible[layer];
                studio.notice = .layer_visibility;
            } else if (alt) {
                studio.layer_locked[layer] = !studio.layer_locked[layer];
                studio.notice = .layer_lock_changed;
            } else studio.active_layer = @intCast(layer);
        },
        c.SDLK_LEFTBRACKET => {
            if (studio.tool == .entity) {
                studio.selectEntityField(@as(usize, studio.selected_entity_field) -| 1);
            } else previousTile(studio);
        },
        c.SDLK_RIGHTBRACKET => {
            if (studio.tool == .entity) {
                studio.selectEntityField(@as(usize, studio.selected_entity_field) + 1);
            } else nextTile(studio, 0);
        },
        c.SDLK_PAGEUP => {
            if (studio.palette_page > 0) studio.palette_page -= 1;
        },
        c.SDLK_PAGEDOWN => studio.palette_page = @min(studio.palette_page + 1, 15),
        c.SDLK_z => {
            if (ctrl and try studio.history.undo(&studio.project)) {
                studio.syncGeometry();
                if (atlasesNeedReload(studio.project, atlases.*)) {
                    try reloadProjectAtlases(
                        allocator,
                        renderer,
                        studio,
                        atlases,
                        game_root,
                        workspace,
                    );
                }
            }
        },
        c.SDLK_y => {
            if (ctrl and try studio.history.redo(&studio.project)) {
                studio.syncGeometry();
                if (atlasesNeedReload(studio.project, atlases.*)) {
                    try reloadProjectAtlases(
                        allocator,
                        renderer,
                        studio,
                        atlases,
                        game_root,
                        workspace,
                    );
                }
            }
        },
        c.SDLK_v => {
            if (ctrl) {
                if (studio.stamp.valid()) {
                    try studio.chooseTool(.stamp);
                } else studio.notice = .stamp_missing;
            } else studio.transformStamp(.vertical);
        },
        c.SDLK_F5 => studio.exportMap(workspace),
        c.SDLK_F6 => try studio.togglePreview(),
        c.SDLK_F7 => studio.mode = .edit,
        c.SDLK_F8 => studio.template_panel = !studio.template_panel,
        c.SDLK_LEFT => studio.moveCursor(-1, 0),
        c.SDLK_RIGHT => studio.moveCursor(1, 0),
        c.SDLK_UP => studio.moveCursor(0, -1),
        c.SDLK_DOWN => studio.moveCursor(0, 1),
        c.SDLK_SPACE, c.SDLK_RETURN => {
            if (studio.tool == .entity and studio.entity_schema_editing) {
                studio.beginEntityText(if (shift) .schema_name else .field_name);
            } else if (studio.tool == .resize) {
                try studio.applyResize();
            } else if (studio.tool == .select) {
                if (studio.selecting) {
                    if (studio.selection) |*selection| selection.last = studio.cursor;
                    try studio.finishSelection();
                } else {
                    studio.selection = .{ .first = studio.cursor, .last = studio.cursor };
                    studio.selecting = true;
                }
            } else if (studio.tool == .line or studio.tool == .rectangle) {
                try studio.beginOrFinishShape(studio.cursor, false, shift);
            } else try studio.applyAt(studio.cursor, false, true);
        },
        c.SDLK_BACKSPACE, c.SDLK_DELETE => {
            if (studio.tool == .entity and studio.entity_schema_editing) {
                try studio.removeEntityField();
            } else if (studio.tool == .line or studio.tool == .rectangle) {
                try studio.beginOrFinishShape(studio.cursor, true, shift);
            } else try studio.applyAt(studio.cursor, true, true);
        },
        else => {},
    }
}

fn controllerButtons(
    controller: *c.SDL_GameController,
) [c.SDL_CONTROLLER_BUTTON_MAX]bool {
    var current: [c.SDL_CONTROLLER_BUTTON_MAX]bool =
        .{false} ** c.SDL_CONTROLLER_BUTTON_MAX;
    for (0..c.SDL_CONTROLLER_BUTTON_MAX) |index| {
        current[index] = c.SDL_GameControllerGetButton(controller, @intCast(index)) != 0;
    }
    return current;
}

fn handleController(
    allocator: std.mem.Allocator,
    renderer: *c.SDL_Renderer,
    studio: *Studio,
    atlases: *[model.layer_count]Atlas,
    game_root: ?[]const u8,
    workspace: *const WorkspaceAssets,
    controller: *c.SDL_GameController,
    previous: *[c.SDL_CONTROLLER_BUTTON_MAX]bool,
    tile_count: u16,
    running: *bool,
) !void {
    const current = controllerButtons(controller);
    const pressed = struct {
        fn value(now: []const bool, before: []const bool, button_index: usize) bool {
            return now[button_index] and !before[button_index];
        }
    }.value;
    if (studio.quit_dialog) {
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_UP) or
            pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_DOWN))
        {
            studio.quit_selection = 1 - studio.quit_selection;
        }
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_B)) {
            studio.quit_dialog = false;
        }
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_A)) {
            studio.confirmQuit(running);
        }
        previous.* = current;
        return;
    }
    if (studio.mode == .preview) {
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_B) or pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_BACK)) studio.mode = .edit;
        previous.* = current;
        return;
    }
    if (studio.template_panel) {
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_UP)) {
            studio.cycleProjectTemplate(-1);
        }
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_DOWN)) {
            studio.cycleProjectTemplate(1);
        }
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_B) or
            pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_BACK))
        {
            studio.template_panel = false;
        } else if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_A)) {
            try studio.finishPointerGesture();
            try studio.applyProjectTemplate();
        }
        previous.* = current;
        return;
    }
    if (studio.tool == .resize) {
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_LEFT)) studio.adjustResize(-1, 0);
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_RIGHT)) studio.adjustResize(1, 0);
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_UP)) studio.adjustResize(0, 1);
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_DOWN)) studio.adjustResize(0, -1);
    } else {
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_LEFT)) studio.moveCursor(-1, 0);
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_RIGHT)) studio.moveCursor(1, 0);
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_UP)) studio.moveCursor(0, -1);
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_DOWN)) studio.moveCursor(0, 1);
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_A)) {
        if (studio.tool == .resize) {
            try studio.applyResize();
        } else if (studio.tool == .select) {
            if (studio.selecting) {
                if (studio.selection) |*selection| selection.last = studio.cursor;
                try studio.finishSelection();
            } else {
                studio.selection = .{ .first = studio.cursor, .last = studio.cursor };
                studio.selecting = true;
            }
        } else if (studio.tool == .line or studio.tool == .rectangle) {
            try studio.beginOrFinishShape(studio.cursor, false, false);
        } else try studio.applyAt(studio.cursor, false, true);
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_B)) {
        if (studio.tool == .resize) {
            studio.resize_width = studio.project.width;
            studio.resize_height = studio.project.height;
        } else if (studio.tool == .line or studio.tool == .rectangle) {
            try studio.beginOrFinishShape(studio.cursor, true, false);
        } else try studio.applyAt(studio.cursor, true, true);
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_X)) {
        if (studio.tool == .resize) {
            studio.cycleResizeAnchor(1);
        } else {
            const value = studio.project.layerCells(studio.active_layer)[studio.project.cellIndex(studio.cursor.x, studio.cursor.y)];
            if (value != model.empty_tile) studio.selected_tile = value;
        }
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_Y)) {
        try studio.chooseTool(@enumFromInt((@intFromEnum(studio.tool) + 1) % tools.len));
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_LEFTSHOULDER)) {
        if (studio.tool == .stamp) {
            studio.transformStamp(.horizontal);
        } else if (studio.tool == .entity) {
            studio.cycleEntityKind(-1);
        } else previousTile(studio);
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER)) {
        if (studio.tool == .stamp) {
            studio.transformStamp(.vertical);
        } else if (studio.tool == .entity) {
            studio.cycleEntityKind(1);
        } else nextTile(studio, tile_count);
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_LEFTSTICK)) {
        try studio.togglePresentation();
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_RIGHTSTICK)) {
        if (studio.tool == .stamp) {
            studio.transformStamp(.clockwise);
        } else try cycleLayerAsset(allocator, renderer, studio, atlases, game_root, workspace, 1);
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_BACK)) try studio.togglePreview();
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_START)) studio.save();
    previous.* = current;
}

fn handleChromeClick(
    allocator: std.mem.Allocator,
    renderer: *c.SDL_Renderer,
    studio: *Studio,
    atlases: *[model.layer_count]Atlas,
    game_root: ?[]const u8,
    workspace: *const WorkspaceAssets,
    x: i32,
    y: i32,
    window_w: i32,
    window_h: i32,
) !void {
    const layout = layoutFor(window_w, window_h, studio.presentation);
    if (y < bar_top) {
        if (x >= 270 and x < 370) studio.save();
        if (x >= 380 and x < 490) studio.exportMap(workspace);
        if (x >= 500 and x < 620) try studio.togglePreview();
        if (x >= 630 and x < 770) try studio.togglePresentation();
        if (x >= 780 and x < 920) studio.template_panel = !studio.template_panel;
        return;
    }
    if (x < layout.left) {
        for (tools, 0..) |tool, index| {
            if (contains(toolRect(layout, index), x, y)) {
                try studio.chooseTool(tool);
                return;
            }
        }
        if (y >= layout.layer_y and y < layout.layer_y + @as(i32, model.layer_count) * layout.tool_step) {
            const layer: usize = @intCast(@divTrunc(y - layout.layer_y, layout.tool_step));
            if (x >= layout.left - 40) {
                studio.layer_locked[layer] = !studio.layer_locked[layer];
                studio.notice = .layer_lock_changed;
            } else if (x >= layout.left - 68) {
                studio.layer_visible[layer] = !studio.layer_visible[layer];
                studio.notice = .layer_visibility;
            } else {
                studio.active_layer = @intCast(layer);
                studio.palette_page = studio.selected_tile / 64;
            }
            return;
        }
    }
    if (x >= window_w - layout.right) {
        const right_x = window_w - layout.right;
        if (studio.template_panel) {
            for (model.project_templates, 0..) |template, index| {
                const row_y = 104 + @as(i32, @intCast(index)) * 38;
                if (y >= row_y and y < row_y + 32) {
                    studio.selected_template = template;
                    return;
                }
            }
            if (y >= 284 and y < 320) try studio.applyProjectTemplate();
            return;
        }
        if (studio.tool == .resize) {
            const half_width = @divTrunc(layout.right - 34, 2);
            if (contains(.{ .x = right_x + 14, .y = 112, .w = half_width, .h = 30 }, x, y)) {
                studio.adjustResize(-1, 0);
            } else if (contains(.{ .x = right_x + @divTrunc(layout.right, 2) + 3, .y = 112, .w = half_width, .h = 30 }, x, y)) {
                studio.adjustResize(1, 0);
            } else if (contains(.{ .x = right_x + 14, .y = 148, .w = half_width, .h = 30 }, x, y)) {
                studio.adjustResize(0, -1);
            } else if (contains(.{ .x = right_x + @divTrunc(layout.right, 2) + 3, .y = 148, .w = half_width, .h = 30 }, x, y)) {
                studio.adjustResize(0, 1);
            } else {
                const anchor_width = @divTrunc(layout.right - 40, 3);
                for (model.resize_anchors, 0..) |anchor, index| {
                    const anchor_rect = Rect{
                        .x = right_x + 14 + @as(i32, @intCast(index % 3)) * (anchor_width + 6),
                        .y = 206 + @as(i32, @intCast(index / 3)) * 36,
                        .w = anchor_width,
                        .h = 30,
                    };
                    if (contains(anchor_rect, x, y)) {
                        studio.resize_anchor = anchor;
                        return;
                    }
                }
                if (contains(.{ .x = right_x + 14, .y = 326, .w = layout.right - 28, .h = 34 }, x, y)) {
                    try studio.applyResize();
                }
            }
            return;
        }
        if (studio.tool == .entity) {
            if (y >= 88 and y < 116) {
                studio.entity_schema_editing = !studio.entity_schema_editing;
                return;
            }
            for (model.entity_kinds, 0..) |kind, index| {
                const row_y = 124 + @as(i32, @intCast(index)) * 34;
                if (y >= row_y and y < row_y + 28) {
                    studio.selected_entity_kind = kind;
                    studio.selected_entity_field = 0;
                    studio.syncSelectedEntityValue();
                    studio.notice = .entity_changed;
                    return;
                }
            }
            if (studio.entity_schema_editing) {
                if (y >= 278 and y < 306) {
                    studio.beginEntityText(.schema_name);
                    return;
                }
                const field_count = studio.project.entityFieldCount(studio.selected_entity_kind);
                for (0..field_count) |field| {
                    const row_y = 330 + @as(i32, @intCast(field)) * 27;
                    if (y >= row_y and y < row_y + 24) {
                        studio.selectEntityField(field);
                        return;
                    }
                }
                if (field_count < model.max_entity_fields) {
                    const add_y = 330 + @as(i32, field_count) * 27;
                    if (y >= add_y and y < add_y + 24) {
                        try studio.addEntityField();
                        return;
                    }
                }
                if (y >= 442 and y < 470) {
                    if (x < right_x + @divTrunc(layout.right, 2)) {
                        studio.beginEntityText(.field_name);
                    } else try studio.removeEntityField();
                    return;
                }
                if (y >= 474 and y < 502) {
                    try studio.cycleEntityFieldKind();
                    return;
                }
                if (y >= 508 and y < 536) {
                    try studio.adjustEntitySchemaNumber(
                        .default_value,
                        if (x < right_x + @divTrunc(layout.right, 2)) -1 else 1,
                    );
                    return;
                }
            } else {
                const value_y: i32 = 276;
                if (y >= value_y and y < value_y + 30) {
                    studio.adjustEntityValue(if (x < right_x + @divTrunc(layout.right, 2)) -1 else 1);
                    return;
                }
                const field_y: i32 = 328;
                for (0..model.max_entity_fields) |field| {
                    if (field >= studio.project.entityFieldCount(studio.selected_entity_kind)) break;
                    if (y >= field_y + @as(i32, @intCast(field)) * 27 and
                        y < field_y + @as(i32, @intCast(field + 1)) * 27)
                    {
                        studio.selectEntityField(field);
                        return;
                    }
                }
            }
            return;
        }
        if (studio.tool == .stamp) {
            if (y >= layout.palette_y and y < layout.palette_y + 32) {
                studio.transformStamp(.horizontal);
            } else if (y < layout.palette_y + 68) {
                studio.transformStamp(.vertical);
            } else if (y < layout.palette_y + 104) {
                studio.transformStamp(.clockwise);
            }
            return;
        }
        const local_x = x - right_x - 18;
        const local_y = y - layout.palette_y;
        if (local_x >= 0 and local_y >= 0 and local_x < 8 * layout.palette_cell and local_y < 8 * layout.palette_cell) {
            const slot: u16 = @intCast(@divTrunc(local_y, layout.palette_cell) * 8 + @divTrunc(local_x, layout.palette_cell));
            studio.selected_tile = studio.palette_page * 64 + slot;
            return;
        }
        const asset_y = layout.palette_y + layout.palette_cell * 8 + 44;
        if (y >= asset_y - 24 and y < asset_y - 2) {
            if (x < right_x + @divTrunc(layout.right, 2)) {
                studio.asset_page -|= 1;
            } else {
                const page_count: u8 = @intCast((compatibleAssetCount(&workspace.catalog, studio.project.tile_size) + 4) / 5);
                if (page_count > 0) studio.asset_page = @min(studio.asset_page + 1, page_count - 1);
            }
            return;
        }
        if (y >= asset_y and y < asset_y + 5 * 25) {
            const row: usize = @intCast(@divTrunc(y - asset_y, 25));
            if (compatibleAssetIndex(&workspace.catalog, studio.project.tile_size, @as(usize, studio.asset_page) * 5 + row)) |asset_index| {
                try assignLayerAsset(allocator, renderer, studio, atlases, game_root, workspace, asset_index);
            }
        }
    }
}

fn previousTile(studio: *Studio) void {
    studio.selected_tile -|= 1;
    studio.palette_page = studio.selected_tile / 64;
}

fn nextTile(studio: *Studio, available: u16) void {
    const maximum = if (available > 0) @min(available - 1, model.max_tile_id) else model.max_tile_id;
    studio.selected_tile = @min(studio.selected_tile + 1, maximum);
    studio.palette_page = studio.selected_tile / 64;
}

// -----------------------------------------------------------------------------
// Workshop rendering

fn render(
    renderer: *c.SDL_Renderer,
    studio: *Studio,
    atlases: [model.layer_count]Atlas,
    workspace: *const WorkspaceAssets,
    width: i32,
    height: i32,
) !void {
    setColor(renderer, 18, 22, 31, 255);
    _ = c.SDL_RenderClear(renderer);
    if (studio.mode == .preview) {
        drawPreview(renderer, studio, atlases, width, height);
        if (studio.quit_dialog) drawQuitDialog(renderer, studio, width, height);
        return;
    }
    const layout = layoutFor(width, height, studio.presentation);
    const playful = studio.presentation == .playful;
    fill(renderer, .{ .x = 0, .y = 0, .w = width, .h = bar_top }, 29, 35, 48, 255);
    fill(renderer, .{ .x = 0, .y = bar_top, .w = layout.left, .h = height - bar_top }, 23, 28, 39, 255);
    fill(renderer, .{ .x = width - layout.right, .y = bar_top, .w = layout.right, .h = height - bar_top }, 23, 28, 39, 255);
    fill(renderer, .{ .x = 0, .y = height - bar_bottom, .w = width, .h = bar_bottom }, 12, 16, 24, 255);
    drawText(renderer, 18, 13, 2, if (playful) "ELIS WORKSHOP" else "ELIS STUDIO", 236, 199, 110);
    drawText(renderer, 18, 38, 1, if (playful) "LEARN  PAINT  BUILD" else "PRECISE AUTHORING", 125, 145, 173);
    drawText(renderer, 180, 24, 1, if (studio.dirty()) "UNSAVED" else "SAVED", if (studio.dirty()) 244 else 120, if (studio.dirty()) 124 else 210, 104);
    button(renderer, .{ .x = 270, .y = 12, .w = 100, .h = 34 }, "SAVE", false);
    button(renderer, .{ .x = 380, .y = 12, .w = 110, .h = 34 }, "EXPORT", false);
    button(renderer, .{ .x = 500, .y = 12, .w = 120, .h = 34 }, "PREVIEW", false);
    button(renderer, .{ .x = 630, .y = 12, .w = 140, .h = 34 }, if (playful) "STUDIO VIEW" else "PLAYFUL VIEW", true);
    button(renderer, .{ .x = 780, .y = 12, .w = 140, .h = 34 }, "TEMPLATES", studio.template_panel);

    drawText(renderer, 18, 70, 1, if (playful) "CHOOSE A TOOL" else "TOOLS", 154, 184, 222);
    for (tools, 0..) |tool, index| {
        button(renderer, toolRect(layout, index), tool_labels[index], studio.tool == tool);
    }
    drawText(renderer, 18, layout.layer_y - 22, 1, if (playful) "BUILDING LAYERS" else "LAYERS  BOTTOM -> TOP", 154, 184, 222);
    for (model.layer_names, 0..) |name, index| {
        const layer_y = layout.layer_y + @as(i32, @intCast(index)) * layout.tool_step;
        button(renderer, .{ .x = 14, .y = layer_y, .w = layout.left - 84, .h = layout.tool_step - 5 }, name, studio.active_layer == index);
        button(renderer, .{ .x = layout.left - 68, .y = layer_y, .w = 24, .h = layout.tool_step - 5 }, if (studio.layer_visible[index]) "S" else "H", studio.layer_visible[index]);
        button(renderer, .{ .x = layout.left - 40, .y = layer_y, .w = 26, .h = layout.tool_step - 5 }, "L", studio.layer_locked[index]);
    }
    drawGuide(renderer, studio, layout, height);

    const canvas = canvasLayout(studio.project, width, height, .edit, layout);
    drawMap(renderer, studio, atlases, canvas, true);

    const right_x = width - layout.right;
    var buffer: [128]u8 = undefined;
    const validation_y: i32 = if (studio.template_panel) blk: {
        drawText(renderer, right_x + 18, 70, 1, "PROJECT TEMPLATES", 154, 184, 222);
        drawText(renderer, right_x + 18, 86, 1, "REPLACES MAP AND ENTITY SCHEMA", 236, 199, 110);
        for (model.project_templates, model.project_template_labels, 0..) |template, label, index| {
            button(renderer, .{
                .x = right_x + 14,
                .y = 104 + @as(i32, @intCast(index)) * 38,
                .w = layout.right - 28,
                .h = 32,
            }, label, studio.selected_template == template);
        }
        const description = model.project_template_descriptions[@intFromEnum(studio.selected_template)];
        drawTextClipped(
            renderer,
            right_x + 18,
            262,
            1,
            description,
            @intCast(@max(@divTrunc(layout.right - 36, font.advance), 1)),
            154,
            184,
            222,
        );
        button(renderer, .{ .x = right_x + 14, .y = 284, .w = layout.right - 28, .h = 36 }, "APPLY TEMPLATE", true);
        drawText(renderer, right_x + 18, 334, 1, "UNDO RESTORES THE CURRENT PROJECT", 125, 145, 173);
        drawText(renderer, right_x + 18, 352, 1, "UP/DOWN SELECT  ENTER APPLY", 125, 145, 173);
        break :blk 402;
    } else if (studio.tool == .resize) blk: {
        drawText(renderer, right_x + 18, 70, 1, "MAP RESIZE", 154, 184, 222);
        const dimensions = std.fmt.bufPrint(&buffer, "{d} X {d}  ->  {d} X {d}", .{
            studio.project.width,
            studio.project.height,
            studio.resize_width,
            studio.resize_height,
        }) catch "MAP DIMENSIONS";
        drawText(renderer, right_x + 18, 88, 1, dimensions, 236, 199, 110);
        const half_width = @divTrunc(layout.right - 34, 2);
        button(renderer, .{ .x = right_x + 14, .y = 112, .w = half_width, .h = 30 }, "- WIDTH", false);
        button(renderer, .{ .x = right_x + @divTrunc(layout.right, 2) + 3, .y = 112, .w = half_width, .h = 30 }, "+ WIDTH", false);
        button(renderer, .{ .x = right_x + 14, .y = 148, .w = half_width, .h = 30 }, "- HEIGHT", false);
        button(renderer, .{ .x = right_x + @divTrunc(layout.right, 2) + 3, .y = 148, .w = half_width, .h = 30 }, "+ HEIGHT", false);
        drawText(renderer, right_x + 18, 188, 1, "CONTENT ANCHOR", 154, 184, 222);
        const anchor_width = @divTrunc(layout.right - 40, 3);
        for (model.resize_anchors, model.resize_anchor_labels, 0..) |anchor, label, index| {
            button(renderer, .{
                .x = right_x + 14 + @as(i32, @intCast(index % 3)) * (anchor_width + 6),
                .y = 206 + @as(i32, @intCast(index / 3)) * 36,
                .w = anchor_width,
                .h = 30,
            }, label, studio.resize_anchor == anchor);
        }
        button(renderer, .{ .x = right_x + 14, .y = 326, .w = layout.right - 28, .h = 34 }, "APPLY RESIZE", true);
        const pending_resize = model.analyzeResize(
            studio.project,
            studio.resize_width,
            studio.resize_height,
            studio.resize_anchor,
        ) catch model.ResizeReport{};
        if (studio.resize_report.changed) {
            const clipped = std.fmt.bufPrint(&buffer, "LAST RESIZE: {d} CELLS CLIPPED", .{
                studio.resize_report.clipped_cells,
            }) catch "LAST RESIZE";
            drawText(renderer, right_x + 18, 378, 1, clipped, if (studio.resize_report.clipped()) 246 else 125, if (studio.resize_report.clipped()) 112 else 210, 173);
            if (studio.resize_report.spawn_clipped or studio.resize_report.goal_clipped) {
                drawText(renderer, right_x + 18, 396, 1, "SPAWN OR GOAL WAS CLIPPED", 246, 112, 110);
            }
        } else if (pending_resize.clipped()) {
            const warning = std.fmt.bufPrint(&buffer, "WARNING: WOULD CLIP {d} CELLS", .{
                pending_resize.clipped_cells,
            }) catch "WARNING: CONTENT WOULD CLIP";
            drawText(renderer, right_x + 18, 378, 1, warning, 246, 112, 110);
            if (pending_resize.spawn_clipped or pending_resize.goal_clipped) {
                drawText(renderer, right_x + 18, 396, 1, "SPAWN OR GOAL WOULD CLIP", 246, 112, 110);
            }
        } else {
            drawText(renderer, right_x + 18, 378, 1, "ALL CONTENT WILL BE PRESERVED", 125, 210, 173);
        }
        break :blk 438;
    } else if (studio.tool == .entity) blk: {
        drawText(
            renderer,
            right_x + 18,
            70,
            1,
            if (studio.entity_schema_editing) "ENTITY SCHEMA" else "ENTITY INSPECTOR",
            154,
            184,
            222,
        );
        button(
            renderer,
            .{ .x = right_x + 14, .y = 88, .w = layout.right - 28, .h = 28 },
            if (studio.entity_schema_editing) "BACK TO INSTANCES" else "EDIT SCHEMA",
            studio.entity_schema_editing,
        );
        const current_index = studio.project.cellIndex(studio.cursor.x, studio.cursor.y);
        const current_kind = studio.project.entityKindAt(current_index);
        for (model.entity_kinds, 0..) |kind, index| {
            button(renderer, .{
                .x = right_x + 14,
                .y = 124 + @as(i32, @intCast(index)) * 34,
                .w = layout.right - 28,
                .h = 28,
            }, studio.project.entitySchemaName(kind), studio.selected_entity_kind == kind);
        }
        if (studio.entity_schema_editing) {
            const schema_name = if (studio.entity_text_target == .schema_name)
                studio.entity_text_buffer[0..studio.entity_text_length]
            else
                studio.project.entitySchemaName(studio.selected_entity_kind);
            const schema_label = std.fmt.bufPrint(&buffer, "TYPE  {s}{s}", .{
                schema_name,
                if (studio.entity_text_target == .schema_name) "_" else "",
            }) catch "TYPE NAME";
            drawText(renderer, right_x + 18, 260, 1, schema_label, 236, 199, 110);
            button(renderer, .{ .x = right_x + 14, .y = 278, .w = layout.right - 28, .h = 28 }, "RENAME TYPE", false);
            drawText(renderer, right_x + 18, 314, 1, "FIELDS", 154, 184, 222);
            const field_count = studio.project.entityFieldCount(studio.selected_entity_kind);
            for (0..field_count) |field| {
                var field_buffer: [64]u8 = undefined;
                const field_label = std.fmt.bufPrint(&field_buffer, "{s}  {s}", .{
                    studio.project.entityFieldName(studio.selected_entity_kind, field),
                    @tagName(studio.project.entityFieldKind(studio.selected_entity_kind, field)),
                }) catch "FIELD";
                button(renderer, .{
                    .x = right_x + 14,
                    .y = 330 + @as(i32, @intCast(field)) * 27,
                    .w = layout.right - 28,
                    .h = 24,
                }, field_label, field == studio.selected_entity_field);
            }
            if (field_count < model.max_entity_fields) {
                button(renderer, .{
                    .x = right_x + 14,
                    .y = 330 + @as(i32, field_count) * 27,
                    .w = layout.right - 28,
                    .h = 24,
                }, "+ ADD FIELD", false);
            }
            const half_width = @divTrunc(layout.right - 34, 2);
            button(renderer, .{ .x = right_x + 14, .y = 442, .w = half_width, .h = 28 }, "RENAME", false);
            button(renderer, .{
                .x = right_x + @divTrunc(layout.right, 2) + 3,
                .y = 442,
                .w = half_width,
                .h = 28,
            }, "REMOVE LAST", false);
            const field_kind = studio.project.entityFieldKind(
                studio.selected_entity_kind,
                studio.selected_entity_field,
            );
            const kind_label = std.fmt.bufPrint(&buffer, "KIND  {s}", .{@tagName(field_kind)}) catch "FIELD KIND";
            button(renderer, .{ .x = right_x + 14, .y = 474, .w = layout.right - 28, .h = 28 }, kind_label, false);
            button(renderer, .{ .x = right_x + 14, .y = 508, .w = half_width, .h = 28 }, "- DEFAULT", false);
            button(renderer, .{
                .x = right_x + @divTrunc(layout.right, 2) + 3,
                .y = 508,
                .w = half_width,
                .h = 28,
            }, "+ DEFAULT", false);
            const range_label = std.fmt.bufPrint(&buffer, "D {d}  RANGE {d}-{d}", .{
                studio.project.entityFieldDefault(studio.selected_entity_kind, studio.selected_entity_field),
                studio.project.entityFieldMinimum(studio.selected_entity_kind, studio.selected_entity_field),
                studio.project.entityFieldMaximum(studio.selected_entity_kind, studio.selected_entity_field),
            }) catch "FIELD RANGE";
            drawText(renderer, right_x + 18, 542, 1, range_label, 236, 199, 110);
            drawText(renderer, right_x + 18, 556, 1, "SHIFT +/- MIN  ALT +/- MAX", 125, 145, 173);
            if (studio.entity_text_target == .field_name) {
                fill(renderer, .{ .x = right_x + 14, .y = 408, .w = layout.right - 28, .h = 28 }, 18, 22, 31, 255);
                const edit_label = std.fmt.bufPrint(&buffer, "{s}_", .{
                    studio.entity_text_buffer[0..studio.entity_text_length],
                }) catch "FIELD NAME";
                drawText(renderer, right_x + 20, 418, 1, edit_label, 249, 211, 112);
            }
            break :blk height;
        }
        const current = std.fmt.bufPrint(&buffer, "CELL {d},{d}  {s}", .{
            studio.cursor.x,
            studio.cursor.y,
            if (current_kind == .none) "EMPTY" else studio.project.entitySchemaName(current_kind),
        }) catch "CURRENT CELL";
        drawText(renderer, right_x + 18, 260, 1, current, 236, 199, 110);
        const value_y: i32 = 276;
        const field_kind = studio.project.entityFieldKind(
            studio.selected_entity_kind,
            studio.selected_entity_field,
        );
        const value_label = std.fmt.bufPrint(&buffer, "{s}  {d}  {s}", .{
            studio.project.entityFieldName(studio.selected_entity_kind, studio.selected_entity_field),
            studio.selected_entity_value,
            @tagName(field_kind),
        }) catch "FIELD VALUE";
        drawText(renderer, right_x + 18, value_y - 14, 1, value_label, 154, 184, 222);
        const half_width = @divTrunc(layout.right - 34, 2);
        button(renderer, .{ .x = right_x + 14, .y = value_y, .w = half_width, .h = 30 }, "- VALUE", false);
        button(renderer, .{
            .x = right_x + @divTrunc(layout.right, 2) + 3,
            .y = value_y,
            .w = half_width,
            .h = 30,
        }, "+ VALUE", false);
        drawText(renderer, right_x + 18, 314, 1, "FIELDS  [ ] SELECT", 154, 184, 222);
        const field_y: i32 = 328;
        for (0..studio.project.entityFieldCount(studio.selected_entity_kind)) |field| {
            var field_buffer: [64]u8 = undefined;
            const value = if (current_kind == studio.selected_entity_kind)
                studio.project.entityFieldAt(current_index, field)
            else
                studio.project.entityFieldDefault(studio.selected_entity_kind, field);
            const field_label = std.fmt.bufPrint(&field_buffer, "{s}  {d}", .{
                studio.project.entityFieldName(studio.selected_entity_kind, field),
                value,
            }) catch "FIELD";
            button(renderer, .{
                .x = right_x + 14,
                .y = field_y + @as(i32, @intCast(field)) * 27,
                .w = layout.right - 28,
                .h = 24,
            }, field_label, field == studio.selected_entity_field);
        }
        drawText(renderer, right_x + 18, 450, 1, "LMB PLACE  RMB REMOVE", 125, 145, 173);
        break :blk 480;
    } else if (studio.tool == .stamp) blk: {
        drawText(renderer, right_x + 18, 70, 1, "STAMP TRANSFORM", 154, 184, 222);
        const dimensions = if (studio.stamp.valid())
            std.fmt.bufPrint(&buffer, "PATTERN {d} X {d}", .{ studio.stamp.width, studio.stamp.height }) catch "PATTERN"
        else
            "NO STAMP CAPTURED";
        drawText(renderer, right_x + 18, 86, 1, dimensions, 236, 199, 110);
        button(renderer, .{ .x = right_x + 14, .y = layout.palette_y, .w = layout.right - 28, .h = 30 }, "H  FLIP HORIZONTAL", false);
        button(renderer, .{ .x = right_x + 14, .y = layout.palette_y + 36, .w = layout.right - 28, .h = 30 }, "V  FLIP VERTICAL", false);
        button(renderer, .{ .x = right_x + 14, .y = layout.palette_y + 72, .w = layout.right - 28, .h = 30 }, "O  ROTATE 90", false);
        drawText(renderer, right_x + 18, layout.palette_y + 122, 1, "STAMP PREVIEW FOLLOWS CURSOR", 125, 145, 173);
        break :blk layout.palette_y + 184;
    } else blk: {
        drawText(renderer, right_x + 18, 70, 1, if (studio.tool == .smart) "SMART MATERIAL FAMILY" else "TILE PALETTE", 154, 184, 222);
        const selected = if (studio.tool == .smart)
            std.fmt.bufPrint(&buffer, "BASE {d}  USES {d}-{d}", .{ studio.selected_tile, studio.selected_tile, @min(studio.selected_tile + 15, model.max_tile_id) }) catch "SMART MATERIAL"
        else
            std.fmt.bufPrint(&buffer, "TILE {d}  PAGE {d}/16", .{ studio.selected_tile, studio.palette_page + 1 }) catch "TILE";
        drawText(renderer, right_x + 18, 86, 1, selected, 236, 199, 110);
        const atlas = atlases[studio.active_layer];
        for (0..64) |slot| {
            const tile: u16 = studio.palette_page * 64 + @as(u16, @intCast(slot));
            const rect = Rect{
                .x = right_x + 18 + @as(i32, @intCast(slot % 8)) * layout.palette_cell,
                .y = layout.palette_y + @as(i32, @intCast(slot / 8)) * layout.palette_cell,
                .w = layout.palette_cell - 3,
                .h = layout.palette_cell - 3,
            };
            drawTile(renderer, atlas, tile, rect, 0);
            if (tile == studio.selected_tile) outline(renderer, rect, 249, 211, 112, 255);
        }
        const asset_header_y = layout.palette_y + layout.palette_cell * 8 + 18;
        const palette_label = if (workspace.palette.exact())
            std.fmt.bufPrint(&buffer, "ASSETS  EXACT PALETTE {d}", .{workspace.palette.defined_count}) catch "ASSETS"
        else
            "ASSETS  DIAGNOSTIC PALETTE";
        drawText(renderer, right_x + 18, asset_header_y, 1, palette_label, 154, 184, 222);
        const page_label = std.fmt.bufPrint(&buffer, "< PAGE {d} >", .{studio.asset_page + 1}) catch "< ASSETS >";
        drawText(renderer, right_x + layout.right - 92, asset_header_y, 1, page_label, 236, 199, 110);
        const asset_y = asset_header_y + 26;
        for (0..5) |row| {
            const asset_index = compatibleAssetIndex(&workspace.catalog, studio.project.tile_size, @as(usize, studio.asset_page) * 5 + row) orelse break;
            const asset = &workspace.catalog.items[asset_index];
            const selected_asset = std.mem.eql(u8, asset.name(), studio.project.layerTilesetName(studio.active_layer));
            button(renderer, .{
                .x = right_x + 14,
                .y = asset_y + @as(i32, @intCast(row)) * 25,
                .w = layout.right - 28,
                .h = 22,
            }, asset.name(), selected_asset);
        }
        break :blk asset_y + 5 * 25 + 12;
    };

    const report = model.validate(studio.project);
    drawText(renderer, right_x + 18, validation_y, 1, "LEVEL CHECK", 154, 184, 222);
    const summary = std.fmt.bufPrint(&buffer, "{d} ERRORS  {d} WARNINGS", .{ report.error_count, report.warning_count }) catch "VALIDATION";
    drawText(renderer, right_x + 18, validation_y + 18, 1, summary, if (report.error_count > 0) 246 else 111, if (report.error_count > 0) 112 else 214, 112);
    const reachable = std.fmt.bufPrint(&buffer, "{d} REACHABLE CELLS", .{report.reachable_cells}) catch "";
    drawText(renderer, right_x + 18, validation_y + 34, 1, reachable, 125, 145, 173);
    const lupi_status = lupiExportStatus(studio.project, workspace);
    drawText(
        renderer,
        right_x + 18,
        validation_y + 50,
        1,
        lupiExportStatusLabel(lupi_status),
        if (lupi_status == .safe) 111 else 246,
        if (lupi_status == .safe) 214 else 112,
        112,
    );
    const visible_issues = @min(report.count, @as(u8, @intCast(@max(@divTrunc(height - bar_bottom - validation_y - 75, 17), 0))));
    for (report.issues[0..visible_issues], 0..) |issue, index| {
        drawText(renderer, right_x + 18, validation_y + 71 + @as(i32, @intCast(index)) * 17, 1, issueLabel(issue.kind), if (issue.severity == .@"error") 246 else 236, if (issue.severity == .@"error") 112 else 199, 110);
    }
    drawNotice(renderer, studio.notice, width, height);
    if (studio.quit_dialog) drawQuitDialog(renderer, studio, width, height);
}

fn drawQuitDialog(renderer: *c.SDL_Renderer, studio: *const Studio, width: i32, height: i32) void {
    fill(renderer, .{ .x = 0, .y = 0, .w = width, .h = height }, 5, 7, 12, 210);
    const panel = Rect{
        .x = @divTrunc(width - 420, 2),
        .y = @divTrunc(height - 230, 2),
        .w = 420,
        .h = 230,
    };
    fill(renderer, panel, 29, 35, 48, 255);
    outline(renderer, panel, 236, 199, 110, 255);
    drawText(renderer, panel.x + 30, panel.y + 24, 2, "UNSAVED CHANGES", 246, 210, 126);
    drawText(
        renderer,
        panel.x + 30,
        panel.y + 54,
        1,
        "SAVE BEFORE CLOSING THE WORKSHOP?",
        218,
        225,
        236,
    );
    for (0..2) |index| {
        const selection: u1 = @intCast(index);
        button(
            renderer,
            quitDialogButtonRect(width, height, selection),
            if (selection == 0) "SAVE AND EXIT" else "DISCARD CHANGES",
            studio.quit_selection == selection,
        );
    }
    if (studio.notice == .save_failed or studio.notice == .edit_failed) {
        drawText(
            renderer,
            panel.x + 30,
            panel.y + 204,
            1,
            if (studio.notice == .save_failed)
                "SAVE FAILED - CHECK THE PROJECT PATH"
            else
                "EDIT COULD NOT BE COMMITTED",
            246,
            112,
            110,
        );
    } else {
        drawText(renderer, panel.x + 30, panel.y + 204, 1, "ESC KEEPS EDITING", 154, 184, 222);
    }
}

fn drawPreview(renderer: *c.SDL_Renderer, studio: *Studio, atlases: [model.layer_count]Atlas, width: i32, height: i32) void {
    fill(renderer, .{ .x = 0, .y = 0, .w = width, .h = height }, 7, 9, 14, 255);
    const canvas = canvasLayout(studio.project, width, height, .preview, layoutFor(width, height, studio.presentation));
    drawMap(renderer, studio, atlases, canvas, false);
    fill(renderer, .{ .x = 0, .y = 0, .w = width, .h = 38 }, 12, 16, 24, 230);
    drawText(renderer, 18, 13, 1, "MAP PREVIEW  -  F7 / ESC RETURN TO EDIT", 218, 225, 236);
}

fn drawMap(renderer: *c.SDL_Renderer, studio: *Studio, atlases: [model.layer_count]Atlas, canvas: Canvas, editor_overlay: bool) void {
    fill(renderer, canvas.rect, 9, 12, 18, 255);
    for (0..studio.project.height) |y| {
        for (0..studio.project.width) |x| {
            const index = studio.project.cellIndex(@intCast(x), @intCast(y));
            const rect = Rect{
                .x = canvas.content.x + @as(i32, @intCast(x)) * canvas.cell,
                .y = canvas.content.y + @as(i32, @intCast(y)) * canvas.cell,
                .w = canvas.cell,
                .h = canvas.cell,
            };
            for (0..model.layer_count) |layer| {
                if (!studio.layer_visible[layer]) continue;
                const tile = studio.project.layerCells(layer)[index];
                if (tile != model.empty_tile) drawTile(renderer, atlases[layer], tile, rect, @intCast(layer));
            }
            if (editor_overlay and studio.project.solid[index] != 0) {
                fill(renderer, rect, 225, 62, 76, 82);
                drawCross(renderer, rect, 225, 62, 76);
            }
            if (editor_overlay) {
                const entity_kind = studio.project.entityKindAt(index);
                if (entity_kind != .none) drawEntityMarker(renderer, rect, entity_kind);
            }
            if (editor_overlay and canvas.cell >= 8) outline(renderer, rect, 45, 53, 68, 110);
        }
    }
    if (studio.project.spawn) |point| drawMarker(renderer, canvas, point, "S", 72, 220, 132);
    if (studio.project.goal) |point| drawMarker(renderer, canvas, point, "G", 244, 192, 74);
    if (editor_overlay) {
        if (studio.selection) |selection| {
            const x_min = @min(selection.first.x, selection.last.x);
            const y_min = @min(selection.first.y, selection.last.y);
            const selection_rect = Rect{
                .x = canvas.content.x + @as(i32, x_min) * canvas.cell,
                .y = canvas.content.y + @as(i32, y_min) * canvas.cell,
                .w = @as(i32, selection.width()) * canvas.cell,
                .h = @as(i32, selection.height()) * canvas.cell,
            };
            fill(renderer, selection_rect, 249, 211, 112, 38);
            outline(renderer, selection_rect, 249, 211, 112, 255);
        }
        if (studio.shaping) if (studio.shape) |shape| {
            const x_min = @min(shape.first.x, shape.last.x);
            const y_min = @min(shape.first.y, shape.last.y);
            const shape_rect = Rect{
                .x = canvas.content.x + @as(i32, x_min) * canvas.cell,
                .y = canvas.content.y + @as(i32, y_min) * canvas.cell,
                .w = @as(i32, shape.width()) * canvas.cell,
                .h = @as(i32, shape.height()) * canvas.cell,
            };
            if (studio.tool == .rectangle) {
                if (studio.shape_filled) fill(renderer, shape_rect, 88, 204, 226, 35);
                outline(renderer, shape_rect, 88, 204, 226, 255);
            } else if (studio.tool == .line) {
                const first_x = canvas.content.x + @as(i32, shape.first.x) * canvas.cell + @divTrunc(canvas.cell, 2);
                const first_y = canvas.content.y + @as(i32, shape.first.y) * canvas.cell + @divTrunc(canvas.cell, 2);
                const last_x = canvas.content.x + @as(i32, shape.last.x) * canvas.cell + @divTrunc(canvas.cell, 2);
                const last_y = canvas.content.y + @as(i32, shape.last.y) * canvas.cell + @divTrunc(canvas.cell, 2);
                setColor(renderer, 88, 204, 226, 255);
                _ = c.SDL_RenderDrawLine(renderer, first_x, first_y, last_x, last_y);
            }
        };
        if (studio.tool == .stamp and studio.stamp.valid()) {
            const preview_width = @min(studio.stamp.width, studio.project.width - studio.cursor.x);
            const preview_height = @min(studio.stamp.height, studio.project.height - studio.cursor.y);
            const preview_rect = Rect{
                .x = canvas.content.x + @as(i32, studio.cursor.x) * canvas.cell,
                .y = canvas.content.y + @as(i32, studio.cursor.y) * canvas.cell,
                .w = @as(i32, preview_width) * canvas.cell,
                .h = @as(i32, preview_height) * canvas.cell,
            };
            fill(renderer, preview_rect, 88, 204, 226, 30);
            outline(renderer, preview_rect, 88, 204, 226, 255);
        }
        const cursor_rect = Rect{
            .x = canvas.content.x + @as(i32, studio.cursor.x) * canvas.cell,
            .y = canvas.content.y + @as(i32, studio.cursor.y) * canvas.cell,
            .w = canvas.cell,
            .h = canvas.cell,
        };
        outline(renderer, cursor_rect, 255, 255, 255, 255);
    }
    outline(renderer, canvas.content, 88, 103, 128, 255);
}

fn drawEntityMarker(renderer: *c.SDL_Renderer, cell: Rect, kind: model.EntityKind) void {
    const color: [3]u8 = switch (kind) {
        .none => return,
        .enemy => .{ 240, 92, 104 },
        .pickup => .{ 90, 218, 154 },
        .trigger => .{ 104, 164, 244 },
        .decoration => .{ 206, 132, 244 },
    };
    const marker = Rect{
        .x = cell.x + @max(@divTrunc(cell.w, 4), 1),
        .y = cell.y + @max(@divTrunc(cell.h, 4), 1),
        .w = @max(@divTrunc(cell.w, 2), 6),
        .h = @max(@divTrunc(cell.h, 2), 6),
    };
    fill(renderer, marker, color[0], color[1], color[2], 230);
    outline(renderer, marker, 245, 248, 252, 220);
    if (cell.w >= 20) {
        drawText(renderer, marker.x + 2, marker.y + @max(@divTrunc(marker.h - 8, 2), 0), 1, model.entityKindLabel(kind)[0..1], 12, 16, 24);
    }
}

fn drawTile(renderer: *c.SDL_Renderer, atlas: Atlas, tile: u16, destination: Rect, layer: u8) void {
    if (atlas.texture) |texture| {
        if (tile < atlas.tile_count) {
            var source = c.SDL_Rect{
                .x = @as(i32, tile % @as(u16, @intCast(atlas.columns))) * atlas.tile_width,
                .y = @as(i32, tile / @as(u16, @intCast(atlas.columns))) * atlas.tile_height,
                .w = atlas.tile_width,
                .h = atlas.tile_height,
            };
            var target = sdlRect(destination);
            _ = c.SDL_RenderCopy(renderer, texture, &source, &target);
            return;
        }
    }
    const color = tileColor(tile, layer);
    fill(renderer, destination, color[0], color[1], color[2], if (layer == 0) 255 else 218);
    if (destination.w >= 12) {
        const inset = Rect{ .x = destination.x + 3, .y = destination.y + 3, .w = @max(destination.w - 6, 1), .h = @max(destination.h - 6, 1) };
        outline(renderer, inset, color[0] +| 24, color[1] +| 24, color[2] +| 24, 170);
    }
}

// -----------------------------------------------------------------------------
// Manifest, palette, and atlas ownership

fn loadWorkspaceAssets(allocator: std.mem.Allocator, game_root: ?[]const u8) WorkspaceAssets {
    const root = game_root orelse return .{};
    var result = WorkspaceAssets{};
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    var path_buffer: [2048]u8 = undefined;
    const manifest_path = std.fmt.bufPrint(&path_buffer, "{s}/lupi_manifest.txt", .{root}) catch return result;
    if (std.Io.Dir.cwd().readFileAlloc(io, manifest_path, allocator, .limited(4 * 1024 * 1024))) |bytes| {
        defer allocator.free(bytes);
        result.catalog = assets.parseManifest(bytes);
    } else |_| {}
    for (result.catalog.slice(), 0..) |asset, index| {
        const asset_path = std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ root, asset.name() }) catch continue;
        if (std.Io.Dir.cwd().readFileAlloc(
            io,
            asset_path,
            allocator,
            .limited(assets.lupi_tileset_pixels_max + 1),
        )) |bytes| {
            result.asset_file_verified[index] = bytes.len == asset.byte_len;
            allocator.free(bytes);
        } else |_| {}
    }
    const palette_path = std.fmt.bufPrint(&path_buffer, "{s}/palette.lua", .{root}) catch return result;
    if (std.Io.Dir.cwd().readFileAlloc(io, palette_path, allocator, .limited(256 * 1024))) |bytes| {
        defer allocator.free(bytes);
        result.palette = assets.parsePaletteLua(bytes);
    } else |_| {}
    return result;
}

fn loadProjectAtlases(
    allocator: std.mem.Allocator,
    renderer: *c.SDL_Renderer,
    game_root: ?[]const u8,
    workspace: *const WorkspaceAssets,
    project: model.Project,
    legacy_path: ?[]const u8,
) ![model.layer_count]Atlas {
    var result: [model.layer_count]Atlas = .{Atlas{}} ** model.layer_count;
    errdefer for (&result) |*atlas| atlas.deinit();
    for (&result, 0..) |*atlas, layer| {
        atlas.* = if (legacy_path) |path| legacy: {
            var loaded = try loadAtlas(
                allocator,
                renderer,
                path,
                project.tile_size,
                workspace.palette,
            );
            loaded.setAssetName(project.layerTilesetName(layer));
            break :legacy loaded;
        } else try loadCatalogAtlas(
            allocator,
            renderer,
            game_root,
            workspace,
            project.layerTilesetName(layer),
            project.tile_size,
        );
    }
    return result;
}

fn loadCatalogAtlas(
    allocator: std.mem.Allocator,
    renderer: *c.SDL_Renderer,
    game_root: ?[]const u8,
    workspace: *const WorkspaceAssets,
    name: []const u8,
    tile_size: u16,
) !Atlas {
    var atlas = Atlas{};
    atlas.setAssetName(name);
    const root = game_root orelse return atlas;
    const asset_index = workspace.catalog.find(name) orelse return atlas;
    const asset = &workspace.catalog.items[asset_index];
    if (!workspace.asset_file_verified[asset_index] or
        !asset.lupiCompatible(tile_size, 0)) return atlas;
    var path_buffer: [2048]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ root, asset.name() });
    var loaded = try loadAtlas(allocator, renderer, path, tile_size, workspace.palette);
    loaded.setAssetName(name);
    return loaded;
}

fn atlasesNeedReload(project: model.Project, atlases: [model.layer_count]Atlas) bool {
    for (atlases, 0..) |atlas, layer| {
        const asset_name = atlas.asset_name[0..atlas.asset_name_length];
        if (!std.mem.eql(u8, project.layerTilesetName(layer), asset_name)) return true;
    }
    return false;
}

fn reloadProjectAtlases(
    allocator: std.mem.Allocator,
    renderer: *c.SDL_Renderer,
    studio: *Studio,
    atlases: *[model.layer_count]Atlas,
    game_root: ?[]const u8,
    workspace: *const WorkspaceAssets,
) !void {
    var replacements = try loadProjectAtlases(
        allocator,
        renderer,
        game_root,
        workspace,
        studio.project,
        null,
    );
    for (0..model.layer_count) |layer| {
        const asset_index = workspace.catalog.find(
            studio.project.layerTilesetName(layer),
        ) orelse continue;
        if (workspace.asset_file_verified[asset_index] and replacements[layer].texture == null) {
            for (&replacements) |*replacement| replacement.deinit();
            studio.notice = .asset_incompatible;
            return;
        }
    }
    for (atlases) |*atlas| atlas.deinit();
    atlases.* = replacements;
    const active = atlases[studio.active_layer];
    if (active.tile_count > 0) {
        studio.selected_tile = @min(studio.selected_tile, active.tile_count - 1);
    }
    studio.palette_page = studio.selected_tile / 64;
}

fn assignLayerAsset(
    allocator: std.mem.Allocator,
    renderer: *c.SDL_Renderer,
    studio: *Studio,
    atlases: *[model.layer_count]Atlas,
    game_root: ?[]const u8,
    workspace: *const WorkspaceAssets,
    asset_index: usize,
) !void {
    if (asset_index >= workspace.catalog.count) return;
    const asset = &workspace.catalog.items[asset_index];
    if (asset.width != studio.project.tile_size or asset.height != studio.project.tile_size) {
        studio.notice = .asset_incompatible;
        return;
    }
    const layer = studio.active_layer;
    if (std.mem.eql(u8, studio.project.layerTilesetName(layer), asset.name())) return;
    var replacement = try loadCatalogAtlas(allocator, renderer, game_root, workspace, asset.name(), studio.project.tile_size);
    errdefer replacement.deinit();
    if (replacement.texture == null) {
        studio.notice = .asset_incompatible;
        return;
    }
    const changed = try studio.history.setLayerTilesetName(&studio.project, layer, asset.name());
    std.debug.assert(changed);
    atlases[layer].deinit();
    atlases[layer] = replacement;
    studio.selected_tile = @min(studio.selected_tile, if (replacement.tile_count > 0) replacement.tile_count - 1 else model.max_tile_id);
    studio.palette_page = studio.selected_tile / 64;
    studio.notice = .asset_selected;
}

fn cycleLayerAsset(
    allocator: std.mem.Allocator,
    renderer: *c.SDL_Renderer,
    studio: *Studio,
    atlases: *[model.layer_count]Atlas,
    game_root: ?[]const u8,
    workspace: *const WorkspaceAssets,
    direction: i32,
) !void {
    const count = compatibleAssetCount(&workspace.catalog, studio.project.tile_size);
    if (count == 0) return;
    var current: usize = 0;
    for (0..count) |ordinal| {
        const index = compatibleAssetIndex(&workspace.catalog, studio.project.tile_size, ordinal).?;
        if (std.mem.eql(u8, workspace.catalog.items[index].name(), studio.project.layerTilesetName(studio.active_layer))) {
            current = ordinal;
            break;
        }
    }
    const next: usize = @intCast(@mod(@as(i32, @intCast(current)) + direction, @as(i32, @intCast(count))));
    const asset_index = compatibleAssetIndex(&workspace.catalog, studio.project.tile_size, next).?;
    try assignLayerAsset(allocator, renderer, studio, atlases, game_root, workspace, asset_index);
    studio.asset_page = @intCast(next / 5);
}

fn lupiExportStatus(project: model.Project, workspace: *const WorkspaceAssets) LupiExportStatus {
    if (!model.validate(project).valid()) return .project_invalid;
    if (model.lupiTileSamplePixels(project) > model.lupi_tile_sample_pixels_max) {
        return .map_budget_exceeded;
    }
    if (model.lupiLuaDataEntries(project) > model.lupi_lua_data_entries_max) {
        return .lua_budget_exceeded;
    }
    for (0..model.layer_count) |layer| {
        const asset_index = workspace.catalog.find(project.layerTilesetName(layer)) orelse
            return .asset_missing;
        if (!workspace.asset_file_verified[asset_index]) return .asset_incompatible;
        var tile_id_max: u16 = 0;
        for (project.layerCells(layer)) |tile| {
            if (tile != model.empty_tile) tile_id_max = @max(tile_id_max, tile);
        }
        if (!workspace.catalog.items[asset_index].lupiCompatible(project.tile_size, tile_id_max)) {
            return .asset_incompatible;
        }
    }
    return .safe;
}

fn compatibleAssetCount(catalog: *const assets.Catalog, tile_size: u16) usize {
    var count: usize = 0;
    for (catalog.slice()) |asset| {
        if (asset.lupiCompatible(tile_size, 0)) count += 1;
    }
    return count;
}

fn compatibleAssetIndex(catalog: *const assets.Catalog, tile_size: u16, ordinal: usize) ?usize {
    var compatible: usize = 0;
    for (catalog.slice(), 0..) |asset, index| {
        if (!asset.lupiCompatible(tile_size, 0)) continue;
        if (compatible == ordinal) return index;
        compatible += 1;
    }
    return null;
}

fn loadAtlas(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, path: ?[]const u8, tile_size: u16, palette: assets.Palette) !Atlas {
    const source_path = path orelse return .{};
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        threaded.io(),
        source_path,
        allocator,
        .limited(assets.lupi_tileset_pixels_max + 1),
    ) catch return .{};
    defer allocator.free(bytes);
    const pixels_per_tile = @as(usize, tile_size) * tile_size;
    if (pixels_per_tile == 0 or bytes.len > assets.lupi_tileset_pixels_max or
        bytes.len < pixels_per_tile or bytes.len % pixels_per_tile != 0)
    {
        return .{};
    }
    const count: u16 = @intCast(@min(bytes.len / pixels_per_tile, model.max_tile_id + 1));
    const columns: i32 = 16;
    const rows: i32 = @intCast((@as(usize, count) + 15) / 16);
    const atlas_width = columns * tile_size;
    const atlas_height = rows * tile_size;
    const surface = c.SDL_CreateRGBSurfaceWithFormat(0, atlas_width, atlas_height, 32, c.SDL_PIXELFORMAT_RGBA8888) orelse return .{};
    defer c.SDL_FreeSurface(surface);
    const destination: [*]u32 = @ptrCast(@alignCast(surface.*.pixels));
    const pitch: usize = @intCast(@divTrunc(surface.*.pitch, 4));
    @memset(destination[0 .. pitch * @as(usize, @intCast(atlas_height))], 0);
    for (0..count) |tile| {
        const atlas_x = (tile % 16) * tile_size;
        const atlas_y = (tile / 16) * tile_size;
        for (0..tile_size) |py| for (0..tile_size) |px| {
            const palette_index = bytes[tile * pixels_per_tile + py * tile_size + px];
            if (palette_index == 0) continue;
            const color = palette.colors[palette_index];
            destination[(@as(usize, atlas_y) + py) * pitch + @as(usize, atlas_x) + px] =
                c.SDL_MapRGBA(surface.*.format, color[0], color[1], color[2], 255);
        };
    }
    const texture = c.SDL_CreateTextureFromSurface(renderer, surface) orelse return .{};
    _ = c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND);
    return .{
        .texture = texture,
        .columns = columns,
        .rows = rows,
        .tile_width = tile_size,
        .tile_height = tile_size,
        .tile_count = count,
    };
}

// -----------------------------------------------------------------------------
// Responsive geometry and drawing primitives

fn layoutFor(width: i32, height: i32, presentation: Presentation) Layout {
    const roomy = width >= 1180 and height >= 700;
    const playful = presentation == .playful;
    const left: i32 = if (roomy and playful) 236 else if (roomy) 214 else 196;
    const palette_cell: i32 = if (roomy and playful) 34 else if (roomy) 31 else 28;
    const minimum_right: i32 = if (roomy and playful) 320 else 272;
    const right = @max(palette_cell * 8 + 36, minimum_right);
    const tool_step: i32 = if (roomy and playful) 36 else 30;
    const tool_y: i32 = 88;
    return .{
        .left = left,
        .right = right,
        .tool_y = tool_y,
        .tool_step = tool_step,
        .layer_y = tool_y + @as(i32, @intCast(tool_rows)) * tool_step + 28,
        .palette_y = 104,
        .palette_cell = palette_cell,
    };
}

fn toolRect(layout: Layout, index: usize) Rect {
    const gap: i32 = 6;
    const button_width = @divTrunc(layout.left - 28 - gap, @as(i32, @intCast(tool_columns)));
    const column: i32 = @intCast(index % tool_columns);
    const row: i32 = @intCast(index / tool_columns);
    return .{
        .x = 14 + column * (button_width + gap),
        .y = layout.tool_y + row * layout.tool_step,
        .w = button_width,
        .h = layout.tool_step - 5,
    };
}

fn toolWritesLayer(tool: Tool) bool {
    return switch (tool) {
        .brush, .smart, .erase, .fill, .stamp, .line, .rectangle => true,
        .pick, .collision, .spawn, .goal, .entity, .select, .resize => false,
    };
}

fn canvasLayout(project: model.Project, width: i32, height: i32, mode: Mode, layout: Layout) Canvas {
    const outer = if (mode == .edit)
        Rect{ .x = layout.left, .y = bar_top, .w = @max(width - layout.left - layout.right, 1), .h = @max(height - bar_top - bar_bottom, 1) }
    else
        Rect{ .x = 18, .y = 52, .w = @max(width - 36, 1), .h = @max(height - 70, 1) };
    const cell = @max(@min(@divTrunc(outer.w - 24, project.width), @divTrunc(outer.h - 24, project.height)), 2);
    const content_w = cell * project.width;
    const content_h = cell * project.height;
    return .{
        .rect = outer,
        .cell = cell,
        .content = .{
            .x = outer.x + @divTrunc(outer.w - content_w, 2),
            .y = outer.y + @divTrunc(outer.h - content_h, 2),
            .w = content_w,
            .h = content_h,
        },
    };
}

fn canvasPoint(project: model.Project, canvas: Canvas, x: i32, y: i32) ?model.Point {
    if (!contains(canvas.content, x, y)) return null;
    const point = model.Point{
        .x = @intCast(@divTrunc(x - canvas.content.x, canvas.cell)),
        .y = @intCast(@divTrunc(y - canvas.content.y, canvas.cell)),
    };
    if (point.x >= project.width or point.y >= project.height) return null;
    return point;
}

fn drawMarker(renderer: *c.SDL_Renderer, canvas: Canvas, point: model.Point, label: []const u8, r: u8, g: u8, b: u8) void {
    const rect = Rect{
        .x = canvas.content.x + @as(i32, point.x) * canvas.cell + @max(@divTrunc(canvas.cell, 5), 1),
        .y = canvas.content.y + @as(i32, point.y) * canvas.cell + @max(@divTrunc(canvas.cell, 5), 1),
        .w = @max(@divTrunc(canvas.cell * 3, 5), 8),
        .h = @max(@divTrunc(canvas.cell * 3, 5), 8),
    };
    fill(renderer, rect, r, g, b, 235);
    if (canvas.cell >= 18) drawText(renderer, rect.x + @max(@divTrunc(rect.w - 5, 2), 1), rect.y + @max(@divTrunc(rect.h - 8, 2), 1), 1, label, 12, 16, 24);
}

fn drawGuide(renderer: *c.SDL_Renderer, studio: *const Studio, layout: Layout, height: i32) void {
    const y = layout.layer_y + @as(i32, model.layer_count) * layout.tool_step + 14;
    const available = height - bar_bottom - y;
    if (available < 42) return;
    if (studio.presentation == .studio) {
        drawText(renderer, 18, y, 1, "TAB PLAYFUL  CTRL-Z/Y", 125, 145, 173);
        if (available >= 58) drawText(renderer, 18, y + 16, 1, "L LINE  D RECT  N RESIZE", 125, 145, 173);
        if (available >= 74) drawText(renderer, 18, y + 32, 1, "SHIFT/ALT + 1-4  VIEW/LOCK", 125, 145, 173);
        return;
    }
    const pulse: i32 = if (studio.reduce_motion) 0 else @intCast((studio.guide_pulse / 24) & 1);
    const card_h = @min(available - 8, 118);
    fill(renderer, .{ .x = 14, .y = y, .w = layout.left - 28, .h = card_h }, 31, 40, 55, 255);
    outline(renderer, .{ .x = 14, .y = y, .w = layout.left - 28, .h = card_h }, 72, 96, 124, 255);
    const face = Rect{ .x = 24, .y = y + 12 - pulse, .w = 32, .h = 30 };
    fill(renderer, face, 249, 211, 112, 255);
    outline(renderer, face, 255, 236, 172, 255);
    fill(renderer, .{ .x = face.x + 7, .y = face.y + 8, .w = 3, .h = 4 }, 29, 35, 48, 255);
    fill(renderer, .{ .x = face.x + 22, .y = face.y + 8, .w = 3, .h = 4 }, 29, 35, 48, 255);
    setColor(renderer, 29, 35, 48, 255);
    _ = c.SDL_RenderDrawLine(renderer, face.x + 9, face.y + 21, face.x + 23, face.y + 21);
    drawText(renderer, 66, y + 13, 1, "PIP'S PAINT TIP", 236, 199, 110);
    if (card_h >= 70) {
        drawTextClipped(renderer, 24, y + 52, 1, guideLine(studio.tool), @intCast(@max(@divTrunc(layout.left - 48, font.advance), 1)), 202, 215, 232);
    }
    if (card_h >= 90) drawText(renderer, 24, y + 72, 1, "A APPLY  B ERASE", 125, 145, 173);
    if (card_h >= 108) drawText(renderer, 24, y + 88, 1, "TAB CHANGES VIEW", 125, 145, 173);
}

fn guideLine(tool: Tool) []const u8 {
    return switch (tool) {
        .brush => "DRAW EXACTLY WHAT YOU PICK.",
        .smart => "PAINT SHAPES; EDGES JOIN!",
        .erase => "MISTAKES ARE EASY TO ERASE.",
        .fill => "COLOR ONE CONNECTED REGION.",
        .pick => "COPY A TILE FROM THE MAP.",
        .collision => "RED CELLS BLOCK THE PLAYER.",
        .spawn => "CHOOSE WHERE PLAY BEGINS.",
        .goal => "GIVE THE PLAYER A DESTINATION.",
        .entity => "PLACE TYPED GAMEPLAY OBJECTS.",
        .select => "DRAG A RECTANGLE TO MAKE A STAMP.",
        .stamp => "PAINT YOUR SAVED STAMP ANYWHERE.",
        .line => "DRAG A STRAIGHT PIXEL LINE.",
        .rectangle => "DRAG A BOX; SHIFT FILLS IT.",
        .resize => "CHANGE SIZE; ANCHOR YOUR CONTENT.",
    };
}

fn drawNotice(renderer: *c.SDL_Renderer, notice: Notice, width: i32, height: i32) void {
    const label: []const u8 = switch (notice) {
        .none => "LMB DRAW  RMB ERASE  WHEEL TILE",
        .saved => "PROJECT SAVED ATOMICALLY",
        .exported => "LUA MAP EXPORTED",
        .asset_selected => "LAYER TILESET CHANGED",
        .asset_incompatible => "ASSET SIZE DOES NOT MATCH THIS MAP GRID",
        .save_failed => "SAVE FAILED - SOURCE RETAINED",
        .edit_failed => "EDIT COMMIT FAILED - SOURCE RETAINED",
        .export_failed => "EXPORT FAILED - SOURCE RETAINED",
        .lupi_export_blocked => "EXPORT BLOCKED - FIX LUPI SAFETY CHECK",
        .invalid_preview => "FIX VALIDATION ERRORS BEFORE PREVIEW",
        .stamp_captured => "STAMP COPIED - PAINT IT WITH MOUSE OR CTRL-V",
        .stamp_missing => "SELECT A RECTANGLE BEFORE PAINTING A STAMP",
        .stamp_transformed => "STAMP TRANSFORMED - SOURCE MAP UNCHANGED",
        .entity_changed => "ENTITY TYPE OR FIELD VALUE CHANGED",
        .layer_locked => "LAYER LOCKED - UNLOCK IT TO PAINT",
        .layer_lock_changed => "LAYER LOCK STATE CHANGED FOR THIS SESSION",
        .layer_visibility => "LAYER VISIBILITY CHANGED FOR THIS SESSION",
        .shape_applied => "SHAPE APPLIED AS ONE UNDOABLE COMMAND",
        .resize_applied => "MAP RESIZED - ALL CONTENT PRESERVED",
        .resize_clipped => "MAP RESIZED - REVIEW CLIPPING DIAGNOSTIC OR UNDO",
        .template_applied => "PROJECT TEMPLATE APPLIED - CTRL-Z RESTORES PRIOR WORK",
    };
    const problem = notice == .save_failed or notice == .edit_failed or
        notice == .export_failed or notice == .lupi_export_blocked or
        notice == .invalid_preview or notice == .asset_incompatible or
        notice == .stamp_missing or notice == .layer_locked or
        notice == .resize_clipped;
    drawText(renderer, 18, height - 20, 1, label, if (problem) 246 else 154, if (problem) 112 else 184, 222);
    _ = width;
}

fn lupiExportStatusLabel(status: LupiExportStatus) []const u8 {
    return switch (status) {
        .safe => "LUPI-SAFE EXPORT: PASS",
        .project_invalid => "LUPI EXPORT: FIX LEVEL ERRORS",
        .map_budget_exceeded => "LUPI EXPORT: MAP WORK TOO HIGH",
        .lua_budget_exceeded => "LUPI EXPORT: LUA DATA TOO HIGH",
        .asset_missing => "LUPI EXPORT: ASSET MISSING",
        .asset_incompatible => "LUPI EXPORT: ASSET/TILE UNSAFE",
    };
}

fn issueLabel(kind: model.IssueKind) []const u8 {
    return switch (kind) {
        .missing_spawn => "ERROR: PLACE PLAYER SPAWN",
        .missing_goal => "ERROR: PLACE GOAL",
        .spawn_blocked => "ERROR: SPAWN IS BLOCKED",
        .goal_blocked => "ERROR: GOAL IS BLOCKED",
        .goal_unreachable => "ERROR: GOAL UNREACHABLE",
        .entity_blocked => "WARN: ENTITY ON COLLISION",
        .empty_background => "WARN: BACKGROUND EMPTY",
    };
}

fn button(renderer: *c.SDL_Renderer, rect: Rect, label: []const u8, selected: bool) void {
    fill(renderer, rect, if (selected) 72 else 38, if (selected) 92 else 47, if (selected) 124 else 64, 255);
    outline(renderer, rect, if (selected) 249 else 72, if (selected) 211 else 84, if (selected) 112 else 106, 255);
    drawText(renderer, rect.x + 9, rect.y + @divTrunc(rect.h - 8, 2), 1, label, if (selected) 255 else 210, if (selected) 231 else 218, if (selected) 166 else 230);
}

fn drawText(renderer: *c.SDL_Renderer, x: i32, y: i32, scale: i32, text: []const u8, r: u8, g: u8, b: u8) void {
    setColor(renderer, r, g, b, 255);
    var cursor_x = x;
    for (text) |byte| {
        if (byte < 32 or byte > 126) {
            cursor_x += font.advance * scale;
            continue;
        }
        const glyph = font.data[byte - 32];
        for (glyph, 0..) |column, px| for (0..font.height) |py| {
            if ((column & (@as(u8, 1) << @intCast(py))) == 0) continue;
            var rect = c.SDL_Rect{
                .x = cursor_x + @as(i32, @intCast(px)) * scale,
                .y = y + @as(i32, @intCast(py)) * scale,
                .w = scale,
                .h = scale,
            };
            _ = c.SDL_RenderFillRect(renderer, &rect);
        };
        cursor_x += font.advance * scale;
    }
}

fn drawTextClipped(renderer: *c.SDL_Renderer, x: i32, y: i32, scale: i32, value: []const u8, max_chars: usize, r: u8, g: u8, b: u8) void {
    drawText(renderer, x, y, scale, value[0..@min(value.len, max_chars)], r, g, b);
}

fn drawCross(renderer: *c.SDL_Renderer, rect: Rect, r: u8, g: u8, b: u8) void {
    setColor(renderer, r, g, b, 210);
    _ = c.SDL_RenderDrawLine(renderer, rect.x + 2, rect.y + 2, rect.x + rect.w - 3, rect.y + rect.h - 3);
    _ = c.SDL_RenderDrawLine(renderer, rect.x + rect.w - 3, rect.y + 2, rect.x + 2, rect.y + rect.h - 3);
}

fn fill(renderer: *c.SDL_Renderer, rect: Rect, r: u8, g: u8, b: u8, a: u8) void {
    setColor(renderer, r, g, b, a);
    var value = sdlRect(rect);
    _ = c.SDL_RenderFillRect(renderer, &value);
}

fn outline(renderer: *c.SDL_Renderer, rect: Rect, r: u8, g: u8, b: u8, a: u8) void {
    setColor(renderer, r, g, b, a);
    var value = sdlRect(rect);
    _ = c.SDL_RenderDrawRect(renderer, &value);
}

fn setColor(renderer: *c.SDL_Renderer, r: u8, g: u8, b: u8, a: u8) void {
    _ = c.SDL_SetRenderDrawColor(renderer, r, g, b, a);
}

fn sdlRect(rect: Rect) c.SDL_Rect {
    return .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
}

fn contains(rect: Rect, x: i32, y: i32) bool {
    return x >= rect.x and y >= rect.y and x < rect.x + rect.w and y < rect.y + rect.h;
}

fn tileColor(tile: u16, layer: u8) [3]u8 {
    const hash = @as(u32, tile) *% 1103515245 +% @as(u32, layer) *% 12345;
    return .{
        @intCast(48 + (hash & 127)),
        @intCast(52 + ((hash >> 8) & 127)),
        @intCast(58 + ((hash >> 16) & 127)),
    };
}

fn indexedPreviewColor(index: u8) [3]u8 {
    return .{
        @intCast(((index >> 5) & 7) * 36),
        @intCast(((index >> 2) & 7) * 36),
        @intCast((index & 3) * 85),
    };
}

fn openFirstController() ?*c.SDL_GameController {
    const count = c.SDL_NumJoysticks();
    var index: c_int = 0;
    while (index < count) : (index += 1) if (c.SDL_IsGameController(index) != 0) return c.SDL_GameControllerOpen(index);
    return null;
}

fn fileExists(path: []const u8) bool {
    var buffer: [2048]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&buffer, "{s}", .{path}) catch return false;
    const file = c.fopen(path_z.ptr, "rb") orelse return false;
    _ = c.fclose(file);
    return true;
}

fn captureRenderer(renderer: *c.SDL_Renderer, path: []const u8) !void {
    var width: c_int = 0;
    var height: c_int = 0;
    if (c.SDL_GetRendererOutputSize(renderer, &width, &height) != 0 or width <= 0 or height <= 0) return error.CaptureSize;
    const surface = c.SDL_CreateRGBSurfaceWithFormat(0, width, height, 32, c.SDL_PIXELFORMAT_RGBA8888) orelse return error.CaptureSurface;
    defer c.SDL_FreeSurface(surface);
    if (c.SDL_RenderReadPixels(renderer, null, c.SDL_PIXELFORMAT_RGBA8888, surface.*.pixels, surface.*.pitch) != 0) return error.CaptureRead;
    var buffer: [2048]u8 = undefined;
    const path_z = try std.fmt.bufPrintZ(&buffer, "{s}", .{path});
    if (c.SDL_SaveBMP(surface, path_z.ptr) != 0) return error.CaptureWrite;
}
