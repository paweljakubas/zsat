const std = @import("std");
const z2d = @import("z2d");

/// The measured extent of the pixels a string actually inks, in device pixels,
/// relative to the pen origin passed to `Context.showText`.
///
/// z2d places the top of the em box at that origin and lets glyphs grow
/// downward from it, so `y0`/`y1` are normally both positive and `y1` is close
/// to the font size. The box is the glyph outline's coverage, not the advance
/// width, which is what lets labels be centred on what the reader sees rather
/// than on the pen positions.
pub const InkBox = struct {
    x0: f64,
    y0: f64,
    x1: f64,
    y1: f64,

    /// Horizontal centre of the inked pixels.
    pub fn midX(self: InkBox) f64 {
        return (self.x0 + self.x1) * 0.5;
    }

    /// Vertical centre of the inked pixels.
    pub fn midY(self: InkBox) f64 {
        return (self.y0 + self.y1) * 0.5;
    }
};

/// A scratch canvas for rasterizing one string off-screen so its ink extent
/// can be measured. This exists because z2d exposes no text metrics:
/// `Font.meta` is private and there is no public advance, bounding box or
/// ascent API, so the only way to learn where a glyph really lands is to draw
/// it and look. The font is borrowed rather than loaded here, so measuring many
/// labels costs one small surface each instead of one font file read each.
const Rasterizer = struct {
    alloc: std.mem.Allocator,
    surface: z2d.Surface,
    font: *z2d.Font,
    width: i32,
    height: i32,
    size: f64,

    /// Opens a scratch canvas comfortably larger than any single string we
    /// expect to measure, so that ink touching an edge means a pathological
    /// font rather than a crop we caused. The canvas starts opaque white, so
    /// "not white" identifies ink without any compositing bookkeeping.
    fn init(alloc: std.mem.Allocator, font: *z2d.Font, size: f64, len: usize) !Rasterizer {
        const width: i32 = @as(i32, @intFromFloat(@as(f64, @ceil(size * @as(f64, @floatFromInt(len)) * 2.0)))) + 16;
        const height: i32 = @as(i32, @intFromFloat(@as(f64, @ceil(size * 2.0)))) + 16;

        var surface = try z2d.Surface.initPixel(
            .{ .rgba = .{ .r = 255, .g = 255, .b = 255, .a = 255 } },
            alloc,
            width,
            height,
        );
        errdefer surface.deinit(alloc);

        return .{
            .alloc = alloc,
            .surface = surface,
            .font = font,
            .width = width,
            .height = height,
            .size = size,
        };
    }

    fn deinit(self: *Rasterizer) void {
        self.surface.deinit(self.alloc);
    }

    /// Draws `text` at the origin and returns the pixels it inked, or null if
    /// it inked nothing. Ink is detected as coverage of at least half a pixel,
    /// which keeps the antialiased fringe from inflating the box while still
    /// tracking the outline's real extent.
    fn measure(self: *Rasterizer, text: []const u8) !?InkBox {
        const pattern: z2d.pattern.Pattern = .{ .opaque_pattern = .{ .pixel = .{ .rgba = .{ .r = 0, .g = 0, .b = 0, .a = 255 } } } };
        try z2d.text.show(self.alloc, &self.surface, &pattern, self.font, text, 0, 0, .{ .size = self.size });

        var x_min: ?i32 = null;
        var x_max: i32 = 0;
        var y_min: ?i32 = null;
        var y_max: i32 = 0;
        var y: i32 = 0;
        while (y < self.height) : (y += 1) {
            const row = self.surface.getStride(0, y, @intCast(self.width)).rgba;
            var x: i32 = 0;
            while (x < self.width) : (x += 1) {
                if (row[@intCast(x)].r < 128) {
                    if (x_min == null or x < x_min.?) x_min = x;
                    if (x > x_max) x_max = x;
                    if (y_min == null) y_min = y;
                    y_max = y;
                }
            }
        }

        if (x_min == null) return null;
        // Pixel `n` covers the unit interval `[n, n + 1)`, so the last inked
        // pixel ends where the following one would start.
        return .{
            .x0 = @floatFromInt(x_min.?),
            .y0 = @floatFromInt(y_min.?),
            .x1 = @as(f64, @floatFromInt(x_max)) + 1.0,
            .y1 = @as(f64, @floatFromInt(y_max)) + 1.0,
        };
    }
};

/// Per-render store of measured ink boxes, keyed by font, size and string.
/// Labels repeat heavily in a plot (one per tick, many ticks per axis), so
/// measuring once per distinct label keeps this to a handful of tiny rasters.
pub const Cache = struct {
    alloc: std.mem.Allocator,
    entries: std.StringHashMapUnmanaged(InkBox) = .empty,
    /// The one font in use. A figure resolves a single font, so holding one
    /// here keeps every measurement from re-reading the font file.
    font: ?z2d.Font = null,
    font_path: []const u8 = "",
    /// True when `font` borrows the embedded default's static memory, which
    /// must never be freed.
    font_builtin: bool = false,
    /// Set once a font fails to load, so a bad path is not retried per label.
    font_broken: bool = false,

    pub fn init(alloc: std.mem.Allocator) Cache {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Cache) void {
        var it = self.entries.keyIterator();
        while (it.next()) |key| self.alloc.free(key.*);
        self.entries.deinit(self.alloc);
        if (self.font) |*font| {
            if (!self.font_builtin) font.deinit(self.alloc);
        }
    }

    /// Returns the ink box of `text` in `font_path` at `size`, measuring it on
    /// first use. `fallback` is returned when the string cannot be rasterized
    /// (an unloadable font, or a surface allocation failure), so callers keep
    /// working off the estimate rather than losing the label.
    pub fn get(
        self: *Cache,
        io: std.Io,
        font_path: []const u8,
        size: f64,
        text: []const u8,
        fallback: InkBox,
    ) InkBox {
        const key = std.fmt.allocPrint(self.alloc, "{s}\x00{d}\x00{s}", .{
            font_path,
            size,
            text,
        }) catch return fallback;
        if (self.entries.get(key)) |cached| {
            self.alloc.free(key);
            return cached;
        }

        var box = fallback;
        if (self.loadFont(io, font_path)) |font| {
            if (Rasterizer.init(self.alloc, font, size, text.len)) |raster| {
                var r = raster;
                defer r.deinit();
                if (r.measure(text) catch null) |measured| box = measured;
            } else |_| {}
        } else {}

        self.entries.put(self.alloc, key, box) catch self.alloc.free(key);
        return box;
    }

    /// Loads `font_path` if it isn't the font already held. Returns null if
    /// the font is unavailable, in which case the caller falls back to the
    /// estimate.
    fn loadFont(self: *Cache, io: std.Io, font_path: []const u8) ?*z2d.Font {
        if (self.font != null and std.mem.eql(u8, self.font_path, font_path)) return &self.font.?;
        if (self.font_broken and std.mem.eql(u8, self.font_path, font_path)) return null;
        if (self.font) |*font| {
            // The embedded default borrows static memory, so only heap-loaded
            // fonts may be freed.
            if (!self.font_builtin) font.deinit(self.alloc);
        }
        self.font_builtin = std.mem.eql(u8, font_path, default_font_path);
        self.font = openFont(io, self.alloc, font_path) catch {
            self.font_broken = true;
            self.font_path = font_path;
            return null;
        };
        self.font_broken = false;
        self.font_path = font_path;
        return &self.font.?;
    }
};

/// The default font (Hack) is embedded so text renders identically everywhere
/// instead of depending on a system font being installed. zsat resolves
/// "default" to `default_font_path`, the sentinel below, and loads the data
/// with `openFont`.
pub const default_font_data: []const u8 = @embedFile("assets/Hack-Regular.ttf");

/// Sentinel standing in for a filesystem path when the embedded font is used,
/// so the cache and layout code keep treating fonts as path-keyed.
pub const default_font_path = "<builtin:Hack-Regular>";

/// Loads a font from `font_path`, resolving the sentinel to the embedded
/// default. The buffer variant borrows `default_font_data`, so a returned
/// buffer font must not be deinitialized.
pub fn openFont(io: std.Io, alloc: std.mem.Allocator, font_path: []const u8) !z2d.Font {
    if (std.mem.eql(u8, font_path, default_font_path)) {
        return z2d.Font.loadBuffer(default_font_data);
    }
    return z2d.Font.loadFile(io, alloc, font_path);
}

/// Sets `context`'s font from `font_path`, resolving the sentinel to the
/// embedded default. A load error is swallowed so callers can still draw the
/// rest of the figure.
pub fn setContextFont(context: *z2d.Context, font_path: []const u8) void {
    if (std.mem.eql(u8, font_path, default_font_path)) {
        context.setFontToBuffer(default_font_data) catch {};
    } else {
        context.setFontToFile(font_path) catch {};
    }
}

test "ink box tracks the drawn glyphs for the default font" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    // The default font's digits sit well below the origin and to the right of
    // the pen, which is what makes the naive 0.6 * size estimate wrong.
    var cache = Cache.init(alloc);
    defer cache.deinit();

    const box = cache.get(io, default_font_path, 40, "0", .{ .x0 = 0, .y0 = 0, .x1 = 0, .y1 = 0 });

    try std.testing.expect(box.x0 > 0.0); // digits have a left side bearing
    try std.testing.expect(box.y0 > 0.0); // and grow downward from the origin
    try std.testing.expect(box.y1 > box.y0);
    try std.testing.expect(box.x1 > box.x0);
    // Hack's digit ink runs 0.2578em to 1.0142em below the em box top, so the
    // ink middle is 0.636em down -- not the 0.6em the old estimate assumed.
    try std.testing.expectApproxEqAbs(0.2578 * 40, box.y0, 1.5);
    try std.testing.expectApproxEqAbs(1.0142 * 40, box.y1, 1.5);
    try std.testing.expectApproxEqAbs(0.6360 * 40, box.midY(), 1.5);
}

test "a longer label measures wider than a single digit" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    var cache = Cache.init(alloc);
    defer cache.deinit();

    const one = cache.get(io, default_font_path, 20, "1", .{ .x0 = 0, .y0 = 0, .x1 = 0, .y1 = 0 });
    const four = cache.get(io, default_font_path, 20, "1.00", .{ .x0 = 0, .y0 = 0, .x1 = 0, .y1 = 0 });

    try std.testing.expect(four.x1 > one.x1);
    try std.testing.expect(four.x0 >= one.x0);
    // A decimal point sits near the baseline, so it extends the ink lower than
    // a digit does -- the ink box has to be measured, not derived from the
    // advance width.
    try std.testing.expect(four.y1 >= one.y1);
}

test "ink boxes are cached per font, size and string" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    var cache = Cache.init(alloc);
    defer cache.deinit();

    const first = cache.get(io, default_font_path, 20, "1.0", .{ .x0 = 0, .y0 = 0, .x1 = 0, .y1 = 0 });
    const second = cache.get(io, default_font_path, 20, "1.0", .{ .x0 = 0, .y0 = 0, .x1 = 0, .y1 = 0 });
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(@as(usize, 1), cache.entries.count());

    // A different size is a different key.
    _ = cache.get(io, default_font_path, 21, "1.0", .{ .x0 = 0, .y0 = 0, .x1 = 0, .y1 = 0 });
    try std.testing.expectEqual(@as(usize, 2), cache.entries.count());
}

test "an unloadable font falls back to the estimate" {
    const alloc = std.testing.allocator;
    var cache = Cache.init(alloc);
    defer cache.deinit();

    const estimate = text_metrics_estimate();
    const box = cache.get(std.testing.io, "/nonexistent/font.ttf", 20, "1.0", estimate);
    try std.testing.expectEqual(estimate, box);
}

fn text_metrics_estimate() InkBox {
    return .{ .x0 = 0, .x1 = 24, .y0 = 0, .y1 = 12 };
}
