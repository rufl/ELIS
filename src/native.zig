/// Shared C ABI declarations.
///
/// Keeping the import in one module guarantees that every Zig subsystem uses
/// the same generated C types. Separate `@cImport` blocks can produce types
/// that look identical but are not interchangeable at module boundaries.
pub const c = @cImport({
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
