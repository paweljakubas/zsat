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

pub const ConfigPaths = struct {
    dir: []u8,
    path: []u8,

    pub fn deinit(self: *ConfigPaths, allocator: std.mem.Allocator) void {
        allocator.free(self.dir);
        allocator.free(self.path);
        self.* = undefined;
    }
};

fn resolvePaths(allocator: std.mem.Allocator, environ: std.process.Environ) !?ConfigPaths {
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
    errdefer allocator.free(config_dir);
    const config_path = try std.fs.path.join(allocator, &.{ config_dir, "zsat.conf" });
    errdefer allocator.free(config_path);

    return .{ .dir = config_dir, .path = config_path };
}

pub fn load(allocator: std.mem.Allocator, io: std.Io, environ: std.process.Environ) !?Store {
    var paths = (try resolvePaths(allocator, environ)) orelse return null;
    defer paths.deinit(allocator);

    const content = std.Io.Dir.cwd().readFileAlloc(io, paths.path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(content);
    return try parse(allocator, content);
}

fn singleLine(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (text) |c| {
        try out.append(allocator, switch (c) {
            '\n', '\r', '\t' => ' ',
            else => c,
        });
    }
    return out.toOwnedSlice(allocator);
}

fn upsertLine(allocator: std.mem.Allocator, content: []const u8, namespace: []const u8, name: []const u8, text: []const u8) ![]u8 {
    var kept: std.ArrayList([]const u8) = .empty;
    defer kept.deinit(allocator);

    var in_target = false;
    var target_found = false;
    var insert_at: usize = 0;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        const is_content_line = line.len > 0 and line[0] != '#';
        var drop = false;

        if (is_content_line and isNamespaceHeader(line)) {
            in_target = std.mem.eql(u8, std.mem.trim(u8, line[1..], " \t"), namespace);
            if (in_target) target_found = true;
        } else if (in_target and is_content_line) {
            if (definitionName(line)) |existing| {
                if (std.mem.eql(u8, existing, name)) drop = true;
            }
        }

        if (!drop) try kept.append(allocator, raw_line);
        if (in_target and is_content_line) insert_at = kept.items.len;
    }

    while (kept.items.len > 0 and std.mem.trim(u8, kept.items[kept.items.len - 1], " \t\r").len == 0) {
        _ = kept.pop();
    }
    insert_at = @min(insert_at, kept.items.len);

    const definition_line = try singleLine(allocator, text);
    defer allocator.free(definition_line);
    if (definition_line.len == 0) return error.InvalidConfig;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    if (target_found) {
        for (kept.items, 0..) |line, index| {
            if (index == insert_at) {
                try out.appendSlice(allocator, definition_line);
                try out.append(allocator, '\n');
            }
            try out.appendSlice(allocator, line);
            try out.append(allocator, '\n');
        }
        if (insert_at == kept.items.len) {
            try out.appendSlice(allocator, definition_line);
            try out.append(allocator, '\n');
        }
    } else {
        for (kept.items) |line| {
            try out.appendSlice(allocator, line);
            try out.append(allocator, '\n');
        }
        if (kept.items.len > 0) try out.append(allocator, '\n');
        try out.appendSlice(allocator, "- ");
        try out.appendSlice(allocator, namespace);
        try out.append(allocator, '\n');
        try out.appendSlice(allocator, definition_line);
        try out.append(allocator, '\n');
    }
    return out.toOwnedSlice(allocator);
}

pub fn saveDefinition(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ: std.process.Environ,
    namespace: []const u8,
    name: []const u8,
    text: []const u8,
    overwrite: bool,
) !void {
    var paths = (try resolvePaths(allocator, environ)) orelse return error.HomeDirectoryMissing;
    defer paths.deinit(allocator);
    return saveDefinitionAt(allocator, io, paths.dir, paths.path, namespace, name, text, overwrite);
}

fn saveDefinitionAt(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: []const u8,
    path: []const u8,
    namespace: []const u8,
    name: []const u8,
    text: []const u8,
    overwrite: bool,
) !void {
    const trimmed_namespace = std.mem.trim(u8, namespace, " \t\r");
    const trimmed_name = std.mem.trim(u8, name, " \t\r");
    if (trimmed_namespace.len == 0 or trimmed_name.len == 0) return error.InvalidConfig;
    if (isNamespaceHeader(trimmed_name) or isNamespaceHeader(trimmed_namespace)) return error.InvalidConfig;

    const cwd = std.Io.Dir.cwd();
    const existing = cwd.readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    const content: []u8 = existing orelse try allocator.alloc(u8, 0);
    defer allocator.free(content);

    var store = try parse(allocator, content);
    defer store.deinit();
    if (!overwrite and store.get(trimmed_namespace, trimmed_name) != null) return error.KeyAlreadyExists;

    const updated = try upsertLine(allocator, content, trimmed_namespace, trimmed_name, text);
    defer allocator.free(updated);

    try cwd.createDirPath(io, dir);
    const file = try cwd.createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    try file.writeStreamingAll(io, updated);
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

const SaveFixture = struct {
    tmp: std.testing.TmpDir,
    dir_path: []u8,
    file_path: []u8,

    fn deinit(self: *SaveFixture, allocator: std.mem.Allocator) void {
        allocator.free(self.file_path);
        allocator.free(self.dir_path);
        self.tmp.cleanup();
    }

    fn read(self: *SaveFixture, io: std.Io, allocator: std.mem.Allocator) ![]u8 {
        return self.tmp.dir.readFileAlloc(io, ".config/zsat/zsat.conf", allocator, .limited(1024 * 1024));
    }

    fn save(self: *SaveFixture, allocator: std.mem.Allocator, io: std.Io, namespace: []const u8, name: []const u8, text: []const u8, overwrite: bool) !void {
        return saveDefinitionAt(allocator, io, self.dir_path, self.file_path, namespace, name, text, overwrite);
    }
};

fn saveFixture(allocator: std.mem.Allocator, init_content: ?[]const u8) !SaveFixture {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    errdefer tmp.cleanup();
    try tmp.dir.createDirPath(io, ".config/zsat");
    if (init_content) |content| {
        try tmp.dir.writeFile(io, .{ .sub_path = ".config/zsat/zsat.conf", .data = content });
    }

    const home = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}", .{&tmp.sub_path});
    const dir_path = try std.fs.path.join(allocator, &.{ home, ".config", "zsat" });
    const file_path = try std.fs.path.join(allocator, &.{ dir_path, "zsat.conf" });

    return .{ .tmp = tmp, .dir_path = dir_path, .file_path = file_path };
}

test "save definition creates a missing namespace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;

    var fixture = try saveFixture(alloc, null);
    defer fixture.deinit(alloc);

    try fixture.save(alloc, io, "mine", "e5", "e5:{vec2d [c: red]}", false);

    const content = try fixture.read(io, alloc);
    var store = try parse(alloc, content);
    defer store.deinit();
    try std.testing.expect(store.hasNamespace("mine"));
    try std.testing.expectEqualStrings("e5:{vec2d [c: red]}", store.get("mine", "e5").?.text);
}

test "save definition creates the config file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const home = try std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}", .{&tmp.sub_path});
    const dir_path = try std.fs.path.join(alloc, &.{ home, ".config", "zsat" });
    const file_path = try std.fs.path.join(alloc, &.{ dir_path, "zsat.conf" });

    try saveDefinitionAt(alloc, io, dir_path, file_path, "mine", "e0", "e0:{vec2d [c: red]}", false);

    const content = try tmp.dir.readFileAlloc(io, ".config/zsat/zsat.conf", alloc, .limited(1024 * 1024));
    var store = try parse(alloc, content);
    defer store.deinit();
    try std.testing.expectEqualStrings("e0:{vec2d [c: red]}", store.get("mine", "e0").?.text);
}

test "save definition rejects an existing key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;

    var fixture = try saveFixture(alloc, "- mine\ne0:{vec2d [c: red]}\n");
    defer fixture.deinit(alloc);

    try std.testing.expectError(error.KeyAlreadyExists, fixture.save(alloc, io, "mine", "e0", "e0:{vec2d [c: blue]}", false));

    const content = try fixture.read(io, alloc);
    try std.testing.expectEqualStrings("- mine\ne0:{vec2d [c: red]}\n", content);
}

test "save definition overwrites an existing key in place" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;

    var fixture = try saveFixture(alloc,
        \\# my config
        \\- mine
        \\e0:{vec2d [c: red]}
        \\
        \\- other
        \\e0:{pt2d [s:5]}
        \\
    );
    defer fixture.deinit(alloc);

    try fixture.save(alloc, io, "mine", "e0", "e0:{vec2d [c: blue]}", true);

    const content = try fixture.read(io, alloc);
    var store = try parse(alloc, content);
    defer store.deinit();
    try std.testing.expectEqualStrings("e0:{vec2d [c: blue]}", store.get("mine", "e0").?.text);
    try std.testing.expectEqualStrings("e0:{pt2d [s:5]}", store.get("other", "e0").?.text);
    try std.testing.expectEqual(@as(usize, 2), store.definitions.len);
    try std.testing.expect(std.mem.indexOf(u8, content, "# my config") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "e0:{vec2d [c: red]}") == null);
}

test "save definition appends to an existing namespace" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;

    var fixture = try saveFixture(alloc, "- mine\ne0:{vec2d [c: red]}\n\n- other\ne0:{pt2d [s:5]}\n");
    defer fixture.deinit(alloc);

    try fixture.save(alloc, io, "mine", "t1", "t1: {txt \"hi\" [c: blue]}", false);

    const content = try fixture.read(io, alloc);
    var store = try parse(alloc, content);
    defer store.deinit();
    try std.testing.expectEqualStrings("t1: {txt \"hi\" [c: blue]}", store.get("mine", "t1").?.text);
    try std.testing.expectEqualStrings("e0:{vec2d [c: red]}", store.get("mine", "e0").?.text);
    try std.testing.expectEqualStrings("e0:{pt2d [s:5]}", store.get("other", "e0").?.text);
}

test "save definition validates namespace and key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const io = std.testing.io;

    var fixture = try saveFixture(alloc, null);
    defer fixture.deinit(alloc);

    try std.testing.expectError(error.InvalidConfig, fixture.save(alloc, io, "", "e0", "e0:{vec2d}", false));
    try std.testing.expectError(error.InvalidConfig, fixture.save(alloc, io, "mine", "", "e0:{vec2d}", false));
    try std.testing.expectError(error.InvalidConfig, fixture.save(alloc, io, "mine", "  ", "e0:{vec2d}", false));
    try std.testing.expectError(error.InvalidConfig, fixture.save(alloc, io, "mine", "- mine", "e0:{vec2d}", false));
}
