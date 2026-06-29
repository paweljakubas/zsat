const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");
const z2d = @import("z2d");
const zigimg = @import("zigimg");
const Styles = @import("draw/styles.zig");
const Inputs = @import("draw/inputs.zig");
const Outputs = @import("draw/outputs.zig");
const Datum = @import("draw/datum.zig");
const Frames = @import("draw/frames.zig");
const Panes = @import("draw/panes.zig");

const Plot = @import("plot");
const draw_help = @import("draw_help.zig");

pub const ParsedData = struct {
    styles: []const Styles.Style,
    inputs: Inputs.Inputs,
    datum: Datum.DataElementValidated,
    outputs: Outputs.OutputsValidated,
    panes: []const Panes.Pane,
    frames: Frames.OutputPaneValidated,
};

const style_flag = zli.Flag{
    .name = "styles",
    .shortcut = "s",
    .description = "Style(s) definition to be used in further steps when constructing the figure.",
    .type = .String,
    .default_value = .{ .String = "e0:{vec2d xy fixed last [lw:10, lc: black, lo: 100, le:none, lj: none, ld: none]}" },
};

const datum_flag = zli.Flag{
    .name = "datum",
    .shortcut = "d",
    .description = "Mapping data streams to the defined styles.",
    .type = .String,
    .default_value = .{ .String = "(vec) -> (vec -> e0)" },
};

const outputs_flag = zli.Flag{
    .name = "outputs",
    .shortcut = "o",
    .description = "Input(s) transformation definition of the outputs.",
    .type = .String,
    .default_value = .{ .String = "(out) -> (anchor {(0,0)}) out" },
};

const panes_flag = zli.Flag{
    .name = "panes",
    .shortcut = "p",
    .description = "Pane(s) definition to be used in frame construction of the figure.",
    .type = .String,
    .default_value = .{ .String = "p0:{size: 600x600}" },
};

const frames_flag = zli.Flag{
    .name = "frames",
    .shortcut = "f",
    .description = "Frame(s) definition of the figure.",
    .type = .String,
    .default_value = .{ .String = "(out) -> out -> p0" },
};

const debug_flag = zli.Flag{
    .name = "debug",
    .description = "Dump the drawing representation for a command invoked.",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

const out_flag = zli.Flag{
    .name = "out",
    .description = "Output filename for the PNG image. When specified, always writes to file instead of displaying in terminal.",
    .type = .String,
    .default_value = .{ .String = "" },
};

pub fn register(init_opts: zli.InitOptions) !*zli.Command {
    const cmd = try zli.Command.init(init_opts, .{
        .name = "draw",
        .shortcut = "d",
        .description = "Construct figure for stdin data using styles, datum, outputs, panes and frames",
    }, run);

    try cmd.addFlag(style_flag);
    try cmd.addFlag(datum_flag);
    try cmd.addFlag(outputs_flag);
    try cmd.addFlag(panes_flag);
    try cmd.addFlag(frames_flag);

    try cmd.addFlag(debug_flag);
    try cmd.addFlag(out_flag);

    // Documentation subcommands
    const vec2d_cmd = try zli.Command.init(init_opts, .{
        .name = "vec2d",
        .description = "2D vector data format and concepts",
        .help = draw_help.vec2d_help,
    }, draw_help.printHelpExec);

    const vec2d_style_cmd = try zli.Command.init(init_opts, .{
        .name = "style",
        .description = "Style attributes: coordinate system, orientation, steps, line properties",
        .help = draw_help.vec2d_style_help,
    }, draw_help.printHelpExec);

    const vec2d_output_cmd = try zli.Command.init(init_opts, .{
        .name = "output",
        .description = "Output transformations: anchor, rotate, scale, mirror",
        .help = draw_help.vec2d_output_help,
    }, draw_help.printHelpExec);

    try vec2d_cmd.addCommand(vec2d_style_cmd);
    try vec2d_cmd.addCommand(vec2d_output_cmd);
    try cmd.addCommand(vec2d_cmd);

    const point_cmd = try zli.Command.init(init_opts, .{
        .name = "point",
        .description = "How to define points: explicit coordinates or references",
        .help = draw_help.point_help,
    }, draw_help.printHelpExec);
    try cmd.addCommand(point_cmd);

    const line_cmd = try zli.Command.init(init_opts, .{
        .name = "line",
        .description = "How to define lines for the mirror transformation",
        .help = draw_help.line_help,
    }, draw_help.printHelpExec);
    try cmd.addCommand(line_cmd);

    const color_cmd = try zli.Command.init(init_opts, .{
        .name = "color",
        .description = "Available color names for line color",
        .help = draw_help.color_help,
    }, draw_help.printHelpExec);
    try cmd.addCommand(color_cmd);

    return cmd;
}

fn parse(ctx: zli.CommandContext, alloc: std.mem.Allocator) !ParsedData {
    const debug = ctx.flag("debug", bool);
    const styles_str = ctx.flag("styles", []const u8);
    const datum_str = ctx.flag("datum", []const u8);
    const panes_str = ctx.flag("panes", []const u8);
    const frames_str = ctx.flag("frames", []const u8);
    const output_str = ctx.flag("outputs", []const u8);

    const stdin_str = try ctx.reader.allocRemaining(alloc, .limited(1024 * 1024));
    defer alloc.free(stdin_str);

    const inputs_parse_result = try Inputs.inputsParser.parse(alloc, stdin_str);
    const inputs = switch (inputs_parse_result.value) {
        .ok => |in| in,
        .err => {
            return error.ParseInputsFailed;
        },
    };
    if (inputs_parse_result.index < stdin_str.len) {
        const rest = stdin_str[inputs_parse_result.index..];
        for (rest) |c| {
            if (c != ' ' and c != '\n' and c != '\r' and c != '\t') {
                return error.ParseInputsFailed;
            }
        }
    }

    const styles_parse_result = try Styles.stylesParser.parse(alloc, styles_str);
    const raw_styles = switch (styles_parse_result.value) {
        .ok => |s| s,
        .err => {
            return error.ParseStylesFailed;
        },
    };
    if (raw_styles.len == 0) {
        return error.ParseStylesFailed;
    }
    const styles = try Styles.resolveStyles(alloc, raw_styles);

    var effective_datum_str = datum_str;
    if (std.mem.eql(u8, datum_str, "(vec) -> (vec -> e0)") and inputs.input.len > 1) {
        var buf = std.ArrayList(u8).empty;
        try buf.appendSlice(alloc, "(vec");
        for (1..inputs.input.len) |_| {
            try buf.appendSlice(alloc, ", vec");
        }
        try buf.appendSlice(alloc, ") -> (vec -> e0");
        for (1..inputs.input.len) |_| {
            try buf.appendSlice(alloc, ", vec -> e0");
        }
        try buf.append(alloc, ')');
        effective_datum_str = try buf.toOwnedSlice(alloc);
    }

    const datum_parse_result = try Datum.connectionParser.parse(alloc, effective_datum_str);
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

    const outputs_parse_result = try Outputs.connectionParser.parse(alloc, output_str);
    const outputsConnection = switch (outputs_parse_result.value) {
        .ok => |o| o,
        .err => {
            return error.ParseOutputsFailed;
        },
    };
    if (outputs_parse_result.index != output_str.len) {
        return error.ParseOutputsFailed;
    }

    const numberOfOutputsForValidation: u8 = @intCast(outputsConnection.outputs.len);

    var outputsValidated = try Outputs.validateConnection(alloc, numberOfOutputsForValidation, outputsConnection);

    // If only one output transformation pair is defined but multiple input
    // rows are present, replicate the pair so each row is drawn independently
    // using the same output transformation.
    if (outputsValidated.transformationPairs.len == 1 and inputs.input.len > 1) {
        const original_pair = outputsValidated.transformationPairs[0];
        const replicated = try alloc.alloc(Outputs.OutputTransformationPair, inputs.input.len);
        for (replicated) |*p| {
            p.* = original_pair;
        }
        outputsValidated.transformationPairs = replicated;
    }

    var result_pairs = try alloc.alloc(Outputs.OutputTransformationPair, outputsValidated.transformationPairs.len);

    for (0..outputsValidated.transformationPairs.len) |idx| {
        const coord_orientation = if (styles.len > idx and styles[idx].styleValue.coordinateOrientation != null) styles[idx].styleValue.coordinateOrientation.? else .fixed;
        const plot_step = if (styles.len > idx and styles[idx].styleValue.plotSteps != null) styles[idx].styleValue.plotSteps.? else .last;
        const coord_type = if (styles.len > idx and styles[idx].styleValue.coordinateSystem != null) styles[idx].styleValue.coordinateSystem.? else .xy;

        const transformed = try Outputs.toExplicitPoint(alloc, inputs, outputsValidated, coord_orientation, plot_step, idx, coord_type);
        result_pairs[idx] = transformed.transformationPairs[idx];
    }

    var outputsExplicit: Outputs.OutputsValidated = undefined;
    outputsExplicit.transformationPairs = result_pairs;

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

    var paneNames = try alloc.alloc([]const u8, panes.len);
    for (panes, 0..) |pane, i| {
        paneNames[i] = try std.fmt.allocPrint(alloc, "p{}", .{pane.paneNumber});
    }
    defer {
        for (paneNames) |name| alloc.free(name);
        alloc.free(paneNames);
    }

    const frames_parse_result = try Frames.connectionParser.parse(alloc, frames_str);
    const frames = switch (frames_parse_result.value) {
        .ok => |f| f,
        .err => {
            return error.ParseFramesFailed;
        },
    };

    const framesNum: u8 = 1;
    const framesValidated = try Frames.validateConnection(alloc, framesNum, paneNames, frames);

    if (debug) {
        const styles_debug = try Styles.serializeStyles(alloc, styles);
        defer alloc.free(styles_debug);
        try ctx.writer.print("stdin:\n{s}\n", .{stdin_str});
        try ctx.writer.print("\n--styles {s}\n", .{styles_debug});
        try ctx.writer.print("--datum {s}\n", .{datum_str});
        try ctx.writer.print("--outputs {s}\n", .{output_str});
        try ctx.writer.print("--panes {s}\n", .{panes_str});
        try ctx.writer.print("--frames {s}\n", .{frames_str});
    }

    return ParsedData{
        .styles = styles,
        .inputs = inputs,
        .datum = datumValidated,
        .outputs = outputsExplicit,
        .panes = panes,
        .frames = framesValidated,
    };
}

fn checkTerminalSupportsKitty(environ: std.process.Environ) bool {
    const term = environ.getPosix("TERM") orelse return false;
    if (!std.mem.containsAtLeast(u8, term, 1, "xterm") and
        !std.mem.containsAtLeast(u8, term, 1, "kitty") and
        !std.mem.containsAtLeast(u8, term, 1, "ghostty")) return false;
    return true;
}

fn rgbaPixelsToBase64(allocator: std.mem.Allocator, pixels: anytype) ![]u8 {
    var byte_data = try std.ArrayList(u8).initCapacity(allocator, pixels.len * 4);
    defer byte_data.deinit(allocator);
    for (pixels) |px| {
        try byte_data.append(allocator, px.r);
        try byte_data.append(allocator, px.g);
        try byte_data.append(allocator, px.b);
        try byte_data.append(allocator, px.a);
    }

    var encoded = try std.ArrayList(u8).initCapacity(allocator, std.base64.standard.Encoder.calcSize(byte_data.items.len));
    try encoded.resize(allocator, std.base64.standard.Encoder.calcSize(byte_data.items.len));
    _ = std.base64.standard.Encoder.encode(encoded.items, byte_data.items);
    return encoded.items;
}

fn kittyEncode(writer: anytype, width: i32, height: i32, encoded: []const u8) !void {
    try writer.writeAll("\n     ");
    const chunk_size = 4096;
    if (encoded.len <= chunk_size) {
        try writer.print("\x1B_Gf=32,s={d},v={d},a=T;{s}\x1B\\", .{ width, height, encoded });
    } else {
        try writer.print("\x1B_Gf=32,s={d},v={d},a=T,m=1;{s}\x1B\\", .{ width, height, encoded[0..chunk_size] });
        var start: usize = chunk_size;
        while (start + chunk_size < encoded.len) {
            try writer.print("\x1B_Gm=1;{s}\x1B\\", .{encoded[start..][0..chunk_size]});
            start += chunk_size;
        }
        try writer.print("\x1B_Gm=0;{s}\x1B\\", .{encoded[start..]});
    }
    try writer.writeAll("\n\n");
}

fn renderToStdout(allocator: std.mem.Allocator, img: Plot.RenderedImage, writer: anytype, io: std.Io) !void {
    const original_width = img.width;
    const original_height = img.height;

    var term_cols: u16 = 80;
    var term_rows: u16 = 24;

    const stdout_file = std.Io.File.stdout();
    if (try stdout_file.isTty(io)) {
        var winsize: std.posix.winsize = undefined;
        if (std.posix.system.ioctl(stdout_file.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize)) == 0 and
            winsize.col > 0 and winsize.col < 1000 and winsize.row > 0 and winsize.row < 1000)
        {
            term_cols = winsize.col;
            term_rows = winsize.row;
        }
    }

    const CELL_WIDTH: f32 = 8.0;
    const CELL_HEIGHT: f32 = 16.0;

    const max_pixel_w: f32 = @as(f32, @floatFromInt(term_cols)) * CELL_WIDTH;
    const max_pixel_h: f32 = @as(f32, @floatFromInt(term_rows)) * CELL_HEIGHT;

    const img_w: f32 = @floatFromInt(original_width);
    const img_h: f32 = @floatFromInt(original_height);
    const scale_x: f32 = max_pixel_w / img_w;
    const scale_y: f32 = max_pixel_h / img_h;
    const scale: f32 = @min(scale_x, scale_y);

    const new_w: u32 = @intFromFloat(scale * img_w);
    const new_h: u32 = @intFromFloat(scale * img_h);

    var pixels = img.pixels;
    var kitty_w: i32 = original_width;
    var kitty_h: i32 = original_height;
    if (new_w < original_width or new_h < original_height) {
        const resized = try resizePixels(allocator, pixels, original_width, original_height, new_w, new_h);
        pixels = resized;
        kitty_w = @intCast(new_w);
        kitty_h = @intCast(new_h);
    }

    const encoded = try rgbaPixelsToBase64(allocator, pixels);
    defer allocator.free(encoded);
    try kittyEncode(writer, kitty_w, kitty_h, encoded);
    try writer.flush();
}

fn resizePixels(
    alloc: std.mem.Allocator,
    pixels: []z2d.pixel.RGBA,
    original_width: i32,
    original_height: i32,
    new_w: u32,
    new_h: u32,
) ![]z2d.pixel.RGBA {
    const original_w_u: u32 = @intCast(original_width);
    const original_h_u: u32 = @intCast(original_height);

    const img_w_f = @as(f32, @floatFromInt(original_width));
    const img_h_f = @as(f32, @floatFromInt(original_height));
    const new_w_f = @as(f32, @floatFromInt(new_w));
    const new_h_f = @as(f32, @floatFromInt(new_h));

    var new_pixels = try alloc.alloc(z2d.pixel.RGBA, new_w * new_h);

    for (0..new_h) |y| {
        const sy = @as(f32, @floatFromInt(y)) * img_h_f / new_h_f;
        const y0 = @as(usize, @intFromFloat(@floor(sy)));
        const y1 = @min(y0 + 1, original_h_u - 1);
        const dy = sy - @floor(sy);

        for (0..new_w) |x| {
            const sx = @as(f32, @floatFromInt(x)) * img_w_f / new_w_f;
            const x0 = @as(usize, @intFromFloat(@floor(sx)));
            const x1 = @min(x0 + 1, original_w_u - 1);
            const dx = sx - @floor(sx);

            const p00 = pixels[y0 * original_w_u + x0];
            const p01 = pixels[y0 * original_w_u + x1];
            const p10 = pixels[y1 * original_w_u + x0];
            const p11 = pixels[y1 * original_w_u + x1];

            new_pixels[y * new_w + x] = .{
                .r = @intFromFloat((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.r)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.r)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.r)) + dx * dy * @as(f32, @floatFromInt(p11.r))),
                .g = @intFromFloat((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.g)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.g)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.g)) + dx * dy * @as(f32, @floatFromInt(p11.g))),
                .b = @intFromFloat((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.b)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.b)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.b)) + dx * dy * @as(f32, @floatFromInt(p11.b))),
                .a = @intFromFloat((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.a)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.a)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.a)) + dx * dy * @as(f32, @floatFromInt(p11.a))),
            };
        }
    }

    return new_pixels;
}

fn resizeImage(alloc: std.mem.Allocator, img: *zigimg.Image, new_w: u32, new_h: u32) !void {
    if (img.pixelFormat() != .rgba32) {
        try img.convert(alloc, .rgba32);
    }

    const original_width = img.width;
    const original_height = img.height;

    if (new_w == original_width and new_h == original_height) return;

    const img_w_f = @as(f32, @floatFromInt(original_width));
    const img_h_f = @as(f32, @floatFromInt(original_height));
    const new_w_f = @as(f32, @floatFromInt(new_w));
    const new_h_f = @as(f32, @floatFromInt(new_h));

    var new_pixels = try alloc.alloc(zigimg.color.Rgba32, new_w * new_h);

    for (0..new_h) |y| {
        const sy = @as(f32, @floatFromInt(y)) * img_h_f / new_h_f;
        const y0 = @as(usize, @intFromFloat(@floor(sy)));
        const y1 = @min(y0 + 1, original_height - 1);
        const dy = sy - @floor(sy);

        for (0..new_w) |x| {
            const sx = @as(f32, @floatFromInt(x)) * img_w_f / new_w_f;
            const x0 = @as(usize, @intFromFloat(@floor(sx)));
            const x1 = @min(x0 + 1, original_width - 1);
            const dx = sx - @floor(sx);

            const p00 = img.pixels.rgba32[y0 * original_width + x0];
            const p01 = img.pixels.rgba32[y0 * original_width + x1];
            const p10 = img.pixels.rgba32[y1 * original_width + x0];
            const p11 = img.pixels.rgba32[y1 * original_width + x1];

            new_pixels[y * new_w + x] = .{
                .r = @intFromFloat(@round((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.r)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.r)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.r)) + dx * dy * @as(f32, @floatFromInt(p11.r)))),
                .g = @intFromFloat(@round((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.g)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.g)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.g)) + dx * dy * @as(f32, @floatFromInt(p11.g)))),
                .b = @intFromFloat(@round((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.b)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.b)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.b)) + dx * dy * @as(f32, @floatFromInt(p11.b)))),
                .a = @intFromFloat(@round((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.a)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.a)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.a)) + dx * dy * @as(f32, @floatFromInt(p11.a)))),
            };
        }
    }

    alloc.free(img.pixels.rgba32);
    img.pixels = .{ .rgba32 = new_pixels };
    img.width = new_w;
    img.height = new_h;
}

fn getSystemTmpDir(alloc: std.mem.Allocator, environ: std.process.Environ) ![]u8 {
    const tmp_env = environ.getPosix("TMPDIR") orelse "/tmp";
    const tmp_dir_path = if (tmp_env.len > 0) tmp_env else "/tmp";
    return try alloc.dupe(u8, tmp_dir_path);
}

fn getNextOutputFilename(alloc: std.mem.Allocator, io: std.Io) ![]u8 {
    var n: u32 = 0;
    while (true) : (n += 1) {
        const filename = try std.fmt.allocPrint(alloc, "output{d}.png", .{n});
        errdefer alloc.free(filename);
        const file = std.Io.Dir.cwd().openFile(io, filename, .{}) catch {
            return filename;
        };
        file.close(io);
    }
}

fn friendlyErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.ParseInputsFailed => "Error: failed to parse input data. Please check your input format.",
        error.ParseStylesFailed => "Error: failed to parse styles. Please check your --styles argument.",
        error.ParseDatumFailed => "Error: failed to parse datum mapping. Please check your --datum argument.",
        error.ParseOutputsFailed => "Error: failed to parse outputs. Please check your --outputs argument.",
        error.ParsePanesFailed => "Error: failed to parse panes. Please check your --panes argument.",
        error.ParseFramesFailed => "Error: failed to parse frames. Please check your --frames argument.",
        error.WrongNumberOfDatum => "Error: the number of datum mappings does not match the number of inputs.",
        error.ElementInMappingInvalid => "Error: an invalid element was found in the datum mapping.",
        error.DataInMappingInvalid => "Error: invalid data type in the datum mapping.",
        error.WrongNumberOfOutputs => "Error: the number of outputs does not match the expected count.",
        error.ArgumentInPairInvalid => "Error: invalid argument in output transformation pair.",
        error.PaneInMappingInvalid => "Error: an invalid pane was referenced in the frames mapping.",
        else => "Error: an unexpected error occurred.",
    };
}

fn run(ctx: zli.CommandContext) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const debug = ctx.flag("debug", bool);

    const environ: *std.process.Environ = @ptrCast(@alignCast(ctx.data.?));

    runInternal(ctx, alloc, environ.*) catch |err| {
        if (debug) return err;
        std.debug.print("{s}\n", .{friendlyErrorMessage(err)});
        std.process.exit(1);
    };
}

fn runInternal(ctx: zli.CommandContext, alloc: std.mem.Allocator, environ: std.process.Environ) !void {
    const parsed_data = try parse(ctx, alloc);

    const out_filename = ctx.flag("out", []const u8);
    const force_file = out_filename.len > 0;
    const term_supports = checkTerminalSupportsKitty(environ);
    const should_display = !force_file and term_supports;

    if (std.mem.eql(u8, out_filename, "/dev/null")) {
        return;
    }

    var output_path: ?[]u8 = null;
    defer if (output_path) |p| alloc.free(p);

    if (force_file) {
        output_path = try alloc.dupe(u8, out_filename);
    } else if (!should_display) {
        output_path = try getNextOutputFilename(alloc, ctx.io);
    }

    const rendered = try Plot.plot_via_z2d(ctx.io, parsed_data, output_path);
    defer rendered.allocator.free(rendered.pixels);

    if (force_file) {
        std.debug.print("Saved to {s}\n", .{out_filename});
    } else if (should_display) {
        var stdout_fw = std.Io.File.stdout().writerStreaming(ctx.io, &.{});
        try renderToStdout(alloc, rendered, &stdout_fw.interface, ctx.io);
    } else {
        const filename = output_path.?;
        std.debug.print("Saved to {s}\n", .{filename});
    }
}
