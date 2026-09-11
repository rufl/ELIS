//! Windows host adapters for the pinned codec's POSIX shell and file contract.
//! The downloaded run.lua and transformation modules still execute unchanged.
const std = @import("std");
const c = @import("native.zig").c;
const allocator = std.heap.page_allocator;

pub fn install(state: *c.lua_State, output_root: []const u8) bool {
    c.lua_pushcclosure(state, shell, 0);
    c.lua_setglobal(state, "elis_codec_shell");
    _ = c.lua_pushlstring(state, output_root.ptr, output_root.len);
    c.lua_setglobal(state, "elis_codec_output");
    return c.luaL_loadstring(state, adapters) == c.LUA_OK and
        c.lua_pcallk(state, 0, 0, 0, 0, null) == c.LUA_OK;
}

fn shell(state: ?*c.lua_State) callconv(.c) c_int {
    const lua = state orelse return 0;
    var length: usize = 0;
    const command = c.lua_tolstring(lua, 1, &length) orelse return failure(lua, "invalid codec command");
    if (std.mem.indexOfScalar(u8, command[0..length], 0) != null) return failure(lua, "NUL in codec command");
    const bash = if (c.getenv("ELIS_CODEC_BASH")) |value| std.mem.span(value) else "C:/msys64/usr/bin/bash.exe";
    // The optional MSYS2 installation supplies Bash/coreutils; native UCRT64
    // ImageMagick is selected ahead of MSYS tools. Preserve the caller's PATH.
    const script = std.fmt.allocPrint(allocator, "export PATH=\"/ucrt64/bin:/usr/bin:$PATH\"; {s}", .{command[0..length]}) catch
        return failure(lua, "allocating codec command");
    defer allocator.free(script);
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const result = std.process.run(allocator, threaded.io(), .{
        .argv = &.{ bash, "--noprofile", "--norc", "-c", script },
        .stdout_limit = .limited(64 * 1024 * 1024),
        .stderr_limit = .limited(1024 * 1024),
    }) catch |err| {
        std.debug.print("Windows demo conversion requires MSYS2 Bash/coreutils and ImageMagick 7. Set ELIS_CODEC_BASH to bash.exe when not installed at C:/msys64: {s}\n", .{@errorName(err)});
        return failure(lua, @errorName(err));
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    const succeeded = switch (result.term) {
        .exited => |code| code == 0,
        else => false,
    };
    if (!succeeded) {
        std.debug.print("Codec command failed: {s}\n{s}\n", .{ command[0..length], result.stderr });
        return failure(lua, if (result.stderr.len != 0) result.stderr else "codec command failed without diagnostics");
    }
    _ = c.lua_pushlstring(lua, result.stdout.ptr, result.stdout.len);
    return 1;
}

fn failure(state: *c.lua_State, message: []const u8) c_int {
    c.lua_pushnil(state);
    _ = c.lua_pushlstring(state, message.ptr, message.len);
    return 2;
}

const adapters =
    \\local native_open = io.open
    \\io.open = function(path, mode)
    \\  mode = mode or "r"
    \\  if not mode:find("b", 1, true) then mode = mode .. "b" end
    \\  return native_open(path, mode)
    \\end
    \\io.popen = function(command, mode)
    \\  assert(mode == nil or mode == "r" or mode == "rb", "codec only reads process output")
    \\  local output, err = elis_codec_shell(command)
    \\  assert(output, err)
    \\  local stream = assert(io.tmpfile())
    \\  assert(stream:write(output))
    \\  assert(stream:seek("set", 0))
    \\  return stream
    \\end
    \\os.execute = function(command)
    \\  local temporary = elis_codec_output .. "/current_tmp"
    \\  local current = elis_codec_output .. "/current"
    \\  local suffix = " " .. temporary .. " && mv -Tf " .. temporary .. " " .. current
    \\  if command:sub(1, 8) == "ln -sfn " and command:sub(-#suffix) == suffix then
    \\    local release = command:sub(9, #command - #suffix)
    \\    -- Each conversion has a fresh private output root. Publish the same
    \\    -- completed tree as a directory, without Windows symlink privileges.
    \\    assert(os.rename(release, current))
    \\  else
    \\    local output, err = elis_codec_shell(command)
    \\    assert(output, err)
    \\  end
    \\  return true, "exit", 0
    \\end
    \\assert(elis_codec_shell("for tool in magick mkdir cp ls test stat; do command -v \"$tool\" >/dev/null || { printf 'Missing converter tool: %s\\n' \"$tool\" >&2; exit 127; }; done"))
;
