const std = @import("std");
const testing = std.testing;
const z2d = @import("z2d");

const pi: f64 = std.math.pi;

/// Point marker style resolved from a pt2d style value.
pub const PointStyle = struct {
    shape: PointShape,
    size: u16, // diameter (circle) / side length (square) in pixels
};

/// The point marker shape.
pub const PointShape = enum {
    circle,
    square,
};

/// Resolves the point marker style (shape, size) for a given input row from
/// the parsed style definitions. Returns `null` when the resolved style is not
/// a pt2d style or carries no attributes.
///
/// Color and opacity are handled by the caller via the shared `lineColor` and
/// `lineOpacity` attributes.
///
/// Example:
/// ```
/// const ps = resolvePointStyle(&styles, &mappings, 0);
/// // ps.?.shape == .circle, ps.?.size == 10
/// ```
pub fn resolvePointStyle(styles: anytype, mappings: anytype, row_idx: usize) ?PointStyle {
    var style_idx: ?usize = null;
    for (mappings) |mapping| {
        if (mapping.from == row_idx) {
            style_idx = mapping.to;
            break;
        }
    }

    const idx = style_idx orelse return null;
    if (idx >= styles.len) return null;
    const style = styles[idx];
    if (style.styleValue.styleType != .pt2d) return null;
    const attrs = style.styleValue.attributes orelse return null;

    return .{
        .shape = if (attrs.pointShape != null) switch (attrs.pointShape.?.value) {
            .circle => .circle,
            .square => .square,
        } else .circle,
        .size = if (attrs.pointSize != null) attrs.pointSize.?.value else 10,
    };
}

/// Draws each point element of the given input row as a marker (circle or
/// square) using the current source color. Converts polar coordinates
/// `(r, phi)` to Cartesian when `coordinate_type == .polar`.
///
/// The marker is centered on the point's plot coordinate, with size in pixels
/// (diameter for circles, side length for squares). Plot Y is clamped to the
/// `[min_y, max_y]` viewport bounds, matching the vec2d behavior.
///
/// Example:
/// ```
/// try drawPoints(&ctx, &input_data, 0, origin_x, origin_y, x_scale, y_scale, min_y, max_y, .xy, .circle, 10);
/// ```
pub fn drawPoints(context: *z2d.Context, input_data: anytype, row_idx: usize, origin_x: f64, origin_y: f64, x_scale: f64, y_scale: f64, min_y: f64, max_y: f64, coordinate_type: anytype, shape: anytype, size: u16) !void {
    if (row_idx >= input_data.input.len) return;
    const input_row = input_data.input[row_idx];
    const half: f64 = @as(f64, @floatFromInt(size)) / 2.0;

    for (input_row.row) |elem| {
        switch (elem) {
            .point => |p| {
                var px = @as(f64, p.x);
                var py = @as(f64, p.y);
                if (coordinate_type == .polar) {
                    const angle_rad = @as(f64, p.y) * pi / 180.0;
                    px = @as(f64, p.x) * @cos(angle_rad);
                    py = @as(f64, p.x) * @sin(angle_rad);
                }
                const plot_x = origin_x + px * x_scale;
                var plot_y = origin_y - py * y_scale;
                if (plot_y < min_y) plot_y = min_y;
                if (plot_y > max_y) plot_y = max_y;

                context.resetPath();
                switch (shape) {
                    .circle => {
                        try context.arc(plot_x, plot_y, half, 0, 2 * pi);
                        try context.closePath();
                    },
                    .square => {
                        try context.moveTo(plot_x - half, plot_y - half);
                        try context.lineTo(plot_x + half, plot_y - half);
                        try context.lineTo(plot_x + half, plot_y + half);
                        try context.lineTo(plot_x - half, plot_y + half);
                        try context.closePath();
                    },
                }
                try context.fill();
            },
            .vector => {},
            .vectors => {},
        }
    }
}

/// Draws a marker at each explicit anchor point of an output transformation.
/// Used when the output transform (e.g. mirror) repositions the input points:
/// the markers follow the transformed anchor coordinates instead of the raw
/// input points. Polar conversion matches `drawPoints`.
pub fn drawOutputPoints(context: *z2d.Context, ops: anytype, origin_x: f64, origin_y: f64, x_scale: f64, y_scale: f64, min_y: f64, max_y: f64, coordinate_type: anytype, shape: anytype, size: u16) !void {
    const half: f64 = @as(f64, @floatFromInt(size)) / 2.0;

    for (ops) |op| {
        if (op == .anchor and op.anchor.point == .point) {
            const p = op.anchor.point.point;
            var px = @as(f64, p.x);
            var py = @as(f64, p.y);
            if (coordinate_type == .polar) {
                const angle_rad = @as(f64, p.y) * pi / 180.0;
                px = @as(f64, p.x) * @cos(angle_rad);
                py = @as(f64, p.x) * @sin(angle_rad);
            }
            const plot_x = origin_x + px * x_scale;
            var plot_y = origin_y - py * y_scale;
            if (plot_y < min_y) plot_y = min_y;
            if (plot_y > max_y) plot_y = max_y;

            context.resetPath();
            switch (shape) {
                .circle => {
                    try context.arc(plot_x, plot_y, half, 0, 2 * pi);
                    try context.closePath();
                },
                .square => {
                    try context.moveTo(plot_x - half, plot_y - half);
                    try context.lineTo(plot_x + half, plot_y - half);
                    try context.lineTo(plot_x + half, plot_y + half);
                    try context.lineTo(plot_x - half, plot_y + half);
                    try context.closePath();
                },
            }
            try context.fill();
        }
    }
}

test "resolvePointStyle" {
    const TestStyleValue = struct {
        styleType: enum { vec2d, pt2d },
        attributes: ?struct { pointShape: ?struct { value: enum { circle, square } }, pointSize: ?struct { value: u16 } },
    };
    const TestStyle = struct { styleValue: TestStyleValue };
    const TestMapping = struct { from: usize, to: usize };

    const styles = [_]TestStyle{
        .{ .styleValue = .{ .styleType = .pt2d, .attributes = .{ .pointShape = .{ .value = .square }, .pointSize = .{ .value = 5 } } } },
        .{ .styleValue = .{ .styleType = .vec2d, .attributes = .{ .pointShape = null, .pointSize = null } } },
    };
    const mappings = [_]TestMapping{
        .{ .from = 0, .to = 0 },
        .{ .from = 1, .to = 1 },
    };

    const ps = resolvePointStyle(&styles, &mappings, 0);
    try testing.expect(ps != null);
    try testing.expectEqual(PointShape.square, ps.?.shape);
    try testing.expectEqual(@as(u16, 5), ps.?.size);

    try testing.expectEqual(@as(?PointStyle, null), resolvePointStyle(&styles, &mappings, 1));
    try testing.expectEqual(@as(?PointStyle, null), resolvePointStyle(&styles, &mappings, 5));
}

test "resolvePointStyle defaults" {
    const TestStyleValue = struct {
        styleType: enum { vec2d, pt2d },
        attributes: ?struct { pointShape: ?struct { value: enum { circle, square } }, pointSize: ?struct { value: u16 } },
    };
    const TestStyle = struct { styleValue: TestStyleValue };
    const TestMapping = struct { from: usize, to: usize };

    const styles = [_]TestStyle{
        .{ .styleValue = .{ .styleType = .pt2d, .attributes = .{ .pointShape = null, .pointSize = null } } },
    };
    const mappings = [_]TestMapping{.{ .from = 0, .to = 0 }};

    const ps = resolvePointStyle(&styles, &mappings, 0);
    try testing.expect(ps != null);
    try testing.expectEqual(PointShape.circle, ps.?.shape);
    try testing.expectEqual(@as(u16, 10), ps.?.size);
}

test "resolvePointStyle no attributes" {
    const TestStyleValue = struct {
        styleType: enum { vec2d, pt2d },
        attributes: ?struct { pointShape: ?struct { value: enum { circle, square } }, pointSize: ?struct { value: u16 } },
    };
    const TestStyle = struct { styleValue: TestStyleValue };
    const TestMapping = struct { from: usize, to: usize };

    const styles = [_]TestStyle{
        .{ .styleValue = .{ .styleType = .pt2d, .attributes = null } },
    };
    const mappings = [_]TestMapping{.{ .from = 0, .to = 0 }};

    try testing.expectEqual(@as(?PointStyle, null), resolvePointStyle(&styles, &mappings, 0));
}
