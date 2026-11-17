//! 会话记录卡片的列表栏 view-model（PLUGIN_ARCH_PLAN 5.2 PL4b 的 `ListVm`）。
//!
//! 状态：记录目录（只读元信息，`history_list.Model`）、来源与类型筛选、搜索词、翻页、删除确认、
//! 消息与重试。不知道详情区的存在，也不直接打开任何东西：“查看”与“导出”经 `Events` 交给卡片
//! （`CardVm`）。功能以原 `HistoryHost` 的代码为准：读取目录、筛选（全部 / SSH / 本地）、搜索主机 /
//! 用户 / 地址、每页 100 条、清空、逐条删除（录制文件一起删除）、导出、失败重试。
//!
//! 删除与清空是可撤销操作（CONSISTENCY_AUDIT #2，`shared/ui/confirm` 的 `undoable`）：点了就把这些记录从列表里藏起来并弹出
//! 带“撤销”的 Toast；删除作业已经准备好（记下记录 key 与清单版本）但不启动，Toast 离场后才启动（`commit`），点“撤销”则丢掉
//! 作业、记录重新显示（`revert`）。同一时间只有一个作业在跑，其余已提交的排队；卡片销毁前未结局的一律提交。
//!
//! 目录读取与删除在后台作业里进行；宿主每帧调 `poll`，作业结束或状态变化时才重建行快照，
//! 值相同不写信号。行里的字符串在两块交替的 arena 里：新快照写进另一块，上一份在下次重建前有效。
const std = @import("std");
const ui = @import("ui");
const catalog = @import("../../model/history_list.zig");
const archive_mod = @import("../../../../vt/session_archive.zig");
const loading = @import("../../model/history_archive.zig");
const labels = @import("../../model/record_labels.zig");
const ids = @import("../../model/ids.zig");
const list_state = @import("../../../../shared/base/list_state.zig");
const list_cursor = @import("../../../../shared/base/list_cursor.zig");

pub const TypeFilter = catalog.TypeFilter;
pub const SourceFilter = catalog.SourceFilter;
pub const Tone = labels.Tone;

pub const Row = struct {
    /// 记录在当前筛选结果里的下标（列表 key）。
    id: u64,
    /// 本页里的位置（键盘上下移动与焦点标识）。
    position: usize,
    title: []const u8,
    date: []const u8,
    detail: []const u8,
    state: []const u8,
    tone: Tone,
    can_open: bool,
    can_export: bool,
    view_hint: []const u8,
    export_label: []const u8,
    export_hint: []const u8,
    selected: bool,
};

const undo_ledger = @import("../../../../shared/base/undo_ledger.zig");


/// 一次可撤销的删除：准备好的作业（记录 key + 清单版本），在撤销窗口里、排队中或运行中都把它的记录藏起来。
const Pending = struct { token: u64, job: *loading.DeleteJob };

pub const Events = struct {
    context: *anyopaque,
    /// 点“查看”：卡片选中这一条并在详情区加载。
    view: *const fn (*anyopaque, archive_mod.Descriptor) void,
    /// 点“导出”：宿主弹保存对话框并启动导出作业。
    export_record: *const fn (*anyopaque, archive_mod.Descriptor) anyerror!void,
};

pub const ListVm = struct {
    allocator: std.mem.Allocator,
    archive: *archive_mod.Archive,
    events: Events,
    model: catalog.Model,
    generation: u64 = 0,
    source: ?SourceFilter = null,
    refresh_job: ?*loading.CatalogJob = null,
    /// 正在运行的删除作业（同一时间一个）。
    delete_job: ?*loading.DeleteJob = null,
    /// 窗口的撤销入口（宿主挂载卡片后写）；没有时删除立即提交。
    undo: ?undo_ledger.Port = null,
    /// 撤销窗口里的删除（未启动）。
    undo_pending: std.ArrayList(Pending) = .empty,
    /// 已提交、等着启动的删除。
    queued: std.ArrayList(*loading.DeleteJob) = .empty,
    /// 已经跑完、等目录重读后才消失的记录 key（重读前不让它们闪回）。
    removed_keys: std.ArrayList([]const u8) = .empty,
    undo_token: u64 = 0,
    catalog_failure: bool = false,
    pending_reload: bool = false,
    loaded: bool = false,
    dirty: bool = true,
    /// 卡片选中的记录（`CardVm` 持有内存）；只用来标出选中行。
    selected_key: ?[]const u8 = null,
    /// 列表键盘移动的当前位置（本页内）。
    cursor: ?usize = null,

    rows: *ui.Signal([]const Row),
    filter: *ui.Signal(TypeFilter),
    query_text: *ui.Signal([]const u8),
    count_text: *ui.Signal([]const u8),
    message_text: *ui.Signal([]const u8),
    message_warning: *ui.Signal(bool),
    retry_shown: *ui.Signal(bool),
    clear_disabled: *ui.Signal(bool),
    busy: *ui.Signal(bool),
    paging: *ui.Signal(Paging),
    empty_title: *ui.Signal([]const u8),
    empty_hint: *ui.Signal([]const u8),
    /// 焦点请求：`focus_target` 是 `ids` 里的焦点标识，`focus_seq` 每次请求加一（视图据此生成焦点请求）。
    focus_seq: *ui.Signal(u32),
    focus_target: []const u8 = "",
    /// 列表视口的纵向滚动（两路受控：用户滚动写它，键盘移动时这里写它把焦点行滚进视口）。
    scroll_y: *ui.Signal(f32),
    /// 列表视口高度（宿主每帧写）。
    viewport_height: f32 = 0,

    arenas: [2]std.heap.ArenaAllocator,
    arena_generation: u1 = 0,
    query_buffers: [2]std.ArrayList(u8) = .{ .empty, .empty },
    query_slot: u1 = 0,
    /// 两块交替的缓冲：信号按切片判等，同一块缓冲改写内容不会被当成变化。
    count_buffers: [2][64]u8 = undefined,
    count_slot: u1 = 0,
    toast_buffer: [96]u8 = undefined,
    message_buffers: [2][256]u8 = undefined,
    message_slot: u1 = 0,

    pub const Paging = struct { shown: bool = false, previous: bool = false, next: bool = false };

    pub fn init(scope: *ui.Scope, allocator: std.mem.Allocator, archive: *archive_mod.Archive, events: Events) !*ListVm {
        const self = try scope.createState(ListVm, .{
            .allocator = allocator,
            .archive = archive,
            .events = events,
            .model = catalog.Model.init(allocator, archive),
            .rows = try scope.createSignal([]const Row, &.{}),
            .filter = try scope.createSignal(TypeFilter, .all),
            .query_text = try scope.createSignal([]const u8, ""),
            .count_text = try scope.createSignal([]const u8, "正在读取…"),
            .message_text = try scope.createSignal([]const u8, ""),
            .message_warning = try scope.createSignal(bool, false),
            .retry_shown = try scope.createSignal(bool, false),
            .clear_disabled = try scope.createSignal(bool, true),
            .busy = try scope.createSignal(bool, false),
            .paging = try scope.createSignal(Paging, .{}),
            .empty_title = try scope.createSignal([]const u8, "正在读取会话历史…"),
            .empty_hint = try scope.createSignal([]const u8, ""),
            .focus_seq = try scope.createSignal(u32, 0),
            .scroll_y = try scope.createSignal(f32, 0),
            .arenas = .{ std.heap.ArenaAllocator.init(allocator), std.heap.ArenaAllocator.init(allocator) },
        });
        try scope.onCleanup(ListVm, self, deinit);
        return self;
    }

    fn deinit(self: *ListVm) void {
        // 卡片销毁：撤销窗口里的删除照常提交（进队列），队列里的作业就地跑完。
        if (self.undo) |port| port.flushOwner(self);
        for (self.undo_pending.items) |pending| self.queued.append(self.allocator, pending.job) catch pending.job.deinit();
        self.undo_pending.deinit(self.allocator);
        if (self.refresh_job) |job| job.deinit();
        if (self.delete_job) |job| job.deinit();
        for (self.queued.items) |job| {
            if (job.start()) {
                job.deinit();
            } else |_| job.deinit();
        }
        self.queued.deinit(self.allocator);
        for (self.removed_keys.items) |key| self.allocator.free(key);
        self.removed_keys.deinit(self.allocator);
        self.refresh_job = null;
        self.delete_job = null;
        self.model.deinit();
        for (&self.arenas) |*arena| arena.deinit();
        for (&self.query_buffers) |*buffer| buffer.deinit(self.allocator);
    }

    // ── 视图读 ──

    pub fn records(self: *const ListVm) []const Row {
        return self.rows.get();
    }
    pub fn typeFilter(self: *const ListVm) TypeFilter {
        return self.filter.get();
    }
    pub fn query(self: *const ListVm) []const u8 {
        return self.query_text.get();
    }
    pub fn countText(self: *const ListVm) []const u8 {
        return self.count_text.get();
    }
    pub fn message(self: *const ListVm) []const u8 {
        return self.message_text.get();
    }
    pub fn messageShown(self: *const ListVm) bool {
        return self.message_text.get().len != 0;
    }
    pub fn warning(self: *const ListVm) bool {
        return self.message_warning.get();
    }
    pub fn retryShown(self: *const ListVm) bool {
        return self.retry_shown.get();
    }
    pub fn clearDisabled(self: *const ListVm) bool {
        return self.clear_disabled.get();
    }
    pub fn actionsDisabled(self: *const ListVm) bool {
        return self.busy.get();
    }
    pub fn pagingShown(self: *const ListVm) bool {
        return self.paging.get().shown;
    }
    pub fn previousDisabled(self: *const ListVm) bool {
        return !self.paging.get().previous;
    }
    pub fn nextDisabled(self: *const ListVm) bool {
        return !self.paging.get().next;
    }
    pub fn emptyTitle(self: *const ListVm) []const u8 {
        return self.empty_title.get();
    }
    pub fn emptyHint(self: *const ListVm) []const u8 {
        return self.empty_hint.get();
    }
    pub fn scrollOffset(self: *const ListVm) f32 {
        return self.scroll_y.get();
    }
    /// 用户滚动后的落定位置（视图回写，键盘移动从这里继续算）。
    pub fn scrolled(self: *ListVm, y: f32) void {
        self.scroll_y.set(y);
    }
    pub fn focusSeq(self: *const ListVm) u32 {
        return self.focus_seq.get();
    }
    pub fn focusTarget(self: *const ListVm) []const u8 {
        return self.focus_target;
    }
    pub fn len(self: *const ListVm) usize {
        return self.model.len();
    }
    pub fn descriptorAt(self: *const ListVm, index: usize) ?archive_mod.Descriptor {
        return self.model.descriptorAt(index);
    }

    // ── 意图 ──

    /// 打开 / 重新从入口打开：重置筛选与搜索，按来源筛选重新读取目录（与原目录浮层的 `show` 相同）。
    pub fn show(self: *ListVm, source: ?SourceFilter) void {
        self.source = source;
        self.model.type_filter = .all;
        self.model.query.clearRetainingCapacity();
        self.filter.set(.all);
        self.setQueryText("");
        self.cursor = null;
        self.scroll_y.set(0);
        self.clearMessage();
        if (self.refresh_job != null or self.delete_job != null) {
            self.pending_reload = true;
        } else self.startRefresh();
        self.requestFocus(ids.focus_search);
        self.dirty = true;
    }
    pub fn setQuery(self: *ListVm, text: []const u8) void {
        if (std.mem.eql(u8, text, self.model.query.items)) return;
        self.setQueryText(text);
        self.model.applyFilter(text, self.model.type_filter) catch |err| return self.report(err);
        self.cursor = null;
        self.scroll_y.set(0);
        self.dirty = true;
    }
    pub fn setFilter(self: *ListVm, kind: TypeFilter) void {
        self.model.applyFilter(self.model.query.items, kind) catch |err| return self.report(err);
        self.filter.set(kind);
        self.cursor = null;
        self.scroll_y.set(0);
        self.dirty = true;
    }
    pub fn previousPage(self: *ListVm) void {
        self.model.page -|= 1;
        self.cursor = null;
        self.scroll_y.set(0);
        self.dirty = true;
    }
    pub fn nextPage(self: *ListVm) void {
        if (self.model.pageEnd() < self.model.len()) self.model.page += 1;
        self.cursor = null;
        self.scroll_y.set(0);
        self.dirty = true;
    }
    /// 搜索框回车只把焦点移到第一条的“查看”。
    pub fn submit(self: *ListVm) void {
        if (self.model.pageEnd() > self.model.pageStart()) {
            self.cursor = 0;
            self.requestFocus(ids.rowFocus(0));
        }
    }
    /// 方向键在本页的“查看”之间循环移动焦点。
    pub fn moveCursor(self: *ListVm, down: bool) bool {
        const count = self.rows.peek().len;
        if (count == 0) return false;
        const next = list_cursor.move(self.cursor, count, down, .wrap).?;
        self.cursor = next;
        self.reveal(next);
        self.requestFocus(ids.rowFocus(next));
        return true;
    }
    /// 行距（`history_card.yss` 的记录行 56 + 行间距 2）。
    pub const row_pitch: f32 = 58;
    pub const row_height: f32 = 56;
    /// 把本页第 `position` 行滚进视口。
    fn reveal(self: *ListVm, position: usize) void {
        if (self.viewport_height <= 0) return;
        const top = @as(f32, @floatFromInt(position)) * row_pitch;
        const current = self.scroll_y.peek();
        if (top < current) {
            self.scroll_y.set(top);
        } else if (top + row_height > current + self.viewport_height) self.scroll_y.set(top + row_height - self.viewport_height);
    }
    pub fn view(self: *ListVm, index: u64) void {
        if (self.delete_job != null) return;
        const descriptor = self.model.descriptorAt(@intCast(index)) orelse return;
        self.cursor = std.math.sub(usize, @intCast(index), self.model.pageStart()) catch null;
        if (!descriptor.can_open) {
            self.setMessage(labels.unavailableReason(descriptor), false);
            return;
        }
        self.events.view(self.events.context, descriptor);
    }
    pub fn exportRecord(self: *ListVm, index: u64) void {
        if (self.delete_job != null) return;
        const descriptor = self.model.descriptorAt(@intCast(index)) orelse return;
        if (!descriptor.can_export) return self.report(error.RecordingUnavailable);
        self.events.export_record(self.events.context, descriptor) catch |err| self.report(err);
    }
    pub fn requestClear(self: *ListVm) void {
        self.requestDelete(null) catch |err| self.report(err);
    }
    pub fn requestRowDelete(self: *ListVm, index: u64) void {
        self.requestDelete(@intCast(index)) catch |err| self.report(err);
    }
    /// 删除一条或清空：立即把这些记录藏起来并弹出带“撤销”的 Toast；真正的删除在 Toast 离场后才启动。
    fn requestDelete(self: *ListVm, index: ?usize) !void {
        if (self.refresh_job != null or self.visibleTotal() == 0) return;
        const job = try loading.DeleteJob.prepare(self.archive.*);
        errdefer job.deinit();
        if (index) |value| {
            const descriptor = self.model.descriptorAt(value) orelse return error.InvalidHistoryIndex;
            if (self.isHidden(descriptor.archive_key)) return;
            try job.add(descriptor);
        } else for (0..self.model.len()) |value| {
            const descriptor = self.model.descriptorAt(value).?;
            if (!self.isHidden(descriptor.archive_key)) try job.add(descriptor);
        }
        if (job.targets.items.len == 0) return error.InvalidHistoryIndex;
        self.undo_token +%= 1;
        const token = self.undo_token;
        try self.undo_pending.append(self.allocator, .{ .token = token, .job = job });
        self.clearMessage();
        self.dirty = true;
        const text = if (index != null) "已删除会话记录" else std.fmt.bufPrint(&self.toast_buffer, "已清空会话记录（{d} 条）", .{job.targets.items.len}) catch "已清空会话记录";
        const port = self.undo orelse return self.commitDelete(token);
        _ = port.undoable(.{ .text = text, .owner = self, .context = self, .token = token, .commit = commitUndo, .revert = revertUndo });
        // 焦点回到搜索框（被删的行已经不在了）。
        self.requestFocus(ids.focus_search);
    }

    fn commitUndo(raw: *anyopaque, token: u64) void {
        const self: *ListVm = @ptrCast(@alignCast(raw));
        self.commitDelete(token);
    }
    fn revertUndo(raw: *anyopaque, token: u64) void {
        const self: *ListVm = @ptrCast(@alignCast(raw));
        const job = self.takePending(token) orelse return;
        job.deinit();
        self.dirty = true;
        self.requestFocus(ids.focus_search);
    }
    fn takePending(self: *ListVm, token: u64) ?*loading.DeleteJob {
        for (self.undo_pending.items, 0..) |pending, i| if (pending.token == token) {
            _ = self.undo_pending.orderedRemove(i);
            return pending.job;
        };
        return null;
    }
    /// 撤销窗口结束：作业进队列，空闲时启动。
    fn commitDelete(self: *ListVm, token: u64) void {
        const job = self.takePending(token) orelse return;
        self.queued.append(self.allocator, job) catch {
            job.deinit();
            return self.report(error.OutOfMemory);
        };
        self.startQueued();
        self.dirty = true;
    }
    fn startQueued(self: *ListVm) void {
        if (self.delete_job != null or self.queued.items.len == 0) return;
        const job = self.queued.orderedRemove(0);
        job.start() catch |err| {
            job.deinit();
            return self.report(err);
        };
        self.delete_job = job;
        self.busy.set(true);
        self.setMessage("正在删除会话记录…", false);
    }
    fn jobHides(job: *const loading.DeleteJob, key: []const u8) bool {
        for (job.targets.items) |target| if (std.mem.eql(u8, target.key, key)) return true;
        return false;
    }
    /// 这条记录在撤销窗口里、排队中、正在删或刚删完等重读：不显示。
    fn isHidden(self: *const ListVm, key: []const u8) bool {
        for (self.undo_pending.items) |pending| if (jobHides(pending.job, key)) return true;
        for (self.queued.items) |job| if (jobHides(job, key)) return true;
        if (self.delete_job) |job| if (jobHides(job, key)) return true;
        for (self.removed_keys.items) |removed| if (std.mem.eql(u8, removed, key)) return true;
        return false;
    }
    fn hiding(self: *const ListVm) bool {
        return self.undo_pending.items.len != 0 or self.queued.items.len != 0 or self.delete_job != null or self.removed_keys.items.len != 0;
    }
    /// 不算藏起来的记录。
    pub fn visibleTotal(self: *const ListVm) usize {
        if (!self.hiding()) return self.model.len();
        var n: usize = 0;
        for (0..self.model.len()) |i| {
            if (!self.isHidden(self.model.descriptorAt(i).?.archive_key)) n += 1;
        }
        return n;
    }
    /// 这一条在撤销窗口里（测试与宿主用）。
    pub fn undoPending(self: *const ListVm) usize {
        return self.undo_pending.items.len;
    }
    pub fn retry(self: *ListVm) void {
        if (self.refresh_job != null or self.delete_job != null or self.queued.items.len != 0) return;
        self.clearMessage();
        self.catalog_failure = false;
        self.startRefresh();
        self.dirty = true;
    }
    /// 失败写进列表栏的消息（橙色）并给出“重新读取”。
    pub fn report(self: *ListVm, err: anyerror) void {
        self.setMessage(loading.errorText(err), true);
        self.retry_shown.set(true);
    }
    pub fn setMessage(self: *ListVm, text: []const u8, warn: bool) void {
        self.message_slot +%= 1;
        const buffer = &self.message_buffers[self.message_slot];
        const n = @min(text.len, buffer.len);
        @memcpy(buffer[0..n], text[0..n]);
        self.message_text.set(buffer[0..n]);
        self.message_warning.set(warn);
    }
    pub fn clearMessage(self: *ListVm) void {
        self.message_text.set("");
        self.message_warning.set(false);
        self.retry_shown.set(false);
    }
    /// 卡片选中的记录变了：重画选中行。
    pub fn setSelected(self: *ListVm, key: ?[]const u8) void {
        self.selected_key = key;
        self.dirty = true;
    }

    // ── 宿主同步（每帧） ──

    pub fn poll(self: *ListVm) void {
        if (self.delete_job) |job| if (job.done.load(.acquire)) {
            self.delete_job = null;
            self.busy.set(false);
            defer job.deinit();
            // 删掉的记录在目录重读完成前继续藏着（失败的那些重读后照常出现）。
            for (job.targets.items) |target| {
                const key = self.allocator.dupe(u8, target.key) catch continue;
                self.removed_keys.append(self.allocator, key) catch self.allocator.free(key);
            }
            if (job.failed > 0) {
                var buffer: [256]u8 = undefined;
                self.setMessage(std.fmt.bufPrint(&buffer, "{d} 条记录未能删除：{s}", .{ job.failed, if (job.failure) |err| loading.errorText(err) else "记录正在使用，请稍后重试。" }) catch "部分记录未能删除，请重试。", true);
            } else self.clearMessage();
            self.pending_reload = true;
            self.startQueued();
            self.dirty = true;
        };
        if (self.refresh_job) |job| if (job.done.load(.acquire)) {
            self.refresh_job = null;
            defer job.deinit();
            if (job.generation == self.generation) {
                if (job.failure) |err| {
                    self.catalog_failure = true;
                    self.report(err);
                } else if (job.catalog) |*loaded| {
                    self.catalog_failure = false;
                    if (self.model.install(loaded, self.source)) {
                        job.catalog = null;
                        if (self.delete_job == null and self.queued.items.len == 0) {
                            for (self.removed_keys.items) |key| self.allocator.free(key);
                            self.removed_keys.clearRetainingCapacity();
                        }
                        self.loaded = true;
                        self.model.applyFilter(self.model.query.items, self.model.type_filter) catch |err| self.report(err);
                    } else |err| self.report(err);
                }
                self.dirty = true;
            }
        };
        if (self.pending_reload and self.refresh_job == null and self.delete_job == null) {
            self.pending_reload = false;
            self.startRefresh();
        }
        if (self.dirty) {
            self.dirty = false;
            self.rebuild() catch |err| self.report(err);
        }
    }

    pub fn isLoading(self: *const ListVm) bool {
        return self.refresh_job != null;
    }

    fn startRefresh(self: *ListVm) void {
        self.generation +%= 1;
        self.catalog_failure = false;
        self.refresh_job = loading.CatalogJob.start(self.archive.*, self.generation) catch |err| {
            self.report(err);
            return;
        };
        self.dirty = true;
    }

    fn setQueryText(self: *ListVm, text: []const u8) void {
        const next: u1 = self.query_slot +% 1;
        const buffer = &self.query_buffers[next];
        buffer.clearRetainingCapacity();
        buffer.appendSlice(self.allocator, text) catch return;
        self.query_slot = next;
        self.query_text.set(buffer.items);
    }

    fn requestFocus(self: *ListVm, id: []const u8) void {
        self.focus_target = id;
        self.focus_seq.set(self.focus_seq.peek() +% 1);
    }

    /// 列表占位文案（共享列表状态模型）。
    const empty_copy: list_state.Copy = .{
        .loading = .{ .title = "正在读取会话历史…", .hint = "记录较多时需要几秒。" },
        .failed = .{ .title = "无法读取会话历史", .hint = "可以点下方的“重新读取”再试一次。" },
        .no_match = .{ .title = "没有匹配的历史会话", .hint = "试试其他关键词或会话类型。" },
        .empty = .{ .title = "还没有会话历史", .hint = "会话结束后，可在这里查看日志。" },
    };
    fn rebuild(self: *ListVm) !void {
        const refreshing = self.refresh_job != null;
        const total = self.visibleTotal();
        if (refreshing or self.catalog_failure) {
            self.count_text.set(if (refreshing) "正在读取…" else "");
        } else {
            self.count_slot +%= 1;
            self.count_text.set(@import("../../../../shared/base/format.zig").count(&self.count_buffers[self.count_slot], total));
        }
        self.clear_disabled.set(refreshing or total == 0);
        const filtered = self.model.query.items.len > 0 or self.model.type_filter != .all;
        const placeholder = list_state.placeholder(list_state.resolve(.{ .loading = refreshing, .failed = self.catalog_failure, .count = total }), filtered, empty_copy) orelse (if (filtered) empty_copy.no_match else empty_copy.empty);
        self.empty_title.set(placeholder.title);
        self.empty_hint.set(placeholder.hint);
        self.paging.set(.{ .shown = !refreshing and total > catalog.page_size, .previous = self.model.page > 0, .next = self.model.pageEnd() < total });

        const next: u1 = self.arena_generation +% 1;
        _ = self.arenas[next].reset(.retain_capacity);
        const arena = self.arenas[next].allocator();
        var rows: std.ArrayList(Row) = .empty;
        var position: usize = 0;
        if (!refreshing) for (self.model.pageStart()..self.model.pageEnd()) |index| {
            const descriptor = self.model.descriptorAt(index).?;
            if (self.hiding() and self.isHidden(descriptor.archive_key)) continue;
            defer position += 1;
            const entry = descriptor.entry;
            var date_buffer: [64]u8 = undefined;
            var duration_buffer: [64]u8 = undefined;
            const replay_unavailable = descriptor.replayability == .baseline_unavailable;
            try rows.append(arena, .{
                .id = index,
                .position = position,
                .title = try arena.dupe(u8, if (descriptor.title.len > 0) descriptor.title else entry.host),
                .date = try arena.dupe(u8, labels.dateLabel(&date_buffer, entry.ended_ms)),
                .detail = try std.fmt.allocPrint(arena, "{s}{s}{s} · {s}", .{ entry.user, if (descriptor.endpoint.len > 0) "@" else "", descriptor.endpoint, @import("../../../../shared/base/format.zig").duration(&duration_buffer, entry.duration_ms, .long) }),
                .state = labels.stateLabel(descriptor),
                .tone = labels.stateTone(descriptor),
                .can_open = descriptor.can_open,
                .can_export = descriptor.can_export,
                .view_hint = if (descriptor.can_open) "查看历史会话（只读）" else try arena.dupe(u8, labels.unavailableReason(descriptor)),
                .export_label = if (replay_unavailable) "导出保留片段" else "导出会话录制",
                .export_hint = if (descriptor.can_export) (if (replay_unavailable) "导出保留片段（asciinema cast）" else "导出会话录制") else "没有可导出的录制内容",
                .selected = if (self.selected_key) |key| std.mem.eql(u8, key, descriptor.archive_key) else false,
            });
        };
        if (ui.reactive.eqlValue([]const Row, self.rows.peek(), rows.items)) return;
        self.arena_generation = next;
        self.rows.set(rows.items);
    }
};
