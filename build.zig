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

    const studio_run = b.addSystemCommand(&.{"zig-out/bin/elis-studio"});
    studio_run.step.dependOn(&native_cmd.step);
    if (b.args) |args| studio_run.addArgs(args);
    const studio = b.step("studio", "Open the native ELIS map and level editor");
    studio.dependOn(&studio_run.step);

    const tests_cmd = b.addSystemCommand(&.{ "bash", "scripts/test_studio.sh" });
    const tests = b.step("test", "Run deterministic editor and instrumentation unit tests");
    tests.dependOn(&tests_cmd.step);

    const studio_smoke_cmd = b.addSystemCommand(&.{ "bash", "scripts/studio_smoke.sh" });
    const studio_smoke = b.step("studio-smoke", "Run native editor save/export/reload smoke");
    studio_smoke.dependOn(&studio_smoke_cmd.step);

    const verify_cmd = b.addSystemCommand(&.{ "bash", "scripts/verify.sh" });
    const verify = b.step("verify", "Run ELIS simulator and Studio verification matrix");
    verify.dependOn(&verify_cmd.step);
}
