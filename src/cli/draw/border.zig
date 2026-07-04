const std = @import("std");
const testing = std.testing;
const mecha = @import("mecha");
const common = @import("common.zig");

pub const Border = struct {
    width: u16 = 0,
    opacity: u8 = 100,
    color: common.ColorName = .black,
};

const BorderAttributeUnion = union(enum) {
    borderWidth: u16,
    borderOpacity: u8,
    borderColor: common.ColorName,
};

// borderWidth / bw parser
const borderWidthParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("borderWidth"), mecha.string("bw") }).discard(),
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

    const r1 = try borderWidthParserRaw.parse(a, "borderWidth:30");
    try testing.expectEqual(@as(u16, 30), r1.value.ok);

    const r2 = try borderWidthParserRaw.parse(a, "bw: 10");
    try testing.expectEqual(@as(u16, 10), r2.value.ok);
}

// borderOpacity / bo parser
const borderOpacityParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("borderOpacity"), mecha.string("bo") }).discard(),
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

    const r1 = try borderOpacityParserRaw.parse(a, "borderOpacity:50");
    try testing.expectEqual(@as(u8, 50), r1.value.ok);

    const r2 = try borderOpacityParserRaw.parse(a, "bo: 100");
    try testing.expectEqual(@as(u8, 100), r2.value.ok);
}

// borderColor / bc parser
const borderColorParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("borderColor"), mecha.string("bc") }).discard(),
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

    const r1 = try borderColorParserRaw.parse(a, "borderColor:red");
    try testing.expectEqual(common.ColorName.red, r1.value.ok);

    const r2 = try borderColorParserRaw.parse(a, "bc: green");
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

const borderAttributesParser = manyBorderAttributeUnionParser.convert(manyToBorder);

test "borderAttributesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try borderAttributesParser.parse(a, "bw:30");
    const b1 = Border{ .width = 30, .opacity = 100, .color = .black };
    try testing.expectEqual(b1, r1.value.ok);

    const r2 = try borderAttributesParser.parse(a, "bo:50, bc:red");
    const b2 = Border{ .width = 0, .opacity = 50, .color = .red };
    try testing.expectEqual(b2, r2.value.ok);

    const r3 = try borderAttributesParser.parse(a, "bw:20, bo:75, bc:blue");
    const b3 = Border{ .width = 20, .opacity = 75, .color = .blue };
    try testing.expectEqual(b3, r3.value.ok);
}

// Full parser: "border [bw:30, bo:100, bc:red]"
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

    const r1 = try borderParser.parse(a, "border [bw:30, bo:100, bc:red]");
    const b1 = Border{ .width = 30, .opacity = 100, .color = .red };
    try testing.expectEqual(b1, r1.value.ok);

    const r2 = try borderParser.parse(a, "b [bw:10, bc:green]");
    const b2 = Border{ .width = 10, .opacity = 100, .color = .green };
    try testing.expectEqual(b2, r2.value.ok);

    const r3 = try borderParser.parse(a, "border [bo:50]");
    const b3 = Border{ .width = 0, .opacity = 50, .color = .black };
    try testing.expectEqual(b3, r3.value.ok);
}

// Parser for use inside pane body (includes "border" keyword and brackets)
pub const borderBracketedParser = borderParser;
