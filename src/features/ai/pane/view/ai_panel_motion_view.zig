//! AI 面板过渡探针的挂载与信号（视图是 `ai_panel_motion.yix`）。宿主每帧写入，同值不触发更新。
const std = @import("std");
const ui = @import("ui");
const template = @import("_ai_panel_motion.yix.zig");

pub const ids = template.ids;

pub const View = struct {
    root: *ui.Node,
    x: *ui.Signal(f32),
    y: *ui.Signal(f32),
    w: *ui.Signal(f32),
    h: *ui.Signal(f32),
    phase: *ui.Signal([]const u8),
    anchor: *ui.Signal([]const u8),
    opacity: *ui.Signal(f32),

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope) !*View {
        const self = try scope.createState(View, .{
            .root = undefined,
            .x = try scope.createSignal(f32, 0),
            .y = try scope.createSignal(f32, 0),
            .w = try scope.createSignal(f32, 0),
            .h = try scope.createSignal(f32, 0),
            .phase = try scope.createSignal([]const u8, "collapsed"),
            .anchor = try scope.createSignal([]const u8, "none"),
            .opacity = try scope.createSignal(f32, 0),
        });
        self.root = try ui.view.render(scope, cx, template.Probe(.{ .x = self.x, .y = self.y, .w = self.w, .h = self.h, .phase_name = self.phase, .anchor_name = self.anchor, .opacity = self.opacity }));
        return self;
    }

    fn put(comptime T: type, signal: *ui.Signal(T), value: T) void {
        if (!std.meta.eql(signal.peek(), value)) signal.set(value);
    }

    /// `rect` in window coordinates; `phase` / `anchor` must outlive the view (static strings).
    pub fn update(self: *View, rect: ui.ComputedRect, opacity: f32, phase: []const u8, anchor: []const u8) void {
        put(f32, self.opacity, @round(std.math.clamp(opacity, 0, 1) * 1000) / 1000);
        const origin = if (self.root.parent) |parent| parent.globalRect() else ui.ComputedRect{ .x = 0, .y = 0, .w = 0, .h = 0 };
        put(f32, self.x, rect.x - origin.x);
        put(f32, self.y, rect.y - origin.y);
        put(f32, self.w, @max(0, rect.w));
        put(f32, self.h, @max(0, rect.h));
        if (!std.mem.eql(u8, self.phase.peek(), phase)) self.phase.set(phase);
        if (!std.mem.eql(u8, self.anchor.peek(), anchor)) self.anchor.set(anchor);
    }
};
