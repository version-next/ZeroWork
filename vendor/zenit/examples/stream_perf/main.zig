//! stream_perf: a document that keeps growing at its end, for measuring how update cost scales
//! with document length (docs/design/streaming-content.md §2.3, §5.8).
//!
//! One scenario per run, chosen by environment variables:
//!   ZENIT_STREAM_SCENARIO        prose (Markdown text, default) | code (one CodeBlock) | log (one
//!                                newline_only text node)
//!   ZENIT_STREAM_INITIAL_BYTES   document length before streaming starts (default 10000)
//!   ZENIT_STREAM_CHUNK_BYTES     bytes appended per chunk (default 64; code / log round up to
//!                                whole lines, prose to a whole UTF-8 character)
//!   ZENIT_STREAM_CHUNKS          chunks to append (default 200)
//!   ZENIT_STREAM_INTERVAL_MS     delay between chunks (default 16)
//!   ZENIT_STREAM_AUTOSTART=1     start immediately instead of waiting for the Start button
//!   ZENIT_STREAM_RESULT_FILE     write the per-chunk work statistics (JSON) here when done
//!
//! The variables are read through the process environment as given; a test-mode build is how
//! the harness runs it (scripts/run_stream_perf_baseline.sh). The status text echoes the
//! configuration in effect so a harness can check it.
//!
//! The content is deterministic (no clock, no randomness), so two runs append the same bytes.
//! Streaming is driven by a re-armed Cx timer, not by input. The status text (`stream.status`)
//! reads `ready <config>`, then `streaming <i>/<n>`, then `done <bytes>`. Per-chunk work counters
//! (one `ui.devtools.work_counters.Sampler` interval per chunk: the append plus every frame
//! until the next one) are written as JSON to ZENIT_STREAM_RESULT_FILE before the status turns
//! `done`; per-frame counters are in `/stats` `work`. A harness resets `/stats`, clicks `stream.start`, waits for `done`
//! and reads both (e2e/stream-perf-baseline.test.ts).
//!
//! Writes go through the only text-signal API that exists today: the whole document is `set`
//! after each chunk. Later work packages switch this to `append` + Inbox (WP2) and incremental
//! Markdown (WP3); the scenarios and the status protocol stay the same so baselines compare.
const std = @import("std");
const ui = @import("ui");
const App = @import("zenit_app").App;
const v = ui.view;
const W = ui.widgets;

const Scenario = enum { prose, code, log };

const Config = struct {
    scenario: Scenario = .prose,
    initial_bytes: usize = 10_000,
    chunk_bytes: usize = 64,
    chunks: usize = 200,
    interval_ms: u64 = 16,
    autostart: bool = false,
    /// Where the per-chunk statistics go when done (JSON); null = not written.
    result_file: ?[]const u8 = null,

    fn fromEnvironment(env: *std.process.Environ.Map) Config {
        var c = Config{};
        if (env.get("ZENIT_STREAM_SCENARIO")) |s| c.scenario = std.meta.stringToEnum(Scenario, s) orelse .prose;
        c.initial_bytes = number(env, "ZENIT_STREAM_INITIAL_BYTES", c.initial_bytes);
        c.chunk_bytes = @max(1, number(env, "ZENIT_STREAM_CHUNK_BYTES", c.chunk_bytes));
        c.chunks = number(env, "ZENIT_STREAM_CHUNKS", c.chunks);
        c.interval_ms = number(env, "ZENIT_STREAM_INTERVAL_MS", c.interval_ms);
        if (env.get("ZENIT_STREAM_AUTOSTART")) |s| c.autostart = std.mem.eql(u8, s, "1");
        c.result_file = env.get("ZENIT_STREAM_RESULT_FILE");
        return c;
    }

    fn number(env: *std.process.Environ.Map, key: []const u8, default: anytype) @TypeOf(default) {
        const raw = env.get(key) orelse return default;
        return std.fmt.parseInt(@TypeOf(default), raw, 10) catch default;
    }
};

/// Deterministic content: an endless sequence of units (a prose paragraph, a code line, a log
/// record) numbered from 0.
const Generator = struct {
    scenario: Scenario,
    next_unit: usize = 0,

    const prose_sentences = [_][]const u8{
        "Streaming text grows at its end while the reader may be anywhere in it. ",
        "增量更新的成本应当只与新增内容有关，而与文档总长无关。 ",
        "A **bold** claim, an *emphasised* aside and some `inline code`. ",
        "列表、标题与段落混排，中英文交替出现。 ",
    };

    fn appendUnit(self: *Generator, out: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
        const i = self.next_unit;
        self.next_unit += 1;
        switch (self.scenario) {
            .prose => {
                if (i % 7 == 0) try out.print(allocator, "## Section {d}\n\n", .{i / 7});
                if (i % 5 == 3) {
                    try out.print(allocator, "- item {d}: {s}\n- item {d}.1\n\n", .{ i, prose_sentences[i % prose_sentences.len], i });
                    return;
                }
                for (0..3) |k| try out.appendSlice(allocator, prose_sentences[(i + k) % prose_sentences.len]);
                try out.appendSlice(allocator, "\n\n");
            },
            .code => try out.print(allocator, "fn step{d:0>6}(x: u32) u32 {{ return x *% {d} +% {d}; }}\n", .{ i, i % 97, i % 13 }),
            .log => try out.print(allocator, "[{d:0>7}] INFO worker={d} request={x:0>8} status=200 bytes={d} took={d}ms\n", .{ i, i % 8, i *% 2654435761 % 0xffffffff, (i * 37) % 4096, i % 50 }),
        }
    }

    /// Append at least `bytes` bytes: whole units for code / log, a whole UTF-8 character for
    /// prose (the source of the next unit is cut, never a character).
    fn appendAtLeast(self: *Generator, pending: *std.ArrayList(u8), out: *std.ArrayList(u8), allocator: std.mem.Allocator, bytes: usize) !void {
        if (self.scenario != .prose) {
            const start = out.items.len;
            while (out.items.len - start < bytes) try self.appendUnit(out, allocator);
            return;
        }
        while (pending.items.len < bytes) try self.appendUnit(pending, allocator);
        var cut = bytes;
        while (cut < pending.items.len and (pending.items[cut] & 0xC0) == 0x80) cut += 1;
        try out.appendSlice(allocator, pending.items[0..cut]);
        std.mem.copyForwards(u8, pending.items[0 .. pending.items.len - cut], pending.items[cut..]);
        pending.shrinkRetainingCapacity(pending.items.len - cut);
    }
};

const work_counters = ui.devtools.work_counters;

const Stream = struct {
    allocator: std.mem.Allocator,
    cx: *ui.Cx,
    config: Config,
    generator: Generator,
    document: std.ArrayList(u8) = .empty,
    pending: std.ArrayList(u8) = .empty,
    doc: *ui.Signal([]const u8),
    status: *ui.Signal([]const u8),
    io: std.Io,
    status_buf: [160]u8 = undefined,
    result_buf: [4096]u8 = undefined,
    /// One interval per chunk: from the tick that appends it to the next tick, i.e. the append
    /// plus every frame that follows until the next append.
    per_chunk: work_counters.Sampler = .{},
    sent: usize = 0,
    timer: u64 = 0,
    started: bool = false,

    /// Before the window (and its Cx) goes away.
    fn stop(self: *Stream) void {
        if (self.timer != 0) self.cx.clearTimer(self.timer);
        self.timer = 0;
    }

    fn deinit(self: *Stream) void {
        self.document.deinit(self.allocator);
        self.pending.deinit(self.allocator);
    }

    fn setStatus(self: *Stream, comptime fmt: []const u8, args: anytype) void {
        const text = std.fmt.bufPrint(&self.status_buf, fmt, args) catch "status overflow";
        self.status.set(text);
    }

    /// `ready` plus the configuration in effect, so a harness can check its variables arrived.
    fn setReady(self: *Stream) void {
        self.setStatus("ready {s} initial={d} chunk={d} chunks={d} interval={d}", .{ @tagName(self.config.scenario), self.document.items.len, self.config.chunk_bytes, self.config.chunks, self.config.interval_ms });
    }

    fn start(self: *Stream) void {
        if (self.started) return;
        self.started = true;
        self.arm();
    }

    fn arm(self: *Stream) void {
        self.timer = self.cx.setTimer(self.config.interval_ms * std.time.ns_per_ms, tick, self) catch 0;
    }

    fn tick(raw: ?*anyopaque) void {
        const self: *Stream = @ptrCast(@alignCast(raw.?));
        self.timer = 0;
        // Close the previous chunk's interval (the first tick opens the first one).
        if (self.sent == 0) self.per_chunk = work_counters.Sampler.init() else self.per_chunk.commit();
        if (self.sent >= self.config.chunks) {
            self.publishResult();
            self.setStatus("done {d}", .{self.document.items.len});
            return;
        }
        self.generator.appendAtLeast(&self.pending, &self.document, self.allocator, self.config.chunk_bytes) catch {
            self.setStatus("error out of memory", .{});
            return;
        };
        self.doc.set(self.document.items);
        self.sent += 1;
        self.setStatus("streaming {d}/{d}", .{ self.sent, self.config.chunks });
        // One more tick after the last chunk closes its interval.
        self.arm();
    }

    /// Per-chunk work statistics as JSON, written to `result_file`.
    fn publishResult(self: *Stream) void {
        const path = self.config.result_file orelse return;
        const r = self.per_chunk.report();
        var w: std.Io.Writer = .fixed(&self.result_buf);
        writeReport(&w, r) catch return self.setStatus("error result overflow", .{});
        std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = path, .data = w.buffered() }) catch
            return self.setStatus("error cannot write {s}", .{path});
    }

    fn writeReport(w: *std.Io.Writer, r: work_counters.Sampler.Report) !void {
        try w.print("{{\"chunks\":{d},\"window\":{d}", .{ r.intervals, r.window });
        inline for (.{ "totals", "p50", "p95", "max" }) |name| {
            const counts: work_counters.Counts = @field(r, name);
            try w.print(",\"{s}\":{{", .{name});
            for (work_counters.counters, 0..) |counter, i| {
                try w.print("{s}\"{s}\":{d}", .{ if (i == 0) "" else ",", @tagName(counter), counts.get(counter) });
            }
            try w.writeAll("}");
        }
        try w.writeAll("}\n");
    }
};

var g_stream: ?*Stream = null;

const S = struct {
    const root = ui.css(.{ .width = .fill, .height = .fill, .direction = .column, .gap = .space300, .padding = .space600, .background = .bg_primary });
    const bar = ui.css(.{ .width = .fill, .height = .fit, .direction = .row, .align_items = .center, .gap = .space300 });
    const status = ui.css(.{ .color = .fg_secondary, .font_size = .md });
    const body = ui.css(.{ .width = .fill, .height = .fit, .direction = .column });
    const log = ui.css(.{ .color = .fg_primary, .font_size = .sm, .use_monospace_font = true, .wrap = .newline_only });
    const start = ui.css(.{ .width = .fit, .height = .fit, .padding = .{ .y = .space150, .x = .space400 }, .corner_radius = .md, .background = .accent, .cursor = .pointer });
    const start_label = ui.css(.{ .color = .fg_inverse, .font_size = .md, .font_weight = .medium });
};

fn mountTree(scope: *ui.Scope, cx: *ui.Cx, stream: *Stream, content: anytype) !*ui.Node {
    return v.render(scope, cx, v.col(.{ .style = S.root }, .{
        v.row(.{ .style = S.bar }, .{
            v.box(.{ .style = S.start, .test_id = "stream.start", .on_click = ui.on.call(stream, Stream.start) }, .{v.text(.{ .style = S.start_label }, "Start")}),
            v.text(.{ .style = S.status, .test_id = "stream.status" }, stream.status),
        }),
        v.with(W.ScrollArea(.{ .direction = .vertical }), .{
            v.box(.{ .style = S.body, .test_id = "stream.content" }, .{content}),
        }),
    }));
}

fn mountUI(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
    const stream = g_stream.?;
    stream.cx = cx;
    stream.doc = try scope.createText(stream.document.items, .{ .capacity = stream.document.items.len * 2 });
    stream.status = try scope.createText("", .{ .capacity = stream.status_buf.len });
    stream.setReady();
    const root = switch (stream.config.scenario) {
        .prose => try mountTree(scope, cx, stream, W.Markdown(.{ .text = stream.doc })),
        .code => try mountTree(scope, cx, stream, W.CodeBlock(.{ .code = stream.doc, .label = "zig" })),
        .log => try mountTree(scope, cx, stream, v.text(.{ .style = S.log, .test_id = "stream.log" }, stream.doc)),
    };
    if (stream.config.autostart) stream.start();
    return root;
}

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const config = Config.fromEnvironment(init.environ_map);

    var stream = Stream{
        .allocator = allocator,
        .cx = undefined,
        .config = config,
        .generator = .{ .scenario = config.scenario },
        .doc = undefined,
        .status = undefined,
        .io = init.io,
    };
    defer stream.deinit();
    try stream.generator.appendAtLeast(&stream.pending, &stream.document, allocator, config.initial_bytes);
    g_stream = &stream;
    defer g_stream = null;

    const app = try App.init(allocator, .{
        .io = init.io,
        .window = .{ .width = 1000, .height = 800, .title = "Stream Perf" },
    });
    defer app.deinit();
    defer stream.stop();
    try app.runWith(mountUI);
}
