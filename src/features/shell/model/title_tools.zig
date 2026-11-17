//! 标题栏工具组（design-r3 稿 5，Pencil `qSGtA`）的纯模型：按钮、分组、折叠级别、Tooltip 与“⋯”菜单。
//!
//! - 7 个按钮分 3 组：通信链路 · 端口转发 · 传输管理 ｜ 命令历史 · 回看日志 · 通知 ｜ 设置；会话组页签下连接组
//!   追加“组广播”。全部是 zenit 原生 Button（ghost / md / icon only，32 × 32），组内间距 2，组间 1 × 16 分隔线、两侧各 6。
//!   主题不是高频操作，不在标题栏（title-click）：切换主题在 设置 › 外观与主题，以及菜单栏“显示 › 外观…”。
//! - 只看空间：页签条按内容需要的宽度排完（含新建按钮）后，剩余空间放不下才折叠（`choose`），工具先于页签进入溢出：
//!   第 1 级：保留进行中的传输、通知、设置，其余收进“⋯”；第 2 级：只剩“⋯”（未读通知时“⋯”上有圆点）。
//!   恢复时留 24 的回差，避免拖动窗口时来回闪。
//! - 交互只响应点击：悬停只出原生 Tooltip，点击打开各自的弹层（宿主），不通过悬停打开任何卡片或预览。
//! - Tooltip 统一“名称 · 快捷键”；有状态的写状态，不可用的写原因（`tooltip`）。“⋯”的菜单项与 Tooltip 文案一致。
//! - 快捷键以代码为准：命令历史、设置、组广播有快捷键（`command`）；文字由宿主从快捷键路由取（随 `[keys]` 变化）。
const std = @import("std");
const shortcut_router = @import("shortcut_router.zig");

pub const Tool = enum(u4) {
    chain,
    forward,
    transfers,
    broadcast,
    command_history,
    history,
    notifications,
    settings,
};
pub const count = @typeInfo(Tool).@"enum".field_names.len;

pub const Group = enum(u2) { connection, records, application };

pub fn groupOf(tool: Tool) Group {
    return switch (tool) {
        .chain, .forward, .transfers, .broadcast => .connection,
        .command_history, .history, .notifications => .records,
.settings => .application,
    };
}

/// 显示顺序（与稿 5 一致；广播只在会话组页签下出现，排在连接组末尾）。
pub const order = [_]Tool{ .chain, .forward, .transfers, .broadcast, .command_history, .history, .notifications, .settings };

/// 名称以代码为准并统一（a11y_label、动作注册表、页签菜单）。
pub fn label(tool: Tool) []const u8 {
    return switch (tool) {
        .chain => "通信链路",
        .forward => "端口转发",
        .transfers => "传输管理",
        .broadcast => "组广播",
        .command_history => "命令历史",
        .history => "回看日志",
        .notifications => "通知",
        .settings => "设置",
    };
}

/// lucide 图标名（`ui.icons.get`）。传输管理按阶段换图标（宿主经 `setIcon` 写入）。
pub fn iconName(tool: Tool) []const u8 {
    return switch (tool) {
        .chain => "network",
        .forward => "plug-zap",
        .transfers => "arrow-down-up",
        .broadcast => "radio",
        .command_history => "list-restart",
        .history => "history",
        .notifications => "bell",
        .settings => "settings",
    };
}

/// 按钮 test_id 沿用旧控件的（test_id 是公开接口，不改名）。
pub fn buttonId(tool: Tool) []const u8 {
    return switch (tool) {
        .chain => "status.connection.chain",
        .forward => "status.connection.forward",
        .transfers => "toolbar.transfers",
        .broadcast => "status.group.broadcast",
        .command_history => "status.command-history",
        .history => "toolbar.history",
        .notifications => "toolbar.notifications",
        .settings => "toolbar.settings",
    };
}

/// 按钮 Tooltip 提示面板的 test_id（`<按钮 id>.tooltip`）：e2e 直接按 id 读提示文字，不必读整棵树。
pub fn tooltipId(tool: Tool) []const u8 {
    return switch (tool) {
        .chain => "status.connection.chain.tooltip",
        .forward => "status.connection.forward.tooltip",
        .transfers => "toolbar.transfers.tooltip",
        .broadcast => "status.group.broadcast.tooltip",
        .command_history => "status.command-history.tooltip",
        .history => "toolbar.history.tooltip",
        .notifications => "toolbar.notifications.tooltip",
        .settings => "toolbar.settings.tooltip",
    };
}

/// “⋯”菜单行的 test_id。
pub fn menuId(tool: Tool) []const u8 {
    return switch (tool) {
        inline else => |value| "toolbar.more." ++ @tagName(value),
    };
}

pub fn fromMenuId(id: []const u8) ?Tool {
    for (std.enums.values(Tool)) |tool| {
        if (std.mem.eql(u8, id, menuId(tool))) return tool;
    }
    return null;
}

/// 工具对应的快捷键命令（提示文字由宿主经路由取）。
pub fn command(tool: Tool) ?shortcut_router.Command {
    return switch (tool) {
        .command_history => .command_history,
        .settings => .open_settings,
        .broadcast => .broadcast,
        else => null,
    };
}

pub const Level = enum(u2) {
    /// 全部展开。
    expanded = 0,
    /// 第 1 级：保留进行中的传输、通知、设置。
    compact = 1,
    /// 第 2 级：只剩“⋯”。
    collapsed = 2,
};

/// 每个按钮当前的事实（宿主每帧写入）。
pub const Facts = struct {
    /// 按钮在当前页签下存在（例如组广播只在会话组页签下出现）。
    present: [count]bool = presentDefault(),
    /// 传输管理有进行中的任务（第 1、2 级仍保留它）。
    transfers_active: bool = false,
};

fn presentDefault() [count]bool {
    var value: [count]bool = @splat(true);
    value[@intFromEnum(Tool.broadcast)] = false;
    return value;
}

/// 按钮在标题栏上直接显示（否则在“⋯”菜单里；不存在的按钮两处都没有）。
pub fn inBar(tool: Tool, level: Level, facts: Facts) bool {
    if (!facts.present[@intFromEnum(tool)]) return false;
    return switch (level) {
        .expanded => true,
        .compact => switch (tool) {
            .transfers => facts.transfers_active,
            .notifications, .settings => true,
            else => false,
        },
        .collapsed => false,
    };
}

pub fn inMenu(tool: Tool, level: Level, facts: Facts) bool {
    return facts.present[@intFromEnum(tool)] and !inBar(tool, level, facts);
}

pub const button: f32 = 32;
pub const group_gap: f32 = 2;
/// 组间：1 × 16 分隔线，两侧各 6。
pub const divider: f32 = 1 + 2 * 6;
/// “⋯”按钮与前面按钮的间距。
pub const more_gap: f32 = 6;
/// 恢复时的回差。
pub const hysteresis: f32 = 24;

/// 工具区在某一级需要的宽度（含“⋯”）。
pub fn width(level: Level, facts: Facts) f32 {
    var total: f32 = 0;
    var last_group: ?Group = null;
    for (order) |tool| {
        if (!inBar(tool, level, facts)) continue;
        const group = groupOf(tool);
        if (last_group) |previous| {
            total += if (previous == group) group_gap else divider;
        }
        last_group = group;
        total += button;
    }
    if (level != .expanded) total += (if (total > 0) more_gap else 0) + button;
    return total;
}

/// 选折叠级别：`available` 是页签条按自然宽度排完（含新建按钮与间距）后剩下的宽度。取放得下的最展开的一级；
/// 比当前更展开时要多留 `hysteresis`。
pub fn choose(available: f32, current: Level, facts: Facts) Level {
    for ([_]Level{ .expanded, .compact }) |level| {
        const need = width(level, facts) + if (@intFromEnum(level) < @intFromEnum(current)) hysteresis else 0;
        if (need <= available) return level;
    }
    return .collapsed;
}

/// 分隔线：两侧的组在标题栏上都有按钮时才显示。`index` 0 在连接组与记录组之间，1 在记录组与应用组之间。
pub fn dividerShown(index: u1, level: Level, facts: Facts) bool {
    var seen: [3]bool = @splat(false);
    for (order) |tool| if (inBar(tool, level, facts)) {
        seen[@intFromEnum(groupOf(tool))] = true;
    };
    return switch (index) {
        0 => seen[0] and (seen[1] or seen[2]),
        1 => seen[2] and seen[1],
    };
}

/// Tooltip / 菜单项文案：“名称 · 状态 · 快捷键”，空的段跳过。`state` 已带名称前缀时（例如“通信链路 · 已连接”）原样使用。
pub fn tooltip(buffer: []u8, tool: Tool, state: []const u8, key: ?[]const u8) []const u8 {
    const name = label(tool);
    var writer = std.Io.Writer.fixed(buffer);
    if (std.mem.startsWith(u8, state, name)) {
        writer.writeAll(state) catch return name;
    } else {
        writer.writeAll(name) catch return name;
        if (state.len != 0) writer.print(" · {s}", .{state}) catch return name;
    }
    if (key) |value| if (value.len != 0) writer.print(" · {s}", .{value}) catch {};
    return writer.buffered();
}

const testing = std.testing;

test "title tools: three groups in the 稿 5 order with the code's names and shortcuts" {
    try testing.expectEqual(Group.connection, groupOf(.transfers));
    try testing.expectEqual(Group.records, groupOf(.notifications));
    try testing.expectEqual(Group.application, groupOf(.settings));
    try testing.expectEqualStrings("通信链路", label(.chain));
    try testing.expectEqual(shortcut_router.Command.command_history, command(.command_history).?);
    try testing.expectEqual(shortcut_router.Command.open_settings, command(.settings).?);
    try testing.expect(command(.chain) == null);
    try testing.expectEqual(Tool.settings, fromMenuId("toolbar.more.settings").?);
    try testing.expectEqual(@as(?Tool, null), fromMenuId("toolbar.more.theme"));
    try testing.expectEqual(@as(?Tool, null), fromMenuId("toolbar.more.nope"));
}

test "title tools: fold levels keep active transfers, notifications and settings" {
    const idle: Facts = .{};
    var busy: Facts = .{};
    busy.transfers_active = true;
    for (order) |tool| try testing.expectEqual(tool != .broadcast, inBar(tool, .expanded, idle));
    try testing.expect(!inBar(.chain, .compact, busy) and !inBar(.command_history, .compact, busy));
    try testing.expect(inBar(.transfers, .compact, busy) and !inBar(.transfers, .compact, idle));
    try testing.expect(inBar(.notifications, .compact, idle) and inBar(.settings, .compact, idle));
    for (order) |tool| try testing.expect(!inBar(tool, .collapsed, busy));
    try testing.expect(inMenu(.chain, .compact, idle) and !inMenu(.broadcast, .compact, idle));
    try testing.expect(dividerShown(0, .expanded, idle) and dividerShown(1, .expanded, idle));
    // 第 1 级：通知（记录组）与设置之间有分隔线；连接组空了，第一条分隔线不显示。
    try testing.expect(!dividerShown(0, .compact, idle) and dividerShown(1, .compact, idle));
    try testing.expect(dividerShown(0, .compact, busy));
}

test "title tools: widths, folding only when tabs leave no room, 24 hysteresis" {
    const idle: Facts = .{};
    // 7 buttons: 3 + 3 + 1 → 7 × 32 + 4 × 2 (in-group) + 2 × 13 (dividers).
    try testing.expectEqual(@as(f32, 7 * 32 + 4 * 2 + 2 * 13), width(.expanded, idle));
    // compact: bell | gear, then ⋯.
    try testing.expectEqual(@as(f32, 32 + 13 + 32 + 6 + 32), width(.compact, idle));
    try testing.expectEqual(@as(f32, 32), width(.collapsed, idle));
    const full = width(.expanded, idle);
    try testing.expectEqual(Level.expanded, choose(full, .expanded, idle));
    try testing.expectEqual(Level.compact, choose(full - 1, .expanded, idle));
    // Coming back needs the 24 margin.
    try testing.expectEqual(Level.compact, choose(full + 10, .compact, idle));
    try testing.expectEqual(Level.expanded, choose(full + hysteresis, .compact, idle));
    try testing.expectEqual(Level.collapsed, choose(40, .expanded, idle));
}

test "title tools: tooltip reads 名称 · 状态 · 快捷键" {
    var buffer: [96]u8 = undefined;
    try testing.expectEqualStrings("命令历史 · ⇧⌘B", tooltip(&buffer, .command_history, "", "⇧⌘B"));
    try testing.expectEqualStrings("命令历史", tooltip(&buffer, .command_history, "", ""));
    try testing.expectEqualStrings("设置 · ⌘,", tooltip(&buffer, .settings, "", "⌘,"));
    try testing.expectEqualStrings("通信链路 · 已连接", tooltip(&buffer, .chain, "通信链路 · 已连接", null));
    try testing.expectEqualStrings("端口转发 · 当前页签不是 SSH 会话", tooltip(&buffer, .forward, "当前页签不是 SSH 会话", null));
    try testing.expectEqualStrings("组广播 · 已开启 · ⇧⌘I", tooltip(&buffer, .broadcast, "已开启", "⇧⌘I"));
}
