const std = @import("std");
const cli = @import("cli/root.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var stdout_fw = std.Io.File.stdout().writerStreaming(io, &.{});
    var stdout = &stdout_fw.interface;

    var buf: [4096]u8 = undefined;
    var stdin_fr = std.Io.File.stdin().readerStreaming(io, &buf);
    const stdin = &stdin_fr.interface;

    const color_handled = cli.maybeHandleColorCommand(init.minimal.args, io, stdout) catch |err| switch (err) {
        error.WriteFailed => return,
        else => |e| return e,
    };
    if (color_handled) return;

    const root = try cli.build(io, stdout, stdin, allocator);
    defer root.deinit();

    var argsIterator = std.process.Args.Iterator.init(init.minimal.args);
    var environ = init.minimal.environ;
    try root.execute(&argsIterator, .{ .data = &environ });

    try stdout.flush();
}
