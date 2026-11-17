//! Reactive state of the jump-host guide (`jump_guide.yix`, design-r3 稿 4).
//! The owning RemoteEditor writes these signals; clicks come back through
//! `Sink`. No layout or styling lives here.
const std = @import("std");
const ui = @import("ui");
const template = @import("_jump_guide.yix.zig");

pub const Action = enum { new_host, direct, back, cancel, save };
pub const Sink = struct {
    context: *anyopaque,
    act: *const fn (*anyopaque, Action) void,
};

pub const JumpGuide = struct {
    cx: *ui.Cx,
    sink: Sink,
    empty_shown: *ui.Signal(bool),
    locked_signal: *ui.Signal(bool),
    /// Nested "新建跳板主机" editor: the parent's target name ("" = not a child).
    child_target: *ui.Signal([]const u8),
    save_disabled: *ui.Signal(bool),
    saving_signal: *ui.Signal(bool),
    post: *ui.Signal(ui.widgets.NotificationPost),
    /// Published strings live as long as the guide: reactive consumers
    /// compare against the previous value lazily. A wizard opens only a few
    /// children and toasts, so this stays tiny.
    strings: std.heap.ArenaAllocator,

    pub fn create(cx: *ui.Cx, scope: *ui.Scope, sink: Sink) !*JumpGuide {
        const self = try scope.createState(JumpGuide, .{
            .cx = cx,
            .sink = sink,
            .empty_shown = try scope.createSignal(bool, false),
            .locked_signal = try scope.createSignal(bool, false),
            .child_target = try scope.createSignal([]const u8, ""),
            .save_disabled = try scope.createSignal(bool, true),
            .saving_signal = try scope.createSignal(bool, false),
            .post = try scope.createSignal(ui.widgets.NotificationPost, .{}),
            .strings = .init(cx.allocator),
        });
        try scope.onCleanup(JumpGuide, self, cleanup);
        return self;
    }
    pub fn mountEmpty(self: *JumpGuide, scope: *ui.Scope) !*ui.Node {
        return ui.view.render(scope, self.cx, template.JumpEmpty(.{ .vm = self }));
    }
    pub fn mountBanner(self: *JumpGuide, scope: *ui.Scope) !*ui.Node {
        return ui.view.render(scope, self.cx, template.JumpChildBanner(.{ .vm = self }));
    }
    pub fn mountFooter(self: *JumpGuide, scope: *ui.Scope) !*ui.Node {
        return ui.view.render(scope, self.cx, template.JumpChildFooter(.{ .vm = self }));
    }

    pub fn setEmpty(self: *JumpGuide, shown: bool) void {
        if (self.empty_shown.peek() != shown) self.empty_shown.set(shown);
    }
    pub fn setLocked(self: *JumpGuide, value: bool) void {
        if (self.locked_signal.peek() != value) self.locked_signal.set(value);
    }
    pub fn setSaveState(self: *JumpGuide, disabled: bool, busy: bool) void {
        if (self.save_disabled.peek() != disabled) self.save_disabled.set(disabled);
        if (self.saving_signal.peek() != busy) self.saving_signal.set(busy);
    }
    /// Child mode: the banner names the parent's target ("" leaves child mode).
    pub fn setChildTarget(self: *JumpGuide, target: ?[]const u8) !void {
        const title = if (target) |name| try std.fmt.allocPrint(self.strings.allocator(), "保存后会自动作为 {s} 的第 1 跳", .{if (name.len != 0) name else "当前主机"}) else "";
        if (std.mem.eql(u8, self.child_target.peek(), title)) return;
        self.child_target.set(title);
    }
    /// Right-bottom native notification after the child saved a jump host.
    pub fn announceSaved(self: *JumpGuide, name: []const u8) !void {
        const title = try std.fmt.allocPrint(self.strings.allocator(), "已保存 {s}", .{name});
        self.post.set(self.post.peek().next(.{ .show = .{ .tone = .success, .title = title, .body = "已作为第 1 跳加入，也已出现在侧栏。" } }));
    }

    // Template readers.
    pub fn emptyShown(self: *JumpGuide) bool {
        return self.empty_shown.get();
    }
    pub fn locked(self: *JumpGuide) bool {
        return self.locked_signal.get();
    }
    pub fn childShown(self: *JumpGuide) bool {
        return self.child_target.get().len != 0;
    }
    pub fn bannerTitle(self: *JumpGuide) []const u8 {
        return self.child_target.get();
    }
    pub fn saveDisabled(self: *JumpGuide) bool {
        return self.save_disabled.get();
    }
    pub fn saving(self: *JumpGuide) bool {
        return self.saving_signal.get();
    }
    pub fn toast(self: *JumpGuide) ui.widgets.NotificationPost {
        return self.post.get();
    }
    pub fn act(self: *JumpGuide, action: Action) void {
        self.sink.act(self.sink.context, action);
    }

    fn cleanup(self: *JumpGuide) void {
        self.strings.deinit();
    }
};
