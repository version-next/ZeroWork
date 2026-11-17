//! HintCapsule: the notification text-hint capsule (`Notifier.hint`) drawn in place.
//!
//!   root (GlassBox, radius 18, width fits the content)
//!   +-- row (36 high, padding 16, gap 8)
//!       +-- chip (success / error mark, optional)
//!       +-- label (13 / 400, one line, ellipsis)
//!
//! Same glass, metrics, ink and marks as the stack's hint capsule, but laid out by the caller in
//! its own tree instead of the window-level notification stack: for a hint that belongs to one
//! surface (centred on the bottom edge of a video card, inside a canvas) rather than to the
//! window. The caller owns position, visibility, timing and fading; the capsule never takes
//! pointer input (no action button, no close, no swipe — use `Notifier.hint` for those).
//!
//! - `text`: the hint (a source);
//! - `mark`: `.none` / `.success` / `.@"error"` (read at mount; `.loading` draws no mark here);
//! - `max_width`: capsule width limit (a source; capped at the stack's 480); a longer text is
//!   truncated with an ellipsis on one line, as in the stack.
//!
//! Zig: `W.HintCapsule(.{ .text = hint, .max_width = room })`.
//! Yix: `<W.HintCapsule text={hint} maxWidth={room} />`.
const std = @import("std");
const core = @import("../../core.zig");
const v = @import("../../view.zig");
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const Source = reactive.Source;
const Cx = core.Cx;
const Node = core.Node;
const theme = core.theme;
const glass_box = @import("../glass_box/mod.zig");
const styles = @import("styles.zig");
const card_mod = @import("card.zig");
const hint_mod = @import("hint.zig");
const H = styles.HintMetrics;
const fixed = core.Sizing.fixed;
const fit: core.Sizing = .{ .fit = .{} };

pub const Mark = hint_mod.Mark;

pub const HintCapsuleProps = struct {
    text: Source([]const u8) = .{ .value = "" },
    /// Read at mount.
    mark: Mark = .none,
    max_width: Source(f32) = .{ .value = H.max_width },
};

/// `W.HintCapsule(.{ .text = "Captured — press ⌃⌥Esc to release" })`.
pub fn HintCapsule(args: anytype) v.ComponentOf(mountCapsule) {
    return v.component(mountCapsule, reactive.props.coerce(HintCapsuleProps, args));
}

fn chipped(mark: Mark) bool {
    return mark == .success or mark == .@"error";
}

/// Label width limit inside a capsule of at most `max_width` (the stack's arithmetic).
pub fn labelLimit(mark: Mark, max_width: f32) f32 {
    const mark_w: f32 = if (chipped(mark)) H.chip + H.gap else 0;
    return @max(0, @min(max_width, H.max_width) - 2 * H.pad_plain - mark_w);
}

fn passThrough(node: *Node) void {
    node.setHitTestVisible(false);
    for (node.children.items) |child| passThrough(child);
}

fn mountCapsule(props: HintCapsuleProps, scope: *Scope, cx: *Cx) anyerror!*Node {
    const pal = styles.palette(cx.tokens);
    const tone = pal.tone(hint_mod.toneOf(props.mark));
    var glass: glass_box.GlassBoxMount = undefined;
    var label: *Node = undefined;
    var chip: ?*Node = null;
    const root_el = v.capture(&glass, v.with(glass_box.GlassBox(.{ .corner_radius = H.radius, .padding = core.Padding.all(0), .body_gap = 0 }), .{
        v.row(.{ .style = core.BoxStyle{
            .width = fit,
            .height = fixed(H.height),
            .align_items = .center,
            .gap = H.gap,
            .padding = .{ .left = H.pad_plain, .right = H.pad_plain },
            .flex_shrink = 0,
        } }, .{
            if (chipped(props.mark)) v.capture(&chip, v.box(.{ .style = core.BoxStyle{
                .width = fixed(H.chip),
                .height = fixed(H.chip),
                .align_items = .center,
                .justify = .center,
                .background = core.Color.TRANSPARENT,
                .border = .{ .overlay = true, .width = 0, .color = tone, .radius = H.chip / 2 },
                .corner_radius = H.chip / 2,
                .flex_shrink = 0,
            } }, v.icon(.{ .style = .{ .width = fixed(H.glyph), .height = fixed(H.glyph) }, .tint = pal.ink }, card_mod.defaultGlyph(hint_mod.toneOf(props.mark))))) else null,
            v.capture(&label, v.attrs(.{ .style = core.BoxStyle{ .flex_shrink = 0, .max_width = labelLimit(props.mark, props.max_width.peek()) } }, v.text(.{ .style = core.TextStyle{
                .color = pal.ink,
                .font_size = H.font,
                .font_weight = H.weight,
                .line_height = 1.4,
                .text_overflow = .ellipsis,
                .wrap = .none,
            } }, props.text))),
        }),
    }));
    const root = try v.render(scope, cx, root_el);
    errdefer cx.freeNode(root);
    root.meta.ownership.meta.component_name = "HintCapsule";
    glass.box.style.width = fit;
    glass.box.style.flex_shrink = 0;
    glass.state.surface.style.overflow_hidden = true;
    glass.box.markSizingDirty();
    passThrough(root);
    try scope.createEffect(.{ .theme_source = try cx.themeSignal(), .label = label, .chip = chip, .mark = props.mark, .max_width = props.max_width, .allocator = cx.allocator }, struct {
        fn paint(c: anytype) void {
            const p = styles.palette(c.theme_source.get());
            const limit = labelLimit(c.mark, c.max_width.get());
            if (c.label.style.max_width() != limit) c.label.setStyleInline(c.allocator, .{ .max_width = limit });
            if (c.label.getText()) |old| if (!std.meta.eql(old.color, p.ink)) {
                var next = old;
                next.color = p.ink;
                c.label.setText(next);
            };
            if (c.chip) |node| {
                node.style.border.color = p.tone(hint_mod.toneOf(c.mark));
                if (node.children.items.len != 0) _ = node.children.items[0].setTint(p.ink);
                node.markRenderDirty();
            }
        }
    }.paint);
    return root;
}

// ===== Tests =====

const testing = std.testing;

fn mounted(scope: *Scope, cx: *Cx, element: anytype) !*Node {
    const root = try v.render(scope, cx, v.col(.{ .style = core.BoxStyle{ .width = fixed(900), .height = fixed(200), .align_items = .start } }, .{element}));
    cx.root = root;
    cx.layout();
    return root.children.items[0];
}

fn findText(node: *Node) ?*Node {
    if (node.getText() != null) return node;
    for (node.children.items) |child| if (findText(child)) |found| return found;
    return null;
}

test "HintCapsule: the stack's 36-high capsule, content-wide, ink follows the theme, never hit" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setTheme(&theme.light);
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const capsule = try mounted(scope, cx, HintCapsule(.{ .text = "Captured" }));
    try testing.expectEqualStrings("HintCapsule", capsule.meta.ownership.meta.component_name.?);
    const r = capsule.rectFromWorldOrFallback();
    try testing.expectApproxEqAbs(@as(f32, H.height), r.h, 0.5);
    try testing.expect(r.w > 2 * H.pad_plain and r.w < 200);
    const label = findText(capsule).?;
    try testing.expectEqualStrings("Captured", label.getText().?.content);
    try testing.expectEqual(theme.light.tokens.color.fg_primary, label.getText().?.color);
    try testing.expect(!capsule.frame_state.state_bits.flags.hit_test_visible);
    try testing.expect(!label.frame_state.state_bits.flags.hit_test_visible);
    cx.setTheme(&theme.dark);
    try testing.expectEqual(theme.dark.tokens.color.fg_primary, label.getText().?.color);
}

test "HintCapsule: max_width bounds a long text (one line, ellipsis) and follows its source" {
    const cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setTheme(&theme.light);
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const room = try scope.createSignal(f32, 300);
    const long = "A very long hint text that certainly does not fit into three hundred points of width at all";
    const capsule = try mounted(scope, cx, HintCapsule(.{ .text = long, .max_width = room, .mark = .success }));
    try testing.expect(capsule.rectFromWorldOrFallback().w <= 300 + 0.5);
    try testing.expectApproxEqAbs(@as(f32, H.height), capsule.rectFromWorldOrFallback().h, 0.5);
    room.set(200);
    cx.layout();
    try testing.expect(capsule.rectFromWorldOrFallback().w <= 200 + 0.5);
    // Never wider than the stack's capsule.
    room.set(2000);
    cx.layout();
    try testing.expect(capsule.rectFromWorldOrFallback().w <= H.max_width + 0.5);
    try testing.expectEqual(@as(f32, H.max_width - 2 * H.pad_plain - H.chip - H.gap), labelLimit(.success, 2000));
}

test "HintCapsule: mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("hint_capsule", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            return try v.render(scope, cx, HintCapsule(.{ .text = "Saved", .mark = .@"error" }));
        }
    }.m);
}
