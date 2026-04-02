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
