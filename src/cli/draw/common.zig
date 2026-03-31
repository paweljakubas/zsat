const mecha = @import("mecha");
const std = @import("std");
const testing = std.testing;

//colour names
pub const ColorName = enum {
    aqua,
    azure,
    black,
    blue,
    brown,
    gold,
    grey,
    green,
    olive,
    orange,
    pink,
    red,
    silver,
    snow,
    violet,
    white,
    yellow,
};

const colorNameParserRaw =
    mecha.oneOf(.{
        mecha.string("aqua"),
        mecha.string("azure"),
        mecha.string("black"),
        mecha.string("blue"),
        mecha.string("brown"),
        mecha.string("gold"),
        mecha.string("grey"),
        mecha.string("green"),
        mecha.string("olive"),
        mecha.string("orange"),
        mecha.string("pink"),
        mecha.string("red"),
        mecha.string("silver"),
        mecha.string("snow"),
        mecha.string("violet"),
        mecha.string("white"),
        mecha.string("yellow"),
    });

const lineColorNameParserRawP = @TypeOf(colorNameParserRaw);

fn toColorNameType(_: std.mem.Allocator, res: lineColorNameParserRawP.T) mecha.ConvertError!ColorName {
    if (std.meta.stringToEnum(ColorName, res)) |validColor| {
        return validColor;
    } else {
        return error.ConversionFailed;
    }
}

pub const colorNameParserTyped = colorNameParserRaw.convert(toColorNameType);

//Parsers
pub const skipWhitespace =
    mecha.ascii.char(' ').many(.{ .collect = false }).discard();
pub const skipOpenBracket =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('(').discard(), skipWhitespace });
pub const skipCloseBracket =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(')').discard(), skipWhitespace });
pub const skipOpenBrace =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('{').discard(), skipWhitespace });
pub const skipCloseBrace =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('}').discard(), skipWhitespace });
pub const skipOpenBraceColon =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(':').discard(), skipWhitespace, mecha.ascii.char('{').discard() });
pub const skipOpenSquare =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('[').discard(), skipWhitespace });
pub const skipCloseSquare =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(']').discard(), skipWhitespace });
pub const skipArrow =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('-').discard(), mecha.ascii.char('>').discard(), skipWhitespace });
pub const skipComma =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(',').discard(), skipWhitespace });
pub const characterInNameParser =
    mecha.oneOf(.{ mecha.ascii.range('a', 'z'), mecha.ascii.range('A', 'Z'), mecha.ascii.range('0', '9') });
pub const nameParser = mecha.many(characterInNameParser, .{ .collect = false });

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

test "floatFromDecimal" {
    const fa = testing.failing_allocator;

    const r1 = try floatFromDecimal.parse(fa, "1");
    try testing.expectEqual(1.0, r1.value.ok);

    const r2 = try floatFromDecimal.parse(fa, "-10");
    try testing.expectEqual(-10.0, r2.value.ok);

    const r3 = try floatFromDecimal.parse(fa, "-10.1");
    try testing.expectEqual(-10.1, r3.value.ok);
}
