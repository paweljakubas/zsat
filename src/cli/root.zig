const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");

const version = @import("version.zig");
const draw = @import("draw.zig");
const draw_help = @import("draw_help.zig");

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
        .version = .{ .major = 0, .minor = 2, .patch = 0, .pre = null, .build = null },
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

/// Handles `zsat draw color [NAME|LETTER] [--help]` before zli gets a chance to
/// print the static help text. zli short-circuits `--help` inside its parser,
/// so the renderer cannot be attached as the command's execFn; instead the
/// arguments are recognized here and the color reference is rendered directly.
///
/// Returns true when the invocation was handled and `execute` must be skipped.
pub fn maybeHandleColorCommand(
    args: std.process.Args,
    io: std.Io,
    writer: *Writer,
) !bool {
    if (comptime std.process.Args.Vector == void) return false;

    const vector = args.vector;
    if (vector.len <= 1) return false;

    var command_tokens: usize = 0;
    var in_color = false;
    var selector: ?[]const u8 = null;

    for (vector[1..]) |arg_ptr| {
        const arg = std.mem.span(arg_ptr);
        if (arg.len == 0 or arg[0] == '-') continue;

        if (!in_color) {
            switch (command_tokens) {
                0 => {
                    if (std.mem.eql(u8, arg, "draw") or std.mem.eql(u8, arg, "d")) {
                        command_tokens = 1;
                    } else return false;
                },
                1 => {
                    if (std.mem.eql(u8, arg, "color")) {
                        in_color = true;
                    } else return false;
                },
                else => return false,
            }
        } else if (selector == null) {
            selector = arg;
        }
    }

    if (!in_color) return false;

    const ansi = std.Io.File.stdout().isTty(io) catch false;
    try draw_help.renderColorReference(selector, ansi, writer);
    try writer.flush();
    return true;
}
