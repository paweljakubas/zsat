const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");
const z2d = @import("z2d");
const zigimg = @import("zigimg");
const Styles = @import("draw/styles.zig");
const Inputs = @import("draw/inputs.zig");
const Datum = @import("draw/datum.zig");
const Frames = @import("draw/frames.zig");
const Panes = @import("draw/panes.zig");

const Plot = @import("plot");

pub const ParsedData = struct {
    styles: []const Styles.Style,
    inputs: Inputs.Inputs,
    datum: Datum.DataElementValidated,
    panes: []const Panes.Pane,
    frames: Frames.OutputPaneValidated,
};

const style_flag = zli.Flag{
    .name = "styles",
    .shortcut = "s",
    .description = "Style(s) definition to be used in further steps when constructing the figure.",
    .type = .String,
    .default_value = .{ .String = "e0:{vec2d xy fixed [lw:20, lc: black, lo: 100, le:none, lj: none, ld: none]}" },
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

pub fn register(writer: *Writer, reader: *Reader, allocator: std.mem.Allocator) !*zli.Command {
    const cmd = try zli.Command.init(writer, reader, allocator, .{
        .name = "draw",
        .shortcut = "d",
        .description = "Construct figure for stdin data using styles, datum, outputs, panes and frames",
    }, run);

    try cmd.addFlag(style_flag);
    try cmd.addFlag(datum_flag);
    try cmd.addFlag(panes_flag);
    try cmd.addFlag(frames_flag);

    try cmd.addFlag(debug_flag);
    try cmd.addFlag(out_flag);

    return cmd;
}

fn parse(ctx: zli.CommandContext, alloc: std.mem.Allocator) !ParsedData {
    const debug = ctx.flag("debug", bool);
    const styles_str = ctx.flag("styles", []const u8);
    const datum_str = ctx.flag("datum", []const u8);
    const panes_str = ctx.flag("panes", []const u8);
    const frames_str = ctx.flag("frames", []const u8);

    const stdin_str = try std.fs.File.stdin().readToEndAlloc(alloc, 1024 * 1024);
    defer alloc.free(stdin_str);

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

    const numberOfOutputs: u8 = @intCast(inputs.input.len);
    const framesValidated = try Frames.validateConnection(alloc, numberOfOutputs, paneNames, frames);

    if (debug) {
        try ctx.writer.print("stdin:\n{s}\n", .{stdin_str});
        try ctx.writer.print("\n--styles {s}\n", .{styles_str});
        try ctx.writer.print("--datum {s}\n", .{datum_str});
        try ctx.writer.print("--panes {s}\n", .{panes_str});
        try ctx.writer.print("--frames {s}\n", .{frames_str});
    }

    return ParsedData{
        .styles = styles,
        .inputs = inputs,
        .datum = datumValidated,
        .panes = panes,
        .frames = framesValidated,
    };
}

fn checkTerminalSupportsKitty() bool {
    const term = std.posix.getenv("TERM") orelse return false;
    if (!std.mem.containsAtLeast(u8, term, 1, "xterm") and
        !std.mem.containsAtLeast(u8, term, 1, "kitty") and
        !std.mem.containsAtLeast(u8, term, 1, "ghostty")) return false;
    return true;
}

fn renderToStdout(allocator: std.mem.Allocator, img: Plot.RenderedImage, writer: anytype) !void {
    const original_width = img.width;
    const original_height = img.height;

    var term_cols: u16 = 80;
    var term_rows: u16 = 24;

    if (std.posix.isatty(std.posix.STDOUT_FILENO)) {
        var winsize: std.posix.winsize = undefined;
        if (std.posix.system.ioctl(1, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize)) == 0 and
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
    if (new_w < original_width or new_h < original_height) {
        const resized = try resizePixels(allocator, pixels, original_width, original_height, new_w, new_h);
        defer allocator.free(resized);
        pixels = resized;
    }

    var byte_data = try std.ArrayList(u8).initCapacity(allocator, pixels.len * 4);
    defer byte_data.deinit(allocator);
    for (pixels) |px| {
        try byte_data.append(allocator, px.r);
        try byte_data.append(allocator, px.g);
        try byte_data.append(allocator, px.b);
        try byte_data.append(allocator, px.a);
    }

    var encoded = try std.ArrayList(u8).initCapacity(allocator, std.base64.standard.Encoder.calcSize(byte_data.items.len));
    defer encoded.deinit(allocator);
    try encoded.resize(allocator, std.base64.standard.Encoder.calcSize(byte_data.items.len));
    _ = std.base64.standard.Encoder.encode(encoded.items, byte_data.items);

    try writer.writeAll("\n     ");
    const chunk_size = 4096;
    const data = encoded.items;
    if (data.len <= chunk_size) {
        try writer.print("\x1B_Gf=32,s={d},v={d},a=T;{s}\x1B\\", .{ img.width, img.height, data });
    } else {
        try writer.print("\x1B_Gf=32,s={d},v={d},a=T,m=1;{s}\x1B\\", .{ img.width, img.height, data[0..chunk_size] });
        var start: usize = chunk_size;
        while (start + chunk_size < data.len) {
            try writer.print("\x1B_Gm=1;{s}\x1B\\", .{data[start..][0..chunk_size]});
            start += chunk_size;
        }
        try writer.print("\x1B_Gm=0;{s}\x1B\\", .{data[start..]});
    }
    try writer.writeAll("\n\n");
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

fn renderImageToStdout(allocator: std.mem.Allocator, file: *std.fs.File, writer: anytype) !void {
    var read_buf: [65536]u8 = undefined;
    var img = try zigimg.Image.fromFile(allocator, file.*, &read_buf);
    defer img.deinit(allocator);

    const original_width = img.width;
    const original_height = img.height;

    var term_cols: u16 = 80;
    var term_rows: u16 = 24;
    var winsize: std.posix.winsize = undefined;
    if (std.posix.system.ioctl(1, std.posix.system.T.IOCGWINSZ, @intFromPtr(&winsize)) == 0) {
        term_cols = winsize.col;
        term_rows = winsize.row;
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

    try img.convert(allocator, .rgba32);

    if (new_w < original_width or new_h < original_height) {
        try resizeImage(allocator, &img, new_w, new_h);
    }

    var byte_data = try std.ArrayList(u8).initCapacity(allocator, img.pixels.rgba32.len * 4);
    defer byte_data.deinit(allocator);
    for (img.pixels.rgba32) |px| {
        try byte_data.append(allocator, px.r);
        try byte_data.append(allocator, px.g);
        try byte_data.append(allocator, px.b);
        try byte_data.append(allocator, px.a);
    }

    var encoded = try std.ArrayList(u8).initCapacity(allocator, std.base64.standard.Encoder.calcSize(byte_data.items.len));
    defer encoded.deinit(allocator);
    try encoded.resize(allocator, std.base64.standard.Encoder.calcSize(byte_data.items.len));
    _ = std.base64.standard.Encoder.encode(encoded.items, byte_data.items);

    try writer.writeAll("\n     ");
    const chunk_size = 4096;
    const data = encoded.items;
    if (data.len <= chunk_size) {
        try writer.print("\x1B_Gf=32,s={d},v={d},a=T;{s}\x1B\\", .{ img.width, img.height, data });
    } else {
        try writer.print("\x1B_Gf=32,s={d},v={d},a=T,m=1;{s}\x1B\\", .{ img.width, img.height, data[0..chunk_size] });
        var start: usize = chunk_size;
        while (start + chunk_size < data.len) {
            try writer.print("\x1B_Gm=1;{s}\x1B\\", .{data[start..][0..chunk_size]});
            start += chunk_size;
        }
        try writer.print("\x1B_Gm=0;{s}\x1B\\", .{data[start..]});
    }
    try writer.writeAll("\n\n");
    try writer.flush();
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

fn getSystemTmpDir(alloc: std.mem.Allocator) ![]u8 {
    const tmp_env = std.posix.getenv("TMPDIR") orelse "/tmp";
    const tmp_dir_path = if (tmp_env.len > 0) tmp_env else "/tmp";
    return try alloc.dupe(u8, tmp_dir_path);
}

fn getNextOutputFilename(alloc: std.mem.Allocator) ![]u8 {
    var n: u32 = 0;
    while (true) : (n += 1) {
        const filename = try std.fmt.allocPrint(alloc, "output{d}.png", .{n});
        errdefer alloc.free(filename);
        const file = std.fs.cwd().openFile(filename, .{}) catch {
            return filename;
        };
        file.close();
    }
}

fn run(ctx: zli.CommandContext) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed_data = try parse(ctx, alloc);

    const out_filename = ctx.flag("out", []const u8);
    const force_file = out_filename.len > 0;
    const term_supports = checkTerminalSupportsKitty();
    const should_display = !force_file and term_supports;

    var output_path: ?[]u8 = null;
    defer if (output_path) |p| alloc.free(p);

    if (force_file) {
        output_path = try alloc.dupe(u8, out_filename);
    } else if (!should_display) {
        output_path = try getNextOutputFilename(alloc);
    }

    const rendered = try Plot.plot_via_z2d(parsed_data, output_path);
    defer rendered.allocator.free(rendered.pixels);

    if (force_file) {
        std.debug.print("Saved to {s}\n", .{out_filename});
    } else if (should_display) {
        var stdout_writer = std.fs.File.stdout().writerStreaming(&.{});
        try renderToStdout(alloc, rendered, &stdout_writer.interface);
    } else {
        const filename = output_path.?;
        std.debug.print("Saved to {s}\n", .{filename});
    }
}
