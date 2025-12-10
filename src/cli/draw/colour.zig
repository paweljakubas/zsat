const mecha = @import("mecha");
const std = @import("std");
const testing = std.testing;

//colour names
pub const ColourName = enum {
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

const lineColorNameParserRaw =
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

fn toLColorNameType(_: std.mem.Allocator, res: lineWidthTypeParserRawP.T) mecha.ConvertError!ColorName {
    const to = struct {
        fn to(str: []const u8) ?ColorName {
            return std.meta.stringToEnum(ColorName, str);
        }
    }.to;
    if (to(res[0])) |validColor| {
        return validColor;
    } else {
        return error.ConversionFailed;
    }
}

const lineColorNameParserTyped = lineColorNameParserRaw.convert(toColorNameType);
