const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");

const element0_flag = zli.Flag{
    .name = "element0",
    .shortcut = "e0",
    .description = "Visual element that wil be contained in the figure. Visualization aspects are defined here.",
    .type = .String,
    .default_value = .{ .String = "cos tam" },
};

pub fn register(writer: *Writer, reader: *Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "draw",
        .shortcut = "d",
        .description = "Construct figure from bits",
    }, run);

    try cmd.addFlag(element0_flag);

    return cmd;
}

fn run(ctx: zli.CommandContext) !void {
    const element0 = ctx.flag("element0", []const u8);

    std.debug.print("Defining {s}\n", .{element0});
}
