//! View-model of the AI composer area (view: `ai_composer.yix`, Pencil Kaf7E ③ / ⑤ / A7 / A8 /
//! A11). Owns the tool row's and the decision panel's view-models, the Textarea's result handle
//! (read by the host for its edit state), the area's margins / height / visibility and the Send /
//! Stop state. The host decides those values (width rule, turn state, draft); this file only holds
//! and shows them.
const std = @import("std");
const ui = @import("ui");
const W = ui.widgets;
const template = @import("_ai_composer.yix.zig");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
pub const Controls = @import("ai_composer_controls_view.zig");
pub const Interaction = @import("ai_composer_interaction_view.zig");

pub const Callbacks = struct {
    context: *anyopaque,
    send: *const fn (*anyopaque) void,
    stop: *const fn (*anyopaque) void,
    prompt_changed: *const fn (*anyopaque, []const u8) void,
};
pub const Options = struct {
    prompt: *ui.Signal([]const u8),
    callbacks: Callbacks,
    controls: Controls.Callbacks,
    interaction: Interaction.Callbacks,
};

pub const View = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    callbacks: Callbacks,
    /// Test-id namespace of the surface this composer is mounted in (main assistant / child dialog).
    space: IdSpace,
    prompt: *ui.Signal([]const u8),
    /// The compound Textarea's mount result (`ref={note}`): the host's IME, paste, drop, history
    /// and send route read and write its edit state.
    note: *ui.view.Ref(W.input.TextareaResult),
    controls: *Controls.View,
    interaction: *Interaction.View,
    /// Kept at mount: the area (the host measures it for the width rule), the queue slot (the
    /// request queue view) and the header row's chip slot (the attachment views).
    root: *ui.Node = undefined,
    queue: *ui.Node = undefined,
    chips: *ui.Node = undefined,
    shown: *ui.Signal(bool),
    field_shown: *ui.Signal(bool),
    /// The Textarea's header row (attachment chips): shown only while there are attachments.
    header_shown: *ui.Signal(bool),
    padding: *ui.Signal(ui.Padding),
    /// Pinned height (0 = fit its content).
    height: *ui.Signal(f32),
    /// Right margin of the “稍后处理” capsule (the area's side margin).
    side: *ui.Signal(f32),

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, options: Options) !*View {
        const self = try scope.createState(View, .{
            .cx = cx,
            .scope = scope,
            .callbacks = options.callbacks,
            .space = IdSpace.of(scope),
            .prompt = options.prompt,
            .note = try ui.view.createRef(scope, W.input.TextareaResult),
            .controls = try Controls.View.init(cx, scope, options.controls),
            .interaction = try Interaction.View.init(cx, scope, options.interaction),
            .shown = try scope.createSignal(bool, true),
            .field_shown = try scope.createSignal(bool, true),
            .header_shown = try scope.createSignal(bool, false),
            .padding = try scope.createSignal(ui.Padding, .{ .left = 12, .right = 12, .bottom = 12 }),
            .height = try scope.createSignal(f32, 0),
            .side = try scope.createSignal(f32, 12),
        });
        self.controls.useActions(.{ .context = self, .send = sendNow, .stop = stopNow });
        _ = try ui.view.render(scope, cx, template.Composer(.{ .vm = self, .note = self.note }));
        return self;
    }
    pub fn keep(self: *View, root: ?*ui.Node, queue: ?*ui.Node, chips: ?*ui.Node, panel: ?*ui.Node, capsule: ?*ui.Node) void {
        self.root = root.?;
        self.queue = queue.?;
        self.chips = chips.?;
        self.interaction.adopt(panel.?, capsule.?);
    }
    /// The compound Textarea (bound once the template has mounted it).
    pub fn input(self: *const View) W.input.TextareaResult {
        return self.note.get().?;
    }
    fn set(comptime T: type, signal: *ui.Signal(T), value: T) void {
        if (!std.meta.eql(signal.peek(), value)) signal.set(value);
    }
    pub fn setShown(self: *View, value: bool) void {
        set(bool, self.shown, value);
    }
    pub fn setFieldShown(self: *View, value: bool) void {
        set(bool, self.field_shown, value);
    }
    /// Shows / hides the header row (attachment chips); returns whether it changed.
    pub fn setHeaderShown(self: *View, value: bool) bool {
        if (self.header_shown.peek() == value) return false;
        self.header_shown.set(value);
        return true;
    }
    /// Pencil Kaf7E A8: Stop while a turn runs; Send unless the turn runs with an empty draft.
    pub fn setActions(self: *View, stop_shown: bool, send_shown: bool) void {
        set(bool, self.controls.stop_shown, stop_shown);
        set(bool, self.controls.send_shown, send_shown);
    }
    /// Send's hint (start / steer / queue, with the alternate key) and its accessible name.
    pub fn setSendHint(self: *View, hint: []const u8, label: []const u8) void {
        if (!std.mem.eql(u8, self.controls.send_hint.peek(), hint)) self.controls.send_hint.set(hint);
        if (!std.mem.eql(u8, self.controls.send_label.peek(), label)) self.controls.send_label.set(label);
    }
    /// Whether Send can act (the host's gate: model, draft, images, turn state).
    pub fn sendDisabledSignal(self: *View) *ui.Signal(bool) {
        return self.controls.send_disabled;
    }
    fn sendNow(raw: *anyopaque) void {
        const self: *View = @ptrCast(@alignCast(raw));
        self.callbacks.send(self.callbacks.context);
    }
    fn stopNow(raw: *anyopaque) void {
        const self: *View = @ptrCast(@alignCast(raw));
        self.callbacks.stop(self.callbacks.context);
    }
    /// Margins (Pencil Kaf7E ⑤) and the pinned height; returns whether anything changed.
    pub fn setArea(self: *View, pad: ui.Padding, h: f32, right: f32) bool {
        var changed = false;
        if (!std.meta.eql(self.padding.peek(), pad)) {
            self.padding.set(pad);
            changed = true;
        }
        if (@abs(self.height.peek() - h) > 0.5) {
            self.height.set(h);
            changed = true;
        }
        if (self.side.peek() != right) {
            self.side.set(right);
            changed = true;
        }
        return changed;
    }
};

// -- View bindings (read by ai_composer.yix) --

pub fn controls(vm: *View) *Controls.View {
    return vm.controls;
}
pub fn interaction(vm: *View) *Interaction.View {
    return vm.interaction;
}
pub fn prompt(vm: *View) []const u8 {
    return vm.prompt.get();
}
/// The field's edit: the draft signal takes it (the field shows the signal), then the host.
pub fn promptChanged(vm: *View, text: []const u8) void {
    if (!std.mem.eql(u8, vm.prompt.peek(), text)) vm.prompt.set(text);
    vm.callbacks.prompt_changed(vm.callbacks.context, vm.prompt.peek());
}
pub fn shown(vm: *View) bool {
    return vm.shown.get();
}
pub fn fieldShown(vm: *View) bool {
    return vm.field_shown.get();
}
pub fn headerShown(vm: *View) bool {
    return vm.header_shown.get();
}
pub fn padding(vm: *View) ui.Padding {
    return vm.padding.get();
}
pub fn height(vm: *View) f32 {
    return vm.height.get();
}
pub fn side(vm: *View) f32 {
    return vm.side.get();
}
