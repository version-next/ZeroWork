//! Reactive session state for the session views (the session list's rows, the welcome page's
//! recent rows, the AI 会话 button's bound count).
//!
//! `SessionPhases` is where a window learns which phase each conversation is in. The assistant store
//! tells it about every change as it happens (`Store.observePhases` → `publish`); a row reads its
//! conversation's phase inside an effect (`phase`), so it repaints when — and only when — a phase
//! changes. No view looks rows up to push a phase into them, and nothing walks a tree per frame.
//!
//! `BoundSessions` is the number of top-level conversations bound to an assistant: the lifecycle
//! store tells it after every binding / membership change (`Store.observeBindings`).
const std = @import("std");
const ui = @import("ui");
const store_mod = @import("../../../../ai/assistant_store.zig");
const lifecycle = @import("../../../../ai/session_lifecycle.zig");

pub const Phase = store_mod.Phase;

/// What a window's session views follow once the window binds the shared conversations.
pub const Sources = struct { presentations: *store_mod.Store, lifecycle: *lifecycle.Store };

pub const SessionPhases = struct {
    allocator: std.mem.Allocator,
    /// Bumped by every change; rows subscribe to it.
    revision: *ui.Signal(u64),
    phases: std.AutoHashMapUnmanaged(u64, Phase) = .empty,
    /// The store this board listens to (null: fed by `publish` only, as in tests and previews).
    store: ?*store_mod.Store = null,

    /// A board owned by `scope`. With a `store` it follows that store's conversations until the
    /// Scope is disposed (or `attach` / `detach` changes the store).
    pub fn mount(scope: *ui.Scope, allocator: std.mem.Allocator, store: ?*store_mod.Store) !*SessionPhases {
        const self = try scope.createState(SessionPhases, .{ .allocator = allocator, .revision = try scope.createSignal(u64, 0) });
        try scope.onCleanup(SessionPhases, self, release);
        if (store) |source| try self.attach(source);
        return self;
    }

    /// Follows `store` from now on (the window binds the shared service lazily). Rows built before
    /// keep the phase they were built with until the store reports a change.
    pub fn attach(self: *SessionPhases, store: *store_mod.Store) !void {
        if (self.store == store) return;
        self.detach();
        try store.observePhases(.{ .context = self, .changed = changed });
        self.store = store;
    }

    /// The owner of the store is about to free it: stop listening now (the Scope may live longer).
    pub fn detach(self: *SessionPhases) void {
        if (self.store) |source| source.unobservePhases(self);
        self.store = null;
    }

    fn release(self: *SessionPhases) void {
        self.detach();
        self.phases.deinit(self.allocator);
    }

    fn changed(raw: *anyopaque, conversation: u64, value: Phase) void {
        const self: *SessionPhases = @ptrCast(@alignCast(raw));
        self.publish(conversation, value);
    }

    /// Conversation `id` is now in `value`. Subscribers run only when that is news.
    pub fn publish(self: *SessionPhases, id: u64, value: Phase) void {
        if (self.phases.get(id)) |known| if (known == value) return;
        // Out of memory: the rows keep showing the previous phase rather than a wrong one.
        self.phases.put(self.allocator, id, value) catch return;
        self.revision.set(self.revision.peek() +% 1);
    }

    /// The phase of conversation `id`, subscribing the calling effect to later changes. `initial`
    /// is what the caller knew when it built its row (no change has been published since then).
    pub fn phase(self: *SessionPhases, id: u64, initial: Phase) Phase {
        _ = self.revision.get();
        return self.phases.get(id) orelse initial;
    }
};

test "SessionPhases: a published change bumps the revision once; the same phase again does not" {
    const owner = try ui.reactive.SignalOwner.init(std.testing.allocator);
    defer owner.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, owner);
    defer scope.dispose();
    const board = try SessionPhases.mount(scope, std.testing.allocator, null);
    try std.testing.expectEqual(Phase.idle, board.phase(7, .idle));
    board.publish(7, .running);
    try std.testing.expectEqual(@as(u64, 1), board.revision.peek());
    try std.testing.expectEqual(Phase.running, board.phase(7, .idle));
    // Another conversation's row keeps what it was built with.
    try std.testing.expectEqual(Phase.done, board.phase(8, .done));
    board.publish(7, .running);
    try std.testing.expectEqual(@as(u64, 1), board.revision.peek());
    board.publish(7, .approval);
    try std.testing.expectEqual(@as(u64, 2), board.revision.peek());
}

test "SessionPhases: follows a store's phase changes and stops when its Scope is disposed" {
    const owner = try ui.reactive.SignalOwner.init(std.testing.allocator);
    defer owner.deinit();
    const root = try ui.Scope.init(std.testing.allocator, null, owner);
    defer root.dispose();
    var store = store_mod.Store.init(std.testing.allocator);
    defer store.deinit();
    const state = try store.create(.{ .tab = 3 });
    const window = try root.childScope();
    const board = try SessionPhases.mount(window, std.testing.allocator, &store);
    store.setPhase(state, .running);
    try std.testing.expectEqual(Phase.running, board.phase(state.id, .idle));
    try std.testing.expectEqual(@as(usize, 1), store.phase_observers.items.len);
    window.dispose();
    try std.testing.expectEqual(@as(usize, 0), store.phase_observers.items.len);
    // A later change reaches nobody (and touches no freed board).
    store.setPhase(state, .done);
}

pub const BoundSessions = struct {
    /// The count; the AI 会话 button's badge and accessible name follow it.
    count: *ui.Signal(usize),
    store: ?*lifecycle.Store = null,

    pub fn mount(scope: *ui.Scope, store: ?*lifecycle.Store) !*BoundSessions {
        const self = try scope.createState(BoundSessions, .{ .count = try scope.createSignal(usize, 0) });
        try scope.onCleanup(BoundSessions, self, detach);
        if (store) |source| try self.attach(source);
        return self;
    }

    /// Follows `store` from now on, starting with its current count.
    pub fn attach(self: *BoundSessions, store: *lifecycle.Store) !void {
        if (self.store == store) return;
        self.detach();
        try store.observeBindings(.{ .context = self, .changed = changed });
        self.store = store;
        self.count.set(store.boundCount());
    }

    /// Stops following the store (its owner is about to free it, or the Scope is disposed).
    pub fn detach(self: *BoundSessions) void {
        if (self.store) |source| source.unobserveBindings(self);
        self.store = null;
    }

    fn changed(raw: *anyopaque) void {
        const self: *BoundSessions = @ptrCast(@alignCast(raw));
        self.count.set(self.store.?.boundCount());
    }
};

test "BoundSessions: follows bind / unbind / removal and stops when its Scope is disposed" {
    const owner = try ui.reactive.SignalOwner.init(std.testing.allocator);
    defer owner.deinit();
    const root = try ui.Scope.init(std.testing.allocator, null, owner);
    defer root.dispose();
    var store = lifecycle.Store.init(std.testing.allocator);
    defer store.deinit();
    const window = try root.childScope();
    const bound = try BoundSessions.mount(window, &store);
    try std.testing.expectEqual(@as(usize, 0), bound.count.peek());
    const agent = try store.attach(.{ .tab = 1 });
    _ = try store.create(agent.id);
    try std.testing.expectEqual(@as(usize, 1), bound.count.peek());
    try std.testing.expectEqual(@as(usize, 1), store.binding_observers.items.len);
    window.dispose();
    try std.testing.expectEqual(@as(usize, 0), store.binding_observers.items.len);
}

test "SessionPhases / BoundSessions: two windows on one shared store both follow it; closing one leaves the other" {
    // The shared stores outlive every window (the application's AI service; windows close first).
    var presentations = store_mod.Store.init(std.testing.allocator);
    defer presentations.deinit();
    var records = lifecycle.Store.init(std.testing.allocator);
    defer records.deinit();
    const owner = try ui.reactive.SignalOwner.init(std.testing.allocator);
    defer owner.deinit();
    const root = try ui.Scope.init(std.testing.allocator, null, owner);
    defer root.dispose();
    const first = try root.childScope();
    const second = try root.childScope();
    const phases_a = try SessionPhases.mount(first, std.testing.allocator, &presentations);
    const phases_b = try SessionPhases.mount(second, std.testing.allocator, &presentations);
    const bound_a = try BoundSessions.mount(first, &records);
    const bound_b = try BoundSessions.mount(second, &records);
    const state = try presentations.create(.{ .tab = 5 });
    // A turn started from window A's host is seen by window B's rows.
    presentations.setPhase(state, .running);
    try std.testing.expectEqual(Phase.running, phases_a.phase(state.id, .idle));
    try std.testing.expectEqual(Phase.running, phases_b.phase(state.id, .idle));
    const agent = try records.attach(.{ .tab = 5 });
    _ = try records.create(agent.id);
    try std.testing.expectEqual(@as(usize, 1), bound_a.count.peek());
    try std.testing.expectEqual(@as(usize, 1), bound_b.count.peek());
    first.dispose();
    try std.testing.expectEqual(@as(usize, 1), presentations.phase_observers.items.len);
    try std.testing.expectEqual(@as(usize, 1), records.binding_observers.items.len);
    presentations.setPhase(state, .approval);
    try std.testing.expectEqual(Phase.approval, phases_b.phase(state.id, .idle));
}
