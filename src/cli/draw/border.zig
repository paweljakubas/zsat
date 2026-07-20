const std = @import("std");
const testing = std.testing;
const mecha = @import("mecha");
const common = @import("common.zig");

pub const Border = struct {
    width: u16 = 10,
    opacity: u8 = 100,
    color: common.ColorName = .black,
};

pub const BorderDefinition = struct {
    name: []const u8,
    w: Border,
};

const BorderAttributeUnion = union(enum) {
    borderWidth: u16,
    borderOpacity: u8,
    borderColor: common.ColorName,
};

// borderWidth / w parser
const borderWidthParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("width"), mecha.string("w") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u16, .{}),
});
const borderWidthUnionParser = borderWidthParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u16) mecha.ConvertError!BorderAttributeUnion {
        return BorderAttributeUnion{ .borderWidth = res };
    }
}.conv);

test "borderWidthParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try borderWidthParserRaw.parse(a, "width:30");
    try testing.expectEqual(@as(u16, 30), r1.value.ok);

    const r2 = try borderWidthParserRaw.parse(a, "w: 10");
    try testing.expectEqual(@as(u16, 10), r2.value.ok);
}

// borderOpacity / o parser
const borderOpacityParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("opacity"), mecha.string("o") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u8, .{}),
});
const borderOpacityUnionParser = borderOpacityParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u8) mecha.ConvertError!BorderAttributeUnion {
        return BorderAttributeUnion{ .borderOpacity = res };
    }
}.conv);

test "borderOpacityParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try borderOpacityParserRaw.parse(a, "opacity:50");
    try testing.expectEqual(@as(u8, 50), r1.value.ok);

    const r2 = try borderOpacityParserRaw.parse(a, "o: 100");
    try testing.expectEqual(@as(u8, 100), r2.value.ok);
}

// borderColor / c parser
const borderColorParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("color"), mecha.string("c") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.colorNameParserTyped,
});
const borderColorUnionParser = borderColorParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: common.ColorName) mecha.ConvertError!BorderAttributeUnion {
        return BorderAttributeUnion{ .borderColor = res };
    }
}.conv);

test "borderColorParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try borderColorParserRaw.parse(a, "color:red");
    try testing.expectEqual(common.ColorName.red, r1.value.ok);

    const r2 = try borderColorParserRaw.parse(a, "c: green");
    try testing.expectEqual(common.ColorName.green, r2.value.ok);
}

const borderAttributeUnionParser = mecha.oneOf(.{
    borderWidthUnionParser,
    borderOpacityUnionParser,
    borderColorUnionParser,
});

const borderSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
const manyBorderAttributeUnionParser = mecha.many(borderAttributeUnionParser, .{ .collect = true, .min = 1, .separator = borderSeparatorParser });

fn manyToBorder(_: std.mem.Allocator, fields: []BorderAttributeUnion) mecha.ConvertError!Border {
    var res = Border{};
    for (fields) |field| switch (field) {
        .borderWidth => |v| res.width = v,
        .borderOpacity => |v| res.opacity = v,
        .borderColor => |v| res.color = v,
    };
    return res;
}

pub const borderAttributesParser = manyBorderAttributeUnionParser.convert(manyToBorder);

test "borderAttributesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try borderAttributesParser.parse(a, "w:30");
    const b1 = Border{ .width = 30, .opacity = 100, .color = .black };
    try testing.expectEqual(b1, r1.value.ok);

    const r2 = try borderAttributesParser.parse(a, "o:50, c:red");
    const b2 = Border{ .width = 10, .opacity = 50, .color = .red };
    try testing.expectEqual(b2, r2.value.ok);

    const r3 = try borderAttributesParser.parse(a, "w:20, o:75, c:blue");
    const b3 = Border{ .width = 20, .opacity = 75, .color = .blue };
    try testing.expectEqual(b3, r3.value.ok);
}

// Full parser: "border [b:30, o:100, c:red]"
const borderParserRaw = mecha.combine(.{
    common.skipWhitespace,
    mecha.oneOf(.{ mecha.string("border"), mecha.string("b") }).discard(),
    common.skipWhitespace,
    common.skipOpenSquare,
    borderAttributesParser,
    common.skipCloseSquare,
});
const borderParserRawP = @TypeOf(borderParserRaw);
fn toBorder(_: std.mem.Allocator, res: borderParserRawP.T) mecha.ConvertError!Border {
    return res;
}
pub const borderParser = borderParserRaw.convert(toBorder);

test "borderParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try borderParser.parse(a, "border [w:30, o:100, c:red]");
    const b1 = Border{ .width = 30, .opacity = 100, .color = .red };
    try testing.expectEqual(b1, r1.value.ok);

    const r2 = try borderParser.parse(a, "b [w:10, c:green]");
    const b2 = Border{ .width = 10, .opacity = 100, .color = .green };
    try testing.expectEqual(b2, r2.value.ok);

    const r3 = try borderParser.parse(a, "border [o:50]");
    const b3 = Border{ .width = 10, .opacity = 50, .color = .black };
    try testing.expectEqual(b3, r3.value.ok);
}

// Border definition parser for styles: "b0: border [b:30]" or "b12: border"
const borderDefNumberParser = mecha.combine(.{
    common.skipWhitespace,
    mecha.ascii.char('b').discard(),
    mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 }).asStr().convert(mecha.toInt(u8, 10)),
});
const borderDefNumberParserP = @TypeOf(borderDefNumberParser);

const borderDefBodyParser = mecha.oneOf(.{
    // border [w:30, c:red]
    mecha.combine(.{
        mecha.oneOf(.{ mecha.string("border"), mecha.string("b") }).discard(),
        common.skipWhitespace,
        common.skipOpenSquare,
        borderAttributesParser,
        common.skipCloseSquare,
    }).convert(struct {
        fn conv(_: std.mem.Allocator, res: Border) mecha.ConvertError!Border {
            return res;
        }
    }.conv),
    // border (default)
    mecha.oneOf(.{ mecha.string("border"), mecha.string("b") }).convert(struct {
        fn conv(_: std.mem.Allocator, _: anytype) mecha.ConvertError!Border {
            return Border{};
        }
    }.conv),
});

const borderDefParserRaw = mecha.combine(.{
    borderDefNumberParser,
    mecha.opt(mecha.ascii.char(':').discard()),
    common.skipWhitespace,
    common.skipOpenBrace,
    borderDefBodyParser,
    common.skipCloseBrace,
});
const borderDefParserRawP = @TypeOf(borderDefParserRaw);
fn toBorderDef(arena: std.mem.Allocator, res: borderDefParserRawP.T) mecha.ConvertError!BorderDefinition {
    const number = res[0];
    const border_val = res[2];
    const name = try std.fmt.allocPrint(arena, "b{d}", .{number});
    return BorderDefinition{ .name = name, .w = border_val };
}
pub const borderDefParser = borderDefParserRaw.convert(toBorderDef);

test "borderDefParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try borderDefParser.parse(a, "b0: {border [w:30, c:red]}");
    try testing.expectEqualStrings("b0", r1.value.ok.name);
    try testing.expectEqual(Border{ .width = 30, .opacity = 100, .color = .red }, r1.value.ok.w);

    const r2 = try borderDefParser.parse(a, "b12: {border}");
    try testing.expectEqualStrings("b12", r2.value.ok.name);
    try testing.expectEqual(Border{ .width = 10, .opacity = 100, .color = .black }, r2.value.ok.w);

    const r3 = try borderDefParser.parse(a, "b1: {b [w:20, o:50]}");
    try testing.expectEqualStrings("b1", r3.value.ok.name);
    try testing.expectEqual(Border{ .width = 20, .opacity = 50, .color = .black }, r3.value.ok.w);
}

// Parser for pane border field: "border: [b:30, c:red]" (returns Border)
pub const paneBorderInlineParser = mecha.combine(.{
    common.skipWhitespace,
    mecha.oneOf(.{ mecha.string("border"), mecha.string("b") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.skipOpenSquare,
    borderAttributesParser,
    common.skipCloseSquare,
}).convert(struct {
    fn conv(_: std.mem.Allocator, res: Border) mecha.ConvertError!Border {
        return res;
    }
}.conv);

test "paneBorderInlineParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try paneBorderInlineParser.parse(a, "border: [w:30, c:red]");
    try testing.expectEqual(Border{ .width = 30, .opacity = 100, .color = .red }, r1.value.ok);

    const r2 = try paneBorderInlineParser.parse(a, "b: [w:15]");
    try testing.expectEqual(Border{ .width = 15, .opacity = 100, .color = .black }, r2.value.ok);
}

// Parser for pane border reference: "border: b0" (returns []const u8)
pub const paneBorderRefParser = mecha.combine(.{
    common.skipWhitespace,
    mecha.oneOf(.{ mecha.string("border"), mecha.string("b") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.combine(.{
        mecha.ascii.char('b'),
        mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1 }),
    }).asStr(),
}).convert(struct {
    fn conv(_: std.mem.Allocator, res: []const u8) mecha.ConvertError![]const u8 {
        return res;
    }
}.conv);

test "paneBorderRefParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try paneBorderRefParser.parse(a, "border: b0");
    try testing.expectEqualStrings("b0", r1.value.ok);

    const r2 = try paneBorderRefParser.parse(a, "b: b12");
    try testing.expectEqualStrings("b12", r2.value.ok);
}
