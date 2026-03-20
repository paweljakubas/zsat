const std = @import("std");
const testing = std.testing;
const inputs = @import("cli");

const Point = inputs.Point;
const Angle = inputs.Angle;

pub fn rotateByAngleAroundPoint(angle: Angle, around: Point, point: Point, accuracy: ?u8) Point {
    const phi = switch (angle) {
        .degrees => std.math.degreesToRadians(angle.degrees),
        .radians => angle.radians,
    };
    const x_rotated = (point.x - around.x) * std.math.cos(phi) - (point.y - around.y) * std.math.sin(phi) + around.x;
    const y_rotated = (point.x - around.x) * std.math.sin(phi) + (point.y - around.y) * std.math.cos(phi) + around.y;
    if (accuracy) |acc| {
        const factor = std.math.pow(f32, 10, @as(f32, @floatFromInt(acc)));
        return Point{
            .x = @round(x_rotated * factor) / factor,
            .y = @round(y_rotated * factor) / factor,
        };
    }
    return Point{ .x = x_rotated, .y = y_rotated };
}

test "rotateByAngleAroundPoint" {
    const sqrt2: f32 = 1.41421;

    const point1 = Point{ .x = 1.0, .y = 1.0 };
    const angle1 = Angle{ .degrees = 45 };
    const pointRes1 = rotateByAngleAroundPoint(angle1, Point{ .x = 0, .y = 0 }, point1, 5);
    try testing.expectEqual(@as(f32, 0.0), pointRes1.x);
    try testing.expectEqual(sqrt2, pointRes1.y);

    const point2 = Point{ .x = 1.0, .y = 1.0 };
    const angle2 = Angle{ .radians = 0.25 * inputs.pi };
    const pointRes2 = rotateByAngleAroundPoint(angle2, Point{ .x = 0, .y = 0 }, point2, 5);
    try testing.expectEqual(@as(f32, 0.0), pointRes2.x);
    try testing.expectEqual(sqrt2, pointRes2.y);

    const point3 = Point{ .x = 5.0, .y = 1.5 };
    const angle3 = Angle{ .degrees = 360 };
    const pointRes3 = rotateByAngleAroundPoint(angle3, Point{ .x = 0, .y = 0 }, point3, 5);
    try testing.expectEqual(@as(f32, 5.0), pointRes3.x);
    try testing.expectEqual(@as(f32, 1.5), pointRes3.y);

    const point4 = Point{ .x = 5.0, .y = 1.5 };
    const angle4 = Angle{ .radians = 2.0 * inputs.pi };
    const pointRes4 = rotateByAngleAroundPoint(angle4, Point{ .x = 0, .y = 0 }, point4, 5);
    try testing.expectEqual(@as(f32, 5.0), pointRes4.x);
    try testing.expectEqual(@as(f32, 1.5), pointRes4.y);

    const point5 = Point{ .x = 5.0, .y = 1.5 };
    const angle5 = Angle{ .degrees = 360 };
    const pointRes5 = rotateByAngleAroundPoint(angle5, Point{ .x = 0.1, .y = 1.1 }, point5, 5);
    try testing.expectEqual(@as(f32, 5.0), pointRes5.x);
    try testing.expectEqual(@as(f32, 1.5), pointRes5.y);

    const point6 = Point{ .x = 5.0, .y = 1.5 };
    const angle6 = Angle{ .radians = 2.0 * inputs.pi };
    const pointRes6 = rotateByAngleAroundPoint(angle6, Point{ .x = 0.15, .y = 10 }, point6, 5);
    try testing.expectEqual(@as(f32, 5.0), pointRes6.x);
    try testing.expectEqual(@as(f32, 1.5), pointRes6.y);

    const point7 = Point{ .x = 1.0, .y = 1.0 };
    const angle7 = Angle{ .degrees = 45 };
    const pointRes7 = rotateByAngleAroundPoint(angle7, Point{ .x = 0, .y = 0 }, point7, null);
    try testing.expectEqual(@as(f32, 0.0), pointRes7.x);
    try testing.expectEqual(@as(f32, 1.4142135), pointRes7.y);

    const point8 = Point{ .x = 1.0, .y = 1.0 };
    const angle8 = Angle{ .radians = 0.25 * inputs.pi };
    const pointRes8 = rotateByAngleAroundPoint(angle8, Point{ .x = 0, .y = 0 }, point8, null);
    try testing.expectEqual(@as(f32, 0.0), pointRes8.x);
    try testing.expectEqual(@as(f32, 1.4142135), pointRes8.y);
}
