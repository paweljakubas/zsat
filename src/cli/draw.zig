const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");
const Styles = @import("draw/styles.zig");
const Inputs = @import("draw/inputs.zig");

const style_flag = zli.Flag{
    .name = "styles",
    .shortcut = "s",
    .description = "Style(s) definition to be used in further steps when constructing the figure.",
    .type = .String,
    .default_value = .{ .String = "e0:{vec2d xy fixed [lw:20, lc: black, lo: 100, le:none, lj: none]}" },
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

const ParsedData = struct {
    styles: Styles.Style,
    inputs: Inputs.Inputs,
};

fn parse(ctx: zli.CommandContext) !ParsedData {
    const debug = ctx.flag("debug", bool);
    const styles_str = ctx.flag("styles", []const u8);

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const stdin_str = try std.fs.File.stdin().readToEndAlloc(alloc, 1024 * 1024);
    defer alloc.free(stdin_str);

    if (debug) {
        std.debug.print("styles: {s}\n", .{styles_str});
        std.debug.print("stdin: {s}\n", .{stdin_str});
    }

    const inputs_parse_result = try Inputs.inputsParser.parse(alloc, stdin_str);
    const inputs = switch (inputs_parse_result.value) {
        .ok => |in| in,
        .err => {
            return error.ParseInputsFailed;
        },
    };

    const styles_parse_result = try Styles.styleParser.parse(alloc, styles_str);
    const styles = switch (styles_parse_result.value) {
        .ok => |s| s,
        .err => {
            return error.ParseStylesFailed;
        },
    };

    return ParsedData{
        .styles = styles,
        .inputs = inputs,
    };
}

fn run(ctx: zli.CommandContext) !void {
    _ = parse(ctx) catch |err| {
        std.debug.print("failed to parse: {}\n", .{err});
        return;
    };
}
