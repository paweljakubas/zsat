const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const zli = @import("zli");
const z2d = @import("z2d");
const zigimg = @import("zigimg");
const mecha = @import("mecha");
const Styles = @import("draw/styles.zig");
const Inputs = @import("draw/inputs.zig");
const Outputs = @import("draw/outputs.zig");
const Datum = @import("draw/datum.zig");
const Frames = @import("draw/frames.zig");
const Panes = @import("draw/panes.zig");
const Border = @import("draw/border.zig");
const Text = @import("draw/text.zig");
const Axis = @import("draw/axis.zig");
const common = @import("draw/common.zig");
const config = @import("config");

const Plot = @import("plot");
const draw_help = @import("draw_help.zig");

pub const ParsedData = struct {
    styles: []const Styles.Style,
    borders: []const Border.BorderDefinition,
    texts: []const Text.TextDefinition,
    textOverlays: []const Text.Text,
    axes: []const Axis.AxisDefinition,
    axisOverlays: []const Axis.AxisOverlay,
    inputs: Inputs.Inputs,
    datum: Datum.DataElementValidated,
    outputs: Outputs.OutputsValidated,
    panes: []const Panes.Pane,
    frames: Frames.OutputPaneValidated,
};

const DrawElement = union(enum) {
    style: Styles.Style,
    point_style: Styles.PointStyleDefinition,
    border: Border.BorderDefinition,
    text: Text.TextDefinition,
    axis: Axis.AxisDefinition,
};

const drawElementParser = mecha.oneOf(.{
    Styles.pointStyleParser.map(struct {
        fn toElem(s: Styles.PointStyleDefinition) mecha.ConvertError!DrawElement {
            return DrawElement{ .point_style = s };
        }
    }.toElem),
    Styles.styleParser.map(struct {
        fn toElem(s: Styles.Style) mecha.ConvertError!DrawElement {
            return DrawElement{ .style = s };
        }
    }.toElem),
    Border.borderDefParser.map(struct {
        fn toElem(b: Border.BorderDefinition) mecha.ConvertError!DrawElement {
            return DrawElement{ .border = b };
        }
    }.toElem),
    Text.textDefParser.map(struct {
        fn toElem(t: Text.TextDefinition) mecha.ConvertError!DrawElement {
            return DrawElement{ .text = t };
        }
    }.toElem),
    Axis.axisDefParser.map(struct {
        fn toElem(a: Axis.AxisDefinition) mecha.ConvertError!DrawElement {
            return DrawElement{ .axis = a };
        }
    }.toElem),
});

const RawDefinition = struct {
    name: []const u8,
    text: []const u8,
};

const QualifiedReference = struct {
    namespace: []const u8,
    name: []const u8,
};

const ImportDirective = struct {
    namespace: []const u8,
    alias: ?[]const u8 = null,
};

const ParsedStyleInput = struct {
    imports: []ImportDirective,
    rest: []const u8,
};

// Definitions gathered for one draw call, together with the names in the order
// the user spelled them out. The two differ whenever definitions are merged in
// from the default namespace without being asked for by name: those stay
// referenceable but take no part in the implicit datum association.
const CollectedStyles = struct {
    definitions: []RawDefinition,
    names: [][]const u8,
};

fn skipSeparators(value: []const u8, index: usize) usize {
    var cursor = index;
    while (cursor < value.len) : (cursor += 1) {
        if (std.ascii.isWhitespace(value[cursor]) or value[cursor] == ',') continue;
        break;
    }
    return cursor;
}

fn matchesWord(value: []const u8, index: usize, word: []const u8) bool {
    if (!std.mem.startsWith(u8, value[index..], word)) return false;
    const end = index + word.len;
    if (end == value.len) return true;
    const next = value[end];
    return std.ascii.isWhitespace(next) or next == ',';
}

fn readNameToken(value: []const u8, index: usize) usize {
    var cursor = index;
    while (cursor < value.len) : (cursor += 1) {
        const character = value[cursor];
        if (std.ascii.isWhitespace(character) or character == ',' or character == ':') break;
    }
    return cursor;
}

fn parseImportDirectives(alloc: std.mem.Allocator, styles_str: []const u8) !ParsedStyleInput {
    var imports: std.ArrayList(ImportDirective) = .empty;
    var index: usize = 0;
    while (true) {
        index = skipSeparators(styles_str, index);
        if (!matchesWord(styles_str, index, "use")) break;

        var cursor = skipSeparators(styles_str, index + "use".len);
        const namespace_start = cursor;
        cursor = readNameToken(styles_str, cursor);
        if (cursor == namespace_start) return error.ParseStylesFailed;
        const namespace = styles_str[namespace_start..cursor];

        var alias: ?[]const u8 = null;
        const after_namespace = cursor;
        cursor = skipSeparators(styles_str, cursor);
        if (matchesWord(styles_str, cursor, "as")) {
            cursor = skipSeparators(styles_str, cursor + "as".len);
            const alias_start = cursor;
            cursor = readNameToken(styles_str, cursor);
            if (cursor == alias_start) return error.ParseStylesFailed;
            alias = styles_str[alias_start..cursor];
        } else {
            cursor = after_namespace;
        }

        try imports.append(alloc, .{ .namespace = namespace, .alias = alias });
        index = cursor;
    }

    return .{
        .imports = try imports.toOwnedSlice(alloc),
        .rest = std.mem.trim(u8, styles_str[index..], " \t\r\n,"),
    };
}

fn splitStyleInput(alloc: std.mem.Allocator, input: []const u8) ![][]const u8 {
    var parts = std.ArrayList([]const u8).empty;
    var start: usize = 0;
    var depth: usize = 0;
    var quoted = false;
    var escaped = false;

    for (input, 0..) |character, index| {
        if (quoted) {
            if (escaped) {
                escaped = false;
            } else if (character == '\\') {
                escaped = true;
            } else if (character == '"') {
                quoted = false;
            }
            continue;
        }

        switch (character) {
            '"' => quoted = true,
            '{', '[', '(' => depth += 1,
            '}', ']', ')' => {
                if (depth > 0) depth -= 1;
            },
            ',' => if (depth == 0) {
                const part = std.mem.trim(u8, input[start..index], " \t\r\n");
                if (part.len > 0) try parts.append(alloc, part);
                start = index + 1;
            },
            else => {},
        }
    }

    const part = std.mem.trim(u8, input[start..], " \t\r\n");
    if (part.len > 0) try parts.append(alloc, part);
    return parts.toOwnedSlice(alloc);
}

fn parseQualifiedReference(value: []const u8) ?QualifiedReference {
    const separator = std.mem.indexOf(u8, value, "::") orelse return null;
    if (std.mem.indexOf(u8, value[separator + 2 ..], "::") != null) return null;
    const namespace = std.mem.trim(u8, value[0..separator], " \t\r\n");
    const name = std.mem.trim(u8, value[separator + 2 ..], " \t\r\n");
    if (namespace.len == 0 or name.len == 0) return null;
    for (namespace) |character| {
        if (std.ascii.isWhitespace(character) or character == ':' or character == '{' or character == '}') return null;
    }
    for (name) |character| {
        if (std.ascii.isWhitespace(character) or character == ':' or character == '{' or character == '}') return null;
    }
    return .{ .namespace = namespace, .name = name };
}

fn upsertRawDefinition(alloc: std.mem.Allocator, definitions: *std.ArrayList(RawDefinition), name: []const u8, text: []const u8) !void {
    for (definitions.items) |*definition| {
        if (std.mem.eql(u8, definition.name, name)) {
            definition.text = text;
            return;
        }
    }
    try definitions.append(alloc, .{ .name = name, .text = text });
}

fn addNamespaceDefinitions(alloc: std.mem.Allocator, definitions: *std.ArrayList(RawDefinition), named: ?*std.ArrayList([]const u8), store: *const config.Store, namespace: []const u8) !bool {
    var found = false;
    for (store.definitions) |definition| {
        if (!std.mem.eql(u8, definition.namespace, namespace)) continue;
        found = true;
        try upsertRawDefinition(alloc, definitions, definition.name, definition.text);
        if (named) |list| try list.append(alloc, definition.name);
    }
    return found;
}

fn referencedBaseName(name: []const u8, text: []const u8) ?[]const u8 {
    if (text.len < name.len) return null;
    var rest = std.mem.trim(u8, text[name.len..], " \t\r\n");
    if (rest.len > 0 and rest[0] == ':') {
        rest = std.mem.trim(u8, rest[1..], " \t\r\n");
    }
    const end = std.mem.indexOfAny(u8, rest, " \t\r\n{[") orelse rest.len;
    const token = rest[0..end];
    if (token.len < 2 or (token[0] != 'e' and token[0] != 'p')) return null;
    for (token[1..]) |character| {
        if (!std.ascii.isDigit(character)) return null;
    }
    return token;
}

/// The definition a `--styles` item builds on, e.g. the `s::a0` of
/// `a0: s::a0{...}`. Only the token right after the item's own name and its
/// colon can be one, and only a qualified name counts, because a bare base is
/// either defined alongside or already in play.
fn inlinePartBaseReference(part: []const u8, name: []const u8) ?QualifiedReference {
    if (part.len <= name.len) return null;
    var rest = std.mem.trim(u8, part[name.len..], " \t\r\n");
    if (rest.len > 0 and rest[0] == ':') rest = std.mem.trim(u8, rest[1..], " \t\r\n");
    const end = std.mem.indexOfAny(u8, rest, " \t\r\n{[") orelse rest.len;
    return parseQualifiedReference(rest[0..end]);
}

fn prefixedName(alloc: std.mem.Allocator, prefix: ?[]const u8, name: []const u8) ![]const u8 {
    if (prefix) |value| return try std.fmt.allocPrint(alloc, "{s}::{s}", .{ value, name });
    return name;
}

fn addReferencedDefinition(alloc: std.mem.Allocator, definitions: *std.ArrayList(RawDefinition), store: *const config.Store, default_store: *const config.Store, visited: *std.ArrayList(QualifiedReference), namespace: []const u8, name: []const u8, prefix: ?[]const u8) !void {
    for (visited.items) |reference| {
        if (std.mem.eql(u8, reference.namespace, namespace) and std.mem.eql(u8, reference.name, name)) return;
    }
    try visited.append(alloc, .{ .namespace = namespace, .name = name });

    const definition = store.get(namespace, name) orelse return reportMissingDefinition(alloc, name, namespace, prefix, store);
    if (referencedBaseName(definition.name, definition.text)) |base| {
        if (store.get(namespace, base) != null) {
            try addReferencedDefinition(alloc, definitions, store, default_store, visited, namespace, base, prefix);
        } else if (!std.mem.eql(u8, namespace, config.default_namespace) and store.get(config.default_namespace, base) != null) {
            try addReferencedDefinition(alloc, definitions, store, default_store, visited, config.default_namespace, base, prefix);
        }
    }
    try upsertRawDefinition(alloc, definitions, try prefixedName(alloc, prefix, definition.name), definition.text);
}

fn namespaceStore(store: ?*const config.Store, default_store: *const config.Store, namespace: []const u8) *const config.Store {
    if (store) |loaded| {
        if (loaded.hasNamespace(namespace)) return loaded;
        if (default_store.hasNamespace(namespace)) return default_store;
        return loaded;
    }
    return default_store;
}

fn findImportAlias(imports: []const ImportDirective, namespace: []const u8) ?ImportDirective {
    for (imports) |directive| {
        const alias = directive.alias orelse continue;
        if (std.mem.eql(u8, alias, namespace)) return directive;
    }
    return null;
}

threadlocal var namespaceErrorDetail: ?[]const u8 = null;
threadlocal var definitionErrorDetail: ?[]const u8 = null;
threadlocal var saveErrorDetail: ?[]const u8 = null;
threadlocal var referenceErrorDetail: ?[]const u8 = null;

/// Reports which definitions of a kind `--styles` actually offers, so that a
/// reference written the wrong way round says so. A definition is known by
/// exactly the name it was collected under: `use ns` and `ns::key` collect under
/// the bare name, `use ns as p` collects under `p::key`.
fn reportUnknownReference(alloc: std.mem.Allocator, kind: []const u8, missing: []const u8, names: []const []const u8) error{OutOfMemory}!void {
    if (names.len == 0) {
        referenceErrorDetail = try std.fmt.allocPrint(alloc, "Error: {s} '{s}' is not defined in --styles. No {s} was defined.", .{ kind, missing, kind });
        return;
    }
    const joined = try std.mem.join(alloc, ", ", names);
    referenceErrorDetail = try std.fmt.allocPrint(alloc, "Error: {s} '{s}' is not defined in --styles. Defined {s}: {s}.", .{ kind, missing, kind, joined });
}

fn namesOf(alloc: std.mem.Allocator, comptime T: type, defs: []const T, comptime field: []const u8) ![][]const u8 {
    const names = try alloc.alloc([]const u8, defs.len);
    for (defs, 0..) |def, i| names[i] = @field(def, field);
    return names;
}

fn availableNamespaces(alloc: std.mem.Allocator, store: ?*const config.Store, default_store: *const config.Store) ![][]const u8 {
    const source: *const config.Store = if (store) |loaded| blk: {
        if (loaded.definitions.len == 0) break :blk default_store;
        break :blk loaded;
    } else default_store;

    var names: std.ArrayList([]const u8) = .empty;
    for (source.definitions) |definition| {
        var already_listed = false;
        for (names.items) |name| {
            if (std.mem.eql(u8, name, definition.namespace)) already_listed = true;
        }
        if (!already_listed) try names.append(alloc, definition.namespace);
    }
    return names.toOwnedSlice(alloc);
}

fn reportMissingNamespace(alloc: std.mem.Allocator, missing: []const u8, store: ?*const config.Store, default_store: *const config.Store) (error{NamespaceNotFound} || error{OutOfMemory}) {
    const available = try availableNamespaces(alloc, store, default_store);
    defer alloc.free(available);

    if (store == null) {
        namespaceErrorDetail = try std.fmt.allocPrint(alloc, "Error: namespace '{s}' was requested, but ~/.config/zsat/zsat.conf does not exist. Only the built-in namespace '{s}' is available.", .{ missing, config.default_namespace });
        return error.NamespaceNotFound;
    }

    if (available.len == 0) {
        namespaceErrorDetail = try std.fmt.allocPrint(alloc, "Error: namespace '{s}' was requested, but no namespaces are defined in ~/.config/zsat/zsat.conf.", .{missing});
        return error.NamespaceNotFound;
    }

    const joined = try std.mem.join(alloc, ", ", available);
    namespaceErrorDetail = try std.fmt.allocPrint(alloc, "Error: namespace '{s}' was requested, but it is not defined in ~/.config/zsat/zsat.conf. Defined namespaces: {s}.", .{ missing, joined });
    return error.NamespaceNotFound;
}

fn namespaceDefinitionNames(alloc: std.mem.Allocator, store: *const config.Store, namespace: []const u8) ![][]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    for (store.definitions) |definition| {
        if (!std.mem.eql(u8, definition.namespace, namespace)) continue;
        var already_listed = false;
        for (names.items) |name| {
            if (std.mem.eql(u8, name, definition.name)) already_listed = true;
        }
        if (!already_listed) try names.append(alloc, definition.name);
    }
    return names.toOwnedSlice(alloc);
}

fn reportMissingDefinition(alloc: std.mem.Allocator, missing: []const u8, namespace: []const u8, prefix: ?[]const u8, store: *const config.Store) (error{StyleReferenceNotFound} || error{OutOfMemory}) {
    const available = try namespaceDefinitionNames(alloc, store, namespace);
    defer alloc.free(available);

    // Only an import alias remaps the namespace: `use work as w` reports that
    // `work` came in under another name. A direct `ns::key` reference keeps its
    // namespace (so does a plain `use ns`), and there is nothing to add then.
    if (prefix) |alias| if (!std.mem.eql(u8, alias, namespace)) {
        namespaceErrorDetail = try std.fmt.allocPrint(alloc, "Error: key '{s}' is not present in namespace '{s}' (imported as '{s}').", .{ missing, namespace, alias });
    } else {
        namespaceErrorDetail = try std.fmt.allocPrint(alloc, "Error: key '{s}' is not present in namespace '{s}'.", .{ missing, namespace });
    } else {
        namespaceErrorDetail = try std.fmt.allocPrint(alloc, "Error: key '{s}' is not present in namespace '{s}'.", .{ missing, namespace });
    }

    if (available.len == 0) {
        definitionErrorDetail = try std.fmt.allocPrint(alloc, "{s} That namespace is currently empty.", .{namespaceErrorDetail.?});
        return error.StyleReferenceNotFound;
    }

    const joined = try std.mem.join(alloc, ", ", available);
    definitionErrorDetail = try std.fmt.allocPrint(alloc, "{s} Defined keys: {s}.", .{ namespaceErrorDetail.?, joined });
    return error.StyleReferenceNotFound;
}

threadlocal var stylesErrorDetail: ?[]const u8 = null;

/// The bare key a `--styles` item spells on its own, e.g. the `e0` of
/// `use sleek, e0`. A namespace-qualified name, an inline definition, or
/// anything that is not a definition name is not one, so this says nothing
/// about those and the caller falls through to its own handling.
fn bareDefinitionKey(arena: std.mem.Allocator, part: []const u8) ?[]const u8 {
    const item = std.mem.trim(u8, part, " \t");
    // A qualifier belongs to the `ns::key` form, which is handled elsewhere and
    // must keep its namespace to be found.
    if (item.len == 0 or std.mem.indexOf(u8, item, "::") != null) return null;
    return matchBareKey(arena, common.lineStyleRefParser, item) orelse
        matchBareKey(arena, common.pointStyleRefParser, item) orelse
        matchBareKey(arena, common.textRefParser, item) orelse
        matchBareKey(arena, common.borderRefParser, item) orelse
        matchBareKey(arena, common.axisRefParser, item);
}

/// `anytype` because the five reference parsers are five unrelated types; what
/// they have in common is that each turns its own letter into a bare key.
fn matchBareKey(arena: std.mem.Allocator, parser: anytype, item: []const u8) ?[]const u8 {
    const r = parser.parse(arena, item) catch return null;
    if (r.index != item.len) return null;
    return switch (r.value) {
        .ok => |name| name,
        .err => null,
    };
}

/// Explains a `--styles` key that no definition answers to, listing the names
/// that would. An aliased import is the usual reason: the definition is there,
/// but under its prefix.
fn reportUnnamedDefinition(alloc: std.mem.Allocator, key: []const u8, definitions: []const RawDefinition) error{OutOfMemory}!void {
    if (definitions.len == 0) {
        stylesErrorDetail = try std.fmt.allocPrint(alloc, "Error: '{s}' names no definition. Define it, e.g. '{s}:{{...}}', or bring a namespace in with 'use ns' first.", .{ key, key });
        return;
    }
    var names: std.ArrayList([]const u8) = .empty;
    for (definitions) |definition| try names.append(alloc, definition.name);
    stylesErrorDetail = try std.fmt.allocPrint(alloc, "Error: '{s}' names no definition in --styles. Defined: {s}.", .{ key, try std.mem.join(alloc, ", ", names.items) });
}

fn findRawDefinition(definitions: []const RawDefinition, name: []const u8) ?RawDefinition {
    for (definitions) |definition| {
        if (std.mem.eql(u8, definition.name, name)) return definition;
    }
    return null;
}

/// The same lookup, but also accepting a definition that reached us under a
/// namespace alias, so `use sleek as s, s::a1` can be saved as `myns::a1`. The
/// whole definition comes back rather than just its text: what the resolver
/// knows a definition by is the name it was collected under, which for such a
/// definition is the alias and not the key being saved.
fn findRawDefinitionByBaseName(definitions: []const RawDefinition, name: []const u8) ?RawDefinition {
    if (findRawDefinition(definitions, name)) |definition| return definition;
    for (definitions) |definition| {
        const qualified = std.mem.lastIndexOf(u8, definition.name, "::") orelse continue;
        if (std.mem.eql(u8, definition.name[qualified + 2 ..], name)) return definition;
    }
    return null;
}

/// Whether a name is an axis key, i.e. `a` followed by digits.
fn isAxisName(name: []const u8) bool {
    if (name.len < 2 or name[0] != 'a') return false;
    for (name[1..]) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

/// Whether a name is a line or point style key, i.e. `eN` or `pN`. A number at
/// or above the point-style offset counts as a `pN`.
fn isStyleName(name: []const u8) bool {
    if (name.len < 2 or (name[0] != 'e' and name[0] != 'p')) return false;
    for (name[1..]) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

/// The text to store for a saved definition. A definition kept in a namespace
/// has to stand on its own, because nothing outside that namespace can be
/// relied on: only the built-in defaults are always in reach. A definition
/// written as `a1: a0{...}` therefore cannot be stored as it stands, so it is
/// expanded into a complete definition first, with the base folded in and every
/// default left out. Definitions with nothing to inherit from are stored as the
/// user spelled them.
fn definitionTextForSave(
    alloc: std.mem.Allocator,
    axes: []const Axis.AxisDefinition,
    styles: []const Styles.Style,
    target_name: []const u8,
    raw: RawDefinition,
) ![]const u8 {
    // What the resolver collected the definition under, which is the name to
    // look it up by. For `use sleek as s, s::a1` saved as `myns::a1` that is
    // `s::a1`, and looking up `a1` instead would find whichever definition the
    // key happens to carry in the current --styles, which need not be this one.
    const collected_name = raw.name;
    const raw_text = raw.text;
    if (isAxisName(target_name)) {
        const resolved = Axis.resolveAxes(alloc, axes) catch |err| switch (err) {
            error.AxisBaseInvalid => {
                saveErrorDetail = Axis.axisBaseErrorDetail();
                return error.AxisBaseInvalid;
            },
            else => return err,
        };
        for (resolved) |axis| {
            if (std.mem.eql(u8, axis.name, collected_name)) return Axis.serializeAxis(alloc, target_name, axis.axis);
        }
        return raw_text;
    }

    if (isStyleName(target_name)) {
        const resolved = try Styles.resolveStyles(alloc, styles);
        for (resolved) |style| {
            const collected = style.name orelse continue;
            if (std.mem.eql(u8, collected, collected_name)) return Styles.serializeStyleMinimal(alloc, target_name, style);
        }
        return raw_text;
    }

    return raw_text;
}

fn saveToConfig(alloc: std.mem.Allocator, ctx: zli.CommandContext, environ: std.process.Environ, definitions: []const RawDefinition, axes: []const Axis.AxisDefinition, styles: []const Styles.Style, save_str: []const u8, overwrite: bool) !void {
    const target = parseQualifiedReference(save_str) orelse {
        saveErrorDetail = try std.fmt.allocPrint(alloc, "Error: --save expects a 'NS::KEY' target, but '{s}' was given.", .{save_str});
        return error.SaveTargetNotFound;
    };
    if (target.namespace.len == 0 or target.name.len == 0 or std.mem.indexOf(u8, target.name, "::") != null) {
        saveErrorDetail = try std.fmt.allocPrint(alloc, "Error: --save expects a 'NS::KEY' target, but '{s}' was given.", .{save_str});
        return error.SaveTargetNotFound;
    }

    const raw_definition = findRawDefinitionByBaseName(definitions, target.name) orelse {
        saveErrorDetail = try std.fmt.allocPrint(alloc, "Error: --save was asked to store '{s}' in namespace '{s}', but that key is not defined in --styles. Define it first, e.g. --styles '{s}:{{...}}'.", .{ target.name, target.namespace, target.name });
        return error.SaveTargetNotFound;
    };

    const text = try definitionTextForSave(alloc, axes, styles, target.name, raw_definition);

    config.saveDefinition(alloc, ctx.io, environ, target.namespace, target.name, text, overwrite) catch |err| switch (err) {
        error.KeyAlreadyExists => {
            saveErrorDetail = try std.fmt.allocPrint(alloc, "Error: key '{s}' is already defined in namespace '{s}' of ~/.config/zsat/zsat.conf. Use --overwrite to replace it.", .{ target.name, target.namespace });
            return error.KeyAlreadyExists;
        },
        error.HomeDirectoryMissing => {
            saveErrorDetail = try std.fmt.allocPrint(alloc, "Error: --save could not locate the home directory, so nothing was written to ~/.config/zsat/zsat.conf.", .{});
            return error.HomeDirectoryMissing;
        },
        error.InvalidConfig => {
            saveErrorDetail = try std.fmt.allocPrint(alloc, "Error: --save cannot store '{s}' in namespace '{s}'. Check the namespace and key names.", .{ target.name, target.namespace });
            return error.InvalidConfig;
        },
        else => |other| return other,
    };
}

fn addImportedDefinitions(alloc: std.mem.Allocator, definitions: *std.ArrayList(RawDefinition), named: *std.ArrayList([]const u8), store: ?*const config.Store, default_store: *const config.Store, directive: ImportDirective) !void {
    const loaded = namespaceStore(store, default_store, directive.namespace);
    if (!loaded.hasNamespace(directive.namespace)) return reportMissingNamespace(alloc, directive.namespace, store, default_store);
    for (loaded.definitions) |definition| {
        if (!std.mem.eql(u8, definition.namespace, directive.namespace)) continue;
        const name = try prefixedName(alloc, directive.alias, definition.name);
        try upsertRawDefinition(alloc, definitions, name, definition.text);
        try named.append(alloc, name);
    }
}

fn collectRawDefinitions(alloc: std.mem.Allocator, styles_str: []const u8, store: ?*const config.Store, default_store: *const config.Store, name_fallback: bool) !CollectedStyles {
    const parsed_input = try parseImportDirectives(alloc, styles_str);
    defer alloc.free(parsed_input.imports);
    const parts = try splitStyleInput(alloc, parsed_input.rest);
    defer alloc.free(parts);

    var references = std.ArrayList(QualifiedReference).empty;
    var inline_parts = std.ArrayList([]const u8).empty;
    for (parts) |part| {
        if (parseQualifiedReference(part)) |reference| {
            try references.append(alloc, reference);
        } else {
            try inline_parts.append(alloc, part);
        }
    }

    var definitions = std.ArrayList(RawDefinition).empty;
    // The names in the order the user spelled them out. This is the order the
    // implicit datum association follows, hence it is tracked apart from
    // `definitions`, which also holds definitions merged in on their own.
    var named = std.ArrayList([]const u8).empty;
    const alias_required = parsed_input.imports.len > 1;
    // A bare `use ns` puts its whole namespace in play, so any of its keys can
    // be referenced by name. An aliased `use ns as p` names nothing on its own:
    // it only answers the references (`p::key`) and inherited bases
    // (`key: p::base{...}`) that spell its prefix out. Pulling the whole
    // namespace in for an alias would leak definitions the user never asked
    // for into the style list, so it is done only when `use ns as p` stands
    // alone, where there is nothing else to go by.
    const has_styles_parts = references.items.len > 0 or inline_parts.items.len > 0;
    var aliases_seen = std.ArrayList([]const u8).empty;
    defer aliases_seen.deinit(alloc);
    for (parsed_input.imports) |directive| {
        if (directive.alias) |alias| {
            for (aliases_seen.items) |seen| {
                if (std.mem.eql(u8, seen, alias)) return error.ParseStylesFailed;
            }
            try aliases_seen.append(alloc, alias);
        } else if (alias_required) {
            return error.ParseStylesFailed;
        }
        const loaded = namespaceStore(store, default_store, directive.namespace);
        if (!loaded.hasNamespace(directive.namespace)) return reportMissingNamespace(alloc, directive.namespace, store, default_store);
        if (directive.alias == null or !has_styles_parts) {
            try addImportedDefinitions(alloc, &definitions, &named, store, default_store, directive);
        }
    }

    if (references.items.len > 0) {
        var visited = std.ArrayList(QualifiedReference).empty;
        for (references.items) |reference| {
            const directive = findImportAlias(parsed_input.imports, reference.namespace);
            const target_namespace = if (directive) |import| import.namespace else reference.namespace;
            // A definition is known by the name it was asked for, so a
            // qualified reference keeps its namespace: `experimental::a1` is
            // collected as `experimental::a1`, the way `use work as w` collects
            // the same definition as `w::a1`. Only an import that keeps the
            // bare names (`use sleek`) gives a bare `a1`, and a bare `a1` is
            // otherwise made explicitly with `a1: experimental::a1`.
            const prefix: ?[]const u8 = if (directive) |import| import.alias else reference.namespace;
            const loaded = namespaceStore(store, default_store, target_namespace);
            if (!loaded.hasNamespace(target_namespace)) return reportMissingNamespace(alloc, target_namespace, store, default_store);
            try addReferencedDefinition(alloc, &definitions, loaded, default_store, &visited, target_namespace, reference.name, prefix);
            try named.append(alloc, try prefixedName(alloc, prefix, reference.name));
        }
    } else if (parsed_input.imports.len == 0) {
        // Nothing was named in --styles, so the definitions of the default
        // namespace are the ones in play. They only count as named when the
        // user did not spell out styles of their own either, as otherwise they
        // are merely there to be referenced (a style can inherit from `e0`).
        const loaded = namespaceStore(store, default_store, config.default_namespace);
        _ = try addNamespaceDefinitions(alloc, &definitions, if (name_fallback) &named else null, loaded, config.default_namespace);
    }

    var inline_visited = std.ArrayList(QualifiedReference).empty;
    defer inline_visited.deinit(alloc);
    for (inline_parts.items) |part| {
        if (config.definitionName(part)) |name| {
            // A base such as the `s::a0` of `a0: s::a0{...}` is a reference in
            // its own right. An aliased import no longer pulls its namespace in
            // wholesale, so the base has to be collected like any other
            // `s::key` for the definition to resolve against it.
            if (inlinePartBaseReference(part, name)) |base| {
                if (findImportAlias(parsed_input.imports, base.namespace)) |directive| {
                    const loaded = namespaceStore(store, default_store, directive.namespace);
                    if (!loaded.hasNamespace(directive.namespace)) return reportMissingNamespace(alloc, directive.namespace, store, default_store);
                    try addReferencedDefinition(alloc, &definitions, loaded, default_store, &inline_visited, directive.namespace, base.name, directive.alias);
                }
            }
            try upsertRawDefinition(alloc, &definitions, name, part);
            try named.append(alloc, name);
            continue;
        }
        // A bare key after a `use ns` names a definition the import already
        // brought in rather than defining one, and says that the implicit
        // --datum association should reach for it. `use sleek, e0, a0` is
        // therefore sleek's `e0` and `a0`, not two new definitions.
        if (bareDefinitionKey(alloc, part)) |key| {
            if (findRawDefinition(definitions.items, key) != null) {
                try named.append(alloc, key);
                continue;
            }
            try reportUnnamedDefinition(alloc, key, definitions.items);
            return error.ParseStylesFailed;
        }
        return error.ParseStylesFailed;
    }

    return CollectedStyles{
        .definitions = try definitions.toOwnedSlice(alloc),
        .names = try named.toOwnedSlice(alloc),
    };
}

const style_flag = zli.Flag{
    .name = "styles",
    .shortcut = "s",
    .description = "Style(s) definition to be used in further steps when constructing the figure.",
    .type = .String,
    .default_value = .{ .String = config.default_style },
};

const datum_flag = zli.Flag{
    .name = "datum",
    .shortcut = "d",
    .description = "Mapping data streams to the defined styles. Omitted, the first data input is associated with the firstly defined style, the second one with the secondly defined style, and so on, wrapping around when there are more inputs than styles.",
    .type = .String,
    .default_value = .{ .String = "" },
};

const outputs_flag = zli.Flag{
    .name = "outputs",
    .shortcut = "o",
    .description = "Input(s) transformation definition of the outputs.",
    .type = .String,
    .default_value = .{ .String = config.default_outputs },
};

const panes_flag = zli.Flag{
    .name = "panes",
    .shortcut = "p",
    .description = "Pane(s) definition to be used in frame construction of the figure.",
    .type = .String,
    .default_value = .{ .String = "p0:{size: 600x600}" },
};

const frames_flag = zli.Flag{
    .name = "frames",
    .shortcut = "f",
    .description = "Frame(s) definition of the figure.",
    .type = .String,
    .default_value = .{ .String = "(out) -> out -> p0" },
};

const debug_flag = zli.Flag{
    .name = "debug",
    .description = "Dump the drawing representation for a command invoked.",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

const save_flag = zli.Flag{
    .name = "save",
    .description = "Persist a style defined in --styles into ~/.config/zsat/zsat.conf as NS::KEY, e.g. --save mynamespace::e1. The namespace is created when it does not exist yet.",
    .type = .String,
    .default_value = .{ .String = "" },
};

const overwrite_flag = zli.Flag{
    .name = "overwrite",
    .description = "Let --save replace a key that is already defined in the target namespace instead of failing.",
    .type = .Bool,
    .default_value = .{ .Bool = false },
};

const out_flag = zli.Flag{
    .name = "out",
    .description = "Output filename for the PNG image. When specified, always writes to file instead of displaying in terminal.",
    .type = .String,
    .default_value = .{ .String = "" },
};

pub fn register(init_opts: zli.InitOptions) !*zli.Command {
    const cmd = try zli.Command.init(init_opts, .{
        .name = "draw",
        .shortcut = "d",
        .description = "Construct figure for stdin data using styles, datum, outputs, panes and frames",
        .help = "To explore help more try: zsat draw objects --help",
    }, run);

    try cmd.addFlag(style_flag);
    try cmd.addFlag(datum_flag);
    try cmd.addFlag(outputs_flag);
    try cmd.addFlag(panes_flag);
    try cmd.addFlag(frames_flag);

    try cmd.addFlag(debug_flag);
    try cmd.addFlag(out_flag);
    try cmd.addFlag(save_flag);
    try cmd.addFlag(overwrite_flag);

    // Documentation subcommands
    const objects_cmd = try zli.Command.init(init_opts, .{
        .name = "objects",
        .description = "Overview of objects and concepts you can explore",
        .help = draw_help.objects_help,
    }, draw_help.printHelpExec);
    try cmd.addCommand(objects_cmd);

    const vec2d_cmd = try zli.Command.init(init_opts, .{
        .name = "vec2d",
        .description = "2D vector data format and concepts",
        .help = draw_help.vec2d_help,
    }, draw_help.printHelpExec);

    const vec2d_style_cmd = try zli.Command.init(init_opts, .{
        .name = "style",
        .description = "Style attributes: coordinate system, orientation, steps, line properties",
        .help = draw_help.vec2d_style_help,
    }, draw_help.printHelpExec);

    const vec2d_output_cmd = try zli.Command.init(init_opts, .{
        .name = "output",
        .description = "Output transformations: anchor, rotate, scale, mirror, center",
        .help = draw_help.vec2d_output_help,
    }, draw_help.printHelpExec);

    try vec2d_cmd.addCommand(vec2d_style_cmd);
    try vec2d_cmd.addCommand(vec2d_output_cmd);
    try cmd.addCommand(vec2d_cmd);

    const pt2d_cmd = try zli.Command.init(init_opts, .{
        .name = "pt2d",
        .description = "2D point data format: input shape, markers, and style attributes",
        .help = draw_help.pt2d_help,
    }, draw_help.printHelpExec);

    const pt2d_style_cmd = try zli.Command.init(init_opts, .{
        .name = "style",
        .description = "Point style attributes: shape, size, color, opacity",
        .help = draw_help.pt2d_style_help,
    }, draw_help.printHelpExec);

    const pt2d_output_cmd = try zli.Command.init(init_opts, .{
        .name = "output",
        .description = "Output transformations: anchor, rotate, mirror, project, center",
        .help = draw_help.pt2d_output_help,
    }, draw_help.printHelpExec);

    try pt2d_cmd.addCommand(pt2d_style_cmd);
    try pt2d_cmd.addCommand(pt2d_output_cmd);
    try cmd.addCommand(pt2d_cmd);

    const point_cmd = try zli.Command.init(init_opts, .{
        .name = "point",
        .description = "How to define points: explicit coordinates or references",
        .help = draw_help.point_help,
    }, draw_help.printHelpExec);
    try cmd.addCommand(point_cmd);

    const line_cmd = try zli.Command.init(init_opts, .{
        .name = "line",
        .description = "How to define lines for the mirror transformation",
        .help = draw_help.line_help,
    }, draw_help.printHelpExec);
    try cmd.addCommand(line_cmd);

    const angle_cmd = try zli.Command.init(init_opts, .{
        .name = "angle",
        .description = "How to represent angles: degrees, radians, and fractions of pi",
        .help = draw_help.angle_help,
    }, draw_help.printHelpExec);
    try cmd.addCommand(angle_cmd);

    const color_cmd = try zli.Command.init(init_opts, .{
        .name = "color",
        .description = "Available color names for line color",
        .help = draw_help.color_help,
    }, draw_help.printHelpExec);
    try cmd.addCommand(color_cmd);

    const border_cmd = try zli.Command.init(init_opts, .{
        .name = "border",
        .description = "How to define pane borders: width, opacity, and color",
        .help = draw_help.border_help,
    }, draw_help.printHelpExec);
    try cmd.addCommand(border_cmd);

    const background_cmd = try zli.Command.init(init_opts, .{
        .name = "background",
        .description = "How to define the pane background: color and opacity",
        .help = draw_help.background_help,
    }, draw_help.printHelpExec);
    try cmd.addCommand(background_cmd);

    const axis_cmd = try zli.Command.init(init_opts, .{
        .name = "axis",
        .description = "How to define axes: line, ticks, and value labels",
        .help = draw_help.axis_help,
    }, draw_help.printHelpExec);
    try cmd.addCommand(axis_cmd);

    return cmd;
}

/// The kind of style a data row can be rendered with: a row carrying any vector
/// is a vec2d row, a row made of points only is a pt2d one.
fn rowStyleType(row: Inputs.InputElementRow) Styles.StyleType {
    for (row.row) |element| switch (element) {
        .point => {},
        .vector, .vectors => return .vec2d,
    };
    return .pt2d;
}

fn containsIndex(indices: []const usize, needle: usize) bool {
    for (indices) |index| {
        if (index == needle) return true;
    }
    return false;
}

/// The n-th style of `order` rendering `wanted` data, or null when none does.
fn nthMatchingStyle(styles: []const Styles.Style, order: []const usize, wanted: Styles.StyleType, n: usize) ?usize {
    var count: usize = 0;
    for (order) |i| {
        if (i < styles.len and styles[i].styleValue.styleType == wanted) count += 1;
    }
    if (count == 0) return null;

    var seen: usize = 0;
    for (order) |i| {
        if (i >= styles.len or styles[i].styleValue.styleType != wanted) continue;
        if (seen == n % count) return i;
        seen += 1;
    }
    return null;
}

/// Builds the datum used when --datum is omitted. Row i is associated with the
/// (i % count)-th style rendering that kind of data, `order` telling which
/// styles are in play and in which sequence: the first input goes with the
/// firstly named style that renders it, the second with the secondly named one,
/// and further rows wrap around. Styles rendering the other kind of data are
/// left out entirely, so they are simply never associated, and a row that no
/// named style renders falls back to the remaining styles, then to the first.
fn implicitDatumString(alloc: std.mem.Allocator, inputs: Inputs.Inputs, style_name_list: []const []const u8, styles: []const Styles.Style, order: []const usize) ![]const u8 {
    const all = try alloc.alloc(usize, styles.len);
    for (all, 0..) |_, i| all[i] = i;

    const per_row = try alloc.alloc([]const u8, inputs.input.len);
    for (inputs.input, 0..) |row, i| {
        const wanted = rowStyleType(row);
        const pick = nthMatchingStyle(styles, order, wanted, i) orelse
            nthMatchingStyle(styles, all, wanted, i) orelse
            (if (order.len > 0) order[0] else 0);
        per_row[i] = style_name_list[pick];
    }
    return Datum.explicitString(alloc, "vec", per_row);
}

fn parse(ctx: zli.CommandContext, alloc: std.mem.Allocator, environ: std.process.Environ) !ParsedData {
    const debug = ctx.flag("debug", bool);
    const styles_str = ctx.flag("styles", []const u8);
    const datum_str = ctx.flag("datum", []const u8);
    const panes_str = ctx.flag("panes", []const u8);
    const frames_str = ctx.flag("frames", []const u8);
    const output_str = ctx.flag("outputs", []const u8);

    const stdin_str = try ctx.reader.allocRemaining(alloc, .limited(1024 * 1024));
    defer alloc.free(stdin_str);

    const inputs_parse_result = try Inputs.inputsParser.parse(alloc, stdin_str);
    const inputs = switch (inputs_parse_result.value) {
        .ok => |in| in,
        .err => {
            return error.ParseInputsFailed;
        },
    };
    if (inputs_parse_result.index < stdin_str.len) {
        const rest = stdin_str[inputs_parse_result.index..];
        for (rest) |c| {
            if (c != ' ' and c != '\n' and c != '\r' and c != '\t') {
                return error.ParseInputsFailed;
            }
        }
    }

    var loaded_store = config.load(alloc, ctx.io, environ) catch |err| switch (err) {
        error.InvalidConfig => return error.ParseStylesFailed,
        else => return err,
    };
    defer if (loaded_store) |*store| store.deinit();
    var default_store = try config.parse(alloc, config.default_content);
    defer default_store.deinit();
    const store_ptr: ?*const config.Store = if (loaded_store) |*store| store else null;
    const styles_given = !std.mem.eql(u8, styles_str, config.default_style);
    const effective_styles_str = if (store_ptr != null and !styles_given) "" else styles_str;

    const collected = try collectRawDefinitions(alloc, effective_styles_str, store_ptr, &default_store, !styles_given);
    var raw_definitions = collected.definitions;
    defer alloc.free(raw_definitions);
    const named = collected.names;
    var has_builtin_e0 = false;
    for (raw_definitions) |definition| {
        if (std.mem.eql(u8, definition.name, "e0")) has_builtin_e0 = true;
    }
    if (!has_builtin_e0) {
        var with_fallback: std.ArrayList(RawDefinition) = .empty;
        try with_fallback.appendSlice(alloc, raw_definitions);
        try upsertRawDefinition(alloc, &with_fallback, "e0", config.default_style);
        alloc.free(raw_definitions);
        raw_definitions = try with_fallback.toOwnedSlice(alloc);
    }

    var draw_elements_list = std.ArrayList(DrawElement).empty;
    for (raw_definitions) |definition| {
        const element_parse_result = try drawElementParser.parse(alloc, definition.text);
        const element = switch (element_parse_result.value) {
            .ok => |e| try e,
            .err => return error.ParseStylesFailed,
        };
        if (element_parse_result.index < definition.text.len) {
            const rest = definition.text[element_parse_result.index..];
            for (rest) |c| {
                if (c != ' ' and c != '\n' and c != '\r' and c != '\t') {
                    return error.ParseStylesFailed;
                }
            }
        }
        try draw_elements_list.append(alloc, element);
    }

    var styles_list = std.ArrayList(Styles.Style).empty;
    var style_names = std.ArrayList([]const u8).empty;
    var borders_list = std.ArrayList(Border.BorderDefinition).empty;
    var texts_list = std.ArrayList(Text.TextDefinition).empty;
    var axes_list = std.ArrayList(Axis.AxisDefinition).empty;
    for (raw_definitions, draw_elements_list.items) |definition, element| {
        switch (element) {
            .style => |s| {
                var named_style = s;
                named_style.name = definition.name;
                try styles_list.append(alloc, named_style);
                try style_names.append(alloc, definition.name);
            },
            .point_style => |p| {
                try styles_list.append(alloc, .{ .styleNumber = p.styleNumber, .styleValue = p.styleValue, .name = definition.name });
                try style_names.append(alloc, definition.name);
            },
            .border => |b| {
                // Styles, texts, borders and axes are all known by the name
                // they were collected under, which is what a `use ns as p`
                // prefix renames. Referencing one therefore means spelling that
                // name, and the number in the definition text is only what the
                // parser could recover on its own.
                var named_border = b;
                named_border.name = definition.name;
                try borders_list.append(alloc, named_border);
            },
            .text => |t| {
                var named_text = t;
                named_text.name = definition.name;
                try texts_list.append(alloc, named_text);
            },
            .axis => |a| {
                var named_axis = a;
                named_axis.name = definition.name;
                try axes_list.append(alloc, named_axis);
            },
        }
    }

    if (styles_list.items.len == 0) {
        try styles_list.append(alloc, Styles.Style{
            .styleNumber = 0,
            .styleValue = Styles.defaultStyleValue,
            .name = "e0",
        });
        try style_names.append(alloc, "e0");
    }

    const raw_styles = try styles_list.toOwnedSlice(alloc);
    const style_name_list = try style_names.toOwnedSlice(alloc);
    const borders = try borders_list.toOwnedSlice(alloc);
    const texts = try texts_list.toOwnedSlice(alloc);
    const axes = try axes_list.toOwnedSlice(alloc);

    // Saving waits until the definitions are parsed, so a definition can be
    // stored expanded out of whatever it resolved against.
    if (ctx.flag("save", []const u8).len > 0) {
        try saveToConfig(alloc, ctx, environ, raw_definitions, axes, raw_styles, ctx.flag("save", []const u8), ctx.flag("overwrite", bool));
    }

    const styles = try Styles.resolveStyles(alloc, raw_styles);

    // Indices into `styles` of the styles the user named, in the order they
    // named them. Borders, texts and axes are named too, yet they are no
    // styles, hence they are skipped here, and a name spelled out twice counts
    // once so that redefining it does not weigh in the association twice.
    var named_indices = std.ArrayList(usize).empty;
    for (named) |name| {
        for (style_name_list, 0..) |style_name, i| {
            if (!std.mem.eql(u8, style_name, name)) continue;
            if (!containsIndex(named_indices.items, i)) try named_indices.append(alloc, i);
            break;
        }
    }

    // When --datum is omitted, the association is derived from the styles: data
    // row i takes the (i % count)-th of them, so the first input goes with the
    // firstly defined style, the second with the secondly defined one, and
    // further rows wrap around. Styles no row picks up are simply left unused.
    var effective_datum_str = datum_str;
    if (std.mem.trim(u8, datum_str, " \t\r\n").len == 0) {
        effective_datum_str = try implicitDatumString(alloc, inputs, style_name_list, styles, named_indices.items);
    }

    const datum_parse_result = try Datum.connectionParser.parse(alloc, effective_datum_str);
    const datum = switch (datum_parse_result.value) {
        .ok => |d| d,
        .err => {
            return error.ParseDatumFailed;
        },
    };

    const numberOfDatum: u8 = @intCast(inputs.input.len);

    // The effective datum applies mappings positionally: row i uses the
    // (i % count)-th mapping, so a single mapping like `(vec) -> (vec -> e0)`
    // broadcasts to every row. Show the rotated form in --debug.
    if (datum.inputs.len != 0 and datum.inputs.len != numberOfDatum) {
        effective_datum_str = try Datum.rotatedString(alloc, datum, numberOfDatum);
    }

    var elements = try alloc.alloc([]const u8, styles.len);
    for (style_name_list, 0..) |name, i| {
        elements[i] = name;
    }
    defer alloc.free(elements);

    const datumValidated = try Datum.validateConnection(alloc, numberOfDatum, elements, datum);

    // The default --outputs anchors a vector at the origin, which is what a
    // displacement wants. A point is already an absolute position, so that
    // anchor would displace the whole cloud by its centroid and leave the plot
    // hugging a corner. When every row is drawn as a point, the identity is the
    // default instead. An explicit --outputs is always left alone.
    var effective_output_str = output_str;
    const outputs_given = !std.mem.eql(u8, output_str, config.default_outputs);
    if (!outputs_given) {
        var all_points = inputs.input.len > 0;
        for (0..inputs.input.len) |row_idx| {
            if (!isPt2dRow(styles, datumValidated.mappings, row_idx)) all_points = false;
        }
        if (all_points) effective_output_str = config.default_outputs_for(true);
    }

    const outputs_parse_result = try Outputs.connectionParser.parse(alloc, effective_output_str);
    const outputsConnection = switch (outputs_parse_result.value) {
        .ok => |o| o,
        .err => {
            return error.ParseOutputsFailed;
        },
    };
    if (outputs_parse_result.index != effective_output_str.len) {
        return error.ParseOutputsFailed;
    }

    const numberOfOutputsForValidation: u8 = @intCast(outputsConnection.outputs.len);

    var outputsValidated = try Outputs.validateConnection(alloc, numberOfOutputsForValidation, outputsConnection);

    // Validate text references from outputs and resolve overlays
    var text_overlays_list = std.ArrayList(Text.Text).empty;
    if (@hasField(@TypeOf(outputsConnection), "textOutputs")) {
        for (outputsConnection.textOutputs) |tout| {
            if (try Text.resolveTextOverlay(alloc, tout.item, texts)) |overlay| {
                if (tout.ops) |ops| {
                    const pos_angle = Outputs.extractTextPositionAndAngle(ops);
                    var modified = overlay;
                    modified.x = pos_angle.x;
                    modified.y = pos_angle.y;
                    modified.angle = pos_angle.angle;
                    try text_overlays_list.append(alloc, modified);
                } else {
                    try text_overlays_list.append(alloc, overlay);
                }
            } else {
                try reportUnknownReference(alloc, "text", tout.item.name, try namesOf(alloc, Text.TextDefinition, texts, "name"));
                return error.TextReferenceInvalid;
            }
        }
    }
    const text_overlays = try text_overlays_list.toOwnedSlice(alloc);

    // Validate axis references from outputs and resolve overlays
    var axis_overlays_list = std.ArrayList(Axis.AxisOverlay).empty;
    if (@hasField(@TypeOf(outputsConnection), "axisOutputs")) {
        const resolved_axes = try Axis.resolveAxes(alloc, axes);
        for (outputsConnection.axisOutputs) |aout| {
            if (try Axis.resolveAxisOverlay(alloc, aout.item, resolved_axes, aout.from, aout.to)) |overlay| {
                try axis_overlays_list.append(alloc, overlay);
            } else {
                try reportUnknownReference(alloc, "axis", aout.item.name, try namesOf(alloc, Axis.AxisDefinition, axes, "name"));
                return error.AxisReferenceInvalid;
            }
        }
    }
    const axis_overlays = try axis_overlays_list.toOwnedSlice(alloc);

    // Output transformation pairs are assigned to input rows by index. When
    // the counts differ, the sequence is rotated: row i uses the
    // (i % count)-th pair. This keeps the mapping total -- every row is drawn,
    // including with a single pair, which then simply broadcasts to all rows.
    if (outputsValidated.transformationPairs.len > 0 and inputs.input.len != outputsValidated.transformationPairs.len) {
        const original_count = outputsValidated.transformationPairs.len;
        const original = outputsValidated.transformationPairs[0..original_count];
        const rotated = try alloc.alloc(Outputs.OutputTransformationPair, inputs.input.len);
        for (0..inputs.input.len) |i| {
            rotated[i] = original[i % original_count];
        }
        outputsValidated.transformationPairs = rotated;
    }

    // Show the rotated form in --debug, mirroring how the datum mapping is
    // expanded over the rows. Keyed off the parsed (pre-rotation) connection
    // so the display matches the rotation applied above.
    var effective_outputs_str = effective_output_str;
    if (outputsConnection.transformationPairs.len > 0 and inputs.input.len != outputsConnection.transformationPairs.len) {
        const rows: u8 = @intCast(inputs.input.len);
        effective_outputs_str = try Outputs.rotatedString(alloc, outputsConnection, rows);
    }

    // The scale and orthogonal transformations do not make sense for point
    // (pt2d) output: a point carries no magnitude to scale nor a direction
    // whose orthogonal component could be taken. Reject these explicitly,
    // including when they occur inside a composite (hook/train) tine.
    for (0..inputs.input.len) |row_idx| {
        if (row_idx >= outputsValidated.transformationPairs.len) continue;
        const is_pt2d = isPt2dRow(styles, datumValidated.mappings, row_idx);
        const pair = outputsValidated.transformationPairs[row_idx];
        if (pair.composite) |c| {
            if (Outputs.compositeRejectsPointOps(c, is_pt2d)) return error.PointScaleNotSupported;
            continue;
        }
        for (pair.operation.ops) |op| {
            switch (op) {
                .scale => if (is_pt2d) return error.PointScaleNotSupported,
                .orthogonal => if (is_pt2d) return error.PointOrthogonalNotSupported,
                else => {},
            }
        }
    }

    var result_pairs = try alloc.alloc(Outputs.OutputTransformationPair, outputsValidated.transformationPairs.len);

    // The frame of an output (orientation, plot steps, coordinate system) is a
    // property of the style that renders the row, which the datum association
    // picks out — not of the style at the row's positional index. `use sleek as
    // s` imports `s::e0` ahead of a user's own `e0`, so indexing positionally
    // would silently apply the imported style's frame. Index through the datum
    // mapping, exactly as the plotting step does (styleIndexForRow in plot.zig).
    for (0..outputsValidated.transformationPairs.len) |idx| {
        const style_idx = styleIndexForRow(datumValidated.mappings, idx);
        const sv = if (style_idx < styles.len) styles[style_idx].styleValue else Styles.defaultStyleValue;
        const coord_orientation = sv.coordinateOrientation orelse .fixed;
        const plot_step = sv.plotSteps orelse .last;
        const coord_type = sv.coordinateSystem orelse .xy;

        const transformed = try Outputs.toExplicitPoint(alloc, inputs, outputsValidated, coord_orientation, plot_step, idx, coord_type);
        result_pairs[idx] = transformed.transformationPairs[idx];
    }

    var outputsExplicit: Outputs.OutputsValidated = undefined;
    outputsExplicit.transformationPairs = result_pairs;

    const panes_parse_result = try Panes.panesParser.parse(alloc, panes_str);
    const panes = switch (panes_parse_result.value) {
        .ok => |p| p,
        .err => {
            return error.ParsePanesFailed;
        },
    };
    if (panes.len == 0) {
        return error.ParsePanesFailed;
    }

    // Validate pane border references
    {
        const border_names = try namesOf(alloc, Border.BorderDefinition, borders, "name");
        for (panes) |pane| {
            if (pane.paneValue.border == .ref) {
                const name = pane.paneValue.border.ref;
                var found = false;
                for (borders) |bdef| {
                    if (std.mem.eql(u8, bdef.name, name)) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    try reportUnknownReference(alloc, "border", name, border_names);
                    return error.BorderReferenceInvalid;
                }
            }
        }
    }

    var paneNames = try alloc.alloc([]const u8, panes.len);
    for (panes, 0..) |pane, i| {
        paneNames[i] = try std.fmt.allocPrint(alloc, "p{}", .{pane.paneNumber});
    }
    defer {
        for (paneNames) |name| alloc.free(name);
        alloc.free(paneNames);
    }

    const frames_parse_result = try Frames.connectionParser.parse(alloc, frames_str);
    const frames = switch (frames_parse_result.value) {
        .ok => |f| f,
        .err => {
            return error.ParseFramesFailed;
        },
    };

    const framesNum: u8 = 1;
    const framesValidated = try Frames.validateConnection(alloc, framesNum, paneNames, frames);

    if (debug) {
        const styles_debug = try Styles.serializeStyles(alloc, styles);
        defer alloc.free(styles_debug);
        const borders_debug = try Border.serializeBorderDefinitions(alloc, borders);
        defer alloc.free(borders_debug);
        const axes_debug = try Axis.serializeAxisDefinitions(alloc, axes);
        defer alloc.free(axes_debug);
        const texts_debug = try Text.serializeTextDefinitions(alloc, texts);
        defer alloc.free(texts_debug);
        // Show every kind --styles collected: the styles, then the borders,
        // axes and texts they reach for in --outputs and --panes, each written
        // out expanded so the line is a complete account of what is in play.
        var sections = std.ArrayList([]const u8).empty;
        defer sections.deinit(alloc);
        try sections.append(alloc, styles_debug);
        if (borders_debug.len > 0) try sections.append(alloc, borders_debug);
        if (axes_debug.len > 0) try sections.append(alloc, axes_debug);
        if (texts_debug.len > 0) try sections.append(alloc, texts_debug);
        try ctx.writer.print("stdin:\n{s}\n", .{stdin_str});
        try ctx.writer.print("\n--styles '{s}'\n", .{try std.mem.join(alloc, ", ", sections.items)});
        try ctx.writer.print("--datum '{s}'\n", .{effective_datum_str});
        try ctx.writer.print("--outputs '{s}'\n", .{effective_outputs_str});
        // Build panes string with embedded border info
        var panes_debug_parts = std.ArrayList([]const u8).empty;
        defer {
            for (panes_debug_parts.items) |p| alloc.free(p);
            panes_debug_parts.deinit(alloc);
        }
        for (panes, 0..) |pane, i| {
            if (i > 0) try panes_debug_parts.append(alloc, try alloc.dupe(u8, ", "));
            const size = pane.paneValue.paneSize.?;
            const b = resolvePaneBorder(pane, borders);
            const bg = resolvePaneBackground(pane);
            const bg_str = try std.fmt.allocPrint(alloc, "background: {{opacity: {}, color: {s}}}", .{ bg.opacity, @tagName(bg.color) });
            const pane_str = if (b) |border_val|
                try std.fmt.allocPrint(alloc, "p{d}:{{size: {}x{}, border: {{width: {}, opacity: {}, color: {s}}}, {s}}}", .{ pane.paneNumber, size.width, size.height, border_val.width, border_val.opacity, @tagName(border_val.color), bg_str })
            else
                try std.fmt.allocPrint(alloc, "p{d}:{{size: {}x{}, border: none, {s}}}", .{ pane.paneNumber, size.width, size.height, bg_str });
            try panes_debug_parts.append(alloc, pane_str);
        }
        const panes_debug = try std.mem.join(alloc, "", panes_debug_parts.items);
        defer alloc.free(panes_debug);
        try ctx.writer.print("--panes '{s}'\n", .{panes_debug});
        try ctx.writer.print("--frames '{s}'\n", .{frames_str});
    }

    return ParsedData{
        .styles = styles,
        .borders = borders,
        .texts = texts,
        .textOverlays = text_overlays,
        .axes = axes,
        .axisOverlays = axis_overlays,
        .inputs = inputs,
        .datum = datumValidated,
        .outputs = outputsExplicit,
        .panes = panes,
        .frames = framesValidated,
    };
}

fn resolvePaneBorder(pane: Panes.Pane, borders: []const Border.BorderDefinition) ?Border.Border {
    switch (pane.paneValue.border) {
        .none => return null,
        .defined => |b| return b,
        .ref => |name| {
            for (borders) |bdef| {
                if (std.mem.eql(u8, bdef.name, name)) {
                    return bdef.w;
                }
            }
            return null;
        },
    }
}

fn resolvePaneBackground(pane: Panes.Pane) Border.Background {
    switch (pane.paneValue.background) {
        .none => return .{},
        .defined => |b| return b,
    }
}

/// Finds the style index for a given input row via the datum mappings. Rows
/// without a mapping that reaches the styles fall back to the first style.
/// Mirrors styleIndexForRow in plot.zig, which the rendering step uses.
fn styleIndexForRow(mappings: []const Datum.DataElementMapping, row_idx: usize) usize {
    var style_idx: usize = 0;
    for (mappings) |mapping| {
        if (mapping.from == row_idx) {
            style_idx = mapping.to;
            break;
        }
    }
    return style_idx;
}

fn isPt2dRow(styles: []const Styles.Style, mappings: []const Datum.DataElementMapping, row_idx: usize) bool {
    var style_idx: ?usize = null;
    for (mappings) |mapping| {
        if (mapping.from == row_idx) {
            style_idx = mapping.to;
            break;
        }
    }
    const idx = style_idx orelse return false;
    if (idx >= styles.len) return false;
    return styles[idx].styleValue.styleType == .pt2d;
}

fn checkTerminalSupportsKitty(environ: std.process.Environ) bool {
    const term = environ.getPosix("TERM") orelse return false;
    if (!std.mem.containsAtLeast(u8, term, 1, "xterm") and
        !std.mem.containsAtLeast(u8, term, 1, "kitty") and
        !std.mem.containsAtLeast(u8, term, 1, "ghostty")) return false;
    return true;
}

fn rgbaPixelsToBase64(allocator: std.mem.Allocator, pixels: anytype) ![]u8 {
    var byte_data = try std.ArrayList(u8).initCapacity(allocator, pixels.len * 4);
    defer byte_data.deinit(allocator);
    for (pixels) |px| {
        try byte_data.append(allocator, px.r);
        try byte_data.append(allocator, px.g);
        try byte_data.append(allocator, px.b);
        try byte_data.append(allocator, px.a);
    }

    var encoded = try std.ArrayList(u8).initCapacity(allocator, std.base64.standard.Encoder.calcSize(byte_data.items.len));
    try encoded.resize(allocator, std.base64.standard.Encoder.calcSize(byte_data.items.len));
    _ = std.base64.standard.Encoder.encode(encoded.items, byte_data.items);
    return encoded.items;
}

fn kittyEncode(writer: anytype, width: i32, height: i32, encoded: []const u8) !void {
    try writer.writeAll("\n     ");
    const chunk_size = 4096;
    if (encoded.len <= chunk_size) {
        try writer.print("\x1B_Gf=32,s={d},v={d},a=T;{s}\x1B\\", .{ width, height, encoded });
    } else {
        try writer.print("\x1B_Gf=32,s={d},v={d},a=T,m=1;{s}\x1B\\", .{ width, height, encoded[0..chunk_size] });
        var start: usize = chunk_size;
        while (start + chunk_size < encoded.len) {
            try writer.print("\x1B_Gm=1;{s}\x1B\\", .{encoded[start..][0..chunk_size]});
            start += chunk_size;
        }
        try writer.print("\x1B_Gm=0;{s}\x1B\\", .{encoded[start..]});
    }
    try writer.writeAll("\n\n");
}

fn renderToStdout(allocator: std.mem.Allocator, img: Plot.RenderedImage, writer: anytype, io: std.Io) !void {
    const original_width = img.width;
    const original_height = img.height;

    var term_cols: u16 = 80;
    var term_rows: u16 = 24;

    const stdout_file = std.Io.File.stdout();
    if (try stdout_file.isTty(io)) {
        var winsize: std.posix.winsize = undefined;
        if (std.posix.system.ioctl(stdout_file.handle, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize)) == 0 and
            winsize.col > 0 and winsize.col < 1000 and winsize.row > 0 and winsize.row < 1000)
        {
            term_cols = winsize.col;
            term_rows = winsize.row;
        }
    }

    const CELL_WIDTH: f32 = 8.0;
    const CELL_HEIGHT: f32 = 16.0;

    const max_pixel_w: f32 = @as(f32, @floatFromInt(term_cols)) * CELL_WIDTH;
    const max_pixel_h: f32 = @as(f32, @floatFromInt(term_rows)) * CELL_HEIGHT;

    const img_w: f32 = @floatFromInt(original_width);
    const img_h: f32 = @floatFromInt(original_height);
    const scale_x: f32 = max_pixel_w / img_w;
    const scale_y: f32 = max_pixel_h / img_h;
    const scale: f32 = @min(scale_x, scale_y);

    const new_w: u32 = @intFromFloat(scale * img_w);
    const new_h: u32 = @intFromFloat(scale * img_h);

    var pixels = img.pixels;
    var kitty_w: i32 = original_width;
    var kitty_h: i32 = original_height;
    if (new_w < original_width or new_h < original_height) {
        const resized = try resizePixels(allocator, pixels, original_width, original_height, new_w, new_h);
        pixels = resized;
        kitty_w = @intCast(new_w);
        kitty_h = @intCast(new_h);
    }

    const encoded = try rgbaPixelsToBase64(allocator, pixels);
    defer allocator.free(encoded);
    try kittyEncode(writer, kitty_w, kitty_h, encoded);
    try writer.flush();
}

fn resizePixels(
    alloc: std.mem.Allocator,
    pixels: []z2d.pixel.RGBA,
    original_width: i32,
    original_height: i32,
    new_w: u32,
    new_h: u32,
) ![]z2d.pixel.RGBA {
    const original_w_u: u32 = @intCast(original_width);
    const original_h_u: u32 = @intCast(original_height);

    const img_w_f = @as(f32, @floatFromInt(original_width));
    const img_h_f = @as(f32, @floatFromInt(original_height));
    const new_w_f = @as(f32, @floatFromInt(new_w));
    const new_h_f = @as(f32, @floatFromInt(new_h));

    var new_pixels = try alloc.alloc(z2d.pixel.RGBA, new_w * new_h);

    for (0..new_h) |y| {
        const sy = @as(f32, @floatFromInt(y)) * img_h_f / new_h_f;
        const y0 = @as(usize, @intFromFloat(@floor(sy)));
        const y1 = @min(y0 + 1, original_h_u - 1);
        const dy = sy - @floor(sy);

        for (0..new_w) |x| {
            const sx = @as(f32, @floatFromInt(x)) * img_w_f / new_w_f;
            const x0 = @as(usize, @intFromFloat(@floor(sx)));
            const x1 = @min(x0 + 1, original_w_u - 1);
            const dx = sx - @floor(sx);

            const p00 = pixels[y0 * original_w_u + x0];
            const p01 = pixels[y0 * original_w_u + x1];
            const p10 = pixels[y1 * original_w_u + x0];
            const p11 = pixels[y1 * original_w_u + x1];

            new_pixels[y * new_w + x] = .{
                .r = @intFromFloat((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.r)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.r)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.r)) + dx * dy * @as(f32, @floatFromInt(p11.r))),
                .g = @intFromFloat((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.g)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.g)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.g)) + dx * dy * @as(f32, @floatFromInt(p11.g))),
                .b = @intFromFloat((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.b)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.b)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.b)) + dx * dy * @as(f32, @floatFromInt(p11.b))),
                .a = @intFromFloat((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.a)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.a)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.a)) + dx * dy * @as(f32, @floatFromInt(p11.a))),
            };
        }
    }

    return new_pixels;
}

fn resizeImage(alloc: std.mem.Allocator, img: *zigimg.Image, new_w: u32, new_h: u32) !void {
    if (img.pixelFormat() != .rgba32) {
        try img.convert(alloc, .rgba32);
    }

    const original_width = img.width;
    const original_height = img.height;

    if (new_w == original_width and new_h == original_height) return;

    const img_w_f = @as(f32, @floatFromInt(original_width));
    const img_h_f = @as(f32, @floatFromInt(original_height));
    const new_w_f = @as(f32, @floatFromInt(new_w));
    const new_h_f = @as(f32, @floatFromInt(new_h));

    var new_pixels = try alloc.alloc(zigimg.color.Rgba32, new_w * new_h);

    for (0..new_h) |y| {
        const sy = @as(f32, @floatFromInt(y)) * img_h_f / new_h_f;
        const y0 = @as(usize, @intFromFloat(@floor(sy)));
        const y1 = @min(y0 + 1, original_height - 1);
        const dy = sy - @floor(sy);

        for (0..new_w) |x| {
            const sx = @as(f32, @floatFromInt(x)) * img_w_f / new_w_f;
            const x0 = @as(usize, @intFromFloat(@floor(sx)));
            const x1 = @min(x0 + 1, original_width - 1);
            const dx = sx - @floor(sx);

            const p00 = img.pixels.rgba32[y0 * original_width + x0];
            const p01 = img.pixels.rgba32[y0 * original_width + x1];
            const p10 = img.pixels.rgba32[y1 * original_width + x0];
            const p11 = img.pixels.rgba32[y1 * original_width + x1];

            new_pixels[y * new_w + x] = .{
                .r = @intFromFloat(@round((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.r)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.r)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.r)) + dx * dy * @as(f32, @floatFromInt(p11.r)))),
                .g = @intFromFloat(@round((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.g)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.g)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.g)) + dx * dy * @as(f32, @floatFromInt(p11.g)))),
                .b = @intFromFloat(@round((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.b)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.b)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.b)) + dx * dy * @as(f32, @floatFromInt(p11.b)))),
                .a = @intFromFloat(@round((1 - dx) * (1 - dy) * @as(f32, @floatFromInt(p00.a)) + dx * (1 - dy) * @as(f32, @floatFromInt(p01.a)) + (1 - dx) * dy * @as(f32, @floatFromInt(p10.a)) + dx * dy * @as(f32, @floatFromInt(p11.a)))),
            };
        }
    }

    alloc.free(img.pixels.rgba32);
    img.pixels = .{ .rgba32 = new_pixels };
    img.width = new_w;
    img.height = new_h;
}

fn getSystemTmpDir(alloc: std.mem.Allocator, environ: std.process.Environ) ![]u8 {
    const tmp_env = environ.getPosix("TMPDIR") orelse "/tmp";
    const tmp_dir_path = if (tmp_env.len > 0) tmp_env else "/tmp";
    return try alloc.dupe(u8, tmp_dir_path);
}

fn getNextOutputFilename(alloc: std.mem.Allocator, io: std.Io) ![]u8 {
    var n: u32 = 0;
    while (true) : (n += 1) {
        const filename = try std.fmt.allocPrint(alloc, "output{d}.png", .{n});
        errdefer alloc.free(filename);
        const file = std.Io.Dir.cwd().openFile(io, filename, .{}) catch {
            return filename;
        };
        file.close(io);
    }
}

fn friendlyErrorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.ParseInputsFailed => "Error: failed to parse input data. Please check your input format.",
        error.ParseStylesFailed => stylesErrorDetail orelse "Error: failed to parse styles. Please check your --styles argument.",
        error.SaveTargetNotFound => saveErrorDetail orelse "Error: the key given to --save is not defined in --styles.",
        error.KeyAlreadyExists => saveErrorDetail orelse "Error: the key given to --save already exists in the target namespace. Use --overwrite to replace it.",
        error.HomeDirectoryMissing => saveErrorDetail orelse "Error: could not locate the home directory.",
        error.NamespaceNotFound => namespaceErrorDetail orelse "Error: the requested style namespace was not found in ~/.config/zsat/zsat.conf. Check the 'use' directive or the 'NS::NAME' reference in --styles.",
        error.StyleReferenceNotFound => definitionErrorDetail orelse "Error: the requested style was not found in the selected namespace.",
        error.ParseDatumFailed => "Error: failed to parse datum mapping. Please check your --datum argument.",
        error.ParseOutputsFailed => "Error: failed to parse outputs. Please check your --outputs argument.",
        error.ParsePanesFailed => "Error: failed to parse panes. Please check your --panes argument.",
        error.ParseFramesFailed => "Error: failed to parse frames. Please check your --frames argument.",
        error.ElementInMappingInvalid => Datum.elementMappingErrorDetail() orelse "Error: an invalid element was found in the datum mapping.",
        error.DataInMappingInvalid => "Error: invalid data type in the datum mapping.",
        error.WrongNumberOfOutputs => "Error: the number of outputs does not match the expected count.",
        error.ArgumentInPairInvalid => "Error: invalid argument in output transformation pair.",
        error.PaneInMappingInvalid => "Error: an invalid pane was referenced in the frames mapping.",
        error.BorderReferenceInvalid => referenceErrorDetail orelse "Error: a pane references a border that was not defined in --styles.",
        error.TextReferenceInvalid => referenceErrorDetail orelse "Error: an output references a text object that was not defined in --styles.",
        error.TextHoleCountMismatch => Text.textHoleErrorDetail() orelse "Error: the number of values given for a text object in --outputs does not match the number of '{}' holes in the value defined for it in --styles.",
        error.AxisBaseInvalid => Axis.axisBaseErrorDetail() orelse "Error: an axis definition references a base axis that is not defined in --styles (the base must be declared before the axis that inherits from it).",
        error.AxisReferenceInvalid => referenceErrorDetail orelse "Error: an output references an axis object that was not defined in --styles.",
        error.PointScaleNotSupported => "Error: the 'scale' output transformation does not make sense for point (pt2d) output. Remove 'scale' from your --outputs argument.",
        error.PointOrthogonalNotSupported => "Error: the 'orthogonal' output transformation does not make sense for point (pt2d) output. Remove 'orthogonal' from your --outputs argument.",
        else => "Error: an unexpected error occurred.",
    };
}

fn run(ctx: zli.CommandContext) !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const debug = ctx.flag("debug", bool);

    // --overwrite only says something together with --save. Reaching here
    // without one almost always means the key was handed to --overwrite
    // instead, as in `--overwrite myns::a1`: --overwrite is a switch, so the
    // key is not its value, and `draw` takes no bare arguments, so the key is
    // dropped without a word and nothing gets stored. Saying so beats a draw
    // that runs and quietly writes nothing.
    if (ctx.flag("overwrite", bool) and ctx.flag("save", []const u8).len == 0) {
        const detail = try std.fmt.allocPrint(alloc, "Error: --overwrite was given without --save, so there is nothing to overwrite. --overwrite is a switch and takes no value of its own: give the target to --save instead, as '--save NS::KEY --overwrite'.", .{});
        saveErrorDetail = detail;
        std.debug.print("{s}\n", .{detail});
        std.process.exit(1);
    }

    const environ: *std.process.Environ = @ptrCast(@alignCast(ctx.data.?));

    runInternal(ctx, alloc, environ.*) catch |err| {
        if (debug) return err;
        std.debug.print("{s}\n", .{friendlyErrorMessage(err)});
        std.process.exit(1);
    };
}

fn runInternal(ctx: zli.CommandContext, alloc: std.mem.Allocator, environ: std.process.Environ) !void {
    const parsed_data = try parse(ctx, alloc, environ);

    const out_filename = ctx.flag("out", []const u8);
    const force_file = out_filename.len > 0;
    const term_supports = checkTerminalSupportsKitty(environ);
    const stdout_is_tty = try std.Io.File.stdout().isTty(ctx.io);
    const should_display = !force_file and term_supports and stdout_is_tty;

    if (std.mem.eql(u8, out_filename, "/dev/null")) {
        return;
    }

    var output_path: ?[]u8 = null;
    defer if (output_path) |p| alloc.free(p);

    if (force_file) {
        output_path = try alloc.dupe(u8, out_filename);
    } else if (!should_display) {
        output_path = try getNextOutputFilename(alloc, ctx.io);
    }

    const rendered = try Plot.plot_via_z2d(ctx.io, parsed_data, output_path);
    defer rendered.allocator.free(rendered.pixels);

    if (force_file) {
        std.debug.print("Saved to {s}\n", .{out_filename});
    } else if (should_display) {
        var stdout_fw = std.Io.File.stdout().writerStreaming(ctx.io, &.{});
        try renderToStdout(alloc, rendered, &stdout_fw.interface, ctx.io);
    } else {
        const filename = output_path.?;
        std.debug.print("Saved to {s}\n", .{filename});
    }
}
