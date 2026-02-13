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
//const float = mecha.oneOf(.{
//  mecha.combine(.{ mecha.utf8.char('-').opt(), scientific }),
//});

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

//const scientific = mecha.combine(.{ integer, mecha.utf8.char('.'), digits, exponent });
//const exponent = mecha.combine(.{
//    mecha.oneOf(.{ mecha.utf8.char('E'), mecha.utf8.char('e') }),
//    sign,
//    digits,
//});
//const sign = mecha.oneOf(.{
//    mecha.utf8.char('+'),
//    mecha.utf8.char('-'),
//});

//const inputSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });

test "floatFromInteger" {
    var buf: [4096]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const allocator = fba.allocator();

    const r1 = try floatFromInteger.parse(allocator, "1");
    try testing.expectEqual(1.0, r1.value.ok);

    const r2 = try floatFromInteger.parse(allocator, "-10");
    try testing.expectEqual(-10.0, r2.value.ok);
}
