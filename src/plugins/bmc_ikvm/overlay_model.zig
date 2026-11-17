//! KVM 卡片浮层的纯逻辑（Pencil j8WXoF「ZW · KVM 卡片浮层 2026-11-13」，需求总账 #58）：
//! 工具栏状态区的优先级与文案、画面浮层的几何（含 D 区四角避让规则表）、HUD 与提示条的显隐计时。
//! 不碰节点、不读时钟；`views.zig` 在状态 / 几何 / 时钟到点时调用，经 `overlay_view.zig` 写信号。
const std = @import("std");
const contract = @import("../../host/plugin_ui_contract.zig");
const services = @import("services.zig");
const release_hint = @import("input_mapping.zig").release_hint;

pub const Rect = contract.LauncherRect;
pub const Placement = contract.LauncherPlacement;

/// O3：图标列 = 图标 48 + 内边距 24 + 间距 12。
pub const icon_column: f32 = 84;
/// 画面浮层与画面边 / 图标的间距。
pub const edge: f32 = 12;
/// O2：画面宽 < 640 收成一行 FPS，< 480 隐藏。
pub const hud_compact_width: f32 = 640;
pub const hud_hidden_width: f32 = 480;
/// O2：指针进入画面 150 ms 后淡出，离开 600 ms 后恢复。
pub const hud_fade_in_ms: f64 = 600;
pub const hud_fade_out_ms: f64 = 150;
/// O3：瞬时提示 3 s 后淡出。
pub const hint_transient_ms: f64 = 3000;
/// O4：图标在底角时中心卡高度上限再减 80。
pub const bottom_icon_reserve: f32 = 80;

/// O1：同一时刻只显示优先级最高的一个——电源 > AI 操作 > 键鼠捕获 > AI 观察（用户已拍板）。
pub const Status = enum { none, ai_observing, captured, ai_operating, power };

pub const AiActivity = enum { none, observing, operating };

pub fn status(power_running: bool, ai: AiActivity, captured: bool) Status {
    if (power_running) return .power;
    if (ai == .operating) return .ai_operating;
    if (captured) return .captured;
    if (ai == .observing) return .ai_observing;
    return .none;
}

pub const TagColor = enum { neutral, accent, info, warning };

pub fn statusColor(value: Status) TagColor {
    return switch (value) {
        .power => .warning,
        .ai_operating => .accent,
        .captured => .info,
        .ai_observing, .none => .neutral,
    };
}

/// 电源动作的短动词（Tag 与等待画面共用）。
pub fn powerVerb(action: services.PowerAction) []const u8 {
    return switch (action) {
        .on => "开机",
        .graceful_shutdown => "关机",
        .graceful_restart, .force_restart => "重启",
        .force_off => "断电",
        .power_cycle => "断电重启",
    };
}

/// Tag 文案；窄工具栏用短词（j8WXoF O1："AI 操作""已捕获 ⌃⌥Esc""重启 12 s"）。
pub fn statusLabel(buf: []u8, value: Status, compact: bool, power: ?services.PowerAction, power_elapsed_s: u64) []const u8 {
    return switch (value) {
        .none => "",
        .power => blk: {
            const verb = powerVerb(power orelse .graceful_restart);
            break :blk (if (compact) std.fmt.bufPrint(buf, "{s} {d} s", .{ verb, power_elapsed_s }) else std.fmt.bufPrint(buf, "正在{s} · 已 {d} s", .{ verb, power_elapsed_s })) catch verb;
        },
        .ai_operating => if (compact) "AI 操作" else "AI 操作中",
        .captured => if (compact) "已捕获 " ++ release_hint else "键鼠已捕获 · " ++ release_hint ++ " 释放",
        .ai_observing => if (compact) "AI 观察" else "AI 观察中",
    };
}

/// 电源结果仍在执行（已获批准、尚未终结）。等待批准 / 二次认证不算执行。
pub fn powerRunning(phase: services.Phase) bool {
    return switch (phase) {
        .queued, .refreshing, .sending, .accepted_remote, .tracking_task, .verifying => true,
        .awaiting_approval, .awaiting_auth, .succeeded, .failed, .outcome_unknown, .cancelled_unsent => false,
    };
}

pub const HudMode = enum { hidden, compact, full };

pub fn hudMode(viewport_width: f32) HudMode {
    return if (viewport_width < hud_hidden_width) .hidden else if (viewport_width < hud_compact_width) .compact else .full;
}

pub fn hudText(buf: []u8, mode: HudMode, width: u32, height: u32, display_fps: ?f32, decode_fps: ?f32) []const u8 {
    var display: [16]u8 = undefined;
    var decode: [16]u8 = undefined;
    const d = if (display_fps) |v| std.fmt.bufPrint(&display, "{d:.1}", .{v}) catch "—" else "—";
    const e = if (decode_fps) |v| std.fmt.bufPrint(&decode, "{d:.1}", .{v}) catch "—" else "—";
    return switch (mode) {
        .hidden => "",
        .compact => std.fmt.bufPrint(buf, "{s} FPS", .{d}) catch "",
        .full => std.fmt.bufPrint(buf, "{d} × {d} · 显示 {s} · 解码 {s} FPS", .{ width, height, d, e }) catch "",
    };
}

fn isRight(corner: contract.LauncherCorner) bool {
    return corner == .bottom_right or corner == .top_right;
}
fn isBottom(corner: contract.LauncherCorner) bool {
    return corner == .bottom_right or corner == .bottom_left;
}

/// O2 位置（相对视频卡片的右 / 上边距）。默认画面右上、距画面边 12；100% 模式有竖向滚动条时再左移 12。
/// 图标停在右上：HUD 横向让位，右沿 = 图标左沿 − 12，与图标垂直居中（D 区表）。
pub fn hudInsets(card: Rect, viewport: Rect, launcher: ?Placement, hud_height: f32, scrollbar_y: bool) struct { right: f32, top: f32 } {
    var right_edge = viewport.x + viewport.w - edge - (if (scrollbar_y) edge else 0);
    var top = viewport.y + edge;
    if (launcher) |l| if (l.corner == .top_right) {
        right_edge = @min(right_edge, l.rect.x - edge);
        top = l.rect.y + l.rect.h / 2 - hud_height / 2;
    };
    return .{ .right = card.x + card.w - right_edge, .top = top - card.y };
}

/// O3 区间（相对视频卡片）：画面底边上 12，左右各留 84 给图标列。
pub fn hintBand(card: Rect, viewport: Rect) struct { left: f32, width: f32, bottom: f32 } {
    return .{
        .left = viewport.x - card.x + icon_column,
        .width = @max(0, viewport.w - 2 * icon_column),
        .bottom = (card.y + card.h) - (viewport.y + viewport.h) + edge,
    };
}

/// O4 中心卡（连接 / 失败卡与等待画面）在窗口坐标里的位置与尺寸：宽 = min(画面宽 − 32, `max_width`)；
/// 高度上限 = min(画面高 − 24, `max_height`)，图标在本卡片底角时再减 80；图标在顶角且中心卡伸进图标列时
/// top ≥ 图标底 + 12（D 区表）。`height` = null 时取上限（连接卡），否则取它与上限的较小者。
pub fn centerCard(viewport: Rect, max_width: f32, max_height: f32, height: ?f32, launcher: ?Placement) Rect {
    const w = @min(@max(viewport.w - 32, 0), max_width);
    var cap = @min(@max(viewport.h - 24, 0), max_height);
    if (launcher) |l| if (isBottom(l.corner)) {
        cap = @max(0, cap - bottom_icon_reserve);
    };
    const h = if (height) |value| @min(value, cap) else cap;
    const x = viewport.x + @max(0, (viewport.w - w) / 2);
    var y = viewport.y + @max(edge, (viewport.h - h) / 2);
    if (launcher) |l| if (!isBottom(l.corner)) {
        const column_left = l.rect.x - edge;
        const column_right = l.rect.x + l.rect.w + edge;
        if (x < column_right and x + w > column_left) y = @max(y, l.rect.y + l.rect.h + edge);
    };
    return .{ .x = x, .y = y, .w = w, .h = h };
}

/// O2 的显隐状态机：指针进入画面 150 ms 后淡出，离开 600 ms 后恢复（中途折返就取消，不闪）。
///
/// ```
///            enter                 150 ms                leave                 600 ms
///  visible ─────────▶ leaving ─────────────▶ hidden ─────────▶ returning ─────────────▶ visible
///     ▲                  │ leave                ▲                   │ enter
///     └──────────────────┘                      └───────────────────┘
/// ```
///
/// 只有两种输入：指针是否在画面上（`pointer`，来自画面节点的原生 hover，一处）和时钟到点（`due`）。
/// 时间是调用方给的单调毫秒；状态机不读时钟、不碰节点，等待中的状态用 `deadline` 报出下一次到点时间。
pub const HudReveal = struct {
    pub const State = enum { visible, leaving, hidden, returning };
    state: State = .visible,
    /// 进入 `leaving` / `returning` 的时刻。
    since_ms: f64 = 0,

    /// 指针进入 / 离开画面。重复报告同一侧不改变状态（不会把计时重新起算）。
    pub fn pointer(self: *HudReveal, inside: bool, now_ms: f64) void {
        self.state = switch (self.state) {
            .visible => if (inside) .leaving else return,
            .leaving => if (inside) return else .visible,
            .hidden => if (inside) return else .returning,
            .returning => if (inside) .hidden else return,
        };
        self.since_ms = now_ms;
    }
    /// 时钟到点：把已经等够的状态落到终态。
    pub fn due(self: *HudReveal, now_ms: f64) void {
        const at = self.deadline() orelse return;
        if (now_ms < at) return;
        self.state = if (self.state == .leaving) .hidden else .visible;
    }
    /// 下一次需要 `due` 的时刻；null = 稳定，不需要计时。
    pub fn deadline(self: *const HudReveal) ?f64 {
        return switch (self.state) {
            .leaving => self.since_ms + hud_fade_out_ms,
            .returning => self.since_ms + hud_fade_in_ms,
            .visible, .hidden => null,
        };
    }
    /// HUD 当前应当淡出（不透明度 0）。等待恢复期间仍是淡出的，等待淡出期间仍是显示的。
    pub fn faded(self: *const HudReveal) bool {
        return self.state == .hidden or self.state == .returning;
    }
};

/// O3 提示：瞬时提示 3 s 后淡出；错误提示保留到用户下一次操作。
pub const Hint = struct {
    pub const Kind = enum { transient, until_action };
    text: [256]u8 = undefined,
    len: usize = 0,
    kind: Kind = .transient,
    shown_ms: f64 = 0,
    active: bool = false,

    pub fn show(self: *Hint, text: []const u8, kind: Kind, now_ms: f64) void {
        if (text.len == 0) return self.clear();
        const n = @min(text.len, self.text.len);
        @memcpy(self.text[0..n], text[0..n]);
        self.len = n;
        self.kind = kind;
        self.shown_ms = now_ms;
        self.active = true;
    }
    pub fn clear(self: *Hint) void {
        self.active = false;
        self.len = 0;
    }
    /// 用户的下一次操作（按键、点击）收起"保留到下一次操作"的提示。
    pub fn userAction(self: *Hint) void {
        if (self.active and self.kind == .until_action) self.clear();
    }
    pub fn visible(self: *Hint, now_ms: f64) bool {
        if (self.active and self.kind == .transient and now_ms - self.shown_ms >= hint_transient_ms) self.clear();
        return self.active;
    }
    pub fn slice(self: *const Hint) []const u8 {
        return self.text[0..self.len];
    }
    /// 瞬时提示到期的时刻；null = 没有在计时（未显示，或要等用户操作）。
    pub fn deadline(self: *const Hint) ?f64 {
        return if (self.active and self.kind == .transient) self.shown_ms + hint_transient_ms else null;
    }
};

test "O1 shows only the highest priority: power > AI operating > captured > AI observing" {
    try std.testing.expectEqual(Status.power, status(true, .operating, true));
    try std.testing.expectEqual(Status.ai_operating, status(false, .operating, true));
    try std.testing.expectEqual(Status.captured, status(false, .observing, true));
    try std.testing.expectEqual(Status.ai_observing, status(false, .observing, false));
    try std.testing.expectEqual(Status.none, status(false, .none, false));
    var buf: [64]u8 = undefined;
    try std.testing.expectEqualStrings("正在重启 · 已 12 s", statusLabel(&buf, .power, false, .graceful_restart, 12));
    try std.testing.expectEqualStrings("重启 12 s", statusLabel(&buf, .power, true, .force_restart, 12));
    try std.testing.expectEqualStrings("已捕获 ⌃⌥Esc", statusLabel(&buf, .captured, true, null, 0));
    try std.testing.expectEqual(TagColor.warning, statusColor(.power));
    try std.testing.expectEqual(TagColor.accent, statusColor(.ai_operating));
    try std.testing.expect(powerRunning(.tracking_task));
    try std.testing.expect(!powerRunning(.awaiting_approval));
    try std.testing.expect(!powerRunning(.succeeded));
}

test "O2 HUD: right-top 12 from the picture; gives way sideways to a top-right icon; narrow rules" {
    const card: Rect = .{ .x = 300, .y = 100, .w = 1000, .h = 700 };
    const vp: Rect = .{ .x = 308, .y = 108, .w = 984, .h = 684 };
    const plain = hudInsets(card, vp, null, 28, false);
    try std.testing.expectEqual(@as(f32, 20), plain.right);
    try std.testing.expectEqual(@as(f32, 20), plain.top);
    try std.testing.expectEqual(@as(f32, 32), hudInsets(card, vp, null, 28, true).right);
    // Bottom-right icon: different corner, nothing moves.
    const br: Placement = .{ .corner = .bottom_right, .rect = .{ .x = 1228, .y = 732, .w = 48, .h = 48 } };
    try std.testing.expectEqual(plain.right, hudInsets(card, vp, br, 28, false).right);
    // Top-right icon at toolbar bottom + 12: HUD right = icon left - 12, centred on the icon.
    const tr: Placement = .{ .corner = .top_right, .rect = .{ .x = 1228, .y = 112, .w = 48, .h = 48 } };
    const moved = hudInsets(card, vp, tr, 28, false);
    try std.testing.expectEqual(@as(f32, 1300 - (1228 - 12)), moved.right);
    try std.testing.expectEqual(@as(f32, 112 + 24 - 14 - 100), moved.top);
    try std.testing.expectEqual(HudMode.full, hudMode(640));
    try std.testing.expectEqual(HudMode.compact, hudMode(639));
    try std.testing.expectEqual(HudMode.hidden, hudMode(479));
    var buf: [96]u8 = undefined;
    try std.testing.expectEqualStrings("1280 × 1024 · 显示 8.0 · 解码 8.2 FPS", hudText(&buf, .full, 1280, 1024, 8.0, 8.2));
    try std.testing.expectEqualStrings("8.0 FPS", hudText(&buf, .compact, 1280, 1024, 8.0, 8.2));
    try std.testing.expectEqualStrings("— FPS", hudText(&buf, .compact, 0, 0, null, null));
}

test "O3 band keeps 84 for the icon column on both sides; O4 avoids the icon per corner" {
    const card: Rect = .{ .x = 300, .y = 100, .w = 1000, .h = 700 };
    const vp: Rect = .{ .x = 308, .y = 108, .w = 984, .h = 684 };
    const band = hintBand(card, vp);
    try std.testing.expectEqual(@as(f32, 8 + 84), band.left);
    try std.testing.expectEqual(@as(f32, 984 - 168), band.width);
    try std.testing.expectEqual(@as(f32, 8 + 12), band.bottom);
    // Connection card: 520 x 441 when there is room and no bottom icon.
    const free = centerCard(vp, 520, 441, null, null);
    try std.testing.expectEqual(@as(f32, 520), free.w);
    try std.testing.expectEqual(@as(f32, 441), free.h);
    // Bottom corner icon: height cap - 80.
    const br: Placement = .{ .corner = .bottom_right, .rect = .{ .x = 1228, .y = 732, .w = 48, .h = 48 } };
    try std.testing.expectEqual(@as(f32, 361), centerCard(vp, 520, 441, null, br).h);
    // Top-right icon: unaffected while the card stays out of the icon column...
    const tr: Placement = .{ .corner = .top_right, .rect = .{ .x = 1228, .y = 112, .w = 48, .h = 48 } };
    try std.testing.expectEqual(free.y, centerCard(vp, 520, 441, null, tr).y);
    // ...but a narrow picture that pushes it into the column moves it below the icon.
    const narrow: Rect = .{ .x = 900, .y = 108, .w = 392, .h = 684 };
    const tr2: Placement = .{ .corner = .top_right, .rect = .{ .x = 1220, .y = 112, .w = 48, .h = 48 } };
    try std.testing.expect(centerCard(narrow, 520, 120, 120, tr2).y >= 112 + 48 + 12);
    // A sized card (waiting alert) keeps its height.
    try std.testing.expectEqual(@as(f32, 96), centerCard(vp, 520, 441, 96, null).h);
}

test "HUD reveal: fades 150 ms after the pointer enters, returns 600 ms after it leaves, a turn-back cancels the wait" {
    var hud: HudReveal = .{};
    try std.testing.expect(!hud.faded());
    try std.testing.expectEqual(@as(?f64, null), hud.deadline());
    // Outside stays visible, with nothing to wait for.
    hud.pointer(false, 0);
    try std.testing.expectEqual(HudReveal.State.visible, hud.state);
    // Enter: still shown for 150 ms, then hidden; no further deadline.
    hud.pointer(true, 1000);
    try std.testing.expectEqual(HudReveal.State.leaving, hud.state);
    try std.testing.expectEqual(@as(?f64, 1150), hud.deadline());
    hud.due(1149);
    try std.testing.expect(!hud.faded());
    // Reporting the same side again does not restart the wait.
    hud.pointer(true, 1100);
    try std.testing.expectEqual(@as(?f64, 1150), hud.deadline());
    hud.due(1150);
    try std.testing.expectEqual(HudReveal.State.hidden, hud.state);
    try std.testing.expect(hud.faded());
    try std.testing.expectEqual(@as(?f64, null), hud.deadline());
    // Leave: stays hidden for 600 ms, then visible.
    hud.pointer(false, 2000);
    try std.testing.expectEqual(HudReveal.State.returning, hud.state);
    try std.testing.expect(hud.faded());
    try std.testing.expectEqual(@as(?f64, 2600), hud.deadline());
    hud.due(2599);
    try std.testing.expect(hud.faded());
    hud.due(2600);
    try std.testing.expectEqual(HudReveal.State.visible, hud.state);
    try std.testing.expect(!hud.faded());
    // A brush over the picture shorter than 150 ms never hides it.
    hud.pointer(true, 3000);
    hud.pointer(false, 3100);
    try std.testing.expectEqual(HudReveal.State.visible, hud.state);
    try std.testing.expectEqual(@as(?f64, null), hud.deadline());
    hud.due(3200);
    try std.testing.expect(!hud.faded());
    // Coming back before the 600 ms are over keeps it hidden, without a flash.
    hud.pointer(true, 4000);
    hud.due(4150);
    hud.pointer(false, 5000);
    hud.pointer(true, 5300);
    try std.testing.expectEqual(HudReveal.State.hidden, hud.state);
    hud.due(5600);
    try std.testing.expect(hud.faded());
    // A late clock (one frame after a long idle) lands on the settled state in one step.
    hud.pointer(false, 6000);
    hud.due(60_000);
    try std.testing.expectEqual(HudReveal.State.visible, hud.state);
}

test "hints: transient ones time out after 3 s, errors stay until the next user action" {
    var hint: Hint = .{};
    try std.testing.expectEqual(@as(?f64, null), hint.deadline());
    hint.show("已捕获键鼠，按 " ++ release_hint ++ " 释放", .transient, 0);
    try std.testing.expectEqual(@as(?f64, 3000), hint.deadline());
    try std.testing.expect(hint.visible(2999));
    try std.testing.expect(!hint.visible(3000));
    hint.show("此按键尚不支持", .until_action, 0);
    try std.testing.expectEqual(@as(?f64, null), hint.deadline());
    try std.testing.expect(hint.visible(10_000));
    hint.userAction();
    try std.testing.expect(!hint.visible(10_001));
}
