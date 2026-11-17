//! A run of steps as one native W.Disclosure (Pencil Kaf7E A5 / A6): collapsed it is one 28-high
//! row (chevron, status, title, detail, elapsed); open, its steps hang on the left rail. No card,
//! no soft edges. The host appends the step rows into `content` (inside the rail).
const std = @import("std");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const groups = @import("../../../../ai/step_groups.zig");
const events = @import("../../../../ai/step_events.zig");
const visual = @import("../model/ai_step_visual.zig");
const status_view = @import("ai_step_status.zig");
pub const Props = struct {
    group: *groups.State,
    title: []const u8,
    projection: []const u8,
    tool_name: ?[]const u8 = null,
    step_count: ?usize = null,
    phase: events.Phase,
    elapsed_ms: u64,
    live: bool = false,
    /// Failures and rejections are counted apart (step_groups.Summary).
    failed_steps: usize = 0,
    rejected_steps: usize = 0,
    on_toggle: ?ui.Handler(void) = null,
};
pub const Result = struct {
    root: *ui.Node,
    content: *ui.Node,
    state: *State,
    pub fn update(self: Result, props: Props) !void {
        try self.state.update(props);
    }
};
const State = struct {
    cx: *ui.Cx,
    props: Props,
    open: *ui.Signal(bool),
    title: *ui.Signal([]const u8),
    detail: *ui.Signal([]const u8),
    detail_tone: *ui.Signal(ui.widgets.disclosure.DisclosureTone),
    trailing: *ui.Signal([]const u8),
    status: *status_view.Status,
    ticking: bool = false,
    mounted_ms: u64,
    last_tick_ms: u64 = 0,
    /// Owned copies behind the text signals (the host passes transient buffers); two per text so the
    /// value a signal still holds stays valid while the next one is written.
    texts: [3][2]std.ArrayList(u8) = .{ .{ .empty, .empty }, .{ .empty, .empty }, .{ .empty, .empty } },
    turns: [3]u1 = .{ 0, 0, 0 },
    clock_buffer: [48]u8 = undefined,
    fn setOwned(self: *State, slot: usize, signal: *ui.Signal([]const u8), value: []const u8) !void {
        if (std.mem.eql(u8, signal.peek(), value)) return;
        self.turns[slot] +%= 1;
        var buffer = &self.texts[slot][self.turns[slot]];
        buffer.clearRetainingCapacity();
        try buffer.appendSlice(self.cx.allocator, value);
        signal.set(buffer.items);
    }
    fn update(self: *State, props: Props) !void {
        if (self.props.group != props.group) {
            props.group.retain();
            self.props.group.release();
        }
        self.props = props;
        self.mounted_ms = monotonicMs();
        try self.setOwned(0, self.title, props.title);
        const cancelled = props.phase == .cancelled;
        const detail = try visual.groupDetail(self.cx.allocator, props.step_count, props.failed_steps, props.rejected_steps, cancelled, props.projection);
        defer self.cx.allocator.free(detail);
        try self.setOwned(1, self.detail, detail);
        const tone: ui.widgets.disclosure.DisclosureTone = if (props.failed_steps > 0 or props.phase == .failed) .danger else .neutral;
        if (self.detail_tone.peek() != tone) self.detail_tone.set(tone);
        try self.status.set(visual.group(props.phase, @max(props.failed_steps, @intFromBool(props.phase == .failed)), props.rejected_steps, props.tool_name == null));
        try self.setOwned(2, self.trailing, elapsed(&self.clock_buffer, props.elapsed_ms));
        if (self.open.peek() != props.group.expanded) self.open.set(props.group.expanded);
        if (props.live and !self.ticking) try self.cx.addAfterLayoutHook(self, State.tick);
        if (!props.live and self.ticking) self.cx.removeAfterLayoutHook(self);
        self.ticking = props.live;
    }
    fn openChanged(self: *State, open: bool) void {
        if (self.props.group.expanded == open) return;
        self.props.group.expanded = open;
        if (self.props.on_toggle) |callback| callback.invoke();
        self.cx.requestRedraw();
    }
    fn cleanup(self: *State) void {
        self.cx.removeAfterLayoutHook(self);
        self.props.group.release();
        for (&self.texts) |*pair| for (pair) |*text| text.deinit(self.cx.allocator);
    }
    fn tick(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *State = @ptrCast(@alignCast(raw));
        const now = monotonicMs();
        self.cx.scheduleRedrawAfterNs(100 * std.time.ns_per_ms);
        if (now -| self.last_tick_ms < 100) return .done;
        self.last_tick_ms = now;
        var buffer: [48]u8 = undefined;
        self.setOwned(2, self.trailing, elapsed(&buffer, self.props.elapsed_ms +| (now -| self.mounted_ms))) catch return .done;
        return .needs_layout;
    }
};
fn monotonicMs() u64 {
    return @intCast(@divTrunc(@import("../../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
}
fn elapsed(buffer: []u8, ms: u64) []const u8 {
    return @import("../../../../shared/base/format.zig").duration(buffer, ms, .short);
}
const Slots = struct {
    content: ?*ui.Node = null,
    status: ?*ui.Node = null,
};
fn contentNode(slots: *Slots, _: *ui.Scope, cx: *ui.Cx) !*ui.Node {
    const node = try ui.box(cx, .{ .width = .fill(), .min_width = 0, .height = .{ .fit = .{} }, .direction = .column, .gap = 2, .flex_shrink = 0 }, .{});
    slots.content = node;
    return node;
}
fn statusNode(slots: *Slots, _: *ui.Scope, _: *ui.Cx) !*ui.Node {
    return slots.status.?;
}
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, props: Props) !Result {
    const space = IdSpace.of(scope);
    const status = try status_view.Status.mount(cx, scope, 14, space.id("ai.step_group.status"));
    const state = try scope.createState(State, .{
        .cx = cx,
        .props = props,
        .open = try scope.createSignal(bool, props.group.expanded),
        .title = try scope.createSignal([]const u8, ""),
        .detail = try scope.createSignal([]const u8, ""),
        .detail_tone = try scope.createSignal(ui.widgets.disclosure.DisclosureTone, .neutral),
        .trailing = try scope.createSignal([]const u8, ""),
        .status = status,
        .mounted_ms = monotonicMs(),
    });
    props.group.retain();
    scope.onCleanup(State, state, State.cleanup) catch |err| {
        props.group.release();
        return err;
    };
    try state.update(props);
    var slots: Slots = .{ .status = status.root };
    const v = ui.view;
    const root = try v.render(scope, cx, v.with(ui.widgets.Disclosure(.{
        .open = state.open,
        .title = state.title,
        .detail = state.detail,
        .detail_tone = state.detail_tone,
        .trailing = state.trailing,
        .on_open_change = ui.on.call(state, State.openChanged),
        .trigger_test_id = space.id("ai.step_group.header"),
        .content_test_id = space.id("ai.step_group.content"),
        .chevron_test_id = space.id("ai.step_group.disclosure"),
        .title_test_id = space.id("ai.step_group.title"),
        .detail_test_id = space.id("ai.step_group.summary"),
        .trailing_test_id = space.id("ai.step_group.elapsed"),
    }), .{v.component(contentNode, &slots)}).slots(.{ .status = v.component(statusNode, &slots) }));
    root.meta.ownership.meta.test_id = space.id("ai.step_group");
    return .{ .root = root, .content = slots.content.?, .state = state };
}
