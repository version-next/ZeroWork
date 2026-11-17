const std = @import("std");
const Allocator = std.mem.Allocator;

const SignalBase = @import("signal_base.zig").SignalBase;
const SignalOwner = @import("owner.zig").SignalOwner;
const Scope = @import("scope.zig").Scope;
const eqlValue = @import("eq.zig").eqlValue;
const graph_mod = @import("graph.zig");

const debug_checks = SignalOwner.debug_checks;
const is_test = @import("builtin").is_test;
const alive_sentinel: u32 = 0x5161_A11E;
const dead_sentinel: u32 = 0x5161_DEAD;
const debug_writer_slots = 8;

/// Reactive type marker: `Signal` / `Memo` / `Derived` declare `pub const zenit_reactive`.
/// props normalize (`props.zig`) checks only this marker, no duck type.
pub const ReactiveKind = enum { signal, memo, derived };

/// Owned text signal storage (`scope.createText`). Double-buffer: write target non-current
/// chunk, safe for `set(transform(get()))`. Slice lifetime contract: see `Signal([]const u8)
/// .get` comment. Owned slice double-buffer (`scope.createText` / `scope.createList`): set
/// copy into non-current then switch, so prior slice valid after next write. Shallow copy elements.
///
/// Appends (docs/design/append-inbox.md §3.1): the inactive buffer remembers how many of its
/// leading elements equal the current value (`inactive_prefix`). An append copies only what it
/// lacks (the previous appends' tails) and the new tail, then switches as `store` does; each
/// element is copied at most twice, plus the one-off full copy when a buffer grows (doubling).
pub fn SliceStore(comptime E: type) type {
    // String list owns bytes together: element slices point to this store's byte buffer (same
    // double-buffer as element array)
    const deep = E == []const u8;
    return struct {
        allocator: Allocator,
        bufs: [2][]E = .{ &.{}, &.{} },
        bytes: if (deep) [2][]u8 else void = if (deep) .{ &.{}, &.{} } else {},
        active: u1 = 0,
        /// Leading elements of the inactive buffer equal to the current value's.
        inactive_prefix: usize = 0,
        /// Deep lists: bytes those elements use at the start of the inactive byte buffer, and
        /// bytes the current value uses at the start of the active one.
        inactive_prefix_bytes: if (deep) usize else void = if (deep) 0 else {},
        active_bytes: if (deep) usize else void = if (deep) 0 else {},
        /// See `Signal.appendEpoch`: unchanged by a write that keeps the old value as a prefix.
        /// Drawn from a process-wide counter, so equal epochs also mean the same signal.
        epoch: u64 = 0,
        /// Elements copied (tests: the append cost bound). `grow_copied` counts full refills.
        copied: if (is_test) usize else void = if (is_test) 0 else {},
        grow_copied: if (is_test) usize else void = if (is_test) 0 else {},

        const Self = @This();

        /// Copy `content` into non-current and switch. Two-phase: new ready before switch, fail
        /// returns false, current unchanged, no leak. A replacement: the epoch advances.
        pub fn store(self: *Self, content: []const E) bool {
            const target: u1 = self.active ^ 1;
            self.assertOutside(target, content);
            const used = self.fill2(target, content, &.{}) orelse return self.failed();
            self.active = target;
            // The buffer now inactive holds the old value, not (in general) a prefix of this one.
            self.inactive_prefix = 0;
            if (deep) {
                self.inactive_prefix_bytes = 0;
                self.active_bytes = used;
            }
            self.epoch = nextEpoch();
            return true;
        }

        /// Shallow element lists: overwrite the current elements in place with content-equal
        /// ones whose bits differ (their borrowed fields point elsewhere). Text and string lists
        /// own their bytes: nothing to adopt.
        pub fn adoptEqual(self: *Self, content: []const E) void {
            if (deep or E == u8) return;
            const dst = self.bufs[self.active][0..content.len];
            if (dst.ptr == content.ptr) return;
            if (std.mem.eql(u8, std.mem.sliceAsBytes(dst), std.mem.sliceAsBytes(content))) return;
            @memcpy(dst, content);
        }

        /// Append `tail` to `value` (the active buffer's value) into the non-current buffer
        /// and switch. Same two-phase contract as `store`; the epoch is unchanged.
        pub fn append(self: *Self, value: []const E, tail: []const E) bool {
            const target: u1 = self.active ^ 1;
            self.assertOutside(target, tail);
            const start = self.inactive_prefix;
            const new_len = value.len + tail.len;
            var fits = self.bufs[target].len >= new_len;
            var byte_start: usize = 0;
            if (deep) {
                byte_start = self.inactive_prefix_bytes;
                const needed = byte_start + totalBytes(value[start..]) + totalBytes(tail);
                fits = fits and self.bytes[target].len >= needed;
            }
            if (fits) {
                if (deep) {
                    var off = byte_start;
                    off = self.copyStrings(target, start, off, value[start..]);
                    off = self.copyStrings(target, value.len, off, tail);
                    self.inactive_prefix_bytes = self.active_bytes;
                    self.active_bytes = off;
                } else {
                    @memcpy(self.bufs[target][start..value.len], value[start..]);
                    @memcpy(self.bufs[target][value.len..new_len], tail);
                }
                if (is_test) self.copied += new_len - start;
            } else {
                const used = self.fill2(target, value, tail) orelse return self.failed();
                if (deep) {
                    self.inactive_prefix_bytes = self.active_bytes;
                    self.active_bytes = used;
                }
                if (is_test) self.grow_copied += new_len;
            }
            self.active = target;
            // The buffer now inactive holds exactly `value`: a prefix of the new value.
            self.inactive_prefix = value.len;
            return true;
        }

        /// A failed fill may have replaced part of the target (a deep list's byte buffer): what
        /// it held is no longer a prefix of anything.
        fn failed(self: *Self) bool {
            self.inactive_prefix = 0;
            if (deep) self.inactive_prefix_bytes = 0;
            return false;
        }

        fn totalBytes(items: []const E) usize {
            var total: usize = 0;
            for (items) |str| total += str.len;
            return total;
        }

        fn copyStrings(self: *Self, target: u1, first: usize, byte_offset: usize, items: []const E) usize {
            var off = byte_offset;
            for (items, first..) |str, k| {
                const dst = self.bytes[target][off .. off + str.len];
                @memcpy(dst, str);
                self.bufs[target][k] = dst;
                off += str.len;
            }
            return off;
        }

        /// Contract: callers must not pass slices of the prior-prior value (the write target).
        fn assertOutside(self: *const Self, target: u1, content: []const E) void {
            if (!debug_checks or content.len == 0) return;
            if (self.bufs[target].len > 0) {
                const buf = self.bufs[target];
                const lo = @intFromPtr(buf.ptr);
                const hi = lo + buf.len * @sizeOf(E);
                const p = @intFromPtr(content.ptr);
                std.debug.assert(p + content.len * @sizeOf(E) <= lo or p >= hi);
            }
            if (deep and self.bytes[target].len > 0) {
                // Strings can't point into the prior-prior byte buffer either (growth frees it).
                const lo = @intFromPtr(self.bytes[target].ptr);
                const hi = lo + self.bytes[target].len;
                for (content) |str| {
                    if (str.len == 0) continue;
                    const p = @intFromPtr(str.ptr);
                    std.debug.assert(p + str.len <= lo or p >= hi);
                }
            }
        }

        /// Write to `target` buffer (no switch). Fail returns false, target invalid.
        pub fn fill(self: *Self, target: u1, content: []const E) bool {
            const used = self.fill2(target, content, &.{}) orelse return false;
            if (deep and target == self.active) self.active_bytes = used;
            return true;
        }

        /// `fill` of `head ++ tail`; returns the bytes the strings use (deep lists, else 0).
        fn fill2(self: *Self, target: u1, head: []const E, tail: []const E) ?usize {
            const len = head.len + tail.len;
            if (deep) {
                const total = totalBytes(head) + totalBytes(tail);
                if (self.bytes[target].len < total) {
                    const cap = @max(total, self.bytes[target].len * 2, 64);
                    const fresh = self.allocator.alloc(u8, cap) catch return null;
                    self.allocator.free(self.bytes[target]);
                    self.bytes[target] = fresh;
                }
            }
            if (self.bufs[target].len < len) {
                const cap = @max(len, self.bufs[target].len * 2, 16);
                const fresh = self.allocator.alloc(E, cap) catch return null;
                self.allocator.free(self.bufs[target]);
                self.bufs[target] = fresh;
            }
            if (deep) {
                const off = self.copyStrings(target, 0, 0, head);
                return self.copyStrings(target, head.len, off, tail);
            }
            @memcpy(self.bufs[target][0..head.len], head);
            @memcpy(self.bufs[target][head.len..len], tail);
            return 0;
        }

        pub fn current(self: *const Self, len: usize) []const E {
            return self.bufs[self.active][0..len];
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.bufs[0]);
            self.allocator.free(self.bufs[1]);
            if (deep) {
                self.allocator.free(self.bytes[0]);
                self.allocator.free(self.bytes[1]);
            }
        }
    };
}

/// Append epochs are unique across the process (0 is reserved for static sources): a reader
/// that kept (epoch, length) from one source and now reads another never mistakes it for an
/// extension.
/// (wasm32 without the `atomics` feature has no threads and no 64-bit atomics: a plain counter.)
const threaded = !(@import("builtin").cpu.arch.isWasm() and !std.Target.wasm.featureSetHas(@import("builtin").cpu.features, .atomics));
var epoch_counter: if (threaded) std.atomic.Value(u64) else u64 = if (threaded) .init(1) else 1;

pub fn nextEpoch() u64 {
    if (!threaded) {
        defer epoch_counter += 1;
        return epoch_counter;
    }
    return epoch_counter.fetchAdd(1, .monotonic);
}

/// Owned text storage
pub const TextStore = SliceStore(u8);

/// `T` = `[]const E` -> `E`, else void (no owned storage)
pub fn SliceElem(comptime T: type) type {
    const info = @typeInfo(T);
    if (info == .pointer and info.pointer.size == .slice and info.pointer.attrs.@"const" and info.pointer.sentinel_ptr == null) return info.pointer.child;
    return void;
}

/// Signal(T): generic reactive data source
///
/// Usage:
/// ```zig
/// var owner = try SignalOwner.init(allocator);
/// defer owner.deinit();
///
/// const count = try owner.createSignal(i32, 0);
/// count.set(42);        // notify subscribers
/// const val = count.get(); // auto-register dependency
/// ```
pub fn Signal(comptime T: type) type {
    return struct {
        base: SignalBase,
        value: T,
        owner: *SignalOwner,
        /// Only `scope.createText` / `scope.createList` slices non-empty: value in signal's own
        /// double-buffer (owned).
        slice_store: if (has_store) ?*SliceStore(SliceElem(T)) else void = if (has_store) null else {},
        debug: Debug = .{},

        const Self = @This();
        pub const Value = T;
        pub const zenit_reactive: ReactiveKind = .signal;
        const has_store = SliceElem(T) != void;

        /// Debug diagnostic state (docs/SIGNAL_API_DESIGN.md section 4.11); Release empty struct.
        pub const Debug = if (debug_checks) struct {
            alive: u32 = alive_sentinel,
            /// Owning scope (owner arena path = null); borrow check use.
            scope: ?*Scope = null,
            writers: [debug_writer_slots]usize = @as([debug_writer_slots]usize, @splat(0)),
            writer_next: u8 = 0,
        } else struct {};

        inline fn checkAlive(self: *const Self) void {
            if (debug_checks) {
                if (self.debug.alive != alive_sentinel) {
                    std.debug.panic("Signal({s}) used after its scope was disposed", .{@typeName(T)});
                }
            }
        }

        /// Owning scope; owner arena path or Release build = null.
        pub fn debugScope(self: *const Self) ?*Scope {
            return if (debug_checks) self.debug.scope else null;
        }

        /// Most recent writer return address (new to old, 0 = empty slot). Release empty.
        pub fn debugRecentWriters(self: *const Self) [debug_writer_slots]usize {
            if (!debug_checks) return @as([debug_writer_slots]usize, @splat(0));
            var out: [debug_writer_slots]usize = undefined;
            for (0..debug_writer_slots) |i| {
                const idx = (@as(usize, self.debug.writer_next) + debug_writer_slots - 1 - i) % debug_writer_slots;
                out[i] = self.debug.writers[idx];
            }
            return out;
        }

        /// owner path low-level: allocate in owner arena, freed with owner, no manual free.
        /// App/component code uses `scope.createSignal` (freed with scope).
        pub fn create(owner: *SignalOwner, initial: T) !*Self {
            owner.assertThread();
            const signal = try owner.allocator().create(Self);
            signal.* = .{
                .base = SignalBase.init(owner.allocator(), &vtable),
                .value = initial,
                .owner = owner,
            };

            // Register to owner
            try owner.registerSignal(&signal.base);

            // Sync register NodeId to graph
            const gid = try owner.graph.createSignal();
            signal.base.graph_node_raw = @bitCast(gid);

            return signal;
        }

        /// Create Signal in Scope (retain mode path)
        ///
        /// Use scope.allocator, register to scope (not Arena)
        pub fn createInScope(scope: *Scope, initial: T) !*Self {
            scope.owner.assertThread();
            const signal = try scope.allocator.create(Self);
            errdefer scope.allocator.destroy(signal);
            signal.* = .{
                .base = SignalBase.init(scope.allocator, &scope_vtable),
                .value = initial,
                .owner = scope.owner,
            };
            if (debug_checks) signal.debug.scope = scope;
            // Scope path: subscribers list also scope.allocator
            signal.base.scope_allocator = scope.allocator;

            const gid = try scope.owner.graph.createSignal();
            errdefer scope.owner.graph.destroyNode(gid);
            // Publish in the scope only after graph allocation succeeds.
            try scope.registerSignal(&signal.base);
            signal.base.graph_node_raw = @bitCast(gid);

            return signal;
        }

        /// Vtable (owner arena path, freed with owner)
        const vtable = SignalBase.VTable{
            .cleanup = cleanupImpl,
        };

        /// Vtable (Scope path, single free support)
        const scope_vtable = SignalBase.VTable{
            .cleanup = cleanupImpl,
            .destroy = destroyImpl,
        };

        fn cleanupImpl(base: *SignalBase) void {
            // Arena allocator auto-frees all
            _ = base;
        }

        fn destroyImpl(base: *SignalBase, allocator: Allocator) void {
            const self: *Self = @alignCast(@fieldParentPtr("base", base));
            // subscribers field deleted; graph.destroyNode handles edges
            if (has_store) {
                if (self.slice_store) |ts| {
                    ts.deinit();
                    allocator.destroy(ts);
                }
            }
            if (debug_checks) self.debug.alive = dead_sentinel;
            allocator.destroy(self);
        }

        /// Read value + auto-register dependency
        ///
        /// Single-track tracking: graph.tracking_stack is the only dependency source.
        /// `owner.untrack`
        /// inside (null sentinel reader on stack top) doesn't log a dependency.
        ///
        /// Owned slice (`scope.createText` / `createList`): the returned slice is valid only for
        /// the
        /// current sync call (handler/effect/memo compute until return) and while no signal
        /// re-write
        /// happens. After a write don't reuse it: double-buffering makes `set(transform(get()))`
        /// safe, but a
        /// second write makes the prior slice alias new content (silent wrong value). To keep
        /// across
        /// calls, use dupe/getInto.
        pub fn get(self: *Self) T {
            self.checkAlive();
            self.owner.assertThread();
            if (debug_checks) self.owner.noteTrackedRead("Signal");

            if (self.base.graph_node_raw != 0xFFFFFFFF) {
                const gid: graph_mod.NodeId = @bitCast(self.base.graph_node_raw);
                self.owner.graph.trackRead(gid) catch |err| {
                    std.log.warn("[reactive.Signal] graph.trackRead failed: {}", .{err});
                };
            }

            return self.value;
        }

        /// Read value no-depend
        pub fn peek(self: *const Self) T {
            self.checkAlive();
            self.owner.assertThread();
            return self.value;
        }

        /// Copy current text (cross-call keep). `Signal([]const u8)` only.
        pub fn dupe(self: *const Self, allocator: Allocator) ![]u8 {
            comptime if (T != []const u8) @compileError("dupe is only available on Signal([]const u8)");
            return allocator.dupe(u8, self.peek());
        }

        /// Copy current text into caller buffer; buffer short = truncate. Return written slice.
        pub fn getInto(self: *Self, buf: []u8) []u8 {
            comptime if (T != []const u8) @compileError("getInto is only available on Signal([]const u8)");
            const v = self.get();
            const n = @min(v.len, buf.len);
            @memcpy(buf[0..n], v[0..n]);
            return buf[0..n];
        }

        /// Set new value + notify all subscribers
        ///
        /// Owned slices (`scope.createText` / `createList`): a value that starts with the current
        /// one is stored as an append (only the extension is copied) and keeps `appendEpoch`;
        /// any other change advances it.
        pub fn set(self: *Self, new_value: T) void {
            self.checkAlive();
            self.owner.assertThread();
            // Skip unchanged. eqlValue replaces std.meta.eql fixes three bugs: []const u8
            // compares content not (ptr, len), NaN bytewise same = no forever dirty, struct with
            // slice
            // fields recurse correctly.
            if (eqlValue(T, self.value, new_value)) {
                // A shallow owned list keeps the caller's borrowed fields "while current": an
                // equal value rebuilt over new memory must become the current one, or the list
                // keeps pointing at memory the caller is free to release. Not a change: no notify.
                if (has_store) if (self.slice_store) |ts| ts.adoptEqual(new_value);
                return;
            }

            if (has_store) {
                if (self.slice_store) |ts| {
                    const old = self.value;
                    const ok = if (extendsOwned(old, new_value)) ts.append(old, new_value[old.len..]) else ts.store(new_value);
                    if (!ok) {
                        // Two-phase commit: fail = value unchanged (design section 4.8).
                        if (debug_checks) self.owner.debug.text_store_failures += 1;
                        std.log.warn("[reactive.Signal] owned slice store allocation failed; value unchanged", .{});
                        return;
                    }
                    self.value = ts.current(new_value.len);
                } else {
                    self.value = new_value;
                }
            } else {
                self.value = new_value;
            }
            self.commitWrite(@returnAddress());
        }

        /// `new_value` keeps `old` (the stored value) as its prefix, so `set` may store it as an
        /// append. Text and string lists own their bytes: content decides. Any other element is a
        /// shallow copy whose borrowed fields stay the caller's, so the prefix must be the same
        /// bits: a caller that rebuilt equal elements over new memory and freed the old would
        /// otherwise leave the kept prefix pointing at freed memory (bitwise differences only
        /// cost a full copy).
        fn extendsOwned(old: T, new_value: T) bool {
            if (!has_store) return false;
            if (new_value.len <= old.len) return false;
            const head = new_value[0..old.len];
            if (SliceElem(T) == u8 or SliceElem(T) == []const u8) return eqlValue(T, old, head);
            return std.mem.eql(u8, std.mem.sliceAsBytes(old), std.mem.sliceAsBytes(head));
        }

        /// Owned slices only (`scope.createText` / `createList` / `createSignalFor` of a
        /// `[]const E`): append `tail` to the current value. Copies only the increment (amortized
        /// O(tail.len)), no whole-value comparison; a non-empty tail always notifies, an empty one
        /// does nothing. Same reader contract as `set`; no address stability across writes.
        /// `appendEpoch` is unchanged. Allocation failure: error.OutOfMemory, value and epoch
        /// unchanged, nobody notified (unlike `set`, the caller must know: a silently dropped
        /// tail would misplace every later one). Calling it on a borrowed slice signal
        /// (`scope.createSignal`) is a programming error.
        pub fn append(self: *Self, tail: T) error{OutOfMemory}!void {
            comptime if (!has_store) @compileError("append is only available on Signal([]const E), got Signal(" ++ @typeName(T) ++ ")");
            self.checkAlive();
            self.owner.assertThread();
            if (tail.len == 0) return;
            const ts = self.slice_store orelse std.debug.panic("Signal({s}).append on a borrowed slice signal; create it with scope.createText / createList / createSignalFor", .{@typeName(T)});
            const old = self.value;
            if (!ts.append(old, tail)) {
                if (debug_checks) self.owner.debug.text_store_failures += 1;
                return error.OutOfMemory;
            }
            self.value = ts.current(old.len + tail.len);
            self.commitWrite(@returnAddress());
        }

        /// Append epoch of an owned slice signal: unchanged by a write that kept the old value
        /// as its prefix (`append`, or `set` of a value starting with it), advanced by any other
        /// write. So a reader that saw epoch `e` and length `n` and now sees epoch `e` again knows
        /// the first `n` elements did not change. Borrowed slice signals: null (their memory can
        /// be rewritten in place). Registers no dependency (read it beside `get`).
        pub fn appendEpoch(self: *const Self) ?u64 {
            comptime if (!has_store) @compileError("appendEpoch is only available on Signal([]const E), got Signal(" ++ @typeName(T) ++ ")");
            self.checkAlive();
            self.owner.assertThread();
            const ts = self.slice_store orelse return null;
            return ts.epoch;
        }

        /// Elements copied by owned-slice writes (tests: append cost).
        pub fn testCopyCounts(self: *const Self) struct { copied: usize, grow_copied: usize } {
            comptime if (!has_store or !is_test) @compileError("testCopyCounts is a test-only owned-slice counter");
            const ts = self.slice_store.?;
            return .{ .copied = ts.copied, .grow_copied = ts.grow_copied };
        }

        fn commitWrite(self: *Self, ret_addr: usize) void {
            if (comptime @import("builtin").is_test) {
                if (self.owner.test_write_trace) |trace| trace.write(trace.context, &self.base);
            }
            if (debug_checks) self.recordWrite(ret_addr);

            // Writes go through the graph. graph.markSignalWritten internally:
            //   1. signal.version++
            //   2. observers mark dirty (effect -> pending_effects)
            //   3. batch_depth == 0 runs drainPendingEffects (topo-sort run)
            //   4. drain calls effect graphRecomputeCb -> EffectBase.runWithTracking
            //
            // The graph path covers all dispatch in topo order, with no 16 limit and diamond-glitch
            // freedom.
            if (self.base.graph_node_raw != 0xFFFFFFFF) {
                const gid: @import("graph.zig").NodeId = @bitCast(self.base.graph_node_raw);
                // The drain may run an effect that disposes this signal's scope: only the owner
                // (which outlives it) is used afterwards.
                const owner = self.owner;
                owner.graph.markSignalWritten(gid) catch |err| {
                    std.log.err("[reactive.Signal] graph.markSignalWritten failed: {}", .{err});
                };
                // the write's effect drain (if any) has finished: settle point
                owner.drainSettledTasks();
            }
        }

        /// Swap to content-equal but bottom memory different, don't notify (read unchanged).
        /// Borrow slice data source: caller swapped new array, old freed later, signal can't keep
        /// pointing old (list line in-place update). Owned (write copies) owns copy, noop.
        pub fn replaceSameContent(self: *Self, new_value: T) void {
            self.checkAlive();
            self.owner.assertThread();
            std.debug.assert(eqlValue(T, self.value, new_value));
            if (has_store) {
                if (self.slice_store != null) return;
            }
            self.value = new_value;
        }

        fn recordWrite(self: *Self, ret_addr: usize) void {
            self.owner.debug.signal_writes += 1;
            self.debug.writers[self.debug.writer_next] = ret_addr;
            self.debug.writer_next = @intCast((@as(usize, self.debug.writer_next) + 1) % debug_writer_slots);
            if (self.base.graph_node_raw != 0xFFFFFFFF) {
                const gid: graph_mod.NodeId = @bitCast(self.base.graph_node_raw);
                if (self.owner.graph.currentReaderReads(gid)) {
                    // Pain point 4: effect state sync. Switch to memo/scope.linked.
                    self.owner.debug.self_write_warnings += 1;
                    std.log.warn("[reactive] an effect/memo wrote Signal({s}) that it also read; use a memo or scope.linked instead", .{@typeName(T)});
                }
            }
        }

        /// Update value via function
        pub fn update(self: *Self, comptime updateFn: fn (T) T) void {
            self.set(updateFn(self.value));
        }

        /// Update with context: `sig.updateWith(ctx, comptime f)`, `f(ctx, old) T`.
        pub fn updateWith(self: *Self, ctx: anytype, comptime updateFn: anytype) void {
            self.set(updateFn(ctx, self.peek()));
        }
    };
}

// ===== Tests =====

test "Signal: basic get/set" {
    var owner = try SignalOwner.init(std.testing.allocator);
    defer owner.deinit();

    const count = try Signal(i32).create(owner, 42);

    try std.testing.expectEqual(@as(i32, 42), count.get());

    count.set(100);
    try std.testing.expectEqual(@as(i32, 100), count.get());
}

test "Signal: peek doesn't track" {
    var owner = try SignalOwner.init(std.testing.allocator);
    defer owner.deinit();

    const count = try Signal(i32).create(owner, 0);

    // peek shouldn't trigger dependency tracking
    _ = count.peek();

    try std.testing.expectEqual(@as(i32, 0), count.peek());
}

test "Signal: update function" {
    var owner = try SignalOwner.init(std.testing.allocator);
    defer owner.deinit();

    const count = try Signal(i32).create(owner, 0);

    count.update(struct {
        fn inc(val: i32) i32 {
            return val + 1;
        }
    }.inc);

    try std.testing.expectEqual(@as(i32, 1), count.get());
}

test "Signal: skip notification if value unchanged" {
    var owner = try SignalOwner.init(std.testing.allocator);
    defer owner.deinit();

    const count = try Signal(i32).create(owner, 42);

    var notify_count: u32 = 0;

    // Simulate subscription
    const MockEffect = struct {
        var counter: *u32 = undefined;

        fn run(_: *anyopaque) void {
            counter.* += 1;
        }
    };

    MockEffect.counter = &notify_count;

    // Set same value shouldn't notify
    count.set(42);
    try std.testing.expectEqual(@as(u32, 0), notify_count);

    // Set different value should notify
    count.set(100);
    // Note: doesn't actually notify here (no real subscriber)
}

// ===== append / appendEpoch (docs/design/append-inbox.md §4.1, §8) =====

const NotifyCounter = struct {
    sig: *Signal([]const u8),
    runs: usize = 0,
    fn run(self: *@This()) void {
        _ = self.sig.get();
        self.runs += 1;
    }
};

test "Signal.append: n appends copy each element at most twice, plus doubling refills" {
    const testing = std.testing;
    const owner = try SignalOwner.init(testing.allocator);
    defer owner.deinit();
    const scope = try Scope.init(testing.allocator, null, owner);
    defer scope.dispose();
    const text = try scope.createText("", .{});
    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(testing.allocator);
    var chunk: [7]u8 = undefined;
    var total: usize = 0;
    for (0..2000) |i| {
        for (&chunk, 0..) |*c, k| c.* = @intCast('a' + (i + k) % 26);
        const n = 1 + i % chunk.len;
        try text.append(chunk[0..n]);
        try expected.appendSlice(testing.allocator, chunk[0..n]);
        total += n;
    }
    try testing.expectEqualStrings(expected.items, text.peek());
    const counts = text.testCopyCounts();
    // Incremental copies: each element at most twice (its own append, then the other buffer
    // catching up once).
    try testing.expect(counts.copied <= 2 * total);
    // Refills when a buffer grows: doubling bounds each buffer's refills by twice the final size.
    try testing.expect(counts.grow_copied <= 4 * total + 64);
    // A whole-value copy per append would be ~total^2 / 2 / 4 elements.
    try testing.expect(counts.copied + counts.grow_copied < 7 * total);
}

test "Signal.appendEpoch: prefix-keeping writes keep it, any other change advances it" {
    const testing = std.testing;
    const owner = try SignalOwner.init(testing.allocator);
    defer owner.deinit();
    const scope = try Scope.init(testing.allocator, null, owner);
    defer scope.dispose();
    const text = try scope.createText("ab", .{});
    var counter = NotifyCounter{ .sig = text };
    try scope.createEffect(&counter, NotifyCounter.run);
    try testing.expectEqual(@as(usize, 1), counter.runs);
    const e0 = text.appendEpoch().?;

    try text.append("cd");
    try testing.expectEqual(e0, text.appendEpoch().?);
    try testing.expectEqual(@as(usize, 2), counter.runs);
    try text.append("");
    try testing.expectEqual(@as(usize, 2), counter.runs); // empty tail: nothing
    text.set("abcdef"); // longer, starts with the current value: an append
    try testing.expectEqual(e0, text.appendEpoch().?);
    try testing.expectEqualStrings("abcdef", text.peek());
    try testing.expectEqual(@as(usize, 3), counter.runs);
    text.set("abcdef"); // equal: no write, no notify
    try testing.expectEqual(e0, text.appendEpoch().?);
    try testing.expectEqual(@as(usize, 3), counter.runs);

    text.set("abcxef"); // same length, different content
    const e1 = text.appendEpoch().?;
    try testing.expect(e1 != e0);
    text.set("abc"); // truncation
    const e2 = text.appendEpoch().?;
    try testing.expect(e2 != e1);
    text.set("xbcd"); // longer but not an extension
    const e3 = text.appendEpoch().?;
    try testing.expect(e3 != e2);
    text.set(""); // clear
    const e4 = text.appendEpoch().?;
    try testing.expect(e4 != e3);
    try text.append("z"); // append to empty
    try testing.expectEqual(e4, text.appendEpoch().?);
    try testing.expectEqualStrings("z", text.peek());
    try testing.expectEqual(@as(usize, 8), counter.runs);
}

test "Signal.append: a read slice stays valid through the next write; transform(get()) stays safe" {
    const testing = std.testing;
    const owner = try SignalOwner.init(testing.allocator);
    defer owner.deinit();
    const scope = try Scope.init(testing.allocator, null, owner);
    defer scope.dispose();
    const text = try scope.createText("hello", .{});
    for (0..200) |i| {
        const before = text.peek();
        var copy: [4096]u8 = undefined;
        @memcpy(copy[0..before.len], before);
        if (i % 3 == 0) {
            // Append a piece of the current value to itself (reads the active buffer).
            try text.append(before[0..@min(before.len, 3)]);
        } else if (i % 3 == 1) {
            try text.append("-x");
        } else {
            // set(transform(get())): the extension path reads `before` while writing.
            var buf: [4096]u8 = undefined;
            @memcpy(buf[0..before.len], before);
            buf[before.len] = '!';
            text.set(buf[0 .. before.len + 1]);
        }
        // The slice read before the write still holds the old value.
        try testing.expectEqualStrings(copy[0..before.len], before);
        try testing.expect(std.mem.startsWith(u8, text.peek(), copy[0..before.len]));
        if (text.peek().len > 3000) text.set("hello");
    }
}

test "Signal.append: owned string lists append and keep their epoch; strings are the list's own" {
    const testing = std.testing;
    const owner = try SignalOwner.init(testing.allocator);
    defer owner.deinit();
    const scope = try Scope.init(testing.allocator, null, owner);
    defer scope.dispose();
    const list = try scope.createList([]const u8, &.{"alpha"});
    const e0 = list.appendEpoch().?;
    var buf: [32]u8 = undefined;
    for (0..300) |i| {
        const s = std.fmt.bufPrint(&buf, "row-{d}", .{i}) catch unreachable;
        try list.append(&.{s});
        @memset(&buf, 'X'); // the caller's buffer is reused: the list must own its bytes
    }
    try testing.expectEqual(e0, list.appendEpoch().?);
    const v = list.peek();
    try testing.expectEqual(@as(usize, 301), v.len);
    try testing.expectEqualStrings("alpha", v[0]);
    for (v[1..], 0..) |s, i| {
        var want: [32]u8 = undefined;
        try testing.expectEqualStrings(std.fmt.bufPrint(&want, "row-{d}", .{i}) catch unreachable, s);
    }
    list.set(&.{ "alpha", "row-0" });
    try testing.expect(list.appendEpoch().? != e0);
    // set of a longer list that starts with the current one: an append.
    const e1 = list.appendEpoch().?;
    list.set(&.{ "alpha", "row-0", "tail" });
    try testing.expectEqual(e1, list.appendEpoch().?);
    try testing.expectEqualStrings("tail", list.peek()[2]);
}

test "Signal.appendEpoch: borrowed slice signals report null; Source variants" {
    const testing = std.testing;
    const source_mod = @import("source.zig");
    const owner = try SignalOwner.init(testing.allocator);
    defer owner.deinit();
    const scope = try Scope.init(testing.allocator, null, owner);
    defer scope.dispose();
    const borrowed = try scope.createSignal([]const u8, "abc");
    try testing.expectEqual(@as(?u64, null), borrowed.appendEpoch());
    const owned = try scope.createText("abc", .{});
    const memo = try scope.createMemo([]const u8, owned, struct {
        fn f(s: *Signal([]const u8)) []const u8 {
            return s.get();
        }
    }.f);
    const S = source_mod.Source([]const u8);
    try testing.expectEqual(@as(?u64, 0), (S{ .value = "static" }).appendEpoch());
    try testing.expectEqual(owned.appendEpoch(), (S{ .signal = owned }).appendEpoch());
    try testing.expectEqual(@as(?u64, null), (S{ .signal = borrowed }).appendEpoch());
    try testing.expectEqual(@as(?u64, null), (S{ .memo = memo }).appendEpoch());
    const d = source_mod.map(owned, struct {
        fn f(v: []const u8) []const u8 {
            return v;
        }
    }.f);
    try testing.expectEqual(@as(?u64, null), source_mod.toSource(d).appendEpoch());
}

test "allocation campaign: Signal.append failure leaves value and epoch unchanged and notifies nobody" {
    const testing = std.testing;
    var fail_index: usize = 0;
    var saw_failure = false;
    var saw_success = false;
    while (fail_index < 64) : (fail_index += 1) {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = fail_index });
        const alloc = failing.allocator();
        const owner = SignalOwner.init(alloc) catch continue;
        defer owner.deinit();
        owner.graph.tracking_stack.ensureTotalCapacity(alloc, 8) catch continue;
        const scope = Scope.init(alloc, null, owner) catch continue;
        defer scope.dispose();
        const text = scope.createText("seed", .{}) catch continue;
        var counter = NotifyCounter{ .sig = text };
        scope.createEffect(&counter, NotifyCounter.run) catch continue;
        const runs = counter.runs;
        var expected: [512]u8 = undefined;
        var len: usize = 4;
        @memcpy(expected[0..4], "seed");
        for (0..40) |i| {
            const piece = "0123456789"[0 .. 1 + i % 10];
            const epoch = text.appendEpoch().?;
            const before_runs = counter.runs;
            text.append(piece) catch {
                saw_failure = true;
                try testing.expectEqualStrings(expected[0..len], text.peek());
                try testing.expectEqual(epoch, text.appendEpoch().?);
                try testing.expectEqual(before_runs, counter.runs);
                continue;
            };
            @memcpy(expected[len .. len + piece.len], piece);
            len += piece.len;
            try testing.expectEqualStrings(expected[0..len], text.peek());
        }
        // After failures the signal still appends correctly once memory is back (prefix reset).
        if (counter.runs > runs) saw_success = true;
    }
    try testing.expect(saw_failure and saw_success);
}

test "allocation campaign: owned string list append failure keeps the list intact" {
    const testing = std.testing;
    var fail_index: usize = 0;
    while (fail_index < 48) : (fail_index += 1) {
        var failing = testing.FailingAllocator.init(testing.allocator, .{ .fail_index = fail_index });
        const alloc = failing.allocator();
        const owner = SignalOwner.init(alloc) catch continue;
        defer owner.deinit();
        const scope = Scope.init(alloc, null, owner) catch continue;
        defer scope.dispose();
        const list = scope.createList([]const u8, &.{"head"}) catch continue;
        var count: usize = 1;
        for (0..30) |i| {
            var buf: [16]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "r{d}", .{i}) catch unreachable;
            list.append(&.{s}) catch {
                try testing.expectEqual(count, list.peek().len);
                continue;
            };
            count += 1;
        }
        const v = list.peek();
        try testing.expectEqualStrings("head", v[0]);
        // Every surviving row has a well-formed "r<digits>" string (no dangling bytes).
        for (v[1..]) |s| try testing.expect(s.len >= 2 and s[0] == 'r');
    }
}

const BorrowedItem = struct { id: u32, text: []const u8 };

test "Signal.set: a struct list rebuilt over new memory never keeps a prefix pointing at the old" {
    const testing = std.testing;
    const owner = try SignalOwner.init(testing.allocator);
    defer owner.deinit();
    const scope = try Scope.init(testing.allocator, null, owner);
    defer scope.dispose();
    const list = try scope.createList(BorrowedItem, &.{});

    // Generation 1 in its own memory.
    const first = try testing.allocator.dupe(u8, "alpha");
    list.set(&.{.{ .id = 1, .text = first }});
    const e1 = list.appendEpoch().?;

    // Generation 2: rebuilt (an equal first element, one more) over new memory; the old is freed.
    const again = try testing.allocator.dupe(u8, "alpha");
    defer testing.allocator.free(again);
    const second = try testing.allocator.dupe(u8, "beta");
    defer testing.allocator.free(second);
    list.set(&.{ .{ .id = 1, .text = again }, .{ .id = 2, .text = second } });
    testing.allocator.free(first);
    // The kept element is the caller's new one, not the freed one: a content-equal prefix with
    // different bits is stored whole, as a replacement.
    try testing.expectEqual(again.ptr, list.peek()[0].text.ptr);
    try testing.expectEqualStrings("alpha", list.peek()[0].text);
    const e2 = list.appendEpoch().?;
    try testing.expect(e2 != e1);

    // A bit-identical prefix (the same element values) is an append: epoch kept.
    const tail = try testing.allocator.dupe(u8, "gamma");
    defer testing.allocator.free(tail);
    list.set(&.{ .{ .id = 1, .text = again }, .{ .id = 2, .text = second }, .{ .id = 3, .text = tail } });
    try testing.expectEqual(e2, list.appendEpoch().?);
    try testing.expectEqual(@as(usize, 3), list.peek().len);
    try testing.expectEqual(tail.ptr, list.peek()[2].text.ptr);
}

test "Signal.set: an equal struct list over new memory is adopted without a notification" {
    const testing = std.testing;
    const owner = try SignalOwner.init(testing.allocator);
    defer owner.deinit();
    const scope = try Scope.init(testing.allocator, null, owner);
    defer scope.dispose();
    const list = try scope.createList(BorrowedItem, &.{});
    var counter: struct {
        sig: *Signal([]const BorrowedItem),
        runs: usize = 0,
        fn run(self: *@This()) void {
            _ = self.sig.get();
            self.runs += 1;
        }
    } = .{ .sig = list };
    try scope.createEffect(&counter, @TypeOf(counter).run);

    const old_a = try testing.allocator.dupe(u8, "alpha");
    const old_b = try testing.allocator.dupe(u8, "beta");
    list.set(&.{ .{ .id = 1, .text = old_a }, .{ .id = 2, .text = old_b } });
    const runs = counter.runs;
    const epoch = list.appendEpoch().?;

    // The caller rebuilds the same rows over new memory and frees the old: the list must not keep
    // pointing at it ("borrowed fields must remain valid while current").
    const new_a = try testing.allocator.dupe(u8, "alpha");
    defer testing.allocator.free(new_a);
    const new_b = try testing.allocator.dupe(u8, "beta");
    defer testing.allocator.free(new_b);
    list.set(&.{ .{ .id = 1, .text = new_a }, .{ .id = 2, .text = new_b } });
    testing.allocator.free(old_a);
    testing.allocator.free(old_b);
    try testing.expectEqual(runs, counter.runs); // equal value: not a change
    try testing.expectEqual(epoch, list.appendEpoch().?);
    try testing.expectEqual(new_a.ptr, list.peek()[0].text.ptr);
    try testing.expectEqual(new_b.ptr, list.peek()[1].text.ptr);
    try testing.expectEqualStrings("beta", list.peek()[1].text);
}

test "Signal.appendEpoch: different signals never share an epoch" {
    const testing = std.testing;
    const owner = try SignalOwner.init(testing.allocator);
    defer owner.deinit();
    const scope = try Scope.init(testing.allocator, null, owner);
    defer scope.dispose();
    const a = try scope.createText("same", .{});
    const b = try scope.createText("same", .{});
    try testing.expect(a.appendEpoch().? != b.appendEpoch().?);
    try testing.expect(a.appendEpoch().? != 0); // 0 is a static source's
    a.set("other");
    b.set("other");
    try testing.expect(a.appendEpoch().? != b.appendEpoch().?);
}
