const std = @import("std");
const actions = @import("../../../host/actions.zig");
const capabilities = @import("../../../host/capability_snapshot.zig");
/// 菜单项右侧的快捷键文字只从快捷键路由取（`key`），随 `[keys]` 变化；`shortcut` 只放不是按键组合的说明（@ts、手势）。
const shell = @import("../../shell/mod.zig");
const shortcut_router = shell.shortcut_router;
/// 菜单的声明与排列规则（menus 包）：本文件只声明条目，排列、分隔线、快捷键文字都在 `menu_spec`。
pub const menu_spec = shell.menu_spec;
pub const Entry = menu_spec.Entry;
pub const Shortcut = shortcut_router.Command;

/// `group_tab`：会话组页签菜单（并入同一份声明，不再在 workspace 里硬编码）。
pub const Kind = enum { terminal, host_asset, session_ended, tab, group_tab };
pub const Action = enum {
    ask_ai,
    copy,
    paste,
    upload_file,
    download_file,
    toggle_block_selection,
    toggle_timestamp,
    history,
    command_history,
    search,
    export_selection,
    new_tab,
    open_in_current_group,
    duplicate_into_group,
    new_window,
    reuse_connection,
    clone_host,
    edit_host,
    save_host,
    pin_host,
    move_group,
    delete_host,
    reconnect,
    close_session,
    // Tab (page) context menu, mockup-tab-context.
    join_session_group,
    rename_tab,
    tab_color,
    clone_session,
    view_jump_chain,
    /// 会话连接卡片（title-click）：原先悬停在当前页签上弹出，现在从页签菜单点击打开。
    session_identity,
    export_session,
    close_others,
    start_background_socks,
    manage_background_socks,
    /// 清屏（终端右键菜单，design-r3 B1）：向会话发送 ⌃L，由 shell / 全屏程序自己清屏重绘，与键入 ⌃L 相同。
    clear_screen,
    /// 会话组页签菜单：全部左右 / 上下排列（由 workspace 对捕获的组执行）。
    arrange_side,
    arrange_stack,
};

pub const Item = struct {
    action: Action,
    label: []const u8,
    /// lucide 图标名（`ui.icons.get`）。
    icon: []const u8,
    /// 快捷键命令：文字由路由给出（`menu_spec.shortcutText`）。
    key: ?Shortcut = null,
    /// 不是按键组合的说明文字（@ts、手势）。
    shortcut: ?[]const u8 = null,
    /// 分组序号（`menu_spec.arrange`：组号小的在前，组间分隔线，危险项最后）。
    group: u8 = 0,
    danger: bool = false,
};

pub fn isVisible(action: Action, context: Context) bool {
    if (action == .duplicate_into_group and !context.single_session) return false;
    if (context.has_saved_connection) |saved| if (!saved and action == .edit_host) return false;
    if (action == .save_host and !context.has_unsaved_connection) return false;
    if (context.capability_snapshot) |snapshot| if (catalogAction(action)) |id| return actions.project(id, snapshot).visible;
    return true;
}
pub fn projection(action: Action, context: Context) ?capabilities.Projection {
    const snapshot = context.capability_snapshot orelse return null;
    return actions.project(catalogAction(action) orelse return null, snapshot);
}
/// The menu maps labels to the shared business catalog, never maintains a
/// second provider/capability table of its own.
fn catalogAction(action: Action) ?actions.ActionId {
    return switch (action) {
        .ask_ai => .toggle_ai,
        .copy => .copy,
        // 清屏与粘贴同属“向会话写输入”，可见 / 可用跟随同一能力。
        .paste, .clear_screen => .paste,
        .upload_file => .upload,
        .download_file => .download,
        .toggle_block_selection, .search => .search_terminal,
        .toggle_timestamp => .toggle_timestamp,
        .history => .open_history,
        .command_history => .open_history,
        .export_selection, .export_session => .export_record,
        .new_tab, .reuse_connection => .create_sibling_session,
        .edit_host => .edit_connection,
        .save_host => .save_connection,
        .reconnect => .reconnect,
        .close_session => .request_close,
        .join_session_group => .join_group,
        .rename_tab => .rename_tab,
        .clone_session, .duplicate_into_group => .duplicate_session,
        .view_jump_chain => .open_route_details,
        .close_others => .close_other_tabs,
        .start_background_socks, .manage_background_socks => .toggle_socks,
        else => null,
    };
}
pub fn isEnabled(action: Action, context: Context) bool {
    if (!isVisible(action, context)) return false;
    // 协议插件被禁用（Q5）：不能连接、不能用协议编辑器克隆；编辑（只改通用字段）、删除、置顶、移动分组照常。
    if (context.plugin_disabled) switch (action) {
        .new_tab, .new_window, .open_in_current_group, .clone_host, .start_background_socks, .manage_background_socks => return false,
        else => {},
    };
    if (projection(action, context)) |value| if (!value.enabled) return false;
    return switch (action) {
        .open_in_current_group => context.group_target_available,
        .duplicate_into_group => context.single_session and !context.read_only and !context.session_ended and
            (if (context.capability_snapshot) |snapshot| actions.project(.join_group, snapshot).enabled else true),
        .new_window => context.new_window_available,
        .reuse_connection => context.reuse_connection_available and !context.session_ended,
        .ask_ai, .copy, .export_selection => context.has_selection,
        .reconnect => context.session_ended,
        .paste, .clear_screen => !context.read_only,
        .upload_file, .download_file => (context.capability_snapshot != null or context.transfer_available) and !context.read_only and !context.session_ended,
        .join_session_group => !context.read_only and !context.session_ended,
        .close_others => context.multi_tabs,
        .start_background_socks => context.background_socks and !context.background_active,
        .manage_background_socks => context.background_socks and context.background_active,
        else => true,
    };
}

pub const Context = struct {
    capability_snapshot: ?capabilities.Snapshot = null,
    has_saved_connection: ?bool = null,
    has_unsaved_connection: bool = false,
    new_window_available: bool = false,
    reuse_connection_available: bool = false,
    local_session: bool = false,
    read_only: bool = false,
    has_selection: bool = false,
    session_ended: bool = false,
    /// Tab menu: "关闭其他页签" needs more than one open tab.
    multi_tabs: bool = false,
    transfer_available: bool = false,
    background_socks: bool = false,
    background_active: bool = false,
    group_target_available: bool = false,
    single_session: bool = false,
    /// 主机的协议插件被禁用（Q5，RfJyL）：连接类菜单项置灰；“编辑”“删除”保留。
    plugin_disabled: bool = false,
};


/// 不可用的原因（菜单行标题后显示，也是无障碍描述）；可用或说不出具体原因时为 null。
pub fn disabledReason(action: Action, context: Context) ?[]const u8 {
    if (isEnabled(action, context)) return null;
    if (context.plugin_disabled) switch (action) {
        .new_tab, .new_window, .open_in_current_group, .clone_host, .start_background_socks, .manage_background_socks => return "协议插件已禁用",
        else => {},
    };
    if (projection(action, context)) |value| if (!value.enabled and value.reason.len != 0) return value.reason;
    return switch (action) {
        .ask_ai, .copy, .export_selection => if (!context.has_selection) "未选中内容" else null,
        .paste, .clear_screen => if (context.read_only) "只读会话" else null,
        .upload_file, .download_file, .join_session_group, .duplicate_into_group, .reuse_connection => if (context.session_ended) "会话已结束" else if (context.read_only) "只读会话" else null,
        .close_others => "只有一个页签",
        .open_in_current_group => "没有可加入的会话组",
        else => null,
    };
}

/// 一次菜单的条目存放处（条目借用这里的字符串与子菜单）。
pub const Entries = struct {
    list: [menu_spec.max_rows]Entry = undefined,
    colors: [tab_colors.len + 2]Entry = undefined,
    header: [160]u8 = undefined,
    color_label: [48]u8 = undefined,
    count: usize = 0,

    fn add(self: *Entries, entry: Entry) void {
        if (self.count == self.list.len) return;
        self.list[self.count] = entry;
        self.count += 1;
    }
    pub fn slice(self: *const Entries) []const Entry {
        return self.list[0..self.count];
    }
};

/// 打开菜单时宿主补充的事实：主机名与置顶（侧栏主机菜单）、页签当前颜色（颜色子菜单）。
pub const Extra = struct {
    host_name: []const u8 = "",
    host_pinned: bool = false,
    tab_color: ?TabColor = null,
};

/// 右键菜单行的 test_id：`context.menu.<动作>`（面板是 `context.menu`）。
pub fn contextTestId(action: Action) []const u8 {
    return switch (action) {
        inline else => |value| "context.menu." ++ @tagName(value),
    };
}
/// 终端右键菜单行的 test_id：`terminal.menu.<动作>`（面板是 `terminal.menu`）。
pub fn rightClickTestId(action: Action) []const u8 {
    switch (action) {
        inline else => |tag| return "terminal.menu." ++ @tagName(tag),
    }
}
/// 会话组页签菜单行的 test_id（沿用 `groups.tab.*`）。
fn groupTabTestId(action: Action) []const u8 {
    return switch (action) {
        .rename_tab => "groups.tab.rename",
        .tab_color => "groups.tab.color",
        .close_session => "groups.tab.close",
        .arrange_side => "groups.tab.side",
        .arrange_stack => "groups.tab.stack",
        else => contextTestId(action),
    };
}

fn entryOf(item: Item, context: Context, test_id: []const u8) Entry {
    return .{
        .id = @tagName(item.action),
        .label = item.label,
        .icon = item.icon,
        .command = item.key,
        .note = item.shortcut,
        .disabled = !isEnabled(item.action, context),
        .disabled_reason = disabledReason(item.action, context),
        .danger = item.danger,
        .group = item.group,
        .test_id = test_id,
    };
}

/// “颜色：当前值 ›”的子菜单：跟随环境 · 6 种颜色 · 无，当前选中的一项打勾。会话组页签没有环境，“跟随环境”不可选。
fn colorEntry(out: *Entries, current: ?TabColor, follow_allowed: bool, test_id: []const u8) Entry {
    const choice = current orelse .follow;
    out.colors[0] = .{ .id = tab_color_id_prefix ++ "follow", .label = "跟随环境", .test_id = "tabs.color.follow", .icon = "circle-dashed", .selected = choice == .follow, .disabled_reason = if (follow_allowed) null else "会话组不适用" };
    inline for (tab_colors, 0..) |entry, index| {
        const hex = comptime std.fmt.comptimePrint("{x:0>6}", .{entry.rgb});
        out.colors[index + 1] = .{ .id = tab_color_id_prefix ++ hex, .label = entry.name, .test_id = "tabs.color." ++ hex, .icon = "circle", .tint = entry.rgb, .selected = choice == .rgb and choice.rgb == entry.rgb };
    }
    out.colors[tab_colors.len + 1] = .{ .id = tab_color_id_prefix ++ "none", .label = "无", .test_id = "tabs.color.none", .icon = "circle-off", .selected = choice == .none };
    return .{ .id = "tab_color", .label = tabColorLabel(&out.color_label, choice), .icon = "palette", .children = out.colors[0..], .test_id = test_id };
}

/// 菜单的条目（纯函数）：右键页签 / 会话组页签 / 侧栏主机 / 中键终端 / 会话结束。顺序、分组与危险项位置由
/// `menu_spec.arrange` 统一决定，这里只声明。看不见的项不出现；不可用的项置灰并写原因。
pub fn entries(kind: Kind, context: Context, extra: Extra, out: *Entries) []const Entry {
    out.count = 0;
    if (kind == .host_asset) {
        const title = std.fmt.bufPrint(&out.header, "主机 · {s}", .{if (extra.host_name.len != 0) extra.host_name else "主机"}) catch "主机";
        out.add(.{ .label = title, .kind = .header, .test_id = "context.menu.header" });
    }
    if (kind == .terminal and !context.local_session) out.add(.{ .label = "终端操作", .kind = .header, .test_id = "context.menu.header" });
    for (items(kind, context)) |item| {
        if (!isVisible(item.action, context)) continue;
        const test_id = if (kind == .group_tab) groupTabTestId(item.action) else contextTestId(item.action);
        if (item.action == .tab_color) {
            // Literal ids (the colour row is the one prefix-built id e2e names directly).
            const color_id = if (kind == .group_tab) "groups.tab.color" else "context.menu.tab_color";
            var color = colorEntry(out, extra.tab_color, kind != .group_tab, color_id);
            color.group = item.group;
            out.add(color);
            continue;
        }
        var entry = entryOf(item, context, test_id);
        if (item.action == .pin_host and extra.host_pinned) entry.label = "取消置顶";
        out.add(entry);
    }
    return out.slice();
}

/// 终端右键菜单（design-r3 B1，Pencil `BZBAu`；设置 › 终端与工作区 ›“右键行为 = 弹出菜单”）的条目（纯函数）。
/// 常用组按稿：粘贴 ⌘V / 查找… ⌘F / 复制 ⌘C（无选区时置灰，原因“未选中内容”）/ 清屏 ⌃L；有选区时“复制”排第一。
/// 之后是同一 `context` 下终端菜单（中键菜单）的其余项——问 AI、上传 / 下载、矩形块选、时间戳、命令历史、历史回溯、
/// 导出选中……——可见性、可用性都沿用本文件的表，组号整体后移一位（常用组之后）。
/// 清屏写 ⌃L 而不是稿里的 ⌘K：清屏就是向会话发送 ⌃L，⌘K 在 ZeroWork 里没有绑定，写上会是按了没反应的假提示。
pub fn rightClickEntries(context: Context, out: *Entries) []const Entry {
    out.count = 0;
    const copy_first = isEnabled(.copy, context);
    const paste: Item = .{ .action = .paste, .label = "粘贴", .icon = "clipboard", .key = .paste };
    const search: Item = .{ .action = .search, .label = "查找…", .icon = "search", .key = .search };
    const copy: Item = .{ .action = .copy, .label = "复制", .icon = "copy", .key = .copy };
    const clear: Item = .{ .action = .clear_screen, .label = "清屏", .icon = "eraser", .key = .clear_screen };
    const primary = if (copy_first) [_]Item{ copy, paste, search, clear } else [_]Item{ paste, search, copy, clear };
    for (primary) |item| if (isVisible(item.action, context)) out.add(entryOf(item, context, rightClickTestId(item.action)));
    for (items(.terminal, context)) |item| {
        switch (item.action) {
            .copy, .paste, .search, .clear_screen => continue,
            else => {},
        }
        if (!isVisible(item.action, context)) continue;
        var shifted = item;
        shifted.group = item.group + 1;
        out.add(entryOf(shifted, context, rightClickTestId(item.action)));
    }
    return out.slice();
}

test "right click menu: paste, find, copy (disabled with its reason), clear; copy leads with a selection" {
    var out: Entries = .{};
    const empty = rightClickEntries(.{}, &out);
    try std.testing.expectEqualStrings("paste", empty[0].id);
    try std.testing.expectEqualStrings("search", empty[1].id);
    try std.testing.expectEqualStrings("copy", empty[2].id);
    try std.testing.expect(empty[2].isDisabled());
    try std.testing.expectEqualStrings("复制", empty[2].label);
    try std.testing.expectEqualStrings("未选中内容", empty[2].disabled_reason.?);
    try std.testing.expectEqualStrings("clear_screen", empty[3].id);
    try std.testing.expectEqual(Shortcut.clear_screen, empty[3].command.?);
    const defaults: shortcut_router.Map = .{};
    try std.testing.expectEqualStrings("⌃L", menu_spec.shortcutText(empty[3], .{ .keys = &defaults }).?);
    for (empty[0..4]) |entry| try std.testing.expectEqual(@as(u8, 0), entry.group);
    for (empty[4..]) |entry| try std.testing.expect(entry.group > 0);
    var selected_out: Entries = .{};
    const selected = rightClickEntries(.{ .has_selection = true }, &selected_out);
    try std.testing.expectEqualStrings("copy", selected[0].id);
    try std.testing.expect(!selected[0].isDisabled());
    try std.testing.expectEqualStrings("terminal.menu.copy", selected[0].test_id);
}

test "right click menu keeps the other terminal menu items, Ask AI included, after the common group" {
    for ([_]Context{ .{ .has_selection = true }, .{ .has_selection = true, .local_session = true } }) |context| {
        var out: Entries = .{};
        const list = rightClickEntries(context, &out);
        var expected: usize = 0;
        for (items(.terminal, context)) |item| {
            if (item.action == .copy or item.action == .paste or item.action == .search) continue;
            if (!isVisible(item.action, context)) continue;
            try std.testing.expectEqualStrings(@tagName(item.action), list[4 + expected].id);
            try std.testing.expect(list[4 + expected].icon.len != 0 and isIconName(list[4 + expected].icon));
            expected += 1;
        }
        try std.testing.expectEqual(list.len, 4 + expected);
    }
    var out: Entries = .{};
    for (rightClickEntries(.{ .has_selection = true }, &out)) |entry| if (std.mem.eql(u8, entry.id, "ask_ai")) {
        try std.testing.expect(!entry.isDisabled());
        try std.testing.expectEqual(Shortcut.ai, entry.command.?);
    };
    var empty_out: Entries = .{};
    for (rightClickEntries(.{}, &empty_out)) |entry| if (std.mem.eql(u8, entry.id, "ask_ai")) try std.testing.expectEqualStrings("未选中内容", entry.disabled_reason.?);
}

test "read-only terminals keep copy and find but disable paste and clear with the reason" {
    var out: Entries = .{};
    const list = rightClickEntries(.{ .read_only = true, .has_selection = true, .local_session = true }, &out);
    try std.testing.expect(std.mem.eql(u8, list[0].id, "copy") and !list[0].isDisabled());
    try std.testing.expect(std.mem.eql(u8, list[1].id, "paste") and list[1].isDisabled());
    try std.testing.expectEqualStrings("只读会话", list[1].disabled_reason.?);
    try std.testing.expect(std.mem.eql(u8, list[2].id, "search") and !list[2].isDisabled());
    try std.testing.expect(std.mem.eql(u8, list[3].id, "clear_screen") and list[3].isDisabled());
    try std.testing.expectEqualStrings("terminal.menu.paste", rightClickTestId(.paste));
}

/// 每张表的图标都是 lucide 名字（小写字母、数字与连字符），不再混用 emoji 字符。
fn isIconName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |byte| if (!(std.ascii.isLower(byte) or std.ascii.isDigit(byte) or byte == '-')) return false;
    return true;
}

pub fn items(kind: Kind, context: Context) []const Item {
    return switch (kind) {
        .terminal => if (context.local_session) &local_terminal else &terminal_menu,
        .host_asset => if (context.background_socks) (if (context.background_active) &host_background_active else &host_background_available) else &host_asset,
        .session_ended => if (context.local_session) &local_tab else &session_ended,
        .tab => if (context.local_session) &local_tab else &tab_menu,
        .group_tab => &group_tab,
    };
}

/// Tab (page) context menu — mockup-tab-context: session lifecycle and per-tab configuration; deliberately
/// disjoint from terminal text actions. 常用组：重命名… / 颜色 ›（稿 3）；关闭页签是危险项，排在最后。
const tab_menu = [_]Item{
    .{ .action = .rename_tab, .label = "重命名…", .icon = "pencil", .key = .rename_tab },
    .{ .action = .tab_color, .label = "页签颜色", .icon = "palette" },
    .{ .action = .join_session_group, .label = "加入会话组…", .icon = "group", .group = 1 },
    .{ .action = .duplicate_into_group, .label = "复制并创建会话组", .icon = "panels-top-left", .group = 1 },
    .{ .action = .new_tab, .label = "新标签连接", .icon = "plus", .group = 1 },
    .{ .action = .reuse_connection, .label = "复用连接", .icon = "copy", .group = 1 },
    .{ .action = .new_window, .label = "新窗口连接", .icon = "app-window", .group = 1 },
    .{ .action = .edit_host, .label = "编辑主机配置", .icon = "settings", .group = 1 },
    .{ .action = .save_host, .label = "保存为主机", .icon = "save", .group = 1 },
    .{ .action = .view_jump_chain, .label = "通信链路", .icon = "network", .group = 1 },
    .{ .action = .session_identity, .label = "会话详情", .icon = "info", .group = 1 },
    .{ .action = .export_session, .label = "导出记录", .icon = "download", .group = 1 },
    .{ .action = .close_others, .label = "关闭其他页签", .icon = "x", .group = 1 },
    .{ .action = .close_session, .label = "关闭页签", .icon = "x", .key = .close_tab, .danger = true },
};

/// 会话组页签菜单（稿 3）：重命名…（F2）/ 颜色 ›（“跟随环境”不适用）/ 全部左右 · 上下排列 / 关闭页签（危险，最后）。
const group_tab = [_]Item{
    .{ .action = .rename_tab, .label = "重命名…", .icon = "pencil", .key = .rename_tab },
    .{ .action = .tab_color, .label = "页签颜色", .icon = "palette" },
    .{ .action = .arrange_side, .label = "全部左右排列", .icon = "columns-2", .group = 1 },
    .{ .action = .arrange_stack, .label = "全部上下排列", .icon = "rows-2", .group = 1 },
    .{ .action = .close_session, .label = "关闭页签", .icon = "x", .key = .close_tab, .danger = true },
};

// Mount delivered Local services only; never inherit remote asset operations.
const local_tab = [_]Item{
    .{ .action = .new_tab, .label = "新建本地会话", .icon = "plus" },
    .{ .action = .clone_session, .label = "复制会话与目录", .icon = "copy" },
    .{ .action = .rename_tab, .label = "重命名…", .icon = "pencil", .key = .rename_tab },
    .{ .action = .tab_color, .label = "页签颜色", .icon = "palette" },
    .{ .action = .join_session_group, .label = "加入会话组…", .icon = "group", .group = 1 },
    .{ .action = .duplicate_into_group, .label = "复制并创建会话组", .icon = "panels-top-left", .group = 1 },
    .{ .action = .command_history, .label = "命令历史", .icon = "list-restart", .key = .command_history, .group = 2 },
    .{ .action = .history, .label = "当前会话历史", .icon = "history", .group = 2 },
    .{ .action = .search, .label = "搜索终端", .icon = "search", .key = .search, .group = 2 },
    .{ .action = .export_session, .label = "导出会话记录", .icon = "download", .group = 2 },
    .{ .action = .session_identity, .label = "会话详情", .icon = "info", .group = 2 },
    .{ .action = .close_session, .label = "关闭页签", .icon = "x", .key = .close_tab, .danger = true },
};
const local_terminal = [_]Item{
    .{ .action = .copy, .label = "复制选区", .icon = "copy", .key = .copy },
    .{ .action = .paste, .label = "粘贴", .icon = "clipboard", .key = .paste },
    .{ .action = .toggle_block_selection, .label = "矩形选择", .icon = "text-select", .shortcut = shortcut_router.block_selection_gesture, .group = 1 },
    .{ .action = .toggle_timestamp, .label = "时间戳", .icon = "clock", .group = 1 },
    .{ .action = .command_history, .label = "命令历史", .icon = "list-restart", .key = .command_history, .group = 1 },
    .{ .action = .history, .label = "当前会话历史", .icon = "history", .group = 1 },
    .{ .action = .search, .label = "在终端中搜索", .icon = "search", .key = .search, .group = 2 },
    .{ .action = .export_selection, .label = "导出选中内容…", .icon = "download", .group = 2 },
    .{ .action = .duplicate_into_group, .label = "复制并创建会话组", .icon = "panels-top-left", .group = 3 },
};

/// 远程终端的中键菜单（有无选区同一张表，可用性随选区）。
const terminal_menu = [_]Item{
    .{ .action = .duplicate_into_group, .label = "复制并创建会话组", .icon = "panels-top-left" },
    .{ .action = .ask_ai, .label = "问 AI（附选中输出）", .icon = "sparkles", .key = .ai },
    .{ .action = .copy, .label = "复制", .icon = "copy", .key = .copy },
    .{ .action = .paste, .label = "粘贴", .icon = "clipboard", .key = .paste },
    .{ .action = .upload_file, .label = "上传文件", .icon = "upload" },
    .{ .action = .download_file, .label = "下载文件", .icon = "download" },
    .{ .action = .toggle_block_selection, .label = "矩形块选模式", .icon = "text-select", .shortcut = shortcut_router.block_selection_gesture, .group = 1 },
    .{ .action = .toggle_timestamp, .label = "时间戳侧栏", .icon = "clock", .shortcut = "@ts", .group = 1 },
    .{ .action = .command_history, .label = "命令历史", .icon = "list-restart", .key = .command_history, .group = 1 },
    .{ .action = .history, .label = "历史回溯", .icon = "history", .shortcut = "@log", .group = 1 },
    .{ .action = .search, .label = "在终端中搜索", .icon = "search", .key = .search, .group = 2 },
    .{ .action = .export_selection, .label = "导出选中内容…", .icon = "download", .group = 2 },
};

/// 侧栏主机右键菜单（标题“主机 · 名称”由 `entries` 加）：连接在前，配置其次，整理再次，删除最后。
const host_asset = [_]Item{
    .{ .action = .new_tab, .label = "新标签连接", .icon = "terminal", .shortcut = "双击" },
    .{ .action = .new_window, .label = "新窗口连接", .icon = "app-window" },
    .{ .action = .open_in_current_group, .label = "在当前会话组内打开", .icon = "panels-top-left" },
    .{ .action = .clone_host, .label = "复制主机配置", .icon = "copy", .group = 1 },
    .{ .action = .edit_host, .label = "编辑主机配置", .icon = "sliders-horizontal", .group = 1 },
    .{ .action = .history, .label = "历史会话", .icon = "history", .group = 1 },
    .{ .action = .pin_host, .label = "置顶主机", .icon = "pin", .group = 1 },
    .{ .action = .move_group, .label = "移动到分组", .icon = "folder-input", .group = 2 },
    .{ .action = .delete_host, .label = "删除主机资产", .icon = "trash-2", .danger = true },
};
const host_background_available = host_asset[0..2].* ++ [_]Item{.{ .action = .start_background_socks, .label = "仅开启 SOCKS5 转发", .icon = "plug-zap" }} ++ host_asset[2..].*;
const host_background_active = host_asset[0..2].* ++ [_]Item{.{ .action = .manage_background_socks, .label = "管理后台转发", .icon = "plug-zap" }} ++ host_asset[2..].*;

const session_ended = [_]Item{
    .{ .action = .reconnect, .label = "重新连接", .icon = "refresh-cw" },
    .{ .action = .history, .label = "回溯历史 @log", .icon = "history" },
    .{ .action = .close_session, .label = "关闭", .icon = "x", .group = 1 },
};

test "every menu table uses lucide icon names and groups ascend in declaration order" {
    for ([_][]const Item{ &tab_menu, &group_tab, &local_tab, &local_terminal, &terminal_menu, &host_asset, &host_background_available, &host_background_active, &session_ended }) |table| {
        var last: u8 = 0;
        for (table) |item| {
            try std.testing.expect(isIconName(item.icon));
            if (!item.danger) {
                try std.testing.expect(item.group >= last);
                last = item.group;
            }
        }
    }
    try std.testing.expect(!isIconName("✨"));
}

test "tab menu: rename and colour first, the rest below one separator, close (danger) last" {
    var out: Entries = .{};
    const remote = entries(.tab, .{ .multi_tabs = true }, .{}, &out);
    var built: [menu_spec.max_rows]menu_spec.Row = undefined;
    const rows = menu_spec.arrange(remote, &built);
    try std.testing.expectEqualStrings("rename_tab", rows[0].entry.id);
    try std.testing.expectEqual(Shortcut.rename_tab, rows[0].entry.command.?);
    try std.testing.expectEqualStrings("tab_color", rows[1].entry.id);
    try std.testing.expectEqual(@as(usize, tab_colors.len + 2), rows[1].entry.children.len);
    try std.testing.expect(rows[2] == .separator);
    try std.testing.expect(rows[rows.len - 2] == .separator);
    const last = rows[rows.len - 1].entry;
    try std.testing.expectEqualStrings("close_session", last.id);
    try std.testing.expect(last.danger);
    try std.testing.expectEqual(Shortcut.close_tab, last.command.?);
    try std.testing.expectEqualStrings("context.menu.close_session", last.test_id);
    // Text follows [keys]: a remapped close key shows its new chord.
    var map: shortcut_router.Map = .{};
    try map.set(.close_tab, .{ .key = .e, .shift = true });
    try std.testing.expectEqualStrings("⇧⌘E", menu_spec.shortcutText(last.*, .{ .keys = &map }).?);
}

test "group tab menu: one declaration with the session tab menu (rename, colour without follow, layouts, close last)" {
    var out: Entries = .{};
    const list = entries(.group_tab, .{}, .{ .tab_color = .{ .rgb = 0xc48cdb } }, &out);
    var built: [menu_spec.max_rows]menu_spec.Row = undefined;
    const rows = menu_spec.arrange(list, &built);
    const ids = [_]?[]const u8{ "rename_tab", "tab_color", null, "arrange_side", "arrange_stack", null, "close_session" };
    try std.testing.expectEqual(ids.len, rows.len);
    for (ids, rows) |id, row| if (id) |value| try std.testing.expectEqualStrings(value, row.entry.id) else try std.testing.expect(row == .separator);
    try std.testing.expectEqualStrings("groups.tab.rename", rows[0].entry.test_id);
    try std.testing.expectEqualStrings("groups.tab.close", rows[6].entry.test_id);
    try std.testing.expectEqualStrings("颜色：紫（自定义）", rows[1].entry.label);
    try std.testing.expectEqualStrings("会话组不适用", rows[1].entry.children[0].disabled_reason.?);
    try std.testing.expect(rows[1].entry.children[2].selected == false);
    var selected: usize = 0;
    for (rows[1].entry.children) |child| selected += @intFromBool(child.selected);
    try std.testing.expectEqual(@as(usize, 1), selected);
}

test "host menu: header with the host name, connect first, delete (danger) last; disabled plugin explains why" {
    var out: Entries = .{};
    const list = entries(.host_asset, .{ .plugin_disabled = true, .new_window_available = true }, .{ .host_name = "web-1", .host_pinned = true }, &out);
    try std.testing.expectEqual(menu_spec.Kind.header, list[0].kind);
    try std.testing.expectEqualStrings("主机 · web-1", list[0].label);
    try std.testing.expectEqualStrings("new_tab", list[1].id);
    try std.testing.expectEqualStrings("协议插件已禁用", list[1].disabled_reason.?);
    for (list) |entry| if (std.mem.eql(u8, entry.id, "pin_host")) try std.testing.expectEqualStrings("取消置顶", entry.label);
    for (list) |entry| if (std.mem.eql(u8, entry.id, "edit_host")) try std.testing.expect(!entry.isDisabled());
    var built: [menu_spec.max_rows]menu_spec.Row = undefined;
    const rows = menu_spec.arrange(list, &built);
    try std.testing.expectEqualStrings("delete_host", rows[rows.len - 1].entry.id);
    try std.testing.expect(rows[rows.len - 2] == .separator);
}

test "tab colours: follow, none and the six colours round-trip through storage and ids" {
    try std.testing.expectEqual(TabColor.follow, tabColorOf(null));
    try std.testing.expectEqual(TabColor.none, tabColorOf(tab_color_none));
    try std.testing.expectEqual(@as(u32, 0xc48cdb), tabColorOf(0xc48cdb).rgb);
    try std.testing.expectEqual(@as(?u32, null), tabColorStored(.follow));
    try std.testing.expectEqual(@as(?u32, tab_color_none), tabColorStored(.none));
    var label: [48]u8 = undefined;
    try std.testing.expectEqualStrings("颜色：紫（自定义）", tabColorLabel(&label, .{ .rgb = 0xc48cdb }));
    try std.testing.expectEqualStrings("颜色：跟随环境", tabColorLabel(&label, .follow));
    try std.testing.expectEqualStrings("颜色：自定义", tabColorLabel(&label, .{ .rgb = 0x818cf8 }));
    try std.testing.expectEqual(TabColor.follow, parseTabColorId("tab_color.follow").?);
    try std.testing.expectEqual(TabColor.none, parseTabColorId("tab_color.none").?);
    try std.testing.expectEqual(@as(u32, 0xe27878), parseTabColorId("tab_color.e27878").?.rgb);
    try std.testing.expect(parseTabColorId("tab_color.1000000") == null);
    try std.testing.expect(parseTabColorId("rename_tab") == null);
    try std.testing.expectEqual(@as(usize, 6), tab_colors.len);
}

test "local menus expose current local capabilities without remote or future operations" {
    for ([_]Kind{ .tab, .session_ended }) |kind| {
        const list = items(kind, .{ .local_session = true });
        try std.testing.expectEqual(@as(usize, 12), list.len);
        try std.testing.expectEqual(Action.new_tab, list[0].action);
        try std.testing.expectEqual(Action.clone_session, list[1].action);
        try std.testing.expect(list[1].shortcut == null and list[1].key == null);
        for (list) |item| try std.testing.expect(item.action != .edit_host and item.action != .view_jump_chain and item.action != .reconnect);
    }
    const context: Context = .{ .local_session = true };
    try std.testing.expect(!isEnabled(.copy, context));
    try std.testing.expect(isEnabled(.paste, context));
    try std.testing.expect(!isEnabled(.paste, .{ .local_session = true, .read_only = true }));
    try std.testing.expect(isEnabled(.copy, .{ .local_session = true, .read_only = true, .has_selection = true }));
    try std.testing.expect(!isEnabled(.export_selection, context));
    // copy-terms: the local terminal menu carries no theme entry (themes live in 设置 › 外观 only).
    for (items(.terminal, context)) |item| try std.testing.expect(!std.mem.eql(u8, item.icon, "palette"));
}

test "new-window action stays unavailable until shared application host supports it" {
    try std.testing.expect(!isEnabled(.new_window, .{}));
    try std.testing.expect(isEnabled(.new_window, .{ .new_window_available = true }));
}

test "background SOCKS menu exposes only saved SSH capability and original background management" {
    const absent = items(.host_asset, .{});
    for (absent) |item| try std.testing.expect(item.action != .start_background_socks and item.action != .manage_background_socks);
    const available = items(.host_asset, .{ .background_socks = true });
    try std.testing.expectEqual(Action.start_background_socks, available[2].action);
    try std.testing.expect(isEnabled(available[2].action, .{ .background_socks = true }));
    const active = items(.host_asset, .{ .background_socks = true, .background_active = true });
    try std.testing.expectEqual(Action.manage_background_socks, active[2].action);
    try std.testing.expect(!isEnabled(.start_background_socks, .{ .background_socks = true, .background_active = true }));
}

test "menu actions respect selection and session context" {
    try std.testing.expect(!isEnabled(.copy, .{}));
    try std.testing.expect(isEnabled(.copy, .{ .has_selection = true }));
    try std.testing.expect(!isEnabled(.reconnect, .{}));
    try std.testing.expect(isEnabled(.reconnect, .{ .session_ended = true }));
    try std.testing.expect(!isEnabled(.open_in_current_group, .{}));
    try std.testing.expect(isEnabled(.open_in_current_group, .{ .group_target_available = true }));
    try std.testing.expect(isEnabled(.duplicate_into_group, .{ .single_session = true }));
    try std.testing.expect(!isEnabled(.duplicate_into_group, .{ .single_session = true, .read_only = true }));
    try std.testing.expect(!isVisible(.duplicate_into_group, .{ .single_session = false }));
    try std.testing.expectEqualStrings("只有一个页签", disabledReason(.close_others, .{}).?);
    try std.testing.expect(disabledReason(.close_others, .{ .multi_tabs = true }) == null);
}

test "tab menu carries session lifecycle actions, disjoint from text ops" {
    const tab = items(.tab, .{});
    try std.testing.expectEqual(@as(usize, 14), tab.len);
    for (tab) |item| {
        try std.testing.expect(item.action != .copy);
        try std.testing.expect(item.action != .paste);
        try std.testing.expect(item.action != .search);
    }
    // Theme entries are only 设置 › 外观 and the menu bar 显示 › 外观… (bugfix-4), never a tab menu item.
    for ([_]Context{ .{}, .{ .local_session = true }, .{ .session_ended = true } }) |context| {
        for (items(.tab, context)) |item| try std.testing.expect(!std.mem.eql(u8, item.icon, "palette") or item.action == .tab_color);
    }
    try std.testing.expect(tab[13].danger);
    try std.testing.expectEqual(Action.close_session, tab[13].action);
    try std.testing.expect(!isEnabled(.close_others, .{ .multi_tabs = false }));
    try std.testing.expect(isEnabled(.close_others, .{ .multi_tabs = true }));
}

test "SSH connection actions are confined to the tab menu" {
    for ([_]Context{ .{}, .{ .has_selection = true }, .{ .local_session = true } }) |context| {
        for (items(.terminal, context)) |item| {
            try std.testing.expect(item.action != .new_tab and item.action != .reuse_connection and item.action != .new_window);
        }
    }
    try std.testing.expect(!isEnabled(.reuse_connection, .{}));
    try std.testing.expect(isEnabled(.reuse_connection, .{ .reuse_connection_available = true }));
    try std.testing.expect(!isEnabled(.reuse_connection, .{ .reuse_connection_available = true, .session_ended = true }));
}

test "tab menu connection actions distinguish saved assets from temporary remote sessions" {
    const temporary: Context = .{ .has_saved_connection = false, .has_unsaved_connection = true };
    try std.testing.expect(isVisible(.save_host, temporary));
    try std.testing.expect(isEnabled(.save_host, temporary));
    try std.testing.expect(!isVisible(.edit_host, temporary));
    const saved: Context = .{ .has_saved_connection = true };
    try std.testing.expect(isVisible(.edit_host, saved));
    try std.testing.expect(!isVisible(.save_host, saved));
    try std.testing.expect(!isEnabled(.save_host, .{}));
    for (items(.terminal, temporary)) |item| try std.testing.expect(item.action != .save_host);
}

test "mixed session group menu does not require terminal services" {
    const owner: @import("../../../host/identity.zig").SessionHandle = .{ .session_id = @fromBackingInt(8) };
    const context: Context = .{ .capability_snapshot = .{ .owner = owner, .revision = 1, .services = &.{} } };
    try std.testing.expect(isEnabled(.join_session_group, context));
    try std.testing.expect(!isEnabled(.join_session_group, .{ .read_only = true }));
    try std.testing.expect(!isEnabled(.join_session_group, .{ .session_ended = true }));
    try std.testing.expectEqual(@as(usize, 0), actions.requirements(.join_group).len);
}

test "Q5: a host whose plugin is disabled keeps edit and delete but cannot connect" {
    const context: Context = .{ .plugin_disabled = true, .new_window_available = true, .group_target_available = true };
    for ([_]Action{ .new_tab, .new_window, .open_in_current_group, .clone_host }) |action| try std.testing.expect(!isEnabled(action, context));
    for ([_]Action{ .edit_host, .delete_host, .pin_host, .move_group, .history }) |action| try std.testing.expect(isEnabled(action, context));
    try std.testing.expect(isEnabled(.new_tab, .{}));
}

/// 页签颜色（稿 3“颜色 ›”子菜单）：跟随环境（默认：主机所在环境的颜色，本地终端不着色）· 6 种颜色 · 无。
pub const TabColor = union(enum) {
    follow,
    none,
    rgb: u32,
};
pub const TabColorChoice = struct { rgb: u32, name: []const u8 };
/// 6 种颜色（取自 ZeroWork 现有色板里与 zenit 语义色相近的 6 个：危险红、橙、警告琥珀、成功绿、信息蓝、强调紫）。
pub const tab_colors = [_]TabColorChoice{
    .{ .rgb = 0xe27878, .name = "红" },
    .{ .rgb = 0xe89963, .name = "橙" },
    .{ .rgb = 0xe2ad67, .name = "琥珀" },
    .{ .rgb = 0x67b88b, .name = "绿" },
    .{ .rgb = 0x87bde8, .name = "蓝" },
    .{ .rgb = 0xc48cdb, .name = "紫" },
};
/// `SessionTab.tab_color` 里“无”的取值（0xRRGGBB 之外）；null 是“跟随环境”。
pub const tab_color_none: u32 = 0x1000000;
pub fn tabColorOf(stored: ?u32) TabColor {
    const value = stored orelse return .follow;
    if (value == tab_color_none) return .none;
    return .{ .rgb = value & 0xffffff };
}
pub fn tabColorStored(color: TabColor) ?u32 {
    return switch (color) {
        .follow => null,
        .none => tab_color_none,
        .rgb => |value| value & 0xffffff,
    };
}
pub fn tabColorName(rgb: u32) ?[]const u8 {
    for (tab_colors) |choice| if (choice.rgb == rgb & 0xffffff) return choice.name;
    return null;
}
/// 父项文案：“颜色：跟随环境”/“颜色：无”/“颜色：紫（自定义）”/ 色板外的旧颜色写“颜色：自定义”。
pub fn tabColorLabel(buffer: []u8, color: TabColor) []const u8 {
    return switch (color) {
        .follow => "颜色：跟随环境",
        .none => "颜色：无",
        .rgb => |value| if (tabColorName(value)) |name| std.fmt.bufPrint(buffer, "颜色：{s}（自定义）", .{name}) catch "颜色" else "颜色：自定义",
    };
}
/// 子菜单项 id：`tab_color.follow` / `tab_color.none` / `tab_color.e27878`。
pub const tab_color_id_prefix = "tab_color.";
pub fn parseTabColorId(id: []const u8) ?TabColor {
    if (!std.mem.startsWith(u8, id, tab_color_id_prefix)) return null;
    const rest = id[tab_color_id_prefix.len..];
    if (std.mem.eql(u8, rest, "follow")) return .follow;
    if (std.mem.eql(u8, rest, "none")) return .none;
    const value = std.fmt.parseInt(u32, rest, 16) catch return null;
    if (value > 0xffffff) return null;
    return .{ .rgb = value };
}
