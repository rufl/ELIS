const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const native_cmd = b.addSystemCommand(&.{ "bash", "scripts/build_native.sh" });
    native_cmd.addArg(@tagName(optimize));
    b.getInstallStep().dependOn(&native_cmd.step);

    const run = b.addSystemCommand(&.{"zig-out/bin/elis"});
    run.step.dependOn(&native_cmd.step);
    if (b.args) |args| run.addArgs(args);
    const step = b.step("run", "Run ELIS");
    step.dependOn(&run.step);

    const native = b.step("native", "Build the native binary with the portable linker workaround");
    native.dependOn(&native_cmd.step);
}
