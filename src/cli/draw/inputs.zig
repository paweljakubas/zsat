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

const digits = mecha.combine(.{
    zeronine.many(.{ .collect = false, .min = 1, .max = 8 }),
});

const zeronine = mecha.utf8.range('0', '9');
const onenine = mecha.utf8.range('1', '9');

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

const floatParser = mecha.oneOf(.{
    floatFromInteger,
    floatFromFraction,
    floatFromScientific,
});

//const inputSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });

test "floatFromInteger" {
    const fa = testing.failing_allocator;

    const r1 = try floatFromInteger.parse(fa, "1");
    try testing.expectEqual(1.0, r1.value.ok);

    const r2 = try floatFromInteger.parse(fa, "-10");
    try testing.expectEqual(-10.0, r2.value.ok);
}

test "floatFromFraction" {
    const fa = testing.failing_allocator;

    const r1 = try floatFromFraction.parse(fa, "1.11");
    try testing.expectEqual(1.11, r1.value.ok);

    const r2 = try floatFromFraction.parse(fa, "-10.01");
    try testing.expectEqual(-10.01, r2.value.ok);
}

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

    const r7 = try floatFromFraction.parse(fa, "1.11");
    try testing.expectEqual(1.11, r7.value.ok);

    const r8 = try floatFromFraction.parse(fa, "-10.01");
    try testing.expectEqual(-10.01, r8.value.ok);

    const r9 = try floatFromFraction.parse(fa, "1");
    try testing.expectEqual(1.0, r9.value.ok);

    const r10 = try floatFromFraction.parse(fa, "-10");
    try testing.expectEqual(-10.00, r10.value.ok);
}
