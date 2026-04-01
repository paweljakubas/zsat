const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");

const style_flag = zli.Flag{
    .name = "styles",
    .shortcut = "s",
    .description = "Style(s) definition to be used in further steps when constructing the figure.",
    .type = .String,
    .default_value = .{ .String = "e0:{vec2d xy fixed [lw:2; lc: black]}" },
};

const debug_flag = zli.Flag{
    .name = "debug",
    .description = "Dump the drawing representation for a command invoked.",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

pub fn register(writer: *Writer, reader: *Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "draw",
        .shortcut = "d",
        .description = "Construct figure from elements, sources, outputs, panes and frames",
    }, run);

    try cmd.addFlag(style_flag);
    try cmd.addFlag(debug_flag);

    return cmd;
}

fn run(ctx: zli.CommandContext) !void {
    const debug = ctx.flag("debug", bool);
    const styles = ctx.flag("styles", []const u8);

    if (debug) {
        std.debug.print("styles: {s}\n", .{elements});
    } else {
        std.debug.print("plotting \n", .{});
    }
}
