const std = @import("std");
const testing = std.testing;

const mecha = @import("mecha");

const common = @import("common.zig");
const inputs = @import("inputs.zig");

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
    pin: AnchorPartial,
    rotate: RotatePartial,
    scale: ScalePartial,
    mirror: MirrorPartial,
};

//Pin obj to point
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
        mecha.string("pin"),
        mecha.string("p"),
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
        mecha.string("pin"),
        mecha.string("p"),
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

    const r11 = try anchorPartialParser.parse(fa, "p {(-12,2.1)} ");
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
    return OneArgFunctionPartial{ .pin = p };
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

    const r1 = try oneArgFunctionPartialParser.parse(a, "pin (0% self)");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const p1 = AnchorPartial{ .point = gp1 };
    const o1 = OneArgFunctionPartial{ .pin = p1 };
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

    const r1 = try hookParser.parse(a, "((pin (0% self)) with)");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const p1 = AnchorPartial{ .point = gp1 };
    const o1 = OneArgFunctionPartial{ .pin = p1 };
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

    const r1 = try trainParser.parse(a, "((pin (0% self)) with (pin {(-12,2.1)}))");
    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1a = GeneralPoint{ .fraction = f1 };
    const p1a = AnchorPartial{ .point = gp1a };
    const o1a = OneArgFunctionPartial{ .pin = p1a };

    const p1b_point = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp1b = GeneralPoint{ .point = p1b_point };
    const p1b = AnchorPartial{ .point = gp1b };
    const o1b = OneArgFunctionPartial{ .pin = p1b };

    const t1 = Train{ .left = CompositeInside{ .stop = o1a }, .middle = .with, .right = CompositeInside{ .stop = o1b } };
    try testing.expectEqualDeep(t1, r1.value.ok);

    const r2 = try trainParser.parse(a, "((r [-120 a (10% self)]) with (pin {(-12,2.1)}))");

    const f2 = ElementFraction{ .fromStart = 10, .element = .self };
    const p2 = GeneralPoint{ .fraction = f2 };
    const r2a = RotateArg{ .phi = -120.0, .point = p2 };
    const alloc2 = try a.dupe(RotateArg, &[1]RotateArg{r2a});
    const o2a = OneArgFunctionPartial{ .rotate = RotatePartial{ .elements = alloc2 } };

    const p2b_point = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp2b = GeneralPoint{ .point = p2b_point };
    const p2b = AnchorPartial{ .point = gp2b };
    const o2b = OneArgFunctionPartial{ .pin = p2b };

    const t2 = Train{ .left = CompositeInside{ .stop = o2a }, .middle = .with, .right = CompositeInside{ .stop = o2b } };
    try testing.expectEqualDeep(t2, r2.value.ok);

    //
    const r3 = try trainParser.parse(a, "((scale [[2,3]] on) with (pin {(-12,2.1)}))");

    const v3 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s3 = ScaleArg{ .translation = v3 };
    const alloc3 = try a.dupe(ScaleArg, &[1]ScaleArg{s3});
    const o3 = OneArgFunctionPartial{ .scale = ScalePartial{ .elements = alloc3 } };
    const h3 = Hook{ .left = CompositeInside{ .stop = o3 }, .right = .on };

    const p3b_point = inputs.Point{ .x = -12.0, .y = 2.1 };
    const gp3b = GeneralPoint{ .point = p3b_point };
    const p3b = AnchorPartial{ .point = gp3b };
    const o3b = OneArgFunctionPartial{ .pin = p3b };

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

    const r1 = try composeParser.parse(a, "(pin (0% self) & scale [[2,3]])");

    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const p1 = AnchorPartial{ .point = gp1 };
    const o1 = OneArgFunctionPartial{ .pin = p1 };
    const v2 = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s2 = ScaleArg{ .translation = v2 };
    const alloc2 = try a.dupe(ScaleArg, &[1]ScaleArg{s2});
    const o2 = OneArgFunctionPartial{ .scale = ScalePartial{ .elements = alloc2 } };

    const c1 = Compose{ .ops = &[2]OneArgFunctionPartial{ o1, o2 } };
    try testing.expectEqualDeep(c1, r1.value.ok);

    const r2 = try composeParser.parse(a, "(p {(1,2)} & scale [[2,3]] & r [-120 a (10% self)])");
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

    const r1 = try outputTransformationPairParser.parse(a, "(pin (0% self)) out");

    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gp1 = GeneralPoint{ .fraction = f1 };
    const p1 = AnchorPartial{ .point = gp1 };
    const o1 = OneArgFunctionPartial{ .pin = p1 };
    const c1 = Compose{ .ops = &[1]OneArgFunctionPartial{o1} };

    const out1 = OutputTransformationPair{
        .outputName = "out",
        .operation = c1,
    };
    try testing.expectEqualDeep(out1, r1.value.ok);

    const r2 = try outputTransformationPairParser.parse(a, "(pin {(1,2)} & scale [[2,3]]) out1");

    const pt2 = inputs.Point{ .x = 1.0, .y = 2 };
    const gp2 = GeneralPoint{ .point = pt2 };
    const p2 = AnchorPartial{ .point = gp2 };
    const o2a = OneArgFunctionPartial{ .pin = p2 };
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
pub const connectionParser = mecha.oneOf(.{
    connectionParserRawMultiple,
    connectionParserRawSingle,
});

test "connectionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try connectionParser.parse(a, "(out) -> (pin (0% self)) out");

    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gpa1 = GeneralPoint{ .fraction = f1 };
    const ap1 = AnchorPartial{ .point = gpa1 };
    const of1 = OneArgFunctionPartial{ .pin = ap1 };
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

    const r2 = try connectionParser.parse(a, "(out1, out2) -> ( (pin (30% self)) out1, (pin {(1,2)} & scale [[2,3]]) out2 )");

    const f2a = ElementFraction{ .fromStart = 30, .element = .self };
    const gpa2a = GeneralPoint{ .fraction = f2a };
    const ap2a = AnchorPartial{ .point = gpa2a };
    const of2a = OneArgFunctionPartial{ .pin = ap2a };
    const c2a = Compose{ .ops = &[1]OneArgFunctionPartial{of2a} };
    const tp2a = OutputTransformationPair{
        .outputName = "out1",
        .operation = c2a,
    };

    const pt2b = inputs.Point{ .x = 1.0, .y = 2 };
    const gpa2b = GeneralPoint{ .point = pt2b };
    const ap2b = AnchorPartial{ .point = gpa2b };
    const of2b_first = OneArgFunctionPartial{ .pin = ap2b };
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
};

pub const OutputValidated = struct {
    transformationPairs: []const OutputTransformationPair,
};

// Validate 'Connection' to get 'OutputsValidated' if
// (a) outputName's in each transformationPairs of the connection is in 'outputs' (if not `OutputError.ArgumentInPairInvalid` triggered)
// (b) the number of outputs is the same as the one specified in numberOfOutputs arg (if not `OutputError.WrongNumberOfOutputs` triggered)
// Otherwise, one of the errors from OutputError is emitted
pub fn validateConnection(_: std.mem.Allocator, numberOfOutputs: u8, connection: Connection) !OutputValidated {
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

    return OutputValidated{
        .transformationPairs = connection.transformationPairs,
    };
}

test "connection validation" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const f1 = ElementFraction{ .fromStart = 0, .element = .self };
    const gpa1 = GeneralPoint{ .fraction = f1 };
    const ap1 = AnchorPartial{ .point = gpa1 };
    const of1 = OneArgFunctionPartial{ .pin = ap1 };
    const c1 = Compose{ .ops = &[1]OneArgFunctionPartial{of1} };

    const tp1 = OutputTransformationPair{
        .outputName = "out",
        .operation = c1,
    };
    const out1 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const connection1 = Connection{
        .outputs = &[1]Output{out1},
        .transformationPairs = &[1]OutputTransformationPair{tp1},
    };
    const connectionValidated1 = OutputValidated{
        .transformationPairs = &[1]OutputTransformationPair{tp1},
    };

    const validation1 = validateConnection(a, 1, connection1);
    try testing.expectEqualDeep(try validation1, connectionValidated1);

    const validation2 = validateConnection(a, 2, connection1);
    try testing.expectError(OutputError.WrongNumberOfOutputs, validation2);

    const f2 = ElementFraction{ .fromStart = 0, .element = .self };
    const gpa2 = GeneralPoint{ .fraction = f2 };
    const ap2 = AnchorPartial{ .point = gpa2 };
    const of2 = OneArgFunctionPartial{ .pin = ap2 };
    const c2 = Compose{ .ops = &[1]OneArgFunctionPartial{of2} };

    const tp2 = OutputTransformationPair{
        .outputName = "out1",
        .operation = c2,
    };
    const out2 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const connection2 = Connection{
        .outputs = &[1]Output{out2},
        .transformationPairs = &[1]OutputTransformationPair{tp2},
    };

    const validation3 = validateConnection(a, 1, connection2);
    try testing.expectError(OutputError.ArgumentInPairInvalid, validation3);

    const f3a = ElementFraction{ .fromStart = 30, .element = .self };
    const gpa3a = GeneralPoint{ .fraction = f3a };
    const ap3a = AnchorPartial{ .point = gpa3a };
    const of3a = OneArgFunctionPartial{ .pin = ap3a };
    const c3a = Compose{ .ops = &[1]OneArgFunctionPartial{of3a} };
    const tp3a = OutputTransformationPair{
        .outputName = "out1",
        .operation = c3a,
    };

    const pt3b = inputs.Point{ .x = 1.0, .y = 2 };
    const gpa3b = GeneralPoint{ .point = pt3b };
    const ap3b = AnchorPartial{ .point = gpa3b };
    const of3b_first = OneArgFunctionPartial{ .pin = ap3b };
    const v3b = inputs.Vector{ .x = 2.0, .y = 3.0 };
    const s3b = ScaleArg{ .translation = v3b };
    const alloc3b = try a.dupe(ScaleArg, &[1]ScaleArg{s3b});
    const of3b_second = OneArgFunctionPartial{ .scale = ScalePartial{ .elements = alloc3b } };
    const c3b = Compose{ .ops = &[2]OneArgFunctionPartial{ of3b_first, of3b_second } };
    const tp3b = OutputTransformationPair{
        .outputName = "out2",
        .operation = c3b,
    };

    const out3a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const out3b = Output{ .name = &[_]u8{ 'o', 'u', 't', '3' } };
    const connection3 = Connection{
        .outputs = &[2]Output{ out3a, out3b },
        .transformationPairs = &[2]OutputTransformationPair{ tp3a, tp3b },
    };

    const validation4 = validateConnection(a, 2, connection3);
    try testing.expectError(OutputError.ArgumentInPairInvalid, validation4);

    const validation5 = validateConnection(a, 3, connection3);
    try testing.expectError(OutputError.WrongNumberOfOutputs, validation5);
}
