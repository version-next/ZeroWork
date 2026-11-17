//! View-model of the composer's decision panel (view: `ai_composer_interaction.yix`, Pencil Kaf7E
//! A7 / A11). Holds the pending request (tickets, owned display copies), the panel's signals, the
//! submit / replay guard and the actions sent to the host. The caller owns authorization and
//! supplies exact broker identities.
const std = @import("std");
const ui = @import("ui");
const question = @import("../../../../ai/user_interaction.zig");
const routing = @import("../../../../ai/execution_routing.zig");
const template = @import("_ai_composer_interaction.yix.zig");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const W = ui.widgets;
/// The decision content viewport: ≤ 180, short panels cap it lower (≥ 60).
pub const max_body_height: f32 = 180;
pub const min_body_height: f32 = 60;
pub const Ticket = union(enum) {
    tool: struct { sequence: u64, hash: [32]u8 },
    host: struct { sequence: u64, hash: [32]u8 },
    question: question.Ticket,
    pub fn eql(a: Ticket, b: Ticket) bool {
        if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
        return switch (a) {
            .tool => |v| v.sequence == b.tool.sequence and std.mem.eql(u8, &v.hash, &b.tool.hash),
            .host => |v| v.sequence == b.host.sequence and std.mem.eql(u8, &v.hash, &b.host.hash),
            .question => |v| v.eql(b.question),
        };
    }
};
pub const Option = struct { id: []const u8, label: []const u8, description: []const u8 = "" };
pub const Snapshot = struct {
    ticket: Ticket,
    title: []const u8,
    target: []const u8 = "",
    detail: []const u8 = "",
    impact: []const u8 = "",
    options: []const Option = &.{},
    allow_custom: bool = true,
    route: ?routing.Route = null,
    route_selectable: bool = false,
    route_reason: []const u8 = "",
};
pub const Action = union(enum) { approve, reject, answer: struct { option_id: ?[]const u8, text: []const u8 }, route: routing.Route };
pub const Callbacks = struct { context: *anyopaque, act: *const fn (*anyopaque, Ticket, Action) anyerror!void };
const Owned = struct {
    arena: std.heap.ArenaAllocator,
    value: Snapshot,
    radio: []ui.widgets.checkbox.RadioOption = &.{},
    fn init(a: std.mem.Allocator, source: Snapshot, space: IdSpace) !Owned {
        var arena = std.heap.ArenaAllocator.init(a);
        errdefer arena.deinit();
        const allocator = arena.allocator();
        var value = source;
        inline for (.{ "title", "target", "detail", "impact", "route_reason" }) |field| @field(value, field) = try allocator.dupe(u8, @field(source, field));
        const options = try allocator.dupe(Option, source.options[0..@min(source.options.len, 6)]);
        for (options) |*option| {
            option.id = try allocator.dupe(u8, option.id);
            option.label = try allocator.dupe(u8, option.label);
            option.description = try allocator.dupe(u8, option.description);
        }
        value.options = options;
        // The question's choices as native radio options (test ids ai.interaction.option.N; N = 6 is “其他”).
        const radio = try allocator.alloc(ui.widgets.checkbox.RadioOption, options.len + @intFromBool(source.allow_custom));
        for (options, 0..) |option, index| radio[index] = radioOption(space, index, option.label, option.description);
        if (source.allow_custom) radio[options.len] = radioOption(space, 6, "其他", "");
        return .{ .arena = arena, .value = value, .radio = radio };
    }
};
const radio_values = [_][]const u8{ "0", "1", "2", "3", "4", "5", "custom" };
fn radioIds(comptime space: IdSpace) [7][]const u8 {
    var ids: [7][]const u8 = undefined;
    for (0..7) |index| ids[index] = space.id(std.fmt.comptimePrint("ai.interaction.option.{d}", .{index}));
    return ids;
}
fn radioOption(space: IdSpace, index: usize, label: []const u8, description: []const u8) ui.widgets.checkbox.RadioOption {
    const ids = switch (space) {
        inline else => |known| comptime radioIds(known),
    };
    var option: ui.widgets.checkbox.RadioOption = .{ .value = radio_values[index], .label = label, .test_id = ids[index] };
    if (@hasField(ui.widgets.checkbox.RadioOption, "description")) {
        if (description.len != 0) option.description = description;
    }
    return option;
}
/// Run-mode segments in routing.Route order (test ids ai.interaction.route.N, N = the route).
const route_ids = [_][]const u8{ "batch", "current_terminal", "new_terminal" };
const route_labels = [_][]const u8{ "批处理", "当前终端", "新工作终端" };
fn routeTabs(comptime space: IdSpace, comptime disabled: bool) [3]ui.widgets.tabs.TabItem {
    var tabs: [3]ui.widgets.tabs.TabItem = undefined;
    for (&tabs, 0..) |*tab, index| tab.* = .{ .id = route_ids[index], .label = route_labels[index], .disabled = disabled, .test_id = space.id(std.fmt.comptimePrint("ai.interaction.route.{d}", .{index})) };
    return tabs;
}
/// The segments of one surface (`space`), enabled or locked.
fn routeTabsOf(space: IdSpace, disabled: bool) []const ui.widgets.tabs.TabItem {
    return switch (space) {
        inline else => |known| switch (disabled) {
            inline else => |off| &comptime routeTabs(known, off),
        },
    };
}
pub const View = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    callbacks: Callbacks,
    /// Test-id namespace of the surface this panel is mounted in (main assistant / child dialog).
    space: IdSpace,
    /// Nodes of the mounted view, handed over by the template (`keep`): the host's layout, press /
    /// focus release and tests use them.
    panel: *ui.Node = undefined,
    viewport: *ui.Node = undefined,
    accept: *ui.Node = undefined,
    reject: *ui.Node = undefined,
    submit_button: *ui.Node = undefined,
    /// The custom answer field (a live Ref from the template: its edit state answers “still
    /// composing?”; empty while the panel is not mounted).
    answer: ?*ui.view.Ref(W.input.InputResult) = null,
    /// “有 1 项操作待确认” capsule shown after 稍后处理 (native secondary sm Button).
    pending: *ui.Node = undefined,
    // Display state (the view reads these).
    title: *ui.Signal([]const u8),
    target: *ui.Signal([]const u8),
    detail: *ui.Signal([]const u8),
    impact: *ui.Signal([]const u8),
    route_reason: *ui.Signal([]const u8),
    error_text: *ui.Signal([]const u8),
    pending_text: *ui.Signal([]const u8),
    /// expanded / pending capsule / question / error / route row shown.
    shown: *ui.Signal(bool),
    capsule_shown: *ui.Signal(bool),
    question: *ui.Signal(bool),
    failed: *ui.Signal(bool),
    route_selectable: *ui.Signal(bool),
    radio: *ui.Signal([]const ui.widgets.checkbox.RadioOption),
    /// Run-mode segment shown as chosen (the route's id; null = none chosen yet).
    route_active: *ui.Signal(?[]const u8),
    max_body: *ui.Signal(f32),
    focus_request: *ui.Signal(ui.view.FocusRequest),
    selected: *ui.Signal(?[]const u8),
    custom_text: *ui.Signal([]const u8),
    disabled: *ui.Signal(bool),
    source: ?Owned = null,
    postponed: bool = false,
    visible: bool = true,
    submitted: bool = false,
    pub fn init(cx: *ui.Cx, scope: *ui.Scope, callbacks: Callbacks) !*View {
        const self = try scope.createState(View, .{
            .cx = cx,
            .scope = scope,
            .callbacks = callbacks,
            .space = IdSpace.of(scope),
            .title = try scope.createText("", .{}),
            .target = try scope.createText("", .{}),
            .detail = try scope.createText("", .{ .capacity = 256 }),
            .impact = try scope.createText("", .{}),
            .route_reason = try scope.createText("", .{}),
            .error_text = try scope.createText("", .{}),
            .pending_text = try scope.createText("有 1 项操作待确认", .{}),
            .shown = try scope.createSignal(bool, false),
            .capsule_shown = try scope.createSignal(bool, false),
            .question = try scope.createSignal(bool, false),
            .failed = try scope.createSignal(bool, false),
            .route_selectable = try scope.createSignal(bool, false),
            .radio = try scope.createSignal([]const ui.widgets.checkbox.RadioOption, &.{}),
            .route_active = try scope.createSignal(?[]const u8, null),
            .max_body = try scope.createSignal(f32, max_body_height),
            .focus_request = try scope.createSignal(ui.view.FocusRequest, .{}),
            .selected = try scope.createSignal(?[]const u8, null),
            .custom_text = try scope.createText("", .{ .capacity = 4096 }),
            .disabled = try scope.createSignal(bool, false),
        });
        try scope.onCleanup(View, self, release);
        return self;
    }
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, callbacks: Callbacks) !*View {
        const self = try init(cx, scope, callbacks);
        self.adopt(try ui.view.render(scope, cx, template.Interaction(.{ .m = self })), try ui.view.render(scope, cx, template.PendingCapsule(.{ .m = self })));
        return self;
    }
    /// The rendered panel and capsule (`mount`, or a template that places them: the composer).
    pub fn adopt(self: *View, panel: *ui.Node, pending: *ui.Node) void {
        self.panel = panel;
        self.pending = pending;
    }
    /// The panel's parts, from the template's refs once it has mounted them.
    pub fn keep(self: *View, viewport: ?W.scroll_area.ScrollAreaResult, accept: ?*ui.Node, reject: ?*ui.Node, submit_button: ?*ui.Node, answer: *ui.view.Ref(W.input.InputResult)) void {
        self.answer = answer;
        self.viewport = viewport.?.container;
        self.accept = accept.?;
        self.reject = reject.?;
        self.submit_button = submit_button.?;
    }
    pub fn update(self: *View, snapshot: ?Snapshot) !bool {
        const changed = if (snapshot) |value| if (self.source) |old| !value.ticket.eql(old.value.ticket) else true else self.source != null;
        if (changed) {
            self.cancelPress();
            self.releaseFocus();
            const next = if (snapshot) |value| try Owned.init(self.cx.allocator, value, self.space) else null;
            // The view drops its borrows of the old copy before the arena goes.
            self.radio.set(if (next) |owned| (if (owned.value.ticket == .question) owned.radio else &.{}) else &.{});
            if (self.source) |*old| old.arena.deinit();
            self.source = next;
            self.postponed = false;
            self.submitted = false;
            self.disabled.set(false);
            self.selected.set(null);
            self.custom_text.set("");
            self.failed.set(false);
            if (self.source) |owned| {
                const value = owned.value;
                const is_question = value.ticket == .question;
                self.question.set(is_question);
                self.title.set(value.title);
                self.target.set(value.target);
                self.detail.set(value.detail);
                self.impact.set(value.impact);
                if (is_question and value.options.len == 0) self.selected.set("custom");
                self.pending_text.set(if (is_question) "有 1 个问题待回答" else "有 1 项操作待确认");
            }
        }
        if (snapshot) |value| {
            self.route_selectable.set(value.route_selectable);
            if (value.route_selectable) {
                self.route_reason.set(value.route_reason);
                self.route_active.set(if (value.route) |route| route_ids[@backingInt(route)] else null);
            }
        }
        self.show();
        return changed;
    }
    /// Cap the decision content's viewport (≤ max_body_height) so the panel fits short windows.
    pub fn setMaxBody(self: *View, height: f32) bool {
        const next = @min(max_body_height, @max(min_body_height, height));
        if (@abs(self.max_body.peek() - next) < 0.5) return false;
        self.max_body.set(next);
        return true;
    }
    pub fn setVisible(self: *View, visible: bool) void {
        if (self.visible and !visible) {
            self.cancelPress();
            self.releaseFocus();
        }
        self.visible = visible;
        self.show();
    }
    pub fn expanded(self: *const View) bool {
        return self.visible and self.source != null and !self.postponed;
    }
    pub fn pendingVisible(self: *const View) bool {
        return self.visible and self.source != null and self.postponed;
    }
    fn show(self: *View) void {
        if (self.shown.peek() != self.expanded()) self.shown.set(self.expanded());
        if (self.capsule_shown.peek() != self.pendingVisible()) self.capsule_shown.set(self.pendingVisible());
    }
    fn chooseRouteId(self: *View, id: []const u8) void {
        for (route_ids, 0..) |route_id, index| if (std.mem.eql(u8, route_id, id)) {
            self.emit(.{ .route = @enumFromInt(index) });
            return;
        };
    }
    fn selected_(self: *View) void {
        self.failed.set(false);
        const selection = self.selected.peek() orelse return;
        // “其他”: the answer field opens under the list and takes the focus.
        if (std.mem.eql(u8, selection, "custom")) self.focus_request.set(self.focus_request.peek().to("ai.interaction.answer"));
    }
    fn customChanged_(self: *View) void {
        if (self.selected.peek() == null or !std.mem.eql(u8, self.selected.peek().?, "custom")) self.selected.set("custom");
        self.failed.set(false);
    }
    fn postpone_(self: *View) void {
        if (self.submitted) return;
        self.releaseFocus();
        self.postponed = true;
        self.show();
        self.cx.requestRedraw();
    }
    fn reopen_(self: *View) void {
        self.postponed = false;
        self.show();
        self.cx.requestRedraw();
    }
    fn submit_(self: *View) void {
        const value = if (self.source) |owned| owned.value else return;
        const selection = self.selected.peek() orelse {
            self.fail("请选择一项，或输入答案");
            return;
        };
        if (std.mem.eql(u8, selection, "custom")) {
            if (std.mem.trim(u8, self.custom_text.peek(), " \t\r\n").len == 0) {
                self.fail("请输入答案");
                return;
            }
            if (self.custom_text.peek().len > 4096) {
                self.fail("答案不能超过 4096 字节");
                return;
            }
            if (self.composing()) return;
            self.emit(.{ .answer = .{ .option_id = null, .text = self.custom_text.peek() } });
        } else {
            const index = std.fmt.parseInt(usize, selection, 10) catch return;
            if (index >= value.options.len) return;
            self.emit(.{ .answer = .{ .option_id = value.options[index].id, .text = "" } });
        }
    }
    /// The custom answer is still being composed (IME): submitting would send half a word.
    fn composing(self: *View) bool {
        const field = (self.answer orelse return false).get() orelse return false;
        return field.state.imeIsComposing();
    }
    fn emit(self: *View, action: Action) void {
        if (self.submitted) return;
        const source = self.source orelse return;
        self.callbacks.act(self.callbacks.context, source.value.ticket, action) catch |err| {
            self.fail(@errorName(err));
            return;
        };
        if (action != .route) {
            self.submitted = true;
            self.disabled.set(true);
        }
        self.cx.requestRedraw();
    }
    fn fail(self: *View, message: []const u8) void {
        self.error_text.set(message);
        self.failed.set(true);
        self.cx.requestRedraw();
    }
    fn copyDetail_(self: *View) void {
        const source = self.source orelse return;
        _ = ui.platform_services.clipboardSetText(self.cx.system_sdk, source.value.detail);
    }
    fn cancelPress(self: *View) void {
        if (self.cx.pressed_node) |pressed| if (pressed.isDescendantOf(self.panel) or pressed == self.pending or pressed.isDescendantOf(self.pending)) self.cx.cancelPointerInteractions(.explicit);
    }
    fn releaseFocus(self: *View) void {
        if (self.cx.focus_manager.current_focus) |focused| if (focused.isDescendantOf(self.panel) or focused == self.pending or focused.isDescendantOf(self.pending)) self.cx.clearFocus();
    }
    fn release(self: *View) void {
        self.radio.set(&.{});
        if (self.source) |*owned| owned.arena.deinit();
    }
};

// -- View bindings (read by ai_composer_interaction.yix) --

pub fn glyph(comptime name: []const u8) ui.SvgAsset {
    return comptime ui.icons.get(name).?;
}
pub fn expanded(m: *View) bool {
    return m.shown.get();
}
pub fn pendingShown(m: *View) bool {
    return m.capsule_shown.get();
}
pub fn isQuestion(m: *View) bool {
    return m.question.get();
}
pub fn title(m: *View) []const u8 {
    return m.title.get();
}
pub fn target(m: *View) []const u8 {
    return m.target.get();
}
pub fn targetShown(m: *View) bool {
    return m.target.get().len != 0;
}
pub fn detail(m: *View) []const u8 {
    return m.detail.get();
}
pub fn commandShown(m: *View) bool {
    return !m.question.get() and m.detail.get().len != 0;
}
pub fn impact(m: *View) []const u8 {
    return m.impact.get();
}
pub fn impactShown(m: *View) bool {
    return m.impact.get().len != 0;
}
pub fn routeShown(m: *View) bool {
    return m.route_selectable.get();
}
pub fn routeItems(m: *View) []const ui.widgets.tabs.TabItem {
    return routeTabsOf(m.space, m.disabled.get());
}
pub fn routeActive(m: *View) ?[]const u8 {
    return m.route_active.get();
}
pub fn reasonShown(m: *View) bool {
    return m.route_selectable.get() and m.route_reason.get().len != 0;
}
pub fn routeReason(m: *View) []const u8 {
    return m.route_reason.get();
}
pub fn optionsShown(m: *View) bool {
    return m.radio.get().len != 0;
}
pub fn radioOptions(m: *View) []const ui.widgets.checkbox.RadioOption {
    return m.radio.get();
}
/// The custom answer field opens under the list once “其他” is chosen (existing behaviour).
pub fn customShown(m: *View) bool {
    const selection = m.selected.get() orelse return false;
    return m.question.get() and std.mem.eql(u8, selection, "custom");
}
pub fn errorShown(m: *View) bool {
    return m.failed.get();
}
pub fn errorText(m: *View) []const u8 {
    return m.error_text.get();
}
pub fn pendingText(m: *View) []const u8 {
    return m.pending_text.get();
}
pub fn focus(m: *View) ui.view.FocusRequest {
    return m.focus_request.get();
}
pub fn maxBody(m: *View) f32 {
    return m.max_body.get();
}
pub fn selectedValue(m: *View) ?[]const u8 {
    return m.selected.get();
}
pub fn customText(m: *View) []const u8 {
    return m.custom_text.get();
}
pub fn locked(m: *View) bool {
    return m.disabled.get();
}
pub fn chooseRoute(m: *View, id: []const u8) void {
    m.chooseRouteId(id);
}
pub fn selectionChanged(m: *View, value: []const u8) void {
    m.selected.set(value);
    m.selected_();
}
pub fn customChanged(m: *View, text: []const u8) void {
    m.custom_text.set(text);
    m.customChanged_();
}
pub fn copyDetail(m: *View) void {
    m.copyDetail_();
}
pub fn postpone(m: *View) void {
    m.postpone_();
}
pub fn reopen(m: *View) void {
    m.reopen_();
}
pub fn approve(m: *View) void {
    m.emit(.approve);
}
pub fn deny(m: *View) void {
    m.emit(.reject);
}
pub fn submit(m: *View) void {
    m.submit_();
}
