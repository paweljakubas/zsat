const std = @import("std");
const testing = std.testing;

const mecha = @import("mecha");
const common = @import("common.zig");

// style
pub const StyleType = enum {
    vec2d,
    //Point2D,

    pub fn defaultStyleType() StyleType {
        return .vec2d;
    }
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

pub const Style = struct {
    styleNumber: u8,
    styleValue: StyleValue,
};

pub const StyleValue = struct {
    styleType: ?StyleType = .defaultStyleType(),
    coordinateSystem: ?CoordinateType = .defaultCoordinateType(),
    coordinateOrientation: ?CoordinateOrientation = .defaultCoordinateOrientation(),
    attributes: ?Vec2dAttributes = Vec2dAttributes{},
};

const StyleValueUnion = union(enum) {
    styleType: StyleType,
    coordinateSystem: CoordinateType,
    coordinateOrientation: CoordinateOrientation,
    attributes: Vec2dAttributes,
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

    pub fn defaultLineWidthType() LineWidthType {
        return LineWidthType{
            .reference = .normalized,
            .value = 20,
        };
    }
};

pub const LineColorType = struct {
    value: common.ColorName,

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

pub const Vec2dAttributes = struct {
    lineWidth: LineWidthType = .defaultLineWidthType(),
    lineColor: LineColorType = .defaultLineColorType(),
    lineOpacity: LineOpacityType = .defaultLineOpacityType(),
    lineCap: LineCapType = .defaultLineCapType(),
    lineJoin: LineJoinType = .defaultLineJoinType(),
    lineDashing: ?LineDashingType = null,
};

const Vec2dAttributesUnion = union(enum) {
    lineWidth: LineWidthType,
    lineColor: LineColorType,
    lineOpacity: LineOpacityType,
    lineCap: LineCapType,
    lineJoin: LineJoinType,
    lineDashing: ?LineDashingType,
};

//Parsers
const skipOpenRecBracket =
    mecha.combine(.{ common.skipWhitespace, mecha.ascii.char('[').discard() });
const skipCloseRecBracket =
    mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(']').discard(), common.skipWhitespace });

const styleNumberParserRaw =
    mecha.combine(.{ common.skipWhitespace, mecha.ascii.char('e').discard(), mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 }).asStr().convert(mecha.toInt(u8, 10)) });

test "styleNumber" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try styleNumberParserRaw.parse(a, "e2");
    try testing.expectEqual(2, r1.value.ok);

    const r2 = try styleNumberParserRaw.parse(a, " e0");
    try testing.expectEqual(0, r2.value.ok);

    const r3 = try styleNumberParserRaw.parse(a, " e11");
    try testing.expectEqual(11, r3.value.ok);

    const r4 = try styleNumberParserRaw.parse(a, "11");
    try testing.expectEqual(0, r4.index);
}

const styleTypeParserRaw =
    mecha.combine(.{ common.skipWhitespace, mecha.convert(mecha.string("vec2d").asStr(), mecha.toEnum(StyleType)) });
const styleTypeParserRawP = @TypeOf(styleTypeParserRaw);
fn toElementTypeUnion(_: std.mem.Allocator, res: styleTypeParserRawP.T) mecha.ConvertError!StyleValueUnion {
    return StyleValueUnion{ .styleType = res };
}
const styleTypeUnionParser = styleTypeParserRaw.convert(toElementTypeUnion);

test "styleType" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try styleTypeParserRaw.parse(a, "vec2d");
    try testing.expectEqual(.vec2d, r1.value.ok);

    const r2 = try styleTypeParserRaw.parse(a, " vec2d");
    try testing.expectEqual(.vec2d, r2.value.ok);

    const r3 = try styleTypeParserRaw.parse(a, "dot");
    try testing.expectEqual(0, r3.index);
}

test "styleTypeUnion" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try styleTypeUnionParser.parse(a, "vec2d");
    try testing.expectEqual(StyleValueUnion{ .styleType = .vec2d }, r1.value.ok);

    const r2 = try styleTypeUnionParser.parse(a, " vec2d");
    try testing.expectEqual(StyleValueUnion{ .styleType = .vec2d }, r2.value.ok);
}

const coordinateTypeParserRaw =
    mecha.combine(.{ common.skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("xy"), mecha.string("polar") }).asStr(), mecha.toEnum(CoordinateType)) });
const coordinateTypeParserRawP = @TypeOf(coordinateTypeParserRaw);
fn toCoordinateTypeUnion(_: std.mem.Allocator, res: coordinateTypeParserRawP.T) mecha.ConvertError!StyleValueUnion {
    return StyleValueUnion{ .coordinateSystem = res };
}
const coordinateTypeUnionParser = coordinateTypeParserRaw.convert(toCoordinateTypeUnion);

test "coordinateType" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try coordinateTypeParserRaw.parse(a, "xy");
    try testing.expectEqual(.xy, r1.value.ok);

    const r2 = try coordinateTypeParserRaw.parse(a, " xy");
    try testing.expectEqual(.xy, r2.value.ok);

    const r3 = try coordinateTypeParserRaw.parse(a, "polar");
    try testing.expectEqual(.polar, r3.value.ok);

    const r4 = try coordinateTypeParserRaw.parse(a, "rad");
    try testing.expectEqual(0, r4.index);
}

test "coordinateTypeUnion" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try coordinateTypeUnionParser.parse(a, "xy");
    try testing.expectEqual(StyleValueUnion{ .coordinateSystem = .xy }, r1.value.ok);

    const r2 = try coordinateTypeUnionParser.parse(a, " xy");
    try testing.expectEqual(StyleValueUnion{ .coordinateSystem = .xy }, r2.value.ok);

    const r3 = try coordinateTypeUnionParser.parse(a, "polar");
    try testing.expectEqual(StyleValueUnion{ .coordinateSystem = .polar }, r3.value.ok);
}

const coordinateOrientationParserRaw =
    mecha.combine(.{ common.skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("fixed"), mecha.string("adjusting") }).asStr(), mecha.toEnum(CoordinateOrientation)) });
const coordinateOrientationParserRawP = @TypeOf(coordinateOrientationParserRaw);
fn toCoordinateOrientationUnion(_: std.mem.Allocator, res: coordinateOrientationParserRawP.T) mecha.ConvertError!StyleValueUnion {
    return StyleValueUnion{ .coordinateOrientation = res };
}
const coordinateOrientationUnionParser = coordinateOrientationParserRaw.convert(toCoordinateOrientationUnion);

test "coordinateOrientationParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try coordinateOrientationParserRaw.parse(a, "fixed");
    try testing.expectEqual(.fixed, r1.value.ok);

    const r2 = try coordinateOrientationParserRaw.parse(a, " fixed");
    try testing.expectEqual(.fixed, r2.value.ok);

    const r3 = try coordinateOrientationParserRaw.parse(a, " adjusting");
    try testing.expectEqual(.adjusting, r3.value.ok);

    const r4 = try coordinateOrientationParserRaw.parse(a, "var");
    try testing.expectEqual(0, r4.index);
}

test "coordinateOrientationUnionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try coordinateOrientationUnionParser.parse(a, "fixed");
    try testing.expectEqual(StyleValueUnion{ .coordinateOrientation = .fixed }, r1.value.ok);

    const r2 = try coordinateOrientationUnionParser.parse(a, " fixed");
    try testing.expectEqual(StyleValueUnion{ .coordinateOrientation = .fixed }, r2.value.ok);

    const r3 = try coordinateOrientationUnionParser.parse(a, " adjusting");
    try testing.expectEqual(StyleValueUnion{ .coordinateOrientation = .adjusting }, r3.value.ok);
}

//LineWidth parser
const lineWidthTypeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("lwL"), mecha.string("lwG"), mecha.string("lwN"), mecha.string("lwO"), mecha.string("lw") }), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.int(u16, .{}) });
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
fn toLineWidthUnion(_: std.mem.Allocator, res: lineWidthTypeParserRawP.T) mecha.ConvertError!Vec2dAttributesUnion {
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
        return Vec2dAttributesUnion{ .lineWidth = .{
            .reference = switchRes,
            .value = res[1],
        } };
    } else {
        return error.ConversionFailed;
    }
}
const lineWidthUnionParser = lineWidthTypeParserRaw.convert(toLineWidthUnion);

test "LineWidthTypeParserRaw" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const Parser = @TypeOf(lineWidthTypeParserRaw);

    const r1 = try lineWidthTypeParserRaw.parse(a, "lw:10");
    try testing.expectEqual(Parser.T{ "lw", 10 }, r1.value.ok);

    const r2 = try lineWidthTypeParserRaw.asStr().parse(a, "lw  :  10");
    try testing.expectEqualStrings("lw  :  10", r2.value.ok);

    const r3 = try lineWidthTypeParserRaw.parse(a, "lwL  :  10");
    try testing.expectEqual(Parser.T{ "lwL", 10 }, r3.value.ok);
}

test "LineWidthTypeParserTyped" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineWidthTypeParserTyped.parse(a, "lw:10");
    try testing.expectEqual(LineWidthType{ .reference = .normalized, .value = 10 }, r1.value.ok);

    const r2 = try lineWidthTypeParserTyped.parse(a, "lw  :  10");
    try testing.expectEqual(LineWidthType{ .reference = .normalized, .value = 10 }, r2.value.ok);

    const r3 = try lineWidthTypeParserTyped.parse(a, "lwG  :  6");
    try testing.expectEqual(LineWidthType{ .reference = .global, .value = 6 }, r3.value.ok);
}

//LineColor parser
const lineColorTypeParserRaw =
    mecha.combine(.{ mecha.string("lc").discard(), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, common.colorNameParserTyped });
const lineColorTypeParserRawP = @TypeOf(lineColorTypeParserRaw);
fn toLineColorType(_: std.mem.Allocator, res: lineColorTypeParserRawP.T) mecha.ConvertError!LineColorType {
    return .{ .value = res };
}
const lineColorTypeParserTyped = lineColorTypeParserRaw.convert(toLineColorType);
fn toLineColorUnion(_: std.mem.Allocator, res: lineColorTypeParserRawP.T) mecha.ConvertError!Vec2dAttributesUnion {
    return Vec2dAttributesUnion{ .lineColor = .{ .value = res } };
}
const lineColorUnionParser = lineColorTypeParserRaw.convert(toLineColorUnion);

test "LineWColorTypeParserTyped" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineColorTypeParserTyped.parse(a, "lc:green");
    try testing.expectEqual(LineColorType{ .value = .green }, r1.value.ok);

    const r2 = try lineColorTypeParserTyped.parse(a, "lc :  green");
    try testing.expectEqual(LineColorType{ .value = .green }, r2.value.ok);

    const r3 = try lineColorTypeParserTyped.parse(a, "lc : yellow");
    try testing.expectEqual(LineColorType{ .value = .yellow }, r3.value.ok);
}

//LineOpacity parser
const lineOpacityTypeParserRaw =
    mecha.combine(.{ mecha.string("lo").discard(), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.int(u8, .{}) });
const lineOpacityTypeParserRawP = @TypeOf(lineOpacityTypeParserRaw);
fn toLineOpacityType(_: std.mem.Allocator, res: lineOpacityTypeParserRawP.T) mecha.ConvertError!LineOpacityType {
    return .{ .value = res };
}
const lineOpacityTypeParserTyped = lineOpacityTypeParserRaw.convert(toLineOpacityType);
fn toLineOpacityUnion(_: std.mem.Allocator, res: lineOpacityTypeParserRawP.T) mecha.ConvertError!Vec2dAttributesUnion {
    return Vec2dAttributesUnion{ .lineOpacity = .{ .value = res } };
}
const lineOpacityUnionParser = lineOpacityTypeParserRaw.convert(toLineOpacityUnion);

test "LineOpacityTypeParserTyped" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineOpacityTypeParserTyped.parse(a, "lo:10");
    try testing.expectEqual(LineOpacityType{ .value = 10 }, r1.value.ok);

    const r2 = try lineOpacityTypeParserTyped.parse(a, "lo  :  10");
    try testing.expectEqual(LineOpacityType{ .value = 10 }, r2.value.ok);

    const r3 = try lineOpacityTypeParserTyped.parse(a, "lo  :  6");
    try testing.expectEqual(LineOpacityType{ .value = 6 }, r3.value.ok);
}

//LineCap parser
const lineCapTypeParserRaw =
    mecha.combine(.{ mecha.string("le").discard(), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.oneOf(.{ mecha.string("none"), mecha.string("n"), mecha.string("butt"), mecha.string("b"), mecha.string("round"), mecha.string("r"), mecha.string("square"), mecha.string("s") }) });
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
fn toLineCapUnion(_: std.mem.Allocator, res: lineCapTypeParserRawP.T) mecha.ConvertError!Vec2dAttributesUnion {
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
        return Vec2dAttributesUnion{ .lineCap = .{
            .value = switchRes,
        } };
    } else {
        return error.ConversionFailed;
    }
}
const lineCapUnionParser = lineCapTypeParserRaw.convert(toLineCapUnion);

test "LineCapTypeParserTyped" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineCapTypeParserTyped.parse(a, "le: n");
    try testing.expectEqual(LineCapType{ .value = .none }, r1.value.ok);

    const r2 = try lineCapTypeParserTyped.parse(a, "le  :  none");
    try testing.expectEqual(LineCapType{ .value = .none }, r2.value.ok);

    const r3 = try lineCapTypeParserTyped.parse(a, "le  :  b");
    try testing.expectEqual(LineCapType{ .value = .butt }, r3.value.ok);
}

//LineJoin parser
const lineJoinTypeParserRaw =
    mecha.combine(.{ mecha.string("lj").discard(), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.oneOf(.{ mecha.string("none"), mecha.string("n"), mecha.string("mitter"), mecha.string("m"), mecha.string("round"), mecha.string("r"), mecha.string("bevel"), mecha.string("b") }) });
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
fn toLineJoinUnion(_: std.mem.Allocator, res: lineJoinTypeParserRawP.T) mecha.ConvertError!Vec2dAttributesUnion {
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
        return Vec2dAttributesUnion{ .lineJoin = .{
            .value = switchRes,
        } };
    } else {
        return error.ConversionFailed;
    }
}
const lineJoinUnionParser = lineJoinTypeParserRaw.convert(toLineJoinUnion);

test "LineJoinTypeParserTyped" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineJoinTypeParserTyped.parse(a, "lj: n");
    try testing.expectEqual(LineJoinType{ .value = .none }, r1.value.ok);

    const r2 = try lineJoinTypeParserTyped.parse(a, "lj  :  none");
    try testing.expectEqual(LineJoinType{ .value = .none }, r2.value.ok);

    const r3 = try lineJoinTypeParserTyped.parse(a, "lj  :  b");
    try testing.expectEqual(LineJoinType{ .value = .bevel }, r3.value.ok);
}

//LineDashing parser
const lineDashingTypeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("ldL"), mecha.string("ldG"), mecha.string("ldN"), mecha.string("ldO"), mecha.string("ld") }), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.string("[").discard(), common.skipWhitespace, mecha.int(u16, .{}).many(.{ .collect = true, .min = 2, .separator = mecha.combine(.{ common.skipWhitespace, mecha.string(","), common.skipWhitespace }).discard() }), common.skipWhitespace, mecha.string("]").discard(), common.skipWhitespace, mecha.opt(mecha.int(u16, .{})) });
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
        const reference: ReferenceFrame = switch (validT) {
            .ld => .output,
            .ldL => .local,
            .ldG => .global,
            .ldN => .normalized,
            .ldO => .output,
        };
        return .{
            .reference = reference,
            .onOff = res[1],
            .offset = res[2] orelse 0,
        };
    } else {
        return error.ConversionFailed;
    }
}
const lineDashingTypeParserTyped = lineDashingTypeParserRaw.convert(toLineDashingType);
fn toLineDashingUnion(_: std.mem.Allocator, res: lineDashingTypeParserRawP.T) mecha.ConvertError!Vec2dAttributesUnion {
    const to = struct {
        fn to(str: []const u8) ?LineDashingT {
            return std.meta.stringToEnum(LineDashingT, str);
        }
    }.to;
    if (to(res[0])) |validT| {
        const reference: ReferenceFrame = switch (validT) {
            .ld => .output,
            .ldL => .local,
            .ldG => .global,
            .ldN => .normalized,
            .ldO => .output,
        };
        return Vec2dAttributesUnion{ .lineDashing = .{
            .reference = reference,
            .onOff = res[1],
            .offset = res[2] orelse 0,
        } };
    } else {
        return error.ConversionFailed;
    }
}
const lineDashingUnionParser = lineDashingTypeParserRaw.convert(toLineDashingUnion);

const lineDashingNullParserRaw = mecha.combine(.{
    mecha.string("ld"),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.oneOf(.{ mecha.string("null"), mecha.string("none") }),
});
const lineDashingNullParser = lineDashingNullParserRaw.convert(struct {
    fn toNull(_: std.mem.Allocator, _: anytype) mecha.ConvertError!Vec2dAttributesUnion {
        return Vec2dAttributesUnion{ .lineDashing = null };
    }
}.toNull);

test "LineDashingTypeParserTyped" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineDashingTypeParserTyped.parse(a, "ld: [2 , 3] 1");
    try testing.expectEqualDeep(LineDashingType{ .reference = .output, .onOff = &[2]u16{ 2, 3 }, .offset = 1 }, r1.value.ok);

    const r2 = try lineDashingTypeParserTyped.parse(a, "ld  :  [2   ,    3]    1");
    try testing.expectEqualDeep(LineDashingType{ .reference = .output, .onOff = &[_]u16{ 2, 3 }, .offset = 1 }, r2.value.ok);

    const r3 = try lineDashingTypeParserTyped.parse(a, "ldG  :  [ 2,3,10] 0");
    try testing.expectEqualDeep(LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 }, r3.value.ok);
}

//Vec2dAttributes parser
const vec2dAttributeUnionParser = mecha.oneOf(.{
    lineWidthUnionParser,
    lineColorUnionParser,
    lineOpacityUnionParser,
    lineCapUnionParser,
    lineJoinUnionParser,
    lineDashingNullParser,
    lineDashingUnionParser,
});

test "vec2dAttributeUnionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try vec2dAttributeUnionParser.parse(a, "lw:10");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, r1.value.ok);

    const r2 = try vec2dAttributeUnionParser.parse(a, "lw  :  10");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, r2.value.ok);

    const r3 = try vec2dAttributeUnionParser.parse(a, "lwG  :  6");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineWidth = .{ .reference = .global, .value = 6 } }, r3.value.ok);

    const r4 = try vec2dAttributeUnionParser.parse(a, "lc:green");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineColor = .{ .value = .green } }, r4.value.ok);

    const r5 = try vec2dAttributeUnionParser.parse(a, "lc :  green");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineColor = .{ .value = .green } }, r5.value.ok);

    const r6 = try vec2dAttributeUnionParser.parse(a, "lc : yellow");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineColor = .{ .value = .yellow } }, r6.value.ok);

    const r7 = try vec2dAttributeUnionParser.parse(a, "lo:10");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineOpacity = .{ .value = 10 } }, r7.value.ok);

    const r8 = try vec2dAttributeUnionParser.parse(a, "lo  :  10");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineOpacity = .{ .value = 10 } }, r8.value.ok);

    const r9 = try vec2dAttributeUnionParser.parse(a, "lo  :  6");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineOpacity = .{ .value = 6 } }, r9.value.ok);

    const r10 = try vec2dAttributeUnionParser.parse(a, "le: n");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineCap = .{ .value = .none } }, r10.value.ok);

    const r11 = try vec2dAttributeUnionParser.parse(a, "le  :  none");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineCap = .{ .value = .none } }, r11.value.ok);

    const r12 = try vec2dAttributeUnionParser.parse(a, "le  :  b");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineCap = .{ .value = .butt } }, r12.value.ok);

    const r13 = try vec2dAttributeUnionParser.parse(a, "lj: n");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineJoin = .{ .value = .none } }, r13.value.ok);

    const r14 = try vec2dAttributeUnionParser.parse(a, "lj  :  none");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineJoin = .{ .value = .none } }, r14.value.ok);

    const r15 = try vec2dAttributeUnionParser.parse(a, "lj  :  b");
    try testing.expectEqual(Vec2dAttributesUnion{ .lineJoin = .{ .value = .bevel } }, r15.value.ok);

    const r16 = try vec2dAttributeUnionParser.parse(a, "ld: [2 , 3] 1");
    try testing.expectEqualDeep(Vec2dAttributesUnion{ .lineDashing = .{ .reference = .output, .onOff = &[2]u16{ 2, 3 }, .offset = 1 } }, r16.value.ok);

    const r17 = try vec2dAttributeUnionParser.parse(a, "ld  :  [2   ,    3]    1");
    try testing.expectEqualDeep(Vec2dAttributesUnion{ .lineDashing = .{ .reference = .output, .onOff = &[_]u16{ 2, 3 }, .offset = 1 } }, r17.value.ok);

    const r18 = try vec2dAttributeUnionParser.parse(a, "ldG  :  [ 2,3,10] 0");
    try testing.expectEqualDeep(Vec2dAttributesUnion{ .lineDashing = .{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 } }, r18.value.ok);
}

const vec2dAttributeSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
const many_vec2dAttributeUnionParser = mecha.many(vec2dAttributeUnionParser, .{ .separator = vec2dAttributeSeparatorParser });
fn manyToVec2dAttributes(arena: std.mem.Allocator, fields: []Vec2dAttributesUnion) mecha.ConvertError!Vec2dAttributes {
    var res = Vec2dAttributes{};
    for (fields) |field| switch (field) {
        .lineWidth => |f| res.lineWidth = f,
        .lineColor => |f| res.lineColor = f,
        .lineOpacity => |f| res.lineOpacity = f,
        .lineCap => |f| res.lineCap = f,
        .lineJoin => |f| res.lineJoin = f,
        .lineDashing => |f| res.lineDashing = f,
    };

    arena.free(fields);
    return res;
}
const vec2dAttributesParser = many_vec2dAttributeUnionParser.convert(manyToVec2dAttributes);
const vec2dAttributesParserBracketed = mecha.combine(.{ skipOpenRecBracket, vec2dAttributesParser, skipCloseRecBracket });
const vec2dAttributesParserBracketedP = @TypeOf(vec2dAttributesParserBracketed);
fn toVec2dAttributesParserBracketedUnion(_: std.mem.Allocator, res: vec2dAttributesParserBracketedP.T) mecha.ConvertError!StyleValueUnion {
    return StyleValueUnion{ .attributes = res };
}
const vec2dAttributesParserBracketedUnion = vec2dAttributesParserBracketed.convert(toVec2dAttributesParserBracketedUnion);

test "many_vec2dAttributeUnionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try many_vec2dAttributeUnionParser.parse(a, "lw:10");
    try testing.expectEqualDeep(&[1]Vec2dAttributesUnion{Vec2dAttributesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }}, r1.value.ok);

    const r2 = try many_vec2dAttributeUnionParser.parse(a, "lo  :  6");
    try testing.expectEqualDeep(&[1]Vec2dAttributesUnion{Vec2dAttributesUnion{ .lineOpacity = .{ .value = 6 } }}, r2.value.ok);

    const r3 = try many_vec2dAttributeUnionParser.parse(a, "lw:10 , lo  :  6");
    try testing.expectEqualDeep(&[2]Vec2dAttributesUnion{ Vec2dAttributesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, Vec2dAttributesUnion{ .lineOpacity = .{ .value = 6 } } }, r3.value.ok);

    const r4 = try many_vec2dAttributeUnionParser.parse(a, "ldG  :  [ 2,3,10] 0");
    try testing.expectEqualDeep(&[1]Vec2dAttributesUnion{Vec2dAttributesUnion{ .lineDashing = .{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 } }}, r4.value.ok);

    const r5 = try many_vec2dAttributeUnionParser.parse(a, "lw:10 ,ldG  :  [ 2,3,10] 0, lo  :  6");
    try testing.expectEqualDeep(&[3]Vec2dAttributesUnion{ Vec2dAttributesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, Vec2dAttributesUnion{ .lineDashing = .{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 } }, Vec2dAttributesUnion{ .lineOpacity = .{ .value = 6 } } }, r5.value.ok);
}

test "vec2dAttributesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try vec2dAttributesParser.parse(a, "lw:10");
    const styles1 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = .defaultLineOpacityType(),
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    try testing.expectEqual(styles1, r1.value.ok);

    const r2 = try vec2dAttributesParser.parse(a, "lw:10, lo  :  6");
    const styles2 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    try testing.expectEqual(styles2, r2.value.ok);

    const r3 = try vec2dAttributesParser.parse(a, "ldG  :  [ 2,3,10] 0,lw:10, lo  :  6");
    const styles3 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 },
    };
    try testing.expectEqualDeep(styles3, r3.value.ok);
}

test "vec2dAttributesParserUnion" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try vec2dAttributesParserBracketedUnion.parse(a, "[lw:10]");
    const styles1 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = .defaultLineOpacityType(),
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    const exp_value1 = StyleValueUnion{ .attributes = styles1 };
    try testing.expectEqual(exp_value1, r1.value.ok);

    const r2 = try vec2dAttributesParserBracketedUnion.parse(a, "[lw:10, lo  :  6]");
    const styles2 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    const exp_value2 = StyleValueUnion{ .attributes = styles2 };
    try testing.expectEqual(exp_value2, r2.value.ok);

    const r3 = try vec2dAttributesParserBracketedUnion.parse(a, "[ldG  :  [ 2,3,10] 0,lw:10, lo  :  6]");
    const styles3 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 },
    };
    const exp_value3 = StyleValueUnion{ .attributes = styles3 };
    try testing.expectEqualDeep(exp_value3, r3.value.ok);
}

//Style parser
const styleValueUnionParser = mecha.oneOf(.{
    styleTypeUnionParser,
    coordinateTypeUnionParser,
    coordinateOrientationUnionParser,
    vec2dAttributesParserBracketedUnion,
});
const many_styleValueUnionParser = mecha.many(styleValueUnionParser, .{ .separator = common.skipWhitespace });
fn manyToStyleValue(arena: std.mem.Allocator, fields: []StyleValueUnion) mecha.ConvertError!StyleValue {
    var res = StyleValue{};
    for (fields) |field| switch (field) {
        .styleType => |f| res.styleType = f,
        .coordinateSystem => |f| res.coordinateSystem = f,
        .coordinateOrientation => |f| res.coordinateOrientation = f,
        .attributes => |f| res.attributes = f,
    };

    arena.free(fields);
    return res;
}
const styleValueParser = many_styleValueUnionParser.convert(manyToStyleValue);

test "styleValueParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r0 = try styleValueParser.parse(a, "vec2d polar");
    const styles0 = Vec2dAttributes{
        .lineWidth = .defaultLineWidthType(),
        .lineColor = .defaultLineColorType(),
        .lineOpacity = .defaultLineOpacityType(),
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    const exp_value0 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
        .coordinateOrientation = .fixed,
        .attributes = styles0,
    };
    try testing.expectEqual(exp_value0, r0.value.ok);

    const r1 = try styleValueParser.parse(a, "[lw:10]");
    const styles1 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = .defaultLineOpacityType(),
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    const exp_value1 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .xy,
        .coordinateOrientation = .fixed,
        .attributes = styles1,
    };
    try testing.expectEqual(exp_value1, r1.value.ok);

    const r2 = try styleValueParser.parse(a, "vec2d  [lw:10, lo  :  6]");
    const styles2 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    const exp_value2 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .xy,
        .coordinateOrientation = .fixed,
        .attributes = styles2,
    };
    try testing.expectEqual(exp_value2, r2.value.ok);

    const r3 = try styleValueParser.parse(a, "vec2d polar [ldG  :  [ 2,3,10] 0,lw:10, lo  :  6]");
    const styles3 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 },
    };
    const exp_value3 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
        .coordinateOrientation = .fixed,
        .attributes = styles3,
    };
    try testing.expectEqualDeep(exp_value3, r3.value.ok);
}

pub const styleParser =
    mecha.combine(.{ styleNumberParserRaw, common.skipOpenBraceColon, styleValueParser, common.skipCloseBrace }).map(mecha.toStruct(Style));

test "styleParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r0 = try styleParser.parse(a, "e0:{vec2d polar}");
    const styles0 = Vec2dAttributes{
        .lineWidth = .defaultLineWidthType(),
        .lineColor = .defaultLineColorType(),
        .lineOpacity = .defaultLineOpacityType(),
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    const exp_value0 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
        .coordinateOrientation = .fixed,
        .attributes = styles0,
    };
    const exp_element0 = Style{
        .styleNumber = 0,
        .styleValue = exp_value0,
    };
    try testing.expectEqual(exp_element0, r0.value.ok);

    const r1 = try styleParser.parse(a, "e8: {[lw:10]}");
    const styles1 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = .defaultLineOpacityType(),
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    const exp_value1 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .xy,
        .coordinateOrientation = .fixed,
        .attributes = styles1,
    };
    const exp_element1 = Style{
        .styleNumber = 8,
        .styleValue = exp_value1,
    };
    try testing.expectEqual(exp_element1, r1.value.ok);

    const r2 = try styleParser.parse(a, " e8: {  vec2d  [lw:10, lo  :  6]}");
    const styles2 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    const exp_value2 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .xy,
        .coordinateOrientation = .fixed,
        .attributes = styles2,
    };
    const exp_element2 = Style{
        .styleNumber = 8,
        .styleValue = exp_value2,
    };
    try testing.expectEqual(exp_element2, r2.value.ok);

    const r3 = try styleParser.parse(a, "e11: { vec2d polar [ldG  :  [ 2,3,10] 0,lw:10, lo  :  6]}");
    const styles3 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 },
    };
    const exp_value3 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
        .coordinateOrientation = .fixed,
        .attributes = styles3,
    };
    const exp_element3 = Style{
        .styleNumber = 11,
        .styleValue = exp_value3,
    };
    try testing.expectEqualDeep(exp_element3, r3.value.ok);
}

const styleSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
const stylesParserRaw = mecha.many(styleParser, .{ .collect = true, .separator = styleSeparatorParser });
const stylesParserRawP = @TypeOf(stylesParserRaw);
fn toStylesSlice(arena: std.mem.Allocator, raw: stylesParserRawP.T) mecha.ConvertError![]Style {
    const result = try arena.alloc(Style, raw.len);
    @memcpy(result, raw);
    arena.free(raw);
    return result;
}
pub const stylesParser = stylesParserRaw.convert(toStylesSlice);

test "stylesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r0 = try stylesParser.parse(a, "e0:{vec2d polar}, e8: {[lw:10]}");
    const styles0 = Vec2dAttributes{
        .lineWidth = .defaultLineWidthType(),
        .lineColor = .defaultLineColorType(),
        .lineOpacity = .defaultLineOpacityType(),
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    const exp_value0 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
        .coordinateOrientation = .fixed,
        .attributes = styles0,
    };
    const exp_element0 = Style{
        .styleNumber = 0,
        .styleValue = exp_value0,
    };

    const styles1 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = .defaultLineOpacityType(),
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    const exp_value1 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .xy,
        .coordinateOrientation = .fixed,
        .attributes = styles1,
    };
    const exp_element1 = Style{
        .styleNumber = 8,
        .styleValue = exp_value1,
    };
    const exp_styles0 = [2]Style{ exp_element0, exp_element1 };
    try testing.expectEqualDeep(&exp_styles0, r0.value.ok);

    const r1 = try stylesParser.parse(a, " e8: {  vec2d  [lw:10, lo  :  6]}, e11: { vec2d polar [ldG  :  [ 2,3,10] 0,lw:10, lo  :  6]}");
    const styles2 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = null,
    };
    const exp_value2 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .xy,
        .coordinateOrientation = .fixed,
        .attributes = styles2,
    };
    const exp_element2 = Style{
        .styleNumber = 8,
        .styleValue = exp_value2,
    };

    const styles3 = Vec2dAttributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = .defaultLineColorType(),
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = .defaultLineCapType(),
        .lineJoin = .defaultLineJoinType(),
        .lineDashing = LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 },
    };
    const exp_value3 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
        .coordinateOrientation = .fixed,
        .attributes = styles3,
    };
    const exp_element3 = Style{
        .styleNumber = 11,
        .styleValue = exp_value3,
    };

    const exp_styles1 = [2]Style{ exp_element2, exp_element3 };
    try testing.expectEqualDeep(&exp_styles1, r1.value.ok);
}
