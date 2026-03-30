const std = @import("std");
const testing = std.testing;
const inputs = @import("cli");

const Point = inputs.Point;
const Angle = inputs.Angle;
const Line = inputs.Line;

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

// Line is assuming ay=bx+c
// Line cannot be a=b=0, this should be filtered out at the parsing level
// 1. if we have vertical line, ie., a=0 and b/=0, y component of any point is maintained.
//    x component is mirrored.
//    Here, if (-c/b)< point.x then point.x'= (-c/b) - (point.x + (c/b))
//    Here, if (-c/b)> point.x then point.x'= (-c/b) + ((-c/b) - point.x)
//    Here, if (-c/b) == point.x then point.x'= point.x
// 2. if we have horizontal line, ie., a/=0 and b=0, x component of any point is maintained.
//    y component is mirrored.
//    Here, if (c/a) > point.y then point.y'= (c/a) + ((c/a) - point.y)
//    Here, if (c/a) < point.y then point.y'= (c/a) - (point.y - (c/a))
//    Here, if (c/a) == point.y then point.y'= point.y
pub fn mirrorPointOverLine(what: Point, over: Line, accuracy: ?u8) Point {
    if (over.a == 0.0) {
        const mirror_x = -over.c / over.b;
        const mirrored_x = 2.0 * mirror_x - what.x;
        if (accuracy) |acc| {
            const factor = std.math.pow(f32, 10, @as(f32, @floatFromInt(acc)));
            return Point{
                .x = @round(mirrored_x * factor) / factor,
                .y = what.y,
            };
        }
        return Point{ .x = mirrored_x, .y = what.y };
    }
    if (over.b == 0.0) {
        const mirror_y = over.c / over.a;
        const mirrored_y = 2.0 * mirror_y - what.y;
        if (accuracy) |acc| {
            const factor = std.math.pow(f32, 10, @as(f32, @floatFromInt(acc)));
            return Point{
                .x = what.x,
                .y = @round(mirrored_y * factor) / factor,
            };
        }
        return Point{ .x = what.x, .y = mirrored_y };
    }
    return what;
}

test "mirrorPointOverLine" {
    const point1 = Point{ .x = 1.0, .y = 1.0 };
    const line1 = Line{ .a = 0.0, .b = 1.0, .c = 0.0 };
    const mirrorRes1 = mirrorPointOverLine(point1, line1, 5);
    try testing.expectEqual(@as(f32, -1.0), mirrorRes1.x);
    try testing.expectEqual(@as(f32, 1.0), mirrorRes1.y);

    const point2 = Point{ .x = 1.0, .y = -1.0 };
    const line2 = Line{ .a = 0.0, .b = 1.0, .c = 0.0 };
    const mirrorRes2 = mirrorPointOverLine(point2, line2, 5);
    try testing.expectEqual(@as(f32, -1.0), mirrorRes2.x);
    try testing.expectEqual(@as(f32, -1.0), mirrorRes2.y);

    const point3 = Point{ .x = 1.0, .y = -1.0 };
    const line3 = Line{ .a = 0.0, .b = 2.0, .c = 4.0 };
    const mirrorRes3 = mirrorPointOverLine(point3, line3, 5);
    try testing.expectEqual(@as(f32, -5.0), mirrorRes3.x);
    try testing.expectEqual(@as(f32, -1.0), mirrorRes3.y);

    const point4 = Point{ .x = -1.0, .y = -1.0 };
    const line4 = Line{ .a = 0.0, .b = 2.0, .c = 4.0 };
    const mirrorRes4 = mirrorPointOverLine(point4, line4, 5);
    try testing.expectEqual(@as(f32, -3.0), mirrorRes4.x);
    try testing.expectEqual(@as(f32, -1.0), mirrorRes4.y);

    const point5 = Point{ .x = 1.0, .y = -1.0 };
    const line5 = Line{ .a = 0.0, .b = -2.0, .c = 4.0 };
    const mirrorRes5 = mirrorPointOverLine(point5, line5, 5);
    try testing.expectEqual(@as(f32, 3.0), mirrorRes5.x);
    try testing.expectEqual(@as(f32, -1.0), mirrorRes5.y);

    const point6 = Point{ .x = -1.0, .y = -1.0 };
    const line6 = Line{ .a = 0.0, .b = -2.0, .c = 4.0 };
    const mirrorRes6 = mirrorPointOverLine(point6, line6, 5);
    try testing.expectEqual(@as(f32, 5.0), mirrorRes6.x);
    try testing.expectEqual(@as(f32, -1.0), mirrorRes6.y);

    const point7 = Point{ .x = 2.0, .y = -1.0 };
    const line7 = Line{ .a = 0.0, .b = -2.0, .c = 4.0 };
    const mirrorRes7 = mirrorPointOverLine(point7, line7, 5);
    try testing.expectEqual(@as(f32, 2.0), mirrorRes7.x);
    try testing.expectEqual(@as(f32, -1.0), mirrorRes7.y);

    const point8 = Point{ .x = 2.0, .y = -1.0 };
    const line8 = Line{ .a = -2.0, .b = 0.0, .c = 2.0 };
    const mirrorRes8 = mirrorPointOverLine(point8, line8, 5);
    try testing.expectEqual(@as(f32, 2.0), mirrorRes8.x);
    try testing.expectEqual(@as(f32, -1.0), mirrorRes8.y);

    const point9 = Point{ .x = 2.0, .y = -1.0 };
    const line9 = Line{ .a = -2.0, .b = 0.0, .c = 4.0 };
    const mirrorRes9 = mirrorPointOverLine(point9, line9, 5);
    try testing.expectEqual(@as(f32, 2.0), mirrorRes9.x);
    try testing.expectEqual(@as(f32, -3.0), mirrorRes9.y);

    const point10 = Point{ .x = 2.0, .y = 1.0 };
    const line10 = Line{ .a = -2.0, .b = 0.0, .c = 4.0 };
    const mirrorRes10 = mirrorPointOverLine(point10, line10, 5);
    try testing.expectEqual(@as(f32, 2.0), mirrorRes10.x);
    try testing.expectEqual(@as(f32, -5.0), mirrorRes10.y);

    const point11 = Point{ .x = 2.0, .y = 1.0 };
    const line11 = Line{ .a = 2.0, .b = 0.0, .c = 4.0 };
    const mirrorRes11 = mirrorPointOverLine(point11, line11, 5);
    try testing.expectEqual(@as(f32, 2.0), mirrorRes11.x);
    try testing.expectEqual(@as(f32, 3.0), mirrorRes11.y);

    const point12 = Point{ .x = 2.0, .y = -1.0 };
    const line12 = Line{ .a = 2.0, .b = 0.0, .c = 4.0 };
    const mirrorRes12 = mirrorPointOverLine(point12, line12, 5);
    try testing.expectEqual(@as(f32, 2.0), mirrorRes12.x);
    try testing.expectEqual(@as(f32, 5.0), mirrorRes12.y);
}
