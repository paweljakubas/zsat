const std = @import("std");
const cmdtest = @import("cmdtest");
const testing = std.testing;

const zsat_path = "zsat";

fn cleanupOutputFiles() void {
    var n: u32 = 0;
    while (true) : (n += 1) {
        const filename = std.fmt.allocPrint(std.heap.page_allocator, "output{d}.png", .{n}) catch break;
        defer std.heap.page_allocator.free(filename);
        std.fs.cwd().deleteFile(filename) catch break;
    }
}

test "zsat version" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "version" };
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expect(std.mem.startsWith(u8, result.stdout, "0.0.1\n"));
    try testing.expect(result.stdout.len == 14); // "0.0.1\n" + 7 char commit + "\n"
}

test "zsat draw" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with invalid styles" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--styles", "invalid" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ParseStylesFailed"));
}

test "zsat draw with invalid stdin" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "invalid" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ParseInputsFailed"));
}

test "zsat draw with invalid datum" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--datum", "invalid" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ParseDatumFailed"));
}

test "zsat draw with invalid styles and datum" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--styles", "invalid", "--datum", "invalid" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ParseStylesFailed"));
}

test "zsat draw with two styles" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--styles", "e0:{vec2d}, e8:{vec2d polar}", "--datum", "(vec) -> (vec -> e0)" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with wrong number of datum" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--datum", "(vec, vec) -> (vec -> e0)" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "WrongNumberOfDatum"));
}

test "zsat draw with invalid element in mapping" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e5)" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ElementInMappingInvalid"));
}

test "zsat draw with invalid data in mapping" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--datum", "(vec) -> (other -> e0)" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "DataInMappingInvalid"));
}

test "zsat draw with two panes" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--panes", "p0:{view:{(0,0), (100, 100)}}, p1:{view:{(0,0), (50, 50)}}" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with invalid panes" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--panes", "invalid" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ParsePanesFailed"));
}

test "zsat draw with styles, datum and panes" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e0)", "--panes", "p0:{view:{(0,0), (100, 100)}}" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with two styles, two panes" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--styles", "e0:{vec2d}, e1:{vec2d}", "--datum", "(vec) -> (vec -> e0)", "--panes", "p0:{view:{(0,0), (100, 100)}}, p1:{view:{(0,0), (50, 50)}}" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with frames" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--frames", "(out) -> out -> p0" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with invalid frames" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--frames", "invalid" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ParseFramesFailed"));
}

test "zsat draw with invalid pane in frames" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--frames", "(out) -> out -> p5" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "PaneInMappingInvalid"));
}

test "zsat draw with styles, datum, panes and frames" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e0)", "--panes", "p0:{view:{(0,0), (100, 100)}}", "--frames", "(out) -> out -> p0" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with debug" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--debug" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "stdin:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--styles"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--datum"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--panes"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--frames"));
}

test "zsat draw with debug and custom options" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--debug", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e0)", "--panes", "p0:{view:{(0,0), (100, 100)}}", "--frames", "(out) -> out -> p0" };
    var result = try cmdtest.run(.{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .Exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "stdin:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--styles e0:{vec2d}"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--datum (vec) -> (vec -> e0)"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--panes p0:{view:{(0,0), (100, 100)}}"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--frames (out) -> out -> p0"));
}
