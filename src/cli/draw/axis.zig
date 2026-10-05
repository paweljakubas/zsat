const std = @import("std");
const testing = std.testing;
const mecha = @import("mecha");
const common = @import("common.zig");
const inputs = @import("inputs.zig");

// ---- enums ----

pub const TickForm = enum {
    above,
    middle,
    below,
    dot,
    square,
};

// Which point of a value label sits on the offset that `spacing` places off
// the axis. `center` puts the middle there, so a longer number grows in both
// directions. `start`/`end` put an edge there, which keeps the distance from
// the axis line fixed no matter how many digits the label has. The names refer
// to the label's reading direction, which rotates with `angle`, so `start` is
// not necessarily the leftmost edge on screen.
pub const TickEdge = enum {
    center,
    start,
    end,
};

// ---- style structs ----

pub const AxisLineStyle = struct {
    color: common.ColorName = .black,
    opacity: u8 = 100,
    size: u16 = 2,
};

pub const TickStyle = struct {
    color: common.ColorName = .black,
    opacity: u8 = 100,
    size: u16 = 1,
    height: u16 = 5,
    form: TickForm = .above,
};

pub const ValueStyle = struct {
    color: common.ColorName = .black,
    size: u16 = 12,
    font: []const u8 = "default",
    opacity: u8 = 100,
    spacing: u16 = 2,
    form: TickForm = .above,
    angle: inputs.Angle = .{ .degrees = 0 },
    edge: TickEdge = .center,
};

/// Parse-time partial representation of a ticks style. Fields are null when
/// not written, so a base axis can fill them in during style resolution.
const PartialTickStyle = struct {
    color: ?common.ColorName = null,
    opacity: ?u8 = null,
    size: ?u16 = null,
    height: ?u16 = null,
    form: ?TickForm = null,
};

/// Parse-time partial representation of a values style.
const PartialValueStyle = struct {
    color: ?common.ColorName = null,
    size: ?u16 = null,
    font: ?[]const u8 = null,
    opacity: ?u8 = null,
    spacing: ?u16 = null,
    form: ?TickForm = null,
    angle: ?inputs.Angle = null,
    edge: ?TickEdge = null,
};

pub const TickDefinition = struct {
    positions: []const f32,
    style: TickStyle = .{},
};

pub const ValueDefinition = struct {
    vals: []const f32,
    style: ValueStyle = .{},
};

pub const Axis = struct {
    line: AxisLineStyle = .{},
    ticks: ?TickDefinition = null,
    values: ?ValueDefinition = null,
};

/// Parse-time partial representation of a ticks section. Fields are null when
/// not written in the definition body, so a base axis can fill them in.
const PartialTick = struct {
    positions: ?[]const f32 = null,
    style: ?PartialTickStyle = null,
};

/// Parse-time partial representation of a values section.
const PartialValue = struct {
    vals: ?[]const f32 = null,
    style: ?PartialValueStyle = null,
};

/// Parse-time partial representation of an axis definition. `base` references
/// another axis by the name it is known under (`aM`, or `ns::aM` when it came
/// from a namespace import) whose resolved style is used as a starting point,
/// and the fields present in the body override it following the style update
/// rules.
const PartialAxis = struct {
    base: ?[]const u8 = null,
    line: ?AxisLineStyle = null,
    ticks: ?PartialTick = null,
    values: ?PartialValue = null,
};

pub const AxisDefinition = struct {
    number: u8,
    name: []const u8,
    axis: PartialAxis,
};

/// Axis with the full inheritance chain resolved into concrete styles.
pub const ResolvedAxis = struct {
    name: []const u8,
    axis: Axis,
};

pub const AxisItem = struct {
    name: []const u8,
};

pub const AxisOverride = struct {
    // Reserved for future overrides
};

pub const AxisOverlay = struct {
    from: inputs.Point,
    to: inputs.Point,
    line: AxisLineStyle,
    ticks: ?TickDefinition,
    values: ?ValueDefinition,
};

// ---- position / vals parser (explicit list or range) ----

const explicitFloatListParser = common.floatFromDecimal.many(.{ .collect = true, .separator = common.skipComma });

const floatRangeParser = mecha.combine(.{
    common.floatFromDecimal,
    common.skipComma,
    common.floatFromDecimal,
    common.skipComma,
    mecha.string("..").discard(),
    common.skipComma,
    common.floatFromDecimal,
}).convert(struct {
    fn conv(arena: std.mem.Allocator, res: anytype) mecha.ConvertError![]f32 {
        const start = res[0];
        const second = res[1];
        const end = res[2];
        const step = second - start;
        if (@abs(step) < 1e-10) {
            const arr = try arena.alloc(f32, 1);
            arr[0] = start;
            return arr;
        }
        var count: usize = 0;
        if (step > 0) {
            if (end < start) {
                const arr = try arena.alloc(f32, 1);
                arr[0] = start;
                return arr;
            }
            count = @as(usize, @intFromFloat(@floor((end - start) / step))) + 1;
        } else {
            if (end > start) {
                const arr = try arena.alloc(f32, 1);
                arr[0] = start;
                return arr;
            }
            count = @as(usize, @intFromFloat(@floor((start - end) / -step))) + 1;
        }
        if (count > 10000) return error.ConversionFailed;
        var arr = try arena.alloc(f32, count);
        for (0..count) |i| {
            arr[i] = start + @as(f32, @floatFromInt(i)) * step;
        }
        return arr;
    }
}.conv);

const floatPositionsParser = mecha.oneOf(.{
    floatRangeParser,
    explicitFloatListParser,
});

test "floatPositionsParser explicit" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try floatPositionsParser.parse(a, "2, 4, 6, 8, 10");
    try testing.expectEqual(@as(usize, 5), r1.value.ok.len);
    try testing.expectEqual(@as(f32, 2.0), r1.value.ok[0]);
    try testing.expectEqual(@as(f32, 10.0), r1.value.ok[4]);
}

test "floatPositionsParser range" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try floatPositionsParser.parse(a, "2, 4, .., 10");
    try testing.expectEqual(@as(usize, 5), r1.value.ok.len);
    try testing.expectEqual(@as(f32, 2.0), r1.value.ok[0]);
    try testing.expectEqual(@as(f32, 4.0), r1.value.ok[1]);
    try testing.expectEqual(@as(f32, 10.0), r1.value.ok[4]);
}

test "floatPositionsParser range negative" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try floatPositionsParser.parse(a, "10, 8, .., 2");
    try testing.expectEqual(@as(usize, 5), r1.value.ok.len);
    try testing.expectEqual(@as(f32, 10.0), r1.value.ok[0]);
    try testing.expectEqual(@as(f32, 2.0), r1.value.ok[4]);
}

// ---- line style parser ----

const AxisLineAttribute = union(enum) {
    color: common.ColorName,
    opacity: u8,
    size: u16,
};

const lineColorParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("color"), mecha.string("c") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.colorNameParserTyped,
});
const lineColorUnionParser = lineColorParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: common.ColorName) mecha.ConvertError!AxisLineAttribute {
        return AxisLineAttribute{ .color = res };
    }
}.conv);

const lineOpacityParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("opacity"), mecha.string("o") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u8, .{}),
});
const lineOpacityUnionParser = lineOpacityParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u8) mecha.ConvertError!AxisLineAttribute {
        return AxisLineAttribute{ .opacity = res };
    }
}.conv);

const lineSizeParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("size"), mecha.string("s") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u16, .{}),
});
const lineSizeUnionParser = lineSizeParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u16) mecha.ConvertError!AxisLineAttribute {
        return AxisLineAttribute{ .size = res };
    }
}.conv);

const lineAttributeUnionParser = mecha.oneOf(.{
    lineColorUnionParser,
    lineOpacityUnionParser,
    lineSizeUnionParser,
});

const manyLineAttributeUnionParser = mecha.many(lineAttributeUnionParser, .{ .collect = true, .min = 1, .separator = common.skipComma });

fn manyToLineStyle(_: std.mem.Allocator, fields: []AxisLineAttribute) mecha.ConvertError!AxisLineStyle {
    var res = AxisLineStyle{};
    for (fields) |field| switch (field) {
        .color => |v| res.color = v,
        .opacity => |v| res.opacity = v,
        .size => |v| res.size = v,
    };
    return res;
}

const lineAttributesParser = manyLineAttributeUnionParser.convert(manyToLineStyle);

test "lineAttributesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineAttributesParser.parse(a, "c:red, o:80, s:3");
    try testing.expectEqual(common.ColorName.red, r1.value.ok.color);
    try testing.expectEqual(@as(u8, 80), r1.value.ok.opacity);
    try testing.expectEqual(@as(u16, 3), r1.value.ok.size);
}

// ---- tick style parser ----

const TickFormT = enum {
    above,
    a,
    middle,
    m,
    below,
    b,
    dot,
    d,
    square,
    s,
};

fn toTickForm(_: std.mem.Allocator, res: []const u8) mecha.ConvertError!TickForm {
    if (std.meta.stringToEnum(TickFormT, res)) |validT| {
        return switch (validT) {
            .above => .above,
            .a => .above,
            .middle => .middle,
            .m => .middle,
            .below => .below,
            .b => .below,
            .dot => .dot,
            .d => .dot,
            .square => .square,
            .s => .square,
        };
    }
    return error.ConversionFailed;
}

const tickFormParser = mecha.oneOf(.{
    mecha.string("above"),
    mecha.string("a"),
    mecha.string("middle"),
    mecha.string("m"),
    mecha.string("below"),
    mecha.string("b"),
    mecha.string("dot"),
    mecha.string("d"),
    mecha.string("square"),
    mecha.string("s"),
}).convert(toTickForm);

const TickAttribute = union(enum) {
    color: common.ColorName,
    opacity: u8,
    size: u16,
    height: u16,
    form: TickForm,
};

const tickColorParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("color"), mecha.string("c") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.colorNameParserTyped,
});
const tickColorUnionParser = tickColorParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: common.ColorName) mecha.ConvertError!TickAttribute {
        return TickAttribute{ .color = res };
    }
}.conv);

const tickOpacityParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("opacity"), mecha.string("o") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u8, .{}),
});
const tickOpacityUnionParser = tickOpacityParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u8) mecha.ConvertError!TickAttribute {
        return TickAttribute{ .opacity = res };
    }
}.conv);

const tickSizeParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("size"), mecha.string("s") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u16, .{}),
});
const tickSizeUnionParser = tickSizeParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u16) mecha.ConvertError!TickAttribute {
        return TickAttribute{ .size = res };
    }
}.conv);

const tickHeightParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("height"), mecha.string("h") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u16, .{}),
});
const tickHeightUnionParser = tickHeightParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u16) mecha.ConvertError!TickAttribute {
        return TickAttribute{ .height = res };
    }
}.conv);

const tickFormParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("form"), mecha.string("f") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    tickFormParser,
});
const tickFormUnionParser = tickFormParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: TickForm) mecha.ConvertError!TickAttribute {
        return TickAttribute{ .form = res };
    }
}.conv);

const tickAttributeUnionParser = mecha.oneOf(.{
    tickColorUnionParser,
    tickOpacityUnionParser,
    tickSizeUnionParser,
    tickHeightUnionParser,
    tickFormUnionParser,
});

const manyTickAttributeUnionParser = mecha.many(tickAttributeUnionParser, .{ .collect = true, .min = 1, .separator = common.skipComma });

fn manyToPartialTickStyle(_: std.mem.Allocator, fields: []TickAttribute) mecha.ConvertError!PartialTickStyle {
    var res = PartialTickStyle{};
    for (fields) |field| switch (field) {
        .color => |v| res.color = v,
        .opacity => |v| res.opacity = v,
        .size => |v| res.size = v,
        .height => |v| res.height = v,
        .form => |v| res.form = v,
    };
    return res;
}

const tickAttributesParser = manyTickAttributeUnionParser.convert(manyToPartialTickStyle);

test "tickAttributesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try tickAttributesParser.parse(a, "c:red, o:80, s:2, h:7, f:above");
    try testing.expectEqual(common.ColorName.red, r1.value.ok.color.?);
    try testing.expectEqual(@as(u8, 80), r1.value.ok.opacity.?);
    try testing.expectEqual(@as(u16, 2), r1.value.ok.size.?);
    try testing.expectEqual(@as(u16, 7), r1.value.ok.height.?);
    try testing.expectEqual(TickForm.above, r1.value.ok.form.?);
}

// ---- value style parser ----

const ValueAttribute = union(enum) {
    color: common.ColorName,
    opacity: u8,
    size: u16,
    font: []const u8,
    spacing: u16,
    form: TickForm,
    angle: inputs.Angle,
    edge: TickEdge,
};

const valueColorParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("color"), mecha.string("c") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.colorNameParserTyped,
});
const valueColorUnionParser = valueColorParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: common.ColorName) mecha.ConvertError!ValueAttribute {
        return ValueAttribute{ .color = res };
    }
}.conv);

const valueOpacityParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("opacity"), mecha.string("o") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u8, .{}),
});
const valueOpacityUnionParser = valueOpacityParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u8) mecha.ConvertError!ValueAttribute {
        return ValueAttribute{ .opacity = res };
    }
}.conv);

const valueSizeParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("size"), mecha.string("s") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u16, .{}),
});
const valueSizeUnionParser = valueSizeParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u16) mecha.ConvertError!ValueAttribute {
        return ValueAttribute{ .size = res };
    }
}.conv);

const valueFontParserRaw = mecha.combine(.{
    mecha.string("font").discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    Text.textValueParser,
});
const valueFontUnionParser = valueFontParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: []const u8) mecha.ConvertError!ValueAttribute {
        return ValueAttribute{ .font = res };
    }
}.conv);

const valueFormParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("form"), mecha.string("f") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    tickFormParser,
});
const valueSpacingParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("spacing"), mecha.string("sp") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.int(u16, .{}),
});
const valueSpacingUnionParser = valueSpacingParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: u16) mecha.ConvertError!ValueAttribute {
        return ValueAttribute{ .spacing = res };
    }
}.conv);

const valueFormUnionParser = valueFormParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: TickForm) mecha.ConvertError!ValueAttribute {
        return ValueAttribute{ .form = res };
    }
}.conv);

const valueAngleParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("angle"), mecha.string("a") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    inputs.angleParser,
});
const valueAngleUnionParser = valueAngleParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: inputs.Angle) mecha.ConvertError!ValueAttribute {
        return ValueAttribute{ .angle = res };
    }
}.conv);

const TickEdgeT = enum {
    center,
    c,
    start,
    s,
    end,
    e,
};

fn toTickEdge(_: std.mem.Allocator, res: []const u8) mecha.ConvertError!TickEdge {
    if (std.meta.stringToEnum(TickEdgeT, res)) |validE| {
        return switch (validE) {
            .center => .center,
            .c => .center,
            .start => .start,
            .s => .start,
            .end => .end,
            .e => .end,
        };
    }
    return error.ConversionFailed;
}

const tickEdgeParser = mecha.oneOf(.{
    mecha.string("center"),
    mecha.string("c"),
    mecha.string("start"),
    mecha.string("s"),
    mecha.string("end"),
    mecha.string("e"),
}).convert(toTickEdge);

const valueEdgeParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("edge"), mecha.string("e") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    tickEdgeParser,
});
const valueEdgeUnionParser = valueEdgeParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: TickEdge) mecha.ConvertError!ValueAttribute {
        return ValueAttribute{ .edge = res };
    }
}.conv);

const valueAttributeUnionParser = mecha.oneOf(.{
    valueColorUnionParser,
    valueOpacityUnionParser,
    valueSizeUnionParser,
    valueFontUnionParser,
    valueSpacingUnionParser,
    valueFormUnionParser,
    valueAngleUnionParser,
    valueEdgeUnionParser,
});

const manyValueAttributeUnionParser = mecha.many(valueAttributeUnionParser, .{ .collect = true, .min = 1, .separator = common.skipComma });

fn manyToPartialValueStyle(_: std.mem.Allocator, fields: []ValueAttribute) mecha.ConvertError!PartialValueStyle {
    var res = PartialValueStyle{};
    for (fields) |field| switch (field) {
        .color => |v| res.color = v,
        .opacity => |v| res.opacity = v,
        .size => |v| res.size = v,
        .font => |v| res.font = v,
        .spacing => |v| res.spacing = v,
        .form => |v| res.form = v,
        .angle => |v| res.angle = v,
        .edge => |v| res.edge = v,
    };
    return res;
}

const valueAttributesParser = manyValueAttributeUnionParser.convert(manyToPartialValueStyle);

test "valueAttributesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try valueAttributesParser.parse(a, "c:red, o:80, s:12, sp:4, f:below, a:30");
    try testing.expectEqual(common.ColorName.red, r1.value.ok.color.?);
    try testing.expectEqual(@as(u8, 80), r1.value.ok.opacity.?);
    try testing.expectEqual(@as(u16, 12), r1.value.ok.size.?);
    try testing.expectEqual(@as(u16, 4), r1.value.ok.spacing.?);
    try testing.expectEqual(TickForm.below, r1.value.ok.form.?);
    try testing.expectEqual(inputs.Angle{ .degrees = 30 }, r1.value.ok.angle.?);

    const r2 = try valueAttributesParser.parse(a, "a:1r4p");
    try testing.expectEqual(inputs.Angle{ .radians = 0.25 * inputs.pi }, r2.value.ok.angle.?);

    const r3 = try valueAttributesParser.parse(a, "e:start");
    try testing.expectEqual(TickEdge.start, r3.value.ok.edge.?);
    try testing.expectEqual(TickEdge.end, (try valueAttributesParser.parse(a, "edge:end")).value.ok.edge.?);
    try testing.expectEqual(TickEdge.center, (try valueAttributesParser.parse(a, "e:c")).value.ok.edge.?);
    try testing.expectEqual(TickEdge.start, (try valueAttributesParser.parse(a, "e:s")).value.ok.edge.?);
    try testing.expectEqual(TickEdge.end, (try valueAttributesParser.parse(a, "e:e")).value.ok.edge.?);

    // Unspecified stays null so a base axis can supply it; the `center`
    // default is applied later, when the style resolves into a ValueStyle.
    try testing.expect((try valueAttributesParser.parse(a, "c:red")).value.ok.edge == null);
}

test "tickEdgeParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    try testing.expectEqual(TickEdge.center, (try tickEdgeParser.parse(a, "center")).value.ok);
    try testing.expectEqual(TickEdge.start, (try tickEdgeParser.parse(a, "start")).value.ok);
    try testing.expectEqual(TickEdge.end, (try tickEdgeParser.parse(a, "end")).value.ok);
    try testing.expectEqual(TickEdge.center, (try tickEdgeParser.parse(a, "c")).value.ok);
    try testing.expectEqual(TickEdge.start, (try tickEdgeParser.parse(a, "s")).value.ok);
    try testing.expectEqual(TickEdge.end, (try tickEdgeParser.parse(a, "e")).value.ok);

    // Only the documented names and their one-letter forms convert; anything
    // else fails. Note `e:sideways` still prefix-matches the `s` abbreviation
    // and yields `start`, which is harmless because the enclosing style parser
    // requires the whole attribute body to be consumed, so the caller is what
    // ultimately rejects an unknown name.
    try testing.expect((try tickEdgeParser.parse(a, "zzz")).value == .err);
}

// ---- import text parser for font value ----
const Text = @import("text.zig");

// ---- ticks body parser ----

const TickBodyAttribute = union(enum) {
    positions: []const f32,
    style: PartialTickStyle,
};

const tickPositionsParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("pos"), mecha.string("p") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    floatPositionsParser,
});
const tickPositionsUnionParser = tickPositionsParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: []f32) mecha.ConvertError!TickBodyAttribute {
        return TickBodyAttribute{ .positions = res };
    }
}.conv);

const tickStyleSectionParser = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("style"), mecha.string("s") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.skipOpenSquare,
    tickAttributesParser,
    common.skipCloseSquare,
});
const tickStyleUnionParser = tickStyleSectionParser.convert(struct {
    fn conv(_: std.mem.Allocator, res: PartialTickStyle) mecha.ConvertError!TickBodyAttribute {
        return TickBodyAttribute{ .style = res };
    }
}.conv);

const tickBodyAttributeParser = mecha.oneOf(.{
    tickPositionsUnionParser,
    tickStyleUnionParser,
});

const manyTickBodyAttributeParser = mecha.many(tickBodyAttributeParser, .{ .collect = true, .min = 1, .separator = common.skipComma });

fn manyToPartialTick(arena: std.mem.Allocator, fields: []TickBodyAttribute) mecha.ConvertError!PartialTick {
    var res = PartialTick{};
    for (fields) |field| switch (field) {
        .positions => |v| res.positions = v,
        .style => |v| res.style = v,
    };
    arena.free(fields);
    return res;
}

const ticksBodyParser = manyTickBodyAttributeParser.convert(manyToPartialTick);

// ---- values body parser ----

const ValueBodyAttribute = union(enum) {
    vals: []const f32,
    style: PartialValueStyle,
};

const valueValsParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("vals"), mecha.string("v") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    floatPositionsParser,
});
const valueValsUnionParser = valueValsParserRaw.convert(struct {
    fn conv(_: std.mem.Allocator, res: []f32) mecha.ConvertError!ValueBodyAttribute {
        return ValueBodyAttribute{ .vals = res };
    }
}.conv);

const valueStyleSectionParser = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("style"), mecha.string("s") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.skipOpenSquare,
    valueAttributesParser,
    common.skipCloseSquare,
});
const valueStyleUnionParser = valueStyleSectionParser.convert(struct {
    fn conv(_: std.mem.Allocator, res: PartialValueStyle) mecha.ConvertError!ValueBodyAttribute {
        return ValueBodyAttribute{ .style = res };
    }
}.conv);

const valueBodyAttributeParser = mecha.oneOf(.{
    valueValsUnionParser,
    valueStyleUnionParser,
});

const manyValueBodyAttributeParser = mecha.many(valueBodyAttributeParser, .{ .collect = true, .min = 1, .separator = common.skipComma });

fn manyToPartialValue(arena: std.mem.Allocator, fields: []ValueBodyAttribute) mecha.ConvertError!PartialValue {
    var res = PartialValue{};
    for (fields) |field| switch (field) {
        .vals => |v| res.vals = v,
        .style => |v| res.style = v,
    };
    arena.free(fields);
    return res;
}

const valuesBodyParser = manyValueBodyAttributeParser.convert(manyToPartialValue);

// ---- axis body parser ----

const AxisBodyAttribute = union(enum) {
    line: AxisLineStyle,
    ticks: PartialTick,
    values: PartialValue,
};

const lineSectionParser = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("line"), mecha.string("l") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.skipOpenSquare,
    lineAttributesParser,
    common.skipCloseSquare,
}).convert(struct {
    fn conv(_: std.mem.Allocator, res: AxisLineStyle) mecha.ConvertError!AxisBodyAttribute {
        return AxisBodyAttribute{ .line = res };
    }
}.conv);

const ticksSectionParser = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("ticks"), mecha.string("t") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.skipOpenSquare,
    ticksBodyParser,
    common.skipCloseSquare,
}).convert(struct {
    fn conv(_: std.mem.Allocator, res: PartialTick) mecha.ConvertError!AxisBodyAttribute {
        return AxisBodyAttribute{ .ticks = res };
    }
}.conv);

const valuesSectionParser = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("values"), mecha.string("v") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.skipOpenSquare,
    valuesBodyParser,
    common.skipCloseSquare,
}).convert(struct {
    fn conv(_: std.mem.Allocator, res: PartialValue) mecha.ConvertError!AxisBodyAttribute {
        return AxisBodyAttribute{ .values = res };
    }
}.conv);

const axisBodyAttributeParser = mecha.oneOf(.{
    lineSectionParser,
    ticksSectionParser,
    valuesSectionParser,
});

const manyAxisBodyAttributeParser = mecha.many(axisBodyAttributeParser, .{ .collect = true, .min = 0, .separator = common.skipComma });

fn manyToAxis(arena: std.mem.Allocator, fields: []AxisBodyAttribute) mecha.ConvertError!PartialAxis {
    var res = PartialAxis{};
    for (fields) |field| switch (field) {
        .line => |v| res.line = v,
        .ticks => |v| res.ticks = v,
        .values => |v| res.values = v,
    };
    arena.free(fields);
    return res;
}

const axisBodyParser = manyAxisBodyAttributeParser.convert(manyToAxis);

// ---- definition parser: a0: a1 {axis line:[...], ticks:[...], values:[...]} ----

const axisDefNumberParser = mecha.combine(.{
    common.skipWhitespace,
    mecha.ascii.char('a').discard(),
    mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 }).asStr().convert(mecha.toInt(u8, 10)),
});
const axisDefNumberParserP = @TypeOf(axisDefNumberParser);

const axisDefBodyParser = mecha.combine(.{
    mecha.opt(mecha.oneOf(.{ mecha.string("axis"), mecha.string("a") })).discard(),
    common.skipWhitespace,
    axisBodyParser,
});
const axisDefBodyParserP = @TypeOf(axisDefBodyParser);

const axisDefBodySectionParser = mecha.combine(.{
    common.skipOpenBrace,
    axisDefBodyParser,
    common.skipCloseBrace,
});

const axisDefParserRaw = mecha.combine(.{
    axisDefNumberParser,
    mecha.opt(mecha.ascii.char(':').discard()),
    common.skipWhitespace,
    mecha.opt(common.axisRefParser),
    common.skipWhitespace,
    mecha.opt(axisDefBodySectionParser),
});
const axisDefParserRawP = @TypeOf(axisDefParserRaw);

fn toAxisDef(arena: std.mem.Allocator, res: axisDefParserRawP.T) mecha.ConvertError!AxisDefinition {
    const number = res[0];
    const base = res[2];
    const body = res[3];
    const name = try std.fmt.allocPrint(arena, "a{d}", .{number});
    var axis = PartialAxis{};
    if (base) |b| axis.base = b;
    if (body) |b| {
        if (b.base) |bb| axis.base = bb;
        axis.line = b.line;
        axis.ticks = b.ticks;
        axis.values = b.values;
    }
    return AxisDefinition{ .number = number, .name = name, .axis = axis };
}

pub const axisDefParser = axisDefParserRaw.convert(toAxisDef);

// ---- item parser for outputs: a0 ----

const axisItemRefNameParser = mecha.combine(.{
    common.skipWhitespace,
    common.axisRefParser,
});
const axisItemRefNameParserP = @TypeOf(axisItemRefNameParser);

pub const axisItemParser = axisItemRefNameParser.convert(struct {
    fn conv(_: std.mem.Allocator, res: axisItemRefNameParserP.T) mecha.ConvertError!AxisItem {
        return AxisItem{ .name = res };
    }
}.conv);

// ---- resolve axes (inheritance) and overlays ----

threadlocal var baseErrorDetail: ?[]const u8 = null;
/// The names of the axes resolved so far, for the error message.
fn definedAxisNames(arena: std.mem.Allocator, map: std.StringHashMap(Axis)) ![]const u8 {
    if (map.count() == 0) return "none";
    var names: std.ArrayList([]const u8) = .empty;
    var it = map.keyIterator();
    while (it.next()) |name| try names.append(arena, name.*);
    return joinNames(arena, names.items);
}

fn joinNames(arena: std.mem.Allocator, names: []const []const u8) ![]const u8 {
    return std.mem.join(arena, ", ", names);
}

/// Explains the last `error.AxisBaseInvalid`, naming the base that was looked
/// for and the axes --styles actually defines. An axis is known by exactly the
/// name it was collected under, so `sleek::a0` is not `a0` unless it was
/// imported under that name.
pub fn axisBaseErrorDetail() ?[]const u8 {
    return baseErrorDetail;
}

/// Resolves a list of axis definitions into concrete styles, following the
/// style update rules: each definition starts from its base axis (or the
/// defaults when no base is given) and the fields written in its body override
/// the corresponding inherited values. A base is named the way the definition
/// it refers to is known -- `aM`, or `ns::aM` when that came from a namespace
/// import -- and must be defined before it is referenced.
pub fn resolveAxes(arena: std.mem.Allocator, defs: []const AxisDefinition) ![]ResolvedAxis {
    var map = std.StringHashMap(Axis).init(arena);
    defer map.deinit();

    var result = try arena.alloc(ResolvedAxis, defs.len);
    for (defs, 0..) |def, i| {
        var resolved: Axis = if (def.axis.base) |base| blk: {
            if (map.get(base)) |found| break :blk found;
            baseErrorDetail = try std.fmt.allocPrint(arena, "Error: base axis '{s}' of '{s}' is not defined in --styles. Defined axes: {s}.", .{ base, def.name, try definedAxisNames(arena, map) });
            return error.AxisBaseInvalid;
        } else Axis{};

        if (def.axis.line) |l| resolved.line = l;

        if (def.axis.ticks) |t| {
            var ticks = resolved.ticks orelse TickDefinition{ .positions = &.{} };
            if (t.positions) |p| ticks.positions = p;
            if (t.style) |s| {
                if (s.color) |v| ticks.style.color = v;
                if (s.opacity) |v| ticks.style.opacity = v;
                if (s.size) |v| ticks.style.size = v;
                if (s.height) |v| ticks.style.height = v;
                if (s.form) |v| ticks.style.form = v;
            }
            resolved.ticks = ticks;
        }

        if (def.axis.values) |v| {
            var values = resolved.values orelse ValueDefinition{ .vals = &.{} };
            if (v.vals) |vals| values.vals = vals;
            if (v.style) |s| {
                if (s.color) |c| values.style.color = c;
                if (s.size) |sz| values.style.size = sz;
                if (s.font) |f| values.style.font = f;
                if (s.opacity) |o| values.style.opacity = o;
                if (s.spacing) |sp| values.style.spacing = sp;
                if (s.form) |fo| values.style.form = fo;
                if (s.angle) |an| values.style.angle = an;
                if (s.edge) |ed| values.style.edge = ed;
            }
            resolved.values = values;
        }

        result[i] = ResolvedAxis{ .name = def.name, .axis = resolved };
        try map.put(def.name, resolved);
    }
    return result;
}

pub fn resolveAxisOverlay(alloc: std.mem.Allocator, item: AxisItem, axes: []const ResolvedAxis, from: inputs.Point, to: inputs.Point) !?AxisOverlay {
    for (axes) |def| {
        if (std.mem.eql(u8, def.name, item.name)) {
            var overlay = AxisOverlay{
                .from = from,
                .to = to,
                .line = def.axis.line,
                .ticks = null,
                .values = null,
            };
            if (def.axis.ticks) |t| {
                overlay.ticks = TickDefinition{
                    .positions = try alloc.dupe(f32, t.positions),
                    .style = t.style,
                };
            }
            if (def.axis.values) |v| {
                overlay.values = ValueDefinition{
                    .vals = try alloc.dupe(f32, v.vals),
                    .style = v.style,
                };
            }
            return overlay;
        }
    }
    return null;
}

// ---- serialization for --save ----

/// A definition is only useful in a namespace if it stands on its own, so an
/// axis is written out fully expanded: the inheritance chain is already folded
/// into the resolved values, and every field left at its default is left out so
/// the saved line leans on the built-in defaults instead of restating them.
/// Nothing in the result refers to another definition.
fn allocFloatList(alloc: std.mem.Allocator, values: []const f32) ![]const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    errdefer parts.deinit(alloc);
    for (values) |value| try parts.append(alloc, try std.fmt.allocPrint(alloc, "{d}", .{value}));
    return std.mem.join(alloc, ",", parts.items);
}

/// Whether an angle is the `0` a `ValueStyle` starts out with, in either unit.
fn angleIsZero(angle: inputs.Angle) bool {
    return switch (angle) {
        .degrees => |d| d == 0,
        .radians => |r| r == 0,
    };
}

/// Writes an angle in degrees, which is the unit a bare number is read as. The
/// radian spellings (`1r4p`, `2p`, `p`) only cover whole multiples of pi, so
/// degrees are the one form that can carry any angle.
fn allocAngle(alloc: std.mem.Allocator, angle: inputs.Angle) ![]const u8 {
    const degrees: f32 = switch (angle) {
        .degrees => |d| d,
        .radians => |r| r * 180.0 / inputs.pi,
    };
    return std.fmt.allocPrint(alloc, "{d}", .{degrees});
}

fn axisLineAttributes(alloc: std.mem.Allocator, line: AxisLineStyle) !std.ArrayList([]const u8) {
    const defaults: AxisLineStyle = .{};
    var attrs: std.ArrayList([]const u8) = .empty;
    errdefer attrs.deinit(alloc);
    if (line.color != defaults.color) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "c:{s}", .{@tagName(line.color)}));
    if (line.opacity != defaults.opacity) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "o:{}", .{line.opacity}));
    if (line.size != defaults.size) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "s:{}", .{line.size}));
    return attrs;
}

fn tickStyleAttributes(alloc: std.mem.Allocator, style: TickStyle) !std.ArrayList([]const u8) {
    const defaults: TickStyle = .{};
    var attrs: std.ArrayList([]const u8) = .empty;
    errdefer attrs.deinit(alloc);
    if (style.color != defaults.color) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "c:{s}", .{@tagName(style.color)}));
    if (style.opacity != defaults.opacity) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "o:{}", .{style.opacity}));
    if (style.size != defaults.size) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "s:{}", .{style.size}));
    if (style.height != defaults.height) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "h:{}", .{style.height}));
    if (style.form != defaults.form) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "f:{s}", .{@tagName(style.form)}));
    return attrs;
}

fn valueStyleAttributes(alloc: std.mem.Allocator, style: ValueStyle) !std.ArrayList([]const u8) {
    const defaults: ValueStyle = .{};
    var attrs: std.ArrayList([]const u8) = .empty;
    errdefer attrs.deinit(alloc);
    if (style.color != defaults.color) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "c:{s}", .{@tagName(style.color)}));
    if (style.opacity != defaults.opacity) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "o:{}", .{style.opacity}));
    if (style.size != defaults.size) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "s:{}", .{style.size}));
    if (!std.mem.eql(u8, style.font, defaults.font)) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "font:{s}", .{style.font}));
    if (style.spacing != defaults.spacing) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "sp:{}", .{style.spacing}));
    if (style.form != defaults.form) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "f:{s}", .{@tagName(style.form)}));
    if (!angleIsZero(style.angle)) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "a:{s}", .{try allocAngle(alloc, style.angle)}));
    if (style.edge != defaults.edge) try attrs.append(alloc, try std.fmt.allocPrint(alloc, "e:{s}", .{@tagName(style.edge)}));
    return attrs;
}

/// Serializes a resolved axis into a definition line, e.g.
/// `a1: {axis line:[c:grey, o:80, s:5], ticks:[pos:0,0.25, style:[f:below]], values:[vals:0,0.25, style:[a:-90, e:start]]}`.
/// The line parses back into an axis that resolves to `axis`, which is what
/// makes it safe to keep in a namespace that cannot see the original base.
pub fn serializeAxis(alloc: std.mem.Allocator, name: []const u8, axis: Axis) ![]const u8 {
    var sections: std.ArrayList([]const u8) = .empty;
    errdefer sections.deinit(alloc);

    const line_attrs = try axisLineAttributes(alloc, axis.line);
    if (line_attrs.items.len > 0) {
        try sections.append(alloc, try std.fmt.allocPrint(alloc, "axis line:[{s}]", .{try std.mem.join(alloc, ", ", line_attrs.items)}));
    }

    if (axis.ticks) |ticks| {
        var parts: std.ArrayList([]const u8) = .empty;
        // An axis can name a tick style without positions, so an empty list is
        // left out rather than written as a bare `pos:`.
        if (ticks.positions.len > 0) try parts.append(alloc, try std.fmt.allocPrint(alloc, "pos:{s}", .{try allocFloatList(alloc, ticks.positions)}));
        const style_attrs = try tickStyleAttributes(alloc, ticks.style);
        if (style_attrs.items.len > 0) try parts.append(alloc, try std.fmt.allocPrint(alloc, "style:[{s}]", .{try std.mem.join(alloc, ", ", style_attrs.items)}));
        if (parts.items.len > 0) try sections.append(alloc, try std.fmt.allocPrint(alloc, "ticks:[{s}]", .{try std.mem.join(alloc, ", ", parts.items)}));
    }

    if (axis.values) |values| {
        var parts: std.ArrayList([]const u8) = .empty;
        if (values.vals.len > 0) try parts.append(alloc, try std.fmt.allocPrint(alloc, "vals:{s}", .{try allocFloatList(alloc, values.vals)}));
        const style_attrs = try valueStyleAttributes(alloc, values.style);
        if (style_attrs.items.len > 0) try parts.append(alloc, try std.fmt.allocPrint(alloc, "style:[{s}]", .{try std.mem.join(alloc, ", ", style_attrs.items)}));
        if (parts.items.len > 0) try sections.append(alloc, try std.fmt.allocPrint(alloc, "values:[{s}]", .{try std.mem.join(alloc, ", ", parts.items)}));
    }

    return std.fmt.allocPrint(alloc, "{s}: {{{s}}}", .{ name, try std.mem.join(alloc, ", ", sections.items) });
}

/// Serializes, parses and resolves again, then hands back the axis that comes
/// out. Comparing it with what went in is what makes the expansion trustworthy:
/// the text has to mean the same thing on its own.
fn reparseSerialized(alloc: std.mem.Allocator, axis: Axis) !Axis {
    const text = try serializeAxis(alloc, "a7", axis);
    const def = try axisDefParser.parse(alloc, text);
    const resolved = try resolveAxes(alloc, &.{def.value.ok});
    return resolved[0].axis;
}

fn expectAxisRoundTrip(axis: Axis) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    try testing.expectEqualDeep(axis, try reparseSerialized(arena.allocator(), axis));
}

test "serializeAxis round trips a fully styled axis" {
    const axis: Axis = .{
        .line = .{ .color = .grey, .opacity = 80, .size = 5 },
        .ticks = .{
            .positions = &[_]f32{ 0.0, 0.25, 0.5, 0.75, 1.0 },
            .style = .{ .color = .lightgrey, .opacity = 80, .size = 5, .height = 12, .form = .below },
        },
        .values = .{
            .vals = &[_]f32{ 0.0, 0.25, 0.5, 0.75, 1.0 },
            .style = .{ .color = .black, .opacity = 80, .size = 25, .spacing = 4, .form = .below, .angle = .{ .degrees = -90 }, .edge = .start },
        },
    };
    try expectAxisRoundTrip(axis);
}

test "serializeAxis leaves defaults implicit" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Nothing set at all: an axis that is all defaults needs no body.
    try testing.expectEqualStrings("a7: {}", try serializeAxis(a, "a7", .{}));
    try expectAxisRoundTrip(.{});

    // Only the parts that differ from the defaults are written.
    const text = try serializeAxis(a, "a7", .{
        .ticks = .{ .positions = &[_]f32{ 0.0, 1.0 } },
    });
    try testing.expectEqualStrings("a7: {ticks:[pos:0,1]}", text);
    try expectAxisRoundTrip(.{ .ticks = .{ .positions = &[_]f32{ 0.0, 1.0 } } });

    // A field the user set to its default value is dropped too, which still
    // resolves to the same axis.
    try expectAxisRoundTrip(.{ .line = .{ .color = .black, .opacity = 100, .size = 2 } });
    try expectAxisRoundTrip(.{ .ticks = .{ .positions = &[_]f32{ 0.0, 1.0 }, .style = .{} } });
    try expectAxisRoundTrip(.{ .values = .{ .vals = &[_]f32{ 0.0, 1.0 }, .style = .{ .angle = .{ .degrees = 0 }, .edge = .center } } });

    // Zero is the default in either unit, so `0` radians is dropped just the
    // same. It comes back as the degrees form of the default, which is the
    // same angle, hence not a plain round trip of the tag.
    const radian_zero = try serializeAxis(a, "a7", .{ .values = .{ .vals = &[_]f32{0.0}, .style = .{ .angle = .{ .radians = 0 } } } });
    try testing.expectEqualStrings("a7: {values:[vals:0]}", radian_zero);
}

test "serializeAxis writes no reference to another definition" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The shape --save has to deal with: a base axis carrying most of the
    // definition, with only the tick and value styles overridden.
    const defs = [_]AxisDefinition{
        (try axisDefParser.parse(a, "a0: {axis line:[c:grey, o:80, s:5], ticks:[pos:0,0.25,0.5, style:[c:lightgrey, h:12]], values:[vals:0,0.25,0.5, style:[o:80, s:25]]}")).value.ok,
        (try axisDefParser.parse(a, "a1: a0{ticks:[style:[f:below]], values:[style:[f:below, a:-90, e:start]]}")).value.ok,
    };
    const resolved = try resolveAxes(a, &defs);

    const text = try serializeAxis(a, "a1", resolved[1].axis);

    // The base is gone, folded into the values it contributed.
    try testing.expect(std.mem.indexOf(u8, text, "a0{") == null);
    try testing.expect(std.mem.indexOf(u8, text, " a0") == null);
    try testing.expectEqualStrings("a1: {axis line:[c:grey, o:80, s:5], ticks:[pos:0,0.25,0.5, style:[c:lightgrey, h:12, f:below]], values:[vals:0,0.25,0.5, style:[o:80, s:25, f:below, a:-90, e:start]]}", text);

    // And it stands alone: no base to look up, same axis out.
    try testing.expectEqualDeep(resolved[1].axis, try reparseSerialized(a, resolved[1].axis));
}

test "serializeAxis expresses radian angles in degrees" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const half_turn: Axis = .{ .values = .{ .vals = &[_]f32{0.0}, .style = .{ .angle = .{ .radians = inputs.pi } } } };
    const text = try serializeAxis(a, "a7", half_turn);
    // A bare number reads as degrees, so `2p` has to come back out as 180.
    try testing.expectEqualStrings("a7: {values:[vals:0, style:[a:180]]}", text);

    const back = try reparseSerialized(a, half_turn);
    try testing.expectApproxEqAbs(@as(f32, 180.0), back.values.?.style.angle.degrees, 0.001);
}

test "serializeAxis keeps a tick style that has no positions" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const axis: Axis = .{ .ticks = .{ .positions = &.{}, .style = .{ .form = .below } } };
    // A bare `pos:` would not parse, so the empty list is left out.
    try testing.expectEqualStrings("a7: {ticks:[style:[f:below]]}", try serializeAxis(a, "a7", axis));
    try expectAxisRoundTrip(axis);
}

// ---- tests ----

test "axisDefParser full" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try axisDefParser.parse(a, "a0: {axis line:[c:red, o:80, s:2], ticks:[pos:2,4,..,10, style:[c:red, o:80, s:5, h:7, f:above]], values:[vals:2,4,..,10, style:[c:red, o:80, s:12, sp:4, f:below]]}");
    try testing.expectEqualStrings("a0", r1.value.ok.name);
    try testing.expectEqual(common.ColorName.red, r1.value.ok.axis.line.?.color);
    try testing.expectEqual(@as(u8, 80), r1.value.ok.axis.line.?.opacity);
    try testing.expectEqual(@as(u16, 2), r1.value.ok.axis.line.?.size);
    try testing.expect(r1.value.ok.axis.ticks != null);
    try testing.expectEqual(@as(usize, 5), r1.value.ok.axis.ticks.?.positions.?.len);
    try testing.expectEqual(common.ColorName.red, r1.value.ok.axis.ticks.?.style.?.color.?);
    try testing.expectEqual(TickForm.above, r1.value.ok.axis.ticks.?.style.?.form.?);
    try testing.expect(r1.value.ok.axis.values != null);
    try testing.expectEqual(@as(usize, 5), r1.value.ok.axis.values.?.vals.?.len);
    try testing.expectEqual(TickForm.below, r1.value.ok.axis.values.?.style.?.form.?);
}

test "axisDefParser minimal" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try axisDefParser.parse(a, "a0: {a line:[c:red]}");
    try testing.expectEqualStrings("a0", r1.value.ok.name);
    try testing.expectEqual(common.ColorName.red, r1.value.ok.axis.line.?.color);
    try testing.expect(r1.value.ok.axis.ticks == null);
    try testing.expect(r1.value.ok.axis.values == null);
}

test "axisItemParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try axisItemParser.parse(a, "a0");
    try testing.expectEqualStrings("a0", r1.value.ok.name);

    const r2 = try axisItemParser.parse(a, "a12");
    try testing.expectEqualStrings("a12", r2.value.ok.name);
}

test "resolveAxes inheritance" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try axisDefParser.parse(a, "a1: {axis line:[c:grey, o:80, s:5], ticks:[pos:0,0.5,..,3, style:[c:lightgrey]], values:[vals:0,1,2,3, style:[c:black, o:80, s:25, sp:4]]}");
    const r2 = try axisDefParser.parse(a, "a0: a1 {values:[vals:1,2,3]}");

    const defs = [_]AxisDefinition{ r1.value.ok, r2.value.ok };
    const resolved = try resolveAxes(a, &defs);

    try testing.expectEqualStrings("a0", resolved[1].name);
    try testing.expectEqual(common.ColorName.grey, resolved[1].axis.line.color);
    try testing.expectEqual(@as(u8, 80), resolved[1].axis.line.opacity);
    try testing.expectEqual(@as(u16, 5), resolved[1].axis.line.size);
    try testing.expect(resolved[1].axis.ticks != null);
    try testing.expectEqual(@as(usize, 7), resolved[1].axis.ticks.?.positions.len);
    try testing.expectEqual(common.ColorName.lightgrey, resolved[1].axis.ticks.?.style.color);
    try testing.expect(resolved[1].axis.values != null);
    try testing.expectEqualSlices(f32, &.{ 1, 2, 3 }, resolved[1].axis.values.?.vals);
    try testing.expectEqual(common.ColorName.black, resolved[1].axis.values.?.style.color);
    try testing.expectEqual(@as(u8, 80), resolved[1].axis.values.?.style.opacity);
    try testing.expectEqual(@as(u16, 25), resolved[1].axis.values.?.style.size);
}

test "resolveAxes style overrides merge field by field" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try axisDefParser.parse(a, "a1: {axis line:[c:grey, o:80, s:5], ticks:[pos:0,0.5,..,3, style:[c:lightgrey, o:80, s:5, h:12]], values:[vals:0,1,2,3, style:[c:black, o:80, s:25, sp:4, a:30]]}");
    const r2 = try axisDefParser.parse(a, "a0: a1 {values:[vals:1,2,3, style:[f:below]]}");

    const defs = [_]AxisDefinition{ r1.value.ok, r2.value.ok };
    const resolved = try resolveAxes(a, &defs);

    const vs = resolved[1].axis.values.?.style;
    try testing.expectEqual(common.ColorName.black, vs.color);
    try testing.expectEqual(@as(u8, 80), vs.opacity);
    try testing.expectEqual(@as(u16, 25), vs.size);
    try testing.expectEqual(@as(u16, 4), vs.spacing);
    try testing.expectEqual(TickForm.below, vs.form);
    try testing.expectEqual(inputs.Angle{ .degrees = 30 }, vs.angle);

    const ts = resolved[1].axis.ticks.?.style;
    try testing.expectEqual(common.ColorName.lightgrey, ts.color);
    try testing.expectEqual(@as(u8, 80), ts.opacity);
    try testing.expectEqual(@as(u16, 5), ts.size);
    try testing.expectEqual(@as(u16, 12), ts.height);
    try testing.expectEqual(TickForm.above, ts.form);
}

test "resolveAxes value edge defaults to center and is inheritable" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try axisDefParser.parse(a, "a1: {axis values:[vals:0,1, style:[a:-90]]}");
    try testing.expectEqual(TickEdge.center, (try resolveAxes(a, &[_]AxisDefinition{r1.value.ok}))[0].axis.values.?.style.edge);

    const r2 = try axisDefParser.parse(a, "a2: {axis values:[vals:0,1, style:[e:start]]}");
    try testing.expectEqual(TickEdge.start, (try resolveAxes(a, &[_]AxisDefinition{r2.value.ok}))[0].axis.values.?.style.edge);

    // A derived axis keeps the base's edge when it only overrides other fields.
    const r3 = try axisDefParser.parse(a, "a3: a2 {values:[vals:0,1, style:[f:below]]}");
    const defs = [_]AxisDefinition{ r2.value.ok, r3.value.ok };
    const resolved = try resolveAxes(a, &defs);
    try testing.expectEqual(TickEdge.start, resolved[1].axis.values.?.style.edge);
    try testing.expectEqual(TickForm.below, resolved[1].axis.values.?.style.form);

    // ...and can override it back.
    const r4 = try axisDefParser.parse(a, "a4: a2 {values:[vals:0,1, style:[e:end]]}");
    const defs2 = [_]AxisDefinition{ r2.value.ok, r4.value.ok };
    try testing.expectEqual(TickEdge.end, (try resolveAxes(a, &defs2))[1].axis.values.?.style.edge);
}

test "resolveAxes undefined base is an error" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try axisDefParser.parse(a, "a0: a9 {line:[c:red]}");

    const defs = [_]AxisDefinition{r1.value.ok};
    try testing.expectError(error.AxisBaseInvalid, resolveAxes(a, &defs));
}

test "resolveAxes follows a namespaced base name" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try axisDefParser.parse(a, "a1: {axis line:[c:grey], ticks:[pos:0,0.5,..,2]}");
    const r2 = try axisDefParser.parse(a, "a2: s::a1 {values:[vals:1,2,3]}");

    // A definition head is always bare; the name it is known by is stamped on
    // afterwards, which is what makes it `s::a1` rather than `a1` here.
    var base = r1.value.ok;
    base.name = "s::a1";
    const defs = [_]AxisDefinition{ base, r2.value.ok };
    const resolved = try resolveAxes(a, &defs);

    // The base is looked up under its collected name, `s::a1`, and everything
    // the child does not mention is inherited from it.
    try testing.expectEqualStrings("a2", resolved[1].name);
    try testing.expectEqual(common.ColorName.grey, resolved[1].axis.line.color);
    try testing.expectEqual(@as(usize, 5), resolved[1].axis.ticks.?.positions.len);
    try testing.expectEqualSlices(f32, &.{ 1, 2, 3 }, resolved[1].axis.values.?.vals);
}

test "resolveAxes names the base and the axes it could have used" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try axisDefParser.parse(a, "a1: {axis line:[c:grey]}");
    const r2 = try axisDefParser.parse(a, "a2: a1 {line:[c:red]}");

    var base = r1.value.ok;
    base.name = "s::a1";
    const defs = [_]AxisDefinition{ base, r2.value.ok };
    try testing.expectError(error.AxisBaseInvalid, resolveAxes(a, &defs));
    try testing.expect(std.mem.indexOf(u8, axisBaseErrorDetail().?, "base axis 'a1' of 'a2'") != null);
    try testing.expect(std.mem.indexOf(u8, axisBaseErrorDetail().?, "Defined axes: s::a1.") != null);
}
