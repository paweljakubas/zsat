const std = @import("std");
const cmdtest = @import("cmdtest");
const testing = std.testing;

const zsat_path = "zsat";

fn cleanupOutputFiles() void {
    var n: u32 = 0;
    while (true) : (n += 1) {
        const filename = std.fmt.allocPrint(std.heap.page_allocator, "output{d}.png", .{n}) catch break;
        defer std.heap.page_allocator.free(filename);
        std.Io.Dir.cwd().deleteFile(std.testing.io, filename) catch break;
    }
}

test "zsat version" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "version" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expect(std.mem.startsWith(u8, result.stdout, "0.0.1\n"));
    // Note: zli 5.1.1 appends a terminal cursor-show escape sequence (\x1b[?25h)
    // to stdout on command completion, so we no longer assert an exact length.
    try testing.expect(result.stdout.len > 8);
}

test "zsat draw" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with invalid styles" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "invalid" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "failed to parse styles"));
}

test "zsat draw with malformed pt2d style attribute" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0:{pt2d [sh:triangle]}" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(1,1)}" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "failed to parse styles"));
}

test "zsat draw with malformed pt2d style size" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0:{pt2d [s:abc]}" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(1,1)}" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "failed to parse styles"));
}

test "zsat draw with invalid stdin" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "invalid" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "failed to parse input data"));
}

test "zsat draw with invalid datum" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--datum", "invalid" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "failed to parse datum mapping"));
}

test "zsat draw with invalid styles and datum" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "invalid", "--datum", "invalid" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "failed to parse styles"));
}

test "zsat draw with style missing vec2d" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0:{[l:10]}", "--datum", "(vec) -> (vec -> e0)" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

test "zsat draw with style reference" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0: e0{[l:15, c: red]}", "--datum", "(vec) -> (vec -> e0)" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

test "zsat draw with style copy" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e1: e0", "--datum", "(vec) -> (vec -> e1)" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
}

test "zsat draw with multiline styles" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0:{vec2d},\n  e1:{vec2d polar}" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with two styles" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0:{vec2d}, e8:{vec2d polar}", "--datum", "(vec) -> (vec -> e0)" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with wrong number of datum" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--datum", "(vec, vec) -> (vec -> e0)" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "number of datum mappings does not match"));
}

test "zsat draw with invalid element in mapping" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e5)" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "invalid element was found"));
}

test "zsat draw with invalid data in mapping" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--datum", "(vec) -> (other -> e0)" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "invalid data type in the datum mapping"));
}

test "zsat draw with two panes" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--panes", "p0:{view:{(0,0), (100, 100)}}, p1:{view:{(0,0), (50, 50)}}" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with invalid panes" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--panes", "invalid" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "failed to parse panes"));
}

test "zsat draw with styles, datum and panes" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e0)", "--panes", "p0:{view:{(0,0), (100, 100)}}" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with two styles, two panes" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0:{vec2d}, e1:{vec2d}", "--datum", "(vec) -> (vec -> e0)", "--panes", "p0:{view:{(0,0), (100, 100)}}, p1:{view:{(0,0), (50, 50)}}" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with frames" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--frames", "(out) -> out -> p0" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with invalid frames" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--frames", "invalid" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "failed to parse frames"));
}

test "zsat draw with invalid pane in frames" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--frames", "(out) -> out -> p5" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "invalid pane was referenced"));
}

test "zsat draw with styles, datum, panes and frames" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e0)", "--panes", "p0:{view:{(0,0), (100, 100)}}", "--frames", "(out) -> out -> p0" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw with debug" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "stdin:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--styles"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--datum"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--panes"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--frames"));
}

test "zsat draw with debug and custom options" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e0)", "--panes", "p0:{view:{(0,0), (100, 100)}}", "--frames", "(out) -> out -> p0" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "stdin:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--styles e0:{vec2d xy fixed last [l:10, c: black, o: 100, e:none, j: none, d:none]}"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--datum (vec) -> (vec -> e0)"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--panes p0:{size: 600x600, border: none}"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--frames (out) -> out -> p0"));
}

test "zsat draw -h cleaned output" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "-h" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);

    // Should show the hint pointing to objects --help instead of listing commands
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "To explore help more try: zsat draw objects --help"));

    // Type annotations like [String] or [Bool] should NOT appear
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, " [String]"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, " [Bool]"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, " [Int]"));

    // Defaults should appear on their own line prefixed with "Default:"
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Default: \"(vec) -> (vec -> e0)\""));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Default: \"e0:{vec2d xy fixed last"));
}

test "zsat draw vec2d --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "vec2d", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Vector data is the primary input format"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "multi-segment vector"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Coordinate systems:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "xy"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "polar"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "anchor POINT"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "vec2d output --help"));
}

test "zsat draw vec2d style --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "vec2d", "style", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Style definition syntax"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "fixed"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "origin"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "coord"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "last"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "all"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "l:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "c:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "d:"));
}

test "zsat draw vec2d output --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "vec2d", "output", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "anchor POINT"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "rotate"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "scale"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "mirror"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "1r4p"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "-1r6p"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "point --help"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "line --help"));
}

test "zsat draw point --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "point", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Explicit point"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "{(X, Y)}"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "beg self"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "mid self"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "end self"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "25% self"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "beg out0"));
}

test "zsat draw pt2d --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "pt2d", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Points are an input format"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "{(1,1)}"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "{(0,0), (1,0), (0,1)}"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "xy"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "polar"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "(pt) -> pt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "pt2d style --help"));
}

test "zsat draw pt2d style --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "pt2d", "style", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Style definition syntax"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "pt2d"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "xy"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "polar"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "sh:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "s:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "circle"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "square"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "c:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "o:"));
}

test "zsat draw with pt2d style" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(1,1)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d square multi-point" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:square, s:5, c: red]}", "-o", "(pt) -> pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (1,0), (0,1)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d polar" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d polar [sh:circle, s:8]}", "-o", "(pt) -> pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(2,45)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d multiple rows" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d}", "-o", "(pt) -> pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(1,1)}\n{(2,2)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d anchor works" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> (anchor {(1,2)}) pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (1,0)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d rotate works" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> (rotate [90 a {(-0,0)}]) pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (1,0)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d mirror works" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> (mirror (x=1)) pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (1,0)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d project works" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> (project (y=0)) pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (1,0)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d scale rejected" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> (scale [[2,3]]) pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (1,0)}" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "scale"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "point"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "pt2d"));
}

test "zsat draw pt2d orthogonal rejected" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> (orthogonal (y=0)) pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (1,0)}" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "orthogonal"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "point"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "pt2d"));
}

test "zsat draw pt2d scale works for vec2d" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{vec2d [l:5]}", "-o", "(out) -> (scale [[2,3]]) out" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw line --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "line", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "mirror"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "y = x"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "x = C"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "y = C"));
}

test "zsat draw color --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "color", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "CSS color name"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "c:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "black"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "aqua"));
}

test "zsat draw objects --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "objects", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "vec2d"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "pt2d"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "point"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "line"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "angle"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "color"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "zsat draw vec2d --help"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "zsat draw pt2d --help"));
}

test "zsat draw angle --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "angle", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "degrees"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "radians"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "1r4p"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "-1r6p"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "pi"));
}
