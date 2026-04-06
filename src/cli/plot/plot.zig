const std = @import("std");
const testing = std.testing;
const z2d = @import("z2d");
const inputs = @import("cli");

const Vector = inputs.Vector;
const InputElement = inputs.InputElement;
const InputElementRow = inputs.InputElementRow;
const Inputs = inputs.Inputs;

pub const RenderedImage = struct {
    pixels: []z2d.pixel.RGBA,
    width: i32,
    height: i32,
    allocator: std.mem.Allocator,
};

const ValsRange = struct {
    x: [2]f32,
    y: [2]f32,
};

fn determine_pane_bounds(rows: *const Inputs) ValsRange {
    var min_x: f32 = undefined;
    var max_x: f32 = undefined;
    var min_y: f32 = undefined;
    var max_y: f32 = undefined;
    var initialized = false;

    for (rows.input) |row| {
        var cur_x: f32 = 0.0;
        var cur_y: f32 = 0.0;

        if (!initialized) {
            min_x = cur_x;
            max_x = cur_x;
            min_y = cur_y;
            max_y = cur_y;
            initialized = true;
        } else {
            if (cur_x < min_x) min_x = cur_x;
            if (cur_x > max_x) max_x = cur_x;
            if (cur_y < min_y) min_y = cur_y;
            if (cur_y > max_y) max_y = cur_y;
        }

        for (row.row) |elem| {
            switch (elem) {
                .vector => |v| {
                    cur_x += v.x;
                    cur_y += v.y;
                    if (cur_x < min_x) min_x = cur_x;
                    if (cur_x > max_x) max_x = cur_x;
                    if (cur_y < min_y) min_y = cur_y;
                    if (cur_y > max_y) max_y = cur_y;
                },
                .point => {},
            }
        }
    }

    return .{ .x = .{ min_x, max_x }, .y = .{ min_y, max_y } };
}

test "determine_pane_bounds" {
    const p1 = InputElement{ .vector = Vector{ .x = 2.0, .y = 1.1 } };
    const row1 = InputElementRow{ .row = &[1]InputElement{p1} };
    const in1 = Inputs{ .input = &[1]InputElementRow{row1} };
    const r1 = determine_pane_bounds(&in1);
    const range1 = ValsRange{ .x = .{ 0.0, 2.0 }, .y = .{ 0.0, 1.1 } };
    try testing.expectEqual(range1, r1);

    const p2 = InputElement{ .vector = Vector{ .x = -2.0, .y = -1.1 } };
    const row2 = InputElementRow{ .row = &[1]InputElement{p2} };
    const in2 = Inputs{ .input = &[1]InputElementRow{row2} };
    const r2 = determine_pane_bounds(&in2);
    const range2 = ValsRange{ .x = .{ -2.0, 0.0 }, .y = .{ -1.1, 0.0 } };
    try testing.expectEqual(range2, r2);

    const p3a = InputElement{ .vector = Vector{ .x = 0.0, .y = 1.0 } };
    const p3b = InputElement{ .vector = Vector{ .x = 0.0, .y = -1.0 } };
    const p3c = InputElement{ .vector = Vector{ .x = 1.0, .y = 0.0 } };
    const row3 = InputElementRow{ .row = &[3]InputElement{ p3a, p3b, p3c } };
    const in3 = Inputs{ .input = &[1]InputElementRow{row3} };
    const r3 = determine_pane_bounds(&in3);
    const range3 = ValsRange{ .x = .{ 0.0, 1.0 }, .y = .{ 0.0, 1.0 } };
    try testing.expectEqual(range3, r3);

    const p4a = InputElement{ .vector = Vector{ .x = 0.0, .y = 1.0 } };
    const p4b = InputElement{ .vector = Vector{ .x = 0.0, .y = -1.0 } };
    const p4c = InputElement{ .vector = Vector{ .x = 1.0, .y = 0.0 } };
    const row4a = InputElementRow{ .row = &[2]InputElement{ p4a, p4b } };
    const row4b = InputElementRow{ .row = &[1]InputElement{p4c} };
    const in4 = Inputs{ .input = &[2]InputElementRow{ row4a, row4b } };
    const r4 = determine_pane_bounds(&in4);
    const range4 = ValsRange{ .x = .{ 0.0, 1.0 }, .y = .{ 0.0, 1.0 } };
    try testing.expectEqual(range4, r4);

    const p5a = InputElement{ .vector = Vector{ .x = 3.0, .y = 1.0 } };
    const p5b = InputElement{ .vector = Vector{ .x = -3.0, .y = 1.0 } };
    const p5c = InputElement{ .vector = Vector{ .x = 2.0, .y = -1.0 } };
    const row5a = InputElementRow{ .row = &[2]InputElement{ p5a, p5b } };
    const row5b = InputElementRow{ .row = &[1]InputElement{p5c} };
    const in5 = Inputs{ .input = &[2]InputElementRow{ row5a, row5b } };
    const r5 = determine_pane_bounds(&in5);
    const range5 = ValsRange{ .x = .{ 0.0, 3.0 }, .y = .{ -1.0, 2.0 } };
    try testing.expectEqual(range5, r5);
}

pub fn plot_via_z2d(parsed_data: anytype, output_path: ?[]const u8) !RenderedImage {
    if (parsed_data.panes.len == 0) {
        return error.NoPanes;
    }
    const pane = parsed_data.panes[0];
    const PaneSize = @import("draw_panes").PaneSize;
    const size = pane.paneValue.paneSize orelse PaneSize.defaultPaneSize();

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
