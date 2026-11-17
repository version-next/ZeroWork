//! W.CodeBlock: one code surface with chrome — the fill (bordered or borderless), a header row
//! (optional leading icon, a label such as the fence language or a command, an optional detail
//! such as an exit code, a wrap toggle and a copy button: native ghost xs Buttons) and the code in
//! a ScrollArea capped at a max height (vertical while lines wrap, both axes while they keep
//! their length). Markdown renders fenced blocks with it when `MarkdownOptions.code_block` is not
//! the default; apps mount it directly for code they hold outside Markdown (a streamed fence, a
//! command's output well).
//!
//! `code` may be a signal: the text node follows it in place (no rebuild), so a streamed block keeps
//! its nodes. Labels and test ids are props (localised apps, app e2e). The body's scroll offsets
//! are ScrollArea models (`scroll_x` / `scroll_y` + change handlers), so an owner can keep the
//! reading position across a remount.
const std = @import("std");
const core = @import("../../core.zig");
const view = @import("../../view.zig");
const reactive = @import("../../reactive.zig");
const bind_mod = @import("../../bind.zig");
const svg_assets = @import("../../svg_assets.zig");
const styles = @import("styles.zig");
const md = @import("mod.zig");
const Scope = reactive.Scope;
const Source = reactive.Source;
const Model = reactive.Model;
const Cx = core.Cx;
const Node = core.Node;

/// Accessible names of the header buttons (the copy button shows `copied` for a moment).
pub const CodeBlockLabels = struct {
    wrap: []const u8 = "Wrap lines",
    unwrap: []const u8 = "Don't wrap lines",
    copy: []const u8 = "Copy code",
    copied: []const u8 = "Copied",
};

/// Test ids of the parts (null: none written). The defaults are Markdown's.
pub const CodeBlockTestIds = struct {
    block: ?[]const u8 = null,
    header: ?[]const u8 = null,
    label: ?[]const u8 = null,
    detail: ?[]const u8 = null,
    wrap: ?[]const u8 = "markdown.code.wrap",
    copy: ?[]const u8 = "markdown.code.copy",
    body: ?[]const u8 = "markdown.code.body",
    text: ?[]const u8 = null,
};

/// Ink of the header detail: `success` / `danger` for an exit status.
pub const CodeDetailTone = enum { neutral, success, danger };

pub const CodeBlockProps = struct {
    /// The code shown (a signal is followed in place).
    code: Source([]const u8),
    /// What the copy button writes (null: `code`), e.g. the source with its final newline.
    copy_text: Source(?[]const u8) = .{ .value = null },
    /// Header label: the language, or a command (`label_mono`).
    label: Source([]const u8) = .{ .value = "" },
    label_mono: bool = false,
    /// Leading header icon (12, `fg-tertiary`), e.g. a terminal glyph before a command.
    icon_asset: ?svg_assets.Asset = null,
    /// Header detail before the buttons (xs), e.g. "exit 0".
    detail: Source([]const u8) = .{ .value = "" },
    detail_tone: Source(CodeDetailTone) = .{ .value = .neutral },
    /// Code font, colours and line height come from these options; `code_block` sets the frame,
    /// header, max height, initial wrap and fill. The default is the borderless block with a header.
    options: md.MarkdownOptions = .{ .code_block = .{ .frame = .borderless, .header = true } },
    labels: CodeBlockLabels = .{},
    test_ids: CodeBlockTestIds = .{},
    /// The body's scroll offsets, as ScrollArea's `scroll_x` / `scroll_y` (literal = initial
    /// offset; `*Signal` two-way; read-only source + change handler = owner-kept). The models are
    /// handed to the body's ScrollArea again when the wrap toggle rebuilds it, so a bound or
    /// owner-kept offset survives the toggle (a literal starts over, as before).
    scroll_x: Model(f32) = .{ .local = 0 },
    scroll_y: Model(f32) = .{ .local = 0 },
    /// Settled body offsets changed (ScrollArea `on_scroll_x_change` / `on_scroll_y_change`).
    on_scroll_x_change: ?core.Handler(f32) = null,
    on_scroll_y_change: ?core.Handler(f32) = null,
};

pub fn CodeBlock(props: anytype) CodeBlockBuilder {
    return .{ .props = reactive.props.coerce(CodeBlockProps, props) };
}

pub const CodeBlockBuilder = struct {
    props: CodeBlockProps,

    pub fn mount(self: CodeBlockBuilder, scope: *Scope, cx: *Cx) !*Node {
        const my_scope = try scope.childScope();
        errdefer my_scope.dispose();
        const block = try build(my_scope, cx, self.props);
        errdefer cx.freeNode(block);
        try core.bindScopeToNode(my_scope, block);
        return block;
    }
};

/// Per-block state: the wrap toggle, the copy feedback and the current code text node.
const State = struct {
    cx: *Cx,
    code: Source([]const u8),
    copy_text: Source(?[]const u8),
    wrapped: *reactive.Signal(bool),
    copied: *reactive.Signal(bool),
    on_copy: ?core.Handler([]const u8),
    labels: CodeBlockLabels,
    timer: ?u64 = null,

    const copied_ns: u64 = 1500 * std.time.ns_per_ms;

    fn toggleWrap(self: *State) void {
        self.wrapped.set(!self.wrapped.peek());
    }

    fn copy(self: *State) void {
        const value = self.copy_text.peek() orelse self.code.peek();
        if (!core.platform_services.clipboardSetText(self.cx.system_sdk, value)) return;
        if (self.timer) |id| self.cx.clearTimer(id);
        self.timer = self.cx.setTimer(copied_ns, copiedExpired, self) catch null;
        self.copied.set(true);
        if (self.on_copy) |h| h.call(value);
    }

    fn copiedExpired(raw: ?*anyopaque) void {
        const self: *State = @ptrCast(@alignCast(raw.?));
        self.timer = null;
        self.copied.set(false);
    }

    fn release(self: *State) void {
        if (self.timer) |id| self.cx.clearTimer(id);
        self.timer = null;
    }
};

const Body = struct {
    state: *State,
    opts: md.MarkdownOptions,
    header: bool,
    text_id: ?[]const u8,
    body_id: ?[]const u8,
    scroll_x: Model(f32) = .{ .local = 0 },
    scroll_y: Model(f32) = .{ .local = 0 },
    on_scroll_x_change: ?core.Handler(f32) = null,
    on_scroll_y_change: ?core.Handler(f32) = null,
};

// Theme-following styles: each takes the caller's options and the current tokens, so a theme
// change repaints the block (the options' null colours resolve against the new theme).
fn chromeStyle(opts: md.MarkdownOptions, t: *const core.ThemeTokens) core.BoxStyle {
    return styles.codeBlockChromeStyle(styles.themeOptions(opts, t), t);
}
fn headerStyle(_: bool, t: *const core.ThemeTokens) core.BoxStyle {
    return styles.codeHeaderStyle(t);
}
fn labelStyle(mono: bool, t: *const core.ThemeTokens) core.TextStyle {
    return styles.codeLanguageText(t, mono);
}
const TextKey = struct { opts: md.MarkdownOptions, wrapped: bool };
fn codeTextStyle(key: TextKey, t: *const core.ThemeTokens) core.TextStyle {
    return styles.codeText(styles.themeOptions(key.opts, t), key.wrapped);
}

fn detailInk(tone: CodeDetailTone, t: *const core.ThemeTokens) core.Color {
    return switch (tone) {
        .neutral => t.tokens.color.fg_tertiary,
        .success => t.tokens.color.success,
        .danger => t.tokens.color.danger,
    };
}

fn build(scope: *Scope, cx: *Cx, p: CodeBlockProps) !*Node {
    const opts = styles.themeOptions(p.options, cx.tokens);
    const cb = opts.code_block;
    const state = try scope.createState(State, .{
        .cx = cx,
        .code = p.code,
        .copy_text = p.copy_text,
        .wrapped = try scope.createSignal(bool, cb.wrap),
        .copied = try scope.createSignal(bool, false),
        .on_copy = cb.on_copy,
        .labels = p.labels,
    });
    try scope.onCleanup(State, state, State.release);
    const Button = @import("../button/mod.zig").Button;
    const icons = @import("zenit_icons");
    const Labels = struct { on: *reactive.Signal(bool), labels: CodeBlockLabels };
    const wrap_icon = try scope.derive(?svg_assets.Asset, .{ .on = state.wrapped }, struct {
        fn f(c: anytype) ?svg_assets.Asset {
            return if (c.on.get()) icons.wrap_text else icons.text_wrap;
        }
    }.f);
    const wrap_label = try scope.derive([]const u8, Labels{ .on = state.wrapped, .labels = p.labels }, struct {
        fn f(c: anytype) []const u8 {
            return if (c.on.get()) c.labels.unwrap else c.labels.wrap;
        }
    }.f);
    const copy_icon = try scope.derive(?svg_assets.Asset, .{ .done = state.copied }, struct {
        fn f(c: anytype) ?svg_assets.Asset {
            return if (c.done.get()) icons.check else icons.copy;
        }
    }.f);
    const copy_label = try scope.derive([]const u8, Labels{ .on = state.copied, .labels = p.labels }, struct {
        fn f(c: anytype) []const u8 {
            return if (c.on.get()) c.labels.copied else c.labels.copy;
        }
    }.f);
    const detail_shown = try scope.derive(bool, .{ .d = p.detail }, struct {
        fn f(c: anytype) bool {
            return c.d.get().len != 0;
        }
    }.f);
    // Header icons follow the theme's fg-tertiary.
    const ink = try scope.derive(?core.Color, .{ .theme = try cx.themeSignal() }, struct {
        fn f(c: anytype) ?core.Color {
            return c.theme.get().tokens.color.fg_tertiary;
        }
    }.f);
    var body: *Node = undefined;
    const block = try view.render(scope, cx, view.col(.{ .test_id = p.test_ids.block, .style = view.styleBy(p.options, chromeStyle) }, .{
        if (cb.header) view.row(.{ .test_id = p.test_ids.header, .style = view.styleBy(true, headerStyle) }, .{
            if (p.icon_asset) |asset| view.icon(.{ .style = styles.code_header_leading_icon, .tint = styles.codeHeaderIconTint }, asset) else null,
            view.text(.{ .test_id = p.test_ids.label, .style = view.styleBy(p.label_mono, labelStyle), .box = styles.code_label_box }, p.label),
            view.box(.{ .style = .{ .width = .{ .grow = .{} }, .height = .{ .px = 1 } } }, {}),
            view.show(detail_shown, .{view.text(.{ .test_id = p.test_ids.detail, .style = view.styleBy(p.detail_tone, struct {
                fn f(tone: CodeDetailTone, k: *const core.ThemeTokens) core.TextStyle {
                    var s = styles.codeLanguageText(k, false);
                    s.color = detailInk(tone, k);
                    return s;
                }
            }.f) }, p.detail)}),
            view.attrs(.{ .test_id = p.test_ids.wrap }, Button(.{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = wrap_icon, .icon_size = styles.code_header_icon, .icon_tint = ink, .a11y_label = wrap_label, .on_click = cx.on(State, state, State.toggleWrap) })),
            view.attrs(.{ .test_id = p.test_ids.copy }, Button(.{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = copy_icon, .icon_size = styles.code_header_icon, .icon_tint = ink, .a11y_label = copy_label, .on_click = cx.on(State, state, State.copy) })),
        }) else null,
        view.capture(&body, view.col(.{ .style = .{ .width = .{ .grow = .{} } } }, {})),
    }));
    errdefer cx.freeNode(block);
    block.meta.ownership.meta.component_name = "MarkdownCodeBlock";
    try bind_mod.rebuildOn(cx, scope, state.wrapped, body, Body{ .state = state, .opts = p.options, .header = cb.header, .text_id = p.test_ids.text, .body_id = p.test_ids.body, .scroll_x = p.scroll_x, .scroll_y = p.scroll_y, .on_scroll_x_change = p.on_scroll_x_change, .on_scroll_y_change = p.on_scroll_y_change }, struct {
        fn key(on: bool) u64 {
            return @intFromBool(on);
        }
    }.key, struct {
        fn build(c: Body, s: *Scope, host: *Node, wrapped: bool) !void {
            try buildBody(c, s, host, wrapped);
        }
    }.build);
    return block;
}

/// The code inside its scroll area: wrapping lines scroll vertically only; long lines keep their
/// length and the content scrolls both ways.
fn buildBody(c: Body, scope: *Scope, host: *Node, wrapped: bool) !void {
    const cx = c.state.cx;
    const ScrollArea = @import("../scroll_area/mod.zig").ScrollArea;
    const area = try ScrollArea(.{
        .direction = @as(@import("../scroll_area/mod.zig").ScrollDirection, if (wrapped) .vertical else .both),
        .scroll_x = c.scroll_x,
        .scroll_y = c.scroll_y,
        .on_scroll_x_change = c.on_scroll_x_change,
        .on_scroll_y_change = c.on_scroll_y_change,
        .scrollbars = c.opts.code_block.scrollbars,
        .overscroll_y = c.opts.code_block.overscroll_y,
        .overscroll_x = c.opts.code_block.overscroll_x,
    }).mount(scope, cx);
    errdefer cx.freeNode(area.container);
    area.container.style.height = .{ .fit = .{ .max = c.opts.code_block.max_height orelse std.math.inf(f32) } };
    area.container.style.width = .{ .grow = .{ .min = 0 } };
    if (!wrapped) {
        // As a horizontal area: the content keeps its longest line's width and overflows sideways.
        area.container.style.direction = .row;
        area.container.style.align_items = .start;
        area.content.style.width = .{ .fit = .{} };
        area.content.style.flex_shrink = 0;
    }
    area.container.meta.ownership.meta.test_id = c.body_id;
    try view.mount(scope, cx, area.content, view.box(.{ .style = styles.codeBodyStyle(c.header) }, .{
        view.text(.{ .test_id = c.text_id, .style = view.styleBy(TextKey{ .opts = c.opts, .wrapped = wrapped }, codeTextStyle) }, c.state.code),
    }));
    try host.appendChild(cx.allocator, area.container);
}

// ============================================================================
// Tests
// ============================================================================

const testing = std.testing;

fn findTestId(n: *Node, id: []const u8) ?*Node {
    if (n.meta.ownership.meta.test_id) |t| if (std.mem.eql(u8, t, id)) return n;
    for (n.children.items) |ch| if (findTestId(ch, id)) |r| return r;
    return null;
}

test "CodeBlock: a code signal updates the text in place; labels, test ids, icon, detail and tone" {
    var cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setViewport(420, 600);
    const root = try core.box(cx, .{ .width = .{ .px = 388 }, .height = .{ .px = 600 }, .direction = .column }, .{});
    cx.root = root;
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const code = try scope.createText("ls", .{});
    const detail = try scope.createText("exit 0", .{});
    const tone = try scope.createSignal(CodeDetailTone, .success);
    const node = try CodeBlock(.{
        .code = code,
        .copy_text = @as(?[]const u8, "ls\n"),
        .label = "ls -la",
        .label_mono = true,
        .icon_asset = @import("zenit_icons").terminal,
        .detail = detail,
        .detail_tone = tone,
        .labels = .{ .wrap = "自动换行", .unwrap = "取消自动换行", .copy = "复制代码", .copied = "已复制" },
        .test_ids = .{ .block = "app.code", .header = "app.code.header", .label = "app.code.label", .detail = "app.code.exit", .wrap = "app.code.wrap", .copy = "app.code.copy", .body = "app.code.scroll", .text = "app.code.text" },
    }).mount(scope, cx);
    try root.appendChild(testing.allocator, node);
    cx.layout();
    const k = cx.tokens.tokens;
    try testing.expect(findTestId(root, "app.code") == node);
    try testing.expectApproxEqAbs(@as(f32, 28), findTestId(node, "app.code.header").?.rectFromWorldOrFallback().h, 0.5);
    const label = findTestId(node, "app.code.label").?.getText().?;
    try testing.expectEqualStrings("ls -la", label.content);
    try testing.expect(label.use_monospace_font);
    const exit = findTestId(node, "app.code.exit").?.getText().?;
    try testing.expectEqualStrings("exit 0", exit.content);
    try testing.expect(core.Color.eql(exit.color, k.color.success));
    try testing.expectEqualStrings("复制代码", findTestId(node, "app.code.copy").?.behavior.interaction.a11y.?.label.?);
    // Default wrap = lines wrap: the toggle offers "don't wrap".
    try testing.expectEqualStrings("取消自动换行", findTestId(node, "app.code.wrap").?.behavior.interaction.a11y.?.label.?);
    // Streaming: the same text node takes the longer code.
    const text = findTestId(node, "app.code.text").?;
    code.set("ls\npwd");
    cx.layout();
    try testing.expect(findTestId(node, "app.code.text").? == text);
    try testing.expectEqualStrings("ls\npwd", text.getText().?.content);
    // Tone follows its signal; an empty detail hides it.
    tone.set(.danger);
    cx.layout();
    try testing.expect(core.Color.eql(findTestId(node, "app.code.exit").?.getText().?.color, k.color.danger));
    detail.set("");
    cx.layout();
    const hidden = findTestId(node, "app.code.exit");
    try testing.expect(hidden == null or hidden.?.style.display == .none);
    // Wrap toggle rebuilds the body; the new text node still follows the signal.
    findTestId(node, "app.code.wrap").?.behavior.events.on_click.?.invoke();
    cx.layout();
    try testing.expectEqualStrings("自动换行", findTestId(node, "app.code.wrap").?.behavior.interaction.a11y.?.label.?);
    code.set("ls\npwd\nid");
    cx.layout();
    try testing.expectEqualStrings("ls\npwd\nid", findTestId(node, "app.code.text").?.getText().?.content);
    try testing.expect(findTestId(node, "app.code.scroll") != null);
    cx.root = null;
    cx.freeNode(root);
}

test "CodeBlock: bound scroll offsets reach the body's ScrollArea and survive the wrap toggle" {
    var cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setViewport(200, 200);
    const root = try core.box(cx, .{ .width = .{ .px = 160 }, .height = .{ .px = 200 }, .direction = .column }, .{});
    cx.root = root;
    defer {
        cx.root = null;
        cx.freeNode(root);
    }
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const x = try scope.createSignal(f32, 60);
    const Seen = struct {
        last: f32 = -1,
        fn hit(self: *@This(), v: f32) void {
            self.last = v;
        }
    };
    var seen = Seen{};
    const long_line = "0123456789 0123456789 0123456789 0123456789 0123456789 0123456789 0123456789";
    const node = try CodeBlock(.{
        .code = long_line,
        .options = .{ .code_block = .{ .frame = .borderless, .header = true, .wrap = false } },
        .scroll_x = x,
        .on_scroll_x_change = cx.on(Seen, &seen, Seen.hit),
        .test_ids = .{ .body = "b" },
    }).mount(scope, cx);
    try root.appendChild(testing.allocator, node);
    const ScrollEventCtx = @import("../scroll_area/mod.zig").ScrollEventCtx;
    const offset = struct {
        fn of(n: *Node) f32 {
            const area = findTestId(n, "b").?;
            const ctx: *const ScrollEventCtx = @ptrCast(@alignCast(area.behavior.events.event_context.?));
            return ctx.state.scroll_x;
        }
    };
    for (0..3) |_| {
        cx.layout();
        _ = cx.render();
    }
    // The long line overflows sideways; the bound offset is applied (unclamped: 60 < max).
    try testing.expectApproxEqAbs(@as(f32, 60), offset.of(node), 0.01);
    // Toggle wrap twice: each rebuild mounts a new ScrollArea from the same model.
    for (0..2) |_| {
        findTestId(node, "markdown.code.wrap").?.behavior.events.on_click.?.invoke();
        for (0..3) |_| {
            cx.layout();
            _ = cx.render();
        }
    }
    try testing.expectApproxEqAbs(@as(f32, 60), offset.of(node), 0.01);
    try testing.expectApproxEqAbs(@as(f32, 60), x.peek(), 0.01);
    // An owner write scrolls the body there.
    x.set(20);
    for (0..2) |_| {
        cx.layout();
        _ = cx.render();
    }
    try testing.expectApproxEqAbs(@as(f32, 20), offset.of(node), 0.01);
}

test "CodeBlock: code_block.scrollbars / overscroll reach the body's ScrollArea" {
    var cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    cx.setViewport(200, 200);
    const root = try core.box(cx, .{ .width = .{ .px = 160 }, .height = .{ .px = 200 }, .direction = .column }, .{});
    cx.root = root;
    defer {
        cx.root = null;
        cx.freeNode(root);
    }
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const node = try CodeBlock(.{
        .code = "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl",
        .options = .{ .code_block = .{ .frame = .borderless, .header = false, .max_height = 60, .scrollbars = .always, .overscroll_y = .contain } },
        .test_ids = .{ .body = "cb.body" },
    }).mount(scope, cx);
    try root.appendChild(testing.allocator, node);
    cx.layout();
    _ = cx.render();
    const body = findTestId(node, "cb.body").?;
    const sa = @import("../scroll_area/mod.zig");
    const ev: *const sa.ScrollEventCtx = @ptrCast(@alignCast(body.behavior.events.event_context.?));
    try testing.expectEqual(sa.OverscrollBehavior.contain, ev.overscroll_y);
    try testing.expect(ev.state.scrollbar_fade.persistent);
    try testing.expect(ev.state.maxScrollY() > 0);
    try testing.expect(ev.state.scrollbar_fade.opacity > 0);
}

test "CodeBlock: the fill, label and code follow a theme change" {
    var cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const root = try core.box(cx, .{ .width = .{ .px = 300 }, .height = .{ .px = 200 }, .direction = .column }, .{});
    cx.root = root;
    defer {
        cx.root = null;
        cx.freeNode(root);
    }
    const node = try CodeBlock(.{ .code = "ls", .label = "sh", .test_ids = .{ .label = "l", .text = "t" } }).mount(scope, cx);
    try root.appendChild(testing.allocator, node);
    const theme = core.theme;
    for ([_]*const core.ThemeTokens{ &theme.dark, &theme.light }) |tokens| {
        cx.setTheme(tokens);
        cx.layout();
        _ = cx.render();
        const k = cx.tokens.tokens.color;
        try testing.expect(core.Color.eql(node.getBackground(), k.bg_secondary));
        try testing.expect(core.Color.eql(findTestId(node, "l").?.getText().?.color, k.fg_tertiary));
        try testing.expect(core.Color.eql(findTestId(node, "t").?.getText().?.color, k.fg_primary));
    }
}

test "CodeBlock: without a header there are no buttons; mount sweep does not leak" {
    var cx = try Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const node = try CodeBlock(.{ .code = "a", .options = .{ .code_block = .{ .frame = .borderless } } }).mount(scope, cx);
    defer cx.freeNode(node);
    try testing.expect(findTestId(node, "markdown.code.copy") == null);
    try testing.expect(findTestId(node, "markdown.code.body") != null);
    const sw = @import("../oom_sweep.zig");
    try sw.sweepMount("code block", struct {
        fn m(s: *sw.Scope, c: *sw.Cx) anyerror!?*sw.Node {
            return try CodeBlock(.{ .code = "ls\npwd", .label = "sh", .detail = "exit 1", .detail_tone = .danger, .icon_asset = @import("zenit_icons").terminal }).mount(s, c);
        }
    }.m);
}
