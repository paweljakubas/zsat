const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");

const version = @import("version.zig");
const draw = @import("draw.zig");

pub fn build(io: std.Io, writer: *Writer, reader: *Reader, allocator: std.mem.Allocator) !*zli.Command {
    const init_opts = zli.InitOptions{
        .io = io,
        .writer = writer,
        .reader = reader,
        .allocator = allocator,
    };
    const root = try zli.Command.init(init_opts, .{
        .name = "zsat",
        .description = "Zig-powered science animation and plot command line tool",
        .version = .{ .major = 0, .minor = 0, .patch = 1, .pre = null, .build = null },
    }, showHelp);

    try root.addCommands(&.{
        try version.register(init_opts),
        try draw.register(init_opts),
    });

    return root;
}

fn showHelp(ctx: zli.CommandContext) !void {
    try ctx.command.printHelp();
}
