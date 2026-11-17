//! The child conversation dialog's header (a Modal, not floating; Pencil O9, float_chrome spec): bot ·
//! name · status Tag · 父对话 subtitle, and the dialog appends its own native actions. The floating main panel's header is the generic unified
//! chrome (`shared/ui/float_card/float_chrome.zig`), which also owns the shared narrow-header rule.
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const std = @import("std");
const S = @import("ai_assistant_styles.zig");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
pub const View = struct { bar: *ui.Node, owner: *ui.Node, owner_pill: *ui.Node };
/// A count badge on a header button that outlives the view showing the count (the floating chrome's
/// slot buttons stay while the AI content view is mounted and released, LIFECYCLE.md §3). The badge
/// is the view's node: it is removed from the button when `scope` (the view's) is released, unless
/// the button's tree went first.
pub fn mountCountBadge(cx: *ui.Cx, scope: *ui.Scope, button: *ui.Node, test_id: []const u8) !*ui.Node {
    button.setStyleInline(cx.allocator, .{ .position = .relative });
    const badge = try ui.textStyled(cx, S.countBadgeText, "");
    errdefer cx.destroyDetached(badge);
    badge.setStyleInline(cx.allocator, S.countBadge(cx.tokens));
    badge.meta.ownership.meta.test_id = test_id;
    badge.setDisplay(.none);
    badge.setHitTestVisible(false);
    const Owned = struct {
        cx: *ui.Cx,
        handle: ui.hit.NodeHandle,
        fn release(self: *@This()) void {
            const node = self.cx.node_registry.resolve(self.handle, null) orelse return;
            if (node.parent) |parent| self.cx.detachChild(parent, node);
            self.cx.destroyDetached(node);
        }
    };
    const owned = try scope.createState(Owned, .{ .cx = cx, .handle = .{ .id = badge.id, .generation = try cx.node_registry.trackGeneration(badge) } });
    try scope.onCleanup(Owned, owned, Owned.release);
    try button.appendChild(cx.allocator, badge);
    return badge;
}
pub fn updateCountBadge(cx: *ui.Cx, badge: *ui.Node, count: usize) !void {
    var buffer: [32]u8 = undefined;
    const number = try std.fmt.bufPrint(&buffer, "{d}", .{count});
    if (!std.mem.eql(u8, badge.getText().?.content, number)) try badge.setTextContent(cx.allocator, number);
    badge.setDisplay(if (count == 0) .none else .flex);
}
pub fn repaintCountBadge(cx: *ui.Cx, badge: *ui.Node) void {
    badge.setStyleInline(cx.allocator, S.countBadge(cx.tokens));
    badge.setTextColor(theme.current().accent_ink);
}
/// The child dialog's header (O9): bot (accent) · name · `meta` (the dialog puts its status Tag and the
/// 父对话 subtitle there) · spacer; the dialog appends its native ghost sm actions. `owner` is the name.
/// The buttons never shrink; the `meta` pill gives way first (`flex_shrink` 1, `min_width` 0, clipped)
/// with its subtitle ellipsized natively, the title last (`ai_child_header_styles`).
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, panel: *ui.Node, owner: []const u8) !View {
    const space = IdSpace.of(scope);
    const H = @import("ai_child_header_styles.zig");
    const bar = try ui.boxStyled(cx, H.bar, .{});
    try bar.appendChild(cx.allocator, try ui.iconTint(cx, ui.icons.bot, cx.tokens.tokens.color.accent, H.icon()));
    const label = try ui.textStyled(cx, H.title, owner);
    label.setStyleInline(cx.allocator, H.titleBox());
    try bar.appendChild(cx.allocator, label);
    const pill = try ui.boxStyled(cx, H.meta, .{});
    pill.meta.ownership.meta.test_id = space.id("ai.owner");
    try bar.appendChild(cx.allocator, pill);
    const spacer = try ui.spacer(cx);
    try bar.appendChild(cx.allocator, spacer);
    try panel.appendChild(cx.allocator, bar);
    return .{ .bar = bar, .owner = label, .owner_pill = pill };
}
