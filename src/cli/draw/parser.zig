const mecha = @import("mecha");
const std = @import("std");
const attr = @import("attributes.zig");
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
    elementNumber: u8,
    elementType: ElementType,
    coordinateSystem: ?CoordinateType = .xy,
    coordinateOrientation: ?CoordinateOrientation = .fixed,
};

pub const ReferenceFrame = enum {
    local, // in reference to local reference frame, for example, 20 means 1/5 in the context to something, so when something get larger then the attribute is scaled accordingly
    global, // in reference to global reference frame, for example, 5 means 5% computed wrt the final vector space
    normalized, // in reference to global reference frame, for example, 10 means 10% of the height/width of the final diagram
    output, // in reference to the requested output size of diagram
};

pub const LineWidthType = struct {
    reference: ReferenceFrame,
    value: u8, // in %
};

pub const LineColorType = struct {
    value: attr.ColorName,
};

pub const Vec2dStyles = struct {
    lineWidth: LineWidthType,
    lineColor: LineColorType,
};

//Parsers
const skipWhitespace =
    mecha.ascii.char(' ').many(.{ .collect = false }).discard();
const skipOpenBracket =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(':').discard(), skipWhitespace, mecha.ascii.char('{').discard() });
const skipCloseBracket =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('}').discard(), skipWhitespace });

const elementNumberParser =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('e').discard(), mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 }).asStr().convert(mecha.toInt(u8, 10)) });
const elementTypeParser =
    mecha.combine(.{ skipWhitespace, mecha.convert(mecha.string("vec2d").asStr(), mecha.toEnum(ElementType)) });
const coordinateTypeParser =
    mecha.combine(.{ skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("xy"), mecha.string("polar") }).asStr(), mecha.toEnum(CoordinateType)) });
const coordinateOrientationParser =
    mecha.combine(.{ skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("fixed"), mecha.string("adjusting") }).asStr(), mecha.toEnum(CoordinateOrientation)) });

//LineWidth parser
const lineWidthTypeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("lwL"), mecha.string("lwG"), mecha.string("lwN"), mecha.string("lwO"), mecha.string("lw") }), skipWhitespace, mecha.ascii.char(':').discard(), skipWhitespace, mecha.int(u8, .{}) });

const lineWidthTypeParserRawP = @TypeOf(lineWidthTypeParserRaw);
const LineWidthT = enum {
    lw,
    lwL,
    lwG,
    lwN,
    lwO,
};
fn toLineWidthType(_: std.mem.Allocator, res: lineWidthTypeParserRawP.T) mecha.ConvertError!LineWidthType {
    const to = struct {
        fn to(str: []const u8) ?LineWidthT {
            return std.meta.stringToEnum(LineWidthT, str);
        }
    }.to;
    if (to(res[0])) |validT| {
        const switchRes: ReferenceFrame = switch (validT) {
            .lw => .local,
            .lwL => .local,
            .lwG => .global,
            .lwN => .normalized,
            .lwO => .output,
        };
        return .{
            .reference = switchRes,
            .value = res[1],
        };
    } else {
        return error.ConversionFailed;
    }
}
const lineWidthTypeParserTyped = lineWidthTypeParserRaw.convert(toLineWidthType);

//LineColor parser
const lineColorTypeParserRaw =
    mecha.combine(.{ mecha.string("lc").discard(), skipWhitespace, mecha.ascii.char(':').discard(), skipWhitespace, attr.colorNameParserTyped });
const lineColorTypeParserRawP = @TypeOf(lineColorTypeParserRaw);
fn toLineColorType(_: std.mem.Allocator, res: lineColorTypeParserRawP.T) mecha.ConvertError!LineColorType {
    return .{ .value = res };
}
const lineColorTypeParserTyped = lineColorTypeParserRaw.convert(toLineColorType);

const elementParser =
    mecha.combine(.{ elementNumberParser, skipOpenBracket, elementTypeParser, coordinateTypeParser.opt(), coordinateOrientationParser.opt(), skipCloseBracket }).map(mecha.toStruct(ElementDrawCmd));

test "elementNumber" {
    const fa = testing.failing_allocator;

    const r1 = try elementNumberParser.parse(fa, "e2");
    try testing.expectEqual(2, r1.value.ok);

    const r2 = try elementNumberParser.parse(fa, " e0");
    try testing.expectEqual(0, r2.value.ok);

    const r3 = try elementNumberParser.parse(fa, " e11");
    try testing.expectEqual(11, r3.value.ok);

    const r4 = try elementNumberParser.parse(fa, "11");
    try testing.expectEqual(0, r4.index);
}

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

test "element" {
    const fa = testing.failing_allocator;

    const r1 = try elementParser.parse(fa, "e0:{vec2d}");
    try testing.expectEqual(ElementDrawCmd{ .elementNumber = 0, .elementType = .vec2d, .coordinateSystem = null, .coordinateOrientation = null }, r1.value.ok);

    const r2 = try elementParser.parse(fa, " e0 :{ vec2d     }    ");
    try testing.expectEqual(ElementDrawCmd{ .elementNumber = 0, .elementType = .vec2d, .coordinateSystem = null, .coordinateOrientation = null }, r2.value.ok);

    const r3 = try elementParser.parse(fa, "e5:{vec2d fixed}");
    try testing.expectEqual(ElementDrawCmd{ .elementNumber = 5, .elementType = .vec2d, .coordinateSystem = null, .coordinateOrientation = .fixed }, r3.value.ok);

    const r4 = try elementParser.parse(fa, "e7:{vec2d xy fixed}");
    try testing.expectEqual(ElementDrawCmd{ .elementNumber = 7, .elementType = .vec2d, .coordinateSystem = .xy, .coordinateOrientation = .fixed }, r4.value.ok);
}

test "LineWidthTypeParserRaw" {
    const fa = testing.failing_allocator;

    const Parser = @TypeOf(lineWidthTypeParserRaw);

    const r1 = try lineWidthTypeParserRaw.parse(fa, "lw:10");
    try testing.expectEqual(Parser.T{ "lw", 10 }, r1.value.ok);

    const r2 = try lineWidthTypeParserRaw.asStr().parse(fa, "lw  :  10");
    try testing.expectEqualStrings("lw  :  10", r2.value.ok);

    const r3 = try lineWidthTypeParserRaw.parse(fa, "lwL  :  10");
    try testing.expectEqual(Parser.T{ "lwL", 10 }, r3.value.ok);
}

test "LineWidthTypeParserTyped" {
    const fa = testing.failing_allocator;

    const r1 = try lineWidthTypeParserTyped.parse(fa, "lw:10");
    try testing.expectEqual(LineWidthType{ .reference = .local, .value = 10 }, r1.value.ok);

    const r2 = try lineWidthTypeParserTyped.parse(fa, "lw  :  10");
    try testing.expectEqual(LineWidthType{ .reference = .local, .value = 10 }, r2.value.ok);

    const r3 = try lineWidthTypeParserTyped.parse(fa, "lwG  :  6");
    try testing.expectEqual(LineWidthType{ .reference = .global, .value = 6 }, r3.value.ok);
}

test "LineWColorTypeParserTyped" {
    const fa = testing.failing_allocator;

    const r1 = try lineColorTypeParserTyped.parse(fa, "lc:green");
    try testing.expectEqual(LineColorType{ .value = .green }, r1.value.ok);

    const r2 = try lineColorTypeParserTyped.parse(fa, "lc :  green");
    try testing.expectEqual(LineColorType{ .value = .green }, r2.value.ok);

    const r3 = try lineColorTypeParserTyped.parse(fa, "lc : yellow");
    try testing.expectEqual(LineColorType{ .value = .yellow }, r3.value.ok);
}
