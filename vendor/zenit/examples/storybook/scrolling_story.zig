//! Scroll inputs and nested ownership, using the same ScrollArea as applications.
const std = @import("std");
const ui = @import("ui");
const v = ui.view;
const W = ui.widgets;
const SA = W.scroll_area;

const S = struct {
    fn root(_: *const ui.theme.Values) ui.BoxStyle {
        return .{ .width = .{ .px = 620 }, .gap = 14 };
    }
    fn row(_: *const ui.theme.Values) ui.BoxStyle {
        return .{ .gap = 20, .align_items = .start };
    }
    fn column(_: *const ui.theme.Values) ui.BoxStyle {
        return .{ .gap = 6 };
    }
    fn title(t: *const ui.theme.Values) ui.TextStyle {
        return .{ .font_size = 14, .font_weight = 600, .color = t.tokens.color.fg_primary };
    }
    fn status(t: *const ui.theme.Values) ui.TextStyle {
        return .{ .font_size = 11, .color = t.tokens.color.fg_secondary };
    }
    /// Hoverable rows: with the pointer resting on a list, scrolling moves the highlight to the
    /// row that arrives under it (stationary-pointer hover, core/cx_hover.zig).
    const line = ui.css(.{ .height = 30, .width = .fill, .padding = .{ .x = 10, .y = 4 }, .background = .bg_secondary, ._hover = .{ .background = .bg_active } });
    fn body(t: *const ui.theme.Values) ui.TextStyle {
        return .{ .font_size = 13, .color = t.tokens.color.fg_primary };
    }
    const scenes = ui.css(.{ .width = .fill, .gap = 16, .flex_wrap = .wrap, .align_items = .start });
    const scene = ui.css(.{ .width = .{ .grow = .{ .min = 240 } }, .flex_basis = 240, .gap = 8 });
    const sceneHeader = ui.css(.{ .width = .fill, .gap = 8, .align_items = .center, .justify = .space_between });
    const sceneTitle = ui.css(.{ .width = .fill, .min_width = 0, .font_size = .sm, .font_weight = 500, .color = .fg_secondary, .wrap = .word_break });
    // Reserve both lines before input so an event cannot resize the article.
    const sceneStatus = ui.css(.{ .width = .fill, .height = 32, .flex_shrink = 0, .font_size = .xs, .color = .fg_tertiary, .wrap = .word_break, .max_lines = 2 });
    fn viewport(t: *const ui.theme.Values) ui.BoxStyle {
        return .{
            .background = t.tokens.color.bg_primary,
            .border = .{ .overlay = true, .width = 1, .color = t.tokens.color.border, .radius = 4 },
        };
    }
};

const Watch = struct {
    cx: *ui.Cx,
    area: SA.ScrollAreaResult,
    inner: ?SA.ScrollAreaResult = null,
    two_line_status: bool = false,
    dx: f32 = 0,
    dy: f32 = 0,
    phase: ui.events.ScrollPhase = .none,
    momentum: ui.events.MomentumPhase = .none,
    count: usize = 0,
    shown: [256]u8 = undefined,
    shown_len: usize = 0,

    fn capture(event: ui.events.Event, context: ?*anyopaque) ui.events.EventResult {
        const self: *Watch = @ptrCast(@alignCast(context.?));
        if (event == .scroll) {
            self.dx = event.scroll.dx;
            self.dy = event.scroll.dy;
            self.phase = event.scroll.phase;
            self.momentum = event.scroll.momentum;
            self.count += 1;
            self.cx.needs_redraw = true;
        }
        return .ignored; // Observe without replacing ScrollArea's handler or ownership.
    }
    fn status(node: *ui.Node) void {
        const self: *Watch = @ptrCast(@alignCast(node.meta.per_frame.hooks.slots.anim_state.?));
        var buf: [256]u8 = undefined;
        const main = std.fmt.bufPrint(&buf, "x={d:.0} y={d:.0} · dx={d:.1} dy={d:.1}{s}{s}/{s} · #{d}", .{
            self.area.state.scroll_x,
            self.area.state.scroll_y,
            self.dx,
            self.dy,
            if (self.two_line_status) "\n" else " · ",
            @tagName(self.phase),
            @tagName(self.momentum),
            self.count,
        }) catch return;
        const len = if (self.inner) |inner|
            main.len + (std.fmt.bufPrint(buf[main.len..], " · inner y={d:.0}", .{inner.state.scroll_y}) catch return).len
        else
            main.len;
        const text = buf[0..len];
        if (std.mem.eql(u8, self.shown[0..self.shown_len], text)) return;
        node.setTextContent(self.cx.allocator, text) catch return;
        @memcpy(self.shown[0..text.len], text);
        self.shown_len = text.len;
    }
    fn reset(self: *Watch) void {
        SA.setScrollY(self.area.state, self.area.content, 0);
        SA.setScrollX(self.area.state, self.area.content, 0);
        if (self.inner) |inner| SA.setScrollY(inner.state, inner.content, 0);
        self.dx = 0;
        self.dy = 0;
        self.count = 0;
        self.phase = .none;
        self.momentum = .none;
        self.cx.needs_redraw = true;
    }
};

const Panel = struct { root: *ui.Node, area: SA.ScrollAreaResult, watch: *Watch };
fn panel(scope: *ui.Scope, cx: *ui.Cx, comptime id: []const u8, title: []const u8, width: ?f32, height: f32, direction: SA.ScrollDirection) !Panel {
    const area = try W.ScrollArea(.{ .width = width, .height = height, .direction = direction, .rubber_band_y = false, .rubber_band_x = false }).mount(scope, cx);
    var area_attached = false;
    errdefer if (!area_attached) cx.freeNode(area.container);
    area.container.meta.ownership.meta.test_id = id;
    area.content.meta.ownership.meta.test_id = id ++ ".content";
    const watch = try scope.createState(Watch, .{ .cx = cx, .area = area, .two_line_status = width == null });
    const reset = v.attrs(.{ .test_id = id ++ ".reset" }, W.Button(.{ .label = "Reset", .size = .xs, .variant = .secondary, .on_click = ui.on.call(watch, Watch.reset) }));
    const root = if (width == null) blk: {
        try area.container.setStyleInlineFallible(cx.allocator, S.viewport(cx.tokens));
        break :blk try v.render(scope, cx, v.col(.{ .style = S.scene }, v.row(.{ .style = S.sceneHeader }, .{
            v.text(.{ .style = S.sceneTitle }, title),
            reset,
        })));
    } else try v.render(scope, cx, v.col(.{ .style = S.column }, .{ v.text(.{ .style = S.title }, title), reset }));
    errdefer cx.freeNode(root);
    root.behavior.events.on_event_capture = Watch.capture;
    root.behavior.events.capture_context = watch;
    try root.appendChild(cx.allocator, area.container);
    area_attached = true;
    const label = if (width == null)
        try v.render(scope, cx, v.text(.{ .style = S.sceneStatus, .test_id = id ++ ".status" }, "Ready"))
    else
        try v.render(scope, cx, v.text(.{ .style = S.status, .test_id = id ++ ".status" }, "Ready"));
    label.meta.per_frame.hooks.slots.anim_state = watch;
    label.addBeforeRenderScoped(Watch.status, .self);
    try attach(cx, root, label);
    return .{ .root = root, .area = area, .watch = watch };
}

fn attach(cx: *ui.Cx, parent: *ui.Node, child: *ui.Node) !void {
    errdefer cx.freeNode(child);
    try parent.appendChild(cx.allocator, child);
}
/// Rows carry `<id>.row.NN` test ids (1-based, as labelled) when `id` is given.
fn rows(scope: *ui.Scope, cx: *ui.Cx, parent: *ui.Node, comptime id: ?[]const u8, comptime prefix: []const u8, comptime count: usize) !void {
    inline for (0..count) |i| {
        const text = std.fmt.comptimePrint(prefix ++ " {d:0>2}  ·  Scroll to explore", .{i + 1});
        const row = v.row(.{ .style = S.line }, v.text(.{ .style = S.body }, text));
        const node = if (id) |prefix_id|
            try v.render(scope, cx, v.attrs(.{ .test_id = std.fmt.comptimePrint("{s}.row.{d:0>2}", .{ prefix_id, i + 1 }) }, row))
        else
            try v.render(scope, cx, row);
        try attach(cx, parent, node);
    }
}

fn cards(scope: *ui.Scope, cx: *ui.Cx, area: SA.ScrollAreaResult, width: f32, height: f32, strip_width: f32, padding: ui.Padding) !void {
    try area.content.setStyleInlineFallible(cx.allocator, .{ .width = .fixed(strip_width) });
    const strip = try ui.box(cx, .{
        .width = .fixed(strip_width),
        .height = .fixed(height + padding.vertical()),
        .direction = .row,
        .gap = 12,
        .padding = padding,
    }, .{});
    try attach(cx, area.content, strip);
    for (0..8) |i| {
        var buf: [32]u8 = undefined;
        const text = try std.fmt.bufPrint(&buf, "Card {d}", .{i + 1});
        const card = try W.Card(.{ .title = text, .variant = .outlined }).mount(scope, cx);
        try attach(cx, strip, card);
        try card.setStyleInlineFallible(cx.allocator, .{ .width = .fixed(width), .height = .fixed(height) });
    }
}

pub fn buildSupplement(scope: *ui.Scope, cx: *ui.Cx) !*ui.Node {
    const root = try v.render(scope, cx, v.row(.{ .style = S.scenes }, .{}));
    errdefer cx.freeNode(root);

    const vertical = try panel(scope, cx, "story.layoutbox.scroll.vertical", "Vertical · wheel / trackpad", null, 200, .vertical);
    try attach(cx, root, vertical.root);
    try rows(scope, cx, vertical.area.content, null, "Row", 24);

    const horizontal = try panel(scope, cx, "story.layoutbox.scroll.horizontal", "Horizontal · sideways", null, 200, .horizontal);
    try attach(cx, root, horizontal.root);
    try cards(scope, cx, horizontal.area, 120, 150, 1068, .{ .left = 12, .top = 16 });

    const outer = try panel(scope, cx, "story.layoutbox.scroll.outer", "Nested · inner first", null, 200, .vertical);
    try attach(cx, root, outer.root);
    const inner = try W.ScrollArea(.{ .height = 112, .rubber_band_y = false }).mount(scope, cx);
    try attach(cx, outer.area.content, inner.container);
    inner.container.meta.ownership.meta.test_id = "story.layoutbox.scroll.inner";
    try inner.container.setStyleInlineFallible(cx.allocator, S.viewport(cx.tokens));
    outer.watch.inner = inner;
    try rows(scope, cx, inner.content, null, "Inner", 12);
    try rows(scope, cx, outer.area.content, null, "Outer", 16);
    return root;
}

pub fn build(scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const root = try v.render(scope, cx, v.col(.{ .style = S.root }, .{}));
    const top = try v.render(scope, cx, v.row(.{ .style = S.row }, .{}));
    try root.appendChild(cx.allocator, top);
    const vertical = try panel(scope, cx, "story.scrolling.vertical", "Vertical · wheel / trackpad", 300, 170, .vertical);
    try rows(scope, cx, vertical.area.content, "story.scrolling.vertical", "Row", 40);
    try top.appendChild(cx.allocator, vertical.root);
    const horizontal = try panel(scope, cx, "story.scrolling.horizontal", "Horizontal · sideways scroll", 300, 170, .horizontal);
    try cards(scope, cx, horizontal.area, 130, 140, 1200, .{ .bottom = 20 });
    try top.appendChild(cx.allocator, horizontal.root);
    const outer = try panel(scope, cx, "story.scrolling.outer", "Nested · inner first, then parent at the edge", 620, 190, .vertical);
    const inner = try panel(scope, cx, "story.scrolling.inner", "Inner list", 560, 100, .vertical);
    try rows(scope, cx, inner.area.content, "story.scrolling.inner", "Inner", 20);
    try outer.area.content.appendChild(cx.allocator, inner.root);
    try rows(scope, cx, outer.area.content, null, "Outer", 16);
    try root.appendChild(cx.allocator, outer.root);
    return root;
}
