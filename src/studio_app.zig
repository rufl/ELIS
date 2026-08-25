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

const Tool = enum(u8) { brush, smart, erase, fill, pick, collision, spawn, goal };
const tools = [_]Tool{ .brush, .smart, .erase, .fill, .pick, .collision, .spawn, .goal };
const tool_labels = [_][]const u8{ "PENCIL", "SMART TERRAIN", "ERASER", "FILL", "EYEDROPPER", "COLLISION", "PLAYER START", "GOAL" };
const Notice = enum { none, saved, exported, asset_selected, asset_incompatible, save_failed, export_failed, invalid_preview };
const Mode = enum { edit, preview };
const Presentation = enum { playful, studio };

const Rect = struct { x: i32, y: i32, w: i32, h: i32 };
const Canvas = struct { rect: Rect, cell: i32, content: Rect };
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

    fn deinit(self: *Atlas) void {
        if (self.texture) |texture| c.SDL_DestroyTexture(texture);
        self.* = .{};
    }
};

const WorkspaceAssets = struct {
    catalog: assets.Catalog = .{},
    palette: assets.Palette = assets.Palette.diagnostic(),
};

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
    dragging: bool = false,
    erase_drag: bool = false,
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

    fn finishStroke(self: *Studio) !void {
        if (try self.stroke.finish()) |command| try self.history.commit(command);
        self.dragging = false;
        self.erase_drag = false;
    }

    fn applyAt(self: *Studio, point: model.Point, erase_override: bool, immediate: bool) !void {
        self.cursor = point;
        const index = self.project.cellIndex(point.x, point.y);
        const effective_tool: Tool = if (erase_override and self.tool != .collision) .erase else self.tool;
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
        }
        if (immediate or effective_tool == .fill or effective_tool == .pick or effective_tool == .spawn or effective_tool == .goal) {
            try self.finishStroke();
        }
    }

    fn togglePresentation(self: *Studio) void {
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

    fn exportMap(self: *Studio) void {
        model.exportLuaFile(self.export_path, self.project) catch {
            self.notice = .export_failed;
            return;
        };
        self.notice = .exported;
    }

    fn togglePreview(self: *Studio) void {
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
    var reduce_motion = false;
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
        } else if (std.mem.startsWith(u8, argument, "--window-width=")) {
            window_width = try std.fmt.parseInt(i32, argument["--window-width=".len..], 10);
        } else if (std.mem.startsWith(u8, argument, "--window-height=")) {
            window_height = try std.fmt.parseInt(i32, argument["--window-height=".len..], 10);
        } else if (std.mem.eql(u8, argument, "--help") or std.mem.eql(u8, argument, "-h")) {
            std.debug.print(
                "Usage: elis-studio [--project=file] [--export=file] [--tileset-name=name] " ++
                    "[--tileset-file=raw-bitmap] [--game-root=game] [--width=N] [--height=N] [--tile-size=N] " ++
                    "[--presentation=playful|studio] [--reduce-motion] [--window-width=N] [--window-height=N] " ++
                    "[--save-export] [--smoke] [--capture=file.bmp]\n",
                .{},
            );
            return;
        } else return error.UnknownStudioArgument;
    }

    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_GAMECONTROLLER | c.SDL_INIT_JOYSTICK) != 0) return error.SdlInit;
    defer c.SDL_Quit();
    const allocator = init.gpa;
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
        .last_saved_revision = project.revision,
        .presentation = presentation,
        .reduce_motion = reduce_motion,
    };
    defer studio.deinit();
    if (save_export_on_start) {
        studio.save();
        studio.exportMap();
        if (studio.notice == .save_failed or studio.notice == .export_failed) return error.StudioWriteFailed;
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
    var previous_buttons: [c.SDL_CONTROLLER_BUTTON_MAX]bool = .{false} ** c.SDL_CONTROLLER_BUTTON_MAX;
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
                c.SDL_QUIT => running = false,
                c.SDL_CONTROLLERDEVICEADDED => {
                    if (gamepad == null) gamepad = openFirstController();
                },
                c.SDL_CONTROLLERDEVICEREMOVED => {
                    if (gamepad) |controller| c.SDL_GameControllerClose(controller);
                    gamepad = openFirstController();
                },
                c.SDL_KEYDOWN => if (event.key.repeat == 0) {
                    if (studio.mode == .edit and (event.key.keysym.sym == c.SDLK_COMMA or event.key.keysym.sym == c.SDLK_PERIOD)) {
                        try cycleLayerAsset(allocator, renderer, &studio, &atlases, game_root, &workspace_assets, if (event.key.keysym.sym == c.SDLK_COMMA) -1 else 1);
                    } else try handleKey(&studio, event.key.keysym.sym, event.key.keysym.mod, &running);
                },
                c.SDL_MOUSEBUTTONDOWN => if (studio.mode == .edit) {
                    const point = canvasPoint(studio.project, canvas, event.button.x, event.button.y);
                    if (point) |value| {
                        studio.dragging = true;
                        studio.erase_drag = event.button.button == c.SDL_BUTTON_RIGHT;
                        try studio.applyAt(value, studio.erase_drag, false);
                    } else try handleChromeClick(allocator, renderer, &studio, &atlases, game_root, &workspace_assets, event.button.x, event.button.y, window_w, window_h);
                },
                c.SDL_MOUSEMOTION => if (studio.mode == .edit and studio.dragging) {
                    if (canvasPoint(studio.project, canvas, event.motion.x, event.motion.y)) |point| {
                        try studio.applyAt(point, studio.erase_drag, false);
                    }
                },
                c.SDL_MOUSEBUTTONUP => if (studio.dragging) try studio.finishStroke(),
                c.SDL_MOUSEWHEEL => if (studio.mode == .edit) {
                    if (event.wheel.y > 0) previousTile(&studio) else if (event.wheel.y < 0) nextTile(&studio, atlases[studio.active_layer].tile_count);
                },
                else => {},
            }
        }
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
        );

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

fn handleKey(studio: *Studio, key: c.SDL_Keycode, modifiers: c.SDL_Keymod, running: *bool) !void {
    const ctrl = (modifiers & c.KMOD_CTRL) != 0;
    if (studio.mode == .preview) {
        if (key == c.SDLK_F7 or key == c.SDLK_ESCAPE or key == c.SDLK_BACKSPACE) studio.mode = .edit;
        return;
    }
    switch (key) {
        c.SDLK_ESCAPE => running.* = false,
        c.SDLK_TAB => studio.togglePresentation(),
        c.SDLK_b => studio.tool = .brush,
        c.SDLK_t => studio.tool = .smart,
        c.SDLK_e => studio.tool = .erase,
        c.SDLK_f => studio.tool = .fill,
        c.SDLK_p => studio.tool = .pick,
        c.SDLK_c => studio.tool = .collision,
        c.SDLK_s => {
            if (ctrl) studio.save() else studio.tool = .spawn;
        },
        c.SDLK_g => studio.tool = .goal,
        c.SDLK_1, c.SDLK_2, c.SDLK_3, c.SDLK_4 => studio.active_layer = @intCast(key - c.SDLK_1),
        c.SDLK_LEFTBRACKET => previousTile(studio),
        c.SDLK_RIGHTBRACKET => nextTile(studio, 0),
        c.SDLK_PAGEUP => {
            if (studio.palette_page > 0) studio.palette_page -= 1;
        },
        c.SDLK_PAGEDOWN => studio.palette_page = @min(studio.palette_page + 1, 15),
        c.SDLK_z => {
            if (ctrl) _ = try studio.history.undo(&studio.project);
        },
        c.SDLK_y => {
            if (ctrl) _ = try studio.history.redo(&studio.project);
        },
        c.SDLK_F5 => studio.exportMap(),
        c.SDLK_F6 => studio.togglePreview(),
        c.SDLK_F7 => studio.mode = .edit,
        c.SDLK_LEFT => studio.cursor.x -|= 1,
        c.SDLK_RIGHT => studio.cursor.x = @min(studio.cursor.x + 1, studio.project.width - 1),
        c.SDLK_UP => studio.cursor.y -|= 1,
        c.SDLK_DOWN => studio.cursor.y = @min(studio.cursor.y + 1, studio.project.height - 1),
        c.SDLK_SPACE, c.SDLK_RETURN => try studio.applyAt(studio.cursor, false, true),
        c.SDLK_BACKSPACE, c.SDLK_DELETE => try studio.applyAt(studio.cursor, true, true),
        else => {},
    }
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
) !void {
    var current: [c.SDL_CONTROLLER_BUTTON_MAX]bool = .{false} ** c.SDL_CONTROLLER_BUTTON_MAX;
    for (0..c.SDL_CONTROLLER_BUTTON_MAX) |index| current[index] = c.SDL_GameControllerGetButton(controller, @intCast(index)) != 0;
    const pressed = struct {
        fn value(now: []const bool, before: []const bool, button_index: usize) bool {
            return now[button_index] and !before[button_index];
        }
    }.value;
    if (studio.mode == .preview) {
        if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_B) or pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_BACK)) studio.mode = .edit;
        previous.* = current;
        return;
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_LEFT)) studio.cursor.x -|= 1;
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_RIGHT)) studio.cursor.x = @min(studio.cursor.x + 1, studio.project.width - 1);
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_UP)) studio.cursor.y -|= 1;
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_DPAD_DOWN)) studio.cursor.y = @min(studio.cursor.y + 1, studio.project.height - 1);
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_A)) try studio.applyAt(studio.cursor, false, true);
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_B)) try studio.applyAt(studio.cursor, true, true);
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_X)) {
        const value = studio.project.layerCells(studio.active_layer)[studio.project.cellIndex(studio.cursor.x, studio.cursor.y)];
        if (value != model.empty_tile) studio.selected_tile = value;
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_Y)) studio.tool = @enumFromInt((@intFromEnum(studio.tool) + 1) % tools.len);
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_LEFTSHOULDER)) previousTile(studio);
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER)) nextTile(studio, tile_count);
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_LEFTSTICK)) studio.togglePresentation();
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_RIGHTSTICK)) {
        try cycleLayerAsset(allocator, renderer, studio, atlases, game_root, workspace, 1);
    }
    if (pressed(&current, previous, c.SDL_CONTROLLER_BUTTON_BACK)) studio.togglePreview();
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
        if (x >= 380 and x < 490) studio.exportMap();
        if (x >= 500 and x < 620) studio.togglePreview();
        if (x >= 630 and x < 770) studio.togglePresentation();
        return;
    }
    if (x < layout.left) {
        if (y >= layout.tool_y and y < layout.tool_y + @as(i32, @intCast(tools.len)) * layout.tool_step) {
            studio.tool = @enumFromInt(@as(u8, @intCast(@divTrunc(y - layout.tool_y, layout.tool_step))));
            return;
        }
        if (y >= layout.layer_y and y < layout.layer_y + @as(i32, model.layer_count) * layout.tool_step) {
            studio.active_layer = @intCast(@divTrunc(y - layout.layer_y, layout.tool_step));
            studio.palette_page = studio.selected_tile / 64;
            return;
        }
    }
    if (x >= window_w - layout.right) {
        const right_x = window_w - layout.right;
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

    drawText(renderer, 18, 70, 1, if (playful) "CHOOSE A TOOL" else "TOOLS", 154, 184, 222);
    for (tools, 0..) |tool, index| {
        button(renderer, .{
            .x = 14,
            .y = layout.tool_y + @as(i32, @intCast(index)) * layout.tool_step,
            .w = layout.left - 28,
            .h = layout.tool_step - 5,
        }, tool_labels[index], studio.tool == tool);
    }
    drawText(renderer, 18, layout.layer_y - 22, 1, if (playful) "BUILDING LAYERS" else "LAYERS  BOTTOM -> TOP", 154, 184, 222);
    for (model.layer_names, 0..) |name, index| {
        const layer_y = layout.layer_y + @as(i32, @intCast(index)) * layout.tool_step;
        button(renderer, .{ .x = 14, .y = layer_y, .w = layout.left - 28, .h = layout.tool_step - 5 }, name, studio.active_layer == index);
        if (playful and layout.left >= 220) {
            drawTextClipped(renderer, 82, layer_y + layout.tool_step - 16, 1, studio.project.layerTilesetName(index), 20, 132, 151, 177);
        }
    }
    drawGuide(renderer, studio, layout, height);

    const canvas = canvasLayout(studio.project, width, height, .edit, layout);
    drawMap(renderer, studio, atlases, canvas, true);

    const right_x = width - layout.right;
    drawText(renderer, right_x + 18, 70, 1, if (studio.tool == .smart) "SMART MATERIAL FAMILY" else "TILE PALETTE", 154, 184, 222);
    var buffer: [128]u8 = undefined;
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

    const report = model.validate(studio.project);
    const validation_y = asset_y + 5 * 25 + 12;
    drawText(renderer, right_x + 18, validation_y, 1, "LEVEL CHECK", 154, 184, 222);
    const summary = std.fmt.bufPrint(&buffer, "{d} ERRORS  {d} WARNINGS", .{ report.error_count, report.warning_count }) catch "VALIDATION";
    drawText(renderer, right_x + 18, validation_y + 18, 1, summary, if (report.error_count > 0) 246 else 111, if (report.error_count > 0) 112 else 214, 112);
    const reachable = std.fmt.bufPrint(&buffer, "{d} REACHABLE CELLS", .{report.reachable_cells}) catch "";
    drawText(renderer, right_x + 18, validation_y + 34, 1, reachable, 125, 145, 173);
    const visible_issues = @min(report.count, @as(u8, @intCast(@max(@divTrunc(height - bar_bottom - validation_y - 58, 17), 0))));
    for (report.issues[0..visible_issues], 0..) |issue, index| {
        drawText(renderer, right_x + 18, validation_y + 54 + @as(i32, @intCast(index)) * 17, 1, issueLabel(issue.kind), if (issue.severity == .@"error") 246 else 236, if (issue.severity == .@"error") 112 else 199, 110);
    }
    drawNotice(renderer, studio.notice, width, height);
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
                const tile = studio.project.layerCells(layer)[index];
                if (tile != model.empty_tile) drawTile(renderer, atlases[layer], tile, rect, @intCast(layer));
            }
            if (editor_overlay and studio.project.solid[index] != 0) {
                fill(renderer, rect, 225, 62, 76, 82);
                drawCross(renderer, rect, 225, 62, 76);
            }
            if (editor_overlay and canvas.cell >= 8) outline(renderer, rect, 45, 53, 68, 110);
        }
    }
    if (studio.project.spawn) |point| drawMarker(renderer, canvas, point, "S", 72, 220, 132);
    if (studio.project.goal) |point| drawMarker(renderer, canvas, point, "G", 244, 192, 74);
    if (editor_overlay) {
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
        atlas.* = if (legacy_path) |path|
            try loadAtlas(allocator, renderer, path, project.tile_size, workspace.palette)
        else
            try loadCatalogAtlas(allocator, renderer, game_root, workspace, project.layerTilesetName(layer), project.tile_size);
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
    const root = game_root orelse return .{};
    const asset_index = workspace.catalog.find(name) orelse return .{};
    const asset = &workspace.catalog.items[asset_index];
    if (asset.width != tile_size or asset.height != tile_size) return .{};
    var path_buffer: [2048]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ root, asset.name() });
    return loadAtlas(allocator, renderer, path, tile_size, workspace.palette);
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
    atlases[layer].deinit();
    atlases[layer] = replacement;
    studio.project.setLayerTilesetName(layer, asset.name());
    studio.project.revision +%= 1;
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

fn compatibleAssetCount(catalog: *const assets.Catalog, tile_size: u16) usize {
    var count: usize = 0;
    for (catalog.slice()) |asset| {
        if (asset.width == tile_size and asset.height == tile_size) count += 1;
    }
    return count;
}

fn compatibleAssetIndex(catalog: *const assets.Catalog, tile_size: u16, ordinal: usize) ?usize {
    var compatible: usize = 0;
    for (catalog.slice(), 0..) |asset, index| {
        if (asset.width != tile_size or asset.height != tile_size) continue;
        if (compatible == ordinal) return index;
        compatible += 1;
    }
    return null;
}

fn loadAtlas(allocator: std.mem.Allocator, renderer: *c.SDL_Renderer, path: ?[]const u8, tile_size: u16, palette: assets.Palette) !Atlas {
    const source_path = path orelse return .{};
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const bytes = std.Io.Dir.cwd().readFileAlloc(threaded.io(), source_path, allocator, .limited(16 * 1024 * 1024)) catch return .{};
    defer allocator.free(bytes);
    const pixels_per_tile = @as(usize, tile_size) * tile_size;
    if (pixels_per_tile == 0 or bytes.len < pixels_per_tile) return .{};
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
        .layer_y = tool_y + @as(i32, @intCast(tools.len)) * tool_step + 28,
        .palette_y = 104,
        .palette_cell = palette_cell,
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
    _ = project;
    if (!contains(canvas.content, x, y)) return null;
    return .{
        .x = @intCast(@divTrunc(x - canvas.content.x, canvas.cell)),
        .y = @intCast(@divTrunc(y - canvas.content.y, canvas.cell)),
    };
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
        if (available >= 58) drawText(renderer, 18, y + 16, 1, "B/T/E/F/P/C/S/G TOOLS", 125, 145, 173);
        if (available >= 74) drawText(renderer, 18, y + 32, 1, "F5 EXPORT  F6 PREVIEW", 125, 145, 173);
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
    drawTextClipped(renderer, 24, y + 52, 1, guideLine(studio.tool), @intCast(@max(@divTrunc(layout.left - 48, font.advance), 1)), 202, 215, 232);
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
        .export_failed => "EXPORT FAILED - SOURCE RETAINED",
        .invalid_preview => "FIX VALIDATION ERRORS BEFORE PREVIEW",
    };
    const problem = notice == .save_failed or notice == .export_failed or notice == .invalid_preview or notice == .asset_incompatible;
    drawText(renderer, 18, height - 20, 1, label, if (problem) 246 else 154, if (problem) 112 else 184, 222);
    _ = width;
}

fn issueLabel(kind: model.IssueKind) []const u8 {
    return switch (kind) {
        .missing_spawn => "ERROR: PLACE PLAYER SPAWN",
        .missing_goal => "ERROR: PLACE GOAL",
        .spawn_blocked => "ERROR: SPAWN IS BLOCKED",
        .goal_blocked => "ERROR: GOAL IS BLOCKED",
        .goal_unreachable => "ERROR: GOAL UNREACHABLE",
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
