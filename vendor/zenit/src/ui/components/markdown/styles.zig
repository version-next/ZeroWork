//! Markdown style layer, all parameterized by MarkdownOptions (markdown intentionally independent
//! of layout,
//! colors / sizes injected from opts). mod.zig's emitter only consumes these functions.
const core = @import("../../core.zig");
const Padding = core.Padding;
const TextSpan = core.TextSpan;
const mod = @import("mod.zig");
const MarkdownOptions = mod.MarkdownOptions;

pub fn resolvedColor(opts: MarkdownOptions, comptime field: []const u8) core.Color {
    return @field(opts, field) orelse @field(themeOptions(opts, &core.theme.light), field).?;
}

pub fn mdRootStyle(opts: MarkdownOptions) core.BoxStyle {
    return .{
        .direction = .column,
        .gap = opts.paragraph_gap,
        .width = .{ .grow = .{} },
    };
}

pub fn mdHeadingSizeMul(level: u8) f32 {
    return switch (level) {
        1 => 1.4,
        2 => 1.25,
        3 => 1.15,
        4 => 1.08,
        5 => 1.04,
        else => 1.0,
    };
}

pub fn mdCodeBlockStyle(opts: MarkdownOptions) core.BoxStyle {
    return .{
        .direction = .column,
        .padding = Padding.symmetric(8, 10),
        .background = resolvedColor(opts, "code_bg"),
        .border = .{ .overlay = true, .width = 1, .color = resolvedColor(opts, "rule_color"), .radius = core.theme.light.tokens.radius.control },
        .width = .{ .grow = .{} },
    };
}

pub fn mdCodeLineText(opts: MarkdownOptions) core.TextStyle {
    return .{
        .font_size = opts.code_font_size,
        .color = resolvedColor(opts, "code_color"),
        .font_weight = 450,
        .line_height = opts.code_line_height,
        .use_monospace_font = true,
    };
}

pub fn mdRuleStyle(opts: MarkdownOptions) core.BoxStyle {
    return .{
        .height = .{ .px = 1 },
        .background = resolvedColor(opts, "rule_color"),
        .width = .{ .grow = .{} },
    };
}

pub fn mdBlockquoteStyle() core.BoxStyle {
    return .{
        .direction = .row,
        .padding = .{ .left = 8, .right = 0, .top = 2, .bottom = 2 },
        .width = .{ .grow = .{} },
        .min_width = 0,
    };
}

pub fn mdBlockquoteBarStyle(opts: MarkdownOptions) core.BoxStyle {
    return .{
        .width = .{ .px = 3 },
        .background = resolvedColor(opts, "rule_color"),
        .height = .{ .grow = .{} },
    };
}

pub fn mdBlockquoteBodyStyle() core.BoxStyle {
    return .{
        .padding = .{ .left = 8, .right = 0, .top = 0, .bottom = 0 },
        .width = .{ .grow = .{} },
        // A row item: without this its min-content (an unbreakable URL) would widen the document.
        .min_width = 0,
    };
}

pub fn mdListRowStyle() core.BoxStyle {
    return .{
        .direction = .row,
        .gap = core.theme.light.tokens.space.space150,
        .width = .{ .grow = .{} },
        .min_width = 0,
    };
}

pub fn mdListMarkerText(opts: MarkdownOptions) core.TextStyle {
    return .{
        .font_size = opts.base_font_size,
        .color = resolvedColor(opts, "text_color"),
        .line_height = opts.line_height,
    };
}

// ── inline span styles (code / [alt] image chip / [text](url) link) ──

pub fn mdCodeSpanStyle(opts: MarkdownOptions) TextSpan {
    return .{
        .start = 0,
        .end = 0,
        .use_monospace_font = true,
        .bg_color = resolvedColor(opts, "code_bg"),
        .color = resolvedColor(opts, "code_color"),
        .inline_box_padding_left = 2,
        .inline_box_padding_right = 2,
        .inline_box_corner_radius = 3,
    };
}

pub fn mdImageChipSpanStyle(opts: MarkdownOptions) TextSpan {
    return .{
        .start = 0,
        .end = 0,
        .color = resolvedColor(opts, "code_color"),
        .bg_color = resolvedColor(opts, "code_bg"),
        .inline_box_padding_left = 3,
        .inline_box_padding_right = 3,
        .inline_box_corner_radius = 3,
        .font_weight = 500,
    };
}

pub fn mdLinkSpanStyle(opts: MarkdownOptions) TextSpan {
    return .{
        .start = 0,
        .end = 0,
        .color = resolvedColor(opts, "link_color"),
        .underline = true,
    };
}

pub fn mdBoldSpanStyle() TextSpan {
    return .{ .start = 0, .end = 0, .font_weight = 700 };
}

pub fn mdItalicSpanStyle() TextSpan {
    return .{ .start = 0, .end = 0, .use_italic_font = true };
}

/// Keep caller overrides, while mapping the default Markdown palette to the active theme.
pub fn themeOptions(options: MarkdownOptions, t: *const core.ThemeTokens) MarkdownOptions {
    var out = options;
    inline for (.{ "text_color", "code_color", "code_bg", "link_color", "rule_color" }, .{ "fg_primary", "fg_primary", "surface_inset", "accent", "border" }) |field, token| {
        if (@field(out, field) == null) @field(out, field) = @field(t.tokens.color, token);
    }
    return out;
}

// ── code block with chrome (MarkdownOptions.code_block not default) ──

/// Header icons: 12 inside the ghost xs (20) button.
pub const code_header_icon: f32 = 12;

/// Frame: `.bordered` = 1px rule border on `code_bg`, radius control; `.borderless` = the fill
/// alone (`bg-secondary` unless set), radius xl. Children clip to the frame.
pub fn codeBlockChromeStyle(opts: MarkdownOptions, t: *const core.ThemeTokens) core.BoxStyle {
    const cb = opts.code_block;
    const radius = switch (cb.frame) {
        .bordered => t.tokens.radius.control,
        .borderless => t.tokens.radius.xl,
    };
    const fill = cb.background orelse switch (cb.frame) {
        .bordered => resolvedColor(opts, "code_bg"),
        .borderless => t.tokens.color.bg_secondary,
    };
    return .{
        .direction = .column,
        .width = .{ .grow = .{ .min = 0 } },
        .background = fill,
        .border = switch (cb.frame) {
            .bordered => .{ .overlay = true, .width = 1, .color = resolvedColor(opts, "rule_color"), .radius = radius },
            .borderless => .{ .radius = radius },
        },
        .overflow_hidden = true,
        .clip_shape = .{ .rounded_rect = radius },
        // Clipping drops the automatic minimum height: keep the block whole in a short column.
        .flex_shrink = 0,
    };
}

/// Header row: 28 high; the language at the left (10 in), buttons at the right (4 in).
pub fn codeHeaderStyle(t: *const core.ThemeTokens) core.BoxStyle {
    return .{
        .direction = .row,
        .width = .{ .grow = .{} },
        .height = .{ .px = t.tokens.size.row },
        .align_items = .center,
        .gap = t.tokens.space.space150,
        .padding = .{ .left = 10, .right = t.tokens.space.space100, .top = 0, .bottom = 0 },
    };
}

/// Header label: the fence language (xs `fg-tertiary`) or a command (`mono`); it gives way first
/// (ellipsis) when the header is narrow.
pub fn codeLanguageText(t: *const core.ThemeTokens, mono: bool) core.TextStyle {
    return .{ .font_size = t.tokens.font_size.xs, .color = t.tokens.color.fg_tertiary, .line_height = 1.5, .use_monospace_font = mono, .wrap = .none, .text_overflow = .ellipsis, .selectable = false };
}
pub const code_label_box: core.BoxStyle = .{ .min_width = 0, .flex_shrink = 1 };

/// Optional leading header icon: 12, `fg-tertiary`.
pub const code_header_leading_icon: core.BoxStyle = .{ .width = .{ .px = code_header_icon }, .height = .{ .px = code_header_icon }, .flex_shrink = 0 };
pub fn codeHeaderIconTint(t: *const core.ThemeTokens) core.Color {
    return t.tokens.color.fg_tertiary;
}

/// Code padding: under a header the code starts right below it (0 12 10 12); without one, the
/// framed block's 8 10.
pub fn codeBodyStyle(header: bool) core.BoxStyle {
    return .{
        .direction = .column,
        .padding = if (header) .{ .top = 0, .right = 12, .bottom = 10, .left = 12 } else Padding.symmetric(8, 10),
    };
}

/// The whole code as one text: newlines kept; long lines wrap or keep their length.
pub fn codeText(opts: MarkdownOptions, wrapped: bool) core.TextStyle {
    return .{
        .font_size = opts.code_font_size,
        .color = resolvedColor(opts, "code_color"),
        .font_weight = 450,
        .line_height = opts.code_line_height,
        .use_monospace_font = true,
        .wrap = if (wrapped) .break_all else .newline_only,
    };
}

// ── tables (MarkdownOptions.table) ──

pub fn tableStyle(opts: MarkdownOptions, t: *const core.ThemeTokens) core.BoxStyle {
    return switch (opts.table) {
        .grid => .{
            .direction = .column,
            .width = .{ .grow = .{ .min = 0 } },
            .border = .{ .overlay = true, .width = 1, .color = resolvedColor(opts, "rule_color"), .radius = t.tokens.radius.control },
            .overflow_hidden = true,
            .clip_shape = .{ .rounded_rect = t.tokens.radius.control },
            .flex_shrink = 0,
        },
        else => .{ .direction = .column, .width = .{ .grow = .{ .min = 0 } } },
    };
}

/// `.rules`: every row 6 0 with a 1px separator under it, cells 8 apart. `.grid`: rows divided by
/// the rule colour, the header row on `table-header-bg`.
pub fn tableRowStyle(opts: MarkdownOptions, t: *const core.ThemeTokens, header: bool, last: bool) core.BoxStyle {
    return switch (opts.table) {
        .rules => .{
            .direction = .row,
            .width = .{ .grow = .{} },
            .gap = t.tokens.space.space200,
            .padding = Padding.symmetric(t.tokens.space.space150, 0),
            .border = .{ .width = 1, .color = t.tokens.color.separator, .side_widths = .{ 0, 0, 1, 0 } },
        },
        else => .{
            .direction = .row,
            .width = .{ .grow = .{} },
            .background = if (header) t.tokens.color.table_header_bg else null,
            .border = .{ .width = 1, .color = resolvedColor(opts, "rule_color"), .side_widths = .{ 0, 0, if (last) 0 else 1, 0 } },
        },
    };
}

/// One column's cell: its share of the row is the column's weight (basis 0), so all rows line up.
pub fn tableCellStyle(opts: MarkdownOptions, t: *const core.ThemeTokens, weight: f32, last: bool) core.BoxStyle {
    var style: core.BoxStyle = .{
        .direction = .column,
        .width = .{ .grow = .{ .min = 0 } },
        .flex = weight,
        .flex_basis = 0,
    };
    if (opts.table == .grid) {
        style.padding = Padding.symmetric(t.tokens.space.space150, t.tokens.space.space200);
        style.border = .{ .width = 1, .color = resolvedColor(opts, "rule_color"), .side_widths = .{ 0, if (last) 0 else 1, 0, 0 } };
    }
    return style;
}

pub const TableText = struct { font_size: f32, font_weight: u16, color: core.Color };

/// `.rules`: header sm/600 `fg-secondary`, cells sm `text_color`. `.grid`: body size, header 600.
pub fn tableText(opts: MarkdownOptions, t: *const core.ThemeTokens, header: bool) TableText {
    return switch (opts.table) {
        .rules => .{
            .font_size = t.tokens.font_size.sm,
            .font_weight = if (header) 600 else 400,
            .color = if (header) t.tokens.color.fg_secondary else resolvedColor(opts, "text_color"),
        },
        else => .{
            .font_size = opts.base_font_size,
            .font_weight = if (header) 600 else 400,
            .color = if (header) opts.heading_color orelse resolvedColor(opts, "text_color") else resolvedColor(opts, "text_color"),
        },
    };
}
