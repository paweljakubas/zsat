const mecha = @import("mecha");
const std = @import("std");
const testing = std.testing;

//element
pub const ElementType = enum {
    vec2d,
    //Point2D,
};

// coordinate system type
pub const CoordinateType = enum {
    xy, //(x,y)
    polar, //(r, phi)
};

// coordinate axis position
pub const CoordinateOrientation = enum {
    fixed, //coordinate always stays the same positioned in the space, following figure borders
    adjusting, //coordinate starts as Fixed and then rotates in such a way that x or r axis follows the last segment
};

pub const ElementDrawCmd = struct {
    elementName: u8,
    element: ElementType,
    coordinateSystem: ?CoordinateType = .xy,
    coordinateOrientation: ?CoordinateOrientation = .fixed,
};

//Parsers
const skipWhitespace =
    mecha.ascii.char(' ').many(.{ .collect = false }).discard();

const elementTypeParser =
    mecha.combine(.{ skipWhitespace, mecha.convert(mecha.string("vec2d").asStr(), mecha.toEnum(ElementType)) });
const coordinateTypeParser =
    mecha.combine(.{ skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("xy"), mecha.string("polar") }).asStr(), mecha.toEnum(CoordinateType)) });
const coordinateOrientationParser =
    mecha.combine(.{ skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("fixed"), mecha.string("adjusting") }).asStr(), mecha.toEnum(CoordinateOrientation)) });

//const elementParser = mecha.combine(.{ elementTypeParser, mecha.opt(.{coordinateTypeParser}), mecha.opt(.{coordinateOrientationParser}) });

test "elementType" {
    const fa = testing.failing_allocator;

    const r1 = try elementTypeParser.parse(fa, "vec2d");
    try testing.expectEqual(.vec2d, r1.value.ok);

    const r2 = try elementTypeParser.parse(fa, " vec2d");
    try testing.expectEqual(.vec2d, r2.value.ok);

    const r3 = try elementTypeParser.parse(fa, "dot");
    try testing.expectEqual(0, r3.index);
}

test "coordinateType" {
    const fa = testing.failing_allocator;

    const r1 = try coordinateTypeParser.parse(fa, "xy");
    try testing.expectEqual(.xy, r1.value.ok);

    const r2 = try coordinateTypeParser.parse(fa, " xy");
    try testing.expectEqual(.xy, r2.value.ok);

    const r3 = try coordinateTypeParser.parse(fa, "polar");
    try testing.expectEqual(.polar, r3.value.ok);

    const r4 = try coordinateTypeParser.parse(fa, "rad");
    try testing.expectEqual(0, r4.index);
}

test "coordinateOrientationParser" {
    const fa = testing.failing_allocator;

    const r1 = try coordinateOrientationParser.parse(fa, "fixed");
    try testing.expectEqual(.fixed, r1.value.ok);

    const r2 = try coordinateOrientationParser.parse(fa, " fixed");
    try testing.expectEqual(.fixed, r2.value.ok);

    const r3 = try coordinateOrientationParser.parse(fa, " adjusting");
    try testing.expectEqual(.adjusting, r3.value.ok);

    const r4 = try coordinateOrientationParser.parse(fa, "var");
    try testing.expectEqual(0, r4.index);
}

//test "element" {
//    const fa = testing.failing_allocator;
//
//    const r1 = try elementParser.parse(fa, "e0:{vec}");
//    try testing.expectEqualStrings("vec", r1.value.ok);
//}
