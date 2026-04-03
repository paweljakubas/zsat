const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");
const Styles = @import("draw/styles.zig");
const Inputs = @import("draw/inputs.zig");
const Datum = @import("draw/datum.zig");
const Panes = @import("draw/panes.zig");

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

const panes_flag = zli.Flag{
    .name = "panes",
    .shortcut = "p",
    .description = "Pane(s) definition to be used in further steps when constructing the figure.",
    .type = .String,
    .default_value = .{ .String = "p0:{view:{(0,0), (100, 100)}}" },
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
    try cmd.addFlag(panes_flag);
    try cmd.addFlag(debug_flag);

    return cmd;
}

const ParsedData = struct {
    styles: []const Styles.Style,
    inputs: Inputs.Inputs,
    datum: Datum.DataElementValidated,
    panes: []const Panes.Pane,
};

fn parse(ctx: zli.CommandContext) !ParsedData {
    const debug = ctx.flag("debug", bool);
    const styles_str = ctx.flag("styles", []const u8);
    const datum_str = ctx.flag("datum", []const u8);
    const panes_str = ctx.flag("panes", []const u8);

    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const stdin_str = try std.fs.File.stdin().readToEndAlloc(alloc, 1024 * 1024);
    defer alloc.free(stdin_str);

    if (debug) {
        std.debug.print("stdin: {s}\n", .{stdin_str});
        std.debug.print("styles: {s}\n", .{styles_str});
        std.debug.print("datum: {s}\n", .{datum_str});
        std.debug.print("panes: {s}\n", .{panes_str});
    }

    const inputs_parse_result = try Inputs.inputsParser.parse(alloc, stdin_str);
    const inputs = switch (inputs_parse_result.value) {
        .ok => |in| in,
        .err => {
            return error.ParseInputsFailed;
        },
    };

    const styles_parse_result = try Styles.stylesParser.parse(alloc, styles_str);
    const styles = switch (styles_parse_result.value) {
        .ok => |s| s,
        .err => {
            return error.ParseStylesFailed;
        },
    };
    if (styles.len == 0) {
        return error.ParseStylesFailed;
    }

    const datum_parse_result = try Datum.connectionParser.parse(alloc, datum_str);
    const datum = switch (datum_parse_result.value) {
        .ok => |d| d,
        .err => {
            return error.ParseDatumFailed;
        },
    };

    const numberOfDatum: u8 = @intCast(inputs.input.len);

    var elements = try alloc.alloc([]const u8, styles.len);
    for (styles, 0..) |style, i| {
        elements[i] = try std.fmt.allocPrint(alloc, "e{}", .{style.styleNumber});
    }
    defer alloc.free(elements);

    const datumValidated = try Datum.validateConnection(alloc, numberOfDatum, elements, datum);

    const panes_parse_result = try Panes.panesParser.parse(alloc, panes_str);
    const panes = switch (panes_parse_result.value) {
        .ok => |p| p,
        .err => {
            return error.ParsePanesFailed;
        },
    };
    if (panes.len == 0) {
        return error.ParsePanesFailed;
    }

    return ParsedData{
        .styles = styles,
        .inputs = inputs,
        .datum = datumValidated,
        .panes = panes,
    };
}

fn run(ctx: zli.CommandContext) !void {
    _ = parse(ctx) catch |err| {
        switch (err) {
            error.ParseStylesFailed => std.debug.print("error: failed to parse styles (ParseStylesFailed)\n", .{}),
            error.ParseInputsFailed => std.debug.print("error: failed to parse inputs (stdin) (ParseInputsFailed)\n", .{}),
            error.ParseDatumFailed => std.debug.print("error: failed to parse datum mapping (ParseDatumFailed)\n", .{}),
            error.ParsePanesFailed => std.debug.print("error: failed to parse panes (ParsePanesFailed)\n", .{}),
            Datum.DataElementError.WrongNumberOfDatum => std.debug.print("error: number of inputs in datum mapping does not match number of input rows (WrongNumberOfDatum)\n", .{}),
            Datum.DataElementError.ElementInMappingInvalid => std.debug.print("error: element reference in datum mapping does not exist in styles (use e0, e1, etc.) (ElementInMappingInvalid)\n", .{}),
            Datum.DataElementError.DataInMappingInvalid => std.debug.print("error: data name in datum mapping does not match any input names (use names from stdin like vec) (DataInMappingInvalid)\n", .{}),
            else => std.debug.print("error: {s}\n", .{@errorName(err)}),
        }
        return;
    };
}
