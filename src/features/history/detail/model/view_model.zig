//! 会话记录卡片的详情区 view-model（PLUGIN_ARCH_PLAN 5.2 PL4b 的 `DetailVm`）。
//!
//! 状态：`phase`（空 / 加载中 / 就绪）、记录标题与元信息、只读回放表面。不知道列表的存在。
//! 加载沿用原目录浮层的后台作业（`history_archive.Job`，解码在后台线程，持有整组录制的读租约）；
//! 作业的代次校验沿用原 `HistoryHost.generation`：过期结果丢弃。加载成功后文档交给宿主经
//! `ReplayPort` 挂成只读回放表面（终端视图的归档模式，`features/terminal` 门面导出），回放条
//! （`terminal.history.*`）在表面底部，拖动与跳转由终端视图自己处理。
const std = @import("std");
const ui = @import("ui");
const archive_mod = @import("../../../../vt/session_archive.zig");
const loading = @import("../../model/history_archive.zig");
const labels = @import("../../model/record_labels.zig");

/// 共享列表状态模型（`shared/base/list_state.zig`）；详情区不用 `failed`：加载失败经 `Port.failed` 报给列表栏，自身回到 `empty`。
pub const Phase = @import("../../../../shared/base/list_state.zig").Phase;

/// 宿主挂好的回放表面：`handle` 交回 `release`。表面的节点由宿主放进详情区的插槽，view-model 不碰节点。
pub const Replay = struct { handle: *anyopaque };

pub const Port = struct {
    context: *anyopaque,
    /// 文档的时间线与阅读模型移进表面；文档本身（读租约）仍归 `DetailVm`，在 `release` 之后销毁。
    mount: *const fn (*anyopaque, *loading.Document) anyerror!Replay,
    release: *const fn (*anyopaque, Replay) void,
    /// 加载失败：交给卡片写进列表栏的消息（与原目录浮层相同）。
    failed: *const fn (*anyopaque, anyerror) void,
};

pub const DetailVm = struct {
    allocator: std.mem.Allocator,
    archive: *archive_mod.Archive,
    port: Port,
    job: ?*loading.Job = null,
    generation: u64 = 0,
    document: ?*loading.Document = null,
    replay: ?Replay = null,
    shown_key: std.ArrayList(u8) = .empty,
    pending_key: std.ArrayList(u8) = .empty,
    pending_title: std.ArrayList(u8) = .empty,
    pending_meta: std.ArrayList(u8) = .empty,
    pending_tone: labels.Tone = .neutral,
    pending_state: []const u8 = "",
    title_buffers: [2]std.ArrayList(u8) = .{ .empty, .empty },
    meta_buffers: [2]std.ArrayList(u8) = .{ .empty, .empty },
    text_slot: u1 = 0,

    phase: *ui.Signal(Phase),
    title: *ui.Signal([]const u8),
    meta: *ui.Signal([]const u8),
    state: *ui.Signal([]const u8),
    tone: *ui.Signal(labels.Tone),

    pub fn init(scope: *ui.Scope, allocator: std.mem.Allocator, archive: *archive_mod.Archive, port: Port) !*DetailVm {
        const self = try scope.createState(DetailVm, .{
            .allocator = allocator,
            .archive = archive,
            .port = port,
            .phase = try scope.createSignal(Phase, .empty),
            .title = try scope.createSignal([]const u8, ""),
            .meta = try scope.createSignal([]const u8, ""),
            .state = try scope.createSignal([]const u8, ""),
            .tone = try scope.createSignal(labels.Tone, .neutral),
        });
        try scope.onCleanup(DetailVm, self, deinit);
        return self;
    }

    fn deinit(self: *DetailVm) void {
        if (self.job) |job| job.deinit();
        self.job = null;
        self.releaseShown();
        self.shown_key.deinit(self.allocator);
        self.pending_key.deinit(self.allocator);
        self.pending_title.deinit(self.allocator);
        self.pending_meta.deinit(self.allocator);
        for (&self.title_buffers) |*buffer| buffer.deinit(self.allocator);
        for (&self.meta_buffers) |*buffer| buffer.deinit(self.allocator);
    }

    // ── 视图读 ──

    pub fn currentPhase(self: *const DetailVm) Phase {
        return self.phase.get();
    }
    pub fn recordTitle(self: *const DetailVm) []const u8 {
        return self.title.get();
    }
    pub fn recordMeta(self: *const DetailVm) []const u8 {
        return self.meta.get();
    }
    pub fn stateLabel(self: *const DetailVm) []const u8 {
        return self.state.get();
    }
    pub fn stateTone(self: *const DetailVm) labels.Tone {
        return self.tone.get();
    }

    /// 列表里应当标为选中的记录：正在加载的那条，否则正在显示的那条。
    pub fn selectedKey(self: *const DetailVm) ?[]const u8 {
        if (self.job != null) return self.pending_key.items;
        if (self.replay != null) return self.shown_key.items;
        return null;
    }
    pub fn isLoading(self: *const DetailVm) bool {
        return self.job != null;
    }

    // ── 意图 ──

    /// 选中一条记录：已在显示则不动；正在加载另一条时拒绝（与原目录浮层相同，`HistoryLoadBusy`）。
    pub fn load(self: *DetailVm, descriptor: archive_mod.Descriptor) !void {
        if (self.job) |job| {
            if (std.mem.eql(u8, job.key, descriptor.archive_key)) return;
            return error.HistoryLoadBusy;
        }
        if (self.replay != null and std.mem.eql(u8, self.shown_key.items, descriptor.archive_key)) return;
        try replaceText(self.allocator, &self.pending_key, descriptor.archive_key);
        try replaceText(self.allocator, &self.pending_title, if (descriptor.title.len > 0) descriptor.title else descriptor.entry.host);
        var date_buffer: [64]u8 = undefined;
        var duration_buffer: [64]u8 = undefined;
        self.pending_meta.clearRetainingCapacity();
        try self.pending_meta.print(self.allocator, "{s}{s}{s} · {s} · {s}", .{ descriptor.entry.user, if (descriptor.endpoint.len > 0) "@" else "", descriptor.endpoint, labels.dateLabel(&date_buffer, descriptor.entry.ended_ms), @import("../../../../shared/base/format.zig").duration(&duration_buffer, descriptor.entry.duration_ms, .long) });
        self.pending_state = labels.stateLabel(descriptor);
        self.pending_tone = labels.stateTone(descriptor);
        self.generation +%= 1;
        self.job = try loading.Job.start(self.archive.*, descriptor.archive_key, descriptor.manifest_revision, self.generation);
        if (self.replay == null) self.phase.set(.loading);
    }

    /// 取消正在进行的加载（Esc / 关闭卡片）。
    pub fn cancel(self: *DetailVm) void {
        const job = self.job orelse return;
        self.generation +%= 1;
        job.cancel.store(true, .release);
    }

    // ── 宿主同步（每帧） ──

    pub fn poll(self: *DetailVm) void {
        const job = self.job orelse return;
        if (!job.done.load(.acquire)) return;
        self.job = null;
        defer job.deinit();
        if (job.generation != self.generation) {
            if (self.replay == null) self.phase.set(.empty);
            return;
        }
        if (job.failure) |err| {
            if (self.replay == null) self.phase.set(.empty);
            self.port.failed(self.port.context, err);
            return;
        }
        const document = job.document orelse {
            if (self.replay == null) self.phase.set(.empty);
            return;
        };
        const replay = self.port.mount(self.port.context, document) catch |err| {
            if (self.replay == null) self.phase.set(.empty);
            self.port.failed(self.port.context, err);
            return;
        };
        job.document = null;
        self.releaseShown();
        self.document = document;
        self.replay = replay;
        replaceText(self.allocator, &self.shown_key, self.pending_key.items) catch {};
        self.publishText();
        self.phase.set(.ready);
    }

    fn publishText(self: *DetailVm) void {
        const next: u1 = self.text_slot +% 1;
        replaceText(self.allocator, &self.title_buffers[next], self.pending_title.items) catch return;
        replaceText(self.allocator, &self.meta_buffers[next], self.pending_meta.items) catch return;
        self.text_slot = next;
        self.title.set(self.title_buffers[next].items);
        self.meta.set(self.meta_buffers[next].items);
        self.state.set(self.pending_state);
        self.tone.set(self.pending_tone);
    }

    fn releaseShown(self: *DetailVm) void {
        if (self.replay) |replay| {
            self.port.release(self.port.context, replay);
        }
        self.replay = null;
        if (self.document) |document| document.destroy();
        self.document = null;
    }
};

fn replaceText(allocator: std.mem.Allocator, buffer: *std.ArrayList(u8), text: []const u8) !void {
    buffer.clearRetainingCapacity();
    try buffer.appendSlice(allocator, text);
}
