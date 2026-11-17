/// Empty Component.
/// The empty state of a list, panel or view: optional icon (24, `fg-tertiary`), title (13 / 500,
/// `fg-primary`), description (12, `fg-secondary`, centered, wraps at 280) and an optional single
/// action (secondary sm Button). Fills and centers in the space it is given. View in empty.yix;
/// styles in styles.yss.
const std = @import("std");
const core = @import("../../core.zig");
const Cx = core.Cx;
const Color = core.Color;
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;

/// Create Empty: `W.Empty(.{ .icon = icons.bell, .title = "No alerts", .description = "…" })`.
/// props: icon (null = no glyph) / title / description / action_label (empty = no action) /
/// action_icon_asset / on_action / action_disabled / title_test_id / description_test_id /
/// action_test_id; title / description / action_label / action_disabled take signals.
pub const Empty = @import("_empty.yix.zig").Empty;

// ========== Tests ==========

const view = @import("../../view.zig");
const icons = @import("zenit_icons");

fn harness(cx: *Cx, w: f32, h: f32) !*core.Node {
    const root = try core.box(cx, .{ .width = .{ .px = w }, .height = .{ .px = h }, .direction = .column }, .{});
    cx.root = root;
    return root;
}

test "Empty: icon, title, description centered in the space given; tokens for ink" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const root = try harness(cx, 360, 200);
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const empty = try view.render(scope, cx, Empty(.{ .icon = icons.bell, .title = "No alerts", .description = "Connection and transfer events show here.", .title_test_id = "e.title", .description_test_id = "e.description" }));
    try root.appendChild(std.testing.allocator, empty);
    cx.layout();
    try std.testing.expectEqual(@as(usize, 2), empty.children.items.len);
    const glyph = empty.children.items[0].children.items[0];
    const title = empty.children.items[1].children.items[0].children.items[0];
    const description = empty.children.items[1].children.items[0].children.items[1];
    const r = empty.globalRect();
    try std.testing.expectEqual(@as(f32, 360), r.w);
    try std.testing.expectEqual(@as(f32, 200), r.h);
    try std.testing.expectEqual(@as(f32, 24), glyph.globalRect().w);
    try std.testing.expectEqual(@as(f32, 24), glyph.globalRect().h);
    // horizontally centered
    const g = glyph.globalRect();
    try std.testing.expectApproxEqAbs(r.x + r.w / 2, g.x + g.w / 2, 0.5);
    // vertically centered: the content block sits in the middle
    const top = g.y - r.y;
    const d = description.globalRect();
    const bottom = (r.y + r.h) - (d.y + d.h);
    try std.testing.expectApproxEqAbs(top, bottom, 1.0);
    try std.testing.expectEqualStrings("e.title", title.meta.ownership.meta.test_id.?);
    try std.testing.expectEqualStrings("e.description", description.meta.ownership.meta.test_id.?);
    try std.testing.expect(Color.eql(cx.tokens.tokens.color.fg_primary, title.getTextRaw().?.color));
    try std.testing.expect(Color.eql(cx.tokens.tokens.color.fg_secondary, description.getTextRaw().?.color));
}

test "Empty: no icon and no action = title and description only; no ids written without names" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    _ = try harness(cx, 300, 160);
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const empty = try Empty(.{ .title = "Empty", .description = "Nothing here yet." }).mount(scope, cx);
    defer cx.freeNode(empty);
    try std.testing.expectEqual(@as(usize, 1), empty.children.items.len);
    try std.testing.expect(empty.children.items[0].children.items[0].children.items[0].meta.ownership.meta.test_id == null);
    try std.testing.expect(empty.children.items[0].children.items[0].children.items[1].meta.ownership.meta.test_id == null);
}

test "Empty: the action is a secondary sm Button; click reaches on_action; long description wraps" {
    const cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const root = try harness(cx, 240, 300);
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const Counter = struct {
        n: u32 = 0,
        fn hit(self: *@This()) void {
            self.n += 1;
        }
    };
    var counter: Counter = .{};
    const empty = try view.render(scope, cx, Empty(.{ .icon = icons.info, .title = "Card floated", .description = "The card floats over the window; its session keeps running in this tab, and it can be put back.", .action_label = "Put back", .action_test_id = "e.action", .on_action = cx.on(Counter, &counter, Counter.hit) }));
    try root.appendChild(std.testing.allocator, empty);
    cx.layout();
    try std.testing.expectEqual(@as(usize, 3), empty.children.items.len);
    const description = empty.children.items[1].children.items[0].children.items[1];
    try std.testing.expect(description.globalRect().x >= 0);
    try std.testing.expect(description.globalRect().x + description.globalRect().w <= 240);
    try std.testing.expect(description.globalRect().h > 20);
    const slot = empty.children.items[2];
    const button = slot.children.items[0];
    try std.testing.expectEqualStrings("e.action", button.meta.ownership.meta.test_id.?);
    try std.testing.expectEqual(@as(f32, 24), button.globalRect().h);
    button.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(u32, 1), counter.n);
}

test {
    _ = @import("_styles.yss.zig");
}

// Per-allocation OOM sweep; see src/ui/components/oom_sweep.zig.
test "empty: mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("empty", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*core.Node {
            return try Empty(.{ .icon = icons.bell, .title = "t", .description = "d", .action_label = "a" }).mount(scope, cx);
        }
    }.m);
}
