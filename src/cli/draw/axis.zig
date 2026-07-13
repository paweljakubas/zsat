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

pub const AxisDefinition = struct {
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
    mecha.oneOf(.{ mecha.string("lineColor"), mecha.string("lc") }).discard(),
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
    mecha.oneOf(.{ mecha.string("lineOpacity"), mecha.string("lo") }).discard(),
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
    mecha.oneOf(.{ mecha.string("lineSize"), mecha.string("ls") }).discard(),
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

    const r1 = try lineAttributesParser.parse(a, "lc:red, lo:80, ls:3");
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
    mecha.oneOf(.{ mecha.string("tickColor"), mecha.string("tc") }).discard(),
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
    mecha.oneOf(.{ mecha.string("tickOpacity"), mecha.string("to") }).discard(),
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
    mecha.oneOf(.{ mecha.string("tickSize"), mecha.string("ts") }).discard(),
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
    mecha.oneOf(.{ mecha.string("tickHeight"), mecha.string("th") }).discard(),
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
    mecha.oneOf(.{ mecha.string("tickForm"), mecha.string("tf") }).discard(),
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

fn manyToTickStyle(_: std.mem.Allocator, fields: []TickAttribute) mecha.ConvertError!TickStyle {
    var res = TickStyle{};
    for (fields) |field| switch (field) {
        .color => |v| res.color = v,
        .opacity => |v| res.opacity = v,
        .size => |v| res.size = v,
        .height => |v| res.height = v,
        .form => |v| res.form = v,
    };
    return res;
}

const tickAttributesParser = manyTickAttributeUnionParser.convert(manyToTickStyle);

test "tickAttributesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try tickAttributesParser.parse(a, "tc:red, to:80, ts:2, th:7, tf:above");
    try testing.expectEqual(common.ColorName.red, r1.value.ok.color);
    try testing.expectEqual(@as(u8, 80), r1.value.ok.opacity);
    try testing.expectEqual(@as(u16, 2), r1.value.ok.size);
    try testing.expectEqual(@as(u16, 7), r1.value.ok.height);
    try testing.expectEqual(TickForm.above, r1.value.ok.form);
}

// ---- value style parser ----

const ValueAttribute = union(enum) {
    color: common.ColorName,
    opacity: u8,
    size: u16,
    font: []const u8,
    spacing: u16,
    form: TickForm,
};

const valueColorParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("valueColor"), mecha.string("vc") }).discard(),
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
    mecha.oneOf(.{ mecha.string("valueOpacity"), mecha.string("vo") }).discard(),
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
    mecha.oneOf(.{ mecha.string("valueSize"), mecha.string("vs") }).discard(),
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
    mecha.oneOf(.{ mecha.string("valueFont"), mecha.string("vfont") }).discard(),
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
    mecha.oneOf(.{ mecha.string("valueForm"), mecha.string("vf") }).discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    tickFormParser,
});
const valueSpacingParserRaw = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("valueSpacing"), mecha.string("vsp") }).discard(),
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

const valueAttributeUnionParser = mecha.oneOf(.{
    valueColorUnionParser,
    valueOpacityUnionParser,
    valueSizeUnionParser,
    valueFontUnionParser,
    valueSpacingUnionParser,
    valueFormUnionParser,
});

const manyValueAttributeUnionParser = mecha.many(valueAttributeUnionParser, .{ .collect = true, .min = 1, .separator = common.skipComma });

fn manyToValueStyle(_: std.mem.Allocator, fields: []ValueAttribute) mecha.ConvertError!ValueStyle {
    var res = ValueStyle{};
    for (fields) |field| switch (field) {
        .color => |v| res.color = v,
        .opacity => |v| res.opacity = v,
        .size => |v| res.size = v,
        .font => |v| res.font = v,
        .spacing => |v| res.spacing = v,
        .form => |v| res.form = v,
    };
    return res;
}

const valueAttributesParser = manyValueAttributeUnionParser.convert(manyToValueStyle);

test "valueAttributesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try valueAttributesParser.parse(a, "vc:red, vo:80, vs:12, vsp:4, vf:below");
    try testing.expectEqual(common.ColorName.red, r1.value.ok.color);
    try testing.expectEqual(@as(u8, 80), r1.value.ok.opacity);
    try testing.expectEqual(@as(u16, 12), r1.value.ok.size);
    try testing.expectEqual(@as(u16, 4), r1.value.ok.spacing);
    try testing.expectEqual(TickForm.below, r1.value.ok.form);
}

// ---- import text parser for font value ----
const Text = @import("text.zig");

// ---- ticks body parser ----

const TickBodyAttribute = union(enum) {
    positions: []const f32,
    style: TickStyle,
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
    fn conv(_: std.mem.Allocator, res: TickStyle) mecha.ConvertError!TickBodyAttribute {
        return TickBodyAttribute{ .style = res };
    }
}.conv);

const tickBodyAttributeParser = mecha.oneOf(.{
    tickPositionsUnionParser,
    tickStyleUnionParser,
});

const manyTickBodyAttributeParser = mecha.many(tickBodyAttributeParser, .{ .collect = true, .min = 1, .separator = common.skipComma });

fn manyToTickDefinition(arena: std.mem.Allocator, fields: []TickBodyAttribute) mecha.ConvertError!TickDefinition {
    var res = TickDefinition{ .positions = &.{}, .style = .{} };
    for (fields) |field| switch (field) {
        .positions => |v| res.positions = v,
        .style => |v| res.style = v,
    };
    arena.free(fields);
    return res;
}

const ticksBodyParser = manyTickBodyAttributeParser.convert(manyToTickDefinition);

// ---- values body parser ----

const ValueBodyAttribute = union(enum) {
    vals: []const f32,
    style: ValueStyle,
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
    fn conv(_: std.mem.Allocator, res: ValueStyle) mecha.ConvertError!ValueBodyAttribute {
        return ValueBodyAttribute{ .style = res };
    }
}.conv);

const valueBodyAttributeParser = mecha.oneOf(.{
    valueValsUnionParser,
    valueStyleUnionParser,
});

const manyValueBodyAttributeParser = mecha.many(valueBodyAttributeParser, .{ .collect = true, .min = 1, .separator = common.skipComma });

fn manyToValueDefinition(arena: std.mem.Allocator, fields: []ValueBodyAttribute) mecha.ConvertError!ValueDefinition {
    var res = ValueDefinition{ .vals = &.{}, .style = .{} };
    for (fields) |field| switch (field) {
        .vals => |v| res.vals = v,
        .style => |v| res.style = v,
    };
    arena.free(fields);
    return res;
}

const valuesBodyParser = manyValueBodyAttributeParser.convert(manyToValueDefinition);

// ---- axis body parser ----

const AxisBodyAttribute = union(enum) {
    line: AxisLineStyle,
    ticks: TickDefinition,
    values: ValueDefinition,
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
    fn conv(_: std.mem.Allocator, res: TickDefinition) mecha.ConvertError!AxisBodyAttribute {
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
    fn conv(_: std.mem.Allocator, res: ValueDefinition) mecha.ConvertError!AxisBodyAttribute {
        return AxisBodyAttribute{ .values = res };
    }
}.conv);

const axisBodyAttributeParser = mecha.oneOf(.{
    lineSectionParser,
    ticksSectionParser,
    valuesSectionParser,
});

const manyAxisBodyAttributeParser = mecha.many(axisBodyAttributeParser, .{ .collect = true, .min = 1, .separator = common.skipComma });

fn manyToAxis(arena: std.mem.Allocator, fields: []AxisBodyAttribute) mecha.ConvertError!Axis {
    var res = Axis{};
    for (fields) |field| switch (field) {
        .line => |v| res.line = v,
        .ticks => |v| res.ticks = v,
        .values => |v| res.values = v,
    };
    arena.free(fields);
    return res;
}

const axisBodyParser = manyAxisBodyAttributeParser.convert(manyToAxis);

// ---- definition parser: a0: {axis line:[...], ticks:[...], values:[...]} ----

const axisDefNumberParser = mecha.combine(.{
    common.skipWhitespace,
    mecha.ascii.char('a').discard(),
    mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 }).asStr().convert(mecha.toInt(u8, 10)),
});
const axisDefNumberParserP = @TypeOf(axisDefNumberParser);

const axisDefBodyParser = mecha.combine(.{
    mecha.oneOf(.{ mecha.string("axis"), mecha.string("a") }).discard(),
    common.skipWhitespace,
    axisBodyParser,
});
const axisDefBodyParserP = @TypeOf(axisDefBodyParser);

const axisDefParserRaw = mecha.combine(.{
    axisDefNumberParser,
    mecha.opt(mecha.ascii.char(':').discard()),
    common.skipWhitespace,
    common.skipOpenBrace,
    axisDefBodyParser,
    common.skipCloseBrace,
});
const axisDefParserRawP = @TypeOf(axisDefParserRaw);

fn toAxisDef(arena: std.mem.Allocator, res: axisDefParserRawP.T) mecha.ConvertError!AxisDefinition {
    const number = res[0];
    const body = res[2];
    const name = try std.fmt.allocPrint(arena, "a{d}", .{number});
    return AxisDefinition{ .name = name, .axis = body };
}

pub const axisDefParser = axisDefParserRaw.convert(toAxisDef);

// ---- item parser for outputs: a0 ----

const axisItemNumberParser = mecha.combine(.{
    common.skipWhitespace,
    mecha.ascii.char('a').discard(),
    mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 2 }).asStr().convert(mecha.toInt(u8, 10)),
});
const axisItemNumberParserP = @TypeOf(axisItemNumberParser);

pub const axisItemParser = axisItemNumberParser.convert(struct {
    fn conv(arena: std.mem.Allocator, res: axisItemNumberParserP.T) mecha.ConvertError!AxisItem {
        const name = try std.fmt.allocPrint(arena, "a{d}", .{res});
        return AxisItem{ .name = name };
    }
}.conv);

// ---- resolve overlay ----

pub fn resolveAxisOverlay(alloc: std.mem.Allocator, item: AxisItem, axes: []const AxisDefinition, from: inputs.Point, to: inputs.Point) !?AxisOverlay {
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

// ---- tests ----

test "axisDefParser full" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try axisDefParser.parse(a, "a0: {axis line:[lc:red, lo:80, ls:2], ticks:[pos:2,4,..,10, style:[tc:red, to:80, ts:5, tf:above]], values:[vals:2,4,..,10, style:[vc:red, vo:80, vs:12, vf:below]]}");
    try testing.expectEqualStrings("a0", r1.value.ok.name);
    try testing.expectEqual(common.ColorName.red, r1.value.ok.axis.line.color);
    try testing.expectEqual(@as(u8, 80), r1.value.ok.axis.line.opacity);
    try testing.expectEqual(@as(u16, 2), r1.value.ok.axis.line.size);
    try testing.expect(r1.value.ok.axis.ticks != null);
    try testing.expectEqual(@as(usize, 5), r1.value.ok.axis.ticks.?.positions.len);
    try testing.expectEqual(common.ColorName.red, r1.value.ok.axis.ticks.?.style.color);
    try testing.expectEqual(TickForm.above, r1.value.ok.axis.ticks.?.style.form);
    try testing.expect(r1.value.ok.axis.values != null);
    try testing.expectEqual(@as(usize, 5), r1.value.ok.axis.values.?.vals.len);
    try testing.expectEqual(TickForm.below, r1.value.ok.axis.values.?.style.form);
}

test "axisDefParser minimal" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try axisDefParser.parse(a, "a0: {a line:[lc:red]}");
    try testing.expectEqualStrings("a0", r1.value.ok.name);
    try testing.expectEqual(common.ColorName.red, r1.value.ok.axis.line.color);
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
