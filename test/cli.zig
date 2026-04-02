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
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "styles parsed successfully"));
}

test "zsat draw with invalid styles" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "draw", "--styles", "invalid" };
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "failed to parse styles"));
}
