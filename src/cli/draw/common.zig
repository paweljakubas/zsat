const mecha = @import("mecha");
const std = @import("std");

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
pub const skipArrow =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('-').discard(), mecha.ascii.char('>').discard(), skipWhitespace });
pub const skipComma =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(',').discard(), skipWhitespace });
