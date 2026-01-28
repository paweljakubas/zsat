const mecha = @import("mecha");
const std = @import("std");
const testing = std.testing;

//final ingest pair mapping between data source to target
pub const IngestPair = struct {
    index: u8,
    from: u8,
    to: u8,
};

//Handling the name of data source and its occurence number
pub const Source = struct {
    index: u8,
    name: []const u8,
};

//Handling the mapping of the name of data source to the element that is its data target
pub const Target = struct {
    element: u8,
    sourceName: []const u8,
};

//Parsers
const skipWhitespace =
    mecha.ascii.char(' ').many(.{ .collect = false }).discard();
const skipOpenBracket =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('(').discard(), skipWhitespace });
const skipCloseBracket =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(')').discard(), skipWhitespace });
const skipMap =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('-').discard(), mecha.ascii.char('>').discard() });
const skipLambda =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('\\').discard() });

const ingestSeparatorParser = mecha.combine(.{ skipWhitespace, mecha.ascii.char(',').discard(), skipWhitespace });
const ingestCharacterParser =
    mecha.oneOf(.{ mecha.ascii.range('a', 'z'), mecha.ascii.range('A', 'Z'), mecha.ascii.range('0', '9') });
const ingestNameParser = mecha.many(ingestCharacterParser, .{ .collect = false });
const many_ingestNameParser = mecha.many(ingestNameParser, .{ .collect = true, .separator = ingestSeparatorParser });
const sourcesParserRaw =
    mecha.combine(.{ skipOpenBracket, many_ingestNameParser, skipCloseBracket });
const sourcesParserRawP = @TypeOf(sourcesParserRaw);
fn toSourcesParser(allocator: std.mem.Allocator, names: sourcesParserRawP.T) mecha.ConvertError![]Source {
    var arr = try allocator.alloc(Source, names.len);
    var ix: u8 = 0;
    for (names) |theRes| {
        arr[ix] = Source{ .index = ix, .name = theRes };
        ix += 1;
    }
    allocator.free(names);
    return arr;
}
const sourcesParser = sourcesParserRaw.convert(toSourcesParser);

test "sourcesParser" {
    const a = testing.allocator;

    const r1 = try sourcesParser.parse(a, "(seg)");
    const s1 = Source{ .index = 0, .name = &[_]u8{ 's', 'e', 'g' } };
    const sources1 = [1]Source{s1};
    try testing.expectEqualDeep(&sources1, r1.value.ok[0..1]);
    a.free(r1.value.ok);

    const r2 = try sourcesParser.parse(a, "( seg )");
    const s2 = Source{ .index = 0, .name = &[_]u8{ 's', 'e', 'g' } };
    const sources2 = [1]Source{s2};
    try testing.expectEqualDeep(&sources2, r2.value.ok[0..1]);
    a.free(r2.value.ok);

    const r3 = try sourcesParser.parse(a, "( seg1, seg2 )");
    const s3a = Source{ .index = 0, .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s3b = Source{ .index = 1, .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const sources3 = [2]Source{ s3a, s3b };
    try testing.expectEqualDeep(&sources3, r3.value.ok[0..2]);
    a.free(r3.value.ok);

    const r4 = try sourcesParser.parse(a, "( seg1, seg2, txt1 )");
    const s4a = Source{ .index = 0, .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s4b = Source{ .index = 1, .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const s4c = Source{ .index = 2, .name = &[_]u8{ 't', 'x', 't', '1' } };
    const sources4 = [3]Source{ s4a, s4b, s4c };
    try testing.expectEqualDeep(&sources4, r4.value.ok[0..3]);
    a.free(r4.value.ok);
}
