//! 快捷键行内录制的纯逻辑（P3 3e 第二批，人工验收反馈第 7 条；交互设计见 `docs/ui-revamp/YIX_SPIKE.md`
//! “快捷键行的编辑交互”）。
//!
//! - 动作的显示名、固定（不可修改）的动作、键帽文字（全部是静态字符串，视图可以直接持有）；
//! - 录制到的组合怎么处理（`judge`）：规则与运行时 `Map.set` 相同（Escape / 未知键不可用；除两个固定动作外必须含 ⌘、
//!   不含 ⌃、主键不是 Tab；不能与其它动作重复），只是把“拒绝”细分成用户看得懂的原因，并把冲突对象交给调用方；
//! - 冲突的一步解决（`swap`）：本动作取新组合，对方取本动作原来的组合（运行时没有“未绑定”值，不能清除对方）。
//!
//! 本文件不依赖 zenit `ui`，也不读写 Controller；view-model 用它判定、再经 `Controller.editKeys` 写草稿。
const std = @import("std");
pub const keys = @import("catalog.zig").keybindings;
/// 动作名、键帽与组合文字都取自快捷键路由（唯一来源），本文件只做设置页的录制判定。
const router = @import("../../shell/mod.zig").shortcut_router;
pub const Action = keys.Action;
pub const Chord = keys.Chord;
pub const KeyCode = keys.KeyCode;
pub const Map = keys.Map;

/// 按住的修饰键（录制中实时显示）。
pub const Mods = struct {
    command: bool = false,
    control: bool = false,
    shift: bool = false,
    option: bool = false,

    pub fn any(self: Mods) bool {
        return self.command or self.control or self.shift or self.option;
    }
};

/// 录制到的组合为什么不能用。
pub const Reason = enum {
    none,
    /// 两个固定动作（最近使用的页签、采纳补全）保留给应用。
    fixed,
    /// 未识别的按键或 Escape（Escape 在录制里是“取消”）。
    key_reserved,
    /// 含 ⌃ Control：保留给远端终端。
    control_reserved,
    /// 主键是 Tab：保留给远端终端。
    tab_reserved,
    /// 没有 ⌘ Command。
    needs_command,
    /// 已被应用的固定快捷键（命令历史、设置、新建主机）或系统 / 文本编辑键（退出、隐藏、撤销……）占用。
    reserved,
};

/// 录制到一个组合后的判定。
pub const Verdict = union(enum) {
    /// 可以直接写进草稿。
    accept,
    /// 与当前值相同：什么都不用做。
    same,
    /// 已被另一个动作占用。
    conflict: Action,
    /// 不合规。
    invalid: Reason,
};

/// 两个固定动作：鼠标 / 补全交互保留给应用，不可修改（旧面板的锁图标行）。
pub fn fixed(action: Action) bool {
    return action == .recent_tab or action == .accept_completion;
}

/// 动作的显示名（快捷键路由的注册表）。
pub fn label(action: Action) []const u8 {
    return router.label(router.fromAction(action));
}

/// 说明文字里引用的快捷键（编译期，出厂组合；文字来自路由的唯一格式化）。
pub fn factoryHint(comptime action: Action) []const u8 {
    return comptime router.text((Map{}).get(action));
}
/// AI 输入框“使用另一种跟进行为”的组合（局部键）。
pub fn followUpHint() []const u8 {
    return comptime router.defaultHint(.ai_alternate_follow_up);
}

/// 出厂默认值。
pub fn defaultOf(action: Action) Chord {
    return (Map{}).get(action);
}

/// 判定把 `chord` 给 `action` 会怎样（规则同 `Map.set`）。
pub fn judge(map: Map, action: Action, chord: Chord) Verdict {
    if (fixed(action)) return .{ .invalid = .fixed };
    if (chord.key == .unknown or chord.key == .escape) return .{ .invalid = .key_reserved };
    if (chord.control) return .{ .invalid = .control_reserved };
    if (chord.key == .tab) return .{ .invalid = .tab_reserved };
    if (!chord.command) return .{ .invalid = .needs_command };
    if (map.get(action).eql(chord)) return .same;
    if (router.reservedBy(chord) != null) return .{ .invalid = .reserved };
    if (map.conflict(action, chord)) |other| return .{ .conflict = other };
    return .accept;
}

/// 写入一个已判定为 `accept` 的组合（经 `Map.set`，规则再核一次）。
pub fn apply(map: *Map, action: Action, chord: Chord) !void {
    try map.set(action, chord);
}

/// 冲突的一步解决：`action` 取 `chord`，占用它的动作改用 `action` 原来的组合。对方是固定动作时拒绝（合规组合
/// 不会与固定动作的组合重复，所以实际不会发生）。返回对方。
pub fn swap(map: *Map, action: Action, chord: Chord) !Action {
    const other = map.conflict(action, chord) orelse return error.NoConflict;
    if (fixed(other) or fixed(action)) return error.FixedAction;
    if (judge(map.*, action, chord) != .conflict) return error.InvalidChord;
    var next = map.*;
    next.chords[@backingInt(other)] = map.get(action);
    next.chords[@backingInt(action)] = chord;
    // 整张表再按运行时规则核一遍（与读配置相同）。
    var buffer: [4096]u8 = undefined;
    _ = try Map.parse(try next.format(&buffer));
    map.* = next;
    return other;
}

/// 占用这个组合的固定 / 系统快捷键的名称（冲突提示用）。
pub fn reservedName(chord: Chord) ?[]const u8 {
    const owner = router.reservedBy(chord) orelse return null;
    return router.label(owner);
}

/// 原因的说明文字（行下的红字）。
pub fn reasonText(reason: Reason) []const u8 {
    return switch (reason) {
        .none => "",
        .fixed => "保留给应用，不可修改。",
        .key_reserved => "这个按键不能用作快捷键，请换一个。",
        .control_reserved => "含 " ++ router.glyph.control ++ " Control 的组合保留给远端终端，请改用 " ++ router.glyph.command ++ " Command 组合。",
        .tab_reserved => "Tab 保留给远端终端，请换一个主键。",
        .reserved => "这个组合已被应用或系统使用，请换一个。",
        .needs_command => "需要包含 " ++ router.glyph.command ++ " Command，例如 " ++ comptime router.text(.{ .key = .k, .shift = true }) ++ "。",
    };
}

// ── 键帽（路由的唯一格式化） ──

pub const max_caps = router.max_caps;
pub const Caps = router.Caps;
/// 一个组合的键帽（每个修饰键与主键各一个）。
pub const caps = router.caps;
/// 录制中已按住的修饰键的键帽。
pub fn heldCaps(mods: Mods) Caps {
    return router.modifierCaps(.{ .key = .unknown, .command = mods.command, .control = mods.control, .shift = mods.shift, .option = mods.option });
}
/// 组合的整段文字（“⌘⇧T”），搜索与提示文字用。
pub fn chordText(chord: Chord, buffer: []u8) ![]const u8 {
    const value = router.text(chord);
    if (value.len > buffer.len) return error.NoSpaceLeft;
    @memcpy(buffer[0..value.len], value);
    return buffer[0..value.len];
}
/// 主键的显示文字（静态字符串）。
pub const keyName = router.keyName;

/// 平台按键名是不是修饰键本身（`ui.events.KeyCode` 的标签名；本文件不依赖 ui）。
pub fn modifierKey(name: []const u8) ?enum { command, control, shift, option } {
    const table = .{
        .{ "left_super", .command }, .{ "right_super", .command },
        .{ "left_ctrl", .control },  .{ "right_ctrl", .control },
        .{ "left_shift", .shift },   .{ "right_shift", .shift },
        .{ "left_alt", .option },    .{ "right_alt", .option },
    };
    inline for (table) |entry| if (std.mem.eql(u8, name, entry[0])) return entry[1];
    return null;
}

/// 两个面板里的动作（旧面板：`keys.rows[0..5]` 是“页签与分栏”，其余是“终端与应用”）。
pub const tab_actions = flatten(keys.rows[0..5]);
pub const terminal_actions = flatten(keys.rows[5..]);
fn flatten(comptime rows: []const keys.Row) []const Action {
    comptime {
        var count: usize = 0;
        for (rows) |row| count += row.actions.len;
        var list: [count]Action = undefined;
        var i: usize = 0;
        for (rows) |row| for (row.actions) |action| {
            list[i] = action;
            i += 1;
        };
        const final = list;
        return &final;
    }
}

const testing = std.testing;

test "settings keys model: judge follows the runtime rules and names the reason" {
    const map: Map = .{};
    try testing.expectEqual(Verdict.accept, judge(map, .new_tab, .{ .key = .x, .shift = true }));
    try testing.expectEqual(Verdict.same, judge(map, .new_tab, .{ .key = .t }));
    try testing.expectEqual(Verdict{ .conflict = .copy }, judge(map, .new_tab, .{ .key = .c }));
    try testing.expectEqual(Verdict{ .invalid = .control_reserved }, judge(map, .new_tab, .{ .key = .x, .control = true }));
    try testing.expectEqual(Verdict{ .invalid = .needs_command }, judge(map, .new_tab, .{ .key = .x, .command = false }));
    try testing.expectEqual(Verdict{ .invalid = .tab_reserved }, judge(map, .new_tab, .{ .key = .tab }));
    try testing.expectEqual(Verdict{ .invalid = .key_reserved }, judge(map, .new_tab, .{ .key = .escape }));
    try testing.expectEqual(Verdict{ .invalid = .key_reserved }, judge(map, .new_tab, .{ .key = .unknown }));
    try testing.expectEqual(Verdict{ .invalid = .fixed }, judge(map, .recent_tab, .{ .key = .x }));
    // 与固定 / 系统快捷键冲突：给出占用者，不写入。
    try testing.expectEqual(Verdict{ .invalid = .reserved }, judge(map, .new_tab, .{ .key = .b, .shift = true }));
    try testing.expectEqualStrings("命令历史", reservedName(.{ .key = .b, .shift = true }).?);
    try testing.expectEqual(Verdict{ .invalid = .reserved }, judge(map, .search, .{ .key = .q }));
    try testing.expectEqual(Verdict{ .invalid = .reserved }, judge(map, .search, .{ .key = .comma }));
    try testing.expect(reservedName(.{ .key = .e }) == null);
    // 判定为 accept 的组合 `Map.set` 一定接受；判定为不合规 / 冲突的一定拒绝。
    var copy = map;
    try apply(&copy, .new_tab, .{ .key = .x, .shift = true });
    try testing.expectError(error.Conflict, apply(&copy, .close_tab, .{ .key = .c }));
    try testing.expectError(error.RemoteKeyReserved, apply(&copy, .close_tab, .{ .key = .x, .control = true }));
    for (std.enums.values(Reason)) |reason| if (reason != .none) try testing.expect(reasonText(reason).len != 0);
}

test "settings keys model: swap gives the other action the previous chord and keeps the map valid" {
    var map: Map = .{};
    try testing.expectEqual(Action.copy, try swap(&map, .new_tab, .{ .key = .c }));
    try testing.expect(map.get(.new_tab).eql(.{ .key = .c }));
    try testing.expect(map.get(.copy).eql(.{ .key = .t }));
    try testing.expectError(error.NoConflict, swap(&map, .new_tab, .{ .key = .x, .shift = true }));
    // 恢复默认遇到冲突：默认值被别人占着时同样一步交换回来。
    try testing.expectEqual(Verdict{ .conflict = .copy }, judge(map, .new_tab, defaultOf(.new_tab)));
    _ = try swap(&map, .new_tab, defaultOf(.new_tab));
    try testing.expect(std.meta.eql(map, Map{}));
}

test "settings keys model: keycaps are one static cap per modifier and key" {
    const set = caps(.{ .key = .t, .shift = true });
    try testing.expectEqual(@as(usize, 3), set.len);
    try testing.expectEqualStrings("⇧", set.at(0));
    try testing.expectEqualStrings("⌘", set.at(1));
    try testing.expectEqualStrings("T", set.at(2));
    try testing.expectEqualStrings("", set.at(3));
    try testing.expectEqualStrings("PageUp", caps(.{ .key = .page_up, .command = false }).at(0));
    try testing.expectEqualStrings("F12", keyName(.f12));
    try testing.expectEqualStrings("1", keyName(.@"1"));
    var buffer: [32]u8 = undefined;
    try testing.expectEqualStrings("⌃⌥⇧⌘K", try chordText(.{ .key = .k, .control = true, .shift = true, .option = true }, &buffer));
    try testing.expectEqual(@as(usize, 2), heldCaps(.{ .command = true, .shift = true }).len);
    try testing.expect(modifierKey("left_super").? == .command);
    try testing.expect(modifierKey("a") == null);
    try testing.expectEqual(@as(usize, 16), tab_actions.len);
    try testing.expectEqual(@as(usize, 11), terminal_actions.len);
}
