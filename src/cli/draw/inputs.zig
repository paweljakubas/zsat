const mecha = @import("mecha");
const common = @import("common.zig");
const std = @import("std");
const testing = std.testing;

////Types
pub const Point = struct {
    x: f32,
    y: f32,
};

//Parsers
const digits = mecha.combine(.{
    zeronine.many(.{ .collect = false, .min = 1, .max = 8 }),
});
const zeronine = mecha.utf8.range('0', '9');
const onenine = mecha.utf8.range('1', '9');

const integer = mecha.combine(.{
    onenine,
    zeronine.many(.{ .collect = false, .min = 1, .max = 8 }).opt(),
});
const integerWithSign = mecha.combine(.{ mecha.utf8.char('-').opt(), integer });
const floatFromInteger = integerWithSign.map(struct {
    fn toF32(a: anytype) !f32 {
        var buf: [16]u8 = undefined;
        var i: usize = 0;
        if (a[0]) |_| {
            buf[i] = '-';
            i += 1;
        }
        for (a[1]) |c| {
            buf[i] = @intCast(c);
            i += 1;
        }
        return try std.fmt.parseFloat(f32, buf[0..i]);
    }
}.toF32);

test "floatFromInteger" {
    const fa = testing.failing_allocator;

    const r1 = try floatFromInteger.parse(fa, "1");
    try testing.expectEqual(1.0, r1.value.ok);

    const r2 = try floatFromInteger.parse(fa, "-10");
    try testing.expectEqual(-10.0, r2.value.ok);
}

const fraction = mecha.combine(.{ integer, mecha.utf8.char('.'), digits });
const fractionWithSign = mecha.combine(.{ mecha.utf8.char('-').opt(), fraction });
const floatFromFraction = fractionWithSign.map(struct {
    fn toF32(a: anytype) !f32 {
        var buf: [32]u8 = undefined;
        var i: usize = 0;
        if (a[0]) |_| {
            buf[i] = '-';
            i += 1;
        }
        for (a[1][0]) |c| {
            buf[i] = @intCast(c);
            i += 1;
        }
        buf[i] = '.';
        i += 1;
        for (a[1][2]) |c| {
            buf[i] = @intCast(c);
            i += 1;
        }
        return try std.fmt.parseFloat(f32, buf[0..i]);
    }
}.toF32);

test "floatFromFraction" {
    const fa = testing.failing_allocator;

    const r1 = try floatFromFraction.parse(fa, "1.11");
    try testing.expectEqual(1.11, r1.value.ok);

    const r2 = try floatFromFraction.parse(fa, "-10.01");
    try testing.expectEqual(-10.01, r2.value.ok);
}

const exponent = mecha.combine(.{
    mecha.oneOf(.{ mecha.utf8.char('E'), mecha.utf8.char('e') }),
    sign,
    digits,
});
const sign = mecha.oneOf(.{
    mecha.utf8.char('+'),
    mecha.utf8.char('-'),
});
const scientific = mecha.combine(.{ integer, mecha.utf8.char('.'), digits, exponent });
const scientificWithSign = mecha.combine(.{ mecha.utf8.char('-').opt(), scientific });
const floatFromScientific = scientificWithSign.map(struct {
    fn toF32(a: anytype) !f32 {
        var buf: [32]u8 = undefined;
        var i: usize = 0;
        if (a[0]) |_| {
            buf[i] = '-';
            i += 1;
        }
        for (a[1][0]) |c| {
            buf[i] = @intCast(c);
            i += 1;
        }
        buf[i] = '.';
        i += 1;
        for (a[1][2]) |c| {
            buf[i] = @intCast(c);
            i += 1;
        }
        buf[i] = @intCast(a[1][3][0]);
        i += 1;
        buf[i] = @intCast(a[1][3][1]);
        i += 1;
        for (a[1][3][2]) |c| {
            buf[i] = @intCast(c);
            i += 1;
        }
        return try std.fmt.parseFloat(f32, buf[0..i]);
    }
}.toF32);

test "floatFromScientific" {
    const fa = testing.failing_allocator;

    const r1 = try floatFromScientific.parse(fa, "2e+1");
    try testing.expectEqual(20.0, r1.value.ok);

    const r2 = try floatFromScientific.parse(fa, "9.87E+02");
    try testing.expectEqual(987, r2.value.ok);

    const r3 = try floatFromScientific.parse(fa, "4.321768e+003");
    try testing.expectEqual(4321.768, r3.value.ok);

    const r4 = try floatFromScientific.parse(fa, "-5.3e+004");
    try testing.expectEqual(-53000, r4.value.ok);

    const r5 = try floatFromScientific.parse(fa, "2e-1");
    try testing.expectEqual(0.2, r5.value.ok);

    const r6 = try floatFromScientific.parse(fa, "7.51E-09");
    try testing.expectEqual(0.00000000751, r6.value.ok);
}

const floatParser = mecha.oneOf(.{
    floatFromInteger,
    floatFromFraction,
    floatFromScientific,
});

test "floatParser" {
    const fa = testing.failing_allocator;

    const r1 = try floatParser.parse(fa, "2e+1");
    try testing.expectEqual(20.0, r1.value.ok);

    const r2 = try floatParser.parse(fa, "9.87E+02");
    try testing.expectEqual(987, r2.value.ok);

    const r3 = try floatParser.parse(fa, "4.321768e+003");
    try testing.expectEqual(4321.768, r3.value.ok);

    const r4 = try floatParser.parse(fa, "-5.3e+004");
    try testing.expectEqual(-53000, r4.value.ok);

    const r5 = try floatParser.parse(fa, "2e-1");
    try testing.expectEqual(0.2, r5.value.ok);

    const r6 = try floatParser.parse(fa, "7.51E-09");
    try testing.expectEqual(0.00000000751, r6.value.ok);

    const r7 = try floatParser.parse(fa, "1.11");
    try testing.expectEqual(1.11, r7.value.ok);

    const r8 = try floatParser.parse(fa, "-10.01");
    try testing.expectEqual(-10.01, r8.value.ok);

    const r9 = try floatParser.parse(fa, "1");
    try testing.expectEqual(1.0, r9.value.ok);

    const r10 = try floatParser.parse(fa, "-10");
    try testing.expectEqual(-10.00, r10.value.ok);
}

const pointParserRaw = mecha.combine(.{ common.skipOpenBrace, common.skipOpenBracket, floatParser, common.skipComma, floatParser, common.skipCloseBracket, common.skipCloseBrace });
const pointParserRawP = @TypeOf(pointParserRaw);
fn toPointParser(_: std.mem.Allocator, res: pointParserRawP.T) mecha.ConvertError!Point {
    return Point{ .x = res[0], .y = res[1] };
}
const pointParser = pointParserRaw.convert(toPointParser);

test "pointParser" {
    const fa = testing.failing_allocator;

    const r1 = try pointParser.parse(fa, "{(2,1.1)}");
    const p1 = Point{ .x = 2.0, .y = 1.1 };
    try testing.expectEqual(p1, r1.value.ok);

    const r2 = try pointParser.parse(fa, "{ (2,-1.1) }");
    const p2 = Point{ .x = 2.0, .y = -1.1 };
    try testing.expectEqual(p2, r2.value.ok);

    const r3 = try pointParser.parse(fa, "{ (2e+003 , -1.1) }");
    const p3 = Point{ .x = 2000.0, .y = -1.1 };
    try testing.expectEqual(p3, r3.value.ok);
}

const pointsParserRaw = mecha.combine(.{
    common.skipOpenBrace,
    pointParser.many(.{ .collect = true, .separator = common.skipComma }),
    common.skipCloseBrace,
});
const pointsParserRawP = @TypeOf(pointsParserRaw);
fn toPointsParser(_: std.mem.Allocator, res: pointsParserRawP.T) mecha.ConvertError![]Point {
    return res[1];
}
const pointsParser = pointsParserRaw.convert(toPointsParser);

test "pointsParser" {
    const a = testing.allocator;

    const r1 = try pointsParser.parse(a, "{(2,1.1)}");
    const p1 = Point{ .x = 2.0, .y = 1.1 };
    try testing.expectEqual([1]Point{p1}, r1.value.ok[0..1]);

    const r2 = try pointsParser.parse(a, "{(2,1.1), (-2, -1.1)}");
    const p2a = Point{ .x = 2.0, .y = 1.1 };
    const p2b = Point{ .x = -2.0, .y = -1.1 };
    try testing.expectEqual([2]Point{ p2a, p2b }, r2.value.ok[0..2]);

    const r3 = try pointsParser.parse(a, "{(0,1.0), (0,-1.0), (1.0, 0),}");
    const p3a = Point{ .x = 0.0, .y = 1.0 };
    const p3b = Point{ .x = 0.0, .y = -1.0 };
    const p3c = Point{ .x = 1.0, .y = 0.0 };
    try testing.expectEqual([3]Point{ p3a, p3b, p3c }, r3.value.ok[0..3]);
}
