const std = @import("std");

pub const default_namespace = "sleek";
pub const default_style = "e0:{vec2d xy fixed last [l:10, c: black, o: 100, e:none, j: none, d: none]}";
pub const default_content =
    "- " ++ default_namespace ++ "\n" ++
    default_style ++ "\n" ++
    "t0: {txt \"txt\" [c:red, s:20]}\n" ++
    "a0: {axis line:[c:grey, o:80, s:5], ticks:[pos:0,0.5,..,3, style:[c:lightgrey, o:80, s:5, h:12, f:above]], values:[vals:0,1,2,3, style:[c:black, o:80, s:25, sp:4, f:above]]}\n" ++
    "p0:{pt2d [sh:square, s:15, c: grey]}\n" ++
    "b0: {border [w:25, c:lightgrey]}\n";

pub const Definition = struct {
    namespace: []const u8,
    name: []const u8,
    text: []const u8,
};

pub const Store = struct {
    allocator: std.mem.Allocator,
    content: []u8,
    definitions: []Definition,

    pub fn deinit(self: *Store) void {
        self.allocator.free(self.definitions);
        self.allocator.free(self.content);
        self.* = undefined;
    }

    pub fn get(self: Store, namespace: []const u8, name: []const u8) ?Definition {
        for (self.definitions) |definition| {
            if (std.mem.eql(u8, definition.namespace, namespace) and std.mem.eql(u8, definition.name, name)) {
                return definition;
            }
        }
        return null;
    }

    pub fn hasNamespace(self: Store, namespace: []const u8) bool {
        for (self.definitions) |definition| {
            if (std.mem.eql(u8, definition.namespace, namespace)) return true;
        }
        return false;
    }
};

pub fn definitionName(line: []const u8) ?[]const u8 {
    const boundary = std.mem.indexOfAny(u8, line, ":{") orelse return null;
    const name = std.mem.trim(u8, line[0..boundary], " \t");
    if (name.len == 0) return null;
    return name;
}

fn isNamespaceHeader(line: []const u8) bool {
    return line.len > 0 and line[0] == '-';
}

pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Store {
    const content = try allocator.dupe(u8, source);
    errdefer allocator.free(content);

    var definitions = std.ArrayList(Definition).empty;
    errdefer definitions.deinit(allocator);
    var current_namespace: ?[]const u8 = null;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;

        if (isNamespaceHeader(line)) {
            const namespace = std.mem.trim(u8, line[1..], " \t");
            if (namespace.len == 0) return error.InvalidConfig;
            current_namespace = namespace;
            continue;
        }

        const namespace = current_namespace orelse return error.InvalidConfig;
        const name = definitionName(line) orelse return error.InvalidConfig;
        var replaced = false;
        for (definitions.items) |*definition| {
            if (std.mem.eql(u8, definition.namespace, namespace) and std.mem.eql(u8, definition.name, name)) {
                definition.text = line;
                replaced = true;
                break;
            }
        }
        if (!replaced) {
            try definitions.append(allocator, .{ .namespace = namespace, .name = name, .text = line });
        }
    }

    return .{
        .allocator = allocator,
        .content = content,
        .definitions = try definitions.toOwnedSlice(allocator),
    };
}

pub fn load(allocator: std.mem.Allocator, io: std.Io, environ: std.process.Environ) !?Store {
    const home = environ.getAlloc(allocator, "HOME") catch |err| switch (err) {
        error.EnvironmentVariableMissing => environ.getAlloc(allocator, "USERPROFILE") catch |fallback_err| switch (fallback_err) {
            error.EnvironmentVariableMissing => return null,
            else => return fallback_err,
        },
        else => return err,
    };
    defer allocator.free(home);
    if (home.len == 0) return null;

    const config_dir = try std.fs.path.join(allocator, &.{ home, ".config", "zsat" });
    defer allocator.free(config_dir);
    const config_path = try std.fs.path.join(allocator, &.{ config_dir, "zsat.conf" });
    defer allocator.free(config_path);

    const content = std.Io.Dir.cwd().readFileAlloc(io, config_path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(content);
    return try parse(allocator, content);
}

test "default config" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    var store = try parse(arena.allocator(), default_content);
    defer store.deinit();

    try std.testing.expectEqual(@as(usize, 5), store.definitions.len);
    try std.testing.expectEqualStrings("e0", store.get(default_namespace, "e0").?.name);
    try std.testing.expectEqualStrings("p0", store.get(default_namespace, "p0").?.name);
    try std.testing.expectEqualStrings("b0", store.get(default_namespace, "b0").?.name);
}

test "config namespaces" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    const source =
        "- sleek\n" ++
        "e0:{vec2d}\n" ++
        "\n" ++
        "- namespace1\n" ++
        "e0:{pt2d [s:5]}\n";
    var store = try parse(arena.allocator(), source);
    defer store.deinit();

    try std.testing.expect(store.hasNamespace("sleek"));
    try std.testing.expect(store.hasNamespace("namespace1"));
    try std.testing.expectEqualStrings("e0:{pt2d [s:5]}", store.get("namespace1", "e0").?.text);
}

test "invalid config" {
    try std.testing.expectError(error.InvalidConfig, parse(std.testing.allocator, "e0:{vec2d}\n"));
}

test "duplicate definition keeps last" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();

    const source =
        "- sleek\n" ++
        "e0:{vec2d}\n" ++
        "e0:{pt2d [s:5]}\n" ++
        "\n" ++
        "- other\n" ++
        "e0:{vec2d [c: red]}\n";
    var store = try parse(arena.allocator(), source);
    defer store.deinit();

    try std.testing.expectEqual(@as(usize, 2), store.definitions.len);
    try std.testing.expectEqualStrings("e0:{pt2d [s:5]}", store.get("sleek", "e0").?.text);
    try std.testing.expectEqualStrings("e0:{vec2d [c: red]}", store.get("other", "e0").?.text);
}

test "definition name" {
    try std.testing.expectEqualStrings("e0", definitionName("e0:{vec2d}").?);
    try std.testing.expectEqualStrings("p1", definitionName("p1: p0{pt2d [s:5]}").?);
    try std.testing.expectEqualStrings("t0", definitionName("t0: {txt \"txt\" [c:red]}").?);
    try std.testing.expectEqualStrings("a0", definitionName("a0:{axis line:[c:grey]}").?);
    try std.testing.expect(definitionName("no-separator") == null);
}
