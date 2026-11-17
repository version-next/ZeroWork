//! 浮动 AI 图标的挂载与信号。视图是 `ai_launcher.yix`（原生 GlassButton + Badge + Tooltip）；
//! 这里持有它的信号，宿主每帧写入显隐、位置与状态，同值不触发更新。两个根（脉冲圆点 `ring`、图标 `root`）
//! 由宿主按这个顺序挂到窗口根上。
const std = @import("std");
const ui = @import("ui");
const template = @import("_ai_launcher.yix.zig");
const float_card_motion = @import("../../../../shared/ui/styles/float_card_motion.zig");
/// The launcher geometry / state model (re-exported for hosts that place the view, e.g. previews).
pub const model = @import("../model/ai_launcher.zig");

pub const ids = template.ids;
pub const ButtonDrag = ui.widgets.glass_bars.ButtonDrag;
const SymbolEffect = ui.widgets.glass_bars.SymbolEffect;
const BadgeStatus = ui.widgets.badge.BadgeStatus;

pub const View = struct {
    cx: *ui.Cx,
    root: *ui.Node,
    ring: *ui.Node,
    shown: *ui.Signal(bool),
    x: *ui.Signal(f32),
    y: *ui.Signal(f32),
    label: *ui.Signal([]const u8),
    state_name: *ui.Signal([]const u8),
    glass_tint: *ui.Signal(?ui.Color),
    ink: *ui.Signal(?ui.Color),
    effect: *ui.Signal(SymbolEffect),
    lifted: *ui.Signal(bool),
    dot_shown: *ui.Signal(bool),
    dot_status: *ui.Signal(BadgeStatus),
    /// Pencil j8WXoF: faded out over a captured KVM picture (pointer passes through).
    yielded: bool = false,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, on_open: ui.Handler(void), on_drag: ui.Handler(ButtonDrag)) !*View {
        const self = try scope.createState(View, .{
            .cx = cx,
            .root = undefined,
            .ring = undefined,
            .shown = try scope.createSignal(bool, false),
            .x = try scope.createSignal(f32, 0),
            .y = try scope.createSignal(f32, 0),
            .label = try scope.createSignal([]const u8, model.label(.idle)),
            .state_name = try scope.createSignal([]const u8, @tagName(model.State.idle)),
            .glass_tint = try scope.createSignal(?ui.Color, null),
            .ink = try scope.createSignal(?ui.Color, null),
            .effect = try scope.createSignal(SymbolEffect, .none),
            .lifted = try scope.createSignal(bool, false),
            .dot_shown = try scope.createSignal(bool, false),
            .dot_status = try scope.createSignal(BadgeStatus, .info),
        });
        self.root = try ui.view.render(scope, cx, template.Launcher(.{
            .shown = self.shown,
            .x = self.x,
            .y = self.y,
            .label = self.label,
            .state_name = self.state_name,
            .glass_tint = self.glass_tint,
            .ink = self.ink,
            .effect = self.effect,
            .lifted = self.lifted,
            .dot_shown = self.dot_shown,
            .dot_status = self.dot_status,
            .on_open = on_open,
            .on_drag = on_drag,
        }));
        self.ring = try ui.view.render(scope, cx, template.Ring(.{ .shown = self.shown, .x = self.x, .y = self.y, .dot_status = self.dot_status }));
        return self;
    }

    fn put(comptime T: type, signal: *ui.Signal(T), value: T) void {
        if (!std.meta.eql(signal.peek(), value)) signal.set(value);
    }

    /// `rect` is in window coordinates; null hides the launcher. `yielded`: the remote picture
    /// under it holds the keyboard and mouse — fade to 0 (150 ms) and let the pointer through.
    pub fn update(self: *View, frame: ?model.Rect, state: model.State, lifted: bool, yielded: bool) void {
        put(bool, self.shown, frame != null);
        self.setYielded(yielded and frame != null);
        if (frame) |r| {
            const origin = if (self.root.parent) |parent| parent.globalRect() else ui.ComputedRect{ .x = 0, .y = 0, .w = 0, .h = 0 };
            put(f32, self.x, r.x - origin.x);
            put(f32, self.y, r.y - origin.y);
        }
        const c = &self.cx.tokens.tokens.color;
        put(?ui.Color, self.glass_tint, if (state == .approval) c.warning_subtle else null);
        put(?ui.Color, self.ink, switch (state) {
            .approval => c.warning,
            .working => c.accent,
            else => null,
        });
        put(SymbolEffect, self.effect, if (state == .working) .pulse else .none);
        put(bool, self.lifted, lifted);
        put(bool, self.dot_shown, switch (state) {
            .approval, .failed, .unknown, .success => true,
            .idle, .working => false,
        });
        put(BadgeStatus, self.dot_status, switch (state) {
            .approval, .unknown => .warning,
            .failed => .@"error",
            else => .info,
        });
        if (!std.mem.eql(u8, self.label.peek(), model.label(state))) self.label.set(model.label(state));
        if (!std.mem.eql(u8, self.state_name.peek(), @tagName(state))) self.state_name.set(@tagName(state));
    }

    /// Approval pulse (Db7OS): the ring dot grows 8 -> 16 pt and fades 60% -> 0, `count` times.
    /// Reduced motion keeps only the static tint and dot.
    pub fn ping(self: *View, count: u32) void {
        if (count == 0 or self.cx.reduced_motion) return;
        ui.fx.animation.presets.ping(self.ring, self.cx.allocator, .{ .count = count, .duration = 1.0, .to_scale = 2.0, .from_opacity = 0.6 });
        self.cx.requestRedraw();
    }

    /// Swipe collapse (Pencil AveHg ③): the panel slid out, the icon fades in at its corner —
    /// opacity 0 → 1 and scale `from_scale` → 1 after the delay (`float_card_motion.arrival`).
    pub fn appear(self: *View, motion: float_card_motion.Arrival) void {
        const animation = ui.fx.animation;
        const a = self.cx.allocator;
        // `restart`: start from 0 / `from_scale` even if an earlier fade of the icon is still set.
        animation.animateNode(self.root, a, .{ .prop = .opacity, .from = 0, .to = 1, .duration = motion.duration_s, .delay = motion.delay_s, .easing = motion.easing, .restart = true });
        inline for (.{ .scale_x, .scale_y }) |prop| animation.animateNode(self.root, a, .{ .prop = prop, .from = motion.from_scale, .to = 1, .duration = motion.duration_s, .delay = motion.delay_s, .easing = motion.easing, .restart = true });
        self.cx.requestRedraw();
    }

    fn setYielded(self: *View, yielded: bool) void {
        if (self.yielded == yielded) return;
        self.yielded = yielded;
        // Not hit-test visible = the whole subtree is out of hit testing (pointer passes through).
        self.root.setHitTestVisible(!yielded);
        self.ring.setHitTestVisible(!yielded);
        const to: f32 = if (yielded) 0 else 1;
        if (self.cx.reduced_motion) {
            self.root.setOpacity(to);
        } else ui.fx.animation.animateNode(self.root, self.cx.allocator, .{ .prop = .opacity, .to = to, .duration = 0.15 });
        self.cx.requestRedraw();
    }

    pub fn isYielded(self: *const View) bool {
        return self.yielded;
    }

    pub fn rect(self: *View) ui.ComputedRect {
        return self.root.globalRect();
    }
};
