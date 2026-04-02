const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");
const Styles = @import("draw/styles.zig");
const Inputs = @import("draw/inputs.zig");
const Datum = @import("draw/datum.zig");

const style_flag = zli.Flag{
    .name = "styles",
    .shortcut = "s",
    .description = "Style(s) definition to be used in further steps when constructing the figure.",
    .type = .String,
    .default_value = .{ .String = "e0:{vec2d xy fixed [lw:20, lc: black, lo: 100, le:none, lj: none]}" },
};

const datum_flag = zli.Flag{
    .name = "datum",
    .shortcut = "d",
    .description = "Mapping data streams to the defined styles.",
    .type = .String,
    .default_value = .{ .String = "(vec) -> (vec -> e0)" },
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
    try cmd.addFlag(datum_flag);
    try cmd.addFlag(debug_flag);

    return cmd;
}

const ParsedData = struct {
    styles: Styles.Style,
    inputs: Inputs.Inputs,
    datum: Datum.DataElementValidated,
};

fn parse(ctx: zli.CommandContext) !ParsedData {
    const debug = ctx.flag("debug", bool);
    const styles_str = ctx.flag("styles", []const u8);
    const datum_str = ctx.flag("datum", []const u8);

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const stdin_str = try std.fs.File.stdin().readToEndAlloc(alloc, 1024 * 1024);
    defer alloc.free(stdin_str);

    if (debug) {
        std.debug.print("stdin: {s}\n", .{stdin_str});
        std.debug.print("styles: {s}\n", .{styles_str});
        std.debug.print("datum: {s}\n", .{datum_str});
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

    const datum_parse_result = try Datum.connectionParser.parse(alloc, datum_str);
    const datum = switch (datum_parse_result.value) {
        .ok => |d| d,
        .err => {
            return error.ParseDatumFailed;
        },
    };

    //here we are going to validate datum via validateConnection. We will take the number of inputs, array length of 'input' in Inputs,
    //and also identifiers from style. Here we know that they are preceded by 's' and complemented by number being field 'styleNumber'.
    //Hence, datumValidated is of type DataElementValidated.
    const numberOfDatum: u8 = @intCast(inputs.input.len);

    var elements = try alloc.alloc([]const u8, 1);
    elements[0] = try std.fmt.allocPrint(alloc, "e{}", .{styles.styleNumber});
    defer alloc.free(elements[0]);
    defer alloc.free(elements);

    const datumValidated = try Datum.validateConnection(alloc, numberOfDatum, elements, datum);

    return ParsedData{
        .styles = styles,
        .inputs = inputs,
        .datum = datumValidated,
    };
}

fn run(ctx: zli.CommandContext) !void {
    _ = parse(ctx) catch |err| {
        std.debug.print("failed to parse: {}\n", .{err});
        return;
    };
}
