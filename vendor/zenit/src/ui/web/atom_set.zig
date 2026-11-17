//! The build-time atom set: `style_atoms.static_atoms` plus every theme-token
//! colour (light + dark) for each colour property. The generator
//! (tools/web_css/atoms.zig) writes these rules into zenit-atoms.css; the DomHost
//! enumerates the same set at init so it never re-inserts them at runtime.
const std = @import("std");
const style_atoms = @import("style_atoms.zig");
const theme = @import("../theme.zig");
const Color = @import("../core/types.zig").Color;

pub fn forEach(ctx: anytype, comptime cb: fn (@TypeOf(ctx), []const u8, []const u8) anyerror!void) !void {
    for (style_atoms.static_atoms) |a| try cb(ctx, a.prop, a.value);
    try colorsOf(ctx, cb, theme.light.tokens);
    try colorsOf(ctx, cb, theme.dark.tokens);
}

fn colorsOf(ctx: anytype, comptime cb: fn (@TypeOf(ctx), []const u8, []const u8) anyerror!void, group: anytype) !void {
    @setEvalBranchQuota(1_000_000);
    const G = @TypeOf(group);
    inline for (@import("zenit_reflection").fields(G)) |f| {
        const v = @field(group, f.name);
        const V = @TypeOf(v);
        if (V == Color) {
            var buf: [16]u8 = undefined;
            var w: std.Io.Writer = .fixed(&buf);
            try style_atoms.writeColor(&w, v.r, v.g, v.b, v.a);
            for (style_atoms.color_props) |p| try cb(ctx, p, w.buffered());
        } else if (@typeInfo(V) == .@"struct" and !@typeInfo(V).@"struct".is_tuple) {
            try colorsOf(ctx, cb, v);
        }
    }
}

/// Write one atomic rule `.<class>{prop:value}`.
pub fn writeRule(w: *std.Io.Writer, prop: []const u8, value: []const u8) !void {
    var cb: [96]u8 = undefined;
    try style_atoms.writeSelector(w, style_atoms.className(&cb, prop, value));
    try w.print("{{{s}:{s}}}\n", .{ prop, value });
}
