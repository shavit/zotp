const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const pkg_base32 = b.addModule("base32", .{
        .root_source_file = b.path("./deps/zig-base32/src/base32.zig"),
    });

    const lib = b.addStaticLibrary(.{
        .name = "totp",
        .root_source_file = b.path("src/totp.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("base32", pkg_base32);
    b.installArtifact(lib);

    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run library unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Add executable
    const exe = b.addExecutable(.{
        .name = "zotp",
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("base32", pkg_base32);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the command line app");
    run_step.dependOn(&run_cmd.step);
}
