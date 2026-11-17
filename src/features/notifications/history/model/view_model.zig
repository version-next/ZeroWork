//! 通知历史（“提醒”弹层）的 view-model：筛选、展开项、失败提示与开合是这里的信号；
//! 列表是协调器记录的一份快照（`rows`），视图（`view/notification_history.yix`）只读这里。
//!
//! “清除已结束”是可撤销操作（CONSISTENCY_AUDIT #2，`shared/ui/confirm` 的 `undoable`）：点了先把当时已结束的记录藏起来并弹出
//! 带“撤销”的 Toast，Toast 离场后才真正从协调器里清掉这些记录（`clearHistoryFacts`），点“撤销”则重新显示。
//!
//! 协调器本身不是响应式的：宿主胶水（`view/notification_history.zig`）每帧调 `sync`，
//! 协调器的 `history_revision`、分钟数或筛选 / 展开变化时才重建快照；值相同不写信号，空闲不重绘。
//! 行里的字符串在两块交替的 arena 里：新快照写进另一块，上一份快照在下次重建前一直有效。
const std = @import("std");
const ui = @import("ui");
const host = @import("../../../../host/notification_host.zig");
const card = @import("../../model/notification_card.zig");
const notifications = host.notifications;
const undo_ledger = @import("../../../../shared/base/undo_ledger.zig");

pub const Severity = notifications.Severity;

pub const ids = struct {
    pub const unread = "notifications.unread";
    pub const panel = "notifications.history";
    pub const count = "notifications.history.count";
    pub const header = "notifications.history.header";
    pub const clear = "notifications.history.clear";
    pub const close = "notifications.history.close";
    pub const pending = "notifications.history.pending";
    pub const recent = "notifications.history.recent";
    pub const viewport = "notifications.history.viewport";
    pub const footer = "notifications.history.footer";
    pub const empty = "notifications.history.empty";
    pub const record = "notifications.history.record";
    pub const title = "notifications.history.title";
    pub const summary = "notifications.history.summary";
    pub const actions = "notifications.history.actions";
    pub const action = "notifications.history.action";
    pub const expand = "notifications.history.expand";
    pub const details = "notifications.history.details";
    pub const message = "notifications.history.message";
};

/// 一个动作按钮：始终派发原记录（fact）上的第 `index` 个动作。
pub const Action = struct {
    /// 列表 key：fact 与下标唯一确定一个按钮。
    id: u64,
    fact_id: u64,
    index: u8,
    label: []const u8,
    disabled: bool,
};

/// 多来源事件展开后的一行来源（“{来源} · 待处理 / 已结束”与它的“查看来源”）。
pub const Source = struct {
    id: u64,
    label: []const u8,
    locate: []const Action,
};

pub const Row = struct {
    /// fact_id，列表 key。
    id: u64,
    severity: Severity,
    title: []const u8,
    age: []const u8,
    summary: []const u8,
    actions: []const Action,
    expandable: bool,
    expanded: bool,
    failure: bool,
    detail: []const u8,
    /// 详情区：展开时，或失败且有原因时（失败直接显示原因）。
    details: bool,
    sources: []const Source,
};

pub const ViewModel = struct {
    allocator: std.mem.Allocator,
    host: *host.Host,
    open: *ui.Signal(bool),
    pending_only: *ui.Signal(bool),
    expanded: *ui.Signal(?u64),
    failure: *ui.Signal(bool),
    rows: *ui.Signal([]const Row),
    pending: *ui.Signal(usize),
    ended: *ui.Signal(bool),
    unread: *ui.Signal(usize),
    /// 打开时把焦点给关闭按钮（模板换成 `ui.view.FocusRequest`）。
    focus_seq: *ui.Signal(u32),
    count_buffer: [32]u8 = undefined,
    arenas: [2]std.heap.ArenaAllocator,
    generation: u1 = 0,
    revision: ?u64 = null,
    age_minute: u64 = std.math.maxInt(u64),
    was_open: bool = false,
    dirty: bool = true,
    /// 窗口的撤销入口（宿主胶水写）；没有时立即清除。
    undo: ?undo_ledger.Port = null,
    /// 撤销窗口里的“清除已结束”：每次一批 fact_id（藏起来，Toast 离场后清除）。
    hidden: std.ArrayList(Hidden) = .empty,
    clear_token: u64 = 0,

    const Hidden = struct { token: u64, facts: []u64 };

    pub fn init(scope: *ui.Scope, allocator: std.mem.Allocator, notification_host: *host.Host) !*ViewModel {
        const self = try scope.createState(ViewModel, .{
            .allocator = allocator,
            .host = notification_host,
            .open = try scope.createSignal(bool, false),
            .pending_only = try scope.createSignal(bool, true),
            .expanded = try scope.createSignal(?u64, null),
            .failure = try scope.createSignal(bool, false),
            .rows = try scope.createSignal([]const Row, &.{}),
            .pending = try scope.createSignal(usize, 0),
            .ended = try scope.createSignal(bool, false),
            .unread = try scope.createSignal(usize, 0),
            .focus_seq = try scope.createSignal(u32, 0),
            .arenas = .{ std.heap.ArenaAllocator.init(allocator), std.heap.ArenaAllocator.init(allocator) },
        });
        try scope.onCleanup(ViewModel, self, deinit);
        return self;
    }

    fn deinit(self: *ViewModel) void {
        if (self.undo) |port| port.flushOwner(self);
        for (self.hidden.items) |batch| self.allocator.free(batch.facts);
        self.hidden.deinit(self.allocator);
        if (self.was_open) self.host.coordinator.centerClosed();
        self.was_open = false;
        for (&self.arenas) |*arena| arena.deinit();
    }

    // ── 视图读 ──

    pub fn isOpen(self: *const ViewModel) bool {
        return self.open.get();
    }
    pub fn pendingOnly(self: *const ViewModel) bool {
        return self.pending_only.get();
    }
    pub fn records(self: *const ViewModel) []const Row {
        return self.rows.get();
    }
    /// 头部计数（“N 条”，用户拍板第 4 条）：待处理条数。
    pub fn countText(self: *ViewModel) []const u8 {
        return @import("../../../../shared/base/format.zig").count(&self.count_buffer, self.pending.get());
    }
    pub fn pendingCount(self: *const ViewModel) usize {
        return self.pending.get();
    }
    pub fn hasEnded(self: *const ViewModel) bool {
        return self.ended.get();
    }
    pub fn failed(self: *const ViewModel) bool {
        return self.failure.get();
    }
    /// 铃铛角标：有待处理时显示数量，只有未读时显示一个点。
    pub fn badgeShown(self: *const ViewModel) bool {
        return self.pending.get() > 0 or self.unread.get() > 0;
    }
    pub fn emptyText(self: *const ViewModel) []const u8 {
        return if (self.pending_only.get()) "当前没有待处理提醒" else "暂无重要提醒";
    }
    pub fn emptyHint(self: *const ViewModel) []const u8 {
        return if (self.pending_only.get()) "需要你处理的连接与传输提醒会显示在这里。" else "连接与传输的重要动态会显示在这里。";
    }
    pub fn focusSeq(self: *const ViewModel) u32 {
        return self.focus_seq.get();
    }

    // ── 意图 ──

    pub fn toggle(self: *ViewModel) void {
        self.setOpen(!self.open.peek());
    }
    pub fn setOpen(self: *ViewModel, value: bool) void {
        if (value) self.failure.set(false);
        self.open.set(value);
    }
    pub fn showPending(self: *ViewModel) void {
        self.pending_only.set(true);
        self.dirty = true;
        self.refresh();
    }
    pub fn showRecent(self: *ViewModel) void {
        self.pending_only.set(false);
        self.dirty = true;
        self.refresh();
    }
    pub fn toggleExpand(self: *ViewModel, fact_id: u64) void {
        self.expanded.set(if (self.expanded.peek() == fact_id) null else fact_id);
        self.dirty = true;
        self.refresh();
    }
    /// “清除已结束”：现在已结束的记录先藏起来，弹出带“撤销”的 Toast；Toast 离场后才清除。
    pub fn clear(self: *ViewModel) void {
        const coordinator = &self.host.coordinator;
        var facts: std.ArrayList(u64) = .empty;
        for (coordinator.notification_records.items) |record| {
            if (coordinator.incidentPending(record) or self.isHidden(record.fact_id)) continue;
            facts.append(self.allocator, record.fact_id) catch {
                facts.deinit(self.allocator);
                return coordinator.clearHistory();
            };
        }
        if (facts.items.len == 0) return facts.deinit(self.allocator);
        const owned = facts.toOwnedSlice(self.allocator) catch {
            facts.deinit(self.allocator);
            return coordinator.clearHistory();
        };
        self.clear_token +%= 1;
        const token = self.clear_token;
        self.hidden.append(self.allocator, .{ .token = token, .facts = owned }) catch {
            coordinator.clearHistoryFacts(owned);
            self.allocator.free(owned);
            return;
        };
        self.expanded.set(null);
        self.failure.set(false);
        self.dirty = true;
        self.refresh();
        if (self.undo) |port| {
            _ = port.undoable(.{ .text = "已清除已结束的提醒", .owner = self, .context = self, .token = token, .commit = commitClear, .revert = revertClear });
        } else commitClear(self, token);
    }
    fn takeHidden(self: *ViewModel, token: u64) ?[]u64 {
        for (self.hidden.items, 0..) |batch, i| if (batch.token == token) {
            _ = self.hidden.orderedRemove(i);
            return batch.facts;
        };
        return null;
    }
    fn commitClear(raw: *anyopaque, token: u64) void {
        const self: *ViewModel = @ptrCast(@alignCast(raw));
        const facts = self.takeHidden(token) orelse return;
        defer self.allocator.free(facts);
        self.host.coordinator.clearHistoryFacts(facts);
        self.dirty = true;
    }
    fn revertClear(raw: *anyopaque, token: u64) void {
        const self: *ViewModel = @ptrCast(@alignCast(raw));
        const facts = self.takeHidden(token) orelse return;
        self.allocator.free(facts);
        self.dirty = true;
        self.refresh();
    }
    fn isHidden(self: *const ViewModel, fact_id: u64) bool {
        for (self.hidden.items) |batch| if (std.mem.indexOfScalar(u64, batch.facts, fact_id) != null) return true;
        return false;
    }
    /// 撤销窗口里的批数（测试用）。
    pub fn clearPending(self: *const ViewModel) usize {
        return self.hidden.items.len;
    }
    /// 派发原记录的动作：不可用时留在弹层里显示原因，成功则收起横幅并关闭弹层。
    pub fn invoke(self: *ViewModel, fact_id: u64, index: u8) void {
        self.host.dispatchAction(fact_id, index) catch {
            self.failure.set(true);
            return;
        };
        self.host.coordinator.dismissNotification(fact_id);
        self.open.set(false);
    }

    // ── 宿主同步（每帧） ──

    /// 开合的协调器记账、打开时已读、快照与角标。只在值变化时写信号。
    pub fn sync(self: *ViewModel, window_active: bool) void {
        const coordinator = &self.host.coordinator;
        const opened = self.open.peek();
        if (opened and !self.was_open) {
            coordinator.centerOpened();
            self.dirty = true;
            self.focus_seq.set(self.focus_seq.peek() +% 1);
        }
        if (!opened and self.was_open) coordinator.centerClosed();
        self.was_open = opened;
        if (opened and window_active) coordinator.readHistory();
        self.pending.set(coordinator.historyCount(true));
        self.unread.set(coordinator.unreadHistoryCount());
        if (opened) self.refresh();
    }

    fn refresh(self: *ViewModel) void {
        const coordinator = &self.host.coordinator;
        const minute = if (host.localClock()) |clock| clock.monotonic_ms / 60_000 else |_| self.age_minute;
        if (!self.dirty and self.revision == coordinator.history_revision and self.age_minute == minute) return;
        self.rebuild() catch |err| {
            std.log.debug("notification history: {s}", .{@errorName(err)});
            return;
        };
        self.dirty = false;
        self.revision = coordinator.history_revision;
        self.age_minute = minute;
    }

    fn rebuild(self: *ViewModel) !void {
        const coordinator = &self.host.coordinator;
        const next: u1 = self.generation +% 1;
        _ = self.arenas[next].reset(.retain_capacity);
        const arena = self.arenas[next].allocator();
        const now = (try host.localClock()).monotonic_ms;
        const records_list = coordinator.notification_records.items;
        const total = coordinator.historyCount(false);
        const pending = coordinator.historyCount(true);
        var hidden_ended: usize = 0;
        if (self.hidden.items.len != 0) for (records_list) |record| {
            if (coordinator.isRepresentative(record) and !coordinator.incidentPending(record) and self.isHidden(record.fact_id)) hidden_ended += 1;
        };
        self.ended.set(total > pending + hidden_ended);
        self.pending.set(pending);
        const pending_only = self.pending_only.peek();
        const expanded_fact = self.expanded.peek();
        var rows: std.ArrayList(Row) = .empty;
        var age_buffer: @import("../../../../shared/base/format.zig").Buffer = undefined;
        var i = records_list.len;
        while (i > 0) {
            i -= 1;
            const record = records_list[i];
            if (!coordinator.isRepresentative(record) or (pending_only and !coordinator.incidentPending(record))) continue;
            if (!coordinator.incidentPending(record) and self.isHidden(record.fact_id)) continue;
            const detail = card.extraDetail(record.event);
            const source_text = try card.summary(arena, record.event, record.owner_ended);
            const source_count = coordinator.incidentSourceCount(record);
            const summary = if (source_count > 1) try std.fmt.allocPrint(arena, "{s} 等 {d} 个来源", .{ record.event.owner_name, source_count }) else source_text;
            const failure = record.event.severity == .failure;
            const expandable = (!failure and detail.len > 0) or source_count > 1;
            const expanded = expandable and expanded_fact == record.fact_id;
            const actions = try arena.alloc(Action, record.event.actions.len);
            for (record.event.actions, 0..) |action, index| actions[index] = try actionOf(arena, record, action, index);
            var sources: std.ArrayList(Source) = .empty;
            if (expanded and source_count > 1) for (records_list) |source| {
                if (!source.listed or !notifications.sameIncident(record, source) or !coordinator.isIncidentSource(source)) continue;
                var locate: []const Action = &.{};
                for (source.event.actions, 0..) |action, index| if (action.kind == .locate_owner) {
                    const one = try arena.alloc(Action, 1);
                    one[0] = try actionOf(arena, source, action, index);
                    locate = one;
                    break;
                };
                try sources.append(arena, .{
                    .id = source.fact_id,
                    .label = try std.fmt.allocPrint(arena, "{s} · {s}", .{ source.event.owner_name, if (source.pending()) "待处理" else "已结束" }),
                    .locate = locate,
                });
            };
            try rows.append(arena, .{
                .id = record.fact_id,
                .severity = record.event.severity,
                .title = try arena.dupe(u8, record.event.title),
                .age = try arena.dupe(u8, @import("../../../../shared/base/format.zig").relative(&age_buffer, now, record.published_ms)),
                .summary = summary,
                .actions = actions,
                .expandable = expandable,
                .expanded = expanded,
                .failure = failure,
                .detail = try arena.dupe(u8, detail),
                .details = expanded or (failure and detail.len > 0),
                .sources = sources.items,
            });
        }
        // Equal snapshots keep the signal's current value (and the arena behind it).
        if (ui.reactive.eqlValue([]const Row, self.rows.peek(), rows.items)) return;
        self.generation = next;
        self.rows.set(rows.items);
    }
};

fn actionOf(arena: std.mem.Allocator, record: notifications.NotificationRecord, action: notifications.NotificationAction, index: usize) !Action {
    return .{ .id = record.fact_id *% 4 +% index, .fact_id = record.fact_id, .index = @intCast(index), .label = try arena.dupe(u8, action.label), .disabled = record.owner_ended };
}

test "notification history age text buckets (shared format.relative, now with days)" {
    const relative = @import("../../../../shared/base/format.zig").relative;
    var buffer: [48]u8 = undefined;
    try std.testing.expectEqualStrings("刚刚", relative(&buffer, 59_999, 0));
    try std.testing.expectEqualStrings("5 分钟前", relative(&buffer, 5 * 60_000, 0));
    try std.testing.expectEqualStrings("2 小时前", relative(&buffer, 125 * 60_000, 0));
    try std.testing.expectEqualStrings("1 天前", relative(&buffer, 30 * 60 * 60_000, 0));
}
