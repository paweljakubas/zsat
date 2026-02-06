const mecha = @import("mecha");
const common = @import("common.zig");
const std = @import("std");
const testing = std.testing;

////Types

//Handling the name of output
pub const Output = struct {
    name: []const u8,
};

//Rotate to phi using a given coordination system
//For xy coordinate system it is going to be counter-clock wise to x axis by default
pub const RotateTo = struct {
    phi: u16, //in degrees
    clockwise: bool = false,
};

//Rotate by phi
//By default counter-clock wise, vector is
pub const RotateBy = struct {
    phi: u16,
};

//Parsers
const outputSeparatorParser = mecha.combine(.{ common.skipWhitespace, mecha.ascii.char(',').discard(), common.skipWhitespace });
const outputCharacterParser =
    mecha.oneOf(.{ mecha.ascii.range('a', 'z'), mecha.ascii.range('A', 'Z'), mecha.ascii.range('0', '9') });
const outputNameParser = mecha.many(outputCharacterParser, .{ .collect = false });
const many_outputNameParser = mecha.many(outputNameParser, .{ .collect = true, .separator = outputSeparatorParser });
const outputsParserRaw =
    mecha.combine(.{ common.skipOpenBracket, many_outputNameParser, common.skipCloseBracket });
const outputsParserRawP = @TypeOf(outputsParserRaw);
fn toOutputsParser(allocator: std.mem.Allocator, names: outputsParserRawP.T) mecha.ConvertError![]Output {
    var arr = try allocator.alloc(Output, names.len);
    var ix: u8 = 0;
    for (names) |theRes| {
        arr[ix] = Output{ .name = theRes };
        ix += 1;
    }
    allocator.free(names);
    return arr;
}
const outputsParser = outputsParserRaw.convert(toOutputsParser);

test "outputsParser" {
    const a = testing.allocator;

    const r1 = try outputsParser.parse(a, "(out)");
    const o1 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const output1 = [1]Output{o1};
    try testing.expectEqualDeep(&output1, r1.value.ok[0..1]);
    a.free(r1.value.ok);

    const r2 = try outputsParser.parse(a, "( out )");
    const o2 = Output{ .name = &[_]u8{ 'o', 'u', 't' } };
    const output2 = [1]Output{o2};
    try testing.expectEqualDeep(&output2, r2.value.ok[0..1]);
    a.free(r2.value.ok);

    const r3 = try outputsParser.parse(a, "( out1, out2 )");
    const o3a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const o3b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const output3 = [2]Output{ o3a, o3b };
    try testing.expectEqualDeep(&output3, r3.value.ok[0..2]);
    a.free(r3.value.ok);

    const r4 = try outputsParser.parse(a, "( out1, out2, txt1 )");
    const o4a = Output{ .name = &[_]u8{ 'o', 'u', 't', '1' } };
    const o4b = Output{ .name = &[_]u8{ 'o', 'u', 't', '2' } };
    const o4c = Output{ .name = &[_]u8{ 't', 'x', 't', '1' } };
    const output4 = [3]Output{ o4a, o4b, o4c };
    try testing.expectEqualDeep(&output4, r4.value.ok[0..3]);
    a.free(r4.value.ok);
}
