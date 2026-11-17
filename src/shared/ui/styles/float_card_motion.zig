//! 浮动卡片（AI 面板、会话记录等浮动层）出入场的动效 token：设置 › 外观与主题 › 终端与工作区 ›“浮动卡片切换动画”
//! （`ui.float_card_transition`，Z12b）映射到 zenit `AnchorTransition` 的 token。
//!
//! - `anchor` → `ui.fx.anchor_transition.default_tokens`：收向锚点（所属 tab / 图标）再从锚点展开（zenit Z12）。画面是 genie
//!   网格形变（macOS Dock 最小化：靠锚点的一边先收窄、两侧弯曲、整条被吸进锚点）；飞行期间只画一张缓存纹理，卡片本身不参与布局与绘制
//!   （zenit 静态纹理模型，genie-static）。不支持网格合成的后端退化为“曲线路径 + 缩放”。
//! - `fade`   → `ui.fx.anchor_transition.fade_scale_tokens`：原地淡出并缩小到约 0.97，入场反向（zenit Z12b）。
//!
//! 两者都用 zenit 的默认时长与“减少动态效果”退化（原地纯淡入淡出），ZeroWork 不覆盖 token。
//! 用法（浮动层宿主，每次开始过渡前读一次，保存设置后下一次过渡即生效）：
//!
//!     const mode = config.floatTransitionMode(if (runtime) |r| &r.value else null);
//!     transition.setTokens(float_card_motion.tokens(mode));
//!
//! `setTokens` 在过程中调用时 zenit 会等这次过程落定后再换，不会中途跳变。Yix 声明式用法可把 `tokens(mode)` 放进
//! 信号交给 `anchorMotion`（zenit 已支持源）。
const std = @import("std");
const ui = @import("ui");

pub const Tokens = ui.fx.AnchorMotionTokens;

/// 下滑收起（Pencil AveHg）的速度采样、阈值、时长与曲线：唯一来源是 `shared/base/float_swipe.zig`
/// 的 `Tokens`（纯数值，判定逻辑同处），这里转成 zenit 动画参数。浮动层与收起目标（AI launcher）都从这里取。
pub const swipe = @import("../../base/float_swipe.zig");
pub const swipe_tokens = swipe.tokens;

/// `float_swipe.Curve`（CSS cubic-bezier）→ zenit `Easing`。
pub fn easing(curve: swipe.Curve) ui.fx.Easing {
    return .{ .cubic_bezier = .{ .x1 = curve.x1, .y1 = curve.y1, .x2 = curve.x2, .y2 = curve.y2 } };
}

/// 收起目标（如 AI launcher 图标）在锚角的入场：淡入 + 由 `icon_from_scale` 放大到 1，延迟
/// `icon_in_delay_ms`；减少动态效果时只做 `reduced_fade_ms` 淡入、不缩放、不延迟。
pub const Arrival = struct { duration_s: f32, delay_s: f32, from_scale: f32, easing: ui.fx.Easing };

pub fn arrival(reduced: bool) Arrival {
    const t = swipe_tokens;
    if (reduced) return .{ .duration_s = t.reduced_fade_ms / 1000, .delay_s = 0, .from_scale = 1, .easing = easing(t.icon_in_curve) };
    return .{ .duration_s = t.icon_in_ms / 1000, .delay_s = t.icon_in_delay_ms / 1000, .from_scale = t.icon_from_scale, .easing = easing(t.icon_in_curve) };
}

/// 与 `config.FloatCardTransition` 同名同值（shared_ui 不依赖 core 配置层，按标签名对应）。
pub const Mode = enum { anchor, fade };

/// 设置值 → zenit token。`mode` 可以是本模块的 `Mode`，也可以是 `config.FloatCardTransition`（标签必须是 `anchor` / `fade`）。
pub fn tokens(mode: anytype) Tokens {
    return switch (toMode(mode)) {
        .anchor => ui.fx.anchor_transition.default_tokens,
        .fade => ui.fx.anchor_transition.fade_scale_tokens,
    };
}

/// A move between two places of the same card (放入分屏 from the floating rectangle, 浮动 from the
/// pane): the anchor is the rectangle the card was just shown in, so the picture is fully opaque
/// there (no frame where neither the old place nor the flight shows anything). `fade` is unchanged.
pub fn placeTokens(mode: anytype) Tokens {
    var t = tokens(mode);
    if (t.mode == .anchor) t.end_opacity = 1;
    return t;
}

fn toMode(mode: anytype) Mode {
    const T = @TypeOf(mode);
    if (T == Mode) return mode;
    comptime {
        const names = @typeInfo(T).@"enum".field_names;
        if (names.len != @typeInfo(Mode).@"enum".field_names.len) @compileError("float_card_motion.tokens: expects an enum with exactly anchor / fade");
        for (names) |name| if (!@hasField(Mode, name)) @compileError("float_card_motion.tokens: unknown mode " ++ name);
    }
    return switch (mode) {
        inline else => |tag| @field(Mode, @tagName(tag)),
    };
}

test "float card motion: anchor flies into the anchor, fade shrinks in place to about 0.97" {
    const anchor = tokens(Mode.anchor);
    try std.testing.expectEqual(ui.fx.anchor_transition.Mode.anchor, anchor.mode);
    try std.testing.expect(anchor.usesAnchor());
    // genie-static: the anchor mode is the genie mesh (macOS Dock minimize), zenit's default.
    try std.testing.expectEqual(ui.fx.anchor_transition.Shape.genie, anchor.shape);
    try std.testing.expect(anchor.genie());
    // A move between two places of the card stays opaque at its start (the place it left).
    try std.testing.expectEqual(@as(f32, 1), placeTokens(Mode.anchor).end_opacity);
    try std.testing.expectEqual(tokens(Mode.fade).end_opacity, placeTokens(Mode.fade).end_opacity);
    const fade = tokens(Mode.fade);
    try std.testing.expectEqual(ui.fx.anchor_transition.Mode.fade_scale, fade.mode);
    try std.testing.expect(!fade.usesAnchor());
    try std.testing.expect(fade.fade_scale_end_scale >= 0.96 and fade.fade_scale_end_scale <= 0.98);
    // Reduce motion stays zenit's default for both: a pure fade in place.
    try std.testing.expectEqual(ui.fx.anchor_transition.ReducedMotion.fade, anchor.reduced);
    try std.testing.expectEqual(ui.fx.anchor_transition.ReducedMotion.fade, fade.reduced);
    // Any enum with the same tags maps the same way (config.FloatCardTransition).
    const Other = enum { anchor, fade };
    try std.testing.expectEqual(fade.mode, tokens(Other.fade).mode);
    try std.testing.expectEqual(anchor.mode, tokens(Other.anchor).mode);
}

test "float card motion: swipe arrival of the collapse target follows the AveHg tokens" {
    const full = arrival(false);
    try std.testing.expectApproxEqAbs(@as(f32, 0.16), full.duration_s, 1e-6);
    try std.testing.expectApproxEqAbs(@as(f32, 0.12), full.delay_s, 1e-6);
    try std.testing.expectEqual(@as(f32, 0.92), full.from_scale);
    // Reduce motion: a 120 ms fade, no scale, no delay.
    const reduced = arrival(true);
    try std.testing.expectApproxEqAbs(@as(f32, 0.12), reduced.duration_s, 1e-6);
    try std.testing.expectEqual(@as(f32, 0), reduced.delay_s);
    try std.testing.expectEqual(@as(f32, 1), reduced.from_scale);
    try std.testing.expectEqual(ui.fx.Easing{ .cubic_bezier = .{ .x1 = 0.42, .y1 = 0, .x2 = 1, .y2 = 1 } }, easing(swipe.Curve.ease_in));
}
