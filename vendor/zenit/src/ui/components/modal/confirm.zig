//! ConfirmDialog: the Modal preset for "confirm before an irreversible action".
//!
//!   Modal (native title bar: title + ×; mask; focus trap; Escape)
//!   +-- body
//!       +-- content (column): message text, then the caller's children (the slot)
//!       +-- actions (row, end-aligned): [cancel (secondary)] [confirm (danger | primary)]
//!
//! - `title`, `message`, `confirm_label`, `cancel_label`, `confirm_disabled`, `confirm_loading`
//!   are sources (the open dialog follows them); an empty message hides the text.
//! - Steps inside the dialog (progress, failure + retry): `cancel_disabled` (Escape / × / mask
//!   ignored too), `confirm_shown`, and `refocus` (each change puts focus back on the safe button).
//! - `tone`: `.danger` (default; the confirm button is `variant = .danger`) or `.primary`.
//! - Focus: the dialog opens on the cancel button (the safe choice, `initial_focus = .cancel`) —
//!   not on the title bar's ×, the Modal's first control. `.confirm` puts it on the confirm button.
//! - Cancel = the cancel button, the title bar's ×, Escape and (with `close_on_overlay`, the
//!   default) a mask click: the dialog proposes `open = false`, then `on_cancel` runs.
//! - Confirm: with `close_on_confirm` (default) the dialog proposes `open = false`, then
//!   `on_confirm` runs. A flow that stays open on confirm (progress, failure + retry) sets it false
//!   and closes the dialog itself.
//! - `test_id` names the dialog panel (Yix `testId`); `test_ids` names the title text, the
//!   message, the content slot, the actions row and both buttons.
//!
//! Zig: `W.ConfirmDialog(.{ .open = open, .title = "Delete host?", .message = "…",
//! .confirm_label = "Delete host", .on_confirm = cx.on(S, s, S.remove) }).mount(scope, cx)`.
//! Yix: `<W.ConfirmDialog open={…} title="…" message={…} confirmLabel="…" onConfirm={…}>extra
//! content</W.ConfirmDialog>`.
const std = @import("std");
const core = @import("../../core.zig");
const v = @import("../../view.zig");
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const Source = reactive.Source;
const Model = reactive.Model;
const Cx = core.Cx;
const Node = core.Node;
const Handler = core.Handler;
const modal_mod = @import("mod.zig");
const button = @import("../button/mod.zig");

pub const ConfirmTone = enum { danger, primary };
pub const ConfirmFocus = enum { cancel, confirm };

pub const ConfirmTestIds = struct {
    /// The dialog panel (same as `test_id`; for a Yix element with children, where `testId` would be
    /// an attribute on a component without a root).
    dialog: ?[]const u8 = null,
    /// The title bar's text.
    title: ?[]const u8 = null,
    message: ?[]const u8 = null,
    content: ?[]const u8 = null,
    actions: ?[]const u8 = null,
    cancel: ?[]const u8 = null,
    confirm: ?[]const u8 = null,
    /// The title bar's close button (same as `parts={.{ .close_button = … }}`).
    close: ?[]const u8 = null,
};

pub const ConfirmDialogProps = struct {
    open: Model(bool) = .{ .local = false },
    title: Source([]const u8) = .{ .value = "" },
    message: Source([]const u8) = .{ .value = "" },
    confirm_label: Source([]const u8) = .{ .value = "Confirm" },
    cancel_label: Source([]const u8) = .{ .value = "Cancel" },
    /// Accessible name of the title bar's close button (Modal `close_label`). A source is followed.
    close_label: Source([]const u8) = .{ .value = "Close" },
    /// The title bar shows its close button (Modal `closable`). A source is followed.
    closable: Source(bool) = .{ .value = true },
    /// Read at mount.
    tone: ConfirmTone = .danger,
    confirm_disabled: Source(bool) = .{ .value = false },
    confirm_loading: Source(bool) = .{ .value = false },
    /// A step inside the dialog that must not be interrupted (an erase in progress) disables
    /// cancel; Escape, × and a mask click are ignored while it is.
    cancel_disabled: Source(bool) = .{ .value = false },
    /// The confirm button is shown (a failure that cannot be retried hides it).
    confirm_shown: Source(bool) = .{ .value = true },
    /// Each change while the dialog is open puts focus back on the `initial_focus` button (the
    /// dialog moved to another step, e.g. a failure after a disabled-cancel progress step).
    refocus: Source(u64) = .{ .value = 0 },
    width: Source(f32) = .{ .value = 420 },
    max_height: Source(f32) = .{ .value = 600 },
    /// The window area the dialog belongs to (Modal `within`). A source is followed.
    within: Source(?@import("../../overlay_stack.zig").Anchor) = .{ .value = null },
    /// Room kept from the `within` area's edges (Modal `within_padding`). A source is followed.
    within_padding: Source(f32) = .{ .value = 8 },
    /// Mask click = cancel. Read at mount.
    close_on_overlay: bool = true,
    /// Confirm proposes `open = false` before `on_confirm`. Read at mount.
    close_on_confirm: bool = true,
    /// Where focus lands when the dialog opens. Read at mount.
    initial_focus: ConfirmFocus = .cancel,
    animate_initial_open: bool = false,
    on_confirm: ?Handler(void) = null,
    on_cancel: ?Handler(void) = null,
    /// Dialog panel test id (Yix `testId`). Read at mount.
    test_id: ?[]const u8 = null,
    /// Part test ids. Read at mount.
    test_ids: ConfirmTestIds = .{},
};

pub fn ConfirmDialog(props: anytype) ConfirmDialogBuilder {
    return .{ .props = reactive.props.coerce(ConfirmDialogProps, props) };
}

pub const ConfirmDialogResult = struct {
    modal: modal_mod.ModalResult,
    /// The title bar's text node (null when the title is statically empty: no title bar).
    title: ?*Node,
    /// The title bar's close button (Modal `close_button`; null without a title bar).
    close_button: ?*Node,
    /// Content column: the message, then the caller's children.
    content: *Node,
    message: *Node,
    actions: *Node,
    cancel: *Node,
    confirm: *Node,
    /// The open signal (null when `open` is a split / controlled source).
    open: ?*reactive.Signal(bool),

    pub fn viewParts(self: ConfirmDialogResult) core.ViewParts {
        return .{ .root = if (self.modal.portaled) null else self.modal.overlay, .slot = self.content };
    }
};

const Runtime = struct {
    open: reactive.Bound(bool),
    cancel_disabled: Source(bool),
    close_on_confirm: bool,
    on_confirm: ?Handler(void),
    on_cancel: ?Handler(void),

    fn cancel(self: *Runtime) void {
        if (!self.open.read.peek() or self.cancel_disabled.peek()) return;
        self.open.propose(false, null);
        if (self.on_cancel) |h| h.invoke();
    }

    fn confirm(self: *Runtime) void {
        if (!self.open.read.peek()) return;
        if (self.close_on_confirm) self.open.propose(false, null);
        if (self.on_confirm) |h| h.invoke();
    }

    /// The Modal's own dismissals (×, Escape, mask click) only propose; here they are cancel.
    fn modalOpenChanged(self: *Runtime, open: bool) void {
        if (!open) self.cancel();
    }
};

/// Autofocus registration of the safe button, dropped with the dialog's scope.
const FocusTarget = struct {
    cx: *Cx,
    token: u32,
    fn destroy(ptr: *anyopaque, allocator: std.mem.Allocator) void {
        const self: *FocusTarget = @ptrCast(@alignCast(ptr));
        self.cx.focus_targets.unregister(self.token);
        allocator.destroy(self);
    }
};

fn messageStyle(t: *const core.ThemeTokens) core.TextStyle {
    return .{ .color = t.tokens.color.fg_secondary, .font_size = t.tokens.font_size.md, .line_height = 1.45, .wrap = .word_break };
}

fn contentStyle(t: *const core.ThemeTokens) core.BoxStyle {
    return .{ .direction = .column, .width = .{ .grow = .{} }, .gap = t.tokens.space.space300 };
}

fn actionsStyle(t: *const core.ThemeTokens) core.BoxStyle {
    return .{ .direction = .row, .width = .{ .grow = .{} }, .justify = .end, .align_items = .center, .gap = t.tokens.space.space200 };
}

pub const ConfirmDialogBuilder = struct {
    props: ConfirmDialogProps,

    pub fn mount(self: ConfirmDialogBuilder, scope: *Scope, cx: *Cx) !ConfirmDialogResult {
        const p = self.props;
        const my_scope = try scope.childScope();
        errdefer my_scope.dispose();
        const open = try reactive.resolveModel(bool, my_scope, p.open);
        const rt = try my_scope.createState(Runtime, .{ .open = open, .cancel_disabled = p.cancel_disabled, .close_on_confirm = p.close_on_confirm, .on_confirm = p.on_confirm, .on_cancel = p.on_cancel });

        const modal = try modal_mod.Modal(.{
            .open = Model(bool){ .controlled = open.read },
            .title = p.title,
            .width = p.width,
            .max_height = p.max_height,
            .within = p.within,
            .within_padding = p.within_padding,
            .close_on_overlay = p.close_on_overlay,
            .close_label = p.close_label,
            .closable = p.closable,
            .animate_initial_open = p.animate_initial_open,
            .on_open_change = cx.on(Runtime, rt, Runtime.modalOpenChanged),
        }).mount(my_scope, cx);
        modal.dialog.meta.ownership.meta.component_name = "ConfirmDialog";
        if (p.test_id) |id| modal.dialog.meta.ownership.meta.test_id = id;

        const content = try v.render(my_scope, cx, v.col(.{ .style = contentStyle }, .{}));
        _ = try core.adoptChild(cx, cx.allocator, modal.body, content);
        const message = try v.render(my_scope, cx, v.text(.{ .style = messageStyle }, p.message));
        message.setStyleInline(cx.allocator, .{ .width = .{ .grow = .{} }, .min_width = 0, .flex_shrink = 0 });
        _ = try core.adoptChild(cx, cx.allocator, content, message);
        try my_scope.createEffect(.{ .node = message, .text = p.message }, struct {
            fn follow(c: anytype) void {
                c.node.setDisplay(if (c.text.get().len == 0) .none else .flex);
            }
        }.follow);

        const actions = try v.render(my_scope, cx, v.row(.{ .style = actionsStyle }, .{}));
        _ = try core.adoptChild(cx, cx.allocator, modal.body, actions);
        const cancel = try button.Button(.{ .label = p.cancel_label, .variant = .secondary, .disabled = p.cancel_disabled, .on_click = cx.on(Runtime, rt, Runtime.cancel) }).mount(my_scope, cx);
        _ = try core.adoptChild(cx, cx.allocator, actions, cancel);
        const confirm = try button.Button(.{
            .label = p.confirm_label,
            .variant = @as(button.ButtonVariant, switch (p.tone) {
                .danger => .danger,
                .primary => .primary,
            }),
            .disabled = p.confirm_disabled,
            .loading = p.confirm_loading,
            .on_click = cx.on(Runtime, rt, Runtime.confirm),
        }).mount(my_scope, cx);
        _ = try core.adoptChild(cx, cx.allocator, actions, confirm);
        if (!p.confirm_shown.isStatic() or !p.confirm_shown.peek()) try my_scope.createEffect(.{ .node = confirm, .shown = p.confirm_shown }, struct {
            fn follow(c: anytype) void {
                c.node.setDisplay(if (c.shown.get()) .flex else .none);
            }
        }.follow);

        const title = modal.title;
        const ids = p.test_ids;
        if (ids.dialog) |id| modal.dialog.meta.ownership.meta.test_id = id;
        if (ids.title) |id| if (title) |node| {
            node.meta.ownership.meta.test_id = id;
        };
        if (ids.message) |id| message.meta.ownership.meta.test_id = id;
        if (ids.content) |id| content.meta.ownership.meta.test_id = id;
        if (ids.actions) |id| actions.meta.ownership.meta.test_id = id;
        if (ids.cancel) |id| cancel.meta.ownership.meta.test_id = id;
        if (ids.confirm) |id| confirm.meta.ownership.meta.test_id = id;
        if (ids.close) |id| if (modal.close_button) |node| {
            node.meta.ownership.meta.test_id = id;
        };

        // The safe choice takes focus on every open (focus_targets' dialog autoFocus: a target in
        // a closed dialog waits for it), instead of the title bar's ×.
        const target = try my_scope.allocator.create(FocusTarget);
        errdefer my_scope.allocator.destroy(target);
        const focus_node = switch (p.initial_focus) {
            .cancel => cancel,
            .confirm => confirm,
        };
        target.* = .{ .cx = cx, .token = try cx.focus_targets.register(cx, .target, focus_node, "zenit.confirm.initial", true) };
        errdefer cx.focus_targets.unregister(target.token);
        try my_scope.adoptResource(@ptrCast(target), FocusTarget.destroy);
        if (!p.refocus.isStatic()) {
            const Refocus = struct {
                cx: *Cx,
                node: *Node,
                open: Source(bool),
                revision: Source(u64),
                seen: u64,
                fn follow(c: *@This()) void {
                    const value = c.revision.get();
                    if (value == c.seen) return;
                    c.seen = value;
                    if (c.open.peek()) c.cx.setFocus(c.node);
                }
            };
            const refocus = try my_scope.createState(Refocus, .{ .cx = cx, .node = focus_node, .open = open.read, .revision = p.refocus, .seen = p.refocus.peek() });
            try my_scope.createEffect(refocus, Refocus.follow);
        }

        return .{ .modal = modal, .title = title, .close_button = modal.close_button, .content = content, .message = message, .actions = actions, .cancel = cancel, .confirm = confirm, .open = open.signal };
    }
};

// ===== Tests =====

const testing = std.testing;
const theme = core.theme;

const Probe = struct {
    confirmed: usize = 0,
    cancelled: usize = 0,
    fn onConfirm(self: *Probe) void {
        self.confirmed += 1;
    }
    fn onCancel(self: *Probe) void {
        self.cancelled += 1;
    }
};

fn rig() !struct { cx: *Cx, scope: *Scope, root: *Node } {
    const cx = try Cx.init(testing.allocator, testing.io);
    cx.setTheme(&theme.light);
    cx.setViewport(900, 700);
    const root = try core.box(cx, .{ .width = .{ .px = 900 }, .height = .{ .px = 700 } }, .{});
    cx.root = root;
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    return .{ .cx = cx, .scope = scope, .root = root };
}

fn textOf(node: *Node) []const u8 {
    if (node.getText()) |t| return t.content;
    for (node.children.items) |c| {
        const s = textOf(c);
        if (s.len != 0) return s;
    }
    return "";
}

test "ConfirmDialog: title, message, content slot and the two actions; danger by default" {
    const r = try rig();
    defer r.cx.deinit();
    defer r.scope.dispose();
    var probe: Probe = .{};
    const open = try r.scope.createSignal(bool, false);
    const d = try ConfirmDialog(.{
        .open = open,
        .title = "Delete host?",
        .message = "Saved credentials are removed too.",
        .confirm_label = "Delete host",
        .on_confirm = r.cx.on(Probe, &probe, Probe.onConfirm),
        .test_id = "confirm.dialog",
        .test_ids = .{ .title = "confirm.title", .message = "confirm.message", .cancel = "confirm.cancel", .confirm = "confirm.accept" },
    }).mount(r.scope, r.cx);
    if (!d.modal.portaled) try r.root.appendChild(testing.allocator, d.modal.overlay);
    try testing.expectEqualStrings("confirm.dialog", d.modal.dialog.meta.ownership.meta.test_id.?);
    try testing.expectEqualStrings("Delete host?", d.title.?.getText().?.content);
    try testing.expectEqualStrings("confirm.title", d.title.?.meta.ownership.meta.test_id.?);
    try testing.expectEqualStrings("ConfirmDialog", d.modal.dialog.meta.ownership.meta.component_name.?);
    try testing.expectEqualStrings("Saved credentials are removed too.", d.message.getText().?.content);
    try testing.expectEqualStrings("confirm.message", d.message.meta.ownership.meta.test_id.?);
    try testing.expectEqual(d.message, d.content.children.items[0]);
    try testing.expectEqual(@as(usize, 2), d.actions.children.items.len);
    try testing.expectEqual(d.cancel, d.actions.children.items[0]);
    try testing.expectEqual(d.confirm, d.actions.children.items[1]);
    try testing.expectEqualStrings("Cancel", textOf(d.cancel));
    try testing.expectEqualStrings("Delete host", textOf(d.confirm));
    try testing.expectEqualStrings("confirm.accept", d.confirm.meta.ownership.meta.test_id.?);
    // Danger tone: the confirm button is the native danger variant (its fill is the danger token).
    const danger = try button.Button(.{ .label = "x", .variant = .danger }).mount(r.scope, r.cx);
    defer r.cx.freeNode(danger);
    try testing.expectEqual(danger.getBackground(), d.confirm.getBackground());
    try testing.expectEqual(@as(?*reactive.Signal(bool), open), d.open);
}

test "ConfirmDialog: cancel, Escape and the mask cancel; confirm closes then reports" {
    const r = try rig();
    defer r.cx.deinit();
    defer r.scope.dispose();
    var probe: Probe = .{};
    const open = try r.scope.createSignal(bool, true);
    const d = try ConfirmDialog(.{
        .open = open,
        .title = "End session?",
        .confirm_label = "End session",
        .on_confirm = r.cx.on(Probe, &probe, Probe.onConfirm),
        .on_cancel = r.cx.on(Probe, &probe, Probe.onCancel),
    }).mount(r.scope, r.cx);
    if (!d.modal.portaled) try r.root.appendChild(testing.allocator, d.modal.overlay);
    // An empty message is hidden.
    try testing.expectEqual(core.Display.none, d.message.style.display);
    d.cancel.behavior.events.on_click.?.invoke();
    try testing.expect(!open.peek());
    try testing.expectEqual(@as(usize, 1), probe.cancelled);
    // A closed dialog ignores a late click.
    d.cancel.behavior.events.on_click.?.invoke();
    try testing.expectEqual(@as(usize, 1), probe.cancelled);
    open.set(true);
    // The Modal's own dismissal (Escape here; × and mask click alike) proposes closing: that is cancel.
    r.cx.handleKeyDown(.escape, .{});
    try testing.expect(!open.peek());
    try testing.expectEqual(@as(usize, 2), probe.cancelled);
    open.set(true);
    d.confirm.behavior.events.on_click.?.invoke();
    try testing.expect(!open.peek());
    try testing.expectEqual(@as(usize, 1), probe.confirmed);
    try testing.expectEqual(@as(usize, 2), probe.cancelled);
}

test "ConfirmDialog: close_on_confirm = false stays open; a split open lets the parent refuse" {
    const r = try rig();
    defer r.cx.deinit();
    defer r.scope.dispose();
    var probe: Probe = .{};
    const open = try r.scope.createSignal(bool, true);
    const label = try r.scope.createSignal([]const u8, "Clear data");
    const busy = try r.scope.createSignal(bool, false);
    const d = try ConfirmDialog(.{
        .open = open,
        .title = "Clear all data?",
        .message = "This cannot be undone.",
        .confirm_label = label,
        .confirm_loading = busy,
        .close_on_confirm = false,
        .on_confirm = r.cx.on(Probe, &probe, Probe.onConfirm),
    }).mount(r.scope, r.cx);
    if (!d.modal.portaled) try r.root.appendChild(testing.allocator, d.modal.overlay);
    d.confirm.behavior.events.on_click.?.invoke();
    try testing.expect(open.peek());
    try testing.expectEqual(@as(usize, 1), probe.confirmed);
    label.set("Retry");
    try testing.expectEqualStrings("Retry", textOf(d.confirm));

    // Split: the parent refuses to close (e.g. an operation is running).
    const Gate = struct {
        open: *reactive.Signal(bool),
        allow: bool = false,
        fn write(self: *@This(), value: bool) void {
            if (value or self.allow) self.open.set(value);
        }
    };
    const shown = try r.scope.createSignal(bool, true);
    var gate: Gate = .{ .open = shown };
    const g = try ConfirmDialog(.{ .open = reactive.split(shown, r.cx.on(Gate, &gate, Gate.write)), .title = "t", .confirm_label = "OK" }).mount(r.scope, r.cx);
    if (!g.modal.portaled) try r.root.appendChild(testing.allocator, g.modal.overlay);
    g.cancel.behavior.events.on_click.?.invoke();
    try testing.expect(shown.peek());
    gate.allow = true;
    g.cancel.behavior.events.on_click.?.invoke();
    try testing.expect(!shown.peek());
}

test "ConfirmDialog: an uninterruptible step disables cancel (Escape too); confirm can hide; refocus" {
    const r = try rig();
    defer r.cx.deinit();
    defer r.scope.dispose();
    var probe: Probe = .{};
    const open = try r.scope.createSignal(bool, true);
    const busy = try r.scope.createSignal(bool, true);
    const shown = try r.scope.createSignal(bool, true);
    const step = try r.scope.createSignal(u64, 0);
    const d = try ConfirmDialog(.{ .open = open, .title = "Erasing", .confirm_label = "Erase", .cancel_disabled = busy, .confirm_shown = shown, .refocus = step, .on_cancel = r.cx.on(Probe, &probe, Probe.onCancel) }).mount(r.scope, r.cx);
    if (!d.modal.portaled) try r.root.appendChild(testing.allocator, d.modal.overlay);
    r.cx.layout();
    r.cx.handleKeyDown(.escape, .{});
    try testing.expect(open.peek());
    try testing.expectEqual(@as(usize, 0), probe.cancelled);
    shown.set(false);
    try testing.expectEqual(core.Display.none, d.confirm.style.display);
    busy.set(false);
    r.cx.clearFocus();
    step.set(1);
    try testing.expect(r.cx.isFocused(d.cancel));
    r.cx.handleKeyDown(.escape, .{});
    try testing.expect(!open.peek());
    try testing.expectEqual(@as(usize, 1), probe.cancelled);
}

test "ConfirmDialog: the cancel button is the dialog's autoFocus target; primary tone" {
    const r = try rig();
    defer r.cx.deinit();
    defer r.scope.dispose();
    const open = try r.scope.createSignal(bool, false);
    const d = try ConfirmDialog(.{ .open = open, .title = "Install update?", .confirm_label = "Install", .tone = .primary, .test_ids = .{ .dialog = "confirm.update" } }).mount(r.scope, r.cx);
    try testing.expectEqualStrings("confirm.update", d.modal.dialog.meta.ownership.meta.test_id.?);
    if (!d.modal.portaled) try r.root.appendChild(testing.allocator, d.modal.overlay);
    var found = false;
    for (r.cx.focus_targets.entries.items) |e| if (e.node == d.cancel and e.auto_epoch != null) {
        found = true;
    };
    try testing.expect(found);
    const primary = try button.Button(.{ .label = "x", .variant = .primary }).mount(r.scope, r.cx);
    defer r.cx.freeNode(primary);
    try testing.expectEqual(primary.getBackground(), d.confirm.getBackground());
}

test "ConfirmDialog: mount OOM sweep" {
    try @import("../oom_sweep.zig").sweepMount("confirm_dialog", struct {
        fn mount(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const r = try ConfirmDialog(.{ .title = "t", .message = "m", .confirm_label = "OK" }).mount(scope, cx);
            return if (r.modal.portaled) null else r.modal.overlay;
        }
    }.mount);
}

test "ConfirmDialog: the title bar's close button is a part (parts / test_ids) and takes close_label" {
    const r = try rig();
    defer r.cx.deinit();
    defer r.scope.dispose();
    const a = try ConfirmDialog(.{ .open = true, .title = "Delete?", .close_label = "关闭", .test_ids = .{ .close = "confirm.close" } }).mount(r.scope, r.cx);
    if (!a.modal.portaled) try r.root.appendChild(testing.allocator, a.modal.overlay);
    try testing.expectEqualStrings("confirm.close", a.close_button.?.meta.ownership.meta.test_id.?);
    try testing.expectEqualStrings("关闭", a.close_button.?.behavior.interaction.a11y.?.label.?);
    var b: ConfirmDialogResult = undefined;
    try r.root.appendChild(testing.allocator, try v.render(r.scope, r.cx, v.box(.{}, .{
        v.capture(&b, v.with(ConfirmDialog(.{ .open = true, .title = "Discard?" }), .{}).parts(.{ .close_button = "discard.close" })),
    })));
    if (!b.modal.portaled) try r.root.appendChild(testing.allocator, b.modal.overlay);
    try testing.expectEqualStrings("discard.close", b.close_button.?.meta.ownership.meta.test_id.?);
    // ×: the dialog's cancel.
    b.close_button.?.behavior.events.on_click.?.invoke();
    try testing.expect(!b.open.?.peek());
}
