const std = @import("std");
const cmdtest = @import("cmdtest");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zli_dep = b.dependency("zli", .{ .target = target, .optimize = optimize });
    const mecha_dep = b.dependency("mecha", .{ .target = target, .optimize = optimize });
    const cmdtest_dep = b.dependency("cmdtest", .{});
    const z2d_dep = b.dependency("z2d", .{ .target = target, .optimize = optimize });
    const zigimg_dep = b.dependency("zigimg", .{ .target = target, .optimize = optimize });

    const inputs_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/draw/inputs.zig"),
    });
    const styles_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/draw/styles.zig"),
    });
    const outputs_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/draw/outputs.zig"),
    });
    outputs_mod.addImport("cli", inputs_mod);
    styles_mod.addImport("outputs", outputs_mod);
    inputs_mod.addImport("styles", styles_mod);

    const panes_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/draw/panes.zig"),
    });
    panes_mod.addImport("inputs", inputs_mod);

    {
        const git_argv = [_][]const u8{ "git", "rev-parse", "--short", "HEAD" };
        const commit_hash = b.run(&git_argv);
        const trimmed = std.mem.trim(u8, commit_hash, &std.ascii.whitespace);

        const version_content = b.fmt("pub const commit = \"{s}\";\n", .{trimmed});
        const write_step = b.addWriteFiles();
        const version_path = write_step.add("src/cli/commit.zig", version_content);

        const exe_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        exe_mod.addImport("commit", b.createModule(.{
            .root_source_file = version_path,
        }));

        const exe = b.addExecutable(.{
            .name = "zsat",
            .root_module = exe_mod,
        });

        exe.root_module.addImport("zli", zli_dep.module("zli"));
        exe.root_module.addImport("mecha", mecha_dep.module("mecha"));
        exe.root_module.addImport("cmdtest", cmdtest_dep.module("cmdtest"));
        exe.root_module.addImport("z2d", z2d_dep.module("z2d"));
        exe.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));
        exe.root_module.addImport("cli", inputs_mod);
        exe.root_module.addImport("plot_types", b.createModule(.{
            .root_source_file = b.path("src/cli/plot/plot_types.zig"),
        }));
        const plot_mod = b.createModule(.{
            .root_source_file = b.path("src/cli/plot/plot.zig"),
        });
        plot_mod.addImport("z2d", z2d_dep.module("z2d"));
        plot_mod.addImport("plot_types", b.createModule(.{
            .root_source_file = b.path("src/cli/plot/plot_types.zig"),
        }));
        plot_mod.addImport("styles", styles_mod);
        exe.root_module.addImport("plot", plot_mod);

        b.installArtifact(exe);
        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    {
        const test_step = b.step("test", "Run unit tests");

        const test_files = [_][]const u8{
            "src/cli/draw/common.zig",
            "src/cli/draw/datum.zig",
            "src/cli/draw/frames.zig",
            "src/cli/draw/inputs.zig",
            "src/cli/draw/panes.zig",
            "src/cli/draw/styles.zig",
        };

        for (test_files) |test_file| {
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
            test_mod.addImport("cli", inputs_mod);

            const run_unit_tests = b.addRunArtifact(unit_tests);
            test_step.dependOn(&run_unit_tests.step);
        }

        // Test outputs.zig and geometry.zig using a runner at src/ level
        // to allow cross-directory relative imports
        {
            const exports_mod = b.createModule(.{
                .root_source_file = b.path("src/exports.zig"),
                .optimize = optimize,
                .target = target,
            });
            const exports_tests = b.addTest(.{
                .root_module = exports_mod,
            });
            exports_mod.addImport("zli", zli_dep.module("zli"));
            exports_mod.addImport("mecha", mecha_dep.module("mecha"));
            exports_mod.addImport("cli", inputs_mod);
            const run_exports_tests = b.addRunArtifact(exports_tests);
            test_step.dependOn(&run_exports_tests.step);
        }

        // Test plot.zig separately - doesn't include panes dependency
        {
            const plot_test_mod = b.createModule(.{
                .root_source_file = b.path("src/cli/plot/plot.zig"),
                .optimize = optimize,
                .target = target,
            });
            plot_test_mod.addImport("z2d", z2d_dep.module("z2d"));
            plot_test_mod.addImport("plot_types", b.createModule(.{
                .root_source_file = b.path("src/cli/plot/plot_types.zig"),
            }));
            plot_test_mod.addImport("draw_styles", styles_mod);
            const plot_unit_tests = b.addTest(.{
                .root_module = plot_test_mod,
            });

            plot_test_mod.addImport("zli", zli_dep.module("zli"));
            plot_test_mod.addImport("mecha", mecha_dep.module("mecha"));
            plot_test_mod.addImport("cli", inputs_mod);
            plot_test_mod.addImport("z2d", z2d_dep.module("z2d"));
            plot_test_mod.addImport("plot_types", b.createModule(.{
                .root_source_file = b.path("src/cli/plot/plot_types.zig"),
            }));

            const run_plot_tests = b.addRunArtifact(plot_unit_tests);
            test_step.dependOn(&run_plot_tests.step);
        }

        const cli_test = cmdtest.add(b, .{
            .name = "zsat",
            .test_file = b.path("test/cli.zig"),
        });
        cli_test.setEnvironmentVariable("PATH", "zig-out/bin");
        cli_test.setEnvironmentVariable("TMPDIR", "/tmp");

        test_step.dependOn(&cli_test.step);

        const cli_test_step = b.step("cli-test", "Run CLI integration tests");
        cli_test_step.dependOn(&cli_test.step);
    }
}
