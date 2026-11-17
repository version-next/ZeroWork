//! Global queue progress on the title bar's “传输管理” button (design-r3 稿 5).
//! The button is a native zenit icon-only Button (shell `title_tools.yix`):
//! no drawn ring or percent overlay. The phase picks the glyph and the
//! progress reads in the native Tooltip / ⋯ menu (“传输管理 · 传输进行中 · 42%”);
//! this view only keeps the projection and the button's a11y description.
const std = @import("std");
const ui = @import("ui");
pub const Phase = enum { idle, running, waiting, paused, failed, completed };
pub const View = struct {
    cx: *ui.Cx,
    root: *ui.Node,
    phase: Phase = .idle,
    fraction: ?f32 = null,
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, button: *ui.Node) !*View {
        const self = try scope.createState(View, .{ .cx = cx, .root = button });
        self.update(.idle, null);
        return self;
    }
    pub fn update(self: *View, phase: Phase, fraction: ?f32) void {
        const changed = self.phase != phase or self.fraction != fraction;
        self.phase = phase;
        self.fraction = fraction;
        if (self.root.behavior.interaction.a11y) |*props| props.description = describe(phase, fraction != null);
        if (changed) self.cx.requestRedraw();
    }
    /// “传输进行中 · 42%” etc. (empty when idle).
    pub fn stateText(self: *const View, buffer: []u8) []const u8 {
        return switch (self.phase) {
            .idle => "",
            .running => if (self.fraction) |f| std.fmt.bufPrint(buffer, "传输进行中 · {d:.0}%", .{std.math.clamp(f, 0, 1) * 100}) catch "传输进行中" else "传输进行中",
            .waiting => "等待传输",
            .paused => "传输已暂停",
            .failed => "传输失败，打开查看详情",
            .completed => "传输已完成",
        };
    }
    /// The glyph for the phase (lucide name).
    pub fn iconName(self: *const View) []const u8 {
        return switch (self.phase) {
            .idle, .running, .waiting => "arrow-down-up",
            .paused => "circle-pause",
            .failed => "circle-alert",
            .completed => "circle-check",
        };
    }
    fn describe(phase: Phase, known: bool) []const u8 {
        return switch (phase) {
            .idle => "全局传输队列",
            .running => if (!known) "正在传输，大小未知" else "全局传输进度",
            .waiting => "等待传输",
            .paused => "传输已暂停",
            .failed => "传输失败，打开查看详情",
            .completed => "传输已完成",
        };
    }
};
