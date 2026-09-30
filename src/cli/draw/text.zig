const std = @import("std");
const testing = std.testing;
const mecha = @import("mecha");
const common = @import("common.zig");
const inputs = @import("inputs.zig");

pub const Text = struct {
    value: []const u8,
    x: f32,
    y: f32,
    color: common.ColorName = .black,
    size: u16 = 16,
    font: []const u8 = "default",
    opacity: u8 = 100,
    angle: f32 = 0,
};

pub const TextDefinition = struct {
    name: []const u8,
    text: Text,
};

pub const TextOverride = struct {
    value: ?[]const u8 = null,
    // `+` before the value appends to what the definition says instead of
    // replacing it, so `t0{+" world"}` plots "hello world" for a t0 defined as
    // "hello".
    append: bool = false,
};

pub const TextItem = struct {
    name: []const u8,
    override: ?TextOverride = null,
};

// ---- value parser ----

const quotedStringParserRaw = mecha.combine(.{
    mecha.ascii.char('"').discard(),
    mecha.many(mecha.ascii.not(mecha.ascii.char('"')), .{ .collect = false }).asStr(),
    mecha.ascii.char('"').discard(),
});
const quotedStringParser = quotedStringParserRaw.convert(struct {
    fn conv(arena: std.mem.Allocator, res: []const u8) mecha.ConvertError![]const u8 {
        return try arena.dupe(u8, res);
    }
}.conv);

const textCharPred = struct {
    fn pred(c: u8) bool {
        return c != '(' and c != '[' and c != ',' and c != '}' and c != '"' and !std.ascii.isWhitespace(c);
    }
}.pred;
const unquotedStringParserRaw = mecha.many(mecha.ascii.wrap(textCharPred), .{ .collect = false, .min = 1 }).asStr();
const unquotedStringParser = unquotedStringParserRaw.convert(struct {
    fn conv(arena: std.mem.Allocator, res: []const u8) mecha.ConvertError![]const u8 {
        return try arena.dupe(u8, res);
    }
}.conv);

pub const textValueParser = mecha.oneOf(.{ quotedStringParser, unquotedStringParser });

// ---- point parser ----

const textPointParserRaw = mecha.combine(.{
    common.skipOpenBracket,
    inputs.floatParser,
    common.skipComma,
    inputs.floatParser,
    common.skipCloseBracket,
});
const textPointParserRawP = @TypeOf(textPointParserRaw);
const textPointParser = textPointParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: textPointParserRawP.T) mecha.ConvertError!inputs.Point {
        return inputs.Point{ .x = res[0], .y = res[1] };
    }
}.conv);

// ---- attributes parser ----

const TextAttributeUnion = union(enum) {
    textColor: common.ColorName,
    textSize: u16,
    textFont: []const u8,
    textOpacity: u8,
};

const textColorParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("color"), mecha.string("c") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.colorNameParserTyped,
});
const textColorUnionParser = textColorParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: common.ColorName) mecha.ConvertError!TextAttributeUnion {
        return TextAttributeUnion{ .textColor = res };
    }
}.conv);

const textSizeParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("size"), mecha.string("s") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u16, .{}),
});
const textSizeUnionParser = textSizeParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u16) mecha.ConvertError!TextAttributeUnion {
        return TextAttributeUnion{ .textSize = res };
    }
}.conv);

const textFontParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("font"), mecha.string("f") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    textValueParser,
});
const textFontUnionParser = textFontParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: []const u8) mecha.ConvertError!TextAttributeUnion {
        return TextAttributeUnion{ .textFont = res };
    }
}.conv);

const textOpacityParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("opacity"), mecha.string("o") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u8, .{}),
});
const textOpacityUnionParser = textOpacityParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u8) mecha.ConvertError!TextAttributeUnion {
        return TextAttributeUnion{ .textOpacity = res };
    }
}.conv);

const textAttributeUnionParser = mecha.oneOf(.{
    textColorUnionParser,
    textSizeUnionParser,
    textFontUnionParser,
    textOpacityUnionParser,
});

const textSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
const manyTextAttributeUnionParser = mecha.many(textAttributeUnionParser, .{ .collect = true, .min = 1, .separator = textSeparatorParser });

fn manyToText(_: std.mem.Allocator, fields: []TextAttributeUnion) mecha.ConvertError!Text {
    var res = Text{ .value = "", .x = 0, .y = 0 };
    for (fields) |field| switch (field) {
        .textColor => |v| res.color = v,
        .textSize => |v| res.size = v,
        .textFont => |v| res.font = v,
        .textOpacity => |v| res.opacity = v,
    };
    return res;
}

pub const textAttributesParser = manyTextAttributeUnionParser.convert(manyToText);

// ---- full definition parser: t0: {txt "value" (x,y) [attrs]} ----

const textDefNumberParser = mecha.combine(.{
    common.skipWhitespace,
    mecha.ascii.char('t').discard(),
    mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 }).asStr().convert(mecha.toInt(u8, 10)),
});
const textDefNumberParserP = @TypeOf(textDefNumberParser);

const textDefBodyParser = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("txt"), mecha.string("t") }).discard(),
    common.skipWhitespace,
    textValueParser,
    common.skipWhitespace,
    mecha.opt(mecha.combine(.{
        common.skipOpenSquare,
        textAttributesParser,
        common.skipCloseSquare,
    }).convert(struct {
        fn conv(_: std.mem.Allocator, res: Text) mecha.ConvertError!Text {
            return res;
        }
    }.conv)),
});
const textDefBodyParserP = @TypeOf(textDefBodyParser);

const textDefParserRaw = mecha.combine(.{
    textDefNumberParser,
    mecha.opt(mecha.ascii.char(':').discard()),
    common.skipWhitespace,
    common.skipOpenBrace,
    textDefBodyParser,
    common.skipCloseBrace,
});
const textDefParserRawP = @TypeOf(textDefParserRaw);
fn toTextDef(arena: std.mem.Allocator, res: textDefParserRawP.T) mecha.ConvertError!TextDefinition {
    const number = res[0];
    const body = res[2];
    const name = try std.fmt.allocPrint(arena, "t{d}", .{number});
    var text_val = Text{
        .value = body[0],
        .x = 0,
        .y = 0,
    };
    if (body[1]) |attrs| {
        text_val.color = attrs.color;
        text_val.size = attrs.size;
        text_val.font = attrs.font;
        text_val.opacity = attrs.opacity;
    }
    return TextDefinition{ .name = name, .text = text_val };
}
pub const textDefParser = textDefParserRaw.convert(toTextDef);

// ---- text item parser for outpus: tN or tN{"value", (x,y)} ----

const textItemNumberParser = mecha.combine(.{
    common.skipWhitespace,
    mecha.ascii.char('t').discard(),
    mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 }).asStr().convert(mecha.toInt(u8, 10)),
});
const textItemNumberParserP = @TypeOf(textItemNumberParser);

const textOverrideBodyParser = mecha.combine(.{
    common.skipOpenBrace,
    mecha.opt(mecha.ascii.char('+')),
    mecha.opt(textValueParser),
    common.skipCloseBrace,
});
const textOverrideBodyParserP = @TypeOf(textOverrideBodyParser);

const textItemOverrideParser = mecha.combine(.{
    textItemNumberParser,
    textOverrideBodyParser,
});
const textItemOverrideParserP = @TypeOf(textItemOverrideParser);

const textItemRefParser = textItemNumberParser.convert(struct {
    fn conv(arena: std.mem.Allocator, res: textItemNumberParserP.T) mecha.ConvertError!TextItem {
        const name = try std.fmt.allocPrint(arena, "t{d}", .{res});
        return TextItem{ .name = name, .override = null };
    }
}.conv);

const textItemWithOverrideParser = textItemOverrideParser.convert(struct {
    fn conv(arena: std.mem.Allocator, res: textItemOverrideParserP.T) mecha.ConvertError!TextItem {
        const number = res[0];
        const body = res[1];
        const name = try std.fmt.allocPrint(arena, "t{d}", .{number});
        var override = TextOverride{};
        override.append = body[0] != null;
        if (body[1]) |v| override.value = v;
        return TextItem{ .name = name, .override = override };
    }
}.conv);

pub const textItemParser = mecha.oneOf(.{
    textItemWithOverrideParser,
    textItemRefParser,
});

// ---- resolve text overlay from definition + item ----

pub fn resolveTextOverlay(arena: std.mem.Allocator, item: TextItem, texts: []const TextDefinition) !?Text {
    for (texts) |def| {
        if (std.mem.eql(u8, def.name, item.name)) {
            var result = def.text;
            if (item.override) |ov| {
                if (ov.value) |v| {
                    result.value = if (ov.append)
                        try std.mem.concat(arena, u8, &.{ result.value, v })
                    else
                        v;
                }
            }
            // duplicate strings into arena if needed
            result.value = try arena.dupe(u8, result.value);
            result.font = try arena.dupe(u8, result.font);
            return result;
        }
    }
    return null;
}

pub fn serializeText(allocator: std.mem.Allocator, text: Text) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{{txt \"{s}\" [c:{s}, s:{}, f:{s}, o:{}]}}", .{
        text.value,
        @tagName(text.color),
        text.size,
        text.font,
        text.opacity,
    });
}

pub fn serializeTextDefinitions(allocator: std.mem.Allocator, texts: []const TextDefinition) ![]const u8 {
    if (texts.len == 0) return try allocator.dupe(u8, "");
    var parts = std.ArrayList([]const u8).empty;
    defer {
        for (parts.items) |p| allocator.free(p);
        parts.deinit(allocator);
    }

    for (texts, 0..) |def, i| {
        if (i > 0) try parts.append(allocator, try allocator.dupe(u8, ", "));
        const text_str = try serializeText(allocator, def.text);
        defer allocator.free(text_str);
        const full = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ def.name, text_str });
        try parts.append(allocator, full);
    }

    return try std.mem.join(allocator, "", parts.items);
}

// ---- tests ----

test "textValueParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try textValueParser.parse(a, "\"hello world\"");
    try testing.expectEqualStrings("hello world", r1.value.ok);

    const r2 = try textValueParser.parse(a, "hello");
    try testing.expectEqualStrings("hello", r2.value.ok);
}

test "textPointParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try textPointParser.parse(a, "(1.5, 2.5)");
    try testing.expectEqual(@as(f32, 1.5), r1.value.ok.x);
    try testing.expectEqual(@as(f32, 2.5), r1.value.ok.y);
}

test "textAttributesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try textAttributesParser.parse(a, "c:red, s:20, f:Arial, o:80");
    try testing.expectEqual(common.ColorName.red, r1.value.ok.color);
    try testing.expectEqual(@as(u16, 20), r1.value.ok.size);
    try testing.expectEqualStrings("Arial", r1.value.ok.font);
    try testing.expectEqual(@as(u8, 80), r1.value.ok.opacity);
}

test "textDefParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try textDefParser.parse(a, "t0: {txt \"hello\" [c:red, s:20]}");
    try testing.expectEqualStrings("t0", r1.value.ok.name);
    try testing.expectEqualStrings("hello", r1.value.ok.text.value);
    try testing.expectEqual(common.ColorName.red, r1.value.ok.text.color);
    try testing.expectEqual(@as(u16, 20), r1.value.ok.text.size);

    const r2 = try textDefParser.parse(a, "t1: {t world}");
    try testing.expectEqualStrings("t1", r2.value.ok.name);
    try testing.expectEqualStrings("world", r2.value.ok.text.value);
    try testing.expectEqual(common.ColorName.black, r2.value.ok.text.color);
    try testing.expectEqual(@as(u16, 16), r2.value.ok.text.size);
}

test "textItemParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try textItemParser.parse(a, "t0");
    try testing.expectEqualStrings("t0", r1.value.ok.name);
    try testing.expect(r1.value.ok.override == null);

    const r2 = try textItemParser.parse(a, "t1{\"override\"}");
    try testing.expectEqualStrings("t1", r2.value.ok.name);
    try testing.expectEqualStrings("override", r2.value.ok.override.?.value.?);

    const r3 = try textItemParser.parse(a, "t2{}");
    try testing.expectEqualStrings("t2", r3.value.ok.name);
    try testing.expect(r3.value.ok.override.?.value == null);

    const r4 = try textItemParser.parse(a, "t0{+\" world\"}");
    try testing.expectEqualStrings("t0", r4.value.ok.name);
    try testing.expect(r4.value.ok.override.?.append);
    try testing.expectEqualStrings(" world", r4.value.ok.override.?.value.?);

    const r5 = try textItemParser.parse(a, "t0{+tail}");
    try testing.expectEqualStrings("t0", r5.value.ok.name);
    try testing.expect(r5.value.ok.override.?.append);
    try testing.expectEqualStrings("tail", r5.value.ok.override.?.value.?);

    // Without `+` the value replaces what the definition says.
    const r6 = try textItemParser.parse(a, "t0{\"world\"}");
    try testing.expectEqualStrings("t0", r6.value.ok.name);
    try testing.expect(!r6.value.ok.override.?.append);
    try testing.expectEqualStrings("world", r6.value.ok.override.?.value.?);

    const r7 = try textItemParser.parse(a, "t0{+}");
    try testing.expectEqualStrings("t0", r7.value.ok.name);
    try testing.expect(r7.value.ok.override.?.append);
    try testing.expect(r7.value.ok.override.?.value == null);
}

test "resolveTextOverlay appends with + and replaces without it" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const texts = [_]TextDefinition{.{ .name = "t0", .text = .{ .value = "hello", .x = 0, .y = 0 } }};

    const appended = try resolveTextOverlay(a, .{ .name = "t0", .override = .{ .value = " world", .append = true } }, &texts);
    try testing.expectEqualStrings("hello world", appended.?.value);

    const replaced = try resolveTextOverlay(a, .{ .name = "t0", .override = .{ .value = "world" } }, &texts);
    try testing.expectEqualStrings("world", replaced.?.value);

    const untouched = try resolveTextOverlay(a, .{ .name = "t0", .override = .{} }, &texts);
    try testing.expectEqualStrings("hello", untouched.?.value);

    const by_reference = try resolveTextOverlay(a, .{ .name = "t0" }, &texts);
    try testing.expectEqualStrings("hello", by_reference.?.value);

    const missing = try resolveTextOverlay(a, .{ .name = "t9" }, &texts);
    try testing.expect(missing == null);
}
