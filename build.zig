const std = @import("std");
const cmdtest = @import("cmdtest");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zli_dep = b.dependency("zli", .{ .target = target, .optimize = optimize });
    const mecha_dep = b.dependency("mecha", .{ .target = target, .optimize = optimize });
    const cmdtest_dep = b.dependency("cmdtest", .{});

    {
        const exe_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        const exe = b.addExecutable(.{
            .name = "zsat",
            .root_module = exe_mod,
        });

        exe.root_module.addImport("zli", zli_dep.module("zli"));
        exe.root_module.addImport("mecha", mecha_dep.module("mecha"));
        exe.root_module.addImport("cmdtest", cmdtest_dep.module("cmdtest"));

        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        // This allows the user to pass arguments to the application in the build
        // command itself, like this: `zig build run -- arg1 arg2 etc`
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    {
        const test_step = b.step("test", "Run unit tests");

        for ([_][]const u8{
            "src/cli/draw/common.zig",
            "src/cli/draw/connections.zig",
            "src/cli/draw/inputs.zig",
            "src/cli/draw/outputs.zig",
            "src/cli/draw/styles.zig",
            "src/cli/transform/geometry.zig",
        }) |test_file| {
            const test_mod = b.createModule(.{
                .root_source_file = b.path(test_file),
                .optimize = optimize,
                .target = target,
            });
            const unit_tests = b.addTest(.{
                .root_module = test_mod,
            });

            test_mod.addImport("zli", zli_dep.module("zli"));
            test_mod.addImport("mecha", mecha_dep.module("mecha"));
            test_mod.addImport("cli", b.createModule(.{
                .root_source_file = b.path("src/cli/draw/inputs.zig"),
            }));

            const run_unit_tests = b.addRunArtifact(unit_tests);
            test_step.dependOn(&run_unit_tests.step);
        }

        // Register new test
        const cli_test = cmdtest.add(b, .{
            .name = "zsat",
            .test_file = b.path("test/cli.zig"),
        });

        test_step.dependOn(&cli_test.step);
    }
}
