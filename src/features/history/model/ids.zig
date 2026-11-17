//! 会话记录卡片的 test_id（PLUGIN_ARCH_PLAN 5.2 PL4b「e2e 与 test_id」）。
//!
//! 现有的 `history.*` 全部保留在同一语义节点上：`history.panel` 是卡片根（浮动时是浮动卡片，
//! tab 时是卡片内容根）；列表栏里的搜索、筛选、条数、记录行、翻页、清空、删除确认、空状态、消息、
//! 重试语义不变。语义变化的两个：`history.record.view` 改为在卡片内选中并显示详情（不再新开 tab），
//! `history.close` 改为关闭这张卡片。回放条沿用 `terminal.history.*`（节点在详情区里）。
pub const panel = "history.panel";
pub const header = "history.header";
pub const count = "history.count";
pub const close = "history.close";
pub const close_tooltip = "history.close.tooltip";
pub const open_as_tab = "history.open_as_tab";
pub const list = "history.list";
pub const search = "history.search";
pub const query = "history.query";
pub const filter_all = "history.filter.all";
pub const filter_ssh = "history.filter.ssh";
pub const filter_local = "history.filter.local";
pub const clear = "history.clear";
pub const clear_tooltip = "history.clear.tooltip";
pub const viewport = "history.viewport";
pub const record = "history.record";
pub const record_title = "history.record.title";
pub const record_title_tooltip = "history.record.title.tooltip";
pub const record_detail = "history.record.detail";
pub const record_detail_tooltip = "history.record.detail.tooltip";
pub const record_state = "history.record.state";
pub const record_view = "history.record.view";
pub const record_view_tooltip = "history.record.view.tooltip";
pub const record_export = "history.record.export";
pub const record_export_tooltip = "history.record.export.tooltip";
pub const record_delete = "history.record.delete";
pub const record_delete_tooltip = "history.record.delete.tooltip";
pub const previous = "history.previous";
pub const previous_tooltip = "history.previous.tooltip";
pub const next = "history.next";
pub const next_tooltip = "history.next.tooltip";
pub const empty = "history.empty";
pub const empty_detail = "history.empty.detail";
pub const message = "history.message";
pub const retry = "history.retry";
pub const detail = "history.detail";
pub const detail_empty = "history.detail.empty";
pub const detail_loading = "history.detail.loading";
pub const back = "history.back";

/// 焦点标识（运行时语义，不是 test_id）：搜索框与每页第 N 行的“查看”。
pub const focus_search = "history-focus-search";
pub fn rowFocus(position: usize) []const u8 {
    return if (position < row_focus.len) row_focus[position] else row_focus[row_focus.len - 1];
}
const row_focus = blk: {
    @setEvalBranchQuota(20_000);
    var result: [@import("history_list.zig").page_size][]const u8 = undefined;
    for (&result, 0..) |*slot, i| slot.* = std.fmt.comptimePrint("history-focus-row-{d}", .{i});
    break :blk result;
};
const std = @import("std");
