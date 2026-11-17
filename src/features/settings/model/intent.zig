//! 设置窗口的动作上行：视图（及宿主回流的异步结果）只经 `ViewModel.dispatch(Intent)` 改变状态
//! （ARCHITECTURE_PLAN §4.4、§4.5）。变体用 snake_case 动词短语；带载荷的变体另有构造函数，
//! 供 `.yix` 事件实参使用（V-3：实参里不能写结构体字面量；名字不能与变体重名）。
//! 本文件不依赖 zenit `ui`。
const std = @import("std");
const catalog = @import("catalog.zig");
const values = @import("settings_values.zig");
const keybinding_edit = @import("keybinding_edit.zig");
const background = @import("../../../config/background_asset.zig");
/// “AI 辅助”面板的动作（F-set-ai，见 `ai_pane.zig`）。
pub const ai_pane = @import("ai_pane.zig");
pub const AiCommand = ai_pane.Command;
const data_cleanup = @import("data_cleanup.zig");

pub const Location = catalog.Location;
/// 一个设置字段：`settings_pages.keys` 的 `section.key`。
pub const Key = struct { section: []const u8, key: []const u8 };

/// Save Bar、数据页、通知页、更新页上的按钮（与旧视图的 `settings_content_view.Action` 一一对应）。
pub const Command = enum { reset_defaults, revert, save, import_theme, export_logs, clear_logs, clear_all, open_config_dir, credential_help, check_updates, open_update_release, notification_permission, restart_app };

/// 宿主弹出的“未保存 / 恢复默认”确认里的选择。
pub const Decision = enum {
    /// 保存后关闭（未保存确认的“保存关闭”）。
    save,
    /// 放弃草稿并关闭。
    discard,
    /// 载入默认值草稿（恢复默认确认的“恢复”）。
    reset,
    /// 返回设置（“继续编辑” / “取消” / 关闭按钮）。
    cancel,
};

/// 整窗快捷键（S-6，见 `ViewModel.windowKey`）。
pub const WindowCommand = enum {
    /// Escape：先收起最上层（材质预览、正文里的提示 / 弹层 / 原地编辑、提供方编辑、选择器），都没有时按关闭处理。
    escape,
    /// ⌘W / ⌘,：按关闭处理（未保存草稿要确认）。
    close,
};

pub const Edit = struct { key: Key, value: values.Value };
/// 输入框里的原文（P3 3c）：由 Controller 按 schema 解析，解析失败记为校验问题而不是拒绝输入。
pub const EditRaw = struct { key: Key, text: []const u8 };
pub const SaveFinished = struct { err: ?anyerror = null };
/// 协议插件详情页里改一个插件偏好（F-set-plugins）：插件在注册表里的下标、它的第几个偏好字段、新值的文字
/// （开关是 "true" / "false"，选择是选项值）。由 Controller 按插件声明的字段校验（`setPluginPreference`）。
/// 随应用插件的启用开关（Q5）：`plugin` 是设置页插件列表下标。
pub const PluginEnabled = struct { plugin: u8, enabled: bool };
pub const PluginPreference = struct { plugin: u8, field: u8, value: []const u8 };
/// 面板里的弹层（帮助提示 / 选择框下拉）开合：`id` 是弹层的 test_id（P3 3e）。
pub const Popup = struct { id: []const u8, open: bool };

/// 快捷键行内录制（P3 3e 第二批，见 `model/keybinding_edit.zig` 与 `ViewModel.keyDown`）。
pub const KeyCommand = union(enum) {
    /// 点击键帽区 / 键帽区聚焦时 Enter、Space：这一行进入录制（别的行的录制 / 冲突提示随之收起）。
    record: keybinding_edit.Action,
    /// 录制中按住 / 松开修饰键（实时显示）。
    hold: keybinding_edit.Mods,
    /// 录制中按下了带主键的组合：判定后写草稿，或进入无效 / 冲突态。
    press: keybinding_edit.Chord,
    /// Esc、冲突提示的“取消”、键帽区失焦（录制中 / 无效态）：回到静止，草稿不变。
    cancel,
    /// 键帽区失焦：录制中 / 无效态回到静止；冲突态保留提示，只是不再接按键。
    blur: keybinding_edit.Action,
    /// 冲突提示的“交换”：本动作取新组合，对方改用本动作原来的组合。
    swap,
    /// 单行恢复默认（默认值被别的动作占用时进入冲突态）。
    reset: keybinding_edit.Action,
};

/// 外观与主题面板的动作（P3 3e 外观包）：草稿编辑由 view-model 直接写 Controller（并通知宿主重新校验字体 / 准备背景），
/// 主题库与背景资源经 `Effect.appearance` 交宿主。字符串只在 dispatch 期间有效。
pub const AppearanceIntent = union(enum) {
    /// 主题卡片：选中一个主题（草稿）。
    select_theme: []const u8,
    /// 卡片右键菜单的“删除导入主题”：先弹原生确认框（不可逆，CONSISTENCY_AUDIT #2）。
    request_remove_theme: struct { id: []const u8, name: []const u8 },
    /// 确认框里的“删除导入主题”：真正删除。
    remove_theme: []const u8,
    /// 选择背景图片 / 目录。
    choose_background,
    /// 移除背景图片（草稿路径清空）。
    remove_background,
    /// 背景图片对齐（九宫格）。
    alignment: struct { x: background.Horizontal, y: background.Vertical },
    /// 全窗口材质预览：进入 / 返回设置。
    preview_material: bool,
    /// 恢复已保存的背景（材质预览条）。
    restore_materials,
    /// 开关、选择框、滑块：写一个值。
    edit: Edit,
    /// 输入框逐字编辑：原文交 Controller 解析（无效原文记成字段问题）。
    edit_raw: EditRaw,
    /// 输入框提交（Enter）：透明度按十分位取整，字体相关字段重新校验字体。
    submit: EditRaw,
    /// 字体族选择框里的“自定义字体…”：换成输入框并聚焦它。
    custom_font,
};

pub const Intent = union(enum) {
    // ── 导航与历史 ──
    /// 左侧导航选中分类（`settings_pages.pages` 下标）。
    select_category: u8,
    /// 打开某分类的概览或子页面（重新打开窗口、跳到校验问题）。
    open: Location,
    /// 打开当前分类的第 n 个子页面（概览行）。
    open_subpage: u8,
    back,
    forward,
    // ── 搜索 ──
    search: []const u8,
    // ── 整窗快捷键 ──
    window: WindowCommand,
    // ── 视图状态 ──
    /// 内容视口回报的稳定滚动偏移（S-5，`W.ScrollArea onScrollYChange`）：按挂载时的槽存档。
    scrolled: f32,
    // ── 草稿 ──
    /// 视图经 settings-value 边界改一个字段。
    edit: Edit,
    /// 视图交来输入框原文（`.yix` 行组件 InputRow；P3 3c 新增）。
    edit_raw: EditRaw,
    /// 旧面板直接改了 Controller 的草稿（提供方、扩展、外观、插件等），通知 view-model 重新投影。
    draft_changed,
    /// 面板弹层开合（P3 3e）。
    popup: Popup,
    /// 选择框里的“自定义…”（原地编辑，S-13：view-model 打开 `W.Popover` 并持有草稿）或目录字段（下载目录：
    /// 宿主的系统目录面板，`Effect.pick_directory`）。
    choose: Key,
    /// 快捷键行内录制（P3 3e 第二批）。
    key: KeyCommand,
    /// 协议插件的偏好字段（F-set-plugins）。
    plugin_preference: PluginPreference,
    /// 随应用插件的启用开关（Q5）：只改草稿，保存后下次启动生效。
    plugin_enabled: PluginEnabled,
    /// 跳到第一个校验问题所在的子页面。
    locate_problem,
    // ── 按钮与确认 ──
    command: Command,
    decide: Decision,
    // ── 宿主回流（主线程） ──
    /// 宿主执行完 `Effect.save`：`err == null` 表示已提交。
    save_finished: SaveFinished,
    /// 外观与主题面板（P3 3e 外观包）。
    appearance: AppearanceIntent,
    /// “AI 辅助”面板（F-set-ai）：服务提供方列表 / 详情、模型编辑器、删除确认、技能与 MCP。
    ai: AiCommand,
    /// “清除全部数据…”的确认流程（S-12，`model/data_cleanup.zig`）：宿主回流的检查结果与对话框里的选择。
    cleanup: data_cleanup.Event,
    /// 原地编辑的草稿（S-13，“自定义 TERM 声明…”）：输入框逐字编辑（只改草稿文字，不写 Controller）。
    custom_text: []const u8,
    /// 原地编辑提交（Enter）：交 Controller 校验；通过则收起，失败在编辑框里提示。
    custom_submit: []const u8,

    pub fn selectCategory(page: usize) Intent {
        return .{ .select_category = @intCast(page) };
    }
    pub fn openAt(location: Location) Intent {
        return .{ .open = location };
    }
    pub fn openSubpage(index: u8) Intent {
        return .{ .open_subpage = index };
    }
    pub fn scrolledTo(offset: f32) Intent {
        return .{ .scrolled = offset };
    }
    pub fn searchFor(text: []const u8) Intent {
        return .{ .search = text };
    }
    pub fn editValue(key: Key, value: values.Value) Intent {
        return .{ .edit = .{ .key = key, .value = value } };
    }
    pub fn editText(key: Key, text: []const u8) Intent {
        return .{ .edit_raw = .{ .key = key, .text = text } };
    }
    pub fn popupChanged(id: []const u8, open: bool) Intent {
        return .{ .popup = .{ .id = id, .open = open } };
    }
    pub fn chooseFor(key: Key) Intent {
        return .{ .choose = key };
    }
    pub fn runCommand(command_: Command) Intent {
        return .{ .command = command_ };
    }
    pub fn decideWith(decision: Decision) Intent {
        return .{ .decide = decision };
    }
    /// Save Bar 的保存（`close_after == false`）或确认弹窗的“保存关闭”。
    pub fn saveDraft(close_after: bool) Intent {
        return if (close_after) .{ .decide = .save } else .{ .command = .save };
    }
    pub fn recordKey(action: keybinding_edit.Action) Intent {
        return .{ .key = .{ .record = action } };
    }
    pub fn resetKey(action: keybinding_edit.Action) Intent {
        return .{ .key = .{ .reset = action } };
    }
    pub fn blurKey(action: keybinding_edit.Action) Intent {
        return .{ .key = .{ .blur = action } };
    }
    pub fn swapKey() Intent {
        return .{ .key = .swap };
    }
    pub fn cancelKey() Intent {
        return .{ .key = .cancel };
    }
    pub fn keyCommand(command_: KeyCommand) Intent {
        return .{ .key = command_ };
    }
    pub fn setPluginEnabled(plugin: u8, enabled: bool) Intent {
        return .{ .plugin_enabled = .{ .plugin = plugin, .enabled = enabled } };
    }
    pub fn setPluginPreference(plugin: u8, field: u8, value: []const u8) Intent {
        return .{ .plugin_preference = .{ .plugin = plugin, .field = field, .value = value } };
    }
    pub fn saveFinished(err: ?anyerror) Intent {
        return .{ .save_finished = .{ .err = err } };
    }
    // ── 外观与主题（P3 3e 外观包） ──
    pub fn selectTheme(id: []const u8) Intent {
        return .{ .appearance = .{ .select_theme = id } };
    }
    pub fn removeTheme(id: []const u8) Intent {
        return .{ .appearance = .{ .remove_theme = id } };
    }
    pub fn requestRemoveTheme(id: []const u8, name: []const u8) Intent {
        return .{ .appearance = .{ .request_remove_theme = .{ .id = id, .name = name } } };
    }
    pub fn appearanceValue(key: Key, value: values.Value) Intent {
        return .{ .appearance = .{ .edit = .{ .key = key, .value = value } } };
    }
    pub fn appearanceText(key: Key, text: []const u8) Intent {
        return .{ .appearance = .{ .edit_raw = .{ .key = key, .text = text } } };
    }
    pub fn appearanceSubmit(key: Key, text: []const u8) Intent {
        return .{ .appearance = .{ .submit = .{ .key = key, .text = text } } };
    }
    pub fn alignBackground(x: background.Horizontal, y: background.Vertical) Intent {
        return .{ .appearance = .{ .alignment = .{ .x = x, .y = y } } };
    }
    pub fn appearanceAction(action: std.meta.Tag(AppearanceIntent)) Intent {
        return switch (action) {
            .choose_background => .{ .appearance = .choose_background },
            .remove_background => .{ .appearance = .remove_background },
            .restore_materials => .{ .appearance = .restore_materials },
            .custom_font => .{ .appearance = .custom_font },
            else => unreachable,
        };
    }
    pub fn previewMaterial(active: bool) Intent {
        return .{ .appearance = .{ .preview_material = active } };
    }
    /// F-set-ai：AI 面板的动作（`.yix` 事件实参里用 `m.Intent.aiDo(.{ .open_provider = i })`）。
    pub fn aiDo(command_: AiCommand) Intent {
        return .{ .ai = command_ };
    }
    // ── 清除全部数据（S-12） ──
    pub fn cleanupEvent(event: data_cleanup.Event) Intent {
        return .{ .cleanup = event };
    }
    pub fn confirmCleanup() Intent {
        return .{ .cleanup = .confirm };
    }
    pub fn cancelCleanup() Intent {
        return .{ .cleanup = .cancel };
    }
    // ── 原地编辑（S-13） ──
    pub fn customText(text: []const u8) Intent {
        return .{ .custom_text = text };
    }
    pub fn customSubmit(text: []const u8) Intent {
        return .{ .custom_submit = text };
    }
};
