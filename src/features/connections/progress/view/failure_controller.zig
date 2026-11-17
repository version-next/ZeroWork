//! Owner of the failure view's reactive state (`connection_failure.yix`). The
//! imperative progress View feeds it a projection; clicks come back here and
//! are forwarded to the View's callbacks. No layout or styling lives here.
const std = @import("std");
const ui = @import("ui");
const m = @import("../model/failure_view.zig");
const template = @import("_connection_failure.yix.zig");

pub const Action = enum { edit, toggle_logs, stop_retry, retry_now, credentials, disconnect, trust_key };
pub const Sink = struct {
    context: *anyopaque,
    act: *const fn (*anyopaque, Action) void,
};

pub const FailureView = struct {
    cx: *ui.Cx,
    root: *ui.Node = undefined,
    projection: *ui.Signal(m.Projection),
    /// “替换主机密钥”先弹原生确认框（`shared/ui/confirm`），确认后才交给宿主。
    trust_confirm: *ui.Signal(bool),
    sink: Sink,
    /// The projection is built here and discarded after publication.
    scratch: std.heap.ArenaAllocator,
    /// Published strings and row arrays are interned for the view's
    /// lifetime: reactive consumers (memoised text, keyed rows) compare
    /// against the previous value lazily, so nothing published may be freed
    /// while the view exists. Distinct values per attempt are few (titles,
    /// countdown seconds, log lines), so this stays small.
    interned: std.heap.ArenaAllocator,
    strings: std.StringHashMapUnmanaged(void) = .empty,
    hop_arrays: std.AutoHashMapUnmanaged(u64, []const m.HopRow) = .empty,
    log_arrays: std.AutoHashMapUnmanaged(u64, []const m.LogLine) = .empty,
    generation: u64 = 0,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, sink: Sink) !*FailureView {
        const self = try scope.createState(FailureView, .{
            .cx = cx,
            .projection = try scope.createSignal(m.Projection, .{}),
            .trust_confirm = try scope.createSignal(bool, false),
            .sink = sink,
            .scratch = .init(cx.allocator),
            .interned = .init(cx.allocator),
        });
        try scope.onCleanup(FailureView, self, cleanup);
        self.root = try ui.view.render(scope, cx, template.ConnectionFailure(.{ .vm = self }));
        return self;
    }

    /// Allocator for building the next publication.
    pub fn nextAllocator(self: *FailureView) std.mem.Allocator {
        _ = self.scratch.reset(.retain_capacity);
        return self.scratch.allocator();
    }
    pub fn publish(self: *FailureView, value: m.Projection) !void {
        var next = value;
        inline for (@typeInfo(m.Projection).@"struct".field_names) |name| {
            if (@TypeOf(@field(value, name)) == []const u8) @field(next, name) = try self.string(@field(value, name));
        }
        next.hops = try self.hopRows(value.hops);
        next.log_lines = try self.logRows(value.log_lines);
        self.generation +%= 1;
        next.generation = self.generation;
        self.projection.set(next);
    }
    pub fn hide(self: *FailureView) void {
        self.trust_confirm.set(false);
        if (self.projection.peek().shown) self.projection.set(.{ .generation = self.generation });
    }
    pub fn isShown(self: *const FailureView) bool {
        return self.projection.peek().shown;
    }

    fn string(self: *FailureView, value: []const u8) ![]const u8 {
        if (self.strings.getKey(value)) |stable| return stable;
        const owned = try self.interned.allocator().dupe(u8, value);
        try self.strings.put(self.cx.allocator, owned, {});
        return owned;
    }
    fn hopRows(self: *FailureView, rows: []const m.HopRow) ![]const m.HopRow {
        var hash = std.hash.Wyhash.init(rows.len);
        for (rows) |row| hash.update(std.mem.asBytes(&row.key));
        const key = hash.final();
        if (self.hop_arrays.get(key)) |stable| return stable;
        const owned = try self.interned.allocator().alloc(m.HopRow, rows.len);
        for (rows, owned) |row, *slot| slot.* = .{ .key = row.key, .name = try self.string(row.name), .address = try self.string(row.address), .status = try self.string(row.status), .tone = row.tone };
        try self.hop_arrays.put(self.cx.allocator, key, owned);
        return owned;
    }
    fn logRows(self: *FailureView, rows: []const m.LogLine) ![]const m.LogLine {
        var hash = std.hash.Wyhash.init(rows.len);
        for (rows) |row| hash.update(std.mem.asBytes(&row.id));
        const key = hash.final();
        if (self.log_arrays.get(key)) |stable| return stable;
        const owned = try self.interned.allocator().alloc(m.LogLine, rows.len);
        for (rows, owned) |row, *slot| slot.* = .{ .id = row.id, .text = try self.string(row.text) };
        try self.log_arrays.put(self.cx.allocator, key, owned);
        return owned;
    }

    // Template readers.
    pub fn p(self: *FailureView) m.Projection {
        return self.projection.get();
    }
    pub fn shown(self: *FailureView) bool {
        return self.projection.get().shown;
    }
    pub fn holdShown(self: *FailureView) bool {
        const value = self.projection.get();
        return !value.retry_shown and value.hold_text.len != 0;
    }
    pub fn logsDisabled(self: *FailureView) bool {
        return !self.projection.get().has_logs;
    }
    pub fn logLines(self: *FailureView) []const m.LogLine {
        return self.projection.get().log_lines;
    }
    pub fn act(self: *FailureView, action: Action) void {
        // Replacing a host key is irreversible: confirm first (CONSISTENCY_AUDIT #2).
        if (action == .trust_key) return self.trust_confirm.set(true);
        self.sink.act(self.sink.context, action);
    }

    /// The host-key confirmation accepted: now the host replaces the key.
    pub fn trustConfirmed(self: *FailureView) void {
        self.trust_confirm.set(false);
        if (!self.projection.peek().trust_key) return;
        self.sink.act(self.sink.context, .trust_key);
    }

    fn cleanup(self: *FailureView) void {
        self.strings.deinit(self.cx.allocator);
        self.hop_arrays.deinit(self.cx.allocator);
        self.log_arrays.deinit(self.cx.allocator);
        self.scratch.deinit();
        self.interned.deinit();
    }
};
