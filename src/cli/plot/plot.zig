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
    var width: i32 = 600;
    var height: i32 = 600;
    if (pane.paneValue.paneSize) |s| {
        width = @intCast(s.width);
        height = @intCast(s.height);
    }

    var surface = try z2d.Surface.init(.image_surface_rgba, std.heap.page_allocator, width, height);
    defer surface.deinit(std.heap.page_allocator);

    var context = z2d.Context.init(std.heap.page_allocator, &surface);

    context.setSourceToPixel(.{ .rgba = .{ .r = 255, .g = 255, .b = 255, .a = 255 } });
    try context.moveTo(0, 0);
    try context.lineTo(@floatFromInt(width), 0);
    try context.lineTo(@floatFromInt(width), @floatFromInt(height));
    try context.lineTo(0, @floatFromInt(height));
    try context.closePath();
    try context.fill();

    context.setSourceToPixel(.{ .rgba = .{ .r = 0, .g = 0, .b = 0, .a = 255 } });
    context.setLineWidth(10.0);

    const bounds = determine_pane_bounds(@ptrCast(&parsed_data.inputs));
    const x_range = bounds.x[1] - bounds.x[0];
    const y_range = bounds.y[1] - bounds.y[0];

    const margin: f64 = 20.0;
    const draw_width = @as(f64, @floatFromInt(width)) - 2 * margin;
    const draw_height = @as(f64, @floatFromInt(height)) - 2 * margin;

    if (x_range >= 0 and y_range >= 0) {
        const rX = if (x_range > 0) draw_width / @as(f64, x_range) else draw_width;
        const rY = if (y_range > 0) draw_height / @as(f64, y_range) else draw_height;

        const x_scale = rX;
        const y_scale = rY;

        const origin_x = margin - @as(f64, bounds.x[0]) * x_scale;
        const origin_y = @as(f64, @floatFromInt(height)) - margin;
        const min_y = margin;
        const max_y = @as(f64, @floatFromInt(height)) - margin;

        for (parsed_data.inputs.input) |row| {
            var cur_x = origin_x;
            var cur_y = origin_y;
            try context.moveTo(cur_x, cur_y);

            for (row.row) |elem| {
                switch (elem) {
                    .vector => |v| {
                        cur_x += @as(f64, v.x) * x_scale;
                        cur_y -= @as(f64, v.y) * y_scale;
                        if (cur_y < min_y) cur_y = min_y;
                        if (cur_y > max_y) cur_y = max_y;
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
