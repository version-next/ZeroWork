const std = @import("std");

pub const capacity = 2048;
const Rect = [4]f32; // left, top, right, bottom

fn plainRect(item: anytype) ?Rect {
    if (item.kind != .rect or item.shape_kind != 0 or item.use_draw_transform or
        item.stroke_width != 0 or item.noise_intensity != 0 or item.blend_mode != 0 or
        (item.opacity != 0 and item.opacity != 1)) return null;
    for (item.radii.toArray()) |radius| if (radius != 0) return null;
    for (item.border_widths) |width| if (width != 0) return null;
    const geom = item.geom;
    if (geom.w <= 0 or geom.h <= 0) return null;
    const rect = Rect{ geom.x, geom.y, geom.x + geom.w, geom.y + geom.h };
    for (rect) |edge| if (!std.math.isFinite(edge)) return null;
    return rect;
}

/// A paint-time mask for one full main-target encode. No information from
/// this pass is stored in retained layers or their content fingerprints.
pub fn plan(commands: anytype, scale: f32, mask: *[capacity]bool) []const bool {
    if (commands.len < 2 or commands.len > mask.len or !(scale > 0) or !std.math.isFinite(scale)) return &.{};
    const culled = mask[0..commands.len];
    @memset(culled, false);
    var any = false;
    var cover: ?Rect = null;
    var depth: usize = 0;
    const margin = 3 / scale; // both the occluder's and the victim's AA fringe
    var i = commands.len;
    while (i > 0) {
        i -= 1;
        const item = commands[i];
        if (item.kind == .control) {
            cover = null;
            switch (item.control_kind) {
                .pop_clip, .end_opacity_layer, .end_blur_layer, .end_rounded_clip => depth += 1,
                .push_clip, .begin_opacity_layer, .begin_blur_layer, .begin_rounded_clip => {
                    if (depth == 0) return &.{};
                    depth -= 1;
                },
                .none => {},
            }
            continue;
        }
        if (depth != 0) continue;
        const rect = plainRect(item) orelse continue;
        if (item.color.a == 255) {
            cover = rect;
        } else if (item.color.a > 0) {
            if (cover) |occluder| {
                if (rect[0] >= occluder[0] + margin and rect[1] >= occluder[1] + margin and
                    rect[2] <= occluder[2] - margin and rect[3] <= occluder[3] - margin)
                {
                    culled[i] = true;
                    any = true;
                }
            }
        }
    }
    return if (depth == 0 and any) culled else &.{};
}

test "opaque cover drops translucent fills only inside its fringe and never across backdrop reads" {
    const Item = struct {
        kind: enum { rect, control } = .rect,
        control_kind: enum { none, pop_clip, end_opacity_layer, end_blur_layer, end_rounded_clip, push_clip, begin_opacity_layer, begin_blur_layer, begin_rounded_clip } = .none,
        color: struct { a: u8 } = .{ .a = 150 },
        geom: struct { x: f32 = 10, y: f32 = 10, w: f32 = 50, h: f32 = 50 } = .{},
        shape_kind: u8 = 0,
        use_draw_transform: bool = false,
        stroke_width: f32 = 0,
        noise_intensity: f32 = 0,
        blend_mode: u8 = 0,
        opacity: f32 = 0,
        radii: struct {
            fn toArray(_: @This()) [4]f32 {
                return @splat(0);
            }
        } = .{},
        border_widths: [4]f32 = @splat(0),
    };
    const cover: Item = .{ .color = .{ .a = 255 }, .geom = .{ .x = 0, .y = 0, .w = 100, .h = 100 } };
    const edge: Item = .{ .geom = .{ .x = 1 } };
    var mask: [capacity]bool = undefined;
    try std.testing.expectEqualSlices(bool, &.{ true, false, false }, plan(&[_]Item{ .{}, edge, cover }, 1, &mask));
    try std.testing.expectEqual(@as(usize, 0), plan(&[_]Item{
        .{},                                                    .{ .kind = .control, .control_kind = .begin_blur_layer },
        .{ .kind = .control, .control_kind = .end_blur_layer }, cover,
    }, 1, &mask).len);
    try std.testing.expectEqual(@as(usize, 0), plan(&[_]Item{
        .{ .kind = .control, .control_kind = .push_clip }, .{}, cover,
        .{ .kind = .control, .control_kind = .pop_clip },
    }, 1, &mask).len);
}
