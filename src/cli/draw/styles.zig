const std = @import("std");
const testing = std.testing;

const mecha = @import("mecha");
const common = @import("common.zig");

// style
pub const StyleType = enum {
    vec2d,
    pt2d,

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
    fixed, //coordinate alays stays the same positioned in the space, following figure borders
    origin, //origin of the coordinate system will "move" to the end of the previous calculation
    coord, //origin will be the end of the previous calculation, and x axis will be along last element, y axis will be perpendicular and crossing new origin

    pub fn defaultCoordinateOrientation() CoordinateOrientation {
        return .fixed;
    }
};

// plot the last results or intermediate steps also (think about functional scan)
pub const PlotSteps = enum {
    last, //the last step oly is plotted, ie., after the last operation
    all, //each step is plotted, ie., after every step

    pub fn defaultPlotSteps() PlotSteps {
        return .last;
    }
};

pub const Style = struct {
    styleNumber: u8,
    styleValue: StyleValue,
    name: ?[]const u8 = null,
};

pub const StyleValue = struct {
    styleType: ?StyleType = null,
    coordinateSystem: ?CoordinateType = null,
    coordinateOrientation: ?CoordinateOrientation = null,
    plotSteps: ?PlotSteps = null,
    attributes: ?Attributes = null,
    baseStyle: ?u8 = null,
};

const StyleValueUnion = union(enum) {
    styleType: StyleType,
    coordinateSystem: CoordinateType,
    coordinateOrientation: CoordinateOrientation,
    plotSteps: PlotSteps,
    attributes: Attributes,
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
    onOff: []const u16, // dash segments: pixels for output, 0.1%/10 for local/global (10=1%), 0.1%/1000 for normalized (10=1%)
    offset: i16, // dash offset from path origin: pixels for output, same units as onOff for others

    pub fn defaultLineDashingType() LineDashingType {
        return LineDashingType{
            .reference = .normalized,
            .onOff = &[2]u16{ 10, 10 },
            .offset = 0,
        };
    }
};

pub const Attributes = struct {
    lineWidth: ?LineWidthType = null,
    lineColor: ?LineColorType = null,
    lineOpacity: ?LineOpacityType = null,
    lineCap: ?LineCapType = null,
    lineJoin: ?LineJoinType = null,
    lineDashing: ?LineDashingType = null,
    pointShape: ?PointShapeType = null,
    pointSize: ?PointSizeType = null,
};

pub const PointShape = enum {
    circle,
    square,
};

pub const PointShapeType = struct {
    value: PointShape,

    pub fn defaultPointShapeType() PointShapeType {
        return PointShapeType{ .value = .circle };
    }
};

pub const PointSizeType = struct {
    value: u16, // diameter/side length in pixels

    pub fn defaultPointSizeType() PointSizeType {
        return PointSizeType{ .value = 10 };
    }
};

fn attributesEmpty(a: Attributes) bool {
    return a.lineWidth == null and a.lineColor == null and a.lineOpacity == null and
        a.lineCap == null and a.lineJoin == null and a.lineDashing == null and
        a.pointShape == null and a.pointSize == null;
}

const AttributesUnion = union(enum) {
    lineWidth: LineWidthType,
    lineColor: LineColorType,
    lineOpacity: LineOpacityType,
    lineCap: LineCapType,
    lineJoin: LineJoinType,
    lineDashing: ?LineDashingType,
    pointShape: PointShapeType,
    pointSize: PointSizeType,
};

//Parsers
const skipOpenRecBracket =
    mecha.combine(.{ common.skipWhitespace, mecha.ascii.char('[').discard() });
const skipCloseRecBracket =
    mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(']').discard(), common.skipWhitespace });

const styleNumberParserRaw =
    mecha.combine(.{ common.skipWhitespace, mecha.ascii.char('e').discard(), mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 }).asStr().convert(mecha.toInt(u8, 10)) });
const styleNumberParserRawP = @TypeOf(styleNumberParserRaw);

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
    mecha.combine(.{ common.skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("pt2d"), mecha.string("vec2d") }).asStr(), mecha.toEnum(StyleType)) });
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

    const r3 = try styleTypeParserRaw.parse(a, "pt2d");
    try testing.expectEqual(.pt2d, r3.value.ok);

    const r4 = try styleTypeParserRaw.parse(a, "dot");
    try testing.expectEqual(0, r4.index);
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
    mecha.combine(.{ common.skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("fixed"), mecha.string("origin"), mecha.string("coord") }).asStr(), mecha.toEnum(CoordinateOrientation)) });
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

    const r3 = try coordinateOrientationParserRaw.parse(a, " origin");
    try testing.expectEqual(.origin, r3.value.ok);

    const r4 = try coordinateOrientationParserRaw.parse(a, " coord");
    try testing.expectEqual(.coord, r4.value.ok);

    const r5 = try coordinateOrientationParserRaw.parse(a, "var");
    try testing.expectEqual(0, r5.index);
}

test "coordinateOrientationUnionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try coordinateOrientationUnionParser.parse(a, "fixed");
    try testing.expectEqual(StyleValueUnion{ .coordinateOrientation = .fixed }, r1.value.ok);

    const r2 = try coordinateOrientationUnionParser.parse(a, " fixed");
    try testing.expectEqual(StyleValueUnion{ .coordinateOrientation = .fixed }, r2.value.ok);

    const r3 = try coordinateOrientationUnionParser.parse(a, " origin");
    try testing.expectEqual(StyleValueUnion{ .coordinateOrientation = .origin }, r3.value.ok);
}

const plotStepsParserRaw =
    mecha.combine(.{ common.skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("last"), mecha.string("all") }).asStr(), mecha.toEnum(PlotSteps)) });
const plotStepsParserRawP = @TypeOf(plotStepsParserRaw);
fn toPlotStepsUnion(_: std.mem.Allocator, res: plotStepsParserRawP.T) mecha.ConvertError!StyleValueUnion {
    return StyleValueUnion{ .plotSteps = res };
}
const plotStepsUnionParser = plotStepsParserRaw.convert(toPlotStepsUnion);

test "plotStepsParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try plotStepsParserRaw.parse(a, "last");
    try testing.expectEqual(.last, r1.value.ok);

    const r2 = try plotStepsParserRaw.parse(a, " last");
    try testing.expectEqual(.last, r2.value.ok);

    const r3 = try plotStepsParserRaw.parse(a, " all");
    try testing.expectEqual(.all, r3.value.ok);

    const r4 = try plotStepsParserRaw.parse(a, "var");
    try testing.expectEqual(0, r4.index);
}

test "plotStepsUnionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try plotStepsUnionParser.parse(a, "last");
    try testing.expectEqual(StyleValueUnion{ .plotSteps = .last }, r1.value.ok);

    const r2 = try plotStepsUnionParser.parse(a, " all");
    try testing.expectEqual(StyleValueUnion{ .plotSteps = .all }, r2.value.ok);
}

//LineWidth parser
const lineWidthTypeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("lineL"), mecha.string("lineG"), mecha.string("lineN"), mecha.string("lineO"), mecha.string("line"), mecha.string("lL"), mecha.string("lG"), mecha.string("lN"), mecha.string("lO"), mecha.string("l") }), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.int(u16, .{}) });
const lineWidthTypeParserRawP = @TypeOf(lineWidthTypeParserRaw);
const LineWidthT = enum {
    l,
    lL,
    lG,
    lN,
    lO,
    line,
    lineL,
    lineG,
    lineN,
    lineO,
};
fn toLineWidthType(_: std.mem.Allocator, res: lineWidthTypeParserRawP.T) mecha.ConvertError!LineWidthType {
    const to = struct {
        fn to(str: []const u8) ?LineWidthT {
            return std.meta.stringToEnum(LineWidthT, str);
        }
    }.to;
    if (to(res[0])) |validT| {
        const switchRes: ReferenceFrame = switch (validT) {
            .l, .line, .lN, .lineN => .normalized,
            .lL, .lineL => .local,
            .lG, .lineG => .global,
            .lO, .lineO => .output,
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
fn toLineWidthUnion(_: std.mem.Allocator, res: lineWidthTypeParserRawP.T) mecha.ConvertError!AttributesUnion {
    const to = struct {
        fn to(str: []const u8) ?LineWidthT {
            return std.meta.stringToEnum(LineWidthT, str);
        }
    }.to;
    if (to(res[0])) |validT| {
        const switchRes: ReferenceFrame = switch (validT) {
            .l, .line, .lN, .lineN => .normalized,
            .lL, .lineL => .local,
            .lG, .lineG => .global,
            .lO, .lineO => .output,
        };
        return AttributesUnion{ .lineWidth = .{
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

    const r1 = try lineWidthTypeParserRaw.parse(a, "l:10");
    try testing.expectEqual(Parser.T{ "l", 10 }, r1.value.ok);

    const r2 = try lineWidthTypeParserRaw.asStr().parse(a, "l  :  10");
    try testing.expectEqualStrings("l  :  10", r2.value.ok);

    const r3 = try lineWidthTypeParserRaw.parse(a, "lL  :  10");
    try testing.expectEqual(Parser.T{ "lL", 10 }, r3.value.ok);

    const r4 = try lineWidthTypeParserRaw.parse(a, "lineG  :  10");
    try testing.expectEqual(Parser.T{ "lineG", 10 }, r4.value.ok);
}

test "LineWidthTypeParserTyped" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineWidthTypeParserTyped.parse(a, "l:10");
    try testing.expectEqual(LineWidthType{ .reference = .normalized, .value = 10 }, r1.value.ok);

    const r2 = try lineWidthTypeParserTyped.parse(a, "l  :  10");
    try testing.expectEqual(LineWidthType{ .reference = .normalized, .value = 10 }, r2.value.ok);

    const r3 = try lineWidthTypeParserTyped.parse(a, "lG  :  6");
    try testing.expectEqual(LineWidthType{ .reference = .global, .value = 6 }, r3.value.ok);

    const r4 = try lineWidthTypeParserTyped.parse(a, "line:10");
    try testing.expectEqual(LineWidthType{ .reference = .normalized, .value = 10 }, r4.value.ok);
}

//LineColor parser
const lineColorTypeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("color"), mecha.string("c") }).discard(), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, common.colorNameParserTyped });
const lineColorTypeParserRawP = @TypeOf(lineColorTypeParserRaw);
fn toLineColorType(_: std.mem.Allocator, res: lineColorTypeParserRawP.T) mecha.ConvertError!LineColorType {
    return .{ .value = res };
}
const lineColorTypeParserTyped = lineColorTypeParserRaw.convert(toLineColorType);
fn toLineColorUnion(_: std.mem.Allocator, res: lineColorTypeParserRawP.T) mecha.ConvertError!AttributesUnion {
    return AttributesUnion{ .lineColor = .{ .value = res } };
}
const lineColorUnionParser = lineColorTypeParserRaw.convert(toLineColorUnion);

test "LineWColorTypeParserTyped" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineColorTypeParserTyped.parse(a, "c:green");
    try testing.expectEqual(LineColorType{ .value = .green }, r1.value.ok);

    const r2 = try lineColorTypeParserTyped.parse(a, "c :  green");
    try testing.expectEqual(LineColorType{ .value = .green }, r2.value.ok);

    const r3 = try lineColorTypeParserTyped.parse(a, "color : yellow");
    try testing.expectEqual(LineColorType{ .value = .yellow }, r3.value.ok);
}

//LineOpacity parser
const lineOpacityTypeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("opacity"), mecha.string("o") }).discard(), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.int(u8, .{}) });
const lineOpacityTypeParserRawP = @TypeOf(lineOpacityTypeParserRaw);
fn toLineOpacityType(_: std.mem.Allocator, res: lineOpacityTypeParserRawP.T) mecha.ConvertError!LineOpacityType {
    return .{ .value = res };
}
const lineOpacityTypeParserTyped = lineOpacityTypeParserRaw.convert(toLineOpacityType);
fn toLineOpacityUnion(_: std.mem.Allocator, res: lineOpacityTypeParserRawP.T) mecha.ConvertError!AttributesUnion {
    return AttributesUnion{ .lineOpacity = .{ .value = res } };
}
const lineOpacityUnionParser = lineOpacityTypeParserRaw.convert(toLineOpacityUnion);

test "LineOpacityTypeParserTyped" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineOpacityTypeParserTyped.parse(a, "o:10");
    try testing.expectEqual(LineOpacityType{ .value = 10 }, r1.value.ok);

    const r2 = try lineOpacityTypeParserTyped.parse(a, "o  :  10");
    try testing.expectEqual(LineOpacityType{ .value = 10 }, r2.value.ok);

    const r3 = try lineOpacityTypeParserTyped.parse(a, "opacity  :  6");
    try testing.expectEqual(LineOpacityType{ .value = 6 }, r3.value.ok);
}

//LineCap parser
const lineCapTypeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("cap"), mecha.string("e") }).discard(), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.oneOf(.{ mecha.string("none"), mecha.string("n"), mecha.string("butt"), mecha.string("b"), mecha.string("round"), mecha.string("r"), mecha.string("square"), mecha.string("s") }) });
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
fn toLineCapUnion(_: std.mem.Allocator, res: lineCapTypeParserRawP.T) mecha.ConvertError!AttributesUnion {
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
        return AttributesUnion{ .lineCap = .{
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

    const r1 = try lineCapTypeParserTyped.parse(a, "e: n");
    try testing.expectEqual(LineCapType{ .value = .none }, r1.value.ok);

    const r2 = try lineCapTypeParserTyped.parse(a, "cap  :  none");
    try testing.expectEqual(LineCapType{ .value = .none }, r2.value.ok);

    const r3 = try lineCapTypeParserTyped.parse(a, "e  :  b");
    try testing.expectEqual(LineCapType{ .value = .butt }, r3.value.ok);
}

//LineJoin parser
const lineJoinTypeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("join"), mecha.string("j") }).discard(), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.oneOf(.{ mecha.string("none"), mecha.string("n"), mecha.string("mitter"), mecha.string("m"), mecha.string("round"), mecha.string("r"), mecha.string("bevel"), mecha.string("b") }) });
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
fn toLineJoinUnion(_: std.mem.Allocator, res: lineJoinTypeParserRawP.T) mecha.ConvertError!AttributesUnion {
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
        return AttributesUnion{ .lineJoin = .{
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

    const r1 = try lineJoinTypeParserTyped.parse(a, "j: n");
    try testing.expectEqual(LineJoinType{ .value = .none }, r1.value.ok);

    const r2 = try lineJoinTypeParserTyped.parse(a, "join  :  none");
    try testing.expectEqual(LineJoinType{ .value = .none }, r2.value.ok);

    const r3 = try lineJoinTypeParserTyped.parse(a, "j  :  b");
    try testing.expectEqual(LineJoinType{ .value = .bevel }, r3.value.ok);
}

//LineDashing parser
const lineDashingTypeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("dashL"), mecha.string("dashG"), mecha.string("dashN"), mecha.string("dashO"), mecha.string("dash"), mecha.string("dL"), mecha.string("dG"), mecha.string("dN"), mecha.string("dO"), mecha.string("d") }), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.string("[").discard(), common.skipWhitespace, mecha.int(u16, .{}).many(.{ .collect = true, .min = 2, .separator = mecha.combine(.{ common.skipWhitespace, mecha.string(","), common.skipWhitespace }).discard() }), common.skipWhitespace, mecha.string("]").discard(), common.skipWhitespace, mecha.opt(mecha.int(i16, .{})) });
const lineDashingTypeParserRawP = @TypeOf(lineDashingTypeParserRaw);
const LineDashingT = enum {
    d,
    dL,
    dG,
    dN,
    dO,
    dash,
    dashL,
    dashG,
    dashN,
    dashO,
};
fn toLineDashingType(_: std.mem.Allocator, res: lineDashingTypeParserRawP.T) mecha.ConvertError!LineDashingType {
    const to = struct {
        fn to(str: []const u8) ?LineDashingT {
            return std.meta.stringToEnum(LineDashingT, str);
        }
    }.to;
    if (to(res[0])) |validT| {
        const reference: ReferenceFrame = switch (validT) {
            .d, .dash, .dO, .dashO => .output,
            .dL, .dashL => .local,
            .dG, .dashG => .global,
            .dN, .dashN => .normalized,
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
fn toLineDashingUnion(_: std.mem.Allocator, res: lineDashingTypeParserRawP.T) mecha.ConvertError!AttributesUnion {
    const to = struct {
        fn to(str: []const u8) ?LineDashingT {
            return std.meta.stringToEnum(LineDashingT, str);
        }
    }.to;
    if (to(res[0])) |validT| {
        const reference: ReferenceFrame = switch (validT) {
            .d, .dash, .dO, .dashO => .output,
            .dL, .dashL => .local,
            .dG, .dashG => .global,
            .dN, .dashN => .normalized,
        };
        return AttributesUnion{ .lineDashing = .{
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
    mecha.oneOf(.{ mecha.string("dash"), mecha.string("d") }),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.oneOf(.{ mecha.string("null"), mecha.string("none") }),
});
const lineDashingNullParser = lineDashingNullParserRaw.convert(struct {
    fn toNull(_: std.mem.Allocator, _: anytype) mecha.ConvertError!AttributesUnion {
        return AttributesUnion{ .lineDashing = null };
    }
}.toNull);

//PointShape parser
const pointShapeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("shape"), mecha.string("sh") }).discard(), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("circle"), mecha.string("square") }).asStr(), mecha.toEnum(PointShape)) });
const pointShapeParserRawP = @TypeOf(pointShapeParserRaw);
fn toPointShape(_: std.mem.Allocator, res: pointShapeParserRawP.T) mecha.ConvertError!PointShapeType {
    return .{ .value = res };
}
const pointShapeParserTyped = pointShapeParserRaw.convert(toPointShape);

//PointSize parser
const pointSizeParserRaw =
    mecha.combine(.{ mecha.oneOf(.{ mecha.string("size"), mecha.string("s") }).discard(), common.skipWhitespace, mecha.ascii.char(':').discard(), common.skipWhitespace, mecha.int(u16, .{}) });
const pointSizeParserRawP = @TypeOf(pointSizeParserRaw);
fn toPointSize(_: std.mem.Allocator, res: pointSizeParserRawP.T) mecha.ConvertError!PointSizeType {
    return .{ .value = res };
}
const pointSizeParserTyped = pointSizeParserRaw.convert(toPointSize);

fn toPointShapeUnion(_: std.mem.Allocator, res: pointShapeParserRawP.T) mecha.ConvertError!AttributesUnion {
    return AttributesUnion{ .pointShape = .{ .value = res } };
}
const pointShapeUnionParser = pointShapeParserRaw.convert(toPointShapeUnion);

fn toPointSizeUnion(_: std.mem.Allocator, res: pointSizeParserRawP.T) mecha.ConvertError!AttributesUnion {
    return AttributesUnion{ .pointSize = .{ .value = res } };
}
const pointSizeUnionParser = pointSizeParserRaw.convert(toPointSizeUnion);

test "pointShapeParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try pointShapeParserTyped.parse(a, "sh:circle");
    try testing.expectEqual(PointShapeType{ .value = .circle }, r1.value.ok);

    const r2 = try pointShapeParserTyped.parse(a, "sh  :  square");
    try testing.expectEqual(PointShapeType{ .value = .square }, r2.value.ok);

    const r3 = try pointShapeParserTyped.parse(a, "shape : circle");
    try testing.expectEqual(PointShapeType{ .value = .circle }, r3.value.ok);

    const r4 = try pointShapeParserTyped.parse(a, "circle");
    try testing.expectEqual(0, r4.index);
}

test "pointSizeParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try pointSizeParserTyped.parse(a, "s:10");
    try testing.expectEqual(PointSizeType{ .value = 10 }, r1.value.ok);

    const r2 = try pointSizeParserTyped.parse(a, "s  :  5");
    try testing.expectEqual(PointSizeType{ .value = 5 }, r2.value.ok);

    const r3 = try pointSizeParserTyped.parse(a, "size : 20");
    try testing.expectEqual(PointSizeType{ .value = 20 }, r3.value.ok);

    const r4 = try pointSizeParserTyped.parse(a, "10");
    try testing.expectEqual(0, r4.index);
}

test "LineDashingTypeParserTyped" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineDashingTypeParserTyped.parse(a, "d: [2 , 3] 1");
    try testing.expectEqualDeep(LineDashingType{ .reference = .output, .onOff = &[2]u16{ 2, 3 }, .offset = 1 }, r1.value.ok);

    const r2 = try lineDashingTypeParserTyped.parse(a, "d  :  [2   ,    3]    1");
    try testing.expectEqualDeep(LineDashingType{ .reference = .output, .onOff = &[_]u16{ 2, 3 }, .offset = 1 }, r2.value.ok);

    const r3 = try lineDashingTypeParserTyped.parse(a, "dG  :  [ 2,3,10] 0");
    try testing.expectEqualDeep(LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 }, r3.value.ok);

    const r4 = try lineDashingTypeParserTyped.parse(a, "dashN  :  [ 2,3,10] 0");
    try testing.expectEqualDeep(LineDashingType{ .reference = .normalized, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 }, r4.value.ok);
}

//Attributes parser
const attributesUnionParser = mecha.oneOf(.{
    lineWidthUnionParser,
    lineColorUnionParser,
    lineOpacityUnionParser,
    lineCapUnionParser,
    lineJoinUnionParser,
    lineDashingNullParser,
    lineDashingUnionParser,
    pointShapeUnionParser,
    pointSizeUnionParser,
});

test "attributesUnionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try attributesUnionParser.parse(a, "l:10");
    try testing.expectEqual(AttributesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, r1.value.ok);

    const r2 = try attributesUnionParser.parse(a, "l  :  10");
    try testing.expectEqual(AttributesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, r2.value.ok);

    const r3 = try attributesUnionParser.parse(a, "lG  :  6");
    try testing.expectEqual(AttributesUnion{ .lineWidth = .{ .reference = .global, .value = 6 } }, r3.value.ok);

    const r4 = try attributesUnionParser.parse(a, "c:green");
    try testing.expectEqual(AttributesUnion{ .lineColor = .{ .value = .green } }, r4.value.ok);

    const r5 = try attributesUnionParser.parse(a, "c :  green");
    try testing.expectEqual(AttributesUnion{ .lineColor = .{ .value = .green } }, r5.value.ok);

    const r6 = try attributesUnionParser.parse(a, "c : yellow");
    try testing.expectEqual(AttributesUnion{ .lineColor = .{ .value = .yellow } }, r6.value.ok);

    const r7 = try attributesUnionParser.parse(a, "o:10");
    try testing.expectEqual(AttributesUnion{ .lineOpacity = .{ .value = 10 } }, r7.value.ok);

    const r8 = try attributesUnionParser.parse(a, "o  :  10");
    try testing.expectEqual(AttributesUnion{ .lineOpacity = .{ .value = 10 } }, r8.value.ok);

    const r9 = try attributesUnionParser.parse(a, "o  :  6");
    try testing.expectEqual(AttributesUnion{ .lineOpacity = .{ .value = 6 } }, r9.value.ok);

    const r10 = try attributesUnionParser.parse(a, "e: n");
    try testing.expectEqual(AttributesUnion{ .lineCap = .{ .value = .none } }, r10.value.ok);

    const r11 = try attributesUnionParser.parse(a, "e  :  none");
    try testing.expectEqual(AttributesUnion{ .lineCap = .{ .value = .none } }, r11.value.ok);

    const r12 = try attributesUnionParser.parse(a, "e  :  b");
    try testing.expectEqual(AttributesUnion{ .lineCap = .{ .value = .butt } }, r12.value.ok);

    const r13 = try attributesUnionParser.parse(a, "j: n");
    try testing.expectEqual(AttributesUnion{ .lineJoin = .{ .value = .none } }, r13.value.ok);

    const r14 = try attributesUnionParser.parse(a, "j  :  none");
    try testing.expectEqual(AttributesUnion{ .lineJoin = .{ .value = .none } }, r14.value.ok);

    const r15 = try attributesUnionParser.parse(a, "j  :  b");
    try testing.expectEqual(AttributesUnion{ .lineJoin = .{ .value = .bevel } }, r15.value.ok);

    const r16 = try attributesUnionParser.parse(a, "d: [2 , 3] 1");
    try testing.expectEqualDeep(AttributesUnion{ .lineDashing = .{ .reference = .output, .onOff = &[2]u16{ 2, 3 }, .offset = 1 } }, r16.value.ok);

    const r17 = try attributesUnionParser.parse(a, "d  :  [2   ,    3]    1");
    try testing.expectEqualDeep(AttributesUnion{ .lineDashing = .{ .reference = .output, .onOff = &[_]u16{ 2, 3 }, .offset = 1 } }, r17.value.ok);

    const r18 = try attributesUnionParser.parse(a, "dG  :  [ 2,3,10] 0");
    try testing.expectEqualDeep(AttributesUnion{ .lineDashing = .{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 } }, r18.value.ok);

    const r19 = try attributesUnionParser.parse(a, "sh:square");
    try testing.expectEqual(AttributesUnion{ .pointShape = .{ .value = .square } }, r19.value.ok);

    const r20 = try attributesUnionParser.parse(a, "s:5");
    try testing.expectEqual(AttributesUnion{ .pointSize = .{ .value = 5 } }, r20.value.ok);
}

const attributeSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
const many_attributesUnionParser = mecha.many(attributesUnionParser, .{ .separator = attributeSeparatorParser });
fn manyToAttributes(arena: std.mem.Allocator, fields: []AttributesUnion) mecha.ConvertError!Attributes {
    var res = Attributes{};
    for (fields) |field| switch (field) {
        .lineWidth => |f| res.lineWidth = f,
        .lineColor => |f| res.lineColor = f,
        .lineOpacity => |f| res.lineOpacity = f,
        .lineCap => |f| res.lineCap = f,
        .lineJoin => |f| res.lineJoin = f,
        .lineDashing => |f| res.lineDashing = f,
        .pointShape => |f| res.pointShape = f,
        .pointSize => |f| res.pointSize = f,
    };

    arena.free(fields);
    return res;
}
const attributesParser = many_attributesUnionParser.convert(manyToAttributes);

const attributesParserBracketed = mecha.combine(.{ skipOpenRecBracket, attributesParser, skipCloseRecBracket });
const attributesParserBracketedP = @TypeOf(attributesParserBracketed);
fn toAttributesUnion(_: std.mem.Allocator, res: attributesParserBracketedP.T) mecha.ConvertError!StyleValueUnion {
    return StyleValueUnion{ .attributes = res };
}
const attributesParserBracketedUnion = attributesParserBracketed.convert(toAttributesUnion);

test "many_attributesUnionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try many_attributesUnionParser.parse(a, "l:10");
    try testing.expectEqualDeep(&[1]AttributesUnion{AttributesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }}, r1.value.ok);

    const r2 = try many_attributesUnionParser.parse(a, "o  :  6");
    try testing.expectEqualDeep(&[1]AttributesUnion{AttributesUnion{ .lineOpacity = .{ .value = 6 } }}, r2.value.ok);

    const r3 = try many_attributesUnionParser.parse(a, "l:10 , o  :  6");
    try testing.expectEqualDeep(&[2]AttributesUnion{ AttributesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, AttributesUnion{ .lineOpacity = .{ .value = 6 } } }, r3.value.ok);

    const r4 = try many_attributesUnionParser.parse(a, "dG  :  [ 2,3,10] 0");
    try testing.expectEqualDeep(&[1]AttributesUnion{AttributesUnion{ .lineDashing = .{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 } }}, r4.value.ok);

    const r5 = try many_attributesUnionParser.parse(a, "l:10 ,dG  :  [ 2,3,10] 0, o  :  6");
    try testing.expectEqualDeep(&[3]AttributesUnion{ AttributesUnion{ .lineWidth = .{ .reference = .normalized, .value = 10 } }, AttributesUnion{ .lineDashing = .{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 } }, AttributesUnion{ .lineOpacity = .{ .value = 6 } } }, r5.value.ok);

    const r6 = try many_attributesUnionParser.parse(a, "sh:circle, s:5");
    try testing.expectEqualDeep(&[2]AttributesUnion{ AttributesUnion{ .pointShape = .{ .value = .circle } }, AttributesUnion{ .pointSize = .{ .value = 5 } } }, r6.value.ok);
}

test "attributesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try attributesParser.parse(a, "l:10");
    const styles1 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = null,
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = null,
    };
    try testing.expectEqual(styles1, r1.value.ok);

    const r2 = try attributesParser.parse(a, "l:10, o  :  6");
    const styles2 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = null,
    };
    try testing.expectEqual(styles2, r2.value.ok);

    const r3 = try attributesParser.parse(a, "dG  :  [ 2,3,10] 0,l:10, o  :  6");
    const styles3 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 },
    };
    try testing.expectEqualDeep(styles3, r3.value.ok);

    const r4 = try attributesParser.parse(a, "sh:circle, s:5");
    const styles4 = Attributes{
        .pointShape = PointShapeType{ .value = .circle },
        .pointSize = PointSizeType{ .value = 5 },
    };
    try testing.expectEqualDeep(styles4, r4.value.ok);
}

test "attributesParserBracketedUnion" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try attributesParserBracketedUnion.parse(a, "[l:10]");
    const styles1 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = null,
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = null,
    };
    const exp_value1 = StyleValueUnion{ .attributes = styles1 };
    try testing.expectEqual(exp_value1, r1.value.ok);

    const r2 = try attributesParserBracketedUnion.parse(a, "[l:10, o  :  6]");
    const styles2 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = null,
    };
    const exp_value2 = StyleValueUnion{ .attributes = styles2 };
    try testing.expectEqual(exp_value2, r2.value.ok);

    const r3 = try attributesParserBracketedUnion.parse(a, "[dG  :  [ 2,3,10] 0,l:10, o  :  6]");
    const styles3 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 },
    };
    const exp_value3 = StyleValueUnion{ .attributes = styles3 };
    try testing.expectEqualDeep(exp_value3, r3.value.ok);

    const r4 = try attributesParserBracketedUnion.parse(a, "[sh:circle, s:5]");
    const styles4 = Attributes{
        .pointShape = PointShapeType{ .value = .circle },
        .pointSize = PointSizeType{ .value = 5 },
    };
    const exp_value4 = StyleValueUnion{ .attributes = styles4 };
    try testing.expectEqual(exp_value4, r4.value.ok);

    const r5 = try attributesParserBracketedUnion.parse(a, "[c: red, o: 50, sh:square, s: 5]");
    const styles5 = Attributes{
        .lineColor = LineColorType{ .value = .red },
        .lineOpacity = LineOpacityType{ .value = 50 },
        .pointShape = PointShapeType{ .value = .square },
        .pointSize = PointSizeType{ .value = 5 },
    };
    const exp_value5 = StyleValueUnion{ .attributes = styles5 };
    try testing.expectEqual(exp_value5, r5.value.ok);
}

//Style parser
const styleValueUnionParser = mecha.oneOf(.{
    styleTypeUnionParser,
    coordinateTypeUnionParser,
    coordinateOrientationUnionParser,
    plotStepsUnionParser,
    attributesParserBracketedUnion,
});
const many_styleValueUnionParser = mecha.many(styleValueUnionParser, .{ .separator = common.skipWhitespace });
fn manyToStyleValue(arena: std.mem.Allocator, fields: []StyleValueUnion) mecha.ConvertError!StyleValue {
    var res = StyleValue{};
    for (fields) |field| switch (field) {
        .styleType => |f| res.styleType = f,
        .coordinateSystem => |f| res.coordinateSystem = f,
        .coordinateOrientation => |f| res.coordinateOrientation = f,
        .plotSteps => |f| res.plotSteps = f,
        .attributes => |f| {
            if (!attributesEmpty(f)) res.attributes = f;
        },
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
    const exp_value0 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
    };
    try testing.expectEqual(exp_value0, r0.value.ok);

    const r1 = try styleValueParser.parse(a, "vec2d [l:10, o  :  6]");
    const styles1 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = null,
    };
    const exp_value1 = StyleValue{
        .styleType = .vec2d,
        .attributes = styles1,
    };
    try testing.expectEqual(exp_value1, r1.value.ok);

    const r2 = try styleValueParser.parse(a, "vec2d  [l:10, o  :  6]");
    const styles2 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = null,
    };
    const exp_value2 = StyleValue{
        .styleType = .vec2d,
        .attributes = styles2,
    };
    try testing.expectEqual(exp_value2, r2.value.ok);

    const r3 = try styleValueParser.parse(a, "vec2d polar [dG  :  [ 2,3,10] 0,l:10, o  :  6]");
    const styles3 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 },
    };
    const exp_value3 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
        .attributes = styles3,
    };
    try testing.expectEqualDeep(exp_value3, r3.value.ok);

    const r4 = try styleValueParser.parse(a, "pt2d [sh:square, s:5]");
    const styles4 = Attributes{
        .pointShape = PointShapeType{ .value = .square },
        .pointSize = PointSizeType{ .value = 5 },
    };
    const exp_value4 = StyleValue{
        .styleType = .pt2d,
        .attributes = styles4,
    };
    try testing.expectEqualDeep(exp_value4, r4.value.ok);
}

const bodyParser = mecha.combine(.{ common.skipOpenBrace, many_styleValueUnionParser, common.skipCloseBrace });
const styleParserRaw = mecha.combine(.{
    styleNumberParserRaw,
    mecha.opt(mecha.ascii.char(':').discard()),
    common.skipWhitespace,
    mecha.opt(styleNumberParserRaw),
    common.skipWhitespace,
    mecha.opt(bodyParser),
});
const styleParserRawP = @TypeOf(styleParserRaw);
fn toStyle(_: std.mem.Allocator, res: styleParserRawP.T) mecha.ConvertError!Style {
    const styleNumber = res[0];
    const baseStyle = res[2];
    const body = res[3];

    var styleValue = StyleValue{};
    if (baseStyle) |bs| {
        styleValue.baseStyle = bs;
    }
    if (body) |b| {
        for (b) |field| switch (field) {
            .styleType => |f| styleValue.styleType = f,
            .coordinateSystem => |f| styleValue.coordinateSystem = f,
            .coordinateOrientation => |f| styleValue.coordinateOrientation = f,
            .plotSteps => |f| styleValue.plotSteps = f,
            .attributes => |f| {
                if (!attributesEmpty(f)) styleValue.attributes = f;
            },
        };
    }
    return Style{ .styleNumber = styleNumber, .styleValue = styleValue };
}
pub const styleParser = styleParserRaw.convert(toStyle);

pub const pointStyleOffset: u8 = 128;
pub const PointStyleDefinition = struct {
    styleNumber: u8,
    styleValue: StyleValue,
};

const pointStyleNumberParserRaw =
    mecha.combine(.{ common.skipWhitespace, mecha.ascii.char('p').discard(), mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 }).asStr().convert(mecha.toInt(u8, 10)) });
const pointStyleParserRaw = mecha.combine(.{
    pointStyleNumberParserRaw,
    mecha.opt(mecha.ascii.char(':').discard()),
    common.skipWhitespace,
    mecha.opt(pointStyleNumberParserRaw),
    common.skipWhitespace,
    mecha.opt(bodyParser),
});
const pointStyleParserRawP = @TypeOf(pointStyleParserRaw);
fn toPointStyle(_: std.mem.Allocator, res: pointStyleParserRawP.T) mecha.ConvertError!PointStyleDefinition {
    const number = res[0];
    const base = res[2];
    const body = res[3];
    var styleValue = StyleValue{ .styleType = .pt2d };
    if (base) |base_number| styleValue.baseStyle = pointStyleOffset + base_number;
    if (body) |fields| {
        for (fields) |field| switch (field) {
            .styleType => |style_type| styleValue.styleType = style_type,
            .coordinateSystem => |coordinate_system| styleValue.coordinateSystem = coordinate_system,
            .coordinateOrientation => |coordinate_orientation| styleValue.coordinateOrientation = coordinate_orientation,
            .plotSteps => |plot_steps| styleValue.plotSteps = plot_steps,
            .attributes => |attributes| {
                if (!attributesEmpty(attributes)) styleValue.attributes = attributes;
            },
        };
    }
    if (styleValue.styleType != .pt2d) return error.ConversionFailed;
    return .{ .styleNumber = pointStyleOffset + number, .styleValue = styleValue };
}
pub const pointStyleParser = pointStyleParserRaw.convert(toPointStyle);

test "pointStyleParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r = try pointStyleParser.parse(a, "p0:{pt2d [sh:square, s:15, c: grey]}");
    try testing.expectEqual(@as(u8, 128), r.value.ok.styleNumber);
    try testing.expectEqual(StyleType.pt2d, r.value.ok.styleValue.styleType);
    try testing.expectEqual(PointShape.square, r.value.ok.styleValue.attributes.?.pointShape.?.value);
    try testing.expectEqual(@as(u16, 15), r.value.ok.styleValue.attributes.?.pointSize.?.value);
}

test "stylesParser pN" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r = try stylesParser.parse(a, "p0:{pt2d [sh:square, s:15]}");
    try testing.expectEqual(@as(usize, 1), r.value.ok.len);
    try testing.expectEqual(@as(u8, 128), r.value.ok[0].styleNumber);
}

test "styleParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r0 = try styleParser.parse(a, "e0:{vec2d polar}");
    const exp_value0 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
    };
    const exp_element0 = Style{
        .styleNumber = 0,
        .styleValue = exp_value0,
    };
    try testing.expectEqual(exp_element0, r0.value.ok);

    const r1 = try styleParser.parse(a, "e8: {vec2d [l:10]}");
    const styles1 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = null,
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = null,
    };
    const exp_value1 = StyleValue{
        .styleType = .vec2d,
        .attributes = styles1,
    };
    const exp_element1 = Style{
        .styleNumber = 8,
        .styleValue = exp_value1,
    };
    try testing.expectEqual(exp_element1, r1.value.ok);

    const r2 = try styleParser.parse(a, " e8: {  vec2d  [l:10, o  :  6]}");
    const styles2 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = null,
    };
    const exp_value2 = StyleValue{
        .styleType = .vec2d,
        .attributes = styles2,
    };
    const exp_element2 = Style{
        .styleNumber = 8,
        .styleValue = exp_value2,
    };
    try testing.expectEqual(exp_element2, r2.value.ok);

    const r3 = try styleParser.parse(a, "e11: { vec2d polar [dG  :  [ 2,3,10] 0,l:10, o  :  6]}");
    const styles3 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 },
    };
    const exp_value3 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
        .attributes = styles3,
    };
    const exp_element3 = Style{
        .styleNumber = 11,
        .styleValue = exp_value3,
    };
    try testing.expectEqualDeep(exp_element3, r3.value.ok);

    const r4 = try styleParser.parse(a, "e1: {vec2d }");
    const exp_value4 = StyleValue{
        .styleType = .vec2d,
    };
    const exp_element4 = Style{
        .styleNumber = 1,
        .styleValue = exp_value4,
    };
    try testing.expectEqualDeep(exp_element4, r4.value.ok);

    const r5 = try styleParser.parse(a, "e0:{vec2d polar all}");
    const exp_value5 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
        .plotSteps = .all,
    };
    const exp_element5 = Style{
        .styleNumber = 0,
        .styleValue = exp_value5,
    };
    try testing.expectEqual(exp_element5, r5.value.ok);

    // Test partial style without vec2d (should use defaults)
    const r6 = try styleParser.parse(a, "e0:{[l:15, c: red]}");
    const styles6 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 15 },
        .lineColor = LineColorType{ .value = .red },
        .lineOpacity = null,
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = null,
    };
    const exp_value6 = StyleValue{
        .attributes = styles6,
    };
    const exp_element6 = Style{
        .styleNumber = 0,
        .styleValue = exp_value6,
    };
    try testing.expectEqual(exp_element6, r6.value.ok);

    // Test partial style without colon
    const r7 = try styleParser.parse(a, "e0{[l:15, c: red]}");
    const exp_element7 = Style{
        .styleNumber = 0,
        .styleValue = exp_value6,
    };
    try testing.expectEqual(exp_element7, r7.value.ok);

    // Test reference style with base
    const r8 = try styleParser.parse(a, "e0: e0{[l:15, c: red]}");
    const exp_value8 = StyleValue{
        .baseStyle = 0,
        .attributes = styles6,
    };
    const exp_element8 = Style{
        .styleNumber = 0,
        .styleValue = exp_value8,
    };
    try testing.expectEqual(exp_element8, r8.value.ok);

    // Test copy style
    const r9 = try styleParser.parse(a, "e1: e0");
    const exp_value9 = StyleValue{
        .baseStyle = 0,
    };
    const exp_element9 = Style{
        .styleNumber = 1,
        .styleValue = exp_value9,
    };
    try testing.expectEqual(exp_element9, r9.value.ok);
}

const styleSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
const pointStyleAsStyleParser = pointStyleParser.map(struct {
    fn toStyle(p: PointStyleDefinition) Style {
        return .{ .styleNumber = p.styleNumber, .styleValue = p.styleValue };
    }
}.toStyle);
const styleOrPointParser = mecha.oneOf(.{ styleParser, pointStyleAsStyleParser });
const stylesParserRaw = mecha.many(styleOrPointParser, .{ .collect = true, .separator = styleSeparatorParser });
const stylesParserRawP = @TypeOf(stylesParserRaw);

pub const defaultStyleValue = StyleValue{
    .styleType = .vec2d,
    .coordinateSystem = .xy,
    .coordinateOrientation = .fixed,
    .plotSteps = .last,
    .attributes = Attributes{
        .lineWidth = LineWidthType{ .reference = .output, .value = 10 },
        .lineColor = LineColorType{ .value = .black },
        .lineOpacity = LineOpacityType{ .value = 100 },
        .lineCap = LineCapType{ .value = .none },
        .lineJoin = LineJoinType{ .value = .none },
        .lineDashing = null,
        .pointShape = PointShapeType{ .value = .circle },
        .pointSize = PointSizeType{ .value = 10 },
    },
};

pub fn resolveStyles(arena: std.mem.Allocator, styles: []const Style) ![]Style {
    var map = std.AutoHashMap(u8, StyleValue).init(arena);
    defer map.deinit();

    try map.put(0, defaultStyleValue);

    var result = try arena.alloc(Style, styles.len);
    for (styles, 0..) |style, i| {
        result[i] = style;
        var resolved = if (style.styleValue.baseStyle) |base| blk: {
            const base_value = map.get(base) orelse defaultStyleValue;
            var r = base_value;
            r.baseStyle = null;
            break :blk r;
        } else blk: {
            var r = defaultStyleValue;
            r.baseStyle = null;
            break :blk r;
        };

        if (style.styleValue.attributes) |override_attrs| {
            var resolved_attrs = resolved.attributes orelse Attributes{};
            if (override_attrs.lineWidth) |l| resolved_attrs.lineWidth = l;
            if (override_attrs.lineColor) |lc| resolved_attrs.lineColor = lc;
            if (override_attrs.lineOpacity) |lo| resolved_attrs.lineOpacity = lo;
            if (override_attrs.lineCap) |le| resolved_attrs.lineCap = le;
            if (override_attrs.lineJoin) |lj| resolved_attrs.lineJoin = lj;
            if (override_attrs.lineDashing) |ld| resolved_attrs.lineDashing = ld;
            if (override_attrs.pointShape) |ps| resolved_attrs.pointShape = ps;
            if (override_attrs.pointSize) |psz| resolved_attrs.pointSize = psz;
            resolved.attributes = resolved_attrs;
        }

        if (style.styleValue.styleType) |st| resolved.styleType = st;
        if (style.styleValue.coordinateSystem) |cs| resolved.coordinateSystem = cs;
        if (style.styleValue.coordinateOrientation) |co| resolved.coordinateOrientation = co;
        if (style.styleValue.plotSteps) |ps| resolved.plotSteps = ps;

        result[i].styleValue = resolved;
        try map.put(result[i].styleNumber, result[i].styleValue);
    }

    return result;
}

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

    const r0 = try stylesParser.parse(a, "e0:{vec2d polar}, e8:{vec2d [l:10]}");
    const exp_value0 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
    };
    const exp_element0 = Style{
        .styleNumber = 0,
        .styleValue = exp_value0,
    };

    const styles1 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = null,
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = null,
    };
    const exp_value1 = StyleValue{
        .styleType = .vec2d,
        .attributes = styles1,
    };
    const exp_element1 = Style{
        .styleNumber = 8,
        .styleValue = exp_value1,
    };
    const exp_styles0 = [2]Style{ exp_element0, exp_element1 };
    try testing.expectEqualDeep(&exp_styles0, r0.value.ok);

    const r1 = try stylesParser.parse(a, " e8: {  vec2d  [l:10, o  :  6]}, e11: { vec2d polar [dG  :  [ 2,3,10] 0,l:10, o  :  6]}");
    const styles2 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = null,
    };
    const exp_value2 = StyleValue{
        .styleType = .vec2d,
        .attributes = styles2,
    };
    const exp_element2 = Style{
        .styleNumber = 8,
        .styleValue = exp_value2,
    };

    const styles3 = Attributes{
        .lineWidth = LineWidthType{ .reference = .normalized, .value = 10 },
        .lineColor = null,
        .lineOpacity = LineOpacityType{ .value = 6 },
        .lineCap = null,
        .lineJoin = null,
        .lineDashing = LineDashingType{ .reference = .global, .onOff = &[_]u16{ 2, 3, 10 }, .offset = 0 },
    };
    const exp_value3 = StyleValue{
        .styleType = .vec2d,
        .coordinateSystem = .polar,
        .attributes = styles3,
    };
    const exp_element3 = Style{
        .styleNumber = 11,
        .styleValue = exp_value3,
    };

    const exp_styles1 = [2]Style{ exp_element2, exp_element3 };
    try testing.expectEqualDeep(&exp_styles1, r1.value.ok);
}

test "styleParser pt2d" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try styleParser.parse(a, "e0:{pt2d [sh:square, s:5, c: red, o: 50]}");
    const styles1 = Attributes{
        .pointShape = PointShapeType{ .value = .square },
        .pointSize = PointSizeType{ .value = 5 },
        .lineColor = LineColorType{ .value = .red },
        .lineOpacity = LineOpacityType{ .value = 50 },
    };
    const exp_value1 = StyleValue{
        .styleType = .pt2d,
        .attributes = styles1,
    };
    const exp_element1 = Style{
        .styleNumber = 0,
        .styleValue = exp_value1,
    };
    try testing.expectEqualDeep(exp_element1, r1.value.ok);

    const r2 = try styleParser.parse(a, "e1: e0");
    const exp_element2 = Style{
        .styleNumber = 1,
        .styleValue = StyleValue{ .baseStyle = 0 },
    };
    try testing.expectEqualDeep(exp_element2, r2.value.ok);
}

test "resolveStyles pt2d" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try stylesParser.parse(a, "e0:{pt2d [sh:square]}, e1: e0{[s:5]}");
    const resolved = try resolveStyles(a, r1.value.ok);
    try testing.expectEqual(StyleType.pt2d, resolved[0].styleValue.styleType);
    try testing.expectEqual(PointShape.square, resolved[0].styleValue.attributes.?.pointShape.?.value);
    // e1 inherits shape from e0 and overrides size
    try testing.expectEqual(PointShape.square, resolved[1].styleValue.attributes.?.pointShape.?.value);
    try testing.expectEqual(@as(u16, 5), resolved[1].styleValue.attributes.?.pointSize.?.value);
    // defaults for color/opacity fill in
    try testing.expectEqual(LineColorType{ .value = .black }, resolved[1].styleValue.attributes.?.lineColor.?);
    try testing.expectEqual(LineOpacityType{ .value = 100 }, resolved[1].styleValue.attributes.?.lineOpacity.?);
}

test "serializeStyle pt2d" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try stylesParser.parse(a, "e0:{pt2d [sh:square, s:5]}");
    const resolved = try resolveStyles(a, r1.value.ok);
    const s = try serializeStyle(a, resolved[0]);
    try testing.expectEqualStrings("e0:{pt2d xy fixed last [sh:square, s:5, c: black, o: 100]}", s);
}

/// Serializes a resolved Style to its string representation, filling in defaults.
/// Suitable for --debug output so users see the effective settings.
pub fn serializeStyle(allocator: std.mem.Allocator, style: Style) ![]const u8 {
    var parts = std.ArrayList([]const u8).empty;
    defer {
        for (parts.items) |p| allocator.free(p);
        parts.deinit(allocator);
    }

    const sv = style.styleValue;

    const name_prefix = if (style.name) |name|
        try std.fmt.allocPrint(allocator, "{s}:{{", .{name})
    else
        try std.fmt.allocPrint(allocator, "e{}:{{", .{style.styleNumber});
    try parts.append(allocator, name_prefix);

    // Type
    const st = sv.styleType orelse .vec2d;
    try parts.append(allocator, try allocator.dupe(u8, @tagName(st)));

    // Coordinate system
    const cs = sv.coordinateSystem orelse .xy;
    try parts.append(allocator, try std.fmt.allocPrint(allocator, " {s}", .{@tagName(cs)}));

    // Orientation
    const co = sv.coordinateOrientation orelse .fixed;
    try parts.append(allocator, try std.fmt.allocPrint(allocator, " {s}", .{@tagName(co)}));

    // Plot steps
    const ps = sv.plotSteps orelse .last;
    try parts.append(allocator, try std.fmt.allocPrint(allocator, " {s}", .{@tagName(ps)}));

    // Attributes
    if (st == .pt2d) {
        const attrs = sv.attributes orelse Attributes{};
        const psh = attrs.pointShape orelse PointShapeType.defaultPointShapeType();
        const psz = attrs.pointSize orelse PointSizeType.defaultPointSizeType();
        const pc = attrs.lineColor orelse LineColorType.defaultLineColorType();
        const po = attrs.lineOpacity orelse LineOpacityType.defaultLineOpacityType();

        try parts.append(allocator, try std.fmt.allocPrint(allocator, " [sh:{s}, s:{}, c: {s}, o: {}]}}", .{
            @tagName(psh.value),
            psz.value,
            @tagName(pc.value),
            po.value,
        }));

        return try std.mem.join(allocator, "", parts.items);
    }

    const attrs = sv.attributes orelse Attributes{};
    const l = attrs.lineWidth orelse LineWidthType.defaultLineWidthType();
    const lc = attrs.lineColor orelse LineColorType.defaultLineColorType();
    const lo = attrs.lineOpacity orelse LineOpacityType.defaultLineOpacityType();
    const le = attrs.lineCap orelse LineCapType.defaultLineCapType();
    const lj = attrs.lineJoin orelse LineJoinType.defaultLineJoinType();
    const has_dashing = attrs.lineDashing != null;
    const ld = attrs.lineDashing orelse LineDashingType.defaultLineDashingType();

    try parts.append(allocator, try std.fmt.allocPrint(allocator, " [l:{}, c: {s}, o: {}, e:{s}, j: {s}, d:", .{
        l.value,
        @tagName(lc.value),
        lo.value,
        @tagName(le.value),
        @tagName(lj.value),
    }));

    // Dashing pattern
    if (has_dashing and ld.onOff.len > 0) {
        var dash_parts = std.ArrayList([]const u8).empty;
        defer {
            for (dash_parts.items) |p| allocator.free(p);
            dash_parts.deinit(allocator);
        }
        try dash_parts.append(allocator, try allocator.dupe(u8, "["));
        for (ld.onOff, 0..) |v, i| {
            if (i > 0) try dash_parts.append(allocator, try allocator.dupe(u8, ", "));
            try dash_parts.append(allocator, try std.fmt.allocPrint(allocator, "{}", .{v}));
        }
        try dash_parts.append(allocator, try allocator.dupe(u8, "]"));
        const dash_str = try std.mem.join(allocator, "", dash_parts.items);
        try parts.append(allocator, dash_str);
        try parts.append(allocator, try std.fmt.allocPrint(allocator, " {}]}}", .{ld.offset}));
    } else {
        try parts.append(allocator, try allocator.dupe(u8, "none]}"));
    }

    return try std.mem.join(allocator, "", parts.items);
}

/// Serializes a slice of resolved styles into a single comma-separated string.
pub fn serializeStyles(allocator: std.mem.Allocator, styles: []const Style) ![]const u8 {
    var parts = std.ArrayList([]const u8).empty;
    defer {
        for (parts.items) |p| allocator.free(p);
        parts.deinit(allocator);
    }

    for (styles, 0..) |style, i| {
        if (i > 0) try parts.append(allocator, try allocator.dupe(u8, ", "));
        const s = try serializeStyle(allocator, style);
        try parts.append(allocator, s);
    }

    return try std.mem.join(allocator, "", parts.items);
}
