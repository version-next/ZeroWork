//! Forward/backward compatibility of config.toml: unknown keys and sections
//! are skipped with a warning and preserved verbatim through a save.
const std = @import("std");
const config = @import("../config.zig");
const unknown = @import("../config_unknown.zig");
const store = @import("../store.zig");
const RuntimeConfig = @import("../runtime_config.zig").RuntimeConfig;

const Config = config.Config;

fn between(text: []const u8, needle: []const u8, after: []const u8, before: []const u8) !void {
    const at = std.mem.indexOf(u8, text, needle) orelse return error.TestExpectedNeedle;
    const lower = std.mem.indexOf(u8, text, after) orelse return error.TestExpectedAnchor;
    const upper = std.mem.indexOf(u8, text, before) orelse return error.TestExpectedAnchor;
    try std.testing.expect(lower < at and at < upper);
}

/// Written by a hypothetical newer ZeroWork; every known value is valid.
const future_source =
    \\future_top_level = 7
    \\[meta]
    \\config_revision = 3
    \\[ui]
    \\theme = "dark"
    \\future_card_motion = "fade"
    \\font_size = 14
    \\future_list = ["a; still one value", "b # not a comment"]
    \\[ui.future_panel]
    \\# comment kept inside an unknown section
    \\width = 320 # inline comments are not kept
    \\mode = { kind = "dock", side = "right" }
    \\[ssh]
    \\keepalive_sec = 45
    \\future_cipher = "chacha"
    \\[future_sync]
    \\enabled = true
    \\endpoint = "https://sync.example.test/v1"
    \\[[future_sync.targets]]
    \\name = "laptop"
    \\[ai]
    \\future_router = "smart"
    \\[[ai.providers]]
    \\id = "gateway"
    \\endpoint = "http://127.0.0.1:9/v1"
    \\future_region = "eu"
    \\[[ai.providers.models]]
    \\name = "m1"
    \\context_window = 8192
    \\future_price = 0.5
    \\[keys]
    \\search = "cmd+e"
    \\future_action = "cmd+y"
    \\[[plugin_preferences]]
    \\plugin_id = "zw.demo"
    \\key = "mode"
    \\value = "on"
    \\future_scope = "window"
    \\
;

test "config unknown keys and sections are skipped with warnings and known values still apply" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const parsed = try Config.parseWithAllocator(arena.allocator(), future_source);
    try std.testing.expectEqual(@as(u64, 3), parsed.config_revision);
    try std.testing.expectEqual(@as(u16, 45), parsed.ssh.keepalive_sec);
    try std.testing.expectEqual(config.keybindings.KeyCode.e, parsed.keys.get(.search).key);
    try std.testing.expectEqualStrings("gateway", parsed.ai.providers[0].name);
    try std.testing.expectEqual(@as(u32, 8192), parsed.ai.providers[0].models[0].context_window);
    try std.testing.expectEqualStrings("on", parsed.pluginPreference("zw.demo", "mode").?);
    // 9 unknown keys + 3 unknown sections ([ui.future_panel], [future_sync], [[future_sync.targets]]).
    try std.testing.expectEqual(@as(u32, 12), parsed.unknown.skipped);
    try std.testing.expectEqual(@as(u32, 0), parsed.unknown.dropped);
    // Unknown flat provider fields never allocate a phantom provider.
    const flat = try Config.parseWithAllocator(arena.allocator(), "[ai]\nprovider_3_future = 1\nprovider_x_name = \"y\"\n");
    try std.testing.expectEqual(@as(usize, 0), flat.ai.provider_count);
    try std.testing.expectEqual(@as(usize, 2), flat.unknown.entries.len);
    // Without an allocator unknown content is skipped but cannot be kept.
    const borrowed = try Config.parse("[ui]\nmade_up = true\n[elsewhere]\nx = 1\n");
    try std.testing.expectEqual(@as(u32, 2), borrowed.unknown.skipped);
    try std.testing.expectEqual(@as(usize, 0), borrowed.unknown.entries.len);
}

test "config unknown content round trips verbatim in its original section" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var parsed = try Config.parseWithAllocator(arena.allocator(), future_source);
    parsed.ui.font_size = 16; // edit one known field, as the settings page does
    var buffer: [64 * 1024]u8 = undefined;
    const written = try parsed.format(&buffer);

    try std.testing.expect(std.mem.startsWith(u8, written, "future_top_level = 7\n\n[meta]\n"));
    try between(written, "\nfuture_card_motion = \"fade\"\nfuture_list = [\"a; still one value\", \"b # not a comment\"]\n", "[ui]\n", "[ui.materials]\n");
    try between(written, "\n[ui.future_panel]\n# comment kept inside an unknown section\nwidth = 320\nmode = { kind = \"dock\", side = \"right\" }\n", "[ui]\n", "[ui.materials]\n");
    try between(written, "\nfuture_cipher = \"chacha\"\n", "[ssh]\n", "[ai]\n");
    try between(written, "\n[future_sync]\nenabled = true\nendpoint = \"https://sync.example.test/v1\"\n\n[[future_sync.targets]]\nname = \"laptop\"\n", "[ssh]\n", "[ai]\n");
    try between(written, "\nfuture_router = \"smart\"\n", "[ai]\n", "[[ai.providers]]\n");
    try between(written, "\nfuture_region = \"eu\"\n", "[[ai.providers]]\n", "[[ai.providers.models]]\n");
    try between(written, "\nfuture_price = 0.5\n", "[[ai.providers.models]]\n", "[log]\n");
    try between(written, "\nfuture_action = \"cmd+y\"\n", "[keys]\n", "[[plugin_preferences]]\n");
    try std.testing.expect(std.mem.endsWith(u8, written, "value = \"on\"\nfuture_scope = \"window\"\n"));
    try std.testing.expect(std.mem.indexOf(u8, written, "inline comments are not kept") == null);

    // Reading back keeps the edit and the opaque content; a second write is a fixed point.
    const reread = try Config.parseWithAllocator(arena.allocator(), written);
    try std.testing.expectEqual(@as(u8, 16), reread.ui.font_size);
    try std.testing.expectEqual(parsed.unknown.entries.len, reread.unknown.entries.len);
    var second: [64 * 1024]u8 = undefined;
    try std.testing.expectEqualStrings(written, try reread.format(&second));
}

test "config without unknown content keeps the existing write order" {
    var buffer: [64 * 1024]u8 = undefined;
    const written = try (Config{}).format(&buffer);
    try std.testing.expect(std.mem.startsWith(u8, written, "[meta]\nconfig_revision = 1\n\n[ui]\nicon_background = "));
    // `terminal_right_click`（design-r3 B1）、`float_card_transition`（Z12b）追加在 [ui] 末尾，原有键的顺序不变。
    try std.testing.expect(std.mem.indexOf(u8, written, "scrollback_limit = 25000\nterminal_right_click = \"menu\"\nfloat_card_transition = \"anchor\"\n\n[ui.materials]\nblur_px = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\n\n[ui.materials.background]\nenabled = false\npath = ") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\n\n\n") == null);
    var order: [12]usize = undefined;
    for ([_][]const u8{ "[meta]", "[ui]", "[ui.materials]", "[ui.materials.background]", "[updates]", "[completion]", "[transfer]", "[ssh]", "[ai]", "[log]", "[notify]", "[keys]" }, 0..) |header, i| order[i] = std.mem.indexOf(u8, written, header).?;
    for (order[1..], order[0 .. order.len - 1]) |later, earlier| try std.testing.expect(earlier < later);
}

test "config unknown preservation enforces count and size limits" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var many: std.Io.Writer.Allocating = .init(a);
    try many.writer.writeAll("[ui]\n");
    for (0..unknown.max_entries + 44) |i| try many.writer.print("future_{d} = {d}\n", .{ i, i });
    const counted = try Config.parseWithAllocator(a, many.written());
    try std.testing.expectEqual(@as(usize, unknown.max_entries), counted.unknown.entries.len);
    try std.testing.expectEqual(@as(u32, 44), counted.unknown.dropped);

    const long = try a.alloc(u8, unknown.max_line_bytes);
    @memset(long, 'x');
    const oversized = try Config.parseWithAllocator(a, try std.fmt.allocPrint(a, "[ui]\nhuge = \"{s}\"\nsmall = 1\n", .{long}));
    try std.testing.expectEqual(@as(usize, 1), oversized.unknown.entries.len);
    try std.testing.expectEqual(@as(u32, 1), oversized.unknown.dropped);

    var bulky: std.Io.Writer.Allocating = .init(a);
    try bulky.writer.writeAll("[future]\n");
    const chunk = long[0 .. unknown.max_line_bytes - 16];
    for (0..20) |i| try bulky.writer.print("k{d:0>2} = \"{s}\"\n", .{ i, chunk });
    const total = try Config.parseWithAllocator(a, bulky.written());
    var bytes: usize = 0;
    for (total.unknown.entries) |entry| bytes += entry.text.len;
    try std.testing.expect(bytes <= unknown.max_total_bytes);
    try std.testing.expect(total.unknown.dropped > 0);
    try total.validate();
}

test "config unknown values are validated so writes cannot inject sections or keys" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Unsafe or unsupported text is skipped without being preserved.
    for ([_][]const u8{
        "[ui]\nx = \"open\n",
        "[ui]\nx = \"escaped\\\"\n",
        "[ui]\nx = [1, 2\n",
        "[ui]\nx = 1]\n",
        "[ui]\nx = \"bell\x07\"\n",
        "[ui]\n\"quoted key\" = 1\n",
        "[\"quoted section\"]\nx = 1\n",
    }) |source| {
        const parsed = try Config.parseWithAllocator(a, source);
        try std.testing.expectEqual(@as(usize, 0), parsed.unknown.entries.len);
        try std.testing.expect(parsed.unknown.dropped > 0);
    }
    // Escapes inside strings stay opaque and round trip byte for byte.
    const escaped = try Config.parseWithAllocator(a, "[ui]\nx = \"a\\\"]\\n[evil]\\\\\"\n");
    var buffer: [64 * 1024]u8 = undefined;
    const written = try escaped.format(&buffer);
    try std.testing.expect(std.mem.indexOf(u8, written, "\nx = \"a\\\"]\\n[evil]\\\\\"\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "\n[evil]") == null);
    try std.testing.expectEqualStrings("dark", (try Config.parseWithAllocator(a, written)).ui.theme);

    // Entries that did not come from the parser are rechecked before writing.
    for ([_]unknown.Entry{
        .{ .kind = .key, .section = "ui", .text = "x = 1\n[ui]\ntheme = \"evil\"" },
        .{ .kind = .key, .section = "ui", .text = "x = 1; theme = \"evil\"" },
        .{ .kind = .key, .section = "ui", .text = "x = 1 # trailing" },
        .{ .kind = .key, .section = "ui", .text = "[evil] = 1" },
        .{ .kind = .header, .section = "ssh", .text = "[a]\nb = 1" },
        .{ .kind = .header, .section = "ssh", .text = "[a b]" },
        .{ .kind = .line, .section = "ssh", .text = "plain text" },
    }) |entry| {
        var value: Config = .{};
        value.unknown.entries = &.{entry};
        try std.testing.expectError(error.InvalidValue, value.validate());
        try std.testing.expectError(error.InvalidUnknownEntry, value.format(&buffer));
    }
    // A body line is only written directly below its own header.
    var orphan: Config = .{};
    orphan.unknown.entries = &.{.{ .kind = .line, .section = "ssh", .text = "theme = \"evil\"" }};
    try std.testing.expect(std.mem.indexOf(u8, try orphan.format(&buffer), "evil") == null);
}

test "config known keys with invalid values keep failing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectError(error.OutOfRange, Config.parseWithAllocator(a, "[ui]\nfont_size = 2\n"));
    try std.testing.expectError(error.InvalidValue, Config.parseWithAllocator(a, "[ui]\ntheme = 5\n"));
    try std.testing.expectError(error.InvalidValue, Config.parseWithAllocator(a, "[ui]\nicon_background = \"neon\"\n"));
    try std.testing.expectError(error.InvalidExecutionMode, Config.parseWithAllocator(a, "[ai]\nexecution_mode = \"unsafe\"\n"));
    try std.testing.expectError(error.InvalidValue, Config.parseWithAllocator(a, "[ai]\nprovider_0_kind = \"bogus\"\n"));
    try std.testing.expectError(error.InvalidValue, Config.parseWithAllocator(a, "[keys]\nsearch = \"cmd+bogus\"\n"));
    try std.testing.expectError(error.InvalidValue, Config.parseWithAllocator(a, "[ssh]\nreconnect_backoff = [1,2]\n"));
    try std.testing.expectError(error.InvalidAssignment, Config.parseWithAllocator(a, "[ui]\nno separator\n"));
    try std.testing.expectError(error.InvalidAssignment, Config.parseWithAllocator(a, "[future]\nno separator\n"));
    // Malformed headers and redefinitions of known tables remain errors.
    try std.testing.expectError(error.InvalidSection, Config.parseWithAllocator(a, "[ui\nx = 1\n"));
    try std.testing.expectError(error.InvalidSection, Config.parseWithAllocator(a, "[[ui]]\nx = 1\n"));
    try std.testing.expectError(error.InvalidSection, Config.parseWithAllocator(a, "[ai.providers]\nx = 1\n"));
}

test "config compatibility future version file starts and survives a settings save" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "config.toml", .data = future_source });

    // The startup path: store.load through RuntimeConfig.loadOrDefault.
    var runtime = try RuntimeConfig.loadOrDefault(std.testing.io, tmp.dir, std.testing.allocator, "config.toml");
    defer runtime.deinit();
    try std.testing.expectEqual(@as(u16, 45), runtime.value.ssh.keepalive_sec);
    try std.testing.expectEqual(@as(u32, 0), runtime.value.unknown.dropped);
    try runtime.updateSetting(std.testing.io, tmp.dir, "ui", "font_size", .{ .unsigned = 15 });

    const saved = try tmp.dir.readFileAlloc(std.testing.io, "config.toml", std.testing.allocator, .limited(store.max_config_bytes));
    defer std.testing.allocator.free(saved);
    try std.testing.expect(std.mem.indexOf(u8, saved, "font_size = 15\n") != null);
    try between(saved, "\nfuture_card_motion = \"fade\"\n", "[ui]\n", "[ui.materials]\n");
    try between(saved, "\n[future_sync]\nenabled = true\n", "[ssh]\n", "[ai]\n");
    try between(saved, "\n[ui.future_panel]\n", "[ui]\n", "[ui.materials]\n");
    for ([_][]const u8{ "future_top_level = 7\n", "future_cipher = \"chacha\"\n", "future_router = \"smart\"\n", "future_region = \"eu\"\n", "future_price = 0.5\n", "future_action = \"cmd+y\"\n", "future_scope = \"window\"\n", "[[future_sync.targets]]\nname = \"laptop\"\n" }) |needle|
        try std.testing.expect(std.mem.indexOf(u8, saved, needle) != null);

    // A second launch after the save still loads and still carries everything.
    var restarted = try RuntimeConfig.loadOrDefault(std.testing.io, tmp.dir, std.testing.allocator, "config.toml");
    defer restarted.deinit();
    try std.testing.expectEqual(@as(u8, 15), restarted.value.ui.font_size);
    try std.testing.expectEqual(runtime.value.unknown.entries.len, restarted.value.unknown.entries.len);
}
