const std = @import("std");
const testing = std.testing;

const mecha = @import("mecha");

const common = @import("common.zig");

//Final connection pair mapping between data source to target
pub const ConnectionMapping = struct {
    index: u8,
    from: usize,
    to: usize,
};

//Validated connection
pub const ConnectionValidated = struct {
    mappings: []const ConnectionMapping,
};

pub const ConnectionError = error{
    WrongNumberOfInputStreams,
    ElementInMappingInvalid,
    InputInMappingInvalid,
};

//Handling the name of data source
pub const Source = struct {
    name: []const u8,
};

//Handling the mapping of the name of data source to the element that is its data target
pub const TargetPair = struct {
    sourceName: []const u8,
    elementName: []const u8,
};

//Raw, pre-validation result of parsing the connection
pub const Connection = struct {
    inputs: []const Source,
    mappingPairs: []const TargetPair,
};

//Parsers
const ingestSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
const many_sourceNameParser = mecha.many(common.nameParser, .{ .collect = true, .separator = ingestSeparatorParser });
const sourcesParserRaw =
    mecha.combine(.{ common.skipOpenBracket, many_sourceNameParser, common.skipCloseBracket });
const sourcesParserRawP = @TypeOf(sourcesParserRaw);
fn toSourcesParser(arena: std.mem.Allocator, names: sourcesParserRawP.T) mecha.ConvertError![]Source {
    var arr = try arena.alloc(Source, names.len);
    var ix: u8 = 0;
    for (names) |theRes| {
        arr[ix] = Source{ .name = theRes };
        ix += 1;
    }
    arena.free(names);
    return arr;
}
const sourcesParser = sourcesParserRaw.convert(toSourcesParser);

test "sourcesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try sourcesParser.parse(a, "(seg)");
    const s1 = Source{ .name = &[_]u8{ 's', 'e', 'g' } };
    const sources1 = [1]Source{s1};
    try testing.expectEqualDeep(&sources1, r1.value.ok[0..1]);

    const r2 = try sourcesParser.parse(a, "( seg )");
    const s2 = Source{ .name = &[_]u8{ 's', 'e', 'g' } };
    const sources2 = [1]Source{s2};
    try testing.expectEqualDeep(&sources2, r2.value.ok[0..1]);

    const r3 = try sourcesParser.parse(a, "( seg1, seg2 )");
    const s3a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s3b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const sources3 = [2]Source{ s3a, s3b };
    try testing.expectEqualDeep(&sources3, r3.value.ok[0..2]);

    const r4 = try sourcesParser.parse(a, "( seg1, seg2, txt1 )");
    const s4a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s4b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const s4c = Source{ .name = &[_]u8{ 't', 'x', 't', '1' } };
    const sources4 = [3]Source{ s4a, s4b, s4c };
    try testing.expectEqualDeep(&sources4, r4.value.ok[0..3]);
}

const pairTargetNameParser = mecha.manyN(common.nameParser, 2, .{ .separator = common.skipArrow });

test "pairTargetNameParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try pairTargetNameParser.parse(a, "seg -> e0");
    const exp1 = [2][]const u8{ "seg", "e0" };
    try testing.expectEqualDeep(&exp1, &r1.value.ok);

    const r2 = try pairTargetNameParser.parse(a, "seg1  ->  e10");
    const exp2 = [2][]const u8{ "seg1", "e10" };
    try testing.expectEqualDeep(&exp2, &r2.value.ok);
}

const many_targetNameParser = mecha.many(pairTargetNameParser, .{ .collect = true, .separator = ingestSeparatorParser });
const targetsParserRaw =
    mecha.combine(.{ common.skipOpenBracket, many_targetNameParser, common.skipCloseBracket });
const targetsParserRawP = @TypeOf(targetsParserRaw);
fn toTargetsParser(arena: std.mem.Allocator, pairs: targetsParserRawP.T) mecha.ConvertError![]TargetPair {
    var arr = try arena.alloc(TargetPair, pairs.len);
    var ix: u8 = 0;
    for (pairs) |thePair| {
        arr[ix] = TargetPair{ .sourceName = thePair[0], .elementName = thePair[1] };
        ix += 1;
    }
    arena.free(pairs);
    return arr;
}
const targetsParser = targetsParserRaw.convert(toTargetsParser);

test "targetsParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try targetsParser.parse(a, "(seg1 -> e0, seg2 -> e0)");
    const exp1a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const exp1b = TargetPair{ .sourceName = "seg2", .elementName = "e0" };
    const exp1 = [2]TargetPair{ exp1a, exp1b };
    try testing.expectEqualDeep(&exp1, r1.value.ok[0..2]);

    const r2 = try targetsParser.parse(a, "(seg1 -> e0   )");
    const exp2a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const exp2 = [1]TargetPair{exp2a};
    try testing.expectEqualDeep(&exp2, r2.value.ok[0..1]);

    const r3 = try targetsParser.parse(a, "(seg1 -> e0, seg2 -> e0,   txt1 -> e11)");
    const exp3a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const exp3b = TargetPair{ .sourceName = "seg2", .elementName = "e0" };
    const exp3c = TargetPair{ .sourceName = "txt1", .elementName = "e11" };
    const exp3 = [3]TargetPair{ exp3a, exp3b, exp3c };
    try testing.expectEqualDeep(&exp3, r3.value.ok[0..3]);
}

const connectionParserRaw =
    mecha.combine(.{ common.skipWhitespace, sourcesParser, common.skipArrow, targetsParser });
const connectionParserRawP = @TypeOf(connectionParserRaw);
fn toConnectionParser(_: std.mem.Allocator, res: connectionParserRawP.T) mecha.ConvertError!Connection {
    return Connection{ .inputs = res[0], .mappingPairs = res[1] };
}
const connectionParser = connectionParserRaw.convert(toConnectionParser);

test "connectionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try connectionParser.parse(a, "(seg) -> (seg -> e0)");
    const s1 = Source{ .name = &[_]u8{ 's', 'e', 'g' } };
    const source1 = [1]Source{s1};
    const t1 = TargetPair{ .sourceName = "seg", .elementName = "e0" };
    const target1 = [1]TargetPair{t1};
    const exp1 = Connection{ .inputs = &source1, .mappingPairs = &target1 };
    try testing.expectEqualDeep(&exp1, &r1.value.ok);

    const r2 = try connectionParser.parse(a, "(seg1, seg2) -> (seg1 -> e0, seg2->e0)");
    const s2a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s2b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const source2 = [2]Source{ s2a, s2b };
    const t2a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const t2b = TargetPair{ .sourceName = "seg2", .elementName = "e0" };
    const target2 = [2]TargetPair{ t2a, t2b };
    const exp2 = Connection{ .inputs = &source2, .mappingPairs = &target2 };
    try testing.expectEqualDeep(&exp2, &r2.value.ok);

    const r3 = try connectionParser.parse(a, " (seg1, seg2,txt1) -> (seg1 -> e0, seg2->e0,txt1->e11)");
    const s3a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s3b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const s3c = Source{ .name = &[_]u8{ 't', 'x', 't', '1' } };
    const source3 = [3]Source{ s3a, s3b, s3c };
    const t3a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const t3b = TargetPair{ .sourceName = "seg2", .elementName = "e0" };
    const t3c = TargetPair{ .sourceName = "txt1", .elementName = "e11" };
    const target3 = [3]TargetPair{ t3a, t3b, t3c };
    const exp3 = Connection{ .inputs = &source3, .mappingPairs = &target3 };
    try testing.expectEqualDeep(&exp3, &r3.value.ok);
}

// Validate 'Connection' to get 'ConnectionValidated' if
// (a) all elements in mappingPairs of 'connection' are from 'elements' array specified (if not `ConnectionError.ElementInMappingInvalid` triggered)
// (b) the number of sources is the same as the one specified in numberOfSources arg (if not `ConnectionError.WrongNumberOfInputStreams` triggered)
// (c) all sources in mappingPairs of Connection exist in inputs (if not 'ConnectionError.InputInMappingInvalid' triggered)
// Otherwise, one of the errors from ConnectionError is emitted
//
// Usage and allocation information
// if (validateConnection(allocator, numberOfSources, elements, connection)) |validatedConnection| {
//    ...
//    allocator.free(validatedConnection.mappings);
// } else |err| {
//    ...
// }
pub fn validateConnection(arena: std.mem.Allocator, numberOfSources: u8, elements: []const []const u8, connection: Connection) !ConnectionValidated {
    if (connection.inputs.len != numberOfSources) {
        return ConnectionError.WrongNumberOfInputStreams;
    }

    var srcArr = try arena.alloc([]const u8, connection.inputs.len);
    var ix: u8 = 0;
    for (connection.inputs) |theSource| {
        srcArr[ix] = theSource.name;
        ix += 1;
    }

    var outArr = try arena.alloc(ConnectionMapping, connection.mappingPairs.len);
    ix = 0;
    for (connection.mappingPairs) |theTarget| {
        const elemToFind = theTarget.elementName;
        const srcToFind = theTarget.sourceName;
        const elemIx = try indexOfPos(ConnectionValidationCheck.elementCheck, elements, elemToFind);
        const srcIx = try indexOfPos(ConnectionValidationCheck.inputCheck, srcArr, srcToFind);
        outArr[ix] = ConnectionMapping{ .index = ix, .from = srcIx, .to = elemIx };
        ix += 1;
    }

    return ConnectionValidated{ .mappings = outArr };
}

const ConnectionValidationCheck = enum {
    elementCheck,
    inputCheck,
};

fn indexOfPos(check: ConnectionValidationCheck, vec: []const []const u8, elem: []const u8) !usize {
    for (vec, 0..) |vecElem, ix| {
        const cmp = std.mem.eql(u8, vecElem, elem);
        if (cmp) {
            return ix;
        }
    }
    const err = switch (check) {
        .elementCheck => ConnectionError.ElementInMappingInvalid,
        .inputCheck => ConnectionError.InputInMappingInvalid,
    };
    return err;
}

test "connection validation" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s1 = Source{ .name = &[_]u8{ 's', 'e', 'g' } };
    const source1 = [1]Source{s1};
    const t1 = TargetPair{ .sourceName = "seg", .elementName = "e0" };
    const target1 = [1]TargetPair{t1};
    const connection1 = Connection{ .inputs = &source1, .mappingPairs = &target1 };
    const im1 = ConnectionMapping{ .index = 0, .from = 0, .to = 0 };
    const mappings1 = [1]ConnectionMapping{im1};
    const connectionValidated1 = ConnectionValidated{ .mappings = &mappings1 };
    const elems1: [1][]const u8 = .{"e0"};
    const validation1 = try validateConnection(a, 1, &elems1, connection1);
    try testing.expectEqualDeep(&validation1, &connectionValidated1);

    const validation2 = validateConnection(a, 2, &elems1, connection1);
    try testing.expectEqual(validation2, ConnectionError.WrongNumberOfInputStreams);

    const s3a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s3b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const source3 = [2]Source{ s3a, s3b };
    const t3a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const t3b = TargetPair{ .sourceName = "seg2", .elementName = "e0" };
    const target3 = [2]TargetPair{ t3a, t3b };
    const connection3 = Connection{ .inputs = &source3, .mappingPairs = &target3 };
    const im3a = ConnectionMapping{ .index = 0, .from = 0, .to = 0 };
    const im3b = ConnectionMapping{ .index = 1, .from = 1, .to = 0 };
    const mappings3 = [2]ConnectionMapping{ im3a, im3b };
    const connectionValidated3 = ConnectionValidated{ .mappings = &mappings3 };
    const elems3: [1][]const u8 = .{"e0"};
    const validation3 = try validateConnection(a, 2, &elems3, connection3);
    try testing.expectEqualDeep(&validation3, &connectionValidated3);

    const s4a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s4b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const source4 = [2]Source{ s4a, s4b };
    const t4a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const t4b = TargetPair{ .sourceName = "seg2", .elementName = "e11" };
    const target4 = [2]TargetPair{ t4a, t4b };
    const connection4 = Connection{ .inputs = &source4, .mappingPairs = &target4 };
    const im4a = ConnectionMapping{ .index = 0, .from = 0, .to = 1 };
    const im4b = ConnectionMapping{ .index = 1, .from = 1, .to = 0 };
    const mappings4 = [2]ConnectionMapping{ im4a, im4b };
    const connectionValidated4 = ConnectionValidated{ .mappings = &mappings4 };
    const elems4: [2][]const u8 = .{ "e11", "e0" };
    const validation4 = try validateConnection(a, 2, &elems4, connection4);
    try testing.expectEqualDeep(&validation4, &connectionValidated4);

    const s5a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s5b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const source5 = [2]Source{ s5a, s5b };
    const t5a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const t5b = TargetPair{ .sourceName = "seg22", .elementName = "e11" };
    const target5 = [2]TargetPair{ t5a, t5b };
    const connection5 = Connection{ .inputs = &source5, .mappingPairs = &target5 };
    const elems5: [2][]const u8 = .{ "e11", "e0" };
    const validation5 = validateConnection(a, 2, &elems5, connection5);
    try testing.expectEqual(validation5, ConnectionError.InputInMappingInvalid);

    const s6a = Source{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s6b = Source{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const source6 = [2]Source{ s6a, s6b };
    const t6a = TargetPair{ .sourceName = "seg1", .elementName = "e0" };
    const t6b = TargetPair{ .sourceName = "seg2", .elementName = "e11" };
    const target6 = [2]TargetPair{ t6a, t6b };
    const connection6 = Connection{ .inputs = &source6, .mappingPairs = &target6 };
    const elems6: [2][]const u8 = .{ "e1", "e0" };
    const validation6 = validateConnection(a, 2, &elems6, connection6);
    try testing.expectEqual(validation6, ConnectionError.ElementInMappingInvalid);
}
