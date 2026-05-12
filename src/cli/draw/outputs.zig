const std = @import("std");
const testing = std.testing;

const mecha = @import("mecha");

const common = @import("common.zig");
const inputs = @import("inputs.zig");
const Styles = @import("styles.zig");

const CoordinateOrientation = Styles.CoordinateOrientation;
const PlotSteps = Styles.PlotSteps;

fn rotateAround(angle_degrees: f32, around_x: f32, around_y: f32, point_x: f32, point_y: f32) inputs.Point {
    const phi = angle_degrees * std.math.pi / 180.0;
    const dx = point_x - around_x;
    const dy = point_y - around_y;
    const x_rotated = dx * @cos(phi) - dy * @sin(phi) + around_x;
    const y_rotated = dx * @sin(phi) + dy * @cos(phi) + around_y;
    return inputs.Point{ .x = x_rotated, .y = y_rotated };
}

fn mirrorPointOverLine(what: inputs.Point, over: inputs.Line, accuracy: ?u8) inputs.Point {
    if (over.a == 0.0) {
        const mirror_x = -over.c / over.b;
        const mirrored_x = 2.0 * mirror_x - what.x;
        if (accuracy) |acc| {
            const factor = std.math.pow(f32, 10, @as(f32, @floatFromInt(acc)));
            return .{ .x = @round(mirrored_x * factor) / factor, .y = what.y };
        }
        return .{ .x = mirrored_x, .y = what.y };
    }
    if (over.b == 0.0) {
        const mirror_y = over.c / over.a;
        const mirrored_y = 2.0 * mirror_y - what.y;
        if (accuracy) |acc| {
            const factor = std.math.pow(f32, 10, @as(f32, @floatFromInt(acc)));
            return .{ .x = what.x, .y = @round(mirrored_y * factor) / factor };
        }
        return .{ .x = what.x, .y = mirrored_y };
    }
    const denom = over.a * over.a + over.b * over.b;
    const xL = (what.y * over.a * over.b + what.x * over.a * over.a - over.c * over.b) / denom;
    const yL = (over.b / over.a) * xL + (over.c / over.a);
    var mirrored_x: f32 = undefined;
    var mirrored_y: f32 = undefined;
    if (what.x > xL) {
        const delta = what.x - xL;
        mirrored_x = xL - delta;
    } else if (what.x == xL) {
        mirrored_x = what.x;
    } else {
        const delta = xL - what.x;
        mirrored_x = xL + delta;
    }
    if (what.y < yL) {
        const delta = yL - what.y;
        mirrored_y = yL + delta;
    } else if (what.y == yL) {
        mirrored_y = what.y;
    } else {
        const delta = what.y - yL;
        mirrored_y = yL - delta;
    }
    if (accuracy) |acc| {
        const factor = std.math.pow(f32, 10, @as(f32, @floatFromInt(acc)));
        return .{ .x = @round(mirrored_x * factor) / factor, .y = @round(mirrored_y * factor) / factor };
    }
    return .{ .x = mirrored_x, .y = mirrored_y };
}

const Line = struct {
    a: f32,
    b: f32,
    c: f32,

    fn fromTwoPoints(x1: f32, y1: f32, x2: f32, y2: f32) Line {
        const a = y1 - y2;
        const b = x2 - x1;
        var c = -a * x1 - b * y1;
        if (@abs(c) < 1e-10) c = 0;
        return Line{ .a = a, .b = b, .c = c };
    }

    fn parallelDistance(d: f32, other: *const Line) Line {
        const denom = @sqrt(other.a * other.a + other.b * other.b);
        const offset = d * denom;
        return Line{ .a = other.a, .b = other.b, .c = other.c - offset };
    }

    fn intersection(l1: *const Line, l2: *const Line) inputs.Point {
        const det = l1.a * l2.b - l2.a * l1.b;
        if (@abs(det) < 1e-10) {
            return inputs.Point{ .x = 0, .y = 0 };
        }
        var x = (l1.b * l2.c - l2.b * l1.c) / det;
        var y = (l2.a * l1.c - l1.a * l2.c) / det;
        if (@abs(x) < 1e-10) x = 0;
        if (@abs(y) < 1e-10) y = 0;
        return inputs.Point{ .x = x, .y = y };
    }
};

////Types

//Handling the name of output
pub const Output = struct {
    name: []const u8,
};

const Composite = union(enum) {
    train: *const Train,
    hook: *const Hook,
};

const CompositeInside = union(enum) {
    stop: OneArgFunctionPartial,
    inside: *const Composite,
};

//Train like in J
//(op1 op2 op3) x == (op1 x) op2 (op3 x)
pub const Train = struct {
    left: CompositeInside,
    middle: TwoArgCombinator,
    right: CompositeInside,
};

//Hook like in J
//(op1 op2) x == (op1 x) op2 x
pub const Hook = struct {
    left: CompositeInside,
    right: TwoArgCombinator,
};

//Compose (&) like in J
//(op1 & op2 & op3) x == op1 (op2 (op3 x))
pub const Compose = struct {
    ops: []const OneArgFunctionPartial,
};

pub const TwoArgCombinator = enum {
    on, //the left arg is above the right arg
    under, //the left arg is under the right arg
    with, //the left arg is on the same layer level as the right arg
};

pub const OneArgFunctionPartial = union(enum) {
    none,
    anchor: AnchorPartial,
    rotate: RotatePartial,
    scale: ScalePartial,
    mirror: MirrorPartial,
};

//Anchor obj to point
pub const AnchorPartial = struct {
    point: GeneralPoint,
};

//Rotate by phi
//By default counter-clock wise if phi is positive. Point against which rotation occur must be specified.
pub const RotateArg = struct {
    phi: f32,
    point: GeneralPoint,
};

//Needs to be called with proper data
pub const RotatePartial = struct {
    elements: []const RotateArg, //each rotation arg works on each element of [elem1, elem2,...]
};

//Scale by vec
pub const ScaleArg = struct {
    translation: inputs.Vector,
};

//Needs to be called with proper data
pub const ScalePartial = struct {
    elements: []const ScaleArg, //each scale arg works on each element of [elem1, elem2,...]
};

//Mirror over line
pub const MirrorPartial = struct {
    line: inputs.Line,
};

pub const ElementReference = union(enum) {
    self,
    other: []const u8,
};

pub const ElementFraction = struct {
    fromStart: i16, //in % from the start of the reference element
    element: ElementReference,
};

const GeneralPoint = union(enum) {
    point: inputs.Point,
    beginning: ElementReference,
    end: ElementReference,
    middle: ElementReference,
    fraction: ElementFraction,
};

//Parsers
const outputSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
const outputCharacterParser =
    mecha.oneOf(.{ mecha.ascii.range('a', 'z'), mecha.ascii.range('A', 'Z'), mecha.ascii.range('0', '9') });
const outputNameParser = mecha.many(outputCharacterParser, .{ .collect = false });
const many_outputNameParser = mecha.many(outputNameParser, .{ .collect = true, .separator = outputSeparatorParser });
const outputsParserRaw =
    mecha.combine(.{ common.skipOpenBracket, many_outputNameParser, common.skipCloseBracket });
const outputsParserRawP = @TypeOf(outputsParserRaw);
fn toOutputsParser(arena: std.mem.Allocator, names: outputsParserRawP.T) mecha.ConvertError![]Output {
    var arr = try arena.alloc(Output, names.len);
    var ix: u8 = 0;
    for (names) |theRes| {
        arr[ix] = Output{ .name = theRes };
        ix += 1;
    }
    arena.free(names);
    return arr;
}
const outputsParser = outputsParserRaw.convert(toOutputsParser);

test "outputsParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try outputsParser.parse(a, "(out)");
    const o1 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const output1 = [1]Output{o1};
    try testing.expectEqualDeep(&output1, r1.value.ok[0..1]);

    const r2 = try outputsParser.parse(a, "( out )");
    const o2 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const output2 = [1]Output{o2};
    try testing.expectEqualDeep(&output2, r2.value.ok[0..1]);

    const r3 = try outputsParser.parse(a, "( out1, out2 )");
    const o3a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const o3b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const output3 = [2]Output{ o3a, o3b };
    try testing.expectEqualDeep(&output3, r3.value.ok[0..2]);

    const r4 = try outputsParser.parse(a, "( out1, out2, txt1 )");
    const o4a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const o4b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const o4c = Output{ .name = &[_]u8{ 't', 'x', 't', '1' } };
    const output4 = [3]Output{ o4a, o4b, o4c };
    try testing.expectEqualDeep(&output4, r4.value.ok[0..3]);
}

const selfParser = mecha.string("self").map(struct {
    fn toSelf(a: anytype) mecha.ConvertError!ElementReference {
        _ = a;
        return .self;
    }
}.toSelf);

const otherParser = common.nameParser.map(struct {
    fn toOther(a: anytype) mecha.ConvertError!ElementReference {
        return ElementReference{ .other = a };
    }
}.toOther);

const elementReferenceParser = mecha.oneOf(.{
    selfParser,
    otherParser,
});

test "elementReferenceParser" {
    const fa = testing.failing_allocator;

    const r1 = try elementReferenceParser.parse(fa, "self");
    try testing.expectEqual(.self, r1.value.ok);

    const r2 = try elementReferenceParser.parse(fa, "v2");
    try testing.expectEqual(ElementReference{ .other = "v2" }, r2.value.ok);

    const r3 = try elementReferenceParser.parse(fa, "line211");
    try testing.expectEqual(ElementReference{ .other = "line211" }, r3.value.ok);
}

const signedDigits = mecha.combine(.{
    mecha.utf8.char('-').opt(),
    mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1 }).asStr(),
}).map(struct {
    fn toSigned(a: anytype) mecha.ConvertError!i16 {
        const sign: i16 = if (a[0]) |_| -1 else 1;
        const num = std.fmt.parseInt(i16, a[1], 10) catch return error.ConversionFailed;
        return num * sign;
    }
}.toSigned);

const elementFractionParser = mecha.combine(.{
    common.skipWhitespace,
    signedDigits,
    common.skipWhitespace,
    mecha.utf8.char('%').discard(),
    common.skipWhitespace,
    elementReferenceParser,
    common.skipWhitespace,
}).map(struct {
    fn toElementFraction(a: anytype) mecha.ConvertError!ElementFraction {
        return ElementFraction{ .fromStart = try a[0], .element = try a[1] };
    }
}.toElementFraction);

test "elementFractionParser" {
    const fa = testing.failing_allocator;

    const r1 = try elementFractionParser.parse(fa, "0% self");
    const o1 = ElementFraction{ .fromStart = 0, .element = .self };
    try testing.expectEqualDeep(o1, r1.value.ok);

    const r2 = try elementFractionParser.parse(fa, "10% self");
    const o2 = ElementFraction{ .fromStart = 10, .element = .self };
    try testing.expectEqualDeep(o2, r2.value.ok);

    const r3 = try elementFractionParser.parse(fa, "-10% self");
    const o3 = ElementFraction{ .fromStart = -10, .element = .self };
    try testing.expectEqualDeep(o3, r3.value.ok);

    const r4 = try elementFractionParser.parse(fa, "0% v333");
    const o4 = ElementFraction{ .fromStart = 0, .element = ElementReference{ .other = "v333" } };
    try testing.expectEqualDeep(o4, r4.value.ok);

    const r5 = try elementFractionParser.parse(fa, "101% some");
    const o5 = ElementFraction{ .fromStart = 101, .element = ElementReference{ .other = "some" } };
    try testing.expectEqualDeep(o5, r5.value.ok);

    const r6 = try elementFractionParser.parse(fa, "-33% dot1");
    const o6 = ElementFraction{ .fromStart = -33, .element = ElementReference{ .other = "dot1" } };
    try testing.expectEqualDeep(o6, r6.value.ok);

    const r7 = try elementFractionParser.parse(fa, " -33 % dot1 ");
    const o7 = ElementFraction{ .fromStart = -33, .element = ElementReference{ .other = "dot1" } };
    try testing.expectEqualDeep(o7, r7.value.ok);

    const r8 = try elementFractionParser.parse(fa, " -033 % dot1 ");
    const o8 = ElementFraction{ .fromStart = -33, .element = ElementReference{ .other = "dot1" } };
    try testing.expectEqualDeep(o8, r8.value.ok);
}

const fractionGPParser = mecha.combine(.{
    common.skipOpenBracket,
    elementFractionParser,
    common.skipCloseBracket,
}).convert(struct {
    fn toFraction(_: std.mem.Allocator, res: anytype) mecha.ConvertError!GeneralPoint {
        return GeneralPoint{ .fraction = try res };
    }
}.toFraction);

const beginningGPParser = mecha.combine(.{
    common.skipOpenBracket,
    mecha.oneOf(.{
        mecha.string("beginning"),
        mecha.string("beg"),
        mecha.string("b"),
    }).discard(),
    common.skipWhitespace,
    elementReferenceParser,
    common.skipCloseBracket,
}).convert(struct {
    fn toBeginning(_: std.mem.Allocator, a: anytype) mecha.ConvertError!GeneralPoint {
        return GeneralPoint{ .beginning = try a };
    }
}.toBeginning);

const endGPParser = mecha.combine(.{
    common.skipOpenBracket,
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("end"),
        mecha.string("e"),
    }).discard(),
    common.skipWhitespace,
    elementReferenceParser,
    common.skipCloseBracket,
}).convert(struct {
    fn toEnd(_: std.mem.Allocator, a: anytype) mecha.ConvertError!GeneralPoint {
        return GeneralPoint{ .end = try a };
    }
}.toEnd);

const middleGPParser = mecha.combine(.{
    common.skipOpenBracket,
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("middle"),
        mecha.string("mid"),
        mecha.string("m"),
    }).discard(),
    common.skipWhitespace,
    elementReferenceParser,
    common.skipCloseBracket,
}).convert(struct {
    fn toMiddle(_: std.mem.Allocator, a: anytype) mecha.ConvertError!GeneralPoint {
        return GeneralPoint{ .middle = try a };
    }
}.toMiddle);

const pointParserLocal = mecha.combine(.{
    common.skipOpenBracket,
    common.floatFromDecimal,
    common.skipComma,
    common.floatFromDecimal,
    common.skipCloseBracket,
}).convert(struct {
    fn toPoint(_: std.mem.Allocator, a: anytype) mecha.ConvertError!inputs.Point {
        return inputs.Point{ .x = a[0], .y = a[1] };
    }
}.toPoint);

const pointGPParser = mecha.combine(.{
    common.skipOpenBrace,
    pointParserLocal,
    common.skipCloseBrace,
}).convert(struct {
    fn toPoint(_: std.mem.Allocator, a: anytype) mecha.ConvertError!GeneralPoint {
        return GeneralPoint{ .point = a };
    }
}.toPoint);

const generalPointParser = mecha.oneOf(.{
    fractionGPParser,
    beginningGPParser,
    endGPParser,
    middleGPParser,
    pointGPParser,
});

test "generalPointParser" {
    const fa = testing.failing_allocator;

    const r1 = try generalPointParser.parse(fa, "(0% self)");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const o1 = GeneralPoint{ .fraction = f1 };
    try testing.expectEqualDeep(o1, r1.value.ok);

    const r2 = try generalPointParser.parse(fa, "(10% self)");
    const f2 = ElementFraction{ .fromStart = 10, .element = .self };
    const o2 = GeneralPoint{ .fraction = f2 };
    try testing.expectEqualDeep(o2, r2.value.ok);

    const r3 = try generalPointParser.parse(fa, "( beg self)");
    const o3 = GeneralPoint{ .beginning = .self };
    try testing.expectEqualDeep(o3, r3.value.ok);

    const r4 = try generalPointParser.parse(fa, "(beginning dot1)");
    const o4 = GeneralPoint{ .beginning = ElementReference{ .other = "dot1" } };
    try testing.expectEqualDeep(o4, r4.value.ok);

    const r5 = try generalPointParser.parse(fa, "(b dot1)");
    const o5 = GeneralPoint{ .beginning = ElementReference{ .other = "dot1" } };
    try testing.expectEqualDeep(o5, r5.value.ok);

    const r6 = try generalPointParser.parse(fa, "(end     self)");
    const o6 = GeneralPoint{ .end = .self };
    try testing.expectEqualDeep(o6, r6.value.ok);

    const r7 = try generalPointParser.parse(fa, "(e vec1)");
    const o7 = GeneralPoint{ .end = ElementReference{ .other = "vec1" } };
    try testing.expectEqualDeep(o7, r7.value.ok);

    const r8 = try generalPointParser.parse(fa, "(m vec1)");
    const o8 = GeneralPoint{ .middle = ElementReference{ .other = "vec1" } };
    try testing.expectEqualDeep(o8, r8.value.ok);

    const r9 = try generalPointParser.parse(fa, "(mid vec1)");
    const o9 = GeneralPoint{ .middle = ElementReference{ .other = "vec1" } };
    try testing.expectEqualDeep(o9, r9.value.ok);

    const r10 = try generalPointParser.parse(fa, "(middle vec1)");
    const o10 = GeneralPoint{ .middle = ElementReference{ .other = "vec1" } };
    try testing.expectEqualDeep(o10, r10.value.ok);

    const r11 = try generalPointParser.parse(fa, "{(-12,2.1)} ");
    const p11 = inputs.Point{ .x = -12.0, .y = 2.1 };
    const o11 = GeneralPoint{ .point = p11 };
    try testing.expectEqualDeep(o11, r11.value.ok);
}

const rotationArgParser = mecha.combine(.{
    common.floatFromDecimal,
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("around"),
        mecha.string("a"),
    }).discard(),
    common.skipWhitespace,
    generalPointParser,
}).convert(struct {
    fn toRotateArg(_: std.mem.Allocator, a: anytype) mecha.ConvertError!RotateArg {
        return RotateArg{ .phi = a[0], .point = a[1] };
    }
}.toRotateArg);

test "rotationArgParser" {
    const fa = testing.failing_allocator;

    const r1 = try rotationArgParser.parse(fa, "90 around (0% self)");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const p1 = GeneralPoint{ .fraction = f1 };
    const o1 = RotateArg{ .phi = 90.0, .point = p1 };
    try testing.expectEqualDeep(o1, r1.value.ok);

    const r2 = try rotationArgParser.parse(fa, "-120 a (10% self)");
    const f2 = ElementFraction{ .fromStart = 10, .element = .self };
    const p2 = GeneralPoint{ .fraction = f2 };
    const o2 = RotateArg{ .phi = -120.0, .point = p2 };
    try testing.expectEqualDeep(o2, r2.value.ok);

    const r3 = try rotationArgParser.parse(fa, "0 a ( beg self)");
    const p3 = GeneralPoint{ .beginning = .self };
    const o3 = RotateArg{ .phi = 0.0, .point = p3 };
    try testing.expectEqualDeep(o3, r3.value.ok);

    const r4 = try rotationArgParser.parse(fa, "-30.5 around (beginning dot1)");
    const p4 = GeneralPoint{ .beginning = ElementReference{ .other = "dot1" } };
    const o4 = RotateArg{ .phi = -30.5, .point = p4 };
    try testing.expectEqualDeep(o4, r4.value.ok);

    const r5 = try rotationArgParser.parse(fa, "45 around (middle vec1)");
    const p5 = GeneralPoint{ .middle = ElementReference{ .other = "vec1" } };
    const o5 = RotateArg{ .phi = 45.0, .point = p5 };
    try testing.expectEqualDeep(o5, r5.value.ok);

    const r6 = try rotationArgParser.parse(fa, "-1234.9 around {(-12,2.1)} ");
    const p6 = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp6 = GeneralPoint{ .point = p6 };
    const o6 = RotateArg{ .phi = -1234.9, .point = gp6 };
    try testing.expectEqualDeep(o6, r6.value.ok);
}

const rotatePartialParserRawWithout = mecha.combine(.{
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("rotate"),
        mecha.string("r"),
    }).discard(),
    common.skipWhitespace,
    common.skipOpenSquare,
    rotationArgParser.many(.{ .collect = true, .separator = common.skipComma }),
    common.skipCloseSquare,
});
const rotatePartialParserRawWith = mecha.combine(.{
    common.skipOpenBracket,
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("rotate"),
        mecha.string("r"),
    }).discard(),
    common.skipWhitespace,
    common.skipOpenSquare,
    rotationArgParser.many(.{ .collect = true, .separator = common.skipComma }),
    common.skipCloseSquare,
    common.skipCloseBracket,
});

const rotatePartialParserRaw = mecha.oneOf(.{
    rotatePartialParserRawWith,
    rotatePartialParserRawWithout,
});
const rotatePartialParserRawP = @TypeOf(rotatePartialParserRaw);
fn toRotatePartial(_: std.mem.Allocator, res: rotatePartialParserRawP.T) mecha.ConvertError!RotatePartial {
    _ = undefined; // unused arena
    return RotatePartial{ .elements = res };
}
const rotatePartialParser = rotatePartialParserRaw.convert(toRotatePartial);

test "rotatePartialParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try rotatePartialParser.parse(a, "rotate [90 a (0% self)]");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const p1 = GeneralPoint{ .fraction = f1 };
    const r1arg = RotateArg{ .phi = 90.0, .point = p1 };
    try testing.expectEqual(@as(usize, 1), r1.value.ok.elements.len);
    try testing.expectEqualDeep(r1arg, r1.value.ok.elements[0]);

    const r2 = try rotatePartialParser.parse(a, "r [-120 a (10% self)]");
    const f2 = ElementFraction{ .fromStart = 10, .element = .self };
    const p2 = GeneralPoint{ .fraction = f2 };
    const r2arg = RotateArg{ .phi = -120.0, .point = p2 };
    try testing.expectEqual(@as(usize, 1), r2.value.ok.elements.len);
    try testing.expectEqualDeep(r2arg, r2.value.ok.elements[0]);

    const r3 = try rotatePartialParser.parse(a, " rotate [0 around ( beg self) , -1234.9 a {(-12,2.1)} ]");
    const p3a = GeneralPoint{ .beginning = .self };
    const r3a = RotateArg{ .phi = 0.0, .point = p3a };
    const p3b = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp3 = GeneralPoint{ .point = p3b };
    const r3b = RotateArg{ .phi = -1234.9, .point = gp3 };
    try testing.expectEqual(@as(usize, 2), r3.value.ok.elements.len);
    try testing.expectEqualDeep(r3a, r3.value.ok.elements[0]);
    try testing.expectEqualDeep(r3b, r3.value.ok.elements[1]);

    const r4 = try rotatePartialParser.parse(a, "(r [-120 a (10% self)])");
    const f4 = ElementFraction{ .fromStart = 10, .element = .self };
    const p4 = GeneralPoint{ .fraction = f4 };
    const r4arg = RotateArg{ .phi = -120.0, .point = p4 };
    try testing.expectEqual(@as(usize, 1), r4.value.ok.elements.len);
    try testing.expectEqualDeep(r4arg, r4.value.ok.elements[0]);
}

const scalePartialParserRawWithout = mecha.combine(.{
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("scale by"),
        mecha.string("s by"),
        mecha.string("scale"),
        mecha.string("s"),
    }).discard(),
    common.skipWhitespace,
    inputs.vectorsParser,
    common.skipWhitespace,
});
const scalePartialParserRawWith = mecha.combine(.{
    common.skipOpenBracket,
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("scale by"),
        mecha.string("s by"),
        mecha.string("scale"),
        mecha.string("s"),
    }).discard(),
    common.skipWhitespace,
    inputs.vectorsParser,
    common.skipWhitespace,
    common.skipCloseBracket,
});

const scalePartialParserRaw = mecha.oneOf(.{
    scalePartialParserRawWith,
    scalePartialParserRawWithout,
});
const scalePartialParserRawP = @TypeOf(scalePartialParserRaw);
fn toScalePartial(arena: std.mem.Allocator, res: scalePartialParserRawP.T) mecha.ConvertError!ScalePartial {
    var args = try arena.alloc(ScaleArg, res.len);
    for (res, 0..) |v, i| {
        args[i] = ScaleArg{ .translation = v };
    }
    arena.free(res);
    return ScalePartial{ .elements = args };
}
const scalePartialParser = scalePartialParserRaw.convert(toScalePartial);

test "scalePartialParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try scalePartialParser.parse(a, "scale [[2,3]]");
    const v1 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s1 = ScaleArg{ .translation = v1 };
    try testing.expectEqual(@as(usize, 1), r1.value.ok.elements.len);
    try testing.expectEqualDeep(s1, r1.value.ok.elements[0]);

    const r2 = try scalePartialParser.parse(a, "s by [[2.1,3.1]]");
    const v2 = inputs.Vector{ .x = 2.1, .y = 3.1 };
    const s2 = ScaleArg{ .translation = v2 };
    try testing.expectEqual(@as(usize, 1), r2.value.ok.elements.len);
    try testing.expectEqualDeep(s2, r2.value.ok.elements[0]);

    const r3 = try scalePartialParser.parse(a, "s by [[2.1,3.1], [-10.0, 1.1e+03]]");
    const v3a = inputs.Vector{ .x = 2.1, .y = 3.1 };
    const v3b = inputs.Vector{ .x = -10.0, .y = 1100.0 };
    const s3a = ScaleArg{ .translation = v3a };
    const s3b = ScaleArg{ .translation = v3b };
    try testing.expectEqual(@as(usize, 2), r3.value.ok.elements.len);
    try testing.expectEqualDeep(s3a, r3.value.ok.elements[0]);
    try testing.expectEqualDeep(s3b, r3.value.ok.elements[1]);

    const r4 = try scalePartialParser.parse(a, "(s by [[2.1,3.1]])");
    const v4 = inputs.Vector{ .x = 2.1, .y = 3.1 };
    const s4 = ScaleArg{ .translation = v4 };
    try testing.expectEqual(@as(usize, 1), r4.value.ok.elements.len);
    try testing.expectEqualDeep(s4, r4.value.ok.elements[0]);
}

const anchorPartialParserRawWithout = mecha.combine(.{
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("anchor"),
        mecha.string("a"),
    }).discard(),
    common.skipWhitespace,
    generalPointParser,
});
const anchorPartialParserRawWith = mecha.combine(.{
    common.skipOpenBracket,
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("anchor"),
        mecha.string("a"),
    }).discard(),
    common.skipWhitespace,
    generalPointParser,
    common.skipWhitespace,
    common.skipCloseBracket,
});

const anchorPartialParserRaw = mecha.oneOf(.{
    anchorPartialParserRawWith,
    anchorPartialParserRawWithout,
});
const anchorPartialParserRawP = @TypeOf(anchorPartialParserRaw);
fn toAnchorPartial(_: std.mem.Allocator, a: anytype) mecha.ConvertError!AnchorPartial {
    return AnchorPartial{ .point = a };
}
const anchorPartialParser = anchorPartialParserRaw.convert(toAnchorPartial);

test "anchorPartialParser" {
    const fa = testing.failing_allocator;

    const r1 = try anchorPartialParser.parse(fa, "anchor (0% self)");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const o1 = AnchorPartial{ .point = gp1 };
    try testing.expectEqualDeep(o1, r1.value.ok);

    const r2 = try anchorPartialParser.parse(fa, "a (10% self)");
    const f2 = ElementFraction{ .fromStart = 10, .element = .self };
    const gp2 = GeneralPoint{ .fraction = f2 };
    const o2 = AnchorPartial{ .point = gp2 };
    try testing.expectEqualDeep(o2, r2.value.ok);

    const r3 = try anchorPartialParser.parse(fa, "a ( beg self)");
    const gp3 = GeneralPoint{ .beginning = .self };
    const o3 = AnchorPartial{ .point = gp3 };
    try testing.expectEqualDeep(o3, r3.value.ok);

    const r4 = try anchorPartialParser.parse(fa, "anchor (beginning dot1)");
    const gp4 = GeneralPoint{ .beginning = ElementReference{ .other = "dot1" } };
    const o4 = AnchorPartial{ .point = gp4 };
    try testing.expectEqualDeep(o4, r4.value.ok);

    const r5 = try anchorPartialParser.parse(fa, "a (b dot1)");
    const gp5 = GeneralPoint{ .beginning = ElementReference{ .other = "dot1" } };
    const o5 = AnchorPartial{ .point = gp5 };
    try testing.expectEqualDeep(o5, r5.value.ok);

    const r6 = try anchorPartialParser.parse(fa, "a (end     self)");
    const gp6 = GeneralPoint{ .end = .self };
    const o6 = AnchorPartial{ .point = gp6 };
    try testing.expectEqualDeep(o6, r6.value.ok);

    const r7 = try anchorPartialParser.parse(fa, "a (e vec1)");
    const gp7 = GeneralPoint{ .end = ElementReference{ .other = "vec1" } };
    const o7 = AnchorPartial{ .point = gp7 };
    try testing.expectEqualDeep(o7, r7.value.ok);

    const r8 = try anchorPartialParser.parse(fa, "a (m vec1)");
    const gp8 = GeneralPoint{ .middle = ElementReference{ .other = "vec1" } };
    const o8 = AnchorPartial{ .point = gp8 };
    try testing.expectEqualDeep(o8, r8.value.ok);

    const r9 = try anchorPartialParser.parse(fa, "anchor (mid vec1)");
    const gp9 = GeneralPoint{ .middle = ElementReference{ .other = "vec1" } };
    const o9 = AnchorPartial{ .point = gp9 };
    try testing.expectEqualDeep(o9, r9.value.ok);

    const r10 = try anchorPartialParser.parse(fa, "anchor (middle vec1)");
    const gp10 = GeneralPoint{ .middle = ElementReference{ .other = "vec1" } };
    const o10 = AnchorPartial{ .point = gp10 };
    try testing.expectEqualDeep(o10, r10.value.ok);

    const r11 = try anchorPartialParser.parse(fa, "anchor {(-12,2.1)} ");
    const p11 = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp11 = GeneralPoint{ .point = p11 };
    const o11 = AnchorPartial{ .point = gp11 };
    try testing.expectEqualDeep(o11, r11.value.ok);

    const r12 = try anchorPartialParser.parse(fa, "(a ( beg self))");
    const gp12 = GeneralPoint{ .beginning = .self };
    const o12 = AnchorPartial{ .point = gp12 };
    try testing.expectEqualDeep(o12, r12.value.ok);

    const r13 = try anchorPartialParser.parse(fa, "( anchor {(-12,2.1)} )");
    const p13 = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp13 = GeneralPoint{ .point = p13 };
    const o13 = AnchorPartial{ .point = gp13 };
    try testing.expectEqualDeep(o13, r13.value.ok);
}

const mirrorLineParser = mecha.combine(.{
    common.skipOpenBracket,
    inputs.lineParser,
    common.skipCloseBracket,
}).convert(struct {
    fn toLine(_: std.mem.Allocator, a: inputs.Line) mecha.ConvertError!inputs.Line {
        return a;
    }
}.toLine);

const mirrorPartialParserRawWithout = mecha.combine(.{
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("mirror"),
        mecha.string("m"),
    }).discard(),
    common.skipWhitespace,
    mirrorLineParser,
});
const mirrorPartialParserRawWith = mecha.combine(.{
    common.skipOpenBracket,
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("mirror"),
        mecha.string("m"),
    }).discard(),
    common.skipWhitespace,
    mirrorLineParser,
    common.skipWhitespace,
    common.skipCloseBracket,
});
const mirrorPartialParserRaw = mecha.oneOf(.{
    mirrorPartialParserRawWith,
    mirrorPartialParserRawWithout,
});
const mirrorPartialParserRawP = @TypeOf(mirrorPartialParserRaw);
fn toMirrorPartial(_: std.mem.Allocator, res: mirrorPartialParserRawP.T) mecha.ConvertError!MirrorPartial {
    return MirrorPartial{ .line = res };
}
const mirrorPartialParser = mirrorPartialParserRaw.convert(toMirrorPartial);

test "mirrorPartialParser" {
    const fa = testing.failing_allocator;

    const r1 = try mirrorPartialParser.parse(fa, "mirror (y=2x+1)");
    const l1 = inputs.Line{ .a = 1.0, .b = 2.0, .c = 1.0 };
    const m1 = MirrorPartial{ .line = l1 };
    try testing.expectEqualDeep(m1, r1.value.ok);

    const r2 = try mirrorPartialParser.parse(fa, "mirror ( y=2x+1 )");
    const l2 = inputs.Line{ .a = 1.0, .b = 2.0, .c = 1.0 };
    const m2 = MirrorPartial{ .line = l2 };
    try testing.expectEqualDeep(m2, r2.value.ok);

    const r3 = try mirrorPartialParser.parse(fa, "m (y=12x+1.1)");
    const l3 = inputs.Line{ .a = 1.0, .b = 12.0, .c = 1.1 };
    const m3 = MirrorPartial{ .line = l3 };
    try testing.expectEqualDeep(m3, r3.value.ok);
}

const twoArgCombinatorParser =
    mecha.combine(.{ common.skipWhitespace, mecha.convert(mecha.oneOf(.{ mecha.string("on"), mecha.string("under"), mecha.string("with") }).asStr(), mecha.toEnum(TwoArgCombinator)) });

test "twoArgCombinatorParser" {
    const fa = testing.failing_allocator;

    const r1 = try twoArgCombinatorParser.parse(fa, "on");
    try testing.expectEqual(.on, r1.value.ok);

    const r2 = try twoArgCombinatorParser.parse(fa, " under");
    try testing.expectEqual(.under, r2.value.ok);

    const r3 = try twoArgCombinatorParser.parse(fa, "with");
    try testing.expectEqual(.with, r3.value.ok);

    const r4 = try twoArgCombinatorParser.parse(fa, "rad");
    try testing.expectEqual(0, r4.index);
}

fn toRotatePartialUnion(_: std.mem.Allocator, res: rotatePartialParserRawP.T) mecha.ConvertError!OneArgFunctionPartial {
    const r = RotatePartial{ .elements = res };
    return OneArgFunctionPartial{ .rotate = r };
}
const rotatePartialUnionParser = rotatePartialParserRaw.convert(toRotatePartialUnion);
fn toScalePartialUnion(arena: std.mem.Allocator, res: scalePartialParserRawP.T) mecha.ConvertError!OneArgFunctionPartial {
    var args = try arena.alloc(ScaleArg, res.len);
    for (res, 0..) |v, i| {
        args[i] = ScaleArg{ .translation = v };
    }
    arena.free(res);
    const s = ScalePartial{ .elements = args };
    return OneArgFunctionPartial{ .scale = s };
}
const scalePartialUnionParser = scalePartialParserRaw.convert(toScalePartialUnion);
fn toAnchorPartialUnion(_: std.mem.Allocator, res: anytype) mecha.ConvertError!OneArgFunctionPartial {
    const p = AnchorPartial{ .point = res };
    return OneArgFunctionPartial{ .anchor = p };
}
const anchorPartialUnionParser = anchorPartialParserRaw.convert(toAnchorPartialUnion);
fn toMirrorPartialUnion(_: std.mem.Allocator, res: MirrorPartial) mecha.ConvertError!OneArgFunctionPartial {
    return OneArgFunctionPartial{ .mirror = res };
}
const mirrorPartialUnionParser = mirrorPartialParser.convert(toMirrorPartialUnion);

const oneArgFunctionPartialParser = mecha.oneOf(.{
    anchorPartialUnionParser,
    rotatePartialUnionParser,
    scalePartialUnionParser,
    mirrorPartialUnionParser,
});

test "oneArgFunctionPartialParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try oneArgFunctionPartialParser.parse(a, "anchor (0% self)");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const p1 = AnchorPartial{ .point = gp1 };
    const o1 = OneArgFunctionPartial{ .anchor = p1 };
    try testing.expectEqualDeep(o1, r1.value.ok);

    const r2 = try oneArgFunctionPartialParser.parse(a, "scale [[2,3]]");
    const v2 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s2 = ScaleArg{ .translation = v2 };
    const o2 = OneArgFunctionPartial{ .scale = ScalePartial{ .elements = try a.dupe(ScaleArg, &[1]ScaleArg{s2}) } };
    try testing.expectEqualDeep(o2, r2.value.ok);

    const r3 = try oneArgFunctionPartialParser.parse(a, " rotate [0 around ( beg self) , -1234.9 a {(-12,2.1)} ]");
    const p3a = GeneralPoint{ .beginning = .self };
    const r3a = RotateArg{ .phi = 0.0, .point = p3a };
    const p3b = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp3 = GeneralPoint{ .point = p3b };
    const r3b = RotateArg{ .phi = -1234.9, .point = gp3 };
    const o3 = OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = try a.dupe(RotateArg, &[2]RotateArg{ r3a, r3b }) } };
    try testing.expectEqualDeep(o3, r3.value.ok);

    const r4 = try oneArgFunctionPartialParser.parse(a, "(r [-120 a (10% self)])");
    const f4 = ElementFraction{ .fromStart = 10, .element = .self };
    const p4 = GeneralPoint{ .fraction = f4 };
    const r4a = RotateArg{ .phi = -120.0, .point = p4 };
    const o4 = OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = try a.dupe(RotateArg, &[1]RotateArg{r4a}) } };
    try testing.expectEqualDeep(o4, r4.value.ok);

    const r5 = try oneArgFunctionPartialParser.parse(a, "(m (y=12x+1.1))");
    const l5 = inputs.Line{ .a = 1.0, .b = 12.0, .c = 1.1 };
    const m5 = MirrorPartial{ .line = l5 };
    const o5 = OneArgFunctionPartial{ .mirror = m5 };
    try testing.expectEqualDeep(o5, r5.value.ok);
}

fn compositeToInside(arena: std.mem.Allocator, a: Composite) mecha.ConvertError!CompositeInside {
    const p = try arena.create(Composite);
    errdefer arena.destroy(p);
    p.* = a;
    return CompositeInside{ .inside = p };
}

fn compositeInsideParserRef() mecha.Parser(CompositeInside) {
    return compositeInsideParser;
}

const compositeInsideParser = mecha.oneOf(.{
    oneArgFunctionPartialParser.map(struct {
        fn toStop(a: OneArgFunctionPartial) CompositeInside {
            return CompositeInside{ .stop = a };
        }
    }.toStop),
    mecha.combine(.{
        common.skipOpenBracket,
        mecha.ref(compositeParserRef),
        common.skipCloseBracket,
    }).convert(compositeToInside),
});

fn compositeParserRef() mecha.Parser(Composite) {
    return compositeParser;
}

fn parseTrainInner(arena: std.mem.Allocator, args: anytype) mecha.ConvertError!*Train {
    const left = args[0];
    const middle = args[1];
    const right = args[2];
    const train = try arena.create(Train);
    errdefer arena.destroy(train);
    train.* = Train{ .left = left, .middle = middle, .right = right };
    return train;
}

const trainParserInner = mecha.combine(.{
    mecha.ref(compositeInsideParserRef),
    common.skipWhitespace,
    twoArgCombinatorParser,
    common.skipWhitespace,
    mecha.ref(compositeInsideParserRef),
}).convert(parseTrainInner);

fn parseHookInner(arena: std.mem.Allocator, args: anytype) mecha.ConvertError!*Hook {
    const left = args[0];
    const right = args[1];
    const hook = try arena.create(Hook);
    errdefer arena.destroy(hook);
    hook.* = Hook{ .left = left, .right = right };
    return hook;
}

const hookParserInner = mecha.combine(.{
    mecha.ref(compositeInsideParserRef),
    common.skipWhitespace,
    twoArgCombinatorParser,
}).convert(parseHookInner);

const compositeParser = mecha.oneOf(.{
    trainParserInner.map(struct {
        fn toTrain(t: *Train) Composite {
            return Composite{ .train = t };
        }
    }.toTrain),
    hookParserInner.map(struct {
        fn toHook(h: *Hook) Composite {
            return Composite{ .hook = h };
        }
    }.toHook),
});

fn parseTrain(_: std.mem.Allocator, t: *Train) mecha.ConvertError!Train {
    return t.*;
}

const trainParser = mecha.combine(.{
    common.skipOpenBracket,
    trainParserInner,
    common.skipCloseBracket,
}).convert(parseTrain);

fn parseHook(_: std.mem.Allocator, h: *Hook) mecha.ConvertError!Hook {
    return h.*;
}

const hookParser = mecha.combine(.{
    common.skipOpenBracket,
    hookParserInner,
    common.skipCloseBracket,
}).convert(parseHook);

test "hookParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try hookParser.parse(a, "((anchor (0% self)) with)");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const p1 = AnchorPartial{ .point = gp1 };
    const o1 = OneArgFunctionPartial{ .anchor = p1 };
    const h1 = Hook{ .left = CompositeInside{ .stop = o1 }, .right = .with };
    try testing.expectEqualDeep(h1, r1.value.ok);

    const r2 = try hookParser.parse(a, "((scale [[2,3]]) under)");
    const v2 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s2 = ScaleArg{ .translation = v2 };
    const alloc2 = try a.dupe(ScaleArg, &[1]ScaleArg{s2});
    const o2 = OneArgFunctionPartial{ .scale = ScalePartial{ .elements = alloc2 } };
    const h2 = Hook{ .left = CompositeInside{ .stop = o2 }, .right = .under };
    try testing.expectEqualDeep(h2, r2.value.ok);
}

test "trainParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try trainParser.parse(a, "((anchor (0% self)) with (anchor {(-12,2.1)}))");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1a = GeneralPoint{ .fraction = f1 };
    const p1a = AnchorPartial{ .point = gp1a };
    const o1a = OneArgFunctionPartial{ .anchor = p1a };

    const p1b_point = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp1b = GeneralPoint{ .point = p1b_point };
    const p1b = AnchorPartial{ .point = gp1b };
    const o1b = OneArgFunctionPartial{ .anchor = p1b };

    const t1 = Train{ .left = CompositeInside{ .stop = o1a }, .middle = .with, .right = CompositeInside{ .stop = o1b } };
    try testing.expectEqualDeep(t1, r1.value.ok);

    const r2 = try trainParser.parse(a, "((r [-120 a (10% self)]) with (anchor {(-12,2.1)}))");

    const f2 = ElementFraction{ .fromStart = 10, .element = .self };
    const p2 = GeneralPoint{ .fraction = f2 };
    const r2a = RotateArg{ .phi = -120.0, .point = p2 };
    const alloc2 = try a.dupe(RotateArg, &[1]RotateArg{r2a});
    const o2a = OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = alloc2 } };

    const p2b_point = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp2b = GeneralPoint{ .point = p2b_point };
    const p2b = AnchorPartial{ .point = gp2b };
    const o2b = OneArgFunctionPartial{ .anchor = p2b };

    const t2 = Train{ .left = CompositeInside{ .stop = o2a }, .middle = .with, .right = CompositeInside{ .stop = o2b } };
    try testing.expectEqualDeep(t2, r2.value.ok);

    //
    const r3 = try trainParser.parse(a, "((scale [[2,3]] on) with (anchor {(-12,2.1)}))");

    const v3 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s3 = ScaleArg{ .translation = v3 };
    const alloc3 = try a.dupe(ScaleArg, &[1]ScaleArg{s3});
    const o3 = OneArgFunctionPartial{ .scale = ScalePartial{ .elements = alloc3 } };
    const h3 = Hook{ .left = CompositeInside{ .stop = o3 }, .right = .on };

    const p3b_point = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp3b = GeneralPoint{ .point = p3b_point };
    const p3b = AnchorPartial{ .point = gp3b };
    const o3b = OneArgFunctionPartial{ .anchor = p3b };

    const t3 = Train{ .left = CompositeInside{ .inside = &Composite{ .hook = &h3 } }, .middle = .with, .right = CompositeInside{ .stop = o3b } };
    try testing.expectEqualDeep(t3, r3.value.ok);
}

const composePartialItemParserRaw = mecha.combine(.{
    common.skipWhitespace,
    mecha.ascii.char('&').discard(),
    common.skipWhitespace,
    oneArgFunctionPartialParser,
});
const many_composePartialItemParserRaw = mecha.many(composePartialItemParserRaw, .{ .min = 0 });
const composeParserRaw = mecha.combine(.{
    common.skipOpenBracket,
    oneArgFunctionPartialParser,
    many_composePartialItemParserRaw,
    common.skipCloseBracket,
});
const composeParserRawP = @TypeOf(composeParserRaw);
fn toCompose(arena: std.mem.Allocator, args: composeParserRawP.T) mecha.ConvertError!Compose {
    var ops = try arena.alloc(OneArgFunctionPartial, 1 + args[1].len);
    ops[0] = args[0];
    @memcpy(ops[1..], args[1]);
    return Compose{ .ops = ops };
}
const composeParser = composeParserRaw.convert(toCompose);

test "composeParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try composeParser.parse(a, "(anchor (0% self) & scale [[2,3]])");

    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const p1 = AnchorPartial{ .point = gp1 };
    const o1 = OneArgFunctionPartial{ .anchor = p1 };
    const v2 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s2 = ScaleArg{ .translation = v2 };
    const alloc2 = try a.dupe(ScaleArg, &[1]ScaleArg{s2});
    const o2 = OneArgFunctionPartial{ .scale = ScalePartial{ .elements = alloc2 } };

    const c1 = Compose{ .ops = &[2]OneArgFunctionPartial{ o1, o2 } };
    try testing.expectEqualDeep(c1, r1.value.ok);

    const r2 = try composeParser.parse(a, "(a {(1,2)} & scale [[2,3]] & r [-120 a (10% self)])");
    try testing.expectEqual(@as(usize, 3), r2.value.ok.ops.len);
}

//Handling the mapping of the name of output to the transformation of it
pub const OutputTransformationPair = struct {
    outputName: []const u8,
    operation: Compose,
};

const outputNameStrParser = mecha.many(outputCharacterParser, .{ .collect = true, .min = 1 }).asStr();
const outputTransformationPairParserRaw = mecha.combine(.{
    composeParser,
    common.skipWhitespace,
    outputNameStrParser,
});
const outputTransformationPairParserRawP = @TypeOf(outputTransformationPairParserRaw);
fn toOutputTransformationPair(_: std.mem.Allocator, args: outputTransformationPairParserRawP.T) mecha.ConvertError!OutputTransformationPair {
    return OutputTransformationPair{
        .outputName = args[1],
        .operation = args[0],
    };
}
const outputTransformationPairParser = outputTransformationPairParserRaw.convert(toOutputTransformationPair);

test "outputTransformationPairParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try outputTransformationPairParser.parse(a, "(anchor (0% self)) out");

    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const p1 = AnchorPartial{ .point = gp1 };
    const o1 = OneArgFunctionPartial{ .anchor = p1 };
    const c1 = Compose{ .ops = &[1]OneArgFunctionPartial{o1} };

    const out1 = OutputTransformationPair{
        .outputName = "out",
        .operation = c1,
    };
    try testing.expectEqualDeep(out1, r1.value.ok);

    const r2 = try outputTransformationPairParser.parse(a, "(anchor {(1,2)} & scale [[2,3]]) out1");

    const pt2 = inputs.Point{ .x = 1.0, .y = 2 };
    const gp2 = GeneralPoint{ .point = pt2 };
    const p2 = AnchorPartial{ .point = gp2 };
    const o2a = OneArgFunctionPartial{ .anchor = p2 };
    const v2 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s2 = ScaleArg{ .translation = v2 };
    const alloc2 = try a.dupe(ScaleArg, &[1]ScaleArg{s2});
    const o2b = OneArgFunctionPartial{ .scale = ScalePartial{ .elements = alloc2 } };
    const c2 = Compose{ .ops = &[2]OneArgFunctionPartial{ o2a, o2b } };

    const out2 = OutputTransformationPair{
        .outputName = "out1",
        .operation = c2,
    };
    try testing.expectEqualDeep(out2, r2.value.ok);
}

//Raw, pre-validation result of parsing the connection
pub const Connection = struct {
    outputs: []const Output,
    transformationPairs: []const OutputTransformationPair,
};

const transformationPairsSeparatorParser = mecha.combine(.{common.skipComma});
const transformationPairsParser = mecha.many(outputTransformationPairParser, .{ .collect = true, .separator = transformationPairsSeparatorParser });
const transformationPairsWithBracketsParser = mecha.combine(.{
    common.skipOpenBracket,
    transformationPairsParser,
    common.skipCloseBracket,
});
const connectionParserRawSingle = mecha.combine(.{
    outputsParser,
    common.skipWhitespace,
    common.skipArrow,
    common.skipWhitespace,
    outputTransformationPairParser,
}).convert(struct {
    fn toSingle(_: std.mem.Allocator, args: anytype) mecha.ConvertError!Connection {
        return Connection{
            .outputs = args[0],
            .transformationPairs = &[1]OutputTransformationPair{args[1]},
        };
    }
}.toSingle);
const connectionParserRawMultiple = mecha.combine(.{
    outputsParser,
    common.skipWhitespace,
    common.skipArrow,
    common.skipWhitespace,
    transformationPairsWithBracketsParser,
}).convert(struct {
    fn toMultiple(_: std.mem.Allocator, args: anytype) mecha.ConvertError!Connection {
        return Connection{
            .outputs = args[0],
            .transformationPairs = args[1],
        };
    }
}.toMultiple);
const identityTransformationParser = outputNameStrParser.convert(struct {
    fn toIdentityTransformation(arena: std.mem.Allocator, name: []const u8) mecha.ConvertError!OutputTransformationPair {
        const identityOp = OneArgFunctionPartial{ .none = {} };
        const ops = try arena.alloc(OneArgFunctionPartial, 1);
        ops[0] = identityOp;
        return OutputTransformationPair{
            .outputName = name,
            .operation = Compose{ .ops = ops },
        };
    }
}.toIdentityTransformation);
const connectionParserRawIdentity = mecha.combine(.{
    outputsParser,
    common.skipWhitespace,
    common.skipArrow,
    common.skipWhitespace,
    identityTransformationParser,
}).convert(struct {
    fn toIdentity(_: std.mem.Allocator, args: anytype) mecha.ConvertError!Connection {
        return Connection{
            .outputs = args[0],
            .transformationPairs = &[1]OutputTransformationPair{args[1]},
        };
    }
}.toIdentity);
pub const connectionParser = mecha.oneOf(.{
    connectionParserRawMultiple,
    connectionParserRawSingle,
    connectionParserRawIdentity,
});

test "connectionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try connectionParser.parse(a, "(out) -> (anchor (0% self)) out");

    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gpa1 = GeneralPoint{ .fraction = f1 };
    const ap1 = AnchorPartial{ .point = gpa1 };
    const of1 = OneArgFunctionPartial{ .anchor = ap1 };
    const c1 = Compose{ .ops = &[1]OneArgFunctionPartial{of1} };

    const tp1 = OutputTransformationPair{
        .outputName = "out",
        .operation = c1,
    };
    const out1 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const exp1 = Connection{
        .outputs = &[1]Output{out1},
        .transformationPairs = &[1]OutputTransformationPair{tp1},
    };
    try testing.expectEqualDeep(exp1, r1.value.ok);

    const r2 = try connectionParser.parse(a, "(out1, out2) -> ( (anchor (30% self)) out1, (anchor {(1,2)} & scale [[2,3]]) out2 )");

    const f2a = ElementFraction{ .fromStart = 30, .element = .self };
    const gpa2a = GeneralPoint{ .fraction = f2a };
    const ap2a = AnchorPartial{ .point = gpa2a };
    const of2a = OneArgFunctionPartial{ .anchor = ap2a };
    const c2a = Compose{ .ops = &[1]OneArgFunctionPartial{of2a} };
    const tp2a = OutputTransformationPair{
        .outputName = "out1",
        .operation = c2a,
    };

    const pt2b = inputs.Point{ .x = 1.0, .y = 2 };
    const gpa2b = GeneralPoint{ .point = pt2b };
    const ap2b = AnchorPartial{ .point = gpa2b };
    const of2b_first = OneArgFunctionPartial{ .anchor = ap2b };
    const v2b = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s2b = ScaleArg{ .translation = v2b };
    const alloc2b = try a.dupe(ScaleArg, &[1]ScaleArg{s2b});
    const of2b_second = OneArgFunctionPartial{ .scale = ScalePartial{ .elements = alloc2b } };
    const c2b = Compose{ .ops = &[2]OneArgFunctionPartial{ of2b_first, of2b_second } };
    const tp2b = OutputTransformationPair{
        .outputName = "out2",
        .operation = c2b,
    };

    const out2a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const out2b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const exp2 = Connection{
        .outputs = &[2]Output{ out2a, out2b },
        .transformationPairs = &[2]OutputTransformationPair{ tp2a, tp2b },
    };
    try testing.expectEqualDeep(exp2, r2.value.ok);
}

pub const OutputError = error{
    ArgumentInPairInvalid,
    WrongNumberOfOutputs,
    CannotDetermineExplicitPoint,
};

pub const ToExplicitPointError = error{
    CannotDetermineExplicitPoint,
    OutOfMemory,
};

pub const OutputsValidated = struct {
    transformationPairs: []const OutputTransformationPair,
};

// Validate 'Connection' to get 'OutputsValidated' if
// (a) outputName's in each transformationPairs of the connection is in 'outputs' (if not `OutputError.ArgumentInPairInvalid` triggered)
// (b) the number of outputs is the same as the one specified in numberOfOutputs arg (if not `OutputError.WrongNumberOfOutputs` triggered)
// Otherwise, one of the errors from OutputError is emitted
pub fn validateConnection(_: std.mem.Allocator, numberOfOutputs: u8, connection: Connection) !OutputsValidated {
    if (connection.outputs.len != numberOfOutputs) {
        return OutputError.WrongNumberOfOutputs;
    }

    for (connection.transformationPairs) |pair| {
        const found = for (connection.outputs) |output| {
            if (std.mem.eql(u8, output.name, pair.outputName)) {
                break true;
            }
        } else false;

        if (!found) {
            return OutputError.ArgumentInPairInvalid;
        }
    }

    return OutputsValidated{ .transformationPairs = connection.transformationPairs };
}

fn computeAnchorGlobal(
    anchor_x: f32,
    anchor_y: f32,
    current_origin_x: f32,
    current_origin_y: f32,
    current_x_axis_x: f32,
    current_x_axis_y: f32,
    current_perp_x: f32,
    current_perp_y: f32,
) inputs.Point {
    const local_px = anchor_x;
    const local_py = anchor_y;
    const line_x_p1_x = current_origin_x + local_py * current_perp_x;
    const line_x_p1_y = current_origin_y + local_py * current_perp_y;
    const line_x_p2_x = line_x_p1_x + current_x_axis_x;
    const line_x_p2_y = line_x_p1_y + current_x_axis_y;
    const line_x = Line.fromTwoPoints(line_x_p1_x, line_x_p1_y, line_x_p2_x, line_x_p2_y);
    const line_y_p1_x = current_origin_x + local_px * current_x_axis_x;
    const line_y_p1_y = current_origin_y + local_px * current_x_axis_y;
    const line_y_p2_x = line_y_p1_x + current_perp_x;
    const line_y_p2_y = line_y_p1_y + current_perp_y;
    const line_y = Line.fromTwoPoints(line_y_p1_x, line_y_p1_y, line_y_p2_x, line_y_p2_y);
    const global_point = line_y.intersection(&line_x);
    return global_point;
}

fn updateCoordFrame(
    current_origin_x: *f32,
    current_origin_y: *f32,
    current_x_axis_x: *f32,
    current_x_axis_y: *f32,
    current_perp_x: *f32,
    current_perp_y: *f32,
    anchor_x: f32,
    anchor_y: f32,
    global_x: f32,
    global_y: f32,
    next_anchor_x: f32,
    next_anchor_y: f32,
) void {
    current_origin_x.* = global_x;
    current_origin_y.* = global_y;
    const dx = next_anchor_x - anchor_x;
    const dy = next_anchor_y - anchor_y;
    const len = @sqrt(dx * dx + dy * dy);
    if (len > 1e-10) {
        current_x_axis_x.* = dx / len;
        current_x_axis_y.* = dy / len;
        current_perp_x.* = -current_x_axis_y.*;
        current_perp_y.* = current_x_axis_x.*;
    }
}

fn generateCoordPolyline(
    allocator: std.mem.Allocator,
    vectors: []const inputs.Vector,
    start_x: f32,
    start_y: f32,
    x_axis_x: f32,
    x_axis_y: f32,
    perp_x: f32,
    perp_y: f32,
) ![]OneArgFunctionPartial {
    const num_points = vectors.len + 1;
    var ops = try allocator.alloc(OneArgFunctionPartial, num_points);
    ops[0] = OneArgFunctionPartial{
        .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = start_x, .y = start_y } } },
    };
    var cur_x: f32 = start_x;
    var cur_y: f32 = start_y;
    for (vectors, 0..) |v, j| {
        const gx = v.x * x_axis_x + v.y * perp_x;
        const gy = v.x * x_axis_y + v.y * perp_y;
        cur_x += gx;
        cur_y += gy;
        ops[j + 1] = OneArgFunctionPartial{
            .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = cur_x, .y = cur_y } } },
        };
    }
    return ops;
}

pub fn toExplicitPoint(allocator: std.mem.Allocator, inp: inputs.Inputs, outputs: OutputsValidated, orientation: CoordinateOrientation, plot_steps: PlotSteps, output_idx: usize) ToExplicitPointError!OutputsValidated {
    var has_non_point_refs = false;
    for (outputs.transformationPairs) |pair| {
        for (pair.operation.ops) |op| {
            if (op == .anchor) {
                switch (op.anchor.point) {
                    .point => {},
                    else => has_non_point_refs = true,
                }
            }
        }
    }

    // Handle compose with non-anchor operations (rotate, scale, mirror)
    // Process ops right-to-left for & composition semantics
    {
        var has_non_anchor = false;
        for (outputs.transformationPairs) |pair| {
            for (pair.operation.ops) |op| {
                if (op != .anchor) {
                    has_non_anchor = true;
                    break;
                }
            }
            if (has_non_anchor) break;
        }

        if (has_non_anchor) {
            var result_pairs = try allocator.alloc(OutputTransformationPair, outputs.transformationPairs.len);

            for (outputs.transformationPairs, 0..) |pair, idx| {
                const ops = pair.operation.ops;
                const num_ops = ops.len;

                var has_mixed = false;
                for (ops) |op| {
                    if (op != .anchor) {
                        has_mixed = true;
                        break;
                    }
                }

                if (!has_mixed) {
                    result_pairs[idx] = pair;
                    continue;
                }

                var vector_count: usize = 0;
                if (idx < inp.input.len) {
                    for (inp.input[idx].row) |elem| {
                        if (elem == .vector) vector_count += 1;
                    }
                }

                var vectors = try allocator.alloc(inputs.Vector, vector_count);
                defer allocator.free(vectors);
                var vidx: usize = 0;
                if (idx < inp.input.len) {
                    const row = inp.input[idx];
                    for (row.row) |elem| {
                        if (elem == .vector) {
                            vectors[vidx] = elem.vector;
                            vidx += 1;
                        }
                    }
                }

                var ctx_begin: ?inputs.Point = null;
                var ctx_end: ?inputs.Point = null;

                var polylines = try allocator.alloc([]inputs.Point, num_ops);
                var poly_count: usize = 0;

                var i: usize = num_ops;
                while (i > 0) {
                    i -= 1;
                    const op = ops[i];

                    if (op == .anchor) {
                        const pt = switch (op.anchor.point) {
                            .point => |p| p,
                            .beginning => |ref| try getExplicitPoint(inp, outputs, ref, idx, .{ .beginning = .self }, orientation),
                            .end => |ref| try getExplicitPoint(inp, outputs, ref, idx, .{ .end = .self }, orientation),
                            .middle => |ref| try getExplicitPoint(inp, outputs, ref, idx, .{ .middle = .self }, orientation),
                            .fraction => |frac| try getExplicitPoint(inp, outputs, frac.element, idx, .{ .fraction = frac }, orientation),
                        };
                        var poly = try allocator.alloc(inputs.Point, vector_count + 1);
                        poly[0] = pt;
                        var cur = pt;
                        for (vectors, 0..) |v, j| {
                            cur = inputs.Point{ .x = cur.x + v.x, .y = cur.y + v.y };
                            poly[j + 1] = cur;
                        }
                        polylines[poly_count] = poly;
                        ctx_begin = poly[0];
                        ctx_end = poly[poly.len - 1];
                        poly_count += 1;
                    } else if (op == .rotate) {
                        const arg = op.rotate.elements[0];
                        const prev_poly = polylines[poly_count - 1];
                        const rot_pt = try resolveGeneralPoint(arg.point, ctx_begin, ctx_end, inp, outputs, idx, orientation);
                        var rot_pt_in_poly = false;
                        for (prev_poly) |p| {
                            if (p.x == rot_pt.x and p.y == rot_pt.y) {
                                rot_pt_in_poly = true;
                                break;
                            }
                        }
                        var poly = try allocator.alloc(inputs.Point, prev_poly.len);
                        if (rot_pt_in_poly) {
                            poly[0] = rot_pt;
                            var out_idx: usize = 1;
                            for (prev_poly) |p| {
                                if (p.x == rot_pt.x and p.y == rot_pt.y) continue;
                                poly[out_idx] = rotateAround(arg.phi, rot_pt.x, rot_pt.y, p.x, p.y);
                                out_idx += 1;
                            }
                        } else {
                            for (prev_poly, 0..) |p, j| {
                                poly[j] = rotateAround(arg.phi, rot_pt.x, rot_pt.y, p.x, p.y);
                            }
                        }
                        polylines[poly_count] = poly;
                        ctx_begin = poly[0];
                        ctx_end = poly[poly.len - 1];
                        poly_count += 1;
                    } else if (op == .scale) {
                        const arg = op.scale.elements[0];
                        const prev_poly = polylines[poly_count - 1];
                        var poly = try allocator.alloc(inputs.Point, prev_poly.len);
                        if (orientation == .coord) {
                            const dx = prev_poly[prev_poly.len - 1].x - prev_poly[0].x;
                            const dy = prev_poly[prev_poly.len - 1].y - prev_poly[0].y;
                            const len = @sqrt(@as(f64, dx) * @as(f64, dx) + @as(f64, dy) * @as(f64, dy));
                            var x_axis_x: f64 = 1.0;
                            var x_axis_y: f64 = 0.0;
                            if (len > 1e-10) {
                                x_axis_x = @as(f64, dx) / len;
                                x_axis_y = @as(f64, dy) / len;
                            }
                            const perp_x = -x_axis_y;
                            const perp_y = x_axis_x;
                            var cur_x: f64 = prev_poly[0].x;
                            var cur_y: f64 = prev_poly[0].y;
                            for (vectors, 0..) |v, j| {
                                const gx = @as(f64, v.x) * x_axis_x + @as(f64, v.y) * perp_x;
                                const gy = @as(f64, v.x) * x_axis_y + @as(f64, v.y) * perp_y;
                                if (j == 0) {
                                    cur_x += gx;
                                    cur_y += gy;
                                    poly[0] = .{ .x = @floatCast(cur_x), .y = @floatCast(cur_y) };
                                    cur_x += gx * @as(f64, arg.translation.x);
                                    cur_y += gy * @as(f64, arg.translation.y);
                                    poly[1] = .{ .x = @floatCast(cur_x), .y = @floatCast(cur_y) };
                                } else {
                                    cur_x += gx * @as(f64, arg.translation.x);
                                    cur_y += gy * @as(f64, arg.translation.y);
                                    poly[j + 1] = .{ .x = @floatCast(cur_x), .y = @floatCast(cur_y) };
                                }
                            }
                        } else {
                            poly[0] = prev_poly[0];
                            for (prev_poly[1..], 0..) |p, j| {
                                poly[j + 1] = inputs.Point{
                                    .x = poly[0].x + (p.x - poly[0].x) * arg.translation.x,
                                    .y = poly[0].y + (p.y - poly[0].y) * arg.translation.y,
                                };
                            }
                            if (orientation == .origin) {
                                for (poly) |*p| {
                                    p.x += ctx_begin.?.x;
                                    p.y += ctx_begin.?.y;
                                }
                            }
                        }
                        polylines[poly_count] = poly;
                        ctx_begin = poly[0];
                        ctx_end = poly[poly.len - 1];
                        poly_count += 1;
                    } else if (op == .mirror) {
                        const prev_poly = polylines[poly_count - 1];
                        var poly = try allocator.alloc(inputs.Point, prev_poly.len);
                        poly[0] = prev_poly[0];
                        for (prev_poly[1..], 0..) |p, j| {
                            poly[j + 1] = mirrorPointOverLine(p, op.mirror.line, null);
                        }
                        if (orientation == .origin) {
                            for (poly) |*p| {
                                p.x += ctx_begin.?.x;
                                p.y += ctx_begin.?.y;
                            }
                        }
                        polylines[poly_count] = poly;
                        ctx_begin = poly[0];
                        ctx_end = poly[poly.len - 1];
                        poly_count += 1;
                    }
                }

                var total_points: usize = 0;
                for (0..poly_count) |j| total_points += polylines[j].len;

                var new_ops = try allocator.alloc(OneArgFunctionPartial, total_points);
                var op_idx: usize = 0;
                for (0..poly_count) |j| {
                    const poly = polylines[j];
                    for (poly) |p| {
                        new_ops[op_idx] = OneArgFunctionPartial{ .anchor = .{ .point = .{ .point = p } } };
                        op_idx += 1;
                    }
                }

                for (0..poly_count) |j| allocator.free(polylines[j]);
                allocator.free(polylines);

                result_pairs[idx] = OutputTransformationPair{
                    .outputName = pair.outputName,
                    .operation = .{ .ops = new_ops },
                };
            }

            return OutputsValidated{ .transformationPairs = result_pairs };
        }
    }

    // ORIGIN MODE: origin shifts with each anchor, anchors positioned relative to current origin
    if (orientation == .origin and !has_non_point_refs) {
        var result_pairs = try allocator.alloc(OutputTransformationPair, outputs.transformationPairs.len);

        for (outputs.transformationPairs, 0..) |pair, idx| {
            var anchor_count: usize = 0;
            for (pair.operation.ops) |op| {
                if (op == .anchor and op.anchor.point == .point) {
                    anchor_count += 1;
                }
            }

            if (anchor_count < 2) {
                result_pairs[idx] = pair;
                continue;
            }

            // & applies in reverse order
            var anchors = try allocator.alloc(inputs.Point, anchor_count);
            var anchor_idx: usize = anchor_count;
            for (pair.operation.ops) |op| {
                if (op == .anchor and op.anchor.point == .point) {
                    anchor_idx -= 1;
                    anchors[anchor_idx] = op.anchor.point.point;
                }
            }

            var new_ops_with_end = try allocator.alloc(OneArgFunctionPartial, 2 * anchor_count);

            var input_x: f32 = 0.0;
            var input_y: f32 = 0.0;
            if (idx < inp.input.len) {
                const row = inp.input[idx];
                for (row.row) |elem| {
                    switch (elem) {
                        .vector => |v| {
                            input_x += v.x;
                            input_y += v.y;
                        },
                        .point => {},
                    }
                }
            }

            var origin_x: f32 = 0.0;
            var origin_y: f32 = 0.0;
            for (0..anchor_count) |i| {
                const p = anchors[i];
                const begin_x = p.x + origin_x;
                const begin_y = p.y + origin_y;
                const end_x = begin_x + input_x;
                const end_y = begin_y + input_y;
                new_ops_with_end[i * 2] = OneArgFunctionPartial{
                    .anchor = AnchorPartial{
                        .point = GeneralPoint{ .point = inputs.Point{ .x = begin_x, .y = begin_y } },
                    },
                };
                new_ops_with_end[i * 2 + 1] = OneArgFunctionPartial{
                    .anchor = AnchorPartial{
                        .point = GeneralPoint{ .point = inputs.Point{ .x = end_x, .y = end_y } },
                    },
                };
                origin_x = begin_x;
                origin_y = begin_y;
            }

            result_pairs[idx] = OutputTransformationPair{
                .outputName = pair.outputName,
                .operation = .{ .ops = new_ops_with_end },
            };
        }

        return OutputsValidated{ .transformationPairs = result_pairs };
    }

    // FIXED MODE: each anchor stays at its position, add input to get end
    if (orientation == .fixed and !has_non_point_refs) {
        var result_pairs = try allocator.alloc(OutputTransformationPair, outputs.transformationPairs.len);

        for (outputs.transformationPairs, 0..) |pair, idx| {
            var anchor_count: usize = 0;
            for (pair.operation.ops) |op| {
                if (op == .anchor and op.anchor.point == .point) {
                    anchor_count += 1;
                }
            }

            if (anchor_count < 2) {
                result_pairs[idx] = pair;
                continue;
            }

            // Collect anchors in reverse order (matching & semantics: last op applied first)
            var anchors = try allocator.alloc(inputs.Point, anchor_count);
            var anchor_idx: usize = anchor_count;
            for (pair.operation.ops) |op| {
                if (op == .anchor and op.anchor.point == .point) {
                    anchor_idx -= 1;
                    anchors[anchor_idx] = op.anchor.point.point;
                }
            }

            var new_ops_with_end = try allocator.alloc(OneArgFunctionPartial, 2 * anchor_count);

            var input_x: f32 = 0.0;
            var input_y: f32 = 0.0;
            if (idx < inp.input.len) {
                const row = inp.input[idx];
                for (row.row) |elem| {
                    switch (elem) {
                        .vector => |v| {
                            input_x += v.x;
                            input_y += v.y;
                        },
                        .point => {},
                    }
                }
            }

            // Each anchor stays at its position, end = anchor + input
            for (0..anchor_count) |i| {
                const p = anchors[i];
                const begin_x = p.x;
                const begin_y = p.y;
                const end_x = p.x + input_x;
                const end_y = p.y + input_y;
                new_ops_with_end[i * 2] = OneArgFunctionPartial{
                    .anchor = AnchorPartial{
                        .point = GeneralPoint{ .point = inputs.Point{ .x = begin_x, .y = begin_y } },
                    },
                };
                new_ops_with_end[i * 2 + 1] = OneArgFunctionPartial{
                    .anchor = AnchorPartial{
                        .point = GeneralPoint{ .point = inputs.Point{ .x = end_x, .y = end_y } },
                    },
                };
            }

            result_pairs[idx] = OutputTransformationPair{
                .outputName = pair.outputName,
                .operation = .{ .ops = new_ops_with_end },
            };
        }

        return OutputsValidated{ .transformationPairs = result_pairs };
    }

    // COORD MODE: chained frame-based geometry for any number of anchors
    // Each anchor defines a new local frame using line intersection
    // Only the last step is plotted, but it includes the full input polyline
    if (orientation == .coord and !has_non_point_refs) {
        var result_pairs = try allocator.alloc(OutputTransformationPair, outputs.transformationPairs.len);

        for (outputs.transformationPairs, 0..) |pair, idx| {
            if (idx != output_idx) {
                result_pairs[idx] = pair;
                continue;
            }
            var anchor_count: usize = 0;
            for (pair.operation.ops) |op| {
                if (op == .anchor and op.anchor.point == .point) {
                    anchor_count += 1;
                }
            }

            if (anchor_count < 1) {
                result_pairs[idx] = pair;
                continue;
            }

            var anchors = try allocator.alloc(inputs.Point, anchor_count);
            var anchor_idx: usize = anchor_count;
            for (pair.operation.ops) |op| {
                if (op == .anchor and op.anchor.point == .point) {
                    anchor_idx -= 1;
                    anchors[anchor_idx] = op.anchor.point.point;
                }
            }

            // Count input vectors
            var vector_count: usize = 0;
            if (output_idx < inp.input.len) {
                const row = inp.input[output_idx];
                for (row.row) |elem| {
                    if (elem == .vector) vector_count += 1;
                }
            }

            // Collect vectors into slice
            var vectors = try allocator.alloc(inputs.Vector, vector_count);
            defer allocator.free(vectors);
            var vidx: usize = 0;
            if (output_idx < inp.input.len) {
                const row = inp.input[output_idx];
                for (row.row) |elem| {
                    if (elem == .vector) {
                        vectors[vidx] = elem.vector;
                        vidx += 1;
                    }
                }
            }

            if (vector_count == 0) {
                // No vectors, just generate (begin, end) for last anchor
                var new_ops_with_end = try allocator.alloc(OneArgFunctionPartial, 2 * anchor_count);
                var current_origin_x: f32 = anchors[0].x;
                var current_origin_y: f32 = anchors[0].y;
                var current_x_axis_x: f32 = 1.0;
                var current_x_axis_y: f32 = 0.0;
                var current_perp_x: f32 = 0.0;
                var current_perp_y: f32 = 1.0;

                for (0..anchor_count) |i| {
                    const anchor_x = anchors[i].x;
                    const anchor_y = anchors[i].y;
                    var global_x: f32 = undefined;
                    var global_y: f32 = undefined;

                    if (i == 0) {
                        global_x = anchor_x;
                        global_y = anchor_y;
                    } else {
                        const local_px = anchor_x;
                        const local_py = anchor_y;
                        const line_x_p1_x = current_origin_x + local_py * current_perp_x;
                        const line_x_p1_y = current_origin_y + local_py * current_perp_y;
                        const line_x_p2_x = line_x_p1_x + current_x_axis_x;
                        const line_x_p2_y = line_x_p1_y + current_x_axis_y;
                        const line_x = Line.fromTwoPoints(line_x_p1_x, line_x_p1_y, line_x_p2_x, line_x_p2_y);
                        const line_y_p1_x = current_origin_x + local_px * current_x_axis_x;
                        const line_y_p1_y = current_origin_y + local_px * current_x_axis_y;
                        const line_y_p2_x = line_y_p1_x + current_perp_x;
                        const line_y_p2_y = line_y_p1_y + current_perp_y;
                        const line_y = Line.fromTwoPoints(line_y_p1_x, line_y_p1_y, line_y_p2_x, line_y_p2_y);
                        const global_point = line_y.intersection(&line_x);
                        global_x = global_point.x;
                        global_y = global_point.y;
                    }

                    new_ops_with_end[i * 2] = OneArgFunctionPartial{
                        .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = global_x, .y = global_y } } },
                    };
                    new_ops_with_end[i * 2 + 1] = OneArgFunctionPartial{
                        .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = global_x, .y = global_y } } },
                    };

                    if (i < anchor_count - 1) {
                        current_origin_x = global_x;
                        current_origin_y = global_y;
                        current_x_axis_x = (anchors[i + 1].x - anchor_x);
                        current_x_axis_y = (anchors[i + 1].y - anchor_y);
                        const len = @sqrt(current_x_axis_x * current_x_axis_x + current_x_axis_y * current_x_axis_y);
                        if (len > 1e-10) {
                            current_x_axis_x /= len;
                            current_x_axis_y /= len;
                            current_perp_x = -current_x_axis_y;
                            current_perp_y = current_x_axis_x;
                        }
                    }
                }
                result_pairs[idx] = OutputTransformationPair{
                    .outputName = pair.outputName,
                    .operation = .{ .ops = new_ops_with_end },
                };
                continue;
            }

            if (plot_steps == .all and anchor_count > 1) {
                // Generate polylines for all intermediate steps
                const num_points = anchor_count * (vector_count + 1);
                var all_ops = try allocator.alloc(OneArgFunctionPartial, num_points);

                var cur_origin_x: f32 = anchors[0].x;
                var cur_origin_y: f32 = anchors[0].y;
                var cur_x_axis_x: f32 = 1.0;
                var cur_x_axis_y: f32 = 0.0;
                var cur_perp_x: f32 = 0.0;
                var cur_perp_y: f32 = 1.0;

                var op_idx: usize = 0;
                for (0..anchor_count) |i| {
                    const anchor_x = anchors[i].x;
                    const anchor_y = anchors[i].y;

                    var global_x: f32 = anchor_x;
                    var global_y: f32 = anchor_y;
                    if (i > 0) {
                        const gp = computeAnchorGlobal(anchor_x, anchor_y, cur_origin_x, cur_origin_y, cur_x_axis_x, cur_x_axis_y, cur_perp_x, cur_perp_y);
                        global_x = gp.x;
                        global_y = gp.y;
                    }

                    // Generate polyline for this step
                    const step_ops = try generateCoordPolyline(allocator, vectors, global_x, global_y, cur_x_axis_x, cur_x_axis_y, cur_perp_x, cur_perp_y);
                    defer allocator.free(step_ops);
                    for (step_ops, 0..) |op, j| {
                        all_ops[op_idx + j] = op;
                    }
                    op_idx += step_ops.len;

                    // Update frame for next step
                    if (i < anchor_count - 1) {
                        updateCoordFrame(&cur_origin_x, &cur_origin_y, &cur_x_axis_x, &cur_x_axis_y, &cur_perp_x, &cur_perp_y, anchor_x, anchor_y, global_x, global_y, anchors[i + 1].x, anchors[i + 1].y);
                    }
                }

                result_pairs[idx] = OutputTransformationPair{
                    .outputName = pair.outputName,
                    .operation = .{ .ops = all_ops },
                };
            } else {
                // .last mode: compute frame after all anchors, generate only final polyline
                var cur_origin_x: f32 = anchors[0].x;
                var cur_origin_y: f32 = anchors[0].y;
                var cur_x_axis_x: f32 = 1.0;
                var cur_x_axis_y: f32 = 0.0;
                var cur_perp_x: f32 = 0.0;
                var cur_perp_y: f32 = 1.0;

                // Process first anchor_count-1 anchors to build frame
                for (0..anchor_count - 1) |i| {
                    const anchor_x = anchors[i].x;
                    const anchor_y = anchors[i].y;
                    var global_x: f32 = anchor_x;
                    var global_y: f32 = anchor_y;

                    if (i > 0) {
                        const gp = computeAnchorGlobal(anchor_x, anchor_y, cur_origin_x, cur_origin_y, cur_x_axis_x, cur_x_axis_y, cur_perp_x, cur_perp_y);
                        global_x = gp.x;
                        global_y = gp.y;
                    }

                    updateCoordFrame(&cur_origin_x, &cur_origin_y, &cur_x_axis_x, &cur_x_axis_y, &cur_perp_x, &cur_perp_y, anchor_x, anchor_y, global_x, global_y, anchors[i + 1].x, anchors[i + 1].y);
                }

                // Last anchor: compute its global position
                const last_anchor_x = anchors[anchor_count - 1].x;
                const last_anchor_y = anchors[anchor_count - 1].y;
                var last_global_x: f32 = last_anchor_x;
                var last_global_y: f32 = last_anchor_y;

                if (anchor_count > 1) {
                    const gp = computeAnchorGlobal(last_anchor_x, last_anchor_y, cur_origin_x, cur_origin_y, cur_x_axis_x, cur_x_axis_y, cur_perp_x, cur_perp_y);
                    last_global_x = gp.x;
                    last_global_y = gp.y;
                }

                // Generate ops for full input polyline starting at last anchor
                const num_points = vector_count + 1;
                var new_ops = try allocator.alloc(OneArgFunctionPartial, num_points);
                new_ops[0] = OneArgFunctionPartial{
                    .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = last_global_x, .y = last_global_y } } },
                };

                var cur_x: f32 = last_global_x;
                var cur_y: f32 = last_global_y;
                for (vectors, 0..) |v, j| {
                    const gx = v.x * cur_x_axis_x + v.y * cur_perp_x;
                    const gy = v.x * cur_x_axis_y + v.y * cur_perp_y;
                    cur_x += gx;
                    cur_y += gy;
                    new_ops[j + 1] = OneArgFunctionPartial{
                        .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = cur_x, .y = cur_y } } },
                    };
                }

                result_pairs[idx] = OutputTransformationPair{
                    .outputName = pair.outputName,
                    .operation = .{ .ops = new_ops },
                };
            }
        }

        return OutputsValidated{ .transformationPairs = result_pairs };
    }

    if (!has_non_point_refs) {
        return outputs;
    }

    var result_pairs = try allocator.alloc(OutputTransformationPair, outputs.transformationPairs.len);

    for (outputs.transformationPairs, 0..) |pair, idx| {
        var new_ops = try allocator.alloc(OneArgFunctionPartial, pair.operation.ops.len);

        for (pair.operation.ops, 0..) |op, op_idx| {
            switch (op) {
                .anchor => |anchor| {
                    var new_point = anchor.point;
                    switch (anchor.point) {
                        .point => {},
                        .beginning => |eref| {
                            const explicit = try getExplicitPoint(inp, outputs, eref, idx, .{ .beginning = .self }, orientation);
                            new_point = .{ .point = explicit };
                        },
                        .end => |eref| {
                            const explicit = try getExplicitPoint(inp, outputs, eref, idx, .{ .end = .self }, orientation);
                            new_point = .{ .point = explicit };
                        },
                        .middle => |eref| {
                            const explicit = try getExplicitPoint(inp, outputs, eref, idx, .{ .middle = .self }, orientation);
                            new_point = .{ .point = explicit };
                        },
                        .fraction => |frac| {
                            const explicit = try getExplicitPoint(inp, outputs, frac.element, idx, .{ .fraction = frac }, orientation);
                            new_point = .{ .point = explicit };
                        },
                    }
                    new_ops[op_idx] = OneArgFunctionPartial{ .anchor = .{ .point = new_point } };
                },
                else => {
                    new_ops[op_idx] = op;
                },
            }
        }

        result_pairs[idx] = OutputTransformationPair{
            .outputName = pair.outputName,
            .operation = .{ .ops = new_ops },
        };
    }

    return OutputsValidated{ .transformationPairs = result_pairs };
}

fn resolveGeneralPoint(
    pt: GeneralPoint,
    ctx_begin: ?inputs.Point,
    ctx_end: ?inputs.Point,
    inp: inputs.Inputs,
    outputs: OutputsValidated,
    idx: usize,
    orientation: CoordinateOrientation,
) ToExplicitPointError!inputs.Point {
    switch (pt) {
        .point => |p| return p,
        .beginning => |ref| {
            if (ref == .self) return ctx_begin orelse return ToExplicitPointError.CannotDetermineExplicitPoint;
            return getExplicitPoint(inp, outputs, ref, idx, .{ .beginning = .self }, orientation);
        },
        .end => |ref| {
            if (ref == .self) return ctx_end orelse return ToExplicitPointError.CannotDetermineExplicitPoint;
            return getExplicitPoint(inp, outputs, ref, idx, .{ .end = .self }, orientation);
        },
        .middle => |ref| {
            if (ref == .self) {
                const b = ctx_begin orelse return ToExplicitPointError.CannotDetermineExplicitPoint;
                const e = ctx_end orelse return ToExplicitPointError.CannotDetermineExplicitPoint;
                return inputs.Point{ .x = (b.x + e.x) / 2.0, .y = (b.y + e.y) / 2.0 };
            }
            return getExplicitPoint(inp, outputs, ref, idx, .{ .middle = .self }, orientation);
        },
        .fraction => |frac| {
            if (frac.element == .self) {
                const b = ctx_begin orelse return ToExplicitPointError.CannotDetermineExplicitPoint;
                const e = ctx_end orelse return ToExplicitPointError.CannotDetermineExplicitPoint;
                const dx = e.x - b.x;
                const dy = e.y - b.y;
                const factor = @as(f32, @floatFromInt(frac.fromStart)) / 100.0;
                return inputs.Point{ .x = b.x + dx * factor, .y = b.y + dy * factor };
            }
            return getExplicitPoint(inp, outputs, frac.element, idx, .{ .fraction = frac }, orientation);
        },
    }
}

fn getExplicitPoint(inp: inputs.Inputs, outputs: OutputsValidated, ref: ElementReference, current_idx: usize, pt_type: GeneralPoint, orientation: CoordinateOrientation) ToExplicitPointError!inputs.Point {
    _ = orientation;
    const target_idx: usize = switch (ref) {
        .self => current_idx,
        .other => |name| blk: {
            for (outputs.transformationPairs, 0..) |pair, i| {
                if (std.mem.eql(u8, pair.outputName, name)) {
                    break :blk i;
                }
            }
            return ToExplicitPointError.CannotDetermineExplicitPoint;
        },
    };

    // For .self references, we cannot determine explicit point at any index
    // because there's no accumulated path to reference
    if (ref == .self) {
        return ToExplicitPointError.CannotDetermineExplicitPoint;
    }

    // For .other, can reference any other output - we look at their raw input data

    if (target_idx >= inp.input.len) {
        return ToExplicitPointError.CannotDetermineExplicitPoint;
    }

    const row = inp.input[target_idx];
    if (row.row.len == 0) {
        return ToExplicitPointError.CannotDetermineExplicitPoint;
    }

    var start_x: f32 = 0.0;
    var start_y: f32 = 0.0;
    var end_x: f32 = 0.0;
    var end_y: f32 = 0.0;

    for (row.row) |elem| {
        switch (elem) {
            .vector => |v| {
                end_x = start_x + v.x;
                end_y = start_y + v.y;
                start_x = end_x;
                start_y = end_y;
            },
            .point => {},
        }
    }

    return switch (pt_type) {
        .point => .{ .x = 0.0, .y = 0.0 }, // shouldn't happen, handled before
        .beginning => .{ .x = 0.0, .y = 0.0 },
        .end => .{ .x = end_x, .y = end_y },
        .middle => .{ .x = end_x / 2.0, .y = end_y / 2.0 },
        .fraction => |frac| {
            if (end_x == 0.0 and end_y == 0.0) {
                return ToExplicitPointError.CannotDetermineExplicitPoint;
            }
            // fraction: point beyond the reference point by percentage
            const factor = 1.0 + @as(f32, @floatFromInt(frac.fromStart)) / 100.0;
            const x = end_x * factor;
            const y = end_y * factor;
            return .{ .x = x, .y = y };
        },
    };
}

test "toExplicitPoint" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const p1 = inputs.Point{ .x = 1.0, .y = 2 };
    const gpa1 = GeneralPoint{ .point = p1 };
    const ap1 = AnchorPartial{ .point = gpa1 };
    const of1 = OneArgFunctionPartial{ .anchor = ap1 };
    const c1 = Compose{ .ops = &[1]OneArgFunctionPartial{of1} };

    const tp1 = OutputTransformationPair{
        .outputName = "out",
        .operation = c1,
    };
    const outputValidated1 = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp1},
    };
    const v1 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row1 = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v1} };
    const input1 = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row1} };

    const res1 = try toExplicitPoint(a, input1, outputValidated1, .fixed, .last, 0);
    try testing.expectEqualDeep(res1, outputValidated1);

    const p2 = ElementFraction{ .fromStart = 30, .element = .self };
    const gpa2 = GeneralPoint{ .fraction = p2 };
    const ap2 = AnchorPartial{ .point = gpa2 };
    const of2 = OneArgFunctionPartial{ .anchor = ap2 };
    const c2 = Compose{ .ops = &[1]OneArgFunctionPartial{of2} };

    const tp2 = OutputTransformationPair{
        .outputName = "out",
        .operation = c2,
    };
    const outputValidated2 = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp2},
    };
    const v2 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row2 = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v2} };
    const input2 = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row2} };

    const res2 = toExplicitPoint(a, input2, outputValidated2, .fixed, .last, 0);
    try testing.expectError(ToExplicitPointError.CannotDetermineExplicitPoint, res2);

    const f3a = ElementFraction{ .fromStart = 50, .element = ElementReference{ .other = "out2" } };
    const gpa3a = GeneralPoint{ .fraction = f3a };
    const ap3a = AnchorPartial{ .point = gpa3a };
    const of3a = OneArgFunctionPartial{ .anchor = ap3a };
    const c3a = Compose{ .ops = &[1]OneArgFunctionPartial{of3a} };
    const tp3a = OutputTransformationPair{
        .outputName = "out1",
        .operation = c3a,
    };

    const pt3b = inputs.Point{ .x = 1.0, .y = 1.0 };
    const gpa3b = GeneralPoint{ .point = pt3b };
    const ap3b = AnchorPartial{ .point = gpa3b };
    const of3b = OneArgFunctionPartial{ .anchor = ap3b };
    const c3b = Compose{ .ops = &[1]OneArgFunctionPartial{of3b} };
    const tp3b = OutputTransformationPair{
        .outputName = "out2",
        .operation = c3b,
    };

    const outputValidated3 = OutputsValidated{
        .transformationPairs = &[2]OutputTransformationPair{ tp3a, tp3b },
    };
    const v3a = inputs.InputElement{ .vector = inputs.Vector{ .x = 0.0, .y = 1.0 } };
    const v3b = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row3a = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v3a} };
    const row3b = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v3b} };
    const input3 = inputs.Inputs{ .input = &[2]inputs.InputElementRow{ row3a, row3b } };

    const pt3c = inputs.Point{ .x = 1.5, .y = 1.5 };
    const gpa3c = GeneralPoint{ .point = pt3c };
    const ap3c = AnchorPartial{ .point = gpa3c };
    const of3c = OneArgFunctionPartial{ .anchor = ap3c };
    const c3c = Compose{ .ops = &[1]OneArgFunctionPartial{of3c} };
    const tp3c = OutputTransformationPair{
        .outputName = "out1",
        .operation = c3c,
    };

    const outputValidated3post = OutputsValidated{
        .transformationPairs = &[2]OutputTransformationPair{ tp3c, tp3b },
    };
    const res3 = try toExplicitPoint(a, input3, outputValidated3, .fixed, .last, 0);
    try testing.expectEqualDeep(res3, outputValidated3post);

    const f4a = ElementFraction{ .fromStart = 50, .element = ElementReference{ .other = "out2" } };
    const gpa4a = GeneralPoint{ .fraction = f4a };
    const ap4a = AnchorPartial{ .point = gpa4a };
    const of4a = OneArgFunctionPartial{ .anchor = ap4a };
    const c4a = Compose{ .ops = &[1]OneArgFunctionPartial{of4a} };
    const tp4a = OutputTransformationPair{
        .outputName = "out1",
        .operation = c4a,
    };
    const p4 = ElementFraction{ .fromStart = 0, .element = .self };
    const gpa4b = GeneralPoint{ .fraction = p4 };
    const ap4b = AnchorPartial{ .point = gpa4b };
    const of4b = OneArgFunctionPartial{ .anchor = ap4b };
    const c4b = Compose{ .ops = &[1]OneArgFunctionPartial{of4b} };
    const tp4b = OutputTransformationPair{
        .outputName = "out2",
        .operation = c4b,
    };
    const outputValidated4 = OutputsValidated{
        .transformationPairs = &[2]OutputTransformationPair{ tp4a, tp4b },
    };
    const v4a = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row4a = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v4a} };
    const v4b = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row4b = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v4b} };
    const input4 = inputs.Inputs{ .input = &[2]inputs.InputElementRow{ row4a, row4b } };

    const res4 = toExplicitPoint(a, input4, outputValidated4, .fixed, .last, 0);
    try testing.expectError(ToExplicitPointError.CannotDetermineExplicitPoint, res4);

    const f5a = ElementFraction{ .fromStart = -50, .element = ElementReference{ .other = "out2" } };
    const gpa5a = GeneralPoint{ .fraction = f5a };
    const ap5a = AnchorPartial{ .point = gpa5a };
    const of5a = OneArgFunctionPartial{ .anchor = ap5a };
    const c5a = Compose{ .ops = &[1]OneArgFunctionPartial{of5a} };
    const tp5a = OutputTransformationPair{
        .outputName = "out1",
        .operation = c5a,
    };

    const pt5b = inputs.Point{ .x = 1.0, .y = 1.0 };
    const gpa5b = GeneralPoint{ .point = pt5b };
    const ap5b = AnchorPartial{ .point = gpa5b };
    const of5b = OneArgFunctionPartial{ .anchor = ap5b };
    const c5b = Compose{ .ops = &[1]OneArgFunctionPartial{of5b} };
    const tp5b = OutputTransformationPair{
        .outputName = "out2",
        .operation = c5b,
    };

    const outputValidated5 = OutputsValidated{
        .transformationPairs = &[2]OutputTransformationPair{ tp5a, tp5b },
    };
    const v5a = inputs.InputElement{ .vector = inputs.Vector{ .x = 0.0, .y = 1.0 } };
    const v5b = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row5a = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v5a} };
    const row5b = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v5b} };
    const input5 = inputs.Inputs{ .input = &[2]inputs.InputElementRow{ row5a, row5b } };

    const pt5c = inputs.Point{ .x = 0.5, .y = 0.5 };
    const gpa5c = GeneralPoint{ .point = pt5c };
    const ap5c = AnchorPartial{ .point = gpa5c };
    const of5c = OneArgFunctionPartial{ .anchor = ap5c };
    const c5c = Compose{ .ops = &[1]OneArgFunctionPartial{of5c} };
    const tp5c = OutputTransformationPair{
        .outputName = "out1",
        .operation = c5c,
    };

    const outputValidated5post = OutputsValidated{
        .transformationPairs = &[2]OutputTransformationPair{ tp5c, tp5b },
    };
    const res5 = try toExplicitPoint(a, input5, outputValidated5, .fixed, .last, 0);
    try testing.expectEqualDeep(res5, outputValidated5post);

    const f6a = ElementFraction{ .fromStart = 30, .element = ElementReference{ .other = "out1" } };
    const gpa6a = GeneralPoint{ .fraction = f6a };
    const ap6a = AnchorPartial{ .point = gpa6a };
    const of6a = OneArgFunctionPartial{ .anchor = ap6a };
    const c6a = Compose{ .ops = &[1]OneArgFunctionPartial{of6a} };
    const tp6a = OutputTransformationPair{
        .outputName = "out2",
        .operation = c6a,
    };

    const pt6b = inputs.Point{ .x = 1.0, .y = 1.0 };
    const gpa6b = GeneralPoint{ .point = pt6b };
    const ap6b = AnchorPartial{ .point = gpa6b };
    const of6b = OneArgFunctionPartial{ .anchor = ap6b };
    const c6b = Compose{ .ops = &[1]OneArgFunctionPartial{of6b} };
    const tp6b = OutputTransformationPair{
        .outputName = "out1",
        .operation = c6b,
    };

    const outputValidated6 = OutputsValidated{
        .transformationPairs = &[2]OutputTransformationPair{ tp6b, tp6a },
    };
    const v6a = inputs.InputElement{ .vector = inputs.Vector{ .x = 0.0, .y = 1.0 } };
    const v6b = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 0.0 } };
    const v6c = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row6a = inputs.InputElementRow{ .row = &[2]inputs.InputElement{ v6a, v6b } };
    const row6b = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v6c} };
    const input6 = inputs.Inputs{ .input = &[2]inputs.InputElementRow{ row6a, row6b } };

    const pt6c = inputs.Point{ .x = 1.3, .y = 1.3 };
    const gpa6c = GeneralPoint{ .point = pt6c };
    const ap6c = AnchorPartial{ .point = gpa6c };
    const of6c = OneArgFunctionPartial{ .anchor = ap6c };
    const c6c = Compose{ .ops = &[1]OneArgFunctionPartial{of6c} };
    const tp6c = OutputTransformationPair{
        .outputName = "out2",
        .operation = c6c,
    };

    const outputValidated6post = OutputsValidated{
        .transformationPairs = &[2]OutputTransformationPair{ tp6b, tp6c },
    };
    const res6 = try toExplicitPoint(a, input6, outputValidated6, .fixed, .last, 0);
    try testing.expectEqualDeep(res6, outputValidated6post);
}

test "toExplicitPoint coord mode - one anchor" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(1,1)}) with input [[1,1]]
    // One anchor in global frame: begin=(1,1), end=(1,1)+(1,1)=(2,2)
    const tp1a = OutputTransformationPair{
        .outputName = "out",
        .operation = .{
            .ops = &[1]OneArgFunctionPartial{
                .{ .anchor = .{ .point = .{ .point = .{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp1a},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .coord, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 2);

    // begin = (1,1)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    // end = (2,2) - input (1,1) added in global frame
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0, 0.01);
}

test "toExplicitPoint coord mode - compose with two anchors" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(2,2)} & a {(1,1)}) with input [[1,1]]
    // In Compose.ops, they appear in source order: first (2,2), then (1,1)
    // & applies anchors in reverse: first (1,1), then (2,2)
    // Step 0: anchor (1,1) in global frame, input (1,1) -> segment (1,1)->(2,2)
    // Step 1: new frame with origin (1,1), x_axis along (1,1)->(2,2)
    //         anchor (2,2) in local frame -> global (1, 3.828)
    //         input (1,1) in local frame -> global (0, 1.414), end = (1, 5.242)
    // Only last step plotted: (1, 3.828) -> (1, 5.242)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 2.0, .y = 2.0 } } } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .coord, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 2);

    // Only last step plotted: begin=(1,3.828), end=(1,5.242)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 3.828, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 5.242, 0.01);
}

test "toExplicitPoint coord mode - compose with three anchors" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(0,1)} & a {(2,2)} & a {(1,1)}) with input [[1,1]]
    // Only last step plotted in frame after two anchors
    // Frame after anchors (1,1) and (2,2): origin (1, 3.828), x_axis vertical (0,1)
    // Last anchor (0,1) local -> global (0, 3.828)
    // Input (1,1) local -> global (-1, 1), end = (-1, 4.828)
    // Polyline: (0, 3.828) -> (-1, 4.828)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[3]OneArgFunctionPartial{
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 0.0, .y = 1.0 } } } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 2.0, .y = 2.0 } } } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .coord, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 2);

    // Only last step: begin=(1.4472, 2.9340), end=(1.0, 1.5924)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.4472138, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 2.9340003, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 1.0000002, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 1.5923595, 0.01);
}

test "toExplicitPoint coord mode - compose with three anchors input [-1,0]" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(0,1)} & a {(2,2)} & a {(1,1)}) with input [[-1,0]]
    // Only last step plotted
    // Frame after anchors (1,1) and (2,2): origin (1, 3.828), x_axis (-0.8944, -0.4472)
    // Last anchor (0,1) local -> global (1.4472, 2.9340)
    // Input (-1,0) local -> global (0.8944, 0.4472), end = (2.3416, 3.3812)
    // Polyline: (1.4472, 2.9340) -> (2.3416, 3.3812)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[3]OneArgFunctionPartial{
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 0.0, .y = 1.0 } } } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 2.0, .y = 2.0 } } } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = -1.0, .y = 0.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .coord, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 2);

    // Only last step: begin=(1.4472, 2.9340), end=(2.3416, 3.3812)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.4472138, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 2.9340003, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.3416405, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 3.3811657, 0.01);
}

test "toExplicitPoint fixed mode - compose with two anchors" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(2,2)} & a {(1,1)}) with input [[1,1]]
    // & applies in reverse: first (1,1), then (2,2)
    // (a) first we have vector [1,1] anchored at (1,1), which means we have vector starting at (1,1) and ending at (2,2)
    // (b) then second anchor acts, and moves beginning to (2,2) meaning we have vector starting at (2,2) and ending at (3,3)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 2.0, .y = 2.0 } } } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // (a {(2,2)} & a {(1,1)}) with input [[1,1]]
    // i=0: begin (1,1), end (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // i=1: begin (2,2), end (3,3)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 2.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 3.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 3.0);
}

test "toExplicitPoint fixed mode - compose with three anchors" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(0,1)} & a {(2,2)} & a {(1,1)}) with input [[1,1]]
    // (a) first we have vector [1,1] anchored at (1,1), which means we have vector starting at (1,1) and ending at (2,2)
    // (b) then second anchor acts, and moves the beginning to (2,2) meaning we have vector starting at (2,2) and ending at (3,3)
    // (c) then the third anchor acts, and moves the beginning to (0,1)) meaning we have vector starting at (0,1) and ending at (1,2)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = .{
            .ops = &[3]OneArgFunctionPartial{
                .{ .anchor = .{ .point = .{ .point = .{ .x = 0.0, .y = 1.0 } } } },
                .{ .anchor = .{ .point = .{ .point = .{ .x = 2.0, .y = 2.0 } } } },
                .{ .anchor = .{ .point = .{ .point = .{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 6);

    // Forward order: anchors = [(0,1), (2,2), (1,1)], input = (1,1)
    // i=0: begin (1,1), end (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // i=1: begin (2,2), end (3,3)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 2.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 3.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 3.0);

    // i=2: begin (0,1), end (1,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[4].anchor.point.point.x, 0.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[4].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[5].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[5].anchor.point.point.y, 2.0);
}

test "toExplicitPoint origin mode - compose with two anchors" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(2,2)} & a {(1,1)}) with input [[1,1]]
    // (a) after applying of a {(1,1)} on [[1,1]] we have vector with begiining at (1,1) and ending at (2,2)
    // (b) origin is moved to (1,1) in global frame, the same x-axis (now y=1 in global frame) as well as y-axis (now x=1 in global frame), and all constitute a new local frame
    // (c) a {(2,2)} acts in a new local frame. And it moves vector beginning to (2,2) in local frame, which is (3,3) in global frame. The ending of the vector is now at (4,4) in the global frame
    // We output 4 ops: first anchor (begin, end), second anchor (begin, end)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 2.0, .y = 2.0 } } } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .origin, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // (a {(2,2)} & a {(1,1)}) with input [[1,1]]
    // input = (1, 1)
    // First anchor (1,1): begin (1,1), end (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // Second anchor (2,2): begin (3,3), end (4,4)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 3.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 3.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 4.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 4.0);
}

test "toExplicitPoint origin mode - compose with three anchors" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(0,1)} & a {(2,2)} & a {(1,1)}) with input [[1,1]]
    // (a) after applying of a {(1,1)} on [[1,1]] we have vector with begiining at (1,1) and ending at (2,2)
    // (b) origin is moved to (1,1) in global frame, the same x-axis (now y=1 in global frame) as well as y-axis (now x=1 in global frame), and all constitute a new local frame
    // (c) a {(2,2)} acts in a new local frame. And it moves vector beginning to (2,2) in local frame, which is (3,3) in global frame. The ending of the vector is now at (4,4) in the global frame
    // (d) origin is moved to the beginning of the vector, that is (3,3) in global frame, the same x-axis (now y=3 in global frame) as well as y-axis (now x=3 in global frame), and all constitute a new local frame
    // (e) a {(0,1)} acts in a new local frame. And it moves vector beginning to (0,1) in local frame, which is (2,3) in global frame. The ending of the vector is now at (3,4) in the global frame
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = .{
            .ops = &[3]OneArgFunctionPartial{
                .{ .anchor = .{ .point = .{ .point = .{ .x = 0.0, .y = 1.0 } } } },
                .{ .anchor = .{ .point = .{ .point = .{ .x = 2.0, .y = 2.0 } } } },
                .{ .anchor = .{ .point = .{ .point = .{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .origin, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 6);

    // i=0: begin = (1,1), end = (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // i=1: begin = (3,3), end = (4,4)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 3.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 3.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 4.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 4.0);

    // i=2: begin = (3,4), end = (4,5)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[4].anchor.point.point.x, 3.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[4].anchor.point.point.y, 4.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[5].anchor.point.point.x, 4.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[5].anchor.point.point.y, 5.0);
}

test "toExplicitPoint origin mode - compose with three anchors input [-1,0]" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(0,1)} & a {(2,2)} & a {(1,1)}) with input [[-1,0]]
    // (a) after applying of a {(1,1)} on [[-1,0]] we have vector with begining at (1,1) and ending at (0,1)
    // (b) origin is moved to (1,1) in global frame, the same x-axis (now y=1 in global frame) as well as y-axis (now x=1 in global frame), and all constitute a new local frame
    // (c) a {(2,2)} acts in a new local frame. And it moves vector beginning to (2,2) in local frame, which is (3,3) in global frame. The ending of the vector is now at (2,3) in the global frame
    // (d) origin is moved to the beginning of the vector, that is (3,3) in global frame, the same x-axis (now y=3 in global frame) as well as y-axis (now x=3 in global frame), and all constitute a new local frame
    // (e) a {(0,1)} acts in a new local frame constituted in (d). And it moves vector beginning to (0,1) in the current local frame, which is (3,4) in global frame. The ending of the vector is now at (2,4) in the global frame
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = .{
            .ops = &[3]OneArgFunctionPartial{
                .{ .anchor = .{ .point = .{ .point = .{ .x = 0.0, .y = 1.0 } } } },
                .{ .anchor = .{ .point = .{ .point = .{ .x = 2.0, .y = 2.0 } } } },
                .{ .anchor = .{ .point = .{ .point = .{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = -1.0, .y = 0.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .origin, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 6);

    // (a {(0,1)} & a {(2,2)} & a {(1,1)}) with input [[-1,0]]
    // First anchor (1,1): begin (1,1), end (0,1)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 0.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 1.0, 0.01);

    // Second anchor (2,2): begin (3,3), end (2,3)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 3.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 3.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 2.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 3.0, 0.01);

    // Third anchor (0,1): begin (3,4), end (2,4)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.x, 3.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.y, 4.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.x, 2.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.y, 4.0, 0.01);
}

test "toExplicitPoint fixed mode - compose with two anchors multi-segment input" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(2,2)} & a {(1,1)}) with input [[1,1],[1,-1]]
    // Fixed mode sums all vectors: (1+1, 1+(-1)) = (2, 0)
    // Anchors reversed: [(1,1), (2,2)]
    // i=0: begin=(1,1), end=(1+2,1+0)=(3,1)
    // i=1: begin=(2,2), end=(2+2,2+0)=(4,2)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 2.0, .y = 2.0 } } } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v1 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const v2 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = -1.0 } };
    const row = inputs.InputElementRow{ .row = &[2]inputs.InputElement{ v1, v2 } };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // i=0: begin=(1,1), end=(3,1)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 3.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 1.0, 0.01);

    // i=1: begin=(2,2), end=(4,2)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 2.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 2.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 4.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 2.0, 0.01);
}

test "toExplicitPoint origin mode - compose with two anchors multi-segment input" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(2,2)} & a {(1,1)}) with input [[1,1],[1,-1]]
    // Origin mode sums all vectors: (1+1, 1+(-1)) = (2, 0)
    // Anchors reversed: [(1,1), (2,2)]
    // i=0: p=(1,1), origin=(0,0), begin=(1,1), end=(3,1), origin becomes (1,1)
    // i=1: p=(2,2), origin=(1,1), begin=(3,3), end=(5,3)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 2.0, .y = 2.0 } } } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v1 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const v2 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = -1.0 } };
    const row = inputs.InputElementRow{ .row = &[2]inputs.InputElement{ v1, v2 } };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .origin, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // i=0: begin=(1,1), end=(3,1)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 3.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 1.0, 0.01);

    // i=1: begin=(3,3), end=(5,3)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 3.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 3.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 5.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 3.0, 0.01);
}

test "toExplicitPoint coord mode - compose with three anchors multi-segment input" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(0,1)} & a {(2,2)} & a {(1,1)}) with input [[1,1],[1,-1]]
    // Frame after anchors (1,1) and (2,2): origin=(1.0,3.8284), x_axis=(-0.8944,-0.4472), perp=(0.4472,-0.8944)
    // Last anchor (0,1) local -> global (1.4472, 2.9340)
    // Apply [1,1] in frame: end1 = (1.0000, 1.5924)
    // Apply [1,-1] from end1: end2 = (-0.3416, 2.0396)
    // Polyline: (1.4472, 2.9340) -> (1.0000, 1.5924) -> (-0.3416, 2.0396)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = .{
            .ops = &[3]OneArgFunctionPartial{
                .{ .anchor = .{ .point = .{ .point = .{ .x = 0.0, .y = 1.0 } } } },
                .{ .anchor = .{ .point = .{ .point = .{ .x = 2.0, .y = 2.0 } } } },
                .{ .anchor = .{ .point = .{ .point = .{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v1 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const v2 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = -1.0 } };
    const row = inputs.InputElementRow{ .row = &[2]inputs.InputElement{ v1, v2 } };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .coord, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 3);

    // Point 0: begin at last anchor global
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.4472, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 2.9340, 0.01);

    // Point 1: after applying [1,1] in frame
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 1.0000, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 1.5924, 0.01);

    // Point 2: after applying [1,-1] in frame
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, -0.3416, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 2.0396, 0.01);
}

test "toExplicitPoint coord mode all - compose with two anchors multi-segment" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(2,2)} & a {(1,1)}) with input [[1,1],[1,-1]]
    // Anchors reversed: [(1,1), (2,2)]
    // Step 0 (global frame, anchor (1,1)): (1,1) -> (2,2) -> (3,1)
    // Step 1 (rotated frame, anchor (2,2)): (2,2) -> (3,3) -> (3.5,2.5)
    // Total ops: 2 * 3 = 6
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 2.0, .y = 2.0 } } } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v1 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const v2 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = -1.0 } };
    const row = inputs.InputElementRow{ .row = &[2]inputs.InputElement{ v1, v2 } };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .coord, .all, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 6);

    // Step 0: (1,1) -> (2,2) -> (3,1)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 3.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.0, 0.01);

    // Step 1: (1, 3.828) -> (1, 5.243) -> (2.414, 5.243)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 3.8284, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.y, 5.2426, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.x, 2.4142, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.y, 5.2426, 0.01);
}

test "toExplicitPoint coord mode all - compose with three anchors multi-segment" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (a {(0,1)} & a {(2,2)} & a {(1,1)}) with input [[1,1]]
    // Anchors reversed: [(1,1), (2,2), (0,1)]
    // Step 0 (global frame, anchor (1,1)): (1,1) -> (2,2)
    // Step 1 (frame after (1,1)->(2,2), anchor (2,2)): frame origin=(1,1), x_axis=(0.707,0.707)
    //   anchor (2,2) local -> global: line intersection at (2,2)
    //   input [1,1] in frame -> (2.707, 3.707)
    //   Polyline: (2,2) -> (2.707, 3.707)
    // Step 2 (frame after (2,2)->(0,1), anchor (0,1)): frame origin=(2,2), x_axis=(-0.894,-0.447)
    //   anchor (0,1) local -> global: (1.447, 2.934)
    //   input [1,1] in frame -> (1.0, 1.592)
    //   Polyline: (1.447, 2.934) -> (1.0, 1.592)
    // Total ops: 3 * 2 = 6
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = .{
            .ops = &[3]OneArgFunctionPartial{
                .{ .anchor = .{ .point = .{ .point = .{ .x = 0.0, .y = 1.0 } } } },
                .{ .anchor = .{ .point = .{ .point = .{ .x = 2.0, .y = 2.0 } } } },
                .{ .anchor = .{ .point = .{ .point = .{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .coord, .all, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 6);

    // Step 0: (1,1) -> (2,2)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0, 0.01);

    // Step 1: (1, 3.828) -> (1, 5.243)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 3.8284, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 5.2426, 0.01);

    // Step 2: (1.447, 2.934) -> (1.0, 1.592)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.x, 1.4472, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.y, 2.9340, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.y, 1.5924, 0.01);
}

test "toExplicitPoint - compose with anchor and rotation" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (rotate [45 a (0% self)] & a {(1,1)}) with input [[1,1]]
    // & applies in reverse: first anchor (1,1), then rotate
    // (a) first we have vector [1,1] anchored at (1,1), which means we have vector starting at (1,1) and ending at (2,2)
    // (b) then rotation acts, and as we rotate around the beginning of itself, ie (1,1), we have the resultant vector starting at (1,1) and ending at (1,1+sqrt(2))
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const p1 = GeneralPoint{ .fraction = f1 };
    const r1arg = RotateArg{ .phi = 45.0, .point = p1 };
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = try a.dupe(RotateArg, &[1]RotateArg{r1arg}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // i=0: begin (1,1), end (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // i=1: begin (1,1), end (1,1+sqrt(2))
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 1.0);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 2.414, 0.01);
}

test "toExplicitPoint - compose with anchor and rotation multi-segment" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (rotate 45 (beg self)) & (anchor {(1,1)}) with input [[1,1],[1,-1]]
    // & applies in reverse: first anchor (1,1), then rotate
    // Input sum: (2,0)
    // (a) anchor at (1,1): segment from (1,1) to (3,1)
    // (b) rotate around beginning of self (= (1,1)) by 45°: segment from (1,1) to (2.414, 2.414)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = try a.dupe(RotateArg, &[1]RotateArg{.{ .phi = 45.0, .point = GeneralPoint{ .beginning = .self } }}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v1 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const v2 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = -1.0 } };
    const row = inputs.InputElementRow{ .row = &[2]inputs.InputElement{ v1, v2 } };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 6);

    // Anchor polyline: (1,1) -> (2,2) -> (3,1)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 3.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.0);

    // Rotate polyline: each anchor point rotated around (1,1) by 45°
    // (1,1) -> (1, 2.414) -> (2.414, 2.414)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 1.0);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.y, 2.414, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.x, 2.414, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.y, 2.414, 0.01);
}

test "toExplicitPoint - compose with anchor and rotation 360 multi-segment" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // (rotate 360 (beg self)) & (anchor {(1,1)}) with input [[1,1],[1,-1]]
    // Rotate 360° is identity: both polylines should be identical
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = try a.dupe(RotateArg, &[1]RotateArg{.{ .phi = 360.0, .point = GeneralPoint{ .beginning = .self } }}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v1 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const v2 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = -1.0 } };
    const row = inputs.InputElementRow{ .row = &[2]inputs.InputElement{ v1, v2 } };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 6);

    // Anchor polyline: (1,1) -> (2,2) -> (3,1)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 3.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.0);

    // Rotate polyline: 360° is identity, same as anchor
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 1.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 1.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.x, 2.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.y, 2.0, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.x, 3.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.y, 1.0, 0.01);
}

test "toExplicitPoint - compose with anchor and rotation around end self" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((rotate [45 around (end self)]) & (anchor {(1,1)})) with input [[1,1]]
    // & applies in reverse: first anchor (1,1), then rotate around end of self
    // (a) anchor at (1,1) with vector [1,1]: polyline from (1,1) to (2,2)
    // (b) rotate around end of itself, i.e. (2,2), by 45°:
    //     polyline starts at rotation point (2,2),
    //     then remaining non-rotation point (1,1) rotated around (2,2)
    //     → rotate (1,1) around (2,2) by 45°: (2, 2-√2)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = try a.dupe(RotateArg, &[1]RotateArg{.{ .phi = 45.0, .point = GeneralPoint{ .end = .self } }}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // Anchor polyline: (1,1) -> (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // Rotate polyline: (2,2) -> (2, 2-√2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 2.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 2.0);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 2.0 - std.math.sqrt2, 0.01);
}

test "toExplicitPoint - compose with anchor and rotation around end self multi-segment" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((rotate [45 around (end self)]) & (anchor {(1,1)})) with input [[1,1],[1,-1]]
    // & applies in reverse: first anchor (1,1), then rotate around end of self
    // (a) anchor at (1,1) with vectors [1,1],[1,-1]: polyline (1,1)->(2,2)->(3,1)
    // (b) rotate around end of itself, i.e. (3,1), by 45°:
    //     polyline starts at rotation point (3,1),
    //     then remaining non-rotation points rotated around (3,1)
    //     (1,1)→(1.586, -0.414), (2,2)→(1.586, 1.0)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = try a.dupe(RotateArg, &[1]RotateArg{.{ .phi = 45.0, .point = GeneralPoint{ .end = .self } }}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v1 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const v2 = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = -1.0 } };
    const row = inputs.InputElementRow{ .row = &[2]inputs.InputElement{ v1, v2 } };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 6);

    // Anchor polyline: (1,1) -> (2,2) -> (3,1)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 3.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.0);

    // Rotate polyline: (3,1) -> rotated (1,1) -> rotated (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 3.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 1.0);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.x, 3.0 - std.math.sqrt2, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[4].anchor.point.point.y, 1.0 - std.math.sqrt2, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.x, 3.0 - std.math.sqrt2, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[5].anchor.point.point.y, 1.0, 0.01);
}

test "toExplicitPoint - compose with anchor and rotation around mid self" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((rotate [-45 around (mid self)]) & (anchor {(1,1)})) with input [[1,1]]
    // & applies in reverse: first anchor (1,1), then rotate around midpoint of self
    // (a) anchor at (1,1) with vector [1,1]: polyline (1,1)->(2,2)
    // (b) mid self = (1.5, 1.5), not a polyline vertex, so just rotate all points
    //     rotate (1,1) around (1.5,1.5) by -45°: (1.5-√2/2, 1.5)
    //     rotate (2,2) around (1.5,1.5) by -45°: (1.5+√2/2, 1.5)
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = try a.dupe(RotateArg, &[1]RotateArg{.{ .phi = -45.0, .point = GeneralPoint{ .middle = .self } }}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // Anchor polyline: (1,1) -> (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // Rotate polyline: both points rotated (mid self not a vertex)
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 1.5 - std.math.sqrt2 / 2.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.5, 0.01);

    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 1.5 + std.math.sqrt2 / 2.0, 0.01);
    try testing.expectApproxEqAbs(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 1.5, 0.01);
}

test "toExplicitPoint fixed - compose with anchor and scale 1" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((scale [[1,1]]) & (anchor {(1,1)})) with input [[1,1]]
    // & applies in reverse: first anchor (1,1), then rotate around end of self
    // (a) anchor at (1,1) with vector [1,1]: polyline from (1,1) to (2,2)
    // (b) scale [1,1] does not change anything: polyline from (1,1) to (2,2)
    const v1 = inputs.Vector{ .x = 1.0, .y = 1.0 };
    const s1 = ScaleArg{ .translation = v1 };
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .scale = ScalePartial{ .elements = try a.dupe(ScaleArg, &[1]ScaleArg{s1}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // Anchor polyline: (1,1) -> (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // Rotate polyline: (1,1) -> (2, 2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 2.0);
}

test "toExplicitPoint fixed - compose with anchor and scale 2" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((scale [[3,3]]) & (anchor {(1,1)})) with input [[1,1]]
    // & applies in reverse: first anchor (1,1), then rotate around end of self
    // (a) anchor at (1,1) with vector [1,1]: polyline from (1,1) to (2,2)
    // (b) scale [3,3] does not change anything: polyline from (1,1) to (4,4)
    const v1 = inputs.Vector{ .x = 3.0, .y = 3.0 };
    const s1 = ScaleArg{ .translation = v1 };
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .scale = ScalePartial{ .elements = try a.dupe(ScaleArg, &[1]ScaleArg{s1}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // Anchor polyline: (1,1) -> (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // Rotate polyline: (1,1) -> (4, 4)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 4.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 4.0);
}

test "toExplicitPoint fixed - compose with anchor and scale 3" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((scale [[2,3]]) & (anchor {(1,1)})) with input [[1,1]]
    // & applies in reverse: first anchor (1,1), then rotate around end of self
    // (a) anchor at (1,1) with vector [1,1]: polyline from (1,1) to (2,2)
    // (b) scale [2,3] does not change anything: polyline from (1,1) to (3,4)
    const v1 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s1 = ScaleArg{ .translation = v1 };
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .scale = ScalePartial{ .elements = try a.dupe(ScaleArg, &[1]ScaleArg{s1}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // Anchor polyline: (1,1) -> (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // Rotate polyline: (1,1) -> (3, 4)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 3.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 4.0);
}

test "toExplicitPoint origin - compose with anchor and scale 1" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((scale [[1,1]]) & (anchor {(1,1)})) with input [[1,1]]
    // & applies in reverse: first anchor (1,1), then rotate around end of self
    // (a) anchor at (1,1) with vector [1,1]: polyline from (1,1) to (2,2)
    // (b) scale [1,1] does not change anything: polyline from (2,2) to (3,3)
    const v1 = inputs.Vector{ .x = 1.0, .y = 1.0 };
    const s1 = ScaleArg{ .translation = v1 };
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .scale = ScalePartial{ .elements = try a.dupe(ScaleArg, &[1]ScaleArg{s1}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .origin, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // Anchor polyline: (1,1) -> (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // Rotate polyline: (2,2) -> (3, 3)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 2.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 3.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 3.0);
}

test "toExplicitPoint origin - compose with anchor and scale 2" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((scale [[3,3]]) & (anchor {(1,1)})) with input [[1,1]]
    // & applies in reverse: first anchor (1,1), then rotate around end of self
    // (a) anchor at (1,1) with vector [1,1]: polyline from (1,1) to (2,2)
    // (b) scale [3,3] acts on [1,1] vector: polyline from (1,1) to (4,4) in local frame, ie. (2,2) to (5,5) in global frame
    const v1 = inputs.Vector{ .x = 3.0, .y = 3.0 };
    const s1 = ScaleArg{ .translation = v1 };
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .scale = ScalePartial{ .elements = try a.dupe(ScaleArg, &[1]ScaleArg{s1}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .origin, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // Anchor polyline: (1,1) -> (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // Rotate polyline: (2,2) -> (5, 5)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 2.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 5.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 5.0);
}

test "toExplicitPoint origin - compose with anchor and scale 3" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((scale [[2,3]]) & (anchor {(1,1)})) with input [[1,1]]
    // & applies in reverse: first anchor (1,1), then rotate around end of self
    // (a) anchor at (1,1) with vector [1,1]: polyline from (1,1) to (2,2)
    // (b) scale [2,3] acts on [1,1] vector: polyline from (1,1) to (3,4) in local frame, (2,2) to (4,5) in global frame
    const v1 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s1 = ScaleArg{ .translation = v1 };
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .scale = ScalePartial{ .elements = try a.dupe(ScaleArg, &[1]ScaleArg{s1}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .origin, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // Anchor polyline: (1,1) -> (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // Rotate polyline: (2,2) -> (4, 5)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 2.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.x, 4.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 5.0);
}

test "toExplicitPoint coord - compose with anchor and scale 1" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((scale [[1,1]]) & (anchor {(1,1)})) with input [[1,1]]
    // & applies in reverse: first anchor (1,1), then rotate around end of self
    // (a) anchor at (1,1) with vector [1,1]: polyline from (1,1) to (2,2)
    // (b) scale [1,1] does not affect the vector wrt to new local frame: polyline from (1, 1+sqrt(2)) to (1, 2srqt(2))
    const v1 = inputs.Vector{ .x = 1.0, .y = 1.0 };
    const s1 = ScaleArg{ .translation = v1 };
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .scale = ScalePartial{ .elements = try a.dupe(ScaleArg, &[1]ScaleArg{s1}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .coord, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // Anchor polyline: (1,1) -> (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // Rotate polyline: (1, 1+ sqrt(2)) -> (1, 1 + 2srqt(2))
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.0 + std.math.sqrt(2.0));

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 1.0 + 2.0 * std.math.sqrt(2.0));
}

test "toExplicitPoint coord - compose with anchor and scale 2" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((scale [[3,3]]) & (anchor {(1,1)})) with input [[1,1]]
    // & applies in reverse: first anchor (1,1), then rotate around end of self
    // (a) anchor at (1,1) with vector [1,1]: polyline from (1,1) to (2,2)
    // (b) scale [3,3] does affect the vector wrt to new local frame: polyline from (1, 1+sqrt(2)) to (1, 1 + 4srqt(2))
    const v1 = inputs.Vector{ .x = 3.0, .y = 3.0 };
    const s1 = ScaleArg{ .translation = v1 };
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .scale = ScalePartial{ .elements = try a.dupe(ScaleArg, &[1]ScaleArg{s1}) } },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 1.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .coord, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // Anchor polyline: (1,1) -> (2,2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 2.0);

    // Rotate polyline: (1, 1+ sqrt(2)) -> (1, 1 + 4srqt(2))
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.0 + std.math.sqrt(2.0));

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 1.0 + 4.0 * std.math.sqrt(2.0));
}

test "toExplicitPoint fixed - compose with anchor and mirror 1" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ((mirror (y=x)) & (anchor {(1,1)})) with input [[1,0]]
    // & applies in reverse: first anchor (1,1), then mirror
    // (a) anchor at (1,1) with vector [1,0]: polyline from (1,1) to (2,1)
    // (b) mirror (y=x) reflects vector wrt to y=x: polyline from (1, 1) to (1, 2)
    const l1 = inputs.Line{ .a = 1.0, .b = 1.0, .c = 0.0 };
    const m1 = MirrorPartial{ .line = l1 };
    const tp = OutputTransformationPair{
        .outputName = "out",
        .operation = Compose{
            .ops = &[2]OneArgFunctionPartial{
                OneArgFunctionPartial{ .mirror = m1 },
                OneArgFunctionPartial{ .anchor = AnchorPartial{ .point = GeneralPoint{ .point = inputs.Point{ .x = 1.0, .y = 1.0 } } } },
            },
        },
    };
    const outputValidated = OutputsValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp},
    };

    const v = inputs.InputElement{ .vector = inputs.Vector{ .x = 1.0, .y = 0.0 } };
    const row = inputs.InputElementRow{ .row = &[1]inputs.InputElement{v} };
    const inp = inputs.Inputs{ .input = &[1]inputs.InputElementRow{row} };

    const res = try toExplicitPoint(a, inp, outputValidated, .fixed, .last, 0);

    try testing.expectEqual(res.transformationPairs.len, 1);
    try testing.expectEqual(res.transformationPairs[0].operation.ops.len, 4);

    // Anchor polyline: (1,1) -> (2,1)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[0].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.x, 2.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[1].anchor.point.point.y, 1.0);

    // Mirror polyline: (1, 1) -> (1, 2)
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.x, 1.0);
    try testing.expectEqual(res.transformationPairs[0].operation.ops[2].anchor.point.point.y, 1.0);

    try testing.expectEqual(res.transformationPairs[0].operation.ops[3].anchor.point.point.y, 1.0 + 1.0);
}
