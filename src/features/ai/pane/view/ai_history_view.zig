//! Virtual history rows inside the conversation's existing ScrollArea. The live turn and approval
//! surfaces stay outside the recycled history rows.
//!
//! This is the one adapter between the conversation and zenit's `VirtualList`; it uses the list's
//! public interface only (embedded mode, `scroll_owner`):
//! - Scrolling: the conversation's ScrollArea (`outer`) is the only scroll / clip owner. The list
//!   builds no ScrollArea of its own; it reads its window from where it sits in `outer`'s viewport
//!   and hands its scroll corrections (rows measured above the reader) to `outer` in the same pass.
//! - Rows: mounted under the list's own scope (`mountScoped`), so a row is released with its slot
//!   when it scrolls out, with the list when the list is freed, and with the caller's scope.
//! - Heights: rows are measured by layout and stay observed while shown (`observe_item_resize`):
//!   a step group opened inside a row, an editor replacing a bubble or text re-wrapping moves the
//!   rows after it in the same frame. `heights` (owned by the caller, keyed by `keys[index]`)
//!   keeps the last measured heights across remounts of the same conversation; a remount starts
//!   from them as per-row *estimates* (`seedItemEstimate`), so a stale one is corrected when its
//!   row is shown. When `width` (the message column's width, the caller's model) changes, every
//!   row is an estimate again (`remeasureAll`): nothing jumps, each row is measured again as it is
//!   laid out. The caller clears `heights` only when the conversation (the keys) changes.
//! - Accessibility: the list's semantic collection (all rows, not only the resident ones) and its
//!   scroll-to-row go through `outer` as well.
//!
//! Ownership: `mount` returns a handle owned by `scope`; `root` is the caller's to place inside
//! `outer.content` and to free (alone, or with `scope`). `keys`, `heights` and `context` must
//! outlive `scope`. Nothing here reads or writes the list's nodes, hooks or state fields.
const std = @import("std");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const Lists = ui.widgets.virtual_list;
pub const Heights = std.AutoHashMapUnmanaged(usize, f32);
pub const View = struct {
    cx: *ui.Cx,
    /// The list's container (test id `ai.history.virtual`), as tall as the whole history.
    root: *ui.Node = undefined,
    list: *Lists.VirtualListState = undefined,
    context: *anyopaque,
    render: *const fn (*anyopaque, usize, *ui.Scope, *ui.Cx) anyerror!*ui.Node,
    keys: []const usize,
    heights: *Heights,
    /// The width the rows were last laid out for (`width`'s value).
    laid_out_width: f32,
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, outer: ui.widgets.ScrollAreaResult, width: *ui.Signal(f32), keys: []const usize, heights: *Heights, context: *anyopaque, render: @FieldType(View, "render")) !*View {
        const space = IdSpace.of(scope);
        const self = try scope.createState(View, .{ .cx = cx, .keys = keys, .heights = heights, .context = context, .render = render, .laid_out_width = width.peek() });
        const list = try ui.widgets.VirtualList(.{ .item_count = keys.len, .measure_items = true, .observe_item_resize = true, .estimate_item_height = 240, .overscan = 2, .scroll_owner = outer, .on_item_measured = rowMeasured }).mountScoped(scope, cx, self, renderItem);
        self.root = list.container;
        self.list = list.state;
        self.root.meta.ownership.meta.test_id = space.id("ai.history.virtual");
        for (keys, 0..) |key, i| if (heights.get(key)) |height| Lists.seedItemEstimate(list.state, i, height);
        try scope.createEffect(.{ .view = self, .width = width }, struct {
            fn run(ctx: anytype) void {
                const now = ctx.width.get();
                if (now == ctx.view.laid_out_width) return;
                ctx.view.laid_out_width = now;
                Lists.remeasureAll(ctx.view.list);
            }
        }.run);
        return self;
    }
    /// The rows currently mounted: `[start, end)` of `keys`.
    pub fn residentRange(self: *const View) struct { start: usize, end: usize } {
        const range = self.list.visibleRange();
        return .{ .start = range.start, .end = range.end };
    }
    /// `list_scope` is the list's own scope (the owner of the pool slots): a row mounted under it is
    /// retired with its slot on recycle, with the list when the list alone is freed, and with the
    /// caller's scope (the `renderInto` contract).
    fn renderItem(node: *ui.Node, index: usize, list_scope: *ui.Scope, cx: *ui.Cx, raw: ?*anyopaque) void {
        const self: *View = @ptrCast(@alignCast(raw.?));
        ui.view.renderInto(list_scope, cx, node, renderRow, self, .{index}, "AI history row") catch {
            _ = Lists.markPoolNodeRenderIncomplete(node);
        };
    }
    fn renderRow(self: *View, index: usize, scope: *ui.Scope, cx: *ui.Cx) !*ui.Node {
        return self.render(self.context, index, scope, cx);
    }
    fn rowMeasured(index: usize, height: f32, raw: ?*anyopaque) void {
        const self: *View = @ptrCast(@alignCast(raw.?));
        if (index < self.keys.len) self.heights.put(self.cx.allocator, self.keys[index], height) catch {};
    }
};
