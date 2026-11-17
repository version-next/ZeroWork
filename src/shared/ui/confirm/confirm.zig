//! 确认与撤销：危险操作的唯一两个入口（CONSISTENCY_AUDIT #2；用户拍板 2，2026-11-14）。
//!
//! | 操作 | 入口 | 载体 |
//! |---|---|---|
//! | 不可逆（关闭页签、结束 AI 会话、替换主机密钥、清除全部数据…） | `confirm(spec)` | zenit 原生 `W.ConfirmDialog`（Modal 预设） |
//! | 可撤销（删除主机、删除会话记录、清除已结束提醒…） | `undoable(cx, spec)` | 先执行，再弹带“撤销”的原生 Toast |
//!
//! - 不再使用按钮旁弹出的小确认框（行内 Popover），也不在菜单里不确认就执行危险项。
//! - 确认按钮一律“动词 + 对象”（`Action`：`label(.delete, "主机")` = “删除主机”），危险样式只有原生
//!   `variant = .danger` 一种（`tone = .danger`，默认）；取消按钮一律“取消”。
//! - 焦点与关闭按 OverlayHost 的 `dialog` 规则：打开时焦点落在安全按钮“取消”；Esc、标题栏 ×、点遮罩都等于取消；
//!   关闭后焦点回到打开时的位置（原生 Modal）。
//! - 后果（会断开会话、会结束进程、无法撤销）写在说明 `message` 里。
//!
//! `.yix` 里直接用 `<W.ConfirmDialog>`，规则取本文件的常量：`closeOnOverlay={C.close_on_overlay}`、
//! `cancelLabel={C.cancel_label}`、`confirmLabel={C.label(.delete, "服务提供方")}`。
//!
//! 撤销：调用方先做“立即生效且可恢复”的一半（把对象藏起来、记下要删的 id），再 `undoable` 登记真正的提交和
//! 回滚；Toast 离场后提交，点“撤销”回滚（账本见 `shared/base/undo_ledger.zig`）。每个窗口一本账，由窗口的通知栈
//! （`features/notifications`）`install` 时建并注册 Toast 出口；没有出口的窗口立即提交。
const std = @import("std");
const ui = @import("ui");
const overlay = @import("../overlay/overlay_host.zig");
pub const ledger = @import("../../base/undo_ledger.zig");

// ── 确认按钮文案：动词 + 对象（`shared/base/confirm_label.zig`，model 层也能用） ─────────────────

pub const labels = @import("../../base/confirm_label.zig");
pub const Verb = labels.Verb;
pub const label = labels.label;
pub const labelFmt = labels.labelFmt;

/// 全应用只有这一个取消文案。
pub const cancel_label = labels.cancel_label;
/// OverlayHost `dialog`：点遮罩 = 取消。
pub const close_on_overlay = overlay.policy(.dialog).outside;

// ── confirm(spec)：不可逆操作 ──────────────────────────────────────────────────────────────

pub const Tone = enum { danger, primary };

pub const Spec = struct {
    open: ui.Model(bool) = .{ .local = false },
    /// 问句（全角“？”）：“关闭页签？”“替换主机密钥？”。
    title: ui.Source([]const u8),
    /// 后果：会断开会话、会结束进程、无法撤销。
    message: ui.Source([]const u8) = .{ .value = "" },
    /// 确认按钮：`label(...)` 或 `labelFmt(...)` 的结果（动词 + 对象）。
    action: ui.Source([]const u8),
    tone: Tone = .danger,
    /// 取消按钮文案：确认态一律“取消”；只有确认之后同一个框里的进度 / 结果态（“停止后续关闭”“收起结果”）改写。
    cancel: ui.Source([]const u8) = .{ .value = cancel_label },
    action_disabled: ui.Source(bool) = .{ .value = false },
    action_loading: ui.Source(bool) = .{ .value = false },
    /// 确认之后在框里的步骤：进行中不可取消（Esc / × 也不接）、隐藏确认按钮、每换一步焦点回到安全按钮。
    cancel_disabled: ui.Source(bool) = .{ .value = false },
    action_shown: ui.Source(bool) = .{ .value = true },
    refocus: ui.Source(u64) = .{ .value = 0 },
    width: ui.Source(f32) = .{ .value = 420 },
    max_height: ui.Source(f32) = .{ .value = 600 },
    /// 确认后先关闭（默认）；进度 / 失败重试留在框里的流程设 false，自己关闭。
    close_on_confirm: bool = true,
    on_confirm: ?ui.Handler(void) = null,
    /// 取消、×、Esc、点遮罩。
    on_cancel: ?ui.Handler(void) = null,
    test_id: ?[]const u8 = null,
    test_ids: ui.widgets.ConfirmTestIds = .{},
};

pub const Confirm = ui.widgets.ConfirmDialogResult;

/// 挂一个确认框（关着挂上，`open` 打开）。原生 Modal 自己挂到窗口浮层根上；没有浮层根时（单元测试）
/// `result.modal.portaled == false`，调用方把 `result.modal.overlay` 挂到自己的树上。
pub fn confirm(scope: *ui.Scope, cx: *ui.Cx, args: anytype) !Confirm {
    const spec = ui.reactive.props.coerce(Spec, args);
    return ui.widgets.ConfirmDialog(.{
        .open = spec.open,
        .title = spec.title,
        .message = spec.message,
        .confirm_label = spec.action,
        .cancel_label = spec.cancel,
        .tone = switch (spec.tone) {
            .danger => ui.widgets.ConfirmTone.danger,
            .primary => ui.widgets.ConfirmTone.primary,
        },
        .confirm_disabled = spec.action_disabled,
        .confirm_loading = spec.action_loading,
        .cancel_disabled = spec.cancel_disabled,
        .confirm_shown = spec.action_shown,
        .refocus = spec.refocus,
        .width = spec.width,
        .max_height = spec.max_height,
        .close_on_overlay = close_on_overlay,
        .close_on_confirm = spec.close_on_confirm,
        .initial_focus = .cancel,
        .on_confirm = spec.on_confirm,
        .on_cancel = spec.on_cancel,
        .test_id = spec.test_id,
        .test_ids = spec.test_ids,
    }).mount(scope, cx);
}

// ── undoable(spec)：可撤销操作 ─────────────────────────────────────────────────────────────

pub const UndoSpec = ledger.Spec;
pub const Outcome = ledger.Outcome;
pub const Sink = ledger.Sink;

const LedgerSlot = struct { value: ?*ledger.Ledger = null };
const ledger_key = std.hash.Wyhash.hash(0, "ZeroWork.undoLedger");

fn current(cx: *ui.Cx) ?*ledger.Ledger {
    const slot = cx.state(LedgerSlot, ledger_key, .{}) catch return null;
    return slot.value;
}

/// 窗口的通知栈挂上 Toast 出口（建本窗口的撤销账本）。
pub fn install(cx: *ui.Cx, sink: Sink) void {
    const slot = cx.state(LedgerSlot, ledger_key, .{}) catch return;
    if (slot.value) |value| return value.setSink(sink);
    const value = cx.allocator.create(ledger.Ledger) catch return;
    value.* = ledger.Ledger.init(cx.allocator);
    value.setSink(sink);
    slot.value = value;
}

/// 窗口的通知栈卸下（窗口关闭）：还没结局的全部提交，账本随之释放。
pub fn uninstall(cx: *ui.Cx) void {
    const slot = cx.state(LedgerSlot, ledger_key, .{}) catch return;
    const value = slot.value orelse return;
    slot.value = null;
    value.deinit();
    cx.allocator.destroy(value);
}

/// 可撤销操作：调用方已经把“立即生效且可恢复”的一半做完（对象已从界面藏起），这里登记真正的提交与回滚，
/// 并弹出带“撤销”的 Toast。Toast 离场后 `commit`，点“撤销” `revert`；没有 Toast 可弹时立即 `commit`。
/// 返回 true 表示在撤销窗口里。
pub fn undoable(cx: *ui.Cx, spec: UndoSpec) bool {
    const value = current(cx) orelse {
        spec.commit(spec.context, spec.token);
        return false;
    };
    const pending = value.add(spec);
    cx.requestRedraw();
    return pending;
}

/// 给 model / view-model 的登记入口（`ledger.Port`），接到这个窗口的账本。
pub fn port(cx: *ui.Cx) ledger.Port {
    return .{ .context = cx, .add = portAdd, .flush = portFlush };
}
fn portAdd(raw: *anyopaque, spec: UndoSpec) bool {
    return undoable(@ptrCast(@alignCast(raw)), spec);
}
fn portFlush(raw: *anyopaque, owner: *anyopaque) void {
    flushOwner(@ptrCast(@alignCast(raw)), owner);
}

/// 登记方销毁前调用：它名下还没结局的全部提交。
pub fn flushOwner(cx: *ui.Cx, owner: *anyopaque) void {
    if (current(cx)) |value| value.flushOwner(owner);
}

/// Toast 的结局（窗口的通知栈回报）。
pub fn settle(cx: *ui.Cx, toast: u64, outcome: Outcome) void {
    if (current(cx)) |value| value.settle(toast, outcome);
    cx.requestRedraw();
}

/// 这一项还在撤销窗口里（界面保持隐藏）。
pub fn isPending(cx: *ui.Cx, context: *anyopaque, token: u64) bool {
    const value = current(cx) orelse return false;
    return value.isPending(context, token);
}

// ---- Tests ----

const testing = std.testing;

test "confirm labels are verb + object" {
    try testing.expectEqualStrings("删除主机", label(.delete, "主机"));
    try testing.expectEqualStrings("关闭页签", label(.close, "页签"));
    try testing.expectEqualStrings("替换主机密钥", label(.replace, "主机密钥"));
    var buffer: [64]u8 = undefined;
    try testing.expectEqualStrings("关闭 3 个会话", labelFmt(&buffer, .close, " {d} 个会话", .{3}));
    try testing.expectEqualStrings("取消", cancel_label);
    try testing.expect(close_on_overlay);
}
