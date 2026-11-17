//! 设置窗口的 view-model（ARCHITECTURE_PLAN §4.4、§4.5）。
//!
//! - 状态的唯一真相仍是 `Controller`（草稿、历史、搜索词、保存状态）；本文件的信号是它的投影，
//!   在每次 `dispatch` 末尾与宿主重建旧视图前由 `sync` 刷新，从不反向写回。
//! - 视图唯一的动作入口是 `dispatch(Intent)`；需要宿主做的事经 `Ports` 发 `Effect`，
//!   宿主完成后以 Intent 回流（`.save_finished`）。
//! - 生命周期：核心（Controller 指针 + Ports）随宿主存在，窗口未挂载时（重新打开前的定位、
//!   主窗口上的材质预览操作条）也能 dispatch；信号经 `attach` 建在设置窗口的 scope 上，
//!   窗口销毁时由宿主 `detach`。
//! - 选择器是纯函数：只读信号（`.get()` 建立依赖）与 Controller，不写任何状态，便宜可重复求值。
//!
//! 只使用 zenit 的响应式子集（`ui.Signal` / `ui.Scope`）。
const enablement = @import("../../../host/plugin_enablement.zig");
const std = @import("std");
const ui = @import("ui");
const Controller = @import("settings_controller.zig").Controller;
const values = @import("settings_values.zig");
pub const catalog = @import("catalog.zig");
pub const ids = @import("ids.zig");
pub const focus_ids = @import("focus_ids.zig");
/// 已改写为 `.yix` 的面板：文案、test_id 与搜索词（P3 3e）。
pub const fields = @import("pane_fields.zig");
pub const Row = fields.Row;
pub const PaneSpec = fields.Pane;
pub const keybinding_edit = @import("keybinding_edit.zig");
pub const KeyAction = keybinding_edit.Action;
const intent_mod = @import("intent.zig");
const ports_mod = @import("ports.zig");
/// 保存作用域与保存状态机（H-save，纯函数；设计见 `YIX_SPIKE.md`“保存状态机（H-save）”）。
pub const save_flow = @import("save_flow.zig");
pub const Prompt = save_flow.Prompt;
/// “清除全部数据…”的确认流程（S-12，纯函数状态机与文案投影）。
pub const data_cleanup = @import("data_cleanup.zig");
/// 外观与主题面板（P3 3e 外观包）读主题库与字体能力。
const themes = @import("../../../config/theme_registry.zig");
const fonts = @import("../../../config/appearance_font.zig");
/// 协议插件分类的数据（F-set-plugins：两级导航，插件是运行时数据）。
pub const plugin_pane = @import("plugin_pane.zig");
pub const PluginGroup = plugin_pane.Group;
/// “AI 辅助”面板（F-set-ai）：视图状态、动作与选择器（选择器收 `*ViewModel`，视图里写 `m.ai.<选择器>(vm, …)`）。
pub const ai = @import("ai_pane.zig");
const error_text = @import("../../../shared/base/error_text.zig");

pub const Intent = intent_mod.Intent;
pub const Command = intent_mod.Command;
pub const Decision = intent_mod.Decision;
pub const Key = intent_mod.Key;
pub const Location = intent_mod.Location;
pub const WindowCommand = intent_mod.WindowCommand;
pub const KeyCommand = intent_mod.KeyCommand;
/// view-model 发起的一次聚焦请求（S-6）：与 zenit 的 `FocusRequest` 同形（`id` 为 null 表示清焦点；`seq` 区分同一目标的
/// 连续请求），模板原样换成它交给窗口根的 `focusRequest`。view-model 只用 zenit 的响应式子集，不引用视图层类型。
pub const FocusAsk = struct { id: ?[]const u8 = null, seq: u32 = 0 };
/// view-model 发起的一条设置窗口 Toast（S-19，G38）：与 zenit 的 `NotificationPost` 同形（`seq` 每次请求加一，同值不重复弹），
/// 内容是一条文字提示；模板原样换成 `NotificationPost` 交给 `<W.NotificationHost post=…>`。窗口重挂时当前值不重放（组件语义）。
pub const ToastAsk = struct { seq: u64 = 0, text: []const u8 = "", tone: ToastTone = .success };
pub const ToastTone = enum { success, failure };
pub const Value = values.Value;
pub const Effect = ports_mod.Effect;
pub const Gate = ports_mod.Gate;
pub const Ports = ports_mod.Ports;

/// 内容区显示什么：分类概览、面板（整页或子页面）、搜索结果。
pub const Mode = enum { overview, panes, search };
pub const SaveState = @import("settings_controller.zig").State;

/// 投影信号；建在设置窗口的 scope 上。
pub const Signals = struct {
    mode: *ui.Signal(Mode),
    location: *ui.Signal(Location),
    /// 页头标题：“搜索结果”、子页面标题或分类名。
    title: *ui.Signal([]const u8),
    /// 历史能否后退（搜索中后退＝离开搜索，总是可用）。
    can_back: *ui.Signal(bool),
    /// 历史能否前进（搜索中不可用）。
    can_forward: *ui.Signal(bool),
    query: *ui.Signal([]const u8),
    /// 搜索框里的文字（S-4，`W.Input` 的受控值）：`.search` 先同步写它（编辑原地落地；关口拒绝时框里仍保留文字，
    /// 与旧的 Zig 搜索框一致），导航清空它（外部写入：整段替换，不回调 `onChange`）。
    search_field: *ui.Signal([]const u8),
    save_state: *ui.Signal(SaveState),
    dirty: *ui.Signal(bool),
    /// 当前打开的确认对话框（H-save）：窗口模板按它显示原生 `W.Modal`。
    prompt: *ui.Signal(Prompt),
    /// 投影修订号：每次 sync 加一；读草稿值的选择器靠它建立依赖。
    revision: *ui.Signal(u64),
    /// 内容页纪元（P3 3d）：宿主执行“重挂正文”时加一。面板正文仍是旧命令式实现，
    /// 只能整页重挂；`.yix` 外壳按它给内容页换 key。3e 面板 Yix 化后删除。
    epoch: *ui.Signal(u64),
    /// 内容视口的滚动偏移（S-5）：每个“位置”一个独立信号（`ScrollSlot`），内容页挂载时把当前位置的信号
    /// 双向绑到 `W.ScrollArea scrollY`。偏移单独成信号，滚动时不牵动其它选择器。
    scroll: [scroll_slots]*ui.Signal(f32),
    /// view-model 发起的聚焦（S-6，窗口模板根的 `focusRequest`）：按 `focus_ids` 在窗口里找目标。
    focus: *ui.Signal(FocusAsk),
    /// 面板里当前打开的弹层（字段帮助提示 / 选择框下拉）的 test_id；整窗 Escape 先收起它（P3 3e）。
    popup: *ui.Signal(?[]const u8),
    /// 快捷键行内录制的状态（P3 3e 第二批）：只有一行能处在非静止态；每行的选择器读它。
    key_edit: *ui.Signal(KeyEdit),
    /// “清除全部数据…”对话框（S-12）：状态变化时加一；对话框的选择器读它，再读 `ViewModel.cleanup`。
    cleanup: *ui.Signal(u64),
    /// 原地编辑（S-13）的草稿 / 问题变化时加一；编辑框的选择器读它。开合是 `popup`（`custom_popup`）。
    custom: *ui.Signal(u64),
    /// 设置窗口的 Toast 请求（S-19：保存成功 / 失败；窗口模板的 `W.NotificationHost` 跟随它）。
    toast: *ui.Signal(ToastAsk),
};

pub const HostStatus = ports_mod.HostStatus;
pub const ActionState = ports_mod.ActionState;
pub const UpdateStatus = ports_mod.UpdateStatus;

/// 快捷键行内录制的状态（交互设计：`docs/ui-revamp/YIX_SPIKE.md`“快捷键行的编辑交互”）。
pub const KeyEdit = struct {
    /// 处在非静止态的那一行；null = 全部静止。
    action: ?KeyAction = null,
    phase: KeyPhase = .idle,
    /// 键帽区有焦点（录制中、无效态恒为真；冲突态失焦后为假：不再接按键，整窗 Escape 收起提示）。
    capturing: bool = false,
    /// 录制中按住的修饰键。
    held: keybinding_edit.Mods = .{},
    /// 无效 / 冲突态：按下的组合。
    attempt: ?keybinding_edit.Chord = null,
    /// 冲突态：占用它的动作。
    other: ?KeyAction = null,
    reason: keybinding_edit.Reason = .none,
};
pub const KeyPhase = enum { idle, recording, invalid, conflict };
/// 键帽的色调（视图映射到原生 `W.Kbd` 的 `tone`）：静止中性、录制中强调、无效危险、冲突警示。
pub const KeyTone = enum { rest, recording, invalid, conflict };
/// 更新状态徽标的色调（视图映射到原生 `W.Tag` 的颜色；与旧 `settings_updates_styles.badgeInk` 同一判定）。
pub const UpdateTone = enum { idle, active, done, warning };

// ── 外观与主题面板的行数据（P3 3e 外观包） ──
pub const AppearanceStatus = ports_mod.AppearanceStatus;
pub const Texture = ports_mod.Texture;
pub const AppearanceEffect = ports_mod.AppearanceEffect;
pub const AppearanceIntent = intent_mod.AppearanceIntent;
pub const ThemeRecord = themes.Record;
pub const FontWeight = fonts.Weight;
pub const WeightRange = fonts.WeightRange;
/// 主题条的一张卡片（key 是主题 id）；颜色从记录读（`record` 归主题库所有）。
pub const ThemeCard = struct { id: []const u8, record: *const themes.Record, selected: bool, imported: bool, test_id: []const u8, menu_id: []const u8 };
/// 主题能否删除（右键菜单 / 删除按钮的文案与可用性）。
pub const ThemeRemoval = enum { removable, builtin, in_use, previewing, unavailable };
/// 字体族选项的来源（选择框的图标）。
pub const FontKind = enum { bundled, installed, missing, custom };
pub const FontChoice = struct { value: []const u8, label: []const u8, test_id: []const u8, kind: FontKind };
/// 终端预览的排版与配色（颜色是 RGBA u32；null = 主题库未加载，用 token 色）。
pub const PreviewText = struct { size: f32, weight: u16, family: u16, line_height: f32, background: ?u32, foreground: ?u32, prompt: ?u32, caret_width: f32, caret_height: f32, caret_low: bool };
/// 工作区缩略预览的配色与辅助显示开关。
pub const MiniPreview = struct { tokens: themes.UiTokens, terminal: u32, foreground: u32, running: u32, timestamps: bool, highlight: bool, collapsed: bool };
pub const TerminalColors = struct { background: u32 = 0, foreground: u32 = 0 };

/// 字体族选项的存储（系统已安装的等宽字体，窗口 scope 内只枚举一次；选项文字与 test_id 归这里）。
const FontList = struct {
    arena: std.heap.ArenaAllocator,
    base: []FontChoice = &.{},
    out: [2][]FontChoice = .{ &.{}, &.{} },

    fn load(scope: *ui.Scope) !*FontList {
        const self = try scope.allocator.create(FontList);
        self.* = .{ .arena = std.heap.ArenaAllocator.init(scope.allocator) };
        errdefer {
            self.arena.deinit();
            scope.allocator.destroy(self);
        }
        const a = self.arena.allocator();
        var installed = try fonts.installedMonospaceFamilies(a);
        defer installed.deinit();
        var list: std.ArrayList(FontChoice) = .empty;
        // 内置建议只决定顺序；没有安装的建议字体不是选项。
        for (fonts.families) |family| {
            if (!fonts.isBundled(family) and !fonts.isInstalled(family)) continue;
            try list.append(a, .{ .value = family, .label = family, .test_id = try std.fmt.allocPrint(a, "settings.option.font_family.{s}", .{family}), .kind = fontKindOf(family) });
        }
        for (installed.names) |family| {
            var duplicate = false;
            for (list.items) |choice| duplicate = duplicate or std.mem.eql(u8, choice.value, family);
            if (duplicate) continue;
            const name = try a.dupe(u8, family);
            try list.append(a, .{ .value = name, .label = name, .test_id = try std.fmt.allocPrint(a, "settings.option.font_family.{s}", .{name}), .kind = fontKindOf(name) });
        }
        self.base = list.items;
        self.out = .{ try a.alloc(FontChoice, list.items.len + 2), try a.alloc(FontChoice, list.items.len + 2) };
        try scope.onCleanup(FontList, self, cleanup);
        return self;
    }
    fn cleanup(self: *FontList) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self);
    }
};
/// 主题卡片的 test_id（`settings.theme.<id>`、右键菜单 `settings.theme.menu.<id>`）：主题 id 是数据（导入的主题），
/// 字符串归窗口 scope（同字体族选项）。
const ThemeIds = struct {
    arena: std.heap.ArenaAllocator,
    entries: std.ArrayList(Entry) = .empty,
    const Entry = struct { id: []const u8, test_id: []const u8, menu_id: []const u8 };

    fn create(scope: *ui.Scope) !*ThemeIds {
        const self = try scope.allocator.create(ThemeIds);
        self.* = .{ .arena = std.heap.ArenaAllocator.init(scope.allocator) };
        scope.onCleanup(ThemeIds, self, cleanup) catch |err| {
            self.arena.deinit();
            scope.allocator.destroy(self);
            return err;
        };
        return self;
    }
    fn get(self: *ThemeIds, id: []const u8) ?Entry {
        for (self.entries.items) |entry| if (std.mem.eql(u8, entry.id, id)) return entry;
        const a = self.arena.allocator();
        const owned = a.dupe(u8, id) catch return null;
        const entry: Entry = .{ .id = owned, .test_id = std.fmt.allocPrint(a, "settings.theme.{s}", .{id}) catch return null, .menu_id = std.fmt.allocPrint(a, "settings.theme.menu.{s}", .{id}) catch return null };
        self.entries.append(a, entry) catch return null;
        return entry;
    }
    fn cleanup(self: *ThemeIds) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self);
    }
};
fn fontKindOf(family: []const u8) FontKind {
    return if (fonts.isBundled(family)) .bundled else if (fonts.isInstalled(family)) .installed else .missing;
}

/// 左侧导航一行（`ViewModel.navItems`）。
pub const NavItem = struct { key: u64, page: u8, selected: bool, locked: bool };
/// 概览一行（`ViewModel.overviewItems`）：子页面序号；标题、图标与 id 由行内派生按当前分类读出（G21 已由上游修复，
/// 行数据不再自带分类）。
pub const OverviewItem = struct { key: u64, sub: u8, last: bool };
/// 内容视口滚动位置的槽数：普通页面 9 + 搜索 9。
pub const scroll_slots = 2 * catalog.categories.len;

/// 内容视口的滚动位置记在哪个槽（S-5）。规则与旧 `SettingsHost.mountedScrollOffset` 相同，按挂载时的内容判定：
/// - 搜索中：每个分类一份（短暂的搜索结果不覆盖页面的阅读位置）；
/// - 其余：每个分类一份（存 `Controller.scroll_offsets`；概览与它的子页面共用，导航到新位置时清零）。
pub const ScrollSlot = enum(u8) {
    _,

    pub fn normal(page: usize) ScrollSlot {
        return @enumFromInt(page);
    }
    pub fn search(page: usize) ScrollSlot {
        return @enumFromInt(catalog.categories.len + page);
    }
    /// 一页内容按挂载时的状态落在哪个槽。
    pub fn of(page: usize, filtered: bool) ScrollSlot {
        if (filtered) return search(page);
        return normal(page);
    }
    /// 当前 Controller 状态下要挂载的内容页的槽。
    pub fn current(c: *const Controller) ScrollSlot {
        return of(c.model.page_index, c.search_query.len != 0);
    }
    pub fn index(self: ScrollSlot) usize {
        return @intFromEnum(self);
    }
};

const overview_items = blk: {
    var table: [catalog.categories.len][]const OverviewItem = undefined;
    for (catalog.categories, 0..) |category, page| {
        var list: [category.subpages.len]OverviewItem = undefined;
        for (&list, 0..) |*item, sub| item.* = .{ .key = sub, .sub = sub, .last = sub + 1 == category.subpages.len };
        const final = list;
        table[page] = &final;
    }
    break :blk table;
};

pub const ViewModel = struct {
    controller: *Controller,
    ports: Ports,
    signals: ?Signals = null,
    revision: u64 = 0,
    epoch_value: u64 = 0,
    /// `contentEpochs` 返回的行 key；两份交替，换纪元时切片地址也换（Yix 行 key 按内容判等）。
    epoch_keys: [2][1]u64 = .{ .{0}, .{0} },
    /// 概览行摘要的文字缓冲（每个子页面两份交替，见 `overviewSummary`）。
    summaries: [max_subpages]SummarySlot = @splat(.{}),

    nav_items: [2][catalog.categories.len]NavItem = undefined,
    nav_flip: u1 = 0,

    /// 滚动偏移的存档（S-5，原 `SettingsHost.search_scroll_offsets`）：
    /// 随核心存在，窗口关闭再打开时恢复；普通页面与主题库的偏移仍存在 Controller 里。
    search_scroll: [catalog.categories.len]f32 = @splat(0),
    /// 当前（或即将挂载的）内容页的槽：`remountContent` / `attach` 按当时的 Controller 状态定下，`.scrolled` 按它存档。
    mounted_scroll: ScrollSlot = ScrollSlot.normal(0),
    /// 面板字段的显示文字（输入框原文 / 格式化值 / 目录路径）：每个字段两份交替（见 `slotText`）。
    field_text: [field_slot_count]TextSlot = @splat(.{}),
    pane_meta: [pane_slot_count]MetaSlot = @splat(.{}),
    /// 快捷键行的文字（无障碍名、无效 / 冲突说明）：每个动作两槽，各两份交替。
    key_text: [key_action_count][2]KeySlot = @splat(@splat(.{})),
    /// 键帽区的键帽（`keyCaps`），每个动作两份交替。
    key_caps: [key_action_count]CapsSlot = @splat(.{}),
    /// 关于与更新页的文字（版本行、徽标、标题、上次检查、通道、按钮），各两份交替。
    update_text: [6]TextSlot = @splat(.{}),
    /// 保存状态机（H-save，`save_flow.step`）：当前对话框与保存成功后的去向。随核心存在（窗口关闭再打开时已复位）。
    flow: save_flow.Flow = .{},
    /// 等待“未保存的设置”确认的导航（`.leave` 对话框）：选择、分类、子页面、历史，或清空搜索（`.search = ""`）。
    pending_leave: ?Intent = null,
    /// 已经告诉视图 / 宿主的对话框（`setPrompt` 只在变化时发 `Effect.prompt`）。
    shown_prompt: Prompt = .none,
    /// 最后打开的对话框种类与收起时的“草稿无效”判定：收起后正文沿用它们（常驻挂载的 Modal 退出动画期间不跳字）。
    last_prompt: Prompt = .close,
    last_invalid: bool = false,
    /// 确认对话框的说明文字（含作用域标题），两份交替。
    prompt_text: TextSlot = .{},
    /// “清除全部数据…”的确认流程（S-12）：随核心存在（清除进行中关窗再打开仍是同一状态）。
    cleanup: data_cleanup.State = .{},
    /// 对话框状态行的文字（阻塞原因 / 失败原因），两份交替。
    cleanup_text: TextSlot = .{},
    /// 原地编辑（S-13，“自定义 TERM 声明…”）：正在编辑的字段、草稿原文与提交失败的提示。
    custom_key: ?Key = null,
    custom_buf: [256]u8 = undefined,
    custom_len: usize = 0,
    custom_problem: ?[]const u8 = null,
    custom_slot: TextSlot = .{},
    /// 按钮行的 key（流程阶段），两份交替（Yix 行 key 按内容判等）。
    cleanup_keys: [2][1]u64 = .{ .{0}, .{0} },
    /// 删除导入主题的确认框：要删的主题 id 与名称（确认前拷贝在这里）。
    theme_delete_id: [128]u8 = undefined,
    theme_delete_id_len: usize = 0,
    theme_delete_message: [320]u8 = undefined,
    theme_delete_message_len: usize = 0,
    cleanup_flip: u1 = 0,
    /// Toast 的请求序号与文字（S-19；两份交替，Notifier 弹出时自己复制文字）。
    toast_seq: u64 = 0,
    toast_text: TextSlot = .{},
    /// 外观与主题页（P3 3e 外观包）：文字槽、主题卡片（两份交替）、字体族选项、字重缓存、“自定义字体”模式。
    appearance_text: [12]TextSlot = @splat(.{}),
    theme_cards: [2][max_theme_cards]ThemeCard = undefined,
    theme_flip: u1 = 0,
    /// 选过“自定义字体…”：字体族换成输入框（同旧 `custom_font_edit`：随宿主存在，不随重挂复位）。
    custom_font: bool = false,
    /// 正在逐字编辑的外观输入框（`schema` 下标）：只有它显示用户打的原文；滑块 / 选择 / 提交 / Escape 之后显示格式化的草稿值
    /// （`Controller.editKey` 也会写原文，所以不能按“有没有原文”判断；同旧 `Field.text` 只在编辑时跟随输入）。
    typed_field: ?usize = null,
    /// 投影信号所在的窗口 scope（字体族选项的存储归它）。
    scope: ?*ui.Scope = null,
    signals_generation: u64 = 0,
    detached: bool = false,
    font_list: ?*FontList = null,
    theme_ids: ?*ThemeIds = null,
    font_flip: u1 = 0,
    font_keys: [2][1]u64 = .{ .{0}, .{0} },
    font_key_flip: u1 = 0,
    weight_cache: fonts.SupportedWeights = .{},
    weight_list: fonts.SupportedWeights = .{},
    weight_family: [128]u8 = undefined,
    weight_family_len: usize = std.math.maxInt(usize),
    weight_keys: [2][1]u64 = .{ .{0}, .{0} },
    weight_key_flip: u1 = 0,
    /// 协议插件（F-set-plugins）：列表行数据（每组两份交替）、行 / 详情的 test_id、偏好字段的 id 与文字、分组说明。
    plugin_items: [plugin_pane.groups.len][2][plugin_pane.max_plugins]DrillItem = undefined,
    plugin_item_flip: [plugin_pane.groups.len]u1 = @splat(0),
    plugin_ids: [plugin_pane.max_plugins][plugin_part_count]IdSlot = undefined,
    plugin_pref_items: [2][plugin_pane.max_preferences]PluginPrefItem = undefined,
    plugin_pref_flip: u1 = 0,
    plugin_pref_ids: [plugin_pane.max_preferences][plugin_pref_part_count]IdSlot = undefined,
    plugin_pref_text: [plugin_pane.max_preferences]TextSlot = @splat(.{}),
    plugin_group_meta: [plugin_pane.groups.len]MetaSlot = @splat(.{}),
    /// “计划中”的行（路线条目，两份交替）。
    plugin_planned_items: [2][plugin_pane.roadmap.entries.len]PlannedItem = undefined,
    plugin_planned_flip: u1 = 0,
    /// 最近一次偏好编辑被 Controller 拒绝的原因（行下提示，同旧 `PreferenceControl.edit` 的错误名）。
    plugin_problem: ?PluginProblem = null,
    plugin_enable_problem: ?PluginProblem = null,
    plugin_toggle_label: MetaSlot = .{},
    plugin_notice_title: MetaSlot = .{},
    /// “AI 辅助”面板的视图状态（F-set-ai，`ai_pane.Ui`）：打开的对话框、编辑器表单、MCP 编辑表单、文字槽。
    ai: ai.Ui = .{},

    const max_subpages = 8;

    const SummarySlot = struct { flip: u1 = 0, buffers: [2][256]u8 = undefined };
    const TextSlot = struct { flip: u1 = 0, len: [2]usize = .{ 0, 0 }, buffers: [2][512]u8 = undefined };
    const MetaSlot = struct { flip: u1 = 0, len: [2]usize = .{ 0, 0 }, buffers: [2][160]u8 = undefined };
    const CapsSlot = struct { flip: u1 = 0, caps: [2]keybinding_edit.Caps = .{ .{}, .{} } };
    const KeySlot = struct { flip: u1 = 0, len: [2]usize = .{ 0, 0 }, buffers: [2][256]u8 = undefined };
    const key_action_count = std.enums.values(KeyAction).len;
    const max_theme_cards = 256;

    pub fn init(controller: *Controller, ports: Ports) ViewModel {
        return .{ .controller = controller, .ports = ports };
    }

    /// 在窗口 scope 上建投影信号并立即同步一次。重复 attach 会替换旧信号。
    pub fn attach(self: *ViewModel, scope: *ui.Scope) !void {
        const c = self.controller;
        self.revision += 1;
        self.mounted_scroll = ScrollSlot.current(c);
        self.scope = scope;
        self.detached = false;
        self.signals_generation += 1;
        const Forget = struct {
            vm: *ViewModel,
            generation: u64,
            fn run(f: *@This()) void {
                if (f.vm.signals_generation == f.generation) f.vm.signals = null;
            }
        };
        const forget = try scope.createState(Forget, .{ .vm = self, .generation = self.signals_generation });
        try scope.onCleanup(Forget, forget, Forget.run);
        self.font_list = null;
        self.theme_ids = null;
        self.signals = .{
            .mode = try scope.createSignal(Mode, modeOf(c)),
            .location = try scope.createSignal(Location, c.location()),
            .title = try scope.createText(titleOf(c), .{}),
            .can_back = try scope.createSignal(bool, canBackOf(c)),
            .can_forward = try scope.createSignal(bool, canForwardOf(c)),
            .query = try scope.createText(c.search_query, .{}),
            .search_field = try scope.createText(c.search_query, .{}),
            .focus = try scope.createSignal(FocusAsk, .{}),
            .popup = try scope.createSignal(?[]const u8, null),
            .key_edit = try scope.createSignal(KeyEdit, .{}),
            .cleanup = try scope.createSignal(u64, 0),
            .custom = try scope.createSignal(u64, 0),
            .toast = try scope.createSignal(ToastAsk, .{ .seq = self.toast_seq }),
            .save_state = try scope.createSignal(SaveState, c.state()),
            .dirty = try scope.createSignal(bool, c.model.dirty),
            .prompt = try scope.createSignal(Prompt, self.flow.prompt),
            .revision = try scope.createSignal(u64, self.revision),
            .epoch = try scope.createSignal(u64, self.epoch_value),
            .scroll = scroll: {
                var list: [scroll_slots]*ui.Signal(f32) = undefined;
                for (&list, 0..) |*signal, slot| signal.* = try scope.createSignal(f32, self.scrollStore(@enumFromInt(slot)).*);
                break :scroll list;
            },
        };
    }

    /// 宿主执行一次“重挂内容页”（旧正文整页重建的 `.yix` 等价物；P3 3d）。
    pub fn remountContent(self: *ViewModel) void {
        self.epoch_value +%= 1;
        self.epoch_keys[self.epoch_value & 1][0] = self.epoch_value;
        // 新内容页按此刻的 Controller 状态挂载，它的视口绑这个槽（`pageScroll`）。
        self.mounted_scroll = ScrollSlot.current(self.controller);
        if (self.signals) |s| {
            s.popup.set(null);
            s.key_edit.set(.{});
            s.epoch.set(self.epoch_value);
        }
    }
    // ── 滚动位置（S-5） ──

    fn scrollStore(self: *ViewModel, slot: ScrollSlot) *f32 {
        const c = self.controller;
        const index = @intFromEnum(slot);
        if (index < ScrollSlot.search(0).index()) return &c.scroll_offsets[index];
        return &self.search_scroll[index - ScrollSlot.search(0).index()];
    }
    /// 存档里某个槽的偏移。
    pub fn scrollOffset(self: *ViewModel, slot: ScrollSlot) f32 {
        return self.scrollStore(slot).*;
    }
    /// 改一个槽的偏移：存档与信号一起写；该槽的内容页正挂着时，视口在下一次有布局的 before-render 里滚过去。
    pub fn setScroll(self: *ViewModel, slot: ScrollSlot, offset: f32) void {
        self.scrollStore(slot).* = offset;
        if (self.signals) |s| s.scroll[@intFromEnum(slot)].set(offset);
    }
    /// 当前挂载的内容页的槽（宿主的数据清理流程记下 / 恢复原位置时用）。
    pub fn mountedScroll(self: *const ViewModel) ScrollSlot {
        return self.mounted_scroll;
    }
    /// 内容页视口的滚动偏移（`page.yix` 的 `scrollY`，配 `onScrollYChange` → `.scrolled`）。槽在内容页挂载前
    /// 定下（`remountContent` / `attach` 按当时的 Controller 状态），一个视口从挂载到卸载只读这一个槽的信号。
    pub fn pageScroll(self: *const ViewModel) f32 {
        return self.signals.?.scroll[@intFromEnum(self.mounted_scroll)].get();
    }

    // ── 整窗按键与焦点（S-6） ──

    /// 窗口模板根的 `onKeyDownCapture` 交来的按键（捕获阶段，先于任何子控件，与原宿主卡片上的捕获处理器同序；
    /// 窗口没有焦点时按键落到窗口内容根，同样经过）。输入框组字期间框架不调用捕获处理器，按键归输入法。
    /// 返回 true 表示接下了（模板随即 `e.stop()`：子控件与冒泡都不再收到）；正在录制快捷键、确认弹窗打开时放行
    /// （`Gate.window_keys`）。
    pub fn windowKey(self: *ViewModel, key: ui.events.KeyCode, modifiers: ui.events.Modifiers) bool {
        const command = windowCommand(key, modifiers) orelse return false;
        // 快捷键行在录制（含无效态）：整窗快捷键都不触发。Escape 在这里直接取消录制：焦点离开键帽区本已由 `onBlurWithin`
        // 结束录制（G31），但节点销毁 / 窗口失焦等“静默失焦”不触发 `onBlurWithin`，整窗捕获兜底；⌘W / ⌘, 放行给那一行，作为一个待判定的组合。
        if (self.keyCapturing()) {
            if (command == .escape) self.dispatch(Intent.cancelKey());
            return command == .escape;
        }
        // 确认对话框（原生 `W.Modal`）打开时按键归它：Escape 由浮层栈收起（经 `onOpenChange` 回到“继续编辑”）。
        if (self.flow.prompt != .none) return false;
        // F-set-ai：模型编辑器 / 删除确认（原生 `W.Modal`）同样。
        if (self.ai.modalOpen()) return false;
        // “清除全部数据…”对话框同理（S-12）：Escape 经 `onOpenChange` 变成“取消”（清除进行中不接）；⌘W / ⌘, 不关窗。
        if (self.cleanup.mode != .closed) return false;
        if (!self.ports.permits(.window_keys)) return false;
        self.dispatch(.{ .window = command });
        return true;
    }
    /// view-model 发起聚焦（`focus_ids` 里的目标）；目标不在树上时由框架挂起到它就绪。
    pub fn requestFocus(self: *ViewModel, id: []const u8) void {
        const s = self.signals orelse return;
        const current = s.focus.peek();
        s.focus.set(.{ .id = id, .seq = current.seq +% 1 });
    }
    /// 在设置窗口里弹一条 Toast（S-19）：窗口没挂着（没有信号）时不弹，同旧宿主的 `windowed` 判定。
    fn postToast(self: *ViewModel, text: []const u8, tone: ToastTone) void {
        const s = self.signals orelse return;
        self.toast_seq +%= 1;
        s.toast.set(.{ .seq = self.toast_seq, .text = swapIn(&self.toast_text, text), .tone = tone });
    }
    /// 窗口模板里 `W.NotificationHost` 的请求源（模板换成 zenit 的 `NotificationPost`）。
    pub fn toast(self: *const ViewModel) ToastAsk {
        return self.signals.?.toast.get();
    }
    /// 窗口模板根的 `focusRequest`（模板换成 zenit 的 `FocusRequest`）。
    pub fn focusRequest(self: *const ViewModel) FocusAsk {
        return self.signals.?.focus.get();
    }

    /// 窗口 scope 即将销毁：忘掉信号（内存随 scope 释放）。
    pub fn detach(self: *ViewModel) void {
        // The window scope (and its memos) retires at the runtime's next safe boundary: keep the
        // signals readable until that scope's cleanup forgets them.
        self.detached = true;
        self.scope = null;
        self.font_list = null;
        self.theme_ids = null;
    }
    pub fn attached(self: *const ViewModel) bool {
        return self.signals != null and !self.detached;
    }

    /// 从 Controller 刷新投影信号。宿主在 dispatch 之外直接改了 Controller 时（worker 回流、
    /// 重新打开窗口）也调用它；它只读 Controller。
    pub fn sync(self: *ViewModel) void {
        self.revision += 1;
        const s = self.signals orelse return;
        const c = self.controller;
        s.mode.set(modeOf(c));
        s.location.set(c.location());
        s.title.set(titleOf(c));
        s.can_back.set(canBackOf(c));
        s.can_forward.set(canForwardOf(c));
        s.query.set(c.search_query);
        s.save_state.set(c.state());
        s.dirty.set(c.model.dirty);
        s.revision.set(self.revision);
    }

    // ── 动作上行 ──

    pub fn dispatch(self: *ViewModel, intent: Intent) void {
        switch (intent) {
            .select_category, .open, .open_subpage, .back, .forward => self.navigate(intent, true),
            .search => |query| self.search(query),
            // 只翻一个视图信号，不重新投影（不建依赖、不重建）。
            .scrolled => |y| {
                // 视口回报的稳定偏移：同步写存档与该槽的信号（受控值的提议须同步落地），不重新投影。
                self.setScroll(self.mounted_scroll, y);
                return;
            },
            .window => |command| switch (command) {
                .escape => self.emit(.escape),
                .close => self.emit(.request_close),
            },
            .edit => |edit| self.editField(edit.key, edit.value),
            // 解析 / 校验失败已记成字段问题（行内提示），不再当作操作失败报告（与旧面板的 `Field.edit` 相同）。
            .edit_raw => |edit| self.controller.editRaw(edit.key.section, edit.key.key, edit.text) catch |err| {
                const index = catalog.schema.find(edit.key.section, edit.key.key);
                const recorded = if (index) |i| self.controller.raw_fields[i].problem != null else false;
                if (!recorded) self.emit(.{ .failed = err });
            },
            .popup => |popup| {
                const s = self.signals orelse return;
                if (popup.open) {
                    s.popup.set(popup.id);
                } else if (s.popup.peek()) |open| {
                    if (std.mem.eql(u8, open, popup.id)) s.popup.set(null);
                }
                return;
            },
            .choose => |key| {
                if (self.isSavingNow()) return;
                if (self.signals) |s| s.popup.set(null);
                if (directoryField(key)) {
                    self.emit(.{ .pick_directory = key });
                    return;
                }
                self.openCustom(key);
                return;
            },
            .custom_text => |text| {
                self.setCustom(text, null);
                return;
            },
            .custom_submit => |text| if (!self.submitCustom(text)) return,
            .draft_changed => {
                if (self.controller.validationProblem() == null) self.emit(.resolve_problems);
                self.emit(.rebuild);
            },
            .key => |command| if (!self.keyCommand(command)) return,
            .plugin_preference => |edit| self.editPluginPreference(edit),
            .plugin_enabled => |edit| self.editPluginEnabled(edit),
            .ai => |command| self.runAi(command),
            .locate_problem => self.locateProblem(),
            .command => |command| self.runCommand(command),
            .decide => |decision| self.advance(.{ .choose = decision }),
            .save_finished => |finished| {
                self.sync();
                if (finished.err) |err| {
                    self.emit(.{ .save_failed = err });
                    // Save Bar 留着并显示“保存失败，草稿已保留”；Toast 里给原因。
                    // 原因只查 `shared/base/error_text.zig`；原始错误名由宿主写进应用日志。
                    var buffer: [384]u8 = undefined;
                    self.postToast(std.fmt.bufPrint(&buffer, "保存失败：{s}", .{error_text.lineOr(err, "草稿已保留" ++ error_text.log_suffix)}) catch "保存失败，草稿已保留", .failure);
                    self.advance(.{ .saved = false });
                    self.sync();
                    return;
                }
                if (self.controller.close_ready) {
                    // “保存关闭”：窗口随即关闭，不弹 Toast。
                    self.flow = .{ .prompt = self.flow.prompt };
                    self.emit(.close_window);
                    return;
                }
                self.emit(.saved);
                self.postToast("设置已保存", .success);
                self.advance(.{ .saved = true });
                self.sync();
                return;
            },
            .appearance => |action| self.appearanceIntent(action),
            .cleanup => |event| {
                self.cleanupStep(event);
                return;
            },
        }
        self.sync();
    }

    /// 喂一个事件给清理流程（S-12）：状态变了才写信号；要宿主做的事发 `Effect.data_cleanup`。
    fn cleanupStep(self: *ViewModel, event: data_cleanup.Event) void {
        const before = self.cleanup;
        const action = data_cleanup.step(&self.cleanup, event);
        if (!data_cleanup.State.same(&before, &self.cleanup)) if (self.signals) |s| s.cleanup.set(s.cleanup.peek() +% 1);
        if (action != .none) self.emit(.{ .data_cleanup = action });
    }
    // ── 原地编辑（S-13：选择框里的“自定义 TERM 声明…”） ──

    /// 原地编辑打开时的弹层 id（`popup` 里的名字，也是 `W.Popover` 面板的 test_id）。
    pub const custom_popup = "settings.term.custom";
    /// 走系统目录面板的字段（同旧 `settings_picker.mount` 的 `download_dir` 分支）。
    fn directoryField(key: Key) bool {
        return std.mem.eql(u8, key.key, "download_dir");
    }
    fn openCustom(self: *ViewModel, key: Key) void {
        self.custom_key = key;
        var buffer: [256]u8 = undefined;
        const current = formatValue(self.controller.model.value, key, &buffer) catch "";
        self.setCustom(current, null);
        if (self.signals) |s| s.popup.set(custom_popup);
    }
    fn setCustom(self: *ViewModel, text: []const u8, problem: ?[]const u8) void {
        const n = @min(text.len, self.custom_buf.len);
        std.mem.copyForwards(u8, self.custom_buf[0..n], text[0..n]);
        self.custom_len = n;
        self.custom_problem = problem;
        if (self.signals) |s| s.custom.set(s.custom.peek() +% 1);
    }
    /// Enter：交 Controller 校验（同旧 `settings_picker.commit` 的单值分支）。通过则收起并重新投影；失败留在编辑框里提示。
    fn submitCustom(self: *ViewModel, text: []const u8) bool {
        const key = self.custom_key orelse return false;
        if (self.isSavingNow()) return false;
        const input = std.mem.trim(u8, text, " \t");
        const current = values.read(self.controller.model.value, key.section, key.key) orelse return false;
        const next: values.Value = switch (current) {
            .text => .{ .text = input },
            .unsigned => .{ .unsigned = std.fmt.parseInt(u32, input, 10) catch {
                self.setCustom(text, problemText(key, error.InvalidValue));
                return false;
            } },
            else => return false,
        };
        self.controller.editKey(key.section, key.key, next) catch |err| {
            self.setCustom(text, problemText(key, err));
            return false;
        };
        self.custom_problem = null;
        if (self.signals) |s| {
            if (s.popup.peek()) |open| if (std.mem.eql(u8, open, custom_popup)) s.popup.set(null);
            s.custom.set(s.custom.peek() +% 1);
        }
        return true;
    }
    fn customState(self: *const ViewModel) void {
        _ = self.signals.?.custom.get();
    }
    /// 编辑框里的原文（受控值：逐字编辑同步落地）。
    pub fn customText(self: *ViewModel) []const u8 {
        self.customState();
        return swapIn(&self.custom_slot, self.custom_buf[0..self.custom_len]);
    }
    pub fn customInvalid(self: *const ViewModel) bool {
        self.customState();
        return self.custom_problem != null;
    }
    pub fn customProblem(self: *const ViewModel) []const u8 {
        self.customState();
        return self.custom_problem orelse "";
    }
    pub fn customOpen(self: *const ViewModel) bool {
        return self.popupOpen(custom_popup);
    }

    /// 宿主收起确认态（设置窗口关闭）：不触发任何动作，同旧实现随窗口销毁的命令式对话框。清除进行中 / 失败态保留。
    pub fn dismissCleanup(self: *ViewModel) void {
        if (self.cleanup.mode != .confirm) return;
        self.cleanup.mode = .closed;
        if (self.signals) |s| s.cleanup.set(s.cleanup.peek() +% 1);
    }
    /// 宿主的确认态轮询要知道对话框是否停在确认态（`poll` 每帧复查阻塞原因）。
    pub fn cleanupConfirming(self: *const ViewModel) bool {
        return self.cleanup.mode == .confirm;
    }

    fn isSavingNow(self: *const ViewModel) bool {
        return self.controller.state() == .saving;
    }
    /// 搜索结果里这个分类是否显示：协议插件看注册表里的匹配，其余看面板匹配。
    pub fn pageShownInResults(self: *const ViewModel, page: usize) bool {
        if (page == plugin_pane.page) return self.pluginHits();
        return self.pageHits(page);
    }
    /// 搜索结果页是否一个命中都没有（“没有匹配的设置”）。
    pub fn noHits(self: *const ViewModel) bool {
        for (0..catalog.categories.len) |page| if (self.pageShownInResults(page)) return false;
        return true;
    }
    fn emit(self: *ViewModel, effect: Effect) void {
        self.ports.emit(effect);
    }

    /// 分类行、概览行与页头的后退 / 前进：同样的关口，清空搜索，新位置从顶部开始。
    /// `guarded`（用户发起的导航）：草稿里有目标作用域之外的改动时先确认（H-save，`save_flow.leaveNeedsConfirm`），
    /// 导航挂起到用户选择之后；跳到校验问题、确认后的导航本身不再确认。
    fn navigate(self: *ViewModel, intent: Intent, guarded: bool) void {
        if (!self.ports.permits(.navigate)) return;
        const c = self.controller;
        if (guarded and self.leaveBlocked(intent, targetOf(c, intent))) return;
        self.emit(.leave_page);
        const before = c.location();
        const was_searching = searching(c);
        c.setSearch("") catch |err| {
            self.emit(.{ .failed = err });
            return;
        };
        if (self.signals) |s| s.search_field.set("");
        switch (intent) {
            .select_category => |page| c.navigate(.{ .page = page }),
            .open => |target| c.navigate(target),
            .open_subpage => |sub| c.navigate(.{ .page = @intCast(c.model.page_index), .sub = sub }),
            // 搜索中后退只离开搜索（回到搜索开始处）。
            .back => if (!was_searching) {
                _ = c.goBack();
            },
            .forward => _ = c.goForward(),
            else => unreachable,
        }
        c.model.selectKey(0);
        const after = c.location();
        if (!std.meta.eql(after, before)) {
            self.setScroll(ScrollSlot.normal(after.page), 0);
            // F-set-ai：离开 / 换了提供方详情页，显示 API Key 与提供方级提示复位。
            if (!std.meta.eql(after.ai_provider, before.ai_provider)) self.ai.leaveDetail();
        }
        self.emit(.navigated);
    }

    fn search(self: *ViewModel, query: []const u8) void {
        // 搜索框的受控值必须在 `onChange` 里同步落地（G18）；关口拒绝只是不搜索。
        if (self.signals) |s| s.search_field.set(query);
        if (!self.ports.permits(.search)) return;
        // 清空搜索回到搜索开始处的页面（H-save）：那里的作用域装不下草稿时先确认；进入 / 改变搜索不用（搜索结果的
        // 作用域是全部字段）。
        if (std.mem.trim(u8, query, " \t\r\n").len == 0 and searching(self.controller)) {
            if (self.leaveBlocked(.{ .search = "" }, searchReturn(self.controller))) return;
        }
        self.applySearch(query);
    }
    fn applySearch(self: *ViewModel, query: []const u8) void {
        self.controller.setSearch(query) catch |err| {
            self.emit(.{ .failed = err });
            return;
        };
        self.emit(.rebuild);
    }

    /// 经 settings-value 边界改一个字段（校验 + dirty）。不重建：正在输入的控件要保住焦点。
    fn editField(self: *ViewModel, key: Key, value: values.Value) void {
        const c = self.controller;
        const before = values.read(c.model.value, key.section, key.key);
        c.editKey(key.section, key.key, value) catch |err| {
            self.emit(.{ .failed = err });
            return;
        };
        const event_switch = std.mem.eql(u8, key.section, "notify") and
            (std.mem.eql(u8, key.key, "transfer_done") or std.mem.eql(u8, key.key, "reconnect") or std.mem.eql(u8, key.key, "ai_ready"));
        if (event_switch and before != null and before.? == .boolean and !before.?.boolean and value == .boolean and value.boolean) {
            self.emit(.request_notification_authorization);
        }
    }

    fn locateProblem(self: *ViewModel) void {
        const c = self.controller;
        const problem = c.validationProblem() orelse return;
        self.emit(.{ .focus_problem = problem.ai_address });
        if (problem.page != 4) c.folded_sections = 0;
        const sub: ?u8 = if (problem.field_index) |index| catalog.forKey(problem.page, catalog.pages.keys[index].section, catalog.pages.keys[index].key) else switch (problem.page) {
            0 => 0, // 背景图片 → 主题
            3 => 1, // 传输内存预算 → SFTP 引擎
            4 => 0, // 提供方 / 模型草稿 → 服务提供方
            else => null,
        };
        self.setPrompt(.none);
        // F-set-ai：提供方 / 模型草稿的问题打开那个提供方的详情页（第三级）。
        const ai_target: ?u8 = if (problem.ai_address) |address| (if (address.provider < c.model.value.ai.provider_count and address.provider <= std.math.maxInt(u8)) @as(u8, @intCast(address.provider)) else null) else null;
        self.navigate(.{ .open = .{ .page = @intCast(problem.page), .sub = sub, .ai_provider = ai_target } }, false);
        self.setScroll(ScrollSlot.normal(problem.page), 0);
        if (problem.ai_address) |address| if (ai_target != null) {
            if (address.field == .model_id or address.field == .context_window) {
                const p = c.model.value.ai.providers[address.provider];
                if (address.model < p.model_count and address.model <= std.math.maxInt(u8)) _ = ai.run(self, .{ .edit_model = .{ .provider = @intCast(address.provider), .model = @intCast(address.model) } });
            } else self.requestFocus(ai.providerFocus(address.provider, address.field));
        };
        // 已改写的面板：聚焦出错的输入框（目标在新纪元挂好后由框架送达；滚动区跟随焦点）。
        if (problem.field_index) |index| if (focusTarget(catalog.pages.keys[index].section, catalog.pages.keys[index].key)) |target| self.requestFocus(target);
    }

    fn save(self: *ViewModel, close_after: bool) void {
        if (!self.ports.permits(.save)) return self.advance(.save_blocked);
        const c = self.controller;
        if (!c.model.dirty) {
            self.advance(.save_blocked);
            if (close_after) self.emit(.close_window);
            return;
        }
        if (c.validationProblem() != null) {
            self.advance(.save_blocked);
            self.emit(.report_problem);
            self.locateProblem();
            return;
        }
        self.emit(.{ .save = .{ .close_after = close_after } });
    }

    // ── 保存状态机（H-save） ──

    /// 喂一个事件给 `save_flow.step`，执行它要求的动作。
    fn advance(self: *ViewModel, event: save_flow.Event) void {
        const before = self.flow.prompt;
        const next = save_flow.step(self.flow, event);
        self.flow = next.flow;
        if (self.flow.prompt != before) self.setPrompt(self.flow.prompt);
        switch (next.action) {
            .none, .present => {},
            .save => self.save(false),
            .save_and_close => self.save(true),
            .discard_and_close => self.emit(.discard_and_close),
            .discard_and_leave => {
                // 宿主放弃草稿（`revertDraft`：回到最新已存配置、清理外观草稿资源）。宿主拒绝（保存中、主题安装进行中）时留在原处。
                self.emit(.revert);
                if (self.controller.model.dirty) {
                    self.pending_leave = null;
                    return;
                }
                self.leavePending();
            },
            .stay => {
                self.pending_leave = null;
                // 清空搜索被拦下：搜索框回到当前搜索词。
                if (self.signals) |s| s.search_field.set(self.controller.search_query);
            },
            .reset_scope => self.resetScope(),
            .leave => self.leavePending(),
            .close => self.emit(.close_window),
        }
        if (event == .choose and event.choose == .cancel) self.emit(.dismiss_decision);
    }
    fn setPrompt(self: *ViewModel, prompt: Prompt) void {
        if (prompt == .none) self.flow.prompt = .none;
        if (self.shown_prompt == prompt) return;
        self.shown_prompt = prompt;
        self.rememberPrompt(prompt);
        if (self.signals) |s| s.prompt.set(prompt);
        self.emit(.{ .prompt = prompt });
    }
    /// 去 `to` 之前是否要先确认（是则挂起 `intent`、弹出“未保存的设置”）。
    fn leaveBlocked(self: *ViewModel, intent: Intent, to: save_flow.Where) bool {
        const c = self.controller;
        if (save_flow.Where.eql(self.scopeHere(), to)) return false;
        if (!save_flow.leaveNeedsConfirm(c.dirty_fields, to)) return false;
        self.pending_leave = intent;
        self.advance(.ask_leave);
        return true;
    }
    /// 执行挂起的导航（已保存或已放弃）。
    fn leavePending(self: *ViewModel) void {
        const intent = self.pending_leave orelse return;
        self.pending_leave = null;
        switch (intent) {
            .search => |query| {
                if (self.signals) |s| s.search_field.set(query);
                self.applySearch(query);
            },
            else => self.navigate(intent, false),
        }
        self.sync();
    }
    /// 当前作用域恢复默认值（草稿）。
    fn resetScope(self: *ViewModel) void {
        if (!self.ports.permits(.reset)) return;
        self.controller.resetScope(save_flow.fieldsAt(self.scopeHere())) catch |err| {
            self.emit(.{ .failed = err });
            return;
        };
        // 外观字段可能变了：与手动改值同一条路径（宿主重新校验字体、按需准备背景、刷新材质预览）。
        self.emit(.{ .appearance = .changed });
        self.emit(.rebuild);
    }
    /// 右侧当前显示的作用域。
    fn scopeHere(self: *const ViewModel) save_flow.Where {
        return whereOf(self.controller);
    }
    /// 重新打开窗口时回到上次的位置（宿主发起，不是用户离开当前作用域：不确认）。草稿随核心保留时（预览 runner）
    /// 位置照常恢复，草稿仍在原处。
    pub fn restoreLocation(self: *ViewModel, target: Location) void {
        self.navigate(.{ .open = target }, false);
        self.sync();
    }
    /// 关窗前（宿主 `toggle` 判定草稿有改动时调用）：弹出“未保存的设置”。
    pub fn askClose(self: *ViewModel) void {
        self.advance(.ask_close);
        self.sync();
    }
    /// 宿主收起对话框（窗口关闭、跳到校验问题）：不触发任何选择。
    pub fn dismissPrompt(self: *ViewModel) void {
        self.pending_leave = null;
        self.flow = .{};
        self.shown_prompt = .none;
        if (self.signals) |s| if (s.prompt.peek() != .none) {
            self.rememberPrompt(.none);
            s.prompt.set(.none);
        };
    }

    fn runCommand(self: *ViewModel, command: Command) void {
        switch (command) {
            .save => self.save(false),
            .revert => self.emit(.revert),
            // 只有当前作用域的值与默认值不同才可点（视图已禁用；这里再判一次）。
            .reset_defaults => if (!self.isSavingNow() and save_flow.differsFromDefaults(self.controller.model.value, self.scopeHere())) self.advance(.ask_reset),
            .import_theme => self.emit(.import_theme),
            .export_logs => self.emit(.export_logs),
            .clear_logs => self.emit(.clear_logs),
            .clear_all => self.emit(.clear_all),
            .open_config_dir => self.emit(.open_config_dir),
            .credential_help => self.emit(.explain_credentials),
            .check_updates => self.emit(.check_updates),
            .open_update_release => self.emit(.open_update_release),
            .notification_permission => self.emit(.open_notification_permission),
            // 只在待重启状态可点（草稿是干净的，不会触发“未保存”确认之外的分支）。
            .restart_app => if (!self.isSavingNow()) self.emit(.restart_app),
        }
    }

    // ── “清除全部数据…”对话框（S-12，`view/data_cleanup.yix`；文案与可用性在 `data_cleanup.zig`） ──

    fn cleanupState(self: *const ViewModel) *const data_cleanup.State {
        _ = self.signals.?.cleanup.get();
        return &self.cleanup;
    }
    pub fn cleanupOpen(self: *const ViewModel) bool {
        return data_cleanup.open(self.cleanupState());
    }
    pub fn cleanupTitle(self: *const ViewModel) []const u8 {
        return data_cleanup.title(self.cleanupState());
    }
    pub fn cleanupHeadline(self: *const ViewModel) []const u8 {
        return data_cleanup.headline(self.cleanupState());
    }
    pub fn cleanupHeadlineWarning(self: *const ViewModel) bool {
        return data_cleanup.headlineWarning(self.cleanupState());
    }
    pub fn cleanupMessage(self: *ViewModel) []const u8 {
        return swapIn(&self.cleanup_text, data_cleanup.message(self.cleanupState()));
    }
    pub fn cleanupMessageWarning(self: *const ViewModel) bool {
        return data_cleanup.messageWarning(self.cleanupState());
    }
    pub fn cleanupCancelLabel(self: *const ViewModel) []const u8 {
        return data_cleanup.cancelLabel(self.cleanupState());
    }
    pub fn cleanupCancelA11y(self: *const ViewModel) []const u8 {
        return data_cleanup.cancelA11y(self.cleanupState());
    }
    pub fn cleanupCancelDisabled(self: *const ViewModel) bool {
        return data_cleanup.cancelDisabled(self.cleanupState());
    }
    pub fn cleanupPrimaryLabel(self: *const ViewModel) []const u8 {
        return data_cleanup.primaryLabel(self.cleanupState());
    }
    pub fn cleanupPrimaryA11y(self: *const ViewModel) []const u8 {
        return data_cleanup.primaryA11y(self.cleanupState());
    }
    pub fn cleanupPrimaryShown(self: *const ViewModel) bool {
        return data_cleanup.primaryShown(self.cleanupState());
    }
    pub fn cleanupPrimaryDisabled(self: *const ViewModel) bool {
        return data_cleanup.primaryDisabled(self.cleanupState());
    }
    pub fn cleanupPrimaryBusy(self: *const ViewModel) bool {
        return data_cleanup.primaryBusy(self.cleanupState());
    }
    /// 按钮行的 key：流程阶段（换阶段时按钮行重挂，“取消 / 退出应用”重新取得焦点）。
    pub fn cleanupPhase(self: *ViewModel) []const u64 {
        const phase: u64 = @intFromEnum(self.cleanupState().mode);
        if (self.cleanup_keys[self.cleanup_flip][0] == phase) return &self.cleanup_keys[self.cleanup_flip];
        self.cleanup_flip +%= 1;
        self.cleanup_keys[self.cleanup_flip][0] = phase;
        return &self.cleanup_keys[self.cleanup_flip];
    }

    // ── 面板正文（P3 3e：`view/panes/*.yix` 与 `view/components/rows.yix`） ──
    //
    // 面板的形态（显示哪些面板、哪些行、哪一行是最后一行）在内容页挂载时定下，不建依赖：位置与搜索词变了
    // 宿主换纪元整页重挂（同 `contentMode`）。字段的值、校验问题、禁用态、弹层与宿主状态跟随 `revision` /
    // 各自的信号按信号局部更新——编辑一个字段不重挂任何节点。

    /// 面板在当前内容页是否显示：子页面只显示目录列出的面板；搜索时按面板的匹配词过滤。
    pub fn paneShown(self: *const ViewModel, item: *const fields.Pane) bool {
        const c = self.controller;
        if (searching(c)) return fields.paneMatches(c.search_query, item);
        if (!c.drill_down) return true;
        const sub = catalog.get(item.page, c.model.subpage) orelse return true;
        return item.page != c.model.page_index or catalog.contains(sub, item.id);
    }
    /// 行在搜索时是否命中（不搜索时全部显示）；只读行另看宿主有没有给值（`infoShown`）。
    pub fn rowShown(self: *const ViewModel, item: *const fields.Pane, row: Row) bool {
        if (fields.rowMatches(self.controller.search_query, item, row)) return true;
        // 快捷键行另按当前组合匹配（旧 `settings_keys.shortcutRow` 的 `chordText`）。
        const action = row.shortcut orelse return false;
        var buffer: [32]u8 = undefined;
        const chord = keybinding_edit.chordText(self.controller.model.value.keys.get(action), &buffer) catch return false;
        return catalog.search.matches(fields.effectiveQuery(self.controller.search_query, item.page), chord);
    }
    /// 面板里最后一个显示的行（它下面没有分隔线）。
    pub fn rowLast(self: *const ViewModel, item: *const fields.Pane, row: Row) bool {
        var last: ?Row = null;
        for (item.rows) |candidate| if (self.rowShown(item, candidate) and self.infoPresent(candidate)) {
            last = candidate;
        };
        const found = last orelse return false;
        return std.mem.eql(u8, found.label, row.label);
    }
    /// 分类在搜索结果里有没有命中的面板（没有时整块不显示）。
    pub fn pageHits(self: *const ViewModel, page: usize) bool {
        return fields.pageMatches(self.controller.search_query, page);
    }
    /// 面板页头右侧的说明：有草稿摘要的显示摘要（跟随草稿），否则是固定说明。
    pub fn paneMeta(self: *ViewModel, item: *const fields.Pane) []const u8 {
        const render = item.summary orelse return item.meta;
        _ = self.signals.?.revision.get();
        var buffer: [160]u8 = undefined;
        const text = render(self.controller.model.value, &buffer) catch return item.meta;
        return swapIn(&self.pane_meta[paneSlot(item)], text);
    }

    /// 输入框显示的文字：用户打的原文（含无效的），否则是草稿值的格式化（重连间隔按“1, 2, 4, 8, 16”）。
    pub fn fieldText(self: *ViewModel, row: Row) []const u8 {
        _ = self.signals.?.revision.get();
        const key = row.key.?;
        const index = catalog.schema.find(key.section, key.key).?;
        var buffer: [512]u8 = undefined;
        const text = self.controller.raw_fields[index].input orelse (formatValue(self.controller.model.value, key, &buffer) catch "");
        return swapIn(&self.field_text[fieldSlot(key)], text);
    }
    /// 选择框当前值（草稿里的文字）。
    pub fn selectValue(self: *ViewModel, row: Row) ?[]const u8 {
        const value = self.valueOf(row.key.?) orelse return null;
        if (value != .text) return null;
        return swapIn(&self.field_text[fieldSlot(row.key.?)], value.text);
    }
    /// 字段的校验提示（无问题时为空串）。
    pub fn fieldProblem(self: *const ViewModel, row: Row) []const u8 {
        _ = self.signals.?.revision.get();
        const key = row.key orelse return "";
        const problem = self.controller.fieldProblem(catalog.schema.find(key.section, key.key).?) orelse return "";
        return problemText(key, problem);
    }
    pub fn fieldInvalid(self: *const ViewModel, row: Row) bool {
        return self.fieldProblem(row).len != 0;
    }
    /// 字段是否不可编辑：保存中，或它依赖的开关关着（`Controller.fieldApplicable`：自动重连 → 次数 → 间隔 / 缓存）。
    pub fn fieldDisabled(self: *const ViewModel, row: Row) bool {
        _ = self.signals.?.revision.get();
        if (self.isSaving()) return true;
        const key = row.key orelse return false;
        return !self.controller.fieldApplicable(catalog.schema.find(key.section, key.key).?);
    }

    /// 某个弹层（帮助提示 / 选择框下拉，按 test_id）是否打开。
    /// 删除导入主题确认框的说明与目标（只在框打开时有意义）。
    pub fn themeDeleteMessage(self: *const ViewModel) []const u8 {
        _ = self.popupOpen(ids.theme_delete);
        return self.theme_delete_message[0..self.theme_delete_message_len];
    }
    pub fn themeDeleteId(self: *const ViewModel) []const u8 {
        return self.theme_delete_id[0..self.theme_delete_id_len];
    }
    pub fn popupOpen(self: *const ViewModel, id: []const u8) bool {
        const open = self.signals.?.popup.get() orelse return false;
        return std.mem.eql(u8, open, id);
    }
    /// 整窗 Escape 在面板里的分层（旧 `Binding.consumeEscape`）：先收起打开的提示 / 下拉，再撤回正在编辑的输入框并清焦点。
    /// `focused` 是此刻持有焦点的控件的 focus id（模板写在控件上的 `focusId`；宿主从 zenit 的
    /// `focus_targets.targetName` 读出，没有名字时为 null），按它认出正在编辑的输入框——不看节点的 test_id。
    /// 宿主在旧正文之后、提供方与选择器之前调用；返回 true 表示接下了。
    pub fn consumeEscape(self: *ViewModel, focused: ?[]const u8) bool {
        const s = self.signals orelse return false;
        // 快捷键行的冲突提示（Tab 离开后不再接按键，Escape 经整窗分层到这里）。先于弹层：非静止时键帽区的提示
        // 不显示（`rows.yix` 的 `tipOpen`），`popup` 里可能还记着它。
        if (s.key_edit.peek().action != null) {
            s.key_edit.set(.{});
            return true;
        }
        if (s.popup.peek() != null) {
            s.popup.set(null);
            return true;
        }
        // 正在编辑的输入框（表单字段 / F-set-ai 提供方的连接输入框）：Esc 只让它失焦。改过的值回到
        // 聚焦时的值是原生 Input 的统一规则（OverlayHost `install` → `Cx.input_escape`），在这之前已经发生。
        const editing = ai.isProviderFocus(focused) or (if (focused) |id| fields.findInputByFocus(id) != null else false);
        if (!editing) return false;
        s.focus.set(.{ .id = null, .seq = s.focus.peek().seq +% 1 });
        self.sync();
        return true;
    }

    // ── 快捷键行内录制（P3 3e 第二批；判定与键帽在 `keybinding_edit.zig`） ──

    /// 有一行在录制（含无效态，或冲突态且键帽区仍有焦点）：整窗快捷键放行（`windowKey`）。
    pub fn keyCapturing(self: *const ViewModel) bool {
        const s = self.signals orelse return false;
        const edit = s.key_edit.peek();
        return edit.action != null and edit.capturing;
    }
    /// 键帽区（`W.Pressable`）的 `onKeyDown`（组件根的捕获槽，先于它自己的 Enter / Space 激活）：这一行在录制时接下按键。
    /// Tab 不接（照常移焦，失焦结束录制）；Esc 取消；单独的修饰键只更新“按住的修饰键”；其余按组合判定。返回 true 表示接下了。
    pub fn keyDown(self: *ViewModel, action: KeyAction, key: ui.events.KeyCode, modifiers: ui.events.Modifiers) bool {
        if (!self.recordingRow(action)) return false;
        // Tab：不接，照常移焦；焦点离开键帽区时由它的 `onBlurWithin` 结束录制（G31，`Intent.blurKey`）。
        if (key == .tab) return false;
        if (key == .escape) {
            self.dispatch(Intent.keyCommand(.cancel));
            return true;
        }
        if (keybinding_edit.modifierKey(@tagName(key))) |which| {
            var held = modsOf(modifiers);
            switch (which) {
                .command => held.command = true,
                .control => held.control = true,
                .shift => held.shift = true,
                .option => held.option = true,
            }
            self.dispatch(Intent.keyCommand(.{ .hold = held }));
            return true;
        }
        self.dispatch(Intent.keyCommand(.{ .press = .{ .key = keybinding_edit.keys.fromKey(key), .command = modifiers.super, .control = modifiers.ctrl, .shift = modifiers.shift, .option = modifiers.alt } }));
        return true;
    }
    /// 录制中松开修饰键：更新“按住的修饰键”。
    pub fn keyUp(self: *ViewModel, action: KeyAction, key: ui.events.KeyCode, modifiers: ui.events.Modifiers) bool {
        if (!self.recordingRow(action)) return false;
        const which = keybinding_edit.modifierKey(@tagName(key)) orelse return false;
        var held = modsOf(modifiers);
        switch (which) {
            .command => held.command = false,
            .control => held.control = false,
            .shift => held.shift = false,
            .option => held.option = false,
        }
        self.dispatch(Intent.keyCommand(.{ .hold = held }));
        return true;
    }
    fn recordingRow(self: *const ViewModel, action: KeyAction) bool {
        const s = self.signals orelse return false;
        const edit = s.key_edit.peek();
        return edit.action == action and edit.capturing;
    }
    fn modsOf(modifiers: ui.events.Modifiers) keybinding_edit.Mods {
        return .{ .command = modifiers.super, .control = modifiers.ctrl, .shift = modifiers.shift, .option = modifiers.alt };
    }
    /// 返回 true 表示草稿变了（随后重新投影）。
    fn keyCommand(self: *ViewModel, command: KeyCommand) bool {
        const s = self.signals orelse return false;
        const edit = s.key_edit.peek();
        switch (command) {
            .record => |action| {
                if (keybinding_edit.fixed(action) or self.isSavingNow()) return false;
                s.popup.set(null);
                s.key_edit.set(.{ .action = action, .phase = .recording, .capturing = true });
                self.requestFocus(keyFocus(action));
                return false;
            },
            .hold => |mods| {
                if (edit.action == null or !edit.capturing) return false;
                var next = edit;
                next.held = mods;
                s.key_edit.set(next);
                return false;
            },
            .press => |chord| {
                const action = edit.action orelse return false;
                if (!edit.capturing) return false;
                return self.offerKey(action, chord, true);
            },
            .cancel => {
                s.key_edit.set(.{});
                return false;
            },
            .blur => |action| {
                if (edit.action != action) return false;
                if (edit.phase == .conflict) {
                    var next = edit;
                    next.capturing = false;
                    next.held = .{};
                    s.key_edit.set(next);
                } else s.key_edit.set(.{});
                return false;
            },
            .swap => {
                const action = edit.action orelse return false;
                const chord = edit.attempt orelse return false;
                if (edit.phase != .conflict or self.isSavingNow()) return false;
                var map = self.controller.model.value.keys;
                _ = keybinding_edit.swap(&map, action, chord) catch |err| {
                    self.emit(.{ .failed = err });
                    return false;
                };
                return self.commitKeys(map);
            },
            .reset => |action| {
                if (keybinding_edit.fixed(action) or self.isSavingNow()) return false;
                return self.offerKey(action, keybinding_edit.defaultOf(action), false);
            },
        }
    }
    /// 把一个组合交给某一行：合规且不冲突就写草稿；与当前值相同回到静止；否则进入无效 / 冲突态。
    fn offerKey(self: *ViewModel, action: KeyAction, chord: keybinding_edit.Chord, capturing: bool) bool {
        const s = self.signals.?;
        var map = self.controller.model.value.keys;
        switch (keybinding_edit.judge(map, action, chord)) {
            .same => {
                s.key_edit.set(.{});
                return false;
            },
            .accept => {
                keybinding_edit.apply(&map, action, chord) catch |err| {
                    self.emit(.{ .failed = err });
                    return false;
                };
                return self.commitKeys(map);
            },
            .conflict => |other| s.key_edit.set(.{ .action = action, .phase = .conflict, .capturing = capturing, .attempt = chord, .other = other }),
            .invalid => |reason| s.key_edit.set(.{ .action = action, .phase = .invalid, .capturing = capturing, .attempt = chord, .reason = reason }),
        }
        return false;
    }
    /// 整张表一次事务写进草稿（同旧录制对话框的 `recordedKeysChanged`），这一行回到静止（键帽区仍保留焦点）。
    fn commitKeys(self: *ViewModel, map: keybinding_edit.Map) bool {
        self.controller.editKeys(map) catch |err| {
            self.emit(.{ .failed = err });
            return false;
        };
        if (self.signals) |s| s.key_edit.set(.{});
        return true;
    }
    fn keyFocus(action: KeyAction) []const u8 {
        return switch (action) {
            inline else => |a| comptime fields.keys.row(a).ids.focus,
        };
    }

    /// 这一行当前的录制状态（读信号建依赖）；不是这一行时为 null。
    fn keyEditOf(self: *const ViewModel, action: KeyAction) ?KeyEdit {
        const edit = self.signals.?.key_edit.get();
        return if (edit.action == action) edit else null;
    }
    fn keyChord(self: *const ViewModel, action: KeyAction) keybinding_edit.Chord {
        _ = self.signals.?.revision.get();
        return self.controller.model.value.keys.get(action);
    }
    pub fn keyPhase(self: *const ViewModel, action: KeyAction) KeyPhase {
        const edit = self.keyEditOf(action) orelse return .idle;
        return edit.phase;
    }
    /// 键帽区显示的键帽：静止是草稿里的组合；录制中是按住的修饰键；无效 / 冲突是按下的组合。
    fn keyCapsOf(self: *const ViewModel, action: KeyAction) keybinding_edit.Caps {
        if (self.keyEditOf(action)) |edit| switch (edit.phase) {
            .recording => return keybinding_edit.heldCaps(edit.held),
            .invalid, .conflict => if (edit.attempt) |chord| return keybinding_edit.caps(chord),
            .idle => {},
        };
        return keybinding_edit.caps(self.keyChord(action));
    }
    /// 键帽区的键帽（原生 `W.Kbd` 的 `keys`，每键一个键帽）：静止是草稿里的组合；录制中是按住的修饰键；无效 / 冲突是按下的组合。
    /// 每个动作两份交替的存储（文字是静态字符串），内容不变时返回同一份。
    pub fn keyCaps(self: *ViewModel, action: KeyAction) []const []const u8 {
        const caps = self.keyCapsOf(action);
        const slot = &self.key_caps[@intFromEnum(action)];
        const current = &slot.caps[slot.flip];
        if (current.len == caps.len and for (current.slice(), caps.slice()) |a, b| {
            if (!std.mem.eql(u8, a, b)) break false;
        } else true) return current.slice();
        slot.flip +%= 1;
        slot.caps[slot.flip] = caps;
        return slot.caps[slot.flip].slice();
    }
    pub fn keyTone(self: *const ViewModel, action: KeyAction) KeyTone {
        return switch (self.keyPhase(action)) {
            .idle => .rest,
            .recording => .recording,
            .invalid => .invalid,
            .conflict => .conflict,
        };
    }
    /// 录制中（显示“按下新快捷键…”）。
    pub fn keyRecording(self: *const ViewModel, action: KeyAction) bool {
        return self.keyPhase(action) == .recording;
    }
    /// 非静止（键帽区呈选中态）。
    pub fn keyActive(self: *const ViewModel, action: KeyAction) bool {
        return self.keyPhase(action) != .idle;
    }
    pub fn keyConflict(self: *const ViewModel, action: KeyAction) bool {
        return self.keyPhase(action) == .conflict;
    }
    pub fn keyProblemShown(self: *const ViewModel, action: KeyAction) bool {
        const phase = self.keyPhase(action);
        return phase == .invalid or phase == .conflict;
    }
    /// 行下的说明：无效的原因，或“⌘J 已用于“AI 运维助手”。交换后“AI 运维助手”改用 ⌘T。”
    pub fn keyProblem(self: *ViewModel, action: KeyAction) []const u8 {
        const edit = self.keyEditOf(action) orelse return "";
        switch (edit.phase) {
            .invalid => {
                // 与固定 / 系统快捷键冲突：写明占用者（“⇧⌘B 已用于“命令历史”，请换一个。”）。
                if (edit.reason == .reserved) if (edit.attempt) |chord| if (keybinding_edit.reservedName(chord)) |owner| {
                    var attempt_buffer: [32]u8 = undefined;
                    const attempt = keybinding_edit.chordText(chord, &attempt_buffer) catch "";
                    var buffer: [256]u8 = undefined;
                    const text = std.fmt.bufPrint(&buffer, "{s} 已用于“{s}”，请换一个。", .{ attempt, owner }) catch keybinding_edit.reasonText(edit.reason);
                    return swapIn(&self.key_text[@intFromEnum(action)][1], text);
                };
                return keybinding_edit.reasonText(edit.reason);
            },
            .conflict => {
                const chord = edit.attempt orelse return "";
                const other = edit.other orelse return "";
                var attempt_buffer: [32]u8 = undefined;
                var mine_buffer: [32]u8 = undefined;
                const attempt = keybinding_edit.chordText(chord, &attempt_buffer) catch "";
                const mine = keybinding_edit.chordText(self.keyChord(action), &mine_buffer) catch "";
                var buffer: [256]u8 = undefined;
                const name = keybinding_edit.label(other);
                const text = std.fmt.bufPrint(&buffer, "{s} 已用于“{s}”。交换后“{s}”改用 {s}。", .{ attempt, name, name, mine }) catch "该组合已被其它动作使用。";
                return swapIn(&self.key_text[@intFromEnum(action)][1], text);
            },
            else => return "",
        }
    }
    /// 草稿里的组合与已保存的不同（“未保存”标记）。
    pub fn keyModified(self: *const ViewModel, action: KeyAction) bool {
        return !self.keyChord(action).eql(self.controller.original.value.keys.get(action));
    }
    /// 单行“恢复默认”可用：可修改、不是默认值、不在保存。
    pub fn keyResettable(self: *const ViewModel, action: KeyAction) bool {
        if (keybinding_edit.fixed(action) or self.isSaving()) return false;
        return !self.keyChord(action).eql(keybinding_edit.defaultOf(action));
    }
    /// 键帽区可点（固定动作与保存中不可）。
    pub fn keyEditable(self: *const ViewModel, action: KeyAction) bool {
        return !keybinding_edit.fixed(action) and !self.isSaving();
    }
    /// 键帽区的悬停提示。
    pub fn keyTip(self: *const ViewModel, action: KeyAction) []const u8 {
        if (keybinding_edit.fixed(action)) return "此快捷键不可修改";
        return switch (self.keyPhase(action)) {
            .recording, .invalid => "按下新快捷键，Esc 取消",
            .conflict => if (self.keyEditOf(action).?.capturing) "按下其它组合重新录制，Esc 取消" else "点击修改快捷键",
            .idle => "点击修改快捷键",
        };
    }
    /// 键帽区的无障碍名（“修改“新建页签”的快捷键，当前 ⌘T”）。
    pub fn keyA11y(self: *ViewModel, action: KeyAction) []const u8 {
        if (keybinding_edit.fixed(action)) return "此快捷键不可修改";
        if (self.keyRecording(action)) return "按下新快捷键，Esc 取消";
        var chord_buffer: [32]u8 = undefined;
        const chord = keybinding_edit.chordText(self.keyChord(action), &chord_buffer) catch "";
        var buffer: [256]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "修改“{s}”的快捷键，当前 {s}", .{ keybinding_edit.label(action), chord }) catch keybinding_edit.label(action);
        return swapIn(&self.key_text[@intFromEnum(action)][0], text);
    }

    // ── 关于与更新（宿主的更新器状态，`HostStatus.update`） ──

    fn updateStatus(self: *const ViewModel) UpdateStatus {
        _ = self.signals.?.revision.get();
        return self.ports.hostStatus().update;
    }
    fn orElse(text: []const u8, fallback: []const u8) []const u8 {
        return if (text.len != 0) text else fallback;
    }
    /// 版本行：“<版本> · <构建信息>”（同旧 `Live.refresh`）。
    pub fn updateVersionText(self: *ViewModel) []const u8 {
        const status = self.updateStatus();
        var buffer: [512]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "{s} · {s}", .{ orElse(status.current_version, "—"), orElse(status.metadata, "构建信息未知") }) catch "版本信息未知";
        return swapIn(&self.update_text[0], text);
    }
    pub fn updateBadge(self: *ViewModel) []const u8 {
        return swapIn(&self.update_text[1], orElse(self.updateStatus().badge, "待检查"));
    }
    /// 徽标色调（旧 `badgeInk`）：失败 / 收尾警示；已准备或无需更新成功；未检查中性；其余强调。
    pub fn updateTone(self: *const ViewModel) UpdateTone {
        const status = self.updateStatus();
        const eql = std.mem.eql;
        if (eql(u8, status.state, "failed") or eql(u8, status.state, "draining")) return .warning;
        if (eql(u8, status.state, "ready") or eql(u8, orElse(status.badge, "待检查"), "无需更新")) return .done;
        if (status.state.len == 0 or eql(u8, status.state, "idle")) return .idle;
        return .active;
    }
    pub fn updateTitle(self: *ViewModel) []const u8 {
        return swapIn(&self.update_text[2], orElse(self.updateStatus().title, "检查是否有可用的新版本"));
    }
    /// 有可用的新版本（版本卡里的更新块换成强调底色）。
    pub fn updateAvailable(self: *const ViewModel) bool {
        return self.updateStatus().available_version.len != 0;
    }
    pub fn updateLastCheck(self: *ViewModel) []const u8 {
        return swapIn(&self.update_text[3], orElse(self.updateStatus().last_check, "尚未检查"));
    }
    pub fn updateChannel(self: *ViewModel) []const u8 {
        return swapIn(&self.update_text[4], orElse(self.updateStatus().channel, "正式版"));
    }
    /// 检查更新按钮的文字（同旧 `Live.refresh`）。
    pub fn updateButton(self: *const ViewModel) []const u8 {
        const status = self.updateStatus();
        if (std.mem.eql(u8, status.state, "draining")) return "查看收尾进度";
        if (std.mem.eql(u8, status.state, "checking")) return "正在检查…";
        if (status.available_version.len != 0) return "查看更新";
        return "检查更新";
    }
    /// 检查中或保存中不可点（同旧 `Live.disabled`）。
    pub fn updateButtonDisabled(self: *const ViewModel) bool {
        return self.isSaving() or std.mem.eql(u8, self.updateStatus().state, "checking");
    }

    // ── 宿主状态（面板里的只读行、动作按钮、通知授权） ──

    /// 只读行的值：静态值，或宿主给的路径（缓存 / 诊断日志目录读不到时“由应用管理”）。
    pub fn infoValue(self: *const ViewModel, row: Row) []const u8 {
        if (row.value.len != 0) return row.value;
        _ = self.signals.?.revision.get();
        return self.hostPath(row) orelse "由应用管理";
    }
    /// 配置文件 / 主机配置读不到时整行不显示（旧实现不挂这一行）。
    pub fn infoShown(self: *const ViewModel, row: Row) bool {
        _ = self.signals.?.revision.get();
        return self.infoPresent(row);
    }
    fn infoPresent(self: *const ViewModel, row: Row) bool {
        if (row.kind != .info or row.value.len != 0) return true;
        if (row.ids.field.ptr == fields.data.config_path.ids.field.ptr or row.ids.field.ptr == fields.data.hosts_path.ids.field.ptr) return self.hostPath(row) != null;
        return true;
    }
    /// 只读值是不是路径（路径单行省略，悬停 / 聚焦显示全文提示）。
    pub fn infoIsPath(self: *const ViewModel, row: Row) bool {
        const text = self.infoValue(row);
        return std.mem.startsWith(u8, text, "/") or std.mem.startsWith(u8, text, "~/");
    }
    fn hostPath(self: *const ViewModel, row: Row) ?[]const u8 {
        const paths = self.ports.hostStatus().data_paths;
        const table = [_]Row{ fields.data.config_path, fields.data.hosts_path, fields.data.cache_dir, fields.data.logs_dir };
        for (table, 0..) |candidate, index| if (std.mem.eql(u8, candidate.label, row.label)) return paths[index];
        return null;
    }
    /// 动作按钮可不可点（保存中一律不可点；清理类另看宿主：会话进行中、清理中）。
    pub fn actionEnabled(self: *const ViewModel, row: Row) bool {
        _ = self.signals.?.revision.get();
        if (self.isSaving()) return false;
        return self.actionState(row).enabled;
    }
    /// 动作不可用的原因（悬停提示；没有时为空串）。
    pub fn actionReason(self: *const ViewModel, row: Row) []const u8 {
        _ = self.signals.?.revision.get();
        return self.actionState(row).reason orelse "";
    }
    fn actionState(self: *const ViewModel, row: Row) ports_mod.ActionState {
        const status = self.ports.hostStatus();
        return switch (row.command orelse return .{}) {
            .clear_logs => status.clear_logs,
            .clear_all => status.clear_all,
            else => .{},
        };
    }
    /// 通知授权的说明全文（`?` 提示）。
    pub fn permissionHelp(self: *const ViewModel) []const u8 {
        _ = self.signals.?.revision.get();
        return self.ports.hostStatus().authorization_help orelse "当前无法使用系统通知。";
    }
    /// 通知授权状态（由说明归纳，同旧 `permissionStatus`）。
    pub fn permissionStatus(self: *const ViewModel) []const u8 {
        const help = self.permissionHelp();
        if (std.mem.indexOf(u8, help, "均关闭") != null) return "系统显示已关闭";
        if (std.mem.indexOf(u8, help, "已被拒绝") != null) return "已拒绝";
        if (std.mem.indexOf(u8, help, "临时授权") != null) return "临时授权";
        if (std.mem.indexOf(u8, help, "已获授权") != null) return "已允许";
        if (std.mem.indexOf(u8, help, "尚未授权") != null) return "未授权";
        if (std.mem.indexOf(u8, help, "正在查询") != null) return "查询中…";
        return "不可用";
    }
    fn permissionActionable(self: *const ViewModel) bool {
        const status = self.permissionStatus();
        return !std.mem.eql(u8, status, "不可用") and !std.mem.eql(u8, status, "查询中…");
    }
    /// 正在等系统授权结果：按钮换成“等待授权…”。
    pub fn permissionWaiting(self: *const ViewModel) bool {
        if (!self.permissionActionable()) return false;
        const feedback = self.ports.hostStatus().authorization_feedback orelse return false;
        return std.mem.eql(u8, feedback, "正在等待系统通知授权结果…");
    }
    /// 授权请求的回执（宿主 `authorization_feedback`：“系统通知授权请求失败”、请求后的授权说明等），显示在权限行下方
    /// （旧外壳写在 Save Bar 的状态位里）。等待中的那句已由“等待授权…”表示，这里不重复。
    pub fn permissionFeedback(self: *const ViewModel) []const u8 {
        _ = self.signals.?.revision.get();
        const feedback = self.ports.hostStatus().authorization_feedback orelse return "";
        if (std.mem.eql(u8, feedback, "正在等待系统通知授权结果…")) return "";
        return feedback;
    }
    pub fn permissionFeedbackShown(self: *const ViewModel) bool {
        return self.permissionFeedback().len != 0;
    }
    pub fn permissionButtonShown(self: *const ViewModel) bool {
        return self.permissionActionable() and !self.permissionWaiting();
    }
    pub fn permissionButton(self: *const ViewModel) []const u8 {
        return if (std.mem.eql(u8, self.permissionStatus(), "未授权")) "允许通知" else "打开系统设置";
    }

    // ── 选择器（纯；需已 attach） ──

    pub fn mode(self: *const ViewModel) Mode {
        return self.signals.?.mode.get();
    }
    pub fn location(self: *const ViewModel) Location {
        return self.signals.?.location.get();
    }
    pub fn title(self: *const ViewModel) []const u8 {
        return self.signals.?.title.get();
    }
    pub fn searchText(self: *const ViewModel) []const u8 {
        return self.signals.?.query.get();
    }
    /// 搜索框显示的文字（`nav.yix` 的 `W.Input value`）。
    pub fn searchField(self: *const ViewModel) []const u8 {
        return self.signals.?.search_field.get();
    }
    pub fn saveState(self: *const ViewModel) SaveState {
        return self.signals.?.save_state.get();
    }
    pub fn isDirty(self: *const ViewModel) bool {
        return self.signals.?.dirty.get();
    }
    pub fn isSaving(self: *const ViewModel) bool {
        return self.saveState() == .saving;
    }
    /// 页头“后退”是否可点（保存中一律不可点）。
    pub fn backEnabled(self: *const ViewModel) bool {
        return self.signals.?.can_back.get() and !self.isSaving();
    }
    pub fn forwardEnabled(self: *const ViewModel) bool {
        return self.signals.?.can_forward.get() and !self.isSaving();
    }
    /// 左侧导航行是否为当前分类。
    pub fn categorySelected(self: *const ViewModel, page: usize) bool {
        return self.location().page == page;
    }
    /// 面板（面板根 test_id）在当前位置是否可见：子页面只显示目录列出的面板；概览不显示面板。
    pub fn paneVisible(self: *const ViewModel, section_id: []const u8) bool {
        const where = self.location();
        switch (self.mode()) {
            .overview => return false,
            .search => return true,
            .panes => {
                if (!self.controller.drill_down) return true;
                const sub = catalog.get(where.page, where.sub) orelse return true;
                return catalog.contains(sub, section_id);
            },
        }
    }
    /// 草稿里某字段的当前值。
    pub fn valueOf(self: *const ViewModel, key: Key) ?values.Value {
        _ = self.signals.?.revision.get();
        return values.read(self.controller.model.value, key.section, key.key);
    }
    pub fn boolOf(self: *const ViewModel, key: Key) bool {
        const value = self.valueOf(key) orelse return false;
        return value == .boolean and value.boolean;
    }
    // ── Save Bar、恢复默认与确认对话框（H-save；规则在 `save_flow.zig`） ──

    fn barOf(self: *const ViewModel) save_flow.Bar {
        _ = self.signals.?.revision.get();
        const host = self.ports.hostStatus();
        return save_flow.bar(.{ .phase = @enumFromInt(@intFromEnum(self.saveState())), .dirty = self.isDirty(), .appearance_busy = host.appearance_busy, .font_problem = host.font_problem });
    }
    /// Save Bar 是否显示：只在草稿有未保存的改动（或正在保存）时显示；干净、已保存时不显示（成功由 Toast 告知）。
    pub fn footerVisible(self: *const ViewModel) bool {
        return self.barOf().shown;
    }
    /// Save Bar 状态文字：“未保存”“有设置需要修正”“正在保存…”“保存失败，草稿已保留”。
    pub fn footerMessage(self: *const ViewModel) []const u8 {
        return self.barOf().message;
    }
    /// 状态文字是否用危险墨色（校验无效、保存失败）。
    pub fn footerDanger(self: *const ViewModel) bool {
        return self.barOf().tone == .danger;
    }
    /// 当前位置有没有“恢复默认…”（作用域里有可编辑字段；概览、搜索结果、只有动作的子页面没有）。
    /// 读位置信号：内容页按位置整页重挂，这里只为跟随。
    pub fn resetShown(self: *const ViewModel) bool {
        _ = self.signals.?.location.get();
        _ = self.signals.?.mode.get();
        // 协议插件详情页：插件没有偏好字段时没有可恢复的东西（F-set-plugins）。
        if (self.pluginDetail()) |index| if (plugin_pane.preferenceFields(self.pluginEntries()[index]).len == 0) return false;
        const here = self.scopeHere();
        // F-set-ai：提供方详情页不显示“恢复默认…”（服务提供方的作用域是整张提供方表，在详情页上恢复默认会清掉
        // 所有提供方，不是“恢复这一个”；列表页保留，行为不变）。
        if (here.location.ai_provider != null) return false;
        return !here.searching and save_flow.editable(here);
    }
    /// “恢复默认…”可点：当前作用域的值与默认值不同，且不在保存。
    pub fn resetEnabled(self: *const ViewModel) bool {
        _ = self.signals.?.revision.get();
        if (self.isSaving()) return false;
        return save_flow.differsFromDefaults(self.controller.model.value, self.scopeHere());
    }
    /// 当前打开的确认对话框。
    pub fn promptKind(self: *const ViewModel) Prompt {
        return self.signals.?.prompt.get();
    }
    /// 对话框正文按哪一种显示：打开时是当前的；收起后（常驻挂载的原生 Modal 正在播退出动画）保持最后打开的那一种，
    /// 文案与按钮不在淡出途中跳变。
    fn dialogKind(self: *const ViewModel) Prompt {
        const kind = self.promptKind();
        return if (kind != .none) kind else self.last_prompt;
    }
    /// 打开时记下种类；收起前记下“草稿无效”的判定（收起后的正文沿用它）。
    fn rememberPrompt(self: *ViewModel, next: Prompt) void {
        if (next != .none) {
            self.last_prompt = next;
            return;
        }
        if (self.signals) |s| if (s.prompt.peek() != .none) {
            self.last_invalid = self.promptInvalid();
        };
    }
    pub fn promptOpen(self: *const ViewModel) bool {
        return self.promptKind() != .none;
    }
    /// 关窗 / 离开确认时草稿无效（“保存”换成“返回修正”，说明换成校验问题）。
    fn promptInvalid(self: *const ViewModel) bool {
        _ = self.signals.?.revision.get();
        const kind = self.promptKind();
        if (kind == .none) return self.last_invalid;
        return (kind == .close or kind == .leave) and self.controller.validationProblem() != null;
    }
    pub fn promptTitle(self: *const ViewModel) []const u8 {
        return switch (self.dialogKind()) {
            .reset => "恢复默认设置？",
            else => "未保存的设置",
        };
    }
    pub fn promptMessage(self: *ViewModel) []const u8 {
        const kind = self.promptKind();
        // 收起后（退出动画中）保持最后显示的说明。
        if (kind == .none) return self.prompt_text.buffers[self.prompt_text.flip][0..self.prompt_text.len[self.prompt_text.flip]];
        if (self.promptInvalid()) {
            var buffer: [2048]u8 = undefined;
            return swapIn(&self.prompt_text, self.controller.validationMessage(&buffer));
        }
        var buffer: [256]u8 = undefined;
        const text = switch (kind) {
            .none => "",
            .close => "设置更改尚未保存。关闭前要保存吗？",
            .leave => std.fmt.bufPrint(&buffer, "“{s}”的更改尚未保存。离开前要保存吗？", .{titleOf(self.controller)}) catch "更改尚未保存。离开前要保存吗？",
            .reset => std.fmt.bufPrint(&buffer, "把“{s}”的设置恢复为默认值？恢复后仍需保存才会生效，保存前可以撤销。", .{titleOf(self.controller)}) catch "把本页设置恢复为默认值？",
        };
        return swapIn(&self.prompt_text, text);
    }
    /// 说明是校验问题（危险墨色）。
    pub fn promptProblem(self: *const ViewModel) bool {
        return self.promptInvalid();
    }
    pub fn promptNotice(self: *const ViewModel) []const u8 {
        if (self.promptInvalid()) return "请返回设置修正后保存，草稿已保留。";
        return switch (self.dialogKind()) {
            .reset => "只影响本页；其它页面的设置不变。",
            else => "保存失败会保留草稿。",
        };
    }
    /// “继续编辑”（关窗 / 离开）或“取消”（恢复默认）。
    pub fn promptCancelLabel(self: *const ViewModel) []const u8 {
        return if (self.dialogKind() == .reset) "取消" else "继续编辑";
    }
    /// 关窗 / 离开确认有“放弃”与“保存”；恢复默认确认有“恢复默认”。
    pub fn promptAsksSave(self: *const ViewModel) bool {
        const kind = self.dialogKind();
        return kind == .close or kind == .leave;
    }
    pub fn promptAsksReset(self: *const ViewModel) bool {
        return self.dialogKind() == .reset;
    }
    pub fn promptSaveLabel(self: *const ViewModel) []const u8 {
        if (self.promptInvalid()) return "返回修正";
        return if (self.dialogKind() == .close) "保存关闭" else "保存";
    }

    // ── “AI 辅助”面板（F-set-ai；动作与选择器在 `ai_pane.zig`） ──

    fn runAi(self: *ViewModel, command: ai.Command) void {
        switch (ai.run(self, command)) {
            .none => {},
            .open_detail => |index| self.navigate(.{ .open = .{ .page = ai.page, .sub = ai.providers_sub, .ai_provider = index } }, true),
            .open_list => self.navigate(.{ .open = .{ .page = ai.page, .sub = ai.providers_sub } }, false),
        }
        if (self.controller.validationProblem() == null) self.emit(.resolve_problems);
    }

    // ── 选择器（P3 3d：`.yix` 外壳、页头、概览、Save Bar） ──

    /// 内容页挂载时的模式（概览 / 面板 / 搜索）。不建依赖：内容页按纪元整页重挂，
    /// 同一纪元里正文的形态固定，避免导航后、宿主重挂前先把旧正文多挂一次。
    pub fn contentMode(self: *const ViewModel) Mode {
        return modeOf(self.controller);
    }
    /// 页头后退 / 前进的历史是否有这一步（不含“保存中”；决定 35% 透明度）。
    pub fn historyHasBack(self: *const ViewModel) bool {
        return self.signals.?.can_back.get();
    }
    pub fn historyHasForward(self: *const ViewModel) bool {
        return self.signals.?.can_forward.get();
    }
    /// 左侧导航的行数据：key 含纪元与选中态，二者变化时该行重挂（行样式在挂载时按主题求值）。
    pub fn navItems(self: *ViewModel) []const NavItem {
        const epoch = self.signals.?.epoch.get();
        const current = self.pageIndex();
        const locked = self.controlsLocked();
        self.nav_flip +%= 1;
        const list = &self.nav_items[self.nav_flip];
        for (list, 0..) |*item, page| {
            const selected = page == current;
            item.* = .{ .key = epoch * 64 + page * 2 + @intFromBool(selected), .page = @intCast(page), .selected = selected, .locked = locked };
        }
        return list;
    }
    /// 当前分类概览的行数据（key 为子页面下标）。
    pub fn overviewItems(self: *const ViewModel) []const OverviewItem {
        return overview_items[self.pageIndex()];
    }
    /// 内容页的行 key（只有一行）：纪元变了 key 就变，内容页随之重挂。
    pub fn contentEpochs(self: *const ViewModel) []const u64 {
        const epoch = self.signals.?.epoch.get();
        return &self.epoch_keys[epoch & 1];
    }
    pub fn isSearching(self: *const ViewModel) bool {
        return self.mode() == .search;
    }
    pub fn overviewShown(self: *const ViewModel) bool {
        return self.mode() == .overview;
    }
    /// 当前分类（`settings_pages.pages` 下标）。
    pub fn pageIndex(self: *const ViewModel) usize {
        return self.location().page;
    }
    /// 页头标题前的上一级（znote 页头的 “Boards › 名称” 面包屑）：子页 / 插件详情是所属分类，服务提供方详情是
    /// “服务提供方”，分类页、概览与搜索结果是 “设置”。只读位置与模式信号。
    pub fn crumb(self: *const ViewModel) []const u8 {
        if (self.mode() != .panes) return "设置";
        const loc = self.location();
        if (loc.ai_provider != null) if (catalog.get(loc.page, loc.sub)) |sub| return sub.title;
        if (loc.sub != null) return catalog.title(loc.page);
        return "设置";
    }
    /// 页头帮助按钮的提示文字：搜索时说明搜索范围，否则是分类说明。
    pub fn helpText(self: *const ViewModel) []const u8 {
        if (self.isSearching()) return "在全部设置分类中查找。";
        return catalog.categories[self.pageIndex()].description;
    }
    /// 保存中：导航行、概览行、历史按钮一律不可点。
    pub fn controlsLocked(self: *const ViewModel) bool {
        return self.isSaving();
    }
    /// 概览第 `sub` 行的摘要（当前草稿值）。文字写进 view-model 自己的缓冲：每行两份交替，
    /// 新旧两版内容同时有效，Yix 按内容判等时不会把同一块内存当作“没变”。
    pub fn overviewSummary(self: *ViewModel, sub: usize) []const u8 {
        _ = self.signals.?.revision.get();
        const list = catalog.subpages(self.pageIndex());
        if (sub >= list.len or sub >= max_subpages) return "";
        const slot = &self.summaries[sub];
        slot.flip +%= 1;
        return list[sub].summary(self.controller.model.value, &slot.buffers[slot.flip]) catch "";
    }
    /// Save Bar “保存”是否可用：有草稿、不在保存、外观 worker 空闲、字体无问题。
    /// 无效草稿也可点（宿主据此定位问题，不写盘）。
    pub fn saveEnabled(self: *const ViewModel) bool {
        return self.barOf().save_enabled;
    }
    /// Save Bar “撤销”是否可用。
    pub fn revertEnabled(self: *const ViewModel) bool {
        return self.barOf().revert_enabled;
    }
    /// 宿主状态行（`HostStatus.status_line` 的投影；随 `sync` 刷新）。
    pub fn statusLine(self: *const ViewModel) []const u8 {
        _ = self.signals.?.revision.get();
        return self.ports.hostStatus().status_line;
    }
    pub fn statusLineShown(self: *const ViewModel) bool {
        _ = self.signals.?.revision.get();
        return self.ports.hostStatus().status_line_shown;
    }
    // ── 外观与主题（P3 3e 外观包；`view/panes/appearance.yix`） ──
    //
    // 草稿编辑直接写 Controller，随后发 `Effect.appearance(.changed)` 让宿主重新校验字体、按需准备背景、刷新材质预览
    // （旧 `Binding.valuesChanged` → `draft_values_changed`）；主题库与背景资源的操作交宿主。宿主状态（主题库、字体校验、
    // 背景缩略图、worker 忙）经 `Ports.appearance` 读取，宿主在它们变化时 `sync`（`revision` 加一），读它的选择器随之重算。
    // 面板不整页重挂：切换开关时同一个原生 `W.Switch` 原地滑动（S-11）。

    fn appearanceIntent(self: *ViewModel, action: intent_mod.AppearanceIntent) void {
        const c = self.controller;
        switch (action) {
            .select_theme => |id| {
                if (self.appearanceLockedNow()) return;
                const registry = self.ports.appearanceStatus().registry orelse return;
                c.selectTheme(registry, id) catch |err| {
                    self.emit(.{ .failed = err });
                    return;
                };
            },
            .request_remove_theme => |target| {
                if (self.appearanceLockedNow()) return;
                if (target.id.len > self.theme_delete_id.len) return;
                @memcpy(self.theme_delete_id[0..target.id.len], target.id);
                self.theme_delete_id_len = target.id.len;
                const message = std.fmt.bufPrint(&self.theme_delete_message, "将删除导入的主题“{s}”及其文件，无法撤销。内置主题不受影响。", .{target.name}) catch "将删除这个导入的主题及其文件，无法撤销。";
                self.theme_delete_message_len = message.len;
                if (self.signals) |s| s.popup.set(ids.theme_delete);
                return;
            },
            .remove_theme => |id| {
                if (self.appearanceLockedNow()) return;
                if (self.signals) |s| s.popup.set(null);
                self.emit(.{ .appearance = .{ .remove_theme = id } });
                return;
            },
            .choose_background => {
                if (self.appearanceLockedNow()) return;
                self.emit(.{ .appearance = .pick_background });
                return;
            },
            .remove_background => {
                if (self.appearanceLockedNow()) return;
                c.editKey("ui.materials.background", "path", .{ .text = "" }) catch |err| {
                    self.emit(.{ .failed = err });
                    return;
                };
            },
            .alignment => |where| {
                if (self.signals) |s| s.popup.set(null);
                if (self.appearanceLockedNow()) return;
                c.editBackgroundAlignment(where.x, where.y) catch |err| {
                    self.emit(.{ .failed = err });
                    return;
                };
            },
            .preview_material => |active| {
                if (active and self.appearanceLockedNow()) return;
                self.emit(.{ .appearance = .{ .preview_material = active } });
                return;
            },
            .restore_materials => {
                if (self.appearanceLockedNow()) return;
                self.emit(.{ .appearance = .restore_materials });
                return;
            },
            .edit => |edit| {
                if (self.appearanceLockedNow()) return;
                const value: values.Value = if (std.mem.eql(u8, edit.key.key, "interval_minutes") and edit.value == .text)
                    .{ .unsigned = std.fmt.parseInt(u32, edit.value.text, 10) catch return }
                else
                    edit.value;
                if (self.typed_field == catalog.schema.find(edit.key.section, edit.key.key)) self.typed_field = null;
                c.editKey(edit.key.section, edit.key.key, value) catch |err| {
                    self.emit(.{ .failed = err });
                    return;
                };
                if (self.signals) |s| if (s.popup.peek()) |open| if (std.mem.startsWith(u8, open, ids.field_prefix)) s.popup.set(null);
            },
            // 解析失败记成字段问题（行内提示），不当作操作失败（同旧 `Field.edit`）。
            .edit_raw => |edit| {
                if (self.appearanceLockedNow()) return;
                self.typed_field = catalog.schema.find(edit.key.section, edit.key.key);
                c.editRaw(edit.key.section, edit.key.key, edit.text) catch {};
            },
            .submit => |edit| {
                if (self.appearanceLockedNow()) return;
                const index = catalog.schema.find(edit.key.section, edit.key.key) orelse return;
                // 没改过的输入框按 Enter 不改值：显示的是取整后的文字（行高 1.234 显示 1.23），原样提交会改掉已存的值。
                if (self.typed_field == index) c.editRaw(edit.key.section, edit.key.key, edit.text) catch {};
                // 有效的提交之后显示格式化的值（无效原文继续显示，便于改正）。
                if (c.raw_fields[index].problem == null) self.typed_field = null;
                if (std.mem.eql(u8, edit.key.key, "transparency") and c.raw_fields[index].problem == null) {
                    const rounded = @round(c.model.value.ui.materials.background.transparency * 10) / 10;
                    c.editKey(edit.key.section, edit.key.key, .{ .decimal = rounded }) catch {};
                }
                if (std.mem.eql(u8, edit.key.section, "ui")) self.emit(.{ .appearance = .validate_font });
            },
            .custom_font => {
                if (self.appearanceLockedNow()) return;
                self.custom_font = true;
                if (self.signals) |s| s.popup.set(null);
                self.requestFocus(fields.appearance.font_family.ids.focus);
            },
        }
        // 草稿可能变了：宿主重新校验字体 / 准备背景 / 刷新材质预览；问题都解决了就撤回“无法保存设置”的通知。
        self.emit(.{ .appearance = .changed });
        if (c.validationProblem() == null) self.emit(.resolve_problems);
    }

    fn appearanceStatus(self: *const ViewModel) AppearanceStatus {
        _ = self.signals.?.revision.get();
        return self.ports.appearanceStatus();
    }
    fn appearanceLockedNow(self: *const ViewModel) bool {
        return self.isSavingNow() or self.ports.appearanceStatus().busy;
    }
    /// 外观页的控件不可用：保存中，或外观 worker 正在准备主题 / 背景（同旧 `appearance_view.disabled`）。
    pub fn appearanceLocked(self: *const ViewModel) bool {
        return self.isSaving() or self.appearanceStatus().busy;
    }
    /// 外观资源已就绪（主题库可用；“导入”“选择背景”“全窗口预览”可用）。
    pub fn appearanceReady(self: *const ViewModel) bool {
        return self.appearanceStatus().ready;
    }
    fn draftUi(self: *const ViewModel) @FieldType(catalog.config.Config, "ui") {
        _ = self.signals.?.revision.get();
        return self.controller.model.value.ui;
    }

    // 主题

    /// 当前（草稿）主题的记录；主题库还没加载时为 null。
    pub fn themeRecord(self: *const ViewModel) ?*const themes.Record {
        const registry = self.appearanceStatus().registry orelse return null;
        return registry.get(self.draftUi().theme);
    }
    /// 主题面板页头：当前主题名（主题库没有它时是 id）。
    pub fn themeName(self: *ViewModel) []const u8 {
        const name = if (self.themeRecord()) |record| record.theme.name else self.draftUi().theme;
        return swapIn(&self.appearance_text[0], name);
    }
    /// 主题条下的说明：“N 个主题 · 左右滚动浏览”。
    pub fn themeCountText(self: *ViewModel) []const u8 {
        const registry = self.appearanceStatus().registry orelse return self.themeName();
        var buffer: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "{d} 个主题 · 左右滚动浏览", .{registry.counts().all}) catch "";
        return swapIn(&self.appearance_text[1], text);
    }
    /// 草稿主题与已保存的不同（“预览中”）。
    pub fn themePreviewing(self: *const ViewModel) bool {
        _ = self.signals.?.revision.get();
        return !std.mem.eql(u8, self.controller.model.value.ui.theme, self.controller.original.value.ui.theme);
    }
    /// 主题条的卡片（主题库顺序；key 是主题 id，选中变化时卡片原地更新）。
    pub fn themeCards(self: *ViewModel) []const ThemeCard {
        const registry = self.appearanceStatus().registry orelse return &.{};
        const draft = self.draftUi().theme;
        self.theme_flip +%= 1;
        const list = &self.theme_cards[self.theme_flip];
        if (self.theme_ids == null) if (self.scope) |scope| {
            self.theme_ids = ThemeIds.create(scope) catch null;
        };
        const cache = self.theme_ids orelse return &.{};
        var count: usize = 0;
        for (registry.records.items) |*record| {
            if (count == list.len) break;
            const named = cache.get(record.id) orelse continue;
            list[count] = .{ .id = named.id, .record = record, .selected = std.mem.eql(u8, draft, record.id), .imported = record.source_kind == .imported, .test_id = named.test_id, .menu_id = named.menu_id };
            count += 1;
        }
        return list[0..count];
    }
    /// 主题条挂载时的初始横向偏移：让选中的卡片进入视口（框架把偏移夹到 [0, 最大]）。只在挂载时读（不建依赖），
    /// 之后由用户滚动（旧 `ThemeStripSelection` 也只在重挂后定位一次）。
    pub fn themeStripStart(self: *const ViewModel) f32 {
        const registry = self.ports.appearanceStatus().registry orelse return 0;
        for (registry.records.items, 0..) |record, index| {
            if (std.mem.eql(u8, record.id, self.controller.model.value.ui.theme)) return @as(f32, @floatFromInt(index)) * theme_card_pitch;
        }
        return 0;
    }
    pub const theme_card_pitch: f32 = 158;
    /// 能不能删除某个主题；不能时给出原因（右键菜单的文字、当前主题删除按钮的提示）。
    pub fn themeRemoval(self: *const ViewModel, id: []const u8) ThemeRemoval {
        const status = self.appearanceStatus();
        const registry = status.registry orelse return .unavailable;
        registry.checkRemove(id, registry.revision, .{ .saved = status.saved_theme, .draft = self.controller.model.value.ui.theme }) catch |err| return switch (err) {
            error.BuiltinThemeProtected => .builtin,
            error.CurrentThemeProtected => .in_use,
            error.DraftThemeProtected => .previewing,
            else => .unavailable,
        };
        return .removable;
    }
    /// 当前主题是不是内置的（删除按钮的文字）。
    pub fn themeBuiltin(self: *const ViewModel) bool {
        const record = self.themeRecord() orelse return true;
        return record.source_kind == .builtin;
    }
    /// “删除当前主题”按钮的提示（旧 `themeSection` 的 `remove_reason`）。
    pub fn themeRemoveReason(self: *const ViewModel) []const u8 {
        return switch (self.themeRemoval(self.draftUi().theme)) {
            .removable => "删除当前主题",
            .builtin => error_text.theme(error.BuiltinThemeProtected).?.line,
            .in_use => error_text.theme(error.CurrentThemeProtected).?.line,
            .previewing => error_text.theme(error.DraftThemeProtected).?.line,
            .unavailable => "主题库不可用",
        };
    }
    pub fn themeRemoveEnabled(self: *const ViewModel) bool {
        return self.themeRemoval(self.draftUi().theme) == .removable and !self.appearanceLocked();
    }
    /// 主题导入 / 删除失败的提示（`Controller.theme_library.problem`；没有时为空串）。
    pub fn themeProblem(self: *const ViewModel) []const u8 {
        _ = self.signals.?.revision.get();
        const problem = self.controller.theme_library.problem orelse return "";
        return themeProblemText(problem);
    }

    // 应用图标

    pub fn iconBackground(self: *const ViewModel) ?[]const u8 {
        return @tagName(self.draftUi().icon_background);
    }

    /// 终端与工作区 ›“浮动卡片切换动画”（`ui.float_card_transition`，Z12b）：草稿值，`anchor` / `fade`。
    pub fn floatCardTransition(self: *const ViewModel) ?[]const u8 {
        return @tagName(self.draftUi().float_card_transition);
    }

    /// 终端与工作区 ›“右键行为”（`ui.terminal_right_click`）：草稿值，`menu` / `paste`。
    pub fn terminalRightClick(self: *const ViewModel) ?[]const u8 {
        return @tagName(self.draftUi().terminal_right_click);
    }

    // 背景图片

    fn backgroundDraft(self: *const ViewModel) @FieldType(@FieldType(@FieldType(catalog.config.Config, "ui"), "materials"), "background") {
        return self.draftUi().materials.background;
    }
    pub fn backgroundEnabled(self: *const ViewModel) bool {
        return self.backgroundDraft().enabled;
    }
    pub fn backgroundHasPath(self: *const ViewModel) bool {
        return self.backgroundDraft().path.len != 0;
    }
    pub fn backgroundDirectory(self: *const ViewModel) bool {
        return self.backgroundDraft().source == .directory;
    }
    /// 显示的路径：背景选择框刚选的（worker 准备中），否则是草稿路径。
    pub fn backgroundPath(self: *ViewModel) []const u8 {
        const selected = self.appearanceStatus().selected_image_path;
        const path = if (selected.len != 0) selected else self.backgroundDraft().path;
        return swapIn(&self.appearance_text[2], path);
    }
    /// 文件名（没有路径时“尚未选择图片 / 目录”）。
    pub fn backgroundName(self: *ViewModel) []const u8 {
        const path = self.backgroundPath();
        if (path.len == 0) return if (self.backgroundDirectory()) "尚未选择目录" else "尚未选择图片";
        return swapIn(&self.appearance_text[3], std.fs.path.basename(path));
    }
    /// 背景准备的状态行（旧 `materialSection` 的 `status`）。
    pub fn backgroundState(self: *ViewModel) []const u8 {
        const status = self.appearanceStatus();
        const background = self.backgroundDraft();
        const draft = &self.controller.background;
        const path = if (status.selected_image_path.len != 0) status.selected_image_path else background.path;
        var buffer: [512]u8 = undefined;
        const text: []const u8 = switch (draft.state) {
            .loading => if (background.source == .directory) "正在准备首张图片…" else "正在读取与解码…",
            .missing => "文件已移动 · 草稿保留",
            .denied => "权限不足 · 草稿保留",
            .invalid => "图片无法解码 · 草稿保留",
            .failed => if (draft.problem != null and draft.problem.? == error.NoUsableImages) "目录中没有可用图片 · 草稿保留" else "图片准备失败 · 草稿保留",
            .empty => if (background.source == .directory) "选择图片或目录，目录仅使用当前层级" else if (path.len == 0) "选择一张图片或一个目录" else "等待准备图片",
            .ready => if (draft.last_good) |*good| if (good.playlist != null) blk: {
                const saved = status.saved_background;
                const current = if (!status.preview_active and status.runtime_image_path.len != 0 and saved != null and good.matches(saved.?)) status.runtime_image_path else good.selectedPath();
                break :blk std.fmt.bufPrint(&buffer, "目录轮播 · {s}", .{std.fs.path.basename(current)}) catch "目录轮播";
            } else std.fmt.bufPrint(&buffer, "本地 · {d} × {d}", .{ good.image.width, good.image.height }) catch "本地图片" else "等待准备图片",
        };
        return swapIn(&self.appearance_text[4], text);
    }
    pub fn backgroundFailed(self: *const ViewModel) bool {
        _ = self.signals.?.revision.get();
        return self.controller.background.problem != null;
    }
    pub fn backgroundChooseLabel(self: *const ViewModel) []const u8 {
        return if (self.backgroundDraft().path.len == 0) "选择背景" else "更换背景";
    }
    /// 选择框（轮播方式 / 切换间隔 / 图片适配）的当前值（选项的 value）。
    pub fn backgroundChoice(self: *ViewModel, row: Row) ?[]const u8 {
        const background = self.backgroundDraft();
        const key = row.key orelse return null;
        if (std.mem.eql(u8, key.key, "order")) return @tagName(background.order);
        if (std.mem.eql(u8, key.key, "fit")) return @tagName(background.fit);
        if (std.mem.eql(u8, key.key, "interval_minutes")) {
            var buffer: [16]u8 = undefined;
            return swapIn(&self.appearance_text[5], std.fmt.bufPrint(&buffer, "{d}", .{background.interval_minutes}) catch "5");
        }
        return null;
    }
    /// 图片对齐的当前选项名（“左上”…“右下”）。
    pub fn alignmentLabel(self: *const ViewModel) []const u8 {
        const background = self.backgroundDraft();
        return alignment_names[@backingInt(background.alignment_y)][@backingInt(background.alignment_x)];
    }
    pub fn alignmentChosen(self: *const ViewModel, x: usize, y: usize) bool {
        const background = self.backgroundDraft();
        return @backingInt(background.alignment_x) == x and @backingInt(background.alignment_y) == y;
    }
    pub const alignment_names = [3][3][]const u8{ .{ "左上", "顶部居中", "右上" }, .{ "左侧居中", "居中", "右侧居中" }, .{ "左下", "底部居中", "右下" } };
    /// 背景缩略图（宿主已上传的纹理）；没有时显示占位图标。草稿路径清空后不再显示（旧实现：显式移除的草稿没有缩略图）。
    pub fn backgroundThumbnail(self: *const ViewModel) ?ports_mod.Texture {
        if (self.backgroundDraft().path.len == 0) return null;
        return self.appearanceStatus().thumbnail;
    }

    // 数值字段（输入框 + 滑块）

    /// 输入框显示的文字：用户打的原文（含无效的），否则是草稿值（透明度一位小数、行高两位小数、字重显示数值，同旧 `fieldDisplay`）。
    pub fn appearanceText(self: *ViewModel, row: Row) []const u8 {
        _ = self.signals.?.revision.get();
        const key = row.key.?;
        const index = catalog.schema.find(key.section, key.key).?;
        var buffer: [512]u8 = undefined;
        const raw = if (self.typed_field == index) self.controller.raw_fields[index].input else null;
        const weight_name = std.mem.eql(u8, key.key, "font_weight") and raw != null and std.meta.stringToEnum(fonts.Weight, raw.?) != null;
        const text = if (raw != null and !weight_name) raw.? else displayValue(self.controller.model.value, key, &buffer) catch "";
        return swapIn(&self.field_text[fieldSlot(key)], text);
    }
    /// 滑块的值（草稿）。
    pub fn appearanceNumber(self: *const ViewModel, row: Row) f32 {
        const value = self.valueOf(row.key.?) orelse return 0;
        return switch (value) {
            .unsigned => |n| @floatFromInt(n),
            .decimal => |n| n,
            .text => |text| if (fonts.parseWeight(text)) |weight| @floatFromInt(@backingInt(weight)) else 400,
            .boolean => 0,
        };
    }
    /// 外观字段的校验提示（旧 `appearance_view.fieldProblem`；字重给出当前字体支持的范围）。
    pub fn appearanceProblem(self: *ViewModel, row: Row) []const u8 {
        _ = self.signals.?.revision.get();
        const key = row.key orelse return "";
        const problem = self.controller.fieldProblem(catalog.schema.find(key.section, key.key).?) orelse return "";
        if (std.mem.eql(u8, key.key, "font_weight")) if (self.weightRange()) |range| {
            var buffer: [64]u8 = undefined;
            return swapIn(&self.appearance_text[6], std.fmt.bufPrint(&buffer, "请输入 {d}–{d} 的整数。", .{ range.min, range.max }) catch "字重数值无效。");
        };
        return appearanceProblemText(key, problem);
    }
    pub fn appearanceInvalid(self: *ViewModel, row: Row) bool {
        return self.appearanceProblem(row).len != 0;
    }

    // 字体与排版

    /// 字体族在“自定义字体…”输入框模式（选了“自定义字体…”之后，直到窗口宿主销毁；同旧 `custom_font_edit`）。
    pub fn customFont(self: *const ViewModel) bool {
        _ = self.signals.?.revision.get();
        return self.custom_font;
    }
    pub fn fontFamily(self: *ViewModel) ?[]const u8 {
        return swapIn(&self.appearance_text[7], self.draftUi().font_family);
    }
    /// 字体族选择框的 key（只有一行）：字体族变了 key 就变，选择框随之重挂（前置图标在挂载时定）。
    pub fn fontFamilyKeys(self: *ViewModel) []const u64 {
        const key = std.hash.Wyhash.hash(0, self.draftUi().font_family);
        self.font_key_flip +%= 1;
        self.font_keys[self.font_key_flip][0] = key;
        return &self.font_keys[self.font_key_flip];
    }
    /// 字体来源（选择框的图标）：内置 / 系统已安装 / 已保存但未安装。
    pub fn fontKind(self: *const ViewModel) FontKind {
        return fontKindOf(self.draftUi().font_family);
    }
    /// 字体族选项：内置建议（已安装的才列）+ 系统等宽字体，已保存但已卸载的字体保留，最后是“自定义字体…”。
    pub fn fontChoices(self: *ViewModel) []const FontChoice {
        const family = self.draftUi().font_family;
        const list = self.fontList() orelse return &.{};
        self.font_flip +%= 1;
        const out = list.out[self.font_flip];
        var count: usize = 0;
        var found = false;
        for (list.base) |choice| {
            out[count] = choice;
            count += 1;
            found = found or std.mem.eql(u8, choice.value, family);
        }
        if (!found) {
            const label = list.arena.allocator().dupe(u8, family) catch return out[0..count];
            const test_id = std.fmt.allocPrint(list.arena.allocator(), "settings.option.font_family.{s}", .{family}) catch return out[0..count];
            out[count] = .{ .value = label, .label = label, .test_id = test_id, .kind = fontKindOf(family) };
            count += 1;
        }
        out[count] = .{ .value = "custom", .label = "自定义字体…", .test_id = "settings.option.font_family.custom", .kind = .custom };
        count += 1;
        return out[0..count];
    }
    fn fontList(self: *ViewModel) ?*FontList {
        if (self.font_list) |list| return list;
        const scope = self.scope orelse return null;
        const list = FontList.load(scope) catch return null;
        self.font_list = list;
        return list;
    }
    /// 当前字体支持的字重（按字体族缓存：CoreText 查询）。
    fn weights(self: *ViewModel) fonts.SupportedWeights {
        const family = self.draftUi().font_family;
        if (self.weight_family_len == family.len and std.mem.eql(u8, self.weight_family[0..family.len], family)) return self.weight_cache;
        self.weight_cache = fonts.supportedWeights(family);
        const n = @min(family.len, self.weight_family.len);
        @memcpy(self.weight_family[0..n], family[0..n]);
        self.weight_family_len = n;
        return self.weight_cache;
    }
    /// 连续字重的范围（可变字体）；不是可变字体时为 null（显示字重选择框）。
    pub fn weightRange(self: *ViewModel) ?fonts.WeightRange {
        return self.weights().variable;
    }
    /// 字重行的形态 key（只有一行）：可变字体的范围或可选字重集合变了，行随之重挂（滑块的范围、选择框的选项在挂载时定）。
    pub fn weightKeys(self: *ViewModel) []const u64 {
        const supported = self.weights();
        var hasher = std.hash.Wyhash.init(0);
        if (supported.variable) |range| hasher.update(std.mem.asBytes(&range)) else for (supported.slice()) |weight| hasher.update(std.mem.asBytes(&weight));
        self.weight_key_flip +%= 1;
        self.weight_keys[self.weight_key_flip][0] = hasher.final();
        return &self.weight_keys[self.weight_key_flip];
    }
    /// 字重选择框的选项（当前字体支持的字重，按字重从细到粗）。
    pub fn weightChoices(self: *ViewModel) []const fonts.Weight {
        const supported = self.weights();
        self.weight_list = supported;
        return self.weight_list.slice();
    }
    /// 字重选择框的当前值（字重的枚举名）；字体不支持任何字重时为 null（“暂无可用字重”）。
    pub fn weightValue(self: *const ViewModel) ?[]const u8 {
        const weight = fonts.parseWeight(self.draftUi().font_weight) orelse return @tagName(fonts.Weight.regular);
        return @tagName(weight);
    }
    /// 可变字体的范围说明（“支持连续字重 · 100–900”）。
    pub fn weightRangeText(self: *ViewModel) []const u8 {
        const range = self.weightRange() orelse return "";
        var buffer: [64]u8 = undefined;
        return swapIn(&self.appearance_text[8], std.fmt.bufPrint(&buffer, "支持连续字重 · {d}–{d}", .{ range.min, range.max }) catch "");
    }
    /// 光标形状（Tabs 的当前项）。
    pub fn cursorStyle(self: *const ViewModel) ?[]const u8 {
        const style = self.draftUi().cursor_style;
        for ([_][]const u8{ "block", "bar", "underline" }) |known| if (std.mem.eql(u8, known, style)) return known;
        return "block";
    }
    /// 字体校验的状态行（`settings.font.status`）：问题，或回退时实际使用的字体；没有时为空串（不显示）。
    pub fn fontStatusText(self: *ViewModel) []const u8 {
        const status = self.appearanceStatus();
        if (status.font_problem) |problem| return swapIn(&self.appearance_text[9], problem);
        if (!status.font_fallback) return "";
        var buffer: [256]u8 = undefined;
        return swapIn(&self.appearance_text[9], std.fmt.bufPrint(&buffer, "字体缺失 · 实际使用 {s}", .{status.font_actual}) catch "字体缺失 · 使用系统回退");
    }

    // 预览（终端字体预览、工作区缩略预览）

    /// 预览面板页头：“实时 · <实际字体> · <字号> pt”。
    pub fn previewMeta(self: *ViewModel) []const u8 {
        const status = self.appearanceStatus();
        const actual = if (status.font_actual.len != 0) status.font_actual else "系统等宽字体";
        var buffer: [256]u8 = undefined;
        return swapIn(&self.appearance_text[10], std.fmt.bufPrint(&buffer, "实时 · {s} · {d} pt", .{ actual, self.draftUi().font_size }) catch "实时");
    }
    /// 请求的字体不可用时的说明（预览顶部）；可用时为空串。
    pub fn previewFallback(self: *ViewModel) []const u8 {
        const status = self.appearanceStatus();
        if (!status.font_fallback) return "";
        const actual = if (status.font_actual.len != 0) status.font_actual else "系统等宽字体";
        var buffer: [512]u8 = undefined;
        return swapIn(&self.appearance_text[11], std.fmt.bufPrint(&buffer, "请求字体 {s} 当前不可用，预览使用 {s}。", .{ self.draftUi().font_family, actual }) catch "");
    }
    /// 终端预览的排版与配色（草稿字号 / 字重 / 行高、字体校验解析出的字体、草稿主题的终端颜色）。
    pub fn previewText(self: *const ViewModel) PreviewText {
        const status = self.appearanceStatus();
        const ui_value = self.draftUi();
        const record = self.themeRecord();
        const size: f32 = @floatFromInt(ui_value.font_size);
        return .{
            .size = size,
            .weight = @backingInt(fonts.parseWeight(ui_value.font_weight) orelse .regular),
            .family = status.font_family_id,
            .line_height = ui_value.line_height,
            .background = if (record) |r| r.theme.bg else null,
            .foreground = if (record) |r| r.theme.fg else null,
            .prompt = if (record) |r| r.theme.ansi[2] else null,
            .caret_width = if (std.mem.eql(u8, ui_value.cursor_style, "bar")) 2 else if (status.font_cell_width > 0) status.font_cell_width else size * 0.6,
            .caret_height = if (std.mem.eql(u8, ui_value.cursor_style, "underline")) 2 else size * ui_value.line_height,
            .caret_low = std.mem.eql(u8, ui_value.cursor_style, "underline"),
        };
    }
    /// 工作区缩略预览（“终端与工作区”面板底部）的配色与辅助显示开关；主题库还没加载时不显示。
    pub fn miniPreview(self: *const ViewModel) ?MiniPreview {
        const record = self.themeRecord() orelse return null;
        const ui_value = self.draftUi();
        return .{ .tokens = record.ui_tokens, .terminal = record.theme.bg, .foreground = record.theme.fg, .running = record.theme.ansi[2], .timestamps = ui_value.timestamp_gutter, .highlight = ui_value.input_line_highlight, .collapsed = ui_value.sidebar_collapsed };
    }
    pub fn miniPreviewShown(self: *const ViewModel) bool {
        return self.themeRecord() != null;
    }
    /// ANSI 16 色板的第 `index` 色（当前主题；没有主题库时透明）。
    pub fn ansiColor(self: *const ViewModel, index: usize) u32 {
        const record = self.themeRecord() orelse return 0;
        return record.theme.ansi[index];
    }
    pub fn terminalColors(self: *const ViewModel) TerminalColors {
        const record = self.themeRecord() orelse return .{};
        return .{ .background = record.theme.bg, .foreground = record.theme.fg };
    }

    // ── 协议插件（F-set-plugins） ──

    /// 已注册的插件（注册表顺序；超过 `plugin_pane.max_plugins` 的不显示）。
    pub fn pluginEntries(self: *const ViewModel) []const plugin_pane.Manifest {
        return pluginEntriesOf(self.controller);
    }
    fn pluginEntry(self: *const ViewModel, index: u8) plugin_pane.Manifest {
        return self.pluginEntries()[index];
    }
    /// 当前显示的详情页（注册表下标）；列表页、搜索结果、别的分类为 null。挂载时读，不建依赖（页面形态按纪元固定）。
    pub fn pluginDetail(self: *const ViewModel) ?u8 {
        return pluginDetailOf(self.controller);
    }
    pub fn pluginDetailShown(self: *const ViewModel) bool {
        return self.pluginDetail() != null;
    }
    /// 搜索词下有没有命中的插件或路线条目（搜索结果里本分类是否显示）。
    pub fn pluginHits(self: *const ViewModel) bool {
        return plugin_pane.anyMatch(self.pluginEntries(), self.pluginQuery()) or self.pluginPlannedShown();
    }
    fn pluginQuery(self: *const ViewModel) []const u8 {
        return if (searching(self.controller)) self.controller.search_query else "";
    }
    /// 列表页没有任何已注册的插件（“没有已注册的插件”）。
    pub fn pluginListEmpty(self: *const ViewModel) bool {
        return self.pluginEntries().len == 0;
    }
    /// 分组有没有（命中的）插件：没有时整个分组面板不显示。
    pub fn pluginGroupShown(self: *const ViewModel, group: PluginGroup) bool {
        return plugin_pane.groupCount(self.pluginEntries(), group, self.pluginQuery()) != 0;
    }
    /// 分组页头右侧：“3 个协议 · 随应用管理”（旧分组标签的后半）。
    pub fn pluginGroupMeta(self: *ViewModel, group: PluginGroup) []const u8 {
        var buffer: [160]u8 = undefined;
        const count = plugin_pane.groupCount(self.pluginEntries(), group, self.pluginQuery());
        const text = std.fmt.bufPrint(&buffer, "{d} 个协议 · 随应用管理", .{count}) catch "随应用管理";
        return swapIn(&self.plugin_group_meta[@intFromEnum(group)], text);
    }
    /// 分组里的行（搜索时只有命中的）；两份交替（Yix 行 key 按内容判等）。
    pub fn pluginItems(self: *ViewModel, group: PluginGroup) []const DrillItem {
        const g = @intFromEnum(group);
        self.plugin_item_flip[g] +%= 1;
        const list = &self.plugin_items[g][self.plugin_item_flip[g]];
        const query = self.pluginQuery();
        var count: usize = 0;
        for (self.pluginEntries(), 0..) |entry, index| {
            if (entry.origin != plugin_pane.origin(group) or !plugin_pane.matches(query, entry)) continue;
            const i: u8 = @intCast(index);
            list[count] = .{
                .key = index,
                .row_id = self.pluginId(i, .row),
                .title_id = self.pluginId(i, .name),
                .summary_id = self.pluginId(i, .description),
                .trail_id = self.pluginId(i, .trail),
                .icon = entry.icons.settings,
                .title = entry.display_name,
                .summary = plugin_pane.description(entry),
                .trail = if (plugin_pane.stateTag(pluginPhaseOf(self.controller, entry.id)).len != 0) "" else entry.plugin_version,
                .badge = plugin_pane.stateTag(pluginPhaseOf(self.controller, entry.id)),
                .badge_id = self.pluginId(i, .disabled),
                .badge_warning = plugin_pane.stateWarning(pluginPhaseOf(self.controller, entry.id)),
                .muted = !self.controller.plugin_page.launchEnabled(entry.id),
                .target = Intent.openAt(.{ .page = plugin_pane.page, .sub = i }),
            };
            count += 1;
        }
        if (count != 0) list[count - 1].last = true;
        return list[0..count];
    }
    /// “计划中”分组有没有（命中的）路线条目。
    pub fn pluginPlannedShown(self: *const ViewModel) bool {
        return plugin_pane.plannedCount(self.pluginQuery()) != 0;
    }
    /// “计划中”的行（路线条目；搜索时只有命中的）。没有能力、版本号，也不进详情页。
    pub fn pluginPlannedItems(self: *ViewModel) []const PlannedItem {
        self.plugin_planned_flip +%= 1;
        const list = &self.plugin_planned_items[self.plugin_planned_flip];
        const query = self.pluginQuery();
        var count: usize = 0;
        inline for (plugin_pane.roadmap.entries, 0..) |entry, index| {
            if (plugin_pane.plannedMatches(query, entry)) {
                list[count] = .{
                    .key = index,
                    .row_id = comptime plugin_pane.plannedId(entry, "row"),
                    .title_id = comptime plugin_pane.plannedId(entry, "name"),
                    .summary_id = comptime plugin_pane.plannedId(entry, "summary"),
                    .icon = entry.icon,
                    .title = entry.display_name,
                    .summary = comptime plugin_pane.plannedSummary(entry),
                };
                count += 1;
            }
        }
        if (count != 0) list[count - 1].last = true;
        return list[0..count];
    }
    /// 插件节点的 test_id（`settings.plugin.<插件 id>.<后缀>`）。
    pub fn pluginId(self: *ViewModel, index: u8, part: PluginPart) []const u8 {
        return idInto(&self.plugin_ids[index][@intFromEnum(part)], self.pluginEntry(index).id, ".", part.suffix());
    }
    pub fn pluginName(self: *const ViewModel, index: u8) []const u8 {
        return self.pluginEntry(index).display_name;
    }
    pub fn pluginDescription(self: *const ViewModel, index: u8) []const u8 {
        return plugin_pane.description(self.pluginEntry(index));
    }
    /// 列表行的尾注：插件版本（注册的元数据）。
    pub fn pluginVersion(self: *const ViewModel, index: u8) []const u8 {
        return self.pluginEntry(index).plugin_version;
    }
    /// 插件在设置里的图标名（`icons.settings`，视图映射成 `ui.icons`）。
    pub fn pluginIcon(self: *const ViewModel, index: u8) []const u8 {
        return self.pluginEntry(index).icons.settings;
    }
    pub fn pluginOriginTag(self: *const ViewModel, index: u8) []const u8 {
        return plugin_pane.originTag(self.pluginEntry(index).origin);
    }
    pub fn pluginNote(self: *const ViewModel, index: u8) []const u8 {
        return plugin_pane.manageNote(self.pluginEntry(index).origin);
    }
    pub fn pluginBodyId(self: *const ViewModel, index: u8) []const u8 {
        return plugin_pane.bodyId(self.pluginEntry(index).origin);
    }
    pub fn pluginPermissions(self: *const ViewModel, index: u8) []const u8 {
        return plugin_pane.permissions(self.pluginEntry(index));
    }

    /// 详情页的偏好字段行。
    pub fn pluginPrefItems(self: *ViewModel, index: u8) []const PluginPrefItem {
        self.plugin_pref_flip +%= 1;
        const list = &self.plugin_pref_items[self.plugin_pref_flip];
        const fields_ = plugin_pane.preferenceFields(self.pluginEntry(index));
        for (fields_, 0..) |_, field| list[field] = .{ .key = field, .field = @intCast(field), .last = field + 1 == fields_.len };
        return list[0..fields_.len];
    }
    pub fn pluginHasPrefs(self: *const ViewModel, index: u8) bool {
        return plugin_pane.preferenceFields(self.pluginEntry(index)).len != 0;
    }
    fn pluginField(self: *const ViewModel, index: u8, field: u8) plugin_pane.PreferenceField {
        return plugin_pane.preferenceFields(self.pluginEntry(index))[field];
    }
    pub fn pluginPrefId(self: *ViewModel, index: u8, field: u8, part: PluginPrefPart) []const u8 {
        const slot = &self.plugin_pref_ids[field][@intFromEnum(part)];
        const entry = self.pluginEntry(index);
        const key = self.pluginField(index, field).key;
        const text = std.fmt.bufPrint(&slot.buffer, "settings.plugin.{s}.{s}{s}", .{ entry.id, key, part.suffix() }) catch return "settings.plugin";
        slot.len = text.len;
        return slot.buffer[0..slot.len];
    }
    pub fn pluginPrefLabel(self: *const ViewModel, index: u8, field: u8) []const u8 {
        return self.pluginField(index, field).label;
    }
    pub fn pluginPrefKind(self: *const ViewModel, index: u8, field: u8) PluginPrefKind {
        return switch (self.pluginField(index, field).kind) {
            .boolean => .boolean,
            .string => .string,
            .choice => .choice,
        };
    }
    /// 生效时机（“下次连接生效” / “保存后生效”）。
    pub fn pluginPrefTiming(self: *const ViewModel, index: u8, field: u8) []const u8 {
        return plugin_pane.timingText(self.pluginField(index, field));
    }
    pub fn pluginPrefNextConnection(self: *const ViewModel, index: u8, field: u8) bool {
        return self.pluginField(index, field).apply_timing == .next_connection;
    }
    /// 字段在草稿里的值（否则是默认值）。
    pub fn pluginPrefText(self: *ViewModel, index: u8, field: u8) []const u8 {
        _ = self.signals.?.revision.get();
        const text = plugin_pane.preferenceValue(self.controller.model.value, self.pluginEntry(index).id, self.pluginField(index, field));
        return swapIn(&self.plugin_pref_text[field], text);
    }
    pub fn pluginPrefChecked(self: *ViewModel, index: u8, field: u8) bool {
        return std.mem.eql(u8, self.pluginPrefText(index, field), "true");
    }
    pub fn pluginPrefOptionCount(self: *const ViewModel, index: u8, field: u8) usize {
        return @min(self.pluginField(index, field).options.len, plugin_pane.max_options);
    }
    pub fn pluginPrefOptionValue(self: *const ViewModel, index: u8, field: u8, option: usize) []const u8 {
        return self.pluginField(index, field).options[option].value;
    }
    pub fn pluginPrefOptionLabel(self: *const ViewModel, index: u8, field: u8, option: usize) []const u8 {
        return self.pluginField(index, field).options[option].label;
    }
    /// 偏好编辑被拒绝的原因（行下提示；没有时为空串）。
    pub fn pluginPrefProblem(self: *const ViewModel, index: u8, field: u8) []const u8 {
        _ = self.signals.?.revision.get();
        const problem = self.plugin_problem orelse return "";
        return if (problem.plugin == index and problem.field == field) problem.reason else "";
    }
    pub fn pluginPrefInvalid(self: *const ViewModel, index: u8, field: u8) bool {
        return self.pluginPrefProblem(index, field).len != 0;
    }
    // ── 随应用插件的启用开关（PLUGIN_ARCH_PLAN 6.2.1 Q5；Pencil XqqLV 稿 2：Jm2fZ / SH1gb / NHr2L / B0QXg6 / DzPbO / IeCzY） ──

    /// “状态”分组只给随应用提供（`bundled`）的插件；内置三项没有开关（Q5a）。
    pub fn pluginToggleShown(self: *const ViewModel, index: u8) bool {
        return self.controller.plugin_page.linked(self.pluginEntry(index).id) != null;
    }
    /// 开关的值：草稿里的启用状态（拨动后是“改了未保存”，经保存栏保存）。
    pub fn pluginEnabledDraft(self: *const ViewModel, index: u8) bool {
        _ = self.signals.?.revision.get();
        const linked = self.controller.plugin_page.linked(self.pluginEntry(index).id) orelse return true;
        return enablement.savedEnabled(self.controller.model.value, linked);
    }
    /// 41 号说明稿的状态：已启用 → 改了未保存 → 待重启 → 已禁用（以本次启动、已保存配置、草稿三者比较）。
    pub fn pluginPhase(self: *const ViewModel, index: u8) enablement.Phase {
        _ = self.signals.?.revision.get();
        return pluginPhaseOf(self.controller, self.pluginEntry(index).id);
    }
    pub fn pluginPhaseIs(self: *const ViewModel, index: u8, value: enablement.Phase) bool {
        return self.pluginPhase(index) == value;
    }
    pub fn pluginPending(self: *const ViewModel, index: u8) bool {
        const value = self.pluginPhase(index);
        return value == .pending_disable or value == .pending_enable;
    }
    /// 本次启动没有加载这个插件（已禁用，或配置无法读取，Q5c）：详情页的说明与列表行按“已禁用”显示。
    pub fn pluginNotLoaded(self: *const ViewModel, index: u8) bool {
        return !self.controller.plugin_page.launchEnabled(self.pluginEntry(index).id);
    }
    /// 配置无法读取，随应用插件这次没有加载（Q5c）。
    pub fn pluginConfigUnreadable(self: *const ViewModel, index: u8) bool {
        const launch = self.controller.plugin_page.launch orelse return false;
        return launch.config_unreadable and self.pluginToggleShown(index);
    }
    /// 开关行的标签（“启用 BMC · iKVM”）。
    pub fn pluginToggleLabel(self: *ViewModel, index: u8) []const u8 {
        var buffer: [160]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "启用 {s}", .{self.pluginName(index)}) catch "启用";
        return swapIn(&self.plugin_toggle_label, text);
    }
    /// 头部卡片的状态标签（待重启是 warning，已禁用是中性；其它状态不显示）。
    pub fn pluginStateTag(self: *const ViewModel, index: u8) []const u8 {
        return plugin_pane.stateTag(self.pluginPhase(index));
    }
    pub fn pluginStateTagShown(self: *const ViewModel, index: u8) bool {
        return self.pluginStateTag(index).len != 0;
    }
    /// 待重启提示（NHr2L / DzPbO）：标题“重启 ZeroWork 后停用 / 启用 {名称}”。
    pub fn pluginPendingTitle(self: *ViewModel, index: u8) []const u8 {
        var buffer: [256]u8 = undefined;
        const verb = if (self.pluginPhase(index) == .pending_enable) "启用" else "停用";
        const text = std.fmt.bufPrint(&buffer, "重启 ZeroWork 后{s} {s}", .{ verb, self.pluginName(index) }) catch "重启 ZeroWork 后生效";
        return swapIn(&self.plugin_notice_title, text);
    }
    pub fn pluginPendingMessage(self: *const ViewModel, index: u8) []const u8 {
        return plugin_pane.pendingMessage(self.pluginPhase(index));
    }
    /// 已禁用提示（B0QXg6 / IeCzY）：标题“{名称} 已禁用”；配置无法读取时说明原因（Q5c）。
    pub fn pluginDisabledTitle(self: *ViewModel, index: u8) []const u8 {
        var buffer: [256]u8 = undefined;
        const text = if (self.pluginConfigUnreadable(index)) "配置无法读取，随应用提供的插件暂未加载" else std.fmt.bufPrint(&buffer, "{s} 已禁用", .{self.pluginName(index)}) catch "已禁用";
        return swapIn(&self.plugin_notice_title, text);
    }
    pub fn pluginDisabledMessage(self: *const ViewModel, index: u8) []const u8 {
        return if (self.pluginConfigUnreadable(index)) plugin_pane.unreadable_message else plugin_pane.disabled_message;
    }
    /// 已禁用提示的显示：本次没有加载、也没有待重启的改动（待重启时显示待重启提示）。
    pub fn pluginDisabledShown(self: *const ViewModel, index: u8) bool {
        return self.pluginToggleShown(index) and self.pluginNotLoaded(index) and !self.pluginPending(index);
    }
    /// 拨动开关（Q5）：被依赖时拒绝禁用并在行下说明原因。
    fn editPluginEnabled(self: *ViewModel, edit: intent_mod.PluginEnabled) void {
        const c = self.controller;
        if (c.state() == .saving) return;
        const entries = self.pluginEntries();
        if (edit.plugin >= entries.len) return;
        c.setPluginEnabled(entries[edit.plugin].id, edit.enabled) catch |err| {
            self.plugin_enable_problem = .{ .plugin = edit.plugin, .field = 0, .reason = error_text.lineOr(err, "无法更改插件开关" ++ error_text.log_suffix) };
            return;
        };
        self.plugin_enable_problem = null;
    }
    pub fn pluginEnableProblem(self: *const ViewModel, index: u8) []const u8 {
        _ = self.signals.?.revision.get();
        const problem = self.plugin_enable_problem orelse return "";
        return if (problem.plugin == index) problem.reason else "";
    }
    pub fn pluginEnableInvalid(self: *const ViewModel, index: u8) bool {
        return self.pluginEnableProblem(index).len != 0;
    }

    /// 改一个插件偏好（经 Controller 按插件声明校验；保存中不改，同旧 `PreferenceControl.edit`）。
    fn editPluginPreference(self: *ViewModel, edit: intent_mod.PluginPreference) void {
        const c = self.controller;
        if (c.state() == .saving) return;
        const entries = self.pluginEntries();
        if (edit.plugin >= entries.len) return;
        const fields_ = plugin_pane.preferenceFields(entries[edit.plugin]);
        if (edit.field >= fields_.len) return;
        c.setPluginPreference(entries[edit.plugin].id, fields_[edit.field].key, edit.value) catch |err| {
            self.plugin_problem = .{ .plugin = edit.plugin, .field = edit.field, .reason = error_text.lineOr(err, "无法应用此偏好" ++ error_text.log_suffix) };
            return;
        };
        if (self.plugin_problem) |problem| if (problem.plugin == edit.plugin and problem.field == edit.field) {
            self.plugin_problem = null;
        };
    }
};

// ── 协议插件（F-set-plugins：两级导航，人工验收反馈第 10 条；数据规则在 `plugin_pane.zig`） ──
//
// 列表页 = `Location{ .page = 5 }`，详情页 = `Location{ .page = 5, .sub = <注册表下标> }`。页面形态（列表 / 哪个插件的详情、
// 哪些行）在内容页挂载时定下（同其它面板，位置与搜索词变了宿主换纪元整页重挂）；偏好字段的值与校验提示跟随 `revision`。

/// 两级导航的一行（`components/rows.yix` 的 `DrillRow`；F-set-plugins 起，列表页通用）：图标底 + 标题 / 摘要 + 尾注 + 箭头，
/// 点击发 `target`（通常是 `Intent.openAt(子页)`）。`icon` 是 `ui.icons` 的名字（视图映射，找不到用 `plug`）；文字与 id
/// 由调用方保证在页面挂载期间有效。`last` = 本组最后一行（下面没有分隔线）。
pub const DrillItem = struct {
    key: u64,
    row_id: []const u8,
    title_id: []const u8 = "",
    summary_id: []const u8 = "",
    trail_id: []const u8 = "",
    icon: []const u8,
    title: []const u8,
    summary: []const u8 = "",
    trail: []const u8 = "",
    /// 行尾的状态标签（协议插件 Q5：“已禁用”中性、“重启后停用 / 启用”warning，代替尾注；空串不显示）。
    badge: []const u8 = "",
    badge_id: []const u8 = "",
    badge_warning: bool = false,
    /// 图标与标题降为次要色（被禁用的插件，UuE31）。
    muted: bool = false,
    last: bool = false,
    target: Intent,
};
/// “计划中”的一行（路线条目）：图标、名称、“{目标版本} 版本待实施”；不可点击，没有尾注与箭头。
pub const PlannedItem = struct {
    key: u64,
    row_id: []const u8,
    title_id: []const u8,
    summary_id: []const u8,
    icon: []const u8,
    title: []const u8,
    summary: []const u8,
    last: bool = false,
};
/// 详情页的一个偏好字段行。
pub const PluginPrefItem = struct { key: u64, field: u8, last: bool };
pub const PluginPrefKind = enum { boolean, string, choice };
pub const PluginProblem = struct { plugin: u8, field: u8, reason: []const u8 };
/// 插件节点的 test_id（`settings.plugin.<插件 id>.<后缀>`）。
pub const PluginPart = enum {
    /// 列表行（可点击根）、名称、说明、尾注（版本）。
    row,
    name,
    description,
    trail,
    /// 详情页：根、头部卡片、来源标签、说明、管理说明、版本值、权限“?”、权限提示、权限值。
    detail,
    header,
    origin,
    summary,
    version_message,
    version,
    permissions,
    permissions_tip,
    permissions_value,
    /// 随应用插件的启用（Q5）：“状态”分组、开关、开关下方说明、头部卡片的状态标签、列表行的“已禁用 / 重启后停用”标记、
    /// 待重启 / 已禁用提示、“立即重启”。
    status,
    enabled,
    enabled_hint,
    state,
    disabled,
    notice,
    restart,
    enabled_error,

    fn suffix(self: PluginPart) []const u8 {
        return switch (self) {
            .row => "row",
            .name => "name",
            .description => "description",
            .trail => "trail",
            .detail => "detail",
            .header => "header",
            .origin => "origin",
            .summary => "summary",
            .version_message => "version.message",
            .version => "version",
            .permissions => "permissions",
            .permissions_tip => "permissions.tooltip",
            .permissions_value => "permissions.value",
            .status => "status",
            .enabled => "enabled",
            .enabled_hint => "enabled.hint",
            .state => "state",
            .disabled => "disabled",
            .notice => "notice",
            .restart => "restart",
            .enabled_error => "enabled.error",
        };
    }
};
/// 偏好字段节点的 test_id（`settings.plugin.<插件 id>.<字段 key>[.<后缀>]`；控件沿用旧 id）。
pub const PluginPrefPart = enum {
    row,
    control,
    timing,
    timing_tip,
    err,

    fn suffix(self: PluginPrefPart) []const u8 {
        return switch (self) {
            .row => ".row",
            .control => "",
            .timing => ".timing",
            .timing_tip => ".timing.tooltip",
            .err => ".error",
        };
    }
};
const plugin_part_count = std.enums.values(PluginPart).len;
const plugin_pref_part_count = std.enums.values(PluginPrefPart).len;
const IdSlot = struct { len: usize = 0, buffer: [128]u8 = undefined };

/// 某插件在设置页的启用状态（Q5）：本次启动 / 已保存配置 / 草稿。不是随应用插件时恒为 `.enabled`。
pub fn pluginPhaseOf(c: *const Controller, plugin_id: []const u8) enablement.Phase {
    const linked = c.plugin_page.linked(plugin_id) orelse return .enabled;
    return enablement.phase(c.plugin_page.launchEnabled(plugin_id), enablement.savedEnabled(c.model.original, linked), enablement.savedEnabled(c.model.value, linked));
}

fn pluginDetailOf(c: *const Controller) ?u8 {
    if (!c.drill_down or c.model.page_index != plugin_pane.page) return null;
    if (searching(c)) return null;
    const sub = c.model.subpage orelse return null;
    return if (sub < c.plugin_page.entries().len) sub else null;
}
fn idInto(slot: *IdSlot, plugin_id: []const u8, comptime separator: []const u8, suffix: []const u8) []const u8 {
    const text = std.fmt.bufPrint(&slot.buffer, "settings.plugin.{s}" ++ separator ++ "{s}", .{ plugin_id, suffix }) catch return "settings.plugin";
    slot.len = text.len;
    return slot.buffer[0..slot.len];
}

pub fn pluginEntriesOf(c: *const Controller) []const plugin_pane.Manifest {
    const all = c.plugin_page.entries();
    return all[0..@min(all.len, plugin_pane.max_plugins)];
}

// ── 投影规则（与旧视图 settings_content_view 的判定一致） ──

fn searching(c: *const Controller) bool {
    return std.mem.trim(u8, c.search_query, " \t\r\n").len != 0;
}
fn modeOf(c: *const Controller) Mode {
    if (searching(c)) return .search;
    const page = c.model.page_index;
    if (c.drill_down and catalog.get(page, c.model.subpage) == null and catalog.hasOverview(page)) return .overview;
    return .panes;
}
fn titleOf(c: *const Controller) []const u8 {
    if (searching(c)) return "搜索结果";
    if (pluginDetailOf(c)) |index| return c.plugin_page.entries()[index].display_name;
    // F-set-ai：提供方详情页的标题是提供方名称。
    if (c.drill_down) if (c.aiProviderDetail()) |index| return ai.displayName(c.model.value.ai.providers[index]);
    if (c.drill_down) if (catalog.get(c.model.page_index, c.model.subpage)) |sub| return sub.title;
    return catalog.title(c.model.page_index);
}
fn canBackOf(c: *const Controller) bool {
    return searching(c) or c.history.canBack();
}
fn canForwardOf(c: *const Controller) bool {
    return !searching(c) and c.history.canForward();
}
fn whereOf(c: *const Controller) save_flow.Where {
    return .{ .location = c.location(), .searching = searching(c), .drill_down = c.drill_down };
}
/// 清空搜索后回到的位置（`Controller.setSearch("")`：搜索开始处的分类与子页面）。
fn searchReturn(c: *const Controller) save_flow.Where {
    const page = c.search_return_page orelse c.model.page_index;
    const sub = if (c.search_return_page != null) c.search_return_subpage else c.model.subpage;
    return .{ .location = .{ .page = @intCast(page), .sub = catalog_history.validSubpage(page, sub) }, .drill_down = c.drill_down };
}
/// 一次导航（用户发起）会落到哪里——与 `ViewModel.navigate` 对 Controller 的操作逐分支对应，但不改任何状态。
fn targetOf(c: *const Controller, intent: Intent) save_flow.Where {
    const was_searching = searching(c);
    const base: Location = if (was_searching) searchReturn(c).location else c.location();
    const history = c.history;
    const target: Location = switch (intent) {
        .select_category => |page| .{ .page = page },
        .open => |location_| location_,
        .open_subpage => |sub| .{ .page = base.page, .sub = sub },
        .back => if (!was_searching and history.canBack()) history.items[history.cursor - 1] else base,
        .forward => if (history.canForward()) history.items[history.cursor + 1] else base,
        else => base,
    };
    return .{ .location = .{ .page = target.page, .sub = catalog_history.validSubpage(target.page, target.sub) }, .drill_down = c.drill_down };
}
const catalog_history = @import("settings_history.zig");

// ── 面板正文的辅助（P3 3e） ──

/// 已改写面板里某个输入框的焦点标识（`locate_problem` 聚焦出错字段）；不是面板输入框时为 null。
fn focusTarget(section: []const u8, key: []const u8) ?[]const u8 {
    for (fields.pages) |list| for (list) |item| for (item.rows) |row| if (row.key) |candidate| {
        if (row.kind == .input and std.mem.eql(u8, candidate.section, section) and std.mem.eql(u8, candidate.key, key)) return row.ids.focus;
    };
    return null;
}
/// 已改写面板里的全部草稿字段（文字缓冲按它分槽）。
const field_keys = blk: {
    var count: usize = 0;
    for (fields.pages) |list| for (list) |item| for (item.rows) |row| {
        if (row.key != null) count += 1;
    };
    var list: [count]Key = undefined;
    var index: usize = 0;
    for (fields.pages) |pages_list| for (pages_list) |item| for (item.rows) |row| if (row.key) |key| {
        list[index] = key;
        index += 1;
    };
    break :blk list;
};
const field_slot_count = field_keys.len;
const pane_slot_count = blk: {
    var count: usize = 0;
    for (fields.pages) |list| count += list.len;
    break :blk count;
};
fn fieldSlot(key: Key) usize {
    for (field_keys, 0..) |candidate, index| if (std.mem.eql(u8, candidate.section, key.section) and std.mem.eql(u8, candidate.key, key.key)) return index;
    unreachable;
}
fn paneSlot(item: *const fields.Pane) usize {
    var index: usize = 0;
    for (fields.pages) |list| for (list) |candidate| {
        if (candidate == item) return index;
        index += 1;
    };
    unreachable;
}
/// 把文字写进槽里两份缓冲中的另一份再返回（内容没变时返回原切片）：Yix 按内容判等，
/// 旧切片在下一次换文字前一直有效，不会与新内容共用内存。
fn swapIn(slot: anytype, text: []const u8) []const u8 {
    const n = @min(text.len, slot.buffers[0].len);
    const current = slot.buffers[slot.flip][0..slot.len[slot.flip]];
    if (std.mem.eql(u8, current, text[0..n])) return current;
    slot.flip +%= 1;
    @memcpy(slot.buffers[slot.flip][0..n], text[0..n]);
    slot.len[slot.flip] = n;
    return slot.buffers[slot.flip][0..n];
}
/// 草稿值的显示文字（旧 `settings_controls.valueText`）。
pub fn formatValue(value: catalog.config.Config, key: Key, buffer: []u8) ![]const u8 {
    if (std.mem.eql(u8, key.section, "ssh") and std.mem.eql(u8, key.key, "reconnect_backoff")) {
        const sequence = value.ssh.reconnect_backoff;
        return std.fmt.bufPrint(buffer, "{d}, {d}, {d}, {d}, {d}", .{ sequence[0], sequence[1], sequence[2], sequence[3], sequence[4] });
    }
    return switch (values.read(value, key.section, key.key) orelse return error.UnknownKey) {
        .text => |text| text,
        .unsigned => |number| std.fmt.bufPrint(buffer, "{d}", .{number}),
        .decimal => |number| std.fmt.bufPrint(buffer, "{d}", .{number}),
        .boolean => error.InvalidType,
    };
}
/// 字段校验问题的提示文案（旧 `settings_controls.problemText`）。
pub fn problemText(key: Key, problem: anyerror) []const u8 {
    const window_policy = catalog.window_policy;
    if (problem == error.TransferWindowBudgetExceeded) return "单任务窗口超过 " ++ @import("../../../shared/base/format.zig").comptimeBytes(window_policy.max_job_window_bytes) ++ "，请减小分块大小或窗口分块数";
    if (problem == error.TransferGlobalWindowBudgetExceeded) return "并发窗口总量超过 " ++ @import("../../../shared/base/format.zig").comptimeBytes(window_policy.max_global_window_bytes) ++ "，请减小分块大小、窗口分块数或并发任务数";
    if (problem == error.TransferWindowOverflow) return "传输窗口总量溢出，请减小分块大小、窗口分块数或并发任务数";
    if (std.mem.eql(u8, key.key, "reconnect_backoff")) return "请输入 5 个 0–255 整数，例如 [1,2,4,8,16]";
    if (std.mem.eql(u8, key.key, "reconnect_max")) return "请输入 0–5 的整数";
    if (std.mem.eql(u8, key.key, "quiet_hours")) return "请输入有效时段，例如 22:00-08:00";
    if (std.mem.eql(u8, key.key, "shared_pacing_kbps")) return "请输入 0–4294967295 的整数";
    if (std.mem.eql(u8, key.key, "window_chunks") or std.mem.eql(u8, key.key, "max_tasks")) return "请输入 1–255 的整数";
    if (std.mem.eql(u8, key.key, "term")) return "终端类型不能为空";
    return "请输入 1–65535 的整数";
}

/// 整窗快捷键的键位（纯函数）：Escape；⌘W 与 ⌘,（原宿主 `onWindowKey` 的全部分支）。
pub fn windowCommand(key: ui.events.KeyCode, modifiers: ui.events.Modifiers) ?WindowCommand {
    if (key == .escape) return .escape;
    if (modifiers.super and (key == .w or key == .comma)) return .close;
    return null;
}

// ── 外观与主题面板的文案（P3 3e 外观包；与旧 `appearance_view` 逐字相同） ──

/// 输入框显示的草稿值（旧 `appearance_view.fieldDisplay`）：字重显示数值、透明度一位小数、行高两位小数。
fn displayValue(value: catalog.config.Config, key: Key, buffer: []u8) ![]const u8 {
    const current = values.read(value, key.section, key.key) orelse return error.UnknownKey;
    if (std.mem.eql(u8, key.key, "font_weight") and current == .text) return std.fmt.bufPrint(buffer, "{d}", .{@backingInt(fonts.parseWeight(current.text) orelse .regular)});
    if (std.mem.eql(u8, key.key, "transparency") and current == .decimal) return std.fmt.bufPrint(buffer, "{d:.1}", .{current.decimal});
    if (std.mem.eql(u8, key.key, "line_height") and current == .decimal) return std.fmt.bufPrint(buffer, "{d:.2}", .{current.decimal});
    return switch (current) {
        .text => |text| text,
        .unsigned => |number| std.fmt.bufPrint(buffer, "{d}", .{number}),
        .decimal => |number| std.fmt.bufPrint(buffer, "{d}", .{number}),
        .boolean => |on| if (on) "true" else "false",
    };
}
/// 外观字段的校验提示（旧 `appearance_view.fieldProblem`）。
fn appearanceProblemText(key: Key, problem: anyerror) []const u8 {
    if (std.mem.eql(u8, key.key, "blur_px")) return "请输入 0–96 的整数；有效草稿保留，Esc 撤销本次输入。";
    if (std.mem.eql(u8, key.key, "transparency")) return "请输入 0–100 的有限数值；有效草稿保留，Esc 撤销本次输入。";
    if (std.mem.eql(u8, key.key, "font_size")) return "请输入 8–48 的整数。";
    if (std.mem.eql(u8, key.key, "font_family")) return fonts.problemMessage(error.InvalidFamily);
    if (std.mem.eql(u8, key.key, "font_weight")) return fonts.problemMessage(problem);
    if (std.mem.eql(u8, key.key, "line_height")) return "请输入 1.0–3.0 的有限数值，不含单位。";
    return error_text.lineOr(problem, "取值无效");
}
/// 主题导入 / 删除失败的提示：只查 `shared/base/error_text.zig` 的主题目录（宿主通知用同一份）。
fn themeProblemText(problem: anyerror) []const u8 {
    return error_text.lineFrom(error_text.theme(problem), "主题操作未完成" ++ error_text.log_suffix);
}
