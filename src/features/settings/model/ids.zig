//! 设置窗口的 test_id 表（ARCHITECTURE_PLAN §4.5、§6.3）。
//!
//! test_id 是公开接口，全部冻结（D12）：这里登记现有字符串，不改名；P3 3d 只新增了外壳 / 概览的
//! `settings.search.slot`、`settings.overview.hero` 两条（基线由主干合并时并入）。
//! - 主链路（外壳、页头、历史、概览、Save Bar、确认弹窗）用具名常量，供 view-model 与将来的 `.yix` 引用；
//! - 动态 id 由纯函数 / comptime 表生成，生成结果与旧视图拼出来的字符串逐字节相同
//!   （`settings.nav.<slug>`、`settings.overview.<category>.<subpage>[.summary]`、`settings.field.<key>`）；
//! - `static` / `prefixes` 是 `tools/arch/test_ids.baseline.txt` 里 `settings.`、`data.cleanup.` 前缀条目的完整清单，
//!   由 `tests/ids_tests.zig` 逐条对照基线。
//! 本文件不依赖 zenit `ui`。
const std = @import("std");
const catalog = @import("catalog.zig");

// ── 窗口外壳（settings_shell.mount 与 SettingsHost.mountWindow）──
pub const window = "settings.window";
pub const panel = "settings.panel";
pub const navigation = "settings.navigation";
pub const navigation_scroll = "settings.navigation.scroll";
pub const navigation_note = "settings.navigation.note";
pub const header = "settings.header";
pub const header_title = "settings.header.title";
pub const header_traffic_lights = "settings.header.traffic_lights";
pub const island = "settings.island";
pub const search = "settings.search";
pub const search_results = "settings.search.results";
/// 搜索槽（P3 3d 新增，未入 tools/arch 基线）：包住搜索框的 fill × 28 盒子。
pub const search_slot = "settings.search.slot";

// ── 内容区（settings_content_view.mountPage）──
pub const content = "settings.content";
pub const viewport = "settings.viewport";
pub const page_intro = "settings.page.intro";
pub const page_title = "settings.page.title";
pub const help = "settings.help";
pub const help_content = "settings.help.content";
pub const history = "settings.history";
pub const history_back = "settings.history.back";
pub const history_forward = "settings.history.forward";
pub const overview = "settings.overview";
pub const overview_list = "settings.overview.list";
/// 概览 hero 区（`HiaCV`；P3 3d 新增，未入 tools/arch 基线）。
pub const overview_hero = "settings.overview.hero";

// ── Save Bar ──
pub const footer = "settings.footer";
pub const footer_state = "settings.footer.state";
pub const save = "settings.save";
pub const revert = "settings.revert";
pub const reset = "settings.reset";

// ── 未保存 / 恢复默认 确认弹窗（SettingsHost.showDecision）──
pub const confirmation = "settings.confirmation";
/// 删除导入主题的原生确认框（`shared/ui/confirm`）：也是它在 `popup` 信号里的标识。
pub const theme_delete = "settings.theme.delete.confirm";
pub const theme_delete_cancel = "settings.theme.delete.cancel";
pub const theme_delete_accept = "settings.theme.delete.accept";
pub const confirmation_cancel = "settings.confirmation.cancel";
pub const confirmation_discard = "settings.confirmation.discard";
pub const confirmation_save = "settings.confirmation.save";
pub const confirmation_reset = "settings.confirmation.reset";
/// 原生 Modal 标题栏的关闭钮（结果部件 `close_button`）。
pub const confirmation_close = "settings.confirmation.close";

// ── 动态 id ──
pub const field_prefix = "settings.field.";
pub const nav_prefix = "settings.nav.";
pub const overview_prefix = "settings.overview.";
pub const summary_suffix = ".summary";

/// 左侧导航行，`settings_pages.pages` 同序：`settings.nav.<分类 slug>`。
pub const nav = [_][]const u8{ "settings.nav.appearance", "settings.nav.keys", "settings.nav.ssh", "settings.nav.transfer", "settings.nav.ai", "settings.nav.plugins", "settings.nav.notifications", "settings.nav.data", "settings.nav.updates" };
comptime {
    std.debug.assert(nav.len == catalog.categories.len);
    for (nav, catalog.categories) |id, category| std.debug.assert(std.mem.eql(u8, id, nav_prefix ++ category.slug));
}

/// `settings.field.<key>`（编译期 key）。
pub fn field(comptime key: []const u8) []const u8 {
    return field_prefix ++ key;
}
/// 设置行根：`settings.row.<key>`；行内校验提示：`settings.error.<key>`（编译期 key，P3 3c）。
pub fn settingRow(comptime key: []const u8) []const u8 {
    return "settings.row." ++ key;
}
pub fn fieldError(comptime key: []const u8) []const u8 {
    return "settings.error." ++ key;
}
/// `settings.field.<key>`（运行期 key），写进调用方缓冲区。
pub fn fieldInto(buffer: []u8, key: []const u8) error{NoSpaceLeft}![]const u8 {
    return std.fmt.bufPrint(buffer, field_prefix ++ "{s}", .{key});
}

/// 概览行：`settings.overview.<分类 slug>.<子页面 slug>`；摘要再接 `.summary`。
pub const OverviewIds = struct { row: []const u8, summary: []const u8 };
const overview_table = blk: {
    var rows: [catalog.categories.len][]const OverviewIds = undefined;
    for (catalog.categories, 0..) |category, page| {
        var list: [category.subpages.len]OverviewIds = undefined;
        for (category.subpages, 0..) |sub, index| {
            const row = overview_prefix ++ category.slug ++ "." ++ sub.slug;
            list[index] = .{ .row = row, .summary = row ++ summary_suffix };
        }
        const final = list;
        rows[page] = &final;
    }
    break :blk rows;
};
/// 某分类第 `sub` 个子页面的概览行 id；越界返回 null。
pub fn overviewRow(page: usize, sub: usize) ?OverviewIds {
    if (page >= overview_table.len or sub >= overview_table[page].len) return null;
    return overview_table[page][sub];
}

/// 子页面里的面板根 id 直接来自目录（`catalog.Subpage.sections`）。
pub fn sections(page: usize, sub: u8) []const []const u8 {
    const subpage = catalog.get(page, sub) orelse return &.{};
    return subpage.sections;
}

/// 运行期拼接 id 用到的前缀（基线里的 `prefix:` 条目）。
pub const prefixes = [_][]const u8{
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

/// 源码里定义的全部静态 id（基线里不带 `prefix:` 的条目）。
pub const static = [_][]const u8{
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

/// `id` 是否是登记过的静态 id。
pub fn isStatic(id: []const u8) bool {
    for (static) |candidate| if (std.mem.eql(u8, candidate, id)) return true;
    return false;
}
/// `prefix` 是否是登记过的前缀。
pub fn isPrefix(prefix: []const u8) bool {
    for (prefixes) |candidate| if (std.mem.eql(u8, candidate, prefix)) return true;
    return false;
}
