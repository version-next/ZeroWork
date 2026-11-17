//! Frame-first delivery handles (docs/design/append-inbox.md §4.2, §5).
//!
//! `Inbox` is an 8-byte value a producer on any thread can keep and `notify()`. The state it
//! names lives in a process-wide slot table whose memory is never returned: a handle that outlived
//! its scope or its window reads a slot whose generation no longer matches and does nothing, so a
//! late `notify` can never touch freed memory and needs no retain / release.
//!
//! Two kinds of slot share the table:
//! - an **inbox** slot: one per `Cx.createInbox`; records the window slot it belongs to;
//! - a **window** slot: one per `Cx` that has inboxes; records the host wake function.
//! `notify` sets the inbox's pending bit; the first pending inbox of a window sets the window's
//! pending bit, and only that empty -> pending transition calls the host wake. The window asks
//! `windowPending` to decide whether to render, then takes each pending inbox before calling it.
//!
//! Every slot state is one atomic word: generation << 2 | open << 1 | pending. Producers only
//! ever set `pending` with a compare-and-swap against the state they read, so a slot closed or
//! reused in between (generation changed, or open cleared) refuses the write. Opening, closing
//! and taking are main-thread operations of the owning window; the small allocator lock below
//! only orders windows that might live on different threads.
const std = @import("std");
const builtin = @import("builtin");
const registry = @This();

/// wasm32 without the `atomics` feature has neither threads nor 64-bit atomic instructions: a plain
/// word is exact there (the Web host is single-threaded). Everywhere else, a real atomic.
const threaded = !(builtin.cpu.arch.isWasm() and !std.Target.wasm.featureSetHas(builtin.cpu.features, .atomics));
const Word = if (threaded) std.atomic.Value(u64) else struct {
    raw: u64,
    const Order = std.builtin.AtomicOrder;
    pub fn init(value: u64) @This() {
        return .{ .raw = value };
    }
    pub fn load(self: *const @This(), comptime _: Order) u64 {
        return self.raw;
    }
    pub fn store(self: *@This(), value: u64, comptime _: Order) void {
        self.raw = value;
    }
    pub fn cmpxchgWeak(self: *@This(), expected: u64, new: u64, comptime _: Order, comptime _: Order) ?u64 {
        if (self.raw != expected) return self.raw;
        self.raw = new;
        return null;
    }
};

/// Wakes the host event loop. Must be callable from any thread at any time for the life of the
/// process (it may run after the window that installed it is gone): a plain global function such
/// as `platform.Window.postEmptyEvent`, never one bound to per-window memory.
pub const WakeFn = *const fn () void;

const index_bits = 24;
const generation_bits = 40;
const index_mask: u64 = (1 << index_bits) - 1;
const generation_mask: u64 = (1 << generation_bits) - 1;
const open_bit: u64 = 0b10;
const pending_bit: u64 = 0b01;

const first_chunk_len: usize = 64;
const max_chunks = 18;
/// Slots addressable by the chunk table (64 * (2^18 - 1)); below the 24-bit index limit.
pub const capacity: usize = first_chunk_len * ((1 << max_chunks) - 1);

pub const Error = error{ OutOfMemory, TooManyInboxes };

const Slot = struct {
    state: Word = .init(0),
    /// Inbox slot: raw handle of its window slot. Written before `state` publishes the
    /// generation, never rewritten until the slot is closed and reused.
    window: Word = .init(0),
    /// Window slot: the host wake function; may be replaced while open (`setWake`).
    wake: std.atomic.Value(?WakeFn) = .init(null),
    /// Free-list link (index + 1, 0 = end). Under `lock` only.
    next_free: u32 = 0,
};

var chunks: [max_chunks]std.atomic.Value(?[*]Slot) = @splat(.init(null));
var lock: std.atomic.Value(bool) = .init(false);
var free_head: u32 = 0;
var next_unused: u32 = 0;
/// Open slots (diagnostics and leak tests).
var open_slots: std.atomic.Value(u32) = .init(0);

fn acquire() void {
    while (lock.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
}

fn release() void {
    lock.store(false, .release);
}

fn chunkOf(index: usize) struct { usize, usize } {
    const q = index / first_chunk_len + 1;
    const k = std.math.log2_int(usize, q);
    const start = first_chunk_len * ((@as(usize, 1) << @intCast(k)) - 1);
    return .{ k, index - start };
}

fn slotAt(index: usize) ?*Slot {
    if (index >= capacity) return null;
    const k, const offset = chunkOf(index);
    const chunk = chunks[k].load(.acquire) orelse return null;
    return &chunk[offset];
}

fn generationOf(state: u64) u64 {
    return state >> 2;
}

fn indexOf(raw: u64) ?usize {
    const field = raw & index_mask;
    if (field == 0) return null;
    return @intCast(field - 1);
}

fn handleGeneration(raw: u64) u64 {
    return raw >> index_bits;
}

fn lookup(raw: u64) ?*Slot {
    return slotAt(indexOf(raw) orelse return null);
}

/// The slot `raw` names while it is still that generation and open; null otherwise.
fn liveSlot(raw: u64) ?struct { *Slot, u64 } {
    const slot = lookup(raw) orelse return null;
    const state = slot.state.load(.acquire);
    if (generationOf(state) != handleGeneration(raw) or state & open_bit == 0) return null;
    return .{ slot, state };
}

const Mark = enum { refused, already, marked };

/// Set the pending bit of the open slot `raw` names. `refused`: closed or reused.
/// Always a read-modify-write, also when the bit is already set: the consumer clears the bit
/// with a CAS before it reads the data, and a producer that wrote its data and then only *loaded*
/// "already pending" would race that clear (store / load, no ordering under acquire / release) —
/// its data could be missed with nothing pending any more. Writing the same value back puts this
/// producer in the release sequence the consumer's clear synchronizes with.
/// `window_out` receives the slot's window field read under the same generation.
fn markPending(raw: u64, window_out: ?*u64) Mark {
    const slot = lookup(raw) orelse return .refused;
    var state = slot.state.load(.acquire);
    while (true) {
        if (generationOf(state) != handleGeneration(raw) or state & open_bit == 0) return .refused;
        // Read before the CAS: the CAS only succeeds if `state` (this generation, open) is still
        // current, and the window field is written before a generation is published and not
        // rewritten until the slot is closed (which changes `state`).
        if (window_out) |out| out.* = slot.window.load(.acquire);
        state = slot.state.cmpxchgWeak(state, state | pending_bit, .acq_rel, .acquire) orelse
            return if (state & pending_bit != 0) .already else .marked;
    }
}

/// Producer side (any thread).
pub fn notify(raw: u64) void {
    var window: u64 = 0;
    if (markPending(raw, &window) != .marked) return;
    if (markPending(window, null) != .marked) return;
    // The window slot may have been closed (or even reused) since the CAS; a wake function is a
    // process-lifetime global, so calling it is at worst a spurious loop wake.
    const slot = lookup(window) orelse return;
    if (slot.wake.load(.acquire)) |wake| wake();
}

pub fn isOpen(raw: u64) bool {
    return liveSlot(raw) != null;
}

/// Main thread: open a slot. `window` = 0 opens a window slot (with `wake`), otherwise an inbox
/// slot belonging to that window.
pub fn open(window: u64, wake: ?WakeFn) Error!u64 {
    acquire();
    defer release();
    var index: usize = undefined;
    if (free_head != 0) {
        index = free_head - 1;
        const slot = slotAt(index).?;
        free_head = slot.next_free;
        slot.next_free = 0;
    } else {
        if (next_unused >= capacity) return error.TooManyInboxes;
        index = next_unused;
        const k, const offset = chunkOf(index);
        if (offset == 0 and chunks[k].load(.monotonic) == null) {
            const len = first_chunk_len << @intCast(k);
            const fresh = std.heap.page_allocator.alloc(Slot, len) catch return error.OutOfMemory;
            for (fresh) |*s| s.* = .{};
            chunks[k].store(fresh.ptr, .release);
        }
        next_unused += 1;
    }
    const slot = slotAt(index).?;
    const generation = (generationOf(slot.state.load(.monotonic)) + 1) & generation_mask;
    slot.window.store(window, .monotonic);
    slot.wake.store(wake, .monotonic);
    // Publishes the fields above with the new generation.
    slot.state.store(generation << 2 | open_bit, .release);
    _ = open_slots.fetchAdd(1, .monotonic);
    return generation << index_bits | (@as(u64, index) + 1);
}

/// Main thread: close the slot `raw` names if it is still that generation and open; later
/// notifies through it do nothing and a pending notification is dropped. Idempotent.
pub fn close(raw: u64) void {
    const slot = lookup(raw) orelse return;
    var state = slot.state.load(.acquire);
    while (true) {
        if (generationOf(state) != handleGeneration(raw) or state & open_bit == 0) return;
        state = slot.state.cmpxchgWeak(state, state & ~(open_bit | pending_bit), .acq_rel, .acquire) orelse break;
    }
    _ = open_slots.fetchSub(1, .monotonic);
    acquire();
    defer release();
    slot.next_free = free_head;
    free_head = @intCast(indexOf(raw).? + 1);
}

/// Main thread: clear and report the pending bit of an open slot.
pub fn take(raw: u64) bool {
    const slot = lookup(raw) orelse return false;
    var state = slot.state.load(.acquire);
    while (true) {
        if (generationOf(state) != handleGeneration(raw) or state & open_bit == 0) return false;
        if (state & pending_bit == 0) return false;
        state = slot.state.cmpxchgWeak(state, state & ~pending_bit, .acq_rel, .acquire) orelse return true;
    }
}

pub fn pending(raw: u64) bool {
    const slot, const state = liveSlot(raw) orelse return false;
    _ = slot;
    return state & pending_bit != 0;
}

/// Main thread: replace a window slot's wake function.
pub fn setWake(window: u64, wake: ?WakeFn) void {
    const slot, _ = liveSlot(window) orelse return;
    slot.wake.store(wake, .release);
}

pub fn openSlotCount() u32 {
    return open_slots.load(.monotonic);
}

/// Frame-first delivery handle (see `Cx.createInbox`). Copy it to any thread or keep it in a
/// `std.atomic.Value(Inbox)`; `.none` is a handle that never delivers.
pub const Inbox = enum(u64) {
    none = 0,
    _,

    /// Any thread, any time; no allocation, no lock, never blocks. Marks the inbox pending and
    /// wakes the host loop; notifications before the callback runs coalesce into one delivery.
    /// A closed inbox (its scope disposed, its window destroyed) or `.none` does nothing.
    pub fn notify(self: Inbox) void {
        registry.notify(@backingInt(self));
    }

    /// Still open. Advisory (for a producer that wants to stop early): the answer may be stale
    /// as soon as it returns.
    pub fn isOpen(self: Inbox) bool {
        return registry.isOpen(@backingInt(self));
    }
};

// ===== Tests =====

const testing = std.testing;

var test_wakes: std.atomic.Value(u32) = .init(0);
fn countWake() void {
    _ = test_wakes.fetchAdd(1, .monotonic);
}

test "inbox slots: notify coalesces per inbox and wakes a window once until it is taken" {
    test_wakes.store(0, .monotonic);
    const window = try open(0, countWake);
    defer close(window);
    const a = try open(window, null);
    defer close(a);
    const b = try open(window, null);
    defer close(b);
    notify(a);
    notify(a);
    notify(b);
    try testing.expectEqual(@as(u32, 1), test_wakes.load(.monotonic));
    try testing.expect(pending(window));
    try testing.expect(take(window));
    try testing.expect(!take(window));
    try testing.expect(take(a));
    try testing.expect(!take(a));
    try testing.expect(take(b));
    // Taken: the next notify wakes again.
    notify(a);
    try testing.expectEqual(@as(u32, 2), test_wakes.load(.monotonic));
}

test "inbox slots: a closed or reused slot ignores its old handle" {
    test_wakes.store(0, .monotonic);
    const window = try open(0, countWake);
    defer close(window);
    const old = try open(window, null);
    close(old);
    close(old); // idempotent
    try testing.expect(!isOpen(old));
    notify(old);
    try testing.expect(!pending(window));
    // The free list hands the same slot out again with the next generation.
    const reused = try open(window, null);
    defer close(reused);
    try testing.expectEqual(indexOf(old), indexOf(reused));
    try testing.expect(reused != old);
    notify(old);
    try testing.expect(!pending(reused));
    try testing.expectEqual(@as(u32, 0), test_wakes.load(.monotonic));
    notify(reused);
    try testing.expect(pending(reused));
    try testing.expectEqual(@as(u32, 1), test_wakes.load(.monotonic));
}

test "inbox slots: an inbox of a closed window is still marked but wakes nobody" {
    test_wakes.store(0, .monotonic);
    const window = try open(0, countWake);
    const inbox = try open(window, null);
    defer close(inbox);
    close(window);
    notify(inbox);
    try testing.expectEqual(@as(u32, 0), test_wakes.load(.monotonic));
    try testing.expect(!pending(window));
}

test "inbox slots: none, forged and out-of-range handles are no-ops" {
    notify(0);
    notify(index_mask); // index beyond any allocated chunk
    notify(std.math.maxInt(u64));
    try testing.expect(!isOpen(0));
    Inbox.none.notify();
    try testing.expect(!Inbox.none.isOpen());
}

test "inbox slots: chunk addressing covers the table without gaps" {
    var expected_k: usize = 0;
    var expected_offset: usize = 0;
    var index: usize = 0;
    while (index < first_chunk_len * 15) : (index += 1) {
        const k, const offset = chunkOf(index);
        try testing.expectEqual(expected_k, k);
        try testing.expectEqual(expected_offset, offset);
        expected_offset += 1;
        if (expected_offset == first_chunk_len << @intCast(expected_k)) {
            expected_k += 1;
            expected_offset = 0;
        }
    }
    const last_k, const last_offset = chunkOf(capacity - 1);
    try testing.expectEqual(@as(usize, max_chunks - 1), last_k);
    try testing.expectEqual((first_chunk_len << (max_chunks - 1)) - 1, last_offset);
    try testing.expect(capacity <= index_mask);
}

test "inbox slots: growing past the first chunk keeps earlier handles valid" {
    const window = try open(0, null);
    defer close(window);
    var handles: [first_chunk_len * 3]u64 = undefined;
    for (&handles) |*h| h.* = try open(window, null);
    defer for (handles) |h| close(h);
    for (handles) |h| {
        notify(h);
        try testing.expect(take(h));
    }
}

test "inbox slots: a stale producer racing close and reuse never marks the new owner" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const window = try open(0, null);
    defer close(window);
    const Producer = struct {
        target: std.atomic.Value(u64),
        stop: std.atomic.Value(bool) = .init(false),
        fn run(self: *@This()) void {
            while (!self.stop.load(.acquire)) notify(self.target.load(.acquire));
        }
    };
    const first = try open(window, null);
    var producer: Producer = .{ .target = .init(first) };
    const thread = try std.Thread.spawn(.{}, Producer.run, .{&producer});
    var current = first;
    var round: usize = 0;
    while (round < 20_000) : (round += 1) {
        close(current);
        const next = try open(window, null);
        // LIFO free list: the same slot, one generation later.
        try testing.expectEqual(indexOf(current), indexOf(next));
        // The producer still holds a closed generation: it must not have marked this one.
        try testing.expect(!take(next));
        current = next;
        producer.target.store(current, .release);
        _ = take(window);
    }
    producer.stop.store(true, .release);
    thread.join();
    close(current);
}

test "inbox slots: concurrent producers lose no notification across window and inbox takes" {
    if (@import("builtin").single_threaded) return error.SkipZigTest;
    const window = try open(0, null);
    defer close(window);
    const inbox = try open(window, null);
    defer close(inbox);
    const per_thread = 50_000;
    const Producer = struct {
        inbox: u64,
        produced: *std.atomic.Value(u64),
        fn run(self: @This()) void {
            for (0..per_thread) |_| {
                // The data write, then the notify (as an application mailbox would).
                _ = self.produced.fetchAdd(1, .monotonic);
                notify(self.inbox);
            }
        }
    };
    var produced: std.atomic.Value(u64) = .init(0);
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Producer.run, .{Producer{ .inbox = inbox, .produced = &produced }});
    // The frame's order: take the window, then each inbox, then read the data.
    var consumed: u64 = 0;
    const Frame = struct {
        fn deliver(w: u64, i: u64, p: *std.atomic.Value(u64), c: *u64) void {
            if (!take(w)) return;
            if (take(i)) c.* = p.load(.monotonic);
        }
    };
    while (produced.load(.monotonic) < threads.len * per_thread) Frame.deliver(window, inbox, &produced, &consumed);
    for (threads) |t| t.join();
    // Whatever the last frame missed is still pending.
    Frame.deliver(window, inbox, &produced, &consumed);
    try testing.expectEqual(@as(u64, threads.len * per_thread), consumed);
    try testing.expect(!pending(window) and !pending(inbox));
}
