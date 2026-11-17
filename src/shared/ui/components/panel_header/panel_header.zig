//! 同级面板统一头部 / 关闭按钮的共享入口（panel-heads）：视图是 `panel_header.yix`。
//!
//! - 计数一律写“N 条”（用户拍板第 4 条），有上下文时“N 条 · 会话名”：`countText`（= `format.countWith`）。
//! - 关闭按钮提示一律“关闭 · Esc”（`close_tooltip`）；Esc 不关闭的地方由调用方写“关闭”。
//! - 命令式视图（还没改成 `.yix` 的面板）用 `mountHeader` / `mountClose` 挂同一个模板，不另写一套。
const std = @import("std");
const ui = @import("ui");
const template = @import("_panel_header.yix.zig");

pub const close_tooltip = "关闭 · Esc";
/// Esc 不归这颗按钮管的地方（例如关闭会断开连接的页签）用这个。
pub const close_tooltip_plain = "关闭";
pub const Inset = @import("_panel_header.yss.zig").Inset;

/// 宿主拿节点：头部根与动作区（命令式面板把自己的辅助动作挂进 `actions`）。
pub const Slots = struct {
    root: ?*ui.Node = null,
    actions: ?*ui.Node = null,
};

pub fn shown(subtitle: []const u8) bool {
    return subtitle.len != 0;
}

/// “N 条”，有上下文时“N 条 · 上下文”（唯一实现在 `shared/base/format.zig`）。
pub const countText = @import("../../../base/format.zig").countWith;

pub const HeaderOptions = struct {
    icon: ui.SvgAsset,
    title: []const u8,
    subtitle: ?*ui.Signal([]const u8) = null,
    inset: Inset = .card,
    accent: bool = false,
    header_test_id: ?[]const u8 = null,
    title_test_id: ?[]const u8 = null,
    subtitle_test_id: ?[]const u8 = null,
    closable: bool = true,
    close_label: []const u8 = "关闭",
    close_tooltip: []const u8 = close_tooltip,
    close_test_id: ?[]const u8 = null,
    close_tooltip_test_id: []const u8 = "",
    close_focus_id: []const u8 = "",
    on_close: ?ui.Handler(void) = null,
};

/// 命令式面板挂统一头部：返回头部根节点；`slots.actions` 是动作区（关闭按钮之前），调用方把辅助动作挂进去。
pub fn mountHeader(scope: *ui.Scope, cx: *ui.Cx, slots: *Slots, options: HeaderOptions) !*ui.Node {
    const subtitle: ui.Source([]const u8) = if (options.subtitle) |signal| .{ .signal = signal } else .{ .value = "" };
    return ui.view.render(scope, cx, ui.view.with(template.PanelHeader(.{
        .icon = options.icon,
        .title = options.title,
        .subtitle = subtitle,
        .inset = options.inset,
        .accent = options.accent,
        .header_test_id = options.header_test_id,
        .title_test_id = options.title_test_id,
        .subtitle_test_id = options.subtitle_test_id,
        .closable = options.closable,
        .close_label = options.close_label,
        .close_tooltip = options.close_tooltip,
        .close_test_id = options.close_test_id,
        .close_tooltip_test_id = options.close_tooltip_test_id,
        .close_focus_id = options.close_focus_id,
        .on_close = options.on_close,
        .slots = slots,
    }), .{}));
}

pub const CloseOptions = struct {
    label: []const u8 = "关闭",
    tooltip: []const u8 = close_tooltip,
    test_id: ?[]const u8 = null,
    tooltip_test_id: []const u8 = "",
    focus_id: []const u8 = "",
    disabled: ?*ui.Signal(bool) = null,
    on_close: ?ui.Handler(void) = null,
    /// 出参：非空时写入原生按钮节点（设焦点、改无障碍名、几何断言用），不必再按 test_id 遍历槽节点。
    button: ?*?*ui.Node = null,
};

/// 命令式视图挂全应用唯一的关闭按钮（原生 ghost sm 图标按钮 + Tooltip），返回它的槽节点；
/// 要按钮本身时传 `options.button`。
pub fn mountClose(scope: *ui.Scope, cx: *ui.Cx, options: CloseOptions) !*ui.Node {
    const disabled: ui.Source(bool) = if (options.disabled) |signal| .{ .signal = signal } else .{ .value = false };
    return ui.view.render(scope, cx, template.PanelClose(.{
        .label = options.label,
        .tooltip = options.tooltip,
        .button_test_id = options.test_id,
        .tooltip_test_id = options.tooltip_test_id,
        .focus_name = options.focus_id,
        .disabled = disabled,
        .on_close = options.on_close,
        .button_out = options.button,
    }));
}
