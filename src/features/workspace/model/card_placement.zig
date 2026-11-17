//! tab 内卡片的放置判定（PLUGIN_ARCH_PLAN 2.5.5 M2–M6）。
//!
//! tab 与 tab 内分屏是同一种东西：tab 是卡片容器，分屏树（`group_layout.Tree`）的叶子是卡片，
//! 单卡 tab 只是只有一个叶子的特例。卡片能否进入分屏、能否作为独立 tab、能否随 tab 移交到另一个
//! 窗口，读卡片类型声明；宿主只再叠加运行状态条件（关闭中、待提交）。roster（广播与"N 个会话"
//! 计数的范围）只接纳会话绑定的卡片——非会话卡片即使在同一个分屏里，也不是组成员。
const std = @import("std");
pub const card_types = @import("../../../host/card_types.zig");
pub const CardTypeDef = card_types.CardTypeDef;

/// 会话 tab 的默认卡片类型（通用会话卡片）；其余类型由创建处显式给出。
pub const session_def = @import("card_type.zig").session_def;
pub const terminal_def = @import("../../terminal/mod.zig").card_type;
pub const file_def = @import("../../files/mod.zig").card_type;
pub const history_def = @import("../../history/mod.zig").card_type;

/// M6：roster 只接纳会话绑定的卡片。
pub fn rosterAdmits(card: *const CardTypeDef) bool {
    return card.binding == .session;
}

/// M3：这张卡片所在的 tab 能否作为入组 / 分屏目标（`canGroupTarget`）。约束来自卡片类型的
/// `split`，入组还要求 roster 准入；运行状态条件（关闭中、待提交）由宿主照旧叠加。
pub fn canJoinSplit(card: *const CardTypeDef, closing: bool, owned_pending: bool) bool {
    return card.placements.split and rosterAdmits(card) and !closing and !owned_pending;
}

/// M3：窗格头"向右 / 向下分屏"是否可用（今天这条不看 owned_pending，保持原样）。
pub fn canSplitPane(card: *const CardTypeDef, closing: bool) bool {
    return card.placements.split and rosterAdmits(card) and !closing;
}

/// M4：卡片能否离开分屏、成为独立 tab（离开组 / 拖出）。
pub fn canStandalone(card: *const CardTypeDef) bool {
    return card.placements.standalone_tab;
}

/// 窗口移交（V0.2 §6，只移视图）：读卡片类型的 `supports_window_transfer` 与会话 owner；运行状态
/// 条件（关闭中）由宿主叠加。渲染器是否支持移交在移交路径上另行判定。
pub fn canTransferWindow(card: *const CardTypeDef, session_owner: bool, closing: bool) bool {
    return card.supports_window_transfer and session_owner and rosterAdmits(card) and !closing;
}

/// M2：`card_type` 与 owner 一致——会话 owner ⇔ 会话绑定的卡片。
pub fn consistent(card: *const CardTypeDef, session_owner: bool) bool {
    return (card.binding == .session) == session_owner;
}

/// 改动前 `canGroupTarget` 的硬编码条件（归档 tab 删除前），只作等价性单测的对照。
fn legacyCanGroupTarget(closing: bool, owned_pending: bool, session_owner: bool) bool {
    return !closing and !owned_pending and session_owner;
}
/// 改动前窗格头 `can_split` 的条件（roster 存在时），只作对照。
fn legacyCanSplit(closing: bool, session_owner: bool) bool {
    return session_owner and !closing;
}
/// 改动前窗口移交的 tab 条件（`validatePluginTransfer`：会话 owner、未关闭、有插件渲染器、
/// 没有终端也没有运行时），只作对照。
fn legacyCanTransfer(session_owner: bool, closing: bool, plugin_renderer: bool, terminal: bool, runtime: bool) bool {
    return session_owner and !closing and plugin_renderer and !terminal and !runtime;
}

const kvm_like: CardTypeDef = .{ .id = "kvm", .title = "KVM", .binding = .session, .placements = .{ .standalone_tab = true, .split = true }, .default_placement = .standalone_tab, .supports_window_transfer = true };

test "new split admission reads card constraints and matches the legacy predicate for every session tab state" {
    const cards = [_]*const CardTypeDef{ &terminal_def, &file_def, &session_def, &kvm_like };
    var checked: usize = 0;
    for (cards) |card| for ([_]bool{ false, true }) |closing| for ([_]bool{ false, true }) |owned_pending| {
        try std.testing.expect(consistent(card, true));
        try std.testing.expectEqual(legacyCanGroupTarget(closing, owned_pending, true), canJoinSplit(card, closing, owned_pending));
        try std.testing.expectEqual(legacyCanSplit(closing, true), canSplitPane(card, closing));
        // 现有类型都允许独立成 tab，离开组的路径行为不变（M4）。
        try std.testing.expect(canStandalone(card));
        checked += 1;
    };
    try std.testing.expectEqual(@as(usize, 16), checked);
}

test "window transfer reads the card type and matches the legacy renderer predicate for every tab shape" {
    // 今天能出现的 tab 形态：终端（有终端视图）、文件（既无终端也无渲染器）、插件渲染器（通用会话卡片或
    // 插件定义的卡片）、会话记录卡片（非会话 owner）。
    const Shape = struct { card: *const CardTypeDef, session_owner: bool, plugin_renderer: bool, terminal: bool, runtime: bool };
    const shapes = [_]Shape{
        .{ .card = &terminal_def, .session_owner = true, .plugin_renderer = false, .terminal = true, .runtime = true },
        .{ .card = &terminal_def, .session_owner = true, .plugin_renderer = false, .terminal = true, .runtime = false },
        .{ .card = &file_def, .session_owner = true, .plugin_renderer = false, .terminal = false, .runtime = false },
        .{ .card = &session_def, .session_owner = true, .plugin_renderer = true, .terminal = false, .runtime = false },
        .{ .card = &kvm_like, .session_owner = true, .plugin_renderer = true, .terminal = false, .runtime = false },
        .{ .card = &history_def, .session_owner = false, .plugin_renderer = false, .terminal = false, .runtime = false },
    };
    for (shapes) |shape| for ([_]bool{ false, true }) |closing| {
        try std.testing.expect(consistent(shape.card, shape.session_owner));
        try std.testing.expectEqual(legacyCanTransfer(shape.session_owner, closing, shape.plugin_renderer, shape.terminal, shape.runtime), canTransferWindow(shape.card, shape.session_owner, closing));
    };
}

test "placements the card type forbids are rejected regardless of state" {
    const no_split: CardTypeDef = .{ .id = "probe", .title = "Probe", .binding = .session, .placements = .{ .standalone_tab = true }, .default_placement = .standalone_tab };
    try std.testing.expect(!canJoinSplit(&no_split, false, false));
    try std.testing.expect(!canSplitPane(&no_split, false));
    // history 卡片：split = false（Q11），且不是会话绑定，不进 roster、不随窗口移交。
    try std.testing.expect(!canJoinSplit(&history_def, false, false) and !canSplitPane(&history_def, false) and !rosterAdmits(&history_def));
    try std.testing.expect(canStandalone(&history_def) and !canTransferWindow(&history_def, false, false));
    const floating_only: CardTypeDef = .{ .id = "chat", .title = "Chat", .binding = .tab, .placements = .{ .float = true }, .default_placement = .float };
    try std.testing.expect(!canStandalone(&floating_only) and !canJoinSplit(&floating_only, false, false));
    // 一致性断言拦住 owner 与卡片类型不符的状态。
    try std.testing.expect(!consistent(&terminal_def, false));
    try std.testing.expect(!consistent(&history_def, true));
}
