const std = @import("std");
const testing = std.testing;

const mecha = @import("mecha");
const common = @import("common.zig");

const inputs = @import("inputs.zig");
const border = @import("border.zig");

pub const Pane = struct {
    paneNumber: u8,
    paneValue: PaneValue,
};

pub const PaneValue = struct {
    paneSize: ?PaneSize = .defaultPaneSize(),
    border: ?border.Border = null,
    view: PaneView = .defaultPaneView(),
};

pub const PaneSize = struct {
    width: u16,
    height: u16,

    pub fn defaultPaneSize() PaneSize {
        return PaneSize{ .width = 800, .height = 600 };
    }
};

pub const PaneView = struct {
    from: inputs.Point,
    to: inputs.Point,

    pub fn defaultPaneView() PaneView {
        return PaneView{ .from = .{ .x = -100.0, .y = -100.0 }, .to = .{ .x = 100.0, .y = 100.0 } };
    }
};

//Parsers
const paneNumberParser =
    mecha.combine(.{ common.skipWhitespace, mecha.ascii.char('p').discard(), mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1, .max = 1 }).asStr().convert(mecha.toInt(u8, 10)) });

test "paneNumber" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try paneNumberParser.parse(a, "p2");
    try testing.expectEqual(2, r1.value.ok);

    const r2 = try paneNumberParser.parse(a, " p0");
    try testing.expectEqual(0, r2.value.ok);

    const r3 = try paneNumberParser.parse(a, " p9");
    try testing.expectEqual(9, r3.value.ok);

    const r4 = try paneNumberParser.parse(a, "q0");
    try testing.expectEqual(0, r4.index);
}

const paneSizeParserRaw = mecha.combine(.{
    common.skipWhitespace,
    mecha.string("size").discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    common.integer.asStr().convert(mecha.toInt(u16, 10)),
    mecha.ascii.char('x').discard(),
    common.integer.asStr().convert(mecha.toInt(u16, 10)),
});
const paneSizeParserRawP = @TypeOf(paneSizeParserRaw);
fn toPaneSize(_: std.mem.Allocator, res: paneSizeParserRawP.T) mecha.ConvertError!PaneSize {
    return PaneSize{ .width = res[0], .height = res[1] };
}
const paneSizeParser = paneSizeParserRaw.convert(toPaneSize);
test "paneSize" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try paneSizeParser.parse(a, "size: 100x100");
    const p1 = PaneSize{ .width = 100, .height = 100 };
    try testing.expectEqual(p1, r1.value.ok);

    const r2 = try paneSizeParser.parse(a, "size:  100x120");
    const p2 = PaneSize{ .width = 100, .height = 120 };
    try testing.expectEqual(p2, r2.value.ok);

    const r3 = try paneSizeParser.parse(a, "size:1024x550");
    const p3 = PaneSize{ .width = 1024, .height = 550 };
    try testing.expectEqual(p3, r3.value.ok);
}

const paneViewParserRaw = mecha.combine(.{
    common.skipWhitespace,
    mecha.string("view").discard(),
    common.skipWhitespace,
    mecha.ascii.char(':').discard(),
    common.skipWhitespace,
    mecha.ascii.char('{').discard(),
    inputs.pointParser,
    common.skipComma,
    inputs.pointParser,
    common.skipWhitespace,
    mecha.ascii.char('}').discard(),
});
const paneViewParserRawP = @TypeOf(paneViewParserRaw);
fn toPaneView(_: std.mem.Allocator, res: paneViewParserRawP.T) mecha.ConvertError!PaneView {
    return PaneView{ .from = res[0], .to = res[1] };
}
const paneViewParser = paneViewParserRaw.convert(toPaneView);
test "paneView" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try paneViewParser.parse(a, "view: {(2,1.1), (10.0, 1.2)}}");
    const p1a = inputs.Point{ .x = 2.0, .y = 1.1 };
    const p1b = inputs.Point{ .x = 10.0, .y = 1.2 };
    const v1 = PaneView{ .from = p1a, .to = p1b };
    try testing.expectEqual(v1, r1.value.ok);

    const r2 = try paneViewParser.parse(a, "view:{(0,0), (10, 10)}}");
    const p2a = inputs.Point{ .x = 0.0, .y = 0.0 };
    const p2b = inputs.Point{ .x = 10.0, .y = 10.0 };
    const v2 = PaneView{ .from = p2a, .to = p2b };
    try testing.expectEqual(v2, r2.value.ok);
}

const PaneFieldUnion = union(enum) {
    paneSize: PaneSize,
    border: border.Border,
    paneView: PaneView,
};

const paneSizeFieldParser = paneSizeParser.convert(struct {
    fn conv(_: std.mem.Allocator, res: PaneSize) mecha.ConvertError!PaneFieldUnion {
        return PaneFieldUnion{ .paneSize = res };
    }
}.conv);

const borderFieldParser = border.borderBracketedParser.convert(struct {
    fn conv(_: std.mem.Allocator, res: border.Border) mecha.ConvertError!PaneFieldUnion {
        return PaneFieldUnion{ .border = res };
    }
}.conv);

const paneViewFieldParser = paneViewParser.convert(struct {
    fn conv(_: std.mem.Allocator, res: PaneView) mecha.ConvertError!PaneFieldUnion {
        return PaneFieldUnion{ .paneView = res };
    }
}.conv);

const paneFieldParser = mecha.oneOf(.{
    paneSizeFieldParser,
    borderFieldParser,
    paneViewFieldParser,
});

const manyPaneFieldsParser = mecha.many(paneFieldParser, .{ .separator = common.skipComma });
fn toPaneValue(_: std.mem.Allocator, fields: []PaneFieldUnion) mecha.ConvertError!PaneValue {
    var res = PaneValue{};
    for (fields) |field| switch (field) {
        .paneSize => |v| res.paneSize = v,
        .border => |v| res.border = v,
        .paneView => |v| res.view = v,
    };
    return res;
}
const paneValueParser = manyPaneFieldsParser.convert(toPaneValue);

const paneParser =
    mecha.combine(.{ paneNumberParser, common.skipOpenBraceColonOrJustBrace, paneValueParser, common.skipCloseBrace }).map(mecha.toStruct(Pane));

test "paneParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r0 = try paneParser.parse(a, "p0:{size: 100x100, view:{(2,1.1), (10.0, 1.2)}}");
    const s0 = PaneSize{ .width = 100, .height = 100 };
    const p0a = inputs.Point{ .x = 2.0, .y = 1.1 };
    const p0b = inputs.Point{ .x = 10.0, .y = 1.2 };
    const p0 = PaneView{ .from = p0a, .to = p0b };
    const v0 = PaneValue{ .paneSize = s0, .view = p0 };
    const pane0 = Pane{ .paneNumber = 0, .paneValue = v0 };
    try testing.expectEqual(pane0, r0.value.ok);

    const r1 = try paneParser.parse(a, "p7:{view:{(0,0), (10, 10)}}");
    const p1a = inputs.Point{ .x = 0.0, .y = 0.0 };
    const p1b = inputs.Point{ .x = 10.0, .y = 10.0 };
    const p1 = PaneView{ .from = p1a, .to = p1b };
    const v1 = PaneValue{ .paneSize = PaneSize.defaultPaneSize(), .view = p1 };
    const pane1 = Pane{ .paneNumber = 7, .paneValue = v1 };
    try testing.expectEqual(pane1, r1.value.ok);
}

test "paneParser with border" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r0 = try paneParser.parse(a, "p0:{size: 100x100, border [bw:30, bc:red], view:{(2,1.1), (10.0, 1.2)}}");
    const s0 = PaneSize{ .width = 100, .height = 100 };
    const b0 = border.Border{ .width = 30, .opacity = 100, .color = .red };
    const p0a = inputs.Point{ .x = 2.0, .y = 1.1 };
    const p0b = inputs.Point{ .x = 10.0, .y = 1.2 };
    const p0 = PaneView{ .from = p0a, .to = p0b };
    const v0 = PaneValue{ .paneSize = s0, .border = b0, .view = p0 };
    const pane0 = Pane{ .paneNumber = 0, .paneValue = v0 };
    try testing.expectEqual(pane0, r0.value.ok);

    const r1 = try paneParser.parse(a, "p1:{border [bo:50, bc:blue]}");
    const b1 = border.Border{ .width = 0, .opacity = 50, .color = .blue };
    const v1 = PaneValue{ .paneSize = PaneSize.defaultPaneSize(), .border = b1, .view = PaneView.defaultPaneView() };
    const pane1 = Pane{ .paneNumber = 1, .paneValue = v1 };
    try testing.expectEqual(pane1, r1.value.ok);

    const r2 = try paneParser.parse(a, "p2:{size: 200x200, border [bw:10]}");
    const s2 = PaneSize{ .width = 200, .height = 200 };
    const b2 = border.Border{ .width = 10, .opacity = 100, .color = .black };
    const v2 = PaneValue{ .paneSize = s2, .border = b2, .view = PaneView.defaultPaneView() };
    const pane2 = Pane{ .paneNumber = 2, .paneValue = v2 };
    try testing.expectEqual(pane2, r2.value.ok);
}

const paneSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
pub const panesParser = mecha.many(paneParser, .{ .collect = true, .separator = paneSeparatorParser });

test "panesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r0 = try panesParser.parse(a, "p0:{size: 100x100, view:{(2,1.1), (10.0, 1.2)}}, p7:{view:{(0,0), (10, 10)}}");
    const s0 = PaneSize{ .width = 100, .height = 100 };
    const p0a = inputs.Point{ .x = 2.0, .y = 1.1 };
    const p0b = inputs.Point{ .x = 10.0, .y = 1.2 };
    const p0 = PaneView{ .from = p0a, .to = p0b };
    const v0 = PaneValue{ .paneSize = s0, .view = p0 };
    const pane0 = Pane{ .paneNumber = 0, .paneValue = v0 };

    const p1a = inputs.Point{ .x = 0.0, .y = 0.0 };
    const p1b = inputs.Point{ .x = 10.0, .y = 10.0 };
    const p1 = PaneView{ .from = p1a, .to = p1b };
    const v1 = PaneValue{ .paneSize = PaneSize.defaultPaneSize(), .view = p1 };
    const pane1 = Pane{ .paneNumber = 7, .paneValue = v1 };

    const exp_panes = [2]Pane{ pane0, pane1 };
    try testing.expectEqualDeep(&exp_panes, r0.value.ok[0..2]);
}
