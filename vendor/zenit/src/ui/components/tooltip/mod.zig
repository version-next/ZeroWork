/// Tooltip Component.
/// A noninteractive description for hover and keyboard focus.
const std = @import("std");
const core = @import("../../core.zig");
const view = @import("../../view.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const Color = core.Color;
const theme = core.theme;
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const Source = reactive.Source;
const Model = reactive.Model;
const Signal = reactive.Signal;
const Handler = core.Handler;
const bind_mod = @import("../../bind.zig");
const popover_mod = @import("../popover/mod.zig");
const time = @import("zenit_time");

// -- Styling in styles.zig --
const styles = @import("styles.zig");
/// In-place bubble (no popover): `W.TooltipSurface`.
pub const surface = @import("surface.zig");

/// Tooltip position (reuse 12 Popover placements).
pub const TooltipPosition = popover_mod.PopoverPosition;

/// Tooltip properties.
pub const TooltipProps = struct {
    /// Hint text (accepts signal / derived value).
    text: Source([]const u8),
    position: TooltipPosition = .bottom,
    offset: f32 = 4,
    /// Delay after hover until tooltip shows (ms); if pointer leaves, doesn't show.
    open_delay_ms: f32 = 500,
    /// Toggle: default driven by hover; pass `*Signal(bool)` to programmatically show/hide.
    open: Model(bool) = .{ .local = false },
    on_open_change: ?Handler(bool) = null,
    /// Fixed bubble / text colors. Deprecated: they are values, not theme references, so they do
    /// not follow a theme switch (a caller would have to remount); the bubble's defaults
    /// (`tooltip-bg` / `tooltip-fg`) do. To be removed in the next breaking window together with a
    /// declarative bubble whose `parts={.{ .content = … }}` overlay is the customization point
    /// (docs/design/component-look-follows-theme.md §3.2).
    background: ?Color = null,
    text_color: ?Color = null,
    font_size: f32 = 12,
    /// Optional bounded content width (px) for paths and other long values; the panel still
    /// shrinks to fit the viewport. null keeps the content-sized tooltip.
    width: ?f32 = null,
    /// Label wrapping override (default: the tooltip style's word breaking).
    wrap: ?core.TextWrap = null,
    /// Label line limit override. null uses the default of three lines.
    /// Zero disables the line clamp. The viewport may still clip the panel.
    max_lines: ?u16 = null,
    /// Test id of the label (the text node inside the hint panel), read at mount. The panel's own
    /// id is `parts={.{ .content = … }}` / `TooltipResult.content`; this names the text so a test can
    /// read it without the caller reaching into the panel's children.
    text_test_id: ?[]const u8 = null,
    /// The trigger fills the width it is given (min 0) instead of sizing to its content, so an
    /// ellipsized label inside stays within its row and the tooltip shows the full text.
    fill: bool = false,
    /// The trigger keeps its content's width but may shrink to 0 when its row runs out of space
    /// (a status bar item): an ellipsized label inside is cut where the space ends and the tooltip
    /// shows the full text. Ignored when `fill` is set.
    shrink: bool = false,
    /// Escape dismisses the open hint first (default). false: the hint stays out of the Escape
    /// order, so Escape reaches the panel around it (a list row's details inside a popover, where
    /// one Escape closes the popover).
    close_on_escape: bool = true,
    /// The hint does not apply now (accepts a signal / derived value). It describes the hint, not
    /// the trigger: the trigger stays interactive. A state, not an event: while true hover and
    /// keyboard focus do not open the hint and an open one closes (without warming the next
    /// trigger); when it turns false while the pointer rests on the trigger (or the trigger holds
    /// keyboard focus) the hint opens then, after the usual delay, without a new hover. (A button's
    /// hint that steps aside while its menu is open; Flutter `TooltipVisibility`.)
    disabled: Source(bool) = .{ .value = false },
    /// `.if_truncated`: the hint applies only while a text in the trigger that may be cut short
    /// (`text_overflow` ellipsis or `max_lines`) does not show in full at its laid-out size
    /// (`Cx.textTruncation`): the expansion hint of a list row repeating its full title (AppKit
    /// `allowsExpansionToolTips`). Also a state: judged on every layout while the pointer rests on
    /// the trigger or it holds keyboard focus — the hint opens when the text becomes cut short and
    /// closes when it comes to fit. A hint opened through a controlled `open` is left alone. Usually
    /// with `fill`, so the label is bounded by its row.
    show: TooltipShow = .always,
};

/// `TooltipProps.show`.
pub const TooltipShow = enum {
    /// Whenever hover / keyboard focus asks for it (and it is not `disabled`).
    always,
    /// Only while a truncatable text in the trigger is cut short.
    if_truncated,
};

/// Create Tooltip: `W.Tooltip(.{ .text = "Copy link" })`.
pub fn Tooltip(props: anytype) TooltipBuilder {
    return .{ .props = reactive.props.coerce(TooltipProps, props) };
}

/// TooltipBuilder.mount return value.
pub const TooltipResult = struct {
    wrapper: *Node,
    trigger: *Node,
    content: *Node,
    /// Toggle signal (null when split).
    open: ?*Signal(bool),
    /// `ui.view` integration (see src/ui/view_parts.zig). The tooltip has no content slot (its
    /// content is `text`), so children go to the trigger: Yix `<W.Tooltip text="…"><W.Button …/></W.Tooltip>`,
    /// Zig `ui.view.with(W.Tooltip(…), .{ … })`; `.trigger(…)` keeps working. `parts={.{ .content = id }}`
    /// reaches the hint panel (a field of this result).
    pub fn viewParts(self: TooltipResult) core.ViewParts {
        return .{ .root = self.wrapper, .slot = self.trigger, .trigger = self.trigger };
    }
};

pub const TooltipBuilder = struct {
    props: TooltipProps,

    /// Retain mode: mount.
    pub fn mount(self: TooltipBuilder, scope: *Scope, cx: *Cx) !TooltipResult {
        cx.owner.enterMount();
        defer cx.owner.exitMount();
        const allocator = cx.allocator;
        const t = cx.tokens;
        const p = self.props;

        const result = try popover_mod.Popover(.{
            .position = p.position,
            .width = p.width,
            .trigger = .hover,
            .safe_triangle = false,
            .offset = .{ .static = p.offset },
            .open_delay_ms = p.open_delay_ms,
            // An explicit width replaces the default bound.
            .max_width = if (p.width == null) styles.max_width else null,
            .constrain_width_to_viewport = true,
            .open = p.open,
            .on_open_change = p.on_open_change,
            .close_on_outside_click = false,
            .close_on_escape = p.close_on_escape,
            .prewarm_hidden_layout = false,
            .tier = .tooltip,
            // The bubble is display-only: input goes through it on every showing.
            .content_hit_test_visible = false,
            .fill_trigger = p.fill,
            .shrink_trigger = p.shrink,
        }).mount(scope, cx);
        // After Popover.mount, wrapper subtree (trigger/content/overlay layers) bound only to
        // my_scope;
        // bindScopeToNode destroy unbinds but doesn't release, so caller's scope.dispose() won't
        // reclaim it.
        // Below: ensureExt / text mount / binding can fail; mid-fail must release here (freeNode
        // auto-disposes bound subscope).
        errdefer cx.freeNode(result.wrapper);

        result.wrapper.meta.ownership.meta.component_name = "Tooltip";
        result.wrapper.behavior.interaction.a11y = .{};
        result.content.meta.ownership.meta.component_name = "TooltipContent";
        result.content.behavior.interaction.a11y = .{ .role = .tooltip };
        // Hit-test visibility has one writer, the layer (`content_hit_test_visible = false` above).
        result.content.style.padding = styles.tooltipPadding(t);
        result.content.style.border = .{ .radius = styles.tooltipRadius(t) };

        const content_ext = try result.content.style.ensureExtFallible(allocator);
        content_ext.hit_shape = .{ .rounded_rect = styles.tooltipRadius(t) };
        content_ext.clip_shape = .{ .rounded_rect = styles.tooltipRadius(t) };

        // Built and mounted: after that, released with wrapper if binding fails. Hangs under
        // Popover's scope (content in portal).
        var label: *Node = undefined;
        var label_style = styles.tooltipLabelStyle(p.text_color, p.font_size, t);
        if (p.wrap) |wrap| label_style.wrap = wrap;
        if (p.max_lines) |limit| label_style.max_lines = limit;
        try view.mount(result.scope, cx, result.content, view.capture(&label, view.text(
            .{ .style = label_style, .test_id = p.text_test_id },
            p.text.peek(),
        )));
        // Popover owns the panel width (px on open, shrunk to the viewport); the label fills it
        // and may shrink below its single-line width so `wrap` can take effect.
        if (p.width != null) {
            try result.content.setStyleInlineFallible(allocator, .{ .min_width = 0 });
            try label.setStyleInlineFallible(allocator, .{ .width = .fill(), .min_width = 0 });
        }
        // Tooltip a11y name points to label's text copy; re-point when dynamic text updates.
        if (result.content.behavior.interaction.a11y) |*a| a.label = label.getText().?.content;
        if (!p.text.isStatic()) {
            // Text binding must belong to Popover's scope: content in portal; on Popover unmount,
            // dispose
            // its scope first, then freeDetachedNodeAfterScopeDispose content (unbind children,
            // don't dispose).
            // If binding hangs elsewhere, unmount still writes freed label.
            try bind_mod.bindTextLabel(cx, result.scope, p.text, label, result.content);
        }
        try result.scope.createEffect(.{
            .theme_source = try cx.themeSignal(),
            .content = result.content,
            .label = label,
            .background = p.background,
            .text_color = p.text_color,
        }, struct {
            fn update(c: anytype) void {
                const tokens = c.theme_source.get();
                c.content.setBackgroundRaw(styles.tooltipContentBackground(c.background, tokens));
                c.content.style.ext.?.setShadow(tokens.tokens.shadow.sm);
                c.content.markRenderDirty();
                if (c.label.getText()) |old| {
                    var text = old;
                    text.color = styles.tooltipLabelColor(c.text_color, tokens);
                    c.label.setText(text);
                }
            }
        }.update);

        const state = try result.scope.createState(TooltipState, .{
            .cx = cx,
            .wrapper = result.wrapper,
            .wrapper_binding = result.wrapper.meta.ownership.scope.node_slot.?,
            .trigger = result.trigger,
            .content = result.content,
            .open = result.open_read,
            .show = result.show,
            .close = result.close,
            .hover_delay_ms = p.open_delay_ms,
            .escape = p.close_on_escape,
            .disabled = p.disabled,
            .show_when = p.show,
            .disabled_now = p.disabled.peek(),
        });
        try result.scope.onCleanup(TooltipState, state, TooltipState.cleanup);
        state.focus_subscription = try cx.focus_manager.subscribeVisibility(state, TooltipState.focusChanged);
        result.wrapper.behavior.events.on_hover = Cx.simpleHandler(TooltipState.hoverEnter, state);
        result.wrapper.behavior.events.on_leave = Cx.simpleHandler(TooltipState.hoverLeave, state);
        try result.scope.createEffect(state, TooltipState.syncOpen);
        if (!p.disabled.isStatic()) try result.scope.createEffect(state, TooltipState.syncDisabled);

        return .{ .wrapper = result.wrapper, .trigger = result.trigger, .content = result.content, .open = result.open };
    }
};

const TooltipState = struct {
    cx: *Cx,
    wrapper: *Node,
    /// Popover's scope binding slot for `wrapper`. The binding is a resource of the same scope,
    /// so it outlives this state's cleanup; freeing the wrapper (directly or through an ancestor)
    /// clears the slot first.
    wrapper_binding: *const ?*Node,
    trigger: *Node,
    content: *Node,
    open: Source(bool),
    show: Handler(void),
    close: Handler(void),
    hover_delay_ms: f32,
    /// Takes Escape while open (`TooltipProps.close_on_escape`).
    escape: bool = true,
    /// `TooltipProps.disabled` / `show`.
    disabled: Source(bool),
    show_when: TooltipShow,
    /// `disabled` as last applied (the effect acts on its changes).
    disabled_now: bool,
    focus_subscription: u64 = 0,
    keyboard_visible: bool = false,
    /// The pointer is over the trigger (hover entered, not left), whether or not the hint opened.
    hovered: bool = false,
    was_open: bool = false,
    /// The current open came from this component (hover, focus, a condition), not from a
    /// controlled `open`: only such an open is closed by `show = .if_truncated`.
    self_opened: bool = false,
    /// Closed by something else (Escape, a controlled `open`) while hovered / focused: stays closed
    /// until the pointer leaves or focus moves (no reopening from a condition meanwhile).
    suppressed: bool = false,
    /// The next close is the hint's condition going away (`disabled`, text came to fit): it does
    /// not warm the next trigger's hover delay.
    quiet_close: bool = false,
    /// `.if_truncated`: an after-layout check runs while hovered or focused.
    fit_check: bool = false,
    focus_task: core.SignalOwner.SettledTask = .{},
    dismiss_task: core.SignalOwner.SettledTask = .{},
    condition_task: core.SignalOwner.SettledTask = .{},

    fn cleanup(self: *TooltipState) void {
        self.focus_task.cancel();
        self.dismiss_task.cancel();
        self.condition_task.cancel();
        self.stopFitCheck();
        self.cx.focus_manager.unsubscribeVisibility(self.focus_subscription);
        self.clearDismissOwner();
        // The bound scope can be disposed before the wrapper is released, or after an
        // ancestor's free released it (e.g. the wrapper sits in a Modal body built from an
        // outer scope). Only a wrapper still bound to this scope is alive to be written.
        if (self.wrapper_binding.* == self.wrapper) {
            self.wrapper.behavior.events.on_hover = null;
            self.wrapper.behavior.events.on_leave = null;
        }
    }

    fn clearDismissOwner(self: *TooltipState) void {
        const current = self.cx.tooltip_state.dismiss orelse return;
        if (current.context == @as(*anyopaque, @ptrCast(self))) self.cx.tooltip_state.dismiss = null;
    }

    /// Whether the hint applies now: not `disabled`, and for `.if_truncated` a cut-short text in
    /// the trigger. null: cannot tell yet (the trigger has no layout, or layout is pending).
    fn applies(self: *TooltipState) ?bool {
        if (self.disabled_now) return false;
        if (self.show_when == .always) return true;
        if (self.wrapper_binding.* != self.wrapper) return false;
        return triggerTruncated(self.cx, self.trigger);
    }

    /// Open from this component (sets `self_opened`), with the delay for how it was asked.
    fn openSelf(self: *TooltipState, delay_ms: f32) void {
        if (self.open.peek() or self.suppressed) return;
        self.setEnterDelay(delay_ms);
        self.cx.needs_redraw = true;
        self.self_opened = true;
        self.show.invoke();
        if (!self.open.peek()) self.self_opened = false;
    }

    /// Close because the hint's condition went away (no warm start for the next trigger).
    fn closeQuietly(self: *TooltipState) void {
        if (!self.open.peek()) return;
        self.quiet_close = true;
        dismiss(self);
    }

    /// The hover / focus that would ask for the hint now, as an open delay (null: none).
    fn askingDelay(self: *TooltipState) ?f32 {
        if (self.keyboard_visible) return 0;
        if (self.hovered and self.cx.dispatcher.hoverFollowsScene() and !self.cx.hover_sync.pointer_from_touch) return self.hover_delay_ms;
        return null;
    }

    fn syncDisabled(self: *TooltipState) void {
        const disabled = self.disabled.get();
        if (disabled == self.disabled_now) return;
        self.disabled_now = disabled;
        self.cx.owner.runOutsideComputation(&self.condition_task, self, applyCondition);
    }

    /// Converge on the condition (`disabled`, `.if_truncated`): close a self-opened hint that no
    /// longer applies; open one that now applies under a resting pointer / held focus.
    fn applyCondition(raw: *anyopaque) void {
        const self: *TooltipState = @ptrCast(@alignCast(raw));
        const applies_now = self.applies() orelse return;
        if (self.open.peek()) {
            if (!applies_now and (self.self_opened or self.disabled_now)) self.closeQuietly();
            return;
        }
        if (!applies_now) return;
        const delay = self.askingDelay() orelse return;
        self.openSelf(delay);
    }

    fn updateFitCheck(self: *TooltipState) void {
        const want = self.show_when == .if_truncated and (self.hovered or self.keyboard_visible) and self.wrapper_binding.* == self.wrapper;
        if (want == self.fit_check) return;
        if (want) {
            self.cx.addAfterLayoutHook(self, fitCheck) catch return;
        } else self.cx.removeAfterLayoutHook(self);
        self.fit_check = want;
    }

    fn stopFitCheck(self: *TooltipState) void {
        if (!self.fit_check) return;
        self.cx.removeAfterLayoutHook(self);
        self.fit_check = false;
    }

    /// `.if_truncated`, hovered or focused: after each layout, open when the text became cut
    /// short, close a self-opened hint when it came to fit.
    fn fitCheck(raw: *anyopaque, _: u8, _: bool) core.AfterLayoutResult {
        const self: *TooltipState = @ptrCast(@alignCast(raw));
        if (self.wrapper_binding.* != self.wrapper) return .done;
        const applies_now = self.applies() orelse return .done;
        const wants_change = if (self.open.peek()) !applies_now and self.self_opened else applies_now and !self.suppressed and self.askingDelay() != null;
        if (wants_change) self.cx.owner.runOutsideComputation(&self.condition_task, self, applyCondition);
        return .done;
    }

    fn syncOpen(self: *TooltipState) void {
        const open = self.open.get();
        if (open == self.was_open) return;
        self.was_open = open;
        // An ancestor's free can release the wrapper (and its content) before this scope
        // disposes; a released tooltip neither registers nor reads its nodes.
        const alive = self.wrapper_binding.* == self.wrapper;
        if (open and alive) {
            const previous = self.cx.tooltip_state.dismiss;
            // Out of the Escape order: still the one hint shown (the previous one closes), but
            // Escape goes past it.
            self.cx.tooltip_state.dismiss = if (self.escape) Cx.simpleHandler(dismiss, self) else null;
            // A previous tooltip can still be open when focus changes while
            // the pointer remains on its trigger.
            if (previous) |handler| {
                if (handler.context != @as(*anyopaque, @ptrCast(self))) handler.invoke();
            }
        } else {
            const quiet = self.quiet_close;
            self.quiet_close = false;
            // Closed by something else (Escape, a controlled `open`) while still asked for: stay
            // closed until the pointer leaves / focus moves.
            if (!quiet and (self.hovered or self.keyboard_visible)) self.suppressed = true;
            self.self_opened = false;
            if (alive and !quiet and self.content.getOpacity() > 0.001) self.recordClose();
            self.clearDismissOwner();
            if (alive) self.setEnterDelay(self.hover_delay_ms);
        }
    }

    fn recordClose(self: *TooltipState) void {
        self.cx.tooltip_state.last_close = .{
            .trigger_id = self.wrapper.id,
            .time_ns = time.monotonicTimestamp(self.cx.io),
        };
    }

    fn setEnterDelay(self: *TooltipState, delay_ms: f32) void {
        // The layer exists only while open: Popover applies the delay to it and to the
        // configuration its next open registers. A zero delay (keyboard focus) also skips the
        // remaining hover delay.
        popover_mod.setEnterDelay(self.content, self.cx, delay_ms);
    }

    fn hoverEnter(raw: *anyopaque) void {
        const self: *TooltipState = @ptrCast(@alignCast(raw));
        self.hovered = true;
        self.suppressed = false;
        self.updateFitCheck();
        if (self.open.peek() or self.cx.hover_sync.pointer_from_touch or !self.cx.dispatcher.hoverFollowsScene()) return;
        // Not applicable, or not known yet (the fit check decides after the next layout).
        if (!(self.applies() orelse false)) return;
        const recent = if (self.cx.tooltip_state.last_close) |last| blk: {
            const elapsed = time.monotonicTimestamp(self.cx.io) - last.time_ns;
            break :blk last.trigger_id != self.wrapper.id and elapsed >= 0 and elapsed <= 300 * std.time.ns_per_ms;
        } else false;
        self.openSelf(if (recent) 0 else self.hover_delay_ms);
    }

    fn hoverLeave(raw: *anyopaque) void {
        const self: *TooltipState = @ptrCast(@alignCast(raw));
        self.hovered = false;
        if (!self.keyboard_visible) self.suppressed = false;
        self.updateFitCheck();
        if (!self.keyboard_visible) dismiss(raw);
    }

    fn focusChanged(raw: *anyopaque) void {
        const self: *TooltipState = @ptrCast(@alignCast(raw));
        const fm = &self.cx.focus_manager;
        const focused = fm.getFocused();
        const visible = fm.focus_visible and focused != null and focused.?.isDescendantOf(self.wrapper);
        if (visible == self.keyboard_visible) return;
        self.keyboard_visible = visible;
        if (!visible and !self.hovered) self.suppressed = false;
        self.updateFitCheck();
        self.cx.owner.runOutsideComputation(&self.focus_task, self, syncFocus);
    }

    fn syncFocus(raw: *anyopaque) void {
        const self: *TooltipState = @ptrCast(@alignCast(raw));
        if (self.keyboard_visible) {
            if (!(self.applies() orelse false)) return;
            if (self.open.peek()) {
                self.setEnterDelay(0);
                self.cx.needs_redraw = true;
            } else self.openSelf(0);
        } else {
            dismiss(raw);
        }
    }

    fn dismiss(raw: *anyopaque) void {
        const self: *TooltipState = @ptrCast(@alignCast(raw));
        self.cx.owner.runOutsideComputation(&self.dismiss_task, self, commitDismiss);
    }

    fn commitDismiss(raw: *anyopaque) void {
        const self: *TooltipState = @ptrCast(@alignCast(raw));
        if (!self.open.peek()) return;
        // Hover delivers leave then enter in one owner batch. Publish the
        // settled close before the next trigger checks the warm interval.
        const owner = self.cx.owner;
        owner.beginReactiveCallback();
        defer owner.endReactiveCallback();
        const was_visible = self.content.getOpacity() > 0.001;
        self.close.invoke();
        if (was_visible and !self.open.peek()) self.recordClose();
    }
};

/// `.if_truncated`: whether a truncatable text in the trigger (single line with an ellipsis, or
/// `max_lines` set) is cut short now; texts in hidden or fully transparent subtrees do not count.
/// null when a candidate has no current layout (not laid out yet, or its layout is pending).
fn triggerTruncated(cx: *Cx, node: *const Node) ?bool {
    if (node.style.display == .none or node.getOpacity() < 0.01) return false;
    var unknown = false;
    if (node.resolveTextProps()) |t| {
        if (t.text_overflow != .clip or t.max_lines > 0) {
            if (cx.textTruncation(node)) |kind| {
                if (kind != .none) return true;
            } else unknown = true;
        }
    }
    for (node.children.items) |child| {
        if (triggerTruncated(cx, child)) |cut| {
            if (cut) return true;
        } else unknown = true;
    }
    return if (unknown) null else false;
}

// ========= Tests =========

test "Tooltip: basic" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Tooltip(.{
        .text = "Hello tooltip",
        .position = .top,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.wrapper);

    const btn = try box(ctx, .{
        .width = .{ .px = 100 },
        .height = .{ .px = 32 },
        .background = theme.dark.tokens.color.accent,
    }, .{
        try core.text(ctx, "Hover me", .{}),
    });
    try result.trigger.appendChild(std.testing.allocator, btn);

    try std.testing.expectEqual(@as(usize, 1), result.wrapper.children.items.len);

    const tooltip = result.content;
    try std.testing.expect(tooltip.parent == null);
    try std.testing.expectEqual(core.Sizing{ .px = 0 }, tooltip.style.width);
    try std.testing.expectEqual(@as(usize, 1), tooltip.children.items.len);
    try std.testing.expect(tooltip.behavior.interaction.a11y != null);
    try std.testing.expectEqual(core.A11yRole.tooltip, tooltip.behavior.interaction.a11y.?.role);
}

test "Tooltip: text_test_id names the label, which follows a text source" {
    const ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(800, 600);
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const root = try box(ctx, .{ .width = .{ .px = 800 }, .height = .{ .px = 600 } }, .{});
    ctx.root = root;
    const text = try scope.createText("first", .{});
    const named = try Tooltip(.{ .text = text, .text_test_id = "hint.text" }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, named.wrapper);
    const label = named.content.children.items[0];
    try std.testing.expectEqualStrings("hint.text", label.meta.ownership.meta.test_id.?);
    try std.testing.expectEqualStrings("first", label.getText().?.content);
    text.set("second line");
    try std.testing.expectEqualStrings("second line", label.getText().?.content);
    // Without it the label stays unnamed (the panel keeps its own id).
    const plain = try Tooltip(.{ .text = "plain" }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, plain.wrapper);
    try std.testing.expect(plain.content.children.items[0].meta.ownership.meta.test_id == null);
}

test "Tooltip: fill keeps an ellipsized label within the width it is given" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const row = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 40 }, .direction = .row }, .{});
    ctx.root = row;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const long = "A very long original session title that does not fit in the row at all";
    const filled = try Tooltip(.{ .text = long, .fill = true }).mount(scope, ctx);
    try row.appendChild(std.testing.allocator, filled.wrapper);
    const label = try core.text(ctx, long, .{ .wrap = .none, .text_overflow = .ellipsis });
    label.setStyleInline(std.testing.allocator, .{ .width = .fill(), .min_width = 0 });
    try filled.trigger.appendChild(std.testing.allocator, label);
    ctx.layout();
    try std.testing.expect(filled.wrapper.rectFromWorldOrFallback().w <= 120.5);
    try std.testing.expect(filled.trigger.rectFromWorldOrFallback().w <= 120.5);
    try std.testing.expect(label.rectFromWorldOrFallback().w <= 120.5);
    // Without fill the trigger keeps its content width (unchanged default).
    const row2 = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 40 }, .direction = .row }, .{});
    try row.appendChild(std.testing.allocator, row2);
    const plain = try Tooltip(.{ .text = long }).mount(scope, ctx);
    try row2.appendChild(std.testing.allocator, plain.wrapper);
    try plain.trigger.appendChild(std.testing.allocator, try core.text(ctx, long, .{ .wrap = .none }));
    ctx.layout();
    try std.testing.expect(plain.trigger.rectFromWorldOrFallback().w > 120.5);
}

test "Tooltip: shrink keeps the content width until the row runs out of space" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 80 }, .direction = .column }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const long = "A very long status value that does not fit in the bar at all";
    // Too narrow: the trigger gives way and the ellipsized label stays within the row.
    const row = try box(ctx, .{ .width = .{ .px = 120 }, .height = .{ .px = 20 }, .direction = .row }, .{});
    try root.appendChild(std.testing.allocator, row);
    const narrow = try Tooltip(.{ .text = long, .shrink = true }).mount(scope, ctx);
    try row.appendChild(std.testing.allocator, narrow.wrapper);
    const label = try core.text(ctx, long, .{ .wrap = .none, .text_overflow = .ellipsis });
    label.setStyleInline(std.testing.allocator, .{ .min_width = 0 });
    try narrow.trigger.appendChild(std.testing.allocator, label);
    // Wide enough: the trigger keeps its content width (it does not fill the row like `fill`).
    const row2 = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 20 }, .direction = .row }, .{});
    try root.appendChild(std.testing.allocator, row2);
    const short = try Tooltip(.{ .text = "Ready", .shrink = true }).mount(scope, ctx);
    try row2.appendChild(std.testing.allocator, short.wrapper);
    const short_label = try core.text(ctx, "Ready", .{ .wrap = .none, .text_overflow = .ellipsis });
    try short.trigger.appendChild(std.testing.allocator, short_label);
    ctx.layout();
    try std.testing.expect(narrow.wrapper.rectFromWorldOrFallback().w <= 120.5);
    try std.testing.expect(narrow.trigger.rectFromWorldOrFallback().w <= 120.5);
    try std.testing.expect(label.rectFromWorldOrFallback().w <= 120.5);
    const short_w = short.wrapper.rectFromWorldOrFallback().w;
    try std.testing.expect(short_w > 0);
    try std.testing.expect(short_w < 200);
    try std.testing.expectApproxEqAbs(short_label.rectFromWorldOrFallback().w, short.trigger.rectFromWorldOrFallback().w, 0.5);
}

test "Tooltip: hover shows" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Tooltip(.{
        .text = "Visible",
        .position = .bottom,
    }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, result.wrapper);

    const tooltip = result.content;

    try std.testing.expectEqual(core.Sizing{ .px = 0 }, tooltip.style.width);
    try std.testing.expect(result.wrapper.behavior.events.on_hover != null);
    try std.testing.expect(result.wrapper.behavior.events.on_leave != null);

    result.wrapper.behavior.events.on_hover.?.invoke();
    try std.testing.expect(tooltip.parent != null);
    try std.testing.expectEqual(core.Sizing{ .fit = .{ .max = styles.max_width } }, tooltip.style.width);

    result.wrapper.behavior.events.on_leave.?.invoke();
    try std.testing.expectEqual(core.Sizing{ .fit = .{ .max = styles.max_width } }, tooltip.style.width);
}

test "Tooltip: close_on_escape false leaves Escape to what is under the hint" {
    const a = std.testing.allocator;
    var cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try box(cx, .{ .width = .fixed(400), .height = .fixed(300), .direction = .row, .gap = 8 }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const kept = try Tooltip(.{ .text = "Kept", .open = true, .close_on_escape = false }).mount(scope, cx);
    const plain = try Tooltip(.{ .text = "Plain", .open = true }).mount(scope, cx);
    for ([_]TooltipResult{ kept, plain }) |tip| {
        try root.appendChild(a, tip.wrapper);
        try tip.trigger.appendChild(a, try box(cx, .{ .width = .fixed(80), .height = .fixed(32) }, .{}));
    }
    cx.layout();
    _ = cx.render();
    try std.testing.expect(cx.overlay_stack.findLayerForNode(kept.content).?.config.dismiss.escape == false);
    try std.testing.expect(cx.overlay_stack.findLayerForNode(plain.content).?.config.dismiss.escape);
    // Escape takes the plain hint; with it gone, a second Escape leaves the kept one open.
    cx.handleKeyDown(.escape, .{});
    try std.testing.expect(!plain.open.?.peek());
    cx.handleKeyDown(.escape, .{});
    try std.testing.expect(kept.open.?.peek());
}

test "Tooltip: crossing between triggers warms the second enter before the input batch settles" {
    const a = std.testing.allocator;
    var cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try box(cx, .{ .width = .fixed(400), .height = .fixed(300), .direction = .row, .gap = 8 }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();

    const first = try Tooltip(.{ .text = "First", .open = true }).mount(scope, cx);
    const second = try Tooltip(.{ .text = "Second" }).mount(scope, cx);
    for ([_]TooltipResult{ first, second }) |tip| {
        try root.appendChild(a, tip.wrapper);
        const trigger = try box(cx, .{ .width = .fixed(80), .height = .fixed(32) }, .{});
        trigger.setFocusable(true);
        try tip.trigger.appendChild(a, trigger);
    }
    cx.layout();
    _ = cx.render();
    try std.testing.expectEqual(@as(f32, 1), first.content.getOpacity());

    const r1 = first.trigger.globalRect();
    const r2 = second.trigger.globalRect();
    cx.handleMouseMove(r1.x + 1, r1.y + 1);
    cx.handleMouseMove(r2.x + 1, r2.y + 1);
    try std.testing.expect(!first.open.?.peek());
    try std.testing.expect(second.open.?.peek());
    const second_layer = cx.overlay_stack.findLayerForNode(second.content).?;
    try std.testing.expectEqual(@as(f32, 0), second_layer.enter_ctrl.delay_remaining_ms);

    cx.handleKeyDown(.escape, .{});
    try std.testing.expect(!second.open.?.peek());
    try std.testing.expect(cx.tooltip_state.dismiss == null);
}

test "Tooltip: a modal opened over a hovered trigger makes its hint step aside and takes the first Escape; a hint inside the modal takes its own" {
    const a = std.testing.allocator;
    const modal_mod = @import("../modal/mod.zig");
    var cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 600);
    const root = try box(cx, .{ .width = .fixed(800), .height = .fixed(600) }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();

    // The pointer rests on a tab: its hint is up.
    const tab = try Tooltip(.{ .text = "Tab" }).mount(scope, cx);
    try root.appendChild(a, tab.wrapper);
    try tab.trigger.appendChild(a, try box(cx, .{ .width = .fixed(80), .height = .fixed(32) }, .{}));
    const visible = try scope.createSignal(bool, false);
    const modal = try modal_mod.Modal(.{ .open = visible, .enter_transition = .none, .exit_transition = .none }).mount(scope, cx);
    if (!modal.portaled) try root.appendChild(a, modal.overlay);
    const inner = try Tooltip(.{ .text = "Inner" }).mount(scope, cx);
    try modal.body.appendChild(a, inner.wrapper);
    try inner.trigger.appendChild(a, try box(cx, .{ .width = .fixed(80), .height = .fixed(32) }, .{}));
    cx.layout();
    _ = cx.render();
    tab.open.?.set(true);
    cx.layout();
    _ = cx.render();
    try std.testing.expect(cx.tooltip_state.dismiss != null);

    // A confirmation opens over it: the tab hint steps aside (a tooltip never covers an overlay opened
    // over its trigger, OverlayStack.tooltipBeneathOverlay) and the first Escape closes the confirmation.
    visible.set(true);
    cx.layout();
    _ = cx.render();
    cx.layout();
    _ = cx.render();
    try std.testing.expect(!tab.open.?.peek());
    cx.handleKeyDown(.escape, .{});
    try std.testing.expect(!visible.peek());
    cx.layout();
    _ = cx.render();

    // With nothing above the tab any more its hint may show again on top, and takes Escape itself.
    tab.open.?.set(true);
    cx.layout();
    _ = cx.render();
    try std.testing.expect(tab.open.?.peek());
    cx.handleKeyDown(.escape, .{});
    try std.testing.expect(!tab.open.?.peek());
    cx.layout();
    _ = cx.render();

    // A hint on a control inside the topmost dialog is not covered: it takes Escape first.
    visible.set(true);
    cx.layout();
    _ = cx.render();
    inner.open.?.set(true);
    cx.layout();
    _ = cx.render();
    cx.handleKeyDown(.escape, .{});
    try std.testing.expect(!inner.open.?.peek());
    try std.testing.expect(visible.peek());
    cx.layout();
    _ = cx.render();
    cx.handleKeyDown(.escape, .{});
    try std.testing.expect(!visible.peek());
}

test "Tooltip: keyboard focus bypasses hover delay without taking focus and press dismisses" {
    const a = std.testing.allocator;
    var cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try box(cx, .{ .width = .fixed(400), .height = .fixed(300) }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const tip = try Tooltip(.{ .text = "Keyboard focus" }).mount(scope, cx);
    try root.appendChild(a, tip.wrapper);
    const trigger = try box(cx, .{ .width = .fixed(80), .height = .fixed(32) }, .{});
    trigger.setFocusable(true);
    try tip.trigger.appendChild(a, trigger);
    cx.layout();
    _ = cx.render();

    cx.focus_manager.setFocusWithReason(trigger, .tab);
    try std.testing.expect(cx.isFocused(trigger));
    try std.testing.expect(tip.open.?.peek());
    try std.testing.expectEqual(@as(f32, 0), cx.overlay_stack.findLayerForNode(tip.content).?.enter_ctrl.delay_remaining_ms);

    const rect = trigger.globalRect();
    cx.handleMouseDown(rect.x + 1, rect.y + 1, .{});
    try std.testing.expect(cx.isFocused(trigger));
    try std.testing.expect(!tip.open.?.peek());
}

const CondRig = struct {
    cx: *Cx,
    scope: *Scope,
    root: *Node,
    fn init() !CondRig {
        const a = std.testing.allocator;
        const cx = try Cx.init(a, std.testing.io);
        errdefer cx.deinit();
        cx.setViewport(600, 300);
        const root = try box(cx, .{ .width = .fixed(600), .height = .fixed(300), .direction = .column }, .{});
        cx.root = root;
        return .{ .cx = cx, .scope = try Scope.init(a, null, cx.owner), .root = root };
    }
    fn frame(self: *CondRig) void {
        self.cx.layout();
        _ = self.cx.render();
    }
    fn deinit(self: *CondRig) void {
        self.scope.dispose();
        self.cx.deinit();
    }
};

test "Tooltip: disabled is a state — no hint while true, opens when it turns false under a resting pointer or focus" {
    const a = std.testing.allocator;
    var r = try CondRig.init();
    defer r.deinit();
    const cx = r.cx;
    const disabled = try r.scope.createSignal(bool, true);
    const tip = try Tooltip(.{ .text = "Only while it applies", .disabled = disabled }).mount(r.scope, cx);
    try r.root.appendChild(a, tip.wrapper);
    const trigger = try box(cx, .{ .width = .fixed(80), .height = .fixed(32) }, .{});
    trigger.setFocusable(true);
    try tip.trigger.appendChild(a, trigger);
    r.frame();
    const rect = trigger.globalRect();

    cx.handleMouseMove(rect.x + 5, rect.y + 5);
    try std.testing.expect(!tip.open.?.peek());
    // Applies while the pointer rests on the trigger: opens (no new hover), with the hover delay.
    disabled.set(false);
    try std.testing.expect(tip.open.?.peek());
    try std.testing.expectEqual(@as(f32, 500), cx.overlay_stack.findLayerForNode(tip.content).?.enter_ctrl.delay_remaining_ms);
    // No longer applies while open: closes, and does not warm the next trigger.
    disabled.set(true);
    try std.testing.expect(!tip.open.?.peek());
    try std.testing.expect(cx.tooltip_state.last_close == null);
    // Pointer leaves, then applies: nothing opens.
    cx.handleMouseMove(590, 290);
    disabled.set(false);
    try std.testing.expect(!tip.open.?.peek());
    // Keyboard focus while disabled: nothing; applies while focused: opens without delay.
    disabled.set(true);
    cx.focus_manager.setFocusWithReason(trigger, .tab);
    try std.testing.expect(cx.isFocused(trigger));
    try std.testing.expect(!tip.open.?.peek());
    disabled.set(false);
    try std.testing.expect(tip.open.?.peek());
    try std.testing.expectEqual(@as(f32, 0), cx.overlay_stack.findLayerForNode(tip.content).?.enter_ctrl.delay_remaining_ms);
}

test "Tooltip: after Escape the hint stays closed until the pointer leaves, even if its condition flips" {
    const a = std.testing.allocator;
    var r = try CondRig.init();
    defer r.deinit();
    const cx = r.cx;
    const disabled = try r.scope.createSignal(bool, false);
    const tip = try Tooltip(.{ .text = "Escapable", .disabled = disabled }).mount(r.scope, cx);
    try r.root.appendChild(a, tip.wrapper);
    const trigger = try box(cx, .{ .width = .fixed(80), .height = .fixed(32) }, .{});
    try tip.trigger.appendChild(a, trigger);
    r.frame();
    const rect = trigger.globalRect();
    cx.handleMouseMove(rect.x + 5, rect.y + 5);
    try std.testing.expect(tip.open.?.peek());
    cx.handleKeyDown(.escape, .{});
    try std.testing.expect(!tip.open.?.peek());
    disabled.set(true);
    disabled.set(false);
    try std.testing.expect(!tip.open.?.peek());
    // Leave and come back: shows again.
    cx.handleMouseMove(590, 290);
    cx.handleMouseMove(rect.x + 6, rect.y + 6);
    try std.testing.expect(tip.open.?.peek());
}

test "Tooltip: show = .if_truncated follows the label — opens when it is cut short, closes when it fits" {
    const a = std.testing.allocator;
    var r = try CondRig.init();
    defer r.deinit();
    const cx = r.cx;
    const row = try box(cx, .{ .width = .fixed(120), .height = .fixed(40), .direction = .row }, .{});
    try r.root.appendChild(a, row);
    const long = "A very long original session title that does not fit in the row at all";
    const tip = try Tooltip(.{ .text = long, .fill = true, .show = .if_truncated }).mount(r.scope, cx);
    try row.appendChild(a, tip.wrapper);
    const label = try core.text(cx, long, .{ .wrap = .none, .text_overflow = .ellipsis });
    label.setStyleInline(a, .{ .width = .fill(), .min_width = 0 });
    try tip.trigger.appendChild(a, label);
    // A secondary clip-overflow text is not a candidate (only truncatable texts count).
    const meta = try core.text(cx, "2026-11-16 12:00 · metadata that is clipped", .{ .wrap = .none });
    meta.setStyleInline(a, .{ .width = .fixed(10), .min_width = 0, .flex_shrink = 0 });
    try tip.trigger.appendChild(a, meta);
    r.frame();
    try std.testing.expectEqual(core.TextTruncation.ellipsized, cx.textTruncation(label).?);

    const rect = tip.wrapper.globalRect();
    cx.handleMouseMove(rect.x + 5, rect.y + 5);
    try std.testing.expect(tip.open.?.peek());
    // The row widens until the title fits: the next layout closes the hint (quietly).
    row.setStyleInline(a, .{ .width = .fixed(590) });
    r.frame();
    try std.testing.expectEqual(core.TextTruncation.none, cx.textTruncation(label).?);
    try std.testing.expect(!tip.open.?.peek());
    try std.testing.expect(cx.tooltip_state.last_close == null);
    // Narrowed again under the resting pointer: the hint comes back without a new hover.
    row.setStyleInline(a, .{ .width = .fixed(120) });
    r.frame();
    try std.testing.expect(tip.open.?.peek());
    // Leaving closes it; with a short title a hover does nothing.
    cx.handleMouseMove(590, 290);
    try std.testing.expect(!tip.open.?.peek());
    try label.setTextContent(a, "Short");
    r.frame();
    cx.handleMouseMove(rect.x + 5, rect.y + 5);
    r.frame();
    try std.testing.expect(!tip.open.?.peek());
    // Text changed under the pointer and not laid out yet: no decision until the layout, then
    // the hint follows it.
    try label.setTextContent(a, long);
    try std.testing.expect(cx.textTruncation(label) == null);
    r.frame();
    try std.testing.expect(tip.open.?.peek());
    // A hint opened through a controlled `open` is left alone when the text fits.
    const forced = try r.scope.createSignal(bool, false);
    const ctl = try Tooltip(.{ .text = "Forced", .open = forced, .show = .if_truncated }).mount(r.scope, cx);
    try r.root.appendChild(a, ctl.wrapper);
    try ctl.trigger.appendChild(a, try core.text(cx, "Fits", .{ .wrap = .none, .text_overflow = .ellipsis }));
    r.frame();
    forced.set(true);
    r.frame();
    try std.testing.expect(forced.peek());
}

test "Cx.textTruncation: ellipsized / clipped single lines, max_lines clamp, overflowing wrapped lines, inherited font, pending layout" {
    const a = std.testing.allocator;
    var r = try CondRig.init();
    defer r.deinit();
    const cx = r.cx;
    const clamped = try core.text(cx, "one two three four five six seven eight nine ten eleven twelve", .{ .wrap = .word, .max_lines = 2 });
    clamped.setStyleInline(a, .{ .width = .fixed(60) });
    const whole = try core.text(cx, "one two", .{ .wrap = .word, .max_lines = 2 });
    whole.setStyleInline(a, .{ .width = .fixed(60) });
    const clipped = try core.text(cx, "A long line that would not fit at all here", .{ .wrap = .none });
    clipped.setStyleInline(a, .{ .width = .fixed(40) });
    const lines = try core.text(cx, "short\naveryveryverylonglinewithoutanybreakopportunity", .{ .wrap = .newline_only });
    lines.setStyleInline(a, .{ .width = .fixed(60) });
    // Font size from the parent's style (inherited), not declared on the text: a label that fits
    // at the default size is cut at 24.
    const big_box = try box(cx, .{ .width = .fixed(100), .font_size = 24, .direction = .column }, .{});
    const inherited = try core.text(cx, "Twelve chars", .{ .wrap = .none, .text_overflow = .ellipsis });
    inherited.setStyleInline(a, .{ .width = .fixed(100) });
    try big_box.appendChild(a, inherited);
    for ([_]*Node{ clamped, whole, clipped, lines, big_box }) |n| try r.root.appendChild(a, n);
    r.frame();
    try std.testing.expectEqual(core.TextTruncation.line_clamped, cx.textTruncation(clamped).?);
    try std.testing.expectEqual(core.TextTruncation.none, cx.textTruncation(whole).?);
    try std.testing.expectEqual(core.TextTruncation.clipped, cx.textTruncation(clipped).?);
    try std.testing.expectEqual(core.TextTruncation.overflowing, cx.textTruncation(lines).?);
    try std.testing.expectEqual(core.TextTruncation.ellipsized, cx.textTruncation(inherited).?);
    // Pending layout: unknown.
    try whole.setTextContent(a, "one two three four five six seven eight nine ten");
    try std.testing.expect(cx.textTruncation(whole) == null);
    r.frame();
    try std.testing.expectEqual(core.TextTruncation.line_clamped, cx.textTruncation(whole).?);
}

test "Tooltip: an open hint closes when its hovered trigger is hidden or detached" {
    const a = std.testing.allocator;
    var cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try box(cx, .{ .width = .fixed(400), .height = .fixed(300) }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const tip = try Tooltip(.{ .text = "Hidden with its trigger" }).mount(scope, cx);
    try root.appendChild(a, tip.wrapper);
    const trigger = try box(cx, .{ .width = .fixed(80), .height = .fixed(32) }, .{});
    try tip.trigger.appendChild(a, trigger);
    cx.layout();
    _ = cx.render();
    const rect = trigger.globalRect();
    cx.handleMouseMove(rect.x + 5, rect.y + 5);
    try std.testing.expect(tip.open.?.peek());
    // Hidden under a resting pointer: the hover re-resolves, the hint closes.
    tip.wrapper.setDisplay(.none);
    for (0..3) |_| {
        cx.layout();
        _ = cx.render();
    }
    try std.testing.expect(!tip.open.?.peek());
    tip.wrapper.setDisplay(.flex);
    for (0..3) |_| {
        cx.layout();
        _ = cx.render();
    }
    cx.handleMouseMove(rect.x + 6, rect.y + 6);
    try std.testing.expect(tip.open.?.peek());
    // Detached (kept alive): closes too.
    cx.detachChild(root, tip.wrapper);
    for (0..3) |_| {
        cx.layout();
        _ = cx.render();
    }
    try std.testing.expect(!tip.open.?.peek());
    try root.appendChild(a, tip.wrapper);
}

test "Tooltip: touch motion does not open hover and mouse motion at the same point does" {
    const a = std.testing.allocator;
    var cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try box(cx, .{ .width = .fixed(400), .height = .fixed(300) }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const tip = try Tooltip(.{ .text = "Hover only" }).mount(scope, cx);
    try root.appendChild(a, tip.wrapper);
    try tip.trigger.appendChild(a, try box(cx, .{ .width = .fixed(80), .height = .fixed(32) }, .{}));
    cx.layout();
    _ = cx.render();

    const rect = tip.trigger.globalRect();
    cx.handlePointerMove(rect.x + 1, rect.y + 1, .{}, true);
    try std.testing.expect(!tip.open.?.peek());
    cx.handleMouseMove(rect.x + 1, rect.y + 1);
    try std.testing.expect(tip.open.?.peek());
    cx.handlePointerMove(rect.x + 1, rect.y + 1, .{}, true);
    try std.testing.expect(!tip.open.?.peek());
}

test "Tooltip: long text wraps within the safe viewport and three lines; the cut ends in an ellipsis" {
    const a = std.testing.allocator;
    var cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(180, 300);
    const root = try box(cx, .{ .width = .fixed(180), .height = .fixed(300) }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const tip = try Tooltip(.{
        .text = "A long description with multiple words must wrap within the window. " ++
            "It cannot grow past the safe viewport even when the application is resized. " ++
            "This third sentence makes the text long enough to exceed the visible line count.",
        .open = true,
    }).mount(scope, cx);
    try root.appendChild(a, tip.wrapper);
    try tip.trigger.appendChild(a, try box(cx, .{ .width = .fixed(80), .height = .fixed(32) }, .{}));
    for (0..8) |_| {
        cx.layout();
        _ = cx.render();
    }

    const panel = tip.content.globalRect();
    const trigger = tip.trigger.globalRect();
    const label = tip.content.children.items[0];
    const text = label.getText().?;
    const label_height = label.globalRect().h;
    try std.testing.expectEqual(@as(f32, 1), tip.content.getOpacity());
    try std.testing.expect(panel.w > 80 and panel.w <= 180 - 2 * 8);
    try std.testing.expectApproxEqAbs(trigger.y + trigger.h + 4, panel.y, 0.1);
    try std.testing.expectApproxEqAbs(3 * text.font_size * text.line_height, label_height, 0.1);
    // The text does not fit in three lines: the third ends in an ellipsis instead of stopping
    // mid-sentence without a cue.
    try std.testing.expect(label.layoutTextLayout().?.lines_truncated);
    // Runs are positioned in the label's own space.
    const third_line_top = 2 * text.font_size * text.line_height;
    var ellipsis_on_third = false;
    for (cx.display_list.items.items) |item| switch (item) {
        .text_run => |run| if (std.mem.eql(u8, run.content, "\xe2\x80\xa6") and run.y > third_line_top) {
            ellipsis_on_third = true;
        },
        else => {},
    };
    try std.testing.expect(ellipsis_on_third);
}

test "Tooltip: the label follows the default, explicit and unclamped line limits" {
    const a = std.testing.allocator;
    const label_text = "one\ntwo\nthree\nfour\nfive";
    const cases = [_]struct { limit: ?u16, lines: u32, truncated: bool }{
        .{ .limit = null, .lines = 3, .truncated = true },
        .{ .limit = 4, .lines = 4, .truncated = true },
        .{ .limit = 0, .lines = 5, .truncated = false },
    };
    for (cases) |case| {
        var cx = try Cx.init(a, std.testing.io);
        defer cx.deinit();
        cx.setViewport(240, 320);
        const root = try box(cx, .{ .width = .fixed(240), .height = .fixed(320) }, .{});
        cx.root = root;
        const scope = try Scope.init(a, null, cx.owner);
        defer scope.dispose();
        const tip = try Tooltip(.{ .text = label_text, .open = true, .max_lines = case.limit }).mount(scope, cx);
        try root.appendChild(a, tip.wrapper);
        try tip.trigger.appendChild(a, try box(cx, .{ .width = .fixed(80), .height = .fixed(32) }, .{}));
        for (0..8) |_| {
            cx.layout();
            _ = cx.render();
        }
        const label = tip.content.children.items[0];
        const layout = label.layoutTextLayout().?;
        try std.testing.expectEqual(case.lines, layout.line_count);
        try std.testing.expectEqual(case.truncated, layout.lines_truncated);
        try std.testing.expectEqualStrings(label_text, tip.content.behavior.interaction.a11y.?.label.?);
    }
}

test "Tooltip: optional width bounds the panel and lets the label wrap" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Tooltip(.{ .text = "/a/very/long/path/that/does/not/fit/on/one/line", .width = 120, .wrap = .char, .max_lines = 0 }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    const label = result.content.children.items[0];
    try std.testing.expectEqual(core.TextWrap.char, label.getText().?.wrap);
    try std.testing.expectEqual(@as(u16, 0), label.getText().?.max_lines);
    try std.testing.expectEqual(core.Sizing.fill(), label.style.width);
    // Closed: still collapsed like the default tooltip.
    try std.testing.expectEqual(core.Sizing{ .px = 0 }, result.content.style.width);

    result.wrapper.behavior.events.on_hover.?.invoke();
    try std.testing.expectEqual(core.Sizing{ .px = 120 }, result.content.style.width);

    // Default: the style's word-breaking label, bounded by the default maximum width.
    const plain = try Tooltip(.{ .text = "Copy" }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, plain.wrapper);
    try std.testing.expectEqual(core.TextWrap.word_break, plain.content.children.items[0].getText().?.wrap);
    try std.testing.expectEqual(@as(u16, 3), plain.content.children.items[0].getText().?.max_lines);
    plain.wrapper.behavior.events.on_hover.?.invoke();
    try std.testing.expectEqual(core.Sizing{ .fit = .{ .max = styles.max_width } }, plain.content.style.width);
}

test "Tooltip: large host lists do not reserve closed overlay slots" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{}, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    // More closed tooltips than the overlay stack's capacity (256).
    for (0..300) |_| {
        const tip = try Tooltip(.{ .text = "Host detail" }).mount(scope, ctx);
        try root.appendChild(std.testing.allocator, tip.wrapper);
    }
    try std.testing.expectEqual(@as(usize, 0), ctx.overlay_stack.layer_count);
}

test "Tooltip: first 10 open frames progress from enter state instead of flashing" {
    const render_engine = @import("../../core/render_engine/mod.zig");
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(400, 300);

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const result = try Tooltip(.{
        .text = "Smooth tooltip",
        .position = .bottom,
        // Test only checks enter animation curve; 10-frame window can't hide default 500ms display
        // delay.
        .open_delay_ms = 0,
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);

    const btn = try box(ctx, .{
        .width = .{ .px = 100 },
        .height = .{ .px = 32 },
    }, .{});
    try result.trigger.appendChild(std.testing.allocator, btn);

    ctx.layout();
    _ = ctx.render();

    const tooltip = result.content;
    result.wrapper.behavior.events.on_hover.?.invoke();

    var opacities: [10]f32 = undefined;
    var slide_y: [10]f32 = undefined;
    // Overlay transitions run on the Cx frame clock (wall-clock derived): sample it in fixed
    // 16ms steps, as a host frame would, so the enter animation actually advances.
    ctx.test_frame_step_ms = 16;
    var now_ms: f64 = 0;
    for (0..10) |i| {
        now_ms += 16.0;
        render_engine.current_frame_time_ms = now_ms;
        render_engine.current_frame_dt_ms = 16.0;
        ctx.advanceFrameClock();
        ctx.layout();
        _ = ctx.render();
        opacities[i] = tooltip.getOpacity();
        slide_y[i] = tooltip.style.getExt().motion_offset[1];
        try std.testing.expectEqual(@as(f32, 1), tooltip.style.scale_x());
    }

    var first_visible_idx: ?usize = null;
    for (opacities, 0..) |opacity, i| {
        if (opacity > 0.0011) {
            first_visible_idx = i;
            break;
        }
    }

    try std.testing.expect(tooltip.rectFromWorldOrFallback().w > 0);
    try std.testing.expect(tooltip.rectFromWorldOrFallback().h > 0);
    const idx = first_visible_idx orelse return error.TooltipDidNotAppear;
    try std.testing.expect(opacities[idx] < 0.3);
    // anchored_fade below the trigger rises into place: it starts at most 4px lower
    // (positive y) and settles toward 0 as it fades in.
    try std.testing.expect(slide_y[idx] > 0 and slide_y[idx] <= 4);

    var last_opacity = opacities[idx];
    var last_slide_y = slide_y[idx];
    for (opacities[(idx + 1)..], slide_y[(idx + 1)..]) |opacity, y| {
        try std.testing.expect(opacity + 0.0001 >= last_opacity);
        try std.testing.expect(y <= last_slide_y + 0.0001);
        last_opacity = opacity;
        last_slide_y = y;
    }
    // The clock advanced: the 150ms enter finishes inside the 10 sampled frames.
    try std.testing.expectApproxEqAbs(@as(f32, 1), opacities[9], 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0), slide_y[9], 0.001);
}

// Test collection from styles.zig; this line required (see docs/STYLING.md).
test "Tooltip: dynamic text updates the label and the tooltip a11y name; unmount stops the binding" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const tip = try scope.createText("Copy", .{});
    const result = try Tooltip(.{ .text = tip }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, result.wrapper);
    const label = result.content.children.items[result.content.children.items.len - 1];
    try std.testing.expectEqualStrings("Copy", label.getText().?.content);
    tip.set("Copied!");
    try std.testing.expectEqualStrings("Copied!", label.getText().?.content);
    try std.testing.expectEqual(label.getText().?.content.ptr, result.content.behavior.interaction.a11y.?.label.?.ptr);

    // Change text after unmount tooltip: binding released with label's scope; can't write freed
    // node.
    ctx.detachChild(root, result.wrapper);
    ctx.freeNode(result.wrapper);
    tip.set("after unmount");
}

test "Tooltip: an ancestor bound to a sibling scope may free the wrapper before the tooltip scope disposes" {
    // Storybook ZIndex: a Tooltip in a Modal body is mounted from the story scope, while the
    // modal barrier is bound to the Modal's own (earlier) child scope. Disposing the story scope
    // frees the barrier subtree, wrapper included, before the tooltip scope runs its cleanup.
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 300 } }, .{});
    ctx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    var scope_live = true;
    defer if (scope_live) scope.dispose();

    const holder_scope = try scope.childScope();
    const holder = try box(ctx, .{}, .{});
    try core.bindScopeToNode(holder_scope, holder);
    try root.appendChild(std.testing.allocator, holder);
    const result = try Tooltip(.{ .text = "Inside" }).mount(scope, ctx);
    holder.appendChild(std.testing.allocator, result.wrapper) catch |err| {
        ctx.freeNode(result.wrapper);
        return err;
    };

    // Unbinds the wrapper from the tooltip scope and frees it; the scope stays alive.
    ctx.detachChild(root, holder);
    ctx.freeNode(holder);
    // The tooltip cleanup must not write hover handlers into the freed wrapper (the testing
    // allocator reports a write after free).
    scope_live = false;
    scope.dispose();
}

test "Tooltip: 动态文本的 mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("tooltip(dynamic)", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const tip = try scope.createText("Copy", .{});
            return (try Tooltip(.{ .text = tip }).mount(scope, cx)).wrapper;
        }
    }.m);
}

test {
    _ = @import("styles.zig");
    _ = @import("surface.zig");
}

test "Tooltip: mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("tooltip", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const r = try Tooltip(.{ .text = "Hello tooltip", .position = .top }).mount(scope, cx);
            return r.wrapper;
        }
    }.m);
}

fn detachFrames(cx: *Cx, count: usize) void {
    for (0..count) |_| {
        cx.frame_count += 1;
        cx.frame_time_ms += 34;
        _ = cx.render();
    }
}

/// Where the tooltip is when the menu holding its trigger closes.
const DetachTiming = enum {
    /// Hovered, still inside the open delay (open, nothing drawn yet).
    delayed,
    /// Fading in.
    entering,
    /// Fully shown.
    visible,
    /// Shown, then closed by the pointer leaving before the menu closes.
    closed,
};

fn expectTooltipSurvivesMenuReopen(timing: DetachTiming, switch_theme: bool) !void {
    const a = std.testing.allocator;
    var cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try box(cx, .{ .width = .fixed(400), .height = .fixed(300) }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();
    // A retained menu: closing it detaches its content (and the tooltip trigger in it) from the
    // window; the nodes survive for the next open.
    const menu_open = try Signal(bool).createInScope(scope, false);
    const menu = try popover_mod.Popover(.{ .trigger = .manual, .open = menu_open }).mount(scope, cx);
    try root.appendChild(a, menu.wrapper);
    try menu.trigger.appendChild(a, try box(cx, .{ .width = .fixed(60), .height = .fixed(20) }, .{}));
    const tip = try Tooltip(.{ .text = "Inside menu" }).mount(scope, cx);
    try menu.content.appendChild(a, tip.wrapper);
    try tip.trigger.appendChild(a, try box(cx, .{ .width = .fixed(80), .height = .fixed(24) }, .{}));
    const label = tip.content.children.items[0];

    for (0..3) |round| {
        menu_open.set(true);
        detachFrames(cx, 12);
        tip.wrapper.behavior.events.on_hover.?.invoke();
        if (round == 0) switch (timing) {
            .delayed => {
                detachFrames(cx, 2);
                try std.testing.expect(tip.open.?.peek());
                try std.testing.expectEqual(@as(f32, 0), tip.content.getOpacity());
            },
            .entering => {
                var frames: usize = 0;
                while (tip.content.getOpacity() <= 0.01 and frames < 40) : (frames += 1) detachFrames(cx, 1);
                const layer = cx.overlay_stack.findLayerForNode(tip.content).?;
                try std.testing.expectEqual(overlay_stack_mod.LayerState.entering, layer.state);
                try std.testing.expect(tip.content.getOpacity() > 0.01 and tip.content.getOpacity() < 0.99);
            },
            .visible, .closed => {
                detachFrames(cx, 30);
                try std.testing.expect(tip.content.getOpacity() > 0.98);
                if (timing == .closed) {
                    tip.wrapper.behavior.events.on_leave.?.invoke();
                    detachFrames(cx, 12);
                    try std.testing.expect(!tip.open.?.peek());
                }
            },
        } else {
            detachFrames(cx, 30);
            try std.testing.expect(tip.open.?.peek());
            try std.testing.expect(tip.content.getOpacity() > 0.98);
            try std.testing.expectEqual(styles.tooltipLabelColor(null, cx.tokens), label.getText().?.color);
        }

        menu_open.set(false);
        detachFrames(cx, 12);
        // The trigger left the window: the tooltip closed through its open state and released
        // its layer and portal slot along with the menu's.
        try std.testing.expect(!attachedToRoot(cx, tip.trigger));
        try std.testing.expect(!tip.open.?.peek());
        try std.testing.expect(tip.content.parent == null);
        try std.testing.expectEqual(@as(usize, 0), cx.overlay_stack.layer_count);
        try std.testing.expect(cx.tooltip_state.dismiss == null);
        if (switch_theme) cx.setTheme(if (round % 2 == 0) &theme.light else &theme.dark);
    }
}

fn attachedToRoot(cx: *Cx, node: *Node) bool {
    var top = node;
    while (top.parent) |parent| top = parent;
    return top == cx.root.?;
}

const overlay_stack_mod = @import("../../overlay_stack.zig");

test "Tooltip: in a retained menu shows again after the menu closes mid-delay and reopens" {
    try expectTooltipSurvivesMenuReopen(.delayed, false);
}

test "Tooltip: in a retained menu shows again after the menu closes mid-enter and reopens" {
    try expectTooltipSurvivesMenuReopen(.entering, false);
}

test "Tooltip: in a retained menu shows again after the menu closes while shown and reopens" {
    try expectTooltipSurvivesMenuReopen(.visible, false);
}

test "Tooltip: in a retained menu shows again after it closed and the menu reopens" {
    try expectTooltipSurvivesMenuReopen(.closed, false);
}

test "Tooltip: in a retained menu survives detach and reopen across theme switches" {
    for ([_]DetachTiming{ .delayed, .entering, .visible, .closed }) |timing| {
        try expectTooltipSurvivesMenuReopen(timing, true);
    }
}

test "Tooltip: a root rebound by its component shows after its identity is rebuilt" {
    // A `.yix` component whose root is a Tooltip rebinds the wrapper; a flight then re-registers it.
    const a = std.testing.allocator;
    var cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try box(cx, .{ .width = .fixed(400), .height = .fixed(300) }, .{});
    cx.root = root;
    const scope = try Scope.init(a, null, cx.owner);
    defer scope.dispose();
    const component = try scope.childScope();
    const tip = try Tooltip(.{ .text = "Rebound" }).mount(try component.childScope(), cx);
    try tip.trigger.appendChild(a, try box(cx, .{ .width = .fixed(80), .height = .fixed(24) }, .{}));
    const slot = tip.wrapper.meta.ownership.scope.node_slot.?;
    // Step 1: the component scope rebinds the root.
    try core.bindScopeToNode(component, tip.wrapper);
    try std.testing.expectEqual(tip.wrapper, slot.*.?);
    try root.appendChild(a, tip.wrapper);
    detachFrames(cx, 2);
    for (0..2) |_| {
        // Step 2: the identity is rebuilt.
        cx.detachChildRetained(root, tip.wrapper);
        try root.appendChild(a, tip.wrapper);
        detachFrames(cx, 2);
        tip.wrapper.behavior.events.on_hover.?.invoke();
        detachFrames(cx, 30);
        try std.testing.expect(tip.open.?.peek());
        try std.testing.expect(tip.content.getOpacity() > 0.98);
        try std.testing.expect(cx.tooltip_state.dismiss != null);
        tip.wrapper.behavior.events.on_leave.?.invoke();
        detachFrames(cx, 12);
        try std.testing.expect(!tip.open.?.peek());
    }
}
