//! 设置窗口的目录：分类 → 子页面 → 面板（Island B v3 设置改版：`p6ZVS`/`lVMiW`/
//! `ClNai`/`M9sJf`/`wrTdG`/`L28sw` 概览与它们的 `›` 子页面）。
//!
//! 有子页面的分类先打开概览（hero + 每个子页面一行）；子页面只显示这里列出的面板，
//! 面板以其根节点的 test_id 识别。没有子页面的分类（快捷键 / 协议插件 / 关于与更新）
//! 照设计直接显示全部面板。
//!
//! 本文件不依赖 zenit `ui`：图标以 `IconId` 记录（枚举名与 `ui.icons` 的声明名一致），
//! 由视图层 `view/settings_subpages.zig` 映射成 `ui.SvgAsset`。
const std = @import("std");
const format = @import("../../../shared/base/format.zig");

// ── 视图需要的 core 模块，经 model 重新导出（view 不直接 import core，ARCHITECTURE_PLAN §4.2）──
pub const config = @import("../../../config/config.zig");
pub const pages = @import("../../../config/settings_pages.zig");
pub const schema = @import("../../../config/settings_schema.zig");
pub const keybindings = @import("../../../config/keybindings.zig");
pub const terminal_types = @import("../../../vt/terminal_type.zig");
pub const window_policy = @import("../../../transfer/window_policy.zig");
/// 搜索别名（每个分类一行产品词与 schema 键），与目录同属静态数据。
pub const search = @import("settings_search.zig");

const history_mod = @import("settings_history.zig");
pub const Location = history_mod.Location;
pub const History = history_mod.History;

/// 概览行摘要：读当前草稿值，写进调用方缓冲区。
pub const Summary = *const fn (config.Config, []u8) anyerror![]const u8;

/// 目录里用到的图标；枚举名即 `ui.icons` 里的声明名。
pub const IconId = enum {
    palette,
    type,
    square_terminal,
    keyboard,
    network,
    waypoints,
    rotate_ccw,
    shield,
    arrow_down_up,
    server,
    folder,
    sparkles,
    plug,
    bell,
    moon,
    database,
    history,
    file_text,
    refresh_cw,
};

pub const Subpage = struct {
    title: []const u8,
    icon: IconId,
    /// 稳定的自动化后缀：`settings.overview.<page>.<slug>`。
    slug: []const u8,
    /// 本子页面显示的面板根（面板 test_id），按页面顺序。
    sections: []const []const u8,
    /// 本子页面编辑的 `section.key` 字段（校验问题 → 子页面）。
    keys: []const []const u8 = &.{},
    summary: Summary,
};

pub const Category = struct {
    /// Hero 图标（`C6Mjq` 56 方块、28 图标）与 hero 说明。
    icon: IconId,
    description: []const u8,
    slug: []const u8,
    subpages: []const Subpage = &.{},
};

/// 与 `settings_pages.pages` 同序。
pub const categories = [_]Category{
    .{ .icon = .palette, .slug = "appearance", .description = "主题、背景与终端显示；保存后全局生效。", .subpages = &.{
        .{ .title = "主题", .icon = .palette, .slug = "theme", .sections = &.{ "settings.appearance.themes", "settings.appearance.app_icon", "settings.appearance.materials", "settings.appearance.preview" }, .keys = &.{ "ui.theme", "ui.icon_background", "ui.materials.blur_px", "ui.materials.background.enabled", "ui.materials.background.path", "ui.materials.background.source", "ui.materials.background.order", "ui.materials.background.interval_minutes", "ui.materials.background.fit", "ui.materials.background.alignment_x", "ui.materials.background.alignment_y", "ui.materials.background.transparency" }, .summary = themeSummary },
        .{ .title = "字体与排版", .icon = .type, .slug = "font", .sections = &.{"settings.appearance.font"}, .keys = &.{ "ui.font_family", "ui.font_size", "ui.font_weight", "ui.line_height", "ui.cursor_style" }, .summary = fontSummary },
        .{ .title = "终端与工作区", .icon = .square_terminal, .slug = "terminal", .sections = &.{"settings.appearance.aids"}, .keys = &.{ "ui.scrollback_limit", "ui.timestamp_gutter", "ui.sidebar_collapsed", "ui.input_line_highlight", "ui.command_info", "completion.enabled", "ui.terminal_right_click", "ui.float_card_transition" }, .summary = terminalSummary },
    } },
    .{ .icon = .keyboard, .slug = "keys", .description = "逐项录制应用快捷键；Tab 与 Control 保留给远端。" },
    .{ .icon = .network, .slug = "ssh", .description = "连接、重连与认证默认值；保存后用于后续连接。", .subpages = &.{
        .{ .title = "连接", .icon = .network, .slug = "connection", .sections = &.{"settings.ssh.connection"}, .keys = &.{ "ssh.keepalive_sec", "ssh.connect_timeout_sec", "ssh.term", "ssh.compression", "ssh.auto_shell_integration" }, .summary = connectionSummary },
        .{ .title = "SOCKS5 转发", .icon = .waypoints, .slug = "socks", .sections = &.{"settings.ssh.socks"}, .keys = &.{ "ssh.socks_port", "ssh.socks_bind" }, .summary = socksSummary },
        .{ .title = "断线重连", .icon = .rotate_ccw, .slug = "reconnect", .sections = &.{"settings.ssh.reconnect"}, .keys = &.{ "ssh.auto_reconnect", "ssh.reconnect_max", "ssh.reconnect_backoff", "ssh.buffer_input" }, .summary = reconnectSummary },
        .{ .title = "双因素认证", .icon = .shield, .slug = "authentication", .sections = &.{"settings.ssh.authentication"}, .keys = &.{ "ssh.otp_modal", "ssh.totp_autofill" }, .summary = authenticationSummary },
    } },
    .{ .icon = .arrow_down_up, .slug = "transfer", .description = "用于新传输任务，正在运行的任务保留原设置。", .subpages = &.{
        .{ .title = "连接隔离", .icon = .network, .slug = "connection", .sections = &.{"settings.transfer.connection"}, .keys = &.{ "transfer.dedicated_connection", "transfer.shared_pacing_kbps" }, .summary = isolationSummary },
        .{ .title = "SFTP 引擎", .icon = .server, .slug = "engine", .sections = &.{"settings.transfer.engine"}, .keys = &.{ "transfer.window_chunks", "transfer.chunk_kb", "transfer.max_tasks", "transfer.resume", "transfer.verify_md5" }, .summary = engineSummary },
        .{ .title = "默认行为", .icon = .folder, .slug = "defaults", .sections = &.{"settings.transfer.defaults"}, .keys = &.{ "transfer.download_dir", "transfer.conflict_policy" }, .summary = transferDefaultsSummary },
    } },
    .{ .icon = .sparkles, .slug = "ai", .description = "配置服务提供方、模型与权限；助手始终作用于原会话。", .subpages = &.{
        .{ .title = "服务提供方", .icon = .sparkles, .slug = "providers", .sections = &.{"settings.ai.providers"}, .summary = providersSummary },
        .{ .title = "行为与权限", .icon = .shield, .slug = "behavior", .sections = &.{ "settings.ai.permissions", "settings.ai.execution", "settings.ai.conversation", "settings.ai.children", "settings.ai.context", "settings.ai.attachments", "settings.ai.behavior" }, .keys = &.{ "ai.permission_mode", "ai.execution_mode", "ai.session_retention", "ai.follow_up_mode", "ai.child_context_mode", "ai.child_reuse_policy", "ai.redact_ip", "ai.default_provider", "ai.step_display", "ai.error_hint" }, .summary = aiBehaviorSummary },
        .{ .title = "技能与 MCP", .icon = .plug, .slug = "extensions", .sections = &.{"settings.ai.extensions"}, .summary = extensionsSummary },
    } },
    .{ .icon = .plug, .slug = "plugins", .description = "查看内置协议服务。" },
    .{ .icon = .bell, .slug = "notifications", .description = "事件提醒、标签圆点与勿扰时段。", .subpages = &.{
        .{ .title = "事件提醒", .icon = .bell, .slug = "events", .sections = &.{"settings.notifications.events"}, .keys = &.{ "notify.transfer_done", "notify.reconnect", "notify.ai_ready", "notify.bell" }, .summary = eventsSummary },
        .{ .title = "注意标记与勿扰", .icon = .moon, .slug = "attention", .sections = &.{"settings.notifications.attention"}, .keys = &.{ "notify.tab_dot", "notify.quiet_hours" }, .summary = attentionSummary },
    } },
    .{ .icon = .database, .slug = "data", .description = "本地配置、会话记录、日志导出与清理。", .subpages = &.{
        .{ .title = "位置与凭据", .icon = .folder, .slug = "location", .sections = &.{"settings.data.location"}, .summary = locationSummary },
        .{ .title = "会话记录", .icon = .history, .slug = "history", .sections = &.{"settings.data.history"}, .keys = &.{ "log.ring_mb", "log.checkpoint_sec", "log.retention_days", "log.export_format" }, .summary = historySummary },
        .{ .title = "导出与清理", .icon = .file_text, .slug = "actions", .sections = &.{"settings.data.actions"}, .summary = actionsSummary },
    } },
    .{ .icon = .refresh_cw, .slug = "updates", .description = "应用版本、自动检查与安全安装更新。" },
};

comptime {
    std.debug.assert(categories.len == pages.pages.len);
    std.debug.assert(categories.len == search.page_terms.len);
    for (categories, history_mod.subpage_counts) |category, count| std.debug.assert(category.subpages.len == count);
    // 子页是运行时数据的分类（协议插件，F-set-plugins）：静态表里没有子页（也就没有概览）。
    std.debug.assert(std.mem.eql(u8, categories[history_mod.dynamic_page].slug, "plugins") and categories[history_mod.dynamic_page].subpages.len == 0);
}

/// 分类标题（左侧导航与概览 hero）。
pub fn title(page: usize) []const u8 {
    return pages.pages[page].name;
}
pub fn subpages(page: usize) []const Subpage {
    return if (page < categories.len) categories[page].subpages else &.{};
}
pub fn hasOverview(page: usize) bool {
    return subpages(page).len != 0;
}
pub fn get(page: usize, sub: ?u8) ?Subpage {
    const index = sub orelse return null;
    const list = subpages(page);
    return if (index < list.len) list[index] else null;
}
/// 某个面板（面板根 test_id）是否属于该子页面。
pub fn contains(subpage: Subpage, section_id: []const u8) bool {
    for (subpage.sections) |id| if (std.mem.eql(u8, id, section_id)) return true;
    return false;
}
/// 编辑 `section.key` 的子页面，用于跳到校验问题所在处。
pub fn forKey(page: usize, section: []const u8, key: []const u8) ?u8 {
    var buffer: [96]u8 = undefined;
    const name = std.fmt.bufPrint(&buffer, "{s}.{s}", .{ section, key }) catch return null;
    for (subpages(page), 0..) |subpage, index| {
        for (subpage.keys) |candidate| if (std.mem.eql(u8, candidate, name)) return @intCast(index);
    }
    return null;
}

// 概览行摘要（`F6n7A` 等）：读实时草稿值，从不放示例数据。

fn onOff(value: bool, on: []const u8, off: []const u8) []const u8 {
    return if (value) on else off;
}
fn themeSummary(value: config.Config, buffer: []u8) ![]const u8 {
    const background = if (value.ui.materials.background.enabled) "背景图片已开启" else "无背景图片";
    return std.fmt.bufPrint(buffer, "{s} · {s}", .{ value.ui.theme, background });
}
fn cursorName(style: []const u8) []const u8 {
    if (std.mem.eql(u8, style, "bar")) return "竖线光标";
    if (std.mem.eql(u8, style, "underline")) return "下划线光标";
    return "方块光标";
}
fn fontSummary(value: config.Config, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "{s} · {d} pt · 行高 {d} · {s}", .{ value.ui.font_family, value.ui.font_size, value.ui.line_height, cursorName(value.ui.cursor_style) });
}
fn terminalSummary(value: config.Config, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "回滚 {d} 行 · {s} · {s}", .{ value.ui.scrollback_limit, onOff(value.ui.timestamp_gutter, "显示时间戳", "不显示时间戳"), onOff(value.completion.enabled, "命令补全", "无命令补全") });
}
fn connectionSummary(value: config.Config, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "超时 {d} 秒 · 保活 {d} 秒 · {s}", .{ value.ssh.connect_timeout_sec, value.ssh.keepalive_sec, value.ssh.term });
}
fn socksSummary(value: config.Config, buffer: []u8) ![]const u8 {
    const scope = if (std.mem.eql(u8, value.ssh.socks_bind, "127.0.0.1")) "仅本机" else "允许局域网";
    return std.fmt.bufPrint(buffer, "{s} · 默认端口 {d} · {s}", .{ value.ssh.socks_bind, value.ssh.socks_port, scope });
}
fn reconnectSummary(value: config.Config, buffer: []u8) ![]const u8 {
    if (!value.ssh.auto_reconnect) return "已关闭自动重连";
    return std.fmt.bufPrint(buffer, "自动重连 · 最多 {d} 次 · {s}", .{ value.ssh.reconnect_max, onOff(value.ssh.buffer_input, "缓存断线期间输入", "不缓存输入") });
}
fn authenticationSummary(value: config.Config, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "{s} · {s}", .{ onOff(value.ssh.otp_modal, "专用验证码表单", "终端内输入"), onOff(value.ssh.totp_autofill, "TOTP 自动填充", "不自动填充") });
}
fn isolationSummary(value: config.Config, buffer: []u8) ![]const u8 {
    const connection = onOff(value.transfer.dedicated_connection, "独立传输连接", "共享终端连接");
    if (value.transfer.shared_pacing_kbps == 0) return std.fmt.bufPrint(buffer, "{s} · 共享通道不限速", .{connection});
    // 配置值按 KiB/s 计（传输限速 `transfer_pacer` 按 × 1024 字节每秒换算）；显示按 `shared/base/format`。
    var rate: format.Buffer = undefined;
    return std.fmt.bufPrint(buffer, "{s} · 共享通道 {s}", .{ connection, format.rate(&rate, @as(u64, value.transfer.shared_pacing_kbps) * 1024) });
}
fn engineSummary(value: config.Config, buffer: []u8) ![]const u8 {
    // 配置值按 KiB（1024 字节）计；显示按 `shared/base/format`（IEC：“64 KiB”）。
    var size: format.Buffer = undefined;
    return std.fmt.bufPrint(buffer, "{d} × {s} · {d} 并发{s}", .{ value.transfer.window_chunks, format.bytes(&size, @as(u64, value.transfer.chunk_kb) * 1024), value.transfer.max_tasks, onOff(value.transfer.verify_md5, " · MD5 校验", "") });
}
fn transferDefaultsSummary(value: config.Config, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "{s} · 同名文件每次询问", .{value.transfer.download_dir});
}
fn providersSummary(value: config.Config, buffer: []u8) ![]const u8 {
    if (value.ai.provider_count == 0) return "尚未配置";
    return std.fmt.bufPrint(buffer, "{d} 个 · 默认 {s}", .{ value.ai.provider_count, value.ai.default_provider });
}
fn aiBehaviorSummary(value: config.Config, buffer: []u8) ![]const u8 {
    const permission = if (value.ai.permission_mode == .auto) "自动执行" else "确认后执行";
    return std.fmt.bufPrint(buffer, "{s} · {s} · {s}", .{ permission, config.executionModeLabel(value.ai.execution_mode), onOff(value.ai.redact_ip, "隐藏连接身份", "发送连接身份") });
}
fn extensionsSummary(_: config.Config, _: []u8) ![]const u8 {
    return "本地技能与 MCP 服务";
}
fn eventsSummary(value: config.Config, buffer: []u8) ![]const u8 {
    const enabled = @as(u8, @intFromBool(value.notify.transfer_done)) + @intFromBool(value.notify.reconnect) + @intFromBool(value.notify.ai_ready) + @intFromBool(value.notify.bell);
    return std.fmt.bufPrint(buffer, "{d} / 4 类事件已开启", .{enabled});
}
fn attentionSummary(value: config.Config, buffer: []u8) ![]const u8 {
    const dot = onOff(value.notify.tab_dot, "标签圆点", "无标签圆点");
    const time = value.notify.quiet_hours;
    if (time.len != 11) return std.fmt.bufPrint(buffer, "{s} · 勿扰关闭", .{dot});
    return std.fmt.bufPrint(buffer, "{s} · 勿扰 {s}–{s}", .{ dot, time[0..5], time[6..11] });
}
fn locationSummary(_: config.Config, _: []u8) ![]const u8 {
    return "本机存储 · macOS 钥匙串";
}
fn historySummary(value: config.Config, buffer: []u8) ![]const u8 {
    // 配置值按 1024 × 1024 字节计（与 `session_runtime` 一致）；显示按 `shared/base/format`。
    var size: format.Buffer = undefined;
    return std.fmt.bufPrint(buffer, "缓冲 {s} · 每 {d} 秒快照 · 保留 {d} 天", .{ format.bytes(&size, @as(u64, value.log.ring_mb) * 1024 * 1024), value.log.checkpoint_sec, value.log.retention_days });
}
fn actionsSummary(_: config.Config, _: []u8) ![]const u8 {
    return "导出诊断日志 · 清理会话记录 · 清除全部数据";
}
