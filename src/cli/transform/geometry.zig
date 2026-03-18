const std = @import("std");
const testing = std.testing;

const Point = struct {
    x: f32,
    y: f32,
};

const Angle = union(enum) {
    degrees: f32,
    radians: f32,
};

pub fn rotateByAngleAroundPoint(angle: Angle, around: Point, point: Point) Point {
    const phi = switch (angle) {
        .degrees => std.math.degreesToRadians(angle.degrees),
        .radians => angle.radians,
    };
    const x_rotated = (point.x - around.x) * std.math.cos(phi) - (point.y - around.y) * std.math.sin(phi) + around.x;
    const y_rotated = (point.x - around.x) * std.math.sin(phi) + (point.y - around.y) * std.math.cos(phi) + around.y;
    return Point{ .x = x_rotated, .y = y_rotated };
}

test "rotateByAngleAroundPoint" {
    const sqrt2: f32 = 1.41421356237;
    const pi: f32 = 3.14159265359;

    const point1 = Point{ .x = 1.0, .y = 1.0 };
    const angle1 = Angle{ .degrees = 45 };
    const pointRes1 = rotateByAngleAroundPoint(angle1, Point{ .x = 0, .y = 0 }, point1);
    try testing.expectEqual(@as(f32, 0.0), pointRes1.x);
    try testing.expectEqual(sqrt2, pointRes1.y);

    const point2 = Point{ .x = 1.0, .y = 1.0 };
    const angle2 = Angle{ .radians = 0.25 * pi };
    const pointRes2 = rotateByAngleAroundPoint(angle2, Point{ .x = 0, .y = 0 }, point2);
    try testing.expectEqual(@as(f32, 0.0), pointRes2.x);
    try testing.expectEqual(sqrt2, pointRes2.y);
}
