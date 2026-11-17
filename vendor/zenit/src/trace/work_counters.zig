//! Deterministic work counters (docs/design/streaming-content.md §5.8).
//!
//! What the frame pipeline did, counted instead of timed: text bytes re-broken into lines or
//! hashed, bytes handed to the platform shaper, text lines turned into display items, nodes
//! allocated and freed, layout passes, after-layout rounds, Markdown bytes scanned. A counter
//! only depends on the work, so two runs of the same scenario give the same numbers and a gate
//! can compare a 10 KB document with a 1 MB one without wall-clock noise.
//!
//! The totals are process-wide and monotonic: any thread may add (`.monotonic` atomic adds), a
//! reader takes a snapshot. A `Sampler` turns them into a series by recording their growth
//! between boundaries its owner chooses:
//! - every `Cx` holds one (`cx.work_counters`) that the native hosts commit once per presented
//!   frame, next to the frame timing history; the test harness reports it under `/stats` `work`;
//! - an application can keep its own, committed once per update, for per-update statistics.
//! With several windows, a window's frame value is the whole process's work between two of its
//! frames: exact for one window, an upper bound otherwise (`/stats` says `"scope": "process"`).
//!
//! Lives in `trace` because the counting points span the `ui` and `render` modules (shaping
//! happens in both) and both import this one module instance.
const std = @import("std");

pub const Counter = enum(u8) {
    /// Text line-breaking computations (`computeTextLayout` / `measureTextExtent`); stored layouts
    /// reused from the cache are not counted.
    text_layouts,
    /// Content bytes those computations processed.
    text_layout_bytes,
    /// Text content bytes hashed for cache keys and change detection (`hashText` and the
    /// streaming hashers that report through `add`).
    text_hash_bytes,
    /// Bytes handed to the platform shaper (CoreText / HarfBuzz / DirectWrite), including the
    /// font's own width measurement: the shaping that actually ran after the caches missed.
    text_shape_bytes,
    /// Laid-out text lines turned into display items (paint re-recording; replayed display lists
    /// are not counted).
    text_paint_lines,
    /// Heap `Node` allocations / frees.
    nodes_created,
    nodes_destroyed,
    /// Top-level layout walks (`layoutNode` entered at recursion depth 0).
    layout_passes,
    /// After-layout hook rounds that ran.
    after_layout_rounds,
    /// Bytes the Markdown block scanner advanced over.
    md_scanned_bytes,
};

pub const counters = std.enums.values(Counter);
pub const counter_count = counters.len;

/// One value per counter.
pub const Counts = struct {
    values: [counter_count]u64 = @splat(0),

    pub fn get(self: Counts, counter: Counter) u64 {
        return self.values[@intFromEnum(counter)];
    }

    /// `self - earlier`, per counter, for two snapshots of the same totals: modulo the totals'
    /// word width, so an interval stays right across a wrap of the free-running totals.
    pub fn since(self: Counts, earlier: Counts) Counts {
        var out: Counts = .{};
        for (&out.values, self.values, earlier.values) |*o, now, then|
            o.* = @as(Word, @truncate(now)) -% @as(Word, @truncate(then));
        return out;
    }

    pub fn plus(self: Counts, other: Counts) Counts {
        var out: Counts = .{};
        for (&out.values, self.values, other.values) |*o, x, y| o.* = x +% y;
        return out;
    }
};

/// Totals are machine words: every target has word-sized atomics (wasm32 has no 64-bit ones).
/// On 32-bit targets a total wraps after 4 Gi; intervals stay exact (Counts.since) as long as one
/// interval is below that, and `Sampler` accumulates intervals in u64.
const Word = usize;

/// A set of monotonic totals safe to add to from any thread.
pub const Totals = struct {
    values: [counter_count]Word = @splat(0),

    pub inline fn add(self: *Totals, counter: Counter, amount: u64) void {
        _ = @atomicRmw(Word, &self.values[@intFromEnum(counter)], .Add, @truncate(amount), .monotonic);
    }

    /// Counters are read one by one: a concurrent add lands in one of two consecutive snapshots,
    /// never in both or neither.
    pub fn snapshot(self: *const Totals) Counts {
        var out: Counts = .{};
        for (&out.values, &self.values) |*o, *t| o.* = @atomicLoad(Word, t, .monotonic);
        return out;
    }
};

var process_totals: Totals = .{};

pub inline fn add(counter: Counter, amount: u64) void {
    process_totals.add(counter, amount);
}

pub inline fn bump(counter: Counter) void {
    process_totals.add(counter, 1);
}

/// Process totals since start.
pub fn snapshot() Counts {
    return process_totals.snapshot();
}

/// Hash text content (Wyhash, `seed`) and count it as `text_hash_bytes`. Use it wherever text
/// content is hashed for a cache key or change detection, so whole-text hashing stays visible.
pub inline fn hashText(seed: u64, bytes: []const u8) u64 {
    add(.text_hash_bytes, bytes.len);
    return std.hash.Wyhash.hash(seed, bytes);
}

/// Boundaries kept for the percentile window (frame_perf.history_size: ~2 s of frames at 60 Hz).
pub const history_size: usize = 120;

/// The process totals' growth between consecutive boundaries its owner commits.
pub const Sampler = struct {
    /// Process totals at the previous boundary (or at init / reset).
    boundary: Counts = .{},
    /// Sum of the committed intervals since the last reset.
    accumulated: Counts = .{},
    /// Intervals committed since the last reset.
    intervals: u64 = 0,
    ring: [history_size]Counts = @splat(.{}),
    /// Next ring write position (always < history_size).
    write: usize = 0,
    /// Valid ring entries (<= history_size).
    len: usize = 0,

    /// Start from now: work done before this point belongs to no interval of this sampler.
    pub fn init() Sampler {
        return .{ .boundary = snapshot() };
    }

    /// Forget committed intervals and start again from the current totals.
    pub fn reset(self: *Sampler) void {
        self.* = init();
    }

    /// Close the current interval: its value is the process totals' growth since the previous
    /// boundary.
    pub fn commit(self: *Sampler) void {
        self.commitAt(snapshot());
    }

    /// `commit` with explicit totals (a caller sampling its own `Totals`).
    pub fn commitAt(self: *Sampler, now: Counts) void {
        const interval = now.since(self.boundary);
        self.boundary = now;
        self.accumulated = self.accumulated.plus(interval);
        self.intervals +%= 1;
        self.ring[self.write] = interval;
        self.write = (self.write + 1) % history_size;
        if (self.len < history_size) self.len += 1;
    }

    pub const Report = struct {
        /// Intervals committed since the last reset.
        intervals: u64,
        /// Intervals in the percentile window (min(intervals, history_size)).
        window: usize,
        totals: Counts,
        /// The most recent committed interval (zero when none).
        last: Counts,
        /// Per-counter nearest-rank percentiles over the window; zero when the window is empty.
        p50: Counts,
        p95: Counts,
        max: Counts,
    };

    pub fn report(self: *const Sampler) Report {
        var out = Report{
            .intervals = self.intervals,
            .window = self.len,
            .totals = self.accumulated,
            .last = .{},
            .p50 = .{},
            .p95 = .{},
            .max = .{},
        };
        if (self.len == 0) return out;
        out.last = self.ring[(self.write + history_size - 1) % history_size];
        var column: [history_size]u64 = undefined;
        for (0..counter_count) |c| {
            const sorted = column[0..self.len];
            for (self.ring[0..self.len], sorted) |interval, *value| value.* = interval.values[c];
            std.mem.sort(u64, sorted, {}, std.sort.asc(u64));
            out.p50.values[c] = percentile(sorted, 50);
            out.p95.values[c] = percentile(sorted, 95);
            out.max.values[c] = sorted[sorted.len - 1];
        }
        return out;
    }
};

/// Nearest rank on an ascending slice, the same rule as frame_perf.Sampler.percentile.
fn percentile(sorted: []const u64, pct: usize) u64 {
    return sorted[@min(sorted.len - 1, (sorted.len - 1) * pct / 100)];
}

fn countsWith(counter: Counter, value: u64) Counts {
    var c: Counts = .{};
    c.values[@intFromEnum(counter)] = value;
    return c;
}

test "work counters: each interval holds the growth since the previous boundary" {
    var sampler = Sampler{};
    sampler.commitAt(countsWith(.text_layout_bytes, 100));
    sampler.commitAt(countsWith(.text_layout_bytes, 107));
    sampler.commitAt(countsWith(.text_layout_bytes, 107));
    const r = sampler.report();
    try std.testing.expectEqual(@as(u64, 3), r.intervals);
    try std.testing.expectEqual(@as(usize, 3), r.window);
    try std.testing.expectEqual(@as(u64, 107), r.totals.get(.text_layout_bytes));
    try std.testing.expectEqual(@as(u64, 0), r.last.get(.text_layout_bytes));
    try std.testing.expectEqual(@as(u64, 7), r.p50.get(.text_layout_bytes));
    try std.testing.expectEqual(@as(u64, 100), r.max.get(.text_layout_bytes));
}

test "work counters: work before init or reset belongs to no interval" {
    add(.nodes_created, 5);
    var sampler = Sampler.init();
    const at_init = sampler.boundary;
    sampler.commitAt(at_init);
    try std.testing.expectEqual(@as(u64, 0), sampler.report().totals.get(.nodes_created));
    sampler.commitAt(at_init.plus(countsWith(.nodes_created, 2)));
    try std.testing.expectEqual(@as(u64, 2), sampler.report().totals.get(.nodes_created));
    sampler.reset();
    try std.testing.expectEqual(@as(u64, 0), sampler.report().intervals);
    try std.testing.expectEqual(@as(u64, 0), sampler.report().totals.get(.nodes_created));
}

test "work counters: the percentile window keeps the most recent history_size intervals" {
    var sampler = Sampler{};
    var now: Counts = .{};
    // Interval i (1-based) scans i bytes; 200 intervals overflow the 120-entry ring.
    for (1..201) |i| {
        now.values[@intFromEnum(Counter.md_scanned_bytes)] += i;
        sampler.commitAt(now);
    }
    const r = sampler.report();
    try std.testing.expectEqual(@as(u64, 200), r.intervals);
    try std.testing.expectEqual(history_size, r.window);
    try std.testing.expectEqual(@as(u64, 200 * 201 / 2), r.totals.get(.md_scanned_bytes));
    try std.testing.expectEqual(@as(u64, 200), r.last.get(.md_scanned_bytes));
    try std.testing.expectEqual(@as(u64, 200), r.max.get(.md_scanned_bytes));
    // Window = intervals 81..200; nearest rank over 120 sorted values: 50 % -> index 59,
    // 95 % -> index 113.
    try std.testing.expectEqual(@as(u64, 81 + 59), r.p50.get(.md_scanned_bytes));
    try std.testing.expectEqual(@as(u64, 81 + 113), r.p95.get(.md_scanned_bytes));
    try std.testing.expectEqual(@as(u64, 0), r.max.get(.nodes_created));
}

test "work counters: an interval stays exact across a wrap of the word-sized totals" {
    const top: u64 = std.math.maxInt(Word);
    const before = countsWith(.text_layout_bytes, top - 9);
    const after = countsWith(.text_layout_bytes, 20); // wrapped: top - 9 + 30
    try std.testing.expectEqual(@as(u64, 30), after.since(before).get(.text_layout_bytes));
}

test "work counters: an empty sampler reports zeros" {
    const r = (Sampler{}).report();
    try std.testing.expectEqual(@as(u64, 0), r.intervals);
    try std.testing.expectEqual(@as(usize, 0), r.window);
    for (counters) |c| try std.testing.expectEqual(@as(u64, 0), r.max.get(c));
}

test "work counters: concurrent adds are not lost" {
    var totals: Totals = .{};
    const Worker = struct {
        fn run(t: *Totals) void {
            for (0..10_000) |_| t.add(.text_shape_bytes, 3);
        }
    };
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Worker.run, .{&totals});
    for (threads) |t| t.join();
    try std.testing.expectEqual(@as(u64, 4 * 10_000 * 3), totals.snapshot().get(.text_shape_bytes));
}

test "work counters: hashText counts the bytes it hashes" {
    const before = snapshot().get(.text_hash_bytes);
    try std.testing.expectEqual(std.hash.Wyhash.hash(7, "abc"), hashText(7, "abc"));
    try std.testing.expectEqual(before + 3, snapshot().get(.text_hash_bytes));
}
