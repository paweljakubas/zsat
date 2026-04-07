const std = @import("std");
const z2d = @import("z2d");
const inputs = @import("plot_types");

const Vector = inputs.Vector;
const InputElement = inputs.InputElement;
const InputElementRow = inputs.InputElementRow;
const Inputs = inputs.Inputs;
const ValsRange = inputs.ValsRange;
const determine_pane_bounds = inputs.determine_pane_bounds;

pub const RenderedImage = struct {
    pixels: []z2d.pixel.RGBA,
    width: i32,
    height: i32,
    allocator: std.mem.Allocator,
};

pub fn plot_via_z2d(parsed_data: anytype, output_path: ?[]const u8) !RenderedImage {
    if (parsed_data.panes.len == 0) {
        return error.NoPanes;
    }
    const pane = parsed_data.panes[0];
    var width: i32 = 800;
    var height: i32 = 600;
    if (pane.paneValue.paneSize) |s| {
        width = @intCast(s.width);
        height = @intCast(s.height);
    }

    var surface = try z2d.Surface.init(.image_surface_rgba, std.heap.page_allocator, width, height);
    defer surface.deinit(std.heap.page_allocator);

    var context = z2d.Context.init(std.heap.page_allocator, &surface);

    // White background (RGBA: 255, 255, 255, 255)
    context.setSourceToPixel(.{ .rgba = .{ .r = 255, .g = 255, .b = 255, .a = 255 } });
    try context.moveTo(0, 0);
    try context.lineTo(@floatFromInt(width), 0);
    try context.lineTo(@floatFromInt(width), @floatFromInt(height));
    try context.lineTo(0, @floatFromInt(height));
    try context.closePath();
    try context.fill();

    // Black lines (RGBA: 0, 0, 0, 255) - stroke
    context.setSourceToPixel(.{ .rgba = .{ .r = 0, .g = 0, .b = 0, .a = 255 } });
    context.setLineWidth(2.0);

    const bounds = determine_pane_bounds(@ptrCast(@constCast(&parsed_data.inputs)));
    const x_min = bounds.x[0];
    const x_max = bounds.x[1];
    const y_min = bounds.y[0];
    const y_max = bounds.y[1];
    const x_range = x_max - x_min;
    const y_range = y_max - y_min;

    const margin: f64 = 20.0;
    const draw_width = @as(f64, @floatFromInt(width)) - 2 * margin;
    const draw_height = @as(f64, @floatFromInt(height)) - 2 * margin;
    std.debug.print("DEBUG: draw area: {d}x{d}, margin={d}\n", .{ draw_width, draw_height, margin });

    if (x_range > 0 and y_range > 0) {
        const rX = draw_width / @as(f64, x_range);
        const rY = draw_height / @as(f64, y_range);
        const scale = @min(rX, rY);

        for (parsed_data.inputs.input) |row| {
            var cur_x: f64 = margin;
            var cur_y: f64 = @as(f64, @floatFromInt(height)) - margin;

            try context.moveTo(cur_x, cur_y);

            for (row.row) |elem| {
                switch (elem) {
                    .vector => |v| {
                        cur_x += @as(f64, v.x) * scale;
                        cur_y -= @as(f64, v.y) * scale;
                        try context.lineTo(cur_x, cur_y);
                    },
                    .point => {},
                }
            }

            try context.stroke();
        }
    }

    if (output_path) |filename| {
        try z2d.png_exporter.writeToPNGFile(surface, filename, .{});
    }

    const pixels = switch (surface) {
        .image_surface_rgba => |s| s.buf,
        else => unreachable,
    };
    const duped = try std.heap.page_allocator.dupe(z2d.pixel.RGBA, pixels);

    return .{
        .pixels = duped,
        .width = width,
        .height = height,
        .allocator = std.heap.page_allocator,
    };
}
