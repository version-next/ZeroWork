//! Atomic CSS for the Web DOM host (Panda-style).
//!
//! Every resolved style declaration `prop:value` maps to one class
//! (`d_flex`, `flex-d_row`, `gap_8px`, `bg_#ffffffff`). The host writes class
//! lists, not inline styles:
//!
//! - Build time: every enumerable atom (`staticAtoms`, plus theme-token colours
//!   supplied by the generator) is emitted into `zenit-atoms.css`
//!   (tools/web_css/atoms.zig). The browser only loads a stylesheet.
//! - Runtime: a value only known at runtime (an app's `width:228px`) gets its rule
//!   inserted once into a constructed stylesheet, then reused by every node.
//! - Inline style is reserved for per-frame values: layout-domain boundary
//!   geometry, transform and opacity (DomHost decides; see `isVolatile`).
//!
//! Generator and host import this file, so the static set cannot drift.
const std = @import("std");

/// Short Panda-like property aliases (unknown properties use their own name).
const aliases = std.StaticStringMap([]const u8).initComptime(.{
    .{ "display", "d" },                 .{ "flex-direction", "flex-d" },
    .{ "align-items", "ai" },            .{ "align-content", "ac" },
    .{ "justify-content", "jc" },        .{ "align-self", "as" },
    .{ "flex-wrap", "flex-w" },          .{ "flex-grow", "grow" },
    .{ "flex-shrink", "shrink" },        .{ "flex-basis", "basis" },
    .{ "position", "pos" },              .{ "pointer-events", "pe" },
    .{ "padding-top", "pt" },            .{ "padding-right", "pr" },
    .{ "padding-bottom", "pb" },         .{ "padding-left", "pl" },
    .{ "margin-top", "mt" },             .{ "margin-right", "mr" },
    .{ "margin-bottom", "mb" },          .{ "margin-left", "ml" },
    .{ "width", "w" },                   .{ "height", "h" },
    .{ "min-width", "min-w" },           .{ "max-width", "max-w" },
    .{ "min-height", "min-h" },          .{ "max-height", "max-h" },
    .{ "background-color", "bg" },       .{ "background-image", "bg-img" },
    .{ "color", "c" },                   .{ "border-color", "bd-c" },
    .{ "border-style", "bd-s" },         .{ "border-top-width", "bd-t" },
    .{ "border-right-width", "bd-r" },   .{ "border-bottom-width", "bd-b" },
    .{ "border-left-width", "bd-l" },    .{ "border-top-left-radius", "r-tl" },
    .{ "border-top-right-radius", "r-tr" }, .{ "border-bottom-right-radius", "r-br" },
    .{ "border-bottom-left-radius", "r-bl" }, .{ "overflow", "ov" },
    .{ "overflow-x", "ov-x" },           .{ "font-family", "ff" },
    .{ "font-size", "fs" },              .{ "font-weight", "fw" },
    .{ "font-style", "fst" },            .{ "line-height", "lh" },
    .{ "white-space", "ws" },            .{ "text-align", "ta" },
    .{ "text-overflow", "to" },          .{ "text-decoration", "td" },
    .{ "box-shadow", "shadow" },         .{ "backdrop-filter", "bf" },
    .{ "-webkit-backdrop-filter", "wbf" }, .{ "mask-image", "mask" },
    .{ "-webkit-mask-image", "wmask" },  .{ "z-index", "z" },
    .{ "outline", "ol" },                .{ "outline-offset", "ol-off" },
    .{ "aspect-ratio", "ar" },           .{ "grid-template-columns", "grid-tc" },
    .{ "grid-template-rows", "grid-tr" }, .{ "column-gap", "cgap" },
    .{ "row-gap", "rgap" },              .{ "grid-column", "gcol" },
    .{ "grid-row", "grow-r" },           .{ "-webkit-line-clamp", "clamp" },
    .{ "-webkit-box-orient", "box-o" },  .{ "transform-origin", "t-origin" },
    .{ "background-size", "bg-size" },
});

fn plainValue(v: []const u8) bool {
    if (v.len == 0 or v.len > 28) return false;
    for (v) |ch| switch (ch) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '.', '%', '#', ' ' => {},
        else => return false,
    };
    return true;
}

/// Class name for one declaration: `<alias>_<value>` (spaces -> `_`), or
/// `<alias>_<hash>` for long / punctuated values (gradients, shadows, stacks).
pub fn className(buf: []u8, prop: []const u8, value: []const u8) []const u8 {
    var w: std.Io.Writer = .fixed(buf);
    w.writeAll(aliases.get(prop) orelse prop) catch unreachable;
    w.writeByte('_') catch unreachable;
    if (std.mem.startsWith(u8, value, "var(--") and std.mem.endsWith(u8, value, ")") and plainValue(value[6 .. value.len - 1])) {
        w.writeAll(value[6 .. value.len - 1]) catch unreachable; // ff_zf-0
    } else if (plainValue(value)) {
        for (value) |ch| w.writeByte(if (ch == ' ') '_' else ch) catch unreachable;
    } else {
        var h = std.hash.Wyhash.init(0x5a);
        h.update(prop);
        h.update(value);
        w.print("{x:0>8}", .{@as(u32, @truncate(h.final()))}) catch unreachable;
    }
    return w.buffered();
}

/// CSS selector escape for a class name (`.` `%` `#` and the like).
pub fn writeSelector(w: *std.Io.Writer, cls: []const u8) !void {
    try w.writeByte('.');
    for (cls, 0..) |ch, i| switch (ch) {
        'a'...'z', 'A'...'Z', '_' => try w.writeByte(ch),
        '0'...'9', '-' => if (i == 0) try w.print("\\{x} ", .{ch}) else try w.writeByte(ch),
        else => try w.print("\\{c}", .{ch}),
    };
}

pub const Atom = struct { prop: []const u8, value: []const u8 };

fn atoms(comptime prop: []const u8, comptime values: []const []const u8) []const Atom {
    comptime {
        var out: [values.len]Atom = undefined;
        for (values, 0..) |v, i| out[i] = .{ .prop = prop, .value = v };
        const final = out;
        return &final;
    }
}

fn pxRange(comptime prop: []const u8, comptime lo: comptime_int, comptime hi: comptime_int) []const Atom {
    comptime {
        var out: [hi - lo + 1]Atom = undefined;
        for (lo..hi + 1, 0..) |v, i| out[i] = .{ .prop = prop, .value = std.fmt.comptimePrint("{d}px", .{v}) };
        const final = out;
        return &final;
    }
}

const aligns: []const []const u8 = &.{ "flex-start", "flex-end", "center", "stretch", "baseline", "first baseline" };
const justifies: []const []const u8 = &.{ "flex-start", "flex-end", "center", "space-between", "space-around", "space-evenly" };

/// Enumerable atoms emitted at build time (colours come from the theme tokens,
/// added by the generator; see tools/web_css/atoms.zig).
pub const static_atoms: []const Atom = blk: {
    @setEvalBranchQuota(100_000);
    var all: []const Atom = &.{};
    all = all ++ atoms("display", &.{ "flex", "none", "block", "grid", "-webkit-box" });
    all = all ++ atoms("flex-direction", &.{ "row", "row-reverse", "column", "column-reverse" });
    all = all ++ atoms("align-items", aligns);
    all = all ++ atoms("align-self", aligns ++ &[_][]const u8{"auto"});
    all = all ++ atoms("align-content", justifies ++ &[_][]const u8{ "normal", "stretch" });
    all = all ++ atoms("justify-content", justifies);
    all = all ++ atoms("flex-wrap", &.{ "nowrap", "wrap", "wrap-reverse" });
    all = all ++ atoms("flex-grow", &.{ "0", "1" });
    all = all ++ atoms("flex-shrink", &.{ "0", "1" });
    all = all ++ atoms("flex-basis", &.{ "auto", "content", "0px" });
    all = all ++ atoms("position", &.{ "relative", "absolute", "static" });
    all = all ++ atoms("pointer-events", &.{ "auto", "none" });
    all = all ++ atoms("overflow", &.{"hidden"});
    all = all ++ atoms("overflow-x", &.{"clip"});
    all = all ++ atoms("contain", &.{ "layout", "layout size" });
    all = all ++ atoms("white-space", &.{ "pre", "pre-wrap" });
    all = all ++ atoms("text-align", &.{ "start", "center", "end" });
    all = all ++ atoms("text-overflow", &.{"ellipsis"});
    all = all ++ atoms("text-decoration", &.{"line-through"});
    all = all ++ atoms("font-style", &.{"italic"});
    all = all ++ atoms("-webkit-box-orient", &.{"vertical"});
    all = all ++ atoms("border-style", &.{"solid"});
    all = all ++ atoms("transform-origin", &.{"50% 50%"});
    all = all ++ atoms("background-size", &.{"100% 100%"});
    all = all ++ atoms("font-family", &.{ "var(--zf-0)", "var(--zfm-0)" });
    all = all ++ atoms("font-weight", &.{ "100", "200", "300", "400", "500", "600", "700", "800", "900" });
    for (.{ "width", "height" }) |p| all = all ++ atoms(p, &.{ "auto", "max-content" });
    for (.{ "min-width", "min-height" }) |p| all = all ++ atoms(p, &.{ "auto", "0px" });
    for (.{ "max-width", "max-height" }) |p| all = all ++ atoms(p, &.{"none"});
    for (.{ "margin-top", "margin-right", "margin-bottom", "margin-left" }) |p| all = all ++ atoms(p, &.{ "0px", "auto" });
    for (.{ "padding-top", "padding-right", "padding-bottom", "padding-left" }) |p| all = all ++ pxRange(p, 0, 32);
    all = all ++ pxRange("gap", 0, 32);
    all = all ++ pxRange("font-size", 9, 32);
    for (.{ "border-top-width", "border-right-width", "border-bottom-width", "border-left-width" }) |p| all = all ++ pxRange(p, 1, 4);
    for (.{ "border-top-left-radius", "border-top-right-radius", "border-bottom-right-radius", "border-bottom-left-radius" }) |p| all = all ++ pxRange(p, 1, 24);
    break :blk all;
};

/// Hex colour as the host writes it (one spelling per colour => one atom).
pub fn writeColor(w: *std.Io.Writer, r: u8, g: u8, b: u8, a: u8) !void {
    try w.print("#{x:0>2}{x:0>2}{x:0>2}{x:0>2}", .{ r, g, b, a });
}

pub const color_props = [_][]const u8{ "background-color", "color", "border-color" };

test "class names: readable for plain values, hashed for punctuation" {
    var b: [64]u8 = undefined;
    try std.testing.expectEqualStrings("d_flex", className(&b, "display", "flex"));
    try std.testing.expectEqualStrings("as_first_baseline", className(&b, "align-self", "first baseline"));
    try std.testing.expectEqualStrings("bg_#ffffffff", className(&b, "background-color", "#ffffffff"));
    try std.testing.expectEqualStrings("ff_zf-0", className(&b, "font-family", "var(--zf-0)"));
    try std.testing.expectEqualStrings("shadow_0px_1px_2px_0px_#00000022", className(&b, "box-shadow", "0px 1px 2px 0px #00000022"));
    const h = className(&b, "background-image", "linear-gradient(to right,#000000ff,#ffffffff)");
    try std.testing.expect(std.mem.startsWith(u8, h, "bg-img_") and h.len == "bg-img_".len + 8);
    var sb: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&sb);
    try writeSelector(&w, "bg_#ff.5%");
    try std.testing.expectEqualStrings(".bg_\\#ff\\.5\\%", w.buffered());
}
