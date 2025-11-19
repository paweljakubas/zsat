const mecha = @import("mecha");
const std = @import("std");
const testing = std.testing;

//element
pub const ElementType = enum {
    Vector2D,
    Point2D,
};

// coordinate system type
pub const CoordinateType = enum {
    Cartesian2D, //(x,y)
    Polar2D, //(r, phi)
};

// coordinate axis position
pub const CoordinateOrientation = enum {
    Fixed, //coordinate always stays the same positioned in the space
    Adjusting, //coordinate starts for each segment as set and then rotates in such a way that x or r axis follows the last segment
};

pub const ElementDrawCmd = struct {
    element: ElementType,
    coordinateSystem: CoordinateType,
    coordinateOrientation: CoordinateOrientation,
};

//Parsers
const skipWhitespace =
    mecha.ascii.char(' ').many(.{ .collect = false }).discard();

pub const elementTypeParser = mecha.combine(.{ skipWhitespace, mecha.string("vec") });

test "elementType" {
    const fa = testing.failing_allocator;

    const r1 = try elementTypeParser.parse(fa, "vec");
    try testing.expectEqualStrings("vec", r1.value.ok);

    const r2 = try elementTypeParser.parse(fa, " vec");
    try testing.expectEqualStrings("vec", r2.value.ok);
}
