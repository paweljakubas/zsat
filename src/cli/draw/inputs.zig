const mecha = @import("mecha");
const common = @import("common.zig");
const std = @import("std");
const testing = std.testing;

////Types
const sign = mecha.oneOf(.{
    mecha.utf8.char('+'),
    mecha.utf8.char('-'),
});

const exponent = mecha.combine(.{
    mecha.oneOf(.{ mecha.utf8.char('E'), mecha.utf8.char('e') }),
    sign,
    common.digits,
});

const scientific = mecha.combine(.{
    mecha.utf8.char('-').opt(),
    common.integer,
    mecha.combine(.{
        mecha.utf8.char('.'),
        common.digits,
    }).opt(),
    exponent,
});

const floatFromScientific = scientific.asStr().convert(mecha.toFloat(f32));

test "floatFromScientific" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const fa = arena.allocator();

    const r1 = try floatFromScientific.parse(fa, "2e+1");
    try testing.expectEqual(20.0, r1.value.ok);

    const r2 = try floatFromScientific.parse(fa, "9.87E+02");
    try testing.expectEqual(987.0, r2.value.ok);

    const r3 = try floatFromScientific.parse(fa, "4.321768e+003");
    try testing.expectEqual(4321.768, r3.value.ok);

    const r4 = try floatFromScientific.parse(fa, "-5.3e+004");
    try testing.expectEqual(-53000.0, r4.value.ok);

    const r5 = try floatFromScientific.parse(fa, "2e-1");
    try testing.expectEqual(0.2, r5.value.ok);

    const r6 = try floatFromScientific.parse(fa, "7.51E-09");
    try testing.expectEqual(0.00000000751, r6.value.ok);
}

const floatParser = mecha.oneOf(.{
    floatFromScientific,
    common.floatFromDecimal,
});

test "floatParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const fa = arena.allocator();

    const r1 = try floatParser.parse(fa, "2e+1");
    try testing.expectEqual(20.0, r1.value.ok);

    const r2 = try floatParser.parse(fa, "9.87E+02");
    try testing.expectEqual(987.0, r2.value.ok);

    const r3 = try floatParser.parse(fa, "4.321768e+003");
    try testing.expectEqual(4321.768, r3.value.ok);

    const r4 = try floatParser.parse(fa, "-5.3e+004");
    try testing.expectEqual(-53000.0, r4.value.ok);

    const r5 = try floatParser.parse(fa, "2e-1");
    try testing.expectEqual(0.2, r5.value.ok);

    const r6 = try floatParser.parse(fa, "7.51E-09");
    try testing.expectEqual(0.00000000751, r6.value.ok);

    const r7 = try floatParser.parse(fa, "1.11");
    try testing.expectEqual(1.11, r7.value.ok);

    const r8 = try floatParser.parse(fa, "-10.01");
    try testing.expectEqual(-10.01, r8.value.ok);

    const r9 = try floatParser.parse(fa, "1");
    try testing.expectEqual(1.0, r9.value.ok);

    const r10 = try floatParser.parse(fa, "-10");
    try testing.expectEqual(-10.0, r10.value.ok);
}

pub const Point = struct {
    x: f32,
    y: f32,
};

const pointParserRaw = mecha.combine(.{ common.skipOpenBracket, floatParser, common.skipComma, floatParser, common.skipCloseBracket });
const pointParserRawP = @TypeOf(pointParserRaw);
fn toPointParser(_: std.mem.Allocator, res: pointParserRawP.T) mecha.ConvertError!Point {
    return Point{ .x = res[0], .y = res[1] };
}
pub const pointParser = pointParserRaw.convert(toPointParser);

test "pointParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const fa = arena.allocator();

    const r1 = try pointParser.parse(fa, "(2,1.1)");
    const p1 = Point{ .x = 2.0, .y = 1.1 };
    try testing.expectEqual(p1, r1.value.ok);

    const r2 = try pointParser.parse(fa, " (2,-1.1) ");
    const p2 = Point{ .x = 2.0, .y = -1.1 };
    try testing.expectEqual(p2, r2.value.ok);

    const r3 = try pointParser.parse(fa, " (2e+003 , -1.1) ");
    const p3 = Point{ .x = 2000.0, .y = -1.1 };
    try testing.expectEqual(p3, r3.value.ok);
}

const pointsParser = mecha.combine(.{
    common.skipOpenBrace,
    pointParser.many(.{ .collect = true, .separator = common.skipComma }),
    common.skipCloseBrace,
});

test "pointsParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try pointsParser.parse(a, "{(2,1.1)}");
    const p1 = Point{ .x = 2.0, .y = 1.1 };
    try testing.expectEqualDeep(&[1]Point{p1}, r1.value.ok[0..1]);

    const r2 = try pointsParser.parse(a, "{(2,1.1), (-2, -1.1)}");
    const p2a = Point{ .x = 2.0, .y = 1.1 };
    const p2b = Point{ .x = -2.0, .y = -1.1 };
    try testing.expectEqualDeep(&[2]Point{ p2a, p2b }, r2.value.ok[0..2]);

    const r3 = try pointsParser.parse(a, "{(0,1.0), (0,-1.0), (1.0, 0)}");
    const p3a = Point{ .x = 0.0, .y = 1.0 };
    const p3b = Point{ .x = 0.0, .y = -1.0 };
    const p3c = Point{ .x = 1.0, .y = 0.0 };
    try testing.expectEqualDeep(&[3]Point{ p3a, p3b, p3c }, r3.value.ok[0..3]);
}

pub const Vector = struct {
    x: f32,
    y: f32,
};

/// Converts a polar vector (x=r, y=phi_degrees) to Cartesian (dx, dy).
/// This is used when CoordinateType is .polar in styles.
pub fn polarVectorToCartesian(v: Vector) Vector {
    const phi_rad = v.y * (pi / 180.0);
    return Vector{
        .x = v.x * @cos(phi_rad),
        .y = v.x * @sin(phi_rad),
    };
}

const vectorParserRaw = mecha.combine(.{ common.skipOpenSquare, floatParser, common.skipComma, floatParser, common.skipCloseSquare });
const vectorParserRawP = @TypeOf(vectorParserRaw);
fn toVectorParser(_: std.mem.Allocator, res: vectorParserRawP.T) mecha.ConvertError!Vector {
    return Vector{ .x = res[0], .y = res[1] };
}
const vectorParser = vectorParserRaw.convert(toVectorParser);

test "vectorParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const fa = arena.allocator();

    const r1 = try vectorParser.parse(fa, "[2,1.1]");
    const p1 = Vector{ .x = 2.0, .y = 1.1 };
    try testing.expectEqual(p1, r1.value.ok);

    const r2 = try vectorParser.parse(fa, " [2,-1.1] ");
    const p2 = Vector{ .x = 2.0, .y = -1.1 };
    try testing.expectEqual(p2, r2.value.ok);

    const r3 = try vectorParser.parse(fa, " [2e+003 , -1.1] ");
    const p3 = Vector{ .x = 2000.0, .y = -1.1 };
    try testing.expectEqual(p3, r3.value.ok);
}

test "polarVectorToCartesian" {
    // sqrt(2) @ 45° -> (1, 1)
    const v1 = polarVectorToCartesian(Vector{ .x = @sqrt(2.0), .y = 45.0 });
    try testing.expectApproxEqAbs(@as(f32, 1.0), v1.x, 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 1.0), v1.y, 0.0001);

    // r=2 @ 90° -> (0, 2)
    const v2 = polarVectorToCartesian(Vector{ .x = 2.0, .y = 90.0 });
    try testing.expectApproxEqAbs(@as(f32, 0.0), v2.x, 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 2.0), v2.y, 0.0001);

    // r=0 -> (0, 0)
    const v3 = polarVectorToCartesian(Vector{ .x = 0.0, .y = 45.0 });
    try testing.expectApproxEqAbs(@as(f32, 0.0), v3.x, 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), v3.y, 0.0001);

    // r=1 @ 0° -> (1, 0)
    const v4 = polarVectorToCartesian(Vector{ .x = 1.0, .y = 0.0 });
    try testing.expectApproxEqAbs(@as(f32, 1.0), v4.x, 0.0001);
    try testing.expectApproxEqAbs(@as(f32, 0.0), v4.y, 0.0001);
}

pub const vectorsParser = mecha.combine(.{
    common.skipOpenSquare,
    vectorParser.many(.{ .collect = true, .separator = common.skipComma }),
    common.skipCloseSquare,
});

test "vectorsParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try vectorsParser.parse(a, "[[2,1.1]]");
    const p1 = Vector{ .x = 2.0, .y = 1.1 };
    try testing.expectEqualDeep(&[1]Vector{p1}, r1.value.ok[0..1]);
    const r2 = try vectorsParser.parse(a, "[[2,1.1], [-2, -1.1]]");
    const p2a = Vector{ .x = 2.0, .y = 1.1 };
    const p2b = Vector{ .x = -2.0, .y = -1.1 };
    try testing.expectEqualDeep(&[2]Vector{ p2a, p2b }, r2.value.ok[0..2]);

    const r3 = try vectorsParser.parse(a, "[[0,1.0], [0,-1.0], [1.0, 0]]");
    const p3a = Vector{ .x = 0.0, .y = 1.0 };
    const p3b = Vector{ .x = 0.0, .y = -1.0 };
    const p3c = Vector{ .x = 1.0, .y = 0.0 };
    try testing.expectEqualDeep(&[3]Vector{ p3a, p3b, p3c }, r3.value.ok[0..3]);
}

pub const InputElement = union(enum) {
    point: Point,
    vector: Vector,
};

pub const InputElementRow = struct {
    row: []const InputElement,
};

pub const Inputs = struct {
    input: []const InputElementRow,
};

const newlines = mecha.ascii.char('\n').many(.{ .collect = false, .min = 1 });
const rowSeparator = mecha.combine(.{ newlines.discard(), common.skipWhitespace });
const newlineParser = mecha.combine(.{ mecha.ascii.char('\n'), common.skipWhitespace });

const inputElementParser = mecha.oneOf(.{
    vectorParser.asStr().convert(struct {
        fn conv(_: std.mem.Allocator, str: []const u8) mecha.ConvertError!InputElement {
            const result = try vectorParser.parse(std.heap.page_allocator, str);
            return InputElement{ .vector = result.value.ok };
        }
    }.conv),
    pointParser.asStr().convert(struct {
        fn conv(_: std.mem.Allocator, str: []const u8) mecha.ConvertError!InputElement {
            const result = try pointParser.parse(std.heap.page_allocator, str);
            return InputElement{ .point = result.value.ok };
        }
    }.conv),
});

const inputElementRowParserRawVec = mecha.combine(.{
    common.skipOpenSquare,
    vectorParser.many(.{ .collect = true, .separator = common.skipComma }),
    common.skipCloseSquare,
}).asStr();

const inputElementRowParserRawPoint = mecha.combine(.{
    common.skipOpenBrace,
    pointParser.many(.{ .collect = true, .separator = common.skipComma }),
    common.skipCloseBrace,
}).asStr();

const inputElementRowParserRaw = mecha.oneOf(.{
    inputElementRowParserRawVec,
    inputElementRowParserRawPoint,
});

const inputElementRowParserRawP = @TypeOf(inputElementRowParserRaw);
fn toInputElementRow(_: std.mem.Allocator, str: inputElementRowParserRawP.T) mecha.ConvertError!InputElementRow {
    const s = str;
    if (s[0] == '[') {
        const result = try vectorsParser.parse(std.heap.page_allocator, s);
        var elements = try std.heap.page_allocator.alloc(InputElement, result.value.ok.len);
        for (result.value.ok, 0..) |v, i| {
            elements[i] = InputElement{ .vector = v };
        }
        return InputElementRow{ .row = elements };
    } else {
        const result = try pointsParser.parse(std.heap.page_allocator, s);
        var elements = try std.heap.page_allocator.alloc(InputElement, result.value.ok.len);
        for (result.value.ok, 0..) |p, i| {
            elements[i] = InputElement{ .point = p };
        }
        return InputElementRow{ .row = elements };
    }
}

const inputElementRowParser = inputElementRowParserRaw.convert(toInputElementRow);

const newlineWithRow = mecha.combine(.{
    newlineParser,
    inputElementRowParser,
});

const inputsParserRaw = mecha.combine(.{
    common.skipWhitespace,
    inputElementRowParser,
    newlineWithRow.many(.{ .collect = true }),
    common.skipWhitespace,
});

const inputsParserRawP = @TypeOf(inputsParserRaw);
fn toInputs(alloc: std.mem.Allocator, res: inputsParserRawP.T) mecha.ConvertError!Inputs {
    const firstRow = res[0];
    const moreRows = res[1];

    const totalRows = moreRows.len + 1;
    var rows = try alloc.alloc(InputElementRow, totalRows);
    rows[0] = firstRow;
    for (moreRows, 0..) |pair, i| {
        rows[i + 1] = pair[1];
    }
    return Inputs{ .input = rows };
}

pub const inputsParser = inputsParserRaw.convert(toInputs);

test "inputsParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try inputsParser.parse(a, "[[2,1.1]]");
    const p1 = InputElement{ .vector = Vector{ .x = 2.0, .y = 1.1 } };
    const row1 = InputElementRow{ .row = &[1]InputElement{p1} };
    const in1 = Inputs{ .input = &[1]InputElementRow{row1} };
    try testing.expectEqualDeep(in1, r1.value.ok);

    const r2 = try inputsParser.parse(a, "[[2,1.1], [-2, -1.1]]");
    const p2a = InputElement{ .vector = Vector{ .x = 2.0, .y = 1.1 } };
    const p2b = InputElement{ .vector = Vector{ .x = -2.0, .y = -1.1 } };
    const row2 = InputElementRow{ .row = &[2]InputElement{ p2a, p2b } };
    const in2 = Inputs{ .input = &[1]InputElementRow{row2} };
    try testing.expectEqualDeep(in2, r2.value.ok);

    const r3 = try inputsParser.parse(a, "[[0,1.0], [0,-1.0], [1.0, 0]]");
    const p3a = InputElement{ .vector = Vector{ .x = 0.0, .y = 1.0 } };
    const p3b = InputElement{ .vector = Vector{ .x = 0.0, .y = -1.0 } };
    const p3c = InputElement{ .vector = Vector{ .x = 1.0, .y = 0.0 } };
    const row3 = InputElementRow{ .row = &[3]InputElement{ p3a, p3b, p3c } };
    const in3 = Inputs{ .input = &[1]InputElementRow{row3} };
    try testing.expectEqualDeep(in3, r3.value.ok);

    const r4 = try inputsParser.parse(a, "[[0,1.0], [0,-1.0]] \n [[1.0, 0]]");
    const p4a = InputElement{ .vector = Vector{ .x = 0.0, .y = 1.0 } };
    const p4b = InputElement{ .vector = Vector{ .x = 0.0, .y = -1.0 } };
    const p4c = InputElement{ .vector = Vector{ .x = 1.0, .y = 0.0 } };
    const row4a = InputElementRow{ .row = &[2]InputElement{ p4a, p4b } };
    const row4b = InputElementRow{ .row = &[1]InputElement{p4c} };
    const in4 = Inputs{ .input = &[2]InputElementRow{ row4a, row4b } };
    try testing.expectEqualDeep(in4, r4.value.ok);

    const r5 = try inputsParser.parse(a, "{(2,1.1), (-2, -1.1)}");
    const p5a = InputElement{ .point = Point{ .x = 2.0, .y = 1.1 } };
    const p5b = InputElement{ .point = Point{ .x = -2.0, .y = -1.1 } };
    const row5 = InputElementRow{ .row = &[2]InputElement{ p5a, p5b } };
    const in5 = Inputs{ .input = &[1]InputElementRow{row5} };
    try testing.expectEqualDeep(in5, r5.value.ok);

    const r6 = try inputsParser.parse(a, "[[0,1.0], [0,-1.0]] \n [[1.0, 0]]\n {(2,1.1), (-2, -1.1)}");
    const p6a = InputElement{ .vector = Vector{ .x = 0.0, .y = 1.0 } };
    const p6b = InputElement{ .vector = Vector{ .x = 0.0, .y = -1.0 } };
    const p6c = InputElement{ .vector = Vector{ .x = 1.0, .y = 0.0 } };
    const p6d = InputElement{ .point = Point{ .x = 2.0, .y = 1.1 } };
    const p6e = InputElement{ .point = Point{ .x = -2.0, .y = -1.1 } };
    const row6a = InputElementRow{ .row = &[2]InputElement{ p6a, p6b } };
    const row6b = InputElementRow{ .row = &[1]InputElement{p6c} };
    const row6c = InputElementRow{ .row = &[2]InputElement{ p6d, p6e } };
    const in6 = Inputs{ .input = &[3]InputElementRow{ row6a, row6b, row6c } };
    try testing.expectEqualDeep(in6, r6.value.ok);
}

pub const Angle = union(enum) {
    degrees: f32,
    radians: f32,
};

pub const pi: f32 = 3.14159265359;

const angleParserPiSuffix = mecha.combine(.{
    mecha.utf8.char('p'),
});

const angleParserPiSuffixP = @TypeOf(angleParserPiSuffix);
fn parsePiSuffix(_: std.mem.Allocator, _: angleParserPiSuffixP.T) mecha.ConvertError!f32 {
    return pi;
}

const angleParserWithRatio = mecha.combine(.{
    common.integer,
    mecha.utf8.char('r'),
    common.integer,
    mecha.utf8.char('p'),
}).asStr();

const angleParserWithRatioP = @TypeOf(angleParserWithRatio);
fn parseWithRatio(_: std.mem.Allocator, res: angleParserWithRatioP.T) mecha.ConvertError!f32 {
    const slash_index = std.mem.indexOfScalar(u8, res, 'r').?;
    const p_index = std.mem.indexOfScalar(u8, res, 'p').?;
    const numerator = std.fmt.parseInt(i32, res[0..slash_index], 10) catch return error.ConversionFailed;
    const denominator = std.fmt.parseInt(i32, res[slash_index + 1 .. p_index], 10) catch return error.ConversionFailed;
    const num_f: f32 = @floatFromInt(numerator);
    const den_f: f32 = @floatFromInt(denominator);
    return (num_f / den_f) * pi;
}

const angleParserWithInt = mecha.combine(.{
    common.integer,
    mecha.utf8.char('p'),
}).asStr();

const angleParserWithIntP = @TypeOf(angleParserWithInt);
fn parseWithInt(_: std.mem.Allocator, res: angleParserWithIntP.T) mecha.ConvertError!f32 {
    const p_index = std.mem.indexOfScalar(u8, res, 'p').?;
    const multiplier = std.fmt.parseInt(i32, res[0..p_index], 10) catch return error.ConversionFailed;
    const mult_f: f32 = @floatFromInt(multiplier);
    return mult_f * pi;
}

const angleParserRadians = mecha.oneOf(.{
    angleParserWithRatio.convert(parseWithRatio),
    angleParserWithInt.convert(parseWithInt),
    angleParserPiSuffix.convert(parsePiSuffix),
});

const angleParserRadiansP = @TypeOf(angleParserRadians);
fn parseRadians(_: std.mem.Allocator, res: angleParserRadiansP.T) mecha.ConvertError!Angle {
    return Angle{ .radians = res };
}

const angleParserDegrees = floatParser;

const angleParserDegreesP = @TypeOf(angleParserDegrees);
fn parseDegrees(_: std.mem.Allocator, res: angleParserDegreesP.T) mecha.ConvertError!Angle {
    return Angle{ .degrees = res };
}

pub const angleParser = mecha.oneOf(.{
    angleParserRadians.convert(parseRadians),
    angleParserDegrees.convert(parseDegrees),
});

test "angleParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try angleParser.parse(a, "90");
    const a1 = Angle{ .degrees = 90.0 };
    try testing.expectEqualDeep(a1, r1.value.ok);

    const r2 = try angleParser.parse(a, "90.0");
    const a2 = Angle{ .degrees = 90.0 };
    try testing.expectEqualDeep(a2, r2.value.ok);

    const r3 = try angleParser.parse(a, "-90");
    const a3 = Angle{ .degrees = -90.0 };
    try testing.expectEqualDeep(a3, r3.value.ok);

    const r4 = try angleParser.parse(a, "p");
    const a4 = Angle{ .radians = pi };
    try testing.expectEqualDeep(a4, r4.value.ok);

    const r5 = try angleParser.parse(a, "1r4p");
    const a5 = Angle{ .radians = 0.25 * pi };
    try testing.expectEqualDeep(a5, r5.value.ok);

    const r6 = try angleParser.parse(a, "5r12p");
    const a6 = Angle{ .radians = 5.0 * pi / 12.0 };
    try testing.expectApproxEqAbs(a6.radians, r6.value.ok.radians, 0.0001);

    const r7 = try angleParser.parse(a, "4p");
    const a7 = Angle{ .radians = 4 * pi };
    try testing.expectEqualDeep(a7, r7.value.ok);
}

//ay=bx+c
pub const Line = struct {
    a: f32,
    b: f32,
    c: f32,
};

fn toYLineType(_: std.mem.Allocator, res: anytype) !Line {
    if (res.len == 3) {
        return Line{ .a = 1.0, .b = res[1], .c = res[2] };
    } else {
        return Line{ .a = 1.0, .b = 0.0, .c = res[1] };
    }
}

fn toXLineType(_: std.mem.Allocator, res: anytype) !Line {
    return Line{ .a = 0.0, .b = 1.0, .c = -res[1] };
}

const xLineParserRaw = mecha.combine(.{
    mecha.utf8.char('x'),
    common.skipWhitespace,
    mecha.utf8.char('=').discard(),
    common.skipWhitespace,
    floatParser,
});

const xLineParserVal = xLineParserRaw.convert(toXLineType);

const yLineWithXParser = mecha.combine(.{
    mecha.utf8.char('y'),
    common.skipWhitespace,
    mecha.utf8.char('=').discard(),
    common.skipWhitespace,
    floatParser,
    mecha.utf8.char('x').discard(),
    common.skipWhitespace,
    mecha.oneOf(.{ mecha.utf8.char('+'), mecha.utf8.char('-') }).discard(),
    common.skipWhitespace,
    floatParser,
});

const yLineWithX = yLineWithXParser.convert(toYLineType);

const yLineWithoutXParser = mecha.combine(.{
    mecha.utf8.char('y'),
    common.skipWhitespace,
    mecha.utf8.char('=').discard(),
    common.skipWhitespace,
    floatParser,
});

const yLineWithoutX = yLineWithoutXParser.convert(toYLineType);

const yLineParser = mecha.oneOf(.{ yLineWithX, yLineWithoutX });

pub const lineParser = mecha.oneOf(.{ xLineParserVal, yLineParser });

test "lineParser" {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const r1 = try lineParser.parse(a, "y=2x+1");
    const l1 = Line{ .a = 1.0, .b = 2.0, .c = 1.0 };
    try testing.expectEqualDeep(l1, r1.value.ok);

    const r2 = try lineParser.parse(a, "y=0.2x+100");
    const l2 = Line{ .a = 1.0, .b = 0.2, .c = 100.0 };
    try testing.expectEqualDeep(l2, r2.value.ok);

    const r3 = try lineParser.parse(a, "y=-0.2x + 100");
    const l3 = Line{ .a = 1.0, .b = -0.2, .c = 100.0 };
    try testing.expectEqualDeep(l3, r3.value.ok);

    const r4 = try lineParser.parse(a, "y=100.1");
    const l4 = Line{ .a = 1.0, .b = 0.0, .c = 100.1 };
    try testing.expectEqualDeep(l4, r4.value.ok);

    const r5 = try lineParser.parse(a, "x=100.1");
    const l5 = Line{ .a = 0.0, .b = 1.0, .c = -100.1 };
    try testing.expectEqualDeep(l5, r5.value.ok);

    const r6 = try lineParser.parse(a, "y = 0");
    const l6 = Line{ .a = 1.0, .b = 0.0, .c = 0.0 };
    try testing.expectEqualDeep(l6, r6.value.ok);

    const r7 = try lineParser.parse(a, "x =0");
    const l7 = Line{ .a = 0.0, .b = 1.0, .c = 0.0 };
    try testing.expectEqualDeep(l7, r7.value.ok);
}
