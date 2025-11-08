const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");

const version = @import("version.zig");

pub fn build(writer: *Writer, reader: *Reader, allocator: std.mem.Allocator) !*zli.Command {
    const root = try zli.Command.init(writer, reader, allocator, .{
        .name = "zsat",
        .description = "Animation and plot toolkit",
        .version = .{ .major = 0, .minor = 0, .patch = 1, .pre = null, .build = null },
    }, showHelp);

    try root.addCommands(&.{
        try version.register(writer, reader, allocator),
    });

    return root;
}

fn showHelp(ctx: zli.CommandContext) !void {
    try ctx.command.printHelp();
}
