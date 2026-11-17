//! `model/ids.zig` 对照 test_id 基线（`tools/arch/test_ids.baseline.txt` 中 `settings.`、`data.cleanup.` 前缀的全部条目）。
//! 下面两张表是基线在本包提交时的原样拷贝（测试模块不能 @embedFile 模块根之外的文件，V-1）；
//! 基线若因确认的改名而变化，须同步这里。
const std = @import("std");
const ids = @import("../model/ids.zig");
const catalog = @import("../model/catalog.zig");

const baseline_static = [_][]const u8{
    "data.cleanup.cancel",
    "data.cleanup.confirm",
    "data.cleanup.headline",
    "data.cleanup.message",
    "data.cleanup.modal",
    "settings.ai",
    "settings.ai.add_provider",
    "settings.ai.attachments",
    "settings.ai.behavior",
    "settings.ai.children",
    "settings.ai.context",
    "settings.ai.conversation",
    "settings.ai.delete.cancel",
    "settings.ai.delete.confirm",
    "settings.ai.delete.dialog",
    "settings.ai.delete.footer",
    "settings.ai.execution",
    "settings.ai.extensions",
    "settings.ai.mcp",
    "settings.ai.model.cancel",
    "settings.ai.model.capabilities.heading",
    "settings.ai.model.catalog",
    "settings.ai.model.catalog_status",
    "settings.ai.model.context",
    "settings.ai.model.context.source",
    "settings.ai.model.default",
    "settings.ai.model.dialog",
    "settings.ai.model.effort.high",
    "settings.ai.model.effort.low",
    "settings.ai.model.effort.max",
    "settings.ai.model.effort.medium",
    "settings.ai.model.effort.none",
    "settings.ai.model.effort.ultra",
    "settings.ai.model.effort.xhigh",
    "settings.ai.model.efforts",
    "settings.ai.model.error",
    "settings.ai.model.fetch_models",
    "settings.ai.model.footer",
    "settings.ai.model.id",
    "settings.ai.model.reasoning",
    "settings.ai.model.reasoning.no",
    "settings.ai.model.reasoning.yes",
    "settings.ai.model.save",
    "settings.ai.model.test",
    "settings.ai.model.test_status",
    "settings.ai.model.viewport",
    "settings.ai.model.vision",
    "settings.ai.model.vision.no",
    "settings.ai.model.vision.yes",
    "settings.ai.permissions",
    "settings.ai.provider_error",
    "settings.ai.provider_list",
    "settings.ai.provider_pane",
    "settings.ai.providers",
    "settings.ai.providers.empty",
    "settings.ai.providers.empty.add",
    "settings.ai.skills",
    "settings.appearance",
    "settings.appearance.aids",
    "settings.appearance.app_icon",
    "settings.appearance.font",
    "settings.appearance.help.cursor_style",
    "settings.appearance.help.icon_background",
    "settings.appearance.help.transparency",
    "settings.appearance.materials",
    "settings.appearance.mini_preview",
    "settings.appearance.preview",
    "settings.appearance.themes",
    "settings.background.choose",
    "settings.background.filename",
    "settings.background.identity",
    "settings.background.material.layer",
    "settings.background.material.surface",
    "settings.background.position_fields",
    "settings.background.preview",
    "settings.background.preview.image",
    "settings.background.remove",
    "settings.background.rotation_fields",
    "settings.background.state",
    "settings.child_context.independent",
    "settings.child_context.inherit",
    "settings.child_reuse.model",
    "settings.child_reuse.new",
    "settings.child_reuse.prefer_reuse",
    "settings.chooser.alignment",
    "settings.confirmation",
    "settings.confirmation.cancel",
    "settings.confirmation.close",
    "settings.confirmation.discard",
    "settings.confirmation.reset",
    "settings.confirmation.save",
    "settings.content",
    "settings.data",
    "settings.data.actions",
    "settings.data.clear_all",
    "settings.data.clear_logs",
    "settings.data.credential_help",
    "settings.data.export_logs",
    "settings.data.history",
    "settings.data.location",
    "settings.directory.label",
    "settings.directory.tooltip",
    "settings.extensions.cancel",
    "settings.extensions.detail",
    "settings.extensions.status",
    "settings.field.alignment",
    "settings.field.cursor_style",
    "settings.field.float_card_transition",
    "settings.field.font_family",
    "settings.field.icon_background",
    "settings.field.terminal_right_click",
    "settings.follow_up_mode.queue",
    "settings.follow_up_mode.steer",
    "settings.font.options",
    "settings.font.preview",
    "settings.font.preview.caret",
    "settings.font.preview.command",
    "settings.font.preview.multilingual",
    "settings.font.preview.prompt",
    "settings.font.status",
    "settings.footer",
    "settings.footer.state",
    "settings.header",
    "settings.header.title",
    "settings.header.traffic_lights",
    "settings.help",
    "settings.help.content",
    "settings.history",
    "settings.history.back",
    "settings.history.forward",
    "settings.island",
    "settings.keys",
    "settings.keys.tabs",
    "settings.keys.terminal",
    "settings.materials.header",
    "settings.materials.preview.actions",
    "settings.materials.preview.full",
    "settings.materials.preview.open",
    "settings.materials.preview.restore",
    "settings.materials.preview.return",
    "settings.materials.preview.save",
    "settings.mcp.add",
    "settings.mcp.apply",
    "settings.mcp.cancel",
    "settings.mcp.clear_env",
    "settings.mcp.clear_headers",
    "settings.mcp.http",
    "settings.mcp.stdio",
    "settings.nav.ai",
    "settings.nav.appearance",
    "settings.nav.data",
    "settings.nav.keys",
    "settings.nav.notifications",
    "settings.nav.plugins",
    "settings.nav.ssh",
    "settings.nav.transfer",
    "settings.nav.updates",
    "settings.navigation",
    "settings.navigation.note",
    "settings.navigation.scroll",
    "settings.notifications",
    "settings.notifications.attention",
    "settings.notifications.events",
    "settings.notifications.permission",
    "settings.notifications.permission.feedback",
    "settings.notifications.permission.info",
    "settings.notifications.permission.open",
    "settings.option.float_card_transition.anchor",
    "settings.option.float_card_transition.fade",
    "settings.option.font_family.custom",
    "settings.option.icon_background.dark",
    "settings.option.icon_background.light",
    "settings.option.icon_background.transparent",
    "settings.option.terminal_right_click.menu",
    "settings.option.terminal_right_click.paste",
    "settings.overlay",
    "settings.overview",
    // P3 3d 新增，同上。
    "settings.overview.hero",
    "settings.overview.list",
    "settings.page.intro",
    "settings.page.title",
    "settings.panel",
    "settings.plugins",
    "settings.plugins.builtin",
    "settings.plugins.builtin.body",
    "settings.plugins.bundled",
    "settings.plugins.bundled.body",
    "settings.record-cleanup",
    "settings.record-cleanup.cancel",
    "settings.record-cleanup.confirm",
    "settings.record-cleanup.detail",
    "settings.record-cleanup.headline",
    "settings.record-cleanup.receipt",
    "settings.reset",
    "settings.revert",
    "settings.save",
    "settings.search",
    "settings.search.results",
    // P3 3d 新增（外壳 / 概览），tools/arch/test_ids.baseline.txt 由主干合并时并入。
    "settings.search.slot",
    "settings.skills.add",
    "settings.skills.drop",
    "settings.skills.summary",
    "settings.skills.toolbar",
    "settings.ssh",
    "settings.ssh.authentication",
    "settings.ssh.connection",
    "settings.ssh.reconnect",
    "settings.ssh.socks",
    "settings.step_display.collapsed",
    "settings.step_display.expanded",
    "settings.term.custom.note",
    "settings.term.option.custom",
    "settings.theme.ansi",
    "settings.theme.catppuccin",
    "settings.theme.current",
    "settings.theme.delete.accept",
    "settings.theme.delete.cancel",
    "settings.theme.delete.confirm",
    "settings.theme.dracula",
    "settings.theme.import",
    "settings.theme.remove.current",
    "settings.theme.sauber",
    "settings.theme.strip",
    "settings.transfer",
    "settings.transfer.connection",
    "settings.transfer.defaults",
    "settings.transfer.engine",
    "settings.updates",
    "settings.updates.badge",
    "settings.updates.channel",
    "settings.updates.last_check",
    "settings.updates.open",
    "settings.updates.preferences",
    "settings.updates.source",
    "settings.updates.version",
    "settings.updates.version_text",
    "settings.viewport",
    "settings.window",
};
const baseline_prefixes = [_][]const u8{
    "settings.ai.model.catalog.option.",
    "settings.ai.provider.",
    "settings.alignment.",
    "settings.appearance.help.",
    "settings.chooser.",
    "settings.error.",
    "settings.field.",
    "settings.help.",
    "settings.help.content.",
    "settings.key.",
    "settings.key.fixed.",
    "settings.key.row.",
    "settings.key.tooltip.",
    "settings.mcp.",
    "settings.mcp.field.",
    "settings.option.",
    "settings.option.font_family.",
    "settings.overview.",
    "settings.path.",
    "settings.plugin.",
    "settings.row.",
    "settings.skill.",
    "settings.slider.",
    "settings.term.option.",
    "settings.theme.",
    "settings.theme.menu.",
    "settings.theme.remove.",
    "settings.toggle.",
};

test "settings ids cover every baseline settings and data.cleanup static id" {
    for (baseline_static) |id| {
        if (!ids.isStatic(id)) {
            std.debug.print("missing static id {s}\n", .{id});
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(baseline_static.len, ids.static.len);
}

test "settings ids cover every baseline settings and data.cleanup prefix" {
    for (baseline_prefixes) |prefix| {
        if (!ids.isPrefix(prefix)) {
            std.debug.print("missing prefix {s}\n", .{prefix});
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(baseline_prefixes.len, ids.prefixes.len);
}

test "settings ids named constants are baseline ids" {
    const named = [_][]const u8{
        ids.window,          ids.panel,            ids.navigation,         ids.navigation_scroll, ids.navigation_note,
        ids.header,          ids.header_title,     ids.header_traffic_lights, ids.island,         ids.search,
        ids.search_results,  ids.content,          ids.viewport,           ids.page_intro,        ids.page_title,
        ids.help,            ids.help_content,     ids.history,            ids.history_back,      ids.history_forward,
        ids.overview,        ids.overview_list,    ids.footer,             ids.footer_state,
        ids.save,            ids.revert,           ids.reset,              ids.confirmation,      ids.confirmation_cancel,
        ids.confirmation_discard, ids.confirmation_save, ids.confirmation_reset, ids.confirmation_close,
    };
    for (named) |id| try std.testing.expect(ids.isStatic(id));
    for ([_][]const u8{ ids.field_prefix, ids.overview_prefix }) |prefix| try std.testing.expect(ids.isPrefix(prefix));
}

test "settings ids generate the same dynamic strings as the legacy views" {
    // settings_shell.nav_ids 原先的字面量表。
    const legacy_nav = [_][]const u8{ "settings.nav.appearance", "settings.nav.keys", "settings.nav.ssh", "settings.nav.transfer", "settings.nav.ai", "settings.nav.plugins", "settings.nav.notifications", "settings.nav.data", "settings.nav.updates" };
    for (legacy_nav, ids.nav) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
        try std.testing.expect(ids.isStatic(actual));
    }
    // settings_content_view.mountOverview：bufPrint("settings.overview.{s}.{s}") 与 stableId(row_id, ".summary")。
    var rows: usize = 0;
    for (catalog.categories, 0..) |category, page| {
        for (category.subpages, 0..) |sub, index| {
            var buffer: [96]u8 = undefined;
            const row = try std.fmt.bufPrint(&buffer, "settings.overview.{s}.{s}", .{ category.slug, sub.slug });
            const generated = ids.overviewRow(page, index).?;
            try std.testing.expectEqualStrings(row, generated.row);
            var summary_buffer: [128]u8 = undefined;
            try std.testing.expectEqualStrings(try std.fmt.bufPrint(&summary_buffer, "{s}{s}", .{ row, ".summary" }), generated.summary);
            rows += 1;
        }
        try std.testing.expectEqual(@as(?ids.OverviewIds, null), ids.overviewRow(page, category.subpages.len));
    }
    try std.testing.expectEqual(@as(usize, 18), rows);
    try std.testing.expectEqual(@as(?ids.OverviewIds, null), ids.overviewRow(catalog.categories.len, 0));
    // panes/settings_controls.zig：stableId(scope, "settings.field.", key.key)。
    try std.testing.expectEqualStrings("settings.field.font_family", ids.field("font_family"));
    var field_buffer: [64]u8 = undefined;
    for (catalog.pages.keys) |key| {
        var expected: [64]u8 = undefined;
        try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "{s}{s}", .{ "settings.field.", key.key }), try ids.fieldInto(&field_buffer, key.key));
    }
    for ([_][]const u8{ "settings.field.alignment", "settings.field.cursor_style", "settings.field.font_family", "settings.field.icon_background" }) |id| {
        try std.testing.expect(ids.isStatic(id));
        try std.testing.expect(std.mem.startsWith(u8, id, ids.field_prefix));
    }
    // 面板根 id 来自目录，且都是登记过的静态 id。
    for (catalog.categories, 0..) |category, page| for (0..category.subpages.len) |index| {
        for (ids.sections(page, @intCast(index))) |id| try std.testing.expect(ids.isStatic(id));
    };
    try std.testing.expectEqual(@as(usize, 0), ids.sections(1, 0).len);
}
