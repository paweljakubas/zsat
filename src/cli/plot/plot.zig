const std = @import("std");
const testing = std.testing;
const z2d = @import("z2d");
const Panes = @import("../draw/panes.zig");

pub const ParsedData = @import("../draw.zig").ParsedData;

pub fn plot_via_z2d(parsed_data: ParsedData, output_path: ?[]const u8) !void {
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

    const filename = output_path orelse "output.png";
    try z2d.png_exporter.writeToPNGFile(surface, filename, .{});
}
