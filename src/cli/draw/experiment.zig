const mecha = @import("mecha");
const common = @import("common.zig");
const std = @import("std");
const testing = std.testing;

////Types
const Composite = union(enum) {
    a: *FactorA,
    b: *FactorB,
};

const CompositeInside = union(enum) {
    stop,
    inside: *Composite,
};

const FactorA = struct {
    composite: CompositeInside,
    simple: f32,
};

const FactorB = struct {
    compositeLeft: CompositeInside,
    simple: u32,
    compositeRight: CompositeInside,
};

const floatParser = mecha.combine(.{
    mecha.ascii.range('0', '9').many(.{ .collect = false, .min = 1 }).asStr(),
    mecha.ascii.char('.').discard(),
    mecha.ascii.range('0', '9').many(.{ .collect = false }).asStr(),
}).map(struct {
    fn toFloat(parts: anytype) f32 {
        const int_part = parts[0];
        const frac_part = parts[1];
        var buf: [64]u8 = undefined;
        const combined = std.fmt.bufPrint(&buf, "{s}.{s}", .{ int_part, frac_part }) catch unreachable;
        return std.fmt.parseFloat(f32, combined) catch unreachable;
    }
}.toFloat);

fn parseFactorA(allocator: std.mem.Allocator, fa: *FactorA) mecha.ConvertError!FactorA {
    const result = fa.*;
    allocator.destroy(fa);
    return result;
}

const factorAParser = mecha.combine(.{
    common.skipOpenBracket,
    factorAParserInner,
    common.skipCloseBracket,
}).convert(parseFactorA);

fn parseFactorB(allocator: std.mem.Allocator, fb: *FactorB) mecha.ConvertError!FactorB {
    const result = fb.*;
    allocator.destroy(fb);
    return result;
}

const factorBParser = mecha.combine(.{
    common.skipOpenBracket,
    factorBParserInner,
    common.skipCloseBracket,
}).convert(parseFactorB);

fn compositeInsideParserRef() mecha.Parser(CompositeInside) {
    return compositeInsideParser;
}

fn compositeToInside(allocator: std.mem.Allocator, a: Composite) mecha.ConvertError!CompositeInside {
    const p = try allocator.create(Composite);
    p.* = a;
    return CompositeInside{ .inside = p };
}

const compositeInsideParser = mecha.oneOf(.{
    mecha.combine(.{
        common.skipOpenBracket,
        mecha.ref(compositeParserRef),
        common.skipCloseBracket,
    }).convert(compositeToInside),
    mecha.string("stop").map(struct {
        fn toStop(_: anytype) CompositeInside {
            return .stop;
        }
    }.toStop),
});

fn compositeParserRef() mecha.Parser(Composite) {
    return compositeParser;
}

fn parseFactorAInner(allocator: std.mem.Allocator, args: anytype) mecha.ConvertError!*FactorA {
    const composite = args[0];
    const simple = args[1];
    const fa = try allocator.create(FactorA);
    fa.* = FactorA{ .composite = composite, .simple = simple };
    return fa;
}

const factorAParserInner = mecha.combine(.{
    mecha.ref(compositeInsideParserRef),
    common.skipWhitespace,
    floatParser,
}).convert(parseFactorAInner);

fn parseFactorBInner(allocator: std.mem.Allocator, args: anytype) mecha.ConvertError!*FactorB {
    const compositeLeft = args[0];
    const simple = args[1];
    const compositeRight = args[2];
    const fb = try allocator.create(FactorB);
    fb.* = FactorB{ .compositeLeft = compositeLeft, .simple = simple, .compositeRight = compositeRight };
    return fb;
}

const factorBParserInner = mecha.combine(.{
    mecha.ref(compositeInsideParserRef),
    common.skipWhitespace,
    mecha.int(u32, .{}),
    common.skipWhitespace,
    mecha.ref(compositeInsideParserRef),
}).convert(parseFactorBInner);

const compositeParser = mecha.oneOf(.{
    factorAParserInner.map(struct {
        fn toFactorA(a: *FactorA) Composite {
            return Composite{ .a = a };
        }
    }.toFactorA),
    factorBParserInner.map(struct {
        fn toFactorB(a: *FactorB) Composite {
            return Composite{ .b = a };
        }
    }.toFactorB),
});

fn freeCompositeInside(a: std.mem.Allocator, ci: CompositeInside) void {
    if (ci == .inside) {
        const comp = ci.inside;
        switch (comp.*) {
            .a => |fa| a.destroy(fa),
            .b => |fb| a.destroy(fb),
        }
        a.destroy(comp);
    }
}

fn freeFactorA(a: std.mem.Allocator, fa: FactorA) void {
    freeCompositeInside(a, fa.composite);
}

fn freeFactorB(a: std.mem.Allocator, fb: FactorB) void {
    freeCompositeInside(a, fb.compositeLeft);
    freeCompositeInside(a, fb.compositeRight);
}

test "factorAParser" {
    const a = testing.allocator;

    const r1 = try factorAParser.parse(a, "(stop 3.3)");
    try testing.expect(r1.value == .ok);
    try testing.expectEqual(@as(f32, 3.3), r1.value.ok.simple);
    try testing.expect(r1.value.ok.composite == .stop);
    defer freeFactorA(a, r1.value.ok);

    const r2 = try factorAParser.parse(a, "((stop 5 stop) 2.2)");
    try testing.expect(r2.value == .ok);
    try testing.expectEqual(@as(f32, 2.2), r2.value.ok.simple);
    try testing.expect(r2.value.ok.composite == .inside);
    defer freeFactorA(a, r2.value.ok);

    const r3 = try factorAParser.parse(a, "((stop 1.1) 5.0)");
    try testing.expect(r3.value == .ok);
    try testing.expectEqual(@as(f32, 5.0), r3.value.ok.simple);
    try testing.expect(r3.value.ok.composite == .inside);
    defer freeFactorA(a, r3.value.ok);
}

test "factorBParser" {
    const a = testing.allocator;

    const r1 = try factorBParser.parse(a, "(stop 3 stop)");
    try testing.expect(r1.value == .ok);
    try testing.expectEqual(@as(u32, 3), r1.value.ok.simple);
    try testing.expect(r1.value.ok.compositeLeft == .stop);
    try testing.expect(r1.value.ok.compositeRight == .stop);
    defer freeFactorB(a, r1.value.ok);

    const r2 = try factorBParser.parse(a, "((stop 5 stop) 2 stop)");
    try testing.expect(r2.value == .ok);
    try testing.expectEqual(@as(u32, 2), r2.value.ok.simple);
    try testing.expect(r2.value.ok.compositeLeft == .inside);
    try testing.expect(r2.value.ok.compositeRight == .stop);
    defer freeFactorB(a, r2.value.ok);

    const r3 = try factorBParser.parse(a, "((stop 1.1) 5 (stop 11 stop))");
    try testing.expect(r3.value == .ok);
    try testing.expectEqual(@as(u32, 5), r3.value.ok.simple);
    try testing.expect(r3.value.ok.compositeLeft == .inside);
    try testing.expect(r3.value.ok.compositeRight == .inside);
    defer freeFactorB(a, r3.value.ok);
}
