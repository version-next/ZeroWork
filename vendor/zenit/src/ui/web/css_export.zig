//! Build-time `ui.css` / `ui.cva` (and therefore YSS, which compiles to them)
//! → CSS class exporter. Zero runtime: this runs in a host generator at build
//! time; the browser only loads the emitted stylesheet.
//!
//! Single source of truth: values are resolved by the **same** resolver the
//! native renderer uses (`css.resolveInto`), so the stylesheet cannot drift from
//! desktop semantics. Token references additionally keep their identity as CSS
//! custom properties (`var(--z-color-accent, <resolved>)`), so a theme switch is
//! a pure CSS variable swap (see `emitTokens`).
//!
//! Naming:
//!   ui.css  `S.card`              → `.S-card`
//!   ui.cva  `S.Badge` base        → `.S-Badge`
//!           variant even=true     → `.S-Badge--even-true`
//!           compound              → `.S-Badge--a-x.S-Badge--b-y`
//!   conditions `_hover`/`_active`/`_selected`/… → `[data-z-hover]` etc. (the host
//!   mirrors zenit's interaction state; DOM pseudo-classes are not authoritative
//!   because input is routed through zenit hit testing).
//!   Layout properties are emitted under `.z-css-layout` (applied only to subtrees
//!   the host hands to CSS layout, WEB_HOST_DESIGN §3); paint applies everywhere.
const std = @import("std");
const css = @import("../css.zig");
const core = @import("../core.zig");
const theme = @import("../theme.zig");

const BoxStyle = core.BoxStyle;
const Color = core.Color;
const ThemeTokens = theme.ThemeTokens;
const Writer = std.Io.Writer;
const EnumLiteral = @TypeOf(.enum_literal);

pub const Options = struct {
    /// Class prefix (usually the styles module name).
    prefix: []const u8,
};

fn colorCss(w: *Writer, c: Color) !void {
    if (c.a == 255) return w.print("#{x:0>2}{x:0>2}{x:0>2}", .{ c.r, c.g, c.b });
    try w.print("rgba({d},{d},{d},{d:.3})", .{ c.r, c.g, c.b, @as(f32, @floatFromInt(c.a)) / 255.0 });
}

fn kebab(comptime s: []const u8) []const u8 {
    comptime {
        var out: [s.len]u8 = undefined;
        for (s, 0..) |ch, i| out[i] = if (ch == '_') '-' else ch;
        const final = out;
        return &final;
    }
}

/// `var(--z-<cat>-<name>, ` prefix when the spec value is a token reference.
fn tokenOf(comptime V: type, comptime v: anytype, comptime cat: css.Category) ?[]const u8 {
    if (V == EnumLiteral and cat != .none) return "--z-" ++ kebab(@tagName(cat)) ++ "-" ++ kebab(@tagName(v));
    if (comptime css.refCategory(V)) |c| return "--z-" ++ kebab(@tagName(c)) ++ "-" ++ kebab(@tagName(v));
    return null;
}

const Sink = struct {
    paint: *Writer,
    layout: *Writer,
};

fn decl(w: *Writer, prop: []const u8, token: ?[]const u8, comptime fmt: []const u8, args: anytype) !void {
    try w.print("{s}:", .{prop});
    if (token) |t| try w.print("var({s},", .{t});
    try w.print(fmt, args);
    if (token != null) try w.writeByte(')');
    try w.writeByte(';');
}

fn colorDecl(w: *Writer, prop: []const u8, token: ?[]const u8, c: Color) !void {
    try w.print("{s}:", .{prop});
    if (token) |t| try w.print("var({s},", .{t});
    try colorCss(w, c);
    if (token != null) try w.writeByte(')');
    try w.writeByte(';');
}

fn sizing(w: *Writer, prop: []const u8, s: core.Sizing) !void {
    switch (s) {
        .px => |v| try w.print("{s}:{d}px;", .{ prop, v }),
        .percent => |v| try w.print("{s}:{d}%;", .{ prop, v }),
        .grow => |g| {
            try w.print("flex-grow:1;flex-basis:0;{s}:auto;", .{prop});
            if (g.min > 0) try w.print("min-{s}:{d}px;", .{ prop, g.min });
            if (std.math.isFinite(g.max)) try w.print("max-{s}:{d}px;", .{ prop, g.max });
        },
        .fit => |g| {
            try w.print("{s}:fit-content;", .{prop});
            if (g.min > 0) try w.print("min-{s}:{d}px;", .{ prop, g.min });
            if (std.math.isFinite(g.max)) try w.print("max-{s}:{d}px;", .{ prop, g.max });
        },
    }
}

fn emitField(sink: Sink, comptime name: []const u8, value: anytype, token: ?[]const u8) !void {
    const p = sink.paint;
    const l = sink.layout;
    const eq = comptime std.mem.eql;
    if (comptime eq(u8, name, "background")) return colorDecl(p, "background-color", token, value);
    if (comptime eq(u8, name, "text_color")) return colorDecl(p, "color", token, value);
    if (comptime eq(u8, name, "icon_color")) return colorDecl(p, "--z-icon-color", token, value);
    if (comptime eq(u8, name, "border_color")) return colorDecl(p, "border-color", token, value);
    if (comptime eq(u8, name, "opacity")) return decl(p, "opacity", token, "{d}", .{value});
    if (comptime eq(u8, name, "font_size")) return decl(p, "font-size", token, "{d}px", .{value});
    if (comptime eq(u8, name, "font_weight")) return decl(p, "font-weight", token, "{d}", .{value});
    if (comptime eq(u8, name, "corner_radius")) return decl(p, "border-radius", token, "{d}px", .{value});
    if (comptime eq(u8, name, "border_width")) return decl(p, "border-width", token, "{d}px", .{value});
    if (comptime std.mem.startsWith(u8, name, "border_") and std.mem.endsWith(u8, name, "_width"))
        return decl(p, "border-" ++ name["border_".len .. name.len - "_width".len] ++ "-width", token, "{d}px", .{value});
    if (comptime std.mem.startsWith(u8, name, "border_") and std.mem.endsWith(u8, name, "_color"))
        return colorDecl(p, "border-" ++ name["border_".len .. name.len - "_color".len] ++ "-color", token, value);
    if (comptime eq(u8, name, "border")) {
        const b: core.Border = value;
        const bw = b.resolvedWidths();
        try p.print("border-style:solid;border-width:{d}px {d}px {d}px {d}px;", .{ bw[0], bw[1], bw[2], bw[3] });
        try colorDecl(p, "border-color", null, b.color);
        if (b.radius > 0) try p.print("border-radius:{d}px;", .{b.radius});
        return;
    }
    if (comptime eq(u8, name, "corner_radii")) {
        const r = @as(core.CornerRadius, value).resolve4();
        return p.print("border-radius:{d}px {d}px {d}px {d}px;", .{ r[0], r[1], r[2], r[3] });
    }
    if (comptime eq(u8, name, "shadow")) {
        const s: core.Shadow = value;
        try p.print("box-shadow:{d}px {d}px {d}px {d}px ", .{ s.offset_x, s.offset_y, s.blur, s.spread });
        try colorCss(p, s.color);
        return p.writeByte(';');
    }
    if (comptime eq(u8, name, "overflow_hidden")) return if (value) p.writeAll("overflow:hidden;") else {};
    if (comptime eq(u8, name, "cursor")) return p.print("cursor:{s};", .{cursorCss(value)});
    // ── layout (CSS-layout subtrees only) ──
    if (comptime eq(u8, name, "padding") or eq(u8, name, "margin")) {
        const v: core.Padding = value;
        return l.print("{s}:{d}px {d}px {d}px {d}px;", .{ name, v.top, v.right, v.bottom, v.left });
    }
    if (comptime eq(u8, name, "gap")) return decl(l, "gap", token, "{d}px", .{value});
    if (comptime eq(u8, name, "width") or eq(u8, name, "height")) return sizing(l, name, value);
    if (comptime eq(u8, name, "min_width") or eq(u8, name, "max_width") or eq(u8, name, "min_height") or eq(u8, name, "max_height")) {
        if (!std.math.isFinite(value) or value < 0) return;
        return l.print("{s}:{d}px;", .{ kebab(name), value });
    }
    if (comptime eq(u8, name, "direction")) return l.print("display:flex;flex-direction:{s};", .{if (value == .row) "row" else "column"});
    if (comptime eq(u8, name, "justify")) return l.print("justify-content:{s};", .{switch (value) {
        .start => "flex-start",
        .end => "flex-end",
        inline else => |tag| comptime kebab(@tagName(tag)),
    }});
    if (comptime eq(u8, name, "align_items")) return l.print("align-items:{s};", .{switch (value) {
        .start => "flex-start",
        .end => "flex-end",
        inline else => |tag| comptime kebab(@tagName(tag)),
    }});
    if (comptime eq(u8, name, "flex")) return l.print("flex-grow:{d};", .{value});
    if (comptime eq(u8, name, "flex_shrink")) return l.print("flex-shrink:{d};", .{value});
    if (comptime eq(u8, name, "flex_wrap")) return l.print("flex-wrap:{s};", .{switch (value) {
        .no_wrap => "nowrap",
        inline else => |tag| comptime kebab(@tagName(tag)),
    }});
    if (comptime eq(u8, name, "position")) return l.print("position:{s};", .{@tagName(value)});
    if (comptime eq(u8, name, "z_index")) return p.print("z-index:{d};", .{value});
    // Anything else is zenit-only paint (glass, gradients, warp…): the host keeps
    // painting it from the node; record it for the mapping audit.
    try p.print("/* zenit:{s} */", .{name});
}

fn cursorCss(c: core.CursorShape) []const u8 {
    return switch (c) {
        .inherit => "inherit",
        .default => "default",
        .pointer => "pointer",
        .text => "text",
        .crosshair => "crosshair",
        .move => "move",
        .not_allowed => "not-allowed",
        .grab => "grab",
        .grabbing => "grabbing",
        .ew_resize => "ew-resize",
        .ns_resize => "ns-resize",
        .nwse_resize => "nwse-resize",
        .nesw_resize => "nesw-resize",
        .col_resize => "col-resize",
        .row_resize => "row-resize",
        .wait => "wait",
        .progress => "progress",
        .help => "help",
        .none => "none",
        .custom, .uncontrolled => "auto",
    };
}

fn unwrap(v: anytype) ?@typeInfo(@TypeOf(v)).optional.child {
    return v;
}

/// One rule pair (paint + layout) for a style layer; recurses into conditions.
fn emitLayer(w: *Writer, comptime selector: []const u8, comptime spec: anytype, t: *const ThemeTokens) !void {
    const S = @TypeOf(spec);
    var paint_buf: [4096]u8 = undefined;
    var layout_buf: [2048]u8 = undefined;
    var paint: Writer = .fixed(&paint_buf);
    var layout: Writer = .fixed(&layout_buf);
    const sink: Sink = .{ .paint = &paint, .layout = &layout };
    inline for (@import("zenit_reflection").fields(S)) |f| {
        if (comptime css.isConditionKey(f.name) or css.isMetaKey(f.name) or std.mem.eql(u8, f.name, "typography")) continue;
        const name = comptime css.boxName(f.name);
        const raw = @field(spec, f.name);
        const resolved = css.resolveInto(@FieldType(BoxStyle, name), comptime css.catOf(name), raw, t);
        if (unwrap(resolved)) |value| {
            const token = comptime tokenOf(@TypeOf(raw), raw, css.catOf(name));
            try emitField(sink, name, value, token);
        }
    }
    if (paint.end > 0) try w.print("{s}{{{s}}}\n", .{ selector, paint.buffered() });
    if (layout.end > 0) try w.print(".z-css-layout{s},.z-css-layout {s}{{{s}}}\n", .{ selector, selector, layout.buffered() });
    inline for (@import("zenit_reflection").fields(S)) |f| {
        if (comptime !css.isConditionKey(f.name)) continue;
        try emitLayer(w, selector ++ "[data-z-" ++ comptime kebab(f.name[1..]) ++ "]", @field(spec, f.name), t);
    }
}

fn optionName(comptime name: []const u8) []const u8 {
    // cva bool dimensions use `.false` / `.true`; enum options keep their names.
    return kebab(name);
}

/// Emit every `ui.css` / `ui.cva` declaration found in `Styles` (a styles.zig
/// namespace, or a YSS-generated twin).
pub fn emitModule(comptime Styles: type, w: *Writer, comptime opts: Options, t: *const ThemeTokens) !void {
    @setEvalBranchQuota(1_000_000);
    try w.print("/* zenit web css: {s} (generated; do not edit) */\n", .{opts.prefix});
    inline for (comptime @typeInfo(Styles).@"struct".decl_names) |dname| {
        const V = @field(Styles, dname);
        if (comptime @TypeOf(V) == type) {
            if (comptime @hasDecl(V, "zenit_recipe_config")) {
                try emitRecipe(w, "." ++ comptime kebabPrefix(opts) ++ dname, V.zenit_recipe_config, t);
            }
        } else if (comptime isCssValue(@TypeOf(V))) {
            try emitLayer(w, "." ++ comptime kebabPrefix(opts) ++ dname, @TypeOf(V).spec, t);
        }
    }
}

fn kebabPrefix(comptime opts: Options) []const u8 {
    return opts.prefix ++ "-";
}

fn isCssValue(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "zenit_style_part") and T.zenit_style_part == .css and @hasDecl(T, "spec");
}

fn emitRecipe(w: *Writer, comptime cls: []const u8, comptime config: anytype, t: *const ThemeTokens) !void {
    const C = @TypeOf(config);
    if (@hasField(C, "base")) try emitLayer(w, cls, css.specOf(config.base), t);
    if (@hasField(C, "variants")) {
        inline for (@import("zenit_reflection").fields(@TypeOf(config.variants))) |dim| {
            const opts = @field(config.variants, dim.name);
            inline for (@import("zenit_reflection").fields(@TypeOf(opts))) |o| {
                try emitLayer(w, cls ++ "--" ++ kebab(dim.name) ++ "-" ++ optionName(o.name), css.specOf(@field(opts, o.name)), t);
            }
        }
    }
    if (@hasField(C, "compound")) {
        inline for (config.compound) |c| {
            comptime var sel: []const u8 = "";
            inline for (@import("zenit_reflection").fields(@TypeOf(c.when))) |p| {
                const opt = @field(c.when, p.name);
                const opt_name = if (@TypeOf(opt) == bool) (if (opt) "true" else "false") else @tagName(opt);
                sel = sel ++ cls ++ "--" ++ kebab(p.name) ++ "-" ++ kebab(opt_name);
            }
            try emitLayer(w, sel, css.specOf(c.style), t);
        }
    }
}

/// Token custom properties for a theme, scoped by selector (e.g. `:root` for
/// light, `[data-theme="dark"]` for dark). Walks the whole token tree: colors
/// become CSS colors, numbers get `px` except unitless categories.
pub fn emitTokens(w: *Writer, selector: []const u8, t: *const ThemeTokens) !void {
    @setEvalBranchQuota(1_000_000);
    try w.print("{s}{{", .{selector});
    try emitTokenGroup(w, "--z", t.tokens, false);
    try w.writeAll("}\n");
}

fn emitTokenGroup(w: *Writer, comptime prefix: []const u8, group: anytype, comptime unitless: bool) !void {
    @setEvalBranchQuota(1_000_000);
    const G = @TypeOf(group);
    inline for (@import("zenit_reflection").fields(G)) |f| {
        const v = @field(group, f.name);
        const V = @TypeOf(v);
        const name = prefix ++ "-" ++ comptime kebab(f.name);
        if (V == Color) {
            try w.print("{s}:", .{name});
            try colorCss(w, v);
            try w.writeByte(';');
        } else if (V == f32 or V == f64 or V == u16 or V == u8 or V == i32 or V == u32) {
            const no_unit = unitless or comptime (std.mem.indexOf(u8, name, "weight") != null or std.mem.indexOf(u8, name, "opacity") != null or std.mem.indexOf(u8, name, "line-height") != null);
            try w.print("{s}:{d}{s};", .{ name, v, if (no_unit) "" else "px" });
        } else if (@typeInfo(V) == .@"struct" and !@typeInfo(V).@"struct".is_tuple) {
            try emitTokenGroup(w, name, v, unitless);
        }
    }
}

test "css export: css + cva + tokens" {
    const T = theme.refs;
    const S = struct {
        pub const card = css.css(.{ .background = T.color.bg_secondary, .padding = T.space.space400, .corner_radius = T.radius.md, ._hover = .{ .opacity = 0.8 } });
        pub const Badge = css.cva(.{
            .base = .{ .border = .{ .width = T.border_width.thin, .color = T.color.border } },
            .variants = .{ .even = .{ .false = .{}, .true = .{ .background = T.color.success_subtle } } },
            .defaults = .{ .even = false },
        });
    };
    var buf: [16 * 1024]u8 = undefined;
    var w: Writer = .fixed(&buf);
    try emitModule(S, &w, .{ .prefix = "S" }, &theme.light);
    try emitTokens(&w, ":root", &theme.light);
    const out = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, out, ".S-card{background-color:var(--z-color-bg-secondary,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "border-radius:var(--z-radius-md,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, ".S-card[data-z-hover]{opacity:0.8;}") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, ".z-css-layout.S-card,.z-css-layout .S-card{padding:") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, ".S-Badge{border-style:solid;") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, ".S-Badge--even-true{background-color:var(--z-color-success-subtle,") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "--z-color-bg-primary:#ffffff;") != null);
}
