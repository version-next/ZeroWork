const std = @import("std");
const theme = @import("example");
const edge = @import("edge");
const empty = @import("empty");
const sv = @import("zenit_style_values");
const preset = @import("preset_fixture");
const TOKENS = theme.refs;

test "real generated provider has unified typed refs and canonical renderer values" {
    try std.testing.expectEqual(theme.Token(.color), @TypeOf(TOKENS.color.surface));
    try std.testing.expectEqual(theme.Token(.color), @TypeOf(TOKENS.color.blue.@"500"));
    try std.testing.expect(theme.Token(.color) != theme.Token(.font_size));
    try std.testing.expectEqual(sv.Color, @TypeOf(theme.modes.dark.tokens.color.surface));
    try std.testing.expectEqual(@as(f32, 32), theme.resolve(.font_size, TOKENS.font_size.xxxl, &theme.modes.dark));
    try std.testing.expectEqual(@as(f32, 32), theme.resolve(.font_size, TOKENS.font_size.title, &theme.modes.dark));
    try std.testing.expectEqual(@as(u8, 0x93), theme.resolve(.color, TOKENS.color.action, &theme.modes.dark).r);
    try std.testing.expectEqual(@as(u8, 255), theme.resolve(.color, TOKENS.color.action, &theme.modes.high_contrast).r);
    try std.testing.expectEqual(@as(u8, 0), theme.resolve(.color, TOKENS.color.action, &theme.modes.high_contrast).b);
}
test "escaped names and empty categories compile as actual Zig" {
    try std.testing.expectEqual(@as(f32, 32), edge.resolve(.font_size, edge.refs.font_size.xLargeBlaBla, &edge.modes.light));
    try std.testing.expectEqual(@as(f32, 1), edge.resolve(.space, edge.refs.space.group.@"500", &edge.modes.light));
    try std.testing.expectEqual(@as(f32, 2), edge.resolve(.space, edge.refs.space.group.@"error", &edge.modes.light));
    try std.testing.expectEqual(@as(f32, 3), edge.resolve(.space, edge.refs.space.group.@"text-hairline", &edge.modes.light));
    try std.testing.expectEqual(@as(f32, 4), edge.resolve(.space, edge.refs.space.group._, &edge.modes.light));
    try std.testing.expectEqual(@as(f32, 5), edge.resolve(.space, edge.refs.space.group.semantic, &edge.modes.light));
    try std.testing.expectEqual(@as(f32, 24), edge.resolve(.size, edge.refs.size.fill, &edge.modes.light));
    try std.testing.expectEqual(@as(usize, 0), @import("zenit_reflection").fields(empty.Token(.color)).len);
    try std.testing.expectEqual(@as(usize, 0), @import("zenit_reflection").fields(@TypeOf(empty.modes.light.tokens.color)).len);
    try std.testing.expect(!@hasField(empty.Values, "system"));
    try std.testing.expect(!@hasField(@TypeOf(empty.modes.dark.tokens.color), "accent"));
}

test "default JSON keeps the scalar scales of the original preset in all three modes" {
    @setEvalBranchQuota(10000);
    const generated = @import("default");
    inline for (.{ "light", "dark", "high_contrast" }) |mode| {
        const old = @field(preset, mode);
        const new = @field(generated.modes, mode);
        inline for (@import("zenit_reflection").fields(preset.ThemeTokens)) |category| {
            if (comptime std.mem.eql(u8, category.name, "name") or std.mem.eql(u8, category.name, "scheme") or std.mem.eql(u8, category.name, "control")) continue;
            // Colors and elevation were redesigned (zenit UI native.pen); the design contract test below owns them.
            if (comptime std.mem.eql(u8, category.name, "color") or std.mem.eql(u8, category.name, "shadow")) continue;
            inline for (@import("zenit_reflection").fields(category.type)) |field| {
                // Component size variants moved to recipes; their geometry is tested with the components.
                if (comptime std.mem.eql(u8, category.name, "size") and (std.mem.eql(u8, field.name, "badge_sm") or std.mem.eql(u8, field.name, "badge_md"))) continue;
                // Checkbox indicator follows the desktop fusion spec (16 px, Foundations 06).
                if (comptime std.mem.eql(u8, category.name, "size") and std.mem.eql(u8, field.name, "checkbox")) continue;
                const key = comptime if (std.mem.eql(u8, category.name, "space")) renamedSpace(field.name) else field.name;
                try std.testing.expectEqualDeep(@field(@field(old, category.name), field.name), @field(@field(new.tokens, category.name), key));
            }
        }
    }
}

test "default JSON matches the zenit UI native design contract" {
    const d = @import("default").modes;
    const hex = sv.Color.hex;
    // Surfaces: App Gray canvas, white islands, blue selection (Foundations 00/02).
    try std.testing.expectEqual(hex(0xEFEFF1), d.light.tokens.color.bg_base);
    try std.testing.expectEqual(hex(0xFFFFFF), d.light.tokens.color.bg_primary);
    try std.testing.expectEqual(hex(0xE4E4E7), d.light.tokens.color.border);
    try std.testing.expectEqual(hex(0xEAEDFD), d.light.tokens.color.selection_bg);
    try std.testing.expectEqual(hex(0x3F4BBC), d.light.tokens.color.selection_fg);
    try std.testing.expectEqual(hex(0x4F5ED9), d.light.tokens.color.accent);
    try std.testing.expectEqual(hex(0x8C98EE), d.dark.tokens.color.accent);
    try std.testing.expectEqual(hex(0xD7DCFA), d.high_contrast.tokens.color.accent);
    try std.testing.expectEqual(hex(0x18181B), d.light.tokens.color.fg_primary);
    try std.testing.expectEqual(hex(0x0A0A0A), d.high_contrast.tokens.color.bg_base);
    // Palette ramps are addressable as base tokens.
    try std.testing.expectEqual(hex(0x4F5ED9), d.light.tokens.color.blue.@"600");
    try std.testing.expectEqual(hex(0x5C5C64), d.light.tokens.color.app_gray.@"650");
    // Elevation xs 1/2 · sm 2/6 · md 12/32 · lg 16/48 (offset Y / blur); none in high contrast.
    try std.testing.expectEqual(@as(f32, 1), d.light.tokens.shadow.xs.offset_y);
    try std.testing.expectEqual(@as(f32, 32), d.light.tokens.shadow.md.blur);
    try std.testing.expectEqual(@as(f32, 48), d.dark.tokens.shadow.lg.blur);
    try std.testing.expectEqual(sv.Color.rgba(0x0A, 0x0A, 0x0F, 0x2E), d.light.tokens.shadow.md.color);
    try std.testing.expectEqual(@as(u8, 0), d.high_contrast.tokens.shadow.lg.color.a);
    // Surface tints for large areas (Foundations 00B).
    try std.testing.expectEqual(hex(0xFBFBFC), d.light.tokens.color.surface_inset);
    try std.testing.expectEqual(hex(0xF8F9FF), d.light.tokens.color.accent_surface);
    try std.testing.expectEqual(hex(0xFFF8F8), d.light.tokens.color.surface_danger);
    // Role radii: Control 6 · Panel 10 · Island 12 · Dialog 12.
    try std.testing.expectEqual(@as(f32, 6), d.light.tokens.radius.control);
    try std.testing.expectEqual(@as(f32, 10), d.light.tokens.radius.panel);
    try std.testing.expectEqual(@as(f32, 12), d.light.tokens.radius.island);
    try std.testing.expectEqual(@as(f32, 12), d.light.tokens.radius.dialog);
}

fn renamedSpace(comptime old: []const u8) []const u8 {
    const names = .{ ._0 = "space0", ._0_5 = "space50", ._1 = "space100", ._1_5 = "space150", ._2 = "space200", ._3 = "space300", ._4 = "space400", ._6 = "space600", ._8 = "space800", ._10 = "space1000", ._12 = "space1200" };
    return @field(names, old);
}

test "default theme: every component role equals its default alias target in every mode" {
    @setEvalBranchQuota(100_000);
    const generated = @import("default");
    const roles = @import("token_resolver").roles.component_roles;
    inline for (.{ "light", "dark", "high_contrast" }) |mode| {
        const colors = @field(generated.modes, mode).tokens.color;
        inline for (roles) |role| {
            const name = comptime role.path["color.".len..];
            const target = comptime role.target["color.".len..];
            try std.testing.expectEqual(@field(colors, target), @field(colors, name));
        }
    }
}

test "layered provider: default.json + app overlay generates the base, the app tokens and the override" {
    @setEvalBranchQuota(100_000);
    const base = @import("default");
    const app = @import("layered");
    const hex = sv.Color.hex;
    // App-added semantic tokens are typed refs and Values fields like built-in ones.
    try std.testing.expectEqual(app.Token(.color), @TypeOf(app.refs.color.zw_island_ground));
    try std.testing.expectEqual(hex(0xF4F1EC), app.modes.light.tokens.color.zw_island_ground);
    try std.testing.expectEqual(hex(0x1B1A19), app.modes.dark.tokens.color.zw_island_ground);
    try std.testing.expectEqual(hex(0x141312), app.modes.dim.tokens.color.zw_island_ground);
    try std.testing.expectEqual(base.modes.light.tokens.color.border, app.modes.light.tokens.color.zw_island_edge);
    try std.testing.expectEqual(@as(f32, 44), app.resolve(.size, app.refs.size.zw_rail, &app.modes.light));
    // The overlay's mode falls back to dark for everything it does not set.
    try std.testing.expectEqual(app.modes.dark.tokens.color.bg_primary, app.modes.dim.tokens.color.bg_primary);
    // Override: accent and every default alias of it (roles included) follow the app value.
    try std.testing.expectEqual(hex(0xA23010), app.modes.light.tokens.color.accent);
    try std.testing.expectEqual(hex(0xE07050), app.modes.dark.tokens.color.accent);
    try std.testing.expectEqual(hex(0xA23010), app.modes.light.tokens.color.switch_track_on);
    try std.testing.expectEqual(hex(0xA23010), app.modes.light.tokens.color.progress_fill);
    try std.testing.expectEqual(hex(0xE07050), app.modes.high_contrast.tokens.color.accent);
    // Everything the overlay does not touch is the base value.
    inline for (.{ "light", "dark", "high_contrast" }) |mode| {
        const b = @field(base.modes, mode).tokens;
        const l = @field(app.modes, mode).tokens;
        try std.testing.expectEqual(b.color.bg_primary, l.color.bg_primary);
        try std.testing.expectEqual(b.color.danger, l.color.danger);
        try std.testing.expectEqual(b.space.space200, l.space.space200);
        try std.testing.expectEqualDeep(b.shadow.md, l.shadow.md);
    }
    // Metadata pointers name the real file.
    var saw_app = false;
    var saw_base = false;
    for (app.metadata) |meta| {
        if (std.mem.eql(u8, meta.path, "color.zw_island_ground") or std.mem.eql(u8, meta.path, "color.accent")) {
            try std.testing.expect(std.mem.endsWith(u8, meta.pointer[0 .. std.mem.indexOfScalar(u8, meta.pointer, '#').?], "app_overlay.json"));
            saw_app = true;
        }
        if (std.mem.eql(u8, meta.path, "color.bg_primary")) {
            try std.testing.expect(std.mem.endsWith(u8, meta.pointer, "default.json#/semantic/color/bg_primary"));
            saw_base = true;
        }
    }
    try std.testing.expect(saw_app and saw_base);
}
