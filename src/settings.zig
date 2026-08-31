//! Versioned simulator preferences.
//!
//! Parsing is transactional and persistence is atomic. Invalid or incomplete
//! profiles fall back to defaults rather than partially applying bindings.

const std = @import("std");
const c = @import("native.zig").c;
const input = @import("input.zig");
const localization = @import("localization.zig");

const format_version = 1;
const file_name = "settings-v1.ini";
const maximum_file_size = 4096;

/// User preferences are deliberately small and versioned. A damaged or newer
/// file never prevents startup: loading is transactional and falls back to a
/// complete set of defaults unless every required field validates.
pub const Settings = struct {
    language: localization.Language = .pt_br,
    bindings: input.Bindings = input.Bindings.defaults(),

    pub fn load() Settings {
        const result = Settings{};
        var path_buffer: [2048]u8 = undefined;
        const path = settingsPath(&path_buffer) orelse return result;
        const file = c.fopen(path.ptr, "rb") orelse return result;
        defer _ = c.fclose(file);

        var contents: [maximum_file_size]u8 = undefined;
        const length = c.fread(&contents, 1, contents.len, file);
        if (c.ferror(file) != 0 or length == 0 or length == contents.len) return result;

        var candidate = Settings{};
        var found_version = false;
        var found_language = false;
        var found_keyboard = false;
        var found_gamepad = false;
        var lines = std.mem.splitScalar(u8, contents[0..length], '\n');
        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");
            if (std.mem.startsWith(u8, line, "version=")) {
                found_version = (std.fmt.parseUnsigned(u32, line[8..], 10) catch 0) == format_version;
            } else if (std.mem.startsWith(u8, line, "language=")) {
                candidate.language = localization.Language.fromTag(line[9..]) orelse continue;
                found_language = true;
            } else if (std.mem.startsWith(u8, line, "keyboard=")) {
                found_keyboard = parseKeyboard(line[9..], &candidate.bindings);
            } else if (std.mem.startsWith(u8, line, "gamepad=")) {
                found_gamepad = parseGamepad(line[8..], &candidate.bindings);
            }
        }
        if (found_version and found_language and found_keyboard and found_gamepad and validBindings(candidate.bindings)) return candidate;
        return result;
    }

    /// Flushes through the standard atomic-file API before replacing the old
    /// settings. A crash cannot leave a half-written profile or shared temp race.
    pub fn save(self: Settings) bool {
        if (!validBindings(self.bindings)) return saveFailure("invalid bindings");
        var path_buffer: [2048]u8 = undefined;
        const path = settingsPath(&path_buffer) orelse return saveFailure("preference path");
        var contents: [maximum_file_size]u8 = undefined;
        var used: usize = 0;
        if (!append(&contents, &used, "version={d}\nlanguage={s}\nkeyboard=", .{ format_version, self.language.tag() })) return false;
        for (self.bindings.keyboard, 0..) |row, action_index| {
            for (row, 0..) |value, slot| {
                if (!append(&contents, &used, "{s}{d}", .{ if (action_index == 0 and slot == 0) "" else ",", value })) return false;
            }
        }
        if (!append(&contents, &used, "\ngamepad=", .{})) return false;
        for (self.bindings.gamepad, 0..) |value, index| {
            if (!append(&contents, &used, "{s}{d}", .{ if (index == 0) "" else ",", value })) return false;
        }
        if (!append(&contents, &used, "\n", .{})) return false;

        var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();
        var atomic_file = std.Io.Dir.cwd().createFileAtomic(
            io,
            path,
            .{ .replace = true },
        ) catch return saveFailure("open atomic file");
        defer atomic_file.deinit(io);
        atomic_file.file.writeStreamingAll(io, contents[0..used]) catch
            return saveFailure("write settings");
        atomic_file.file.sync(io) catch return saveFailure("flush settings");
        atomic_file.replace(io) catch return saveFailure("replace settings file");
        return true;
    }
};

fn saveFailure(stage: []const u8) bool {
    std.debug.print("Falha ao salvar configuracoes ({s}).\n", .{stage});
    return false;
}

fn settingsPath(buffer: []u8) ?[:0]u8 {
    // Keep the pre-ELIS application identifier so upgrades retain language
    // and control bindings without a platform-specific migration.
    const preference_path = c.SDL_GetPrefPath("lupi-org-br", "lupinho-zig");
    if (preference_path == null) return null;
    defer c.SDL_free(preference_path);
    return std.fmt.bufPrintZ(buffer, "{s}{s}", .{ std.mem.span(preference_path), file_name }) catch null;
}

fn append(buffer: []u8, used: *usize, comptime format: []const u8, args: anytype) bool {
    const written = std.fmt.bufPrint(buffer[used.*..], format, args) catch return false;
    used.* += written.len;
    return true;
}

fn parseKeyboard(value: []const u8, bindings: *input.Bindings) bool {
    var values = std.mem.splitScalar(u8, value, ',');
    var count: usize = 0;
    while (values.next()) |part| : (count += 1) {
        if (count >= input.action_count * input.keyboard_slot_count) return false;
        const parsed = std.fmt.parseInt(c_int, part, 10) catch return false;
        bindings.keyboard[count / input.keyboard_slot_count][count % input.keyboard_slot_count] = parsed;
    }
    return count == input.action_count * input.keyboard_slot_count;
}

fn parseGamepad(value: []const u8, bindings: *input.Bindings) bool {
    var values = std.mem.splitScalar(u8, value, ',');
    var count: usize = 0;
    while (values.next()) |part| : (count += 1) {
        if (count >= input.action_count) return false;
        bindings.gamepad[count] = std.fmt.parseInt(c_int, part, 10) catch return false;
    }
    return count == input.action_count;
}

fn validBindings(bindings: input.Bindings) bool {
    var keyboard_seen: [input.scancode_count]bool = .{false} ** input.scancode_count;
    for (bindings.keyboard) |row| {
        for (row) |value| {
            if (value == input.unbound) continue;
            if (!input.validScancode(value) or keyboard_seen[@intCast(value)]) return false;
            keyboard_seen[@intCast(value)] = true;
        }
    }
    var gamepad_seen: [input.button_count]bool = .{false} ** input.button_count;
    for (bindings.gamepad) |value| {
        if (value == input.unbound) continue;
        if (!input.validGamepadButton(value) or gamepad_seen[@intCast(value)]) return false;
        gamepad_seen[@intCast(value)] = true;
    }
    return true;
}
