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
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('(').discard() });
const skipCloseBracket =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char(')').discard(), skipWhitespace });
const skipMap =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('-').discard(), mecha.ascii.char('>').discard() });
const skipLambda =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('\\').discard() });

const sourcesSeparatorParser = mecha.combine(.{ skipWhitespace, mecha.ascii.char(',').discard(), skipWhitespace });
const sourceCharacterParser =
    mecha.oneOf(.{ mecha.ascii.range('a', 'z'), mecha.ascii.range('A', 'Z'), mecha.ascii.range('0', '9') });
const sourceNameParser = mecha.many(sourceCharacterParser, .{ .collect = false });
const many_sourceNameParser = mecha.many(sourceNameParser, .{ .collect = true, .separator = sourcesSeparatorParser });
const sourcesParserRaw =
    mecha.combine(.{ skipOpenBracket, many_sourceNameParser, skipCloseBracket });
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
}
