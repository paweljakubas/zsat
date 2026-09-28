const std = @import("std");
const config = @import("config");

const created_message = " ~/.config/zsat/zsat.conf created, its saved styles can be used in --styles";
const found_message = " ~/.config/zsat/zsat.conf found, its saved styles can be used in --styles";

pub fn main(init: std.process.Init) !void {
    const home = init.environ_map.get("HOME") orelse init.environ_map.get("USERPROFILE") orelse return;
    if (home.len == 0) return;

    const allocator = init.gpa;
    const config_dir = try std.fs.path.join(allocator, &.{ home, ".config", "zsat" });
    defer allocator.free(config_dir);
    const config_path = try std.fs.path.join(allocator, &.{ config_dir, "zsat.conf" });
    defer allocator.free(config_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(init.io, config_dir);

    const existing = cwd.openFile(init.io, config_path, .{ .allow_directory = false }) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (existing) |file| {
        file.close(init.io);
        try printMessage(init.io, found_message);
        return;
    }

    const file = cwd.createFile(init.io, config_path, .{
        .exclusive = true,
        .truncate = false,
    }) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try printMessage(init.io, found_message);
            return;
        },
        else => return err,
    };
    try file.writeStreamingAll(init.io, config.default_content);
    file.close(init.io);
    try printMessage(init.io, created_message);
}

fn printMessage(io: std.Io, message: []const u8) !void {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(io, &buffer);
    try writer.interface.writeAll(message);
    try writer.interface.writeByte('\n');
    try writer.interface.flush();
}
