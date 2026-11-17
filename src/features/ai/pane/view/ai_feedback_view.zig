//! Local UI feedback: one content-sized surface inside the transcript scroll.
//! It is not an assistant message and never enters model history.
//! The view is `ai_feedback.yix` (native `W.Alert`); this file owns its three
//! signals so the host keeps the imperative `show` / `dismiss` entry points.
const std = @import("std");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const template = @import("_ai_feedback.yix.zig");

pub const Kind = template.Kind;
pub const rollback_label = "已回退，原消息已恢复到输入框，此回合及后续对话已移除。";

pub const View = struct {
    cx: *ui.Cx,
    root: *ui.Node,
    text: *ui.Signal([]const u8),
    kind: *ui.Signal(Kind),
    shown: *ui.Signal(bool),
    /// The host passes transient buffers; the shown text lives in one of two
    /// owned slots (the other still backs the previous value until replaced).
    slots: [2]std.ArrayList(u8) = .{ .empty, .empty },
    slot: u1 = 0,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope) !*View {
        const self = try scope.createState(View, .{
            .cx = cx,
            .root = undefined,
            .text = try scope.createSignal([]const u8, ""),
            .kind = try scope.createSignal(Kind, .warning),
            .shown = try scope.createSignal(bool, false),
        });
        try scope.onCleanup(View, self, cleanup);
        self.root = try ui.view.render(scope, cx, template.Feedback(.{ .space = IdSpace.of(scope),
            .text = self.text,
            .kind = self.kind,
            .shown = self.shown,
            .on_dismiss = cx.on(View, self, dismiss),
        }));
        return self;
    }

    /// Polling can report the same failure on successive frames: equal values
    /// write nothing, so the idle scene stays clean.
    pub fn show(self: *View, label: []const u8, kind: Kind) void {
        const visible = label.len != 0;
        if (!std.mem.eql(u8, self.text.peek(), label)) {
            const next = &self.slots[self.slot +% 1];
            next.clearRetainingCapacity();
            next.appendSlice(self.cx.allocator, label) catch return;
            self.slot +%= 1;
            self.text.set(next.items);
        }
        if (self.kind.peek() != kind) self.kind.set(kind);
        if (self.shown.peek() != visible) self.shown.set(visible);
    }

    /// Blocking reasons stay until resolved; only completed actions offer this.
    pub fn dismiss(self: *View) void {
        if (self.shown.peek()) self.shown.set(false);
    }

    fn cleanup(self: *View) void {
        for (&self.slots) |*slot| slot.deinit(self.cx.allocator);
    }
};
