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

    pub fn defaultCoordinateType() CoordinateType {
        return .xy;
    }
};

// coordinate axis position
pub const CoordinateOrientation = enum {
    fixed, //coordinate always stays the same positioned in the space, following figure borders
    adjusting, //coordinate starts as Fixed and then rotates in such a way that x or r axis follows the last segment

    pub fn defaultCoordinateOrientation() CoordinateOrientation {
        return .fixed;
    }
};

pub const ElementDrawCmd = struct {
    elementNumber: u8,
    elementType: ElementType,
    coordinateSystem: ?CoordinateType = .defaultCoordinateType(),
    coordinateOrientation: ?CoordinateOrientation = .defaultCoordinateOrientation(),
    elementStyle: ?Vec2dStyles = Vec2dStyles{},
};

const ElementDrawCmdUnion = union(enum) {
    elementNumber: u8,
    elementType: ElementType,
    coordinateSystem: CoordinateType,
    coordinateOrientation: CoordinateOrientation,
    elementStyle: Vec2dStyles,
};

pub const ReferenceFrame = enum {
    local, // in reference to local reference frame, for example, 200 means 1/5 in the context to something, so when something get larger then the attribute is scaled accordingly
    global, // in reference to global reference frame, for example, 50 means 5% computed wrt the final vector space
    normalized, // in reference to global reference frame, for example, 10 means 1% of the height/width of the final diagram
    output, // in reference to the requested output size of diagram, for example, 10 in pixels
};

pub const LineWidthType = struct {
    reference: ReferenceFrame,
    value: u16, // in 0.1 % for local/global/normalized and in number of pixels for output

    fn defaultLineWidthaType() LineWidthType {
        return LineWidthType{
            .reference = .normalized,
            .value = 20,
        };
    }
};

pub const LineColorType = struct {
    value: attr.ColorName,

    pub fn defaultLineColorType() LineColorType {
        return LineColorType{
            .value = .black,
        };
    }
};

pub const LineOpacityType = struct {
    value: u8, // The opacity is a value between 100 (completely opaque, the default) and 0 (completely transparent) with relation to the current opacity.

    pub fn defaultLineOpacityType() LineOpacityType {
        return LineOpacityType{
            .value = 100,
        };
    }
};

pub const LineCap = enum {
    none,
    butt,
    round,
    square,
};

pub const LineCapType = struct {
    value: LineCap,

    pub fn defaultLineCapType() LineCapType {
        return LineCapType{
            .value = .none,
        };
    }
};

pub const LineJoin = enum {
    none,
    mitter,
    round,
    bevel,
};

pub const LineJoinType = struct {
    value: LineJoin,

    pub fn defaultLineJoinType() LineJoinType {
        return LineJoinType{
            .value = .none,
        };
    }
};

pub const LineDashingType = struct {
    reference: ReferenceFrame,
    onOff: []const u16, // in 0.1 % for local/global/normalized (i.e., 10 = 1%) and in number of pixels for output
    offset: u16, // in 0.1 % for local/global/normalized (i.e., 10 = 1%) and in number of pixels for output

    pub fn defaultLineDashingType() LineDashingType {
        return LineDashingType{
            .reference = .normalized,
            .onOff = &[2]u16{ 10, 10 },
            .offset = 0,
        };
    }
};

pub const Vec2dStyles = struct {
    lineWidth: LineWidthType = .defaultLineWidthaType(),
    lineColor: LineColorType = .defaultLineColorType(),
    lineOpacity: LineOpacityType = .defaultLineOpacityType(),
    lineCap: LineCapType = .defaultLineCapType(),
    lineJoin: LineJoinType = .defaultLineJoinType(),
    lineDashing: LineDashingType = .defaultLineDashingType(),
};

const Vec2dStylesUnion = union(enum) {
    lineWidth: LineWidthType,
    lineColor: LineColorType,
    lineOpacity: LineOpacityType,
    lineCap: LineCapType,
    lineJoin: LineJoinType,
    lineDashing: LineDashingType,
};

//Parsers
const skipWhitespace =
    mecha.ascii.char(' ').many(.{ .collect = false }).discard();
const skipOpenBracket =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(':').discard(), skipWhitespace, mecha.ascii.char('{').discard() });
const skipCloseBracket =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('}').discard(), skipWhitespace });
const skipOpenRecBracket =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('[').discard() });
const skipCloseRecBracket =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(']').discard(), skipWhitespace });

const elementNumberParserRaw =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('e').discard(), mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 }).asStr().convert(mecha.toInt(u8, 10)) });
const elementNumberParserRawP = @TypeOf(elementNumberParserRaw);
fn toElementNumberUnion(_: std.mem.Allocator, res: elementNumberParserRawP.T) mecha.ConvertError!ElementDrawCmdUnion {
    return ElementDrawCmdUnion{ .elementNumber = res };
}
const elementNumberUnionParser = elementNumberParserRaw.convert(toElementNumberUnion);

const elementTypeParserRaw =
    mecha.combine(.{ skipWhitespace, mecha.convert(mecha.string("vec2d").asStr(), mecha.toEnum(ElementType)) });
const elementTypeParserRawP = @TypeOf(elementTypeParserRaw);
fn toElementTypeUnion(_: std.mem.Allocator, res: elementTypeParserRawP.T) mecha.ConvertError!ElementDrawCmdUnion {
    return ElementDrawCmdUnion{ .elementType = res };
}
const elementTypeUnionParser = elementTypeParserRaw.convert(toElementTypeUnion);

const coordinateTypeParserRaw =
    mecha.combine(.{ skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("xy"), mecha.string("polar") }).asStr(), mecha.toEnum(CoordinateType)) });
const coordinateTypeParserRawP = @TypeOf(coordinateTypeParserRaw);
fn toCoordinateTypeUnion(_: std.mem.Allocator, res: coordinateTypeParserRawP.T) mecha.ConvertError!ElementDrawCmdUnion {
    return ElementDrawCmdUnion{ .coordinateSystem = res };
}
const coordinateTypeUnionParser = coordinateTypeParserRaw.convert(toCoordinateTypeUnion);

const coordinateOrientationParserRaw =
    mecha.combine(.{ skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("fixed"), mecha.string("adjusting") }).asStr(), mecha.toEnum(CoordinateOrientation)) });
const coordinateOrientationParserRawP = @TypeOf(coordinateOrientationParserRaw);
fn toCoordinateOrientationUnion(_: std.mem.Allocator, res: coordinateOrientationParserRawP.T) mecha.ConvertError!ElementDrawCmdUnion {
    return ElementDrawCmdUnion{ .coordinateOrientation = res };
}
const coordinateOrientationUnionParser = coordinateOrientationParserRaw.convert(toCoordinateOrientationUnion);

//LineWidth parser
const lineWidthTypeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("lwL"), mecha.string("lwG"), mecha.string("lwN"), mecha.string("lwO"), mecha.string("lw") }), skipWhitespace, mecha.ascii.char(':').discard(), skipWhitespace, mecha.int(u16, .{}) });
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
            .lw => .normalized,
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
fn toLineWidthUnion(_: std.mem.Allocator, res: lineWidthTypeParserRawP.T) mecha.ConvertError!Vec2dStylesUnion {
    const to = struct {
        fn to(str: []const u8) ?LineWidthT {
            return std.meta.stringToEnum(LineWidthT, str);
        }
    }.to;
    if (to(res[0])) |validT| {
        const switchRes: ReferenceFrame = switch (validT) {
            .lw => .normalized,
            .lwL => .local,
            .lwG => .global,
            .lwN => .normalized,
            .lwO => .output,
        };
        return Vec2dStylesUnion{ .lineWidth = .{
            .reference = switchRes,
            .value = res[1],
        } };
    } else {
        return error.ConversionFailed;
    }
}
const lineWidthUnionParser = lineWidthTypeParserRaw.convert(toLineWidthUnion);

//LineColor parser
const lineColorTypeParserRaw =
    mecha.combine(.{ mecha.string("lc").discard(), skipWhitespace, mecha.ascii.char(':').discard(), skipWhitespace, attr.colorNameParserTyped });
const lineColorTypeParserRawP = @TypeOf(lineColorTypeParserRaw);
fn toLineColorType(_: std.mem.Allocator, res: lineColorTypeParserRawP.T) mecha.ConvertError!LineColorType {
    return .{ .value = res };
}
const lineColorTypeParserTyped = lineColorTypeParserRaw.convert(toLineColorType);
fn toLineColorUnion(_: std.mem.Allocator, res: lineColorTypeParserRawP.T) mecha.ConvertError!Vec2dStylesUnion {
    return Vec2dStylesUnion{ .lineColor = .{ .value = res } };
}
const lineColorUnionParser = lineColorTypeParserRaw.convert(toLineColorUnion);

//LineOpacity parser
const lineOpacityTypeParserRaw =
    mecha.combine(.{ mecha.string("lo").discard(), skipWhitespace, mecha.ascii.char(':').discard(), skipWhitespace, mecha.int(u8, .{}) });
const lineOpacityTypeParserRawP = @TypeOf(lineOpacityTypeParserRaw);
fn toLineOpacityType(_: std.mem.Allocator, res: lineOpacityTypeParserRawP.T) mecha.ConvertError!LineOpacityType {
    return .{ .value = res };
}
const lineOpacityTypeParserTyped = lineOpacityTypeParserRaw.convert(toLineOpacityType);
fn toLineOpacityUnion(_: std.mem.Allocator, res: lineOpacityTypeParserRawP.T) mecha.ConvertError!Vec2dStylesUnion {
    return Vec2dStylesUnion{ .lineOpacity = .{ .value = res } };
}
const lineOpacityUnionParser = lineOpacityTypeParserRaw.convert(toLineOpacityUnion);

//LineCap parser
const lineCapTypeParserRaw =
    mecha.combine(.{ mecha.string("le").discard(), skipWhitespace, mecha.ascii.char(':').discard(), skipWhitespace, mecha.oneOf(.{ mecha.string("none"), mecha.string("n"), mecha.string("butt"), mecha.string("b"), mecha.string("round"), mecha.string("r"), mecha.string("square"), mecha.string("s") }) });
const lineCapTypeParserRawP = @TypeOf(lineCapTypeParserRaw);
const LineCapT = enum {
    none,
    n,
    butt,
    b,
    round,
    r,
    square,
    s,
};
fn toLineCapType(_: std.mem.Allocator, res: lineCapTypeParserRawP.T) mecha.ConvertError!LineCapType {
    const to = struct {
        fn to(str: []const u8) ?LineCapT {
            return std.meta.stringToEnum(LineCapT, str);
        }
    }.to;
    if (to(res)) |validT| {
        const switchRes: LineCap = switch (validT) {
            .none => .none,
            .n => .none,
            .butt => .butt,
            .b => .butt,
            .round => .round,
            .r => .round,
            .square => .square,
            .s => .square,
        };
        return .{
            .value = switchRes,
        };
    } else {
        return error.ConversionFailed;
    }
}
const lineCapTypeParserTyped = lineCapTypeParserRaw.convert(toLineCapType);
fn toLineCapUnion(_: std.mem.Allocator, res: lineCapTypeParserRawP.T) mecha.ConvertError!Vec2dStylesUnion {
    const to = struct {
        fn to(str: []const u8) ?LineCapT {
            return std.meta.stringToEnum(LineCapT, str);
        }
    }.to;
    if (to(res)) |validT| {
        const switchRes: LineCap = switch (validT) {
            .none => .none,
            .n => .none,
            .butt => .butt,
            .b => .butt,
            .round => .round,
            .r => .round,
            .square => .square,
            .s => .square,
        };
        return Vec2dStylesUnion{ .lineCap = .{
            .value = switchRes,
        } };
    } else {
        return error.ConversionFailed;
    }
}
const lineCapUnionParser = lineCapTypeParserRaw.convert(toLineCapUnion);

//LineJoin parser
const lineJoinTypeParserRaw =
    mecha.combine(.{ mecha.string("lj").discard(), skipWhitespace, mecha.ascii.char(':').discard(), skipWhitespace, mecha.oneOf(.{ mecha.string("none"), mecha.string("n"), mecha.string("mitter"), mecha.string("m"), mecha.string("round"), mecha.string("r"), mecha.string("bevel"), mecha.string("b") }) });
const lineJoinTypeParserRawP = @TypeOf(lineJoinTypeParserRaw);
const LineJoinT = enum {
    none,
    n,
    mitter,
    m,
    round,
    r,
    bevel,
    b,
};
fn toLineJoinType(_: std.mem.Allocator, res: lineJoinTypeParserRawP.T) mecha.ConvertError!LineJoinType {
    const to = struct {
        fn to(str: []const u8) ?LineJoinT {
            return std.meta.stringToEnum(LineJoinT, str);
        }
    }.to;
    if (to(res)) |validT| {
        const switchRes: LineJoin = switch (validT) {
            .none => .none,
            .n => .none,
            .mitter => .mitter,
            .m => .mitter,
            .round => .round,
            .r => .round,
            .bevel => .bevel,
            .b => .bevel,
        };
        return .{
            .value = switchRes,
        };
    } else {
        return error.ConversionFailed;
    }
}
const lineJoinTypeParserTyped = lineJoinTypeParserRaw.convert(toLineJoinType);
fn toLineJoinUnion(_: std.mem.Allocator, res: lineJoinTypeParserRawP.T) mecha.ConvertError!Vec2dStylesUnion {
    const to = struct {
        fn to(str: []const u8) ?LineJoinT {
            return std.meta.stringToEnum(LineJoinT, str);
        }
    }.to;
    if (to(res)) |validT| {
        const switchRes: LineJoin = switch (validT) {
            .none => .none,
            .n => .none,
            .mitter => .mitter,
            .m => .mitter,
            .round => .round,
            .r => .round,
            .bevel => .bevel,
            .b => .bevel,
        };
        return Vec2dStylesUnion{ .lineJoin = .{
            .value = switchRes,
        } };
    } else {
        return error.ConversionFailed;
    }
}
const lineJoinUnionParser = lineJoinTypeParserRaw.convert(toLineJoinUnion);

//LineDashing parser
const lineDashingTypeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("ldL"), mecha.string("ldG"), mecha.string("ldN"), mecha.string("ldO"), mecha.string("ld") }), skipWhitespace, mecha.ascii.char(':').discard(), skipWhitespace, mecha.string("[").discard(), skipWhitespace, mecha.int(u16, .{}).many(.{ .collect = true, .min = 2, .separator = mecha.combine(.{ skipWhitespace, mecha.string(","), skipWhitespace }).discard() }), skipWhitespace, mecha.string("]").discard(), skipWhitespace, mecha.int(u16, .{}) });
const lineDashingTypeParserRawP = @TypeOf(lineDashingTypeParserRaw);
const LineDashingT = enum {
    ld,
    ldL,
    ldG,
    ldN,
    ldO,
};
fn toLineDashingType(_: std.mem.Allocator, res: lineDashingTypeParserRawP.T) mecha.ConvertError!LineDashingType {
    const to = struct {
        fn to(str: []const u8) ?LineDashingT {
            return std.meta.stringToEnum(LineDashingT, str);
        }
    }.to;
    if (to(res[0])) |validT| {
        const switchRes: ReferenceFrame = switch (validT) {
            .ld => .normalized,
            .ldL => .local,
            .ldG => .global,
            .ldN => .normalized,
            .ldO => .output,
        };
        return .{
            .reference = switchRes,
            .onOff = res[1],
            .offset = res[2],
        };
    } else {
        return error.ConversionFailed;
    }
}
const lineDashingTypeParserTyped = lineDashingTypeParserRaw.convert(toLineDashingType);
fn toLineDashingUnion(_: std.mem.Allocator, res: lineDashingTypeParserRawP.T) mecha.ConvertError!Vec2dStylesUnion {
    const to = struct {
        fn to(str: []const u8) ?LineDashingT {
            return std.meta.stringToEnum(LineDashingT, str);
        }
    }.to;
    if (to(res[0])) |validT| {
        const switchRes: ReferenceFrame = switch (validT) {
            .ld => .normalized,
            .ldL => .local,
            .ldG => .global,
            .ldN => .normalized,
            .ldO => .output,
        };
        return Vec2dStylesUnion{ .lineDashing = .{
            .reference = switchRes,
            .onOff = res[1],
            .offset = res[2],
        } };
    } else {
        return error.ConversionFailed;
    }
}
const lineDashingUnionParser = lineDashingTypeParserRaw.convert(toLineDashingUnion);

//Vec2dStyles parser
const vec2dStyleUnionParser = mecha.oneOf(.{
    lineWidthUnionParser,
    lineColorUnionParser,
    lineOpacityUnionParser,
    lineCapUnionParser,
    lineJoinUnionParser,
    lineDashingUnionParser,
});

const vec2dStyleSeparatorParser = mecha.combine(.{ skipWhitespace, mecha.ascii.char(',').discard(), skipWhitespace });
const many_vec2dStyleUnionParser = mecha.many(vec2dStyleUnionParser, .{ .separator = vec2dStyleSeparatorParser });
fn manyToVec2dStyles(alloc: std.mem.Allocator, fields: []Vec2dStylesUnion) mecha.ConvertError!Vec2dStyles {
    var res = Vec2dStyles{};
    for (fields) |field| switch (field) {
        .lineWidth => |f| res.lineWidth = f,
        .lineColor => |f| res.lineColor = f,
        .lineOpacity => |f| res.lineOpacity = f,
        .lineCap => |f| res.lineCap = f,
        .lineJoin => |f| res.lineJoin = f,
        .lineDashing => |f| res.lineDashing = f,
    };

    alloc.free(fields);
    return res;
}
const vec2dStylesParser = many_vec2dStyleUnionParser.convert(manyToVec2dStyles);
const vec2dStylesParserBracketed = mecha.combine(.{ skipOpenRecBracket, vec2dStylesParser, skipCloseRecBracket });

//ElementDrawCmd parser
const elementParserUnionParser = mecha.oneOf(.{
    elementNumberUnionParser,
    elementTypeUnionParser,
    coordinateTypeUnionParser,
    coordinateOrientationUnionParser,
});

const elementParser =
    mecha.combine(.{ elementNumberParserRaw, skipOpenBracket, elementTypeParserRaw, coordinateTypeParserRaw.opt(), coordinateOrientationParserRaw.opt(), skipCloseBracket, vec2dStylesParserBracketed.opt() }).map(mecha.toStruct(ElementDrawCmd));

test "elementNumber" {
    const fa = testing.failing_allocator;

    const r1 = try elementNumberParserRaw.parse(fa, "e2");
    try testing.expectEqual(2, r1.value.ok);

    const r2 = try elementNumberParserRaw.parse(fa, " e0");
    try testing.expectEqual(0, r2.value.ok);

    const r3 = try elementNumberParserRaw.parse(fa, " e11");
    try testing.expectEqual(11, r3.value.ok);

    const r4 = try elementNumberParserRaw.parse(fa, "11");
    try testing.expectEqual(0, r4.index);
}

test "elementNumberUnion" {
    const fa = testing.failing_allocator;

    const r1 = try elementNumberUnionParser.parse(fa, "e2");
    try testing.expectEqual(ElementDrawCmdUnion{ .elementNumber = 2 }, r1.value.ok);

    const r2 = try elementNumberUnionParser.parse(fa, " e0");
    try testing.expectEqual(ElementDrawCmdUnion{ .elementNumber = 0 }, r2.value.ok);

    const r3 = try elementNumberUnionParser.parse(fa, " e11");
    try testing.expectEqual(ElementDrawCmdUnion{ .elementNumber = 11 }, r3.value.ok);
}

test "elementType" {
    const fa = testing.failing_allocator;

    const r1 = try elementTypeParserRaw.parse(fa, "vec2d");
    try testing.expectEqual(.vec2d, r1.value.ok);

    const r2 = try elementTypeParserRaw.parse(fa, " vec2d");
    try testing.expectEqual(.vec2d, r2.value.ok);

    const r3 = try elementTypeParserRaw.parse(fa, "dot");
    try testing.expectEqual(0, r3.index);
}

test "elementTypeUnion" {
    const fa = testing.failing_allocator;

    const r1 = try elementTypeUnionParser.parse(fa, "vec2d");
    try testing.expectEqual(ElementDrawCmdUnion{ .elementType = .vec2d }, r1.value.ok);

    const r2 = try elementTypeUnionParser.parse(fa, " vec2d");
    try testing.expectEqual(ElementDrawCmdUnion{ .elementType = .vec2d }, r2.value.ok);
}

test "coordinateType" {
    const fa = testing.failing_allocator;

    const r1 = try coordinateTypeParserRaw.parse(fa, "xy");
    try testing.expectEqual(.xy, r1.value.ok);

    const r2 = try coordinateTypeParserRaw.parse(fa, " xy");
    try testing.expectEqual(.xy, r2.value.ok);

    const r3 = try coordinateTypeParserRaw.parse(fa, "polar");
    try testing.expectEqual(.polar, r3.value.ok);

    const r4 = try coordinateTypeParserRaw.parse(fa, "rad");
    try testing.expectEqual(0, r4.index);
}

test "coordinateTypeUnion" {
    const fa = testing.failing_allocator;

    const r1 = try coordinateTypeUnionParser.parse(fa, "xy");
    try testing.expectEqual(ElementDrawCmdUnion{ .coordinateSystem = .xy }, r1.value.ok);

    const r2 = try coordinateTypeUnionParser.parse(fa, " xy");
    try testing.expectEqual(ElementDrawCmdUnion{ .coordinateSystem = .xy }, r2.value.ok);

    const r3 = try coordinateTypeUnionParser.parse(fa, "polar");
    try testing.expectEqual(ElementDrawCmdUnion{ .coordinateSystem = .polar }, r3.value.ok);
}

test "coordinateOrientationParser" {
    const fa = testing.failing_allocator;

    const r1 = try coordinateOrientationParserRaw.parse(fa, "fixed");
    try testing.expectEqual(.fixed, r1.value.ok);

    const r2 = try coordinateOrientationParserRaw.parse(fa, " fixed");
    try testing.expectEqual(.fixed, r2.value.ok);

    const r3 = try coordinateOrientationParserRaw.parse(fa, " adjusting");
    try testing.expectEqual(.adjusting, r3.value.ok);

    const r4 = try coordinateOrientationParserRaw.parse(fa, "var");
    try testing.expectEqual(0, r4.index);
}

test "coordinateOrientationUnionParser" {
    const fa = testing.failing_allocator;

    const r1 = try coordinateOrientationUnionParser.parse(fa, "fixed");
    try testing.expectEqual(ElementDrawCmdUnion{ .coordinateOrientation = .fixed }, r1.value.ok);

    const r2 = try coordinateOrientationUnionParser.parse(fa, " fixed");
    try testing.expectEqual(ElementDrawCmdUnion{ .coordinateOrientation = .fixed }, r2.value.ok);

    const r3 = try coordinateOrientationUnionParser.parse(fa, " adjusting");
    try testing.expectEqual(ElementDrawCmdUnion{ .coordinateOrientation = .adjusting }, r3.value.ok);
}

test "element" {
    const fa = testing.failing_allocator;

    const r1 = try elementParser.parse(fa, "e0:{vec2d}");
    try testing.expectEqual(ElementDrawCmd{ .elementNumber = 0, .elementType = .vec2d, .coordinateSystem = null, .coordinateOrientation = null, .elementStyle = null }, r1.value.ok);

    const r2 = try elementParser.parse(fa, " e0 :{ vec2d     }    ");
    try testing.expectEqual(ElementDrawCmd{ .elementNumber = 0, .elementType = .vec2d, .coordinateSystem = null, .coordinateOrientation = null, .elementStyle = null }, r2.value.ok);

    const r3 = try elementParser.parse(fa, "e5:{vec2d fixed}");
    try testing.expectEqual(ElementDrawCmd{ .elementNumber = 5, .elementType = .vec2d, .coordinateSystem = null, .coordinateOrientation = .fixed, .elementStyle = null }, r3.value.ok);

    const r4 = try elementParser.parse(fa, "e7:{vec2d xy fixed}");
    try testing.expectEqual(ElementDrawCmd{ .elementNumber = 7, .elementType = .vec2d, .coordinateSystem = .xy, .coordinateOrientation = .fixed, .elementStyle = null }, r4.value.ok);
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
    try testing.expectEqual(LineWidthType{ .reference = .normalized, .value = 10 }, r1.value.ok);

    const r2 = try lineWidthTypeParserTyped.parse(fa, "lw  :  10");
    try testing.expectEqual(LineWidthType{ .reference = .normalized, .value = 10 }, r2.value.ok);

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

test "LineOpacityTypeParserTyped" {
    const fa = testing.failing_allocator;

    const r1 = try lineOpacityTypeParserTyped.parse(fa, "lo:10");
    try testing.expectEqual(LineOpacityType{ .value = 10 }, r1.value.ok);

    const r2 = try lineOpacityTypeParserTyped.parse(fa, "lo  :  10");
    try testing.expectEqual(LineOpacityType{ .value = 10 }, r2.value.ok);

    const r3 = try lineOpacityTypeParserTyped.parse(fa, "lo  :  6");
    try testing.expectEqual(LineOpacityType{ .value = 6 }, r3.value.ok);
}

test "LineCapTypeParserTyped" {
    const fa = testing.failing_allocator;

    const r1 = try lineCapTypeParserTyped.parse(fa, "le: n");
    try testing.expectEqual(LineCapType{ .value = .none }, r1.value.ok);

    const r2 = try lineCapTypeParserTyped.parse(fa, "le  :  none");
    try testing.expectEqual(LineCapType{ .value = .none }, r2.value.ok);

    const r3 = try lineCapTypeParserTyped.parse(fa, "le  :  b");
    try testing.expectEqual(LineCapType{ .value = .butt }, r3.value.ok);
}

test "LineJoinTypeParserTyped" {
    const fa = testing.failing_allocator;

    const r1 = try lineJoinTypeParserTyped.parse(fa, "lj: n");
    try testing.expectEqual(LineJoinType{ .value = .none }, r1.value.ok);

    const r2 = try lineJoinTypeParserTyped.parse(fa, "lj  :  none");
    try testing.expectEqual(LineJoinType{ .value = .none }, r2.value.ok);

    const r3 = try lineJoinTypeParserTyped.parse(fa, "lj  :  b");
    try testing.expectEqual(LineJoinType{ .value = .bevel }, r3.value.ok);
}

test "LineDashingTypeParserTyped" {
    const a = testing.allocator;

    const r1 = try lineDashingTypeParserTyped.parse(a, "ld: [2 , 3] 1");
    defer a.free(r1.value.ok.onOff);
    try testing.expectEqualDeep(LineDashingType{ .reference = .normalized, .onOff = &[2]u16{ 2, 3 }, .offset = 1 }, r1.value.ok);

    const r2 = try lineDashingTypeParserTyped.parse(a, "ld  :  [2   ,    3]    1");
    defer a.free(r2.value.ok.onOff);
    try testing.expectEqualDeep(LineDashingType{ .reference = .normalized, .onOff = &[_]u16{ 2, 3 }, .offset = 1 }, r2.value.ok);

    const r3 = try lineDashingTypeParserTyped.parse(a, "ldG  :  [ 2,3,10] 0");
    defer a.free(r3.value.ok.onOff);
    try testing.expectEqualDeep(LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 }, r3.value.ok);
}

test "vec2dStyleUnionParser" {
    const fa = testing.failing_allocator;

    const r1 = try vec2dStyleUnionParser.parse(fa, "lw:10");
    try testing.expectEqual(Vec2dStylesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, r1.value.ok);

    const r2 = try vec2dStyleUnionParser.parse(fa, "lw  :  10");
    try testing.expectEqual(Vec2dStylesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, r2.value.ok);

    const r3 = try vec2dStyleUnionParser.parse(fa, "lwG  :  6");
    try testing.expectEqual(Vec2dStylesUnion{ .lineWidth = .{ .reference = .global, .value = 6 } }, r3.value.ok);

    const r4 = try vec2dStyleUnionParser.parse(fa, "lc:green");
    try testing.expectEqual(Vec2dStylesUnion{ .lineColor = .{ .value = .green } }, r4.value.ok);

    const r5 = try vec2dStyleUnionParser.parse(fa, "lc :  green");
    try testing.expectEqual(Vec2dStylesUnion{ .lineColor = .{ .value = .green } }, r5.value.ok);

    const r6 = try vec2dStyleUnionParser.parse(fa, "lc : yellow");
    try testing.expectEqual(Vec2dStylesUnion{ .lineColor = .{ .value = .yellow } }, r6.value.ok);

    const r7 = try vec2dStyleUnionParser.parse(fa, "lo:10");
    try testing.expectEqual(Vec2dStylesUnion{ .lineOpacity = .{ .value = 10 } }, r7.value.ok);

    const r8 = try vec2dStyleUnionParser.parse(fa, "lo  :  10");
    try testing.expectEqual(Vec2dStylesUnion{ .lineOpacity = .{ .value = 10 } }, r8.value.ok);

    const r9 = try vec2dStyleUnionParser.parse(fa, "lo  :  6");
    try testing.expectEqual(Vec2dStylesUnion{ .lineOpacity = .{ .value = 6 } }, r9.value.ok);

    const r10 = try vec2dStyleUnionParser.parse(fa, "le: n");
    try testing.expectEqual(Vec2dStylesUnion{ .lineCap = .{ .value = .none } }, r10.value.ok);

    const r11 = try vec2dStyleUnionParser.parse(fa, "le  :  none");
    try testing.expectEqual(Vec2dStylesUnion{ .lineCap = .{ .value = .none } }, r11.value.ok);

    const r12 = try vec2dStyleUnionParser.parse(fa, "le  :  b");
    try testing.expectEqual(Vec2dStylesUnion{ .lineCap = .{ .value = .butt } }, r12.value.ok);

    const r13 = try vec2dStyleUnionParser.parse(fa, "lj: n");
    try testing.expectEqual(Vec2dStylesUnion{ .lineJoin = .{ .value = .none } }, r13.value.ok);

    const r14 = try vec2dStyleUnionParser.parse(fa, "lj  :  none");
    try testing.expectEqual(Vec2dStylesUnion{ .lineJoin = .{ .value = .none } }, r14.value.ok);

    const r15 = try vec2dStyleUnionParser.parse(fa, "lj  :  b");
    try testing.expectEqual(Vec2dStylesUnion{ .lineJoin = .{ .value = .bevel } }, r15.value.ok);

    const a = testing.allocator;

    const r16 = try vec2dStyleUnionParser.parse(a, "ld: [2 , 3] 1");
    defer a.free(r16.value.ok.lineDashing.onOff);
    try testing.expectEqualDeep(Vec2dStylesUnion{ .lineDashing = .{ .reference = .normalized, .onOff = &[2]u16{ 2, 3 }, .offset = 1 } }, r16.value.ok);

    const r17 = try vec2dStyleUnionParser.parse(a, "ld  :  [2   ,    3]    1");
    defer a.free(r17.value.ok.lineDashing.onOff);
    try testing.expectEqualDeep(Vec2dStylesUnion{ .lineDashing = .{ .reference = .normalized, .onOff = &[_]u16{ 2, 3 }, .offset = 1 } }, r17.value.ok);

    const r18 = try vec2dStyleUnionParser.parse(a, "ldG  :  [ 2,3,10] 0");
    defer a.free(r18.value.ok.lineDashing.onOff);
    try testing.expectEqualDeep(Vec2dStylesUnion{ .lineDashing = .{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 } }, r18.value.ok);
}

test "many_vec2dStyleUnionParser" {
    const a = testing.allocator;

    const r1 = try many_vec2dStyleUnionParser.parse(a, "lw:10");
    defer a.free(r1.value.ok);
    try testing.expectEqualDeep(&[1]Vec2dStylesUnion{Vec2dStylesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }}, r1.value.ok);

    const r2 = try many_vec2dStyleUnionParser.parse(a, "lo  :  6");
    defer a.free(r2.value.ok);
    try testing.expectEqualDeep(&[1]Vec2dStylesUnion{Vec2dStylesUnion{ .lineOpacity = .{ .value = 6 } }}, r2.value.ok);

    const r3 = try many_vec2dStyleUnionParser.parse(a, "lw:10 , lo  :  6");
    defer a.free(r3.value.ok);
    try testing.expectEqualDeep(&[2]Vec2dStylesUnion{ Vec2dStylesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, Vec2dStylesUnion{ .lineOpacity = .{ .value = 6 } } }, r3.value.ok);

    const r4 = try many_vec2dStyleUnionParser.parse(a, "ldG  :  [ 2,3,10] 0");
    const r4_dashing = r4.value.ok[0];
    defer a.free(r4_dashing.lineDashing.onOff);
    defer a.free(r4.value.ok);
    try testing.expectEqualDeep(&[1]Vec2dStylesUnion{Vec2dStylesUnion{ .lineDashing = .{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 } }}, r4.value.ok);

    const r5 = try many_vec2dStyleUnionParser.parse(a, "lw:10 ,ldG  :  [ 2,3,10] 0, lo  :  6");
    const r5_dashing = r5.value.ok[1];
    defer a.free(r5_dashing.lineDashing.onOff);
    defer a.free(r5.value.ok);
    try testing.expectEqualDeep(&[3]Vec2dStylesUnion{ Vec2dStylesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, Vec2dStylesUnion{ .lineDashing = .{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 } }, Vec2dStylesUnion{ .lineOpacity = .{ .value = 6 } } }, r5.value.ok);
}

test "vec2dStylesParser" {
    const a = testing.allocator;

    const r1 = try vec2dStylesParser.parse(a, "lw:10");
    const styles1 = Vec2dStyles{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = .defaultLineOpacityType(),
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = .defaultLineDashingType(),
    };
    try testing.expectEqual(styles1, r1.value.ok);

    const r2 = try vec2dStylesParser.parse(a, "lw:10, lo  :  6");
    const styles2 = Vec2dStyles{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = .defaultLineDashingType(),
    };
    try testing.expectEqual(styles2, r2.value.ok);

    const r3 = try vec2dStylesParser.parse(a, "ldG  :  [ 2,3,10] 0,lw:10, lo  :  6");
    const styles3 = Vec2dStyles{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 },
    };
    defer a.free(r3.value.ok.lineDashing.onOff);
    try testing.expectEqualDeep(styles3, r3.value.ok);
}
