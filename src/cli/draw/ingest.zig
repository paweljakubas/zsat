const mecha = @import("mecha");
const std = @import("std");
const testing = std.testing;

//final ingest pair mapping between data source to target
pub const IngestionMapping = struct {
    index: u8,
    from: usize,
    to: usize,
};

//Validated ingestion
pub const IngestionValidated = struct {
    mappings: []const IngestionMapping,
};

pub const IngestionError = error{
    WrongNumberOfInputStreams,
    ElementMissingAfterCheck,
};

//Handling the name of data source and its occurence number
pub const Source = struct {
    name: []const u8,
};

//Handling the mapping of the name of data source to the element that is its data target
pub const TargetPair = struct {
    sourceName: []const u8,
    elementName: []const u8,
};

//Raw, pre-validation result of parsing the ingestion
pub const Ingestion = struct {
    inputs: []const Source,
    mappingPairs: []const TargetPair,
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
const skipArrow =
    mecha.combine(.{ skipWhitespace, mecha.ascii.char('-').discard(), mecha.ascii.char('>').discard(), skipWhitespace });

const ingestSeparatorParser = mecha.combine(.{ skipWhitespace, mecha.ascii.char(',').discard(), skipWhitespace });
const ingestCharacterParser =
    mecha.oneOf(.{ mecha.ascii.range('a', 'z'), mecha.ascii.range('A', 'Z'), mecha.ascii.range('0', '9') });
const ingestNameParser = mecha.many(ingestCharacterParser, .{ .collect = false });
const many_sourceNameParser = mecha.many(ingestNameParser, .{ .collect = true, .separator = ingestSeparatorParser });
const sourcesParserRaw =
    mecha.combine(.{ skipOpenBracket, many_sourceNameParser, skipCloseBracket });
const sourcesParserRawP = @TypeOf(sourcesParserRaw);
fn toSourcesParser(allocator: std.mem.Allocator, names: sourcesParserRawP.T) mecha.ConvertError![]Source {
    var arr = try allocator.alloc(Source, names.len);
    var ix: u8 = 0;
    for (names) |theRes| {
        arr[ix] = Source{ .name = theRes };
        ix += 1;
    }
    allocator.free(names);
    return arr;
}
const sourcesParser = sourcesParserRaw.convert(toSourcesParser);

test "sourcesParser" {
    const a = testing.allocator;

    const r1 = try sourcesParser.parse(a, "(seg)");
    const s1 = Source{ .name = &[_]u8{ 's', 'e', 'g' } };
    const sources1 = [1]Source{s1};
    try testing.expectEqualDeep(&sources1, r1.value.ok[0..1]);
    a.free(r1.value.ok);

    const r2 = try sourcesParser.parse(a, "( seg )");
    const s2 = Source{ .name = &[_]u8{ 's', 'e', 'g' } };
    const sources2 = [1]Source{s2};
    try testing.expectEqualDeep(&sources2, r2.value.ok[0..1]);
    a.free(r2.value.ok);

    const r3 = try sourcesParser.parse(a, "( seg1, seg2 )");
    const s3a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s3b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const sources3 = [2]Source{ s3a, s3b };
    try testing.expectEqualDeep(&sources3, r3.value.ok[0..2]);
    a.free(r3.value.ok);

    const r4 = try sourcesParser.parse(a, "( seg1, seg2, txt1 )");
    const s4a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s4b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const s4c = Source{ .name = &[_]u8{ 't', 'x', 't', '1' } };
    const sources4 = [3]Source{ s4a, s4b, s4c };
    try testing.expectEqualDeep(&sources4, r4.value.ok[0..3]);
    a.free(r4.value.ok);
}

const pairTargetNameParser = mecha.manyN(ingestNameParser, 2, .{ .separator = skipArrow });

test "pairTargetNameParser" {
    const fa = testing.failing_allocator;

    const r1 = try pairTargetNameParser.parse(fa, "seg -> e0");
    const exp1 = [2][]const u8{ "seg", "e0" };
    try testing.expectEqualDeep(&exp1, &r1.value.ok);

    const r2 = try pairTargetNameParser.parse(fa, "seg1  ->  e10");
    const exp2 = [2][]const u8{ "seg1", "e10" };
    try testing.expectEqualDeep(&exp2, &r2.value.ok);
}

const many_targetNameParser = mecha.many(pairTargetNameParser, .{ .collect = true, .separator = ingestSeparatorParser });
const targetsParserRaw =
    mecha.combine(.{ skipOpenBracket, many_targetNameParser, skipCloseBracket });
const targetsParserRawP = @TypeOf(targetsParserRaw);
fn toTargetsParser(allocator: std.mem.Allocator, pairs: targetsParserRawP.T) mecha.ConvertError![]TargetPair {
    var arr = try allocator.alloc(TargetPair, pairs.len);
    var ix: u8 = 0;
    for (pairs) |thePair| {
        arr[ix] = TargetPair{ .sourceName = thePair[0], .elementName = thePair[1] };
        ix += 1;
    }
    allocator.free(pairs);
    return arr;
}
const targetsParser = targetsParserRaw.convert(toTargetsParser);

test "targetsParser" {
    const a = testing.allocator;

    const r1 = try targetsParser.parse(a, "(seg1 -> e0, seg2 -> e0)");
    const exp1a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const exp1b = TargetPair{ .sourceName = "seg2", .elementName = "e0" };
    const exp1 = [2]TargetPair{ exp1a, exp1b };
    try testing.expectEqualDeep(&exp1, r1.value.ok[0..2]);
    a.free(r1.value.ok);

    const r2 = try targetsParser.parse(a, "(seg1 -> e0   )");
    const exp2a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const exp2 = [1]TargetPair{exp2a};
    try testing.expectEqualDeep(&exp2, r2.value.ok[0..1]);
    a.free(r2.value.ok);

    const r3 = try targetsParser.parse(a, "(seg1 -> e0, seg2 -> e0,   txt1 -> e11)");
    const exp3a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const exp3b = TargetPair{ .sourceName = "seg2", .elementName = "e0" };
    const exp3c = TargetPair{ .sourceName = "txt1", .elementName = "e11" };
    const exp3 = [3]TargetPair{ exp3a, exp3b, exp3c };
    try testing.expectEqualDeep(&exp3, r3.value.ok[0..3]);
    a.free(r3.value.ok);
}

const ingestionParserRaw =
    mecha.combine(.{ skipWhitespace, sourcesParser, skipArrow, targetsParser });
const ingestionParserRawP = @TypeOf(ingestionParserRaw);
fn toIngestionParser(_: std.mem.Allocator, res: ingestionParserRawP.T) mecha.ConvertError!Ingestion {
    return Ingestion{ .inputs = res[0], .mappingPairs = res[1] };
}
const ingestionParser = ingestionParserRaw.convert(toIngestionParser);

test "ingestionParser" {
    const a = testing.allocator;

    const r1 = try ingestionParser.parse(a, "(seg) -> (seg -> e0)");
    const s1 = Source{ .name = &[_]u8{ 's', 'e', 'g' } };
    const source1 = [1]Source{s1};
    const t1 = TargetPair{ .sourceName = "seg", .elementName = "e0" };
    const target1 = [1]TargetPair{t1};
    const exp1 = Ingestion{ .inputs = &source1, .mappingPairs = &target1 };
    try testing.expectEqualDeep(&exp1, &r1.value.ok);
    a.free(r1.value.ok.inputs);
    a.free(r1.value.ok.mappingPairs);

    const r2 = try ingestionParser.parse(a, "(seg1, seg2) -> (seg1 -> e0, seg2->e0)");
    const s2a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s2b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const source2 = [2]Source{ s2a, s2b };
    const t2a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const t2b = TargetPair{ .sourceName = "seg2", .elementName = "e0" };
    const target2 = [2]TargetPair{ t2a, t2b };
    const exp2 = Ingestion{ .inputs = &source2, .mappingPairs = &target2 };
    try testing.expectEqualDeep(&exp2, &r2.value.ok);
    a.free(r2.value.ok.inputs);
    a.free(r2.value.ok.mappingPairs);

    const r3 = try ingestionParser.parse(a, " (seg1, seg2,txt1) -> (seg1 -> e0, seg2->e0,txt1->e11)");
    const s3a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s3b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const s3c = Source{ .name = &[_]u8{ 't', 'x', 't', '1' } };
    const source3 = [3]Source{ s3a, s3b, s3c };
    const t3a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const t3b = TargetPair{ .sourceName = "seg2", .elementName = "e0" };
    const t3c = TargetPair{ .sourceName = "txt1", .elementName = "e11" };
    const target3 = [3]TargetPair{ t3a, t3b, t3c };
    const exp3 = Ingestion{ .inputs = &source3, .mappingPairs = &target3 };
    try testing.expectEqualDeep(&exp3, &r3.value.ok);
    a.free(r3.value.ok.inputs);
    a.free(r3.value.ok.mappingPairs);
}

//Validate Ingestion to get IngestionValidated if
// (a) all elements in mappingPairs of Ingestion are from elements array specified
// (b) the number of sources is the same as the one specified in numberOfSources arg
// (c) all sources in mappingPairs of Ingestion exist in inputs.
// Otherwise, one of the emit error from IngestionError
pub fn validateIngestion(allocator: std.mem.Allocator, numberOfSources: u8, elements: []const []const u8, ingestion: Ingestion) !IngestionValidated {
    if (ingestion.inputs.len != numberOfSources) {
        return IngestionError.WrongNumberOfInputStreams;
    }

    var srcArr = try allocator.alloc([]const u8, ingestion.inputs.len);
    defer allocator.free(srcArr);
    var ix: u8 = 0;
    for (ingestion.inputs) |theSource| {
        srcArr[ix] = theSource.name;
        ix += 1;
    }

    var outArr = try allocator.alloc(IngestionMapping, ingestion.mappingPairs.len);
    ix = 0;
    for (ingestion.mappingPairs) |theTarget| {
        const elemToFind = theTarget.elementName;
        const srcToFind = theTarget.sourceName;
        const elemIx = try indexOfPos(elements, elemToFind);
        const srcIx = try indexOfPos(srcArr, srcToFind);
        outArr[ix] = IngestionMapping{ .index = ix, .from = srcIx, .to = elemIx };
        ix += 1;
    }

    return IngestionValidated{ .mappings = outArr };
}

fn indexOfPos(vec: []const []const u8, elem: []const u8) !usize {
    for (vec, 0..) |vecElem, ix| {
        const cmp = std.mem.eql(u8, vecElem, elem);
        if (cmp) {
            return ix;
        }
    }
    return IngestionError.ElementMissingAfterCheck;
}

test "ingestion validation" {
    const a = testing.allocator;

    const s1 = Source{ .name = &[_]u8{ 's', 'e', 'g' } };
    const source1 = [1]Source{s1};
    const t1 = TargetPair{ .sourceName = "seg", .elementName = "e0" };
    const target1 = [1]TargetPair{t1};
    const ingestion1 = Ingestion{ .inputs = &source1, .mappingPairs = &target1 };
    const im1 = IngestionMapping{ .index = 0, .from = 0, .to = 0 };
    const mappings1 = [1]IngestionMapping{im1};
    const ingestionValidated1 = IngestionValidated{ .mappings = &mappings1 };
    const elems1: [1][]const u8 = .{"e0"};
    const validation1 = try validateIngestion(a, 1, &elems1, ingestion1);
    try testing.expectEqualDeep(&validation1, &ingestionValidated1);
    a.free(validation1.mappings);

    const validation2 = validateIngestion(a, 2, &elems1, ingestion1);
    try testing.expectEqual(validation2, IngestionError.WrongNumberOfInputStreams);

    const s3a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s3b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const source3 = [2]Source{ s3a, s3b };
    const t3a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const t3b = TargetPair{ .sourceName = "seg2", .elementName = "e0" };
    const target3 = [2]TargetPair{ t3a, t3b };
    const ingestion3 = Ingestion{ .inputs = &source3, .mappingPairs = &target3 };
    const im3a = IngestionMapping{ .index = 0, .from = 0, .to = 0 };
    const im3b = IngestionMapping{ .index = 1, .from = 1, .to = 0 };
    const mappings3 = [2]IngestionMapping{ im3a, im3b };
    const ingestionValidated3 = IngestionValidated{ .mappings = &mappings3 };
    const elems3: [1][]const u8 = .{"e0"};
    const validation3 = try validateIngestion(a, 2, &elems3, ingestion3);
    try testing.expectEqualDeep(&validation3, &ingestionValidated3);
    a.free(validation3.mappings);

    const s4a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s4b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const source4 = [2]Source{ s4a, s4b };
    const t4a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const t4b = TargetPair{ .sourceName = "seg2", .elementName = "e11" };
    const target4 = [2]TargetPair{ t4a, t4b };
    const ingestion4 = Ingestion{ .inputs = &source4, .mappingPairs = &target4 };
    const im4a = IngestionMapping{ .index = 0, .from = 0, .to = 1 };
    const im4b = IngestionMapping{ .index = 1, .from = 1, .to = 0 };
    const mappings4 = [2]IngestionMapping{ im4a, im4b };
    const ingestionValidated4 = IngestionValidated{ .mappings = &mappings4 };
    const elems4: [2][]const u8 = .{ "e11", "e0" };
    const validation4 = try validateIngestion(a, 2, &elems4, ingestion4);
    try testing.expectEqualDeep(&validation4, &ingestionValidated4);
    a.free(validation4.mappings);
}
