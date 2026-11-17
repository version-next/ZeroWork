//! 每个 tab 的浮动 AI 图标 `ai.launcher`（Pencil XqqLV：tfmv1 / cVXd5 状态矩阵，Db7OS 规则，wqZ1s 位置与拖放）。
//!
//! 只有纯逻辑：状态投影（同一时刻只显示一种）、"打开面板即清除"的已读记账、四角停放几何。
//! 视图在 `pane/view/ai_launcher.yix`，宿主在 `AiHost.updateLauncher`。
const std = @import("std");

/// Db7OS 的优先级：待审批 > 运行中 > 失败 > 结果待核实 > 有新回答未读 > 空闲。
pub const State = enum { idle, working, approval, success, failed, unknown };

pub const Flags = struct { pending: bool, busy: bool, failed: bool, unknown: bool, has_answer: bool };

/// 与原 AI 条的投影顺序一致：pending > busy > failed > unknown > has_answer > idle。
pub fn project(flags: Flags) State {
    return if (flags.pending) .approval else if (flags.busy) .working else if (flags.failed) .failed else if (flags.unknown) .unknown else if (flags.has_answer) .success else .idle;
}

/// a11y 与提示文案（Db7OS："a11y label 随状态变化"；tfmv1 的提示气泡）。
pub fn label(state: State) []const u8 {
    return switch (state) {
        .idle => "AI 助手",
        .approval => "AI 助手，有操作等待批准",
        .working => "AI 助手，正在执行",
        .failed => "AI 助手，任务失败，点击查看",
        .unknown => "AI 助手，执行结果仍待核实",
        .success => "AI 助手，有新回答",
    };
}

/// 当前事实（未经已读过滤）。
pub const Facts = struct { pending: bool, busy: bool, failed: bool, unknown: bool };

/// 一个归属对象（tab）的已读记账。失败 / 待核实 / 未读在面板打开时清除；
/// 待审批与运行中不记账，状态解除才消失。
/// "有新回答"是一次运行在面板收起时结束（运行中 → 不再运行且没有失败）；在别的 tab 时结束的，切回来时也算。
pub const Seen = struct {
    failed: bool = false,
    unknown: bool = false,
    unread: bool = false,
    was_busy: bool = false,

    /// 面板可见：当前的一切都算已读。
    pub fn acknowledge(self: *Seen, facts: Facts) void {
        self.* = .{ .failed = facts.failed, .unknown = facts.unknown, .was_busy = facts.busy };
    }

    /// 面板隐藏：只显示打开面板之后才出现的事项。事实消失后清掉已读位，下次再出现时重新提示。
    pub fn flags(self: *Seen, facts: Facts) Flags {
        if (!facts.failed) self.failed = false;
        if (!facts.unknown) self.unknown = false;
        if (self.was_busy and !facts.busy and !facts.failed) self.unread = true;
        // 新一轮运行开始：旧的未读 / 失败角标作废（运行中优先显示）。
        if (facts.busy) self.unread = false;
        self.was_busy = facts.busy;
        return .{ .pending = facts.pending, .busy = facts.busy, .failed = facts.failed and !self.failed, .unknown = facts.unknown and !self.unknown, .has_answer = self.unread };
    }
};

/// 停放的角；所有 tab 共用一个（wqZ1s："停放的角是全局位置"）。
pub const Corner = enum { bottom_right, bottom_left, top_right, top_left };

pub const Rect = struct { x: f32, y: f32, w: f32, h: f32 };

/// zenit GlassButton 纯图标默认尺寸（glass_bars.button_image_diameter）。
pub const size: f32 = 48;
/// wqZ1s：距右 24（终端滚动条热区 12 + 间距 12）、距下 20；左 / 上取同样的边距。
pub const inset_x: f32 = 24;
pub const inset_y: f32 = 20;
/// O6（Pencil j8WXoF D）：卡片报告了顶部固定 chrome（KVM 工具栏）时，顶角锚点 = chrome 下沿 + 12。
pub const chrome_gap: f32 = 12;

fn right(corner: Corner) bool {
    return corner == .bottom_right or corner == .top_right;
}
fn bottom(corner: Corner) bool {
    return corner == .bottom_right or corner == .bottom_left;
}

/// 图标在 `area`（tab 内容区）里的矩形。图标位置稳定，卡片浮层给它让位（j8WXoF 待拍板 1 = A）：
/// 只有顶角看占角卡片的顶部 chrome 下沿 `top_chrome_bottom`（窗口坐标；null = 没有，仍是内容区顶 + 20）。
pub fn place(corner: Corner, area: Rect, top_chrome_bottom: ?f32) Rect {
    const x = if (right(corner)) area.x + area.w - inset_x - size else area.x + inset_x;
    const y = if (bottom(corner)) area.y + area.h - inset_y - size else if (top_chrome_bottom) |b| @max(area.y, b) + chrome_gap else area.y + inset_y;
    return .{ .x = x, .y = y, .w = size, .h = size };
}

/// 停靠的 AI 窗格让位（ai-redesign-c：停靠到分屏时 launcher 压在窗格输入区右下角）：图标的停放位置压在停靠的 AI
/// 窗格上时，改停在内容区去掉该窗格后剩下的那块的同一个角（列窗格去掉一列，行窗格去掉一行）。
/// 剩下的地方放不下图标（含边距）时不变。
pub fn avoidPane(corner: Corner, area: Rect, pane: ?Rect) Rect {
    const p = pane orelse return area;
    if (p.w <= 0 or p.h <= 0) return area;
    // The pane need not reach the corner pixel exactly (split gaps / insets): test the launcher's rest.
    const rest = place(corner, area, null);
    const overlaps = rest.x < p.x + p.w and rest.x + rest.w > p.x and rest.y < p.y + p.h and rest.y + rest.h > p.y;
    if (!overlaps) return area;
    var out = area;
    // A column pane (narrower than the body): drop its column; a row pane: drop its row.
    if (p.w < area.w * 0.9) {
        if (right(corner)) {
            out.w = p.x - area.x;
        } else {
            out.x = p.x + p.w;
            out.w = area.x + area.w - out.x;
        }
    } else if (p.h < area.h * 0.9) {
        if (bottom(corner)) {
            out.h = p.y - area.y;
        } else {
            out.y = p.y + p.h;
            out.h = area.y + area.h - out.y;
        }
    } else return area;
    if (out.w < size + 2 * inset_x or out.h < size + 2 * inset_y) return area;
    return out;
}

/// 内容区里贴着该角的一点：占着这个点的卡片就是"占角卡片"（分屏时只有它执行避让规则）。
pub fn cornerPoint(corner: Corner, area: Rect) struct { x: f32, y: f32 } {
    return .{ .x = if (right(corner)) area.x + area.w - 1 else area.x + 1, .y = if (bottom(corner)) area.y + area.h - 1 else area.y + 1 };
}

/// 键鼠被独占的远程画面与图标重叠时，图标淡到 0 并穿透指针（j8WXoF：捕获时让位）。
pub fn yields(launcher: Rect, captured: ?Rect) bool {
    const c = captured orelse return false;
    return c.w > 0 and c.h > 0 and launcher.x < c.x + c.w and launcher.x + launcher.w > c.x and launcher.y < c.y + c.h and launcher.y + launcher.h > c.y;
}

/// 松手吸附：图标中心离哪个角近就停到哪个角。
pub fn nearest(area: Rect, center_x: f32, center_y: f32) Corner {
    const is_right = center_x >= area.x + area.w / 2;
    const is_bottom = center_y >= area.y + area.h / 2;
    return if (is_bottom) (if (is_right) .bottom_right else .bottom_left) else (if (is_right) .top_right else .top_left);
}

/// 拖动中的位置：跟手，但限制在 tab 内容区里（wqZ1s："只在本 tab 内容区内拖"）。
pub fn dragged(start: Rect, dx: f32, dy: f32, area: Rect) Rect {
    const x = std.math.clamp(start.x + dx, area.x, @max(area.x, area.x + area.w - size));
    const y = std.math.clamp(start.y + dy, area.y, @max(area.y, area.y + area.h - size));
    return .{ .x = x, .y = y, .w = size, .h = size };
}

/// 待审批脉冲的节奏（Db7OS）：进入时 2 次，未处理每 60 s 再 1 次。
pub const ping_entry_count: u32 = 2;
pub const ping_repeat_ms: i64 = 60_000;

/// 待审批脉冲的计时：返回本帧要播放的次数（0 = 不播），并给出下一次唤醒的等待时间。
pub const Pinger = struct {
    since: ?i64 = null,
    last: i64 = 0,

    pub const Step = struct { rings: u32, wake_after_ms: ?i64 };

    pub fn step(self: *Pinger, approval: bool, now: i64) Step {
        if (!approval) {
            self.since = null;
            return .{ .rings = 0, .wake_after_ms = null };
        }
        if (self.since == null) {
            self.since = now;
            self.last = now;
            return .{ .rings = ping_entry_count, .wake_after_ms = ping_repeat_ms };
        }
        if (now - self.last >= ping_repeat_ms) {
            self.last = now;
            return .{ .rings = 1, .wake_after_ms = ping_repeat_ms };
        }
        return .{ .rings = 0, .wake_after_ms = ping_repeat_ms - (now - self.last) };
    }
};

test "launcher projection keeps the strip priority" {
    try std.testing.expectEqual(State.approval, project(.{ .pending = true, .busy = true, .failed = true, .unknown = true, .has_answer = true }));
    try std.testing.expectEqual(State.working, project(.{ .pending = false, .busy = true, .failed = true, .unknown = true, .has_answer = true }));
    try std.testing.expectEqual(State.failed, project(.{ .pending = false, .busy = false, .failed = true, .unknown = true, .has_answer = true }));
    try std.testing.expectEqual(State.unknown, project(.{ .pending = false, .busy = false, .failed = false, .unknown = true, .has_answer = true }));
    try std.testing.expectEqual(State.success, project(.{ .pending = false, .busy = false, .failed = false, .unknown = false, .has_answer = true }));
    try std.testing.expectEqual(State.idle, project(.{ .pending = false, .busy = false, .failed = false, .unknown = false, .has_answer = false }));
}

test "opening the panel clears failed, unknown and unread; approval waits for the decision" {
    var seen: Seen = .{};
    var facts: Facts = .{ .pending = false, .busy = false, .failed = false, .unknown = false };
    try std.testing.expectEqual(State.idle, project(seen.flags(facts)));
    // A run that finishes while the panel is hidden is unread.
    facts.busy = true;
    try std.testing.expectEqual(State.working, project(seen.flags(facts)));
    facts.busy = false;
    try std.testing.expectEqual(State.success, project(seen.flags(facts)));
    try std.testing.expectEqual(State.success, project(seen.flags(facts)));
    seen.acknowledge(facts);
    try std.testing.expectEqual(State.idle, project(seen.flags(facts)));
    // A run that finishes while the panel is open is read.
    facts.busy = true;
    seen.acknowledge(facts);
    facts.busy = false;
    seen.acknowledge(facts);
    try std.testing.expectEqual(State.idle, project(seen.flags(facts)));
    // Failure: shown until opened; a later, new failure shows again.
    facts.failed = true;
    try std.testing.expectEqual(State.failed, project(seen.flags(facts)));
    seen.acknowledge(facts);
    try std.testing.expectEqual(State.idle, project(seen.flags(facts)));
    facts.failed = false;
    _ = seen.flags(facts);
    facts.failed = true;
    try std.testing.expectEqual(State.failed, project(seen.flags(facts)));
    // A failed run is not a new answer.
    facts = .{ .pending = false, .busy = true, .failed = false, .unknown = false };
    _ = seen.flags(facts);
    facts = .{ .pending = false, .busy = false, .failed = true, .unknown = false };
    try std.testing.expectEqual(State.failed, project(seen.flags(facts)));
    facts.failed = false;
    facts.unknown = true;
    try std.testing.expectEqual(State.unknown, project(seen.flags(facts)));
    // Approval is not acknowledged by opening the panel.
    facts.pending = true;
    seen.acknowledge(facts);
    try std.testing.expectEqual(State.approval, project(seen.flags(facts)));
}

test "launcher rests 24 / 20 in the tab body corner; top corners sit 12 below the card's top chrome" {
    const area: Rect = .{ .x = 264, .y = 44, .w = 1170, .h = 850 };
    const br = place(.bottom_right, area, null);
    try std.testing.expectEqual(@as(f32, 264 + 1170 - 72), br.x);
    try std.testing.expectEqual(@as(f32, 44 + 850 - 68), br.y);
    try std.testing.expectEqual(@as(f32, 48), br.w);
    const tl = place(.top_left, area, null);
    try std.testing.expectEqual(@as(f32, 264 + 24), tl.x);
    try std.testing.expectEqual(@as(f32, 44 + 20), tl.y);
    // j8WXoF D: KVM toolbar 40 -> top anchor y 52 (tab body coordinates); bottom corners ignore it.
    try std.testing.expectEqual(@as(f32, 44 + 52), place(.top_right, area, 44 + 40).y);
    try std.testing.expectEqual(@as(f32, 44 + 52), place(.top_left, area, 44 + 40).y);
    try std.testing.expectEqual(br.y, place(.bottom_right, area, 44 + 40).y);
    // The icon never moves for card overlays any more: same corner, same rect.
    try std.testing.expectEqual(br, place(.bottom_right, area, null));
}

test "a docked AI pane in the resting corner: the launcher moves to the rest of the tab body" {
    const area: Rect = .{ .x = 0, .y = 40, .w = 1200, .h = 800 };
    // Docked on the right, full height: bottom-right rests at the left part's corner.
    const right_pane: Rect = .{ .x = 640, .y = 40, .w = 560, .h = 800 };
    const avoided = avoidPane(.bottom_right, area, right_pane);
    try std.testing.expectEqual(@as(f32, 640), avoided.w);
    const rest = place(.bottom_right, avoided, null);
    try std.testing.expect(rest.x + rest.w <= right_pane.x - inset_x + 0.01);
    try std.testing.expectEqual(place(.bottom_right, area, null).y, rest.y);
    // The bottom-left corner is not in the pane: unchanged.
    try std.testing.expectEqual(area, avoidPane(.bottom_left, area, right_pane));
    // Docked at the bottom, full width: rests above it.
    const bottom_pane: Rect = .{ .x = 0, .y = 440, .w = 1200, .h = 400 };
    const above = avoidPane(.bottom_right, area, bottom_pane);
    try std.testing.expectEqual(@as(f32, 400), above.h);
    // Left pane, full height: bottom-left moves right of it.
    const left_pane: Rect = .{ .x = 0, .y = 40, .w = 500, .h = 800 };
    try std.testing.expectEqual(@as(f32, 500), avoidPane(.bottom_left, area, left_pane).x);
    // Nothing left that holds the icon: unchanged.
    try std.testing.expectEqual(area, avoidPane(.bottom_right, area, .{ .x = 50, .y = 40, .w = 1150, .h = 800 }));
    try std.testing.expectEqual(area, avoidPane(.bottom_right, area, null));
}

test "the corner card is the one under the corner point; capture yields only on overlap" {
    const area: Rect = .{ .x = 100, .y = 50, .w = 800, .h = 600 };
    try std.testing.expectEqual(@as(f32, 899), cornerPoint(.bottom_right, area).x);
    try std.testing.expectEqual(@as(f32, 649), cornerPoint(.bottom_right, area).y);
    try std.testing.expectEqual(@as(f32, 101), cornerPoint(.top_left, area).x);
    const icon = place(.bottom_right, area, null);
    try std.testing.expect(yields(icon, .{ .x = 100, .y = 90, .w = 800, .h = 560 }));
    try std.testing.expect(!yields(icon, .{ .x = 100, .y = 90, .w = 400, .h = 560 }));
    try std.testing.expect(!yields(icon, null));
}

test "dragging stays inside the tab body and snaps to the nearest corner" {
    const area: Rect = .{ .x = 100, .y = 50, .w = 800, .h = 600 };
    const start = place(.bottom_right, area, null);
    const far = dragged(start, -5000, -5000, area);
    try std.testing.expectEqual(@as(f32, 100), far.x);
    try std.testing.expectEqual(@as(f32, 50), far.y);
    try std.testing.expectEqual(Corner.top_left, nearest(area, far.x + 24, far.y + 24));
    try std.testing.expectEqual(Corner.bottom_left, nearest(area, 200, 600));
    try std.testing.expectEqual(Corner.top_right, nearest(area, 800, 100));
    try std.testing.expectEqual(Corner.bottom_right, nearest(area, 800, 600));
}

test "approval pings twice on entry, then once a minute" {
    var p: Pinger = .{};
    try std.testing.expectEqual(@as(u32, 0), p.step(false, 0).rings);
    try std.testing.expectEqual(@as(u32, 2), p.step(true, 1000).rings);
    const quiet = p.step(true, 31_000);
    try std.testing.expectEqual(@as(u32, 0), quiet.rings);
    try std.testing.expectEqual(@as(?i64, 30_000), quiet.wake_after_ms);
    try std.testing.expectEqual(@as(u32, 1), p.step(true, 61_000).rings);
    try std.testing.expectEqual(@as(u32, 0), p.step(false, 62_000).rings);
    try std.testing.expectEqual(@as(u32, 2), p.step(true, 63_000).rings);
}
