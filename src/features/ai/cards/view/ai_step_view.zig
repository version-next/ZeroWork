//! One stable state/disclosure slot for live tools and provider thinking.
const std = @import("std");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const S = @import("ai_tool_results_styles.zig");
const visual = @import("../model/ai_step_visual.zig");
const status_view = @import("ai_step_status.zig");
const events = @import("../../../../ai/step_events.zig");
pub const Props = struct {
    title: []const u8,
    projection: []const u8,
    projection_is_status: bool = false,
    tool_name: ?[]const u8 = null,
    tool_arguments: ?[]const u8 = null,
    decision: ?bool = null,
    detail: []const u8,
    copy_detail: bool = true,
    phase: events.Phase,
    elapsed_ms: u64,
    show_elapsed: bool = true,
    expanded: *bool,
    /// The card root's test id (already in the surface's namespace); null = `ai.step`.
    test_id: ?[]const u8 = null,
    on_toggle: ?ui.Handler(void) = null,
    scroll_position: ?*@import("../../../../ai/conversation_turn.zig").ThinkingScroll = null,
};
pub const Result = struct {
    root: *ui.Node,
    state: *State,
    pub fn update(self: Result, props: Props) !void {
        try self.state.update(props);
    }
    pub fn rebindExpanded(self: Result, expanded: *bool) void {
        self.state.props.expanded = expanded;
        self.state.expanded.set(expanded.*);
    }
};
fn setText(cx: *ui.Cx, node: *ui.Node, text: []const u8) !void {
    if (node.getText()) |old| if (std.mem.eql(u8, old.content, text)) return;
    try node.setTextContent(cx.allocator, text);
}
const State = struct {
    cx: *ui.Cx,
    props: Props,
    root: *ui.Node,
    body: *ui.Node,
    disclosure: *@import("../../../../shared/ui/styles/layout_motion.zig").Disclosure,
    indicator: *@import("ai_step_disclosure.zig").Indicator,
    /// The row's disclosure state (the header Pressable's `expanded`, also its accessible state).
    expanded: *ui.Signal(bool),
    clock: *ui.Node,
    title: *ui.Node,
    title_value: *ui.Signal([]const u8),
    projection: *ui.Node,
    rejected_tag: *ui.Node,
    error_line: *ui.Node,
    detail_text: *ui.Node,
    detail_value: *ui.Signal([]const u8),
    ticking: bool = false,
    mounted_ms: u64,
    last_tick_ms: u64 = 0,
    follow: ?@import("../../pane/view/ai_tail_follow.zig").Follow = null,
    restore_scroll: bool = true,
    fn update(self: *State, props: Props) !void {
        if (self.props.scroll_position != props.scroll_position) return error.StepIdentityChanged;
        self.detail_value.set(props.detail);
        self.props = props;
        self.props.detail = self.detail_value.peek();
        self.mounted_ms = @intCast(@divTrunc(@import("../../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
        const title_text = if (props.tool_name) |name| try @import("../model/ai_tool_titles.zig").action(self.cx.allocator, name, props.tool_arguments orelse props.projection) else try self.cx.allocator.dupe(u8, props.title);
        defer self.cx.allocator.free(title_text);
        // Also the row's accessible name (the header Pressable follows it).
        self.title_value.set(title_text);
        try setText(self.cx, self.title, title_text);
        const args = try argumentsText(self.cx.allocator, props);
        defer self.cx.allocator.free(args);
        try setText(self.cx, self.projection, args);
        const failure = try failureText(self.cx.allocator, props);
        defer self.cx.allocator.free(failure);
        try setText(self.cx, self.error_line, failure);
        self.error_line.setDisplay(if (failure.len > 0) .flex else .none);
        self.rejected_tag.setDisplay(if (props.phase == .rejected) .flex else .none);
        try self.indicator.set(visual.step(props.phase));
        self.applyInk();
        if (props.expanded.* or props.copy_detail) try setText(self.cx, self.detail_text, self.props.detail);
        self.clock.setDisplay(if (props.show_elapsed) .flex else .none);
        var buffer: [48]u8 = undefined;
        try setText(self.cx, self.clock, if (props.phase == .approval) "待确认" else @import("../../../../shared/base/format.zig").duration(&buffer, props.elapsed_ms, .short));
        const ticking = props.scroll_position != null or props.phase == .assembling or props.phase == .running or props.phase == .approval or props.phase == .approved;
        if (ticking and !self.ticking) try self.cx.addAfterLayoutHook(self, State.tick);
        if (!ticking and self.ticking) self.cx.removeAfterLayoutHook(self);
        self.ticking = ticking;
    }
    /// Title and failure line follow the phase: a failed step is red, a rejected one recedes.
    fn applyInk(self: *State) void {
        const c = self.cx.tokens.tokens.color;
        self.title.setTextColor(switch (self.props.phase) {
            .failed => c.danger,
            .rejected, .cancelled, .skipped => c.fg_tertiary,
            else => c.fg_primary,
        });
        self.error_line.setTextColor(if (self.props.phase == .failed or (self.props.projection_is_status and self.props.phase != .cancelled and self.props.phase != .skipped)) c.danger else c.fg_tertiary);
        self.cx.requestRedraw();
    }
    fn release(self: *State) void {
        self.rememberScroll();
        self.cx.removeAfterLayoutHook(self);
        if (self.props.scroll_position) |position| position.release();
    }
    fn rememberScroll(self: *State) void {
        if (self.restore_scroll) return;
        if (self.follow) |*follow| {
            // Nested scroll hand-off can move to an edge without incrementing
            // input_serial. Content growth itself never changes the offset.
            if (follow.scroll.state.input_serial != follow.input_serial or @abs(follow.scroll.state.scroll_y - self.props.scroll_position.?.offset) > 0.1) {
                follow.following = follow.scroll.state.scroll_y >= follow.scroll.state.maxScrollY() - 1;
                follow.input_serial = follow.scroll.state.input_serial;
            }
            self.props.scroll_position.?.following = follow.following;
            self.props.scroll_position.?.offset = follow.scroll.state.scroll_y;
        }
    }
    fn tick(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *State = @ptrCast(@alignCast(raw));
        if (@import("../../../../shared/ui/styles/visible_region.zig").snapshot(self.cx, self.root) == null) return .done;
        if (self.props.expanded.*) if (self.follow) |*follow| {
            if (self.restore_scroll) {
                const content_height = follow.scroll.content.globalRect().h;
                const viewport_height = follow.scroll.container.globalRect().h;
                // The host can mount us inside its after-layout hook. Wait for
                // the new nodes' first layout before clamping a saved offset.
                if (content_height <= 0 or viewport_height <= 0) return .done;
                follow.scroll.state.content_height = content_height;
                follow.scroll.state.viewport_height = viewport_height;
                ui.widgets.setScrollY(follow.scroll.state, follow.scroll.content, self.props.scroll_position.?.offset);
                self.restore_scroll = false;
            }
            self.rememberScroll();
            follow.update();
            self.rememberScroll();
        };
        if (self.props.phase != .assembling and self.props.phase != .running and self.props.phase != .approved) return .done;
        const now: u64 = @intCast(@divTrunc(@import("../../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms));
        self.cx.scheduleRedrawAfterNs(100 * std.time.ns_per_ms);
        if (now -| self.last_tick_ms < 100) return .done;
        self.last_tick_ms = now;
        const elapsed = self.props.elapsed_ms +| (now -| self.mounted_ms);
        var buffer: [48]u8 = undefined;
        self.clock.setTextContent(self.cx.allocator, @import("../../../../shared/base/format.zig").duration(&buffer, elapsed, .short)) catch return .done;
        return .needs_layout;
    }
    fn toggle(self: *State) void {
        self.props.expanded.* = !self.props.expanded.*;
        if (self.props.expanded.*) setText(self.cx, self.detail_text, self.detail_value.peek()) catch {};
        self.disclosure.setExpanded(self.props.expanded.*);
        self.expanded.set(self.props.expanded.*);
        if (self.props.on_toggle) |callback| callback.invoke();
        self.cx.requestRedraw();
    }
};
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, props: Props) !*ui.Node {
    return (try mountRetained(cx, scope, props)).root;
}
/// Pencil Kaf7E A6 "Step": a 24 row on the group's rail — status 12, title 12/500, the arguments
/// mono 11 fg_tertiary, a "已拒绝" W.Tag when rejected, the elapsed time 11; a failure adds its
/// reason under the row (11.5 danger, 24 in). The whole row opens the details: one well.
pub fn mountRetained(cx: *ui.Cx, scope: *ui.Scope, props: Props) !Result {
    const space = IdSpace.of(scope);
    const root = try ui.boxStyled(cx, S.stepRoot, .{});
    root.meta.ownership.meta.test_id = props.test_id orelse space.id("ai.step");
    const action_title = if (props.tool_name) |name| try @import("../model/ai_tool_titles.zig").action(cx.allocator, name, props.tool_arguments orelse props.projection) else try cx.allocator.dupe(u8, props.title);
    defer cx.allocator.free(action_title);
    const title_value = try scope.createText(action_title, .{});
    // The row state is made below; the header's click reaches it through this forwarder.
    const toggle = try scope.createState(Toggle, .{});
    const expanded = try scope.createSignal(bool, props.expanded.*);
    const header = try @import("ai_step_disclosure.zig").header(cx, scope, space.id("ai.step.header"), title_value, expanded, cx.on(Toggle, toggle, Toggle.run));
    const indicator = try @import("ai_step_disclosure.zig").Indicator.mount(cx, scope, header, visual.step(props.phase), space.id("ai.step.status"));
    const title_node = try ui.textStyled(cx, S.stepTitle, action_title);
    title_node.setStyleInline(cx.allocator, S.headerTitle(cx.tokens));
    title_node.meta.ownership.meta.test_id = space.id("ai.step.title");
    try header.appendChild(cx.allocator, title_node);
    const args = try argumentsText(cx.allocator, props);
    defer cx.allocator.free(args);
    const projection = if (props.tool_name != null) try ui.textStyled(cx, S.stepArgs, args) else try ui.textStyled(cx, S.stepProse, args);
    projection.setStyleInline(cx.allocator, S.headerSummary(cx.tokens));
    projection.meta.ownership.meta.test_id = space.id("ai.step.projection");
    try header.appendChild(cx.allocator, projection);
    const rejected_tag = try ui.widgets.Tag(.{ .label = "已拒绝", .size = .sm }).mount(scope, cx);
    rejected_tag.meta.ownership.meta.test_id = space.id("ai.step.rejected");
    rejected_tag.setStyleInline(cx.allocator, .{ .flex_shrink = 0 });
    try header.appendChild(cx.allocator, rejected_tag);
    var buf: [48]u8 = undefined;
    const elapsed = if (props.phase == .approval) "待确认" else @import("../../../../shared/base/format.zig").duration(&buf, props.elapsed_ms, .short);
    const clock = try ui.textStyled(cx, S.elapsed, elapsed);
    clock.setStyleInline(cx.allocator, S.elapsedSlot(cx.tokens));
    clock.meta.ownership.meta.test_id = space.id("ai.step.elapsed");
    try header.appendChild(cx.allocator, clock);
    try root.appendChild(cx.allocator, header);
    const error_line = try ui.textStyled(cx, S.stepError, "");
    error_line.setStyleInline(cx.allocator, S.stepErrorBox(cx.tokens));
    error_line.meta.ownership.meta.test_id = space.id("ai.step.error");
    try root.appendChild(cx.allocator, error_line);
    // Sibling scopes are disposed in creation order: save the position before
    // ScrollArea releases its state during a conversation rebuild.
    const state_scope = try scope.childScope();
    const scroll = try ui.widgets.ScrollArea(.{ .direction = .vertical, .overscroll_y = .contain, .scrollbars = .always, .scrollbar_gutter = .stable }).mount(scope, cx);
    scroll.container.setStyleInline(cx.allocator, .{ .width = .fill(), .height = .{ .fit = .{ .max = 150 } }, .flex_shrink = 0 });
    scroll.content.setStyleInline(cx.allocator, S.stepDetailContent(cx.tokens));
    // Kaf7E A6 "Step output": the disclosed detail is one well (bg_secondary, radius 8), 18 in.
    try @import("ai_tool_results_view.zig").followTheme(cx, state_scope, scroll.container, S.stepDetail);
    const well = scroll.container;
    if (props.tool_name) |name| {
        if (!std.mem.startsWith(u8, props.detail, "工具：")) {
            const tool_detail = try @import("../model/ai_tool_titles.zig").detail(cx.allocator, name);
            defer cx.allocator.free(tool_detail);
            const tool = try ui.textStyled(cx, S.text, tool_detail);
            tool.meta.ownership.meta.test_id = space.id("ai.step.tool_id");
            try scroll.content.appendChild(cx.allocator, tool);
        }
    }
    const detail_value = try scope.createText(props.detail, .{});
    const text = try ui.textStyled(cx, S.stepDetailText, if (props.expanded.* or props.copy_detail) props.detail else "");
    try scroll.content.appendChild(cx.allocator, text);
    scroll.container.meta.ownership.meta.test_id = space.id("ai.step.details");
    text.meta.ownership.meta.test_id = space.id("ai.step.detail");
    if (props.copy_detail and props.detail.len > 0) {
        const copy = try scope.createState(Copy, .{ .cx = cx, .text = detail_value });
        copy.button = try @import("../../../../shared/ui/components/copy_button/copy_button.zig").Button.mount(cx, scope, .{ .icon_only = true, .icon_asset = ui.icons.copy, .icon_size = 12, .a11y_label = "复制步骤详情", .variant = .ghost, .size = .xs, .on_click = cx.on(Copy, copy, Copy.run) });
        const copy_button = copy.button.node;
        copy_button.meta.ownership.meta.test_id = space.id("ai.step.copy");
        const copy_hint = try @import("../../../../shared/ui/components/control_hint/control_hint.zig").mount(cx, scope, copy_button, "复制步骤详情", .{ .id = space.id("ai.step.copy.tooltip") });
        try scroll.content.appendChild(cx.allocator, copy_hint.wrapper);
    }
    try @import("../../pane/view/ai_text_selection.zig").attach(cx, scope, scroll.content);
    const disclosure = try @import("../../../../shared/ui/styles/layout_motion.zig").Disclosure.mount(cx, scope, well, props.expanded.*);
    try root.appendChild(cx.allocator, disclosure.root);
    const state = try state_scope.createState(State, .{ .cx = cx, .props = props, .root = root, .body = scroll.container, .disclosure = disclosure, .indicator = indicator, .expanded = expanded, .clock = clock, .title = title_node, .title_value = title_value, .projection = projection, .rejected_tag = rejected_tag, .error_line = error_line, .detail_text = text, .detail_value = detail_value, .mounted_ms = @intCast(@divTrunc(@import("../../../../platform/realtime.zig").monotonicNs(), std.time.ns_per_ms)), .follow = if (props.scroll_position) |position| .{ .scroll = scroll, .following = position.following } else null });
    state.props.detail = detail_value.peek();
    try state_scope.onCleanup(State, state, State.release);
    if (props.scroll_position) |position| position.retain();
    try state.update(props);
    try state_scope.createEffect(.{ .state = state, .publication = try cx.themeSignal() }, struct {
        fn run(ctx: anytype) void {
            _ = ctx.publication.get();
            ctx.state.applyInk();
        }
    }.run);
    toggle.state = state;
    return .{ .root = root, .state = state };
}
/// The header's click, forwarded to the row state once it exists.
const Toggle = struct {
    state: ?*State = null,
    fn run(self: *Toggle) void {
        if (self.state) |state| state.toggle();
    }
};
/// The row's arguments: a tool's projected target (no status words: the glyph carries the state);
/// thinking shows its latest line.
fn argumentsText(a: std.mem.Allocator, props: Props) ![]u8 {
    if (props.tool_name) |name| return @import("../model/ai_tool_header_projection.zig").project(a, name, props.tool_arguments orelse if (props.projection_is_status) "" else props.projection);
    return a.dupe(u8, props.projection);
}
/// The reason under a failed row (or why it did not run); empty otherwise.
fn failureText(a: std.mem.Allocator, props: Props) ![]u8 {
    return switch (props.phase) {
        .failed, .cancelled, .skipped => if (props.projection_is_status and props.projection.len > 0) a.dupe(u8, props.projection) else a.dupe(u8, @import("../model/ai_tool_header_projection.zig").phaseLabel(props.phase)),
        else => if (props.projection_is_status and props.phase != .rejected) a.dupe(u8, props.projection) else a.dupe(u8, ""),
    };
}
const Copy = struct {
    cx: *ui.Cx,
    text: *ui.Signal([]const u8),
    button: *@import("../../../../shared/ui/components/copy_button/copy_button.zig").Button = undefined,
    fn run(self: *Copy) void {
        self.button.copy(self.text.peek());
    }
};
pub fn title(name: []const u8) []const u8 {
    return @import("../model/ai_tool_titles.zig").title(name) orelse "工具调用";
}
