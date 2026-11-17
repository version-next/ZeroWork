//! WP1 (docs/design/streaming-content.md §5.9): a text node lays out and paints every line,
//! however many there are. The first group reproduced the former 1024-line cap (MAX_LINES) at
//! the node level: layout output, fit height and the painted display list. The rest cover the
//! line table's storage contract: spill tables owned by the layout output table, two-phase
//! stores that keep the old layout on failure, aliasing, allocation counts and paint geometry.
const std = @import("std");
const ui = @import("../core.zig");
const text_layout = @import("text_layout.zig");
const LayoutOutputTable = @import("layout_output_table.zig").LayoutOutputTable;
const ElementId = @import("element_id.zig").ElementId;
const CountingAllocator = @import("counting_allocator.zig").CountingAllocator;

const Cx = ui.Cx;
const TextLayout = text_layout.TextLayout;
const LineInfo = text_layout.LineInfo;
const LineScratch = text_layout.LineScratch;
const cap = text_layout.inline_line_capacity;

/// "line 00000\nline 00001\n…" with `count` lines and no trailing newline.
fn numberedLines(allocator: std.mem.Allocator, count: usize) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (0..count) |i| {
        if (i != 0) try out.append(allocator, '\n');
        try out.print(allocator, "line {d:0>5}", .{i});
    }
    return out.toOwnedSlice(allocator);
}

fn lastLine(content: []const u8) []const u8 {
    const start = if (std.mem.lastIndexOfScalar(u8, content, '\n')) |i| i + 1 else 0;
    return content[start..];
}

const Painted = struct { found: bool = false, y: f32 = 0 };

fn paintedRun(cx: *Cx, content: []const u8) Painted {
    var out: Painted = .{};
    for (cx.display_list.items.items) |item| switch (item) {
        .text_run => |run| if (std.mem.eql(u8, run.content, content)) {
            out = .{ .found = true, .y = run.y };
        },
        else => {},
    };
    return out;
}

const NodeCase = struct {
    lines: usize,
    wrap: ui.TextWrap = .newline_only,
    font_size: f32 = 10,
    line_height: f32 = 1.2,
    spans: bool = false,
};

fn expectNodeShowsEveryLine(case: NodeCase) !void {
    const a = std.testing.allocator;
    const content = try numberedLines(a, case.lines);
    defer a.free(content);
    const cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try ui.box(cx, .{ .width = .{ .px = 400 }, .direction = .column }, .{});
    cx.root = root;
    const node = try ui.text(cx, content, .{ .font_size = case.font_size, .line_height = case.line_height, .wrap = case.wrap, .monospace_char_width = 6 });
    try root.appendChild(cx.allocator, node);
    if (case.spans) {
        // A colored span on the first and on the last line: the span paint path per line.
        var props = node.getText().?;
        const last_start: u32 = @intCast(content.len - lastLine(content).len);
        const spans = try cx.allocator.dupe(ui.TextSpan, &.{
            .{ .start = 0, .end = 4, .color = ui.Color.rgba(200, 0, 0, 255) },
            .{ .start = last_start, .end = last_start + 4, .color = ui.Color.rgba(0, 0, 200, 255) },
        });
        props.spans = spans;
        props.spans_owned = true;
        node.setText(props);
    }
    cx.layout();
    _ = cx.render();

    const layout = node.layoutTextLayout() orelse return error.TestExpectedTextLayout;
    try std.testing.expectEqual(case.lines, @as(usize, layout.line_count));
    try std.testing.expectEqual(@as(u32, @intCast(content.len)), layout.lines()[layout.line_count - 1].byte_end);
    const line_h = case.font_size * case.line_height;
    const n: f32 = @floatFromInt(case.lines);
    try std.testing.expectApproxEqAbs(n * line_h, layout.total_height, 0.5);
    try std.testing.expectApproxEqAbs(n * line_h, node.rectFromWorldOrFallback().h, 0.5);

    // The last line is painted where layout put it: (n - 1) line heights down, plus the
    // baseline, the same product as total_height (no accumulated float drift).
    const want_last = lastLine(content);
    if (case.spans) {
        var painted_last = false;
        for (cx.display_list.items.items) |item| switch (item) {
            .text_run => |run| if (run.blob_byte_end == content.len) {
                painted_last = true;
            },
            else => {},
        };
        try std.testing.expect(painted_last);
        return;
    }
    const painted = paintedRun(cx, want_last);
    try std.testing.expect(painted.found);
    const first = paintedRun(cx, "line 00000");
    try std.testing.expect(first.found);
    try std.testing.expectApproxEqAbs((n - 1) * line_h, painted.y - first.y, 0.5);
}

test "WP1 long text: a 5000-line newline_only node lays out and paints its last line" {
    try expectNodeShowsEveryLine(.{ .lines = 5000 });
}

test "WP1 long text: a 5000-line wrapping node lays out and paints its last line" {
    try expectNodeShowsEveryLine(.{ .lines = 5000, .wrap = .word });
}

test "WP1 long text: a 70000-line node (beyond u16) lays out and paints its last line" {
    try expectNodeShowsEveryLine(.{ .lines = 70_000 });
}

test "WP1 long text: line positions do not drift at a non-binary line height" {
    // 13 x 1.35 = 17.55 is not exact in binary: summing it line by line drifts by pixels
    // over 70000 lines; the painted position must equal index x line height.
    try expectNodeShowsEveryLine(.{ .lines = 70_000, .font_size = 13, .line_height = 1.35 });
    try expectNodeShowsEveryLine(.{ .lines = 20_000, .font_size = 16, .line_height = 1.6, .wrap = .word });
}

test "WP1 long text: the span paint path reaches the last of 5000 lines" {
    try expectNodeShowsEveryLine(.{ .lines = 5000, .spans = true });
}

test "WP1 long text: computeTextLayout keeps every line" {
    const a = std.testing.allocator;
    var scratch = LineScratch.init(a);
    defer scratch.deinit();
    inline for (.{ 1025, 5000, 70_000 }) |count| {
        const content = try numberedLines(a, count);
        defer a.free(content);
        inline for (.{ ui.TextWrap.newline_only, ui.TextWrap.word }) |wrap| {
            const layout = try text_layout.computeTextLayout(&scratch, content, 1000, wrap, 0, 10, 1.2, 400, false, true, &.{});
            try std.testing.expectEqual(@as(usize, count), @as(usize, layout.line_count));
            try std.testing.expectEqual(@as(u32, @intCast(content.len)), layout.lines()[layout.line_count - 1].byte_end);
            const extent = text_layout.measureTextExtent(content, 1000, wrap, 0, 10, 1.2, 400, false, true, &.{});
            try std.testing.expectEqual(layout.line_count, extent.line_count);
            try std.testing.expectEqual(layout.max_line_width, extent.max_line_width);
        }
    }
}

test "WP1 long text: one soft-wrapped paragraph longer than the inline table" {
    // No hard newline: the width-wrapping loop itself crosses the inline capacity.
    const a = std.testing.allocator;
    var words: std.ArrayList(u8) = .empty;
    defer words.deinit(a);
    for (0..cap * 3) |i| try words.print(a, "{s}w{d}", .{ if (i == 0) "" else " ", i % 10 });
    var scratch = LineScratch.init(a);
    defer scratch.deinit();
    // Room for one word ("wN") but not two: one word per line.
    const width = text_layout.measureTextWidthByFontKind("w0", 12, 400, false, false) * 1.5;
    const layout = try text_layout.computeTextLayout(&scratch, words.items, width, .word, 0, 12, 1.25, 400, false, false, &.{});
    try std.testing.expectEqual(@as(u32, @intCast(cap * 3)), layout.line_count);
    var previous_end: u32 = 0;
    for (layout.lines()) |line| {
        try std.testing.expect(line.byte_start >= previous_end);
        try std.testing.expect(line.byte_end > line.byte_start);
        previous_end = line.byte_end;
    }
    try std.testing.expectEqual(@as(u32, @intCast(words.items.len)), previous_end);
}

test "WP1 long text: line counts around the inline capacity, with a trailing newline" {
    const a = std.testing.allocator;
    var scratch = LineScratch.init(a);
    defer scratch.deinit();
    for ([_]usize{ cap - 1, cap, cap + 1 }) |count| {
        const body = try numberedLines(a, count);
        defer a.free(body);
        const content = try std.mem.concat(a, u8, &.{ body, "\n" });
        defer a.free(content);
        inline for (.{ ui.TextWrap.newline_only, ui.TextWrap.word }) |wrap| {
            // The trailing separator adds one final empty line, which may itself cross over.
            const layout = try text_layout.computeTextLayout(&scratch, content, 1000, wrap, 0, 10, 1.2, 400, false, true, &.{});
            try std.testing.expectEqual(@as(u32, @intCast(count + 1)), layout.line_count);
            const last = layout.lines()[count];
            try std.testing.expectEqual(@as(u32, @intCast(content.len)), last.byte_start);
            try std.testing.expectEqual(last.byte_start, last.byte_end);
            try std.testing.expectEqual(@as(u32, @intCast(body.len)), layout.lines()[count - 1].byte_end);
        }
    }
}

test "WP1 long text: max_lines still truncates when asked to" {
    const a = std.testing.allocator;
    const content = try numberedLines(a, cap * 2 + 16);
    defer a.free(content);
    var scratch = LineScratch.init(a);
    defer scratch.deinit();
    const layout = try text_layout.computeTextLayout(&scratch, content, 1000, .word, @intCast(cap + 7), 10, 1.2, 400, false, true, &.{});
    try std.testing.expectEqual(@as(u32, @intCast(cap + 7)), layout.line_count);
}

test "WP1 long text: intrinsic width sees the widest line after the inline capacity" {
    const a = std.testing.allocator;
    const short = try numberedLines(a, cap + 10);
    defer a.free(short);
    const wide = "a line much wider than every numbered line before it";
    const content = try std.mem.concat(a, u8, &.{ short, "\n", wide });
    defer a.free(content);
    const cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(2000, 300);
    const root = try ui.box(cx, .{ .width = .{ .px = 2000 }, .direction = .column, .align_items = .start }, .{});
    cx.root = root;
    const node = try ui.text(cx, content, .{ .font_size = 10, .wrap = .newline_only, .monospace_char_width = 6 });
    node.setStyleInline(cx.allocator, .{ .width = .{ .fit = .{} } });
    try root.appendChild(cx.allocator, node);
    cx.layout();
    try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(wide.len)) * 6, node.rectFromWorldOrFallback().w, 0.5);
}

/// A layout with `count` lines whose byte ranges encode their index (for content checks).
fn syntheticLayout(scratch: *LineScratch, count: usize) !TextLayout {
    var layout = TextLayout{ .line_count = @intCast(count), .total_height = @floatFromInt(count) };
    const dst: []LineInfo = if (count <= cap) layout.inline_lines[0..count] else blk: {
        scratch.lines.clearRetainingCapacity();
        try scratch.lines.resize(scratch.allocator, count);
        layout.spill_lines = scratch.lines.items;
        break :blk scratch.lines.items;
    };
    for (dst, 0..) |*line, i| line.* = .{ .byte_start = @intCast(i), .byte_end = @intCast(i + 1), .width = @floatFromInt(i) };
    return layout;
}

fn expectSynthetic(layout: *const TextLayout, count: usize) !void {
    try std.testing.expectEqual(@as(u32, @intCast(count)), layout.line_count);
    for (layout.lines(), 0..) |line, i| {
        if (line.byte_start != i or line.byte_end != i + 1) return error.TestUnexpectedLine;
    }
}

fn storeSequence(allocator: std.mem.Allocator, counts: []const usize) !void {
    var t = LayoutOutputTable.init(allocator);
    defer t.deinit();
    var scratch = LineScratch.init(allocator);
    defer scratch.deinit();
    const id = ElementId{ .index = 0, .generation = 1 };
    try t.ensureSlot(id);
    var previous: ?usize = null;
    for (counts) |count| {
        const next = try syntheticLayout(&scratch, count);
        t.storeTextLayout(id, &next) catch |err| {
            // Two-phase store: the previous complete layout survives a failed one.
            if (previous) |p| try expectSynthetic(t.getConstPtr(id).?.artifacts.text_layout.?, p) else try std.testing.expect(t.getConstPtr(id).?.artifacts.text_layout == null);
            try std.testing.expect(t.layout_oom);
            return err;
        };
        try expectSynthetic(t.getConstPtr(id).?.artifacts.text_layout.?, count);
        previous = count;
    }
    // Replacing the element and clearing release every spill table (testing.allocator checks).
    try t.ensureSlot(.{ .index = 0, .generation = 2 });
    try t.ensureSlot(.{ .index = 1, .generation = 1 });
    const long = try syntheticLayout(&scratch, cap * 3);
    try t.storeTextLayout(.{ .index = 1, .generation = 1 }, &long);
    t.clear(.{ .index = 0, .generation = 2 });
    // Index 1 keeps its spill table into deinit.
}

test "WP1 long text: store short to long to longer to short, exhaustive OOM, no leaks" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, storeSequence, .{&[_]usize{ 3, cap + 1, cap * 4, cap * 4 + 1, 10, cap * 2 }});
}

test "WP1 long text: computeTextLayout reports scratch exhaustion without a partial layout" {
    const a = std.testing.allocator;
    const content = try numberedLines(a, cap * 2);
    defer a.free(content);
    var failing = std.testing.FailingAllocator.init(a, .{ .fail_index = 0 });
    var scratch = LineScratch.init(failing.allocator());
    defer scratch.deinit();
    try std.testing.expectError(error.OutOfMemory, text_layout.computeTextLayout(&scratch, content, 1000, .newline_only, 0, 10, 1.2, 400, false, true, &.{}));
    // Within the inline table nothing touches the scratch allocator.
    const short = try numberedLines(a, cap);
    defer a.free(short);
    const layout = try text_layout.computeTextLayout(&scratch, short, 1000, .newline_only, 0, 10, 1.2, 400, false, true, &.{});
    try std.testing.expectEqual(@as(u32, @intCast(cap)), layout.line_count);
    try std.testing.expectEqual(@as(usize, 0), failing.allocations);
}

test "WP1 long text: assign from itself or from a copy of itself" {
    const a = std.testing.allocator;
    var scratch = LineScratch.init(a);
    defer scratch.deinit();
    inline for (.{ 5, cap * 2 }) |count| {
        var owned: TextLayout = .{};
        defer owned.deinitStorage(a);
        const src = try syntheticLayout(&scratch, count);
        try owned.assign(a, &src);
        try owned.assign(a, &owned);
        try expectSynthetic(&owned, count);
        // A copy borrows the same spill table: assigning it back must not free what it reads.
        var copy = owned;
        copy.total_height = 42;
        try owned.assign(a, &copy);
        try expectSynthetic(&owned, count);
        try std.testing.expectEqual(@as(f32, 42), owned.total_height);
        // Back to a short layout: its lines go inline and the spill table is released.
        var short_scratch = LineScratch.init(a);
        defer short_scratch.deinit();
        const short = try syntheticLayout(&short_scratch, 3);
        try owned.assign(a, &short);
        try expectSynthetic(&owned, 3);
        try std.testing.expectEqual(@as(usize, 0), owned.spill_lines.len);
    }
}

test "WP1 long text: table slots copy, not share, each other's spill tables" {
    var t = LayoutOutputTable.init(std.testing.allocator);
    defer t.deinit();
    var scratch = LineScratch.init(std.testing.allocator);
    defer scratch.deinit();
    const a_id = ElementId{ .index = 0, .generation = 1 };
    const b_id = ElementId{ .index = 1, .generation = 1 };
    try t.ensureSlot(a_id);
    try t.ensureSlot(b_id);
    const long = try syntheticLayout(&scratch, cap * 2);
    try t.storeTextLayout(a_id, &long);
    const a_layout = t.getConstPtr(a_id).?.artifacts.text_layout.?;
    try t.storeTextLayout(b_id, a_layout);
    const b_layout = t.getConstPtr(b_id).?.artifacts.text_layout.?;
    try std.testing.expect(a_layout.spill_lines.ptr != b_layout.spill_lines.ptr);
    t.clear(a_id);
    try expectSynthetic(b_layout, cap * 2);
    // Header writes of a slot's own layout keep its storage.
    try t.set(b_id, t.get(b_id).?);
    try expectSynthetic(t.getConstPtr(b_id).?.artifacts.text_layout.?, cap * 2);
    try std.testing.expect(t.memoryStats().text_spill_bytes >= cap * 2 * @sizeOf(LineInfo));
}

test "WP1 long text: storing an inline-sized layout into an existing slot allocates nothing" {
    var counting = CountingAllocator{ .parent = std.testing.allocator };
    var t = LayoutOutputTable.init(counting.allocator());
    defer t.deinit();
    var scratch = LineScratch.init(std.testing.allocator);
    defer scratch.deinit();
    const id = ElementId{ .index = 0, .generation = 1 };
    try t.ensureSlot(id);
    const first = try syntheticLayout(&scratch, cap);
    try t.storeTextLayout(id, &first);
    const after_first = counting.allocations;
    for (0..@min(20, cap)) |i| {
        const again = try syntheticLayout(&scratch, cap - i);
        try t.storeTextLayout(id, &again);
    }
    try std.testing.expectEqual(after_first, counting.allocations);

    // Growing one line at a time past the inline table reallocates its spill table only
    // logarithmically often (x1.5).
    const grow_start = counting.allocations;
    var count: usize = cap + 1;
    while (count <= cap * 5) : (count += 1) {
        const next = try syntheticLayout(&scratch, count);
        try t.storeTextLayout(id, &next);
    }
    const grow_allocations = counting.allocations - grow_start;
    try std.testing.expect(grow_allocations <= 6);
    try expectSynthetic(t.getConstPtr(id).?.artifacts.text_layout.?, cap * 5);
}

test "WP1 long text: a node flipping between long and short text keeps the right lines" {
    const a = std.testing.allocator;
    const long = try numberedLines(a, cap * 3);
    defer a.free(long);
    const cx = try Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(400, 300);
    const root = try ui.box(cx, .{ .width = .{ .px = 400 }, .direction = .column }, .{});
    cx.root = root;
    const node = try ui.text(cx, long, .{ .font_size = 10, .wrap = .newline_only, .monospace_char_width = 6 });
    try root.appendChild(cx.allocator, node);
    for ([_][]const u8{ long, "one\ntwo", long, "single" }, [_]usize{ cap * 3, 2, cap * 3, 1 }) |content, lines| {
        var props = node.getText().?;
        props.content = content;
        props.owned = false;
        node.setText(props);
        cx.advanceFrameClock();
        cx.layout();
        _ = cx.render();
        const layout = node.layoutTextLayout().?;
        try std.testing.expectEqual(@as(u32, @intCast(lines)), layout.line_count);
        try std.testing.expectEqual(@as(u32, @intCast(content.len)), layout.lines()[lines - 1].byte_end);
        try std.testing.expect(paintedRun(cx, lastLine(content)).found);
        // Short text holds no spill table of its own (only the shared scratch keeps capacity).
        if (lines <= cap) try std.testing.expectEqual(@as(usize, 0), layout.spill_lines.len);
    }
    // An idle trim drops the scratch table's capacity.
    _ = cx.trimIdleRenderCapacity(0);
    try std.testing.expectEqual(@as(usize, 0), cx.world.layout_output.line_scratch.lines.capacity);
}

test "WP1 long text: a mock node without a World stores and releases a long layout" {
    const a = std.testing.allocator;
    const content = try numberedLines(a, cap * 2);
    defer a.free(content);
    var node = ui.Node{ .id = 77, .tag = .text, .style = .{}, .children = .empty };
    defer node.children.deinit(a);
    defer @import("node_lifecycle.zig").releaseStandaloneState(&node);
    var scratch = LineScratch.init(a);
    defer scratch.deinit();
    const computed = try text_layout.computeTextLayout(&scratch, content, 1000, .newline_only, 0, 10, 1.2, 400, false, true, &.{});
    try node.storeTextLayout(&computed);
    try std.testing.expectEqual(@as(u32, @intCast(cap * 2)), node.layoutTextLayout().?.line_count);
    // Reading the header back and writing it again keeps the node's own lines.
    const header = node.getLayoutOutput();
    node.setLayoutOutput(header);
    const stored = node.layoutTextLayout().?;
    try std.testing.expectEqual(@as(u32, @intCast(content.len)), stored.lines()[stored.line_count - 1].byte_end);
    node.clearTextLayout();
    try std.testing.expect(node.layoutTextLayout() == null);
}
