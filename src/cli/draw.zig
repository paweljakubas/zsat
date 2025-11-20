const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");

const element0_flag = zli.Flag{
    .name = "element0",
    .shortcut = "e0",
    .description = "Visual element to be contained in the figure.",
    .type = .String,
    .default_value = .{ .String = "vec xy fixed [lw:2; lc: black]" },
};

const debug_flag = zli.Flag{
    .name = "debug",
    .description = "Dump intermediate draw representation and corresponding Haskell scrypt.",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

pub fn register(writer: *Writer, reader: *Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "draw",
        .shortcut = "d",
        .description = "Construct figure from bits",
    }, run);

    try cmd.addFlag(element0_flag);
    try cmd.addFlag(debug_flag);

    return cmd;
}

fn run(ctx: zli.CommandContext) !void {
    const debug = ctx.flag("debug", bool);
    const element0 = ctx.flag("element0", []const u8);

    if (debug) {
        std.debug.print("element0: {s}\n", .{element0});
    } else {
        std.debug.print("plotting \n", .{});
    }
}
