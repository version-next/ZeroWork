//! `model/catalog.zig`：分类 → 子页面 → 面板目录（自 view/settings_subpages.zig 提出的无 ui 数据）。
const std = @import("std");
const catalog = @import("../model/catalog.zig");
const history = @import("../model/settings_history.zig");

test "settings catalog follows settings_pages order with stable slugs" {
    const slugs = [_][]const u8{ "appearance", "keys", "ssh", "transfer", "ai", "plugins", "notifications", "data", "updates" };
    try std.testing.expectEqual(catalog.pages.pages.len, catalog.categories.len);
    for (slugs, catalog.categories, 0..) |slug, category, page| {
        try std.testing.expectEqualStrings(slug, category.slug);
        try std.testing.expect(category.description.len != 0);
        try std.testing.expectEqualStrings(catalog.pages.pages[page].name, catalog.title(page));
        try std.testing.expectEqual(@as(usize, history.subpage_counts[page]), category.subpages.len);
        try std.testing.expectEqual(category.subpages.len != 0, catalog.hasOverview(page));
    }
    try std.testing.expectEqualStrings("外观与主题", catalog.title(0));
}

test "settings catalog subpages list their own category panes and unique slugs" {
    for (catalog.categories) |category| {
        var prefix_buffer: [64]u8 = undefined;
        const prefix = try std.fmt.bufPrint(&prefix_buffer, "settings.{s}.", .{category.slug});
        for (category.subpages, 0..) |sub, index| {
            try std.testing.expect(sub.title.len != 0 and sub.sections.len != 0);
            for (sub.sections) |section| try std.testing.expect(std.mem.startsWith(u8, section, prefix));
            for (category.subpages[index + 1 ..]) |other| try std.testing.expect(!std.mem.eql(u8, sub.slug, other.slug));
        }
    }
}

test "settings catalog lookup helpers" {
    try std.testing.expectEqual(@as(?catalog.Subpage, null), catalog.get(0, null));
    try std.testing.expectEqual(@as(?catalog.Subpage, null), catalog.get(1, 0));
    try std.testing.expectEqual(@as(?catalog.Subpage, null), catalog.get(0, 3));
    try std.testing.expectEqual(@as(usize, 0), catalog.subpages(99).len);
    const socks = catalog.get(2, 1).?;
    try std.testing.expectEqualStrings("socks", socks.slug);
    try std.testing.expect(catalog.contains(socks, "settings.ssh.socks"));
    try std.testing.expect(!catalog.contains(socks, "settings.ssh.connection"));
    try std.testing.expectEqual(@as(?u8, 1), catalog.forKey(2, "ssh", "socks_port"));
    try std.testing.expectEqual(@as(?u8, 1), catalog.forKey(3, "transfer", "chunk_kb"));
    try std.testing.expectEqual(@as(?u8, 2), catalog.forKey(0, "completion", "enabled"));
    try std.testing.expectEqual(@as(?u8, null), catalog.forKey(1, "ssh", "socks_port"));
    try std.testing.expectEqual(@as(?u8, null), catalog.forKey(2, "ssh", "no_such_key"));
}

test "settings catalog keys map every documented key of a category with subpages once" {
    for (catalog.pages.keys) |entry| {
        var page: usize = catalog.categories.len;
        for (catalog.pages.pages, 0..) |candidate, index| if (std.mem.eql(u8, candidate.name, entry.page)) {
            page = index;
        };
        try std.testing.expect(page < catalog.categories.len);
        if (!catalog.hasOverview(page)) continue;
        try std.testing.expect(catalog.forKey(page, entry.section, entry.key) != null);
    }
}

test "settings catalog summaries render live draft values" {
    var value: catalog.config.Config = .{};
    var buffer: [256]u8 = undefined;
    for (catalog.categories) |category| for (category.subpages) |sub| {
        const text = try sub.summary(value, &buffer);
        try std.testing.expect(text.len != 0);
    };
    value.ssh.auto_reconnect = false;
    try std.testing.expectEqualStrings("已关闭自动重连", try catalog.get(2, 2).?.summary(value, &buffer));
    value.notify.transfer_done = true;
    value.notify.reconnect = false;
    value.notify.ai_ready = false;
    value.notify.bell = false;
    try std.testing.expectEqualStrings("1 / 4 类事件已开启", try catalog.get(6, 0).?.summary(value, &buffer));
    try std.testing.expectEqualStrings("导出诊断日志 · 清理会话记录 · 清除全部数据", try catalog.get(7, 2).?.summary(value, &buffer));
}

test "settings catalog search aliases cover every category" {
    try std.testing.expectEqual(catalog.categories.len, catalog.search.page_terms.len);
    try std.testing.expect(catalog.search.pageMatches("socks5", 2));
    try std.testing.expectEqual(@as(?usize, 2), catalog.search.firstPage("重连"));
}

test "settings byte labels follow shared/base/format (settings-copy, units-iec)" {
    // chunk_kb / ring_mb / shared_pacing_kbps 按 1024 字节计；摘要与输入框后缀都用 IEC 写法（KiB / MiB / KiB/s），整数值不带小数。
    var value: catalog.config.Config = .{};
    value.transfer.window_chunks = 16;
    value.transfer.chunk_kb = 64;
    value.transfer.max_tasks = 3;
    value.log.ring_mb = 64;
    var buffer: [256]u8 = undefined;
    const transfer = catalog.categories[3];
    try std.testing.expectEqualStrings("SFTP 引擎", transfer.subpages[1].title);
    try std.testing.expectEqualStrings("16 × 64 KiB · 3 并发", try transfer.subpages[1].summary(value, &buffer));
    const data = catalog.categories[7];
    const history_page = for (data.subpages) |page| {
        if (std.mem.eql(u8, page.slug, "history")) break page;
    } else unreachable;
    const summary = try history_page.summary(value, &buffer);
    try std.testing.expect(std.mem.startsWith(u8, summary, "缓冲 64 MiB · "));
    const fields = @import("../model/pane_fields.zig");
    try std.testing.expectEqualStrings("KiB", fields.transfer.chunk_kb.unit.?);
    try std.testing.expectEqualStrings("MiB", fields.data.ring_mb.unit.?);
    try std.testing.expectEqualStrings("KiB/s", fields.transfer.shared_pacing_kbps.unit.?);
    // 共享通道限速：transfer_pacer 按 × 1024 字节每秒换算，摘要走 format.rate。
    value.transfer.shared_pacing_kbps = 2048;
    const isolation = transfer.subpages[0];
    try std.testing.expectEqualStrings("独立传输连接 · 共享通道 2 MiB/s", try isolation.summary(value, &buffer));
    value.transfer.shared_pacing_kbps = 512;
    try std.testing.expectEqualStrings("独立传输连接 · 共享通道 512 KiB/s", try isolation.summary(value, &buffer));
    value.transfer.shared_pacing_kbps = 0;
    try std.testing.expectEqualStrings("独立传输连接 · 共享通道不限速", try isolation.summary(value, &buffer));
    value.log.ring_mb = 1536;
    try std.testing.expect(std.mem.startsWith(u8, try history_page.summary(value, &buffer), "缓冲 1.5 GiB · "));
}

test "settings error catalog limits match the real limits and never expose raw error names (settings-copy)" {
    const error_text = @import("../../../shared/base/error_text.zig");
    try std.testing.expectEqual(@as(usize, @import("../../../config/theme_registry.zig").max_import_bytes), error_text.theme_max_bytes);
    try std.testing.expectEqual(@as(usize, @import("../../../ai/mcp_client.zig").max_response_bytes), error_text.mcp_response_max_bytes);
    try std.testing.expectEqualStrings("导入失败：文件超过 2 MiB", error_text.theme(error.ThemeTooLarge).?.line);
    const ai_pane = @import("../model/ai_pane.zig");
    try std.testing.expectEqualStrings("MCP 响应超过 32 MiB", ai_pane.extensionError(error.McpResponseLimit));
    try std.testing.expectEqualStrings("一次只能导入一个技能，请只拖入一个技能文件或文件夹", ai_pane.extensionError(error.ImportOneSkillAtATime));
    try std.testing.expectEqualStrings("扩展操作未完成（详情见应用日志）", ai_pane.extensionError(error.SomethingNobodyMapped));
}
