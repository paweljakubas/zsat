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
    // `+` and `^` decide where the given value lands relative to what the
    // definition says, so `t0{+" world"}` plots "hello world" for a t0 defined
    // as "hello", and `t0{^"nice "}` plots "nice hello". Neither marker replaces.
    append: bool = false,
    prepend: bool = false,
    // Values filling the `{}` holes of the value defined in --styles, given as
    // `t0{{"1", "2"}}` for a t0 defined as "{} - {}", matched left to right.
    args: []const []const u8 = &.{},
};

pub const TextItem = struct {
    name: []const u8,
    override: ?TextOverride = null,
};

/// What `--outputs` puts between the braces of a text reference: either a value
/// on its own, or the list of values filling the holes of the definition.
const TextGivenValue = union(enum) {
    value: []const u8,
    args: []const []const u8,
};

// ---- value parser ----

/// A quoted value holds anything but the `"` that ends it. A `\` has to open an
/// escape, since letting a lone one through would make `\"` ambiguous: the two
/// readings disagree about where the value ends. The escape itself is a backslash
/// and whatever follows, which `unescapeTextValue` then gives a meaning to.
const quotedStringEscapeParser = mecha.combine(.{
    mecha.ascii.char('\\').discard(),
    mecha.ascii.wrap(struct {
        fn pred(_: u8) bool {
            return true;
        }
    }.pred).discard(),
}).discard();

const quotedStringContentParserRaw = mecha.many(mecha.oneOf(.{
    quotedStringEscapeParser,
    mecha.ascii.not(mecha.ascii.wrap(struct {
        fn pred(c: u8) bool {
            return c == '"' or c == '\\';
        }
    }.pred)).discard(),
}), .{ .collect = false }).asStr();

const quotedStringParserRaw = mecha.combine(.{
    mecha.ascii.char('"').discard(),
    quotedStringContentParserRaw,
    mecha.ascii.char('"').discard(),
});
const quotedStringParser = quotedStringParserRaw.convert(struct {
    fn conv(arena: std.mem.Allocator, res: []const u8) mecha.ConvertError![]const u8 {
        return try arena.dupe(u8, res);
    }
}.conv);

/// Turns the escapes a quoted value may carry into what they mean: `\"` is a
/// `"`, `\n` is a line break, which `plot` draws as another line below, and `\\`
/// is a single backslash. Any other escape is left as written, so a value can
/// still show a `\n` of its own by doubling the backslash, and `\t` stays the
/// two characters rather than becoming a tab of unpredictable width.
fn unescapeTextValue(arena: std.mem.Allocator, raw: []const u8) mecha.ConvertError![]const u8 {
    if (std.mem.indexOfScalar(u8, raw, '\\') == null) return try arena.dupe(u8, raw);

    var buf = std.ArrayList(u8).empty;
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '\\' and i + 1 < raw.len) switch (raw[i + 1]) {
            '"' => {
                try buf.append(arena, '"');
                i += 2;
                continue;
            },
            'n' => {
                try buf.append(arena, '\n');
                i += 2;
                continue;
            },
            '\\' => {
                try buf.append(arena, '\\');
                i += 2;
                continue;
            },
            else => {},
        };
        try buf.append(arena, raw[i]);
        i += 1;
    }
    return buf.toOwnedSlice(arena);
}

const quotedTextValueParser = quotedStringParserRaw.convert(unescapeTextValue);

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

// An unquoted value holds no whitespace to begin with, so it has no escape to
// decode either and is taken as it is.
pub const textValueParser = mecha.oneOf(.{ quotedTextValueParser, unquotedStringParser });

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

const textOverrideArgsParserRaw = mecha.combine(.{
    common.skipOpenBrace,
    mecha.many(textValueParser, .{ .collect = true, .min = 1, .separator = textSeparatorParser }),
    common.skipCloseBrace,
});
const textOverrideArgsParser = textOverrideArgsParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: [][]const u8) mecha.ConvertError!TextGivenValue {
        return TextGivenValue{ .args = res };
    }
}.conv);

const textOverrideValueParser = mecha.oneOf(.{
    textOverrideArgsParser,
    textValueParser.convert(struct {
        fn conv(_: std.mem.Allocator, res: []const u8) mecha.ConvertError!TextGivenValue {
            return TextGivenValue{ .value = res };
        }
    }.conv),
});

const textOverrideBodyParser = mecha.combine(.{
    common.skipOpenBrace,
    mecha.many(mecha.oneOf(.{ mecha.ascii.char('+'), mecha.ascii.char('^') }), .{ .collect = false, .max = 2 }),
    common.skipWhitespace,
    mecha.opt(textOverrideValueParser),
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
        override.append = std.mem.indexOfScalar(u8, body[0], '+') != null;
        override.prepend = std.mem.indexOfScalar(u8, body[0], '^') != null;
        if (body[1]) |given| switch (given) {
            .value => |v| override.value = v,
            .args => |args| override.args = args,
        };
        return TextItem{ .name = name, .override = override };
    }
}.conv);

pub const textItemParser = mecha.oneOf(.{
    textItemWithOverrideParser,
    textItemRefParser,
});

// ---- resolve text overlay from definition + item ----

threadlocal var holeErrorDetail: ?[]const u8 = null;

/// Explains the last `error.TextHoleCountMismatch`, naming the text object and
/// both counts.
pub fn textHoleErrorDetail() ?[]const u8 {
    return holeErrorDetail;
}

fn countTextHoles(template: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i + 1 < template.len) : (i += 1) {
        if (template[i] == '{' and template[i + 1] == '}') count += 1;
    }
    return count;
}

/// Fills each `{}` hole of `template` with the matching entry of `args`, in
/// order, so a t0 defined as "{} - {}" plots "1 - 2" when given the args
/// ["1", "2"]. Holes may come before, after or between any amount of text, and
/// their count has to match: pairing them up otherwise would only be a guess.
/// A `{` not followed by `}` is kept as it is, so literal text is still
/// expressible.
pub fn substituteTextHoles(arena: std.mem.Allocator, owner: []const u8, template: []const u8, args: []const []const u8) ![]const u8 {
    const holes = countTextHoles(template);
    if (holes != args.len) {
        holeErrorDetail = try std.fmt.allocPrint(arena, "Error: text object '{s}' is defined with {d} '{{}}' hole(s) in --styles, but {d} value(s) were given in --outputs.", .{ owner, holes, args.len });
        return error.TextHoleCountMismatch;
    }

    var buf = std.ArrayList(u8).empty;
    var used: usize = 0;
    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '{' and i + 1 < template.len and template[i + 1] == '}') {
            try buf.appendSlice(arena, args[used]);
            used += 1;
            i += 2;
        } else {
            try buf.append(arena, template[i]);
            i += 1;
        }
    }
    return buf.toOwnedSlice(arena);
}

pub fn resolveTextOverlay(arena: std.mem.Allocator, item: TextItem, texts: []const TextDefinition) !?Text {
    for (texts) |def| {
        if (std.mem.eql(u8, def.name, item.name)) {
            var result = def.text;
            if (item.override) |ov| {
                // The holes belong to the definition, so they are filled before
                // `+` or a replacement value gets to say anything about it.
                const filled = if (ov.args.len > 0)
                    try substituteTextHoles(arena, item.name, result.value, ov.args)
                else
                    result.value;
                if (ov.value) |v| {
                    // `^` puts the value in front, `+` behind, both wrap, and
                    // no marker at all replaces what the definition says.
                    result.value = if (ov.prepend and ov.append)
                        try std.fmt.allocPrint(arena, "{s}{s}{s}", .{ v, filled, v })
                    else if (ov.prepend)
                        try std.mem.concat(arena, u8, &.{ v, filled })
                    else if (ov.append)
                        try std.mem.concat(arena, u8, &.{ filled, v })
                    else
                        v;
                } else {
                    result.value = filled;
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

test "textValueParser decodes escapes in a quoted value" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `\n` is a line break, so a value can hold more than one line.
    const r1 = try textValueParser.parse(a, "\"a\\nb\"");
    try testing.expectEqualStrings("a\nb", r1.value.ok);

    // `\\` is a backslash, which is how a value shows a `\n` of its own.
    const r2 = try textValueParser.parse(a, "\"a\\\\nb\"");
    try testing.expectEqualStrings("a\\nb", r2.value.ok);

    // Any other escape is left as written, rather than turned into a character
    // whose width or meaning the author did not ask for.
    const r3 = try textValueParser.parse(a, "\"a\\tb\"");
    try testing.expectEqualStrings("a\\tb", r3.value.ok);

    // `\"` is a `"` of the value's own, which is how a value gets to hold the
    // character that would otherwise end it.
    const r4 = try textValueParser.parse(a, "\"a\\\"b\"");
    try testing.expectEqualStrings("a\"b", r4.value.ok);

    const r5 = try textValueParser.parse(a, "\"say \\\"hi\\\"\"");
    try testing.expectEqualStrings("say \"hi\"", r5.value.ok);

    // An unescaped `"` still ends the value, leaving the rest of the input for
    // `--styles` or `--outputs` to refuse rather than for the value to swallow.
    const r6 = try textValueParser.parse(a, "\"a\"b\"");
    try testing.expectEqualStrings("a", r6.value.ok);
    try testing.expectEqual(@as(usize, 3), r6.index);

    // An escaped quote and the end of the value read apart, so a backslash
    // before the closing quote leaves the value open rather than ending it.
    const open = try textValueParser.parse(a, "\"ab\\\"");
    switch (open.value) {
        .ok => return error.TestUnexpectedResult,
        .err => {},
    }

    // A real tab is a real tab; only the spelling of a newline is decoded.
    const r7 = try textValueParser.parse(a, "\"a\tb\"");
    try testing.expectEqualStrings("a\tb", r7.value.ok);

    // Line breaks may come one after another, leaving an empty line between.
    const r8 = try textValueParser.parse(a, "\"a\\n\\nb\"");
    try testing.expectEqualStrings("a\n\nb", r8.value.ok);

    // An unquoted value has no whitespace to begin with, so nothing is decoded.
    const r9 = try textValueParser.parse(a, "a\\nb");
    try testing.expectEqualStrings("a\\nb", r9.value.ok);
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

    const r3 = try textDefParser.parse(a, "t2: {txt \"one\\ntwo\" [c:blue]}");
    try testing.expectEqualStrings("one\ntwo", r3.value.ok.text.value);
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

    // `{{...}}` carries the values filling the `{}` holes of the definition.
    const r8 = try textItemParser.parse(a, "t0{{\"1\", \"2\"}}");
    try testing.expectEqualStrings("t0", r8.value.ok.name);
    try testing.expect(!r8.value.ok.override.?.append);
    try testing.expect(r8.value.ok.override.?.value == null);
    try testing.expectEqual(@as(usize, 2), r8.value.ok.override.?.args.len);
    try testing.expectEqualStrings("1", r8.value.ok.override.?.args[0]);
    try testing.expectEqualStrings("2", r8.value.ok.override.?.args[1]);

    const r9 = try textItemParser.parse(a, "t0{ { x , y } }");
    try testing.expectEqual(@as(usize, 2), r9.value.ok.override.?.args.len);
    try testing.expectEqualStrings("x", r9.value.ok.override.?.args[0]);
    try testing.expectEqualStrings("y", r9.value.ok.override.?.args[1]);

    // A single value is a value, not a one element list.
    const r10 = try textItemParser.parse(a, "t0{{\"1\"}}");
    try testing.expectEqual(@as(usize, 1), r10.value.ok.override.?.args.len);
    try testing.expectEqualStrings("1", r10.value.ok.override.?.args[0]);

    // mecha stops at the first match, so a list that is empty or dangling is not
    // rejected here; it is `--outputs` that insists on consuming its whole
    // input, and so turns these into a parse error.
    const r11 = try textItemParser.parse(a, "t0{{}}");
    try testing.expectEqualStrings("{", r11.value.ok.override.?.value.?);

    // `^` prepends, and may be written alongside `+` or with spaces around it.
    const r12 = try textItemParser.parse(a, "t0{^\"nice \"}");
    try testing.expect(r12.value.ok.override.?.prepend);
    try testing.expect(!r12.value.ok.override.?.append);
    try testing.expectEqualStrings("nice ", r12.value.ok.override.?.value.?);

    const r13 = try textItemParser.parse(a, "t0{ ^ nice }");
    try testing.expect(r13.value.ok.override.?.prepend);
    try testing.expectEqualStrings("nice", r13.value.ok.override.?.value.?);

    const r14 = try textItemParser.parse(a, "t0{^+x}");
    try testing.expect(r14.value.ok.override.?.prepend);
    try testing.expect(r14.value.ok.override.?.append);

    // Neither marker means the value replaces, and the marker is optional
    // altogether for a value on its own.
    const r15 = try textItemParser.parse(a, "t0{\"nice \"}");
    try testing.expect(!r15.value.ok.override.?.prepend);
    try testing.expect(!r15.value.ok.override.?.append);

    // Holes are filled regardless of the markers, and are a value of their own.
    const r16 = try textItemParser.parse(a, "t0{^{\"1\", \"2\"}}");
    try testing.expect(r16.value.ok.override.?.prepend);
    try testing.expectEqual(@as(usize, 2), r16.value.ok.override.?.args.len);
}

test "substituteTextHoles fills holes left to right" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const two = [_][]const u8{ "1", "2" };
    try testing.expectEqualStrings("1 - 2", try substituteTextHoles(a, "t0", "{} - {}", &two));

    // Holes may be preceded, followed and surrounded by any text.
    try testing.expectEqualStrings("<1|b|2>", try substituteTextHoles(a, "t0", "<{}|b|{}>", &two));
    try testing.expectEqualStrings("1", try substituteTextHoles(a, "t0", "{}", &[_][]const u8{"1"}));
    try testing.expectEqualStrings("a1 b2", try substituteTextHoles(a, "t0", "a{} b{}", &two));

    // A brace that does not open a hole is text.
    try testing.expectEqualStrings("{ k }", try substituteTextHoles(a, "t0", "{ {} }", &[_][]const u8{"k"}));
    try testing.expectEqualStrings("}{", try substituteTextHoles(a, "t0", "}{", &.{}));
    try testing.expectEqualStrings("", try substituteTextHoles(a, "t0", "", &.{}));

    // Values may be empty or multi character.
    try testing.expectEqualStrings("-ab", try substituteTextHoles(a, "t0", "{}-{}", &[_][]const u8{ "", "ab" }));

    // Pairing holes up by guesswork would be worse than saying so.
    try testing.expectError(error.TextHoleCountMismatch, substituteTextHoles(a, "t0", "{} - {}", &[_][]const u8{"1"}));
    try testing.expectError(error.TextHoleCountMismatch, substituteTextHoles(a, "t0", "{} - {}", &[_][]const u8{ "1", "2", "3" }));
    try testing.expectError(error.TextHoleCountMismatch, substituteTextHoles(a, "t0", "no holes", &[_][]const u8{"1"}));
    try testing.expectError(error.TextHoleCountMismatch, substituteTextHoles(a, "t0", "{}", &.{}));
    try testing.expect(std.mem.indexOf(u8, textHoleErrorDetail().?, "'t0'") != null);
}

test "resolveTextOverlay fills the holes of the definition" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const texts = [_]TextDefinition{
        .{ .name = "t0", .text = .{ .value = "{} - {}", .x = 0, .y = 0 } },
        .{ .name = "t1", .text = .{ .value = "plain", .x = 0, .y = 0 } },
    };

    const filled = try resolveTextOverlay(a, .{ .name = "t0", .override = .{ .args = &[_][]const u8{ "1", "2" } } }, &texts);
    try testing.expectEqualStrings("1 - 2", filled.?.value);

    // Without values the holes stay as they are, so a literal `{}` still works.
    const literal = try resolveTextOverlay(a, .{ .name = "t0" }, &texts);
    try testing.expectEqualStrings("{} - {}", literal.?.value);

    const untouched = try resolveTextOverlay(a, .{ .name = "t1", .override = .{} }, &texts);
    try testing.expectEqualStrings("plain", untouched.?.value);

    // A count that does not match is reported rather than papered over.
    try testing.expectError(error.TextHoleCountMismatch, resolveTextOverlay(a, .{ .name = "t0", .override = .{ .args = &[_][]const u8{"1"} } }, &texts));
    try testing.expectError(error.TextHoleCountMismatch, resolveTextOverlay(a, .{ .name = "t1", .override = .{ .args = &[_][]const u8{"1"} } }, &texts));
}

test "resolveTextOverlay appends with +, prepends with ^ and replaces without either" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const texts = [_]TextDefinition{.{ .name = "t0", .text = .{ .value = "hello", .x = 0, .y = 0 } }};

    const appended = try resolveTextOverlay(a, .{ .name = "t0", .override = .{ .value = " world", .append = true } }, &texts);
    try testing.expectEqualStrings("hello world", appended.?.value);

    const prepended = try resolveTextOverlay(a, .{ .name = "t0", .override = .{ .value = "nice ", .prepend = true } }, &texts);
    try testing.expectEqualStrings("nice hello", prepended.?.value);

    // Both markers wrap the definition, which is a shorthand of interest mostly
    // for a value that is not empty.
    const wrapped = try resolveTextOverlay(a, .{ .name = "t0", .override = .{ .value = "<", .append = true, .prepend = true } }, &texts);
    try testing.expectEqualStrings("<hello<", wrapped.?.value);

    const replaced = try resolveTextOverlay(a, .{ .name = "t0", .override = .{ .value = "world" } }, &texts);
    try testing.expectEqualStrings("world", replaced.?.value);

    const untouched = try resolveTextOverlay(a, .{ .name = "t0", .override = .{} }, &texts);
    try testing.expectEqualStrings("hello", untouched.?.value);

    const by_reference = try resolveTextOverlay(a, .{ .name = "t0" }, &texts);
    try testing.expectEqualStrings("hello", by_reference.?.value);

    const missing = try resolveTextOverlay(a, .{ .name = "t9" }, &texts);
    try testing.expect(missing == null);
}
