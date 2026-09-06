//! Shared C ABI declarations.
//!
//! Keeping the import in one module guarantees that every Zig subsystem uses
//! the same generated C types. Separate `@cImport` blocks can produce types
//! that look identical but are not interchangeable at module boundaries.
const std = @import("std");
pub const windows = @import("builtin").os.tag == .windows;

pub const c = @cImport({
    @cDefine("SDL_MAIN_HANDLED", "1");
    if (windows) {
        @cDefine("WIN32_LEAN_AND_MEAN", "1");
        @cInclude("windows.h");
        @cInclude("direct.h");
        @cInclude("process.h");
    }
    @cInclude("SDL2/SDL.h");
    @cInclude("lua.h");
    @cInclude("lauxlib.h");
    @cInclude("lualib.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
    @cInclude("dirent.h");
    @cInclude("zip.h");
    @cInclude("curl/curl.h");
    @cInclude("sndfile.h");
});

pub fn mkdir(path: [*:0]const u8, mode: c_uint) c_int {
    return if (windows) c._mkdir(path) else c.mkdir(path, mode);
}

pub const EntryKind = enum { regular, directory, invalid };

/// Never follow symlinks, junctions, or other Windows reparse points.
pub fn entryKind(path: [*:0]const u8) EntryKind {
    if (windows) {
        const attributes = c.GetFileAttributesA(path);
        if (attributes == c.INVALID_FILE_ATTRIBUTES or
            attributes & (c.FILE_ATTRIBUTE_REPARSE_POINT | c.FILE_ATTRIBUTE_DEVICE) != 0) return .invalid;
        return if (attributes & c.FILE_ATTRIBUTE_DIRECTORY != 0) .directory else .regular;
    }
    var info: c.struct_stat = undefined;
    if (c.lstat(path, &info) != 0) return .invalid;
    return switch (info.st_mode & c.S_IFMT) {
        c.S_IFREG => .regular,
        c.S_IFDIR => .directory,
        else => .invalid,
    };
}

/// Remove a reparse point itself, including directory junctions; never its target.
pub fn remove(path: [*:0]const u8) c_int {
    if (windows) {
        const attributes = c.GetFileAttributesA(path);
        if (attributes != c.INVALID_FILE_ATTRIBUTES and attributes & c.FILE_ATTRIBUTE_DIRECTORY != 0) {
            return if (c.RemoveDirectoryA(path) != 0) 0 else -1;
        }
    }
    return c.remove(path);
}

/// Creates a private, unpredictable directory using the host temporary location.
pub fn temporaryDirectory(buffer: []u8, prefix: []const u8) ?[:0]u8 {
    if (!windows) {
        const base = if (c.getenv("TMPDIR")) |value| std.mem.span(value) else "/tmp";
        const path = std.fmt.bufPrintZ(buffer, "{s}/{s}-XXXXXX", .{ base, prefix }) catch return null;
        _ = c.mkdtemp(path.ptr) orelse return null;
        return path;
    }
    var base_buffer: [2048]u8 = undefined;
    const length = c.GetTempPathA(base_buffer.len, &base_buffer);
    if (length == 0 or length >= base_buffer.len) return null;
    // Upstream codec modules use forward slashes for native paths.
    for (base_buffer[0..length]) |*byte| {
        if (byte.* == '\\') byte.* = '/';
    }
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    var random: [16]u8 = undefined;
    threaded.io().randomSecure(&random) catch return null;
    const path = std.fmt.bufPrintZ(buffer, "{s}{s}-{s}", .{
        base_buffer[0..length], prefix, std.fmt.bytesToHex(random, .lower),
    }) catch return null;
    if (c.CreateDirectoryA(path.ptr, null) == 0) return null;
    return path;
}
