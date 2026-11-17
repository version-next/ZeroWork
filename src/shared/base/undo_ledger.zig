//! 撤销账本（CONSISTENCY_AUDIT #2；用户拍板 2“可撤销的操作直接执行，同时弹带‘撤销’的 Toast”）。
//!
//! 一次可撤销操作分两半：
//! - **立即生效的一半**由调用方在登记前做完，而且必须可恢复：把对象从界面上藏起来、把草稿改掉、记下要删的 id。
//! - **真正的提交**（删文件、写配置、清内存记录）登记在这里，Toast 离场后才做；点“撤销”则改为回滚，提交永远不做。
//!
//! 每条登记的结局只有一个，而且一定会有：
//! - Toast 上点“撤销” → `revert`；
//! - Toast 到期、被关掉、被挤出栈、被宿主收起 → `commit`；
//! - 发不出 Toast（没有通知栈、分配失败）→ 立即 `commit`（没有撤销入口就不能留着悬而未决）；
//! - 登记方销毁前（`flushOwner`）或窗口关闭（`flushAll`）→ 还没结局的一律 `commit`。
//!
//! 本文件只管账，不碰界面：Toast 由窗口注册的 `Sink` 发出，Toast 的结局由窗口回报 `settle`。
const std = @import("std");

pub const Outcome = enum { revert, commit };

/// 一次可撤销操作。`context` / `token` 原样交回两个回调；`owner` 用于 `flushOwner`（通常就是 `context`）。
pub const Spec = struct {
    /// Toast 文案：做了什么（“已删除主机 prod-web”）。
    text: []const u8,
    owner: *anyopaque,
    context: *anyopaque,
    token: u64 = 0,
    commit: *const fn (context: *anyopaque, token: u64) void,
    revert: *const fn (context: *anyopaque, token: u64) void,
};

/// 窗口的 Toast 出口：发一条带“撤销”的 Toast，返回它的 id（之后按这个 id 回报结局）。
pub const Sink = struct {
    context: *anyopaque,
    post: *const fn (context: *anyopaque, text: []const u8) anyerror!u64,
};

/// 登记入口（给 model / view-model 层用：它们不引用界面层，宿主把它接到窗口的账本，
/// 即 `shared/ui/confirm` 的 `port(cx)`）。
pub const Port = struct {
    context: *anyopaque,
    add: *const fn (context: *anyopaque, spec: Spec) bool,
    flush: *const fn (context: *anyopaque, owner: *anyopaque) void,

    /// 登记；返回 true 表示在撤销窗口里，false 表示已经直接提交。
    pub fn undoable(self: Port, spec: Spec) bool {
        return self.add(self.context, spec);
    }
    pub fn flushOwner(self: Port, owner: *anyopaque) void {
        self.flush(self.context, owner);
    }
};

const Entry = struct {
    toast: u64,
    owner: *anyopaque,
    context: *anyopaque,
    token: u64,
    commit: *const fn (*anyopaque, u64) void,
    revert: *const fn (*anyopaque, u64) void,

    fn run(self: Entry, outcome: Outcome) void {
        switch (outcome) {
            .commit => self.commit(self.context, self.token),
            .revert => self.revert(self.context, self.token),
        }
    }
};

pub const Ledger = struct {
    allocator: std.mem.Allocator,
    sink: ?Sink = null,
    pending: std.ArrayList(Entry) = .empty,

    pub fn init(allocator: std.mem.Allocator) Ledger {
        return .{ .allocator = allocator };
    }

    /// 窗口关闭：还没结局的全部提交。
    pub fn deinit(self: *Ledger) void {
        self.flushAll();
        self.pending.deinit(self.allocator);
    }

    pub fn setSink(self: *Ledger, sink: ?Sink) void {
        self.sink = sink;
    }

    /// 登记一次已经立即生效的可撤销操作，并弹出带“撤销”的 Toast。弹不出来就立即提交。
    /// 返回 true 表示进了撤销窗口，false 表示已经直接提交。
    pub fn add(self: *Ledger, spec: Spec) bool {
        const entry_template: Entry = .{ .toast = 0, .owner = spec.owner, .context = spec.context, .token = spec.token, .commit = spec.commit, .revert = spec.revert };
        const sink = self.sink orelse {
            entry_template.run(.commit);
            return false;
        };
        self.pending.ensureUnusedCapacity(self.allocator, 1) catch {
            entry_template.run(.commit);
            return false;
        };
        const toast = sink.post(sink.context, spec.text) catch {
            entry_template.run(.commit);
            return false;
        };
        var entry = entry_template;
        entry.toast = toast;
        self.pending.appendAssumeCapacity(entry);
        return true;
    }

    /// 窗口回报一条 Toast 的结局。未知 id（已结局、别的栈）忽略。
    pub fn settle(self: *Ledger, toast: u64, outcome: Outcome) void {
        for (self.pending.items, 0..) |entry, i| if (entry.toast == toast) {
            // 先出账再回调：回调可能再登记新的撤销。
            _ = self.orderedRemove(i);
            entry.run(outcome);
            return;
        };
    }

    /// 登记方要销毁了：它名下还没结局的全部提交（回调还能安全使用它）。
    pub fn flushOwner(self: *Ledger, owner: *anyopaque) void {
        var i: usize = 0;
        while (i < self.pending.items.len) {
            if (self.pending.items[i].owner != owner) {
                i += 1;
                continue;
            }
            const entry = self.orderedRemove(i);
            entry.run(.commit);
        }
    }

    /// 全部提交（窗口关闭）。
    pub fn flushAll(self: *Ledger) void {
        while (self.pending.items.len != 0) {
            const entry = self.orderedRemove(0);
            entry.run(.commit);
        }
    }

    /// 撤销窗口里还有这一项（界面据此保持隐藏）。
    pub fn isPending(self: *const Ledger, context: *anyopaque, token: u64) bool {
        for (self.pending.items) |entry| if (entry.context == context and entry.token == token) return true;
        return false;
    }

    pub fn count(self: *const Ledger) usize {
        return self.pending.items.len;
    }

    fn orderedRemove(self: *Ledger, i: usize) Entry {
        return self.pending.orderedRemove(i);
    }
};

// ---- Tests ----

const testing = std.testing;

const Probe = struct {
    committed: std.ArrayList(u64) = .empty,
    reverted: std.ArrayList(u64) = .empty,
    posted: std.ArrayList([]const u8) = .empty,
    next_toast: u64 = 100,
    fail_post: bool = false,
    ledger: ?*Ledger = null,

    fn commit(raw: *anyopaque, token: u64) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.committed.append(testing.allocator, token) catch unreachable;
    }
    fn revert(raw: *anyopaque, token: u64) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.reverted.append(testing.allocator, token) catch unreachable;
    }
    fn post(raw: *anyopaque, text: []const u8) anyerror!u64 {
        const self: *Probe = @ptrCast(@alignCast(raw));
        if (self.fail_post) return error.NoToastStack;
        try self.posted.append(testing.allocator, text);
        self.next_toast += 1;
        return self.next_toast;
    }
    fn sink(self: *Probe) Sink {
        return .{ .context = self, .post = post };
    }
    fn spec(self: *Probe, text: []const u8, token: u64) Spec {
        return .{ .text = text, .owner = self, .context = self, .token = token, .commit = commit, .revert = revert };
    }
    fn deinit(self: *Probe) void {
        self.committed.deinit(testing.allocator);
        self.reverted.deinit(testing.allocator);
        self.posted.deinit(testing.allocator);
    }
};

test "undo ledger: undo reverts and never commits; the toast leaving commits once" {
    var probe: Probe = .{};
    defer probe.deinit();
    var ledger = Ledger.init(testing.allocator);
    defer ledger.deinit();
    ledger.setSink(probe.sink());
    try testing.expect(ledger.add(probe.spec("已删除主机 a", 1)));
    try testing.expect(ledger.add(probe.spec("已删除主机 b", 2)));
    try testing.expectEqualStrings("已删除主机 a", probe.posted.items[0]);
    // Nothing is committed while the toasts are up.
    try testing.expectEqual(@as(usize, 0), probe.committed.items.len);
    try testing.expect(ledger.isPending(&probe, 1));
    // 撤销 on the first toast: rollback only.
    ledger.settle(101, .revert);
    try testing.expectEqualSlices(u64, &.{1}, probe.reverted.items);
    try testing.expectEqual(@as(usize, 0), probe.committed.items.len);
    try testing.expect(!ledger.isPending(&probe, 1));
    // A late outcome for the same toast does nothing more.
    ledger.settle(101, .commit);
    try testing.expectEqual(@as(usize, 0), probe.committed.items.len);
    // The second toast expires: commit.
    ledger.settle(102, .commit);
    try testing.expectEqualSlices(u64, &.{2}, probe.committed.items);
    try testing.expectEqual(@as(usize, 0), ledger.count());
    // Unknown toast ids are ignored.
    ledger.settle(999, .revert);
    try testing.expectEqual(@as(usize, 1), probe.reverted.items.len);
}

test "undo ledger: without a toast the operation commits right away" {
    var probe: Probe = .{};
    defer probe.deinit();
    var ledger = Ledger.init(testing.allocator);
    defer ledger.deinit();
    // No sink (no notification stack in this window).
    try testing.expect(!ledger.add(probe.spec("x", 7)));
    try testing.expectEqualSlices(u64, &.{7}, probe.committed.items);
    // The sink fails to post.
    probe.fail_post = true;
    ledger.setSink(probe.sink());
    try testing.expect(!ledger.add(probe.spec("y", 8)));
    try testing.expectEqualSlices(u64, &.{ 7, 8 }, probe.committed.items);
    try testing.expectEqual(@as(usize, 0), ledger.count());
}

test "undo ledger: an owner going away and the window closing commit what is still pending" {
    var a: Probe = .{};
    defer a.deinit();
    var b: Probe = .{};
    defer b.deinit();
    var ledger = Ledger.init(testing.allocator);
    ledger.setSink(a.sink());
    _ = ledger.add(a.spec("a1", 1));
    _ = ledger.add(b.spec("b1", 10));
    _ = ledger.add(a.spec("a2", 2));
    ledger.flushOwner(&a);
    try testing.expectEqualSlices(u64, &.{ 1, 2 }, a.committed.items);
    try testing.expectEqual(@as(usize, 0), b.committed.items.len);
    try testing.expectEqual(@as(usize, 1), ledger.count());
    // Window closes: the rest commits.
    ledger.deinit();
    try testing.expectEqualSlices(u64, &.{10}, b.committed.items);
    try testing.expectEqual(@as(usize, 0), a.reverted.items.len + b.reverted.items.len);
}

test "undo ledger: a callback may register the next undo" {
    const Chain = struct {
        ledger: *Ledger,
        probe: *Probe,
        fn commit(raw: *anyopaque, token: u64) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            Probe.commit(self.probe, token);
            if (token == 1) _ = self.ledger.add(self.probe.spec("next", 2));
        }
    };
    var probe: Probe = .{};
    defer probe.deinit();
    var ledger = Ledger.init(testing.allocator);
    defer ledger.deinit();
    ledger.setSink(probe.sink());
    var chain: Chain = .{ .ledger = &ledger, .probe = &probe };
    _ = ledger.add(.{ .text = "first", .owner = &chain, .context = &chain, .token = 1, .commit = Chain.commit, .revert = Probe.revert });
    ledger.settle(101, .commit);
    try testing.expectEqual(@as(usize, 1), ledger.count());
    ledger.settle(102, .commit);
    try testing.expectEqualSlices(u64, &.{ 1, 2 }, probe.committed.items);
}
