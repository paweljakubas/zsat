const std = @import("std");
const testing = std.testing;

const mecha = @import("mecha");

const common = @import("common.zig");

//Final connection pair mapping between data data and element
pub const DataElementMapping = struct {
    index: u8,
    from: usize,
    to: usize,
};

//Validated Mappings
pub const DataElementValidated = struct {
    mappings: []const DataElementMapping,

    pub fn print(self: *const DataElementValidated, writer: anytype) !void {
        try writer.print(" (validated:", .{});
        for (self.mappings) |mapping| {
            try writer.print(" {}->{},", .{ mapping.from, mapping.to });
        }
        try writer.print(")\n", .{});
    }
};

pub const DataElementError = error{
    WrongNumberOfDatum,
    ElementInMappingInvalid,
    DataInMappingInvalid,
};

//Handling the name of data data
pub const Data = struct {
    name: []const u8,
};

//Handling the mapping of the name of data data to the element that is its data target
pub const DataElementPair = struct {
    dataName: []const u8,
    elementName: []const u8,
};

//Raw, pre-validation result of parsing the connection
pub const Connection = struct {
    inputs: []const Data,
    mappingPairs: []const DataElementPair,
};

//Parsers
const ingestSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
const many_dataNameParser = mecha.many(common.nameParser, .{ .collect = true, .separator = ingestSeparatorParser });
const datumParserRaw =
    mecha.combine(.{ common.skipOpenBracket, many_dataNameParser, common.skipCloseBracket });
const datumParserRawP = @TypeOf(datumParserRaw);
fn toDatumParser(arena: std.mem.Allocator, names: datumParserRawP.T) mecha.ConvertError![]Data {
    var arr = try arena.alloc(Data, names.len);
    var ix: u8 = 0;
    for (names) |theRes| {
        arr[ix] = Data{ .name = theRes };
        ix += 1;
    }
    arena.free(names);
    return arr;
}
const datumParser = datumParserRaw.convert(toDatumParser);

test "datumParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try datumParser.parse(a, "(seg)");
    const s1 = Data{ .name = &[_]u8{ 's', 'e', 'g' } };
    const datum1 = [1]Data{s1};
    try testing.expectEqualDeep(&datum1, r1.value.ok[0..1]);

    const r2 = try datumParser.parse(a, "( seg )");
    const s2 = Data{ .name = &[_]u8{ 's', 'e', 'g' } };
    const datum2 = [1]Data{s2};
    try testing.expectEqualDeep(&datum2, r2.value.ok[0..1]);

    const r3 = try datumParser.parse(a, "( seg1, seg2 )");
    const s3a = Data{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s3b = Data{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const datum3 = [2]Data{ s3a, s3b };
    try testing.expectEqualDeep(&datum3, r3.value.ok[0..2]);

    const r4 = try datumParser.parse(a, "( seg1, seg2, txt1 )");
    const s4a = Data{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s4b = Data{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const s4c = Data{ .name = &[_]u8{ 't', 'x', 't', '1' } };
    const datum4 = [3]Data{ s4a, s4b, s4c };
    try testing.expectEqualDeep(&datum4, r4.value.ok[0..3]);
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
fn toTargetsParser(arena: std.mem.Allocator, pairs: targetsParserRawP.T) mecha.ConvertError![]DataElementPair {
    var arr = try arena.alloc(DataElementPair, pairs.len);
    var ix: u8 = 0;
    for (pairs) |thePair| {
        arr[ix] = DataElementPair{ .dataName = thePair[0], .elementName = thePair[1] };
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
    const exp1a = DataElementPair{ .dataName = "seg1", .elementName = "e0" };
    const exp1b = DataElementPair{ .dataName = "seg2", .elementName = "e0" };
    const exp1 = [2]DataElementPair{ exp1a, exp1b };
    try testing.expectEqualDeep(&exp1, r1.value.ok[0..2]);

    const r2 = try targetsParser.parse(a, "(seg1 -> e0   )");
    const exp2a = DataElementPair{ .dataName = "seg1", .elementName = "e0" };
    const exp2 = [1]DataElementPair{exp2a};
    try testing.expectEqualDeep(&exp2, r2.value.ok[0..1]);

    const r3 = try targetsParser.parse(a, "(seg1 -> e0, seg2 -> e0,   txt1 -> e11)");
    const exp3a = DataElementPair{ .dataName = "seg1", .elementName = "e0" };
    const exp3b = DataElementPair{ .dataName = "seg2", .elementName = "e0" };
    const exp3c = DataElementPair{ .dataName = "txt1", .elementName = "e11" };
    const exp3 = [3]DataElementPair{ exp3a, exp3b, exp3c };
    try testing.expectEqualDeep(&exp3, r3.value.ok[0..3]);
}

const connectionParserRaw =
    mecha.combine(.{ common.skipWhitespace, datumParser, common.skipArrow, targetsParser });
const connectionParserRawP = @TypeOf(connectionParserRaw);
fn toConnectionParser(_: std.mem.Allocator, res: connectionParserRawP.T) mecha.ConvertError!Connection {
    return Connection{ .inputs = res[0], .mappingPairs = res[1] };
}
pub const connectionParser = connectionParserRaw.convert(toConnectionParser);

test "connectionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try connectionParser.parse(a, "(seg) -> (seg -> e0)");
    const s1 = Data{ .name = &[_]u8{ 's', 'e', 'g' } };
    const data1 = [1]Data{s1};
    const t1 = DataElementPair{ .dataName = "seg", .elementName = "e0" };
    const target1 = [1]DataElementPair{t1};
    const exp1 = Connection{ .inputs = &data1, .mappingPairs = &target1 };
    try testing.expectEqualDeep(&exp1, &r1.value.ok);

    const r2 = try connectionParser.parse(a, "(seg1, seg2) -> (seg1 -> e0, seg2->e0)");
    const s2a = Data{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s2b = Data{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const data2 = [2]Data{ s2a, s2b };
    const t2a = DataElementPair{ .dataName = "seg1", .elementName = "e0" };
    const t2b = DataElementPair{ .dataName = "seg2", .elementName = "e0" };
    const target2 = [2]DataElementPair{ t2a, t2b };
    const exp2 = Connection{ .inputs = &data2, .mappingPairs = &target2 };
    try testing.expectEqualDeep(&exp2, &r2.value.ok);

    const r3 = try connectionParser.parse(a, " (seg1, seg2,txt1) -> (seg1 -> e0, seg2->e0,txt1->e11)");
    const s3a = Data{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s3b = Data{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const s3c = Data{ .name = &[_]u8{ 't', 'x', 't', '1' } };
    const data3 = [3]Data{ s3a, s3b, s3c };
    const t3a = DataElementPair{ .dataName = "seg1", .elementName = "e0" };
    const t3b = DataElementPair{ .dataName = "seg2", .elementName = "e0" };
    const t3c = DataElementPair{ .dataName = "txt1", .elementName = "e11" };
    const target3 = [3]DataElementPair{ t3a, t3b, t3c };
    const exp3 = Connection{ .inputs = &data3, .mappingPairs = &target3 };
    try testing.expectEqualDeep(&exp3, &r3.value.ok);
}

// Validate 'Connection' to get 'DataElementValidated' if
// (a) all elements in mappingPairs of 'connection' are from 'elements' array specified (if not `DataElementError.ElementInMappingInvalid` triggered)
// (b) the number of datum is the same as the one specified in numberOfDatum arg (if not `DataElementError.WrongNumberOfDatum` triggered)
// (c) all datum in mappingPairs of Connection exist in inputs (if not 'DataElementError.DataInMappingInvalid' triggered)
// Otherwise, one of the errors from DataElementError is emitted
//
// Usage and allocation information
// if (validateConnection(allocator, numberOfDatum, elements, connection)) |validatedConnection| {
//    ...
//    allocator.free(validatedConnection.mappings);
// } else |err| {
//    ...
// }
pub fn validateConnection(arena: std.mem.Allocator, numberOfDatum: u8, elements: []const []const u8, connection: Connection) !DataElementValidated {
    if (connection.inputs.len != numberOfDatum) {
        return DataElementError.WrongNumberOfDatum;
    }

    var srcArr = try arena.alloc([]const u8, connection.inputs.len);
    var ix: u8 = 0;
    for (connection.inputs) |theData| {
        srcArr[ix] = theData.name;
        ix += 1;
    }

    var outArr = try arena.alloc(DataElementMapping, connection.mappingPairs.len);
    ix = 0;
    for (connection.mappingPairs) |theTarget| {
        const elemToFind = theTarget.elementName;
        const srcToFind = theTarget.dataName;
        const elemIx = try indexOfPos(ConnectionValidationCheck.elementCheck, elements, elemToFind);
        const srcIx = try indexOfPos(ConnectionValidationCheck.inputCheck, srcArr, srcToFind);
        outArr[ix] = DataElementMapping{ .index = ix, .from = srcIx, .to = elemIx };
        ix += 1;
    }

    return DataElementValidated{ .mappings = outArr };
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
        .elementCheck => DataElementError.ElementInMappingInvalid,
        .inputCheck => DataElementError.DataInMappingInvalid,
    };
    return err;
}

test "connection validation" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s1 = Data{ .name = &[_]u8{ 's', 'e', 'g' } };
    const data1 = [1]Data{s1};
    const t1 = DataElementPair{ .dataName = "seg", .elementName = "e0" };
    const target1 = [1]DataElementPair{t1};
    const connection1 = Connection{ .inputs = &data1, .mappingPairs = &target1 };
    const im1 = DataElementMapping{ .index = 0, .from = 0, .to = 0 };
    const mappings1 = [1]DataElementMapping{im1};
    const connectionValidated1 = DataElementValidated{ .mappings = &mappings1 };
    const elems1: [1][]const u8 = .{"e0"};
    const validation1 = try validateConnection(a, 1, &elems1, connection1);
    try testing.expectEqualDeep(&validation1, &connectionValidated1);

    const validation2 = validateConnection(a, 2, &elems1, connection1);
    try testing.expectEqual(validation2, DataElementError.WrongNumberOfDatum);

    const s3a = Data{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s3b = Data{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const data3 = [2]Data{ s3a, s3b };
    const t3a = DataElementPair{ .dataName = "seg1", .elementName = "e0" };
    const t3b = DataElementPair{ .dataName = "seg2", .elementName = "e0" };
    const target3 = [2]DataElementPair{ t3a, t3b };
    const connection3 = Connection{ .inputs = &data3, .mappingPairs = &target3 };
    const im3a = DataElementMapping{ .index = 0, .from = 0, .to = 0 };
    const im3b = DataElementMapping{ .index = 1, .from = 1, .to = 0 };
    const mappings3 = [2]DataElementMapping{ im3a, im3b };
    const connectionValidated3 = DataElementValidated{ .mappings = &mappings3 };
    const elems3: [1][]const u8 = .{"e0"};
    const validation3 = try validateConnection(a, 2, &elems3, connection3);
    try testing.expectEqualDeep(&validation3, &connectionValidated3);

    const s4a = Data{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s4b = Data{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const data4 = [2]Data{ s4a, s4b };
    const t4a = DataElementPair{ .dataName = "seg1", .elementName = "e0" };
    const t4b = DataElementPair{ .dataName = "seg2", .elementName = "e11" };
    const target4 = [2]DataElementPair{ t4a, t4b };
    const connection4 = Connection{ .inputs = &data4, .mappingPairs = &target4 };
    const im4a = DataElementMapping{ .index = 0, .from = 0, .to = 1 };
    const im4b = DataElementMapping{ .index = 1, .from = 1, .to = 0 };
    const mappings4 = [2]DataElementMapping{ im4a, im4b };
    const connectionValidated4 = DataElementValidated{ .mappings = &mappings4 };
    const elems4: [2][]const u8 = .{ "e11", "e0" };
    const validation4 = try validateConnection(a, 2, &elems4, connection4);
    try testing.expectEqualDeep(&validation4, &connectionValidated4);

    const s5a = Data{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s5b = Data{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const data5 = [2]Data{ s5a, s5b };
    const t5a = DataElementPair{ .dataName = "seg1", .elementName = "e0" };
    const t5b = DataElementPair{ .dataName = "seg22", .elementName = "e11" };
    const target5 = [2]DataElementPair{ t5a, t5b };
    const connection5 = Connection{ .inputs = &data5, .mappingPairs = &target5 };
    const elems5: [2][]const u8 = .{ "e11", "e0" };
    const validation5 = validateConnection(a, 2, &elems5, connection5);
    try testing.expectEqual(validation5, DataElementError.DataInMappingInvalid);

    const s6a = Data{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s6b = Data{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const data6 = [2]Data{ s6a, s6b };
    const t6a = DataElementPair{ .dataName = "seg1", .elementName = "e0" };
    const t6b = DataElementPair{ .dataName = "seg2", .elementName = "e11" };
    const target6 = [2]DataElementPair{ t6a, t6b };
    const connection6 = Connection{ .inputs = &data6, .mappingPairs = &target6 };
    const elems6: [2][]const u8 = .{ "e1", "e0" };
    const validation6 = validateConnection(a, 2, &elems6, connection6);
    try testing.expectEqual(validation6, DataElementError.ElementInMappingInvalid);
}
