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

const TestConfig = struct {
    tmp: std.testing.TmpDir,
    home: []u8,
    env_map: std.process.Environ.Map,

    fn deinit(self: *TestConfig) void {
        self.env_map.deinit();
        std.testing.allocator.free(self.home);
        self.tmp.cleanup();
    }

    fn readContent(self: *TestConfig) ![]u8 {
        return self.tmp.dir.readFileAlloc(std.testing.io, ".config/zsat/zsat.conf", std.testing.allocator, .limited(1024 * 1024));
    }
};

fn writeTestConfig() !TestConfig {
    return writeTestConfigWith(test_config_content);
}

fn writeTestConfigWith(content: []const u8) !TestConfig {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();

    try tmp.dir.createDirPath(io, ".config/zsat");
    try tmp.dir.writeFile(io, .{ .sub_path = ".config/zsat/zsat.conf", .data = content });

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
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "namespace1::e0" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "c: red") != null);

    const p_argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "namespace1::p1", "--datum", "(pt) -> (pt -> namespace1::p1)" };
    var p_result = try cmdtest.run(io, .{ .argv = p_argv, .stdin = "{(1,1)}", .env_map = &fixture.env_map });
    defer p_result.deinit();

    try testing.expectEqual(@as(u8, 0), p_result.code);
    try testing.expect(std.mem.indexOf(u8, p_result.stdout, "namespace1::p1:{pt2d") != null);
}

test "zsat draw keeps a qualified reference qualified unless it is aliased" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    // `namespace1::p1` is known by that name only: nothing is silently
    // imported under a bare `p1`.
    const bare_argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "namespace1::p1", "--datum", "(pt) -> (pt -> p1)" };
    var bare_result = try cmdtest.run(io, .{ .argv = bare_argv, .stdin = "{(1,1)}", .env_map = &fixture.env_map });
    defer bare_result.deinit();

    try testing.expect(bare_result.code != 0);
    try testing.expect(std.mem.indexOf(u8, bare_result.stderr, "Defined styles: namespace1::p1, e0.") != null);

    // An explicit alias gives the bare name: `p1: namespace1::p1`.
    const alias_argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "namespace1::p1, p1: namespace1::p1", "--datum", "(pt) -> (pt -> p1)" };
    var alias_result = try cmdtest.run(io, .{ .argv = alias_argv, .stdin = "{(1,1)}", .env_map = &fixture.env_map });
    defer alias_result.deinit();

    try testing.expectEqual(@as(u8, 0), alias_result.code);
}

test "zsat draw with multiple use namespace directives" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

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
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use sleek, use namespace1 as s2" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
}

test "zsat draw with duplicate use alias" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use sleek as s, use namespace1 as s" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
}

test "zsat draw omitted datum ignores definitions merged in from the config" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    // The config brings in e0 and p0; the styles named here come first, and
    // only they take part in the association.
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "e1:{vec2d [c:aqua]}, e2:{vec2d [c:red]}" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[1,1]]\n[[0,1]]\n[[1,0]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "--datum '(vec, vec, vec) -> (vec -> e1, vec -> e2, vec -> e1)'") != null);
}

test "zsat draw with use namespace directive" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "use namespace1" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "--styles 'e0:{vec2d xy fixed last [l:25, c: red") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "p1:{pt2d") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "--datum '(vec) -> (vec -> e0)'") != null);
}

test "zsat draw debug expands default datum with multiple inputs" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]\n[[-1,1]]\n[[-1,-1]]" });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "--datum '(vec, vec, vec) -> (vec -> e0, vec -> e0, vec -> e0)'") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "--outputs '(out, out, out) -> ((anchor {(0.0,0.0)}) out, (anchor {(0.0,0.0)}) out, (anchor {(0.0,0.0)}) out)'") != null);
}

test "zsat draw rotates output ops when outputs are fewer than inputs" {
    const filenames = [_][]const u8{ "rot_a.png", "rot_b.png", "rot_c.png" };
    defer for (filenames) |f| std.Io.Dir.cwd().deleteFile(std.testing.io, f) catch {};

    const stdin_3 = "[[1,1]]\n[[-1,1]]\n[[-1,-1]]";
    const two_ops = "(out1,out2) -> ((anchor {(0,0)}) out1,(anchor {(100,100)}) out2)";

    // Three vectors, two ops: rows must use op0, op1, op0.
    var r1 = try cmdtest.run(std.testing.io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "rot_a.png", "--outputs", two_ops }, .stdin = stdin_3 });
    defer r1.deinit();

    // The same rotation, spelled out explicitly with three outputs.
    var r2 = try cmdtest.run(std.testing.io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "rot_b.png", "--outputs", "(out1,out2,out3) -> ((anchor {(0,0)}) out1,(anchor {(100,100)}) out2,(anchor {(0,0)}) out3)" }, .stdin = stdin_3 });
    defer r2.deinit();

    // Only two vectors: the picture a "drop" implementation would also produce.
    var r3 = try cmdtest.run(std.testing.io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "rot_c.png", "--outputs", two_ops }, .stdin = "[[1,1]]\n[[-1,1]]" });
    defer r3.deinit();

    try testing.expectEqual(@as(u8, 0), r1.code);
    try testing.expectEqual(@as(u8, 0), r2.code);
    try testing.expectEqual(@as(u8, 0), r3.code);

    const a = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "rot_a.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(a);
    const b = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "rot_b.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(b);
    const c = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "rot_c.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(c);

    // Rotation must reproduce the explicit spelling...
    try testing.expectEqualSlices(u8, a, b);
    // ...and must NOT drop the third vector.
    try testing.expect(!std.mem.eql(u8, a, c));
}

test "zsat draw debug shows rotated outputs" {
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--outputs", "(out1,out2) -> ((anchor {(0,0)}) out1,(anchor {(1,1)}) out2)" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]\n[[-1,1]]\n[[-1,-1]]" });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "--outputs '(out1, out2, out1) -> ((anchor {(0.0,0.0)}) out1, (anchor {(1.0,1.0)}) out2, (anchor {(0.0,0.0)}) out1)'") != null);
}

test "zsat draw with use namespace directive with alias" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "use namespace1 as s, s::e0, s::p1", "--datum", "(vec) -> (vec -> s::e0)" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "s::e0:{vec2d xy fixed last [l:25, c: red") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "s::p1:{pt2d") != null);
}

/// A namespace holding one definition of every kind, so that the alias can be
/// exercised for text, border and axis as well as for styles.
const all_kinds_config_content =
    \\- all
    \\e0:{vec2d}
    \\p0:{pt2d [sh:square, c: grey]}
    \\t0:{txt "aliased" [c:red]}
    \\a0:{axis}
    \\b0:{border [w:5]}
    \\
;

/// A namespace imported without an alias, so that its definitions keep their
/// bare names and a later one can redefine them.
const bare_import_config_content =
    \\- base
    \\e0:{vec2d [l:10, c: blue]}
    \\t0:{txt "imported"}
    \\a0:{axis line:[c:blue]}
    \\p0:{pt2d [sh:square, c: grey]}
    \\b0:{border [w:5]}
    \\
;

test "zsat draw reaches every kind through a namespace imported without an alias" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(bare_import_config_content);
    defer fixture.deinit();

    const argv = &[_][]const u8{
        zsat_path,
        "draw",
        "--out",
        "/dev/null",
        "--styles",
        "use base",
        "--datum",
        "(vec) -> (vec -> e0)",
        "--outputs",
        "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0)",
        "--panes",
        "p0:{size: 600x600, border: b0}",
    };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw lets a definition after an import override it" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(bare_import_config_content);
    defer fixture.deinit();

    const argv = &[_][]const u8{
        zsat_path,
        "draw",
        "--out",
        "/dev/null",
        "--debug",
        "--styles",
        "use base, e0:{vec2d [l:99, c: red]}, e1: e0{}",
        "--datum",
        "(vec) -> (vec -> e1)",
    };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    // `e1` inherits the redefinition that came before it, not the `e0` that
    // `use base` brought in.
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "e0:{vec2d xy fixed last [l:99, c: red") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "e1:{vec2d xy fixed last [l:99, c: red") != null);
}

test "zsat draw names a definition an import already brought in" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(bare_import_config_content);
    defer fixture.deinit();

    // A bare key after `use ns` is not a new definition but a name for one the
    // import brought in, which is why it needs no body.
    const argv = &[_][]const u8{
        zsat_path,
        "draw",
        "--out",
        "/dev/null",
        "--styles",
        "use base, e0, t0, a0",
        "--datum",
        "(vec) -> (vec -> e0)",
        "--outputs",
        "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0)",
        "--panes",
        "p0:{size: 600x600, border: b0}",
    };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw says which definitions a bare key could have named" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(bare_import_config_content);
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use base, e5", "--outputs", "(out) -> (out)" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "'e5' names no definition in --styles. Defined: e0, t0, a0, p0, b0.") != null);
}

test "zsat draw does not let a bare key reach an aliased definition" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(bare_import_config_content);
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use base as s, s::e0, e0", "--outputs", "(out) -> (out)" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "'e0' names no definition in --styles. Defined: s::e0") != null);
}

test "zsat draw requires the prefix when a namespace is imported under an alias" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(bare_import_config_content);
    defer fixture.deinit();

    // Importing without an alias keeps the bare names; importing with one
    // moves them, so the bare name stops resolving.
    const argv = &[_][]const u8{
        zsat_path,
        "draw",
        "--out",
        "/dev/null",
        "--styles",
        "use base as s, s::e0, s::p0",
        "--datum",
        "(vec) -> (vec -> p0)",
    };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "--datum draws with style 'p0', which --styles does not define.") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "s::p0") != null);
}

test "zsat draw names a text and a border from an aliased namespace" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(all_kinds_config_content);
    defer fixture.deinit();

    const argv = &[_][]const u8{
        zsat_path,
        "draw",
        "--out",
        "/dev/null",
        "--styles",
        "use all as s, s::e0, s::t0, s::b0",
        "--datum",
        "(vec) -> (vec -> s::e0)",
        "--outputs",
        "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) s::t0)",
        "--panes",
        "p0:{size: 600x600, border: s::b0}",
    };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw names an axis from an aliased namespace" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(all_kinds_config_content);
    defer fixture.deinit();

    const argv = &[_][]const u8{
        zsat_path,
        "draw",
        "--out",
        "/dev/null",
        "--styles",
        "use all as s, s::e0, s::a0",
        "--datum",
        "(vec) -> (vec -> s::e0)",
        "--outputs",
        "(out) -> (out, ft {(0,-0.1)} {(1.1,-0.1)} s::a0)",
    };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw inherits an axis from an aliased namespace" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(all_kinds_config_content);
    defer fixture.deinit();

    const argv = &[_][]const u8{
        zsat_path,
        "draw",
        "--out",
        "/dev/null",
        "--styles",
        "use all as s, s::e0, s::a0, a1: s::a0{ticks:[pos:0,0.1,..,1.1]}",
        "--datum",
        "(vec) -> (vec -> s::e0)",
        "--outputs",
        "(out) -> (out, ft {(0,-0.1)} {(1.1,-0.1)} a1)",
    };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw inherits line and point styles from an aliased namespace" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(all_kinds_config_content);
    defer fixture.deinit();

    const argv = &[_][]const u8{
        zsat_path,
        "draw",
        "--out",
        "/dev/null",
        "--debug",
        "--styles",
        "use all as s, e1: s::e0{[c: red]}, p1: s::p0{[s: 4]}",
        "--datum",
        "(vec) -> (vec -> e1)",
    };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    // `e1` keeps the line width of its base and only overrides the colour,
    // `p1` keeps the shape and colour of its base and only overrides the size.
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "e1:{vec2d xy fixed last [l:10, c: red") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "p1:{pt2d xy fixed last [sh:square, s:4, c: grey") != null);
}

test "zsat draw reports the collected name when a bare name is used through an alias" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(all_kinds_config_content);
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use all as s, s::b0", "--panes", "p0:{size: 600x600, border: b0}" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "border 'b0' is not defined in --styles. Defined border: s::b0.") != null);
}

test "zsat draw reports the collected axis name when a bare name is used through an alias" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfigWith(all_kinds_config_content);
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "use all as s, s::a0", "--outputs", "(out) -> (out, ft {(0,-0.1)} {(1.1,-0.1)} a0)" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "axis 'a0' is not defined in --styles. Defined axis: s::a0.") != null);
}

test "zsat draw with use of unknown namespace" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

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
    defer fixture.deinit();

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
    defer fixture.deinit();

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
    defer fixture.deinit();

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
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "gone::xyz" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "namespace 'gone' was requested") != null);
}

test "zsat draw saves a style into a new namespace" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "myns::e5", "--styles", "e5:{vec2d xy fixed last [c: blue]}" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);

    const content = try fixture.readContent();
    defer std.testing.allocator.free(content);
    try testing.expect(std.mem.indexOf(u8, content, "- myns\n") != null);
    // The colour is the only thing that is not a default, so it is the only
    // thing the saved line has to say.
    try testing.expect(std.mem.indexOf(u8, content, "e5:{[c:blue]}\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, test_config_content) != null);

    const use_argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "myns::e5" };
    var use_result = try cmdtest.run(io, .{ .argv = use_argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer use_result.deinit();

    try testing.expectEqual(@as(u8, 0), use_result.code);
    try testing.expect(std.mem.indexOf(u8, use_result.stdout, "c: blue") != null);
}

test "zsat draw saves an inherited style as a complete definition" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    // `e2` inherits through `e1` from `e0`, and the settings that only come
    // from a base have to travel with it: the namespace it lands in cannot
    // resolve `e0` or `e1`, so a saved line naming either would not load.
    const styles = "e0:{[l:30, c:red]}, e1: e0{[c:blue]}, e2: e1{}";
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "myns::e2", "--styles", styles };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);

    const content = try fixture.readContent();
    defer std.testing.allocator.free(content);

    // The whole chain is folded into one line that names no base, and the
    // settings still at their default are left out.
    try testing.expect(std.mem.indexOf(u8, content, "e2:{[l:30, c:blue]}\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "e2: e1\n") == null);

    // Loaded on its own from the saved namespace, it draws what it did before.
    const use_argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "myns::e2" };
    var use_result = try cmdtest.run(io, .{ .argv = use_argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer use_result.deinit();

    try testing.expectEqual(@as(u8, 0), use_result.code);
    try testing.expect(std.mem.indexOf(u8, use_result.stdout, "c: blue") != null);
    try testing.expect(std.mem.indexOf(u8, use_result.stdout, "l:30") != null);
}

test "zsat draw saves a style that came from another namespace" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    const config_with_style =
        \\- extra
        \\e3: e0 {[c: green]}
        \\
    ;
    var fixture = try writeTestConfigWith(config_with_style);
    defer fixture.deinit();

    // `e3` only exists as `x::e3` once the namespace is brought in, so the
    // saved line has to come from that definition rather than from whatever
    // else the key `e3` happens to name here.
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "myns::e3", "--styles", "use extra as x" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);

    const content = try fixture.readContent();
    defer std.testing.allocator.free(content);
    try testing.expect(std.mem.indexOf(u8, content, "e3:{[c:green]}\n") != null);
    try testing.expect(std.mem.indexOf(u8, content, "e3: e0\n") == null);
}

test "zsat draw saves a point style as a complete definition" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    const styles = "p0:{pt2d [sh:square, s:15, c: grey]}, p1: p0{[c:blue]}";
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "myns::p1", "--styles", styles };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);

    const content = try fixture.readContent();
    defer std.testing.allocator.free(content);
    try testing.expect(std.mem.indexOf(u8, content, "p1:{pt2d [sh:square, s:15, c:blue]}\n") != null);
}

test "zsat draw refuses --overwrite without --save" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    // `--overwrite experimental::a1` reads as if the key were the flag's value.
    // It is not: --overwrite is a switch, and draw takes no bare arguments, so
    // the key used to be dropped without a word, --save stayed empty, and the
    // whole draw ran and stored nothing.
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e5:{vec2d xy fixed last [c: blue]}", "--overwrite", "myns::e5" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "--overwrite was given without --save") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "--save NS::KEY --overwrite") != null);

    // Nothing was written, not even a namespace.
    const content = try fixture.readContent();
    defer std.testing.allocator.free(content);
    try testing.expectEqualStrings(test_config_content, content);
}

test "zsat draw saves an inherited axis as a complete definition" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    const config_with_axis =
        \\- sleek
        \\a0: {axis line:[c:grey, o:80, s:5], ticks:[pos:0,0.25,0.5, style:[c:lightgrey, h:12]], values:[vals:0,0.25,0.5, style:[o:80, s:25]]}
        \\
    ;
    var fixture = try writeTestConfigWith(config_with_axis);
    defer fixture.deinit();

    // `a1` inherits from sleek's `a0`. Saving it as it stands would leave a
    // reference to `a0`, which nothing in the target namespace can resolve.
    const styles = "use sleek as s, a1: s::a0{ticks:[pos:0,0.25,0.5,0.75,1], values:[vals:0,0.25,0.5,0.75,1.0]}, a2: a1{ticks:[style:[f:below]], values:[style:[f:below, a:-90, e:start]]}";
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "myns::a2", "--styles", styles };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);

    const content = try fixture.readContent();
    defer std.testing.allocator.free(content);

    // The whole chain, including the base that came from the config, is folded
    // in, and nothing refers to another definition any more.
    try testing.expect(std.mem.indexOf(u8, content, "a0{") == null);
    try testing.expect(std.mem.indexOf(u8, content, "a1{") == null);
    try testing.expect(std.mem.indexOf(u8, content, "s::") == null);
    try testing.expect(std.mem.indexOf(u8, content, "a2: {axis line:[c:grey, o:80, s:5], ticks:[pos:0,0.25,0.5,0.75,1, style:[c:lightgrey, h:12, f:below]], values:[vals:0,0.25,0.5,0.75,1, style:[o:80, s:25, f:below, a:-90, e:start]]}\n") != null);

    // Defaults are left out: no `c:black` for the value labels, and the
    // spacing of 2 that the default carries is not restated.
    try testing.expect(std.mem.indexOf(u8, content, "c:black") == null);
    try testing.expect(std.mem.indexOf(u8, content, "sp:2") == null);

    // The saved definition works on its own, from that namespace alone. Its
    // qualified name is what stayed the same in storage, so that is the name
    // to use here (an explicit alias would make it available bare too).
    const use_argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "myns::a2", "--outputs", "(out) -> (out, ft {(-0.1,0)} {(-0.1,1.1)} myns::a2)", "--panes", "p0:{size: 100x100}" };
    var use_result = try cmdtest.run(io, .{ .argv = use_argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer use_result.deinit();

    try testing.expectEqual(@as(u8, 0), use_result.code);
}

test "zsat draw saves an axis of only defaults as an empty body" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "myns::a7", "--styles", "a7:{axis line:[c:black, o:100, s:2]}" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);

    const content = try fixture.readContent();
    defer std.testing.allocator.free(content);
    // Every field was already the default, so the definition carries none.
    try testing.expect(std.mem.indexOf(u8, content, "a7: {}\n") != null);
}

test "zsat draw appends to a text value with + in outputs" {
    const filenames = [_][]const u8{ "text_append.png", "text_replace.png", "text_direct.png" };
    defer for (filenames) |f| std.Io.Dir.cwd().deleteFile(std.testing.io, f) catch {};

    const io = std.testing.io;
    const stdin_data = "[[1,1]]";
    const styles = "e0:{vec2d}, t0: {txt \"hello\" [c:red, s:20]}";

    var appended = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_append.png", "--styles", styles, "--outputs", "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0{+\" world\"})" }, .stdin = stdin_data });
    defer appended.deinit();

    var replaced = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_replace.png", "--styles", styles, "--outputs", "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0{\" world\"})" }, .stdin = stdin_data });
    defer replaced.deinit();

    var direct = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_direct.png", "--styles", "e0:{vec2d}, t0: {txt \"hello world\" [c:red, s:20]}", "--outputs", "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0)" }, .stdin = stdin_data });
    defer direct.deinit();

    try testing.expectEqual(@as(u8, 0), appended.code);
    try testing.expectEqual(@as(u8, 0), replaced.code);
    try testing.expectEqual(@as(u8, 0), direct.code);

    const a = try std.Io.Dir.cwd().readFileAlloc(io, "text_append.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(a);
    const r = try std.Io.Dir.cwd().readFileAlloc(io, "text_replace.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(r);
    const d = try std.Io.Dir.cwd().readFileAlloc(io, "text_direct.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(d);

    // "+" keeps what t0 was defined as, no "+" replaces it.
    try testing.expectEqualSlices(u8, d, a);
    try testing.expect(!std.mem.eql(u8, r, a));
}

test "zsat draw prepends to a text value with ^ in outputs" {
    const filenames = [_][]const u8{ "text_prepend.png", "text_prepend_replace.png", "text_prepend_direct.png" };
    defer for (filenames) |f| std.Io.Dir.cwd().deleteFile(std.testing.io, f) catch {};

    const io = std.testing.io;
    const stdin_data = "[[1,1]]";
    const styles = "e0:{vec2d}, t0: {txt \"hello\" [c:red, s:20]}";

    var prepended = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_prepend.png", "--styles", styles, "--outputs", "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0{^\"nice \"})" }, .stdin = stdin_data });
    defer prepended.deinit();

    var replaced = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_prepend_replace.png", "--styles", styles, "--outputs", "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0{\"nice \"})" }, .stdin = stdin_data });
    defer replaced.deinit();

    var direct = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_prepend_direct.png", "--styles", "e0:{vec2d}, t0: {txt \"nice hello\" [c:red, s:20]}", "--outputs", "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0)" }, .stdin = stdin_data });
    defer direct.deinit();

    try testing.expectEqual(@as(u8, 0), prepended.code);
    try testing.expectEqual(@as(u8, 0), replaced.code);
    try testing.expectEqual(@as(u8, 0), direct.code);

    const p = try std.Io.Dir.cwd().readFileAlloc(io, "text_prepend.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(p);
    const r = try std.Io.Dir.cwd().readFileAlloc(io, "text_prepend_replace.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(r);
    const d = try std.Io.Dir.cwd().readFileAlloc(io, "text_prepend_direct.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(d);

    // "^" keeps what t0 was defined as and puts the value in front of it, no
    // marker replaces it.
    try testing.expectEqualSlices(u8, d, p);
    try testing.expect(!std.mem.eql(u8, r, p));
}

test "zsat draw fills the {} holes of a text value from outputs" {
    const filenames = [_][]const u8{ "text_holes.png", "text_literal.png" };
    defer for (filenames) |f| std.Io.Dir.cwd().deleteFile(std.testing.io, f) catch {};

    const io = std.testing.io;

    var filled = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_holes.png", "--styles", "e0:{vec2d}, t0:{txt \"{} - {}\" [c:red, s:20]}", "--outputs", "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0{{\"1\", \"2\"}})" }, .stdin = "[[1,1]]" });
    defer filled.deinit();

    // The same text written out in full, holes and all.
    var literal = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_literal.png", "--styles", "e0:{vec2d}, t0:{txt \"1 - 2\" [c:red, s:20]}", "--outputs", "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0)" }, .stdin = "[[1,1]]" });
    defer literal.deinit();

    try testing.expectEqual(@as(u8, 0), filled.code);
    try testing.expectEqual(@as(u8, 0), literal.code);

    const a = try std.Io.Dir.cwd().readFileAlloc(io, "text_holes.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(a);
    const b = try std.Io.Dir.cwd().readFileAlloc(io, "text_literal.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(b);

    try testing.expectEqualSlices(u8, b, a);
}

test "zsat draw breaks a text value into lines on \n" {
    const filenames = [_][]const u8{ "text_lines.png", "text_one_line.png", "text_literal_n.png" };
    defer for (filenames) |f| std.Io.Dir.cwd().deleteFile(std.testing.io, f) catch {};

    const io = std.testing.io;
    const stdin_data = "[[1,1]]";
    const outputs = "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0)";

    var lines = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_lines.png", "--styles", "e0:{vec2d}, t0:{txt \"one\\ntwo\" [c:red, s:20]}", "--outputs", outputs }, .stdin = stdin_data });
    defer lines.deinit();

    // The same two words without the break, to tell the two apart.
    var one_line = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_one_line.png", "--styles", "e0:{vec2d}, t0:{txt \"onetwo\" [c:red, s:20]}", "--outputs", outputs }, .stdin = stdin_data });
    defer one_line.deinit();

    // A doubled backslash plots a `\n` of its own, on one line.
    var literal = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_literal_n.png", "--styles", "e0:{vec2d}, t0:{txt \"a\\\\nb\" [c:red, s:20]}", "--outputs", outputs }, .stdin = stdin_data });
    defer literal.deinit();

    try testing.expectEqual(@as(u8, 0), lines.code);
    try testing.expectEqual(@as(u8, 0), one_line.code);
    try testing.expectEqual(@as(u8, 0), literal.code);

    const a = try std.Io.Dir.cwd().readFileAlloc(io, "text_lines.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(a);
    const b = try std.Io.Dir.cwd().readFileAlloc(io, "text_one_line.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(b);
    const c = try std.Io.Dir.cwd().readFileAlloc(io, "text_literal_n.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(c);

    // A break moves the second line below the first, so this is not the one
    // line rendering, and a literal `\n` is text rather than a break.
    try testing.expect(!std.mem.eql(u8, b, a));
    try testing.expect(!std.mem.eql(u8, c, a));

    // Two lines of "one"/"two" against the literal "\n" of the third, which is
    // one line, so the first is taller than it.
    try testing.expect(!std.mem.eql(u8, c, b));
}

test "zsat draw lets a text value hold a quote of its own" {
    const filenames = [_][]const u8{ "text_quote.png", "text_quote_other.png" };
    defer for (filenames) |f| std.Io.Dir.cwd().deleteFile(std.testing.io, f) catch {};

    const io = std.testing.io;
    const stdin_data = "[[1,1]]";
    const outputs = "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0)";

    var quoted = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_quote.png", "--styles", "e0:{vec2d}, t0:{txt \"say \\\"hi\\\"\" [c:red, s:20]}", "--outputs", outputs }, .stdin = stdin_data });
    defer quoted.deinit();

    // The same words without the quotes, to tell the two apart.
    var plain = try cmdtest.run(io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "text_quote_other.png", "--styles", "e0:{vec2d}, t0:{txt \"say hi\" [c:red, s:20]}", "--outputs", outputs }, .stdin = stdin_data });
    defer plain.deinit();

    try testing.expectEqual(@as(u8, 0), quoted.code);
    try testing.expectEqual(@as(u8, 0), plain.code);

    const a = try std.Io.Dir.cwd().readFileAlloc(io, "text_quote.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(a);
    const b = try std.Io.Dir.cwd().readFileAlloc(io, "text_quote_other.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(b);

    // The quotes are drawn, so this is wider than the same words without them.
    try testing.expect(!std.mem.eql(u8, b, a));
}

test "zsat draw rejects a lone quote or trailing backslash in a text value" {
    defer cleanupOutputFiles();

    // A backslash before the closing quote is an escape, so it opens the value
    // rather than ending it, and a bare `"` leaves the value short of the rest.
    for ([_][]const u8{
        "e0:{vec2d}, t0:{txt \"say hi\\\" [c:red]}",
        "e0:{vec2d}, t0:{txt \"say hi\"\" [c:red]}",
    }) |styles| {
        const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", styles, "--outputs", "(out) -> ((a {(0,0)}) out, (a {(0.5,0.5)}) t0)" };
        var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]" });
        defer result.deinit();

        try testing.expect(result.code != 0);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "failed to parse styles"));
    }
}

test "zsat draw rejects a number of text values not matching the {} holes" {
    defer cleanupOutputFiles();
    const styles = "e0:{vec2d}, t0:{txt \"{} - {}\" [c:red, s:20]}";

    for ([_][]const u8{ "t0{{\"1\"}}", "t0{{\"1\", \"2\", \"3\"}}" }) |given| {
        const outputs = try std.fmt.allocPrint(std.testing.allocator, "(out) -> ((a {{(0,0)}}) out, (a {{(0.5,0.5)}}) {s})", .{given});
        defer std.testing.allocator.free(outputs);

        var argv = [_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", styles, "--outputs", outputs };
        var result = try cmdtest.run(std.testing.io, .{ .argv = &argv, .stdin = "[[1,1]]" });
        defer result.deinit();

        try testing.expect(result.code != 0);
        try testing.expect(std.mem.indexOf(u8, result.stderr, "'t0' is defined with 2 '{}' hole(s)") != null);
    }

    // A value for a definition that has no holes to fill is just as much a
    // mismatch as the other way round.
    const outputs = try std.fmt.allocPrint(std.testing.allocator, "(out) -> ((a {{(0,0)}}) out, (a {{(0.5,0.5)}}) {s})", .{"t0{{\"1\"}}"});
    defer std.testing.allocator.free(outputs);

    var argv = [_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0:{vec2d}, t0:{txt \"plain\" [c:red, s:20]}", "--outputs", outputs };
    var result = try cmdtest.run(std.testing.io, .{ .argv = &argv, .stdin = "[[1,1]]" });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "'t0' is defined with 0 '{}' hole(s)") != null);
}

test "zsat draw rejects a malformed list of text values" {
    defer cleanupOutputFiles();
    const styles = "e0:{vec2d}, t0:{txt \"{} - {}\" [c:red, s:20]}";

    for ([_][]const u8{ "t0{{}}", "t0{{\"1\",}}", "t0{{,}}" }) |given| {
        const outputs = try std.fmt.allocPrint(std.testing.allocator, "(out) -> ((a {{(0,0)}}) out, (a {{(0.5,0.5)}}) {s})", .{given});
        defer std.testing.allocator.free(outputs);

        var argv = [_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", styles, "--outputs", outputs };
        var result = try cmdtest.run(std.testing.io, .{ .argv = &argv, .stdin = "[[1,1]]" });
        defer result.deinit();

        try testing.expect(result.code != 0);
    }
}

test "zsat draw saves a style into an existing namespace" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "namespace1::t5", "--styles", "t5: {txt \"hi\" [c:green, s:12]}" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);

    const content = try fixture.readContent();
    defer std.testing.allocator.free(content);
    try testing.expect(std.mem.indexOf(u8, content, "t5: {txt \"hi\" [c:green, s:12]}") != null);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, content, "- namespace1"));
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, content, "- sleek"));
    try testing.expect(std.mem.indexOf(u8, content, "e0:{vec2d xy fixed last [l:25, c: red") != null);
}

test "zsat draw refuses to save over an existing key" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "namespace1::e0", "--styles", "e0:{vec2d xy fixed last [c: blue]}" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "key 'e0' is already defined in namespace 'namespace1'") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Use --overwrite to replace it") != null);

    const content = try fixture.readContent();
    defer std.testing.allocator.free(content);
    try testing.expectEqualStrings(test_config_content, content);
}

test "zsat draw overwrites a saved key with --overwrite" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "namespace1::e0", "--overwrite", "--styles", "e0:{vec2d xy fixed last [c: blue]}" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);

    const content = try fixture.readContent();
    defer std.testing.allocator.free(content);
    try testing.expectEqual(@as(usize, 1), std.mem.count(u8, content, "e0:{[c:blue]}"));
    try testing.expect(std.mem.indexOf(u8, content, "c: red") == null);
    try testing.expect(std.mem.indexOf(u8, content, "- namespace1") != null);
    try testing.expect(std.mem.indexOf(u8, content, "p1:{pt2d [sh:circle, s:30, c: blue]}") != null);
}

test "zsat draw refuses to save a key missing from --styles" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "myns::e9", "--styles", "e5:{vec2d xy fixed last [c: blue]}" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "store 'e9' in namespace 'myns'") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "not defined in --styles") != null);

    const content = try fixture.readContent();
    defer std.testing.allocator.free(content);
    try testing.expectEqualStrings(test_config_content, content);
}

test "zsat draw rejects a malformed --save target" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var fixture = try writeTestConfig();
    defer fixture.deinit();

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "myns", "--styles", "e5:{vec2d xy fixed last [c: blue]}" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &fixture.env_map });
    defer result.deinit();

    try testing.expect(result.code != 0);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "--save expects a 'NS::KEY' target") != null);
}

test "zsat draw saves into a config file that does not exist yet" {
    defer cleanupOutputFiles();
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const home = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{&tmp.sub_path});
    defer std.testing.allocator.free(home);
    var env_map: std.process.Environ.Map = .init(std.testing.allocator);
    defer env_map.deinit();
    try env_map.put("HOME", home);

    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--save", "fresh::e0", "--styles", "e0:{vec2d xy fixed last [c: blue]}" };
    var result = try cmdtest.run(io, .{ .argv = argv, .stdin = "[[2,1.1]]", .env_map = &env_map });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);

    const content = try tmp.dir.readFileAlloc(io, ".config/zsat/zsat.conf", std.testing.allocator, .limited(1024 * 1024));
    defer std.testing.allocator.free(content);
    try testing.expectEqualStrings("- fresh\ne0:{[c:blue]}\n", content);
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
    defer fixture.deinit();

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
    defer fixture.deinit();

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

test "zsat draw rotates datum mappings with fewer inputs" {
    const filenames = [_][]const u8{ "datum_a.png", "datum_b.png", "datum_c.png" };
    defer for (filenames) |f| std.Io.Dir.cwd().deleteFile(std.testing.io, f) catch {};

    const stdin_3 = "[[1,1]]\n[[-1,1]]\n[[-1,-1]]";
    const styles = "e0:{vec2d}, e1:{vec2d [c:red]}";
    const two_mappings = "(a, b) -> (a -> e0, b -> e1)";

    // Three vectors, two mappings: rows must use e0, e1, e0.
    var r1 = try cmdtest.run(std.testing.io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "datum_a.png", "--styles", styles, "--datum", two_mappings }, .stdin = stdin_3 });
    defer r1.deinit();

    // The same rotation, spelled out explicitly with three mappings.
    var r2 = try cmdtest.run(std.testing.io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "datum_b.png", "--styles", styles, "--datum", "(a, b, a) -> (a -> e0, b -> e1, a -> e0)" }, .stdin = stdin_3 });
    defer r2.deinit();

    // Only two vectors: the picture an "arity error / drop" approach would also produce.
    var r3 = try cmdtest.run(std.testing.io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "datum_c.png", "--styles", styles, "--datum", two_mappings }, .stdin = "[[1,1]]\n[[-1,1]]" });
    defer r3.deinit();

    try testing.expectEqual(@as(u8, 0), r1.code);
    try testing.expectEqual(@as(u8, 0), r2.code);
    try testing.expectEqual(@as(u8, 0), r3.code);

    const a = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "datum_a.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(a);
    const b = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "datum_b.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(b);
    const c = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "datum_c.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(c);

    // Rotation must reproduce the explicit spelling...
    try testing.expectEqualSlices(u8, a, b);
    // ...and must NOT drop the third vector.
    try testing.expect(!std.mem.eql(u8, a, c));
}

test "zsat draw associates inputs with styles in order when datum is omitted" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "e0:{vec2d}, e1:{vec2d [c:red]}" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]\n[[0,1]]" });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "--datum '(vec, vec) -> (vec -> e0, vec -> e1)'") != null);
}

test "zsat draw rotates the omitted datum over more inputs than styles" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "e0:{vec2d}, e1:{vec2d [c:red]}" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]\n[[-1,1]]\n[[-1,-1]]" });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "--datum '(vec, vec, vec) -> (vec -> e0, vec -> e1, vec -> e0)'") != null);
}

test "zsat draw omitted datum renders the same as the spelled out rotation" {
    const filenames = [_][]const u8{ "implicit_a.png", "implicit_b.png" };
    defer for (filenames) |f| std.Io.Dir.cwd().deleteFile(std.testing.io, f) catch {};

    const stdin_3 = "[[1,1]]\n[[-1,1]]\n[[-1,-1]]";
    const styles = "e0:{vec2d}, e1:{vec2d [c:red]}";

    var r1 = try cmdtest.run(std.testing.io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "implicit_a.png", "--styles", styles }, .stdin = stdin_3 });
    defer r1.deinit();

    var r2 = try cmdtest.run(std.testing.io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "implicit_b.png", "--styles", styles, "--datum", "(v0, v1, v2) -> (v0 -> e0, v1 -> e1, v2 -> e0)" }, .stdin = stdin_3 });
    defer r2.deinit();

    try testing.expectEqual(@as(u8, 0), r1.code);
    try testing.expectEqual(@as(u8, 0), r2.code);

    const a = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "implicit_a.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(a);
    const b = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "implicit_b.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(b);

    try testing.expectEqualSlices(u8, a, b);
}

test "zsat draw explicit datum overrides the implicit association" {
    const filenames = [_][]const u8{ "explicit_a.png", "explicit_b.png" };
    defer for (filenames) |f| std.Io.Dir.cwd().deleteFile(std.testing.io, f) catch {};

    const styles = "e0:{vec2d}, e1:{vec2d [c:red]}";
    const stdin_2 = "[[1,1]]\n[[0,1]]";

    var r1 = try cmdtest.run(std.testing.io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "explicit_a.png", "--styles", styles }, .stdin = stdin_2 });
    defer r1.deinit();

    // Reversing the association must not be silently ignored.
    var r2 = try cmdtest.run(std.testing.io, .{ .argv = &[_][]const u8{ zsat_path, "draw", "--out", "explicit_b.png", "--styles", styles, "--datum", "(v0, v1) -> (v0 -> e1, v1 -> e0)" }, .stdin = stdin_2 });
    defer r2.deinit();

    try testing.expectEqual(@as(u8, 0), r1.code);
    try testing.expectEqual(@as(u8, 0), r2.code);

    const a = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "explicit_a.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(a);
    const b = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "explicit_b.png", std.testing.allocator, .limited(1 << 20));
    defer std.testing.allocator.free(b);

    try testing.expect(!std.mem.eql(u8, a, b));
}

test "zsat draw omitted datum only associates styles matching the data shape" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "p0:{pt2d [sh:circle, s:20, c: aqua]}, e0:{vec2d [l:5, c: black]}" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "{(0,0)}\n[[1,0]]\n{(1,1)}" });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "--datum '(vec, vec, vec) -> (vec -> p0, vec -> e0, vec -> p0)'") != null);
}

test "zsat draw with invalid element in mapping" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e5)" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "--datum draws with style 'e5', which --styles does not define."));
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "Defined styles: e0, p0."));
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
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--styles 'e0:{vec2d xy fixed last [l:10, c: black, o: 100, e:none, j: none, d:none]}, p0:{pt2d"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "f:default, o:100]}'\n"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--datum '(vec) -> (vec -> e0)'"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--panes 'p0:{size: 600x600, border: none, background: {opacity: 100, color: white}}'"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--frames '(out) -> out -> p0'"));
}

test "zsat draw with debug and background" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e0)", "--panes", "p0:{background: [c:lightyellow, o:50], border: [w:10, c:red]}", "--frames", "(out) -> out -> p0" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[2,1.1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "--panes 'p0:{size: 600x600, border: {width: 10, opacity: 100, color: red}, background: {opacity: 50, color: lightyellow}}'"));

    const back_argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "--debug", "--styles", "e0:{vec2d}", "--datum", "(vec) -> (vec -> e0)", "--panes", "p0:{back: [c:black, o:10]}", "--frames", "(out) -> out -> p0" };
    var back_result = try cmdtest.run(std.testing.io, .{ .argv = back_argv, .stdin = "[[2,1.1]]" });
    defer back_result.deinit();

    try testing.expectEqual(@as(u8, 0), back_result.code);
    try testing.expect(std.mem.containsAtLeast(u8, back_result.stdout, 1, "background: {opacity: 10, color: black}"));
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
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Default: \"e0:{vec2d xy fixed last"));

    // --datum has no literal default: the association follows the defined styles
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Default: \"(vec) -> (vec -> e0)\"") == null);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "the first data input is associated with the firstly defined style"));
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

test "zsat draw hook comma draws the rotated output with the original" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-o", "(, (rotate [90 a (0% self)])) out" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw hook comma works with explicit outputs arrow" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-o", "(out) -> (, (rotate [90 a (0% self)])) out" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw train with draws both tine results" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-o", "(anchor {(2,0)} with anchor {(1,0)}) out" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw train comma middle draws rotate with scale" {
    defer cleanupOutputFiles();
    // (rotate [90 a (0% self)] , scale [[2,3]]) out
    // = the element rotated by 90 degrees together with the element scaled by (2,3).
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-o", "(rotate [90 a (0% self)] , scale [[2,3]]) out" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw train supports a hook as a tine" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-o", "(rotate [90 a (0% self)] with (, (anchor {(2,0)}))) out" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw train nested inside a train" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-o", "((anchor {(2,0)} with anchor {(0,0)}) with (anchor {(1,0)} with anchor {(0,0)})) out" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]" });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expectEqual(@as(u8, 0), result.code);
}

test "zsat draw rejects the removed on combinator" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "--out", "/dev/null", "-o", "(anchor {(1,0)} on anchor {(2,0)}) out" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv, .stdin = "[[1,1]]" });
    defer result.deinit();

    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "failed to parse outputs"));
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
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "background"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "zsat draw vec2d --help"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "zsat draw pt2d --help"));
}

test "zsat draw background --help" {
    defer cleanupOutputFiles();
    const argv = &[_][]const u8{ zsat_path, "draw", "background", "--help" };
    var result = try cmdtest.run(std.testing.io, .{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "background"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "back"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "c:NAME"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "o:N"));
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
