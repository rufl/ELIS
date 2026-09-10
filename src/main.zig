//! ELIS simulator process.
//!
//! The runtime owns package admission, the bounded Lua VM, the indexed Lupi
//! renderer, host menus/debugging, and final SDL composition. Compatibility
//! changes require matching fixtures and documentation in `COMPATIBILITY.md`.

const std = @import("std");
const builtin = @import("builtin");
const native = @import("native.zig");
const c = native.c;
const input_mod = @import("input.zig");
const Input = input_mod.Input;
const Audio = @import("audio.zig").Audio;
const localization = @import("localization.zig");
const Settings = @import("settings.zig").Settings;
const font = @import("font.zig");
const debug_mod = @import("debug.zig");
const lupi_profile = @import("studio/lupi_profile.zig");

// The Lupi ABI fixes the logical resolution. SDL scales this indexed surface;
// games never observe the host window size.
const W = 480;
const H = 270;
const lupi_flash_bytes = lupi_profile.flash_bytes;
const lupi_archive_entries_max = lupi_profile.archive_entries_max;
const lupi_psram_bytes = lupi_profile.psram_bytes;
const lupi_lua_heap_bytes_max = lupi_profile.lua_heap_bytes_max;
const lupi_tileset_pixels_max = lupi_profile.tileset_pixels_max;
const host_download_bytes_max = lupi_profile.host_demo_download_bytes_max;
const raster_work_max: usize = lupi_profile.tile_sample_pixels_max * 4;
const lupi_codec_revision = "3e8c66299a4606b36b9f490212acc44e084a6aa2";
comptime {
    std.debug.assert(W == lupi_profile.frame_width);
    std.debug.assert(H == lupi_profile.frame_height);
}
const A = std.heap.page_allocator;
const Color = struct { r: u8, g: u8, b: u8, a: u8 };
const Region = struct { x: i32 = 0, y: i32 = 0, w: i32 = 0, h: i32 = 0 };

// The simulator is intentionally single-instance. Lua C callbacks carry no
// engine pointer in the upstream API, so callback-visible runtime state lives
// here while cohesive platform state (input) is encapsulated in its own type.
var fb: [H][W]u8 = undefined;
var pal: [256]Color = .{Color{ .r = 0, .g = 0, .b = 0, .a = 255 }} ** 256;
var cam = Region{};
var clip = Region{};
var clipping = false;
var pattern: [8]u8 = .{0} ** 8;
var raster_work_remaining: usize = raster_work_max;
var input_state: Input = .{};
var audio_state: Audio = .{};
var L: *c.lua_State = undefined;
var ticks: f64 = 0;
var last_frame_ms: f64 = 1000.0 / debug_mod.target_simulation_hz;
var last_work_ms: f64 = 0;
var debug_state: debug_mod.State = .{};
var legacy_sprite_ref: c_int = c.LUA_NOREF;
var game_root: []const u8 = "example";
const BrowserNotice = enum {
    none,
    searching,
    update_failed,
    network_failed,
    catalog_missing,
    codec_download_failed,
    codec_extract_failed,
    codec_invalid,
    demo_prepare_failed,
    codec_host_failed,
    codec_run_failed,
    codec_output_missing,
    demo_source_invalid,
    demo_install_failed,
    audio_copy_failed,
    demos_updated,
    no_updates,
};
const SettingsPage = enum { none, language, controls };
const ControlsNotice = enum { none, saved, save_failed, conflict, defaults_restored };

const LuaHeap = struct {
    used_bytes: usize = 0,

    fn reset(self: *LuaHeap) void {
        std.debug.assert(self.used_bytes == 0);
        self.* = .{};
    }
};
var lua_heap = LuaHeap{};

fn luaAllocate(
    user_data: ?*anyopaque,
    pointer: ?*anyopaque,
    old_size: usize,
    new_size: usize,
) callconv(.c) ?*anyopaque {
    const heap: *LuaHeap = @ptrCast(@alignCast(user_data orelse return null));
    const previous_size = if (pointer == null) 0 else old_size;
    if (new_size == 0) {
        if (pointer) |allocation| c.free(allocation);
        std.debug.assert(previous_size <= heap.used_bytes);
        heap.used_bytes -= previous_size;
        return null;
    }
    if (new_size > previous_size) {
        const growth = new_size - previous_size;
        if (growth > lupi_lua_heap_bytes_max - heap.used_bytes) return null;
    }
    const allocation = c.realloc(pointer, new_size) orelse return null;
    heap.used_bytes = heap.used_bytes - previous_size + new_size;
    return allocation;
}

var settings_state = Settings{};
var browser_notice: BrowserNotice = .none;
var update_log: ?*c.FILE = null;
var update_log_available = false;
var update_dialog = false;
var quit_dialog = false;
var quit_selection: usize = 0;
var settings_page: SettingsPage = .none;
var language_selection: usize = 0;
var controls_selection: usize = 0;
var controls_binding_page: usize = 0;
var controls_capture = false;
var controls_capture_armed = false;
var controls_notice: ControlsNotice = .none;
var controls_conflict_action: input_mod.Action = .up;
var language_save_failed = false;
const Demo = struct { name: []const u8, path: []const u8, official: bool };
var demos: [64]Demo = undefined;
var demo_count: usize = 0;

// -----------------------------------------------------------------------------
// Native demo acquisition and installation

const DownloadTarget = struct {
    file: *c.FILE,
    bytes_written: usize = 0,
};

fn downloadChunkSize(bytes_written: usize, size: usize, count: usize) ?usize {
    if (bytes_written > host_download_bytes_max) return null;
    const byte_count = std.math.mul(usize, size, count) catch return null;
    if (byte_count > host_download_bytes_max - bytes_written) return null;
    return byte_count;
}

fn curlWrite(data: ?*anyopaque, size: usize, count: usize, user: ?*anyopaque) callconv(.c) usize {
    const target: *DownloadTarget = @ptrCast(@alignCast(user orelse return 0));
    const byte_count = downloadChunkSize(target.bytes_written, size, count) orelse
        return 0;
    if (c.fwrite(data, 1, byte_count, target.file) != byte_count) return 0;
    target.bytes_written += byte_count;
    return byte_count;
}

fn downloadFile(url: []const u8, path: []const u8) bool {
    var url_z: [2048]u8 = undefined;
    var path_z: [2048]u8 = undefined;
    const uz = std.fmt.bufPrintZ(&url_z, "{s}", .{url}) catch return false;
    const pz = std.fmt.bufPrintZ(&path_z, "{s}", .{path}) catch return false;
    const file = c.fopen(pz.ptr, "wb") orelse return false;
    var file_open = true;
    defer {
        if (file_open) _ = c.fclose(file);
    }
    const easy = c.curl_easy_init() orelse return false;
    defer c.curl_easy_cleanup(easy);
    var target = DownloadTarget{ .file = file };
    if (c.curl_easy_setopt(easy, c.CURLOPT_URL, uz.ptr) != c.CURLE_OK or
        c.curl_easy_setopt(easy, c.CURLOPT_FOLLOWLOCATION, @as(c_long, 1)) != c.CURLE_OK or
        c.curl_easy_setopt(easy, c.CURLOPT_FAILONERROR, @as(c_long, 1)) != c.CURLE_OK or
        c.curl_easy_setopt(easy, c.CURLOPT_NOSIGNAL, @as(c_long, 1)) != c.CURLE_OK or
        c.curl_easy_setopt(easy, c.CURLOPT_CONNECTTIMEOUT, @as(c_long, 15)) != c.CURLE_OK or
        c.curl_easy_setopt(easy, c.CURLOPT_TIMEOUT, @as(c_long, 300)) != c.CURLE_OK or
        c.curl_easy_setopt(easy, c.CURLOPT_PROTOCOLS_STR, "https") != c.CURLE_OK or
        c.curl_easy_setopt(easy, c.CURLOPT_REDIR_PROTOCOLS_STR, "https") != c.CURLE_OK or
        c.curl_easy_setopt(
            easy,
            c.CURLOPT_MAXFILESIZE_LARGE,
            @as(c.curl_off_t, host_download_bytes_max),
        ) != c.CURLE_OK or
        c.curl_easy_setopt(easy, c.CURLOPT_USERAGENT, "elis/1.0") != c.CURLE_OK or
        c.curl_easy_setopt(
            easy,
            c.CURLOPT_WRITEFUNCTION,
            @as(c.curl_write_callback, @ptrCast(&curlWrite)),
        ) != c.CURLE_OK or
        c.curl_easy_setopt(easy, c.CURLOPT_WRITEDATA, &target) != c.CURLE_OK)
    {
        return false;
    }
    const result = c.curl_easy_perform(easy);
    if (result != c.CURLE_OK) {
        logUpdate("Download", std.mem.span(c.curl_easy_strerror(result)));
        return false;
    }
    if (c.fflush(file) != 0) {
        return false;
    }
    const close_result = c.fclose(file);
    file_open = false;
    return close_result == 0;
}
fn copyFileRaw(source: []const u8, destination: []const u8) bool {
    var source_z: [2048]u8 = undefined;
    var destination_z: [2048]u8 = undefined;
    const src = std.fmt.bufPrintZ(&source_z, "{s}", .{source}) catch return false;
    const dst = std.fmt.bufPrintZ(&destination_z, "{s}", .{destination}) catch return false;
    const input = c.fopen(src.ptr, "rb") orelse return false;
    defer _ = c.fclose(input);
    const output = c.fopen(dst.ptr, "wb") orelse return false;
    var output_open = true;
    defer {
        if (output_open) _ = c.fclose(output);
    }
    var buffer: [8192]u8 = undefined;
    while (true) {
        const got = c.fread(&buffer, 1, buffer.len, input);
        if (got > 0 and c.fwrite(&buffer, 1, got, output) != got) return false;
        if (got < buffer.len) {
            if (c.ferror(input) != 0 or c.fflush(output) != 0) return false;
            const close_result = c.fclose(output);
            output_open = false;
            return close_result == 0;
        }
    }
}

/// Copies only regular files and directories from a private extracted tree.
/// Symlinks and unsupported node types fail closed before installation.
fn copyTree(source: []const u8, destination: []const u8) bool {
    var source_z: [2048]u8 = undefined;
    var destination_z: [2048]u8 = undefined;
    const src = std.fmt.bufPrintZ(&source_z, "{s}", .{source}) catch return false;
    const dst = std.fmt.bufPrintZ(&destination_z, "{s}", .{destination}) catch return false;
    if (native.mkdir(dst.ptr, 0o755) != 0 and packageEntryKind(destination) != .directory) {
        return false;
    }
    const dir = c.opendir(src.ptr) orelse return false;
    defer _ = c.closedir(dir);
    while (c.readdir(dir)) |entry| {
        const name = std.mem.sliceTo(entry.*.d_name[0..], 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        var child_source: [2048]u8 = undefined;
        var child_destination: [2048]u8 = undefined;
        const cs = std.fmt.bufPrint(&child_source, "{s}/{s}", .{ source, name }) catch return false;
        const cd = std.fmt.bufPrint(&child_destination, "{s}/{s}", .{ destination, name }) catch return false;
        switch (packageEntryKind(cs)) {
            .directory => if (!copyTree(cs, cd)) return false,
            .regular => if (!copyFileRaw(cs, cd)) return false,
            .invalid => return false,
        }
    }
    return true;
}
fn isRuntimeMedia(path: []const u8) bool {
    return endsWith(path, ".mp3") or endsWith(path, ".ogg") or endsWith(path, ".wav") or endsWith(path, ".flac");
}

fn githubRepositorySlug(url: []const u8) ?[]const u8 {
    const prefix = "https://github.com/";
    if (!std.mem.startsWith(u8, url, prefix)) return null;
    const repository = url[prefix.len..];
    const slash = std.mem.indexOfScalar(u8, repository, '/') orelse return null;
    if (std.mem.indexOfScalarPos(u8, repository, slash + 1, '/') != null) return null;
    const owner = repository[0..slash];
    const slug = repository[slash + 1 ..];
    if (!githubPathComponent(owner) or !githubPathComponent(slug)) return null;
    return slug;
}

fn githubPathComponent(component: []const u8) bool {
    if (!@import("studio/package_path.zig").safeComponent(component)) return false;
    for (component) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-' and byte != '.') {
            return false;
        }
    }
    return true;
}

/// The official codec currently discards files it does not transform. Keep
/// runtime audio alongside the encoded release so demos using `sfx.music`
/// remain self-contained after installation.
const CopyMediaResult = struct { success: bool = true, changed: bool = false };
fn copyRuntimeMedia(source: []const u8, destination: []const u8, replace_existing: bool) CopyMediaResult {
    var source_z: [2048]u8 = undefined;
    const src = std.fmt.bufPrintZ(&source_z, "{s}", .{source}) catch return .{ .success = false };
    const dir = c.opendir(src.ptr) orelse return .{ .success = false };
    defer _ = c.closedir(dir);
    var result = CopyMediaResult{};
    while (c.readdir(dir)) |entry| {
        const name = std.mem.sliceTo(entry.*.d_name[0..], 0);
        if (name.len == 0 or name[0] == '.') continue;
        var source_child: [2048]u8 = undefined;
        var destination_child: [2048]u8 = undefined;
        const source_path = std.fmt.bufPrint(&source_child, "{s}/{s}", .{ source, name }) catch return .{ .success = false };
        const destination_path = std.fmt.bufPrint(&destination_child, "{s}/{s}", .{ destination, name }) catch return .{ .success = false };
        if (packageEntryKind(source_path) == .directory) {
            var destination_z: [2048]u8 = undefined;
            const target = std.fmt.bufPrintZ(&destination_z, "{s}", .{destination_path}) catch return .{ .success = false };
            _ = native.mkdir(target.ptr, 0o755);
            const nested = copyRuntimeMedia(source_path, destination_path, replace_existing);
            if (!nested.success) return nested;
            result.changed = result.changed or nested.changed;
        } else if (packageEntryKind(source_path) == .regular and isRuntimeMedia(name)) {
            if (!replace_existing and fileExists(destination_path)) continue;
            makeParentDirs(destination_path);
            if (!copyFileRaw(source_path, destination_path)) return .{ .success = false };
            result.changed = true;
        }
    }
    return result;
}
fn findGameRoot(root: []const u8, depth: usize) ?[]const u8 {
    var game: [2048]u8 = undefined;
    const game_path = std.fmt.bufPrint(&game, "{s}/game.lua", .{root}) catch return null;
    if (fileExists(game_path)) return copyString(root);
    if (depth == 0) return null;
    var root_z: [2048]u8 = undefined;
    const root_path = std.fmt.bufPrintZ(&root_z, "{s}", .{root}) catch return null;
    const dir = c.opendir(root_path.ptr) orelse return null;
    defer _ = c.closedir(dir);
    while (c.readdir(dir)) |entry| {
        const name = std.mem.sliceTo(entry.*.d_name[0..], 0);
        if (name.len == 0 or name[0] == '.') continue;
        var child: [2048]u8 = undefined;
        const child_path = std.fmt.bufPrint(&child, "{s}/{s}", .{ root, name }) catch continue;
        if (packageEntryKind(child_path) != .directory) continue;
        if (findGameRoot(child_path, depth - 1)) |found| return found;
    }
    return null;
}
fn findFileRoot(root: []const u8, filename: []const u8, depth: usize) ?[]const u8 {
    var candidate: [2048]u8 = undefined;
    const candidate_path = std.fmt.bufPrint(&candidate, "{s}/{s}", .{ root, filename }) catch return null;
    if (fileExists(candidate_path)) return copyString(root);
    if (depth == 0) return null;
    var root_z: [2048]u8 = undefined;
    const root_path = std.fmt.bufPrintZ(&root_z, "{s}", .{root}) catch return null;
    const dir = c.opendir(root_path.ptr) orelse return null;
    defer _ = c.closedir(dir);
    while (c.readdir(dir)) |entry| {
        const name = std.mem.sliceTo(entry.*.d_name[0..], 0);
        if (name.len == 0 or name[0] == '.') continue;
        var child: [2048]u8 = undefined;
        const child_path = std.fmt.bufPrint(&child, "{s}/{s}", .{ root, name }) catch continue;
        if (packageEntryKind(child_path) != .directory) continue;
        if (findFileRoot(child_path, filename, depth - 1)) |found| return found;
    }
    return null;
}
fn runCodec(codec_root: []const u8, input_root: []const u8, output_root: []const u8) bool {
    const previous_notice = browser_notice;
    browser_notice = .codec_run_failed;
    var script: [2048]u8 = undefined;
    const script_path = std.fmt.bufPrintZ(&script, "{s}/run.lua", .{codec_root}) catch return false;
    var package_path: [4096]u8 = undefined;
    const package = std.fmt.bufPrintZ(&package_path, "{s}/?.lua", .{codec_root}) catch return false;
    const state = c.luaL_newstate() orelse return false;
    defer c.lua_close(state);
    c.luaL_openlibs(state);
    if (native.windows and !@import("codec_windows.zig").install(state, output_root)) {
        browser_notice = .codec_host_failed;
        logUpdate("Windows converter", "Requires MSYS2 Bash/coreutils and ImageMagick 7. Set ELIS_CODEC_BASH if Bash is not C:/msys64/usr/bin/bash.exe.");
        if (c.lua_tolstring(state, -1, null)) |message| logUpdate("Codec host", std.mem.span(message));
        return false;
    }
    _ = c.lua_getglobal(state, "package");
    _ = c.lua_pushstring(state, package.ptr);
    c.lua_setfield(state, -2, "path");
    _ = c.lua_pop(state, 1);
    c.lua_newtable(state);
    _ = c.lua_pushstring(state, "lupi-codec");
    c.lua_rawseti(state, -2, 0);
    _ = c.lua_pushlstring(state, input_root.ptr, input_root.len);
    c.lua_rawseti(state, -2, 1);
    _ = c.lua_pushlstring(state, output_root.ptr, output_root.len);
    c.lua_rawseti(state, -2, 2);
    c.lua_setglobal(state, "arg");
    if (c.luaL_loadfilex(state, script_path.ptr, null) != c.LUA_OK) {
        if (c.lua_tolstring(state, -1, null)) |message| logUpdate("Codec load", std.mem.span(message));
        return false;
    }
    if (c.lua_pcallk(state, 0, 0, 0, 0, null) != c.LUA_OK) {
        if (c.lua_tolstring(state, -1, null)) |message| logUpdate("Codec", std.mem.span(message));
        return false;
    }
    browser_notice = previous_notice;
    return true;
}

fn replaceEqualLength(data: []u8, old: []const u8, new: []const u8) bool {
    if (old.len != new.len) return false;
    const at = std.mem.indexOf(u8, data, old) orelse return false;
    @memcpy(data[at..][0..new.len], new);
    return true;
}

/// The codec's current encoder still places red in the low five bits, while
/// Lupi RGB555 and Lupinho commit 379a599 place blue low and red high. Normalize
/// the temporary downloaded codec before execution so fetched demos retain
/// their intended colors under the console ABI.
fn normalizeCodecPaletteOrder(codec_root: []const u8) bool {
    var path_buffer: [2048]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buffer, "{s}/colors_convert.lua", .{codec_root}) catch return false;
    const source = assetAll(path) orelse return false;
    defer A.free(source);

    const already_rgb555 = std.mem.indexOf(u8, source, "bit.lshift(r5, 10)") != null and
        std.mem.indexOf(u8, source, "local b5 = bit.band(val, 0x1F)") != null;
    if (already_rgb555) return true;

    const changed = replaceEqualLength(source, "bit.lshift(b5, 10)", "bit.lshift(r5, 10)") and
        replaceEqualLength(source, "\n    r5\n  )", "\n    b5\n  )") and
        replaceEqualLength(source, "local b5 = bit.band(bit.rshift(val, 10), 0x1F)", "local r5 = bit.band(bit.rshift(val, 10), 0x1F)") and
        replaceEqualLength(source, "local r5 = bit.band(val, 0x1F)", "local b5 = bit.band(val, 0x1F)");
    if (!changed) return false;

    var path_z_buffer: [2048]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_z_buffer, "{s}", .{path}) catch return false;
    const file = c.fopen(path_z.ptr, "wb") orelse return false;
    defer _ = c.fclose(file);
    return c.fwrite(source.ptr, 1, source.len, file) == source.len and
        c.fflush(file) == 0;
}
fn logUpdate(stage: []const u8, detail: []const u8) void {
    std.debug.print("{s}: {s}\n", .{ stage, detail });
    if (update_log) |file| {
        _ = c.fwrite(stage.ptr, 1, stage.len, file);
        _ = c.fwrite(": ", 1, 2, file);
        _ = c.fwrite(detail.ptr, 1, detail.len, file);
        _ = c.fwrite("\n", 1, 1, file);
    }
}

fn updateCatalog(replace_existing: bool) bool {
    update_log = c.fopen("elis-update.log", "wb");
    update_log_available = update_log != null;
    defer {
        if (update_log) |file| _ = c.fclose(file);
        update_log = null;
    }
    logUpdate("Updater", "Official demo download and conversion");
    browser_notice = .searching;
    const success = nativeUpdateCatalog(replace_existing);
    if (!success and browser_notice == .searching) browser_notice = .update_failed;
    logUpdate("Result", localizedBrowserNotice(localization.get(.en)));
    return success;
}

fn nativeUpdateCatalog(replace_existing: bool) bool {
    if (c.curl_global_init(c.CURL_GLOBAL_DEFAULT) != c.CURLE_OK) {
        browser_notice = .network_failed;
        return false;
    }
    defer c.curl_global_cleanup();
    const catalog = assetAll("demos/catalog.txt") orelse {
        browser_notice = .catalog_missing;
        return false;
    };
    defer A.free(catalog);
    var work_template: [2048]u8 = undefined;
    const work = native.temporaryDirectory(&work_template, "elis-native") orelse return false;
    defer removeTree(work);

    const codec_zip = std.fmt.allocPrint(A, "{s}/codec.zip", .{work}) catch return false;
    defer A.free(codec_zip);
    var codec_url_buffer: [256]u8 = undefined;
    const codec_url = std.fmt.bufPrint(
        &codec_url_buffer,
        "https://github.com/lupi-org-br/lupi-codec/archive/{s}.zip",
        .{lupi_codec_revision},
    ) catch return false;
    if (!downloadFile(codec_url, codec_zip)) {
        browser_notice = .codec_download_failed;
        return false;
    }
    const codec_archive = extractArchive(codec_zip, host_download_bytes_max) orelse {
        browser_notice = .codec_extract_failed;
        return false;
    };
    defer {
        removeTree(codec_archive);
        A.free(codec_archive);
    }
    const codec_root = findFileRoot(codec_archive, "run.lua", 2) orelse {
        browser_notice = .codec_invalid;
        return false;
    };
    defer A.free(codec_root);
    if (!normalizeCodecPaletteOrder(codec_root)) {
        browser_notice = .codec_invalid;
        return false;
    }
    var updated = false;
    var failed = false;
    var cursor: usize = 0;
    while (cursor < catalog.len) {
        const end = std.mem.indexOfScalarPos(u8, catalog, cursor, '\n') orelse catalog.len;
        const line_text = std.mem.trim(u8, catalog[cursor..end], " \t\r");
        cursor = if (end < catalog.len) end + 1 else catalog.len;
        if (line_text.len == 0 or line_text[0] == '#') continue;
        var parts = std.mem.splitScalar(u8, line_text, '|');
        const name = parts.next() orelse continue;
        const url = parts.next() orelse continue;
        if (std.mem.startsWith(u8, url, "builtin:")) continue;
        logUpdate("Demo", url);
        const slug = githubRepositorySlug(url) orelse continue;
        if (slug.len > 80) continue;
        var target: [2048]u8 = undefined;
        const target_path = std.fmt.bufPrint(&target, "demos/{s}", .{slug}) catch {
            failed = true;
            continue;
        };
        const target_exists = fileExists(target_path);
        var source_zip: [2048]u8 = undefined;
        const source_zip_path = std.fmt.bufPrint(&source_zip, "{s}/{s}.zip", .{ work, slug }) catch {
            failed = true;
            continue;
        };
        var source_url: [2048]u8 = undefined;
        const main_url = std.fmt.bufPrint(&source_url, "{s}/archive/refs/heads/main.zip", .{url}) catch {
            failed = true;
            continue;
        };
        if (!downloadFile(main_url, source_zip_path)) {
            const master_url = std.fmt.bufPrint(&source_url, "{s}/archive/refs/heads/master.zip", .{url}) catch {
                failed = true;
                continue;
            };
            if (!downloadFile(master_url, source_zip_path)) {
                browser_notice = .network_failed;
                failed = true;
                continue;
            }
        }
        {
            const source_archive = extractArchive(
                source_zip_path,
                host_download_bytes_max,
            ) orelse {
                browser_notice = .codec_extract_failed;
                failed = true;
                continue;
            };
            defer {
                removeTree(source_archive);
                A.free(source_archive);
            }
            const source_root = findGameRoot(source_archive, 2) orelse {
                browser_notice = .demo_source_invalid;
                failed = true;
                continue;
            };
            defer A.free(source_root);
            // Safe fetches never replace encoded game data, but may add runtime
            // media omitted by older codec runs.
            if (target_exists and !replace_existing) {
                const media = copyRuntimeMedia(source_root, target_path, false);
                if (!media.success) {
                    browser_notice = .audio_copy_failed;
                    failed = true;
                } else if (media.changed) updated = true;
                continue;
            }
            var output: [2048]u8 = undefined;
            const output_path = std.fmt.bufPrint(
                &output,
                "{s}/{s}-release",
                .{ work, slug },
            ) catch {
                failed = true;
                continue;
            };
            if (!runCodec(codec_root, source_root, output_path)) {
                failed = true;
                continue;
            }
            var current: [2048]u8 = undefined;
            const current_path = std.fmt.bufPrint(
                &current,
                "{s}/current",
                .{output_path},
            ) catch {
                failed = true;
                continue;
            };
            if (!fileExists(current_path)) {
                browser_notice = .codec_output_missing;
                failed = true;
                continue;
            }
            if (!copyRuntimeMedia(source_root, current_path, true).success) {
                browser_notice = .audio_copy_failed;
                failed = true;
                continue;
            }
            _ = native.mkdir("demos", 0o755);
            if (installTreeAtomically(current_path, target_path)) updated = true else {
                browser_notice = .demo_install_failed;
                logUpdate("Install failed; check destination permissions", target_path);
                failed = true;
            }
        }
        _ = name;
    }
    if (failed) {
        if (browser_notice == .searching) browser_notice = .update_failed;
        return false;
    }
    browser_notice = if (updated) .demos_updated else .no_updates;
    return true;
}

fn fileExists(path: []const u8) bool {
    var z: [2048]u8 = undefined;
    const p = std.fmt.bufPrintZ(&z, "{s}", .{path}) catch return false;
    return c.access(p.ptr, c.F_OK) == 0;
}

/// Copies to a sibling staging directory and only swaps names after the copy
/// succeeds. If the final rename fails, the previous demo is restored.
fn installTreeAtomically(source: []const u8, target: []const u8) bool {
    var target_z_buf: [2048]u8 = undefined;
    var staging_buf: [2048]u8 = undefined;
    var backup_buf: [2048]u8 = undefined;
    const target_z = std.fmt.bufPrintZ(&target_z_buf, "{s}", .{target}) catch return false;
    const process_id = c.getpid();
    const staging = std.fmt.bufPrintZ(
        &staging_buf,
        "{s}.new.{d}",
        .{ target, process_id },
    ) catch return false;
    const backup = std.fmt.bufPrintZ(
        &backup_buf,
        "{s}.old.{d}",
        .{ target, process_id },
    ) catch return false;

    removeTree(staging);
    removeTree(backup);
    if (!copyTree(source, staging)) {
        removeTree(staging);
        return false;
    }

    const had_previous = fileExists(target);
    if (had_previous and c.rename(target_z.ptr, backup.ptr) != 0) {
        removeTree(staging);
        return false;
    }
    if (c.rename(staging.ptr, target_z.ptr) != 0) {
        if (had_previous) _ = c.rename(backup.ptr, target_z.ptr);
        removeTree(staging);
        return false;
    }
    if (had_previous) removeTree(backup);
    return true;
}
fn copyString(s: []const u8) ?[]const u8 {
    const out = A.alloc(u8, s.len) catch return null;
    @memcpy(out, s);
    return out;
}
fn addDemo(name: []const u8, path: []const u8, official: bool) void {
    if (demo_count >= demos.len or !fileExists(path)) return;
    for (demos[0..demo_count]) |demo| if (std.mem.eql(u8, demo.path, path)) return;
    const n = copyString(name) orelse return;
    const p = copyString(path) orelse {
        A.free(n);
        return;
    };
    demos[demo_count] = .{ .name = n, .path = p, .official = official };
    demo_count += 1;
}
fn clearDemos() void {
    for (demos[0..demo_count]) |demo| {
        A.free(demo.name);
        A.free(demo.path);
    }
    demo_count = 0;
}

fn closeGameLua() void {
    c.lua_close(L);
    std.debug.assert(lua_heap.used_bytes == 0);
}

fn unloadGame(loaded: *bool, active_archive: *?[]u8) void {
    if (loaded.*) {
        audio_state.resetForGame();
        closeGameLua();
        loaded.* = false;
    }
    if (active_archive.*) |root| {
        removeTree(root);
        A.free(root);
        active_archive.* = null;
    }
}
fn scanDemoDirectoryDepth(base: []const u8, depth: usize, official: bool) void {
    var z: [2048]u8 = undefined;
    const dir_path = std.fmt.bufPrintZ(&z, "{s}", .{base}) catch return;
    const dir = c.opendir(dir_path.ptr) orelse return;
    defer _ = c.closedir(dir);
    while (c.readdir(dir)) |entry| {
        const name = std.mem.sliceTo(entry.*.d_name[0..], 0);
        if (name.len == 0 or name[0] == '.') continue;
        var path: [2048]u8 = undefined;
        const full = std.fmt.bufPrint(&path, "{s}/{s}", .{ base, name }) catch continue;
        if (packageEntryKind(full) == .directory) {
            var game_path: [2048]u8 = undefined;
            const game = std.fmt.bufPrint(&game_path, "{s}/game.lua", .{full}) catch continue;
            if (fileExists(game)) addDemo(name, full, official);
            var manifest_path: [2048]u8 = undefined;
            const manifest = std.fmt.bufPrint(&manifest_path, "{s}/lupi_manifest.txt", .{full}) catch continue;
            if (fileExists(manifest)) addDemo(name, full, official);
            if (depth > 0) scanDemoDirectoryDepth(full, depth - 1, official);
        } else if (packageEntryKind(full) == .regular and endsWith(name, ".lupi")) {
            addDemo(name[0 .. name.len - 5], full, official);
        }
    }
}
fn addCatalogDemos() void {
    const catalog = assetAll("demos/catalog.txt") orelse return;
    defer A.free(catalog);
    var cursor: usize = 0;
    while (cursor < catalog.len) {
        const end = std.mem.indexOfScalarPos(u8, catalog, cursor, '\n') orelse catalog.len;
        const line_text = std.mem.trim(u8, catalog[cursor..end], " \t\r");
        cursor = if (end < catalog.len) end + 1 else catalog.len;
        if (line_text.len == 0 or line_text[0] == '#') continue;
        var fields = std.mem.splitScalar(u8, line_text, '|');
        const display_name = fields.next() orelse continue;
        const source = fields.next() orelse continue;
        const slug = if (std.mem.startsWith(u8, source, "builtin:")) blk: {
            const builtin_path = source["builtin:".len..];
            if (archivePathUnsafe(builtin_path)) continue;
            break :blk builtin_path;
        } else githubRepositorySlug(source) orelse continue;
        var path_buffer: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "demos/{s}", .{slug}) catch continue;
        addDemo(display_name, path, true);
    }
}
fn discoverDemos() void {
    clearDemos();
    // Catalog order and names are authoritative; the directory scan that
    // follows discovers future/manual demos not yet present in the catalog.
    addCatalogDemos();
    scanDemoDirectoryDepth("demos", 2, true);
    addDemo("Exemplo", "example", false);
    addDemo("Mazestein 3D", "mazestein3d", false);
    scanDemoDirectoryDepth("games", 1, false);
    scanDemoDirectoryDepth("examples", 1, false);
}

// -----------------------------------------------------------------------------
// Indexed software renderer and browser UI

fn checkInt(L_: *c.lua_State, n: c_int) i32 {
    const value = c.luaL_checknumber(L_, n);
    if (!std.math.isFinite(value) or
        value < @as(f64, @floatFromInt(std.math.minInt(i32))) or
        value > @as(f64, @floatFromInt(std.math.maxInt(i32))))
    {
        _ = c.luaL_error(L_, "number is outside the signed 32-bit renderer range");
        return 0;
    }
    return @intFromFloat(value);
}
fn optionalInt(L_: *c.lua_State, n: c_int, default: i32) i32 {
    const value = c.luaL_optnumber(L_, n, default);
    if (!std.math.isFinite(value) or
        value < @as(f64, @floatFromInt(std.math.minInt(i32))) or
        value > @as(f64, @floatFromInt(std.math.maxInt(i32))))
    {
        _ = c.luaL_error(L_, "number is outside the signed 32-bit renderer range");
        return 0;
    }
    return @intFromFloat(value);
}
fn i(L_: *c.lua_State, n: c_int, default: i32) i32 {
    return optionalInt(L_, n, default);
}
fn color(v: i32) u8 {
    // Upstream stores the C `int` in uint8_t, so out-of-range indices wrap.
    return @truncate(@as(u32, @bitCast(v)));
}
fn resetRasterWork() void {
    raster_work_remaining = raster_work_max;
}

fn takeRasterWork() bool {
    if (raster_work_remaining == 0) return false;
    raster_work_remaining -= 1;
    return true;
}

fn saturatingI32(value: i64) i32 {
    return @intCast(std.math.clamp(
        value,
        @as(i64, std.math.minInt(i32)),
        @as(i64, std.math.maxInt(i32)),
    ));
}

fn xy(x: i32, y: i32) [2]i32 {
    if (!debug_state.render.camera) return .{ x, y };
    return .{
        saturatingI32(@as(i64, x) - cam.x),
        saturatingI32(@as(i64, y) - cam.y),
    };
}
fn solid() bool {
    for (pattern) |v| if (v != 0) return false;
    return true;
}
fn writePixel(x: i32, y: i32, col: i32, pat: bool) void {
    if (x < 0 or y < 0 or x >= W or y >= H) return;
    if (debug_state.render.clipping and clipping) {
        const x_wide: i64 = x;
        const y_wide: i64 = y;
        const clip_x_end = @as(i64, clip.x) + clip.w;
        const clip_y_end = @as(i64, clip.y) + clip.h;
        if (x_wide < clip.x or y_wide < clip.y or
            x_wide >= clip_x_end or y_wide >= clip_y_end) return;
    }
    if (debug_state.render.patterns and pat and !solid() and
        (pattern[@intCast(@mod(y, 8))] & (@as(u8, 1) << @intCast(7 - @mod(x, 8)))) == 0) return;
    fb[@intCast(y)][@intCast(x)] = color(col);
}

fn writePixelWide(x: i64, y: i64, col: i32, pat: bool) void {
    if (x < std.math.minInt(i32) or x > std.math.maxInt(i32) or
        y < std.math.minInt(i32) or y > std.math.maxInt(i32)) return;
    writePixel(@intCast(x), @intCast(y), col, pat);
}

fn px(x: i32, y: i32, col: i32, pat: bool) void {
    if (!takeRasterWork()) return;
    writePixel(x, y, col, pat);
}

fn pxWide(x: i64, y: i64, col: i32, pat: bool) void {
    if (!takeRasterWork()) return;
    writePixelWide(x, y, col, pat);
}
fn line(x0: i32, y0: i32, x1: i32, y1: i32, col: i32) void {
    // Do not pre-clip: upstream runs Bresenham over the original endpoints and
    // lets fb_set clip individual pixels. Pre-clipping changes edge coverage.
    var x = x0;
    var y = y0;
    const delta_x = @as(i64, x1) - x;
    const delta_y = @as(i64, y1) - y;
    const dx: i64 = if (delta_x < 0) -delta_x else delta_x;
    const dy: i64 = if (delta_y < 0) -delta_y else delta_y;
    const sx: i32 = if (x < x1) 1 else -1;
    const sy: i32 = if (y < y1) 1 else -1;
    var e = dx - dy;
    while (raster_work_remaining > 0) {
        px(x, y, col, true);
        if (x == x1 and y == y1) break;
        const q = 2 * e;
        if (q > -dy) {
            e -= dy;
            x += sx;
        }
        if (q < dx) {
            e += dx;
            y += sy;
        }
    }
}
fn rect(x: i32, y: i32, w: i32, h: i32, fill: bool, col: i32) void {
    const p = xy(x, y);
    const x_start: i64 = p[0];
    const y_start: i64 = p[1];
    const x_end = x_start + w;
    const y_end = y_start + h;
    if (fill) {
        if (w <= 0 or h <= 0) return;
        var py = y_start;
        while (py < y_end and raster_work_remaining > 0) : (py += 1) {
            var px_value = x_start;
            while (px_value < x_end and raster_work_remaining > 0) : (px_value += 1) {
                pxWide(px_value, py, col, true);
            }
        }
    } else {
        var px_value = x_start;
        while (px_value < x_end and raster_work_remaining > 0) : (px_value += 1) {
            pxWide(px_value, y_start, col, true);
            pxWide(px_value, y_end - 1, col, true);
        }
        var py = y_start;
        while (py < y_end and raster_work_remaining > 0) : (py += 1) {
            pxWide(x_start, py, col, true);
            pxWide(x_end - 1, py, col, true);
        }
    }
}
fn circle(cx: i32, cy: i32, r: i32, fill: bool, col: i32, border: bool, bcol: i32) void {
    const p = xy(cx, cy);
    const radius: i64 = r;
    if (fill) {
        const radius_squared = radius * radius;
        var y = -radius;
        while (y <= radius and raster_work_remaining > 0) : (y += 1) {
            var x = -radius;
            while (x <= radius and raster_work_remaining > 0) : (x += 1) {
                if (x * x + y * y <= radius_squared) {
                    pxWide(@as(i64, p[0]) + x, @as(i64, p[1]) + y, col, true);
                } else {
                    _ = takeRasterWork();
                }
            }
        }
    }
    if (border and raster_work_remaining > 0) {
        var x: i64 = 0;
        var y = radius;
        var decision = 1 - radius;
        circlePixels(p[0], p[1], x, y, bcol);
        while (x < y and raster_work_remaining > 0) {
            if (decision < 0) {
                decision += 2 * x + 3;
            } else {
                decision += 2 * (x - y) + 5;
                y -= 1;
            }
            x += 1;
            circlePixels(p[0], p[1], x, y, bcol);
        }
    }
}
fn circlePixels(cx: i32, cy: i32, x: i64, y: i64, col: i32) void {
    const center_x: i64 = cx;
    const center_y: i64 = cy;
    pxWide(center_x + x, center_y + y, col, true);
    pxWide(center_x - x, center_y + y, col, true);
    pxWide(center_x + x, center_y - y, col, true);
    pxWide(center_x - x, center_y - y, col, true);
    pxWide(center_x + y, center_y + x, col, true);
    pxWide(center_x - y, center_y + x, col, true);
    pxWide(center_x + y, center_y - x, col, true);
    pxWide(center_x - y, center_y - x, col, true);
}
fn horizontalLine(x1_value: i64, x2_value: i64, y: i64, col: i32) void {
    var x1 = x1_value;
    var x2 = x2_value;
    if (x1 > x2) std.mem.swap(i64, &x1, &x2);
    var x = x1;
    while (x <= x2 and raster_work_remaining > 0) : (x += 1) {
        pxWide(x, y, col, true);
    }
}
fn tri(a: [2]i32, b: [2]i32, d: [2]i32, col: i32) void {
    const pa = xy(a[0], a[1]);
    const pb = xy(b[0], b[1]);
    const pd = xy(d[0], d[1]);
    var x1: i64 = pa[0];
    var y1: i64 = pa[1];
    var x2: i64 = pb[0];
    var y2: i64 = pb[1];
    var x3: i64 = pd[0];
    var y3: i64 = pd[1];

    if (y1 > y2) {
        std.mem.swap(i64, &y1, &y2);
        std.mem.swap(i64, &x1, &x2);
    }
    if (y2 > y3) {
        std.mem.swap(i64, &y2, &y3);
        std.mem.swap(i64, &x2, &x3);
    }
    if (y1 > y2) {
        std.mem.swap(i64, &y1, &y2);
        std.mem.swap(i64, &x1, &x2);
    }
    if (y1 == y3) {
        horizontalLine(@min(x1, @min(x2, x3)), @max(x1, @max(x2, x3)), y1, col);
        return;
    }

    var y = y1;
    while (y <= y3 and raster_work_remaining > 0) : (y += 1) {
        const second_half = y > y2 or y2 == y1;
        const segment_height = if (second_half) y3 - y2 else y2 - y1;
        if (segment_height == 0) continue;
        const alpha: f32 = @as(f32, @floatFromInt(y - y1)) /
            @as(f32, @floatFromInt(y3 - y1));
        const beta: f32 = if (second_half)
            @as(f32, @floatFromInt(y - y2)) / @as(f32, @floatFromInt(y3 - y2))
        else
            @as(f32, @floatFromInt(y - y1)) / @as(f32, @floatFromInt(y2 - y1));
        const xa = x1 + @as(i64, @intFromFloat(@as(f32, @floatFromInt(x3 - x1)) * alpha));
        const xb = if (second_half)
            x2 + @as(i64, @intFromFloat(@as(f32, @floatFromInt(x3 - x2)) * beta))
        else
            x1 + @as(i64, @intFromFloat(@as(f32, @floatFromInt(x2 - x1)) * beta));
        horizontalLine(xa, xb, y, col);
    }
}
fn drawAsciiText(s: []const u8, x0: i32, y: i32, col: i32) void {
    var x: i64 = x0;
    for (s) |ch| {
        if (!takeRasterWork()) break;
        if (ch < 32 or ch > 126) continue;
        const glyph = font.data[ch - 32];
        const screen_x = if (debug_state.render.camera) x - cam.x else x;
        const screen_y = if (debug_state.render.camera)
            @as(i64, y) - cam.y
        else
            @as(i64, y);
        for (glyph, 0..) |column, column_index| {
            for (0..font.height) |row| {
                if ((column & (@as(u8, 1) << @as(u3, @intCast(row)))) != 0) {
                    pxWide(
                        screen_x + @as(i64, @intCast(column_index)),
                        screen_y + @as(i64, @intCast(row)),
                        col,
                        false,
                    );
                }
            }
        }
        x += font.advance;
    }
}

/// The simulator chrome is localized and therefore transliterates common
/// Latin-1 UTF-8 characters before using the canonical ASCII game font.
/// `ui.print` calls `drawAsciiText` directly and keeps strict upstream rules.
fn text(s: []const u8, x0: i32, y: i32, col: i32) void {
    var ascii: [1024]u8 = undefined;
    var output: usize = 0;
    var input: usize = 0;
    while (input < s.len and output < ascii.len) {
        var ch = s[input];
        input += 1;
        if (ch == 0xc3 and input < s.len) {
            const suffix = s[input];
            input += 1;
            ch = switch (suffix) {
                0x80...0x85 => 'A',
                0xa0...0xa5 => 'a',
                0x87 => 'C',
                0xa7 => 'c',
                0x88...0x8b => 'E',
                0xa8...0xab => 'e',
                0x8c...0x8f => 'I',
                0xac...0xaf => 'i',
                0x91 => 'N',
                0xb1 => 'n',
                0x92...0x96 => 'O',
                0xb2...0xb6 => 'o',
                0x99...0x9c => 'U',
                0xb9...0xbc => 'u',
                else => '?',
            };
        }
        ascii[output] = ch;
        output += 1;
    }
    drawAsciiText(ascii[0..output], x0, y, col);
}
const chrome_palette = [5]Color{
    .{ .r = 13, .g = 16, .b = 24, .a = 255 },
    .{ .r = 30, .g = 38, .b = 56, .a = 255 },
    .{ .r = 72, .g = 211, .b = 151, .a = 255 },
    .{ .r = 255, .g = 220, .b = 120, .a = 255 },
    .{ .r = 196, .g = 207, .b = 225, .a = 255 },
};

fn browserPalette() void {
    for (chrome_palette, 0..) |entry, index| pal[index] = entry;
}

/// The pause/quit menu is composited after the game has been converted to
/// RGBA. Index zero must therefore remain transparent, while the browser's
/// five opaque colors move up by one slot.
fn overlayPalette() void {
    pal[0] = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    for (chrome_palette, 0..) |entry, index| pal[index + 1] = entry;
}

fn localizedBrowserNotice(strings: localization.Text) []const u8 {
    return switch (browser_notice) {
        .none => "",
        .searching => strings.searching,
        .update_failed => strings.update_failed,
        .network_failed => strings.network_failed,
        .catalog_missing => strings.catalog_missing,
        .codec_download_failed => strings.codec_download_failed,
        .codec_extract_failed => strings.codec_extract_failed,
        .codec_invalid => strings.codec_invalid,
        .demo_prepare_failed => strings.demo_prepare_failed,
        .codec_host_failed => strings.codec_host_failed,
        .codec_run_failed => strings.codec_run_failed,
        .codec_output_missing => strings.codec_output_missing,
        .demo_source_invalid => strings.demo_source_invalid,
        .demo_install_failed => strings.demo_install_failed,
        .audio_copy_failed => strings.audio_copy_failed,
        .demos_updated => strings.demos_updated,
        .no_updates => strings.no_updates,
    };
}

const BrowserNoticePhase = enum { none, loading, finished, failed };

fn browserNoticePhase() BrowserNoticePhase {
    return switch (browser_notice) {
        .none => .none,
        .searching => .loading,
        .demos_updated, .no_updates => .finished,
        else => .failed,
    };
}

fn browserNoticePhaseText(strings: localization.Text, phase: BrowserNoticePhase) []const u8 {
    return switch (phase) {
        .none => "",
        .loading => strings.status_loading,
        .finished => strings.status_finished,
        .failed => strings.status_failed,
    };
}

fn drawBrowserStatus(strings: localization.Text) void {
    const phase = browserNoticePhase();
    if (phase == .none) {
        text(strings.detected_startup, 32, 238, 4);
        text(strings.update_demos, 32, 250, 4);
        return;
    }

    const notice = localizedBrowserNotice(strings);
    const accent: i32 = if (phase == .finished) 2 else 3;
    rect(26, 232, 428, 21, true, 0);
    rect(27, 233, 426, 19, false, accent);
    text(browserNoticePhaseText(strings, phase), 34, 239, accent);
    text(notice, 112, 239, 4);
    if (phase == .failed and browser_notice != .demo_prepare_failed and update_log_available)
        text("elis-update.log", 32, 257, 4);
}

fn drawMenuRow(label: []const u8, index: usize, selected: usize, y: i32, accent: bool) void {
    if (index == selected) rect(28, y - 3, 410, 15, true, 2);
    const menu_color: i32 = if (index == selected) 0 else if (accent) 3 else 4;
    text(if (index == selected) ">" else " ", 34, y, menu_color);
    text(label, 48, y, menu_color);
}

fn drawBrowser(selected: usize) void {
    resetRasterWork();
    const strings = localization.get(settings_state.language);
    browserPalette();
    for (&fb) |*row| @memset(row, 0);
    rect(18, 14, 444, 242, true, 1);
    text(strings.demos_title, 32, 28, 3);
    text(strings.navigate_hint, 32, 42, 4);
    if (demo_count == 0) {
        text(strings.no_demos, 32, 72, 3);
        text(strings.add_games, 32, 88, 4);
    }
    const visible = @min(demo_count, 5);
    var first: usize = 0;
    if (selected < demo_count and selected >= visible) first = selected + 1 - visible;
    var previous_official: ?bool = null;
    var row: usize = 0;
    for (0..visible) |offset| {
        const index = first + offset;
        if (index >= demo_count) break;
        if (previous_official == null or previous_official.? != demos[index].official) {
            const heading = if (demos[index].official) strings.official_demos else strings.elis_demos;
            const heading_y: i32 = 62 + @as(i32, @intCast(row * 16));
            text(heading, 32, heading_y, 3);
            row += 1;
            previous_official = demos[index].official;
        }
        const y: i32 = 62 + @as(i32, @intCast(row * 16));
        if (index == selected) rect(28, y - 3, 410, 15, true, 2);
        text(if (index == selected) ">" else " ", 34, y, if (index == selected) 0 else 4);
        text(demos[index].name, 48, y, if (index == selected) 0 else 4);
        row += 1;
    }
    drawMenuRow(strings.language, demo_count, selected, 178, false);
    drawMenuRow(strings.controls, demo_count + 1, selected, 198, false);
    drawMenuRow(strings.quit, demo_count + 2, selected, 218, true);
    drawBrowserStatus(strings);
    if (update_dialog) {
        rect(42, 76, 396, 106, true, 0);
        rect(44, 78, 392, 102, false, 3);
        text(strings.update_question, 68, 94, 3);
        text(strings.existing_versions, 72, 112, 4);
        text(strings.replace_only_yes, 56, 126, 4);
        text(strings.yes_no_hint, 116, 150, 3);
    }
}
fn drawQuitDialog(palette_offset: i32) void {
    const strings = localization.get(settings_state.language);
    rect(42, 70, 396, 124, true, palette_offset);
    rect(44, 72, 392, 120, false, 3 + palette_offset);
    text(strings.menu, 196, 86, 3 + palette_offset);
    text(strings.return_demos, 112, 112, if (quit_selection == 0) 3 + palette_offset else 4 + palette_offset);
    text(strings.quit, 106, 132, if (quit_selection == 1) 3 + palette_offset else 4 + palette_offset);
    text(strings.navigate_hint, 92, 162, 4 + palette_offset);
    text(strings.escape_back, 176, 178, 4 + palette_offset);
}

fn drawLanguageScreen() void {
    resetRasterWork();
    const strings = localization.get(settings_state.language);
    browserPalette();
    for (&fb) |*row| @memset(row, 0);
    rect(18, 14, 444, 242, true, 1);
    text(strings.choose_language, 32, 28, 3);
    for (localization.all_languages, 0..) |language, index| {
        drawMenuRow(localization.languageName(language), index, language_selection, 78 + @as(i32, @intCast(index * 28)), false);
    }
    text(strings.language_hint, 32, 236, 4);
    if (language_save_failed) text(strings.save_failed, 320, 218, 3);
}

fn bindingPageName(strings: localization.Text) []const u8 {
    return switch (controls_binding_page) {
        0 => strings.keyboard_1,
        1 => strings.keyboard_2,
        2 => strings.keyboard_3,
        else => strings.gamepad,
    };
}

fn bindingName(action: input_mod.Action, strings: localization.Text) []const u8 {
    const value = if (controls_binding_page < input_mod.keyboard_slot_count)
        input_state.bindings.keyboard[@intFromEnum(action)][controls_binding_page]
    else
        input_state.bindings.gamepad[@intFromEnum(action)];
    if (value == input_mod.unbound) return strings.unbound;
    const raw = if (controls_binding_page < input_mod.keyboard_slot_count)
        c.SDL_GetScancodeName(@intCast(value))
    else
        c.SDL_GameControllerGetStringForButton(@intCast(value));
    if (raw == null) return "?";
    const name = std.mem.span(raw);
    return if (name.len > 0) name else "?";
}

fn drawControlsScreen() void {
    resetRasterWork();
    const strings = localization.get(settings_state.language);
    browserPalette();
    for (&fb) |*row| @memset(row, 0);
    rect(18, 14, 444, 242, true, 1);
    text(strings.controls_title, 32, 26, 3);
    text("<", 224, 46, 3);
    text(bindingPageName(strings), 242, 46, 3);
    text(">", 410, 46, 3);

    const visible: usize = 8;
    const first = if (controls_selection >= visible) controls_selection + 1 - visible else 0;
    for (0..visible) |offset| {
        const action_index = first + offset;
        if (action_index >= input_mod.action_count) break;
        const action: input_mod.Action = @enumFromInt(action_index);
        const y = 70 + @as(i32, @intCast(offset * 18));
        if (action_index == controls_selection) rect(28, y - 3, 410, 15, true, 2);
        const row_color: i32 = if (action_index == controls_selection) 0 else 4;
        text(if (action_index == controls_selection) ">" else " ", 34, y, row_color);
        text(localization.actionName(settings_state.language, action), 48, y, row_color);
        text(bindingName(action, strings), 274, y, row_color);
    }

    if (controls_capture) {
        rect(70, 102, 340, 62, true, 0);
        rect(72, 104, 336, 58, false, 3);
        text(if (controls_binding_page < input_mod.keyboard_slot_count) strings.waiting_key else strings.waiting_button, 128, 122, 3);
        text(strings.escape_back, 176, 144, 4);
    } else {
        text(strings.controls_hint, 32, 224, 4);
        text(strings.controls_edit_hint, 32, 238, 4);
        switch (controls_notice) {
            .none => {},
            .saved => text(strings.saved, 290, 224, 2),
            .save_failed => text(strings.save_failed, 290, 224, 3),
            .defaults_restored => text(strings.defaults_restored, 276, 224, 2),
            .conflict => {
                text(strings.conflict, 280, 224, 3);
                text(localization.actionName(settings_state.language, controls_conflict_action), 280, 238, 3);
            },
        }
    }
}
fn menuPressed(button: c_int) bool {
    return input_state.anyButtonPressed(button);
}
fn menuKeyPressed(scancode: c_int) bool {
    return input_state.anyKeyPressed(scancode);
}

fn persistBindings(success_notice: ControlsNotice) void {
    settings_state.bindings = input_state.bindings;
    controls_notice = if (settings_state.save()) success_notice else .save_failed;
}

fn finishControlCapture(value: c_int) void {
    const action: input_mod.Action = @enumFromInt(controls_selection);
    const conflict = if (controls_binding_page < input_mod.keyboard_slot_count)
        input_state.keyboardConflict(value, action, controls_binding_page)
    else
        input_state.gamepadConflict(value, action);
    if (conflict) |other| {
        controls_conflict_action = other;
        controls_notice = .conflict;
    } else {
        const accepted = if (controls_binding_page < input_mod.keyboard_slot_count)
            input_state.bindKeyboard(action, controls_binding_page, value)
        else
            input_state.bindGamepad(action, value);
        if (accepted) persistBindings(.saved) else controls_notice = .save_failed;
    }
    controls_capture = false;
    controls_capture_armed = false;
}

// -----------------------------------------------------------------------------
// Assets and archive loading

fn asset(path: []const u8, off: usize, n: usize) ?[]u8 {
    var path_z_buf: [2048]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_z_buf, "{s}", .{path}) catch return null;
    const f = c.fopen(path_z.ptr, "rb") orelse return null;
    defer _ = c.fclose(f);
    if (c.fseek(f, @intCast(off), c.SEEK_SET) != 0) return null;
    const b = A.alloc(u8, n) catch return null;
    const got = c.fread(b.ptr, 1, n, f);
    if (got != n) {
        A.free(b);
        return null;
    }
    return b;
}

fn fileSizeLimited(path: []const u8, bytes_max: usize) ?usize {
    var path_z_buffer: [2048]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_z_buffer, "{s}", .{path}) catch return null;
    const file = c.fopen(path_z.ptr, "rb") orelse return null;
    defer _ = c.fclose(file);
    if (c.fseek(file, 0, c.SEEK_END) != 0) return null;
    const end = c.ftell(file);
    if (end < 0 or @as(u64, @intCast(end)) > bytes_max) return null;
    return @intCast(end);
}

fn fileSize(path: []const u8) ?usize {
    return fileSizeLimited(path, lupi_flash_bytes);
}

fn assetAll(path: []const u8) ?[]u8 {
    var path_z_buf: [2048]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_z_buf, "{s}", .{path}) catch return null;
    const f = c.fopen(path_z.ptr, "rb") orelse return null;
    defer _ = c.fclose(f);
    if (c.fseek(f, 0, c.SEEK_END) != 0) return null;
    const end = c.ftell(f);
    if (end <= 0 or @as(u64, @intCast(end)) > lupi_flash_bytes) return null;
    if (c.fseek(f, 0, c.SEEK_SET) != 0) return null;
    const b = A.alloc(u8, @intCast(end)) catch return null;
    const got = c.fread(b.ptr, 1, b.len, f);
    if (got != b.len) {
        A.free(b);
        return null;
    }
    return b;
}
fn gameFitsFlash(root: []const u8) bool {
    var path_buffer: [2048]u8 = undefined;
    const manifest_path = std.fmt.bufPrint(
        &path_buffer,
        "{s}/lupi_manifest.txt",
        .{root},
    ) catch return false;
    const manifest = assetAll(manifest_path) orelse return !fileExists(manifest_path);
    defer A.free(manifest);
    var declared_bytes = manifest.len;
    if (declared_bytes > lupi_flash_bytes) return false;
    var entry_count: usize = 0;
    var declared_paths = std.StringHashMapUnmanaged(void){};
    defer declared_paths.deinit(A);
    var lines = std.mem.splitScalar(u8, manifest, '\n');
    while (lines.next()) |raw_line| {
        const manifest_line = std.mem.trim(u8, raw_line, " \t\r");
        if (manifest_line.len == 0) continue;
        var tokens = std.mem.tokenizeScalar(u8, manifest_line, ' ');
        const identifier_text = tokens.next() orelse return false;
        _ = std.fmt.parseUnsigned(usize, identifier_text, 10) catch return false;
        const size_text = tokens.next() orelse return false;
        const size = std.fmt.parseUnsigned(usize, size_text, 10) catch return false;
        const relative = tokens.next() orelse return false;
        if (archivePathUnsafe(relative)) return false;
        const path_result = declared_paths.getOrPut(A, relative) catch return false;
        if (path_result.found_existing) return false;
        const metadata = std.mem.trim(u8, tokens.rest(), " \t\r");
        if (metadata.len < 2 or metadata[0] != '{' or metadata[metadata.len - 1] != '}') {
            return false;
        }
        const metadata_valid = std.json.validate(A, metadata) catch return false;
        if (!metadata_valid) return false;
        if (entry_count == lupi_archive_entries_max) return false;
        entry_count += 1;
        if (size > lupi_flash_bytes - declared_bytes) return false;
        declared_bytes += size;
        const payload_path = std.fmt.bufPrint(
            &path_buffer,
            "{s}/{s}",
            .{ root, relative },
        ) catch return false;
        if (fileSize(payload_path) != size) return false;
    }
    if (entry_count == 0) return false;
    var scan = PackageScan{};
    return scanPackageTree(root, "", &declared_paths, &scan, 0) and
        scan.bytes <= lupi_flash_bytes;
}

const PackageScan = struct {
    bytes: usize = 0,
    entries: usize = 0,
};

const PackageEntryKind = native.EntryKind;

fn packageEntryKind(path: []const u8) PackageEntryKind {
    var path_buffer: [2048]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_buffer, "{s}", .{path}) catch return .invalid;
    return native.entryKind(path_z.ptr);
}

fn scanPackageTree(
    root: []const u8,
    relative_root: []const u8,
    declared_paths: *const std.StringHashMapUnmanaged(void),
    scan: *PackageScan,
    depth: usize,
) bool {
    if (depth > 32) return false;
    var directory_buffer: [2048]u8 = undefined;
    const directory_path = if (relative_root.len == 0)
        std.fmt.bufPrintZ(&directory_buffer, "{s}", .{root}) catch return false
    else
        std.fmt.bufPrintZ(
            &directory_buffer,
            "{s}/{s}",
            .{ root, relative_root },
        ) catch return false;
    const directory = c.opendir(directory_path.ptr) orelse return false;
    defer _ = c.closedir(directory);
    while (c.readdir(directory)) |entry| {
        const name = std.mem.sliceTo(entry.*.d_name[0..], 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        if (name.len == 0 or scan.entries == lupi_archive_entries_max) return false;
        scan.entries += 1;
        var relative_buffer: [2048]u8 = undefined;
        const relative = if (relative_root.len == 0)
            std.fmt.bufPrint(&relative_buffer, "{s}", .{name}) catch return false
        else
            std.fmt.bufPrint(
                &relative_buffer,
                "{s}/{s}",
                .{ relative_root, name },
            ) catch return false;
        var full_buffer: [2048]u8 = undefined;
        const full = std.fmt.bufPrint(
            &full_buffer,
            "{s}/{s}",
            .{ root, relative },
        ) catch return false;
        switch (packageEntryKind(full)) {
            .directory => if (!scanPackageTree(root, relative, declared_paths, scan, depth + 1)) {
                return false;
            },
            .regular => {
                if (!std.mem.eql(u8, relative, "lupi_manifest.txt") and
                    !declared_paths.contains(relative) and !isRuntimeMedia(relative))
                {
                    return false;
                }
                const size = fileSize(full) orelse return false;
                if (size > lupi_flash_bytes - scan.bytes) return false;
                scan.bytes += size;
            },
            .invalid => return false,
        }
    }
    return true;
}

fn endsWith(path: []const u8, suffix: []const u8) bool {
    return path.len >= suffix.len and std.mem.eql(u8, path[path.len - suffix.len ..], suffix);
}
fn makeParentDirs(path: []const u8) void {
    var buf: [2048]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    // Start after the leading slash so absolute temporary paths keep their
    // root component. Only separators are replaced temporarily.
    for (buf[1..path.len], 1..) |byte, index| {
        if (byte != '/' and !(native.windows and byte == '\\')) continue;
        if (native.windows and index == 2 and buf[1] == ':') continue;
        buf[index] = 0;
        _ = native.mkdir(buf[0..index :0].ptr, 0o755);
        buf[index] = byte;
    }
}
fn removeTree(path: []const u8) void {
    var path_z_buf: [2048]u8 = undefined;
    const path_z = std.fmt.bufPrintZ(&path_z_buf, "{s}", .{path}) catch return;
    if (packageEntryKind(path) != .directory) {
        _ = native.remove(path_z.ptr);
        return;
    }
    const dir = c.opendir(path_z.ptr) orelse return;
    while (c.readdir(dir)) |entry| {
        const name = std.mem.sliceTo(entry.*.d_name[0..], 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        var child: [2048]u8 = undefined;
        const child_path = std.fmt.bufPrintZ(&child, "{s}/{s}", .{ path, name }) catch continue;
        if (packageEntryKind(child_path) == .directory) {
            removeTree(child_path);
        } else _ = native.remove(child_path.ptr);
    }
    _ = c.closedir(dir);
    _ = c.rmdir(path_z.ptr);
}
/// Extracts an archive into a unique temporary directory. The caller owns the
/// returned path and must remove the directory and free the slice.
fn extractArchive(path: []const u8, bytes_max: usize) ?[]u8 {
    if (fileSizeLimited(path, bytes_max) == null) return null;
    var template: [2048]u8 = undefined;
    const root_path = native.temporaryDirectory(&template, "elis-archive") orelse return null;
    const root = root_path.ptr;
    var keep_root = false;
    defer if (!keep_root) removeTree(std.mem.span(root));
    const archive_z = std.fmt.allocPrintSentinel(A, "{s}", .{path}, 0) catch return null;
    defer A.free(archive_z);
    var err: c_int = 0;
    const za = c.zip_open(archive_z.ptr, 0, &err) orelse return null;
    defer _ = c.zip_close(za);
    const count = c.zip_get_num_entries(za, 0);
    if (count < 0 or count > lupi_archive_entries_max) return null;
    var extracted_paths = std.StringHashMapUnmanaged(void){};
    defer extracted_paths.deinit(A);
    var extracted_bytes: u64 = 0;
    var index: usize = 0;
    while (index < count) : (index += 1) {
        var entry: c.zip_stat_t = undefined;
        if (c.zip_stat_index(za, index, 0, &entry) != 0) return null;
        if (entry.size > bytes_max - extracted_bytes) return null;
        extracted_bytes += entry.size;
        const name_ptr = c.zip_get_name(za, index, 0) orelse return null;
        const name = std.mem.span(name_ptr);
        // Reject traversal components rather than harmless names containing
        // two dots (for example "version..old").
        if (archivePathUnsafe(name)) return null;
        const canonical_name = if (name[name.len - 1] == '/') name[0 .. name.len - 1] else name;
        const path_result = extracted_paths.getOrPut(A, canonical_name) catch return null;
        if (path_result.found_existing) return null;
        var out: [2048]u8 = undefined;
        const out_path = std.fmt.bufPrintZ(
            &out,
            "{s}/{s}",
            .{ std.mem.span(root), name },
        ) catch return null;
        if (name[name.len - 1] == '/') {
            makeParentDirs(out_path);
            if (native.mkdir(out_path.ptr, 0o755) != 0 and packageEntryKind(out_path) != .directory) return null;
            continue;
        }
        makeParentDirs(out_path);
        const zf = c.zip_fopen_index(za, index, 0) orelse return null;
        // Exclusive creation also rejects Win32 case/short-name aliases.
        const file = c.fopen(out_path.ptr, "wbx") orelse {
            _ = c.zip_fclose(zf);
            return null;
        };
        var valid = true;
        var written_bytes: u64 = 0;
        var buf: [8192]u8 = undefined;
        while (true) {
            const got = c.zip_fread(zf, &buf, buf.len);
            if (got == 0) break;
            if (got < 0) {
                valid = false;
                break;
            }
            const got_bytes: usize = @intCast(got);
            const got_bytes_u64: u64 = @intCast(got_bytes);
            if (got_bytes_u64 > entry.size - written_bytes or
                c.fwrite(&buf, 1, got_bytes, file) != got_bytes)
            {
                valid = false;
                break;
            }
            written_bytes += got_bytes_u64;
        }
        if (written_bytes != entry.size) valid = false;
        if (c.fclose(file) != 0) valid = false;
        if (c.zip_fclose(zf) != 0) valid = false;
        if (!valid) return null;
    }
    const root_slice = std.mem.span(root);
    const owned_root = A.dupe(u8, root_slice) catch return null;
    keep_root = true;
    return owned_root;
}

fn archivePathUnsafe(path: []const u8) bool {
    if (path.len == 0 or path[0] == '/' or
        std.mem.indexOfScalar(u8, path, '\\') != null)
    {
        return true;
    }
    const relative = if (path[path.len - 1] == '/') path[0 .. path.len - 1] else path;
    if (relative.len == 0) return true;
    var component_count: usize = 0;
    var components = std.mem.splitScalar(u8, relative, '/');
    while (components.next()) |component| {
        if (!@import("studio/package_path.zig").safeComponent(component) or component_count == 32) {
            return true;
        }
        component_count += 1;
    }
    return component_count == 0;
}
const BitmapRange = struct {
    offset: usize,
    length: usize,
};

fn bitmapRange(w: i32, h: i32, tile_id: i32, bytes_max: usize) ?BitmapRange {
    if (w <= 0 or h <= 0 or tile_id < 0) return null;
    const tile_pixels = std.math.mul(u64, @intCast(w), @intCast(h)) catch return null;
    const offset = std.math.mul(u64, tile_pixels, @intCast(tile_id)) catch return null;
    if (tile_pixels > bytes_max or offset > bytes_max - @as(usize, @intCast(tile_pixels))) {
        return null;
    }
    return .{ .offset = @intCast(offset), .length = @intCast(tile_pixels) };
}

fn bitmapData(
    bytes: []const u8,
    w: i32,
    h: i32,
    tile_id: i32,
    x: i64,
    y: i64,
    flip_x: bool,
    flip_y: bool,
) void {
    const range = bitmapRange(w, h, tile_id, bytes.len) orelse return;
    const screen_x = if (debug_state.render.camera) x - cam.x else x;
    const screen_y = if (debug_state.render.camera) y - cam.y else y;
    var yy: i32 = 0;
    while (yy < h and raster_work_remaining > 0) : (yy += 1) {
        var xx: i32 = 0;
        while (xx < w and raster_work_remaining > 0) : (xx += 1) {
            if (!takeRasterWork()) return;
            const src_y = if (flip_y) h - 1 - yy else yy;
            const source_index = @as(i64, src_y) * w + xx;
            const value = bytes[range.offset + @as(usize, @intCast(source_index))];
            if (value != 0) {
                const destination_x = if (flip_x) w - 1 - xx else xx;
                writePixelWide(
                    screen_x + destination_x,
                    screen_y + yy,
                    value,
                    false,
                );
            }
        }
    }
}
fn bitmap(path: []const u8, w: i32, h: i32, tile_id: i32, x: i32, y: i32, flip_x: bool, flip_y: bool) void {
    const range = bitmapRange(w, h, tile_id, lupi_tileset_pixels_max) orelse return;
    const bytes = asset(path, range.offset, range.length) orelse return;
    defer A.free(bytes);
    // `asset` already returned exactly the requested tile. Applying tile_id
    // again here made every ui.tile call except tile 0 address past the slice.
    bitmapData(bytes, w, h, 0, x, y, flip_x, flip_y);
}
fn ts(L_: *c.lua_State, idx: c_int, name: [:0]const u8) ?[]const u8 {
    _ = c.lua_getfield(L_, idx, name);
    defer _ = c.lua_pop(L_, 1);
    var len: usize = 0;
    const s = c.lua_tolstring(L_, -1, &len);
    if (s == null) return null;
    return s[0..len];
}
fn ti(L_: *c.lua_State, idx: c_int, name: [:0]const u8, d: i32) i32 {
    _ = c.lua_getfield(L_, idx, name);
    defer _ = c.lua_pop(L_, 1);
    return i(L_, -1, d);
}
fn checkedTableInt(L_: *c.lua_State, idx: c_int, name: [:0]const u8) i32 {
    _ = c.lua_getfield(L_, idx, name);
    defer _ = c.lua_pop(L_, 1);
    return checkInt(L_, -1);
}
fn logTopLuaError(L_: *c.lua_State, context: []const u8) void {
    var length: usize = 0;
    const message = c.lua_tolstring(L_, -1, &length);
    if (message != null) std.debug.print("{s}: {s}\n", .{ context, message[0..length] });
}
fn cls(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.clears += 1;
    for (&fb) |*row| @memset(row, color(checkInt(L_, 1)));
    clipping = false;
    return 0;
}
fn setPaletteEntry(index: i32, packed_value: i32) void {
    if (index < 0 or index >= pal.len) return;
    const value: u32 = @bitCast(packed_value);
    const blue: u8 = @truncate(value);
    const green: u8 = @truncate(value >> 5);
    const red: u8 = @truncate(value >> 10);
    pal[@intCast(index)] = .{
        .r = ((red & 31) << 3) | ((red & 31) >> 2),
        .g = ((green & 31) << 3) | ((green & 31) >> 2),
        .b = ((blue & 31) << 3) | ((blue & 31) >> 2),
        .a = 255,
    };
}
fn palset(L_: *c.lua_State) callconv(.c) c_int {
    setPaletteEntry(checkInt(L_, 1), checkInt(L_, 2));
    return 0;
}
fn setPallet(L_: *c.lua_State) callconv(.c) c_int {
    const start = checkInt(L_, 1);
    const count = std.math.clamp(checkInt(L_, 2), 0, @as(i32, pal.len));
    c.luaL_checktype(L_, 3, c.LUA_TTABLE);
    for (0..@intCast(count)) |offset| {
        _ = c.lua_rawgeti(L_, 3, @intCast(offset + 1));
        const value = checkInt(L_, -1);
        _ = c.lua_pop(L_, 1);
        const index = @as(i64, start) + @as(i64, @intCast(offset));
        if (index >= 0 and index < pal.len) setPaletteEntry(@intCast(index), value);
    }
    return 0;
}
fn preloadSpritesheet(L_: *c.lua_State) callconv(.c) c_int {
    if (legacy_sprite_ref != c.LUA_NOREF) {
        c.luaL_unref(L_, c.LUA_REGISTRYINDEX, legacy_sprite_ref);
        legacy_sprite_ref = c.LUA_NOREF;
    }
    if (c.lua_istable(L_, 1)) {
        c.lua_pushvalue(L_, 1);
    } else if (c.lua_type(L_, 1) == c.LUA_TSTRING) {
        if (c.lua_getglobal(L_, "__lupi_find") != c.LUA_TFUNCTION) {
            _ = c.lua_pop(L_, 1);
            c.lua_pushboolean(L_, 0);
            return 1;
        }
        _ = c.lua_getglobal(L_, "Sprites");
        c.lua_pushvalue(L_, 1);
        if (c.lua_pcallk(L_, 2, 1, 0, 0, null) != c.LUA_OK) {
            logTopLuaError(L_, "preload_spritesheet");
            _ = c.lua_pop(L_, 1);
            c.lua_pushboolean(L_, 0);
            return 1;
        }
        if (!c.lua_istable(L_, -1)) {
            _ = c.lua_pop(L_, 1);
            c.lua_pushboolean(L_, 0);
            return 1;
        }
    } else {
        // Preserve the current upstream numeric/no-op contract while retaining
        // the functional table/string extension used by modern demos.
        _ = checkInt(L_, 1);
        return 0;
    }
    legacy_sprite_ref = c.luaL_ref(L_, c.LUA_REGISTRYINDEX);
    c.lua_pushboolean(L_, 1);
    return 1;
}
fn drawSprite(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.sprites += 1;
    const x = checkInt(L_, 1);
    const y = checkInt(L_, 2);
    const sprite_index = checkInt(L_, 3);
    const requested_size = checkInt(L_, 4);
    if (!debug_state.render.sprites or legacy_sprite_ref == c.LUA_NOREF) return 0;
    _ = c.lua_rawgeti(L_, c.LUA_REGISTRYINDEX, legacy_sprite_ref);
    defer _ = c.lua_pop(L_, 1);
    const path = ts(L_, -1, "path") orelse return 0;
    const width = ti(L_, -1, "width", requested_size);
    const height = ti(L_, -1, "height", requested_size);
    bitmap(path, width, height, sprite_index, x, y, false, false);
    return 0;
}
fn ln(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.primitives += 1;
    const a = xy(checkInt(L_, 1), checkInt(L_, 2));
    const b = xy(checkInt(L_, 3), checkInt(L_, 4));
    const line_color = checkInt(L_, 5);
    if (debug_state.render.primitives) line(a[0], a[1], b[0], b[1], line_color);
    return 0;
}
fn dr(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.primitives += 1;
    const x = checkInt(L_, 1);
    const y = checkInt(L_, 2);
    const width = checkInt(L_, 3);
    const height = checkInt(L_, 4);
    const fill = c.lua_toboolean(L_, 5) != 0;
    const rect_color = checkInt(L_, 6);
    if (debug_state.render.primitives) rect(x, y, width, height, fill, rect_color);
    return 0;
}
fn oldr(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.primitives += 1;
    const x = checkInt(L_, 1);
    const y = checkInt(L_, 2);
    const x_end = checkInt(L_, 3);
    const y_end = checkInt(L_, 4);
    const rect_color = checkInt(L_, 5);
    if (debug_state.render.primitives) {
        rect(
            x,
            y,
            saturatingI32(@as(i64, x_end) - x),
            saturatingI32(@as(i64, y_end) - y),
            false,
            rect_color,
        );
    }
    return 0;
}
fn oldrf(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.primitives += 1;
    const x = checkInt(L_, 1);
    const y = checkInt(L_, 2);
    const x_end = checkInt(L_, 3);
    const y_end = checkInt(L_, 4);
    const rect_color = checkInt(L_, 5);
    if (debug_state.render.primitives) {
        rect(
            x,
            y,
            saturatingI32(@as(i64, x_end) - x),
            saturatingI32(@as(i64, y_end) - y),
            true,
            rect_color,
        );
    }
    return 0;
}
fn ci(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.primitives += 1;
    const x = checkInt(L_, 1);
    const y = checkInt(L_, 2);
    const radius = checkInt(L_, 3);
    const circle_color = checkInt(L_, 4);
    if (debug_state.render.primitives)
        circle(x, y, radius, true, circle_color, true, circle_color);
    return 0;
}
fn co(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.primitives += 1;
    const x = checkInt(L_, 1);
    const y = checkInt(L_, 2);
    const radius = checkInt(L_, 3);
    const circle_color = checkInt(L_, 4);
    if (debug_state.render.primitives)
        circle(x, y, radius, false, 0, true, circle_color);
    return 0;
}
fn dc(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.primitives += 1;
    const x = checkInt(L_, 1);
    const y = checkInt(L_, 2);
    const radius = checkInt(L_, 3);
    const fill = c.lua_toboolean(L_, 4) != 0;
    const fill_color = checkInt(L_, 5);
    const border = c.lua_toboolean(L_, 6) != 0;
    const border_color = checkInt(L_, 7);
    if (debug_state.render.primitives)
        circle(x, y, radius, fill, fill_color, border, border_color);
    return 0;
}
fn tr(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.primitives += 1;
    const a = [2]i32{ checkInt(L_, 1), checkInt(L_, 2) };
    const b = [2]i32{ checkInt(L_, 3), checkInt(L_, 4) };
    const d = [2]i32{ checkInt(L_, 5), checkInt(L_, 6) };
    const triangle_color = checkInt(L_, 7);
    if (debug_state.render.primitives) tri(a, b, d, triangle_color);
    return 0;
}
fn pr(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.text += 1;
    var length: usize = 0;
    const s = c.luaL_checklstring(L_, 1, &length);
    const x = checkInt(L_, 2);
    const y = checkInt(L_, 3);
    const text_color = checkInt(L_, 4);
    if (debug_state.render.text)
        drawAsciiText(std.mem.sliceTo(s[0..length], 0), x, y, text_color);
    return 0;
}
fn camf(L_: *c.lua_State) callconv(.c) c_int {
    if (c.lua_gettop(L_) == 0) cam = Region{} else cam = .{ .x = checkInt(L_, 1), .y = checkInt(L_, 2) };
    return 0;
}
fn clipf(L_: *c.lua_State) callconv(.c) c_int {
    if (c.lua_gettop(L_) == 0) clipping = false else {
        clipping = true;
        clip = .{ .x = checkInt(L_, 1), .y = checkInt(L_, 2), .w = checkInt(L_, 3), .h = checkInt(L_, 4) };
    }
    return 0;
}
fn fillp(L_: *c.lua_State) callconv(.c) c_int {
    @memset(&pattern, 0);
    const n = @min(c.lua_gettop(L_), 8);
    for (0..@intCast(n)) |k| pattern[k] = color(checkInt(L_, @intCast(k + 1)));
    return 0;
}
fn spr(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.sprites += 1;
    c.luaL_checktype(L_, 1, c.LUA_TTABLE);
    const p = ts(L_, 1, "path") orelse
        return c.luaL_error(L_, "field 'path' must be a string");
    const width = checkedTableInt(L_, 1, "width");
    const height = checkedTableInt(L_, 1, "height");
    const x = checkInt(L_, 2);
    const y = checkInt(L_, 3);
    const flip_x = c.lua_toboolean(L_, 4) != 0;
    const flip_y = c.lua_toboolean(L_, 5) != 0;
    if (debug_state.render.sprites) bitmap(p, width, height, 0, x, y, flip_x, flip_y);
    return 0;
}
fn tile(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.sprites += 1;
    c.luaL_checktype(L_, 1, c.LUA_TTABLE);
    const p = ts(L_, 1, "path") orelse
        return c.luaL_error(L_, "field 'path' must be a string");
    const n = checkInt(L_, 2);
    const width = checkedTableInt(L_, 1, "width");
    const height = checkedTableInt(L_, 1, "height");
    const x = checkInt(L_, 3);
    const y = checkInt(L_, 4);
    const flip_x = (n & 1024) != 0 or c.lua_toboolean(L_, 5) != 0;
    const flip_y = (n & 2048) != 0 or c.lua_toboolean(L_, 6) != 0;
    if (debug_state.render.sprites) {
        bitmap(p, width, height, n & ~@as(i32, 3072), x, y, flip_x, flip_y);
    }
    return 0;
}
fn manifestStringEquals(json: []const u8, field: []const u8, expected: []const u8) bool {
    var needle: [64]u8 = undefined;
    const key = std.fmt.bufPrint(&needle, "\"{s}\"", .{field}) catch return false;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, json, at, key)) |found| {
        var cursor = found + key.len;
        while (cursor < json.len and std.ascii.isWhitespace(json[cursor])) : (cursor += 1) {}
        if (cursor >= json.len or json[cursor] != ':') {
            at = found + key.len;
            continue;
        }
        cursor += 1;
        while (cursor < json.len and std.ascii.isWhitespace(json[cursor])) : (cursor += 1) {}
        if (cursor >= json.len or json[cursor] != '"') return false;
        cursor += 1;
        if (cursor + expected.len >= json.len or
            !std.mem.eql(u8, json[cursor .. cursor + expected.len], expected) or
            json[cursor + expected.len] != '"')
        {
            return false;
        }
        return true;
    }
    return false;
}
fn manifestNumber(json: []const u8, field: []const u8, d: i32) i32 {
    var needle: [64]u8 = undefined;
    const key = std.fmt.bufPrint(&needle, "\"{s}\"", .{field}) catch return d;
    const at = std.mem.indexOf(u8, json, key) orelse return d;
    var end = at + key.len;
    while (end < json.len and std.ascii.isWhitespace(json[end])) : (end += 1) {}
    if (end >= json.len or json[end] != ':') return d;
    end += 1;
    while (end < json.len and std.ascii.isWhitespace(json[end])) : (end += 1) {}
    var stop = end;
    while (stop < json.len and json[stop] >= '0' and json[stop] <= '9') : (stop += 1) {}
    return std.fmt.parseInt(i32, json[end..stop], 10) catch d;
}
fn injectSprites() !void {
    var root_file: [1024]u8 = undefined;
    const path = std.fmt.bufPrint(&root_file, "{s}/lupi_manifest.txt", .{game_root}) catch return;
    const manifest = assetAll(path) orelse return;
    defer A.free(manifest);
    c.lua_pushcclosure(L, @as(c.lua_CFunction, @ptrCast(&injectSpritesProtected)), 0);
    c.lua_pushlightuserdata(L, @ptrCast(@constCast(&manifest)));
    if (c.lua_pcallk(L, 1, 0, 0, 0, null) != c.LUA_OK) return luaLoadError("sprite initialization");
}

// Keep host allocations outside the Lua longjmp boundary.
fn injectSpritesProtected(state: *c.lua_State) callconv(.c) c_int {
    const manifest_ptr: *const []const u8 = @ptrCast(@alignCast(c.lua_touserdata(state, 1)));
    const manifest = manifest_ptr.*;
    c.lua_newtable(L);
    var lines = std.mem.splitScalar(u8, manifest, '\n');
    while (lines.next()) |manifest_line| {
        var tok = std.mem.tokenizeScalar(u8, manifest_line, ' ');
        _ = tok.next() orelse continue;
        const encoded_bytes_text = tok.next() orelse continue;
        const encoded_bytes = std.fmt.parseUnsigned(usize, encoded_bytes_text, 10) catch continue;
        const rel = tok.next() orelse continue;
        const json = tok.rest();
        if (!manifestStringEquals(json, "type", "bitmap")) continue;
        const w = manifestNumber(json, "width", 0);
        const h = manifestNumber(json, "height", 0);
        if (w <= 0 or h <= 0) continue;
        const pixels_per_tile = @as(usize, @intCast(w)) * @as(usize, @intCast(h));
        if (encoded_bytes > lupi_tileset_pixels_max or encoded_bytes % pixels_per_tile != 0) {
            continue;
        }
        const encoded_tiles = encoded_bytes / pixels_per_tile;
        if (encoded_tiles == 0 or encoded_tiles > 1024) continue;
        var full: [1536]u8 = undefined;
        const full_path = std.fmt.bufPrint(&full, "{s}/{s}", .{ game_root, rel }) catch continue;
        if (fileSize(full_path) != encoded_bytes) continue;
        var comps: [32][]const u8 = undefined;
        var count: usize = 0;
        var pt = std.mem.tokenizeScalar(u8, rel, '/');
        while (pt.next()) |part| {
            if (count < comps.len) {
                comps[count] = part;
                count += 1;
            }
        }
        if (count == 0) continue;
        var depth: usize = 0;
        while (depth + 1 < count) {
            _ = c.lua_pushlstring(L, comps[depth].ptr, comps[depth].len);
            _ = c.lua_rawget(L, -2);
            if (!c.lua_istable(L, -1)) {
                _ = c.lua_pop(L, 1);
                c.lua_newtable(L);
                _ = c.lua_pushlstring(L, comps[depth].ptr, comps[depth].len);
                c.lua_pushvalue(L, -2);
                c.lua_settable(L, -4);
            }
            depth += 1;
        }
        c.lua_newtable(L);
        _ = c.lua_pushlstring(L, full_path.ptr, full_path.len);
        c.lua_setfield(L, -2, "path");
        c.lua_pushinteger(L, w);
        c.lua_setfield(L, -2, "width");
        c.lua_pushinteger(L, h);
        c.lua_setfield(L, -2, "height");
        c.lua_pushinteger(L, @intCast(encoded_tiles));
        c.lua_setfield(L, -2, "ntiles");
        _ = c.lua_pushlstring(L, comps[count - 1].ptr, comps[count - 1].len);
        c.lua_insert(L, -2);
        c.lua_settable(L, -3);
        while (depth > 0) {
            _ = c.lua_pop(L, 1);
            depth -= 1;
        }
    }
    _ = c.lua_setglobal(L, "Sprites");
    _ = c.lua_getglobal(L, "Sprites");
    c.lua_pushcclosure(L, @as(c.lua_CFunction, @ptrCast(&spritesFind)), 0);
    c.lua_setfield(L, -2, "find");
    _ = c.lua_pop(L, 1);
    return 0;
}
fn spritesFind(L_: *c.lua_State) callconv(.c) c_int {
    if (c.lua_getglobal(L_, "__lupi_find") != c.LUA_TFUNCTION) {
        _ = c.lua_pop(L_, 1);
        c.lua_pushnil(L_);
        return 1;
    }
    _ = c.lua_getglobal(L_, "Sprites");
    c.lua_pushvalue(L_, 1);
    if (c.lua_pcallk(L_, 2, 1, 0, 0, null) != c.LUA_OK) {
        logTopLuaError(L_, "Sprites.find");
        _ = c.lua_pop(L_, 1);
        c.lua_pushnil(L_);
    }
    return 1;
}
fn spritesLoader(_: *c.lua_State) callconv(.c) c_int {
    injectSprites() catch return c.lua_error(L);
    _ = c.lua_getglobal(L, "Sprites");
    return 1;
}
fn nestedInt(L_: *c.lua_State, parent: c_int, name: [:0]const u8, d: i32) i32 {
    _ = c.lua_getfield(L_, parent, name);
    const value = i(L_, -1, d);
    _ = c.lua_pop(L_, 1);
    return value;
}
fn tableNumber(L_: *c.lua_State, table_index: c_int, name: [:0]const u8) i32 {
    _ = c.lua_getfield(L_, table_index, name);
    defer _ = c.lua_pop(L_, 1);
    return checkInt(L_, -1);
}

fn isReservedMapLayer(name: []const u8) bool {
    return std.mem.eql(u8, name, "metadata") or
        std.mem.eql(u8, name, "lupi_metadata") or
        std.mem.eql(u8, name, "tilesets") or
        std.mem.eql(u8, name, "layers");
}

/// Lua deliberately leaves hash-table iteration order undefined. Generated
/// Lupi maps normally contain one tileset per ui.map call, but hand-written
/// maps may contain several overlapping layers. Sort legacy names so their
/// result remains stable across processes, Lua hash seeds, and Lua releases.
fn sortMapLayerNames(names: [][]const u8) void {
    var index: usize = 1;
    while (index < names.len) : (index += 1) {
        var current = index;
        while (current > 0 and std.mem.order(u8, names[current], names[current - 1]) == .lt) : (current -= 1) {
            std.mem.swap([]const u8, &names[current], &names[current - 1]);
        }
    }
}

fn mapOrderError(L_: *c.lua_State, names: [][]const u8, message: [*:0]const u8) c_int {
    _ = names;
    return c.luaL_error(L_, message);
}

/// Draw one named map layer. Keeping layer lookup separate from ordering makes
/// the overwrite rule obvious: each completed layer is composited over the
/// previous one, while palette index zero remains transparent in bitmapData.
fn drawMapLayer(L_: *c.lua_State, map_index: c_int, sprites: c_int, layer_key: []const u8, map_w: i32, map_h: i32, tile_size: i32, ox: i32, oy: i32) void {
    _ = c.lua_pushlstring(L_, layer_key.ptr, layer_key.len);
    _ = c.lua_rawget(L_, map_index);
    defer _ = c.lua_pop(L_, 1);
    if (!c.lua_istable(L_, -1)) return;
    const values = c.lua_absindex(L_, -1);

    var tileset_name = layer_key;
    _ = c.lua_getfield(L_, map_index, "tilesets");
    if (c.lua_istable(L_, -1)) {
        _ = c.lua_pushlstring(L_, layer_key.ptr, layer_key.len);
        _ = c.lua_rawget(L_, -2);
        var mapped_len: usize = 0;
        const mapped = c.lua_tolstring(L_, -1, &mapped_len);
        if (mapped != null) tileset_name = mapped[0..mapped_len];
        _ = c.lua_pop(L_, 1);
    }
    _ = c.lua_pop(L_, 1);

    if (c.lua_getglobal(L_, "__lupi_find") != c.LUA_TFUNCTION) {
        _ = c.lua_pop(L_, 1);
        return;
    }
    c.lua_pushvalue(L_, sprites);
    _ = c.lua_pushlstring(L_, tileset_name.ptr, tileset_name.len);
    if (c.lua_pcallk(L_, 2, 1, 0, 0, null) != c.LUA_OK) {
        logTopLuaError(L_, "ui.map sprite lookup");
        _ = c.lua_pop(L_, 1);
        return;
    }
    defer _ = c.lua_pop(L_, 1);
    if (!c.lua_istable(L_, -1)) return;

    const sprite = c.lua_absindex(L_, -1);
    const path = ts(L_, sprite, "path") orelse return;
    const tile_w = tableNumber(L_, sprite, "width");
    const tile_h = tableNumber(L_, sprite, "height");
    if (tile_w <= 0 or tile_h <= 0) return;
    const map_data = assetAll(path) orelse return;
    defer A.free(map_data);
    if (map_data.len > lupi_tileset_pixels_max) return;

    const total_wide = @as(i64, map_w) * map_h;
    if (total_wide <= 0 or total_wide > lupi_profile.tile_sample_pixels_max) return;
    const total: i32 = @intCast(total_wide);
    var index: i32 = 1;
    while (index <= total and raster_work_remaining > 0) : (index += 1) {
        _ = c.lua_rawgeti(L_, values, index);
        const tile_number = c.lua_tonumberx(L_, -1, null);
        const id = if (c.lua_isnil(L_, -1) or !std.math.isFinite(tile_number) or
            tile_number < @as(f64, @floatFromInt(std.math.minInt(i32))) or
            tile_number > @as(f64, @floatFromInt(std.math.maxInt(i32))))
            -1
        else
            @as(i32, @intFromFloat(tile_number));
        _ = c.lua_pop(L_, 1);
        if (id < 0) continue;
        const col = @mod(index - 1, map_w);
        const row = @divTrunc(index - 1, map_w);
        bitmapData(
            map_data,
            tile_w,
            tile_h,
            id & ~@as(i32, 3072),
            @as(i64, ox) + @as(i64, col) * tile_size,
            @as(i64, oy) + @as(i64, row) * tile_size,
            (id & 1024) != 0,
            (id & 2048) != 0,
        );
    }
}

fn l_map(L_: *c.lua_State) callconv(.c) c_int {
    debug_state.draw_current.maps += 1;
    c.luaL_checktype(L_, 1, c.LUA_TTABLE);
    const map_index = c.lua_absindex(L_, 1);
    _ = c.lua_getfield(L_, map_index, "metadata");
    if (!c.lua_istable(L_, -1)) {
        _ = c.lua_pop(L_, 1);
        _ = c.lua_getfield(L_, map_index, "lupi_metadata");
    }
    if (!c.lua_istable(L_, -1)) {
        _ = c.lua_pop(L_, 1);
        std.debug.print("MAP - NOT FOUND!\n", .{});
        return 0;
    }
    const metadata = c.lua_absindex(L_, -1);
    const map_w = tableNumber(L_, metadata, "width");
    const map_h = tableNumber(L_, metadata, "height");
    const tile_size = tableNumber(L_, metadata, "tile_size");
    _ = c.lua_pop(L_, 1);
    if (map_w <= 0 or map_h <= 0 or tile_size <= 0) return 0;
    const ox = optionalInt(L_, 2, 0);
    const oy = optionalInt(L_, 3, 0);

    // First collect every drawable string/table entry. We copy only slices:
    // map keys are interned Lua strings and remain alive while this call runs.
    var layer_count: usize = 0;
    c.lua_pushnil(L_);
    while (c.lua_next(L_, map_index) != 0) {
        if (c.lua_type(L_, -2) == c.LUA_TSTRING and c.lua_istable(L_, -1)) {
            var key_len: usize = 0;
            const key = c.lua_tolstring(L_, -2, &key_len);
            if (key != null and !isReservedMapLayer(key[0..key_len])) {
                if (layer_count == debug_mod.layer_count_max) {
                    return c.luaL_error(L_, "ui.map: at most 256 drawable layers are supported");
                }
                layer_count += 1;
            }
        }
        _ = c.lua_pop(L_, 1);
    }
    // The layer count is bounded, so keep all ordering storage on the stack.
    // This also survives Lua's longjmp-based error unwinding without leaking.
    var layer_names_storage: [debug_mod.layer_count_max][]const u8 = undefined;
    const layer_names = layer_names_storage[0..layer_count];
    var collected: usize = 0;
    c.lua_pushnil(L_);
    while (c.lua_next(L_, map_index) != 0) {
        if (c.lua_type(L_, -2) == c.LUA_TSTRING and c.lua_istable(L_, -1)) {
            var key_len: usize = 0;
            const key = c.lua_tolstring(L_, -2, &key_len);
            if (key != null and !isReservedMapLayer(key[0..key_len])) {
                layer_names[collected] = key[0..key_len];
                collected += 1;
            }
        }
        _ = c.lua_pop(L_, 1);
    }

    // An explicit `layers` array is a strict, complete bottom-to-top contract.
    // Invalid or partial declarations fail loudly instead of hiding content or
    // silently changing precedence. Legacy maps receive a lexical fallback.
    _ = c.lua_getfield(L_, map_index, "layers");
    if (!c.lua_isnil(L_, -1)) {
        if (!c.lua_istable(L_, -1)) {
            _ = c.lua_pop(L_, 1);
            return mapOrderError(L_, layer_names, "ui.map: 'layers' must be an array of layer names");
        }
        if (c.lua_rawlen(L_, -1) != layer_count) {
            _ = c.lua_pop(L_, 1);
            return mapOrderError(L_, layer_names, "ui.map: 'layers' must list every map layer exactly once");
        }
        var target: usize = 0;
        while (target < layer_count) : (target += 1) {
            _ = c.lua_rawgeti(L_, -1, @intCast(target + 1));
            if (c.lua_type(L_, -1) != c.LUA_TSTRING) {
                _ = c.lua_pop(L_, 2);
                return mapOrderError(L_, layer_names, "ui.map: every 'layers' entry must be a string");
            }
            var wanted_len: usize = 0;
            const wanted_ptr = c.lua_tolstring(L_, -1, &wanted_len).?;
            const wanted = wanted_ptr[0..wanted_len];
            var found: ?usize = null;
            var candidate = target;
            while (candidate < layer_count) : (candidate += 1) {
                if (std.mem.eql(u8, layer_names[candidate], wanted)) {
                    found = candidate;
                    break;
                }
            }
            _ = c.lua_pop(L_, 1);
            if (found) |source| {
                std.mem.swap([]const u8, &layer_names[target], &layer_names[source]);
            } else {
                _ = c.lua_pop(L_, 1);
                return mapOrderError(L_, layer_names, "ui.map: 'layers' contains an unknown or duplicate layer");
            }
        }
    } else {
        sortMapLayerNames(layer_names);
    }
    _ = c.lua_pop(L_, 1);

    _ = c.lua_getglobal(L_, "Sprites");
    if (!c.lua_istable(L_, -1)) {
        _ = c.lua_pop(L_, 1);
        return 0;
    }
    const sprites = c.lua_absindex(L_, -1);
    defer _ = c.lua_pop(L_, 1);
    for (layer_names) |layer_name| {
        if (raster_work_remaining == 0) break;
        if (debug_state.shouldDrawMapLayer(layer_name)) {
            drawMapLayer(
                L_,
                map_index,
                sprites,
                layer_name,
                map_w,
                map_h,
                tile_size,
                ox,
                oy,
            );
        }
    }
    return 0;
}
fn buttonValue(L_: *c.lua_State) i32 {
    if (c.lua_type(L_, 1) == c.LUA_TSTRING) {
        var len: usize = 0;
        const s = c.lua_tolstring(L_, 1, &len) orelse return 0;
        const name = s[0..len];
        if (std.mem.eql(u8, name, "UP")) return c.SDL_CONTROLLER_BUTTON_DPAD_UP;
        if (std.mem.eql(u8, name, "DOWN")) return c.SDL_CONTROLLER_BUTTON_DPAD_DOWN;
        if (std.mem.eql(u8, name, "LEFT")) return c.SDL_CONTROLLER_BUTTON_DPAD_LEFT;
        if (std.mem.eql(u8, name, "RIGHT")) return c.SDL_CONTROLLER_BUTTON_DPAD_RIGHT;
        if (std.mem.eql(u8, name, "BTN_Z")) return c.SDL_CONTROLLER_BUTTON_A;
        if (std.mem.eql(u8, name, "BTN_X")) return c.SDL_CONTROLLER_BUTTON_B;
        if (std.mem.eql(u8, name, "BTN_E")) return c.SDL_CONTROLLER_BUTTON_X;
        if (std.mem.eql(u8, name, "BTN_Q")) return c.SDL_CONTROLLER_BUTTON_Y;
        if (std.mem.eql(u8, name, "BTN_F")) return c.SDL_CONTROLLER_BUTTON_LEFTSHOULDER;
        if (std.mem.eql(u8, name, "BTN_G")) return c.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER;
        if (std.mem.eql(u8, name, "BTN_A") or std.mem.eql(u8, name, "SNES_A")) return c.SDL_CONTROLLER_BUTTON_A;
        if (std.mem.eql(u8, name, "BTN_B") or std.mem.eql(u8, name, "SNES_B")) return c.SDL_CONTROLLER_BUTTON_B;
        if (std.mem.eql(u8, name, "SNES_X")) return c.SDL_CONTROLLER_BUTTON_X;
        if (std.mem.eql(u8, name, "BTN_Y") or std.mem.eql(u8, name, "SNES_Y")) return c.SDL_CONTROLLER_BUTTON_Y;
        if (std.mem.eql(u8, name, "BTN_L") or std.mem.eql(u8, name, "SNES_L")) return c.SDL_CONTROLLER_BUTTON_LEFTSHOULDER;
        if (std.mem.eql(u8, name, "BTN_R") or std.mem.eql(u8, name, "SNES_R")) return c.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER;
        if (std.mem.eql(u8, name, "BTN_SELECT") or std.mem.eql(u8, name, "SELECT")) return c.SDL_CONTROLLER_BUTTON_BACK;
        if (std.mem.eql(u8, name, "BTN_START") or std.mem.eql(u8, name, "START")) return c.SDL_CONTROLLER_BUTTON_START;
    }
    return checkInt(L_, 1);
}

// -----------------------------------------------------------------------------
// Lua API binding and game lifecycle

fn btn(L_: *c.lua_State) callconv(.c) c_int {
    c.lua_pushboolean(L_, @intFromBool(input_state.held(buttonValue(L_), optionalInt(L_, 2, 0))));
    return 1;
}
fn btnp(L_: *c.lua_State) callconv(.c) c_int {
    c.lua_pushboolean(L_, @intFromBool(input_state.pressed(buttonValue(L_), optionalInt(L_, 2, 0))));
    return 1;
}
fn textInput(L_: *c.lua_State, consume: bool) c_int {
    const value = input_state.peekText() orelse {
        c.lua_pushnil(L_);
        return 1;
    };
    _ = c.lua_pushlstring(L_, value.ptr, value.len);
    if (consume) input_state.consumeText(value.len);
    return 1;
}
fn peektext(L_: *c.lua_State) callconv(.c) c_int {
    return textInput(L_, false);
}
fn readtext(L_: *c.lua_State) callconv(.c) c_int {
    return textInput(L_, true);
}
fn stat(L_: *c.lua_State) callconv(.c) c_int {
    switch (i(L_, 1, 0)) {
        0 => {
            const kib = c.lua_gc(L_, c.LUA_GCCOUNT);
            const bytes = c.lua_gc(L_, c.LUA_GCCOUNTB);
            c.lua_pushnumber(L_, @as(f64, @floatFromInt(kib)) * 1024.0 + @as(f64, @floatFromInt(bytes)));
        },
        1 => c.lua_pushnumber(
            L_,
            @min(last_work_ms * debug_mod.target_simulation_hz / 10.0, 100.0),
        ),
        7 => c.lua_pushnumber(L_, if (last_frame_ms > 0) 1000.0 / last_frame_ms else 0),
        else => c.lua_pushnumber(L_, 0),
    }
    return 1;
}
fn resolveMusicPath(relative: []const u8, output: []u8) ?[:0]const u8 {
    const extensions = [_][]const u8{ "", ".mp3", ".ogg", ".wav", ".flac" };
    for (extensions) |extension| {
        const candidate = std.fmt.bufPrint(output[0 .. output.len - 1], "{s}/{s}{s}", .{ game_root, relative, extension }) catch continue;
        if (!fileExists(candidate)) continue;
        output[candidate.len] = 0;
        return output[0..candidate.len :0];
    }
    return null;
}
fn sfxMusic(L_: *c.lua_State) callconv(.c) c_int {
    if (c.lua_type(L_, 1) == c.LUA_TNUMBER and i(L_, 1, 0) == -1) {
        audio_state.stopMusic();
        return 0;
    }
    var length: usize = 0;
    const name = c.lua_tolstring(L_, 1, &length) orelse return 0;
    var path: [2048]u8 = undefined;
    if (resolveMusicPath(name[0..length], &path)) |resolved| {
        if (audio_state.available() and !audio_state.playMusic(resolved)) std.debug.print("Nao foi possivel reproduzir musica: {s}\n", .{resolved});
    } else std.debug.print("Musica nao encontrada: {s}\n", .{name[0..length]});
    return 0;
}
fn sfxVolume(L_: *c.lua_State) callconv(.c) c_int {
    const requested = c.luaL_optnumber(L_, 1, 1);
    if (std.math.isFinite(requested)) {
        audio_state.setVolume(@floatCast(std.math.clamp(requested, 0, 1)));
    }
    return 0;
}
fn sfxEffect(L_: *c.lua_State) callconv(.c) c_int {
    const requested_pan = c.luaL_optnumber(L_, 3, 0.5);
    const pan: f32 = if (std.math.isFinite(requested_pan))
        @floatCast(std.math.clamp(requested_pan, 0, 1))
    else
        0.5;
    audio_state.playEffect(i(L_, 1, 0), i(L_, 2, 60), pan);
    return 0;
}
fn mid(L_: *c.lua_State) callconv(.c) c_int {
    const a = c.luaL_checknumber(L_, 1);
    const b = c.luaL_checknumber(L_, 2);
    const d = c.luaL_checknumber(L_, 3);
    const result = if ((a <= b and b <= d) or (d <= b and b <= a))
        b
    else if ((b <= a and a <= d) or (d <= a and a <= b))
        a
    else
        d;
    c.lua_pushnumber(L_, result);
    return 1;
}
fn logf(L_: *c.lua_State) callconv(.c) c_int {
    var length: usize = 0;
    const s = c.luaL_checklstring(L_, 1, &length);
    std.debug.print("[ELIS] {s}\n", .{std.mem.sliceTo(s[0..length], 0)});
    return 0;
}
fn add(name: [:0]const u8, f: anytype) void {
    c.lua_pushcclosure(L, @as(c.lua_CFunction, @ptrCast(&f)), 0);
    c.lua_setfield(L, -2, name);
}

fn longBracketOpening(source: []const u8, at: usize) ?usize {
    if (at >= source.len or source[at] != '[') return null;
    var cursor = at + 1;
    while (cursor < source.len and source[cursor] == '=') : (cursor += 1) {}
    if (cursor >= source.len or source[cursor] != '[') return null;
    return cursor - at + 1;
}

fn longBracketClosing(source: []const u8, at: usize, equals: usize) ?usize {
    if (at >= source.len or source[at] != ']') return null;
    var cursor = at + 1;
    var seen: usize = 0;
    while (cursor < source.len and seen < equals and source[cursor] == '=') : ({
        cursor += 1;
        seen += 1;
    }) {}
    if (seen != equals or cursor >= source.len or source[cursor] != ']') return null;
    return cursor - at + 1;
}

fn identifierByte(value: u8) bool {
    return std.ascii.isAlphanumeric(value) or value == '_';
}

/// Lupi's bundled runtime accepts binary integer literals. Distribution Lua
/// 5.4 builds generally do not, so translate only lexer-visible numeric
/// tokens. Quoted strings, escaped bytes, line comments, long strings, and long
/// comments are copied verbatim.
const TranslatedSource = struct {
    allocation: []u8,
    text: []u8,
};

fn translateBinaryLiterals(source: []const u8) ?TranslatedSource {
    const output = A.alloc(u8, source.len) catch return null;
    var input: usize = 0;
    var written: usize = 0;
    var quote: u8 = 0;
    var line_comment = false;
    var long_equals: ?usize = null;

    while (input < source.len) {
        if (quote != 0) {
            const value = source[input];
            output[written] = value;
            written += 1;
            input += 1;
            if (value == '\\' and input < source.len) {
                output[written] = source[input];
                written += 1;
                input += 1;
            } else if (value == quote) quote = 0;
            continue;
        }
        if (line_comment) {
            const value = source[input];
            output[written] = value;
            written += 1;
            input += 1;
            if (value == '\n' or value == '\r') line_comment = false;
            continue;
        }
        if (long_equals) |equals| {
            if (longBracketClosing(source, input, equals)) |length| {
                @memcpy(output[written..][0..length], source[input..][0..length]);
                written += length;
                input += length;
                long_equals = null;
            } else {
                output[written] = source[input];
                written += 1;
                input += 1;
            }
            continue;
        }

        if (source[input] == '\'' or source[input] == '"') {
            quote = source[input];
            output[written] = source[input];
            written += 1;
            input += 1;
            continue;
        }
        if (input + 1 < source.len and source[input] == '-' and source[input + 1] == '-') {
            output[written] = '-';
            output[written + 1] = '-';
            written += 2;
            input += 2;
            if (longBracketOpening(source, input)) |length| {
                @memcpy(output[written..][0..length], source[input..][0..length]);
                long_equals = length - 2;
                written += length;
                input += length;
            } else line_comment = true;
            continue;
        }
        if (longBracketOpening(source, input)) |length| {
            @memcpy(output[written..][0..length], source[input..][0..length]);
            long_equals = length - 2;
            written += length;
            input += length;
            continue;
        }
        const can_start_number = input == 0 or !identifierByte(source[input - 1]);
        if (can_start_number and input + 2 < source.len and source[input] == '0' and
            (source[input + 1] == 'b' or source[input + 1] == 'B') and
            (source[input + 2] == '0' or source[input + 2] == '1'))
        {
            var end = input + 2;
            var value: u64 = 0;
            while (end < source.len and (source[end] == '0' or source[end] == '1')) : (end += 1)
                value = value *% 2 +% @as(u64, source[end] - '0');
            const malformed_suffix = end < source.len and (identifierByte(source[end]) or source[end] == '.');
            if (!malformed_suffix) {
                // Hex preserves one integer token, including wrapping high bits.
                // Signed decimal would inject unary minus (or even a "--" comment).
                var number_buffer: [18]u8 = undefined;
                const numeral = std.fmt.bufPrint(&number_buffer, "0x{x}", .{value}) catch unreachable;
                @memcpy(output[written..][0..numeral.len], numeral);
                written += numeral.len;
                input = end;
                continue;
            }
        }
        output[written] = source[input];
        written += 1;
        input += 1;
    }
    return .{ .allocation = output, .text = output[0..written] };
}

fn luaCompileFile(L_: *c.lua_State) callconv(.c) c_int {
    var path_length: usize = 0;
    const path_pointer = c.luaL_checklstring(L_, 1, &path_length);
    const path = path_pointer[0..path_length];
    const source = assetAll(path) orelse {
        c.lua_pushnil(L_);
        _ = c.lua_pushstring(L_, "cannot open Lua source file");
        return 2;
    };
    defer A.free(source);
    const translated = translateBinaryLiterals(source) orelse {
        c.lua_pushnil(L_);
        _ = c.lua_pushstring(L_, "out of memory while loading Lua source");
        return 2;
    };
    defer A.free(translated.allocation);
    const chunk_name = std.fmt.allocPrintSentinel(A, "@{s}", .{path}, 0) catch {
        c.lua_pushnil(L_);
        _ = c.lua_pushstring(L_, "out of memory while naming Lua source");
        return 2;
    };
    defer A.free(chunk_name);
    if (c.luaL_loadbufferx(L_, translated.text.ptr, translated.text.len, chunk_name.ptr, "t") == c.LUA_OK) return 1;
    c.lua_pushnil(L_);
    c.lua_insert(L_, -2);
    return 2;
}

fn bind() void {
    c.lua_newtable(L);
    add("cls", cls);
    add("palset", palset);
    add("set_pallet", setPallet);
    add("line", ln);
    add("draw_rect", dr);
    add("rect", oldr);
    add("rectfill", oldrf);
    add("draw_circle", dc);
    add("circ", co);
    add("circfill", ci);
    add("trisfill", tr);
    add("print", pr);
    add("camera", camf);
    add("clip", clipf);
    add("fillp", fillp);
    add("spr", spr);
    add("tile", tile);
    add("preload_spritesheet", preloadSpritesheet);
    add("draw_sprite", drawSprite);
    add("map", l_map);
    add("btn", btn);
    add("btnp", btnp);
    add("peektext", peektext);
    add("readtext", readtext);
    add("stat", stat);
    add("mid", mid);
    add("log", logf);
    c.lua_setglobal(L, "ui");

    c.lua_newtable(L);
    add("music", sfxMusic);
    add("volume", sfxVolume);
    add("fx", sfxEffect);
    c.lua_setglobal(L, "sfx");
}
fn resetGameState() void {
    audio_state.resetForGame();
    for (&fb) |*row| @memset(row, 0);
    @memset(&pal, Color{ .r = 0, .g = 0, .b = 0, .a = 0 });
    @memset(&pattern, 0);
    cam = .{};
    clip = .{};
    clipping = false;
    resetRasterWork();
    ticks = 0;
    last_frame_ms = 1000.0 / debug_mod.target_simulation_hz;
    last_work_ms = 0;
    debug_state.resetGame();
    legacy_sprite_ref = c.LUA_NOREF;
}
fn load(path: []const u8) !void {
    if (!gameFitsFlash(path)) return error.GameExceedsLupiFlash;
    resetGameState();
    game_root = path;
    legacy_sprite_ref = c.LUA_NOREF;
    lua_heap.reset();
    L = c.lua_newstate(luaAllocate, &lua_heap) orelse return error.LuaInit;
    errdefer closeGameLua();
    c.luaL_openlibs(L);
    bind();
    registerConstants();
    c.lua_pushcclosure(L, @as(c.lua_CFunction, @ptrCast(&luaCompileFile)), 0);
    c.lua_setglobal(L, "__lupi_compile_file");
    const helper =
        \\local __lupi_require = require
        \\require = function(name, ...)
        \\  local result = __lupi_require(name, ...)
        \\  if name == 'palette' and type(Palette) == 'table' then
        \\    -- Convert RGB888 to the closest zero-based RGB555 palette index.
        \\    Palette.hex = function(rgb)
        \\      local r = math.floor(rgb / 65536) % 256
        \\      local g = math.floor(rgb / 256) % 256
        \\      local b = rgb % 256
        \\      local r5, g5, b5 = math.floor(r / 8), math.floor(g / 8), math.floor(b / 8)
        \\      local target = (r5 << 10) | (g5 << 5) | b5
        \\      local best_index, best_distance = 0, math.huge
        \\      for index, value in ipairs(Palette) do
        \\        if value == target then return index - 1 end
        \\        local pr = ((value >> 10) & 31) * 255 / 31
        \\        local pg = ((value >> 5) & 31) * 255 / 31
        \\        local pb = (value & 31) * 255 / 31
        \\        local distance = (r-pr)^2 + (g-pg)^2 + (b-pb)^2
        \\        if distance < best_distance then
        \\          best_index, best_distance = index - 1, distance
        \\        end
        \\      end
        \\      return best_index
        \\    end
        \\  end
        \\  return result
        \\end
        \\local __lupi_old_searcher = package.searchers[2]
        \\package.searchers[2] = function(name)
        \\  local path = package.searchpath(name, package.path)
        \\  if not path then return '\n\tno file: '..name end
        \\  local chunk, err = __lupi_compile_file(path)
        \\  if not chunk then return err end
        \\  return chunk
        \\end
        \\local __lupi_sprite_indexes = setmetatable({}, { __mode = 'k' })
        \\local function __lupi_sprite_index(root)
        \\  local cached = __lupi_sprite_indexes[root]
        \\  if cached then return cached end
        \\  local index = { by_path = {}, by_name = {} }
        \\  local function visit(node, prefix)
        \\    local keys = {}
        \\    for key in pairs(node or {}) do
        \\      if type(key) == 'string' then keys[#keys + 1] = key end
        \\    end
        \\    table.sort(keys)
        \\    for _, key in ipairs(keys) do
        \\      local value = node[key]
        \\      if type(value) == 'table' then
        \\        local path = prefix == '' and key or (prefix .. '/' .. key)
        \\        if value.path then
        \\          index.by_path[path] = value
        \\          local matches = index.by_name[key] or {}
        \\          matches[#matches + 1] = { path = path, value = value }
        \\          index.by_name[key] = matches
        \\        else
        \\          visit(value, path)
        \\        end
        \\      end
        \\    end
        \\  end
        \\  visit(root, '')
        \\  __lupi_sprite_indexes[root] = index
        \\  return index
        \\end
        \\function __lupi_find(root, name)
        \\  if type(root) ~= 'table' or type(name) ~= 'string' then return nil end
        \\  local index = __lupi_sprite_index(root)
        \\  if string.find(name, '/', 1, true) then return index.by_path[name] end
        \\  local matches = index.by_name[name]
        \\  if not matches then return nil end
        \\  if #matches == 1 then return matches[1].value end
        \\  local paths = {}
        \\  for position, match in ipairs(matches) do paths[position] = match.path end
        \\  error("ambiguous sprite '" .. name .. "': " .. table.concat(paths, ', '), 2)
        \\end
    ;
    if (c.luaL_loadstring(L, helper) != c.LUA_OK) return luaLoadError("helper compile");
    if (c.lua_pcallk(L, 0, 0, 0, 0, null) != c.LUA_OK) return luaLoadError("helper run");
    try injectSprites();
    _ = c.lua_getglobal(L, "package");
    _ = c.lua_getfield(L, -1, "path");
    var current_len: usize = 0;
    const current_path = c.lua_tolstring(L, -1, &current_len);
    if (current_path != null) {
        const package_path = std.fmt.allocPrint(A, "{s};{s}/?.lua", .{ current_path[0..current_len], path }) catch return error.LuaLoad;
        defer A.free(package_path);
        _ = c.lua_pushlstring(L, package_path.ptr, package_path.len);
        c.lua_setfield(L, -3, "path");
    }
    _ = c.lua_pop(L, 2);
    _ = c.lua_getglobal(L, "package");
    _ = c.lua_getfield(L, -1, "preload");
    c.lua_pushcclosure(L, @as(c.lua_CFunction, @ptrCast(&spritesLoader)), 0);
    c.lua_setfield(L, -2, "sprites");
    _ = c.lua_pop(L, 2);
    const f = try std.fmt.allocPrint(A, "{s}/game.lua", .{path});
    defer A.free(f);
    const z = try A.allocSentinel(u8, f.len, 0);
    defer A.free(z);
    @memcpy(z, f);
    _ = c.lua_getglobal(L, "__lupi_compile_file");
    _ = c.lua_pushlstring(L, z.ptr, f.len);
    if (c.lua_pcallk(L, 1, 2, 0, 0, null) != c.LUA_OK) return luaLoadError("game compile");
    if (!c.lua_isfunction(L, -2)) {
        c.lua_remove(L, -2);
        return luaLoadError("game compile");
    }
    _ = c.lua_pop(L, 1);
    if (c.lua_pcallk(L, 0, 0, 0, 0, null) != c.LUA_OK) return luaLoadError("game run");
}
fn luaLoadError(stage: []const u8) error{LuaLoad} {
    var len: usize = 0;
    const msg = c.lua_tolstring(L, -1, &len);
    if (msg != null) std.debug.print("Erro ao carregar Lua ({s}): {s}\n", .{ stage, msg[0..len] }) else std.debug.print("Erro ao carregar Lua ({s})\n", .{stage});
    return error.LuaLoad;
}
fn setLuaConstant(name: [:0]const u8, value: c.lua_Integer) void {
    c.lua_pushinteger(L, value);
    c.lua_setglobal(L, name);
}
fn registerConstants() void {
    setLuaConstant("UP", c.SDL_CONTROLLER_BUTTON_DPAD_UP);
    setLuaConstant("DOWN", c.SDL_CONTROLLER_BUTTON_DPAD_DOWN);
    setLuaConstant("LEFT", c.SDL_CONTROLLER_BUTTON_DPAD_LEFT);
    setLuaConstant("RIGHT", c.SDL_CONTROLLER_BUTTON_DPAD_RIGHT);

    // Original Lupi names: Z/X are the two primary actions, Q/E the upper
    // face buttons and F/G the shoulder pair.
    setLuaConstant("BTN_Z", c.SDL_CONTROLLER_BUTTON_A);
    setLuaConstant("BTN_X", c.SDL_CONTROLLER_BUTTON_B);
    setLuaConstant("BTN_E", c.SDL_CONTROLLER_BUTTON_X);
    setLuaConstant("BTN_Q", c.SDL_CONTROLLER_BUTTON_Y);
    setLuaConstant("BTN_F", c.SDL_CONTROLLER_BUTTON_LEFTSHOULDER);
    setLuaConstant("BTN_G", c.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER);

    // Explicit SNES-style aliases make all twelve digital controls available
    // without changing the historical BTN_X meaning above.
    setLuaConstant("BTN_A", c.SDL_CONTROLLER_BUTTON_A);
    setLuaConstant("BTN_B", c.SDL_CONTROLLER_BUTTON_B);
    setLuaConstant("BTN_Y", c.SDL_CONTROLLER_BUTTON_Y);
    setLuaConstant("BTN_L", c.SDL_CONTROLLER_BUTTON_LEFTSHOULDER);
    setLuaConstant("BTN_R", c.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER);
    setLuaConstant("BTN_SELECT", c.SDL_CONTROLLER_BUTTON_BACK);
    setLuaConstant("BTN_START", c.SDL_CONTROLLER_BUTTON_START);
    setLuaConstant("SNES_A", c.SDL_CONTROLLER_BUTTON_A);
    setLuaConstant("SNES_B", c.SDL_CONTROLLER_BUTTON_B);
    setLuaConstant("SNES_X", c.SDL_CONTROLLER_BUTTON_X);
    setLuaConstant("SNES_Y", c.SDL_CONTROLLER_BUTTON_Y);
    setLuaConstant("SNES_L", c.SDL_CONTROLLER_BUTTON_LEFTSHOULDER);
    setLuaConstant("SNES_R", c.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER);
    setLuaConstant("SELECT", c.SDL_CONTROLLER_BUTTON_BACK);
    setLuaConstant("START", c.SDL_CONTROLLER_BUTTON_START);
}
fn update() bool {
    resetRasterWork();
    if (c.lua_getglobal(L, "update") != c.LUA_TFUNCTION) {
        _ = c.lua_pop(L, 1);
        return true;
    }
    c.lua_pushnumber(L, ticks);
    ticks += 1;
    if (c.lua_pcallk(L, 1, 0, 0, 0, null) != c.LUA_OK) {
        var len: usize = 0;
        const msg = c.lua_tolstring(L, -1, &len);
        if (msg != null) std.debug.print("Erro de atualizacao Lua: {s}\n", .{msg[0..len]}) else std.debug.print("Erro de atualizacao Lua\n", .{});
        _ = c.lua_pop(L, 1);
        return false;
    }
    return true;
}

fn packColor(value: Color) u32 {
    return (@as(u32, value.r) << 24) |
        (@as(u32, value.g) << 16) |
        (@as(u32, value.b) << 8) |
        value.a;
}

/// Converts the console's indexed framebuffer to SDL's RGBA8888 upload format.
/// Keeping this in one function ensures the benchmark and runtime measure and
/// execute the same conversion path.
fn paletteColor(index: u8, simulator_chrome: bool) Color {
    if (!simulator_chrome and index == 0) return .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    return pal[index];
}

fn convertFrame(output: *[W * H]u32, simulator_chrome: bool) void {
    for (0..H) |y| {
        for (0..W) |x| output[y * W + x] = packColor(paletteColor(fb[y][x], simulator_chrome));
    }
}

fn renderQuitOverlay(output: *[W * H]u32) void {
    resetRasterWork();
    const saved_palette = pal;
    const saved_camera = cam;
    const saved_clip = clip;
    const saved_clipping = clipping;
    const saved_pattern = pattern;
    defer {
        pal = saved_palette;
        cam = saved_camera;
        clip = saved_clip;
        clipping = saved_clipping;
        pattern = saved_pattern;
    }
    for (&fb) |*row| @memset(row, 0);
    cam = .{};
    clip = .{};
    clipping = false;
    @memset(&pattern, 0);
    overlayPalette();
    drawQuitDialog(1);
    convertFrame(output, false);
}

fn debugOnOff(enabled: bool) []const u8 {
    return if (enabled) "ON" else "OFF";
}

fn drawDebugLine(x: i32, y: i32, comptime format: []const u8, args: anytype) void {
    var buffer: [128]u8 = undefined;
    const line_text = std.fmt.bufPrint(&buffer, format, args) catch return;
    text(line_text, x, y, 5);
}

fn drawDebugStats() void {
    rect(4, 4, 284, 132, true, 1);
    rect(5, 5, 282, 130, false, 3);
    drawDebugLine(10, 10, "ELIS SIMULATOR DEBUG  {s}", .{@tagName(builtin.mode)});
    drawDebugLine(10, 20, "SIM {d:.1} Hz / 60.0  ({d:.0}%)", .{
        debug_state.simulation_hz,
        debug_state.simulation_hz * 100.0 / debug_mod.target_simulation_hz,
    });
    drawDebugLine(10, 30, "FPS {d:.1}  FRAME {d:.2} ms", .{
        debug_state.fps,
        debug_state.frame_ms_average,
    });
    drawDebugLine(10, 40, "UPDATE {d:.3} ms  WORK {d:.2} ms", .{
        debug_state.update_ms_average,
        debug_state.work_ms_average,
    });
    drawDebugLine(10, 50, "FRAME MAX {d:.2} ms  TICK {d:.0}", .{
        debug_state.frame_ms_max,
        ticks,
    });
    drawDebugLine(10, 60, "LUA {d:.0}/{d} KiB  AUDIO {s}", .{
        @as(f64, @floatFromInt(debug_state.lua_memory_bytes)) / 1024.0,
        lupi_lua_heap_bytes_max / 1024,
        debugOnOff(audio_state.available()),
    });
    const draws = debug_state.draw_last;
    drawDebugLine(10, 70, "DRAWS CLR:{d} PR:{d} SPR:{d} TXT:{d}", .{
        draws.clears,
        draws.primitives,
        draws.sprites,
        draws.text,
    });
    drawDebugLine(10, 80, "MAPS {d}  LAYERS {d} ON / {d} OFF", .{
        draws.maps,
        draws.map_layers_drawn,
        draws.map_layers_hidden,
    });
    drawDebugLine(10, 90, "VIDEO 480x270 > {d}x{d}  {d}x", .{
        debug_state.output_width,
        debug_state.output_height,
        debug_state.viewport_scale,
    });
    drawDebugLine(10, 100, "CAM {s} ({d},{d})  CLIP {s}  PAT {s}", .{
        debugOnOff(debug_state.render.camera),
        cam.x,
        cam.y,
        debugOnOff(debug_state.render.clipping),
        debugOnOff(debug_state.render.patterns),
    });
    drawDebugLine(10, 110, "RENDER M:{s} S:{s} P:{s} T:{s}", .{
        debugOnOff(debug_state.render.maps),
        debugOnOff(debug_state.render.sprites),
        debugOnOff(debug_state.render.primitives),
        debugOnOff(debug_state.render.text),
    });
    if (debug_state.selectedLayer()) |layer| {
        const display_name = layer.displayName();
        const short_name = display_name[0..@min(display_name.len, 27)];
        drawDebugLine(10, 120, "LAYER {d}/{d} {s} [{s}]", .{
            debug_state.selected_layer + 1,
            debug_state.layer_count,
            short_name,
            debugOnOff(layer.enabled),
        });
    } else {
        drawDebugLine(10, 120, "LAYER none discovered", .{});
    }
}

fn drawDebugCommands() void {
    rect(294, 4, 182, 132, true, 1);
    rect(295, 5, 180, 130, false, 4);
    drawDebugLine(300, 10, "RENDER COMMANDS", .{});
    drawDebugLine(300, 20, "F1  Stats", .{});
    drawDebugLine(300, 30, "F2  This help", .{});
    drawDebugLine(300, 40, "F3  Maps [{s}]", .{debugOnOff(debug_state.render.maps)});
    drawDebugLine(300, 50, "F4  Sprites [{s}]", .{debugOnOff(debug_state.render.sprites)});
    drawDebugLine(300, 60, "F5  Primitives [{s}]", .{
        debugOnOff(debug_state.render.primitives),
    });
    drawDebugLine(300, 70, "F6  Text [{s}]", .{debugOnOff(debug_state.render.text)});
    drawDebugLine(300, 80, "F7  Patterns [{s}]", .{debugOnOff(debug_state.render.patterns)});
    drawDebugLine(300, 90, "F8  Clipping [{s}]", .{debugOnOff(debug_state.render.clipping)});
    drawDebugLine(300, 100, "F9  Camera [{s}]", .{debugOnOff(debug_state.render.camera)});
    drawDebugLine(300, 110, "F10 Next layer", .{});
    drawDebugLine(300, 120, "F11 Toggle  F12 Reset", .{});
}

fn renderDebugOverlay(output: *[W * H]u32) void {
    resetRasterWork();
    const saved_palette = pal;
    const saved_camera = cam;
    const saved_clip = clip;
    const saved_clipping = clipping;
    const saved_pattern = pattern;
    defer {
        pal = saved_palette;
        cam = saved_camera;
        clip = saved_clip;
        clipping = saved_clipping;
        pattern = saved_pattern;
    }
    for (&fb) |*row| @memset(row, 0);
    cam = .{};
    clip = .{};
    clipping = false;
    @memset(&pattern, 0);
    overlayPalette();
    if (debug_state.show_stats) drawDebugStats();
    if (debug_state.show_commands) drawDebugCommands();
    convertFrame(output, false);
}

fn handleDebugCommands() void {
    if (menuKeyPressed(c.SDL_SCANCODE_F1))
        debug_state.show_stats = !debug_state.show_stats;
    if (menuKeyPressed(c.SDL_SCANCODE_F2))
        debug_state.show_commands = !debug_state.show_commands;
    if (menuKeyPressed(c.SDL_SCANCODE_F3))
        debug_state.render.maps = !debug_state.render.maps;
    if (menuKeyPressed(c.SDL_SCANCODE_F4))
        debug_state.render.sprites = !debug_state.render.sprites;
    if (menuKeyPressed(c.SDL_SCANCODE_F5))
        debug_state.render.primitives = !debug_state.render.primitives;
    if (menuKeyPressed(c.SDL_SCANCODE_F6))
        debug_state.render.text = !debug_state.render.text;
    if (menuKeyPressed(c.SDL_SCANCODE_F7))
        debug_state.render.patterns = !debug_state.render.patterns;
    if (menuKeyPressed(c.SDL_SCANCODE_F8))
        debug_state.render.clipping = !debug_state.render.clipping;
    if (menuKeyPressed(c.SDL_SCANCODE_F9))
        debug_state.render.camera = !debug_state.render.camera;
    if (menuKeyPressed(c.SDL_SCANCODE_F10)) debug_state.selectNextLayer();
    if (menuKeyPressed(c.SDL_SCANCODE_F11)) debug_state.toggleSelectedLayer();
    if (menuKeyPressed(c.SDL_SCANCODE_F12)) debug_state.resetRendering();
}

fn updateLuaMemoryStats() void {
    const kibibytes = c.lua_gc(L, c.LUA_GCCOUNT);
    const bytes = c.lua_gc(L, c.LUA_GCCOUNTB);
    debug_state.lua_memory_bytes = @as(u64, @intCast(@max(kibibytes, 0))) * 1024 +
        @as(u64, @intCast(@max(bytes, 0)));
}

fn compositeOpaqueOverlay(base: []u32, overlay: []const u32) void {
    std.debug.assert(base.len == overlay.len);
    for (base, overlay) |*destination, source| {
        // The software UI is intentionally binary-alpha, just like every Lupi
        // sprite. Avoiding interpolation preserves exact indexed pixels.
        if (@as(u8, @truncate(source)) != 0) destination.* = source;
    }
}

fn integerViewport(output_width: i32, output_height: i32) c.SDL_Rect {
    const safe_width = @max(output_width, W);
    const safe_height = @max(output_height, H);
    const scale = @max(@min(@divTrunc(safe_width, W), @divTrunc(safe_height, H)), 1);
    const width = W * scale;
    const height = H * scale;
    return .{
        .x = @divTrunc(output_width - width, 2),
        .y = @divTrunc(output_height - height, 2),
        .w = width,
        .h = height,
    };
}

/// Runs game logic and indexed-framebuffer conversion without VSync or frame
/// pacing. This gives the benchmark a deterministic CPU workload while keeping
/// the interactive runtime unchanged.
fn runBenchmark(path: []const u8, frame_count: usize) !void {
    if (frame_count == 0) return error.InvalidFrameCount;
    if (c.SDL_Init(c.SDL_INIT_TIMER) != 0) return error.SdlInit;
    defer c.SDL_Quit();

    try load(path);
    defer closeGameLua();

    // Warm Lua and asset caches before the measured interval.
    for (0..120) |_| {
        if (!update()) return error.LuaUpdate;
        @memset(&fb, [_]u8{0} ** W);
    }

    var output: [W * H]u32 = undefined;
    var checksum: u64 = 0;
    const start = c.SDL_GetPerformanceCounter();
    for (0..frame_count) |frame| {
        if (!update()) return error.LuaUpdate;
        convertFrame(&output, false);
        checksum +%= output[(frame *% 8191) % output.len];
        @memset(&fb, [_]u8{0} ** W);
    }
    const elapsed = c.SDL_GetPerformanceCounter() - start;
    const frequency = c.SDL_GetPerformanceFrequency();
    const elapsed_ms = @as(f64, @floatFromInt(elapsed)) * 1000.0 /
        @as(f64, @floatFromInt(frequency));
    std.debug.print("benchmark mode={s} frames={d} elapsed_ms={d:.3} us_per_frame={d:.3} fps={d:.1} checksum={x}\n", .{
        @tagName(builtin.mode),
        frame_count,
        elapsed_ms,
        elapsed_ms * 1000.0 / @as(f64, @floatFromInt(frame_count)),
        @as(f64, @floatFromInt(frame_count)) * 1000.0 / elapsed_ms,
        checksum,
    });
}

fn captureFrame(path: []const u8, frame_count: usize, output_path: []const u8) !void {
    if (frame_count == 0) return error.InvalidFrameCount;
    if (c.SDL_Init(c.SDL_INIT_TIMER) != 0) return error.SdlInit;
    defer c.SDL_Quit();
    try load(path);
    defer closeGameLua();
    for (0..frame_count) |frame| {
        if (!update()) return error.LuaUpdate;
        if (frame + 1 < frame_count) @memset(&fb, [_]u8{0} ** W);
    }

    var output_z: [2048]u8 = undefined;
    const destination = std.fmt.bufPrintZ(&output_z, "{s}", .{output_path}) catch return error.InvalidOutputPath;
    const file = c.fopen(destination.ptr, "wb") orelse return error.OutputOpenFailed;
    defer _ = c.fclose(file);
    var header: [64]u8 = undefined;
    const header_data = std.fmt.bufPrint(&header, "P6\n{d} {d}\n255\n", .{ W, H }) catch return error.OutputWriteFailed;
    if (c.fwrite(header_data.ptr, 1, header_data.len, file) != header_data.len) return error.OutputWriteFailed;
    var row: [W * 3]u8 = undefined;
    for (0..H) |y| {
        for (0..W) |x| {
            const value = paletteColor(fb[y][x], false);
            row[x * 3] = value.r;
            row[x * 3 + 1] = value.g;
            row[x * 3 + 2] = value.b;
        }
        if (c.fwrite(&row, 1, row.len, file) != row.len) return error.OutputWriteFailed;
    }
    std.debug.print("frame capturado: {s} ({d} quadros)\n", .{ output_path, frame_count });
}

fn countRegion(x: usize, y: usize, width: usize, height: usize) usize {
    var count: usize = 0;
    for (y..y + height) |row| {
        for (x..x + width) |column| {
            if (fb[row][column] != 0) count += 1;
        }
    }
    return count;
}

fn verifyParityCore() !void {
    resetGameState();
    setPaletteEntry(0, 0x7fff);
    setPaletteEntry(1, 0x001f);
    setPaletteEntry(2, 0x03e0);
    setPaletteEntry(3, 0x7c00);
    browser_notice = .searching;
    if (browserNoticePhase() != .loading) return error.BrowserLoadingStatusMismatch;
    browser_notice = .demos_updated;
    if (browserNoticePhase() != .finished) return error.BrowserFinishedStatusMismatch;
    browser_notice = .network_failed;
    if (browserNoticePhase() != .failed) return error.BrowserFailedStatusMismatch;
    browser_notice = .none;

    const transparent = paletteColor(0, false);
    if (transparent.r != 0 or transparent.g != 0 or transparent.b != 0 or transparent.a != 0)
        return error.PaletteZeroMismatch;
    if (!std.meta.eql(pal[1], Color{ .r = 0, .g = 0, .b = 255, .a = 255 }) or
        !std.meta.eql(pal[2], Color{ .r = 0, .g = 255, .b = 0, .a = 255 }) or
        !std.meta.eql(pal[3], Color{ .r = 255, .g = 0, .b = 0, .a = 255 }))
        return error.PaletteOrderMismatch;
    for (0..0x8000) |packed_value| {
        setPaletteEntry(255, @intCast(packed_value));
        const red: u8 = @intCast((packed_value >> 10) & 31);
        const green: u8 = @intCast((packed_value >> 5) & 31);
        const blue: u8 = @intCast(packed_value & 31);
        const expected_color = Color{
            .r = (red << 3) | (red >> 2),
            .g = (green << 3) | (green >> 2),
            .b = (blue << 3) | (blue >> 2),
            .a = 255,
        };
        if (!std.meta.eql(pal[255], expected_color)) return error.ExhaustivePaletteMismatch;
    }
    if (color(-1) != 255 or color(256) != 0) return error.ColorIndexWrapMismatch;
    if (downloadChunkSize(0, 2, 3) != 6 or
        downloadChunkSize(host_download_bytes_max - 1, 1, 2) != null or
        downloadChunkSize(0, std.math.maxInt(usize), 2) != null)
    {
        return error.DownloadBoundMismatch;
    }

    rect(10, 10, 20, 12, false, 1);
    circle(60, 30, 6, true, 1, true, 1);
    tri(.{ 90, 20 }, .{ 100, 20 }, .{ 110, 20 }, 1);
    drawAsciiText("Aa", 120, 10, 1);
    if (countRegion(10, 10, 20, 12) != 60) return error.RectangleRasterMismatch;
    if (countRegion(54, 24, 13, 13) != 129) return error.CircleRasterMismatch;
    if (countRegion(90, 20, 21, 1) != 21) return error.TriangleRasterMismatch;
    if (countRegion(120, 10, 5, 8) != 18 or countRegion(126, 10, 5, 8) != 14)
        return error.FontRasterMismatch;

    for (&fb) |*row| @memset(row, 0);
    rect(10, 10, 0, 3, false, 1);
    if (countRegion(9, 10, 2, 3) != 6) return error.DegenerateRectangleMismatch;

    cam = .{ .x = 8, .y = 9 };
    clip = .{ .x = 1, .y = 2, .w = 3, .h = 4 };
    clipping = true;
    pattern[0] = 0xff;
    ticks = 42;
    resetGameState();
    if (cam.x != 0 or cam.y != 0 or clipping or clip.w != 0 or pattern[0] != 0 or ticks != 0)
        return error.StateResetMismatch;

    const exact_viewport = integerViewport(960, 540);
    if (exact_viewport.x != 0 or exact_viewport.y != 0 or exact_viewport.w != 960 or exact_viewport.h != 540)
        return error.IntegerViewportMismatch;
    const letterboxed_viewport = integerViewport(1000, 600);
    if (letterboxed_viewport.x != 20 or letterboxed_viewport.y != 30 or letterboxed_viewport.w != 960 or letterboxed_viewport.h != 540)
        return error.LetterboxMismatch;

    cam = .{ .x = 123, .y = -45 };
    clip = .{ .x = 1, .y = 2, .w = 3, .h = 4 };
    clipping = true;
    pattern = .{ 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55 };
    const saved_palette = pal;
    const saved_camera = cam;
    const saved_clip = clip;
    const saved_pattern = pattern;
    var overlay: [W * H]u32 = undefined;
    renderQuitOverlay(&overlay);
    if (!std.meta.eql(saved_palette, pal) or !std.meta.eql(saved_camera, cam) or
        !std.meta.eql(saved_clip, clip) or !clipping or !std.meta.eql(saved_pattern, pattern))
        return error.OverlayStateLeak;
    if (@as(u8, @truncate(overlay[0])) != 0 or @as(u8, @truncate(overlay[70 * W + 42])) != 255)
        return error.OverlayAlphaMismatch;
    var base_probe = [2]u32{ packColor(.{ .r = 255, .g = 0, .b = 0, .a = 255 }), packColor(.{ .r = 0, .g = 0, .b = 255, .a = 255 }) };
    const overlay_probe = [2]u32{ packColor(.{ .r = 0, .g = 255, .b = 0, .a = 0 }), packColor(.{ .r = 255, .g = 255, .b = 255, .a = 255 }) };
    compositeOpaqueOverlay(&base_probe, &overlay_probe);
    if (base_probe[0] != packColor(.{ .r = 255, .g = 0, .b = 0, .a = 255 }) or
        base_probe[1] != packColor(.{ .r = 255, .g = 255, .b = 255, .a = 255 }))
        return error.OverlayCompositionMismatch;
    std.debug.print("upstream parity core: pass\n", .{});
}

// -----------------------------------------------------------------------------
// SDL application lifecycle

fn verifySettingsRoundTrip() !void {
    if (c.SDL_Init(0) != 0) return error.SdlInit;
    defer c.SDL_Quit();
    const original = Settings.load();
    var probe = Settings{};
    probe.language = .es;
    probe.bindings.keyboard[@intFromEnum(input_mod.Action.primary)][0] = c.SDL_SCANCODE_Q;
    if (!probe.save()) return error.SettingsSaveFailed;
    var restored = false;
    defer {
        if (!restored) _ = original.save();
    }
    const reloaded = Settings.load();
    if (!std.meta.eql(probe, reloaded)) return error.SettingsRoundTripFailed;
    if (!original.save()) return error.SettingsRestoreFailed;
    restored = true;

    var input_probe = Input{};
    _ = input_probe.bindKeyboard(.up, 0, c.SDL_SCANCODE_Q);
    input_probe.keys[c.SDL_SCANCODE_Q] = true;
    if (!input_probe.held(c.SDL_CONTROLLER_BUTTON_DPAD_UP, 0)) return error.KeyboardBindingFailed;
    if (input_probe.keyboardConflict(c.SDL_SCANCODE_S, .up, 0) != .down) return error.KeyboardConflictFailed;
    _ = input_probe.bindGamepad(.primary, c.SDL_CONTROLLER_BUTTON_GUIDE);
    input_probe.buttons[0][c.SDL_CONTROLLER_BUTTON_GUIDE] = true;
    if (!input_probe.held(c.SDL_CONTROLLER_BUTTON_A, 0)) return error.GamepadBindingFailed;
    std.debug.print("settings round-trip: pass\n", .{});
}

/// Verify the final SDL blend stage, which a framebuffer-only golden cannot
/// observe. A transparent red texel must reveal the black upstream backing;
/// the neighboring opaque green texel must survive unchanged.
fn verifySdlCompositor() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) return error.SdlInit;
    defer c.SDL_Quit();
    const surface = c.SDL_CreateRGBSurfaceWithFormat(0, 2, 1, 32, c.SDL_PIXELFORMAT_RGBA8888) orelse return error.SdlSurface;
    defer c.SDL_FreeSurface(surface);
    const renderer = c.SDL_CreateSoftwareRenderer(surface) orelse return error.SdlRenderer;
    defer c.SDL_DestroyRenderer(renderer);
    const texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STREAMING, 2, 1) orelse return error.SdlTexture;
    defer c.SDL_DestroyTexture(texture);
    _ = c.SDL_SetTextureBlendMode(texture, c.SDL_BLENDMODE_BLEND);
    const source = [2]u32{
        packColor(.{ .r = 255, .g = 0, .b = 0, .a = 0 }),
        packColor(.{ .r = 0, .g = 255, .b = 0, .a = 255 }),
    };
    _ = c.SDL_UpdateTexture(texture, null, &source, 2 * @sizeOf(u32));
    _ = c.SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    if (c.SDL_RenderClear(renderer) != 0) return error.SdlRender;
    if (c.SDL_RenderCopy(renderer, texture, null, null) != 0) return error.SdlRender;
    var readback: [2]u32 = undefined;
    if (c.SDL_RenderReadPixels(renderer, null, c.SDL_PIXELFORMAT_RGBA8888, &readback, 2 * @sizeOf(u32)) != 0)
        return error.SdlReadback;
    if (readback[0] != packColor(.{ .r = 0, .g = 0, .b = 0, .a = 255 }) or
        readback[1] != packColor(.{ .r = 0, .g = 255, .b = 0, .a = 255 }))
        return error.SdlBlendMismatch;
    std.debug.print("SDL compositor parity: pass\n", .{});
}

fn printUsage() void {
    std.debug.print(
        \\Usage:
        \\  elis [GAME_DIRECTORY|GAME.lupi]
        \\  elis --fetch-demos|--update-demos|--lupi-constraints
        \\  elis --benchmark GAME_DIRECTORY FRAMES
        \\  elis --screenshot GAME_DIRECTORY FRAMES OUTPUT.ppm
        \\
    , .{});
}

fn printLupiConstraints() void {
    std.debug.print(
        \\LUPI_CONSTRAINTS_V1
        \\lua=5.4
        \\resolution=480x270
        \\frame_rate_target_hz=60
        \\palette=256_rgb555
        \\framebuffer_bytes={d}
        \\esp32_s3_clock_mhz=240
        \\esp32_flash_bytes={d}
        \\archive_entries_max={d}
        \\host_demo_download_bytes_max={d}
        \\esp32_psram_bytes={d}
        \\rp2350_clock_mhz=345
        \\discrete_gpu=none
        \\player_slots=3
        \\tile_id_max=1023
        \\tileset_pixels_max={d}
        \\raster_work_items_max={d}
        \\runtime_map_layers_max={d}
        \\map_layer_limit=not_published
        \\workshop_visual_layers={d}
        \\workshop_lua_data_entries_max={d}
        \\workshop_lua_source_bytes_max={d}
        \\lua_heap_bytes_max={d}
        \\
    , .{
        @sizeOf(@TypeOf(fb)),
        lupi_flash_bytes,
        lupi_archive_entries_max,
        host_download_bytes_max,
        lupi_psram_bytes,
        lupi_tileset_pixels_max,
        raster_work_max,
        debug_mod.layer_count_max,
        lupi_profile.workshop_visual_layers,
        lupi_profile.lua_data_entries_max,
        lupi_profile.lua_source_bytes_max,
        lupi_lua_heap_bytes_max,
    });
}

pub fn main(init: std.process.Init) !void {
    for (&fb) |*r| @memset(r, 0);
    defer clearDemos();
    c.SDL_SetMainReady();
    var iterator = try std.process.Args.Iterator.initAllocator(init.minimal.args, A);
    defer iterator.deinit();
    var arguments: std.ArrayList([*:0]const u8) = .empty;
    defer arguments.deinit(A);
    while (iterator.next()) |argument| try arguments.append(A, argument.ptr);
    const args = arguments.items;
    if (args.len == 2 and std.mem.eql(u8, std.mem.span(args[1]), "--self-test-parity")) return verifyParityCore();
    if (args.len == 2 and std.mem.eql(u8, std.mem.span(args[1]), "--self-test-settings")) return verifySettingsRoundTrip();
    if (args.len == 2 and std.mem.eql(u8, std.mem.span(args[1]), "--self-test-compositor")) return verifySdlCompositor();
    if (args.len == 2 and std.mem.eql(u8, std.mem.span(args[1]), "--lupi-constraints")) return printLupiConstraints();
    if (args.len == 5 and std.mem.eql(u8, std.mem.span(args[1]), "--screenshot")) {
        const frame_count = std.fmt.parseUnsigned(usize, std.mem.span(args[3]), 10) catch return error.InvalidFrameCount;
        return captureFrame(std.mem.span(args[2]), frame_count, std.mem.span(args[4]));
    }
    if (args.len == 2 and (std.mem.eql(u8, std.mem.span(args[1]), "--fetch-demos") or std.mem.eql(u8, std.mem.span(args[1]), "--update-demos"))) {
        const replace_existing = std.mem.eql(u8, std.mem.span(args[1]), "--update-demos");
        const success = updateCatalog(replace_existing);
        std.debug.print("{s}\n", .{localizedBrowserNotice(localization.get(.pt_br))});
        if (!success) return error.DemoUpdateFailed;
        return;
    }
    if (args.len == 4 and std.mem.eql(u8, std.mem.span(args[1]), "--benchmark")) {
        const frame_count = std.fmt.parseUnsigned(usize, std.mem.span(args[3]), 10) catch {
            std.debug.print("Quantidade de frames invalida: {s}\n", .{std.mem.span(args[3])});
            return;
        };
        return runBenchmark(std.mem.span(args[2]), frame_count);
    }
    if (args.len > 2) {
        printUsage();
        return;
    }
    const browser_mode_at_start = args.len == 1;
    const requested: []const u8 = if (args.len > 1) std.mem.span(args[1]) else "example";
    if (std.mem.eql(u8, requested, "--help") or std.mem.eql(u8, requested, "-h")) {
        printUsage();
        return;
    }
    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO | c.SDL_INIT_GAMECONTROLLER | c.SDL_INIT_JOYSTICK) != 0) return error.SdlInit;
    defer c.SDL_Quit();
    settings_state = Settings.load();
    input_state.setBindings(settings_state.bindings);
    _ = audio_state.init();
    defer audio_state.deinit();
    var browser_mode = browser_mode_at_start;
    var loaded = false;
    var active_archive: ?[]u8 = null;
    defer unloadGame(&loaded, &active_archive);
    if (browser_mode) {
        discoverDemos();
    } else {
        const is_archive = endsWith(requested, ".lupi");
        if (is_archive) active_archive = extractArchive(requested, lupi_flash_bytes) orelse
            return error.InvalidLupiArchive;
        const game = active_archive orelse requested;
        try load(game);
        loaded = true;
    }
    _ = c.SDL_SetHint(c.SDL_HINT_RENDER_SCALE_QUALITY, "0");
    input_state.init();
    defer input_state.deinit();
    c.SDL_StartTextInput();
    defer c.SDL_StopTextInput();
    const win = c.SDL_CreateWindow("ELIS  |  Editor for Lupi with Integrated Simulator", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, W * 2, H * 2, c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE | c.SDL_WINDOW_ALLOW_HIGHDPI) orelse return error.SdlWindow;
    defer c.SDL_DestroyWindow(win);
    input_state.setFocused(c.SDL_GetWindowFlags(win) & c.SDL_WINDOW_INPUT_FOCUS != 0);
    c.SDL_SetWindowMinimumSize(win, W, H);
    const ren = c.SDL_CreateRenderer(win, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC) orelse
        c.SDL_CreateRenderer(win, -1, c.SDL_RENDERER_SOFTWARE) orelse return error.SdlRenderer;
    defer c.SDL_DestroyRenderer(ren);
    const tex = c.SDL_CreateTexture(ren, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STREAMING, W, H) orelse return error.SdlTexture;
    defer c.SDL_DestroyTexture(tex);
    _ = c.SDL_SetTextureBlendMode(tex, c.SDL_BLENDMODE_BLEND);
    var out: [W * H]u32 = undefined;
    var last_game_frame: [W * H]u32 = .{0} ** (W * H);
    var overlay_frame: [W * H]u32 = undefined;
    var run = true;
    var selected_demo: usize = 0;
    var catalog_update_pending = false;
    const performance_frequency = c.SDL_GetPerformanceFrequency();
    const target_frame_counts = @max(performance_frequency / 60, 1);
    while (run) {
        const frame_start = c.SDL_GetPerformanceCounter();
        var simulation_updated = false;
        var update_counts: u64 = 0;
        debug_state.beginFrame();
        var browser_drawn = false;
        if (browser_mode and catalog_update_pending) {
            catalog_update_pending = false;
            _ = updateCatalog(true);
            discoverDemos();
            selected_demo = @min(selected_demo, demo_count + 2);
        }
        input_state.beginFrame();
        var e: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&e) != 0) {
            if (e.type == c.SDL_QUIT) run = false;
            input_state.handleEvent(&e);
        }
        input_state.refreshAxes();
        if (!browser_mode and !quit_dialog) handleDebugCommands();
        if (browser_mode) {
            var update_accepted = false;
            var opened_quit = false;
            const handled_settings = settings_page != .none;
            if (settings_page == .language) {
                if (menuKeyPressed(c.SDL_SCANCODE_ESCAPE) or input_state.cancel_pressed) {
                    settings_page = .none;
                    language_save_failed = false;
                } else {
                    if (menuKeyPressed(c.SDL_SCANCODE_UP) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_UP)) {
                        language_selection = if (language_selection == 0) localization.all_languages.len - 1 else language_selection - 1;
                    }
                    if (menuKeyPressed(c.SDL_SCANCODE_DOWN) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_DOWN)) {
                        language_selection = (language_selection + 1) % localization.all_languages.len;
                    }
                    if (input_state.confirm_pressed) {
                        settings_state.language = localization.all_languages[language_selection];
                        language_save_failed = !settings_state.save();
                        if (!language_save_failed) settings_page = .none;
                    }
                }
            } else if (settings_page == .controls) {
                if (controls_capture) {
                    if (menuKeyPressed(c.SDL_SCANCODE_ESCAPE)) {
                        controls_capture = false;
                        controls_capture_armed = false;
                    } else if (!controls_capture_armed) {
                        // Ignore the Enter/A edge that opened the capture box.
                        controls_capture_armed = true;
                    } else if (controls_binding_page < input_mod.keyboard_slot_count) {
                        if (input_state.firstKeyPressed()) |scancode| finishControlCapture(scancode);
                    } else if (input_state.firstButtonPressed()) |button| {
                        finishControlCapture(button);
                    }
                } else if (menuKeyPressed(c.SDL_SCANCODE_ESCAPE) or input_state.cancel_pressed) {
                    settings_page = .none;
                    controls_notice = .none;
                } else {
                    if (menuKeyPressed(c.SDL_SCANCODE_UP) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_UP)) {
                        controls_selection = if (controls_selection == 0) input_mod.action_count - 1 else controls_selection - 1;
                        controls_notice = .none;
                    }
                    if (menuKeyPressed(c.SDL_SCANCODE_DOWN) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_DOWN)) {
                        controls_selection = (controls_selection + 1) % input_mod.action_count;
                        controls_notice = .none;
                    }
                    if (menuKeyPressed(c.SDL_SCANCODE_LEFT) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_LEFT)) {
                        controls_binding_page = if (controls_binding_page == 0) input_mod.keyboard_slot_count else controls_binding_page - 1;
                        controls_notice = .none;
                    }
                    if (menuKeyPressed(c.SDL_SCANCODE_RIGHT) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_RIGHT)) {
                        controls_binding_page = (controls_binding_page + 1) % (input_mod.keyboard_slot_count + 1);
                        controls_notice = .none;
                    }
                    if (menuKeyPressed(c.SDL_SCANCODE_DELETE)) {
                        const action: input_mod.Action = @enumFromInt(controls_selection);
                        if (controls_binding_page < input_mod.keyboard_slot_count) {
                            _ = input_state.bindKeyboard(action, controls_binding_page, input_mod.unbound);
                        } else _ = input_state.bindGamepad(action, input_mod.unbound);
                        persistBindings(.saved);
                    } else if (menuKeyPressed(c.SDL_SCANCODE_R)) {
                        input_state.resetBindings();
                        persistBindings(.defaults_restored);
                    } else if (input_state.confirm_pressed) {
                        controls_capture = true;
                        controls_capture_armed = false;
                        controls_notice = .none;
                    }
                }
            } else if (!update_dialog and !quit_dialog and (menuKeyPressed(c.SDL_SCANCODE_U) or menuPressed(c.SDL_CONTROLLER_BUTTON_Y))) {
                update_dialog = true;
                browser_notice = .none;
            }
            if (!handled_settings and !update_dialog and !quit_dialog and (menuKeyPressed(c.SDL_SCANCODE_ESCAPE) or input_state.cancel_pressed)) {
                quit_selection = 0;
                quit_dialog = true;
                opened_quit = true;
            }
            if (!handled_settings and update_dialog and (menuKeyPressed(c.SDL_SCANCODE_ESCAPE) or input_state.cancel_pressed)) update_dialog = false;
            if (!handled_settings and update_dialog and input_state.confirm_pressed) {
                update_dialog = false;
                update_accepted = true;
                browser_notice = .searching;
                catalog_update_pending = true;
            }
            if (!handled_settings and quit_dialog) {
                if (!opened_quit and (menuKeyPressed(c.SDL_SCANCODE_ESCAPE) or input_state.cancel_pressed)) {
                    quit_dialog = false;
                    browser_mode = true;
                }
                if (menuKeyPressed(c.SDL_SCANCODE_UP) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_UP)) quit_selection = if (quit_selection == 0) 1 else 0;
                if (menuKeyPressed(c.SDL_SCANCODE_DOWN) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_DOWN)) quit_selection = if (quit_selection == 1) 0 else 1;
                if (input_state.confirm_pressed) {
                    if (quit_selection == 0) quit_dialog = false else run = false;
                }
            } else if (!handled_settings and !update_dialog and (menuKeyPressed(c.SDL_SCANCODE_UP) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_UP))) {
                selected_demo = if (selected_demo == 0) demo_count + 2 else selected_demo - 1;
            }
            if (!handled_settings and !quit_dialog and !update_dialog and (menuKeyPressed(c.SDL_SCANCODE_DOWN) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_DOWN))) {
                selected_demo = (selected_demo + 1) % (demo_count + 3);
            }
            if (!handled_settings and !update_accepted and !update_dialog and !quit_dialog and input_state.confirm_pressed) {
                if (selected_demo == demo_count) {
                    settings_page = .language;
                    language_selection = @intFromEnum(settings_state.language);
                    language_save_failed = false;
                } else if (selected_demo == demo_count + 1) {
                    settings_page = .controls;
                    controls_notice = .none;
                } else if (selected_demo == demo_count + 2) {
                    quit_selection = 0;
                    quit_dialog = true;
                } else if (demo_count > 0) {
                    const requested_demo = demos[selected_demo].path;
                    const is_archive = endsWith(requested_demo, ".lupi");
                    unloadGame(&loaded, &active_archive);
                    if (is_archive) {
                        active_archive = extractArchive(
                            requested_demo,
                            lupi_flash_bytes,
                        );
                        if (active_archive == null) {
                            browser_notice = .demo_prepare_failed;
                            continue;
                        }
                    }
                    const game = active_archive orelse requested_demo;
                    load(game) catch {
                        unloadGame(&loaded, &active_archive);
                        browser_notice = .demo_prepare_failed;
                        continue;
                    };
                    input_state.clearText();
                    ticks = 0;
                    loaded = true;
                    browser_mode = false;
                }
            }
            switch (settings_page) {
                .none => {
                    drawBrowser(selected_demo);
                    if (quit_dialog) drawQuitDialog(0);
                },
                .language => drawLanguageScreen(),
                .controls => drawControlsScreen(),
            }
            browser_drawn = true;
        } else {
            var opened_quit = false;
            // Face B is a game action (BTN_X), so only Escape or Select opens
            // the application menu while a demo is running.
            if (!quit_dialog and (menuKeyPressed(c.SDL_SCANCODE_ESCAPE) or menuPressed(c.SDL_CONTROLLER_BUTTON_BACK))) {
                quit_selection = 0;
                quit_dialog = true;
                opened_quit = true;
            }
            if (quit_dialog) {
                if (!opened_quit and (menuKeyPressed(c.SDL_SCANCODE_ESCAPE) or input_state.cancel_pressed)) {
                    quit_dialog = false;
                }
                if (menuKeyPressed(c.SDL_SCANCODE_UP) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_UP)) quit_selection = if (quit_selection == 0) 1 else 0;
                if (menuKeyPressed(c.SDL_SCANCODE_DOWN) or menuPressed(c.SDL_CONTROLLER_BUTTON_DPAD_DOWN)) quit_selection = if (quit_selection == 1) 0 else 1;
                if (input_state.confirm_pressed) {
                    if (quit_selection == 0) {
                        unloadGame(&loaded, &active_archive);
                        discoverDemos();
                        selected_demo = @min(selected_demo, demo_count + 2);
                        quit_dialog = false;
                        browser_mode = true;
                        input_state.clearText();
                    } else run = false;
                }
            } else {
                const update_start = c.SDL_GetPerformanceCounter();
                _ = update();
                update_counts = c.SDL_GetPerformanceCounter() -% update_start;
                simulation_updated = true;
            }
        }
        debug_state.captureDrawCounters();
        var ww: c_int = 0;
        var wh: c_int = 0;
        _ = c.SDL_GetRendererOutputSize(ren, &ww, &wh);
        debug_state.setViewport(ww, wh);
        if (browser_mode) {
            // Returning from a running demo can switch modes after the browser
            // branch has already been skipped for this frame.
            if (!browser_drawn) drawBrowser(selected_demo);
            convertFrame(&out, true);
        } else if (quit_dialog) {
            out = last_game_frame;
            renderQuitOverlay(&overlay_frame);
            compositeOpaqueOverlay(&out, &overlay_frame);
        } else {
            convertFrame(&out, false);
            last_game_frame = out;
            if (debug_state.show_stats or debug_state.show_commands) {
                renderDebugOverlay(&overlay_frame);
                compositeOpaqueOverlay(&out, &overlay_frame);
            }
        }
        _ = c.SDL_UpdateTexture(tex, null, &out, W * @sizeOf(u32));
        var dst = integerViewport(ww, wh);
        _ = c.SDL_SetRenderDrawColor(ren, 13, 16, 24, 255);
        _ = c.SDL_RenderClear(ren);
        // Upstream composites palette index zero over BLACK. Keep the chrome
        // letterbox dark, but paint the exact game viewport black first.
        _ = c.SDL_SetRenderDrawColor(ren, 0, 0, 0, 255);
        _ = c.SDL_RenderFillRect(ren, &dst);
        _ = c.SDL_RenderCopy(ren, tex, null, &dst);
        _ = c.SDL_RenderPresent(ren);
        const work_end = c.SDL_GetPerformanceCounter();
        last_work_ms = @as(f64, @floatFromInt(work_end -% frame_start)) * 1000.0 /
            @as(f64, @floatFromInt(performance_frequency));
        var frame_end = work_end;
        const work_counts = work_end -% frame_start;
        if (work_counts < target_frame_counts) {
            const remaining_counts = target_frame_counts - work_counts;
            const remaining_ms = remaining_counts * 1000 / performance_frequency;
            if (remaining_ms > 1) c.SDL_Delay(@intCast(remaining_ms - 1));
            while (c.SDL_GetPerformanceCounter() -% frame_start < target_frame_counts)
                std.atomic.spinLoopHint();
            frame_end = c.SDL_GetPerformanceCounter();
        }
        last_frame_ms = @as(f64, @floatFromInt(frame_end -% frame_start)) * 1000.0 /
            @as(f64, @floatFromInt(performance_frequency));
        const sampled = debug_state.finishFrame(
            frame_start,
            work_end,
            frame_end,
            update_counts,
            simulation_updated,
            performance_frequency,
        );
        if (sampled and loaded) updateLuaMemoryStats();
        @memset(&fb, [_]u8{0} ** W);
    }
}
