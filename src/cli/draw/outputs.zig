const mecha = @import("mecha");
const common = @import("common.zig");
const std = @import("std");
const testing = std.testing;

////Types

//Handling the name of output
pub const Output = struct {
    name: []const u8,
};

//Rotate by phi
//By default counter-clock wise, vector is
pub const RotateBy = struct {
    phi: i16,
};

pub const ElementReference = union(enum) {
    self,
    other: []const u8,
};

pub const ElementFraction = struct {
    fromStart: i16, //in % from the start of the reference element
    element: ElementReference,
};

pub const Point = struct {
    x: f32,
    y: f32,
};

const GeneralPoint = union(enum) {
    point: [1]Point,
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
    common.floatFromInteger,
    common.skipComma,
    common.floatFromInteger,
    common.skipCloseBracket,
}).convert(struct {
    fn toPoint(_: std.mem.Allocator, a: anytype) mecha.ConvertError!Point {
        return Point{ .x = a[0], .y = a[1] };
    }
}.toPoint);

const pointGPParser = mecha.combine(.{
    common.skipOpenBrace,
    pointParserLocal,
    common.skipCloseBrace,
}).convert(struct {
    fn toPoint(_: std.mem.Allocator, a: anytype) mecha.ConvertError!GeneralPoint {
        return GeneralPoint{ .point = [1]Point{a} };
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

    const r11 = try generalPointParser.parse(fa, "{-12,2.1)} ");
    const p11 = Point{ .x = -12.0, .y = 2.1 };
    const o11 = GeneralPoint{ .point = [1]Point{p11} };
    try testing.expectEqualDeep(o11, r11.value.ok);
}
