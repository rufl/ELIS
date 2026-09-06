//! Portable package names: one spelling must not escape or alias on another host.
const std = @import("std");

pub fn safeComponent(component: []const u8) bool {
    if (component.len == 0 or component[component.len - 1] == '.' or
        component[component.len - 1] == ' ') return false;
    for (component) |byte| {
        if (byte < 32 or std.mem.indexOfScalar(u8, "\\/:*?\"<>|", byte) != null) return false;
    }
    const stem = component[0 .. std.mem.indexOfScalar(u8, component, '.') orelse component.len];
    for ([_][]const u8{ "CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$" }) |device| {
        if (std.ascii.eqlIgnoreCase(stem, device)) return false;
    }
    if (stem.len == 4 and (std.ascii.eqlIgnoreCase(stem[0..3], "COM") or
        std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) and stem[3] >= '1' and stem[3] <= '9') return false;
    // Win32 also reserves superscript 1, 2, and 3 as COM/LPT suffixes.
    if (stem.len == 5 and (std.ascii.eqlIgnoreCase(stem[0..3], "COM") or
        std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) and stem[3] == 0xc2 and
        (stem[4] == 0xb9 or stem[4] == 0xb2 or stem[4] == 0xb3)) return false;
    return true;
}
