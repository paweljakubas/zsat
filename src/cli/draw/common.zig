const mecha = @import("mecha");
const std = @import("std");
const testing = std.testing;

//colour names
pub const ColorName = enum {
    aliceblue,
    antiquewhite,
    aqua,
    aquamarine,
    azure,
    beige,
    bisque,
    black,
    blanchedalmond,
    blue,
    blueviolet,
    brown,
    burlywood,
    cadetblue,
    chartreuse,
    chocolate,
    coral,
    cornflowerblue,
    cornsilk,
    crimson,
    cyan,
    darkblue,
    darkcyan,
    darkgoldenrod,
    darkgray,
    darkgreen,
    darkgrey,
    darkkhaki,
    darkmagenta,
    darkolivegreen,
    darkorange,
    darkorchid,
    darkred,
    darksalmon,
    darkseagreen,
    darkslateblue,
    darkslategray,
    darkslategrey,
    darkturquoise,
    darkviolet,
    deeppink,
    deepskyblue,
    dimgray,
    dimgrey,
    dodgerblue,
    firebrick,
    floralwhite,
    forestgreen,
    fuchsia,
    gainsboro,
    ghostwhite,
    gold,
    goldenrod,
    gray,
    green,
    greenyellow,
    grey,
    honeydew,
    hotpink,
    indianred,
    indigo,
    ivory,
    khaki,
    lavender,
    lavenderblush,
    lawngreen,
    lemonchiffon,
    lightblue,
    lightcoral,
    lightcyan,
    lightgoldenrodyellow,
    lightgray,
    lightgreen,
    lightgrey,
    lightpink,
    lightsalmon,
    lightseagreen,
    lightskyblue,
    lightslategray,
    lightslategrey,
    lightsteelblue,
    lightyellow,
    lime,
    limegreen,
    linen,
    magenta,
    maroon,
    mediumaquamarine,
    mediumblue,
    mediumorchid,
    mediumpurple,
    mediumseagreen,
    mediumslateblue,
    mediumspringgreen,
    mediumturquoise,
    mediumvioletred,
    midnightblue,
    mintcream,
    mistyrose,
    moccasin,
    navajowhite,
    navy,
    oldlace,
    olive,
    olivedrab,
    orange,
    orangered,
    orchid,
    palegoldenrod,
    palegreen,
    paleturquoise,
    palevioletred,
    papayawhip,
    peachpuff,
    peru,
    pink,
    plum,
    powderblue,
    purple,
    rebeccapurple,
    red,
    rosybrown,
    royalblue,
    saddlebrown,
    salmon,
    sandybrown,
    seagreen,
    seashell,
    sienna,
    silver,
    skyblue,
    slateblue,
    slategray,
    slategrey,
    snow,
    springgreen,
    steelblue,
    tan,
    teal,
    thistle,
    tomato,
    turquoise,
    violet,
    wheat,
    white,
    whitesmoke,
    yellow,
    yellowgreen,
};

pub fn colorNameToRGB(c: ColorName) struct { r: u8, g: u8, b: u8 } {
    return switch (c) {
        .aliceblue => .{ .r = 240, .g = 248, .b = 255 },
        .antiquewhite => .{ .r = 250, .g = 235, .b = 215 },
        .aqua => .{ .r = 0, .g = 255, .b = 255 },
        .aquamarine => .{ .r = 127, .g = 255, .b = 212 },
        .azure => .{ .r = 240, .g = 255, .b = 255 },
        .beige => .{ .r = 245, .g = 245, .b = 220 },
        .bisque => .{ .r = 255, .g = 228, .b = 196 },
        .black => .{ .r = 0, .g = 0, .b = 0 },
        .blanchedalmond => .{ .r = 255, .g = 235, .b = 205 },
        .blue => .{ .r = 0, .g = 0, .b = 255 },
        .blueviolet => .{ .r = 138, .g = 43, .b = 226 },
        .brown => .{ .r = 165, .g = 42, .b = 42 },
        .burlywood => .{ .r = 222, .g = 184, .b = 135 },
        .cadetblue => .{ .r = 95, .g = 158, .b = 160 },
        .chartreuse => .{ .r = 127, .g = 255, .b = 0 },
        .chocolate => .{ .r = 210, .g = 105, .b = 30 },
        .coral => .{ .r = 255, .g = 127, .b = 80 },
        .cornflowerblue => .{ .r = 100, .g = 149, .b = 237 },
        .cornsilk => .{ .r = 255, .g = 248, .b = 220 },
        .crimson => .{ .r = 220, .g = 20, .b = 60 },
        .cyan => .{ .r = 0, .g = 255, .b = 255 },
        .darkblue => .{ .r = 0, .g = 0, .b = 139 },
        .darkcyan => .{ .r = 0, .g = 139, .b = 139 },
        .darkgoldenrod => .{ .r = 184, .g = 134, .b = 11 },
        .darkgray => .{ .r = 169, .g = 169, .b = 169 },
        .darkgreen => .{ .r = 0, .g = 100, .b = 0 },
        .darkgrey => .{ .r = 169, .g = 169, .b = 169 },
        .darkkhaki => .{ .r = 189, .g = 183, .b = 107 },
        .darkmagenta => .{ .r = 139, .g = 0, .b = 139 },
        .darkolivegreen => .{ .r = 85, .g = 107, .b = 47 },
        .darkorange => .{ .r = 255, .g = 140, .b = 0 },
        .darkorchid => .{ .r = 153, .g = 50, .b = 204 },
        .darkred => .{ .r = 139, .g = 0, .b = 0 },
        .darksalmon => .{ .r = 233, .g = 150, .b = 122 },
        .darkseagreen => .{ .r = 143, .g = 188, .b = 143 },
        .darkslateblue => .{ .r = 72, .g = 61, .b = 139 },
        .darkslategray => .{ .r = 47, .g = 79, .b = 79 },
        .darkslategrey => .{ .r = 47, .g = 79, .b = 79 },
        .darkturquoise => .{ .r = 0, .g = 206, .b = 209 },
        .darkviolet => .{ .r = 148, .g = 0, .b = 211 },
        .deeppink => .{ .r = 255, .g = 20, .b = 147 },
        .deepskyblue => .{ .r = 0, .g = 191, .b = 255 },
        .dimgray => .{ .r = 105, .g = 105, .b = 105 },
        .dimgrey => .{ .r = 105, .g = 105, .b = 105 },
        .dodgerblue => .{ .r = 30, .g = 144, .b = 255 },
        .firebrick => .{ .r = 178, .g = 34, .b = 34 },
        .floralwhite => .{ .r = 255, .g = 250, .b = 240 },
        .forestgreen => .{ .r = 34, .g = 139, .b = 34 },
        .fuchsia => .{ .r = 255, .g = 0, .b = 255 },
        .gainsboro => .{ .r = 220, .g = 220, .b = 220 },
        .ghostwhite => .{ .r = 248, .g = 248, .b = 255 },
        .gold => .{ .r = 255, .g = 215, .b = 0 },
        .goldenrod => .{ .r = 218, .g = 165, .b = 32 },
        .gray => .{ .r = 128, .g = 128, .b = 128 },
        .green => .{ .r = 0, .g = 128, .b = 0 },
        .greenyellow => .{ .r = 173, .g = 255, .b = 47 },
        .grey => .{ .r = 128, .g = 128, .b = 128 },
        .honeydew => .{ .r = 240, .g = 255, .b = 240 },
        .hotpink => .{ .r = 255, .g = 105, .b = 180 },
        .indianred => .{ .r = 205, .g = 92, .b = 92 },
        .indigo => .{ .r = 75, .g = 0, .b = 130 },
        .ivory => .{ .r = 255, .g = 255, .b = 240 },
        .khaki => .{ .r = 240, .g = 230, .b = 140 },
        .lavender => .{ .r = 230, .g = 230, .b = 250 },
        .lavenderblush => .{ .r = 255, .g = 240, .b = 245 },
        .lawngreen => .{ .r = 124, .g = 252, .b = 0 },
        .lemonchiffon => .{ .r = 255, .g = 250, .b = 205 },
        .lightblue => .{ .r = 173, .g = 216, .b = 230 },
        .lightcoral => .{ .r = 240, .g = 128, .b = 128 },
        .lightcyan => .{ .r = 224, .g = 255, .b = 255 },
        .lightgoldenrodyellow => .{ .r = 250, .g = 250, .b = 210 },
        .lightgray => .{ .r = 211, .g = 211, .b = 211 },
        .lightgreen => .{ .r = 144, .g = 238, .b = 144 },
        .lightgrey => .{ .r = 211, .g = 211, .b = 211 },
        .lightpink => .{ .r = 255, .g = 182, .b = 193 },
        .lightsalmon => .{ .r = 255, .g = 160, .b = 122 },
        .lightseagreen => .{ .r = 32, .g = 178, .b = 170 },
        .lightskyblue => .{ .r = 135, .g = 206, .b = 250 },
        .lightslategray => .{ .r = 119, .g = 136, .b = 153 },
        .lightslategrey => .{ .r = 119, .g = 136, .b = 153 },
        .lightsteelblue => .{ .r = 176, .g = 196, .b = 222 },
        .lightyellow => .{ .r = 255, .g = 255, .b = 224 },
        .lime => .{ .r = 0, .g = 255, .b = 0 },
        .limegreen => .{ .r = 50, .g = 205, .b = 50 },
        .linen => .{ .r = 250, .g = 240, .b = 230 },
        .magenta => .{ .r = 255, .g = 0, .b = 255 },
        .maroon => .{ .r = 128, .g = 0, .b = 0 },
        .mediumaquamarine => .{ .r = 102, .g = 205, .b = 170 },
        .mediumblue => .{ .r = 0, .g = 0, .b = 205 },
        .mediumorchid => .{ .r = 186, .g = 85, .b = 211 },
        .mediumpurple => .{ .r = 147, .g = 112, .b = 219 },
        .mediumseagreen => .{ .r = 60, .g = 179, .b = 113 },
        .mediumslateblue => .{ .r = 123, .g = 104, .b = 238 },
        .mediumspringgreen => .{ .r = 0, .g = 250, .b = 154 },
        .mediumturquoise => .{ .r = 72, .g = 209, .b = 204 },
        .mediumvioletred => .{ .r = 199, .g = 21, .b = 133 },
        .midnightblue => .{ .r = 25, .g = 25, .b = 112 },
        .mintcream => .{ .r = 245, .g = 255, .b = 250 },
        .mistyrose => .{ .r = 255, .g = 228, .b = 225 },
        .moccasin => .{ .r = 255, .g = 228, .b = 181 },
        .navajowhite => .{ .r = 255, .g = 222, .b = 173 },
        .navy => .{ .r = 0, .g = 0, .b = 128 },
        .oldlace => .{ .r = 253, .g = 245, .b = 230 },
        .olive => .{ .r = 128, .g = 128, .b = 0 },
        .olivedrab => .{ .r = 107, .g = 142, .b = 35 },
        .orange => .{ .r = 255, .g = 165, .b = 0 },
        .orangered => .{ .r = 255, .g = 69, .b = 0 },
        .orchid => .{ .r = 218, .g = 112, .b = 214 },
        .palegoldenrod => .{ .r = 238, .g = 232, .b = 170 },
        .palegreen => .{ .r = 152, .g = 251, .b = 152 },
        .paleturquoise => .{ .r = 175, .g = 238, .b = 238 },
        .palevioletred => .{ .r = 219, .g = 112, .b = 147 },
        .papayawhip => .{ .r = 255, .g = 239, .b = 213 },
        .peachpuff => .{ .r = 255, .g = 218, .b = 185 },
        .peru => .{ .r = 205, .g = 133, .b = 63 },
        .pink => .{ .r = 255, .g = 192, .b = 203 },
        .plum => .{ .r = 221, .g = 160, .b = 221 },
        .powderblue => .{ .r = 176, .g = 224, .b = 230 },
        .purple => .{ .r = 128, .g = 0, .b = 128 },
        .rebeccapurple => .{ .r = 102, .g = 51, .b = 153 },
        .red => .{ .r = 255, .g = 0, .b = 0 },
        .rosybrown => .{ .r = 188, .g = 143, .b = 143 },
        .royalblue => .{ .r = 65, .g = 105, .b = 225 },
        .saddlebrown => .{ .r = 139, .g = 69, .b = 19 },
        .salmon => .{ .r = 250, .g = 128, .b = 114 },
        .sandybrown => .{ .r = 244, .g = 164, .b = 96 },
        .seagreen => .{ .r = 46, .g = 139, .b = 87 },
        .seashell => .{ .r = 255, .g = 245, .b = 238 },
        .sienna => .{ .r = 160, .g = 82, .b = 45 },
        .silver => .{ .r = 192, .g = 192, .b = 192 },
        .skyblue => .{ .r = 135, .g = 206, .b = 235 },
        .slateblue => .{ .r = 106, .g = 90, .b = 205 },
        .slategray => .{ .r = 112, .g = 128, .b = 144 },
        .slategrey => .{ .r = 112, .g = 128, .b = 144 },
        .snow => .{ .r = 255, .g = 250, .b = 250 },
        .springgreen => .{ .r = 0, .g = 255, .b = 127 },
        .steelblue => .{ .r = 70, .g = 130, .b = 180 },
        .tan => .{ .r = 210, .g = 180, .b = 140 },
        .teal => .{ .r = 0, .g = 128, .b = 128 },
        .thistle => .{ .r = 216, .g = 191, .b = 216 },
        .tomato => .{ .r = 255, .g = 99, .b = 71 },
        .turquoise => .{ .r = 64, .g = 224, .b = 208 },
        .violet => .{ .r = 238, .g = 130, .b = 238 },
        .wheat => .{ .r = 245, .g = 222, .b = 179 },
        .white => .{ .r = 255, .g = 255, .b = 255 },
        .whitesmoke => .{ .r = 245, .g = 245, .b = 245 },
        .yellow => .{ .r = 255, .g = 255, .b = 0 },
        .yellowgreen => .{ .r = 154, .g = 205, .b = 50 },
    };
}

const colorNameParserRaw =
    mecha.oneOf(.{
        mecha.string("aliceblue"),
        mecha.string("antiquewhite"),
        mecha.string("aqua"),
        mecha.string("aquamarine"),
        mecha.string("azure"),
        mecha.string("beige"),
        mecha.string("bisque"),
        mecha.string("black"),
        mecha.string("blanchedalmond"),
        mecha.string("blue"),
        mecha.string("blueviolet"),
        mecha.string("brown"),
        mecha.string("burlywood"),
        mecha.string("cadetblue"),
        mecha.string("chartreuse"),
        mecha.string("chocolate"),
        mecha.string("coral"),
        mecha.string("cornflowerblue"),
        mecha.string("cornsilk"),
        mecha.string("crimson"),
        mecha.string("cyan"),
        mecha.string("darkblue"),
        mecha.string("darkcyan"),
        mecha.string("darkgoldenrod"),
        mecha.string("darkgray"),
        mecha.string("darkgreen"),
        mecha.string("darkgrey"),
        mecha.string("darkkhaki"),
        mecha.string("darkmagenta"),
        mecha.string("darkolivegreen"),
        mecha.string("darkorange"),
        mecha.string("darkorchid"),
        mecha.string("darkred"),
        mecha.string("darksalmon"),
        mecha.string("darkseagreen"),
        mecha.string("darkslateblue"),
        mecha.string("darkslategray"),
        mecha.string("darkslategrey"),
        mecha.string("darkturquoise"),
        mecha.string("darkviolet"),
        mecha.string("deeppink"),
        mecha.string("deepskyblue"),
        mecha.string("dimgray"),
        mecha.string("dimgrey"),
        mecha.string("dodgerblue"),
        mecha.string("firebrick"),
        mecha.string("floralwhite"),
        mecha.string("forestgreen"),
        mecha.string("fuchsia"),
        mecha.string("gainsboro"),
        mecha.string("ghostwhite"),
        mecha.string("gold"),
        mecha.string("goldenrod"),
        mecha.string("gray"),
        mecha.string("green"),
        mecha.string("greenyellow"),
        mecha.string("grey"),
        mecha.string("honeydew"),
        mecha.string("hotpink"),
        mecha.string("indianred"),
        mecha.string("indigo"),
        mecha.string("ivory"),
        mecha.string("khaki"),
        mecha.string("lavender"),
        mecha.string("lavenderblush"),
        mecha.string("lawngreen"),
        mecha.string("lemonchiffon"),
        mecha.string("lightblue"),
        mecha.string("lightcoral"),
        mecha.string("lightcyan"),
        mecha.string("lightgoldenrodyellow"),
        mecha.string("lightgray"),
        mecha.string("lightgreen"),
        mecha.string("lightgrey"),
        mecha.string("lightpink"),
        mecha.string("lightsalmon"),
        mecha.string("lightseagreen"),
        mecha.string("lightskyblue"),
        mecha.string("lightslategray"),
        mecha.string("lightslategrey"),
        mecha.string("lightsteelblue"),
        mecha.string("lightyellow"),
        mecha.string("lime"),
        mecha.string("limegreen"),
        mecha.string("linen"),
        mecha.string("magenta"),
        mecha.string("maroon"),
        mecha.string("mediumaquamarine"),
        mecha.string("mediumblue"),
        mecha.string("mediumorchid"),
        mecha.string("mediumpurple"),
        mecha.string("mediumseagreen"),
        mecha.string("mediumslateblue"),
        mecha.string("mediumspringgreen"),
        mecha.string("mediumturquoise"),
        mecha.string("mediumvioletred"),
        mecha.string("midnightblue"),
        mecha.string("mintcream"),
        mecha.string("mistyrose"),
        mecha.string("moccasin"),
        mecha.string("navajowhite"),
        mecha.string("navy"),
        mecha.string("oldlace"),
        mecha.string("olive"),
        mecha.string("olivedrab"),
        mecha.string("orange"),
        mecha.string("orangered"),
        mecha.string("orchid"),
        mecha.string("palegoldenrod"),
        mecha.string("palegreen"),
        mecha.string("paleturquoise"),
        mecha.string("palevioletred"),
        mecha.string("papayawhip"),
        mecha.string("peachpuff"),
        mecha.string("peru"),
        mecha.string("pink"),
        mecha.string("plum"),
        mecha.string("powderblue"),
        mecha.string("purple"),
        mecha.string("rebeccapurple"),
        mecha.string("red"),
        mecha.string("rosybrown"),
        mecha.string("royalblue"),
        mecha.string("saddlebrown"),
        mecha.string("salmon"),
        mecha.string("sandybrown"),
        mecha.string("seagreen"),
        mecha.string("seashell"),
        mecha.string("sienna"),
        mecha.string("silver"),
        mecha.string("skyblue"),
        mecha.string("slateblue"),
        mecha.string("slategray"),
        mecha.string("slategrey"),
        mecha.string("snow"),
        mecha.string("springgreen"),
        mecha.string("steelblue"),
        mecha.string("tan"),
        mecha.string("teal"),
        mecha.string("thistle"),
        mecha.string("tomato"),
        mecha.string("turquoise"),
        mecha.string("violet"),
        mecha.string("wheat"),
        mecha.string("white"),
        mecha.string("whitesmoke"),
        mecha.string("yellow"),
        mecha.string("yellowgreen"),
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
pub const skipAnyWhitespace =
    mecha.oneOf(.{ mecha.ascii.char(' '), mecha.ascii.char('\t'), mecha.ascii.char('\n'), mecha.ascii.char('\r') }).many(.{ .collect = false }).discard();
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
pub const skipOpenBraceColonOrJustBrace = mecha.oneOf(.{
    skipOpenBraceColon,
    skipOpenBrace,
});
pub const skipOpenSquare =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('[').discard(), skipWhitespace });
pub const skipCloseSquare =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(']').discard(), skipWhitespace });
pub const skipArrow =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('-').discard(), mecha.ascii.char('>').discard(), skipWhitespace });
pub const skipComma =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(',').discard(), skipWhitespace });
pub const skipCaretColon =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('^').discard(), mecha.ascii.char(':').discard(), skipWhitespace });
pub const characterInNameParser =
    mecha.oneOf(.{ mecha.ascii.range('a', 'z'), mecha.ascii.range('A', 'Z'), mecha.ascii.range('0', '9'), mecha.ascii.char(':') });
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
pub const integerWithSign = mecha.combine(.{ mecha.utf8.char('-').opt(), integer });
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

/// The `ns::` in front of a definition reference: the namespace the definition
/// was collected from. The identifier stops at the first `:` so that the `::`
/// can be required rather than assumed.
const qualifierIdentParser = mecha.many(mecha.oneOf(.{
    mecha.ascii.range('a', 'z'),
    mecha.ascii.range('A', 'Z'),
    mecha.ascii.range('0', '9'),
    mecha.ascii.char('_'),
    mecha.ascii.char('-'),
}), .{ .collect = false, .min = 1 });

const qualifierParser = mecha.combine(.{
    qualifierIdentParser,
    mecha.ascii.char(':').discard(),
    mecha.ascii.char(':').discard(),
});

const refDigitsParser = mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 });

// A reference to a definition, spelled the way references are written: bare
// `a0`, or qualified `ns::a0` once the definition came in through `use ns`, or
// `p::a0` when it came through `use ns as p`. The whole spelling comes back out,
// because that is exactly the name the definition was collected under, which
// makes resolving a reference a plain comparison and lets an alias shadow the
// bare name it renamed. No leading whitespace is consumed, matching how the
// plain number parsers are used.
//
// One parser per kind rather than a function taking the letter: a mecha parser
// built inside a function sends this compiler into a stack overflow, so the
// letter is spelled out instead.
pub const lineStyleRefParser = mecha.combine(.{
    mecha.opt(qualifierParser),
    mecha.ascii.char('e').discard(),
    refDigitsParser,
}).asStr();
pub const pointStyleRefParser = mecha.combine(.{
    mecha.opt(qualifierParser),
    mecha.ascii.char('p').discard(),
    refDigitsParser,
}).asStr();
pub const textRefParser = mecha.combine(.{
    mecha.opt(qualifierParser),
    mecha.ascii.char('t').discard(),
    refDigitsParser,
}).asStr();
pub const borderRefParser = mecha.combine(.{
    mecha.opt(qualifierParser),
    mecha.ascii.char('b').discard(),
    refDigitsParser,
}).asStr();
pub const axisRefParser = mecha.combine(.{
    mecha.opt(qualifierParser),
    mecha.ascii.char('a').discard(),
    refDigitsParser,
}).asStr();

test "definition refs" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const bare = try axisRefParser.parse(a, "a0");
    try testing.expectEqualStrings("a0", bare.value.ok);

    const qualified = try axisRefParser.parse(a, "sleek::a12");
    try testing.expectEqualStrings("sleek::a12", qualified.value.ok);

    const aliased = try textRefParser.parse(a, "p::t0");
    try testing.expectEqualStrings("p::t0", aliased.value.ok);

    // The identifier only counts as a qualifier when a `::` follows it, so a
    // bare name is not read as a qualifier that then fails to complete.
    const trailing = try axisRefParser.parse(a, "a0, e1");
    try testing.expectEqualStrings("a0", trailing.value.ok);
    try testing.expectEqual(@as(usize, 2), trailing.index);

    // Another kind of definition is not a reference.
    const wrong_kind = try axisRefParser.parse(a, "t0");
    try testing.expectEqual(@as(usize, 0), wrong_kind.index);
}
