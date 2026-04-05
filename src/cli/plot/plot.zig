const std = @import("std");
const testing = std.testing;
const z2d = @import("z2d");
const Panes = @import("../draw/panes.zig");

pub const ParsedData = @import("../draw.zig").ParsedData;

pub const RenderedImage = struct {
    pixels: []z2d.pixel.RGBA,
    width: i32,
    height: i32,
    allocator: std.mem.Allocator,
};

pub fn plot_via_z2d(parsed_data: ParsedData, output_path: ?[]const u8) !RenderedImage {
    if (parsed_data.panes.len == 0) {
        return error.NoPanes;
    }
    const pane = parsed_data.panes[0];
    const size = pane.paneValue.paneSize orelse Panes.PaneSize.defaultPaneSize();

    const width: i32 = @intCast(size.width);
    const height: i32 = @intCast(size.height);

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
