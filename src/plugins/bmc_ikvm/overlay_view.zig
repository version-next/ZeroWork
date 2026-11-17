//! KVM 卡片浮层的挂载与信号。视图是 `overlays.yix`（原生 Tag / Button / TooltipSurface / HintCapsule /
//! Alert）；这里持有信号，`views.zig` 在状态、几何或时钟变化时写入，同值不触发更新。O2 / O3 的淡入淡出是根节点的不透明度动画。
const std = @import("std");
const ui = @import("ui");
const template = @import("_overlays.yix.zig");
const model = @import("overlay_model.zig");

pub const ids = template.ids;
const TagColor = ui.widgets.TagColor;

pub const Overlays = struct {
    cx: *ui.Cx,
    status: *ui.Node,
    hud: *ui.Node,
    hint: *ui.Node,
    waiting: *ui.Node,
    ai_frame: *ui.Node,

    status_shown: *ui.Signal(bool),
    status_label: *ui.Signal([]const u8),
    status_color: *ui.Signal(TagColor),
    takeover: *ui.Signal(bool),

    hud_shown: *ui.Signal(bool),
    hud_right: *ui.Signal(f32),
    hud_top: *ui.Signal(f32),
    hud_text: *ui.Signal([]const u8),
    hud_faded: bool = false,

    hint_shown: *ui.Signal(bool),
    hint_left: *ui.Signal(f32),
    hint_width: *ui.Signal(f32),
    hint_bottom: *ui.Signal(f32),
    hint_text: *ui.Signal([]const u8),
    hint_visible: bool = false,
    hint_hide_at_ms: ?f64 = null,

    waiting_shown: *ui.Signal(bool),
    waiting_left: *ui.Signal(f32),
    waiting_top: *ui.Signal(f32),
    waiting_width: *ui.Signal(f32),
    waiting_title: *ui.Signal([]const u8),
    waiting_message: *ui.Signal([]const u8),

    ai_frame_shown: *ui.Signal(bool),
    ai_frame_width: *ui.Signal(f32),
    ai_frame_height: *ui.Signal(f32),

    /// Text storage: signals hold borrowed slices, so each owns a stable buffer.
    status_buf: [96]u8 = undefined,
    hud_buf: [128]u8 = undefined,
    hint_buf: [256]u8 = undefined,
    title_buf: [128]u8 = undefined,
    message_buf: [256]u8 = undefined,

    /// Mounts the status slot (caller appends `status` to the toolbar) and the picture overlays
    /// (caller appends `ai_frame`, `hud`, `hint`, `waiting` to the video card, in that order).
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, on_takeover: ui.Handler(void)) !*Overlays {
        const self = try scope.createState(Overlays, .{
            .cx = cx,
            .status = undefined,
            .hud = undefined,
            .hint = undefined,
            .waiting = undefined,
            .ai_frame = undefined,
            .status_shown = try scope.createSignal(bool, false),
            .status_label = try scope.createSignal([]const u8, ""),
            .status_color = try scope.createSignal(TagColor, .neutral),
            .takeover = try scope.createSignal(bool, false),
            .hud_shown = try scope.createSignal(bool, false),
            .hud_right = try scope.createSignal(f32, 20),
            .hud_top = try scope.createSignal(f32, 20),
            .hud_text = try scope.createSignal([]const u8, ""),
            .hint_shown = try scope.createSignal(bool, false),
            .hint_left = try scope.createSignal(f32, 0),
            .hint_width = try scope.createSignal(f32, 0),
            .hint_bottom = try scope.createSignal(f32, 20),
            .hint_text = try scope.createSignal([]const u8, ""),
            .waiting_shown = try scope.createSignal(bool, false),
            .waiting_left = try scope.createSignal(f32, 0),
            .waiting_top = try scope.createSignal(f32, 0),
            .waiting_width = try scope.createSignal(f32, 520),
            .waiting_title = try scope.createSignal([]const u8, ""),
            .waiting_message = try scope.createSignal([]const u8, ""),
            .ai_frame_shown = try scope.createSignal(bool, false),
            .ai_frame_width = try scope.createSignal(f32, 0),
            .ai_frame_height = try scope.createSignal(f32, 0),
        });
        self.status = try ui.view.render(scope, cx, template.Status(.{ .shown = self.status_shown, .label = self.status_label, .color = self.status_color, .takeover = self.takeover, .on_takeover = on_takeover }));
        self.ai_frame = try ui.view.render(scope, cx, template.AiFrame(.{ .shown = self.ai_frame_shown, .width = self.ai_frame_width, .height = self.ai_frame_height }));
        self.hud = try ui.view.render(scope, cx, template.Hud(.{ .shown = self.hud_shown, .right = self.hud_right, .top = self.hud_top, .text = self.hud_text }));
        self.hint = try ui.view.render(scope, cx, template.Hint(.{ .shown = self.hint_shown, .left = self.hint_left, .width = self.hint_width, .bottom = self.hint_bottom, .text = self.hint_text }));
        self.waiting = try ui.view.render(scope, cx, template.Waiting(.{ .shown = self.waiting_shown, .left = self.waiting_left, .top = self.waiting_top, .width = self.waiting_width, .title = self.waiting_title, .message = self.waiting_message }));
        return self;
    }

    fn put(comptime T: type, signal: *ui.Signal(T), value: T) void {
        if (!std.meta.eql(signal.peek(), value)) signal.set(value);
    }
    fn putText(signal: *ui.Signal([]const u8), buf: []u8, text: []const u8) void {
        if (std.mem.eql(u8, signal.peek(), text)) return;
        const n = @min(buf.len, text.len);
        // A signal value may alias its own buffer; copy through a scratch first.
        var scratch: [256]u8 = undefined;
        @memcpy(scratch[0..n], text[0..n]);
        @memcpy(buf[0..n], scratch[0..n]);
        signal.set(buf[0..n]);
    }

    pub fn setStatus(self: *Overlays, value: model.Status, label: []const u8) void {
        put(bool, self.status_shown, value != .none);
        putText(self.status_label, &self.status_buf, label);
        put(TagColor, self.status_color, switch (model.statusColor(value)) {
            .neutral => .neutral,
            .accent => .accent,
            .info => .info,
            .warning => .warning,
        });
        put(bool, self.takeover, value == .ai_operating);
    }

    /// O5 over a `card_w` × `card_h` video card: the 2 px stroke sits at inset 6 (inside the 8 pt edge).
    pub fn setAiFrame(self: *Overlays, shown: bool, card_w: f32, card_h: f32) void {
        put(bool, self.ai_frame_shown, shown);
        put(f32, self.ai_frame_width, @max(0, card_w - 12));
        put(f32, self.ai_frame_height, @max(0, card_h - 12));
    }

    /// O2: `shown` = allowed by state and size; `faded` = pointer over the picture (opacity only).
    pub fn setHud(self: *Overlays, shown: bool, right: f32, top: f32, faded: bool) void {
        put(bool, self.hud_shown, shown);
        put(f32, self.hud_right, right);
        put(f32, self.hud_top, top);
        if (faded != self.hud_faded) {
            self.hud_faded = faded;
            self.fade(self.hud, if (faded) 0 else 1, if (faded) 0.15 else 0.2);
        }
    }
    pub fn setHudText(self: *Overlays, text: []const u8) void {
        putText(self.hud_text, &self.hud_buf, text);
    }
    pub fn hudHeight(self: *Overlays) f32 {
        const h = self.hud.globalRect().h;
        return if (h > 0) h else 26;
    }

    /// O3: shows `text` (fade in), or fades out and then hides when `text` is null.
    pub fn setHint(self: *Overlays, text: ?[]const u8, left: f32, width: f32, bottom: f32, now_ms: f64) void {
        put(f32, self.hint_left, left);
        put(f32, self.hint_width, width);
        put(f32, self.hint_bottom, bottom);
        if (text) |value| {
            putText(self.hint_text, &self.hint_buf, value);
            self.hint_hide_at_ms = null;
            put(bool, self.hint_shown, width > 0);
            if (!self.hint_visible) {
                self.hint_visible = true;
                self.fade(self.hint, 1, 0.15);
            }
        } else if (self.hint_visible) {
            self.hint_visible = false;
            self.hint_hide_at_ms = now_ms + 200;
            self.fade(self.hint, 0, 0.2);
        } else if (self.hint_hide_at_ms) |at| if (now_ms >= at or self.cx.reduced_motion) {
            self.hint_hide_at_ms = null;
            put(bool, self.hint_shown, false);
        };
    }

    /// When the faded-out hint must be taken off the layout (`setHint` with null again); null = none.
    pub fn hintDeadline(self: *const Overlays) ?f64 {
        return self.hint_hide_at_ms;
    }

    pub fn setWaiting(self: *Overlays, shown: bool, left: f32, top: f32, width: f32, title: []const u8, message: []const u8) void {
        put(bool, self.waiting_shown, shown);
        if (!shown) return;
        put(f32, self.waiting_left, left);
        put(f32, self.waiting_top, top);
        put(f32, self.waiting_width, width);
        putText(self.waiting_title, &self.title_buf, title);
        putText(self.waiting_message, &self.message_buf, message);
    }
    pub fn waitingHeight(self: *Overlays) ?f32 {
        const h = self.waiting.globalRect().h;
        return if (h > 0) h else null;
    }

    fn fade(self: *Overlays, node: *ui.Node, to: f32, seconds: f32) void {
        if (self.cx.reduced_motion) {
            node.setOpacity(to);
        } else ui.fx.animation.animateNode(node, self.cx.allocator, .{ .prop = .opacity, .to = to, .duration = seconds });
        self.cx.requestRedraw();
    }
};
