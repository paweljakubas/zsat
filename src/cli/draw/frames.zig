const std = @import("std");
const testing = std.testing;

const mecha = @import("mecha");

const common = @import("common.zig");

//Final connection pair mapping between outputs to panes
pub const OutputPaneMapping = struct {
    index: u8,
    from: usize,
    to: usize,
};

//Validated output pane mapping
pub const OutputPaneValidated = struct {
    mappings: []const OutputPaneMapping,
};

pub const OutputPaneError = error{
    WrongNumberOfOutputStreams,
    PaneInMappingInvalid,
    OutputInMappingInvalid,
};

//Handling the name of output
pub const Output = struct {
    name: []const u8,
};

//Handling the mapping of the name of output to the pane that is its outputPane
pub const OutputPanePair = struct {
    outputName: []const u8,
    paneName: []const u8,
};

//Raw, pre-validation result of parsing the connection
pub const Connection = struct {
    outputs: []const Output,
    mappingPairs: []const OutputPanePair,
};

//Parsers
const paneSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char('|').discard(), mecha.ascii.char('|').discard(), common.skipWhitespace });
const outputSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
const many_outputNameParser = mecha.many(common.nameParser, .{ .collect = true, .separator = outputSeparatorParser });
const outputsParserRaw =
    mecha.combine(.{ common.skipOpenBracket, many_outputNameParser, common.skipCloseBracket });
const outputsParserRawP = @TypeOf(outputsParserRaw);
fn toOutputsParser(arena: std.mem.Allocator, names: outputsParserRawP.T) mecha.ConvertError![]Output {
    var arr = try arena.alloc(Output, names.len);
    var ix: u8 = 0;
    for (names) |theRes| {
        arr[ix] = Output{ .name = theRes };
        ix += 1;
    }
    arena.free(names);
    return arr;
}
const outputsParser = outputsParserRaw.convert(toOutputsParser);

test "outputsParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try outputsParser.parse(a, "(out)");
    const s1 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const outputs1 = [1]Output{s1};
    try testing.expectEqualDeep(&outputs1, r1.value.ok[0..1]);

    const r2 = try outputsParser.parse(a, "( out )");
    const s2 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const outputs2 = [1]Output{s2};
    try testing.expectEqualDeep(&outputs2, r2.value.ok[0..1]);

    const r3 = try outputsParser.parse(a, "( out1, out2 )");
    const s3a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const s3b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const outputs3 = [2]Output{ s3a, s3b };
    try testing.expectEqualDeep(&outputs3, r3.value.ok[0..2]);

    const r4 = try outputsParser.parse(a, "( out1, out2, txt1 )");
    const s4a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const s4b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const s4c = Output{ .name = &[_]u8{ 't', 'x', 't', '1' } };
    const outputs4 = [3]Output{ s4a, s4b, s4c };
    try testing.expectEqualDeep(&outputs4, r4.value.ok[0..3]);
}

const pairOutputPaneNameParser = mecha.manyN(common.nameParser, 2, .{ .separator = common.skipArrow });

test "pairOutputPaneNameParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try pairOutputPaneNameParser.parse(a, "out -> p0");
    const exp1 = [2][]const u8{ "out", "p0" };
    try testing.expectEqualDeep(&exp1, &r1.value.ok);

    const r2 = try pairOutputPaneNameParser.parse(a, "out1  ->  p10");
    const exp2 = [2][]const u8{ "out1", "p10" };
    try testing.expectEqualDeep(&exp2, &r2.value.ok);
}

const many_outputPaneNameParser = mecha.many(pairOutputPaneNameParser, .{ .collect = true, .separator = paneSeparatorParser });
const outputPanesParserRawP = @TypeOf(many_outputPaneNameParser);
fn toOutputPanesParser(arena: std.mem.Allocator, pairs: outputPanesParserRawP.T) mecha.ConvertError![]OutputPanePair {
    var arr = try arena.alloc(OutputPanePair, pairs.len);
    var ix: u8 = 0;
    for (pairs) |thePair| {
        arr[ix] = OutputPanePair{ .outputName = thePair[0], .paneName = thePair[1] };
        ix += 1;
    }
    arena.free(pairs);
    return arr;
}
const outputPanesParser = many_outputPaneNameParser.convert(toOutputPanesParser);

test "outputPanesParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try outputPanesParser.parse(a, "out1 -> p0 || out2 -> p0");
    const exp1a = OutputPanePair{ .outputName = "out1", .paneName = "p0" };
    const exp1b = OutputPanePair{ .outputName = "out2", .paneName = "p0" };
    const exp1 = [2]OutputPanePair{ exp1a, exp1b };
    try testing.expectEqualDeep(&exp1, r1.value.ok[0..2]);

    const r2 = try outputPanesParser.parse(a, "seg1 -> e0");
    const exp2a = OutputPanePair{ .outputName = "seg1", .paneName = "e0" };
    const exp2 = [1]OutputPanePair{exp2a};
    try testing.expectEqualDeep(&exp2, r2.value.ok[0..1]);

    const r3 = try outputPanesParser.parse(a, "seg1 -> e0 || seg2 -> e0 ||   txt1 -> e11");
    const exp3a = OutputPanePair{ .outputName = "seg1", .paneName = "e0" };
    const exp3b = OutputPanePair{ .outputName = "seg2", .paneName = "e0" };
    const exp3c = OutputPanePair{ .outputName = "txt1", .paneName = "e11" };
    const exp3 = [3]OutputPanePair{ exp3a, exp3b, exp3c };
    try testing.expectEqualDeep(&exp3, r3.value.ok[0..3]);
}

const connectionParserRaw =
    mecha.combine(.{ common.skipWhitespace, outputsParser, common.skipArrow, outputPanesParser });
const connectionParserRawP = @TypeOf(connectionParserRaw);
fn toConnectionParser(_: std.mem.Allocator, res: connectionParserRawP.T) mecha.ConvertError!Connection {
    return Connection{ .outputs = res[0], .mappingPairs = res[1] };
}
pub const connectionParser = connectionParserRaw.convert(toConnectionParser);

test "connectionParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try connectionParser.parse(a, "(seg) -> seg -> e0");
    const s1 = Output{ .name = &[_]u8{ 's', 'e', 'g' } };
    const output1 = [1]Output{s1};
    const t1 = OutputPanePair{ .outputName = "seg", .paneName = "e0" };
    const outputPane1 = [1]OutputPanePair{t1};
    const exp1 = Connection{ .outputs = &output1, .mappingPairs = &outputPane1 };
    try testing.expectEqualDeep(&exp1, &r1.value.ok);

    const r2 = try connectionParser.parse(a, "(seg1, seg2) -> seg1 -> e0 || seg2->e0");
    const s2a = Output{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s2b = Output{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const output2 = [2]Output{ s2a, s2b };
    const t2a = OutputPanePair{ .outputName = "seg1", .paneName = "e0" };
    const t2b = OutputPanePair{ .outputName = "seg2", .paneName = "e0" };
    const outputPane2 = [2]OutputPanePair{ t2a, t2b };
    const exp2 = Connection{ .outputs = &output2, .mappingPairs = &outputPane2 };
    try testing.expectEqualDeep(&exp2, &r2.value.ok);

    const r3 = try connectionParser.parse(a, " (seg1, seg2,txt1) -> seg1 -> e0 || seg2->e0 || txt1->e11");
    const s3a = Output{ .name = &[_]u8{ 's', 'e', 'g', '1' } };
    const s3b = Output{ .name = &[_]u8{ 's', 'e', 'g', '2' } };
    const s3c = Output{ .name = &[_]u8{ 't', 'x', 't', '1' } };
    const output3 = [3]Output{ s3a, s3b, s3c };
    const t3a = OutputPanePair{ .outputName = "seg1", .paneName = "e0" };
    const t3b = OutputPanePair{ .outputName = "seg2", .paneName = "e0" };
    const t3c = OutputPanePair{ .outputName = "txt1", .paneName = "e11" };
    const outputPane3 = [3]OutputPanePair{ t3a, t3b, t3c };
    const exp3 = Connection{ .outputs = &output3, .mappingPairs = &outputPane3 };
    try testing.expectEqualDeep(&exp3, &r3.value.ok);
}

// Validate 'Connection' to get 'OutputPaneValidated' if
// (a) all panes in mappingPairs of 'connection' are from 'panes' array specified (if not `OutputPaneError.PaneInMappingInvalid` triggered)
// (b) the number of outputs is the same as the one specified in numberOfOutputs arg (if not `OutputPaneError.WrongNumberOfOutputStreams` triggered)
// (c) all outputs in mappingPairs of Connection exist in outputs (if not 'OutputPaneError.OutputInMappingInvalid' triggered)
// Otherwise, one of the errors from OutputPaneError is emitted
//
// Usage and allocation information
// if (validateConnection(allocator, numberOfOutputs, panes, connection)) |validatedConnection| {
//    ...
//    allocator.free(validatedConnection.mappings);
// } else |err| {
//    ...
// }
pub fn validateConnection(arena: std.mem.Allocator, numberOfOutputs: u8, panes: []const []const u8, connection: Connection) !OutputPaneValidated {
    if (connection.outputs.len != numberOfOutputs) {
        return OutputPaneError.WrongNumberOfOutputStreams;
    }

    var outArr = try arena.alloc([]const u8, connection.outputs.len);
    var ix: u8 = 0;
    for (connection.outputs) |theOutput| {
        outArr[ix] = theOutput.name;
        ix += 1;
    }

    var arr = try arena.alloc(OutputPaneMapping, connection.mappingPairs.len);
    ix = 0;
    for (connection.mappingPairs) |theOutputPane| {
        const elemToFind = theOutputPane.paneName;
        const srcToFind = theOutputPane.outputName;
        const elemIx = try indexOfPos(ConnectionValidationCheck.paneCheck, panes, elemToFind);
        const srcIx = try indexOfPos(ConnectionValidationCheck.outputCheck, outArr, srcToFind);
        arr[ix] = OutputPaneMapping{ .index = ix, .from = srcIx, .to = elemIx };
        ix += 1;
    }

    return OutputPaneValidated{ .mappings = arr };
}

const ConnectionValidationCheck = enum {
    paneCheck,
    outputCheck,
};

fn indexOfPos(check: ConnectionValidationCheck, vec: []const []const u8, elem: []const u8) !usize {
    for (vec, 0..) |vecElem, ix| {
        const cmp = std.mem.eql(u8, vecElem, elem);
        if (cmp) {
            return ix;
        }
    }
    const err = switch (check) {
        .paneCheck => OutputPaneError.PaneInMappingInvalid,
        .outputCheck => OutputPaneError.OutputInMappingInvalid,
    };
    return err;
}

test "connection validation" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s1 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const output1 = [1]Output{s1};
    const t1 = OutputPanePair{ .outputName = "out", .paneName = "p0" };
    const outputPane1 = [1]OutputPanePair{t1};
    const connection1 = Connection{ .outputs = &output1, .mappingPairs = &outputPane1 };
    const im1 = OutputPaneMapping{ .index = 0, .from = 0, .to = 0 };
    const mappings1 = [1]OutputPaneMapping{im1};
    const connectionValidated1 = OutputPaneValidated{ .mappings = &mappings1 };
    const elems1: [1][]const u8 = .{"p0"};
    const validation1 = try validateConnection(a, 1, &elems1, connection1);
    try testing.expectEqualDeep(&validation1, &connectionValidated1);

    const validation2 = validateConnection(a, 2, &elems1, connection1);
    try testing.expectEqual(validation2, OutputPaneError.WrongNumberOfOutputStreams);

    const s3a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const s3b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const output3 = [2]Output{ s3a, s3b };
    const t3a = OutputPanePair{ .outputName = "out1", .paneName = "p0" };
    const t3b = OutputPanePair{ .outputName = "out2", .paneName = "p0" };
    const outputPane3 = [2]OutputPanePair{ t3a, t3b };
    const connection3 = Connection{ .outputs = &output3, .mappingPairs = &outputPane3 };
    const im3a = OutputPaneMapping{ .index = 0, .from = 0, .to = 0 };
    const im3b = OutputPaneMapping{ .index = 1, .from = 1, .to = 0 };
    const mappings3 = [2]OutputPaneMapping{ im3a, im3b };
    const connectionValidated3 = OutputPaneValidated{ .mappings = &mappings3 };
    const elems3: [1][]const u8 = .{"p0"};
    const validation3 = try validateConnection(a, 2, &elems3, connection3);
    try testing.expectEqualDeep(&validation3, &connectionValidated3);

    const s4a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const s4b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const output4 = [2]Output{ s4a, s4b };
    const t4a = OutputPanePair{ .outputName = "out1", .paneName = "p0" };
    const t4b = OutputPanePair{ .outputName = "out2", .paneName = "p11" };
    const outputPane4 = [2]OutputPanePair{ t4a, t4b };
    const connection4 = Connection{ .outputs = &output4, .mappingPairs = &outputPane4 };
    const im4a = OutputPaneMapping{ .index = 0, .from = 0, .to = 1 };
    const im4b = OutputPaneMapping{ .index = 1, .from = 1, .to = 0 };
    const mappings4 = [2]OutputPaneMapping{ im4a, im4b };
    const connectionValidated4 = OutputPaneValidated{ .mappings = &mappings4 };
    const elems4: [2][]const u8 = .{ "p11", "p0" };
    const validation4 = try validateConnection(a, 2, &elems4, connection4);
    try testing.expectEqualDeep(&validation4, &connectionValidated4);

    const s5a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const s5b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const output5 = [2]Output{ s5a, s5b };
    const t5a = OutputPanePair{ .outputName = "out1", .paneName = "p0" };
    const t5b = OutputPanePair{ .outputName = "out22", .paneName = "p11" };
    const outputPane5 = [2]OutputPanePair{ t5a, t5b };
    const connection5 = Connection{ .outputs = &output5, .mappingPairs = &outputPane5 };
    const elems5: [2][]const u8 = .{ "p11", "p0" };
    const validation5 = validateConnection(a, 2, &elems5, connection5);
    try testing.expectEqual(validation5, OutputPaneError.OutputInMappingInvalid);

    const s6a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const s6b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const output6 = [2]Output{ s6a, s6b };
    const t6a = OutputPanePair{ .outputName = "out1", .paneName = "p0" };
    const t6b = OutputPanePair{ .outputName = "out2", .paneName = "p11" };
    const outputPane6 = [2]OutputPanePair{ t6a, t6b };
    const connection6 = Connection{ .outputs = &output6, .mappingPairs = &outputPane6 };
    const elems6: [2][]const u8 = .{ "p1", "p0" };
    const validation6 = validateConnection(a, 2, &elems6, connection6);
    try testing.expectEqual(validation6, OutputPaneError.PaneInMappingInvalid);
}
