const mecha = @import("mecha");
const std = @import("std");
const testing = std.testing;

////Types
pub const Vector = struct {
    x: f32,
    y: f32,
};

pub const skipOpenSquare =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('[').discard(), skipWhitespace });
pub const skipCloseSquare =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(']').discard(), skipWhitespace });
pub const skipComma =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(',').discard(), skipWhitespace });
pub const skipWhitespace =
    mecha.ascii.char(' ').many(.{ .collect = false }).discard();
const zeronine = mecha.utf8.range('0', '9');
const onenine = mecha.utf8.range('1', '9');
pub const digits = mecha.combine(.{
    zeronine.many(.{ .collect = false, .min = 1, .max = 8 }),
});
pub const integer = mecha.combine(.{
    mecha.oneOf(.{ onenine, zeronine }),
    zeronine.many(.{ .collect = false, .min = 1, .max = 8 }).opt(),
});
const integerWithSign = mecha.combine(.{ mecha.utf8.char('-').opt(), integer });
const floatWithDecimal = mecha.combine(.{
    integerWithSign,
    mecha.utf8.char('.').opt(),
    zeronine.many(.{ .collect = false, .min = 1 }).opt(),
});
const floatWithDecimalStr = floatWithDecimal.asStr();
pub const floatFromDecimal = floatWithDecimalStr.convert(mecha.toFloat(f32));
const sign = mecha.oneOf(.{
    mecha.utf8.char('+'),
    mecha.utf8.char('-'),
});

const exponent = mecha.combine(.{
    mecha.oneOf(.{ mecha.utf8.char('E'), mecha.utf8.char('e') }),
    sign,
    digits,
});

const scientific = mecha.combine(.{
    mecha.utf8.char('-').opt(),
    integer,
    mecha.combine(.{
        mecha.utf8.char('.'),
        digits,
    }).opt(),
    exponent,
});

const floatFromScientific = scientific.asStr().convert(mecha.toFloat(f32));

const floatParser = mecha.oneOf(.{
    floatFromScientific,
    floatFromDecimal,
});

const vectorParserRaw = mecha.combine(.{ skipOpenSquare, floatParser, skipComma, floatParser, skipCloseSquare });
const vectorParserRawP = @TypeOf(vectorParserRaw);
fn toVectorParser(_: std.mem.Allocator, res: vectorParserRawP.T) mecha.ConvertError!Vector {
    return Vector{ .x = res[0], .y = res[1] };
}
const vectorParser = vectorParserRaw.convert(toVectorParser);

test "vectorParser1" {
    const fa = testing.failing_allocator;

    const r1 = try vectorParser.parse(fa, "[2,1.1]");
    const p1 = Vector{ .x = 2.0, .y = 1.1 };
    try testing.expectEqual(p1, r1.value.ok);

    const r2 = try vectorParser.parse(fa, " [2,-1.1] ");
    const p2 = Vector{ .x = 2.0, .y = -1.1 };
    try testing.expectEqual(p2, r2.value.ok);

    const r3 = try vectorParser.parse(fa, " [2e+003 , -1.1] ");
    const p3 = Vector{ .x = 2000.0, .y = -1.1 };
    try testing.expectEqual(p3, r3.value.ok);
}

pub const vectorsParser = mecha.combine(.{
    skipOpenSquare,
    vectorParser.many(.{ .collect = true, .separator = skipComma }),
    skipCloseSquare,
});

test "vectorsParser1" {
    const a = testing.allocator;

    const r1 = try vectorsParser.parse(a, "[[2,1.1]]");
    const p1 = Vector{ .x = 2.0, .y = 1.1 };
    try testing.expectEqualDeep(&[1]Vector{p1}, r1.value.ok[0..1]);
    a.free(r1.value.ok);

    const r2 = try vectorsParser.parse(a, "[[2,1.1], [-2, -1.1]]");
    const p2a = Vector{ .x = 2.0, .y = 1.1 };
    const p2b = Vector{ .x = -2.0, .y = -1.1 };
    try testing.expectEqualDeep(&[2]Vector{ p2a, p2b }, r2.value.ok[0..2]);
    a.free(r2.value.ok);

    const r3 = try vectorsParser.parse(a, "[[0,1.0], [0,-1.0], [1.0, 0]]");
    const p3a = Vector{ .x = 0.0, .y = 1.0 };
    const p3b = Vector{ .x = 0.0, .y = -1.0 };
    const p3c = Vector{ .x = 1.0, .y = 0.0 };
    try testing.expectEqualDeep(&[3]Vector{ p3a, p3b, p3c }, r3.value.ok[0..3]);
    a.free(r3.value.ok);
}
