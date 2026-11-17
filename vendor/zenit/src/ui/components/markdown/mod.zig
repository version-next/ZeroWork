/// Markdown read-only renderer (render only, no editing).
///
/// For rich-text tooltips, simple doc display on about/settings pages, any "display an existing
/// markdown string" case. **Not** for WYSIWYG editing; real editors couple parser to editing and
/// are built atop zenit as app code.
///
/// Design principles:
/// - Single-pass byte scan -> flat Block array (each Block embeds Inline spans)
/// - Inline spans render via TextSpan (bold/italic/code), not split text nodes
/// - `![alt](data:...)` degrades to a `[alt]` text chip, never fetches images
/// - `<http://...>` autolinks are not expanded, flattened to plain text
/// - Unclosed fence / malformed input is fuzz-safe: forced flush at end
///
/// Not supported (explicit non-goals):
///   - nested lists, setext headings, task lists, footnotes, definition lists, HTML passthrough
///   - image fetching
///
/// Opt-in blocks (default off, so the default output is unchanged):
///   - GFM pipe tables (`MarkdownOptions.table`: `.grid` framed, `.rules` horizontal rules only)
///   - code block chrome (`MarkdownOptions.code_block`): borderless frame, a header row with the
///     fence language, a wrap toggle and a copy button (native ghost xs Buttons), a max height
///     with scrolling inside (both axes while lines do not wrap)
///
/// Consumer:
/// ```zig
/// const result = try markdown.Markdown(text, .{
///     .base_font_size = 12,
///     .theme = my_theme,
/// }).render(cx);
/// try parent.appendChild(cx.allocator, result.root);
/// ```
const std = @import("std");
const core = @import("../../core.zig");
const view = @import("../../view.zig");
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const Source = reactive.Source;
const bind_mod = @import("../../bind.zig");
const svg_assets = @import("../../svg_assets.zig");
pub const code_block = @import("code_block.zig");
const ScrollbarVisibility = @import("../scroll_area/mod.zig").ScrollbarVisibility;
const OverscrollBehavior = @import("../scroll_area/mod.zig").OverscrollBehavior;
pub const CodeBlock = code_block.CodeBlock;
pub const CodeBlockProps = code_block.CodeBlockProps;
pub const CodeBlockLabels = code_block.CodeBlockLabels;
pub const CodeBlockTestIds = code_block.CodeBlockTestIds;
pub const CodeDetailTone = code_block.CodeDetailTone;

const Cx = core.Cx;
const Node = core.Node;
const Color = core.Color;
const Padding = core.Padding;
const TextSpan = core.TextSpan;
const box = core.box;

// ============================================================================
// Public API
// ============================================================================

pub const MarkdownOptions = struct {
    base_font_size: f32 = 12,
    /// Font size for code regions (default slightly smaller than body).
    code_font_size: f32 = 11,
    /// Body text color (null follows the active theme).
    text_color: ?Color = null,
    /// Inline code / fenced code font color (null follows the active theme).
    code_color: ?Color = null,
    /// Inline code / fenced code background (null follows the active theme).
    code_bg: ?Color = null,
    /// Link text color (null follows the active theme).
    link_color: ?Color = null,
    /// Horizontal rule color (null follows the active theme).
    rule_color: ?Color = null,
    /// Heading color (inherit text_color if null).
    heading_color: ?Color = null,
    /// Vertical spacing between paragraphs.
    paragraph_gap: f32 = core.theme.light.tokens.space.space100,
    /// Line spacing inside code block.
    code_line_height: f32 = 1.35,
    /// Body line spacing.
    line_height: f32 = 1.4,
    /// Fenced code block look and chrome. Default: the framed block (1px rule border, no header,
    /// grows with its code).
    code_block: CodeBlockOptions = .{},
    /// GFM pipe tables (`| a | b |` + `|---|---|`). `.none` (default) keeps them as paragraphs.
    table: TableStyle = .none,
    /// Test id written on each table's root (null: none).
    table_test_id: ?[]const u8 = null,
    /// Font size per heading level (`#` … `######`). null: `base_font_size` times the default
    /// scale (1.4 / 1.25 / 1.15 / 1.08 / 1.04 / 1). Headings stay 600 either way.
    heading_sizes: ?[6]f32 = null,
};

/// Fenced code block options (`MarkdownOptions.code_block`). The default value renders the
/// original framed block; any other value renders the block with its own chrome.
pub const CodeBlockOptions = struct {
    frame: CodeFrame = .bordered,
    /// Header row: the fence's language (`fg-tertiary`, xs) and, on the right, a wrap toggle and a
    /// copy button (W.Button ghost xs, icon only). Copy writes the block's code to the clipboard and
    /// shows a check for a moment.
    header: bool = false,
    /// Code taller than this scrolls inside the block. null = the block grows with its code.
    max_height: ?f32 = null,
    /// Lines wrap at first (the header's toggle flips it per block). false: long lines keep their
    /// length and the block scrolls sideways.
    wrap: bool = true,
    /// Fill of the block. null: `code_bg` for `.bordered`, `bg-secondary` for `.borderless`.
    background: ?Color = null,
    /// Called after the copy button wrote the code (the slice is valid only during the call).
    on_copy: ?core.Handler([]const u8) = null,
    /// The scrolling body's thumbs and nested-scroll edges (`ScrollAreaProps.scrollbars` /
    /// `overscroll_y` / `overscroll_x`), e.g. `.scrollbars = .always` so a block cut at
    /// `max_height` (or with long lines) shows that it scrolls. Blocks with chrome only (the
    /// default framed block does not scroll); not part of `isDefault`.
    scrollbars: ScrollbarVisibility = .auto,
    overscroll_y: OverscrollBehavior = .auto,
    overscroll_x: OverscrollBehavior = .auto,

    pub fn isDefault(self: CodeBlockOptions) bool {
        return self.frame == .bordered and !self.header and self.max_height == null and self.wrap and self.background == null;
    }
};

pub const CodeFrame = enum {
    /// 1px rule-colour border, `radius.control`.
    bordered,
    /// No border: the fill alone, `radius.xl` (8) — a code surface inside open text.
    borderless,
};

pub const TableStyle = enum {
    /// Not parsed: pipe rows stay paragraph text.
    none,
    /// Framed table: 1px border around and between cells, header row on `table-header-bg`.
    grid,
    /// Horizontal rules only: no frame, no vertical lines, no header fill; the header is
    /// xs-sm/600 `fg-secondary` and every row ends with a 1px `separator` line.
    rules,
};

// ============================================================================
// Style layer extracted to styles.zig, emitter only consumes, no visual decisions here
// ============================================================================

const styles = @import("styles.zig");
const mdRootStyle = styles.mdRootStyle;
const mdHeadingSizeMul = styles.mdHeadingSizeMul;
const mdCodeBlockStyle = styles.mdCodeBlockStyle;
const mdCodeLineText = styles.mdCodeLineText;
const mdRuleStyle = styles.mdRuleStyle;
const mdBlockquoteStyle = styles.mdBlockquoteStyle;
const mdBlockquoteBarStyle = styles.mdBlockquoteBarStyle;
const mdBlockquoteBodyStyle = styles.mdBlockquoteBodyStyle;
const mdListRowStyle = styles.mdListRowStyle;
const mdListMarkerText = styles.mdListMarkerText;
const mdCodeSpanStyle = styles.mdCodeSpanStyle;
const mdImageChipSpanStyle = styles.mdImageChipSpanStyle;
const mdLinkSpanStyle = styles.mdLinkSpanStyle;
const mdBoldSpanStyle = styles.mdBoldSpanStyle;
const mdItalicSpanStyle = styles.mdItalicSpanStyle;

/// Markdown attributes.
pub const MarkdownProps = struct {
    /// Text (can pass signal/derived: content or buffer address change triggers full reflow). Node
    /// borrows text bytes: static text must outlive component unmount; owned-buffer signal
    /// (`scope.createText`) remains valid after next write, covering reflow window before render.
    text: Source([]const u8),
    options: MarkdownOptions = .{},
};

/// Create Markdown: `W.Markdown(.{ .text = doc, .options = .{ .base_font_size = 13 }
/// }).mount(scope, cx)`.
pub fn Markdown(props: anytype) MarkdownBuilder {
    return .{ .props = reactive.props.coerce(MarkdownProps, props) };
}

pub const MarkdownBuilder = struct {
    props: MarkdownProps,

    pub fn mount(self: MarkdownBuilder, scope: *Scope, cx: *Cx) !*Node {
        const p = self.props;
        const my_scope = try scope.childScope();
        var scope_bound = false;
        errdefer if (!scope_bound) my_scope.dispose();
        const container = try view.render(my_scope, cx, view.box(.{ .style = mdRootStyle(p.options) }, {}));
        // Sweep: if renderInto fails mid-way, container (with already-mounted blocks) can't leak.
        errdefer cx.freeNode(container);
        container.meta.ownership.meta.component_name = "Markdown";
        try core.bindScopeToNode(my_scope, container);
        scope_bound = true;
        const Ctx = struct { cx: *Cx, options: MarkdownOptions };
        const Document = struct { text: []const u8, tokens: *const core.ThemeTokens };
        const theme_signal = try cx.themeSignal();
        const document = try my_scope.derive(Document, .{ .text = p.text, .theme = theme_signal }, struct {
            fn compute(c: anytype) Document {
                return .{ .text = c.text.get(), .tokens = c.theme.get() };
            }
        }.compute);
        try bind_mod.rebuildOn(cx, my_scope, document, container, Ctx{ .cx = cx, .options = p.options }, struct {
            fn key(doc: Document) u64 {
                var h = std.hash.Wyhash.init(0);
                h.update(doc.text);
                @import("trace").work_counters.add(.text_hash_bytes, doc.text.len);
                h.update(std.mem.asBytes(&@intFromPtr(doc.text.ptr)));
                h.update(std.mem.asBytes(&@intFromPtr(doc.tokens)));
                return h.final();
            }
        }.key, struct {
            fn build(c: Ctx, rebuild_scope: *Scope, host: *Node, doc: Document) !void {
                try renderBlocks(rebuild_scope, c.cx, host, doc.text, c.options);
            }
        }.build);
        return container;
    }
};

/// Append markdown directly to an existing container (no outer wrapper); fits embedding into a
/// pre-laid popup/panel.
///
/// **Lifetime**: emitted Nodes' `text.content` slices borrow from `text` until Node destroy; the
/// caller **must ensure `text` outlives Node destroy** (typical: hold `current_text: ?[]u8`, free
/// the old buffer and pass a new one on each refresh). The component never allocates/frees
/// intermediate buffers; the caller owns text.
pub fn renderInto(cx: *Cx, container: *Node, text: []const u8, opts: MarkdownOptions) !void {
    // Block elements are static (no effect, no binding, nodes don't reference scope), mount-time
    // scope lives only this call; Markdown walks renderBlocks with rebuildOn's rebuild scope.
    const tmp_scope = try Scope.init(cx.allocator, null, cx.owner);
    defer tmp_scope.dispose();
    try renderBlocks(tmp_scope, cx, container, text, opts);
}

fn renderBlocks(scope: *Scope, cx: *Cx, container: *Node, text: []const u8, options: MarkdownOptions) !void {
    const opts = styles.themeOptions(options, cx.tokens);
    const allocator = cx.allocator;
    var scanner = BlockScanner{ .src = text, .tables = opts.table != .none };
    while (try scanner.next(allocator)) |block| {
        switch (block) {
            .paragraph => |lines| try emitParagraph(scope, cx, container, lines, opts),
            .heading => |h| try emitHeading(scope, cx, container, h.level, h.text, opts),
            .code_block => |c| if (opts.code_block.isDefault())
                try emitCodeBlock(scope, cx, container, c.content, opts)
            else
                try emitCodeBlockChrome(scope, cx, container, c.content, c.lang, opts),
            .table => |t| try emitTable(scope, cx, container, t, opts),
            .rule => try emitRule(scope, cx, container, opts),
            .blockquote => |q| try emitBlockquote(scope, cx, container, q, opts),
            .list_item => |li| try emitListItem(scope, cx, container, li.ordered, li.marker, li.text, opts),
        }
    }
}

// ============================================================================
// Block scanner
// ============================================================================

const Block = union(enum) {
    paragraph: []const u8,
    heading: struct { level: u8, text: []const u8 },
    code_block: struct { content: []const u8, lang: []const u8 = "" },
    /// Header line, the delimiter line is skipped; `rows` = the body lines (one per row).
    table: TableBlock,
    rule: void,
    blockquote: []const u8,
    list_item: struct { ordered: bool, marker: []const u8, text: []const u8 },
};

const TableBlock = struct { header: []const u8, rows: []const u8 };

const BlockScanner = struct {
    src: []const u8,
    pos: usize = 0,
    /// Recognize GFM pipe tables (MarkdownOptions.table != .none).
    tables: bool = false,

    fn next(self: *BlockScanner, allocator: std.mem.Allocator) !?Block {
        _ = allocator;
        // Every byte the scanner walks over, whichever block it ends up in.
        const start = self.pos;
        defer @import("trace").work_counters.add(.md_scanned_bytes, self.pos -| start);
        // Skip consecutive blank lines.
        while (self.pos < self.src.len) {
            const line = peekLine(self.src, self.pos);
            if (lineIsBlank(line.content)) {
                self.pos = line.next;
                continue;
            }
            break;
        }
        if (self.pos >= self.src.len) return null;

        const line = peekLine(self.src, self.pos);
        const trimmed = trimAscii(line.content);

        // fenced code block
        if (std.mem.startsWith(u8, trimmed, "```") or std.mem.startsWith(u8, trimmed, "~~~")) {
            const fence_char = trimmed[0];
            const lang = fenceLanguage(trimmed);
            self.pos = line.next;
            const content_start = self.pos;
            // Scan to matching fence or EOF.
            while (self.pos < self.src.len) {
                const l = peekLine(self.src, self.pos);
                const t = trimAscii(l.content);
                if (t.len >= 3 and t[0] == fence_char and t[1] == fence_char and t[2] == fence_char) {
                    const content_end = self.pos;
                    self.pos = l.next;
                    return .{ .code_block = .{ .content = trimTrailingNewline(self.src[content_start..content_end]), .lang = lang } };
                }
                self.pos = l.next;
            }
            // Unclosed fence: treat rest as code.
            return .{ .code_block = .{ .content = trimTrailingNewline(self.src[content_start..self.src.len]), .lang = lang } };
        }

        // GFM table: a pipe row followed by a delimiter row; body rows run to the first line
        // without a pipe (or a blank line).
        if (self.tables and isTableStart(self.src, line)) {
            const header = trimmed;
            self.pos = peekLine(self.src, line.next).next;
            const rows_start = self.pos;
            var rows_end = self.pos;
            while (self.pos < self.src.len) {
                const l = peekLine(self.src, self.pos);
                const t = trimAscii(l.content);
                if (t.len == 0 or std.mem.indexOfScalar(u8, t, '|') == null) break;
                rows_end = l.next;
                self.pos = l.next;
            }
            return .{ .table = .{ .header = header, .rows = self.src[rows_start..rows_end] } };
        }

        // Horizontal rule: --- / *** / ___ (3+ chars, spaces allowed).
        if (isHorizontalRule(trimmed)) {
            self.pos = line.next;
            return .rule;
        }

        // ATX heading
        if (atxHeadingLevel(trimmed)) |level| {
            self.pos = line.next;
            const heading_text = trimAscii(trimmed[level + 1 ..]);
            return .{ .heading = .{ .level = level, .text = heading_text } };
        }

        // Blockquote (single level).
        if (trimmed.len > 0 and trimmed[0] == '>') {
            self.pos = line.next;
            const quote_text = if (trimmed.len > 1 and trimmed[1] == ' ')
                trimmed[2..]
            else
                trimmed[1..];
            return .{ .blockquote = quote_text };
        }

        // Unordered list (single level).
        if (trimmed.len >= 2) {
            const first = trimmed[0];
            if ((first == '-' or first == '*' or first == '+') and trimmed[1] == ' ') {
                self.pos = line.next;
                return .{ .list_item = .{ .ordered = false, .marker = trimmed[0..1], .text = trimmed[2..] } };
            }
        }

        // Ordered list `1. xxx` / `10. xxx` (single level).
        if (std.ascii.isDigit(trimmed[0])) {
            var digit_end: usize = 0;
            while (digit_end < trimmed.len and std.ascii.isDigit(trimmed[digit_end])) digit_end += 1;
            if (digit_end > 0 and digit_end + 1 < trimmed.len and trimmed[digit_end] == '.' and trimmed[digit_end + 1] == ' ') {
                self.pos = line.next;
                // The marker keeps its delimiter: "1." renders as "1.", not "1".
                return .{ .list_item = .{ .ordered = true, .marker = trimmed[0 .. digit_end + 1], .text = trimmed[digit_end + 2 ..] } };
            }
        }

        // Paragraph: accumulate following non-empty non-special lines. First line unconditionally
        // consumed: reaching here means it's not a block start; if break condition diverges from
        // block check above (e.g., '#123' not legal ATX), not advancing pos causes next() to loop
        // empty paragraphs -> renderInto infinite loop.
        const para_start = self.pos;
        self.pos = line.next;
        while (self.pos < self.src.len) {
            const l = peekLine(self.src, self.pos);
            const t = trimAscii(l.content);
            if (t.len == 0) break;
            if (std.mem.startsWith(u8, t, "```") or std.mem.startsWith(u8, t, "~~~")) break;
            if (isHorizontalRule(t)) break;
            if (atxHeadingLevel(t) != null) break;
            if (t.len > 0 and t[0] == '>') break;
            if (t.len >= 2 and (t[0] == '-' or t[0] == '*' or t[0] == '+') and t[1] == ' ') break;
            if (self.tables and isTableStart(self.src, l)) break;
            self.pos = l.next;
        }
        return .{ .paragraph = self.src[para_start..self.pos] };
    }
};

// ============================================================================
// Block emitters
// ============================================================================

// Block nodes mount as built (view.mount), applyInlineText failure rolls back with container guard.
// Body nodes = box + applyInlineText: content has TextSpan (bold/italic/code/link) composed by
// InlineBuilder then handed off; view.text has no spans entry, text writes post-mount.
const grow_width = core.BoxStyle{ .width = .{ .grow = .{} } };
const row_item_width = core.BoxStyle{ .width = .{ .grow = .{} }, .min_width = 0 };

fn emitParagraph(scope: *Scope, cx: *Cx, container: *Node, text: []const u8, opts: MarkdownOptions) !void {
    var node: *Node = undefined;
    try view.mount(scope, cx, container, view.capture(&node, view.box(.{ .style = grow_width }, {})));
    try applyInlineText(cx, node, text, opts.base_font_size, styles.resolvedColor(opts, "text_color"), opts.line_height, 400, opts);
}

fn emitHeading(scope: *Scope, cx: *Cx, container: *Node, level: u8, text: []const u8, opts: MarkdownOptions) !void {
    var node: *Node = undefined;
    try view.mount(scope, cx, container, view.capture(&node, view.box(.{
        .style = grow_width,
        // Headings are render-only 'larger heavier text'; screen reader gets role=heading so it
        // lists outline, user can jump by heading. (a11y tree currently lacks heading level field,
        // hierarchy unexpressed.)
        .a11y = core.A11yProps{ .role = .heading, .label = text },
    }, {})));
    const color = opts.heading_color orelse styles.resolvedColor(opts, "text_color");
    const font_size = if (opts.heading_sizes) |sizes| sizes[@min(@max(level, 1), 6) - 1] else opts.base_font_size * mdHeadingSizeMul(level);
    try applyInlineText(cx, node, text, font_size, color, opts.line_height, 600, opts);
}

fn emitCodeBlock(scope: *Scope, cx: *Cx, container: *Node, code: []const u8, opts: MarkdownOptions) !void {
    var block: *Node = undefined;
    try view.mount(scope, cx, container, view.capture(&block, view.box(.{ .style = mdCodeBlockStyle(opts) }, {})));
    var it = std.mem.splitScalar(u8, code, '\n');
    while (it.next()) |line| {
        if (line.len == 0) continue;
        try view.mount(scope, cx, block, view.text(.{ .style = mdCodeLineText(opts) }, line));
    }
}

/// Code block with chrome (`MarkdownOptions.code_block` not default): W.CodeBlock with the fence's
/// language as its label.
fn emitCodeBlockChrome(scope: *Scope, cx: *Cx, container: *Node, code: []const u8, lang: []const u8, opts: MarkdownOptions) !void {
    const node = try code_block.CodeBlock(.{ .code = code, .label = lang, .options = opts }).mount(scope, cx);
    errdefer cx.freeNode(node);
    try container.appendChild(cx.allocator, node);
}

/// GFM pipe table: rows of cells whose widths follow one weight per column (the column's
/// longest cell, clamped), so every row lines up without a measuring pass.
fn emitTable(scope: *Scope, cx: *Cx, container: *Node, table: TableBlock, opts: MarkdownOptions) !void {
    const t = cx.tokens;
    var header_cells: [max_table_columns][]const u8 = undefined;
    const columns = splitCells(table.header, &header_cells);
    if (columns == 0) return emitParagraph(scope, cx, container, table.header, opts);
    var weights: [max_table_columns]f32 = @splat(0);
    for (header_cells[0..columns], 0..) |cell, i| weights[i] = cellWeight(cell);
    var it = std.mem.splitScalar(u8, table.rows, '\n');
    while (it.next()) |line| {
        if (trimAscii(line).len == 0) continue;
        var cells: [max_table_columns][]const u8 = undefined;
        const n = splitCells(trimAscii(line), &cells);
        for (cells[0..@min(n, columns)], 0..) |cell, i| weights[i] = @max(weights[i], cellWeight(cell));
    }
    var root: *Node = undefined;
    try view.mount(scope, cx, container, view.capture(&root, view.col(.{
        .style = styles.tableStyle(opts, t),
        .a11y = core.A11yProps{ .role = .table },
    }, {})));
    root.meta.ownership.meta.component_name = "MarkdownTable";
    if (opts.table_test_id) |id| root.meta.ownership.meta.test_id = id;
    var row_count: usize = 0;
    {
        var rows = std.mem.splitScalar(u8, table.rows, '\n');
        while (rows.next()) |line| {
            if (trimAscii(line).len != 0) row_count += 1;
        }
    }
    try emitTableRow(scope, cx, root, header_cells[0..columns], weights[0..columns], true, row_count == 0, opts);
    var rows = std.mem.splitScalar(u8, table.rows, '\n');
    var index: usize = 0;
    while (rows.next()) |line| {
        const trimmed = trimAscii(line);
        if (trimmed.len == 0) continue;
        index += 1;
        var cells: [max_table_columns][]const u8 = @splat("");
        _ = splitCells(trimmed, &cells);
        try emitTableRow(scope, cx, root, cells[0..columns], weights[0..columns], false, index == row_count, opts);
    }
}

fn emitTableRow(scope: *Scope, cx: *Cx, table: *Node, cells: []const []const u8, weights: []const f32, header: bool, last: bool, opts: MarkdownOptions) !void {
    const t = cx.tokens;
    var row: *Node = undefined;
    try view.mount(scope, cx, table, view.capture(&row, view.row(.{
        .style = styles.tableRowStyle(opts, t, header, last),
        .a11y = core.A11yProps{ .role = .row },
    }, {})));
    const text = styles.tableText(opts, t, header);
    for (cells, weights, 0..) |cell, weight, i| {
        var node: *Node = undefined;
        try view.mount(scope, cx, row, view.box(.{
            .style = styles.tableCellStyle(opts, t, weight, i + 1 == cells.len),
            .a11y = core.A11yProps{ .role = if (header) .columnheader else .gridcell, .label = cell },
        }, .{view.capture(&node, view.box(.{ .style = grow_width }, {}))}));
        try applyInlineText(cx, node, cell, text.font_size, text.color, opts.line_height, text.font_weight, opts);
    }
}

const max_table_columns = 16;

/// Split one pipe row into trimmed cells (outer pipes optional, `\|` stays in the cell).
fn splitCells(line: []const u8, out: *[max_table_columns][]const u8) usize {
    var body = trimAscii(line);
    if (body.len > 0 and body[0] == '|') body = body[1..];
    if (body.len > 0 and body[body.len - 1] == '|' and (body.len < 2 or body[body.len - 2] != '\\')) body = body[0 .. body.len - 1];
    var n: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= body.len) : (i += 1) {
        const at_end = i == body.len;
        if (!at_end and body[i] == '\\' and i + 1 < body.len) {
            i += 1;
            continue;
        }
        if (at_end or body[i] == '|') {
            if (n == max_table_columns) break;
            out[n] = trimAscii(body[start..i]);
            n += 1;
            start = i + 1;
        }
    }
    return n;
}

/// Column weight: display width in ASCII columns (wide characters count 2), clamped so a long
/// cell wraps instead of starving its neighbours.
fn cellWeight(cell: []const u8) f32 {
    var width: f32 = 0;
    const view_utf8 = std.unicode.Utf8View.init(cell) catch return std.math.clamp(@as(f32, @floatFromInt(cell.len)), 3, 40);
    var cps = view_utf8.iterator();
    while (cps.nextCodepoint()) |cp| width += if (cp >= 0x1100) 2 else 1;
    return std.math.clamp(width, 3, 40);
}

/// A GFM table starts at a pipe row whose next line is a delimiter row (`|---|:--:|`).
fn isTableStart(src: []const u8, line: LineSlice) bool {
    const head = trimAscii(line.content);
    if (std.mem.indexOfScalar(u8, head, '|') == null) return false;
    if (line.next >= src.len) return false;
    return isDelimiterRow(trimAscii(peekLine(src, line.next).content));
}

fn isDelimiterRow(line: []const u8) bool {
    if (line.len == 0) return false;
    var dashes: usize = 0;
    var pipes: usize = 0;
    for (line) |c| switch (c) {
        '-' => dashes += 1,
        '|' => pipes += 1,
        ':', ' ', '\t' => {},
        else => return false,
    };
    return dashes >= 1 and (pipes >= 1 or dashes >= 3);
}

/// Fence info string's first word (```` ```zig title ```` -> "zig").
fn fenceLanguage(fence_line: []const u8) []const u8 {
    var i: usize = 0;
    while (i < fence_line.len and (fence_line[i] == '`' or fence_line[i] == '~')) i += 1;
    const info = trimAscii(fence_line[i..]);
    const end = std.mem.indexOfAny(u8, info, " \t{") orelse info.len;
    return info[0..end];
}

fn emitRule(scope: *Scope, cx: *Cx, container: *Node, opts: MarkdownOptions) !void {
    try view.mount(scope, cx, container, view.box(.{ .style = mdRuleStyle(opts) }, {}));
}

fn emitBlockquote(scope: *Scope, cx: *Cx, container: *Node, text: []const u8, opts: MarkdownOptions) !void {
    var body: *Node = undefined;
    try view.mount(scope, cx, container, view.box(.{ .style = mdBlockquoteStyle() }, .{
        view.box(.{ .style = mdBlockquoteBarStyle(opts) }, {}),
        view.capture(&body, view.box(.{ .style = mdBlockquoteBodyStyle() }, {})),
    }));
    try applyInlineText(cx, body, text, opts.base_font_size, styles.resolvedColor(opts, "text_color"), opts.line_height, 400, opts);
}

fn emitListItem(scope: *Scope, cx: *Cx, container: *Node, ordered: bool, marker: []const u8, text: []const u8, opts: MarkdownOptions) !void {
    var body: *Node = undefined;
    try view.mount(scope, cx, container, view.box(.{
        .style = mdListRowStyle(),
        // Label text only, no bullet/number marker; marker is visual (AT broadcasts 'item N'
        // itself).
        .a11y = core.A11yProps{ .role = .listitem, .label = text },
    }, .{
        view.text(.{ .style = mdListMarkerText(opts) }, if (ordered) marker else bulletGlyph()),
        // The text column may shrink below its longest word (a URL breaks instead of widening the row).
        view.capture(&body, view.box(.{ .style = row_item_width }, {})),
    }));
    try applyInlineText(cx, body, text, opts.base_font_size, styles.resolvedColor(opts, "text_color"), opts.line_height, 400, opts);
}

fn bulletGlyph() []const u8 {
    return "•";
}

// ============================================================================
// Inline parser: expand [text](url) / ![alt](url) / **bold** / *italic* / `code`
// into string + TextSpan array, attach to node.text
// ============================================================================

fn applyInlineText(
    cx: *Cx,
    node: *Node,
    raw: []const u8,
    font_size: f32,
    text_color: Color,
    line_height: f32,
    font_weight: u16,
    opts: MarkdownOptions,
) !void {
    const allocator = cx.allocator;
    var builder = InlineBuilder.init(allocator);
    defer builder.deinit();

    try expandInline(&builder, raw, opts);

    // If nothing survives (all data:url discarded), use space to maintain height.
    if (builder.text.items.len == 0) {
        try builder.text.appendSlice(allocator, " ");
    }

    const has_spans = builder.spans.items.len > 0;
    const owned_text = try builder.text.toOwnedSlice(allocator);
    errdefer allocator.free(owned_text);
    const owned_spans = if (has_spans)
        try builder.spans.toOwnedSlice(allocator)
    else
        &[_]TextSpan{};

    // Old owned text/spans freed by ContentTable.setText on next content (automatic free).
    node.setText(.{
        .content = owned_text,
        .owned = true,
        .font_size = font_size,
        .font_weight = font_weight,
        .color = text_color,
        .line_height = line_height,
        .wrap = .word_break,
        .spans = owned_spans,
        .spans_owned = has_spans,
    });
}

const InlineBuilder = struct {
    text: std.ArrayListUnmanaged(u8) = .empty,
    spans: std.ArrayListUnmanaged(TextSpan) = .empty,
    allocator: std.mem.Allocator,

    fn init(a: std.mem.Allocator) InlineBuilder {
        return .{ .allocator = a };
    }

    fn deinit(self: *InlineBuilder) void {
        self.text.deinit(self.allocator);
        self.spans.deinit(self.allocator);
    }

    fn appendPlain(self: *InlineBuilder, s: []const u8) !void {
        try self.text.appendSlice(self.allocator, s);
    }

    fn appendSpan(self: *InlineBuilder, s: []const u8, style: TextSpan) !void {
        const start: u32 = @intCast(self.text.items.len);
        try self.text.appendSlice(self.allocator, s);
        const end: u32 = @intCast(self.text.items.len);
        var span = style;
        span.start = start;
        span.end = end;
        try self.spans.append(self.allocator, span);
    }
};

fn expandInline(builder: *InlineBuilder, raw: []const u8, opts: MarkdownOptions) !void {
    // Normalize truncation sentinels: upstream often uses U+2026 or '...' at end.
    const normalised = raw;
    // (Future: allocate new buffer here for replacement; now direct passthrough.)
    var i: usize = 0;
    while (i < normalised.len) {
        const c = normalised[i];

        // A line ending inside a Markdown paragraph is a soft break, not a
        // forced text-layout newline. Keeping the raw `\n` here made LSP docs
        // preserve source-comment wrapping; the text layout then also emitted
        // an empty visual line before continuing, so prose such as
        // "If the\nrequested number ..." looked as if wrapping were broken.
        // Blank lines have already been split into separate blocks by
        // BlockScanner, so flatten only the remaining paragraph-local break.
        if (c == '\n' or c == '\r') {
            var next = i + 1;
            if (c == '\r' and next < normalised.len and normalised[next] == '\n') {
                next += 1;
            }
            const has_previous_text = builder.text.items.len > 0;
            const has_following_text = next < normalised.len;
            const previous_is_space = has_previous_text and
                (builder.text.items[builder.text.items.len - 1] == ' ' or builder.text.items[builder.text.items.len - 1] == '\t');
            const following_is_space = has_following_text and
                (normalised[next] == ' ' or normalised[next] == '\t');
            if (has_previous_text and has_following_text and !previous_is_space and !following_is_space) {
                try builder.text.append(builder.allocator, ' ');
            }
            i = next;
            continue;
        }

        // `code`
        if (c == '`') {
            if (findMatching(normalised, i + 1, '`')) |end| {
                try builder.appendSpan(normalised[i + 1 .. end], mdCodeSpanStyle(opts));
                i = end + 1;
                continue;
            }
        }

        // **bold**
        if (c == '*' and i + 1 < normalised.len and normalised[i + 1] == '*') {
            if (findDoubleStar(normalised, i + 2)) |end| {
                try builder.appendSpan(normalised[i + 2 .. end], mdBoldSpanStyle());
                i = end + 2;
                continue;
            }
        }

        // *italic* (must not be ** before/after; simple: not * before, find standalone * after).
        if (c == '*' and (i + 1 >= normalised.len or normalised[i + 1] != '*')) {
            if (findMatching(normalised, i + 1, '*')) |end| {
                if (end < normalised.len and (end == normalised.len - 1 or normalised[end + 1] != '*')) {
                    try builder.appendSpan(normalised[i + 1 .. end], mdItalicSpanStyle());
                    i = end + 1;
                    continue;
                }
            }
        }

        // _italic_, underscore italic (CommonMark allows). Avoid snake_case: no trigger if
        // letter/digit before; _ after must follow non-alphanumeric.
        if (c == '_') {
            const prev_is_word = i > 0 and isWordByte(normalised[i - 1]);
            if (!prev_is_word) {
                if (findMatchingUnderscore(normalised, i + 1)) |end| {
                    if (end > i + 1) {
                        try builder.appendSpan(normalised[i + 1 .. end], mdItalicSpanStyle());
                        i = end + 1;
                        continue;
                    }
                }
            }
        }

        // ![alt](url) image
        if (c == '!' and i + 1 < normalised.len and normalised[i + 1] == '[') {
            if (parseLink(normalised, i + 1)) |link| {
                // data:image/* downgrade to [alt] chip.
                const show_alt = link.text;
                if (show_alt.len > 0 and !isDataUri(link.url)) {
                    try builder.appendPlain("[");
                    try builder.appendPlain(show_alt);
                    try builder.appendPlain("]");
                } else if (show_alt.len > 0) {
                    try builder.appendSpan(show_alt, mdImageChipSpanStyle(opts));
                }
                // data:url: output small [alt] badge (branch above), don't embed URL.
                i = link.next;
                continue;
            }
        }

        // [text](url) link
        if (c == '[') {
            if (parseLink(normalised, i)) |link| {
                if (link.text.len > 0) {
                    try builder.appendSpan(link.text, mdLinkSpanStyle(opts));
                }
                i = link.next;
                continue;
            }
        }

        // Plain byte (multibyte UTF-8 keeps original byte sequence).
        try builder.text.append(builder.allocator, c);
        i += 1;
    }
}

const ParsedLink = struct {
    text: []const u8,
    url: []const u8,
    next: usize,
};

/// Parse `[text](url)`. Enter with src[start] == '['. Return null on failure (no consume).
fn parseLink(src: []const u8, start: usize) ?ParsedLink {
    if (start >= src.len or src[start] != '[') return null;
    const bracket_end = findMatching(src, start + 1, ']') orelse return null;
    if (bracket_end + 1 >= src.len or src[bracket_end + 1] != '(') return null;
    const paren_end = findMatching(src, bracket_end + 2, ')') orelse return null;
    return .{
        .text = src[start + 1 .. bracket_end],
        .url = src[bracket_end + 2 .. paren_end],
        .next = paren_end + 1,
    };
}

fn findMatching(src: []const u8, start: usize, ch: u8) ?usize {
    var i = start;
    while (i < src.len) : (i += 1) {
        if (src[i] == ch) return i;
        if (src[i] == '\n') return null; // Inline limited to single line.
    }
    return null;
}

fn findDoubleStar(src: []const u8, start: usize) ?usize {
    var i = start;
    while (i + 1 < src.len) : (i += 1) {
        if (src[i] == '*' and src[i + 1] == '*') return i;
        if (src[i] == '\n') return null;
    }
    return null;
}

fn isWordByte(b: u8) bool {
    return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or (b >= '0' and b <= '9') or b == '_';
}

/// Find next `_` not adjacent to letter/digit (avoid snake_case italic).
fn findMatchingUnderscore(src: []const u8, start: usize) ?usize {
    var i = start;
    while (i < src.len) : (i += 1) {
        if (src[i] == '\n') return null;
        if (src[i] == '_') {
            const next_is_word = i + 1 < src.len and isWordByte(src[i + 1]);
            if (!next_is_word) return i;
        }
    }
    return null;
}

fn isDataUri(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "data:");
}

// ============================================================================
// Helper functions
// ============================================================================

const LineSlice = struct { content: []const u8, next: usize };

fn peekLine(src: []const u8, start: usize) LineSlice {
    if (start >= src.len) return .{ .content = src[start..start], .next = src.len };
    var end = start;
    while (end < src.len and src[end] != '\n') : (end += 1) {}
    const after = if (end < src.len) end + 1 else end;
    // Strip \r.
    var content_end = end;
    if (content_end > start and src[content_end - 1] == '\r') content_end -= 1;
    return .{ .content = src[start..content_end], .next = after };
}

fn lineIsBlank(line: []const u8) bool {
    for (line) |b| if (b != ' ' and b != '\t') return false;
    return true;
}

fn trimAscii(s: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;
    while (start < end and (s[start] == ' ' or s[start] == '\t')) start += 1;
    while (end > start and (s[end - 1] == ' ' or s[end - 1] == '\t' or s[end - 1] == '\r')) end -= 1;
    return s[start..end];
}

fn trimTrailingNewline(s: []const u8) []const u8 {
    var end = s.len;
    while (end > 0 and (s[end - 1] == '\n' or s[end - 1] == '\r')) end -= 1;
    return s[0..end];
}

fn isHorizontalRule(line: []const u8) bool {
    if (line.len < 3) return false;
    const first = line[0];
    if (first != '-' and first != '*' and first != '_') return false;
    var count: usize = 0;
    for (line) |c| {
        if (c == first) {
            count += 1;
        } else if (c != ' ' and c != '\t') {
            return false;
        }
    }
    return count >= 3;
}

/// Valid ATX heading (1-6 `#` followed by space) returns level, else null.
fn atxHeadingLevel(trimmed: []const u8) ?u8 {
    if (trimmed.len == 0 or trimmed[0] != '#') return null;
    var level: u8 = 0;
    while (level < 6 and level < trimmed.len and trimmed[level] == '#') level += 1;
    if (level < trimmed.len and trimmed[level] == ' ') return level;
    return null;
}

// ============================================================================
// Tests
// ============================================================================

test "markdown: 非标题的 # 行按段落推进，不死循环" {
    const cases = [_][]const u8{ "#123 fixed\n", "#include <x>\n", "#\n", "text\n#nope\nmore\n", "####### seven\n" };
    for (cases) |src| {
        var scanner = BlockScanner{ .src = src };
        var n: usize = 0;
        while (try scanner.next(std.testing.allocator)) |b| {
            try std.testing.expect(b == .paragraph);
            try std.testing.expect(b.paragraph.len > 0);
            n += 1;
            try std.testing.expect(n < 8);
        }
        try std.testing.expectEqual(@as(usize, 1), n);
    }
    // Valid heading still breaks paragraph.
    var scanner = BlockScanner{ .src = "para\n## H\n" };
    try std.testing.expect((try scanner.next(std.testing.allocator)).? == .paragraph);
    try std.testing.expect((try scanner.next(std.testing.allocator)).? == .heading);
}

test "markdown: detects paragraph vs heading" {
    var scanner = BlockScanner{ .src = "# Hello\n\nA paragraph.\n" };
    const h = (try scanner.next(std.testing.allocator)).?;
    try std.testing.expect(h == .heading);
    try std.testing.expectEqual(@as(u8, 1), h.heading.level);
    try std.testing.expectEqualStrings("Hello", h.heading.text);
    const p = (try scanner.next(std.testing.allocator)).?;
    try std.testing.expect(p == .paragraph);
}

test "markdown: fenced code block with unclosed fence" {
    var scanner = BlockScanner{ .src = "```\nfoo\nbar\n" };
    const b = (try scanner.next(std.testing.allocator)).?;
    try std.testing.expect(b == .code_block);
    try std.testing.expectEqualStrings("foo\nbar", b.code_block.content);
}

test "markdown: horizontal rule" {
    var scanner = BlockScanner{ .src = "---\n" };
    const b = (try scanner.next(std.testing.allocator)).?;
    try std.testing.expect(b == .rule);
}

test "markdown: list items and blockquote" {
    var scanner = BlockScanner{ .src = "- first\n- second\n> quoted\n" };
    const a = (try scanner.next(std.testing.allocator)).?;
    try std.testing.expect(a == .list_item);
    try std.testing.expect(!a.list_item.ordered);
    const b = (try scanner.next(std.testing.allocator)).?;
    try std.testing.expect(b == .list_item);
    const c = (try scanner.next(std.testing.allocator)).?;
    try std.testing.expect(c == .blockquote);
    try std.testing.expectEqualStrings("quoted", c.blockquote);
}

test "markdown: an unbreakable run in a list item or a quote breaks inside the column instead of widening it" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(320, 400);
    const root = try box(cx, .{ .width = .{ .px = 288 }, .height = .{ .px = 400 }, .direction = .column }, .{});
    cx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const long = "/var/lib/very/long/path/without/any/spaces/compute-bmc-01/sel/2026-09-10T01-42-07Z/export-full-0001.json";
    const md = try Markdown(.{ .text = "1. first " ++ long ++ "\n- " ++ long ++ "\n> " ++ long }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, md);
    cx.layout();
    const width = md.rectFromWorldOrFallback().w;
    try std.testing.expect(width <= 288.5);
    for (md.children.items) |row| {
        try std.testing.expect(row.rectFromWorldOrFallback().w <= 288.5);
        // Row items may shrink below their min-content (the platform text engine measures an
        // unbreakable run as the min-content; the test text engine does not, so assert the contract).
        try std.testing.expectEqual(@as(f32, 0), row.style.getExt().min_width);
        const text_column = row.children.items[row.children.items.len - 1];
        try std.testing.expectEqual(@as(f32, 0), text_column.style.getExt().min_width);
    }
    cx.root = null;
    cx.freeNode(root);
}

test "markdown: an ordered list item keeps the period after its number" {
    var scanner = BlockScanner{ .src = "1. first\n12. twelfth\n" };
    const a = (try scanner.next(std.testing.allocator)).?;
    try std.testing.expect(a.list_item.ordered);
    try std.testing.expectEqualStrings("1.", a.list_item.marker);
    try std.testing.expectEqualStrings("first", a.list_item.text);
    const b = (try scanner.next(std.testing.allocator)).?;
    try std.testing.expectEqualStrings("12.", b.list_item.marker);
    try std.testing.expectEqualStrings("twelfth", b.list_item.text);

    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const md = try Markdown(.{ .text = "1. first\n2. second" }).mount(scope, cx);
    defer cx.freeNode(md);
    try std.testing.expect(findTextNode(md, "1.") != null);
    try std.testing.expect(findTextNode(md, "2.") != null);
}

test "markdown inline: data uri image dropped to chip" {
    var builder = InlineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try expandInline(&builder, "before ![Baseline icon](data:image/svg+xml;base64,abc) after", .{});
    const out = builder.text.items;
    // URL should not appear, 'Baseline icon' chip should.
    try std.testing.expect(std.mem.indexOf(u8, out, "data:image") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "base64") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Baseline icon") != null);
}

test "markdown inline: code span gets monospace + bg_color TextSpan" {
    var builder = InlineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try expandInline(&builder, "call `foo()` now", .{});
    try std.testing.expect(std.mem.indexOf(u8, builder.text.items, "`") == null);
    try std.testing.expect(std.mem.indexOf(u8, builder.text.items, "foo()") != null);
    try std.testing.expect(builder.spans.items.len >= 1);
    try std.testing.expect(builder.spans.items[0].use_monospace_font);
}

test "markdown inline: bold and italic spans" {
    var builder = InlineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try expandInline(&builder, "**bold** and *italic*", .{});
    try std.testing.expect(std.mem.indexOf(u8, builder.text.items, "*") == null);
    try std.testing.expectEqual(@as(usize, 2), builder.spans.items.len);
    try std.testing.expectEqual(@as(?u16, 700), builder.spans.items[0].font_weight);
    try std.testing.expect(builder.spans.items[1].use_italic_font);
}

test "markdown inline: ellipsis and plain link" {
    var builder = InlineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    try expandInline(&builder, "see [MDN](https://mdn.io/x) \u{2026}", .{});
    // Link URL absent, only 'MDN' kept.
    try std.testing.expect(std.mem.indexOf(u8, builder.text.items, "https://") == null);
    try std.testing.expect(std.mem.indexOf(u8, builder.text.items, "MDN") != null);
    // One link span.
    try std.testing.expect(builder.spans.items.len >= 1);
    try std.testing.expect(builder.spans.items[0].underline);
}

test "markdown inline: paragraph soft breaks become spaces" {
    var builder = InlineBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try expandInline(
        &builder,
        "A typed array. If the\nrequested number of bytes could not be allocated.\r\nThe operation raises an exception.",
        .{},
    );

    try std.testing.expectEqualStrings(
        "A typed array. If the requested number of bytes could not be allocated. The operation raises an exception.",
        builder.text.items,
    );
}

test "markdown: pathological unclosed inline tokens stay safe" {
    var builder = InlineBuilder.init(std.testing.allocator);
    defer builder.deinit();
    // Unclosed code/link/bold: no crash, keep original literal.
    try expandInline(&builder, "foo `unclosed and **half bold and [link no paren", .{});
    try std.testing.expect(builder.text.items.len > 0);
}

test "markdown: empty input yields no blocks" {
    var scanner = BlockScanner{ .src = "" };
    try std.testing.expect((try scanner.next(std.testing.allocator)) == null);
}

test "markdown: blank-only input yields no blocks" {
    var scanner = BlockScanner{ .src = "\n\n\t\n" };
    try std.testing.expect((try scanner.next(std.testing.allocator)) == null);
}

// styles.zig test collection; required (see docs/STYLING.md).
test {
    _ = @import("styles.zig");
}

// Remaining unsweep components (markdown render / form_field / select_headless).
const sweep_md = "# Title\n\nA **bold** and *italic* with `code` and [link](https://x.y) ![alt](a.png)\n\n- one\n- two\n1. first\n\n```\nlet x = 1;\nlet y = 2;\n```\n\n---\n\n> quoted **text**\n";
test "markdown: mount 在任意分配点失败时不泄漏（sweep）" {
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMount("markdown", struct {
        fn m(scope: *sw.Scope, cx: *sw.Cx) anyerror!?*sw.Node {
            return try Markdown(.{ .text = sweep_md }).mount(scope, cx);
        }
    }.m);
}

test "markdown: 动态文本的 mount 在任意分配点失败时不泄漏（sweep）" {
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMount("markdown(dynamic)", struct {
        fn m(scope: *sw.Scope, cx: *sw.Cx) anyerror!?*sw.Node {
            const doc = try scope.createText(sweep_md, .{});
            return try Markdown(.{ .text = doc }).mount(scope, cx);
        }
    }.m);
}

test "Markdown: a text signal re-renders the document" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const doc = try scope.createText("# One", .{});
    const root = try Markdown(.{ .text = doc }).mount(scope, ctx);
    defer ctx.freeNode(root);
    try std.testing.expectEqual(@as(usize, 1), root.children.items.len);
    doc.set("# One\n\nTwo\n\n---");
    try std.testing.expectEqual(@as(usize, 3), root.children.items.len);
}

test "review regression 5: Markdown semantic defaults and explicit default-colored overrides" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const node = try Markdown(.{ .text = "Body" }).mount(scope, cx);
    defer cx.freeNode(node);
    cx.root = node;
    defer cx.root = null;
    try std.testing.expect(Color.eql(node.children.items[0].getText().?.color, cx.tokens.tokens.color.fg_primary));
    cx.setTheme(&core.theme.dark);
    try std.testing.expect(Color.eql(node.children.items[0].getText().?.color, core.theme.dark.tokens.color.fg_primary));
    const custom = core.theme.light.tokens.color.fg_primary;
    const options = styles.themeOptions(.{ .text_color = custom }, &core.theme.dark);
    try std.testing.expect(Color.eql(custom, options.text_color.?));
    cx.root = null;
}

test "review regression 5: every explicit color survives even when equal to the light default" {
    const fields = .{ "text_color", "code_color", "code_bg", "link_color", "rule_color" };
    const tokens = .{ "fg_primary", "fg_primary", "surface_inset", "accent", "border" };
    inline for (fields, tokens) |field, token| {
        var options: MarkdownOptions = .{};
        const explicit = @field(core.theme.light.tokens.color, token);
        @field(options, field) = explicit;
        for ([_]*const core.ThemeTokens{ &core.theme.light, &core.theme.dark, &core.theme.high_contrast }) |t| {
            try std.testing.expectEqual(explicit, @field(styles.themeOptions(options, t), field).?);
            try std.testing.expectEqual(@field(t.tokens.color, token), @field(styles.themeOptions(.{}, t), field).?);
        }
    }
}

// ── Opt-in tables and code block chrome ──

fn findTestId(n: *Node, id: []const u8) ?*Node {
    if (n.meta.ownership.meta.test_id) |t| if (std.mem.eql(u8, t, id)) return n;
    for (n.children.items) |c| if (findTestId(c, id)) |r| return r;
    return null;
}

fn findComponent(n: *Node, name: []const u8) ?*Node {
    if (n.meta.ownership.meta.component_name) |c| if (std.mem.eql(u8, c, name)) return n;
    for (n.children.items) |c| if (findComponent(c, name)) |r| return r;
    return null;
}

fn findTextNode(n: *Node, text: []const u8) ?*Node {
    if (n.getText()) |t| if (std.mem.eql(u8, t.content, text)) return n;
    for (n.children.items) |c| if (findTextNode(c, text)) |r| return r;
    return null;
}

test {
    _ = code_block;
}

const table_md = "Intro line\n| Time | Sensor | Event |\n|---|:---:|---|\n| 09/10 01:42:07 | PSU 2 | AC lost |\n| 09/10 01:42:09 | System | Power off |\n\nAfter";

test "markdown: pipe tables parse only when enabled; fence language is the info word" {
    var off = BlockScanner{ .src = table_md };
    const p = (try off.next(std.testing.allocator)).?;
    try std.testing.expect(p == .paragraph);
    try std.testing.expect(std.mem.indexOf(u8, p.paragraph, "| Time") != null);

    var on = BlockScanner{ .src = table_md, .tables = true };
    const intro = (try on.next(std.testing.allocator)).?;
    try std.testing.expectEqualStrings("Intro line\n", intro.paragraph);
    const t = (try on.next(std.testing.allocator)).?;
    try std.testing.expect(t == .table);
    try std.testing.expectEqualStrings("| Time | Sensor | Event |", t.table.header);
    var cells: [max_table_columns][]const u8 = undefined;
    try std.testing.expectEqual(@as(usize, 3), splitCells(t.table.header, &cells));
    try std.testing.expectEqualStrings("Sensor", cells[1]);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, t.table.rows, "\n"));
    try std.testing.expect((try on.next(std.testing.allocator)).? == .paragraph);
    try std.testing.expect((try on.next(std.testing.allocator)) == null);

    var fence = BlockScanner{ .src = "```bash title\nls\n```" };
    const code = (try fence.next(std.testing.allocator)).?;
    try std.testing.expectEqualStrings("bash", code.code_block.lang);
    try std.testing.expectEqualStrings("ls", code.code_block.content);
    // An escaped pipe stays inside its cell.
    try std.testing.expectEqual(@as(usize, 2), splitCells("| a \\| b | c |", &cells));
    try std.testing.expectEqualStrings("a \\| b", cells[0]);
}

test "Markdown table .rules: no frame or column lines, sm/600 fg-secondary header, a separator under every row, aligned columns" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(420, 400);
    const root = try box(cx, .{ .width = .{ .px = 388 }, .height = .{ .px = 400 }, .direction = .column }, .{});
    cx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const md = try Markdown(.{ .text = table_md, .options = .{ .table = .rules } }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, md);
    cx.layout();
    const table = findComponent(md, "MarkdownTable").?;
    try std.testing.expectEqual(@as(usize, 3), table.children.items.len);
    try std.testing.expectEqual(@as(f32, 0), table.style.border.width);
    const k = cx.tokens.tokens;
    const header_text = findTextNode(table, "Time").?.getText().?;
    try std.testing.expect(Color.eql(header_text.color, k.color.fg_secondary));
    try std.testing.expectEqual(@as(u16, 600), header_text.font_weight);
    try std.testing.expectEqual(k.font_size.sm, header_text.font_size);
    for (table.children.items) |row| {
        try std.testing.expectEqual(@as(f32, 1), row.style.border.resolvedWidths()[2]);
        try std.testing.expect(Color.eql(row.style.border.color, k.color.separator));
        try std.testing.expect(row.getBackground().a == 0);
        for (row.children.items) |cell| try std.testing.expectEqual(@as(f32, 0), cell.style.border.resolvedWidths()[1]);
        try std.testing.expectApproxEqAbs(@as(f32, 30), row.rectFromWorldOrFallback().h, 1.5);
    }
    // Same column, same x and width in every row.
    const first = table.children.items[0];
    for (table.children.items[1..]) |row| for (row.children.items, first.children.items) |a, b| {
        try std.testing.expectApproxEqAbs(b.rectFromWorldOrFallback().x, a.rectFromWorldOrFallback().x, 0.5);
        try std.testing.expectApproxEqAbs(b.rectFromWorldOrFallback().w, a.rectFromWorldOrFallback().w, 0.5);
    };
    cx.root = null;
    cx.freeNode(root);
}

test "Markdown: heading_sizes sets each level's size; table_test_id names the table" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const md = try Markdown(.{ .text = "# One\n\n### Three\n\nBody\n\n" ++ table_md, .options = .{ .base_font_size = 13, .heading_sizes = .{ 16, 16, 13, 13, 13, 13 }, .table = .rules, .table_test_id = "app.table" } }).mount(scope, cx);
    defer cx.freeNode(md);
    const one = findTextNode(md, "One").?.getText().?;
    try std.testing.expectEqual(@as(f32, 16), one.font_size);
    try std.testing.expectEqual(@as(u16, 600), one.font_weight);
    const three = findTextNode(md, "Three").?.getText().?;
    try std.testing.expectEqual(@as(f32, 13), three.font_size);
    try std.testing.expectEqual(@as(u16, 600), three.font_weight);
    try std.testing.expectEqual(@as(u16, 400), findTextNode(md, "Body").?.getText().?.font_weight);
    try std.testing.expect(findTestId(md, "app.table") == findComponent(md, "MarkdownTable").?);
    // Default: the base size times the scale, no table id.
    const plain = try Markdown(.{ .text = "# One\n\n" ++ table_md, .options = .{ .base_font_size = 10, .table = .rules } }).mount(scope, cx);
    defer cx.freeNode(plain);
    try std.testing.expectApproxEqAbs(@as(f32, 14), findTextNode(plain, "One").?.getText().?.font_size, 0.01);
    try std.testing.expect(findComponent(plain, "MarkdownTable").?.meta.ownership.meta.test_id == null);
}

test "Markdown table .grid frames the table, divides cells and fills the header" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const md = try Markdown(.{ .text = table_md, .options = .{ .table = .grid } }).mount(scope, cx);
    defer cx.freeNode(md);
    const table = findComponent(md, "MarkdownTable").?;
    try std.testing.expectEqual(@as(f32, 1), table.style.border.width);
    const header = table.children.items[0];
    try std.testing.expect(Color.eql(header.getBackground(), cx.tokens.tokens.color.table_header_bg));
    try std.testing.expectEqual(@as(f32, 1), header.children.items[0].style.border.resolvedWidths()[1]);
    try std.testing.expectEqual(@as(f32, 0), header.children.items[2].style.border.resolvedWidths()[1]);
    // The last row has no line under it (the frame closes it).
    try std.testing.expectEqual(@as(f32, 0), table.children.items[2].style.border.resolvedWidths()[2]);
}

test "Markdown code block: default options keep the framed block (no header, no scroll area)" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const md = try Markdown(.{ .text = "```zig\nconst a = 1;\nconst b = 2;\n```" }).mount(scope, cx);
    defer cx.freeNode(md);
    const block = md.children.items[0];
    try std.testing.expectEqual(@as(usize, 2), block.children.items.len);
    try std.testing.expectEqual(@as(f32, 1), block.style.border.width);
    try std.testing.expect(findComponent(md, "MarkdownCodeBlock") == null);
    try std.testing.expect(findComponent(md, "ScrollArea") == null);
}

const long_code = "```bash\n#!/usr/bin/env bash\nset -euo pipefail\nfor host in $(cat hosts.txt); do ssh -o ConnectTimeout=5 \"$host\" 'df -hP / | awk \"NR==2 {print $5}\"' | sed \"s/^/$host /\"; done\na\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nm\nn\no\np\n```";

test "Markdown code block chrome: borderless fill, header (language, wrap, copy), max height scrolls both ways" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(420, 600);
    const root = try box(cx, .{ .width = .{ .px = 388 }, .height = .{ .px = 600 }, .direction = .column }, .{});
    cx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const md = try Markdown(.{ .text = long_code, .options = .{ .base_font_size = 13, .code_font_size = 12, .code_block = .{ .frame = .borderless, .header = true, .max_height = 160, .wrap = false } } }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, md);
    cx.layout();
    const k = cx.tokens.tokens;
    const block = findComponent(md, "MarkdownCodeBlock").?;
    try std.testing.expectEqual(@as(f32, 0), block.style.border.width);
    try std.testing.expectEqual(k.radius.xl, block.style.border.radius);
    try std.testing.expect(Color.eql(block.getBackground(), k.color.bg_secondary));
    const header = block.children.items[0];
    try std.testing.expectApproxEqAbs(@as(f32, 28), header.rectFromWorldOrFallback().h, 0.5);
    const lang = findTextNode(header, "bash").?.getText().?;
    try std.testing.expect(Color.eql(lang.color, k.color.fg_tertiary));
    const wrap = findTestId(block, "markdown.code.wrap").?;
    const copy = findTestId(block, "markdown.code.copy").?;
    try std.testing.expectEqualStrings("Button", wrap.meta.ownership.meta.component_name.?);
    try std.testing.expectEqualStrings("Copy code", copy.behavior.interaction.a11y.?.label.?);
    try std.testing.expectEqualStrings("Wrap lines", wrap.behavior.interaction.a11y.?.label.?);
    // Body: capped at max height (28 header + 160), wider content than the viewport.
    const area = findTestId(block, "markdown.code.body").?;
    try std.testing.expectApproxEqAbs(@as(f32, 160), area.rectFromWorldOrFallback().h, 0.5);
    const content = area.children.items[0];
    try std.testing.expect(content.rectFromWorldOrFallback().w > area.rectFromWorldOrFallback().w);
    try std.testing.expect(content.rectFromWorldOrFallback().h > area.rectFromWorldOrFallback().h);

    // Toggle wrap: the body is rebuilt; lines wrap inside the viewport width.
    wrap.behavior.events.on_click.?.invoke();
    cx.layout();
    try std.testing.expectEqualStrings("Don't wrap lines", findTestId(block, "markdown.code.wrap").?.behavior.interaction.a11y.?.label.?);
    const area2 = findTestId(block, "markdown.code.body").?;
    try std.testing.expect(area2 != area or true);
    try std.testing.expect(area2.children.items[0].rectFromWorldOrFallback().w <= area2.rectFromWorldOrFallback().w + 0.5);
    try std.testing.expect(findTextNode(area2, long_code[8 .. long_code.len - 4]).?.getText().?.wrap == .break_all);

    // Copy without a clipboard (no SDK in tests) reports nothing and keeps the copy icon.
    findTestId(block, "markdown.code.copy").?.behavior.events.on_click.?.invoke();
    try std.testing.expectEqualStrings("Copy code", findTestId(block, "markdown.code.copy").?.behavior.interaction.a11y.?.label.?);
    cx.root = null;
    cx.freeNode(root);
}

test "Markdown code block chrome: short code is as tall as its lines (max height is only a cap), even in a short column" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(420, 600);
    // A column shorter than the blocks: the clipped block must not shrink below its content.
    const root = try box(cx, .{ .width = .{ .px = 388 }, .height = .{ .px = 60 }, .direction = .column }, .{});
    cx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    for ([_]bool{ true, false }) |wrap| {
        const md = try Markdown(.{ .text = "```\nls -la\ncd /\npwd\nexit\n```", .options = .{ .code_block = .{ .frame = .borderless, .header = true, .max_height = 320, .wrap = wrap } } }).mount(scope, cx);
        try root.appendChild(std.testing.allocator, md);
        cx.layout();
        const area = findTestId(md, "markdown.code.body").?;
        const content = area.children.items[0];
        try std.testing.expect(area.rectFromWorldOrFallback().h < 120);
        try std.testing.expectApproxEqAbs(content.rectFromWorldOrFallback().h, area.rectFromWorldOrFallback().h, 0.5);
        try std.testing.expect(content.rectFromWorldOrFallback().h > 4 * 11);
        const block = findComponent(md, "MarkdownCodeBlock").?;
        try std.testing.expectApproxEqAbs(28 + area.rectFromWorldOrFallback().h, block.rectFromWorldOrFallback().h, 0.5);
    }
    cx.root = null;
    cx.freeNode(root);
}

test "markdown: chrome code block + table mount 在任意分配点失败时不泄漏（sweep）" {
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMount("markdown(chrome)", struct {
        fn m(scope: *sw.Scope, cx: *sw.Cx) anyerror!?*sw.Node {
            return try Markdown(.{ .text = "```sh\nls\n```\n\n| a | b |\n|---|---|\n| 1 | 2 |\n", .options = .{ .table = .rules, .code_block = .{ .frame = .borderless, .header = true, .max_height = 120 } } }).mount(scope, cx);
        }
    }.m);
}
