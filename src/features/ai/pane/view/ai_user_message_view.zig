//! A user turn (Pencil Kaf7E A3): the native `W.Card` bubble (bg_active, radius panel, 8 12) at
//! most 85% wide, and under it the actions row (time, copy, rewind, edit) that shows only while
//! the pointer is over the turn or keyboard focus is inside it (Kaf7E ⑦). Hidden actions keep their
//! space so the column does not jump; while editing they stay shown.
const std = @import("std");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const S = @import("ai_assistant_styles.zig");

pub const Bubble = struct {
    /// The card (width capped at 85%); test id `ai.message.user.bubble`.
    root: *ui.Node,
    /// The card body: the message text or the inline editor goes here.
    body: *ui.Node,
};

/// The message column's width (the host's model value; it changes when the panel is resized,
/// docked or floated). The views below cap their own nodes from it and follow it while mounted, so
/// the host never has to find them in the tree again.
pub const ContentWidth = *ui.Signal(f32);

/// Keeps `node`'s max width at `limit(content_width)` for as long as `scope` lives.
fn followWidth(cx: *ui.Cx, scope: *ui.Scope, node: *ui.Node, content_width: ContentWidth, comptime limit: fn (f32) f32) !void {
    try scope.createEffect(.{ .cx = cx, .node = node, .width = content_width }, struct {
        fn run(ctx: anytype) void {
            const max_width = limit(ctx.width.get());
            if (ctx.node.style.getExt().max_width == max_width) return;
            ctx.node.setStyle(ctx.cx.allocator, .max_width, max_width);
        }
    }.run);
}

const BodySpec = struct { target: *?*ui.Node, content_width: ContentWidth };
fn bodyNode(spec: BodySpec, scope: *ui.Scope, cx: *ui.Cx) !*ui.Node {
    // The text column inside the card carries the 85% cap (minus the card's 12 + 12 padding), so
    // the text wraps there and the card grows to its lines.
    const node = try ui.box(cx, S.userBubbleBody(spec.content_width.peek()), .{});
    errdefer cx.freeNode(node);
    try followWidth(cx, scope, node, spec.content_width, S.userBubbleTextMaxWidth);
    spec.target.* = node;
    return node;
}

/// The bubble's text column is capped from `content_width` and follows it.
pub fn mountBubble(cx: *ui.Cx, scope: *ui.Scope, content_width: ContentWidth) !Bubble {
    const space = IdSpace.of(scope);
    var body: ?*ui.Node = null;
    const v = ui.view;
    const card = try v.render(scope, cx, v.with(ui.widgets.Card(.{ .variant = .bubble }), .{v.component(bodyNode, BodySpec{ .target = &body, .content_width = content_width })}));
    card.meta.ownership.meta.test_id = space.id("ai.message.user.bubble");
    return .{ .root = card, .body = body.? };
}

/// The rail of sent attachments / images above the bubble (test id `ai.message.attachments`),
/// capped like the bubble and following `content_width`.
pub fn mountAttachments(cx: *ui.Cx, scope: *ui.Scope, content_width: ContentWidth) !*ui.Node {
    const space = IdSpace.of(scope);
    const node = try ui.box(cx, S.userAttachments(content_width.peek()), .{});
    errdefer cx.freeNode(node);
    try followWidth(cx, scope, node, content_width, S.userBubbleMaxWidth);
    node.meta.ownership.meta.test_id = space.id("ai.message.attachments");
    return node;
}

/// Shows `actions` while the pointer is over `row` or focus is inside it. `row` holds both the
/// bubble and the actions, so moving from the bubble onto an action stays inside the hovered path.
///
/// One source per input: hover is the native hover of `row` (`useHover`; zenit re-resolves hover
/// under a resting pointer when the scene changes, so a rebuilt transcript needs no geometry test
/// here), focus is the native focus-within of `row` (`on_focus_within` / `on_blur_within`).
pub const Reveal = struct {
    cx: *ui.Cx,
    row: *ui.Node,
    actions: *ui.Node,
    pinned: bool,
    hovered: *ui.Signal(bool),
    focus_within: *ui.Signal(bool),
    shown: ?bool = null,

    pub fn attach(cx: *ui.Cx, scope: *ui.Scope, row: *ui.Node, actions: *ui.Node, pinned: bool) !void {
        const self = try scope.createState(Reveal, .{
            .cx = cx,
            .row = row,
            .actions = actions,
            .pinned = pinned,
            .hovered = try ui.hooks.useHover(scope, row),
            .focus_within = try scope.createSignal(bool, focusInside(cx, row)),
        });
        row.behavior.events.on_focus_within = ui.Cx.handlerFrom(Reveal, self, focusEntered);
        row.behavior.events.on_blur_within = ui.Cx.handlerFrom(Reveal, self, focusLeft);
        try scope.createEffect(self, apply);
    }
    fn focusInside(cx: *ui.Cx, row: *ui.Node) bool {
        return if (cx.focus_manager.current_focus) |node| node.isDescendantOf(row) else false;
    }
    fn focusEntered(self: *Reveal) void {
        self.focus_within.set(true);
    }
    fn focusLeft(self: *Reveal) void {
        self.focus_within.set(false);
    }
    fn apply(self: *Reveal) void {
        const hovered = self.hovered.get();
        // Focus dropped without a blur (a closing card abandons it) is not reported: read it back.
        const focused = self.focus_within.get() and focusInside(self.cx, self.row);
        const show = wanted(self.pinned, hovered, focused);
        if (self.shown == show) return;
        self.shown = show;
        self.actions.setOpacity(if (show) 1 else 0);
        self.cx.requestRedraw();
    }
    pub fn wanted(pinned: bool, hovered: bool, focused: bool) bool {
        return pinned or hovered or focused;
    }
};

test "user actions show on hover, on focus inside, or while editing" {
    try std.testing.expect(!Reveal.wanted(false, false, false));
    try std.testing.expect(Reveal.wanted(false, true, false));
    try std.testing.expect(Reveal.wanted(false, false, true));
    try std.testing.expect(Reveal.wanted(true, false, false));
}
