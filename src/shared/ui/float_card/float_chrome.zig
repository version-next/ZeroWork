//! The floating card's unified window chrome (PLUGIN_ARCH_PLAN 2.5.7, Pencil「浮动卡片统一窗口外观」):
//! floating is one placement state shared by every card, so the window look of a floating card is
//! provided here, once, and a card type only declares content and a little data:
//!
//! - its title, icon (accent or neutral) and optional subtitle (a signal: the owner text, a count);
//! - which header actions it supports — derived from its `float_card.Descriptor` interactions
//!   (fixed order and icons: `open_as_tab` · `dock_to_split` · `minimize` · `maximize` · `close`) —
//!   and their test ids. The two placement actions are on every card (float-split): a card type that
//!   does not allow the placement gets the native disabled Button with the reason as its Tooltip,
//!   and the owner may disable an allowed one for its current state (`setActionState`);
//! - optional card-specific slot buttons, drawn left of the actions at the same size.
//!
//! The view is `float_chrome.yix` (native Card floating, Grabber, ghost sm icon Buttons + Tooltips).
//! `FloatLayer.attach` wires the chrome's actions to the card (maximize is the layer's own, the rest go
//! to the owner) and keeps the maximize button's icon / label in step with the placement.
//!
//! Narrow headers (bugfix-1, #64): buttons never shrink; the subtitle gives way first — it ellipsizes
//! while the spacer has no slack and hides below `min_subtitle_width`, coming back once it fits again.
const std = @import("std");
const ui = @import("ui");
const model = @import("../../base/float_card.zig");
const template = @import("_float_chrome.yix.zig");

pub const Action = model.HeaderAction;

/// Test ids of the chrome's nodes. Defaults are the generic `float.*` ids; a card passes its own
/// (existing e2e ids never change).
pub const Ids = struct {
    root: []const u8 = "float.card",
    grip: []const u8 = "float.drag",
    /// The native Grabber inside the grip (its held state widens it to 48; swipe-collapse probes).
    grabber: []const u8 = "float.grabber",
    header: []const u8 = "float.header",
    subtitle: []const u8 = "float.subtitle",
    open_as_tab: []const u8 = "float.open_as_tab",
    dock_to_split: []const u8 = "float.dock_to_split",
    minimize: []const u8 = "float.minimize",
    maximize: []const u8 = "float.maximize",
    close: []const u8 = "float.close",
    open_as_tab_tooltip: []const u8 = "float.open_as_tab.tooltip",
    dock_to_split_tooltip: []const u8 = "float.dock_to_split.tooltip",
    minimize_tooltip: []const u8 = "float.minimize.tooltip",
    maximize_tooltip: []const u8 = "float.maximize.tooltip",
    close_tooltip: []const u8 = "float.close.tooltip",
};

/// Accessible names / tooltips that differ from the generic "<verb><title>" (e.g. the AI close ends
/// the conversation).
pub const Labels = struct {
    minimize: ?[]const u8 = null,
    close: ?[]const u8 = null,
    close_tooltip: ?[]const u8 = null,
};

/// A card's own header button (left of the actions, same native ghost sm icon button + Tooltip).
pub const SlotButton = struct {
    test_id: []const u8,
    tooltip_id: []const u8,
    icon: ui.SvgAsset,
    label: []const u8,
};

pub const Spec = struct {
    title: []const u8,
    /// The card type's name in refusal Tooltips ("终端不支持收起") when the title names the instance
    /// (a session card's title is the session's name); null = `title`.
    type_title: ?[]const u8 = null,
    icon: ui.SvgAsset,
    accent_icon: bool = false,
    descriptor: model.Descriptor,
    ids: Ids,
    labels: Labels = .{},
    slot_buttons: []const SlotButton = &.{},
    /// The subtitle source; null = the chrome owns one (`setSubtitle`).
    subtitle: ?*ui.Signal([]const u8) = null,
};

/// Where a header press goes: actions to the floating layer (`FloatLayer.attach` installs it), slot
/// buttons to the card owner.
pub const Handler = struct {
    ctx: ?*anyopaque = null,
    action: ?*const fn (ctx: ?*anyopaque, action: Action) void = null,
    slot: ?*const fn (ctx: ?*anyopaque, index: usize) void = null,
};

pub const max_slot_buttons = 4;
const action_count = model.header_action_count;
pub const ActionEntry = struct { id: []const u8, action: Action };
pub const SlotEntry = struct { test_id: []const u8, tooltip_id: []const u8, icon: ui.SvgAsset, label: []const u8, index: usize };

/// Header height of the chrome above the content (grip 14 + header 30).
pub const grip_height: f32 = 14;
pub const header_height: f32 = 30;
pub const top_height: f32 = grip_height + header_height;
/// Narrowest subtitle worth showing (a few readable characters).
pub const min_subtitle_width: f32 = 48;
pub const subtitle_font_size: f32 = 11;

/// The view-model `float_chrome.yix` reads.
pub const Vm = struct {
    ids: Ids,
    title: []const u8,
    icon: ui.SvgAsset,
    accent_icon: bool,
    actions: model.HeaderActions,
    action_storage: [action_count]ActionEntry = undefined,
    action_entries: []const ActionEntry = &.{},
    slot_storage: [max_slot_buttons]SlotEntry = undefined,
    slot_buttons: []const SlotEntry = &.{},
    labels: [action_count][]const u8 = @splat(""),
    /// Per action: disabled (native Button `disabled`) and the Tooltip shown while disabled.
    disabled: [action_count]*ui.Signal(bool) = undefined,
    refusals: [action_count]*ui.Signal([]const u8) = undefined,
    refusal_buffers: [action_count][2][128]u8 = undefined,
    refusal_slots: [action_count]u1 = @splat(0),
    /// The card type's own refusal (placement not allowed); null = allowed.
    type_refusal: [action_count]?[]const u8 = @splat(null),
    type_refusal_buffers: [action_count][128]u8 = undefined,
    restore_label: []const u8 = "",
    close_tooltip: []const u8 = "",
    maximized: *ui.Signal(bool),
    /// The grip is held (pointer down on it / dragging it; swipe-collapse AveHg): the strip takes
    /// the hover fill and the Grabber its accent, wide state. Written by the floating layer.
    grip_held: *ui.Signal(bool),
    subtitle: *ui.Signal([]const u8),
    subtitle_buffers: [2][256]u8 = undefined,
    subtitle_slot: u1 = 0,
    owned_subtitle: bool = false,
    handler: Handler = .{},
    slot_handler: Handler = .{},
    /// Wrappers of the rendered buttons (popover anchors), by slot index / action.
    slot_nodes: [max_slot_buttons]?*ui.Node = @splat(null),
    action_nodes: [action_count]?*ui.Node = @splat(null),
    /// Accessible names of the slot buttons (a card may show a live count, e.g. "子智能体，2 个运行中").
    slot_labels: [max_slot_buttons]*ui.Signal([]const u8) = undefined,
    slot_label_buffers: [max_slot_buttons][2][96]u8 = undefined,
    slot_label_slots: [max_slot_buttons]u1 = @splat(0),

    pub fn slotLabel(self: *const Vm, index: usize) []const u8 {
        return self.slot_labels[index].get();
    }

    pub fn subtitleText(self: *const Vm) []const u8 {
        return self.subtitle.get();
    }
    pub fn isMaximized(self: *const Vm) bool {
        return self.maximized.get();
    }
    pub fn gripHeld(self: *const Vm) bool {
        return self.grip_held.get();
    }
    pub fn actionId(self: *const Vm, action: Action) []const u8 {
        return switch (action) {
            .open_as_tab => self.ids.open_as_tab,
            .dock_to_split => self.ids.dock_to_split,
            .minimize => self.ids.minimize,
            .maximize => self.ids.maximize,
            .close => self.ids.close,
        };
    }
    pub fn tooltipId(self: *const Vm, action: Action) []const u8 {
        return switch (action) {
            .open_as_tab => self.ids.open_as_tab_tooltip,
            .dock_to_split => self.ids.dock_to_split_tooltip,
            .minimize => self.ids.minimize_tooltip,
            .maximize => self.ids.maximize_tooltip,
            .close => self.ids.close_tooltip,
        };
    }
    /// One icon per action for every card (maximize turns into restore while maximized).
    pub fn actionIcon(self: *const Vm, action: Action) ui.SvgAsset {
        return switch (action) {
            .open_as_tab => ui.icons.app_window,
            .dock_to_split => ui.icons.panel_right,
            .minimize => ui.icons.minus,
            .maximize => if (self.maximized.get()) ui.icons.minimize_2 else ui.icons.maximize_2,
            .close => ui.icons.x,
        };
    }
    pub fn actionLabel(self: *const Vm, action: Action) []const u8 {
        if (action == .maximize and self.maximized.get()) return self.restore_label;
        return self.labels[@intFromEnum(action)];
    }
    pub fn actionTooltip(self: *const Vm, action: Action) []const u8 {
        if (self.disabled[@intFromEnum(action)].get()) return self.refusals[@intFromEnum(action)].get();
        if (action == .close and self.close_tooltip.len != 0) return self.close_tooltip;
        return self.actionLabel(action);
    }
    pub fn actionDisabled(self: *const Vm, action: Action) bool {
        return self.disabled[@intFromEnum(action)].get();
    }
    pub fn act(self: *Vm, action: Action) void {
        if (self.disabled[@intFromEnum(action)].peek()) return;
        const callback = self.handler.action orelse return;
        callback(self.handler.ctx, action);
    }
    pub fn press(self: *Vm, index: usize) void {
        const callback = self.slot_handler.slot orelse return;
        callback(self.slot_handler.ctx, index);
    }
};

/// Nodes the host reads from the rendered chrome.
pub const Slots = struct {
    root: ?*ui.Node = null,
    grip: ?*ui.Node = null,
    header: ?*ui.Node = null,
    title_text: ?*ui.Node = null,
    icon: ?*ui.Node = null,
    subtitle: ?*ui.Node = null,
    subtitle_text: ?*ui.Node = null,
    spacer: ?*ui.Node = null,
    body: ?*ui.Node = null,
};

pub const Chrome = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    vm: Vm,
    slots: Slots = .{},
    /// Header width when the spacer stepped aside for the title (it returns once the header is a gap wider).
    spacer_hidden_at: f32 = 0,
    /// The chrome root (the layer's frame; carries the card's root test id).
    root: *ui.Node = undefined,
    /// `float.drag`: the 14 pt strip with the Grabber.
    grip: *ui.Node = undefined,
    header: *ui.Node = undefined,
    /// The card's content goes in here.
    body: *ui.Node = undefined,
    owned_labels: [action_count][]u8 = undefined,
    owned_count: usize = 0,

    /// Render the chrome for `spec` (not attached anywhere: the floating layer adopts `root`).
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, spec: Spec) !*Chrome {
        if (spec.slot_buttons.len > max_slot_buttons) return error.TooManySlotButtons;
        const subtitle = spec.subtitle orelse try scope.createSignal([]const u8, "");
        const self = try scope.createState(Chrome, .{ .cx = cx, .scope = scope, .vm = .{
            .ids = spec.ids,
            .title = spec.title,
            .icon = spec.icon,
            .accent_icon = spec.accent_icon,
            .actions = model.headerActions(spec.descriptor),
            .maximized = try scope.createSignal(bool, false),
            .grip_held = try scope.createSignal(bool, false),
            .subtitle = subtitle,
            .owned_subtitle = spec.subtitle == null,
        } });
        for (spec.slot_buttons, 0..) |button, index| {
            self.vm.slot_storage[index] = .{ .test_id = button.test_id, .tooltip_id = button.tooltip_id, .icon = button.icon, .label = button.label, .index = index };
            self.vm.slot_labels[index] = try scope.createSignal([]const u8, button.label);
        }
        self.vm.slot_buttons = self.vm.slot_storage[0..spec.slot_buttons.len];
        for (self.vm.actions.slice(), 0..) |action, index| self.vm.action_storage[index] = .{ .id = self.vm.actionId(action), .action = action };
        self.vm.action_entries = self.vm.action_storage[0..self.vm.actions.len];
        for (std.enums.values(Action)) |action| {
            const index = @intFromEnum(action);
            if (!model.headerActionEnabled(spec.descriptor, action)) self.vm.type_refusal[index] = model.refusalText(&self.vm.type_refusal_buffers[index], action, spec.type_title orelse spec.title);
            self.vm.disabled[index] = try scope.createSignal(bool, self.vm.type_refusal[index] != null);
            self.vm.refusals[index] = try scope.createSignal([]const u8, self.vm.type_refusal[index] orelse "");
        }
        try scope.onCleanup(Chrome, self, freeLabels);
        self.vm.labels[@intFromEnum(Action.open_as_tab)] = "作为标签页打开";
        self.vm.labels[@intFromEnum(Action.dock_to_split)] = "放入分屏";
        self.vm.labels[@intFromEnum(Action.minimize)] = spec.labels.minimize orelse try self.label("收起", spec.title);
        self.vm.labels[@intFromEnum(Action.maximize)] = try self.label("放大", spec.title);
        self.vm.labels[@intFromEnum(Action.close)] = spec.labels.close orelse try self.label("关闭", spec.title);
        self.vm.restore_label = try self.label("还原", spec.title);
        self.vm.close_tooltip = spec.labels.close_tooltip orelse "";
        self.root = try ui.view.render(scope, cx, template.FloatChrome(.{ .vm = &self.vm, .slots = &self.slots }));
        self.grip = self.slots.grip orelse return error.FloatChromeIncomplete;
        self.header = self.slots.header orelse return error.FloatChromeIncomplete;
        self.body = self.slots.body orelse return error.FloatChromeIncomplete;
        try cx.addAfterLayoutHook(self, fitHook);
        try scope.onCleanup(Chrome, self, release);
        return self;
    }

    /// "<verb><title>", with a space before a Latin title ("放大 AI 助手", "放大会话记录").
    fn label(self: *Chrome, verb: []const u8, title: []const u8) ![]const u8 {
        const space = title.len != 0 and title[0] < 0x80;
        const text = try std.fmt.allocPrint(self.scope.allocator, "{s}{s}{s}", .{ verb, if (space) " " else "", title });
        self.owned_labels[self.owned_count] = text;
        self.owned_count += 1;
        return text;
    }

    fn freeLabels(self: *Chrome) void {
        for (self.owned_labels[0..self.owned_count]) |text| self.scope.allocator.free(text);
        self.owned_count = 0;
    }

    fn release(self: *Chrome) void {
        self.cx.removeAfterLayoutHook(self);
    }

    /// The card's slot buttons (by index) go to `handler.slot`.
    pub fn setSlotHandler(self: *Chrome, handler: Handler) void {
        self.vm.slot_handler = handler;
    }

    /// Header actions go to `handler.action` (the floating layer installs its card here).
    pub fn setActionHandler(self: *Chrome, handler: Handler) void {
        self.vm.handler = handler;
    }

    /// The owner's state for a placement action: null = available (when the card type allows it),
    /// otherwise disabled with `reason` as its Tooltip (copied). The card type's own refusal wins.
    pub fn setActionState(self: *Chrome, action: Action, reason: ?[]const u8) void {
        const index = @intFromEnum(action);
        const text = self.vm.type_refusal[index] orelse reason orelse "";
        const disabled = self.vm.type_refusal[index] != null or reason != null;
        if (!std.mem.eql(u8, self.vm.refusals[index].peek(), text)) {
            self.vm.refusal_slots[index] +%= 1;
            const buffer = &self.vm.refusal_buffers[index][self.vm.refusal_slots[index]];
            const n = utf8Prefix(text, buffer.len);
            @memcpy(buffer[0..n], text[0..n]);
            self.vm.refusals[index].set(buffer[0..n]);
        }
        if (self.vm.disabled[index].peek() != disabled) self.vm.disabled[index].set(disabled);
    }

    /// Whether `action` can be pressed now (shown and not disabled).
    pub fn actionEnabled(self: *const Chrome, action: Action) bool {
        for (self.vm.actions.slice()) |shown| if (shown == action) return !self.vm.disabled[@intFromEnum(action)].peek();
        return false;
    }

    pub fn setMaximized(self: *Chrome, maximized: bool) void {
        if (self.vm.maximized.peek() != maximized) self.vm.maximized.set(maximized);
    }

    /// Held feedback of the `float.drag` grip (the floating layer sets it on press, clears on release).
    pub fn setGripHeld(self: *Chrome, held: bool) void {
        if (self.vm.grip_held.peek() != held) self.vm.grip_held.set(held);
    }

    /// Set the chrome-owned subtitle (copied; the caller's buffer may be reused).
    pub fn setSubtitle(self: *Chrome, text: []const u8) void {
        if (std.mem.eql(u8, self.vm.subtitle.peek(), text)) return;
        if (!self.vm.owned_subtitle) return;
        self.vm.subtitle_slot +%= 1;
        const buffer = &self.vm.subtitle_buffers[self.vm.subtitle_slot];
        const n = utf8Prefix(text, buffer.len);
        @memcpy(buffer[0..n], text[0..n]);
        self.vm.subtitle.set(buffer[0..n]);
    }

    /// The wrapper of slot button `index` (anchor of the card's popovers, same rect as the button).
    pub fn slotNode(self: *Chrome, index: usize) ?*ui.Node {
        return if (index < max_slot_buttons) self.vm.slot_nodes[index] else null;
    }

    /// The wrapper of a declared action's button (e.g. the close confirmation's anchor).
    pub fn actionNode(self: *Chrome, action: Action) ?*ui.Node {
        return self.vm.action_nodes[@intFromEnum(action)];
    }

    /// Live accessible name of slot button `index` (copied).
    pub fn setSlotLabel(self: *Chrome, index: usize, text: []const u8) void {
        if (index >= self.vm.slot_buttons.len) return;
        if (std.mem.eql(u8, self.vm.slot_labels[index].peek(), text)) return;
        self.vm.slot_label_slots[index] +%= 1;
        const buffer = &self.vm.slot_label_buffers[index][self.vm.slot_label_slots[index]];
        const n = utf8Prefix(text, buffer.len);
        @memcpy(buffer[0..n], text[0..n]);
        self.vm.slot_labels[index].set(buffer[0..n]);
    }

    fn fitHook(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *Chrome = @ptrCast(@alignCast(raw));
        if (self.header.globalRect().w <= 0) return .done;
        const subtitle = self.slots.subtitle orelse return .done;
        const spacer = self.slots.spacer orelse return .done;
        const text = self.slots.subtitle_text orelse return .done;
        // While the spacer stands aside (narrowest width) there is no slack: the subtitle stays hidden.
        if (spacer.style.display != .none) if (fitTrailing(self.cx, self.header, spacer, subtitle, text, 0, min_subtitle_width)) return .needs_layout;
        // The title is the last to give way (ai-redesign-c: 320 / 420 floating widths showed “AI…” while the
        // subtitle still had room to yield): while the title is squeezed below its natural width, the
        // subtitle hides first.
        if (self.slots.title_text) |title| {
            if (subtitle.style.display != .none and titleSqueezed(self.cx, title)) {
                subtitle.setDisplay(.none);
                return .needs_layout;
            }
            // At the narrowest width (320 with eight buttons) even the empty spacer's gap squeezes the
            // title: the spacer leaves (the buttons follow the title), and comes back once the header
            // has that gap to spare again.
            if (spacer.style.display != .none and subtitle.style.display == .none and spacer.globalRect().w < 0.5 and (titleSqueezed(self.cx, title) or self.headerOverflows())) {
                spacer.setDisplay(.none);
                self.spacer_hidden_at = self.header.globalRect().w;
                return .needs_layout;
            }
            // Still squeezed (eight native 25.6 buttons at 320): the decorative card icon steps aside too.
            if (self.slots.icon) |icon| if (spacer.style.display == .none and icon.style.display != .none and (titleSqueezed(self.cx, title) or self.headerOverflows())) {
                icon.setDisplay(.none);
                return .needs_layout;
            };
            if (spacer.style.display == .none and self.header.globalRect().w > self.spacer_hidden_at + self.header.style.gap + 0.5) {
                spacer.setDisplay(.flex);
                if (self.slots.icon) |icon| icon.setDisplay(.flex);
                return .needs_layout;
            }
        }
        return .done;
    }

    /// The header's buttons reach past its right padding (they never shrink; the title would rather
    /// overflow them than give way).
    fn headerOverflows(self: *Chrome) bool {
        const header = self.header.globalRect();
        const limit = header.x + header.w - self.header.style.padding.right + 0.5;
        var right: f32 = 0;
        for (self.vm.slot_nodes) |slot| if (slot) |node| {
            const r = node.globalRect();
            right = @max(right, r.x + r.w);
        };
        for (self.vm.action_nodes) |action| if (action) |node| {
            const r = node.globalRect();
            right = @max(right, r.x + r.w);
        };
        return right > limit;
    }

    /// The title text is narrower than its one-line natural width (it shows an ellipsis).
    pub fn titleSqueezed(cx: *ui.Cx, title: *ui.Node) bool {
        return titleSqueezedBy(cx, title, 0);
    }
    fn titleSqueezedBy(cx: *ui.Cx, title: *ui.Node, extra: f32) bool {
        const value = title.getText() orelse return false;
        if (value.content.len == 0) return false;
        const natural = cx.text.measureTextWidth(value.content, value.font_size, value.font_weight, value.use_italic_font);
        return title.globalRect().w - extra + 0.5 < natural;
    }

};

/// Shared narrow-header rule (bugfix-1): `item` (holding the text `label`, `padding` wide besides the
/// text) gives way first. While the spacer has no slack it shrinks (its label ellipsizes) down to
/// `min_width` and hides below that; it comes back once the spacer's slack holds it again. Returns
/// whether `item`'s display changed (the caller relayouts).
pub fn fitTrailing(cx: *ui.Cx, bar: *ui.Node, spacer: *ui.Node, item: *ui.Node, label: *ui.Node, padding: f32, min_width: f32) bool {
    const slack = spacer.globalRect().w;
    if (item.style.display != .none) {
        const text = if (label.getText()) |value| value.content else "";
        if (text.len == 0) return false;
        if (slack > 0.5 or item.globalRect().w >= min_width) return false;
        item.setDisplay(.none);
        return true;
    }
    const text = if (label.getText()) |value| value.content else "";
    if (text.len == 0) {
        item.setDisplay(.flex);
        return true;
    }
    const natural = cx.text.measureTextWidth(text, subtitle_font_size, 400, false) + padding;
    if (slack < @min(natural, min_width) + bar.style.gap) return false;
    item.setDisplay(.flex);
    return true;
}

/// The longest prefix of `text` within `limit` bytes that does not cut a UTF-8 sequence.
fn utf8Prefix(text: []const u8, limit: usize) usize {
    var n = @min(text.len, limit);
    while (n > 0 and n < text.len and (text[n] & 0xC0) == 0x80) n -= 1;
    return n;
}

/// Where a card's popover view writes the live accessible name of its slot button.
pub const SlotLabel = struct {
    chrome: *Chrome,
    index: usize,
    pub fn set(self: SlotLabel, text: []const u8) void {
        self.chrome.setSlotLabel(self.index, text);
    }
};
