// Local copy of inputs types for plot.zig to avoid module conflicts
const std = @import("std");
const testing = std.testing;

pub const Vector = extern struct {
    x: f32,
    y: f32,
};

pub const Point = extern struct {
    x: f32,
    y: f32,
};

pub const InputElement = union(enum) {
    point: Point,
    vector: Vector,
};

pub const InputElementRow = struct {
    row: []const InputElement,
};

// This must match draw/inputs.zig Inputs struct exactly
pub const Inputs = struct {
    input: []const InputElementRow,
};

pub const ValsRange = struct {
    x: [2]f32,
    y: [2]f32,
};

test "determine_pane_bounds" {
    const p1 = InputElement{ .vector = Vector{ .x = 2.0, .y = 1.1 } };
    const row1 = InputElementRow{ .row = &[1]InputElement{p1} };
    const in1 = Inputs{ .input = &[1]InputElementRow{row1} };
    const r1 = determine_pane_bounds(&in1, &.{});
    const range1 = ValsRange{ .x = .{ 0.0, 2.0 }, .y = .{ 0.0, 1.1 } };
    try testing.expectEqual(range1, r1);

    const p2 = InputElement{ .vector = Vector{ .x = -2.0, .y = -1.1 } };
    const row2 = InputElementRow{ .row = &[1]InputElement{p2} };
    const in2 = Inputs{ .input = &[1]InputElementRow{row2} };
    const r2 = determine_pane_bounds(&in2, &.{});
    const range2 = ValsRange{ .x = .{ -2.0, 0.0 }, .y = .{ -1.1, 0.0 } };
    try testing.expectEqual(range2, r2);

    const p3a = InputElement{ .vector = Vector{ .x = 0.0, .y = 1.0 } };
    const p3b = InputElement{ .vector = Vector{ .x = 0.0, .y = -1.0 } };
    const p3c = InputElement{ .vector = Vector{ .x = 1.0, .y = 0.0 } };
    const row3 = InputElementRow{ .row = &[3]InputElement{ p3a, p3b, p3c } };
    const in3 = Inputs{ .input = &[1]InputElementRow{row3} };
    const r3 = determine_pane_bounds(&in3, &.{});
    const range3 = ValsRange{ .x = .{ 0.0, 1.0 }, .y = .{ 0.0, 1.0 } };
    try testing.expectEqual(range3, r3);

    const p4a = InputElement{ .vector = Vector{ .x = 0.0, .y = 1.0 } };
    const p4b = InputElement{ .vector = Vector{ .x = 0.0, .y = -1.0 } };
    const p4c = InputElement{ .vector = Vector{ .x = 1.0, .y = 0.0 } };
    const row4a = InputElementRow{ .row = &[2]InputElement{ p4a, p4b } };
    const row4b = InputElementRow{ .row = &[1]InputElement{p4c} };
    const in4 = Inputs{ .input = &[2]InputElementRow{ row4a, row4b } };
    const r4 = determine_pane_bounds(&in4, &.{});
    const range4 = ValsRange{ .x = .{ 0.0, 1.0 }, .y = .{ 0.0, 1.0 } };
    try testing.expectEqual(range4, r4);

    const p5a = InputElement{ .vector = Vector{ .x = 3.0, .y = 1.0 } };
    const p5b = InputElement{ .vector = Vector{ .x = -3.0, .y = 1.0 } };
    const p5c = InputElement{ .vector = Vector{ .x = 2.0, .y = -1.0 } };
    const row5a = InputElementRow{ .row = &[2]InputElement{ p5a, p5b } };
    const row5b = InputElementRow{ .row = &[1]InputElement{p5c} };
    const in5 = Inputs{ .input = &[2]InputElementRow{ row5a, row5b } };
    const r5 = determine_pane_bounds(&in5, &.{});
    const range5 = ValsRange{ .x = .{ 0.0, 3.0 }, .y = .{ -1.0, 2.0 } };
    try testing.expectEqual(range5, r5);
}

test "determine_pane_bounds with anchors at (0,0)" {
    const v1 = InputElement{ .vector = Vector{ .x = 2.0, .y = 1.0 } };
    const row1 = InputElementRow{ .row = &[1]InputElement{v1} };
    const in1 = Inputs{ .input = &[1]InputElementRow{row1} };
    const anchors1 = &[1]?Vector{Vector{ .x = 0.0, .y = 0.0 }};
    const r1 = determine_pane_bounds(&in1, anchors1);
    const range1 = ValsRange{ .x = .{ 0.0, 2.0 }, .y = .{ 0.0, 1.0 } };
    try testing.expectEqual(range1, r1);
}

test "determine_pane_bounds with anchors at non-zero point" {
    const v1 = InputElement{ .vector = Vector{ .x = 1.0, .y = 1.0 } };
    const row1 = InputElementRow{ .row = &[1]InputElement{v1} };
    const in1 = Inputs{ .input = &[1]InputElementRow{row1} };
    const anchors1 = &[1]?Vector{Vector{ .x = -1.0, .y = 3.0 }};
    const r1 = determine_pane_bounds(&in1, anchors1);
    const range1 = ValsRange{ .x = .{ -1.0, 0.0 }, .y = .{ 0.0, 4.0 } };
    try testing.expectEqual(range1, r1);

    const v2a = InputElement{ .vector = Vector{ .x = 1.0, .y = 1.0 } };
    const v2b = InputElement{ .vector = Vector{ .x = -2.0, .y = 2.0 } };
    const row2 = InputElementRow{ .row = &[2]InputElement{ v2a, v2b } };
    const in2 = Inputs{ .input = &[1]InputElementRow{row2} };
    const anchors2 = &[1]?Vector{Vector{ .x = 0.0, .y = 0.0 }};
    const r2 = determine_pane_bounds(&in2, anchors2);
    const range2 = ValsRange{ .x = .{ 0.0, 1.0 }, .y = .{ 0.0, 3.0 } };
    try testing.expectEqual(range2, r2);

    const v3a = InputElement{ .vector = Vector{ .x = 1.0, .y = 1.0 } };
    const v3b = InputElement{ .vector = Vector{ .x = -2.0, .y = 2.0 } };
    const row3a = InputElementRow{ .row = &[1]InputElement{v3a} };
    const row3b = InputElementRow{ .row = &[1]InputElement{v3b} };
    const in3 = Inputs{ .input = &[2]InputElementRow{ row3a, row3b } };
    const anchors3 = &[2]?Vector{ null, Vector{ .x = 0.0, .y = 0.0 } };
    const r3 = determine_pane_bounds(&in3, anchors3);
    const range3 = ValsRange{ .x = .{ 0.0, 1.0 }, .y = .{ 0.0, 3.0 } };
    try testing.expectEqual(range3, r3);
}

test "determine_pane_bounds with multiple rows and anchors" {
    const v1 = InputElement{ .vector = Vector{ .x = 0.0, .y = 1.0 } };
    const row1 = InputElementRow{ .row = &[1]InputElement{v1} };
    const v2a = InputElement{ .vector = Vector{ .x = 1.0, .y = 1.0 } };
    const v2b = InputElement{ .vector = Vector{ .x = -2.0, .y = 2.0 } };
    const row2 = InputElementRow{ .row = &[2]InputElement{ v2a, v2b } };
    const in1 = Inputs{ .input = &[2]InputElementRow{ row1, row2 } };
    const anchors = &[2]?Vector{ Vector{ .x = -1.0, .y = 3.0 }, Vector{ .x = 0.0, .y = 0.0 } };
    const r1 = determine_pane_bounds(&in1, anchors);
    const range1 = ValsRange{ .x = .{ -1.0, 1.0 }, .y = .{ 0.0, 4.0 } };
    try testing.expectEqual(range1, r1);
}

pub fn determine_paneBoundsWithAnchors(rows: *const Inputs, anchor_points: anytype) ValsRange {
    var minX: f32 = 0.0;
    var maxX: f32 = 0.0;
    var minY: f32 = 0.0;
    var maxY: f32 = 0.0;

    for (rows.input, 0..) |row, row_idx| {
        if (row.row.len == 0) continue;

        var curX: f32 = 0.0;
        var curY: f32 = 0.0;

        if (anchor_points.len > row_idx) {
            if (anchor_points[row_idx]) |anchor| {
                curX = anchor.x;
                curY = anchor.y;
            }
        }

        if (curX < minX) minX = curX;
        if (curX > maxX) maxX = curX;
        if (curY < minY) minY = curY;
        if (curY > maxY) maxY = curY;

        for (row.row) |elem| {
            switch (elem) {
                .vector => |v| {
                    curX = curX + v.x;
                    curY = curY + v.y;
                },
                .vectors => |vs| {
                    for (vs) |v| {
                        curX = curX + v.x;
                        curY = curY + v.y;
                    }
                },
                .point => |p| {
                    curX = p.x;
                    curY = p.y;
                },
            }
            if (curX < minX) minX = curX;
            if (curX > maxX) maxX = curX;
            if (curY < minY) minY = curY;
            if (curY > maxY) maxY = curY;
        }
    }

    return .{ .x = .{ minX, maxX }, .y = .{ minY, maxY } };
}

pub fn determine_paneBoundsWithStartAndEnd(rows: *const Inputs, anchor_points: anytype, anchor_end_points: anytype) ValsRange {
    var minX: f32 = 0.0;
    var maxX: f32 = 0.0;
    var minY: f32 = 0.0;
    var maxY: f32 = 0.0;

    for (rows.input, 0..) |row, row_idx| {
        if (row.row.len == 0) continue;

        var curX: f32 = 0.0;
        var curY: f32 = 0.0;

        // Use start point (anchor_points)
        if (anchor_points.len > row_idx) {
            if (anchor_points[row_idx]) |anchor| {
                curX = anchor.x;
                curY = anchor.y;
            }
        }

        if (curX < minX) minX = curX;
        if (curX > maxX) maxX = curX;
        if (curY < minY) minY = curY;
        if (curY > maxY) maxY = curY;

        // Use end point (anchor_end_points)
        if (anchor_end_points.len > row_idx) {
            if (anchor_end_points[row_idx]) |end| {
                curX = end.x;
                curY = end.y;
            }
        }

        if (curX < minX) minX = curX;
        if (curX > maxX) maxX = curX;
        if (curY < minY) minY = curY;
        if (curY > maxY) maxY = curY;
    }

    return .{ .x = .{ minX, maxX }, .y = .{ minY, maxY } };
}

pub fn determine_pane_bounds(rows: *const Inputs, anchor_points: anytype) ValsRange {
    return determine_paneBoundsWithAnchors(rows, anchor_points);
}

pub fn determine_pane_bounds_with_end(rows: *const Inputs, anchor_points: anytype, anchor_end_points: anytype) ValsRange {
    return determine_paneBoundsWithStartAndEnd(rows, anchor_points, anchor_end_points);
}
