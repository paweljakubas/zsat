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
    vector: Vector,
    point: Point,
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

pub fn determine_pane_bounds(rows: *const Inputs) ValsRange {
    var min_x: f32 = 0.0;
    var max_x: f32 = 0.0;
    var min_y: f32 = 0.0;
    var max_y: f32 = 0.0;
    var cur_x: f32 = 0.0;
    var cur_y: f32 = 0.0;
    var first = true;

    for (rows.input) |row| {
        for (row.row) |elem| {
            switch (elem) {
                .vector => |v| {
                    cur_x += v.x;
                    cur_y += v.y;
                    if (first) {
                        min_x = cur_x;
                        max_x = cur_x;
                        min_y = cur_y;
                        max_y = cur_y;
                        first = false;
                    } else {
                        if (cur_x < min_x) min_x = cur_x;
                        if (cur_x > max_x) max_x = cur_x;
                        if (cur_y < min_y) min_y = cur_y;
                        if (cur_y > max_y) max_y = cur_y;
                    }
                },
                .point => |p| {
                    cur_x = p.x;
                    cur_y = p.y;
                    if (first) {
                        min_x = cur_x;
                        max_x = cur_x;
                        min_y = cur_y;
                        max_y = cur_y;
                        first = false;
                    } else {
                        if (cur_x < min_x) min_x = cur_x;
                        if (cur_x > max_x) max_x = cur_x;
                        if (cur_y < min_y) min_y = cur_y;
                        if (cur_y > max_y) max_y = cur_y;
                    }
                },
            }
        }
    }

    return .{ .x = .{ min_x, max_x }, .y = .{ min_y, max_y } };
}
