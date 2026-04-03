const std = @import("std");
const cmdtest = @import("cmdtest");
const testing = std.testing;

test "zsat version" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "version" };
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("0.0.1\n", result.stdout);
}

test "zsat draw" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "draw" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with invalid styles" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "draw", "--styles", "invalid" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ParseStylesFailed"));
}

test "zsat draw with invalid stdin" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "draw" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "invalid" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ParseInputsFailed"));
}

test "zsat draw with invalid datum" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "draw", "--datum", "invalid" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ParseDatumFailed"));
}

test "zsat draw with invalid styles and datum" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "draw", "--styles", "invalid", "--datum", "invalid" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ParseStylesFailed"));
}

test "zsat draw with two styles" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "draw", "--styles", "e0:{vec2d}, e8:{vec2d polar}", "--datum", "(vec) -> (vec -> e0)" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with wrong number of datum" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "draw", "--datum", "(vec, vec) -> (vec -> e0)" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "WrongNumberOfDatum"));
}

test "zsat draw with invalid element in mapping" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "draw", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e5)" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ElementInMappingInvalid"));
}

test "zsat draw with invalid data in mapping" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "draw", "--datum", "(vec) -> (other -> e0)" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "DataInMappingInvalid"));
}
