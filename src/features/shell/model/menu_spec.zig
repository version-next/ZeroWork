//! 菜单的声明式描述与排列规则（CONSISTENCY_AUDIT #3，menus 包）——所有菜单的唯一来源。
//!
//! 每个菜单（侧栏右键、页签右键、会话组页签、终端右键、中键菜单、溢出“⋯”、窗格“更多”、文件区右键、
//! 传输任务“⋯”、新建会话、KVM“更多”……）只声明一组 `Entry`：标题、图标名、快捷键命令（文字只从
//! `shortcut_router` 取）、禁用与原因、危险标记、子菜单、分组。怎么排、哪里画分隔线只在 `arrange`
//! 定一处，投影成原生 `W.Menu` 的行在 `view/app_menu.zig`（`build`），挂载也只经那里。
//!
//! 排列规则（docs/ui-revamp/CONSISTENCY_AUDIT.md 拍板附录“菜单项顺序与分组”）：
//! 1. 常用操作在前：声明顺序就是常用程度，`group` 小的组在前（0 = 常用组）；
//! 2. 同组内保持声明顺序，组与组之间一条分隔线；分组标题（`kind = .header`）开启一个组；
//! 3. 危险操作（`danger`）一律放最后，单独成组，前面一条分隔线；标为 `danger` 的分组标题是这组的标题
//!    （说明危险项的作用范围），排在危险项之前、同一条分隔线之后；
//! 4. 菜单项只发出动作（`id`），危险项的确认或撤销由动作的执行方负责（confirm-undo 包），菜单不自己确认。
const std = @import("std");
const shortcut_router = @import("shortcut_router.zig");

pub const Command = shortcut_router.Command;

pub const Kind = enum { item, header };

pub const Entry = struct {
    /// 动作 id：选中时原样交回宿主（`on_select`）。标题行不用。
    id: []const u8 = "",
    label: []const u8,
    kind: Kind = .item,
    /// lucide 图标名（`ui.icons.get`）；空串 = 无图标。
    icon: []const u8 = "",
    /// 快捷键命令：右侧文字由路由按当前 `[keys]` 给出（没有组合时不显示）。
    command: ?Command = null,
    /// 不是按键组合的说明（手势、“@ts”）；有 `command` 时不用。
    note: ?[]const u8 = null,
    /// 不可用时为 true；原因写在 `disabled_reason`（显示在标题后，也是无障碍描述）。
    disabled: bool = false,
    disabled_reason: ?[]const u8 = null,
    danger: bool = false,
    /// 分组序号（0 = 常用组）；`arrange` 按它稳定排序，组间画分隔线。
    group: u8 = 0,
    /// 勾选态（单选子菜单的当前项）。
    selected: bool = false,
    /// 标题下的第二行说明（原生 `MenuItem.description`：这一项做什么）。
    description: ?[]const u8 = null,
    /// 行右侧的原生 sm Tag（如“交互式”）。
    tag: ?[]const u8 = null,
    /// 图标着色（色块行，0xRRGGBB）。
    tint: ?u32 = null,
    /// 运行期才知道的图标（会话类型图标等）：指向 `ui.SvgAsset`，优先于 `icon`。模型层不认识 ui 类型，只透传。
    icon_asset: ?*const anyopaque = null,
    children: []const Entry = &.{},
    submenu_test_id: []const u8 = "",
    submenu_max_height: ?f32 = null,
    test_id: []const u8 = "",

    pub fn isDisabled(self: Entry) bool {
        return self.disabled or self.disabled_reason != null;
    }
};

/// 排好的一行：一个条目，或条目前的分隔线。
pub const Row = union(enum) {
    separator,
    entry: *const Entry,
};

pub const max_rows = 64;

fn rank(entry: *const Entry) u16 {
    return (@as(u16, @intFromBool(entry.danger)) << 8) | entry.group;
}

/// 唯一的排列规则：按（危险在后，组号）稳定排序；组变化处、分组标题前插分隔线（第一行之前不插）。
pub fn arrange(entries: []const Entry, out: *[max_rows]Row) []const Row {
    var order: [max_rows]*const Entry = undefined;
    const n = @min(entries.len, max_rows);
    for (entries[0..n], 0..) |*entry, index| order[index] = entry;
    std.sort.insertion(*const Entry, order[0..n], {}, struct {
        fn less(_: void, a: *const Entry, b: *const Entry) bool {
            // A group's heading leads its group.
            if (rank(a) == rank(b)) return a.kind == .header and b.kind != .header;
            return rank(a) < rank(b);
        }
    }.less);
    var count: usize = 0;
    var previous: ?u16 = null;
    for (order[0..n]) |entry| {
        if (count + 2 > max_rows) break;
        const key = rank(entry);
        // A heading that opens a new group already follows the separator the group change put in.
        if (previous) |last| if (last != key or entry.kind == .header) {
            out[count] = .separator;
            count += 1;
        };
        previous = key;
        out[count] = .{ .entry = entry };
        count += 1;
    }
    return out[0..count];
}

/// 右侧文字：有命令取路由的当前组合（未绑定时不显示），否则是说明文字。
pub fn shortcutText(entry: Entry, router: shortcut_router.Router) ?[]const u8 {
    if (entry.kind != .item) return null;
    if (entry.command) |command| {
        const hint = router.hint(command);
        return if (hint.len == 0) null else hint;
    }
    const note = entry.note orelse return null;
    return if (note.len == 0) null else note;
}

test "arrange: common group first, declared order kept, danger last after a separator" {
    const entries = [_]Entry{
        .{ .id = "close", .label = "关闭页签", .danger = true },
        .{ .id = "rename", .label = "重命名…" },
        .{ .id = "export", .label = "导出记录", .group = 1 },
        .{ .id = "color", .label = "页签颜色" },
        .{ .id = "details", .label = "会话详情", .group = 1 },
    };
    var buffer: [max_rows]Row = undefined;
    const rows = arrange(&entries, &buffer);
    const want = [_]?[]const u8{ "rename", "color", null, "export", "details", null, "close" };
    try std.testing.expectEqual(want.len, rows.len);
    for (want, rows) |id, row| {
        if (id) |value| try std.testing.expectEqualStrings(value, row.entry.id) else try std.testing.expect(row == .separator);
    }
}

test "arrange: a header starts a group with a separator before it (not at the top)" {
    const entries = [_]Entry{
        .{ .label = "主机 · web", .kind = .header },
        .{ .id = "open", .label = "新标签连接" },
        .{ .label = "快捷连接", .kind = .header, .group = 1 },
        .{ .id = "new", .label = "新建主机", .group = 1 },
        .{ .id = "delete", .label = "删除主机", .danger = true },
    };
    var buffer: [max_rows]Row = undefined;
    const rows = arrange(&entries, &buffer);
    try std.testing.expectEqual(@as(usize, 7), rows.len);
    try std.testing.expect(rows[0].entry.kind == .header);
    try std.testing.expect(rows[2] == .separator and rows[3].entry.kind == .header);
    try std.testing.expect(rows[5] == .separator and rows[6].entry.danger);
}

test "arrange: a danger heading opens the danger group, one separator before both" {
    const entries = [_]Entry{
        .{ .id = "revoke", .label = "撤销会话列表授权", .danger = true },
        .{ .label = "执行权限", .kind = .header },
        .{ .id = "confirm", .label = "确认后执行", .description = "部分读取自动", .selected = true },
        .{ .id = "auto", .label = "自动执行", .tag = "交互式" },
        .{ .label = "当前助手范围 · 禁止项不可执行", .kind = .header, .danger = true },
    };
    var buffer: [max_rows]Row = undefined;
    const rows = arrange(&entries, &buffer);
    try std.testing.expectEqual(@as(usize, 6), rows.len);
    try std.testing.expect(rows[0].entry.kind == .header and !rows[0].entry.danger);
    try std.testing.expectEqualStrings("confirm", rows[1].entry.id);
    try std.testing.expectEqualStrings("auto", rows[2].entry.id);
    try std.testing.expect(rows[3] == .separator);
    try std.testing.expect(rows[4].entry.kind == .header and rows[4].entry.danger);
    try std.testing.expectEqualStrings("revoke", rows[5].entry.id);
}

test "shortcut text comes from the router and follows [keys]; notes for gestures" {
    const defaults: shortcut_router.Map = .{};
    const router: shortcut_router.Router = .{ .keys = &defaults };
    try std.testing.expectEqualStrings(router.hint(.close_tab), shortcutText(.{ .label = "关闭页签", .command = .close_tab }, router).?);
    var map: shortcut_router.Map = .{};
    try map.set(.close_tab, .{ .key = .e, .shift = true });
    try std.testing.expectEqualStrings("⇧⌘E", shortcutText(.{ .label = "关闭页签", .command = .close_tab }, .{ .keys = &map }).?);
    try std.testing.expectEqualStrings("@ts", shortcutText(.{ .label = "时间戳", .note = "@ts" }, router).?);
    try std.testing.expect(shortcutText(.{ .label = "无" }, router) == null);
    try std.testing.expect(shortcutText(.{ .label = "组", .kind = .header, .note = "x" }, router) == null);
    try std.testing.expect((Entry{ .label = "复制", .disabled_reason = "未选中内容" }).isDisabled());
}
