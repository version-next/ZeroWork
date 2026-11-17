//! 快捷键的唯一入口（一致性审查 #9，用户拍板 2026-11-14 第 4 条）：注册、分发、让位与冲突判定。
//!
//! - **注册表**（`entries`）：应用里每一个快捷键都在这里登记一次——
//!   `[keys]` 里可配置的 27 个（键位来自 `config/keybindings.zig` 的 `Map`，即 config.toml 的 `[keys]`）、
//!   不可配置的应用快捷键（重命名页签、命令历史、设置、新建主机）、系统 / 文本编辑键（退出、隐藏、撤销……，
//!   由 AppKit 或获得焦点的输入框处理，登记在这里是为了冲突判定和菜单栏），以及只由某个控件处理的局部键
//!   （搜索上一个 / 下一个匹配、清屏、AI 输入框的另一种跟进……，登记在这里是为了提示文字只有一个来源）。
//!   插件自有的键（KVM 的 ⌃⌥Esc）由插件自己判定，文字用同一个格式化（shared/base/shortcut_glyphs.zig）。
//! - **分发**（`Router.route`）：按下的组合 → 哪个命令；可配置的优先，固定的被同一组合的可配置项覆盖时让出。
//! - **让位**（`Yield` / `Context`）：终端全屏程序、插件会话、正在输入法组字、文本输入框有焦点、浮层打开时，
//!   哪些命令把按键让给内容。各处不再单独判断，宿主只把事实填进 `Context`。
//! - **提示文字**（`text` / `Router.hint`）：Tooltip、右键菜单、菜单栏、设置 › 快捷键 都从这里取，返回静态字符串。
//!
//! 本文件是纯模型：不依赖 zenit `ui`，按键与修饰键用 `anytype` 按标签名对应（与 `Map.match` 相同）。
const std = @import("std");
const keys = @import("../../../config/keybindings.zig");
const host_actions = @import("../../../host/actions.zig");
const glyphs = @import("../../../shared/base/shortcut_glyphs.zig");

pub const Map = keys.Map;
pub const Chord = keys.Chord;
pub const KeyCode = keys.KeyCode;
pub const Action = keys.Action;

// ── 命令 ──

pub const Command = enum {
    // [keys]：与 `keybindings.Action` 同名同序（comptime 校验）。
    new_tab,
    close_tab,
    tab_1,
    tab_2,
    tab_3,
    tab_4,
    tab_5,
    tab_6,
    tab_7,
    tab_8,
    tab_9,
    previous_tab,
    next_tab,
    recent_tab,
    split_vertical,
    split_horizontal,
    copy,
    paste,
    search,
    completion,
    accept_completion,
    quick_connect,
    reconnect,
    sidebar,
    ai,
    upload,
    broadcast,
    // 不可配置的应用快捷键。
    rename_tab,
    command_history,
    open_settings,
    new_host,
    // 系统与文本编辑（AppKit / 获得焦点的输入框处理）。
    quit,
    hide,
    hide_others,
    minimize,
    undo,
    redo,
    cut,
    select_all,
    // 局部键：只由一个控件处理。
    search_next,
    search_previous,
    ai_alternate_follow_up,
    clear_screen,
};
pub const command_count = @typeInfo(Command).@"enum".field_names.len;

comptime {
    for (@typeInfo(Action).@"enum".field_names, 0..) |name, index| {
        if (!std.mem.eql(u8, name, @typeInfo(Command).@"enum".field_names[index])) @compileError("Command must start with keybindings.Action");
    }
}

/// `[keys]` 动作对应的命令。
pub fn fromAction(action: Action) Command {
    return @enumFromInt(@intFromEnum(action));
}
/// 命令对应的 `[keys]` 动作；不可配置的命令为 null。
pub fn toAction(command: Command) ?Action {
    const index = @intFromEnum(command);
    if (index >= @typeInfo(Action).@"enum".field_names.len) return null;
    return @enumFromInt(index);
}

pub const Kind = enum {
    /// config.toml `[keys]` 可改。
    configurable,
    /// 应用的固定快捷键（不可改；同一组合被可配置项占用时让出）。
    fixed,
    /// 系统 / 文本编辑键：AppKit 或获得焦点的输入框处理，路由不分发。
    system,
    /// 局部键：只由一个控件处理，路由不分发，只提供提示文字。
    local,
};

/// 让位条件：命中任一条时，路由把按键让给内容（`Decision.yield`）。
pub const Yield = packed struct(u8) {
    /// 终端以外的文本输入框有焦点。
    editor: bool = false,
    /// AI 消息的只读选区有焦点。
    ai_selection: bool = false,
    /// 阻挡页签切换的浮层打开（快速连接、菜单、编辑器、传输、SOCKS、帮助、AI 浮窗……）。
    panel: bool = false,
    /// 当前终端正在输入法组字。
    preedit: bool = false,
    /// 当前内容自己处理这个键：终端全屏程序（备用屏幕）、插件会话（例如 KVM 的 F2 进 BIOS）。
    content: bool = false,
    /// 当前终端的本地行编辑器打开。
    local_editor: bool = false,
    _pad: u2 = 0,
};

/// 宿主在每次按键时填写的事实。
pub const Context = struct {
    /// 窗口级输入法组字：所有快捷键暂停。
    composing: bool = false,
    editor: bool = false,
    ai_selection: bool = false,
    panel: bool = false,
    preedit: bool = false,
    content: bool = false,
    local_editor: bool = false,

    fn hits(self: Context, rule: Yield) bool {
        return (rule.editor and self.editor) or (rule.ai_selection and self.ai_selection) or (rule.panel and self.panel) or
            (rule.preedit and self.preedit) or (rule.content and self.content) or (rule.local_editor and self.local_editor);
    }
};

/// 固定组合怎么比较修饰键。
pub const Match = enum {
    /// 修饰键完全一致。
    exact,
    /// 只要求组合里的修饰键按下，其余修饰键不管（⌘N、⌘, 沿用旧宿主的判断）。
    loose,
    /// 页签 MRU：⌃Tab，⇧ 反向（Shift 不参与比较）。
    shift_free,
};

pub const Entry = struct {
    command: Command,
    kind: Kind,
    /// 动作名（设置 › 快捷键、菜单栏、冲突提示共用）。
    label: []const u8,
    /// 固定 / 系统 / 局部键的组合；可配置项为出厂默认值（实际键位读 `[keys]`）。
    chord: Chord,
    match: Match = .exact,
    yield: Yield = .{},
};

fn configurable(command: Command, name: []const u8, yield: Yield) Entry {
    return .{ .command = command, .kind = .configurable, .label = name, .chord = (Map{}).get(toAction(command).?), .yield = yield };
}

const rename_chord = host_actions.descriptor(.rename_tab).default_chord.?;

/// 注册表：每个命令恰好一条，按 `Command` 的顺序。
pub const entries = [_]Entry{
    configurable(.new_tab, "新建页签", .{}),
    configurable(.close_tab, "关闭页签", .{}),
    configurable(.tab_1, "直达第 1 个页签", .{}),
    configurable(.tab_2, "直达第 2 个页签", .{}),
    configurable(.tab_3, "直达第 3 个页签", .{}),
    configurable(.tab_4, "直达第 4 个页签", .{}),
    configurable(.tab_5, "直达第 5 个页签", .{}),
    configurable(.tab_6, "直达第 6 个页签", .{}),
    configurable(.tab_7, "直达第 7 个页签", .{}),
    configurable(.tab_8, "直达第 8 个页签", .{}),
    configurable(.tab_9, "直达第 9 个页签", .{}),
    configurable(.previous_tab, "上一个页签", .{}),
    configurable(.next_tab, "下一个页签", .{}),
    // ⌃Tab：保留给应用的固定边界（不可改），浮层打开、组字、本地行编辑时让给内容。
    .{ .command = .recent_tab, .kind = .configurable, .label = "最近使用的页签", .chord = (Map{}).get(.recent_tab), .match = .shift_free, .yield = .{ .panel = true, .preedit = true, .local_editor = true } },
    configurable(.split_vertical, "垂直分栏", .{}),
    configurable(.split_horizontal, "水平分栏", .{}),
    configurable(.copy, "复制", .{ .editor = true, .ai_selection = true }),
    configurable(.paste, "粘贴", .{ .editor = true, .ai_selection = true }),
    configurable(.search, "搜索当前终端", .{}),
    configurable(.completion, "打开补全菜单", .{ .editor = true }),
    configurable(.accept_completion, "采纳补全", .{}),
    configurable(.quick_connect, "快速连接", .{}),
    configurable(.reconnect, "立即重连", .{}),
    configurable(.sidebar, "显示或隐藏侧栏", .{}),
    configurable(.ai, "AI 运维助手", .{}),
    configurable(.upload, "上传面板", .{}),
    configurable(.broadcast, "广播输入", .{}),
    // F2：终端全屏程序（mc、htop、vim 映射）与转发按键的插件会话（KVM：F2 进 BIOS）自己用；组字时不抢。
    .{ .command = .rename_tab, .kind = .fixed, .label = "重命名页签", .chord = rename_chord, .yield = .{ .panel = true, .preedit = true, .content = true } },
    .{ .command = .command_history, .kind = .fixed, .label = "命令历史", .chord = .{ .key = .b, .shift = true } },
    .{ .command = .open_settings, .kind = .fixed, .label = "设置", .chord = .{ .key = .comma }, .match = .loose },
    .{ .command = .new_host, .kind = .fixed, .label = "新建主机", .chord = .{ .key = .n }, .match = .loose },
    .{ .command = .quit, .kind = .system, .label = "退出 ZeroWork", .chord = .{ .key = .q } },
    .{ .command = .hide, .kind = .system, .label = "隐藏 ZeroWork", .chord = .{ .key = .h } },
    .{ .command = .hide_others, .kind = .system, .label = "隐藏其他", .chord = .{ .key = .h, .option = true } },
    .{ .command = .minimize, .kind = .system, .label = "最小化", .chord = .{ .key = .m } },
    .{ .command = .undo, .kind = .system, .label = "撤销", .chord = .{ .key = .z } },
    .{ .command = .redo, .kind = .system, .label = "重做", .chord = .{ .key = .z, .shift = true } },
    .{ .command = .cut, .kind = .system, .label = "剪切", .chord = .{ .key = .x } },
    .{ .command = .select_all, .kind = .system, .label = "全选", .chord = .{ .key = .a } },
    .{ .command = .search_next, .kind = .local, .label = "下一个匹配", .chord = .{ .key = .@"return", .command = false } },
    .{ .command = .search_previous, .kind = .local, .label = "上一个匹配", .chord = .{ .key = .@"return", .command = false, .shift = true } },
    .{ .command = .ai_alternate_follow_up, .kind = .local, .label = "使用另一种跟进行为", .chord = .{ .key = .@"return", .shift = true } },
    .{ .command = .clear_screen, .kind = .local, .label = "清屏", .chord = .{ .key = .l, .command = false, .control = true } },
};

comptime {
    if (entries.len != command_count) @compileError("every Command needs exactly one entry");
    for (entries, 0..) |item, index| if (@intFromEnum(item.command) != index) @compileError("entries must follow Command order");
}

pub fn entry(command: Command) *const Entry {
    return &entries[@intFromEnum(command)];
}
pub fn label(command: Command) []const u8 {
    return entry(command).label;
}

// ── 文字：唯一的格式化 ──

/// 修饰键符号与显示顺序（shared/base 的唯一格式化）。
pub const glyph = glyphs;
pub const modifier_order = glyphs.order;

fn modifierGlyph(modifier: glyphs.Modifier) []const u8 {
    return glyphs.glyph(modifier);
}
fn modifierHeld(chord: Chord, modifier: glyphs.Modifier) bool {
    return (glyphs.Mods{ .command = chord.command, .control = chord.control, .shift = chord.shift, .option = chord.option }).has(modifier);
}

/// 主键的显示文字（静态字符串）。
pub fn keyName(key: KeyCode) []const u8 {
    return switch (key) {
        .@"return" => "↩",
        .tab => "Tab",
        .space => "Space",
        .delete => "⌫",
        .escape => "Esc",
        .forward_delete => "⌦",
        .left => "←",
        .right => "→",
        .down => "↓",
        .up => "↑",
        .slash => "/",
        .minus => "-",
        .equal => "=",
        .left_bracket => "[",
        .right_bracket => "]",
        .period => ".",
        .comma => ",",
        .semicolon => ";",
        .quote => "'",
        .backslash => "\\",
        .grave => "`",
        .page_up => "PageUp",
        .page_down => "PageDown",
        .unknown => "?",
        else => upper_names[@intFromEnum(key)],
    };
}
const upper_names = blk: {
    const names = @typeInfo(KeyCode).@"enum".field_names;
    var table: [names.len][]const u8 = undefined;
    for (names, 0..) |raw, index| {
        var name: [raw.len]u8 = undefined;
        for (raw, 0..) |char, i| name[i] = std.ascii.toUpper(char);
        const final = name;
        table[index] = &final;
    }
    break :blk table;
};

const key_count = @typeInfo(KeyCode).@"enum".field_names.len;
fn maskOf(chord: Chord) u4 {
    return @as(u4, @intFromBool(chord.command)) | @as(u4, @intFromBool(chord.control)) << 1 | @as(u4, @intFromBool(chord.shift)) << 2 | @as(u4, @intFromBool(chord.option)) << 3;
}
fn chordOfMask(key: KeyCode, mask: u4) Chord {
    return .{ .key = key, .command = mask & 1 != 0, .control = mask & 2 != 0, .shift = mask & 4 != 0, .option = mask & 8 != 0 };
}
/// 每个组合的文字都在编译期生成：调用方可以长期持有，不必管缓冲区。
const texts = blk: {
    @setEvalBranchQuota(400_000);
    var table: [key_count][16][]const u8 = undefined;
    for (0..key_count) |k| for (0..16) |m| {
        const chord = chordOfMask(@enumFromInt(k), @intCast(m));
        var value: []const u8 = "";
        for (modifier_order) |modifier| {
            if (modifierHeld(chord, modifier)) value = value ++ modifierGlyph(modifier);
        }
        value = value ++ keyName(chord.key);
        table[k][m] = value;
    };
    break :blk table;
};

/// 一个组合的整段文字（“⌘T”），静态字符串。
pub fn text(chord: Chord) []const u8 {
    return texts[@intFromEnum(chord.key)][maskOf(chord)];
}

/// 命令的出厂提示文字（编译期可用；只用于不可配置的局部键，或无法随配置变化的静态文案）。
pub fn defaultHint(comptime command: Command) []const u8 {
    return comptime text(entry(command).chord);
}

/// 手势提示：⌥ 拖动做矩形选择（终端；不是按键组合，没有路由分发）。
pub const block_selection_gesture = glyph.option ++ "+拖拽";

/// Tooltip / 无障碍名的统一写法：“名称 · 快捷键”；没有快捷键时只有名称。
pub fn tooltip(buffer: []u8, name: []const u8, hint: []const u8) []const u8 {
    if (hint.len == 0) return name;
    return std.fmt.bufPrint(buffer, "{s} · {s}", .{ name, hint }) catch name;
}

/// 一个组合最多 5 个键帽：修饰键 + 主键（顺序同 `modifier_order`）。
pub const max_caps = 5;
pub const Caps = struct {
    items: [max_caps][]const u8 = @splat(""),
    len: usize = 0,

    fn push(self: *Caps, value: []const u8) void {
        self.items[self.len] = value;
        self.len += 1;
    }
    pub fn slice(self: *const Caps) []const []const u8 {
        return self.items[0..self.len];
    }
    /// 第 `index` 个键帽的文字；没有时为空串。
    pub fn at(self: Caps, index: usize) []const u8 {
        return if (index < self.len) self.items[index] else "";
    }
};
/// 按住的修饰键的键帽（录制中）。
pub fn modifierCaps(chord: Chord) Caps {
    var out: Caps = .{};
    for (modifier_order) |modifier| if (modifierHeld(chord, modifier)) out.push(modifierGlyph(modifier));
    return out;
}
/// 一个组合的键帽（每个修饰键与主键各一个）。
pub fn caps(chord: Chord) Caps {
    var out = modifierCaps(chord);
    out.push(keyName(chord.key));
    return out;
}

// ── 路由 ──

pub const Decision = union(enum) {
    /// 不是快捷键：按键照常交给焦点控件。
    none,
    /// 窗口在组字：所有快捷键暂停，按键交给输入法。
    suspended,
    /// 执行这个命令。
    run: Command,
    /// 是这个命令的组合，但现在让给内容（终端全屏程序、插件会话、输入框……）。
    yield: Command,

    pub fn command(self: Decision) ?Command {
        return switch (self) {
            .run, .yield => |value| value,
            else => null,
        };
    }
    pub fn runs(self: Decision, which: Command) bool {
        return switch (self) {
            .run => |value| value == which,
            else => false,
        };
    }
};

fn keyOf(key: anytype) KeyCode {
    return keys.fromKey(key);
}
fn chordOfEvent(key: anytype, mods: anytype) Chord {
    return .{ .key = keyOf(key), .command = mods.super, .shift = mods.shift, .control = mods.ctrl, .option = mods.alt };
}

/// 一个窗口的路由：只持有 `[keys]` 的指针，键位改了（设置保存）立即生效。
pub const Router = struct {
    keys: *const Map,

    /// 当前生效的组合；固定命令被可配置项占用时为 null（让出）。系统 / 局部键总是自己的组合。
    pub fn chord(self: Router, command: Command) ?Chord {
        if (toAction(command)) |action| return self.keys.get(action);
        const item = entry(command);
        if (item.kind == .fixed) {
            for (std.meta.tags(Action)) |action| if (self.keys.get(action).eql(item.chord)) return null;
        }
        return item.chord;
    }

    /// 提示文字（Tooltip、菜单项右侧、设置页）；没有快捷键时为空串。
    pub fn hint(self: Router, command: Command) []const u8 {
        return if (self.chord(command)) |value| text(value) else "";
    }

    /// 按键对应哪个命令（不看让位）。可配置项优先；固定项被同一组合的可配置项覆盖时让出。
    pub fn match(self: Router, key: anytype, mods: anytype) ?Command {
        if (self.keys.match(key, mods)) |action| return fromAction(action);
        const pressed = chordOfEvent(key, mods);
        for (entries) |item| {
            if (item.kind == .system or item.kind == .local) continue;
            const wanted = if (toAction(item.command)) |action| self.keys.get(action) else item.chord;
            const hit = switch (item.match) {
                .exact => item.kind == .fixed and wanted.eql(pressed),
                .loose => wanted.key == pressed.key and (!wanted.command or pressed.command) and (!wanted.shift or pressed.shift) and (!wanted.control or pressed.control) and (!wanted.option or pressed.option),
                .shift_free => wanted.key == pressed.key and wanted.command == pressed.command and wanted.control == pressed.control and wanted.option == pressed.option,
            };
            if (hit) return item.command;
        }
        return null;
    }

    /// 分发判定：命令、让位，或不是快捷键。
    pub fn route(self: Router, key: anytype, mods: anytype, context: Context) Decision {
        if (context.composing) return .suspended;
        const command = self.match(key, mods) orelse return .none;
        return if (context.hits(entry(command).yield)) .{ .yield = command } else .{ .run = command };
    }
};

// ── 菜单栏（NSMenu）：由注册表生成，快捷键与路由一致 ──

/// 菜单栏里由 AppKit 处理的标准项（没有路由命令）。
pub const MenuRole = enum { about, show_all, zoom, bring_all_to_front };
pub const MenuItem = union(enum) {
    command: Command,
    role: MenuRole,
    separator,
};
pub const Menu = struct { title: []const u8, items: []const MenuItem };

/// 菜单栏的结构。菜单项的名称与快捷键都取自注册表（`label` / `Router.chord`），只收录含 ⌘ 的组合：
/// F2、⌃Tab、→ 这类同时是终端 / 内容按键的组合不进 AppKit 的快捷键匹配。
pub const menu_bar = [_]Menu{
    .{ .title = "ZeroWork", .items = &.{ .{ .role = .about }, .separator, .{ .command = .open_settings }, .separator, .{ .command = .hide }, .{ .command = .hide_others }, .{ .role = .show_all }, .separator, .{ .command = .quit } } },
    .{ .title = "会话", .items = &.{ .{ .command = .new_tab }, .{ .command = .new_host }, .{ .command = .quick_connect }, .{ .command = .reconnect }, .separator, .{ .command = .split_vertical }, .{ .command = .split_horizontal }, .separator, .{ .command = .upload }, .{ .command = .broadcast }, .separator, .{ .command = .close_tab } } },
    .{ .title = "编辑", .items = &.{ .{ .command = .undo }, .{ .command = .redo }, .separator, .{ .command = .cut }, .{ .command = .copy }, .{ .command = .paste }, .{ .command = .select_all }, .separator, .{ .command = .search }, .{ .command = .completion } } },
    .{ .title = "显示", .items = &.{ .{ .command = .sidebar }, .{ .command = .ai }, .{ .command = .command_history } } },
    .{ .title = "窗口", .items = &.{ .{ .command = .minimize }, .{ .role = .zoom }, .separator, .{ .command = .previous_tab }, .{ .command = .next_tab }, .separator, .{ .role = .bring_all_to_front } } },
};

/// 菜单项的显示名。
pub fn menuLabel(item: MenuItem) []const u8 {
    return switch (item) {
        .command => |command| label(command),
        .role => |role| switch (role) {
            .about => "关于 ZeroWork",
            .show_all => "显示全部",
            .zoom => "缩放",
            .bring_all_to_front => "前置全部窗口",
        },
        .separator => "",
    };
}

/// 菜单命令的编号（`command_id`），与 `Command` 一一对应。
pub const menu_command_base: u64 = 0x5a57_0000;
pub fn menuCommandId(command: Command) u64 {
    return menu_command_base + @intFromEnum(command);
}
pub fn fromMenuCommandId(id: u64) ?Command {
    if (id < menu_command_base or id >= menu_command_base + command_count) return null;
    return @enumFromInt(id - menu_command_base);
}

/// NSMenuItem 的 keyEquivalent（AppKit 的写法：字母小写、功能键用私有区字符）。
pub fn keyEquivalent(key: KeyCode) []const u8 {
    return switch (key) {
        .@"return" => "\r",
        .tab => "\t",
        .space => " ",
        .delete => "\x08",
        .escape => "\x1b",
        .forward_delete => "\x7f",
        .up => "\u{F700}",
        .down => "\u{F701}",
        .left => "\u{F702}",
        .right => "\u{F703}",
        .f1 => "\u{F704}",
        .f2 => "\u{F705}",
        .f3 => "\u{F706}",
        .f4 => "\u{F707}",
        .f5 => "\u{F708}",
        .f6 => "\u{F709}",
        .f7 => "\u{F70A}",
        .f8 => "\u{F70B}",
        .f9 => "\u{F70C}",
        .f10 => "\u{F70D}",
        .f11 => "\u{F70E}",
        .f12 => "\u{F70F}",
        .home => "\u{F729}",
        .end => "\u{F72B}",
        .page_up => "\u{F72C}",
        .page_down => "\u{F72D}",
        .unknown => "",
        else => keyName(key),
    };
}
fn lowerKeyName(key: KeyCode) []const u8 {
    return @tagName(key);
}

/// 菜单栏的一项在当前键位下的快捷键：没有组合或不含 ⌘ 时为 null（菜单里不写快捷键）。
pub fn menuChord(router: Router, item: MenuItem) ?Chord {
    const command = switch (item) {
        .command => |value| value,
        else => return null,
    };
    const value = router.chord(command) orelse return null;
    return if (value.command) value else null;
}
/// keyEquivalent 用的主键文字：字母用小写（⇧ 由修饰键表达）。
pub fn menuKey(chord: Chord) []const u8 {
    return switch (chord.key) {
        .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m, .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z => lowerKeyName(chord.key),
        else => keyEquivalent(chord.key),
    };
}

/// 某个组合已被固定 / 系统快捷键占用（设置 › 快捷键 的冲突提示）。
pub fn reservedBy(chord: Chord) ?Command {
    for (entries) |item| switch (item.kind) {
        .fixed, .system => if (item.chord.eql(chord)) return item.command,
        else => {},
    };
    return null;
}

const testing = std.testing;
const Mods = struct { super: bool = false, ctrl: bool = false, shift: bool = false, alt: bool = false };
const Key = enum { a, b, c, f, k, n, t, w, comma, tab, f2, right, one };

test "router: configurable keys come from [keys]; fixed keys yield to a configured chord" {
    var map: Map = .{};
    const router: Router = .{ .keys = &map };
    try testing.expectEqual(Command.copy, router.match(Key.c, Mods{ .super = true }).?);
    try testing.expectEqual(Command.command_history, router.match(Key.b, Mods{ .super = true, .shift = true }).?);
    try testing.expectEqualStrings("⇧⌘B", router.hint(.command_history));
    try testing.expectEqual(Command.rename_tab, router.match(Key.f2, Mods{}).?);
    try testing.expectEqual(Command.new_host, router.match(Key.n, Mods{ .super = true, .shift = true }).?);
    try testing.expectEqual(Command.open_settings, router.match(Key.comma, Mods{ .super = true }).?);
    try testing.expectEqual(Command.recent_tab, router.match(Key.tab, Mods{ .ctrl = true, .shift = true }).?);
    try testing.expect(router.match(Key.tab, Mods{ .ctrl = true, .super = true }) == null);
    try map.set(.new_tab, .{ .key = .b, .shift = true });
    try testing.expectEqual(Command.new_tab, router.match(Key.b, Mods{ .super = true, .shift = true }).?);
    try testing.expect(router.chord(.command_history) == null);
    try testing.expectEqualStrings("", router.hint(.command_history));
    try testing.expectEqualStrings("⇧⌘B", router.hint(.new_tab));
    try map.set(.search, .{ .key = .e });
    try testing.expect(router.match(Key.f, Mods{ .super = true }) == null);
    try testing.expectEqualStrings("⌘E", router.hint(.search));
}

test "router: yield rules are declared once per command" {
    const map: Map = .{};
    const router: Router = .{ .keys = &map };
    try testing.expect(router.route(Key.f2, Mods{}, .{}).runs(.rename_tab));
    try testing.expectEqual(Decision{ .yield = .rename_tab }, router.route(Key.f2, Mods{}, .{ .content = true }));
    try testing.expectEqual(Decision{ .yield = .rename_tab }, router.route(Key.f2, Mods{}, .{ .panel = true }));
    try testing.expect(router.route(Key.f2, Mods{}, .{ .local_editor = true }).runs(.rename_tab));
    try testing.expectEqual(Decision{ .yield = .recent_tab }, router.route(Key.tab, Mods{ .ctrl = true }, .{ .local_editor = true }));
    try testing.expectEqual(Decision{ .yield = .copy }, router.route(Key.c, Mods{ .super = true }, .{ .editor = true }));
    try testing.expectEqual(Decision{ .yield = .copy }, router.route(Key.c, Mods{ .super = true }, .{ .ai_selection = true }));
    try testing.expect(router.route(Key.c, Mods{ .super = true }, .{ .content = true }).runs(.copy));
    try testing.expectEqual(Decision.suspended, router.route(Key.c, Mods{ .super = true }, .{ .composing = true }));
    try testing.expectEqual(Decision.none, router.route(Key.a, Mods{}, .{}));
    // Right (accept completion) is matched but never needs Command; the terminal owns it.
    try testing.expect(router.route(Key.right, Mods{}, .{}).runs(.accept_completion));
}

test "router: one formatter; every text is static and caps follow the same order" {
    try testing.expectEqualStrings("⌘T", text(.{ .key = .t }));
    try testing.expectEqualStrings("⌃⌥⇧⌘K", text(.{ .key = .k, .control = true, .shift = true, .option = true }));
    try testing.expectEqualStrings("⇧↩", defaultHint(.search_previous));
    var buffer: [64]u8 = undefined;
    try testing.expectEqualStrings("设置 · ⌘,", tooltip(&buffer, "设置", defaultHint(.open_settings)));
    try testing.expectEqualStrings("设置", tooltip(&buffer, "设置", ""));
    try testing.expectEqualStrings("F2", text(.{ .key = .f2, .command = false }));
    try testing.expectEqualStrings("⌃Tab", text(.{ .key = .tab, .command = false, .control = true }));
    const set = caps(.{ .key = .t, .shift = true });
    try testing.expectEqual(@as(usize, 3), set.len);
    try testing.expectEqualStrings("⇧", set.at(0));
    try testing.expectEqualStrings("⌘", set.at(1));
    try testing.expectEqualStrings("T", set.at(2));
    try testing.expectEqualStrings("", set.at(3));
    try testing.expectEqualStrings("PageUp", keyName(.page_up));
    try testing.expectEqualStrings("1", keyName(.@"1"));
}

test "router: the menu bar is generated from the registry with the router's chords" {
    var map: Map = .{};
    const router: Router = .{ .keys = &map };
    var seen: [command_count]bool = @splat(false);
    for (menu_bar) |menu| for (menu.items) |item| switch (item) {
        .command => |command| {
            try testing.expect(!seen[@intFromEnum(command)]);
            seen[@intFromEnum(command)] = true;
            try testing.expect(entry(command).kind != .local);
            try testing.expectEqual(command, fromMenuCommandId(menuCommandId(command)).?);
        },
        else => {},
    };
    try testing.expectEqualStrings("⇧⌘B", text(menuChord(router, .{ .command = .command_history }).?));
    try testing.expectEqualStrings("b", menuKey(menuChord(router, .{ .command = .command_history }).?));
    try testing.expectEqualStrings(",", menuKey(menuChord(router, .{ .command = .open_settings }).?));
    try testing.expectEqualStrings("[", menuKey(menuChord(router, .{ .command = .previous_tab }).?));
    try map.set(.close_tab, .{ .key = .e, .shift = true });
    try testing.expectEqualStrings("e", menuKey(menuChord(router, .{ .command = .close_tab }).?));
    try testing.expect(menuChord(router, .{ .command = .close_tab }).?.shift);
    try testing.expect(fromMenuCommandId(1) == null);
    try testing.expectEqualStrings("关于 ZeroWork", menuLabel(.{ .role = .about }));
}

test "router: registry ids are unique and fixed chords never collide with factory keys" {
    const defaults: Map = .{};
    for (entries) |item| {
        if (item.kind == .configurable) continue;
        for (std.meta.tags(Action)) |action| try testing.expect(!defaults.get(action).eql(item.chord));
    }
    try testing.expectEqual(Command.command_history, reservedBy(.{ .key = .b, .shift = true }).?);
    try testing.expectEqual(Command.quit, reservedBy(.{ .key = .q }).?);
    try testing.expect(reservedBy(.{ .key = .e }) == null);
    try testing.expect(rename_chord.eql(.{ .key = .f2, .command = false }));
}
