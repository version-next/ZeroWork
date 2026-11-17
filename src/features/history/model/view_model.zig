//! 会话记录卡片的根 view-model（PLUGIN_ARCH_PLAN 5.2 PL4b 的 `CardVm`）：唯一协调者。
//!
//! 用户判定：“会话记录不用再分为列表和回放，它就像 FTP 一样，它就是一个独立的 card 完整的，有 list
//! 和 detail”。一张卡片一个 `CardVm`，持有自己的列表（`ListVm`）与详情（`DetailVm`）：列表发出
//! “查看”，这里让详情加载；详情的选中记录回写列表的选中行。所以“tab 可以开多张”（Q15）各自的
//! 选中记录天然互不影响。
//!
//! 卡片不知道自己在哪：放置（浮动 / 独立 tab）由宿主决定，这里只记录当前放置以决定头部显示
//! “作为 tab 打开 / 关闭”。卡片宽度不足以并排时（`card_type.split_min_width`）退化为列表或详情
//! 二选一，详情头带“返回”。
const std = @import("std");
const ui = @import("ui");
const archive_mod = @import("../../../vt/session_archive.zig");
const card_type = @import("card_type.zig");
const list_mod = @import("../list/model/view_model.zig");
const detail_mod = @import("../detail/model/view_model.zig");
const loading = @import("history_archive.zig");
const ids = @import("ids.zig");

pub const ListVm = list_mod.ListVm;
pub const DetailVm = detail_mod.DetailVm;
pub const Placement = enum { float, tab };
pub const Layout = enum { split, list_only, detail_only };

/// 宿主（`HistoryHost`）实现：放置、关闭、导出与回放表面。
pub const Host = struct {
    context: *anyopaque,
    open_as_tab: *const fn (*anyopaque, *CardVm) void,
    close: *const fn (*anyopaque, *CardVm) void,
    export_record: *const fn (*anyopaque, archive_mod.Descriptor) anyerror!void,
    mount_replay: *const fn (*anyopaque, *loading.Document) anyerror!detail_mod.Replay,
    release_replay: *const fn (*anyopaque, detail_mod.Replay) void,
};

pub const CardVm = struct {
    allocator: std.mem.Allocator,
    host: Host,
    list: *ListVm,
    detail: *DetailVm,
    placement: *ui.Signal(Placement),
    layout: *ui.Signal(Layout),
    focus_seq: *ui.Signal(u32),
    focus_target: []const u8 = "",
    width: f32 = 0,
    /// 焦点在详情区的回放表面里（宿主每帧写）：此时 Esc 归终端，不关卡片。
    replay_focused: bool = false,
    /// 窄卡片：用户点了“查看”，想看详情（“返回”清掉）。
    wants_detail: bool = false,
    selected_copy: std.ArrayList(u8) = .empty,
    has_selected: bool = false,

    pub fn init(scope: *ui.Scope, allocator: std.mem.Allocator, archive: *archive_mod.Archive, host: Host, placement: Placement) !*CardVm {
        const self = try scope.createState(CardVm, .{
            .allocator = allocator,
            .host = host,
            .list = undefined,
            .detail = undefined,
            .placement = try scope.createSignal(Placement, placement),
            .layout = try scope.createSignal(Layout, .list_only),
            .focus_seq = try scope.createSignal(u32, 0),
        });
        try scope.onCleanup(CardVm, self, deinit);
        self.list = try ListVm.init(scope, allocator, archive, .{ .context = self, .view = viewRecord, .export_record = exportRecord });
        self.detail = try DetailVm.init(scope, allocator, archive, .{ .context = self, .mount = mountReplay, .release = releaseReplay, .failed = loadFailed });
        return self;
    }

    fn deinit(self: *CardVm) void {
        self.selected_copy.deinit(self.allocator);
    }

    // ── 视图读 ──

    pub fn floating(self: *const CardVm) bool {
        return self.placement.get() == .float;
    }
    pub fn currentLayout(self: *const CardVm) Layout {
        return self.layout.get();
    }
    pub fn listShown(self: *const CardVm) bool {
        return self.layout.get() != .detail_only;
    }
    pub fn detailShown(self: *const CardVm) bool {
        return self.layout.get() != .list_only;
    }
    pub fn dividerShown(self: *const CardVm) bool {
        return self.layout.get() == .split;
    }
    pub fn backShown(self: *const CardVm) bool {
        return self.layout.get() == .detail_only;
    }
    pub fn replayFocused(self: *const CardVm) bool {
        return self.replay_focused;
    }
    pub fn focusSeq(self: *const CardVm) u32 {
        return self.focus_seq.get();
    }
    pub fn focusTarget(self: *const CardVm) []const u8 {
        return self.focus_target;
    }

    // ── 意图 ──

    /// 列表点“查看”：在本卡片里选中并显示详情（不再新开 tab）。
    pub fn select(self: *CardVm, descriptor: archive_mod.Descriptor) void {
        self.detail.load(descriptor) catch |err| return self.list.report(err);
        self.wants_detail = true;
        self.updateLayout();
    }
    pub fn back(self: *CardVm) void {
        self.wants_detail = false;
        self.updateLayout();
        self.focus_target = ids.focus_search;
        self.focus_seq.set(self.focus_seq.peek() +% 1);
    }
    pub fn openAsTab(self: *CardVm) void {
        if (self.placement.peek() != .float) return;
        self.host.open_as_tab(self.host.context, self);
    }
    pub fn close(self: *CardVm) void {
        self.detail.cancel();
        self.host.close(self.host.context, self);
    }
    /// Esc（冒泡到卡片根）：取消加载。浮动卡片本身由通用浮动层按卡片规则关闭
    /// （OverlayHost `card`：焦点在卡片里时 Esc 关闭）。返回是否处理。
    pub fn escape(self: *CardVm) bool {
        if (self.detail.isLoading()) {
            self.detail.cancel();
            return true;
        }
        return false;
    }
    /// 从入口再次打开（重置筛选，按来源筛选重新读取目录）。
    pub fn show(self: *CardVm, source: ?list_mod.SourceFilter) void {
        self.list.show(source);
        self.wants_detail = false;
        self.updateLayout();
    }

    // ── 宿主同步（每帧） ──

    pub fn setPlacement(self: *CardVm, placement: Placement) void {
        self.placement.set(placement);
    }
    pub fn setWidth(self: *CardVm, width: f32) void {
        if (@abs(width - self.width) < 0.5) return;
        self.width = width;
        self.updateLayout();
    }
    pub fn poll(self: *CardVm) void {
        self.detail.poll();
        self.syncSelection();
        self.list.poll();
        self.updateLayout();
    }

    fn syncSelection(self: *CardVm) void {
        const key = self.detail.selectedKey();
        const same = if (key) |value| self.has_selected and std.mem.eql(u8, value, self.selected_copy.items) else !self.has_selected;
        if (same) return;
        self.selected_copy.clearRetainingCapacity();
        if (key) |value| self.selected_copy.appendSlice(self.allocator, value) catch {};
        self.has_selected = key != null;
        self.list.setSelected(if (self.has_selected) self.selected_copy.items else null);
    }

    fn updateLayout(self: *CardVm) void {
        const next: Layout = if (self.width <= 0 or self.width >= card_type.split_min_width) .split else if (self.wants_detail and self.detail.phase.peek() != .empty) .detail_only else .list_only;
        self.layout.set(next);
    }

    fn viewRecord(raw: *anyopaque, descriptor: archive_mod.Descriptor) void {
        const self: *CardVm = @ptrCast(@alignCast(raw));
        self.select(descriptor);
    }
    fn exportRecord(raw: *anyopaque, descriptor: archive_mod.Descriptor) anyerror!void {
        const self: *CardVm = @ptrCast(@alignCast(raw));
        return self.host.export_record(self.host.context, descriptor);
    }
    fn mountReplay(raw: *anyopaque, document: *loading.Document) anyerror!detail_mod.Replay {
        const self: *CardVm = @ptrCast(@alignCast(raw));
        return self.host.mount_replay(self.host.context, document);
    }
    fn releaseReplay(raw: *anyopaque, replay: detail_mod.Replay) void {
        const self: *CardVm = @ptrCast(@alignCast(raw));
        self.host.release_replay(self.host.context, replay);
    }
    fn loadFailed(raw: *anyopaque, err: anyerror) void {
        const self: *CardVm = @ptrCast(@alignCast(raw));
        self.wants_detail = false;
        self.list.report(err);
        self.updateLayout();
    }
};
