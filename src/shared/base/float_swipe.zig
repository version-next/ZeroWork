//! 下滑收起（Pencil AveHg「Row · 下滑收起」，规则帧 JmcNv）：浮动卡片的一项可枚举交互
//! (`float_card.Interaction.swipe_collapse`)，判定与数值全部在这里，浮动层
//! (`shared/ui/float_card/float_layer.zig`) 只负责把拖动事件喂进来、执行判定结果。
//!
//! 规则（稿上原文的落地）：
//! - 适用：带顶部把手（`float.drag` / Drag Trigger）且能拖动的浮动卡片；只有在把手上按下才算。
//!   卡片支持“收起”（`minimize`）时才会收起（`deriveInto`），否则下甩只当普通拖动、按稿弹回。
//! - 前提：按下时面板贴底——底边到视图底的距离 ≤ `docked_max_gap`（24）。不贴底时是普通拖动。
//! - 贴底拖动时面板跟手、可以被拖出视图底；松手时满足任一即收起：
//!   ① 向下速度 ≥ `fling_velocity`（900 px/s，取最后 `sample_window_ms` = 80ms 的采样）；
//!   ② 超出视图底的部分 ≥ 自身高度 × `overshoot_fraction`（1/3）。
//!   都不满足：弹回贴底位置（`spring_ms` 180ms，ease-out）。
//! - 误触保护：总位移 < `min_distance`（8px）不判定；横向位移大于纵向按普通拖动处理。
//! - 收起：继承松手速度继续下滑出视图，同时 opacity 1→0（`collapse_ms` 220ms，ease-in）；结束后移除。
//!   收起的目标（如 AI 的 launcher 图标）在锚角淡入：`icon_in_ms` 160ms，延迟 `icon_in_delay_ms`
//!   120ms，scale `icon_from_scale` 0.92→1。
//! - 减少动态效果：不做位移动画，只做 `reduced_fade_ms`（120ms）淡出 / 淡入。
//!
//! 惯性（规则帧 JmcNv：“面板不贴底时，下甩只是普通拖动 + 惯性，不收起”）：适用于所有浮动卡片的普通拖动。
//! - 判定顺序：先判下滑收起（`decide`）；结果是 `settle`（普通拖动结束、没有要弹回的偏移）时才判惯性（`glide`）。
//! - 速度：与下滑收起同一套采样（最后 `sample_window_ms` = 80ms），取 x、y 两个分量，合速度超过
//!   `glide_max_velocity` 时按比例压到它。
//! - 不做惯性：指针总位移 < `min_distance`（8px）、合速度 < `glide_min_velocity`、开启“减少动态效果”。
//! - 曲线：指数衰减（macOS / UIKit 滚动减速的模型，`glide_deceleration` 是每毫秒保留的速度比例，
//!   0.99 即 UIScrollView 的 `.fast`）：位移 = v / k · (1 − e^(−k·t))，k = −ln(rate) × 1000（1/s）。
//!   滑行最长 `glide_max_ms`，此时剩余速度 < 初速的千分之一，停在原地不可察觉。
//! - 范围：夹在拖动区域内（标题栏以下的整个窗口，内缩 8，即浮动层 `region`），x、y 各自独立：某一方向
//!   碰到边缘就在碰到的那一刻停在边缘（不回弹、不过冲），另一方向照常减速。
//! - 停下的位置就是用户放下的位置（按“记住位置”规则保存）；滑行中再次按下立即在当前位置接管。
//!
//! 坐标是窗口内容坐标（与 `float_card.Rect` 相同），y 向下为正，速度单位 px/s。
const std = @import("std");
const float_card = @import("float_card.zig");

pub const Rect = float_card.Rect;

/// CSS cubic-bezier(x1, y1, x2, y2)；浮动层转成 zenit `Easing.cubic_bezier`。
pub const Curve = struct {
    x1: f32,
    y1: f32,
    x2: f32,
    y2: f32,

    pub const ease_in: Curve = .{ .x1 = 0.42, .y1 = 0, .x2 = 1, .y2 = 1 };
    pub const ease_out: Curve = .{ .x1 = 0, .y1 = 0, .x2 = 0.58, .y2 = 1 };
};

/// 下滑收起的全部数值（稿 AveHg / JmcNv）。浮动层与收起目标（launcher）都从这里读，不在别处写死。
pub const Tokens = struct {
    /// 贴底：面板底边到视图底 ≤ 这个距离（默认锚右下、边距 12 时满足）。
    docked_max_gap: f32 = 24,
    /// 总位移小于它不判定（误触保护）。
    min_distance: f32 = 8,
    /// 松手时向下速度 ≥ 它即收起（px/s）。
    fling_velocity: f32 = 900,
    /// 速度取最后这段时间内的采样（毫秒）。
    sample_window_ms: f32 = 80,
    /// 超出视图底 ≥ 自身高度 × 它即收起。
    overshoot_fraction: f32 = 1.0 / 3.0,
    /// 收起：下滑 + 淡出。
    collapse_ms: f32 = 220,
    collapse_curve: Curve = Curve.ease_in,
    /// 弹回贴底位置。
    spring_ms: f32 = 180,
    spring_curve: Curve = Curve.ease_out,
    /// 收起目标（图标）在锚角淡入。
    icon_in_ms: f32 = 160,
    icon_in_delay_ms: f32 = 120,
    icon_from_scale: f32 = 0.92,
    icon_in_curve: Curve = Curve.ease_out,
    /// 减少动态效果：只做淡出 / 淡入。
    reduced_fade_ms: f32 = 120,

    /// 惯性：每毫秒保留的速度比例（指数衰减系数；0.99 = UIScrollView `.fast`）。
    glide_deceleration: f32 = 0.99,
    /// 惯性：松手合速度低于它不滑行（px/s）。
    glide_min_velocity: f32 = 300,
    /// 惯性：松手合速度的上限（px/s），超过按比例压到它。
    glide_max_velocity: f32 = 6000,
    /// 惯性：滑行最长时长（毫秒）。
    glide_max_ms: f32 = 700,
};

pub const tokens: Tokens = .{};

/// 卡片类型是否参与下滑收起：从 Descriptor 推出，从不由卡片自己声明——能拖动（`move`）且支持
/// “收起”（`minimize`）。不支持收起的卡片（终端会话卡片、会话记录、fixture）下甩只是普通拖动加弹回。
pub fn collapses(descriptor: float_card.Descriptor) bool {
    return descriptor.supports(.move) and descriptor.supports(.minimize);
}

/// 把推导结果写进 `descriptor.interactions`（覆盖任何手写的值）。
pub fn deriveInto(descriptor: *float_card.Descriptor) void {
    descriptor.interactions.setPresent(.swipe_collapse, collapses(descriptor.*));
}

/// “视图底”：卡片能停靠的最低边——所属 tab 内容区的底边与浮动区域底边中较低的那个。
pub fn viewBottom(content: Rect, region: Rect) f32 {
    return @max(content.y + content.height, region.y + region.height);
}

/// 面板贴底：底边到视图底的距离 ≤ `docked_max_gap`（已经压过视图底也算）。
pub fn docked(t: Tokens, rect: Rect, view_bottom: f32) bool {
    return view_bottom - (rect.y + rect.height) <= t.docked_max_gap;
}

/// 拖动采样：按时间记录指针位置，松手时取最后 `sample_window_ms` 内的平均速度（下滑收起用 y，
/// 普通拖动的惯性用 x、y 两个分量）。
pub const Sampler = struct {
    const capacity = 32;
    pub const Sample = struct { t_ns: u64, x: f32, y: f32 };

    buffer: [capacity]Sample = undefined,
    len: usize = 0,
    /// 下一个写入位置（环形）。
    head: usize = 0,

    pub fn reset(self: *Sampler) void {
        self.len = 0;
        self.head = 0;
    }

    pub fn add(self: *Sampler, t_ns: u64, x: f32, y: f32) void {
        if (!std.math.isFinite(x) or !std.math.isFinite(y)) return;
        // 时钟回退时按同一时刻记（不让速度翻号）。
        const t = if (self.latest()) |last| @max(t_ns, last.t_ns) else t_ns;
        self.buffer[self.head] = .{ .t_ns = t, .x = x, .y = y };
        self.head = (self.head + 1) % capacity;
        self.len = @min(self.len + 1, capacity);
    }

    fn at(self: *const Sampler, age: usize) Sample {
        return self.buffer[(self.head + capacity - 1 - age) % capacity];
    }

    pub fn latest(self: *const Sampler) ?Sample {
        return if (self.len == 0) null else self.at(0);
    }

    /// 向下为正的速度（px/s）：最新样本与窗口内最早样本之差除以时间差。窗口里只有一个样本
    /// （松手前停顿超过窗口）时速度为 0。
    pub fn velocity(self: *const Sampler, window_ms: f32) f32 {
        return self.velocity2(window_ms).y;
    }

    /// 两个分量的速度（px/s，向右、向下为正），窗口与 `velocity` 相同。
    pub fn velocity2(self: *const Sampler, window_ms: f32) Velocity {
        if (self.len < 2) return .{};
        const last = self.at(0);
        const window_ns: u64 = @intFromFloat(@max(0, window_ms) * std.time.ns_per_ms);
        var oldest = last;
        var age: usize = 1;
        while (age < self.len) : (age += 1) {
            const s = self.at(age);
            if (last.t_ns - s.t_ns > window_ns) break;
            oldest = s;
        }
        const dt_ns = last.t_ns - oldest.t_ns;
        if (dt_ns == 0) return .{};
        const dt_s = @as(f32, @floatFromInt(dt_ns)) / std.time.ns_per_s;
        return .{ .x = (last.x - oldest.x) / dt_s, .y = (last.y - oldest.y) / dt_s };
    }
};

/// 速度（px/s），向右、向下为正。
pub const Velocity = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn speed(self: Velocity) f32 {
        return std.math.hypot(self.x, self.y);
    }
};

/// 松手瞬间的输入。
pub const Release = struct {
    /// 按下时面板贴底（`docked`）。
    docked: bool,
    /// 卡片支持收起（`collapses`）。
    collapsible: bool,
    /// 指针总位移（松手点 − 按下点）。
    dx: f32,
    dy: f32,
    /// `Sampler.velocity`，向下为正。
    velocity: f32,
    /// 面板底边超出视图底的距离（≤ 0 = 没超出）。
    beyond: f32,
    /// 面板自身高度。
    height: f32,
    /// 面板此刻相对贴底位置向下偏出的距离（弹回要走的路）。
    offset: f32,
};

pub const Decision = enum {
    /// 收起：下滑淡出，交给卡片自己的收起语义。
    collapse,
    /// 弹回贴底位置。
    spring_back,
    /// 普通拖动结束，什么都不用做。
    settle,
};

pub fn decide(t: Tokens, r: Release) Decision {
    const rest: Decision = if (r.offset > 0.5) .spring_back else .settle;
    if (!r.docked) return rest;
    // 误触保护：位移太小、或横向为主，都按普通拖动处理。
    if (std.math.hypot(r.dx, r.dy) < t.min_distance) return rest;
    if (@abs(r.dx) > @abs(r.dy)) return rest;
    if (!r.collapsible) return rest;
    if (r.velocity >= t.fling_velocity) return .collapse;
    if (r.height > 0 and r.beyond >= r.height * t.overshoot_fraction) return .collapse;
    return rest;
}

/// 收起时的下滑：从当前位置一直滑出 `exit_y`（视图 / 窗口底），继承松手速度。
/// 路程 = max(滑出所需, 速度 × 时长)；曲线从 ease-in 出发，把起点斜率抬到松手速度
/// （速度 × 时长 ≥ 路程时就是匀速，即完全继承；慢拖时退回 ease-in 加速滑出）。
pub const Slide = struct { distance: f32, curve: Curve, duration_ms: f32 };

pub fn slideOut(t: Tokens, velocity: f32, top: f32, exit_y: f32) Slide {
    const base = t.collapse_curve;
    const duration_s = t.collapse_ms / 1000;
    const carried = @max(0, velocity) * duration_s;
    const distance = @max(@max(0, exit_y - top), carried);
    var curve = base;
    if (distance > 0 and base.x1 > 0) curve.y1 = @min(base.x1, @max(base.y1, base.x1 * carried / distance));
    return .{ .distance = distance, .curve = curve, .duration_ms = t.collapse_ms };
}

/// 惯性衰减率 k（1/s）：速度 v(t) = v₀ · e^(−k·t)。
pub fn glideRate(t: Tokens) f32 {
    const rate = std.math.clamp(t.glide_deceleration, 0.5, 0.99999);
    return -@log(rate) * 1000;
}

/// 指数衰减在 `s` 秒时走过的距离（不夹取）。
pub fn decayDistance(t: Tokens, velocity: f32, s: f32) f32 {
    const k = glideRate(t);
    return velocity / k * (1 - @exp(-k * @max(0, s)));
}

/// 截断在 a = k·T 处的指数衰减，归一化到 [0, 1]×[0, 1]：f(s) = (1 − e^(−a·s)) / (1 − e^(−a))。
pub fn decayProgress(a: f32, s: f32) f32 {
    if (a < 1e-4) return s;
    return (1 - @exp(-a * s)) / (1 - @exp(-a));
}

/// 上面这段衰减的三次贝塞尔近似（zenit 动画只收 cubic-bezier）：两端点精确；起点切线即初速
/// （控制点 y 不超过 1 时完全继承松手速度）；终点切线为剩余速度。控制点 y 都在 [0, 1] 内，
/// 所以曲线单调、不过冲。对 a ≤ 7（最长 700ms 的整段衰减）最大误差约为路程的 1.5%。
pub fn decayCurve(a: f32) Curve {
    const aa = @max(0, a);
    const h0 = 1 / (3 + aa / 2);
    const h1 = 1.0 / 3.0 + aa / 20;
    const e = @exp(-aa);
    const s0: f32 = if (aa < 1e-4) 1 else aa / (1 - e);
    const s1: f32 = if (aa < 1e-4) 1 else aa * e / (1 - e);
    return .{ .x1 = h0, .y1 = @min(1, h0 * s0), .x2 = 1 - h1, .y2 = std.math.clamp(1 - h1 * s1, 0, 1) };
}

/// 一个方向的惯性滑行：位移（带符号）、时长与曲线。`distance == 0` = 这个方向不动。
pub const GlideAxis = struct {
    distance: f32 = 0,
    duration_ms: f32 = 0,
    curve: Curve = Curve.ease_out,

    pub fn moves(self: GlideAxis) bool {
        return self.distance != 0 and self.duration_ms > 0;
    }
};

/// 一个方向：从 `position` 以 `velocity` 出发按指数衰减滑行，最长 `glide_max_ms`；`[lo, hi]` 是这个方向
/// 允许的位置（拖动区域减去卡片尺寸）。碰到边缘就在碰到的那一刻停在边缘上。
pub fn glideAxis(t: Tokens, velocity: f32, position: f32, lo: f32, hi: f32) GlideAxis {
    if (!std.math.isFinite(velocity) or !std.math.isFinite(position) or velocity == 0 or hi < lo) return .{};
    const k = glideRate(t);
    const max_s = @max(0, t.glide_max_ms) / 1000;
    const full = decayDistance(t, velocity, max_s);
    const edge = if (velocity > 0) hi else lo;
    // 剩到边缘的路（与速度同号）；已经在边缘上（或在外面）就不动。
    const room = edge - position;
    if (room * velocity <= 0) return .{};
    var distance = full;
    var duration_s = max_s;
    if (@abs(full) >= @abs(room)) {
        // 在 t_hit 碰到边缘：room = v/k · (1 − e^(−k·t_hit))。
        const ratio = std.math.clamp(1 - k * room / velocity, 1e-6, 1);
        duration_s = @min(max_s, -@log(ratio) / k);
        distance = room;
    }
    if (@abs(distance) < 0.5 or duration_s <= 0) return .{};
    return .{ .distance = distance, .duration_ms = duration_s * 1000, .curve = decayCurve(k * duration_s) };
}

/// 普通拖动松手时的惯性输入。
pub const GlideRelease = struct {
    /// 指针总位移（松手点 − 按下点）。
    dx: f32,
    dy: f32,
    /// `Sampler.velocity2`。
    velocity: Velocity,
    /// 卡片此刻的矩形（窗口内容坐标）。
    rect: Rect,
    /// 拖动区域（浮动层 `region`：标题栏以下的整个窗口，内缩 8）。
    region: Rect,
    /// 系统“减少动态效果”。
    reduced_motion: bool,
};

pub const Glide = struct {
    x: GlideAxis = .{},
    y: GlideAxis = .{},

    pub fn moves(self: Glide) bool {
        return self.x.moves() or self.y.moves();
    }

    /// 停下的位置（窗口内容坐标）。
    pub fn target(self: Glide, from: Rect) Rect {
        var r = from;
        r.x += self.x.distance;
        r.y += self.y.distance;
        return r;
    }

    pub fn duration_ms(self: Glide) f32 {
        return @max(self.x.duration_ms, self.y.duration_ms);
    }
};

/// 普通拖动松手：滑不滑、往哪滑、滑多久。null = 不做惯性，停在原地。
pub fn glide(t: Tokens, r: GlideRelease) ?Glide {
    if (r.reduced_motion) return null;
    if (std.math.hypot(r.dx, r.dy) < t.min_distance) return null;
    var v = r.velocity;
    if (!std.math.isFinite(v.x) or !std.math.isFinite(v.y)) return null;
    const speed = v.speed();
    if (speed < t.glide_min_velocity) return null;
    if (speed > t.glide_max_velocity) {
        const scale = t.glide_max_velocity / speed;
        v.x *= scale;
        v.y *= scale;
    }
    const result: Glide = .{
        .x = glideAxis(t, v.x, r.rect.x, r.region.x, r.region.x + r.region.width - r.rect.width),
        .y = glideAxis(t, v.y, r.rect.y, r.region.y, r.region.y + r.region.height - r.rect.height),
    };
    return if (result.moves()) result else null;
}

// ── Tests ────────────────────────────────────────────────────────────────────────────────

const testing = std.testing;
const ms = std.time.ns_per_ms;

fn release(over: anytype) Release {
    var r: Release = .{ .docked = true, .collapsible = true, .dx = 0, .dy = 120, .velocity = 0, .beyond = 0, .height = 600, .offset = 120 };
    inline for (@typeInfo(@TypeOf(over)).@"struct".field_names) |name| @field(r, name) = @field(over, name);
    return r;
}

test "swipe tokens: the numbers of the AveHg rule frame" {
    try testing.expectEqual(@as(f32, 24), tokens.docked_max_gap);
    try testing.expectEqual(@as(f32, 8), tokens.min_distance);
    try testing.expectEqual(@as(f32, 900), tokens.fling_velocity);
    try testing.expectEqual(@as(f32, 80), tokens.sample_window_ms);
    try testing.expectApproxEqAbs(@as(f32, 1.0 / 3.0), tokens.overshoot_fraction, 1e-6);
    try testing.expectEqual(@as(f32, 220), tokens.collapse_ms);
    try testing.expectEqual(@as(f32, 180), tokens.spring_ms);
    try testing.expectEqual(@as(f32, 160), tokens.icon_in_ms);
    try testing.expectEqual(@as(f32, 120), tokens.icon_in_delay_ms);
    try testing.expectEqual(@as(f32, 0.92), tokens.icon_from_scale);
    try testing.expectEqual(@as(f32, 120), tokens.reduced_fade_ms);
    try testing.expectEqualDeep(Curve.ease_in, tokens.collapse_curve);
    try testing.expectEqualDeep(Curve.ease_out, tokens.spring_curve);
}

test "swipe availability is derived from minimize (and move), never declared" {
    var d = float_card.fixture;
    d.interactions = .initMany(&.{ .move, .minimize });
    try testing.expect(collapses(d));
    d.interactions = .initMany(&.{ .move, .swipe_collapse });
    deriveInto(&d);
    try testing.expect(!d.supports(.swipe_collapse));
    d.interactions = .initMany(&.{ .minimize, .move });
    deriveInto(&d);
    try testing.expect(d.supports(.swipe_collapse));
    d.interactions = .initMany(&.{.minimize});
    try testing.expect(!collapses(d));
}

test "swipe docked: bottom within 24 of the view bottom (default 12 margin counts), farther does not" {
    const view_bottom: f32 = 850;
    try testing.expect(docked(tokens, .{ .x = 0, .y = 198, .width = 420, .height = 640 }, view_bottom)); // 12
    try testing.expect(docked(tokens, .{ .x = 0, .y = 186, .width = 420, .height = 640 }, view_bottom)); // 24
    try testing.expect(!docked(tokens, .{ .x = 0, .y = 185, .width = 420, .height = 640 }, view_bottom)); // 25
    try testing.expect(docked(tokens, .{ .x = 0, .y = 230, .width = 420, .height = 640 }, view_bottom)); // past it
    try testing.expectEqual(@as(f32, 900), viewBottom(.{ .x = 0, .y = 44, .width = 1, .height = 856 }, .{ .x = 0, .y = 52, .width = 1, .height = 840 }));
    try testing.expectEqual(@as(f32, 892), viewBottom(.{ .x = 0, .y = 44, .width = 1, .height = 820 }, .{ .x = 0, .y = 52, .width = 1, .height = 840 }));
}

test "swipe sampler: velocity over the last 80 ms only; a pause before release reads 0" {
    var s: Sampler = .{};
    try testing.expectEqual(@as(f32, 0), s.velocity(80));
    // Slow start (100 px/s) then a fast flick (2000 px/s) in the last 60 ms.
    var y: f32 = 0;
    var t: u64 = 0;
    for (0..20) |_| {
        s.add(t, 0, y);
        t += 20 * ms;
        y += 2;
    }
    s.add(t, 0, y);
    try testing.expectApproxEqAbs(@as(f32, 100), s.velocity(80), 1);
    for (0..3) |_| {
        t += 20 * ms;
        y += 40;
        s.add(t, 0, y);
    }
    try testing.expectApproxEqAbs(@as(f32, 1525), s.velocity(80), 1); // (2 + 120) px over 80 ms
    try testing.expectApproxEqAbs(@as(f32, 2000), s.velocity(60), 1);
    // Holding still for longer than the window: nothing left to fling.
    s.add(t + 120 * ms, 0, y);
    try testing.expectEqual(@as(f32, 0), s.velocity(80));
    // Upward is negative; a clock that steps back never flips the sign.
    s.reset();
    s.add(10 * ms, 0, 100);
    s.add(5 * ms, 0, 80);
    try testing.expectEqual(@as(f32, 0), s.velocity(80));
    s.add(30 * ms, 0, 60);
    try testing.expect(s.velocity(80) < 0);
    // More samples than the ring holds: still the newest window.
    s.reset();
    for (0..100) |i| s.add(@as(u64, i) * 10 * ms, 0, @as(f32, @floatFromInt(i)) * 5);
    try testing.expectApproxEqAbs(@as(f32, 500), s.velocity(80), 1);
}

test "swipe decide: fast fling or a third past the bottom collapses; otherwise spring back" {
    // ① velocity ≥ 900 px/s.
    try testing.expectEqual(Decision.collapse, decide(tokens, release(.{ .velocity = 900 })));
    try testing.expectEqual(Decision.spring_back, decide(tokens, release(.{ .velocity = 899 })));
    // ② beyond ≥ height / 3, however slowly.
    try testing.expectEqual(Decision.collapse, decide(tokens, release(.{ .velocity = 50, .beyond = 200, .height = 600 })));
    try testing.expectEqual(Decision.spring_back, decide(tokens, release(.{ .velocity = 50, .beyond = 199, .height = 600 })));
    // Upward fling never collapses.
    try testing.expectEqual(Decision.spring_back, decide(tokens, release(.{ .velocity = -3000 })));
}

test "swipe decide: < 8 px, horizontal-dominant, not docked and not collapsible never collapse" {
    // < 8 px total: no decision (a press-and-release that barely moved).
    try testing.expectEqual(Decision.spring_back, decide(tokens, release(.{ .dx = 3, .dy = 6, .velocity = 5000, .offset = 6 })));
    try testing.expectEqual(Decision.settle, decide(tokens, release(.{ .dx = 3, .dy = 6, .velocity = 5000, .offset = 0 })));
    // Horizontal displacement larger than vertical: an ordinary drag.
    try testing.expectEqual(Decision.spring_back, decide(tokens, release(.{ .dx = 200, .dy = 150, .velocity = 4000, .beyond = 400 })));
    try testing.expectEqual(Decision.collapse, decide(tokens, release(.{ .dx = 150, .dy = 200, .velocity = 4000 })));
    // Not docked at press: ordinary drag + no collapse.
    try testing.expectEqual(Decision.settle, decide(tokens, release(.{ .docked = false, .velocity = 4000, .beyond = 400, .offset = 0 })));
    // A card without minimize (terminal session card): the fling springs back.
    try testing.expectEqual(Decision.spring_back, decide(tokens, release(.{ .collapsible = false, .velocity = 4000, .beyond = 400 })));
    try testing.expectEqual(Decision.settle, decide(tokens, release(.{ .collapsible = false, .velocity = 4000, .offset = 0 })));
}

test "swipe slide out: inherits the release velocity, always leaves the view" {
    // Fast fling: travels velocity × 220 ms at constant speed (curve starts at the release slope).
    const fast = slideOut(tokens, 3000, 400, 900);
    try testing.expectApproxEqAbs(@as(f32, 660), fast.distance, 0.01);
    try testing.expectApproxEqAbs(fast.curve.x1, fast.curve.y1, 1e-6);
    // Initial speed = distance / duration × (y1 / x1) = release velocity.
    try testing.expectApproxEqAbs(@as(f32, 3000), fast.distance / (fast.duration_ms / 1000) * (fast.curve.y1 / fast.curve.x1), 0.5);
    // Slow drag past the third: must still leave the view; starts at the slow velocity, then ease-in.
    const slow = slideOut(tokens, 300, 500, 900);
    try testing.expectApproxEqAbs(@as(f32, 400), slow.distance, 0.01);
    try testing.expect(slow.curve.y1 > 0 and slow.curve.y1 < slow.curve.x1);
    try testing.expectApproxEqAbs(@as(f32, 300), slow.distance / (slow.duration_ms / 1000) * (slow.curve.y1 / slow.curve.x1), 0.5);
    // No velocity: plain ease-in.
    try testing.expectEqualDeep(Curve.ease_in, slideOut(tokens, 0, 500, 900).curve);
    try testing.expectEqual(@as(f32, 220), slow.duration_ms);
}

// ── Glide (inertia of an ordinary drag) ──────────────────────────────────────────────────────

const test_region: Rect = .{ .x = 248, .y = 52, .width = 1184, .height = 840 };

fn glideRelease(over: anytype) GlideRelease {
    var r: GlideRelease = .{ .dx = 120, .dy = 0, .velocity = Velocity{ .x = 2000 }, .rect = Rect{ .x = 500, .y = 200, .width = 400, .height = 300 }, .region = test_region, .reduced_motion = false };
    inline for (@typeInfo(@TypeOf(over)).@"struct".field_names) |name| @field(r, name) = @field(over, name);
    return r;
}

/// Evaluate a CSS cubic-bezier at progress `x` (bisection on the x polynomial).
fn bezierAt(c: Curve, x: f32) f32 {
    var lo: f32 = 0;
    var hi: f32 = 1;
    var u: f32 = x;
    for (0..60) |_| {
        u = (lo + hi) / 2;
        const xu = 3 * (1 - u) * (1 - u) * u * c.x1 + 3 * (1 - u) * u * u * c.x2 + u * u * u;
        if (xu < x) lo = u else hi = u;
    }
    return 3 * (1 - u) * (1 - u) * u * c.y1 + 3 * (1 - u) * u * u * c.y2 + u * u * u;
}

test "glide tokens: decay rate, thresholds and the longest glide are tokens" {
    try testing.expectEqual(@as(f32, 0.99), tokens.glide_deceleration);
    try testing.expectEqual(@as(f32, 300), tokens.glide_min_velocity);
    try testing.expectEqual(@as(f32, 6000), tokens.glide_max_velocity);
    try testing.expectEqual(@as(f32, 700), tokens.glide_max_ms);
    // k = −ln(0.99) × 1000 ≈ 10.05 / s: a 2000 px/s release travels ≈ 199 px.
    try testing.expectApproxEqAbs(@as(f32, 10.05), glideRate(tokens), 0.01);
    try testing.expectApproxEqAbs(@as(f32, 199), decayDistance(tokens, 2000, 0.7), 0.5);
}

test "glide decay curve: exponential decay, velocity falls by e^(−k·t), the bezier follows it without overshoot" {
    const k = glideRate(tokens);
    // Velocity after t is v₀·e^(−kt): the distance slope at 100 ms is 0.99^100 of the start.
    const v0: f32 = 3000;
    const h: f32 = 1e-3;
    const slope = (decayDistance(tokens, v0, 0.1 + h) - decayDistance(tokens, v0, 0.1 - h)) / (2 * h);
    try testing.expectApproxEqRel(v0 * std.math.pow(f32, 0.99, 100), slope, 1e-2);
    // Monotone, decelerating, never past the full distance v/k.
    var last: f32 = 0;
    var last_step: f32 = std.math.inf(f32);
    for (1..50) |i| {
        const d = decayDistance(tokens, v0, @as(f32, @floatFromInt(i)) * 0.02);
        try testing.expect(d > last and d < v0 / k);
        try testing.expect(d - last <= last_step + 1e-3);
        last_step = d - last;
        last = d;
    }
    // The bezier stays within ~1.5% of the decay for every truncation up to the full 700 ms glide,
    // ends exactly at 1, starts at the release velocity while y1 < 1, and never exceeds 1.
    for ([_]f32{ 0.3, 1, 2, 3, 4, 5, 6, k * 0.7 }) |a| {
        const c = decayCurve(a);
        try testing.expect(c.y1 >= 0 and c.y1 <= 1 and c.y2 >= 0 and c.y2 <= 1);
        try testing.expectApproxEqAbs(@as(f32, 1), bezierAt(c, 1), 1e-4);
        var prev: f32 = 0;
        for (1..41) |i| {
            const s = @as(f32, @floatFromInt(i)) / 40;
            const y = bezierAt(c, s);
            try testing.expect(y >= prev - 1e-5 and y <= 1 + 1e-5);
            try testing.expectApproxEqAbs(decayProgress(a, s), y, 0.016);
            prev = y;
        }
        if (c.y1 < 1) try testing.expectApproxEqRel(a / (1 - @exp(-a)), c.y1 / c.x1, 1e-4);
    }
}

test "glide: a fast release slides ≈ v/k, decelerating over 700 ms" {
    const g = glide(tokens, glideRelease(.{})).?;
    try testing.expect(!g.y.moves());
    try testing.expectApproxEqAbs(decayDistance(tokens, 2000, 0.7), g.x.distance, 0.01);
    try testing.expectEqual(@as(f32, 700), g.x.duration_ms);
    try testing.expectEqual(@as(f32, 700), g.duration_ms());
    try testing.expectApproxEqAbs(@as(f32, 699), g.target(glideRelease(.{}).rect).x, 0.5);
    // Diagonal: both axes decay together along the release direction.
    const d = glide(tokens, glideRelease(.{ .dx = -60, .dy = -80, .velocity = Velocity{ .x = -900, .y = -1200 } })).?;
    try testing.expectApproxEqRel(@as(f32, 0.75), d.x.distance / d.y.distance, 1e-3);
    try testing.expect(d.x.distance < 0 and d.y.distance < 0);
    // Too fast is capped (direction kept).
    const capped = glide(tokens, glideRelease(.{ .rect = Rect{ .x = 248, .y = 200, .width = 400, .height = 300 }, .velocity = Velocity{ .x = 60000 } })).?;
    try testing.expectApproxEqAbs(decayDistance(tokens, 6000, 0.7), capped.x.distance, 0.5);
}

test "glide edges: stops on the drag region edge at the moment it reaches it, no overshoot, no bounce" {
    // 300 px of room on the right (region right 1432 − width 400 − x 732); 5900 px/s would go ≈ 587.
    const r = glideRelease(.{ .rect = Rect{ .x = 732, .y = 200, .width = 400, .height = 300 }, .velocity = Velocity{ .x = 5900, .y = 500 } });
    const g = glide(tokens, r).?;
    try testing.expectApproxEqAbs(@as(f32, 300), g.x.distance, 1e-3);
    try testing.expectEqual(test_region.x + test_region.width, g.target(r.rect).x + r.rect.width);
    // Reached the edge before 700 ms, at the time the decay covers 300 px: no slower creep along it.
    const k = glideRate(tokens);
    const t_hit = -@log(1 - k * 300 / 5900) / k;
    try testing.expectApproxEqAbs(t_hit * 1000, g.x.duration_ms, 0.5);
    try testing.expect(g.x.duration_ms < 700);
    try testing.expectApproxEqAbs(@as(f32, 300), decayDistance(tokens, 5900, g.x.duration_ms / 1000), 0.5);
    // The other axis decays on its own (it does not hit an edge).
    try testing.expectEqual(@as(f32, 700), g.y.duration_ms);
    try testing.expectApproxEqAbs(decayDistance(tokens, 500, 0.7), g.y.distance, 0.01);
    // The curve of the clamped axis ends exactly at the edge and never passes it.
    var s: f32 = 0;
    while (s <= 1) : (s += 0.01) try testing.expect(bezierAt(g.x.curve, s) <= 1 + 1e-5);
    // Already on the edge in the release direction: that axis does not move.
    const on_edge = glideRelease(.{ .rect = Rect{ .x = 1032, .y = 592, .width = 400, .height = 300 }, .velocity = Velocity{ .x = 3000, .y = 3000 } });
    try testing.expect(glide(tokens, on_edge) == null);
    // Away from that edge: moves.
    try testing.expect(glide(tokens, glideRelease(.{ .rect = on_edge.rect, .velocity = Velocity{ .x = -3000 } })) != null);
    // Top-left corner of the region, flung up-left: stays.
    try testing.expect(glide(tokens, glideRelease(.{ .rect = Rect{ .x = 248, .y = 52, .width = 400, .height = 300 }, .velocity = Velocity{ .x = -3000, .y = -3000 } })) == null);
}

test "glide thresholds: under 8 px, slower than the minimum release speed and reduce motion never glide" {
    try testing.expect(glide(tokens, glideRelease(.{ .dx = 5, .dy = 6 })) == null);
    try testing.expect(glide(tokens, glideRelease(.{ .dx = 8, .dy = 0 })) != null);
    try testing.expect(glide(tokens, glideRelease(.{ .velocity = Velocity{ .x = 200, .y = 200 } })) == null); // 283 px/s
    try testing.expect(glide(tokens, glideRelease(.{ .velocity = Velocity{ .x = 180, .y = 240 } })) != null); // 300 px/s
    try testing.expect(glide(tokens, glideRelease(.{ .reduced_motion = true, .velocity = Velocity{ .x = 5000 } })) == null);
    try testing.expect(glide(tokens, glideRelease(.{ .velocity = Velocity{ .x = std.math.nan(f32) } })) == null);
    // A custom threshold from the tokens applies.
    var t = tokens;
    t.glide_min_velocity = 2500;
    try testing.expect(glide(t, glideRelease(.{})) == null);
}

test "swipe sampler: x and y velocity from the same 80 ms window" {
    var s: Sampler = .{};
    for (0..10) |i| s.add(@as(u64, i) * 10 * ms, @as(f32, @floatFromInt(i)) * -20, @as(f32, @floatFromInt(i)) * 10);
    const v = s.velocity2(80);
    try testing.expectApproxEqAbs(@as(f32, -2000), v.x, 1);
    try testing.expectApproxEqAbs(@as(f32, 1000), v.y, 1);
    try testing.expectApproxEqAbs(@as(f32, 1000), s.velocity(80), 1);
}
