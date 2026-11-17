//! AI history list: ownership of the recycled rows (zenit `renderInto` contract — a row's scope
//! belongs to the list that owns its slot). Three release paths: a row recycled by scrolling, the
//! list freed on its own while the caller's scope lives on, and the caller's scope disposed.
const std = @import("std");
const ui = @import("ui");
const History = @import("../view/ai_history_view.zig");
const a = std.testing.allocator;

const Rows = struct {
    mounted: usize = 0,
    live: usize = 0,
    /// Added to every row mounted from now on (text re-wrapped at another width).
    extra: f32 = 0,
    fn release(self: *Rows) void {
        self.live -= 1;
    }
    fn render(raw: *anyopaque, i: usize, row_scope: *ui.Scope, c: *ui.Cx) !*ui.Node {
        const self: *Rows = @ptrCast(@alignCast(raw));
        const row = try ui.box(c, .{ .width = .fill(), .height = .{ .px = rowHeight(i) + self.extra }, .flex_shrink = 0 }, .{});
        errdefer c.freeNode(row);
        try row_scope.onCleanup(Rows, self, release);
        self.mounted += 1;
        self.live += 1;
        return row;
    }
};

const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    /// The scope the list is mounted in (the conversation scope in the host).
    owner: *ui.Scope,
    outer: ui.widgets.ScrollAreaResult,
    /// The message column's width (the host's model).
    width: *ui.Signal(f32),
    view: *History.View,
    rows: *Rows,
    keys: []usize,
    heights: History.Heights = .{},

    fn init(count: usize) !*Fixture {
        const self = try a.create(Fixture);
        errdefer a.destroy(self);
        const cx = try ui.Cx.init(a, std.testing.io);
        errdefer cx.deinit();
        try cx.setTestFrameStep(16);
        cx.reduced_motion = true;
        cx.setViewport(700, 500);
        const scope = try ui.Scope.init(a, null, cx.owner);
        errdefer scope.dispose();
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
        const outer = try ui.widgets.ScrollArea(.{ .height = 400, .rubber_band_y = false }).mount(scope, cx);
        try cx.root.?.appendChild(a, outer.container);
        const keys = try a.alloc(usize, count);
        errdefer a.free(keys);
        for (keys, 0..) |*key, i| key.* = i;
        const rows = try a.create(Rows);
        errdefer a.destroy(rows);
        rows.* = .{};
        self.* = .{ .cx = cx, .scope = scope, .owner = try scope.childScope(), .outer = outer, .width = try scope.createSignal(f32, 668), .view = undefined, .rows = rows, .keys = keys };
        self.view = try History.View.mount(cx, self.owner, outer, self.width, keys, &self.heights, rows, Rows.render);
        try outer.content.appendChild(a, self.view.root);
        self.frames(8);
        return self;
    }
    fn deinit(self: *Fixture) void {
        self.scope.dispose();
        self.cx.deinit();
        self.heights.deinit(a);
        a.free(self.keys);
        a.destroy(self.rows);
        a.destroy(self);
    }
    fn frames(self: *Fixture, count: usize) void {
        for (0..count) |_| {
            self.cx.advanceFrameClock();
            _ = self.cx.render();
            self.outer.state.content_height = self.outer.content.globalRect().h;
            self.outer.state.viewport_height = self.outer.container.globalRect().h;
        }
    }
};

test "AI history view: a row scrolled out of the window releases its scope" {
    const f = try Fixture.init(600);
    defer f.deinit();
    const first = f.rows.mounted;
    try std.testing.expect(first > 0 and first < 40);
    try std.testing.expectEqual(first, f.rows.live);
    ui.widgets.setScrollY(f.outer.state, f.outer.content, 20000);
    f.frames(8);
    // Other rows are mounted now; the ones that left were released with their slots.
    try std.testing.expect(f.rows.mounted > first);
    try std.testing.expect(f.rows.live < 40);
}

test "AI history view: freeing the list alone releases every row while the caller's scope lives on" {
    const f = try Fixture.init(600);
    defer f.deinit();
    try std.testing.expect(f.rows.live > 0);
    const root = f.view.root;
    f.cx.detachChild(f.outer.content, root);
    f.cx.freeNode(root);
    // No row scope is left behind under the caller's (longer-lived) scope.
    try std.testing.expectEqual(@as(usize, 0), f.rows.live);
    f.frames(4);
    try std.testing.expectEqual(@as(usize, 0), f.rows.live);
}

test "AI history view: disposing the caller's scope releases the list and its rows" {
    const f = try Fixture.init(600);
    defer f.deinit();
    try std.testing.expect(f.rows.live > 0);
    // The host's order (rebuildConversation): scope first, then the nodes.
    const root = f.view.root;
    f.owner.dispose();
    try std.testing.expectEqual(@as(usize, 0), f.rows.live);
    f.cx.detachChild(f.outer.content, root);
    f.cx.destroyDetached(root);
    f.frames(4);
    try std.testing.expectEqual(@as(usize, 0), f.rows.live);
}

fn rowHeight(i: usize) f32 {
    return if (i % 2 == 0) 72 else 96;
}

/// Window y of the mounted row `index` (rows are 72 / 96 tall, in order), or null.
fn rowTop(f: *Fixture, index: usize) ?f32 {
    const range = f.view.residentRange();
    if (index < range.start or index >= range.end) return null;
    // Slots are ordered by data index after the top spacer; hidden slots are 0 tall.
    var at = range.start;
    for (f.view.root.children.items[0].children.items[1..]) |slot| {
        if (slot.children.items.len == 0) continue;
        if (at == index) return slot.globalRect().y;
        at += 1;
    }
    return null;
}

test "AI history view: rows measured above the reader do not move what is on screen" {
    const f = try Fixture.init(600);
    defer f.deinit();
    // Deep into rows never measured (estimate 240, real 72 / 96).
    ui.widgets.setScrollY(f.outer.state, f.outer.content, 60000);
    f.frames(8);
    var tracked = f.view.residentRange().start;
    while (rowTop(f, tracked)) |y| : (tracked += 1) if (y >= 100) break;
    var steps: usize = 0;
    while (steps < 8) : (steps += 1) {
        const before = rowTop(f, tracked) orelse break;
        ui.widgets.setScrollY(f.outer.state, f.outer.content, f.outer.state.scroll_y - 30);
        f.frames(8);
        const after = rowTop(f, tracked) orelse break;
        try std.testing.expectApproxEqAbs(before + 30, after, 0.6);
    }
    try std.testing.expect(steps >= 3);
}

test "AI history view: measured heights are kept by key and a remount starts from them" {
    const f = try Fixture.init(600);
    defer f.deinit();
    ui.widgets.setScrollY(f.outer.state, f.outer.content, 3000);
    f.frames(8);
    const known = f.heights.count();
    try std.testing.expect(known > 4 and known < 100);
    var it = f.heights.iterator();
    while (it.next()) |entry| try std.testing.expectEqual(rowHeight(entry.key_ptr.*), entry.value_ptr.*);
    const total = f.view.root.globalRect().h;
    const first = f.view.residentRange().start;
    const top = rowTop(f, first + 3).?;
    // The host's rebuild: the conversation scope and its nodes go, a new list is mounted.
    const old = f.view.root;
    f.owner.dispose();
    f.cx.detachChild(f.outer.content, old);
    f.cx.destroyDetached(old);
    f.owner = try f.scope.childScope();
    f.view = try History.View.mount(f.cx, f.owner, f.outer, f.width, f.keys, &f.heights, f.rows, Rows.render);
    try f.outer.content.appendChild(a, f.view.root);
    f.frames(1);
    // Same geometry in the first frame: the reader's rows are where they were.
    try std.testing.expectApproxEqAbs(total, f.view.root.globalRect().h, 0.6);
    try std.testing.expectApproxEqAbs(top, rowTop(f, first + 3).?, 0.6);
    f.frames(8);
    try std.testing.expectApproxEqAbs(top, rowTop(f, first + 3).?, 0.6);
}

test "AI history view: every row is exposed to assistive technology and its scroll moves the conversation" {
    const f = try Fixture.init(600);
    defer f.deinit();
    const provider = f.view.root.children.items[0].behavior.interaction.a11y.?.collection.?;
    try std.testing.expectEqual(@as(u32, 600), provider.vtable.count(provider.ctx));
    // The collection's viewport is the conversation's.
    try std.testing.expectEqual(@as(f32, 400), provider.vtable.viewport(provider.ctx).h);
    const item = provider.vtable.item_rect(provider.ctx, 300);
    provider.vtable.apply_scroll(provider.ctx, item.y);
    f.frames(8);
    try std.testing.expect(f.outer.state.scroll_y > 10000);
    const range = f.view.residentRange();
    try std.testing.expect(range.start <= 300 and 300 < range.end);
    try std.testing.expectApproxEqAbs(f.outer.container.globalRect().y, rowTop(f, 300).?, 0.6);
}

/// The mounted rows' own nodes, in data order.
fn rowNodes(f: *Fixture, out: []*ui.Node) []*ui.Node {
    var n: usize = 0;
    for (f.view.root.children.items[0].children.items[1..]) |slot| {
        if (slot.children.items.len == 0 or n == out.len) continue;
        out[n] = slot.children.items[0];
        n += 1;
    }
    return out[0..n];
}

/// Every mounted row's slot is exactly as tall as the row and rows follow each other without
/// gap or overlap.
fn expectContiguous(f: *Fixture) !void {
    var previous: ?ui.ComputedRect = null;
    for (f.view.root.children.items[0].children.items[1..]) |slot| {
        if (slot.children.items.len == 0) continue;
        const rect = slot.globalRect();
        try std.testing.expectApproxEqAbs(slot.children.items[0].globalRect().h, rect.h, 0.01);
        if (previous) |p| try std.testing.expectApproxEqAbs(p.y + p.h, rect.y, 0.01);
        previous = rect;
    }
    try std.testing.expect(previous != null);
}

test "AI history view: a row that grows on its own pushes the rows after it (no stale slot, no overlap)" {
    const f = try Fixture.init(600);
    defer f.deinit();
    ui.widgets.setScrollY(f.outer.state, f.outer.content, 3000);
    f.frames(8);
    try expectContiguous(f);
    const first = f.view.residentRange().start;
    const top = rowTop(f, first + 3).?;
    const next = rowTop(f, first + 4).?;
    const total = f.view.root.globalRect().h;
    // A step group opened inside the row: its content is 150 taller, nobody tells the list.
    var buffer: [64]*ui.Node = undefined;
    const row = rowNodes(f, &buffer)[3];
    row.setStyleInline(a, .{ .height = .{ .px = row.globalRect().h + 150 } });
    f.cx.requestRedraw();
    f.frames(3);
    try expectContiguous(f);
    try std.testing.expectApproxEqAbs(top, rowTop(f, first + 3).?, 0.6);
    try std.testing.expectApproxEqAbs(next + 150, rowTop(f, first + 4).?, 0.6);
    try std.testing.expectApproxEqAbs(total + 150, f.view.root.globalRect().h, 0.6);
    // The kept height follows.
    try std.testing.expectEqual(rowHeight(first + 3) + 150, f.heights.get(first + 3).?);
}

test "AI history view: a stale kept height is only an estimate — the remounted row is measured and corrected" {
    const f = try Fixture.init(600);
    defer f.deinit();
    f.frames(4);
    try std.testing.expectEqual(@as(f32, 72), f.heights.get(0).?);
    // The host's rebuild after the row's content changed (an editor replaced the bubble).
    const old = f.view.root;
    f.owner.dispose();
    f.cx.detachChild(f.outer.content, old);
    f.cx.destroyDetached(old);
    f.rows.extra = 40;
    f.owner = try f.scope.childScope();
    f.view = try History.View.mount(f.cx, f.owner, f.outer, f.width, f.keys, &f.heights, f.rows, Rows.render);
    try f.outer.content.appendChild(a, f.view.root);
    f.frames(4);
    try expectContiguous(f);
    try std.testing.expectEqual(@as(f32, 112), f.heights.get(0).?);
    try std.testing.expectEqual(@as(f32, 136), f.heights.get(1).?);
}

test "AI history view: a new message width re-measures the rows without moving the reader" {
    const f = try Fixture.init(600);
    defer f.deinit();
    // Deep in the history, then up a little so rows above the reader are measured too.
    ui.widgets.setScrollY(f.outer.state, f.outer.content, 60000);
    f.frames(8);
    ui.widgets.setScrollY(f.outer.state, f.outer.content, f.outer.state.scroll_y - 400);
    f.frames(8);
    // The first row that starts inside the viewport.
    var tracked = f.view.residentRange().start;
    while (rowTop(f, tracked)) |y| : (tracked += 1) if (y >= f.outer.container.globalRect().y) break;
    const top = rowTop(f, tracked).?;
    const total = f.view.root.globalRect().h;
    // The panel got narrower: every row re-wraps 30 taller (mounted ones now, the rest when shown).
    var buffer: [64]*ui.Node = undefined;
    for (rowNodes(f, &buffer)) |row| row.setStyleInline(a, .{ .height = .{ .px = row.globalRect().h + 30 } });
    f.rows.extra = 30;
    f.width.set(400);
    f.frames(4);
    try expectContiguous(f);
    // Rows above the reader grew; the conversation was moved by the same amount.
    try std.testing.expectApproxEqAbs(top, rowTop(f, tracked).?, 0.6);
    try std.testing.expect(f.view.root.globalRect().h > total + 60);
    try std.testing.expectEqual(rowHeight(tracked) + 30, f.heights.get(tracked).?);
    // Reading upwards into rows measured at the old width: each step moves the reader's row by
    // exactly the step while those rows are measured again.
    var steps: usize = 0;
    while (steps < 8) : (steps += 1) {
        const before = rowTop(f, tracked) orelse break;
        ui.widgets.setScrollY(f.outer.state, f.outer.content, f.outer.state.scroll_y - 30);
        f.frames(8);
        const after = rowTop(f, tracked) orelse break;
        try std.testing.expectApproxEqAbs(before + 30, after, 0.6);
        try expectContiguous(f);
    }
    try std.testing.expect(steps >= 3);
}
