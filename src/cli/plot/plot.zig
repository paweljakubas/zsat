const std = @import("std");
const testing = std.testing;
const z2d = @import("z2d");
const inputs = @import("plot_types");

const Vector = inputs.Vector;
const InputElement = inputs.InputElement;
const InputElementRow = inputs.InputElementRow;
const Inputs = inputs.Inputs;
const ValsRange = inputs.ValsRange;
const determine_pane_bounds = inputs.determine_pane_bounds;
const determine_pane_bounds_with_end = inputs.determine_pane_bounds_with_end;

const CoordinateType = enum {
    xy,
    polar,
};

const pi: f32 = 3.14159265359;

/// Converts a polar vector (r, phi_degrees) to Cartesian (x, y).
fn polarToCartesian(v: Vector) Vector {
    const angle_rad = v.y * pi / 180.0;
    return Vector{ .x = v.x * @cos(angle_rad), .y = v.x * @sin(angle_rad) };
}

test "getAnchorPoint" {
    const TestPoint = struct { x: f32, y: f32 };
    const TestAnchorPoint = union(enum) { point: TestPoint, fraction: void, beginning: void, end: void, middle: void };
    const TestAnchor = struct { point: TestAnchorPoint };
    const TestOp = union(enum) { anchor: TestAnchor, rotate: void, scale: void, mirror: void, none: void };
    const TestOps = struct { ops: []const TestOp };
    const TestPair = struct { operation: TestOps };

    // Empty pairs
    try testing.expectEqual(@as(?Vector, null), getAnchorPoint(&[0]TestPair{}, 0));

    // Single anchor at (5,6)
    const op1 = TestOp{ .anchor = .{ .point = .{ .point = .{ .x = 5.0, .y = 6.0 } } } };
    const pair1 = TestPair{ .operation = .{ .ops = &[1]TestOp{op1} } };
    const r1 = getAnchorPoint(&[1]TestPair{pair1}, 0);
    try testing.expectEqual(@as(f32, 5.0), r1.?.x);
    try testing.expectEqual(@as(f32, 6.0), r1.?.y);

    // Multiple ops, returns the last anchor point
    const op2a = TestOp{ .rotate = {} };
    const op2b = TestOp{ .anchor = .{ .point = .{ .point = .{ .x = 1.0, .y = 2.0 } } } };
    const op2c = TestOp{ .anchor = .{ .point = .{ .point = .{ .x = 3.0, .y = 4.0 } } } };
    const pair2 = TestPair{ .operation = .{ .ops = &[3]TestOp{ op2a, op2b, op2c } } };
    const r2 = getAnchorPoint(&[1]TestPair{pair2}, 0);
    try testing.expectEqual(@as(f32, 3.0), r2.?.x);
    try testing.expectEqual(@as(f32, 4.0), r2.?.y);

    // Non-point anchor (fraction) is skipped
    const op3a = TestOp{ .anchor = .{ .point = .{ .fraction = {} } } };
    const pair3 = TestPair{ .operation = .{ .ops = &[1]TestOp{op3a} } };
    try testing.expectEqual(@as(?Vector, null), getAnchorPoint(&[1]TestPair{pair3}, 0));

    // Index out of bounds
    try testing.expectEqual(@as(?Vector, null), getAnchorPoint(&[1]TestPair{pair1}, 5));
}

/// Returns the last explicit point anchor for a given output, or null if none found.
///
/// Scans all operations in the transformation pair for the given output index,
/// returning the coordinates of the last one that is an anchor with an explicit point.
/// Non-anchor ops (rotate, scale, mirror) and non-point anchors (fraction, beginning,
/// end, middle) are ignored.
///
/// Example:
/// ```
/// const pt = getAnchorPoint(&pairs, 0);
/// // pt = Vector{ .x = last_anchor.x, .y = last_anchor.y } or null
/// ```
fn getAnchorPoint(transformationPairs: anytype, output_index: usize) ?Vector {
    if (transformationPairs.len == 0 or output_index >= transformationPairs.len) {
        return null;
    }
    const pair = transformationPairs[output_index];
    const ops = pair.operation.ops;
    if (ops.len == 0) {
        return null;
    }
    var last_pin: ?Vector = null;
    for (ops) |op| {
        if (op == .anchor and op.anchor.point == .point) {
            const p = op.anchor.point.point;
            last_pin = Vector{ .x = p.x, .y = p.y };
        }
    }
    return last_pin;
}

/// A rendered plot image, returned as RGBA pixel data.
pub const RenderedImage = struct {
    pixels: []z2d.pixel.RGBA,
    width: i32,
    height: i32,
    allocator: std.mem.Allocator,
};

/// Resolved line style: width, color, cap mode, and join mode.
/// Dashing is applied directly to the context during resolution.
const LineStyle = struct {
    width: f64,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
    cap_mode: z2d.options.CapMode,
    join_mode: z2d.options.JoinMode,
};

test "countVectors" {
    const TestElem = union(enum) { point: struct { x: f32, y: f32 }, vector: struct { x: f32, y: f32 }, vectors: []const struct { x: f32, y: f32 } };
    const TestRow = struct { row: []const TestElem };

    // Two vectors, one point
    const row1 = TestRow{ .row = &[3]TestElem{
        .{ .vector = .{ .x = 1, .y = 2 } },
        .{ .point = .{ .x = 3, .y = 4 } },
        .{ .vector = .{ .x = 5, .y = 6 } },
    } };
    try testing.expectEqual(@as(usize, 2), countVectors(&row1));

    // Only points
    const row2 = TestRow{ .row = &[2]TestElem{
        .{ .point = .{ .x = 1, .y = 2 } },
        .{ .point = .{ .x = 3, .y = 4 } },
    } };
    try testing.expectEqual(@as(usize, 0), countVectors(&row2));

    // Empty row
    const row3 = TestRow{ .row = &[0]TestElem{} };
    try testing.expectEqual(@as(usize, 0), countVectors(&row3));

    // All vectors
    const row4 = TestRow{ .row = &[3]TestElem{
        .{ .vector = .{ .x = 1, .y = 1 } },
        .{ .vector = .{ .x = 2, .y = 2 } },
        .{ .vector = .{ .x = 3, .y = 3 } },
    } };
    try testing.expectEqual(@as(usize, 3), countVectors(&row4));
}

/// Counts the number of vector elements in an input row.
/// Point elements are ignored.
///
/// Example:
/// ```
/// const n = countVectors(row);
/// // n = number of InputElement.vector entries in the row
/// ```
fn countVectors(row: anytype) usize {
    var count: usize = 0;
    for (row.row) |elem| {
        switch (elem) {
            .vector => count += 1,
            .vectors => |vs| count += vs.len,
            .point => {},
        }
    }
    return count;
}

/// Checks whether ops are begin/end pairs produced by processOriginFixed.
/// Each pair must have a delta equal to the sum of input vectors.
fn isBeginEndPairs(ops: anytype, input_data: anytype, row_idx: usize) bool {
    if (ops.len % 2 != 0 or row_idx >= input_data.input.len) return false;
    const input_row = input_data.input[row_idx];
    var sum_x: f32 = 0;
    var sum_y: f32 = 0;
    for (input_row.row) |elem| {
        switch (elem) {
            .vector => |v| {
                sum_x += v.x;
                sum_y += v.y;
            },
            .vectors => |vs| {
                for (vs) |v| {
                    sum_x += v.x;
                    sum_y += v.y;
                }
            },
            .point => {},
        }
    }
    for (0..ops.len / 2) |i| {
        const begin_op = ops[i * 2];
        const end_op = ops[i * 2 + 1];
        if (begin_op != .anchor or begin_op.anchor.point != .point or
            end_op != .anchor or end_op.anchor.point != .point)
        {
            return false;
        }
        const dx = end_op.anchor.point.point.x - begin_op.anchor.point.point.x;
        const dy = end_op.anchor.point.point.y - begin_op.anchor.point.point.y;
        if (@abs(dx - sum_x) > 0.001 or @abs(dy - sum_y) > 0.001) {
            return false;
        }
    }
    return true;
}

test "updateBounds" {
    var minX: f32 = 0;
    var maxX: f32 = 0;
    var minY: f32 = 0;
    var maxY: f32 = 0;
    var initialized = false;

    // First call initializes bounds to the point
    updateBounds(5.0, 10.0, &minX, &maxX, &minY, &maxY, &initialized);
    try testing.expect(initialized);
    try testing.expectEqual(@as(f32, 5.0), minX);
    try testing.expectEqual(@as(f32, 5.0), maxX);
    try testing.expectEqual(@as(f32, 10.0), minY);
    try testing.expectEqual(@as(f32, 10.0), maxY);

    // Wider point expands max
    updateBounds(15.0, 20.0, &minX, &maxX, &minY, &maxY, &initialized);
    try testing.expectEqual(@as(f32, 5.0), minX);
    try testing.expectEqual(@as(f32, 15.0), maxX);
    try testing.expectEqual(@as(f32, 10.0), minY);
    try testing.expectEqual(@as(f32, 20.0), maxY);

    // Negative point expands min
    updateBounds(-5.0, -10.0, &minX, &maxX, &minY, &maxY, &initialized);
    try testing.expectEqual(@as(f32, -5.0), minX);
    try testing.expectEqual(@as(f32, 15.0), maxX);
    try testing.expectEqual(@as(f32, -10.0), minY);
    try testing.expectEqual(@as(f32, 20.0), maxY);

    // Point within existing bounds does not change them
    updateBounds(0.0, 0.0, &minX, &maxX, &minY, &maxY, &initialized);
    try testing.expectEqual(@as(f32, -5.0), minX);
    try testing.expectEqual(@as(f32, 15.0), maxX);
    try testing.expectEqual(@as(f32, -10.0), minY);
    try testing.expectEqual(@as(f32, 20.0), maxY);
}

/// Updates running min/max bounds with a new point. Initializes bounds on first call.
///
/// Example:
/// ```
/// updateBounds(1.0, 2.0, &minX, &maxX, &minY, &maxY, &initialized);
/// ```
fn updateBounds(px: f32, py: f32, minX: *f32, maxX: *f32, minY: *f32, maxY: *f32, initialized: *bool) void {
    if (!initialized.*) {
        minX.* = px;
        maxX.* = px;
        minY.* = py;
        maxY.* = py;
        initialized.* = true;
    }
    if (px < minX.*) minX.* = px;
    if (px > maxX.*) maxX.* = px;
    if (py < minY.*) minY.* = py;
    if (py > maxY.*) maxY.* = py;
}

test "walkInputRowBounds" {
    const TestVec = struct { x: f32, y: f32 };
    const TestElem = union(enum) { point: TestVec, vector: TestVec, vectors: []const TestVec };
    const TestRow = struct { row: []const TestElem };
    const TestInputs = struct { input: []const TestRow };

    var minX: f32 = 0;
    var maxX: f32 = 0;
    var minY: f32 = 0;
    var maxY: f32 = 0;
    var initialized = false;

    // Start at (10,10), then vector (1,2) -> (11,12), then point (0,0) -> (0,0)
    const row = TestRow{ .row = &[2]TestElem{
        .{ .vector = .{ .x = 1.0, .y = 2.0 } },
        .{ .point = .{ .x = 0.0, .y = 0.0 } },
    } };
    const test_inputs = TestInputs{ .input = &[1]TestRow{row} };

    walkInputRowBounds(10.0, 10.0, &test_inputs, 0, &minX, &maxX, &minY, &maxY, &initialized, CoordinateType.xy);
    try testing.expect(initialized);
    // After start (10,10): bounds = (10,10,10,10)
    // After vector (1,2): cur = (11,12), bounds = (10,11,10,12)
    // After point (0,0): cur = (0,0), bounds = (0,11,0,12)
    try testing.expectEqual(@as(f32, 0.0), minX);
    try testing.expectEqual(@as(f32, 11.0), maxX);
    try testing.expectEqual(@as(f32, 0.0), minY);
    try testing.expectEqual(@as(f32, 12.0), maxY);

    // idx out of range — no change
    updateBounds(100.0, 100.0, &minX, &maxX, &minY, &maxY, &initialized);
    walkInputRowBounds(0.0, 0.0, &test_inputs, 5, &minX, &maxX, &minY, &maxY, &initialized, CoordinateType.xy);
    try testing.expectEqual(@as(f32, 100.0), maxX);
}

test "walkInputRowBounds polar cumulative" {
    const Vec = struct { x: f32, y: f32 };
    const TestElem = union(enum) { point: Vec, vector: Vec, vectors: []const Vec };
    const TestRow = struct { row: []const TestElem };
    const TestInputs = struct { input: []const TestRow };

    // [[1,45], [1,10], [2,10]] in polar -> cumulative angles 45, 55, 65 degrees
    const vs = &[3]Vec{
        .{ .x = 1.0, .y = 45.0 },
        .{ .x = 1.0, .y = 10.0 },
        .{ .x = 2.0, .y = 10.0 },
    };
    const row = TestRow{ .row = &[1]TestElem{.{ .vectors = vs }} };
    const test_inputs = TestInputs{ .input = &[1]TestRow{row} };

    var minX: f32 = 0;
    var maxX: f32 = 0;
    var minY: f32 = 0;
    var maxY: f32 = 0;
    var initialized = false;

    walkInputRowBounds(0.0, 0.0, &test_inputs, 0, &minX, &maxX, &minY, &maxY, &initialized, CoordinateType.polar);
    try testing.expect(initialized);
    // After first vector (45°): (cos45, sin45) ~ (0.707, 0.707)
    // After second vector (55°): (0.707+cos55, 0.707+sin55) ~ (1.281, 1.526)
    // After third vector (65°): (1.281+2*cos65, 1.526+2*sin65) ~ (2.127, 3.339)
    try testing.expectApproxEqAbs(@as(f32, 0.0), minX, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 2.126), maxX, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), minY, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 3.339), maxY, 0.001);
}

/// Walks through input vectors/points from a starting position, updating bounds
/// at each step. Vectors accumulate, points replace the current position.
/// For polar coordinates, angles are cumulative across the row.
///
/// Example:
/// ```
fn walkInputRowBounds(start_x: f32, start_y: f32, input_data: anytype, row_idx: usize, minX: *f32, maxX: *f32, minY: *f32, maxY: *f32, initialized: *bool, coordinate_type: anytype) void {
    if (row_idx >= input_data.input.len) return;
    const input_row = input_data.input[row_idx];
    var heading: f32 = 0.0;
    for (input_row.row) |elem| {
        switch (elem) {
            .vector => |v| {
                var dx = v.x;
                var dy = v.y;
                if (coordinate_type == .polar) {
                    heading += v.y;
                    const angle_rad = heading * pi / 180.0;
                    dx = v.x * @cos(angle_rad);
                    dy = v.x * @sin(angle_rad);
                }
                updateBounds(start_x, start_y, minX, maxX, minY, maxY, initialized);
                updateBounds(start_x + dx, start_y + dy, minX, maxX, minY, maxY, initialized);
            },
            .vectors => |vs| {
                var cur_x = start_x;
                var cur_y = start_y;
                updateBounds(cur_x, cur_y, minX, maxX, minY, maxY, initialized);
                for (vs) |v| {
                    var dx = v.x;
                    var dy = v.y;
                    if (coordinate_type == .polar) {
                        heading += v.y;
                        const angle_rad = heading * pi / 180.0;
                        dx = v.x * @cos(angle_rad);
                        dy = v.x * @sin(angle_rad);
                    }
                    cur_x += dx;
                    cur_y += dy;
                    updateBounds(cur_x, cur_y, minX, maxX, minY, maxY, initialized);
                }
            },
            .point => |p| {
                if (coordinate_type == .polar) {
                    const angle_rad = p.y * pi / 180.0;
                    updateBounds(p.x * @cos(angle_rad), p.x * @sin(angle_rad), minX, maxX, minY, maxY, initialized);
                } else {
                    updateBounds(p.x, p.y, minX, maxX, minY, maxY, initialized);
                }
            },
        }
    }
}

test "computeBounds" {
    const TestPoint = struct { x: f32, y: f32 };
    const TestAnchorPoint = union(enum) { point: TestPoint, fraction: void, beginning: void, end: void, middle: void };
    const TestAnchor = struct { point: TestAnchorPoint };
    const TestOp = union(enum) { anchor: TestAnchor, rotate: void, scale: void, mirror: void, none: void };
    const TestOps = struct { ops: []const TestOp };
    const TestPair = struct { operation: TestOps };

    const TestVec = struct { x: f32, y: f32 };
    const TestElem = union(enum) { point: TestVec, vector: TestVec, vectors: []const TestVec };
    const TestRow = struct { row: []const TestElem };
    const TestInputs = struct { input: []const TestRow };

    // Fixed mode: one begin/end pair (1,1)->(5,5)
    const op_fixed = [_]TestOp{
        .{ .anchor = .{ .point = .{ .point = .{ .x = 1.0, .y = 1.0 } } } },
        .{ .anchor = .{ .point = .{ .point = .{ .x = 5.0, .y = 5.0 } } } },
    };
    const pair_fixed = TestPair{ .operation = .{ .ops = &op_fixed } };
    const outputs_fixed = struct { transformationPairs: []const TestPair }{ .transformationPairs = &[1]TestPair{pair_fixed} };
    const inputs_empty = TestInputs{ .input = &[0]TestRow{} };
    const r1 = computeBounds(&outputs_fixed, &inputs_empty, &[1]enum { coord, origin, fixed }{.fixed}, &[1]CoordinateType{.xy});
    try testing.expectEqual(@as(f32, 1.0), r1.x[0]);
    try testing.expectEqual(@as(f32, 5.0), r1.x[1]);
    try testing.expectEqual(@as(f32, 1.0), r1.y[0]);
    try testing.expectEqual(@as(f32, 5.0), r1.y[1]);

    // Coord mode: all anchor points
    const op_coord = [_]TestOp{
        .{ .anchor = .{ .point = .{ .point = .{ .x = 2.0, .y = 3.0 } } } },
        .{ .anchor = .{ .point = .{ .point = .{ .x = 7.0, .y = 1.0 } } } },
    };
    const pair_coord = TestPair{ .operation = .{ .ops = &op_coord } };
    const outputs_coord = struct { transformationPairs: []const TestPair }{ .transformationPairs = &[1]TestPair{pair_coord} };
    const r2 = computeBounds(&outputs_coord, &inputs_empty, &[1]enum { coord, origin, fixed }{.coord}, &[1]CoordinateType{.xy});
    try testing.expectEqual(@as(f32, 2.0), r2.x[0]);
    try testing.expectEqual(@as(f32, 7.0), r2.x[1]);
    try testing.expectEqual(@as(f32, 1.0), r2.y[0]);
    try testing.expectEqual(@as(f32, 3.0), r2.y[1]);

    // Origin mode: begin/end pair (100,100)->(103,104)
    const row = TestRow{ .row = &[1]TestElem{.{ .vector = .{ .x = 3.0, .y = 4.0 } }} };
    const test_inputs = TestInputs{ .input = &[1]TestRow{row} };
    const op_origin = [_]TestOp{
        .{ .anchor = .{ .point = .{ .point = .{ .x = 100.0, .y = 100.0 } } } },
        .{ .anchor = .{ .point = .{ .point = .{ .x = 103.0, .y = 104.0 } } } },
    };
    const pair_origin = TestPair{ .operation = .{ .ops = &op_origin } };
    const outputs_origin = struct { transformationPairs: []const TestPair }{ .transformationPairs = &[1]TestPair{pair_origin} };
    const r3 = computeBounds(&outputs_origin, &test_inputs, &[1]enum { coord, origin, fixed }{.origin}, &[1]CoordinateType{.xy});
    // begin=(100,100), end=(103,104), bounds cover (100,100) and (103,104)
    try testing.expectEqual(@as(f32, 100.0), r3.x[0]);
    try testing.expectEqual(@as(f32, 103.0), r3.x[1]);
    try testing.expectEqual(@as(f32, 100.0), r3.y[0]);
    try testing.expectEqual(@as(f32, 104.0), r3.y[1]);

    // Empty outputs -> default bounds (0,0)-(1,1)
    const outputs_empty = struct { transformationPairs: []const TestPair }{ .transformationPairs = &[0]TestPair{} };
    const r4 = computeBounds(&outputs_empty, &inputs_empty, &[0]enum { coord, origin, fixed }{}, &[0]CoordinateType{});
    try testing.expectEqual(@as(f32, 0.0), r4.x[0]);
    try testing.expectEqual(@as(f32, 1.0), r4.x[1]);
    try testing.expectEqual(@as(f32, 0.0), r4.y[0]);
    try testing.expectEqual(@as(f32, 1.0), r4.y[1]);

    // Single anchor: walk from anchor point
    const op_single = [_]TestOp{
        .{ .anchor = .{ .point = .{ .point = .{ .x = 5.0, .y = 5.0 } } } },
    };
    const pair_single = TestPair{ .operation = .{ .ops = &op_single } };
    const outputs_single = struct { transformationPairs: []const TestPair }{ .transformationPairs = &[1]TestPair{pair_single} };
    const r5 = computeBounds(&outputs_single, &test_inputs, &[1]enum { coord, origin, fixed }{.fixed}, &[1]CoordinateType{.xy});
    // start=(5,5), vector=(3,4) -> end=(8,9), bounds cover (5,5) and (8,9)
    try testing.expectEqual(@as(f32, 5.0), r5.x[0]);
    try testing.expectEqual(@as(f32, 8.0), r5.x[1]);
    try testing.expectEqual(@as(f32, 5.0), r5.y[0]);
    try testing.expectEqual(@as(f32, 9.0), r5.y[1]);

    // Single anchor with polar multi-segment: cumulative angles
    const polar_vs = &[3]TestVec{
        .{ .x = 1.0, .y = 45.0 },
        .{ .x = 1.0, .y = 10.0 },
        .{ .x = 2.0, .y = 10.0 },
    };
    const polar_row = TestRow{ .row = &[1]TestElem{.{ .vectors = polar_vs }} };
    const polar_inputs = TestInputs{ .input = &[1]TestRow{polar_row} };
    const r6 = computeBounds(&outputs_single, &polar_inputs, &[1]enum { coord, origin, fixed }{.fixed}, &[1]CoordinateType{.polar});
    // start=(5,5), polar vectors with cumulative heading 45, 55, 65
    // end ~ (5+2.126, 5+3.339) = (7.126, 8.339)
    try testing.expectApproxEqAbs(@as(f32, 5.0), r6.x[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 7.126), r6.x[1], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 5.0), r6.y[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 8.339), r6.y[1], 0.001);
}

/// Resolves the coordinate orientation for a given input row from styles and datum mappings.
/// Looks up the style index via mappings, then extracts coordinateOrientation (default .fixed).
fn resolveCoordOrientation(styles: anytype, mappings: anytype, row_idx: usize) @TypeOf(.fixed) {
    var style_idx: usize = 0;
    for (mappings) |mapping| {
        if (mapping.from == row_idx) {
            style_idx = mapping.to;
            break;
        }
    }
    if (style_idx < styles.len) {
        if (styles[style_idx].styleValue.coordinateOrientation) |orientation| {
            return orientation;
        }
    }
    return @as(@TypeOf(.fixed), .fixed);
}

/// Computes the bounding box (min/max x/y) across all outputs, respecting each
/// output's coordinate orientation mode.
///
/// Steps per orientation:
/// - coord: all anchor points from all polylines
/// - origin: last anchor's begin point + input polyline walk
/// - fixed: (begin, end) pairs from all anchors
/// - single anchor: anchor point + input polyline walk
///
/// Example:
/// ```
/// const bounds = computeBounds(&outputs, &input_data, &coord_orientations);
/// // bounds.x = {min_x, max_x}, bounds.y = {min_y, max_y}
/// ```
fn computeBounds(outputs: anytype, input_data: anytype, coord_orientations: anytype, coord_types: anytype) ValsRange {
    var minX: f32 = 0.0;
    var maxX: f32 = 0.0;
    var minY: f32 = 0.0;
    var maxY: f32 = 0.0;
    var boundsInitialized = false;

    for (outputs.transformationPairs, 0..) |pair, row_idx| {
        const ops = pair.operation.ops;
        const orientation = if (row_idx < coord_orientations.len) coord_orientations[row_idx] else .fixed;
        if (row_idx >= coord_types.len) continue;
        const coord_type = coord_types[row_idx];

        if (ops.len >= 2 and orientation == .coord) {
            for (ops) |op| {
                if (op == .anchor and op.anchor.point == .point) {
                    updateBounds(op.anchor.point.point.x, op.anchor.point.point.y, &minX, &maxX, &minY, &maxY, &boundsInitialized);
                }
            }
        } else if (ops.len >= 2 and orientation == .fixed) {
            for (0..ops.len / 2) |i| {
                const begin_op = ops[i * 2];
                const end_op = ops[i * 2 + 1];
                if (begin_op == .anchor and begin_op.anchor.point == .point) {
                    updateBounds(begin_op.anchor.point.point.x, begin_op.anchor.point.point.y, &minX, &maxX, &minY, &maxY, &boundsInitialized);
                }
                if (end_op == .anchor and end_op.anchor.point == .point) {
                    updateBounds(end_op.anchor.point.point.x, end_op.anchor.point.point.y, &minX, &maxX, &minY, &maxY, &boundsInitialized);
                }
            }
        } else if (ops.len >= 2 and orientation == .origin) {
            const vector_count = if (row_idx < input_data.input.len) countVectors(input_data.input[row_idx]) else 0;
            if (isBeginEndPairs(ops, input_data, row_idx)) {
                for (0..ops.len / 2) |i| {
                    const begin_op = ops[i * 2];
                    const end_op = ops[i * 2 + 1];
                    if (begin_op == .anchor and begin_op.anchor.point == .point) {
                        updateBounds(begin_op.anchor.point.point.x, begin_op.anchor.point.point.y, &minX, &maxX, &minY, &maxY, &boundsInitialized);
                    }
                    if (end_op == .anchor and end_op.anchor.point == .point) {
                        updateBounds(end_op.anchor.point.point.x, end_op.anchor.point.point.y, &minX, &maxX, &minY, &maxY, &boundsInitialized);
                    }
                }
            } else if (vector_count > 0 and ops.len % (vector_count + 1) == 0) {
                for (ops) |op| {
                    if (op == .anchor and op.anchor.point == .point) {
                        updateBounds(op.anchor.point.point.x, op.anchor.point.point.y, &minX, &maxX, &minY, &maxY, &boundsInitialized);
                    }
                }
            } else {
                const start_op = ops[ops.len - 2];
                if (start_op == .anchor and start_op.anchor.point == .point) {
                    const sx = start_op.anchor.point.point.x;
                    const sy = start_op.anchor.point.point.y;
                    walkInputRowBounds(sx, sy, input_data, row_idx, &minX, &maxX, &minY, &maxY, &boundsInitialized, coord_type);
                    updateBounds(sx, sy, &minX, &maxX, &minY, &maxY, &boundsInitialized);
                }
            }
        } else if (ops.len == 1) {
            const start_op = ops[0];
            if (start_op == .anchor and start_op.anchor.point == .point) {
                const sx = start_op.anchor.point.point.x;
                const sy = start_op.anchor.point.point.y;
                walkInputRowBounds(sx, sy, input_data, row_idx, &minX, &maxX, &minY, &maxY, &boundsInitialized, coord_type);
                updateBounds(sx, sy, &minX, &maxX, &minY, &maxY, &boundsInitialized);
            }
        }
    }

    if (!boundsInitialized) {
        minX = 0;
        maxX = 1;
        minY = 0;
        maxY = 1;
    }

    return ValsRange{ .x = .{ minX, maxX }, .y = .{ minY, maxY } };
}

/// Resolves line style (width, color, cap, join, dashing) for a given input row
/// from the parsed style definitions. Applies dashing directly to the context.
///
/// Looks up the style index from the datum mappings, then reads line width (supporting
/// normalized/global/output/local references), color with opacity blending, dashing
/// pattern/offset, line cap mode (butt/round/square), and line join mode (miter/round/bevel).
///
/// Example:
/// ```
/// const style = try resolveStyle(&ctx, styles, mappings, 0, height);
/// // style.width, style.r/g/b/a, style.cap_mode, style.join_mode
/// ```
fn resolveStyle(context: *z2d.Context, styles: anytype, mappings: anytype, row_idx: usize, height: i32) !LineStyle {
    var style_idx: usize = 0;
    for (mappings) |mapping| {
        if (mapping.from == row_idx) {
            style_idx = mapping.to;
            break;
        }
    }

    var ls = LineStyle{
        .width = 10.0,
        .r = 0,
        .g = 0,
        .b = 0,
        .a = 255,
        .cap_mode = .butt,
        .join_mode = .miter,
    };

    if (style_idx < styles.len) {
        const style = styles[style_idx];
        if (style.styleValue.attributes) |attrs| {
            if (attrs.lineWidth) |lw| {
                switch (lw.reference) {
                    .normalized => {
                        const h2: f64 = @floatFromInt(height);
                        const v: f64 = @floatFromInt(lw.value);
                        ls.width = v * h2 / 1000.0;
                    },
                    .global => {
                        const v: f64 = @floatFromInt(lw.value);
                        ls.width = v / 10.0;
                    },
                    .output => {
                        const v: f64 = @floatFromInt(lw.value);
                        ls.width = v;
                    },
                    .local => {
                        const v: f64 = @floatFromInt(lw.value);
                        ls.width = v / 10.0;
                    },
                }
            }
            if (attrs.lineColor) |lc| {
                const rgb = colorNameToRGB(lc.value);
                ls.r = rgb.r;
                ls.g = rgb.g;
                ls.b = rgb.b;
            }
            if (attrs.lineOpacity) |lo| {
                const alpha: u16 = @intCast(@as(u16, lo.value) * 255 / 100);
                ls.r = @intCast(@as(u16, ls.r) * alpha / 255);
                ls.g = @intCast(@as(u16, ls.g) * alpha / 255);
                ls.b = @intCast(@as(u16, ls.b) * alpha / 255);
                ls.a = @intCast(alpha);
            }

            if (attrs.lineDashing) |ld| {
                var dashes = try std.heap.page_allocator.alloc(f64, ld.onOff.len);
                for (ld.onOff, 0..) |val, i| {
                    const v: f64 = @floatFromInt(val);
                    dashes[i] = switch (ld.reference) {
                        .normalized => v * @as(f64, @floatFromInt(height)) / 1000.0,
                        .global => v / 10.0,
                        .output => v,
                        .local => v / 10.0,
                    };
                }
                context.setDashes(dashes);
                const offset_v: f64 = @floatFromInt(ld.offset);
                const offset_px = switch (ld.reference) {
                    .normalized => offset_v * @as(f64, @floatFromInt(height)) / 1000.0,
                    .global => offset_v / 10.0,
                    .output => offset_v,
                    .local => offset_v / 10.0,
                };
                context.setDashOffset(-offset_px);
            } else {
                context.setDashes(&.{});
                context.setDashOffset(0);
            }

            if (attrs.lineCap) |cap| {
                ls.cap_mode = switch (cap.value) {
                    .none => .butt,
                    .butt => .butt,
                    .round => .round,
                    .square => .square,
                };
            }

            if (attrs.lineJoin) |join| {
                ls.join_mode = switch (join.value) {
                    .none => .miter,
                    .mitter => .miter,
                    .round => .round,
                    .bevel => .bevel,
                };
            }
        }
    }

    return ls;
}

/// Draws a polyline from an anchor point through all input vectors/points.
/// Shared by origin mode (last anchor's begin) and single-anchor mode.
///
/// Steps:
/// - Convert start point to plot coordinates, moveTo
/// - Walk through input row elements:
///   - vector: add displacement to current position
///   - point: set absolute position
/// - Convert each intermediate position to plot coords, lineTo
/// - Clamp Y to [min_y, max_y] (viewport bounds)
/// - Stroke the path
///
/// Example:
/// ```
/// try drawPolylineFromAnchor(&ctx, 0, 0, &input_data, 0, origin_x, origin_y, x_scale, y_scale, min_y, max_y);
/// ```
fn drawPolylineFromAnchor(context: *z2d.Context, start_x: f64, start_y: f64, input_data: anytype, row_idx: usize, origin_x: f64, origin_y: f64, x_scale: f64, y_scale: f64, min_y: f64, max_y: f64, coordinate_type: anytype) !void {
    if (row_idx >= input_data.input.len) return;
    const input_row = input_data.input[row_idx];
    var heading: f32 = 0.0;

    for (input_row.row) |elem| {
        switch (elem) {
            .vector => |v| {
                var dx = @as(f64, v.x);
                var dy = @as(f64, v.y);
                if (coordinate_type == .polar) {
                    heading += v.y;
                    const angle_rad = heading * pi / 180.0;
                    dx = @as(f64, v.x) * @cos(angle_rad);
                    dy = @as(f64, v.x) * @sin(angle_rad);
                }
                context.resetPath();
                const bx = origin_x + start_x * x_scale;
                var by = origin_y - start_y * y_scale;
                if (by < min_y) by = min_y;
                if (by > max_y) by = max_y;
                try context.moveTo(bx, by);
                const ex = origin_x + (start_x + dx) * x_scale;
                var ey = origin_y - (start_y + dy) * y_scale;
                if (ey < min_y) ey = min_y;
                if (ey > max_y) ey = max_y;
                try context.lineTo(ex, ey);
                try context.stroke();
            },
            .vectors => |vs| {
                context.resetPath();
                var cur_x = start_x;
                var cur_y = start_y;
                var plot_x = origin_x + cur_x * x_scale;
                var plot_y = origin_y - cur_y * y_scale;
                if (plot_y < min_y) plot_y = min_y;
                if (plot_y > max_y) plot_y = max_y;
                try context.moveTo(plot_x, plot_y);
                for (vs) |v| {
                    var dx = @as(f64, v.x);
                    var dy = @as(f64, v.y);
                    if (coordinate_type == .polar) {
                        heading += v.y;
                        const angle_rad = heading * pi / 180.0;
                        dx = @as(f64, v.x) * @cos(angle_rad);
                        dy = @as(f64, v.x) * @sin(angle_rad);
                    }
                    cur_x += dx;
                    cur_y += dy;
                    plot_x = origin_x + cur_x * x_scale;
                    plot_y = origin_y - cur_y * y_scale;
                    if (plot_y < min_y) plot_y = min_y;
                    if (plot_y > max_y) plot_y = max_y;
                    try context.lineTo(plot_x, plot_y);
                }
                try context.stroke();
            },
            .point => |p| {
                var px = @as(f64, p.x);
                var py = @as(f64, p.y);
                if (coordinate_type == .polar) {
                    const angle_rad = p.y * pi / 180.0;
                    px = @as(f64, p.x) * @cos(angle_rad);
                    py = @as(f64, p.x) * @sin(angle_rad);
                }
                context.resetPath();
                const plot_px = origin_x + px * x_scale;
                var plot_py = origin_y - py * y_scale;
                if (plot_py < min_y) plot_py = min_y;
                if (plot_py > max_y) plot_py = max_y;
                try context.moveTo(plot_px, plot_py);
                try context.lineTo(plot_px, plot_py);
                try context.stroke();
            },
        }
    }
}

/// Draws polylines in coord mode, where ops are organized into steps of
/// (vector_count + 1) consecutive anchor points. Each step represents one
/// anchor's full polyline (start + all vectors).
///
/// Steps:
/// - Determine points_per_step from vector count
/// - For each step:
///   - reset path, walk its anchor points
///   - convert to plot coordinates (clamp Y)
///   - moveTo first point, lineTo subsequent ones
///   - stroke the completed polyline
///
/// Example:
/// ```
/// try drawCoordPolylines(&ctx, ops, &input_data, 0, origin_x, origin_y, x_scale, y_scale, min_y, max_y);
/// ```
fn drawCoordPolylines(context: *z2d.Context, ops: anytype, input_data: anytype, row_idx: usize, origin_x: f64, origin_y: f64, x_scale: f64, y_scale: f64, min_y: f64, max_y: f64) !void {
    const vector_count = if (row_idx < input_data.input.len) countVectors(input_data.input[row_idx]) else 0;
    const points_per_step = if (vector_count > 0) vector_count + 1 else 1;
    const step_count = ops.len / points_per_step;

    for (0..step_count) |s| {
        context.resetPath();
        var first = true;
        const start = s * points_per_step;
        const end = start + points_per_step;
        for (start..end) |j| {
            const op = ops[j];
            if (op == .anchor and op.anchor.point == .point) {
                const px = @as(f64, op.anchor.point.point.x);
                const py = @as(f64, op.anchor.point.point.y);
                const plot_x = origin_x + px * x_scale;
                var plot_y = origin_y - py * y_scale;
                if (plot_y < min_y) plot_y = min_y;
                if (plot_y > max_y) plot_y = max_y;
                if (first) {
                    try context.moveTo(plot_x, plot_y);
                    first = false;
                } else {
                    try context.lineTo(plot_x, plot_y);
                }
            }
        }
        try context.stroke();
    }
}

/// Draws (begin, end) line segments for fixed mode, where ops are interleaved
/// begin/end point pairs (begin_0, end_0, begin_1, end_1, ...).
///
/// Steps:
/// - Iterate over ops as consecutive pairs
/// - For each pair with valid anchor points:
///   - convert begin and end to plot coordinates (clamp Y)
///   - reset path, moveTo begin, lineTo end, stroke
fn drawFixedPairs(context: *z2d.Context, ops: anytype, origin_x: f64, origin_y: f64, x_scale: f64, y_scale: f64, min_y: f64, max_y: f64) !void {
    const pair_count = ops.len / 2;
    for (0..pair_count) |i| {
        const begin_op = ops[i * 2];
        const end_op = ops[i * 2 + 1];
        if (begin_op == .anchor and begin_op.anchor.point == .point and
            end_op == .anchor and end_op.anchor.point == .point)
        {
            const bx = @as(f64, begin_op.anchor.point.point.x);
            const by = @as(f64, begin_op.anchor.point.point.y);
            const ex = @as(f64, end_op.anchor.point.point.x);
            const ey = @as(f64, end_op.anchor.point.point.y);
            const plot_bx = origin_x + bx * x_scale;
            var plot_by = origin_y - by * y_scale;
            const plot_ex = origin_x + ex * x_scale;
            var plot_ey = origin_y - ey * y_scale;
            if (plot_by < min_y) plot_by = min_y;
            if (plot_by > max_y) plot_by = max_y;
            if (plot_ey < min_y) plot_ey = min_y;
            if (plot_ey > max_y) plot_ey = max_y;

            context.resetPath();
            try context.moveTo(plot_bx, plot_by);
            try context.lineTo(plot_ex, plot_ey);
            try context.stroke();
        }
    }
}

/// Renders all parsed outputs onto a z2d canvas and returns the resulting image
/// (or writes it to a PNG file if output_path is provided).
///
/// Processing phases:
/// 1. Canvas setup: create surface, fill white background
/// 2. Bounds computation: find min/max X/Y across all outputs via computeBounds
/// 3. Coordinate transform: compute scale and origin from bounds + margin
/// 4. Drawing loop: for each input row:
///    a. Resolve line style (width, color, dashing, caps) via resolveStyle
///    b. Draw data based on orientation:
///       - coord: drawCoordPolylines (multiple polyline steps)
///       - origin: drawPolylineFromAnchor (input polyline at last anchor)
///       - fixed: drawFixedPairs ((begin, end) segments)
///       - single anchor: drawPolylineFromAnchor (input polyline from anchor)
/// 5. Output: write PNG or return RenderedImage with pixel data
pub fn plot_via_z2d(io: std.Io, parsed_data: anytype, output_path: ?[]const u8) !RenderedImage {
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

    var context = z2d.Context.init(io, std.heap.page_allocator, &surface);

    context.setSourceToPixel(.{ .rgba = .{ .r = 255, .g = 255, .b = 255, .a = 255 } });
    context.setLineWidth(0.0); // Disable stroke during fill
    try context.moveTo(0, 0);
    try context.lineTo(@floatFromInt(width), 0);
    try context.lineTo(@floatFromInt(width), @floatFromInt(height));
    try context.lineTo(0, @floatFromInt(height));
    try context.closePath();
    try context.fill();
    context.setLineWidth(10.0); // Re-enable for data lines
    context.resetPath(); // Clear path state after fill
    const outputs = parsed_data.outputs;
    const input_data = parsed_data.inputs;

    const CoordOrientation = @typeInfo(@TypeOf(parsed_data.styles[0].styleValue.coordinateOrientation)).optional.child;
    const coord_orientations = try std.heap.page_allocator.alloc(CoordOrientation, outputs.transformationPairs.len);
    defer std.heap.page_allocator.free(coord_orientations);
    for (0..outputs.transformationPairs.len) |idx| {
        coord_orientations[idx] = if (parsed_data.styles.len > idx and parsed_data.styles[idx].styleValue.coordinateOrientation != null)
            parsed_data.styles[idx].styleValue.coordinateOrientation.?
        else
            .fixed;
    }

    const StyleCoordType = @typeInfo(@TypeOf(parsed_data.styles[0].styleValue.coordinateSystem)).optional.child;
    const coord_types = try std.heap.page_allocator.alloc(StyleCoordType, outputs.transformationPairs.len);
    defer std.heap.page_allocator.free(coord_types);
    for (0..outputs.transformationPairs.len) |idx| {
        coord_types[idx] = if (parsed_data.styles.len > idx and parsed_data.styles[idx].styleValue.coordinateSystem != null)
            parsed_data.styles[idx].styleValue.coordinateSystem.?
        else
            .xy;
    }

    const bounds = computeBounds(outputs, input_data, coord_orientations, coord_types);

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
        const origin_y = @as(f64, @floatFromInt(height)) - margin + @as(f64, bounds.y[0]) * y_scale;
        const min_y = margin;
        const max_y = @as(f64, @floatFromInt(height)) - margin;

        for (parsed_data.inputs.input, 0..) |_, row_idx| {
            const style = try resolveStyle(&context, parsed_data.styles, parsed_data.datum.mappings, row_idx, height);
            context.setSourceToPixel(.{ .rgba = .{ .r = style.r, .g = style.g, .b = style.b, .a = style.a } });
            context.setLineWidth(style.width);
            context.setLineCapMode(style.cap_mode);
            context.setLineJoinMode(style.join_mode);

            const orientation = if (row_idx < coord_orientations.len) coord_orientations[row_idx] else .fixed;
            if (row_idx >= coord_types.len) continue;
            const ct = coord_types[row_idx];

            if (row_idx < outputs.transformationPairs.len) {
                const pair = outputs.transformationPairs[row_idx];
                const ops = pair.operation.ops;

                if (ops.len >= 2) {
                    if (orientation == .coord) {
                        try drawCoordPolylines(&context, ops, input_data, row_idx, origin_x, origin_y, x_scale, y_scale, min_y, max_y);
                    } else if (orientation == .origin) {
                        const vector_count = if (row_idx < input_data.input.len) countVectors(input_data.input[row_idx]) else 0;
                        if (isBeginEndPairs(ops, input_data, row_idx)) {
                            try drawFixedPairs(&context, ops, origin_x, origin_y, x_scale, y_scale, min_y, max_y);
                        } else if (vector_count > 0 and ops.len % (vector_count + 1) == 0) {
                            try drawCoordPolylines(&context, ops, input_data, row_idx, origin_x, origin_y, x_scale, y_scale, min_y, max_y);
                        } else {
                            const start_op = ops[ops.len - 2];
                            if (start_op == .anchor and start_op.anchor.point == .point) {
                                try drawPolylineFromAnchor(&context, @as(f64, start_op.anchor.point.point.x), @as(f64, start_op.anchor.point.point.y), input_data, row_idx, origin_x, origin_y, x_scale, y_scale, min_y, max_y, ct);
                            }
                        }
                    } else {
                        const vector_count = if (row_idx < input_data.input.len) countVectors(input_data.input[row_idx]) else 0;
                        if (vector_count > 0 and ops.len % (vector_count + 1) == 0) {
                            try drawCoordPolylines(&context, ops, input_data, row_idx, origin_x, origin_y, x_scale, y_scale, min_y, max_y);
                        } else {
                            try drawFixedPairs(&context, ops, origin_x, origin_y, x_scale, y_scale, min_y, max_y);
                        }
                    }
                }
                if (ops.len == 1) {
                    const start_op = ops[0];
                    if (start_op == .anchor and start_op.anchor.point == .point) {
                        try drawPolylineFromAnchor(&context, @as(f64, start_op.anchor.point.point.x), @as(f64, start_op.anchor.point.point.y), input_data, row_idx, origin_x, origin_y, x_scale, y_scale, min_y, max_y, ct);
                    }
                }
            }
        }
    }

    if (output_path) |filename| {
        try z2d.png_exporter.writeToPNGFile(io, surface, filename, .{});
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

test "colorNameToRGB" {
    const TestColor = enum {
        aliceblue,
        antiquewhite,
        aqua,
        aquamarine,
        azure,
        beige,
        bisque,
        black,
        blanchedalmond,
        blue,
        blueviolet,
        brown,
        burlywood,
        cadetblue,
        chartreuse,
        chocolate,
        coral,
        cornflowerblue,
        cornsilk,
        crimson,
        cyan,
        darkblue,
        darkcyan,
        darkgoldenrod,
        darkgray,
        darkgreen,
        darkgrey,
        darkkhaki,
        darkmagenta,
        darkolivegreen,
        darkorange,
        darkorchid,
        darkred,
        darksalmon,
        darkseagreen,
        darkslateblue,
        darkslategray,
        darkslategrey,
        darkturquoise,
        darkviolet,
        deeppink,
        deepskyblue,
        dimgray,
        dimgrey,
        dodgerblue,
        firebrick,
        floralwhite,
        forestgreen,
        fuchsia,
        gainsboro,
        ghostwhite,
        gold,
        goldenrod,
        gray,
        green,
        greenyellow,
        grey,
        honeydew,
        hotpink,
        indianred,
        indigo,
        ivory,
        khaki,
        lavender,
        lavenderblush,
        lawngreen,
        lemonchiffon,
        lightblue,
        lightcoral,
        lightcyan,
        lightgoldenrodyellow,
        lightgray,
        lightgreen,
        lightgrey,
        lightpink,
        lightsalmon,
        lightseagreen,
        lightskyblue,
        lightslategray,
        lightslategrey,
        lightsteelblue,
        lightyellow,
        lime,
        limegreen,
        linen,
        magenta,
        maroon,
        mediumaquamarine,
        mediumblue,
        mediumorchid,
        mediumpurple,
        mediumseagreen,
        mediumslateblue,
        mediumspringgreen,
        mediumturquoise,
        mediumvioletred,
        midnightblue,
        mintcream,
        mistyrose,
        moccasin,
        navajowhite,
        navy,
        oldlace,
        olive,
        olivedrab,
        orange,
        orangered,
        orchid,
        palegoldenrod,
        palegreen,
        paleturquoise,
        palevioletred,
        papayawhip,
        peachpuff,
        peru,
        pink,
        plum,
        powderblue,
        purple,
        rebeccapurple,
        red,
        rosybrown,
        royalblue,
        saddlebrown,
        salmon,
        sandybrown,
        seagreen,
        seashell,
        sienna,
        silver,
        skyblue,
        slateblue,
        slategray,
        slategrey,
        snow,
        springgreen,
        steelblue,
        tan,
        teal,
        thistle,
        tomato,
        turquoise,
        violet,
        wheat,
        white,
        whitesmoke,
        yellow,
        yellowgreen,
    };

    try testing.expectEqual(@as(u8, 0), (colorNameToRGB(@as(TestColor, .black))).r);
    try testing.expectEqual(@as(u8, 0), (colorNameToRGB(@as(TestColor, .black))).g);
    try testing.expectEqual(@as(u8, 0), (colorNameToRGB(@as(TestColor, .black))).b);

    try testing.expectEqual(@as(u8, 255), (colorNameToRGB(@as(TestColor, .white))).r);
    try testing.expectEqual(@as(u8, 255), (colorNameToRGB(@as(TestColor, .white))).g);
    try testing.expectEqual(@as(u8, 255), (colorNameToRGB(@as(TestColor, .white))).b);

    try testing.expectEqual(@as(u8, 255), (colorNameToRGB(@as(TestColor, .red))).r);
    try testing.expectEqual(@as(u8, 0), (colorNameToRGB(@as(TestColor, .red))).g);
    try testing.expectEqual(@as(u8, 0), (colorNameToRGB(@as(TestColor, .red))).b);

    try testing.expectEqual(@as(u8, 0), (colorNameToRGB(@as(TestColor, .green))).r);
    try testing.expectEqual(@as(u8, 128), (colorNameToRGB(@as(TestColor, .green))).g);
    try testing.expectEqual(@as(u8, 0), (colorNameToRGB(@as(TestColor, .green))).b);

    try testing.expectEqual(@as(u8, 0), (colorNameToRGB(@as(TestColor, .blue))).r);
    try testing.expectEqual(@as(u8, 0), (colorNameToRGB(@as(TestColor, .blue))).g);
    try testing.expectEqual(@as(u8, 255), (colorNameToRGB(@as(TestColor, .blue))).b);

    try testing.expectEqual(@as(u8, 240), (colorNameToRGB(@as(TestColor, .aliceblue))).r);
    try testing.expectEqual(@as(u8, 248), (colorNameToRGB(@as(TestColor, .aliceblue))).g);
    try testing.expectEqual(@as(u8, 255), (colorNameToRGB(@as(TestColor, .aliceblue))).b);

    try testing.expectEqual(@as(u8, 255), (colorNameToRGB(@as(TestColor, .coral))).r);
    try testing.expectEqual(@as(u8, 127), (colorNameToRGB(@as(TestColor, .coral))).g);
    try testing.expectEqual(@as(u8, 80), (colorNameToRGB(@as(TestColor, .coral))).b);
}

/// Converts a CSS named color to its (r, g, b) components.
///
/// Accepts any enum type whose variants match standard CSS color names.
/// Used by resolveStyle to convert parsed color names to pixel values.
///
/// Example:
/// ```
/// const rgb = colorNameToRGB(common.ColorName.coral);
/// // rgb = .{ .r = 255, .g = 127, .b = 80 }
/// ```
fn colorNameToRGB(c: anytype) struct { r: u8, g: u8, b: u8 } {
    return switch (c) {
        .aliceblue => .{ .r = 240, .g = 248, .b = 255 },
        .antiquewhite => .{ .r = 250, .g = 235, .b = 215 },
        .aqua => .{ .r = 0, .g = 255, .b = 255 },
        .aquamarine => .{ .r = 127, .g = 255, .b = 212 },
        .azure => .{ .r = 240, .g = 255, .b = 255 },
        .beige => .{ .r = 245, .g = 245, .b = 220 },
        .bisque => .{ .r = 255, .g = 228, .b = 196 },
        .black => .{ .r = 0, .g = 0, .b = 0 },
        .blanchedalmond => .{ .r = 255, .g = 235, .b = 205 },
        .blue => .{ .r = 0, .g = 0, .b = 255 },
        .blueviolet => .{ .r = 138, .g = 43, .b = 226 },
        .brown => .{ .r = 165, .g = 42, .b = 42 },
        .burlywood => .{ .r = 222, .g = 184, .b = 135 },
        .cadetblue => .{ .r = 95, .g = 158, .b = 160 },
        .chartreuse => .{ .r = 127, .g = 255, .b = 0 },
        .chocolate => .{ .r = 210, .g = 105, .b = 30 },
        .coral => .{ .r = 255, .g = 127, .b = 80 },
        .cornflowerblue => .{ .r = 100, .g = 149, .b = 237 },
        .cornsilk => .{ .r = 255, .g = 248, .b = 220 },
        .crimson => .{ .r = 220, .g = 20, .b = 60 },
        .cyan => .{ .r = 0, .g = 255, .b = 255 },
        .darkblue => .{ .r = 0, .g = 0, .b = 139 },
        .darkcyan => .{ .r = 0, .g = 139, .b = 139 },
        .darkgoldenrod => .{ .r = 184, .g = 134, .b = 11 },
        .darkgray => .{ .r = 169, .g = 169, .b = 169 },
        .darkgreen => .{ .r = 0, .g = 100, .b = 0 },
        .darkgrey => .{ .r = 169, .g = 169, .b = 169 },
        .darkkhaki => .{ .r = 189, .g = 183, .b = 107 },
        .darkmagenta => .{ .r = 139, .g = 0, .b = 139 },
        .darkolivegreen => .{ .r = 85, .g = 107, .b = 47 },
        .darkorange => .{ .r = 255, .g = 140, .b = 0 },
        .darkorchid => .{ .r = 153, .g = 50, .b = 204 },
        .darkred => .{ .r = 139, .g = 0, .b = 0 },
        .darksalmon => .{ .r = 233, .g = 150, .b = 122 },
        .darkseagreen => .{ .r = 143, .g = 188, .b = 143 },
        .darkslateblue => .{ .r = 72, .g = 61, .b = 139 },
        .darkslategray => .{ .r = 47, .g = 79, .b = 79 },
        .darkslategrey => .{ .r = 47, .g = 79, .b = 79 },
        .darkturquoise => .{ .r = 0, .g = 206, .b = 209 },
        .darkviolet => .{ .r = 148, .g = 0, .b = 211 },
        .deeppink => .{ .r = 255, .g = 20, .b = 147 },
        .deepskyblue => .{ .r = 0, .g = 191, .b = 255 },
        .dimgray => .{ .r = 105, .g = 105, .b = 105 },
        .dimgrey => .{ .r = 105, .g = 105, .b = 105 },
        .dodgerblue => .{ .r = 30, .g = 144, .b = 255 },
        .firebrick => .{ .r = 178, .g = 34, .b = 34 },
        .floralwhite => .{ .r = 255, .g = 250, .b = 240 },
        .forestgreen => .{ .r = 34, .g = 139, .b = 34 },
        .fuchsia => .{ .r = 255, .g = 0, .b = 255 },
        .gainsboro => .{ .r = 220, .g = 220, .b = 220 },
        .ghostwhite => .{ .r = 248, .g = 248, .b = 255 },
        .gold => .{ .r = 255, .g = 215, .b = 0 },
        .goldenrod => .{ .r = 218, .g = 165, .b = 32 },
        .gray => .{ .r = 128, .g = 128, .b = 128 },
        .green => .{ .r = 0, .g = 128, .b = 0 },
        .greenyellow => .{ .r = 173, .g = 255, .b = 47 },
        .grey => .{ .r = 128, .g = 128, .b = 128 },
        .honeydew => .{ .r = 240, .g = 255, .b = 240 },
        .hotpink => .{ .r = 255, .g = 105, .b = 180 },
        .indianred => .{ .r = 205, .g = 92, .b = 92 },
        .indigo => .{ .r = 75, .g = 0, .b = 130 },
        .ivory => .{ .r = 255, .g = 255, .b = 240 },
        .khaki => .{ .r = 240, .g = 230, .b = 140 },
        .lavender => .{ .r = 230, .g = 230, .b = 250 },
        .lavenderblush => .{ .r = 255, .g = 240, .b = 245 },
        .lawngreen => .{ .r = 124, .g = 252, .b = 0 },
        .lemonchiffon => .{ .r = 255, .g = 250, .b = 205 },
        .lightblue => .{ .r = 173, .g = 216, .b = 230 },
        .lightcoral => .{ .r = 240, .g = 128, .b = 128 },
        .lightcyan => .{ .r = 224, .g = 255, .b = 255 },
        .lightgoldenrodyellow => .{ .r = 250, .g = 250, .b = 210 },
        .lightgray => .{ .r = 211, .g = 211, .b = 211 },
        .lightgreen => .{ .r = 144, .g = 238, .b = 144 },
        .lightgrey => .{ .r = 211, .g = 211, .b = 211 },
        .lightpink => .{ .r = 255, .g = 182, .b = 193 },
        .lightsalmon => .{ .r = 255, .g = 160, .b = 122 },
        .lightseagreen => .{ .r = 32, .g = 178, .b = 170 },
        .lightskyblue => .{ .r = 135, .g = 206, .b = 250 },
        .lightslategray => .{ .r = 119, .g = 136, .b = 153 },
        .lightslategrey => .{ .r = 119, .g = 136, .b = 153 },
        .lightsteelblue => .{ .r = 176, .g = 196, .b = 222 },
        .lightyellow => .{ .r = 255, .g = 255, .b = 224 },
        .lime => .{ .r = 0, .g = 255, .b = 0 },
        .limegreen => .{ .r = 50, .g = 205, .b = 50 },
        .linen => .{ .r = 250, .g = 240, .b = 230 },
        .magenta => .{ .r = 255, .g = 0, .b = 255 },
        .maroon => .{ .r = 128, .g = 0, .b = 0 },
        .mediumaquamarine => .{ .r = 102, .g = 205, .b = 170 },
        .mediumblue => .{ .r = 0, .g = 0, .b = 205 },
        .mediumorchid => .{ .r = 186, .g = 85, .b = 211 },
        .mediumpurple => .{ .r = 147, .g = 112, .b = 219 },
        .mediumseagreen => .{ .r = 60, .g = 179, .b = 113 },
        .mediumslateblue => .{ .r = 123, .g = 104, .b = 238 },
        .mediumspringgreen => .{ .r = 0, .g = 250, .b = 154 },
        .mediumturquoise => .{ .r = 72, .g = 209, .b = 204 },
        .mediumvioletred => .{ .r = 199, .g = 21, .b = 133 },
        .midnightblue => .{ .r = 25, .g = 25, .b = 112 },
        .mintcream => .{ .r = 245, .g = 255, .b = 250 },
        .mistyrose => .{ .r = 255, .g = 228, .b = 225 },
        .moccasin => .{ .r = 255, .g = 228, .b = 181 },
        .navajowhite => .{ .r = 255, .g = 222, .b = 173 },
        .navy => .{ .r = 0, .g = 0, .b = 128 },
        .oldlace => .{ .r = 253, .g = 245, .b = 230 },
        .olive => .{ .r = 128, .g = 128, .b = 0 },
        .olivedrab => .{ .r = 107, .g = 142, .b = 35 },
        .orange => .{ .r = 255, .g = 165, .b = 0 },
        .orangered => .{ .r = 255, .g = 69, .b = 0 },
        .orchid => .{ .r = 218, .g = 112, .b = 214 },
        .palegoldenrod => .{ .r = 238, .g = 232, .b = 170 },
        .palegreen => .{ .r = 152, .g = 251, .b = 152 },
        .paleturquoise => .{ .r = 175, .g = 238, .b = 238 },
        .palevioletred => .{ .r = 219, .g = 112, .b = 147 },
        .papayawhip => .{ .r = 255, .g = 239, .b = 213 },
        .peachpuff => .{ .r = 255, .g = 218, .b = 185 },
        .peru => .{ .r = 205, .g = 133, .b = 63 },
        .pink => .{ .r = 255, .g = 192, .b = 203 },
        .plum => .{ .r = 221, .g = 160, .b = 221 },
        .powderblue => .{ .r = 176, .g = 224, .b = 230 },
        .purple => .{ .r = 128, .g = 0, .b = 128 },
        .rebeccapurple => .{ .r = 102, .g = 51, .b = 153 },
        .red => .{ .r = 255, .g = 0, .b = 0 },
        .rosybrown => .{ .r = 188, .g = 143, .b = 143 },
        .royalblue => .{ .r = 65, .g = 105, .b = 225 },
        .saddlebrown => .{ .r = 139, .g = 69, .b = 19 },
        .salmon => .{ .r = 250, .g = 128, .b = 114 },
        .sandybrown => .{ .r = 244, .g = 164, .b = 96 },
        .seagreen => .{ .r = 46, .g = 139, .b = 87 },
        .seashell => .{ .r = 255, .g = 245, .b = 238 },
        .sienna => .{ .r = 160, .g = 82, .b = 45 },
        .silver => .{ .r = 192, .g = 192, .b = 192 },
        .skyblue => .{ .r = 135, .g = 206, .b = 235 },
        .slateblue => .{ .r = 106, .g = 90, .b = 205 },
        .slategray => .{ .r = 112, .g = 128, .b = 144 },
        .slategrey => .{ .r = 112, .g = 128, .b = 144 },
        .snow => .{ .r = 255, .g = 250, .b = 250 },
        .springgreen => .{ .r = 0, .g = 255, .b = 127 },
        .steelblue => .{ .r = 70, .g = 130, .b = 180 },
        .tan => .{ .r = 210, .g = 180, .b = 140 },
        .teal => .{ .r = 0, .g = 128, .b = 128 },
        .thistle => .{ .r = 216, .g = 191, .b = 216 },
        .tomato => .{ .r = 255, .g = 99, .b = 71 },
        .turquoise => .{ .r = 64, .g = 224, .b = 208 },
        .violet => .{ .r = 238, .g = 130, .b = 238 },
        .wheat => .{ .r = 245, .g = 222, .b = 179 },
        .white => .{ .r = 255, .g = 255, .b = 255 },
        .whitesmoke => .{ .r = 245, .g = 245, .b = 245 },
        .yellow => .{ .r = 255, .g = 255, .b = 0 },
        .yellowgreen => .{ .r = 154, .g = 205, .b = 50 },
    };
}
