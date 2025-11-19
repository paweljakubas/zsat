const std = @import("std");
const cmdtest = @import("cmdtest");
const testing = std.testing;

test "zsat version" {
    const argv = &[_][]const u8{ "./zig-out/bin/zsat", "version" };
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("0.0.1\n", result.stdout);
}
