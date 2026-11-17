//! 设置窗口的副作用出口（ARCHITECTURE_PLAN §4.4、§4.5）。
//!
//! `dispatch` 同步更新 Controller 草稿与投影信号；需要 I/O、原生面板、窗口、worker、纹理或通知中心时，
//! 发出 `Effect` 交给宿主（`SettingsHost` 实现 `Ports`）。宿主做完后在主线程以 Intent 回流
//! （`.save_finished`）。model 不 import host、不做 I/O。本文件不依赖 zenit `ui`。
const ai_draft = @import("settings_ai_draft.zig");
const intent = @import("intent.zig");
const save_flow = @import("save_flow.zig");
const themes = @import("../../../config/theme_registry.zig");
const background = @import("../../../config/background_asset.zig");
const ai_pane = @import("ai_pane.zig");
const data_cleanup = @import("data_cleanup.zig");

/// dispatch 改草稿前向宿主确认的关口：宿主持有 worker、MCP 编辑器、输入法组合等状态。
/// 返回 false 表示拒绝（是否提示由宿主决定）。
pub const Gate = enum {
    /// 切换分类 / 子页面 / 历史：外观 worker 或保存进行中、MCP 编辑未完成时拒绝。
    navigate,
    /// 改搜索词：MCP 操作进行中或编辑器打开时静默拒绝。
    search,
    /// 保存：另加输入法组合中、模型编辑器打开时拒绝。
    save,
    /// 载入默认值草稿：外观 worker 或保存进行中时拒绝。
    reset,
    /// 整窗快捷键（Escape / ⌘W / ⌘,）：正在录制快捷键、确认弹窗打开时不接（按键照常交给它们）。
    window_keys,
};

pub const Effect = union(enum) {
    // ── 旧视图的重建（Yix 化之后由信号驱动，届时删除） ──
    /// 离开当前挂载页前记住它的滚动位置。
    leave_page,
    /// 位置变了：下一帧重建导航与内容，隐藏状态行。
    navigated,
    /// 草稿或搜索结果变了：下一帧重建内容。
    rebuild,
    // ── 反馈 ──
    /// 操作失败：状态行 / 应用内通知报告错误名。
    failed: anyerror,
    /// 草稿已无校验问题：撤回“偏好设置”的操作错误通知。
    resolve_problems,
    /// 保存被校验问题拦下：发布“无法保存设置”通知。
    report_problem,
    /// 跳到校验问题前：收起确认弹窗与选择器，并记住要展开的 AI 草稿位置。
    focus_problem: ?ai_draft.Address,
    /// 事件提醒开关从关变开：向系统申请通知授权。
    request_notification_authorization,
    // ── 草稿生命周期 ──
    /// 执行保存流水线（字体校验、主题安装、背景纹理、提交配置）；完成后回流 `.save_finished`。
    save: struct { close_after: bool },
    /// 放弃草稿回到最新已存配置，并清理外观草稿资源。
    revert,
    /// 确认对话框变了（H-save：view-model 持有，窗口按 `ViewModel.prompt` 信号显示原生 `W.Modal`；宿主不画）。
    prompt: save_flow.Prompt,
    /// 用户在确认对话框里选了“继续编辑 / 取消”（宿主据此撤回挂起的原生关窗请求）。
    dismiss_decision,
    /// 保存已提交（H-save）。设置窗口里的 Toast 由 view-model 的 `toast` 信号驱动窗口模板的 `W.NotificationHost`（S-19），
    /// 宿主不再弹；“保存关闭”不弹（窗口随即关闭）。
    saved,
    /// 保存失败（H-save）：草稿保留，Save Bar 显示“保存失败”；错误 Toast 同样由 view-model 的 `toast` 信号发出（S-19）。
    save_failed: anyerror,
    /// 放弃草稿并关闭窗口（含中止主题安装）。
    discard_and_close,
    /// 关闭设置窗口。
    close_window,
    /// 整窗 Escape：宿主按层收起（材质预览 → 正文提示 / 弹层 / 原地编辑 → 提供方编辑 → 选择器），都没有时按关闭处理。
    escape,
    /// ⌘W / ⌘,：按关闭处理（草稿未保存时弹确认，保存中不关）。
    request_close,
    // ── 其余按钮 ──
    import_theme,
    export_logs,
    clear_logs,
    /// 打开“清除全部数据”确认：宿主做打开前的检查（另一窗口正在清除时拒绝）、记下回焦位置，
    /// 再以 `Intent.cleanup(.show)` 回流当时的阻塞原因（S-12）。
    clear_all,
    /// “清除全部数据”对话框里的选择（S-12）：`.confirm` / `.retry` 宿主复查后接手清除（回流 `.working` 或 `.blocked`），
    /// `.dismiss` 宿主恢复滚动与焦点（清除已开始时退出应用）。
    data_cleanup: data_cleanup.Action,
    open_config_dir,
    explain_credentials,
    check_updates,
    open_update_release,
    /// “立即重启”（Q5，NHr2L / DzPbO）：走正常的退出流程（与 ⌘Q 相同的关闭确认，不强制结束任何进程），
    /// 退出完成后再启动同一个应用；用户在关闭确认里取消时什么都不发生。
    restart_app,
    /// 打开系统通知设置（或首次申请授权）。
    open_notification_permission,
    /// 目录字段（下载目录）要系统目录面板（S-13）：宿主弹面板，选中后写草稿并重新投影。
    /// “自定义 TERM 声明…”的原地编辑归 view-model（`ViewModel.custom*`）+ `.yix` 的原生 `W.Popover`，不经宿主。
    pick_directory: intent.Key,
    /// 外观与主题（P3 3e 外观包）：宿主持有的外观资源（主题库、背景 worker、字体校验、材质预览）。
    appearance: AppearanceEffect,
    /// “AI 辅助”面板要宿主做的事（F-set-ai）：获取模型清单、测试模型、技能导入 / 查看、MCP 测试 / 网页登录 / 退出授权。
    /// 结果经 `HostStatus.ai` 回来（宿主每帧比较、变了才 `sync`）。
    ai: ai_pane.Job,
};

/// 外观面板要宿主做的事（旧 `appearance_ui_context.Command` 的 `.yix` 等价物）。字符串只在回调期间有效。
pub const AppearanceEffect = union(enum) {
    /// 草稿里的外观字段变了：宿主重新校验字体、按需准备背景、刷新材质预览（旧 `draft_values_changed`）。
    changed,
    /// 输入框提交（Enter）：只重新校验字体（旧 `validate_font`）。
    validate_font,
    /// 选择背景图片 / 目录（系统面板）。
    pick_background,
    /// 删除导入的主题。
    remove_theme: []const u8,
    /// 进入 / 离开全窗口材质预览。
    preview_material: bool,
    /// 恢复已保存的背景（材质预览条）。
    restore_materials,
};

/// 宿主持有、视图要显示的状态（P3 3d 新增，只读）：Save Bar 的可用性与状态文字依赖它们。
/// 由宿主在 `sync` 前更新；视图只经 view-model 的选择器读取。
pub const HostStatus = struct {
    /// 外观 worker 正在准备主题 / 背景（保存与撤销不可用）。
    appearance_busy: bool = false,
    /// 字体校验有问题（保存不可用）。
    font_problem: bool = false,
    /// 通知授权的反馈文字（通知页、草稿干净或有效时替代 Save Bar 状态文字）；宿主持有。
    authorization_feedback: ?[]const u8 = null,
    /// 宿主状态行的最后一条文字（编辑失败、刷新前缀）；宿主持有，换文字时换地址。
    status_line: []const u8 = "",
    /// 状态行是否显示：宿主现有写入点全部隐藏它，所以恒为 false（保留字段，显示策略归宿主）。
    status_line_shown: bool = false,
    /// 通知授权的说明全文（通知页“系统通知权限”行；null 时为“当前无法使用系统通知。”）。
    authorization_help: ?[]const u8 = null,
    /// 数据页“已结束会话记录 / 全部应用数据”按钮的可用性与原因。
    clear_logs: ActionState = .{},
    clear_all: ActionState = .{},
    /// 数据页的路径：配置文件、主机配置、缓存目录、诊断日志目录（读不到为 null）。宿主持有。
    data_paths: [4]?[]const u8 = @splat(null),
    /// 关于与更新页（P3 3e 第二批）：更新器的状态投影；宿主每帧比较指纹，变了才 `sync`。
    update: UpdateStatus = .{},
    /// “AI 辅助”面板（F-set-ai）：模型清单、模型测试、扩展任务的状态与结果。
    ai: ai_pane.HostAi = .{},
};

/// 外观页要显示的宿主状态（P3 3e 外观包；旧 `appearance_ui_context.Context` 的只读部分）。经 `Ports.appearance` 单独读取，
/// 不并进 `HostStatus`（主题卡片等选择器读得频繁，不必每次都算数据页路径与更新器状态）。指针与文字由宿主持有。
pub const AppearanceStatus = struct {
    /// 宿主已初始化外观资源（主题库、worker）；未初始化时主题条为空、相关按钮不可用。
    ready: bool = false,
    /// 外观 worker / 保存进行中（面板控件不可用，同旧 `disabled`）。
    busy: bool = false,
    registry: ?*const themes.Registry = null,
    /// 已保存（运行中）的主题 id 与背景（“使用中”判定、轮播显示当前图片）。
    saved_theme: []const u8 = "",
    saved_background: ?background.Background = null,
    /// 字体校验结果（预览字体、回退提示、问题）。
    font_family_id: u16 = 0,
    font_actual: []const u8 = "",
    font_fallback: bool = false,
    font_problem: ?[]const u8 = null,
    /// 预览字体的单元格宽度（光标宽度；0 = 按字号估算）。
    font_cell_width: f32 = 0,
    /// 背景选择框最近选中的路径（worker 准备中先显示它）与运行中轮播的当前图片。
    selected_image_path: []const u8 = "",
    runtime_image_path: []const u8 = "",
    /// 全窗口材质预览打开着。
    preview_active: bool = false,
    /// 背景缩略图的纹理（宿主已上传；null = 没有可显示的图片）。
    thumbnail: ?Texture = null,
};
pub const Texture = struct { id: u32, width: u32, height: u32 };

/// 更新器状态（旧 `Hooks.read(.{ .section = "updates" })` 的各个键）。文字由宿主持有（静态缓冲或 C 字符串），
/// view-model 读出后复制进自己的双缓冲再交给视图。
pub const UpdateStatus = struct {
    /// `idle` / `checking` / `available` / `downloading` / `verifying` / `ready` / `preparing` / `installing` /
    /// `failed` / `draining`（取消后仍在收尾）。空串同 `idle`。
    state: []const u8 = "",
    /// 当前版本（`zw_update_current_version`）；空串显示“—”。
    current_version: []const u8 = "",
    /// 构建信息（`version_metadata`，含 `main@<commit>` 与时间）。
    metadata: []const u8 = "",
    /// 状态徽标文字（“待检查”“正在检查”“有新版本”“无需更新”…）。
    badge: []const u8 = "",
    /// 版本卡里的状态标题（“检查是否有可用的新版本”“1.2.3 正式版可用”…）。
    title: []const u8 = "",
    /// 可用的新版本号（有更新时非空）。
    available_version: []const u8 = "",
    /// 上次检查（“尚未检查”）。
    last_check: []const u8 = "",
    /// 更新通道（“正式版”）。
    channel: []const u8 = "",
};

/// 宿主侧动作的可用性（与旧 `settings_content_view.ActionState` 同形）。
pub const ActionState = struct { enabled: bool = true, reason: ?[]const u8 = null };

/// 宿主实现：函数指针表 + `*anyopaque`（与旧视图 `Hooks` 同一写法）。
pub const Ports = struct {
    context: *anyopaque,
    run: *const fn (*anyopaque, Effect) void,
    allow: *const fn (*anyopaque, Gate) bool,
    /// 可选（P3 3d）：宿主状态；未提供时视为全默认。
    status: ?*const fn (*anyopaque) HostStatus = null,
    /// 可选（P3 3e 外观包）：外观页的宿主状态；未提供时视为全默认（外观资源未初始化）。
    appearance: ?*const fn (*anyopaque) AppearanceStatus = null,

    pub fn emit(self: Ports, effect: Effect) void {
        self.run(self.context, effect);
    }
    pub fn permits(self: Ports, gate: Gate) bool {
        return self.allow(self.context, gate);
    }
    pub fn hostStatus(self: Ports) HostStatus {
        const read = self.status orelse return .{};
        return read(self.context);
    }
    pub fn appearanceStatus(self: Ports) AppearanceStatus {
        const read = self.appearance orelse return .{};
        return read(self.context);
    }
};
