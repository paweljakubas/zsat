const mecha = @import("mecha");
const common = @import("common.zig");
const inputs = @import("inputs.zig");
const std = @import("std");
const testing = std.testing;

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

pub const TwoArgCombinator = enum {
    on, //the left arg is above the right arg
    under, //the left arg is under the right arg
    with, //the left arg is on the same layer level as the right arg
};

pub const OneArgFunctionPartial = union(enum) {
    pin: PinPartial,
    rotate: RotatePartial,
    scale: ScalePartial,
};

//Pin obj to point
pub const PinPartial = struct {
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
fn toOutputsParser(allocator: std.mem.Allocator, names: outputsParserRawP.T) mecha.ConvertError![]Output {
    var arr = try allocator.alloc(Output, names.len);
    var ix: u8 = 0;
    for (names) |theRes| {
        arr[ix] = Output{ .name = theRes };
        ix += 1;
    }
    allocator.free(names);
    return arr;
}
const outputsParser = outputsParserRaw.convert(toOutputsParser);

test "outputsParser" {
    const a = testing.allocator;

    const r1 = try outputsParser.parse(a, "(out)");
    const o1 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const output1 = [1]Output{o1};
    try testing.expectEqualDeep(&output1, r1.value.ok[0..1]);
    a.free(r1.value.ok);

    const r2 = try outputsParser.parse(a, "( out )");
    const o2 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const output2 = [1]Output{o2};
    try testing.expectEqualDeep(&output2, r2.value.ok[0..1]);
    a.free(r2.value.ok);

    const r3 = try outputsParser.parse(a, "( out1, out2 )");
    const o3a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const o3b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const output3 = [2]Output{ o3a, o3b };
    try testing.expectEqualDeep(&output3, r3.value.ok[0..2]);
    a.free(r3.value.ok);

    const r4 = try outputsParser.parse(a, "( out1, out2, txt1 )");
    const o4a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const o4b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const o4c = Output{ .name = &[_]u8{ 't', 'x', 't', '1' } };
    const output4 = [3]Output{ o4a, o4b, o4c };
    try testing.expectEqualDeep(&output4, r4.value.ok[0..3]);
    a.free(r4.value.ok);
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
    return RotatePartial{ .elements = res };
}
const rotatePartialParser = rotatePartialParserRaw.convert(toRotatePartial);

test "rotatePartialParser" {
    const a = testing.allocator;

    const r1 = try rotatePartialParser.parse(a, "rotate [90 a (0% self)]");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const p1 = GeneralPoint{ .fraction = f1 };
    const r1arg = RotateArg{ .phi = 90.0, .point = p1 };
    try testing.expectEqual(@as(usize, 1), r1.value.ok.elements.len);
    try testing.expectEqualDeep(r1arg, r1.value.ok.elements[0]);
    a.free(r1.value.ok.elements);

    const r2 = try rotatePartialParser.parse(a, "r [-120 a (10% self)]");
    const f2 = ElementFraction{ .fromStart = 10, .element = .self };
    const p2 = GeneralPoint{ .fraction = f2 };
    const r2arg = RotateArg{ .phi = -120.0, .point = p2 };
    try testing.expectEqual(@as(usize, 1), r2.value.ok.elements.len);
    try testing.expectEqualDeep(r2arg, r2.value.ok.elements[0]);
    a.free(r2.value.ok.elements);

    const r3 = try rotatePartialParser.parse(a, " rotate [0 around ( beg self) , -1234.9 a {(-12,2.1)} ]");
    const p3a = GeneralPoint{ .beginning = .self };
    const r3a = RotateArg{ .phi = 0.0, .point = p3a };
    const p3b = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp3 = GeneralPoint{ .point = p3b };
    const r3b = RotateArg{ .phi = -1234.9, .point = gp3 };
    try testing.expectEqual(@as(usize, 2), r3.value.ok.elements.len);
    try testing.expectEqualDeep(r3a, r3.value.ok.elements[0]);
    try testing.expectEqualDeep(r3b, r3.value.ok.elements[1]);
    a.free(r3.value.ok.elements);

    const r4 = try rotatePartialParser.parse(a, "(r [-120 a (10% self)])");
    const f4 = ElementFraction{ .fromStart = 10, .element = .self };
    const p4 = GeneralPoint{ .fraction = f4 };
    const r4arg = RotateArg{ .phi = -120.0, .point = p4 };
    try testing.expectEqual(@as(usize, 1), r4.value.ok.elements.len);
    try testing.expectEqualDeep(r4arg, r4.value.ok.elements[0]);
    a.free(r4.value.ok.elements);
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
fn toScalePartial(allocator: std.mem.Allocator, res: scalePartialParserRawP.T) mecha.ConvertError!ScalePartial {
    var args = try allocator.alloc(ScaleArg, res.len);
    for (res, 0..) |v, i| {
        args[i] = ScaleArg{ .translation = v };
    }
    allocator.free(res);
    return ScalePartial{ .elements = args };
}
const scalePartialParser = scalePartialParserRaw.convert(toScalePartial);

test "scalePartialParser" {
    const a = testing.allocator;

    const r1 = try scalePartialParser.parse(a, "scale [[2,3]]");
    const v1 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s1 = ScaleArg{ .translation = v1 };
    try testing.expectEqual(@as(usize, 1), r1.value.ok.elements.len);
    try testing.expectEqualDeep(s1, r1.value.ok.elements[0]);
    a.free(r1.value.ok.elements);

    const r2 = try scalePartialParser.parse(a, "s by [[2.1,3.1]]");
    const v2 = inputs.Vector{ .x = 2.1, .y = 3.1 };
    const s2 = ScaleArg{ .translation = v2 };
    try testing.expectEqual(@as(usize, 1), r2.value.ok.elements.len);
    try testing.expectEqualDeep(s2, r2.value.ok.elements[0]);
    a.free(r2.value.ok.elements);

    const r3 = try scalePartialParser.parse(a, "s by [[2.1,3.1], [-10.0, 1.1e+03]]");
    const v3a = inputs.Vector{ .x = 2.1, .y = 3.1 };
    const v3b = inputs.Vector{ .x = -10.0, .y = 1100.0 };
    const s3a = ScaleArg{ .translation = v3a };
    const s3b = ScaleArg{ .translation = v3b };
    try testing.expectEqual(@as(usize, 2), r3.value.ok.elements.len);
    try testing.expectEqualDeep(s3a, r3.value.ok.elements[0]);
    try testing.expectEqualDeep(s3b, r3.value.ok.elements[1]);
    a.free(r3.value.ok.elements);

    const r4 = try scalePartialParser.parse(a, "(s by [[2.1,3.1]])");
    const v4 = inputs.Vector{ .x = 2.1, .y = 3.1 };
    const s4 = ScaleArg{ .translation = v4 };
    try testing.expectEqual(@as(usize, 1), r4.value.ok.elements.len);
    try testing.expectEqualDeep(s4, r4.value.ok.elements[0]);
    a.free(r4.value.ok.elements);
}

const pinPartialParserRawWithout = mecha.combine(.{
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("pin"),
        mecha.string("p"),
    }).discard(),
    common.skipWhitespace,
    mecha.combine(.{
        mecha.string("at").discard(),
    }).opt().discard(),
    common.skipWhitespace,
    generalPointParser,
});
const pinPartialParserRawWith = mecha.combine(.{
    common.skipOpenBracket,
    common.skipWhitespace,
    mecha.oneOf(.{
        mecha.string("pin"),
        mecha.string("p"),
    }).discard(),
    common.skipWhitespace,
    mecha.combine(.{
        mecha.string("at").discard(),
    }).opt().discard(),
    common.skipWhitespace,
    generalPointParser,
    common.skipWhitespace,
    common.skipCloseBracket,
});

const pinPartialParserRaw = mecha.oneOf(.{
    pinPartialParserRawWith,
    pinPartialParserRawWithout,
});
const pinPartialParserRawP = @TypeOf(pinPartialParserRaw);
fn toPinPartial(_: std.mem.Allocator, a: anytype) mecha.ConvertError!PinPartial {
    return PinPartial{ .point = a };
}
const pinPartialParser = pinPartialParserRaw.convert(toPinPartial);

test "pinPartialParser" {
    const fa = testing.failing_allocator;

    const r1 = try pinPartialParser.parse(fa, "pin (0% self)");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const o1 = PinPartial{ .point = gp1 };
    try testing.expectEqualDeep(o1, r1.value.ok);

    const r2 = try pinPartialParser.parse(fa, "p (10% self)");
    const f2 = ElementFraction{ .fromStart = 10, .element = .self };
    const gp2 = GeneralPoint{ .fraction = f2 };
    const o2 = PinPartial{ .point = gp2 };
    try testing.expectEqualDeep(o2, r2.value.ok);

    const r3 = try pinPartialParser.parse(fa, "pin at ( beg self)");
    const gp3 = GeneralPoint{ .beginning = .self };
    const o3 = PinPartial{ .point = gp3 };
    try testing.expectEqualDeep(o3, r3.value.ok);

    const r4 = try pinPartialParser.parse(fa, "pin (beginning dot1)");
    const gp4 = GeneralPoint{ .beginning = ElementReference{ .other = "dot1" } };
    const o4 = PinPartial{ .point = gp4 };
    try testing.expectEqualDeep(o4, r4.value.ok);

    const r5 = try pinPartialParser.parse(fa, "p (b dot1)");
    const gp5 = GeneralPoint{ .beginning = ElementReference{ .other = "dot1" } };
    const o5 = PinPartial{ .point = gp5 };
    try testing.expectEqualDeep(o5, r5.value.ok);

    const r6 = try pinPartialParser.parse(fa, "pin at (end     self)");
    const gp6 = GeneralPoint{ .end = .self };
    const o6 = PinPartial{ .point = gp6 };
    try testing.expectEqualDeep(o6, r6.value.ok);

    const r7 = try pinPartialParser.parse(fa, "p (e vec1)");
    const gp7 = GeneralPoint{ .end = ElementReference{ .other = "vec1" } };
    const o7 = PinPartial{ .point = gp7 };
    try testing.expectEqualDeep(o7, r7.value.ok);

    const r8 = try pinPartialParser.parse(fa, "p (m vec1)");
    const gp8 = GeneralPoint{ .middle = ElementReference{ .other = "vec1" } };
    const o8 = PinPartial{ .point = gp8 };
    try testing.expectEqualDeep(o8, r8.value.ok);

    const r9 = try pinPartialParser.parse(fa, "pin at (mid vec1)");
    const gp9 = GeneralPoint{ .middle = ElementReference{ .other = "vec1" } };
    const o9 = PinPartial{ .point = gp9 };
    try testing.expectEqualDeep(o9, r9.value.ok);

    const r10 = try pinPartialParser.parse(fa, "pin at (middle vec1)");
    const gp10 = GeneralPoint{ .middle = ElementReference{ .other = "vec1" } };
    const o10 = PinPartial{ .point = gp10 };
    try testing.expectEqualDeep(o10, r10.value.ok);

    const r11 = try pinPartialParser.parse(fa, "p at {(-12,2.1)} ");
    const p11 = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp11 = GeneralPoint{ .point = p11 };
    const o11 = PinPartial{ .point = gp11 };
    try testing.expectEqualDeep(o11, r11.value.ok);

    const r12 = try pinPartialParser.parse(fa, "(pin at ( beg self))");
    const gp12 = GeneralPoint{ .beginning = .self };
    const o12 = PinPartial{ .point = gp12 };
    try testing.expectEqualDeep(o12, r12.value.ok);

    const r13 = try pinPartialParser.parse(fa, "( p at {(-12,2.1)} )");
    const p13 = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp13 = GeneralPoint{ .point = p13 };
    const o13 = PinPartial{ .point = gp13 };
    try testing.expectEqualDeep(o13, r13.value.ok);
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
fn toScalePartialUnion(allocator: std.mem.Allocator, res: scalePartialParserRawP.T) mecha.ConvertError!OneArgFunctionPartial {
    errdefer allocator.free(res);
    var args = try allocator.alloc(ScaleArg, res.len);
    errdefer allocator.free(args);
    for (res, 0..) |v, i| {
        args[i] = ScaleArg{ .translation = v };
    }
    allocator.free(res);
    const s = ScalePartial{ .elements = args };
    return OneArgFunctionPartial{ .scale = s };
}
const scalePartialUnionParser = scalePartialParserRaw.convert(toScalePartialUnion);
fn toPinPartialUnion(_: std.mem.Allocator, res: anytype) mecha.ConvertError!OneArgFunctionPartial {
    const p = PinPartial{ .point = res };
    return OneArgFunctionPartial{ .pin = p };
}
const pinPartialUnionParser = pinPartialParserRaw.convert(toPinPartialUnion);

const oneArgFunctionPartialParser = mecha.oneOf(.{
    pinPartialUnionParser,
    rotatePartialUnionParser,
    scalePartialUnionParser,
});

test "oneArgFunctionPartialParser" {
    const fa = testing.failing_allocator;

    const r1 = try oneArgFunctionPartialParser.parse(fa, "pin (0% self)");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const p1 = PinPartial{ .point = gp1 };
    const o1 = OneArgFunctionPartial{ .pin = p1 };
    try testing.expectEqualDeep(o1, r1.value.ok);

    const a = testing.allocator;

    const r2 = try oneArgFunctionPartialParser.parse(a, "scale [[2,3]]");
    const v2 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s2 = ScaleArg{ .translation = v2 };
    const o2 = OneArgFunctionPartial{ .scale = ScalePartial{ .elements = try a.dupe(ScaleArg, &[1]ScaleArg{s2}) } };
    try testing.expectEqualDeep(o2, r2.value.ok);
    a.free(r2.value.ok.scale.elements);
    a.free(o2.scale.elements);

    const r3 = try oneArgFunctionPartialParser.parse(a, " rotate [0 around ( beg self) , -1234.9 a {(-12,2.1)} ]");
    const p3a = GeneralPoint{ .beginning = .self };
    const r3a = RotateArg{ .phi = 0.0, .point = p3a };
    const p3b = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp3 = GeneralPoint{ .point = p3b };
    const r3b = RotateArg{ .phi = -1234.9, .point = gp3 };
    const o3 = OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = try a.dupe(RotateArg, &[2]RotateArg{ r3a, r3b }) } };
    try testing.expectEqualDeep(o3, r3.value.ok);
    a.free(r3.value.ok.rotate.elements);
    a.free(o3.rotate.elements);

    const r4 = try oneArgFunctionPartialParser.parse(a, "(r [-120 a (10% self)])");
    const f4 = ElementFraction{ .fromStart = 10, .element = .self };
    const p4 = GeneralPoint{ .fraction = f4 };
    const r4a = RotateArg{ .phi = -120.0, .point = p4 };
    const o4 = OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = try a.dupe(RotateArg, &[1]RotateArg{r4a}) } };
    try testing.expectEqualDeep(o4, r4.value.ok);
    a.free(r4.value.ok.rotate.elements);
    a.free(o4.rotate.elements);
}

fn compositeToInside(allocator: std.mem.Allocator, a: Composite) mecha.ConvertError!CompositeInside {
    const p = try allocator.create(Composite);
    errdefer allocator.destroy(p);
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

fn parseTrainInner(allocator: std.mem.Allocator, args: anytype) mecha.ConvertError!*Train {
    const left = args[0];
    const middle = args[1];
    const right = args[2];
    const train = try allocator.create(Train);
    errdefer allocator.destroy(train);
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

fn parseHookInner(allocator: std.mem.Allocator, args: anytype) mecha.ConvertError!*Hook {
    const left = args[0];
    const right = args[1];
    const hook = try allocator.create(Hook);
    errdefer allocator.destroy(hook);
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

fn parseTrain(allocator: std.mem.Allocator, t: *Train) mecha.ConvertError!Train {
    const result = t.*;
    allocator.destroy(t);
    return result;
}

const trainParser = mecha.combine(.{
    common.skipOpenBracket,
    trainParserInner,
    common.skipCloseBracket,
}).convert(parseTrain);

fn parseHook(allocator: std.mem.Allocator, h: *Hook) mecha.ConvertError!Hook {
    const result = h.*;
    allocator.destroy(h);
    return result;
}

const hookParser = mecha.combine(.{
    common.skipOpenBracket,
    hookParserInner,
    common.skipCloseBracket,
}).convert(parseHook);

fn freeCompositeInside(a: std.mem.Allocator, ci: CompositeInside) void {
    if (ci == .inside) {
        const comp = ci.inside;
        switch (comp.*) {
            .train => |tr| a.destroy(tr),
            .hook => |hk| a.destroy(hk),
        }
        a.destroy(comp);
    }
}

fn freeOneArgFunctionPartial(a: std.mem.Allocator, oa: OneArgFunctionPartial) void {
    switch (oa) {
        .scale => |scalepart| a.free(scalepart.elements),
        .pin => {},
        .rotate => |rotatepart| a.free(rotatepart.elements),
    }
}

fn freeTrain(a: std.mem.Allocator, tr: Train) void {
    freeCompositeInside(a, tr.left);
    freeCompositeInside(a, tr.right);
    switch (tr.left) {
        .stop => |onearg| freeOneArgFunctionPartial(a, onearg),
        .inside => {},
    }
    switch (tr.right) {
        .stop => |onearg| freeOneArgFunctionPartial(a, onearg),
        .inside => {},
    }
}

fn freeHook(a: std.mem.Allocator, hk: Hook) void {
    switch (hk.left) {
        .stop => |onearg| {
            switch (onearg) {
                .scale => |scalepart| {
                    a.free(scalepart.elements);
                },
                .pin => {},
                .rotate => |rotatepart| a.free(rotatepart.elements),
            }
        },
        .inside => |comp| {
            switch (comp.*) {
                .train => |tr| freeTrain(a, tr.*),
                .hook => |hk_inner| freeHook(a, hk_inner.*),
            }
            a.destroy(comp);
        },
    }
}

test "hookParser" {
    const a = testing.allocator;

    const r1 = try hookParser.parse(a, "((pin (0% self)) with)");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const p1 = PinPartial{ .point = gp1 };
    const o1 = OneArgFunctionPartial{ .pin = p1 };
    const h1 = Hook{ .left = CompositeInside{ .stop = o1 }, .right = .with };
    try testing.expectEqualDeep(h1, r1.value.ok);
    freeHook(a, r1.value.ok);

    const r2 = try hookParser.parse(a, "((scale [[2,3]]) under)");
    const v2 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s2 = ScaleArg{ .translation = v2 };
    const alloc2 = try a.dupe(ScaleArg, &[1]ScaleArg{s2});
    const o2 = OneArgFunctionPartial{ .scale = ScalePartial{ .elements = alloc2 } };
    const h2 = Hook{ .left = CompositeInside{ .stop = o2 }, .right = .under };
    try testing.expectEqualDeep(h2, r2.value.ok);
    freeHook(a, r2.value.ok);
    a.free(alloc2);
}

test "trainParser" {
    const a = testing.allocator;

    const r1 = try trainParser.parse(a, "((pin (0% self)) with (pin {(-12,2.1)}))");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1a = GeneralPoint{ .fraction = f1 };
    const p1a = PinPartial{ .point = gp1a };
    const o1a = OneArgFunctionPartial{ .pin = p1a };

    const p1b_point = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp1b = GeneralPoint{ .point = p1b_point };
    const p1b = PinPartial{ .point = gp1b };
    const o1b = OneArgFunctionPartial{ .pin = p1b };

    const t1 = Train{ .left = CompositeInside{ .stop = o1a }, .middle = .with, .right = CompositeInside{ .stop = o1b } };
    try testing.expectEqualDeep(t1, r1.value.ok);
    freeTrain(a, r1.value.ok);

    const r2 = try trainParser.parse(a, "((r [-120 a (10% self)]) with (pin {(-12,2.1)}))");

    const f2 = ElementFraction{ .fromStart = 10, .element = .self };
    const p2 = GeneralPoint{ .fraction = f2 };
    const r2a = RotateArg{ .phi = -120.0, .point = p2 };
    const alloc2 = try a.dupe(RotateArg, &[1]RotateArg{r2a});
    const o2a = OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = alloc2 } };

    const p2b_point = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp2b = GeneralPoint{ .point = p2b_point };
    const p2b = PinPartial{ .point = gp2b };
    const o2b = OneArgFunctionPartial{ .pin = p2b };

    const t2 = Train{ .left = CompositeInside{ .stop = o2a }, .middle = .with, .right = CompositeInside{ .stop = o2b } };
    try testing.expectEqualDeep(t2, r2.value.ok);
    freeTrain(a, r2.value.ok);
    a.free(alloc2);

    //    const r3 = try trainParser.parse(a, "(((r [-120 a (10% self)])) with (pin {(-12,2.1)}))");
    //    undefined;
    //
    //    const r4 = try trainParser.parse(a, " ( (((r [-120 a (10% self)])) on (scale [[2,3]])) with (pin {(-12,2.1)}))");
    //    undefined;
}
