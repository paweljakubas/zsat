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

test "zsat draw with pN style" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "p0:{pt2d [sh:square, s:15, c: grey]}", "--datum", "(pt) -> (pt -> p0)" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(1,1)}" });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
}

const test_config_content =
    \\- sleek
    \\e0:{vec2d xy fixed last [l:10, c: black, o: 100, e:none, j: none, d: none]}
    \\t0: {txt "txt" [c:red, s:20]}
    \\p0:{pt2d [sh:square, s:15, c: grey]}
    \\
    \\- namespace1
    \\e0:{vec2d xy fixed last [l:25, c: red, o: 100, e:none, j: none, d: none]}
    \\p1:{pt2d [sh:circle, s:30, c: blue]}
    \\
;

fn writeTestConfig() !struct { tmp: std.testing.TmpDir, home: []u8, env_map: std.process.Environ.Map } {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();

    try tmp.dir.createDirPath(io, ".config/zsat");
    try tmp.dir.writeFile(io, .{ .sub_path = ".config/zsat/zsat.conf", .data = test_config_content });

    const home = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    errdefer std.testing.allocator.free(home);

    var env_map: std.process.Environ.Map = .init(std.testing.allocator);
    errdefer env_map.deinit();
    try env_map.put("HOME", home);

    return .{ .tmp = tmp, .home = home, .env_map = env_map };
}

test "zsat draw with style from config namespace" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "namespace1::e0" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "c: red") != null);

    const p_argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "namespace1::p1", "--datum", "(pt) -> (pt -> p1)" };
    var p_result = try cmdtest.run(io, .{ .argv = p_argv, .stdin = "{(1,1)}", .env_map = &fixture.env_map });
    defer p_result.deinit();

    try testing.expectEqual(@as(u8, 0), p_result.code);
    try testing.expect(std.mem.indexOf(u8, p_result.stdout, "p1:{pt2d") != null);
}

test "zsat draw with multiple use namespace directives" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "use sleek as s1, use namespace1 as s2, s1::e0, s2::e0", "--datum", "(vec) -> (vec -> s1::e0)" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "s1::e0:{vec2d xy fixed last [l:10, c: black") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "s2::e0:{vec2d xy fixed last [l:25, c: red") != null);
}

test "zsat draw with multiple use namespace directives requires alias" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use sleek, use namespace1 as s2" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
}

test "zsat draw with duplicate use alias" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use sleek as s, use namespace1 as s" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
}

test "zsat draw with use namespace directive" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "use namespace1" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "--styles e0:{vec2d xy fixed last [l:25, c: red") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "p1:{pt2d") != null);
}

test "zsat draw with use namespace directive with alias" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "use namespace1 as s, s::e0, s::p1", "--datum", "(vec) -> (vec -> s::e0)" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "s::e0:{vec2d xy fixed last [l:25, c: red") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "s::p1:{pt2d") != null);
}

test "zsat draw with use of unknown namespace" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use missing_namespace" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "namespace 'missing_namespace' was requested") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Defined namespaces: sleek, namespace1.") != null);
}

test "zsat draw lists available namespaces on error" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "gone::e0" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "namespace 'gone' was requested") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Defined namespaces: sleek, namespace1.") != null);
}

test "zsat draw lists available keys on missing key error" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "namespace1::xyz" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "key 'xyz' is not present in namespace 'namespace1'.") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Defined keys: e0, p1.") != null);
}

test "zsat draw reports alias in missing key error" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use sleek as s1, use namespace1 as s2, s2::nope" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "key 'nope' is not present in namespace 'namespace1' (imported as 's2').") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Defined keys: e0, p1.") != null);
}

test "zsat draw reports missing namespace before missing key" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "gone::xyz" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "namespace 'gone' was requested") != null);
}

test "zsat draw reports missing config file" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "gone::e0" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "zsat.conf does not exist") != null);
}

test "zsat draw with use of unknown namespace among several" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use sleek as s1, use missing_namespace as s2" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "namespace") != null);
}

test "zsat draw with unknown alias reference" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.env_map.deinit();
    defer std.testing.allocator.free(fixture.home);
    defer fixture.tmp.cleanup();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use sleek as s1, unknown_alias::e0" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "namespace") != null);
}

test "zsat draw with unknown config namespace" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "missing_namespace::e0" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.indexOf(u8, result.stderr, "namespace") != null);
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
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "pt2d output --help"));
}

test "zsat draw pt2d output --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "pt2d", "output", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "anchor POINT"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "rotate"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "mirror"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "project"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "scale"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "orthogonal"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "1r4p"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "-1r6p"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "point --help"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "line --help"));
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

test "zsat draw pt2d anchor multi point works" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> (anchor {(1,2)}) pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (2,0), (1,3)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d anchor single point works" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> (anchor {(1,2)}) pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(5,5)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d anchor compose with rotate works" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> (anchor {(1,2)} & rotate [90 a {(-0,0)}]) pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (2,0), (1,3)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d pure anchor with identity sibling works" {
    // out1's identity op triggers Phase 2 for all pairs; out2's pure anchor must
    // still translate its point set so its centroid lands on the anchor.
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{
        zsat_path, "draw",                                                                       "--out", "/dev/null",
        "-s",      "e0:{pt2d [sh:circle, s:10]}, e1:{pt2d [sh:square, s:10]}, e2:{vec2d [l:5]}", "-d",    "(pt0, pt1, vec0) -> (pt0 -> e0, pt1 -> e1, vec0 -> e2)",
        "-o",      "(out1, out2, out3) -> (out1, a {(0.75, 0.25)} out2, a {(0,0)} out3)",
    };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (1,1)}\n{(0.3,0.3),(0.33,0.45),(0.75,0.75)}\n[[1,0.75]]" });
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

test "zsat draw pt2d center works" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> (center) pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (2,0)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw pt2d center shorthand works" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{pt2d [sh:circle, s:10]}", "-o", "(pt) -> (c) pt" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0), (2,0)}" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw vec2d center works" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{vec2d [l:5]}", "-o", "(out) -> (center) out" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw vec2d center shorthand works" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-s", "e0:{vec2d [l:5]}", "-o", "(out) -> (c) out" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
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
