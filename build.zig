const std = @import("std");

/// Zig 0.16 ships no build step for removing a directory tree, so `clean` brings
/// its own. Deleting the cache root from inside the make phase is the point of
/// the step, so it must not depend on any other step of this build.
const RemoveDirTree = struct {
    step: std.Build.Step,
    lazy_path: std.Build.LazyPath,

    fn create(b: *std.Build, lazy_path: std.Build.LazyPath) *RemoveDirTree {
        const self = b.allocator.create(RemoveDirTree) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "remove directory tree",
                .owner = b,
                .makeFn = make,
            }),
            .lazy_path = lazy_path,
        };
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
        _ = options;
        const self: *RemoveDirTree = @fieldParentPtr("step", step);
        const b = step.owner;
        const path = self.lazy_path.getPath3(b, step);
        try path.root_dir.handle.deleteTree(b.graph.io, path.subPathOrDot());
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run unit tests");
    const cli_test_step = b.step("cli-test", "Run CLI integration tests");

    const zli_dep = b.dependency("zli", .{ .target = target, .optimize = optimize });
    const mecha_dep = b.dependency("mecha", .{ .target = target, .optimize = optimize });
    const cmdtest_dep = b.dependency("cmdtest", .{});
    const z2d_dep = b.dependency("z2d", .{ .target = target, .optimize = optimize });
    const zigimg_dep = b.dependency("zigimg", .{ .target = target, .optimize = optimize });

    const config_mod = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
    });
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
    outputs_mod.addImport("mecha", mecha_dep.module("mecha"));
    styles_mod.addImport("outputs", outputs_mod);
    inputs_mod.addImport("styles", styles_mod);

    const panes_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/draw/panes.zig"),
    });
    panes_mod.addImport("inputs", inputs_mod);

    const pt2d_mod = b.createModule(.{
        .root_source_file = b.path("src/cli/plot/pt2d.zig"),
    });
    pt2d_mod.addImport("z2d", z2d_dep.module("z2d"));

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
        exe.root_module.addImport("config", config_mod);
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
        plot_mod.addImport("pt2d", pt2d_mod);
        exe.root_module.addImport("plot", plot_mod);

        const install_artifact = b.addInstallArtifact(exe, .{});
        b.getInstallStep().dependOn(&install_artifact.step);

        const config_installer_mod = b.createModule(.{
            .root_source_file = b.path("src/install_config.zig"),
            .target = b.graph.host,
        });
        config_installer_mod.addImport("config", config_mod);

        const config_installer = b.addExecutable(.{
            .name = "zsat-config-installer",
            .root_module = config_installer_mod,
        });
        const install_config = b.addRunArtifact(config_installer);
        install_config.stdio = .inherit;
        // Only the install step writes ~/.config/zsat/zsat.conf. Steps that merely
        // need the binary, like 'run', depend on the compile step instead, and the
        // CLI tests depend on the install artifact rather than the install step, so
        // that they never create the config file either.
        b.getInstallStep().dependOn(&install_config.step);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(&exe.step);

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);

        const cli_test_mod = b.createModule(.{
            .root_source_file = b.path("test/cli.zig"),
            .target = b.graph.host,
            .imports = &.{
                .{
                    .name = "cmdtest",
                    .module = cmdtest_dep.module("cmdtest"),
                },
            },
        });
        const cli_test_exe = b.addTest(.{
            .name = "zsat",
            .root_module = cli_test_mod,
        });
        const run_cli_tests = b.addRunArtifact(cli_test_exe);
        run_cli_tests.step.dependOn(&install_artifact.step);
        const original_path = b.graph.environ_map.get("PATH") orelse "";
        run_cli_tests.setEnvironmentVariable("PATH", b.fmt("{s}{c}{s}", .{
            b.exe_dir,
            std.fs.path.delimiter,
            original_path,
        }));
        run_cli_tests.setEnvironmentVariable("TMPDIR", "/tmp");
        run_cli_tests.setEnvironmentVariable("HOME", "/tmp/zsat-cli-test-home");
        cli_test_step.dependOn(&run_cli_tests.step);
        test_step.dependOn(&run_cli_tests.step);
    }

    {
        const test_files = [_][]const u8{
            "src/config.zig",
            "src/cli/draw/common.zig",
            "src/cli/draw/border.zig",
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

        // Test outputs.zig and geometry.zig using a common root in src/cli/
        // so that cross-directory relative imports (e.g. ../transform/geometry.zig)
        // are resolved within the same module tree and all nested tests are included.
        {
            const cli_test_mod = b.createModule(.{
                .root_source_file = b.path("src/cli/test_all.zig"),
                .optimize = optimize,
                .target = target,
            });
            cli_test_mod.addImport("mecha", mecha_dep.module("mecha"));
            cli_test_mod.addImport("cli", inputs_mod);
            cli_test_mod.addImport("z2d", z2d_dep.module("z2d"));
            const cli_tests = b.addTest(.{
                .root_module = cli_test_mod,
            });
            const run_cli_tests = b.addRunArtifact(cli_tests);
            test_step.dependOn(&run_cli_tests.step);
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
            plot_test_mod.addImport("pt2d", pt2d_mod);
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
    }

    {
        const clean_step = b.step("clean", "Remove the build cache and the install prefix");

        const cache_path: std.Build.LazyPath = .{ .cwd_relative = b.cache_root.path orelse "." };
        clean_step.dependOn(&RemoveDirTree.create(b, cache_path).step);

        const install_path: std.Build.LazyPath = .{ .cwd_relative = b.install_path };
        clean_step.dependOn(&RemoveDirTree.create(b, install_path).step);
    }
}
