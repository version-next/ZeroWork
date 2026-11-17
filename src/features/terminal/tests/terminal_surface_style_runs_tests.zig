//! Node cost of per-cell styled terminal output (lolcat, 256-colour charts,
//! syntax-highlighted diffs) and the style-run contract that bounds it.
//! Real Ghostty engine + public zenit tree, no window or process.
const std = @import("std");
const ui = @import("ui");
const View = @import("../view/terminal_view.zig").TerminalViewNode;
const fixture = @import("terminal_surface_view_tests.zig");
const FakeTransport = fixture.FakeTransport;
const owner = fixture.owner;
const a = std.testing.allocator;

const rows = 24;
const cols = 80;

/// lolcat input: words with spaces, repeated to fill a row.
const sentence = "the quick brown fox jumps over the lazy dog while a rainbow paints each letter ";

/// One screen of per-cell styled output. `phase` shifts every colour so two
/// screens differ in every visible cell.
fn styledScreen(out: *std.ArrayList(u8), phase: u8) !void {
    const w = struct {
        fn print(list: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
            var buf: [128]u8 = undefined;
            try list.appendSlice(a, try std.fmt.bufPrint(&buf, fmt, args));
        }
    }.print;
    try out.appendSlice(a, "\x1b[H\x1b[2J");
    for (0..rows) |row| {
        try w(out, "\x1b[{d};1H", .{row + 1});
        switch (row) {
            // 256-colour foreground chart: right-aligned colour numbers.
            1 => for (0..cols / 4) |index| {
                const colour = (16 + index * 11 + phase) % 240 + 16;
                try w(out, "\x1b[38;5;{d}m{d:>4}", .{ colour, colour });
            },
            // 256-colour background chart: every cell its own background.
            2 => for (0..cols) |col| try w(out, "\x1b[48;5;{d}m ", .{(col + phase) % 240 + 16}),
            // Status line: eight 10-cell segments, each its own fg / bg.
            3 => for (0..8) |index| try w(out, "\x1b[48;5;{d};38;5;{d}m seg{d:0>2}    ", .{ 17 + index * 6, (index * 29 + phase) % 216 + 16, index }),
            // Per-word bold / italic / underline styles / strike / dim.
            4 => for (0..10) |index| {
                const sgr = [_][]const u8{ "1", "3", "4", "4:3", "9", "2", "1;3", "4:4", "4:5", "0" };
                try w(out, "\x1b[0;38;5;{d};{s}mword{d:0>2}\x1b[0m ", .{ (index * 17 + phase) % 200 + 20, sgr[index], index });
            },
            // Syntax-highlighted diff line on a whole-line added background.
            5 => {
                try out.appendSlice(a, "\x1b[0;48;2;20;60;30m");
                const tokens = [_]struct { []const u8, []const u8 }{ .{ "38;5;114", "+" }, .{ "39", "    " }, .{ "38;5;204", "const" }, .{ "39", " " }, .{ "38;5;81", "value" }, .{ "39", " = " }, .{ "38;5;221", "render" }, .{ "39", "(" }, .{ "38;5;141", "cells" }, .{ "39", ", " }, .{ "38;5;173", "42" }, .{ "39", ");" }, .{ "3;38;5;102", " // per-cell styles" } };
                for (tokens) |token| try w(out, "\x1b[{s}m{s}", .{ token[0], token[1] });
                try out.appendSlice(a, "\x1b[K");
            },
            // Wide characters between colourful ASCII.
            6 => for (0..16) |col| try w(out, "\x1b[38;5;{d}m{c}中", .{ (col * 11 + phase) % 216 + 16, @as(u8, @intCast('a' + col)) }),
            // Box drawing (terminal cell graphics) in alternating colours.
            7 => {
                try out.appendSlice(a, "\x1b[0m");
                for (0..40) |col| try w(out, "\x1b[38;5;{d}m─", .{(col + phase) % 216 + 16});
            },
            // Per-word reverse / hidden / blink / dim / plain / reverse bold.
            8 => for (0..11) |index| {
                const sgr = [_][]const u8{ "7", "8", "5", "2", "0", "7;1" };
                try w(out, "\x1b[0;38;5;{d};{s}mword{d:0>2}\x1b[0m ", .{ (index * 13 + phase) % 216 + 16, sgr[index % sgr.len], index });
            },
            // Per-word overline / double underline (own colour, then red).
            9 => for (0..16) |index| {
                const sgr = [_][]const u8{ "53", "21", "0", "4:2;58;5;196" };
                try w(out, "\x1b[0;38;5;{d};{s}mw{d:0>2}\x1b[0m ", .{ (index * 7 + phase) % 216 + 16, sgr[index % sgr.len], index });
            },
            // Worst case: every cell its own colour and no spaces at all.
            10 => for (0..cols) |col| {
                const t = (row * 3 + col + phase) % 96;
                try w(out, "\x1b[38;2;{d};{d};{d}m{c}", .{ @min(255, t * 8), @min(255, (95 - t) * 8), (col * 3) % 256, @as(u8, @intCast('!' + (col + row) % 90)) });
            },
            // lolcat: a truecolour rainbow over words, every cell its own colour.
            else => for (0..cols) |col| {
                const t = (row * 3 + col + phase) % 96;
                const r: u8 = @intCast(@min(255, t * 8));
                const g: u8 = @intCast(@min(255, (95 - t) * 8));
                const b: u8 = @intCast((col * 3 + row * 5) % 256);
                try w(out, "\x1b[38;2;{d};{d};{d}m{c}", .{ r, g, b, sentence[(col + row * 7) % sentence.len] });
            },
        }
        try out.appendSlice(a, "\x1b[0m");
    }
}

fn visibleNodes(node: *ui.Node) usize {
    if (node.style.display == .none) return 0;
    var count: usize = 1;
    for (node.children.items) |child| count += visibleNodes(child);
    return count;
}

fn visibleTextNodes(node: *ui.Node) usize {
    if (node.style.display == .none) return 0;
    var count: usize = if (node.getText() != null) 1 else 0;
    for (node.children.items) |child| count += visibleTextNodes(child);
    return count;
}

const Mounted = struct {
    transport: *FakeTransport,
    cx: *ui.Cx,
    view: View,
    fn init(transport: *FakeTransport) !Mounted {
        try transport.init(rows, cols);
        errdefer transport.deinit();
        const cx = try ui.Cx.init(a, std.testing.io);
        errdefer cx.deinit();
        cx.setViewport(1200, 900);
        var view = try View.mount(cx);
        cx.root = view.root;
        view.setTypography(14, 1.5, 400);
        view.setTimestampGutter(false);
        try view.bindTerminalService(transport.service());
        _ = cx.render();
        _ = try view.refreshTerminalService(owner, true);
        _ = cx.render();
        // The view sizes the grid from its bounds: fit the window to exactly
        // `cols` x `rows` cells (plus half a cell of slack) before feeding.
        const surface = view.terminal_surface.?;
        var width: f32 = 1200;
        var height: f32 = 900;
        for (0..5) |_| {
            for (0..2) |_| {
                cx.layout();
                surface.force_snapshot = true;
                _ = try view.refreshTerminalService(owner, true);
                _ = cx.render();
            }
            const projection = &surface.snapshot.?.projection;
            if (projection.cols == cols and projection.rows == rows) break;
            width += (@as(f32, cols) - @as(f32, @floatFromInt(projection.cols))) * surface.options.cell_width;
            height += (@as(f32, rows) - @as(f32, @floatFromInt(projection.rows))) * surface.options.row_height;
            cx.setViewport(width, height);
        }
        return .{ .transport = transport, .cx = cx, .view = view };
    }
    fn deinit(self: *Mounted) void {
        self.view.releaseBuffers(self.cx);
        self.cx.deinit();
        self.transport.deinit();
    }
    fn show(self: *Mounted, sequence: u64, bytes: []const u8) !void {
        try self.transport.controller.feedOutput(owner, sequence, bytes, @intCast(sequence));
        self.view.terminal_surface.?.force_snapshot = true;
        self.cx.requestRedraw();
        self.cx.advanceFrameClock();
        self.cx.layout();
        _ = try self.view.refreshTerminalService(owner, true);
        self.cx.layout();
        _ = self.cx.render();
    }
};

test "terminal surface style runs: node count and frame cost of a per-cell styled screen" {
    var transport: FakeTransport = undefined;
    var mounted = try Mounted.init(&transport);
    defer mounted.deinit();
    var screen: std.ArrayList(u8) = .empty;
    defer screen.deinit(a);
    try styledScreen(&screen, 0);
    try mounted.show(1, screen.items);
    const surface = mounted.view.terminal_surface.?;
    const projection = &surface.snapshot.?.projection;
    try std.testing.expectEqual(@as(u16, cols), projection.cols);
    try std.testing.expectEqual(@as(usize, rows), projection.visible_rows.len);
    var total: usize = 0;
    var text_total: usize = 0;
    var per_row: [rows]usize = undefined;
    for (surface.rows.items[0..rows], 0..) |row, index| {
        per_row[index] = visibleNodes(row.root) - 1;
        total += per_row[index];
        text_total += visibleTextNodes(row.root);
    }
    // Frame cost: alternate two screens that differ in every styled cell, so
    // each frame re-renders every row (Debug build; relative numbers only).
    var other: std.ArrayList(u8) = .empty;
    defer other.deinit(a);
    try styledScreen(&other, 37);
    const iterations = 12;
    const realtime = @import("../../../platform/realtime.zig");
    const begin = realtime.monotonicNs();
    for (0..iterations) |i| try mounted.show(2 + i, if (i % 2 == 0) other.items else screen.items);
    const elapsed: u64 = @intCast(realtime.monotonicNs() - begin);
    std.debug.print("\n[r2t-nodes] rows={d} cols={d} visible_nodes={d} text_nodes={d} per_row={any} avg_frame_us={d}\n", .{ rows, cols, total, text_total, per_row, elapsed / iterations / 1000 });
}

const surface_module = @import("../view/terminal_surface.zig");
const vt = @import("../../../vt/snapshot.zig");
const BandKind = surface_module.BandKind;

fn left(node: *ui.Node) f32 {
    return node.style.ext.?.inset.left.px;
}

/// Per-cell oracle: the ink the pre-run renderer gave a cell's own node.
const Expected = struct {
    fg: ui.Color,
    bg: ?ui.Color,
    weight: u16,
    italic: bool,
    strike: bool,
    underline: ?ui.types.UnderlineStyle,
    underline_color: ui.Color,
    overline: ?ui.Color,
    double_underline: ?ui.Color,
};
fn expected(surface: *const surface_module.Surface, cell: vt.Cell, projection: *const vt.Projection) Expected {
    const reverse_screen = projection.modes.reverse_colors;
    var fg = surface_module.resolveColor(cell.foreground, ui.Color.hex(if (reverse_screen) projection.colors.background else projection.colors.foreground), projection.colors);
    var bg = surface_module.resolveColor(cell.background, ui.Color.hex(if (reverse_screen) projection.colors.foreground else projection.colors.background), projection.colors);
    if (cell.attributes & (1 << 4) != 0) std.mem.swap(ui.Color, &fg, &bg);
    if (cell.attributes & (1 << 6) != 0) fg.a = @intCast(@as(u16, fg.a) / 2);
    const hide = cell.attributes & (1 << 7) != 0 or (cell.attributes & (1 << 3) != 0 and surface.focused and !surface.reduced_motion and !surface.blink);
    if (hide) fg.a = 0;
    const underline_color = if (hide) ui.Color.TRANSPARENT else surface_module.resolveColor(cell.underline_color, fg, projection.colors);
    return .{
        .fg = fg,
        .bg = if (cell.background != .default or cell.attributes & (1 << 4) != 0 or reverse_screen) bg else null,
        .weight = if (cell.attributes & 1 != 0) @min(@as(u16, 900), surface.options.weight + 300) else surface.options.weight,
        .italic = cell.attributes & 2 != 0,
        .strike = cell.attributes & (1 << 5) != 0,
        .underline = switch (cell.underline) {
            0, 2 => null,
            3 => .wavy,
            4 => .dotted,
            5 => .dashed,
            else => .solid,
        },
        .underline_color = underline_color,
        .overline = if (cell.attributes & (1 << 8) != 0) fg else null,
        .double_underline = if (cell.underline == 2) underline_color else null,
    };
}

fn visibleBands(row: anytype, kind: BandKind) usize {
    var count: usize = 0;
    for (row.bands.get(kind).items) |band| {
        if (band.style.display != .none) count += 1;
    }
    return count;
}

fn visibleGlyphs(row: anytype) usize {
    var count: usize = 0;
    for (row.glyphs.items) |glyph| {
        if (glyph.node.style.display != .none) count += 1;
    }
    return count;
}

/// Every drawn cell is painted exactly as its own node used to be: the text
/// node covering its column carries its byte at the cell's x with the cell's
/// ink, and each band kind covers it exactly once in the cell's colour.
fn expectCellExact(surface: *surface_module.Surface) !void {
    const projection = &surface.snapshot.?.projection;
    const cw = surface.options.cell_width;
    for (projection.visible_rows) |value| {
        const row = &surface.rows.items[value.viewport_y];
        const cells = projection.cells[value.cell_start..][0..value.cell_count];
        const origin = surface.bodyX() + row.layout.shift_x;
        for (cells, 0..) |cell, col| {
            if (cell.width == .wide_tail) continue;
            const grapheme = projection.grapheme(cell);
            const drawn = !(grapheme.len == 0 and cell.background == .default and cell.attributes == 0 and !projection.modes.reverse_colors);
            const x = origin + @as(f32, @floatFromInt(col)) * cw;
            const want = expected(surface, cell, projection);
            var covering: ?*ui.Node = null;
            for (row.glyphs.items) |glyph| {
                if (glyph.node.style.display == .none) continue;
                if (left(glyph.node) <= x + 0.001 and x + 0.001 < left(glyph.node) + glyph.node.style.width.px) {
                    try std.testing.expect(covering == null);
                    covering = glyph.node;
                }
            }
            if (!drawn) {
                try std.testing.expect(covering == null);
                for (std.enums.values(BandKind)) |kind| for (row.bands.get(kind).items) |band| {
                    if (band.style.display == .none) continue;
                    try std.testing.expect(!(left(band) <= x + 0.001 and x + 0.001 < left(band) + band.style.width.px));
                };
                continue;
            }
            const node = covering orelse return error.CellNotPainted;
            const props = node.getText().?;
            try std.testing.expectApproxEqAbs(cw, props.monospace_char_width, 0.0001);
            const offset_cells = (x - left(node)) / cw;
            try std.testing.expectApproxEqAbs(@round(offset_cells), offset_cells, 0.001);
            const offset: u32 = @intFromFloat(@round(offset_cells));
            if (props.content.len > 1 and grapheme.len <= 1 and cell.width == .single) {
                // Fixed-advance run: byte offset == column offset.
                try std.testing.expectEqual(if (grapheme.len == 0) ' ' else grapheme[0], props.content[offset]);
            } else {
                try std.testing.expectEqual(@as(u32, 0), offset);
                try std.testing.expectEqualStrings(if (grapheme.len == 0) " " else grapheme, props.content);
                try std.testing.expectApproxEqAbs(cw * @as(f32, if (cell.width == .wide_lead) 2 else 1), node.style.width.px, 0.001);
            }
            // Resolve the node's paint at this byte: a covering span overrides the base.
            var color = props.color;
            var weight = props.font_weight;
            var italic = props.use_italic_font;
            var strike = props.strikethrough;
            var underline: ?ui.types.UnderlineStyle = null;
            var underline_color: ?ui.Color = null;
            var spans_covering: usize = 0;
            for (props.spans) |span| if (span.start <= offset and offset < span.end) {
                spans_covering += 1;
                if (span.color) |c| color = c;
                if (span.font_weight) |w| weight = w;
                italic = italic or span.use_italic_font;
                strike = span.strikethrough;
                if (span.underline) underline = span.underline_style;
                underline_color = span.underline_color;
            };
            try std.testing.expect(spans_covering <= 1);
            if (props.spans.len > 1) try std.testing.expectEqual(@as(usize, 1), spans_covering);
            if (@import("../view/terminal_cell_graphics.zig").codepoint(props.content) != null) {
                // Cell graphics paint their own ink; the text keeps bounds only.
                try std.testing.expectEqual(ui.Color.TRANSPARENT, props.color);
                try std.testing.expectEqual(@as(usize, 0), props.spans.len);
            } else try std.testing.expectEqual(want.fg, color);
            try std.testing.expectEqual(want.weight, weight);
            try std.testing.expectEqual(want.italic, italic);
            try std.testing.expectEqual(want.strike, strike);
            try std.testing.expectEqual(want.underline, underline);
            if (want.underline != null) try std.testing.expectEqual(want.underline_color, underline_color.?);
            const bands = [_]struct { BandKind, ?ui.Color }{ .{ .background, want.bg }, .{ .overline, want.overline }, .{ .double_underline, want.double_underline } };
            for (bands) |pair| {
                var hits: usize = 0;
                for (row.bands.get(pair[0]).items) |band| {
                    if (band.style.display == .none) continue;
                    if (!(left(band) <= x + 0.001 and x + 0.001 < left(band) + band.style.width.px)) continue;
                    hits += 1;
                    // Bands start and end on cell edges.
                    const start_cells = (left(band) - origin) / cw;
                    try std.testing.expectApproxEqAbs(@round(start_cells), start_cells, 0.001);
                    try std.testing.expectApproxEqAbs(@round(band.style.width.px / cw), band.style.width.px / cw, 0.001);
                    const painted = switch (pair[0]) {
                        .background, .overline => band.getBackground(),
                        .double_underline => band.style.ext.?.border_side_colors.?.top.?,
                    };
                    try std.testing.expectEqual(pair[1].?, painted);
                    try std.testing.expectApproxEqAbs(switch (pair[0]) {
                        .background => surface.options.row_height,
                        .overline => 1,
                        .double_underline => 4,
                    }, band.style.height.px, 0.001);
                }
                try std.testing.expectEqual(@as(usize, if (pair[1] != null) 1 else 0), hits);
            }
        }
    }
}

test "terminal surface style runs: per-cell styled screen merges into span runs with exact cells" {
    var transport: FakeTransport = undefined;
    var mounted = try Mounted.init(&transport);
    defer mounted.deinit();
    var screen: std.ArrayList(u8) = .empty;
    defer screen.deinit(a);
    try styledScreen(&screen, 0);
    try mounted.show(1, screen.items);
    const surface = mounted.view.terminal_surface.?;
    try expectCellExact(surface);
    const r = surface.rows.items;
    // lolcat / 256-colour foreground / mixed SGR rows: one text node, no bands.
    // lolcat over words: a style change inside a word stays a node boundary
    // (zenit shapes a word as one unit; TextSpan cannot cut it), every other
    // change is a span. One node per intra-word colour change, no bands.
    const projection = &surface.snapshot.?.projection;
    for ([_]usize{ 0, 11, 12, 23 }) |index| {
        const value = projection.visible_rows[index];
        const cells = projection.cells[value.cell_start..][0..value.cell_count];
        var breaks: usize = 0;
        var spaces: usize = 0;
        for (cells[1..], 1..) |cell, col| {
            const before = projection.grapheme(cells[col - 1]);
            const here = projection.grapheme(cell);
            if (here[0] == ' ') spaces += 1;
            if (before[0] != ' ' and here[0] != ' ') breaks += 1;
        }
        try std.testing.expect(spaces >= 12);
        try std.testing.expectEqual(1 + breaks, visibleGlyphs(&r[index]));
        try std.testing.expectEqual(1 + breaks, visibleNodes(r[index].root) - 1);
    }
    // No spaces at all: nothing can merge (one node per cell, as before).
    try std.testing.expectEqual(@as(usize, cols), visibleGlyphs(&r[10]));
    // Colour-number chart: tokens start with spaces, so one node, a span per number.
    try std.testing.expectEqual(@as(usize, 1), visibleGlyphs(&r[1]));
    try std.testing.expectEqual(@as(usize, cols / 4), r[1].glyphs.items[0].node.getText().?.spans.len);
    // 256-colour background chart: one text node, one band per distinct background.
    try std.testing.expectEqual(@as(usize, 1), visibleGlyphs(&r[2]));
    try std.testing.expectEqual(@as(usize, cols), visibleBands(&r[2], .background));
    // Status line: one node; one background band per segment.
    try std.testing.expectEqual(@as(usize, 1), visibleGlyphs(&r[3]));
    try std.testing.expectEqual(@as(usize, 8), visibleBands(&r[3], .background));
    try std.testing.expectEqual(@as(usize, 8), r[3].glyphs.items[0].node.getText().?.spans.len);
    // Per-word SGR: one node, word and separator spans alternate.
    try std.testing.expectEqual(@as(usize, 1), visibleGlyphs(&r[4]));
    // word09's SGR 0 resets its colour: it shares the separators' ink.
    try std.testing.expectEqual(@as(usize, 18), r[4].glyphs.items[0].node.getText().?.spans.len);
    // Highlighted diff on a whole-line background (BCE fills the erased tail):
    // "render(", "(cells", "cells,", "42)" change style inside a word.
    try std.testing.expectEqual(@as(usize, 5), visibleGlyphs(&r[5]));
    try std.testing.expectEqual(@as(usize, 1), visibleBands(&r[5], .background));
    try std.testing.expectApproxEqAbs(@as(f32, cols) * surface.options.cell_width, r[5].bands.get(.background).items[0].style.width.px, 0.001);
    // Wide characters and cell graphics keep their own nodes.
    try std.testing.expectEqual(@as(usize, 32), visibleGlyphs(&r[6]));
    try std.testing.expectEqual(@as(usize, 40), visibleGlyphs(&r[7]));
    // Reverse video: one text node; each reversed word's background is its foreground.
    try std.testing.expectEqual(@as(usize, 1), visibleGlyphs(&r[8]));
    try std.testing.expectEqual(@as(usize, 3), visibleBands(&r[8], .background));
    // Overline / double underline: one text node; one band per decorated word.
    try std.testing.expectEqual(@as(usize, 1), visibleGlyphs(&r[9]));
    try std.testing.expectEqual(@as(usize, 4), visibleBands(&r[9], .overline));
    try std.testing.expectEqual(@as(usize, 8), visibleBands(&r[9], .double_underline));
    // Selection paints above every background and below every glyph and line.
    for (r[0..rows]) |*row| {
        var selection_index: usize = 0;
        for (row.root.children.items, 0..) |child, index| if (child == row.selected) {
            selection_index = index;
        };
        for (row.root.children.items, 0..) |child, index| {
            for (row.bands.get(.background).items) |band| if (band == child) try std.testing.expect(index < selection_index);
            for (row.glyphs.items) |glyph| if (glyph.node == child) try std.testing.expect(index > selection_index);
            for (row.bands.get(.overline).items) |band| if (band == child) try std.testing.expect(index > selection_index);
            for (row.bands.get(.double_underline).items) |band| if (band == child) try std.testing.expect(index > selection_index);
        }
    }
    // Pooled nodes return to plain text and back without growth or stale paint.
    var pool: [rows]usize = undefined;
    for (r[0..rows], 0..) |*row, index| pool[index] = row.glyphs.items.len + row.bands.get(.background).items.len + row.bands.get(.overline).items.len + row.bands.get(.double_underline).items.len;
    try mounted.show(2, "\x1b[0m\x1b[H\x1b[2Jplain text\r\nsecond");
    try expectCellExact(surface);
    try std.testing.expectEqual(@as(usize, 1), visibleGlyphs(&r[0]));
    try std.testing.expectEqual(@as(usize, 0), r[0].glyphs.items[0].node.getText().?.spans.len);
    for (r[0..rows]) |*row| for (std.enums.values(BandKind)) |kind| try std.testing.expectEqual(@as(usize, 0), visibleBands(row, kind));
    try mounted.show(3, screen.items);
    try expectCellExact(surface);
    for (r[0..rows], 0..) |*row, index| try std.testing.expectEqual(pool[index], row.glyphs.items.len + row.bands.get(.background).items.len + row.bands.get(.overline).items.len + row.bands.get(.double_underline).items.len);
}

test "terminal surface style runs: selection and copy over merged runs follow cells" {
    var transport: FakeTransport = undefined;
    var mounted = try Mounted.init(&transport);
    defer mounted.deinit();
    var screen: std.ArrayList(u8) = .empty;
    defer screen.deinit(a);
    try styledScreen(&screen, 0);
    try mounted.show(1, screen.items);
    const surface = mounted.view.terminal_surface.?;
    const cx = mounted.cx;
    _ = cx.render();
    // Drag across columns 7..12 ("word01") of the per-word SGR row (row 4).
    const bounds = surface.viewport.globalRect();
    const cw = surface.options.cell_width;
    const y = bounds.y + surface.presentationY(4) + surface.options.row_height * 0.5;
    const x0 = bounds.x + surface.contentPadding().left + surface.bodyX() + 7 * cw + cw * 0.2;
    const x1 = bounds.x + surface.contentPadding().left + surface.bodyX() + 12 * cw + cw * 0.8;
    cx.handleMouseDownEx(x0, y, .left, .{});
    cx.handleMouseMoveEx(x1, y, .{});
    cx.handleMouseUpEx(x1, y, .left, .{});
    _ = try mounted.view.refreshTerminalService(owner, true);
    cx.layout();
    _ = cx.render();
    const copied = (try mounted.view.copySelectionText(a)) orelse return error.SelectionMissing;
    defer a.free(copied);
    try std.testing.expectEqualStrings("word01", copied);
    const row = &surface.rows.items[4];
    try std.testing.expectEqual(.flex, row.selected.style.display);
    try std.testing.expectApproxEqAbs(surface.bodyX() + row.layout.shift_x + 7 * cw, left(row.selected), 0.001);
    try std.testing.expectApproxEqAbs(6 * cw, row.selected.style.width.px, 0.001);
    // The merged run's spans are untouched by selection.
    try std.testing.expectEqual(@as(usize, 18), row.glyphs.items[0].node.getText().?.spans.len);
    try expectCellExact(surface);
}

test "terminal surface style runs: span cap continues the run in a new node on the grid" {
    var transport: FakeTransport = undefined;
    try transport.init(2, 200);
    defer transport.deinit();
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(a);
    // 100 one-letter words in their own colours, default-coloured spaces
    // between: 200 spans in a run that may merge throughout.
    for (0..100) |index| {
        var buf: [40]u8 = undefined;
        try bytes.appendSlice(a, try std.fmt.bufPrint(&buf, "\x1b[38;2;{d};{d};9m{c}\x1b[39m ", .{ index, 255 - index, @as(u8, @intCast('a' + index % 26)) }));
    }
    try bytes.appendSlice(a, "\x1b[0m");
    try transport.controller.feedOutput(owner, 1, bytes.items, 1);
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(2400, 200);
    var view = try View.mount(cx);
    cx.root = view.root;
    defer view.releaseBuffers(cx);
    view.setTypography(14, 1.5, 400);
    view.setTimestampGutter(false);
    try view.bindTerminalService(transport.service());
    _ = cx.render();
    _ = try view.refreshTerminalService(owner, true);
    _ = cx.render();
    const surface = view.terminal_surface.?;
    try std.testing.expect(surface.snapshot.?.projection.cols >= 200);
    const row = &surface.rows.items[0];
    try std.testing.expectEqual(@as(usize, 2), visibleGlyphs(row));
    const first = row.glyphs.items[0].node;
    const second = row.glyphs.items[1].node;
    try std.testing.expectEqual(@as(usize, 128), first.getText().?.spans.len);
    try std.testing.expectEqual(@as(usize, 128), first.getText().?.content.len);
    try std.testing.expectEqual(@as(usize, 72), second.getText().?.spans.len);
    try std.testing.expectEqual(@as(usize, 72), second.getText().?.content.len);
    try std.testing.expectApproxEqAbs(left(first) + 128 * surface.options.cell_width, left(second), 0.001);
    try expectCellExact(surface);
}

test "terminal surface style runs: blink hides only its own span inside a merged run" {
    const saved = ui.a11y.preferences.current();
    defer ui.a11y.preferences.set(saved);
    ui.a11y.preferences.set(.{});
    var transport: FakeTransport = undefined;
    var mounted = try Mounted.init(&transport);
    defer mounted.deinit();
    try mounted.show(1, "\x1b[H\x1b[2J\x1b[31mab \x1b[5;4mcd\x1b[25;24m \x1b[32mef\x1b[0m");
    const surface = mounted.view.terminal_surface.?;
    const cx = mounted.cx;
    cx.setFocus(mounted.view.root);
    _ = try mounted.view.refreshTerminalService(owner, true);
    try std.testing.expect(surface.focused and !surface.reduced_motion and surface.blink_running);
    const node = surface.rows.items[0].glyphs.items[0].node;
    try std.testing.expectEqualStrings("ab cd ef", node.getText().?.content);
    try std.testing.expectEqual(@as(usize, 4), node.getText().?.spans.len);
    // Visible phase: every span keeps its ink.
    try std.testing.expect(surface.blink);
    var spans = node.getText().?.spans;
    for (spans) |span| try std.testing.expect(span.color.?.a != 0);
    try expectCellExact(surface);
    // Half a period later (blink_half_period_ms = 550): only "cd" and its
    // underline lose their ink, in the same pooled node.
    cx.frame_time_ms = surface.last_blink + 550;
    _ = try mounted.view.refreshTerminalService(owner, true);
    try std.testing.expect(!surface.blink);
    try std.testing.expectEqual(node, surface.rows.items[0].glyphs.items[0].node);
    spans = node.getText().?.spans;
    try std.testing.expectEqual(@as(usize, 4), spans.len);
    try std.testing.expect(spans[0].color.?.a != 0 and spans[2].color.?.a != 0 and spans[3].color.?.a != 0);
    try std.testing.expectEqual(@as(u8, 0), spans[1].color.?.a);
    try std.testing.expect(spans[1].underline);
    try std.testing.expectEqual(@as(u8, 0), spans[1].underline_color.?.a);
    try expectCellExact(surface);
}

test "terminal surface style runs: a style change inside a word stays a shaping boundary" {
    var transport: FakeTransport = undefined;
    var mounted = try Mounted.init(&transport);
    defer mounted.deinit();
    // "->" and "==" are ligatures in the default font (JetBrains Mono): their
    // halves must never be shaped together across a colour change.
    try mounted.show(1, "\x1b[H\x1b[2J\x1b[31m-\x1b[32m>\x1b[0m \x1b[33m=\x1b[34m=\x1b[0m");
    const surface = mounted.view.terminal_surface.?;
    const row = &surface.rows.items[0];
    try std.testing.expectEqual(@as(usize, 3), visibleGlyphs(row));
    const texts = [_][]const u8{ "-", "> =", "=" };
    const columns = [_]f32{ 0, 1, 4 };
    for (row.glyphs.items[0..3], texts, columns) |glyph, text, column| {
        try std.testing.expectEqualStrings(text, glyph.node.getText().?.content);
        try std.testing.expectApproxEqAbs(surface.bodyX() + row.layout.shift_x + column * surface.options.cell_width, left(glyph.node), 0.001);
    }
    try std.testing.expectEqual(@as(usize, 3), row.glyphs.items[1].node.getText().?.spans.len);
    try expectCellExact(surface);
}
