const std = @import("std");
const z2d = @import("z2d");
const inputs = @import("plot_types");

const Vector = inputs.Vector;
const InputElement = inputs.InputElement;
const InputElementRow = inputs.InputElementRow;
const Inputs = inputs.Inputs;
const ValsRange = inputs.ValsRange;
const determine_pane_bounds = inputs.determine_pane_bounds;
const determine_pane_bounds_with_end = inputs.determine_pane_bounds_with_end;

fn getAnchorPoint(transformationPairs: anytype, output_index: usize) ?Vector {
    if (transformationPairs.len == 0 or output_index >= transformationPairs.len) {
        return null;
    }
    const pair = transformationPairs[output_index];
    const ops = pair.operation.ops;
    if (ops.len == 0) {
        return null;
    }
    var last_pin: ?Vector = null;
    for (ops) |op| {
        if (@as(u1, @intFromBool(op == .pin)) == 1) {
            if (@as(u1, @intFromBool(op.pin.point == .point)) == 1) {
                const p = op.pin.point.point;
                last_pin = Vector{ .x = p.x, .y = p.y };
            }
        }
    }
    return last_pin;
}

pub const RenderedImage = struct {
    pixels: []z2d.pixel.RGBA,
    width: i32,
    height: i32,
    allocator: std.mem.Allocator,
};

pub fn plot_via_z2d(parsed_data: anytype, output_path: ?[]const u8) !RenderedImage {
    if (parsed_data.panes.len == 0) {
        return error.NoPanes;
    }
    const pane = parsed_data.panes[0];
    var width: i32 = 600;
    var height: i32 = 600;
    if (pane.paneValue.paneSize) |s| {
        width = @intCast(s.width);
        height = @intCast(s.height);
    }

    var surface = try z2d.Surface.init(.image_surface_rgba, std.heap.page_allocator, width, height);
    defer surface.deinit(std.heap.page_allocator);

    var context = z2d.Context.init(std.heap.page_allocator, &surface);

    context.setSourceToPixel(.{ .rgba = .{ .r = 255, .g = 255, .b = 255, .a = 255 } });
    context.setLineWidth(0.0); // Disable stroke during fill
    try context.moveTo(0, 0);
    try context.lineTo(@floatFromInt(width), 0);
    try context.lineTo(@floatFromInt(width), @floatFromInt(height));
    try context.lineTo(0, @floatFromInt(height));
    try context.closePath();
    try context.fill();
    context.setLineWidth(10.0); // Re-enable for data lines
    context.resetPath(); // Clear path state after fill

    const outputs = parsed_data.outputs;
    const input_data = parsed_data.inputs;
    const coord_orientations = parsed_data.coord_orientations;

    var minX: f32 = 0.0;
    var maxX: f32 = 0.0;
    var minY: f32 = 0.0;
    var maxY: f32 = 0.0;
    var boundsInitialized = false;

    // Iterate over all outputs to find bounds
    for (outputs.transformationPairs, 0..) |pair, row_idx| {
        const ops = pair.operation.ops;

        if (ops.len >= 2) {
            for (0..ops.len / 2) |seg_idx| {
                const start_op = ops[seg_idx * 2];
                const end_op = ops[seg_idx * 2 + 1];

                if (start_op == .pin and start_op.pin.point == .point and
                    end_op == .pin and end_op.pin.point == .point)
                {
                    const sx = start_op.pin.point.point.x;
                    const sy = start_op.pin.point.point.y;
                    const ex = end_op.pin.point.point.x;
                    const ey = end_op.pin.point.point.y;

                    if (!boundsInitialized) {
                        minX = sx;
                        maxX = sx;
                        minY = sy;
                        maxY = sy;
                        boundsInitialized = true;
                    }
                    if (sx < minX) minX = sx;
                    if (sx > maxX) maxX = sx;
                    if (sy < minY) minY = sy;
                    if (sy > maxY) maxY = sy;
                    if (ex < minX) minX = ex;
                    if (ex > maxX) maxX = ex;
                    if (ey < minY) minY = ey;
                    if (ey > maxY) maxY = ey;
                }
            }
        } else if (ops.len == 1) {
            const start_op = ops[0];
            if (start_op == .pin and start_op.pin.point == .point) {
                const anchor_x: f32 = start_op.pin.point.point.x;
                const anchor_y: f32 = start_op.pin.point.point.y;
                var cur_x: f32 = anchor_x;
                var cur_y: f32 = anchor_y;
                if (row_idx < input_data.input.len) {
                    const input_row = input_data.input[row_idx];
                    for (input_row.row) |input_elem| {
                        if (input_elem == .vector) {
                            cur_x += input_elem.vector.x;
                            cur_y += input_elem.vector.y;
                        } else if (input_elem == .point) {
                            cur_x = input_elem.point.x;
                            cur_y = input_elem.point.y;
                        }
                        if (!boundsInitialized) {
                            minX = cur_x;
                            maxX = cur_x;
                            minY = cur_y;
                            maxY = cur_y;
                            boundsInitialized = true;
                        }
                        if (cur_x < minX) minX = cur_x;
                        if (cur_x > maxX) maxX = cur_x;
                        if (cur_y < minY) minY = cur_y;
                        if (cur_y > maxY) maxY = cur_y;
                    }
                }
                // Also include anchor
                if (!boundsInitialized) {
                    minX = anchor_x;
                    maxX = anchor_x;
                    minY = anchor_y;
                    maxY = anchor_y;
                    boundsInitialized = true;
                }
                if (anchor_x < minX) minX = anchor_x;
                if (anchor_x > maxX) maxX = anchor_x;
                if (anchor_y < minY) minY = anchor_y;
                if (anchor_y > maxY) maxY = anchor_y;
            }
        }
    }

    if (!boundsInitialized) {
        minX = 0;
        maxX = 1;
        minY = 0;
        maxY = 1;
    }

    const bounds = ValsRange{ .x = .{ minX, maxX }, .y = .{ minY, maxY } };
    std.debug.print("DEBUG bounds: x=[{}, {}], y=[{}, {}]\n", .{ bounds.x[0], bounds.x[1], bounds.y[0], bounds.y[1] });
    const x_range = bounds.x[1] - bounds.x[0];
    const y_range = bounds.y[1] - bounds.y[0];

    const margin: f64 = 20.0;
    const draw_width = @as(f64, @floatFromInt(width)) - 2 * margin;
    const draw_height = @as(f64, @floatFromInt(height)) - 2 * margin;

    if (x_range >= 0 and y_range >= 0) {
        const rX = if (x_range > 0) draw_width / @as(f64, x_range) else draw_width;
        const rY = if (y_range > 0) draw_height / @as(f64, y_range) else draw_height;

        const x_scale = rX;
        const y_scale = rY;

        const origin_x = margin - @as(f64, bounds.x[0]) * x_scale;
        const origin_y = @as(f64, @floatFromInt(height)) - margin;
        const min_y = margin;
        const max_y = @as(f64, @floatFromInt(height)) - margin;

        const mappings = parsed_data.datum.mappings;

        for (parsed_data.inputs.input, 0..) |_, row_idx| {
            var style_idx: usize = 0;
            for (mappings) |mapping| {
                if (mapping.from == row_idx) {
                    style_idx = mapping.to;
                    break;
                }
            }

            // Extract style
            var line_width: f64 = 10.0;
            var line_r: u8 = 0;
            var line_g: u8 = 0;
            var line_b: u8 = 0;
            var line_a: u8 = 255;
            var line_cap_mode: z2d.options.CapMode = .butt;
            var line_join_mode: z2d.options.JoinMode = .miter;

            if (style_idx < parsed_data.styles.len) {
                const style = parsed_data.styles[style_idx];
                if (style.styleValue.attributes) |attrs| {
                    const lw = attrs.lineWidth;
                    switch (lw.reference) {
                        .normalized => {
                            const h2: f64 = @floatFromInt(height);
                            const v: f64 = @floatFromInt(lw.value);
                            line_width = v * h2 / 1000.0;
                        },
                        .global => {
                            const v: f64 = @floatFromInt(lw.value);
                            line_width = v / 10.0;
                        },
                        .output => {
                            const v: f64 = @floatFromInt(lw.value);
                            line_width = v;
                        },
                        .local => {
                            const v: f64 = @floatFromInt(lw.value);
                            line_width = v / 10.0;
                        },
                    }
                    const lc = attrs.lineColor;
                    const rgb = colorNameToRGB(lc.value);
                    line_r = rgb.r;
                    line_g = rgb.g;
                    line_b = rgb.b;
                    const alpha: u16 = @intCast(@as(u16, attrs.lineOpacity.value) * 255 / 100);
                    line_r = @intCast(@as(u16, line_r) * alpha / 255);
                    line_g = @intCast(@as(u16, line_g) * alpha / 255);
                    line_b = @intCast(@as(u16, line_b) * alpha / 255);
                    line_a = @intCast(alpha);

                    if (attrs.lineDashing) |ld| {
                        var dashes = try std.heap.page_allocator.alloc(f64, ld.onOff.len);
                        for (ld.onOff, 0..) |val, i| {
                            dashes[i] = @floatFromInt(val);
                        }
                        context.setDashes(dashes);
                        const offset_px: f64 = @floatFromInt(ld.offset);
                        context.setDashOffset(offset_px);
                    } else {
                        context.setDashes(&.{});
                        context.setDashOffset(0);
                    }

                    const cap = attrs.lineCap.value;
                    line_cap_mode = switch (cap) {
                        .none => .butt,
                        .butt => .butt,
                        .round => .round,
                        .square => .square,
                    };

                    const join = attrs.lineJoin.value;
                    line_join_mode = switch (join) {
                        .none => .miter,
                        .mitter => .miter,
                        .round => .round,
                        .bevel => .bevel,
                    };
                }
            }

            context.setSourceToPixel(.{ .rgba = .{ .r = line_r, .g = line_g, .b = line_b, .a = line_a } });
            context.setLineWidth(line_width);
            context.setLineCapMode(line_cap_mode);
            context.setLineJoinMode(line_join_mode);

            const orientation = if (row_idx < coord_orientations.len) coord_orientations[row_idx] else .fixed;

            if (row_idx < outputs.transformationPairs.len) {
                const pair = outputs.transformationPairs[row_idx];
                const ops = pair.operation.ops;

                if (ops.len >= 2) {
                    if (orientation == .origin) {
                        // Origin mode: use last two ops
                        const start_op = ops[ops.len - 2];
                        const end_op = ops[ops.len - 1];
                        if (start_op == .pin and start_op.pin.point == .point and
                            end_op == .pin and end_op.pin.point == .point)
                        {
                            const sx = @as(f64, start_op.pin.point.point.x);
                            const sy = @as(f64, start_op.pin.point.point.y);
                            const ex = @as(f64, end_op.pin.point.point.x);
                            const ey = @as(f64, end_op.pin.point.point.y);

                            context.resetPath();
                            var cur_x = origin_x + sx * x_scale;
                            var cur_y = origin_y - sy * y_scale;
                            try context.moveTo(cur_x, cur_y);
                            cur_x = origin_x + ex * x_scale;
                            cur_y = origin_y - ey * y_scale;
                            if (cur_y < min_y) cur_y = min_y;
                            if (cur_y > max_y) cur_y = max_y;
                            try context.lineTo(cur_x, cur_y);
                            try context.stroke();
                        }
                    } else {
                        // Fixed mode: only the last segment is visualized
                        const start_op = ops[ops.len - 2];
                        const end_op = ops[ops.len - 1];
                        if (start_op == .pin and start_op.pin.point == .point and
                            end_op == .pin and end_op.pin.point == .point)
                        {
                            const sx = @as(f64, start_op.pin.point.point.x);
                            const sy = @as(f64, start_op.pin.point.point.y);
                            const ex = @as(f64, end_op.pin.point.point.x);
                            const ey = @as(f64, end_op.pin.point.point.y);

                            context.resetPath();
                            const cur_x = origin_x + sx * x_scale;
                            const cur_y = origin_y - sy * y_scale;
                            try context.moveTo(cur_x, cur_y);
                            const line_x = origin_x + ex * x_scale;
                            var line_y = origin_y - ey * y_scale;
                            if (line_y < min_y) line_y = min_y;
                            if (line_y > max_y) line_y = max_y;
                            try context.lineTo(line_x, line_y);
                            try context.stroke();
                        }
                    }
                } else if (ops.len == 1) {
                    // Single anchor: draw polyline through all input vectors
                    const start_op = ops[0];
                    if (start_op == .pin and start_op.pin.point == .point) {
                        var anchor_x = @as(f64, start_op.pin.point.point.x);
                        var anchor_y = @as(f64, start_op.pin.point.point.y);
                        const cur_x = origin_x + anchor_x * x_scale;
                        const cur_y = origin_y - anchor_y * y_scale;

                        context.resetPath();
                        try context.moveTo(cur_x, cur_y);

                        if (row_idx < input_data.input.len) {
                            const input_row = input_data.input[row_idx];
                            for (input_row.row) |input_elem| {
                                if (input_elem == .vector) {
                                    anchor_x += @as(f64, input_elem.vector.x);
                                    anchor_y += @as(f64, input_elem.vector.y);
                                } else if (input_elem == .point) {
                                    anchor_x = @as(f64, input_elem.point.x);
                                    anchor_y = @as(f64, input_elem.point.y);
                                }
                                const plot_x = origin_x + anchor_x * x_scale;
                                var plot_y = origin_y - anchor_y * y_scale;
                                if (plot_y < min_y) plot_y = min_y;
                                if (plot_y > max_y) plot_y = max_y;
                                try context.lineTo(plot_x, plot_y);
                            }
                        }
                        try context.stroke();
                    }
                }
            }
        }
    }

    if (output_path) |filename| {
        try z2d.png_exporter.writeToPNGFile(surface, filename, .{});
    }

    const pixels = switch (surface) {
        .image_surface_rgba => |s| s.buf,
        else => unreachable,
    };
    const duped = try std.heap.page_allocator.dupe(z2d.pixel.RGBA, pixels);

    return .{
        .pixels = duped,
        .width = width,
        .height = height,
        .allocator = std.heap.page_allocator,
    };
}

fn colorNameToRGB(c: anytype) struct { r: u8, g: u8, b: u8 } {
    return switch (c) {
        .aliceblue => .{ .r = 240, .g = 248, .b = 255 },
        .antiquewhite => .{ .r = 250, .g = 235, .b = 215 },
        .aqua => .{ .r = 0, .g = 255, .b = 255 },
        .aquamarine => .{ .r = 127, .g = 255, .b = 212 },
        .azure => .{ .r = 240, .g = 255, .b = 255 },
        .beige => .{ .r = 245, .g = 245, .b = 220 },
        .bisque => .{ .r = 255, .g = 228, .b = 196 },
        .black => .{ .r = 0, .g = 0, .b = 0 },
        .blanchedalmond => .{ .r = 255, .g = 235, .b = 205 },
        .blue => .{ .r = 0, .g = 0, .b = 255 },
        .blueviolet => .{ .r = 138, .g = 43, .b = 226 },
        .brown => .{ .r = 165, .g = 42, .b = 42 },
        .burlywood => .{ .r = 222, .g = 184, .b = 135 },
        .cadetblue => .{ .r = 95, .g = 158, .b = 160 },
        .chartreuse => .{ .r = 127, .g = 255, .b = 0 },
        .chocolate => .{ .r = 210, .g = 105, .b = 30 },
        .coral => .{ .r = 255, .g = 127, .b = 80 },
        .cornflowerblue => .{ .r = 100, .g = 149, .b = 237 },
        .cornsilk => .{ .r = 255, .g = 248, .b = 220 },
        .crimson => .{ .r = 220, .g = 20, .b = 60 },
        .cyan => .{ .r = 0, .g = 255, .b = 255 },
        .darkblue => .{ .r = 0, .g = 0, .b = 139 },
        .darkcyan => .{ .r = 0, .g = 139, .b = 139 },
        .darkgoldenrod => .{ .r = 184, .g = 134, .b = 11 },
        .darkgray => .{ .r = 169, .g = 169, .b = 169 },
        .darkgreen => .{ .r = 0, .g = 100, .b = 0 },
        .darkgrey => .{ .r = 169, .g = 169, .b = 169 },
        .darkkhaki => .{ .r = 189, .g = 183, .b = 107 },
        .darkmagenta => .{ .r = 139, .g = 0, .b = 139 },
        .darkolivegreen => .{ .r = 85, .g = 107, .b = 47 },
        .darkorange => .{ .r = 255, .g = 140, .b = 0 },
        .darkorchid => .{ .r = 153, .g = 50, .b = 204 },
        .darkred => .{ .r = 139, .g = 0, .b = 0 },
        .darksalmon => .{ .r = 233, .g = 150, .b = 122 },
        .darkseagreen => .{ .r = 143, .g = 188, .b = 143 },
        .darkslateblue => .{ .r = 72, .g = 61, .b = 139 },
        .darkslategray => .{ .r = 47, .g = 79, .b = 79 },
        .darkslategrey => .{ .r = 47, .g = 79, .b = 79 },
        .darkturquoise => .{ .r = 0, .g = 206, .b = 209 },
        .darkviolet => .{ .r = 148, .g = 0, .b = 211 },
        .deeppink => .{ .r = 255, .g = 20, .b = 147 },
        .deepskyblue => .{ .r = 0, .g = 191, .b = 255 },
        .dimgray => .{ .r = 105, .g = 105, .b = 105 },
        .dimgrey => .{ .r = 105, .g = 105, .b = 105 },
        .dodgerblue => .{ .r = 30, .g = 144, .b = 255 },
        .firebrick => .{ .r = 178, .g = 34, .b = 34 },
        .floralwhite => .{ .r = 255, .g = 250, .b = 240 },
        .forestgreen => .{ .r = 34, .g = 139, .b = 34 },
        .fuchsia => .{ .r = 255, .g = 0, .b = 255 },
        .gainsboro => .{ .r = 220, .g = 220, .b = 220 },
        .ghostwhite => .{ .r = 248, .g = 248, .b = 255 },
        .gold => .{ .r = 255, .g = 215, .b = 0 },
        .goldenrod => .{ .r = 218, .g = 165, .b = 32 },
        .gray => .{ .r = 128, .g = 128, .b = 128 },
        .green => .{ .r = 0, .g = 128, .b = 0 },
        .greenyellow => .{ .r = 173, .g = 255, .b = 47 },
        .grey => .{ .r = 128, .g = 128, .b = 128 },
        .honeydew => .{ .r = 240, .g = 255, .b = 240 },
        .hotpink => .{ .r = 255, .g = 105, .b = 180 },
        .indianred => .{ .r = 205, .g = 92, .b = 92 },
        .indigo => .{ .r = 75, .g = 0, .b = 130 },
        .ivory => .{ .r = 255, .g = 255, .b = 240 },
        .khaki => .{ .r = 240, .g = 230, .b = 140 },
        .lavender => .{ .r = 230, .g = 230, .b = 250 },
        .lavenderblush => .{ .r = 255, .g = 240, .b = 245 },
        .lawngreen => .{ .r = 124, .g = 252, .b = 0 },
        .lemonchiffon => .{ .r = 255, .g = 250, .b = 205 },
        .lightblue => .{ .r = 173, .g = 216, .b = 230 },
        .lightcoral => .{ .r = 240, .g = 128, .b = 128 },
        .lightcyan => .{ .r = 224, .g = 255, .b = 255 },
        .lightgoldenrodyellow => .{ .r = 250, .g = 250, .b = 210 },
        .lightgray => .{ .r = 211, .g = 211, .b = 211 },
        .lightgreen => .{ .r = 144, .g = 238, .b = 144 },
        .lightgrey => .{ .r = 211, .g = 211, .b = 211 },
        .lightpink => .{ .r = 255, .g = 182, .b = 193 },
        .lightsalmon => .{ .r = 255, .g = 160, .b = 122 },
        .lightseagreen => .{ .r = 32, .g = 178, .b = 170 },
        .lightskyblue => .{ .r = 135, .g = 206, .b = 250 },
        .lightslategray => .{ .r = 119, .g = 136, .b = 153 },
        .lightslategrey => .{ .r = 119, .g = 136, .b = 153 },
        .lightsteelblue => .{ .r = 176, .g = 196, .b = 222 },
        .lightyellow => .{ .r = 255, .g = 255, .b = 224 },
        .lime => .{ .r = 0, .g = 255, .b = 0 },
        .limegreen => .{ .r = 50, .g = 205, .b = 50 },
        .linen => .{ .r = 250, .g = 240, .b = 230 },
        .magenta => .{ .r = 255, .g = 0, .b = 255 },
        .maroon => .{ .r = 128, .g = 0, .b = 0 },
        .mediumaquamarine => .{ .r = 102, .g = 205, .b = 170 },
        .mediumblue => .{ .r = 0, .g = 0, .b = 205 },
        .mediumorchid => .{ .r = 186, .g = 85, .b = 211 },
        .mediumpurple => .{ .r = 147, .g = 112, .b = 219 },
        .mediumseagreen => .{ .r = 60, .g = 179, .b = 113 },
        .mediumslateblue => .{ .r = 123, .g = 104, .b = 238 },
        .mediumspringgreen => .{ .r = 0, .g = 250, .b = 154 },
        .mediumturquoise => .{ .r = 72, .g = 209, .b = 204 },
        .mediumvioletred => .{ .r = 199, .g = 21, .b = 133 },
        .midnightblue => .{ .r = 25, .g = 25, .b = 112 },
        .mintcream => .{ .r = 245, .g = 255, .b = 250 },
        .mistyrose => .{ .r = 255, .g = 228, .b = 225 },
        .moccasin => .{ .r = 255, .g = 228, .b = 181 },
        .navajowhite => .{ .r = 255, .g = 222, .b = 173 },
        .navy => .{ .r = 0, .g = 0, .b = 128 },
        .oldlace => .{ .r = 253, .g = 245, .b = 230 },
        .olive => .{ .r = 128, .g = 128, .b = 0 },
        .olivedrab => .{ .r = 107, .g = 142, .b = 35 },
        .orange => .{ .r = 255, .g = 165, .b = 0 },
        .orangered => .{ .r = 255, .g = 69, .b = 0 },
        .orchid => .{ .r = 218, .g = 112, .b = 214 },
        .palegoldenrod => .{ .r = 238, .g = 232, .b = 170 },
        .palegreen => .{ .r = 152, .g = 251, .b = 152 },
        .paleturquoise => .{ .r = 175, .g = 238, .b = 238 },
        .palevioletred => .{ .r = 219, .g = 112, .b = 147 },
        .papayawhip => .{ .r = 255, .g = 239, .b = 213 },
        .peachpuff => .{ .r = 255, .g = 218, .b = 185 },
        .peru => .{ .r = 205, .g = 133, .b = 63 },
        .pink => .{ .r = 255, .g = 192, .b = 203 },
        .plum => .{ .r = 221, .g = 160, .b = 221 },
        .powderblue => .{ .r = 176, .g = 224, .b = 230 },
        .purple => .{ .r = 128, .g = 0, .b = 128 },
        .rebeccapurple => .{ .r = 102, .g = 51, .b = 153 },
        .red => .{ .r = 255, .g = 0, .b = 0 },
        .rosybrown => .{ .r = 188, .g = 143, .b = 143 },
        .royalblue => .{ .r = 65, .g = 105, .b = 225 },
        .saddlebrown => .{ .r = 139, .g = 69, .b = 19 },
        .salmon => .{ .r = 250, .g = 128, .b = 114 },
        .sandybrown => .{ .r = 244, .g = 164, .b = 96 },
        .seagreen => .{ .r = 46, .g = 139, .b = 87 },
        .seashell => .{ .r = 255, .g = 245, .b = 238 },
        .sienna => .{ .r = 160, .g = 82, .b = 45 },
        .silver => .{ .r = 192, .g = 192, .b = 192 },
        .skyblue => .{ .r = 135, .g = 206, .b = 235 },
        .slateblue => .{ .r = 106, .g = 90, .b = 205 },
        .slategray => .{ .r = 112, .g = 128, .b = 144 },
        .slategrey => .{ .r = 112, .g = 128, .b = 144 },
        .snow => .{ .r = 255, .g = 250, .b = 250 },
        .springgreen => .{ .r = 0, .g = 255, .b = 127 },
        .steelblue => .{ .r = 70, .g = 130, .b = 180 },
        .tan => .{ .r = 210, .g = 180, .b = 140 },
        .teal => .{ .r = 0, .g = 128, .b = 128 },
        .thistle => .{ .r = 216, .g = 191, .b = 216 },
        .tomato => .{ .r = 255, .g = 99, .b = 71 },
        .turquoise => .{ .r = 64, .g = 224, .b = 208 },
        .violet => .{ .r = 238, .g = 130, .b = 238 },
        .wheat => .{ .r = 245, .g = 222, .b = 179 },
        .white => .{ .r = 255, .g = 255, .b = 255 },
        .whitesmoke => .{ .r = 245, .g = 245, .b = 245 },
        .yellow => .{ .r = 255, .g = 255, .b = 0 },
        .yellowgreen => .{ .r = 154, .g = 205, .b = 50 },
    };
}
