//! 已改写为 `.yix` 的设置面板（P3 3e）：面板与行的文案、test_id、焦点标识与搜索词。
//!
//! - 视图（`view/panes/<分类>.yix`）按自己的顺序摆行，只引用这里的条目（`F.ssh.keepalive_sec`），不写文案、不拼 id；
//! - view-model 用同一份数据做搜索过滤（规则同旧 `settings_controls.Section.matches` / `matchesField`）、
//!   “分类有没有命中”和“面板里最后一行”的判定，所以每个面板的 `rows` 必须与视图里的行同序、同集合；
//! - test_id 与旧面板逐字节相同（`settings.row.<key>`、`settings.field.<key>`、`settings.error.<key>`、
//!   `settings.help.<key>[.tooltip]`、`settings.help.content.<key>`、`<面板 id>[.header|.summary]`）。
//!
//! 后续面板包：在这里加一个分类的 `struct`（行 + 面板）并登记进 `pages`，再在视图的登记表
//! （`view/panes/registry.yix`）加一行。本文件不依赖 zenit `ui`。
const std = @import("std");
const format = @import("../../../shared/base/format.zig");
const intent = @import("intent.zig");
const ids = @import("ids.zig");
const focus_ids = @import("focus_ids.zig");
const catalog = @import("catalog.zig");
const config = catalog.config;
const keybinding_edit = @import("keybinding_edit.zig");

const Key = intent.Key;

/// 行的形态（只影响 view-model 的少数选择器；控件由视图决定）。
pub const Kind = enum { toggle, input, select, directory, info, action, permission, shortcut };

pub const Row = struct {
    kind: Kind,
    /// 草稿字段；只读 / 动作行为 null。
    key: ?Key = null,
    label: []const u8,
    /// 字段说明（标题旁的“?”提示，或 `inline_help` 时直接写在标签下）。
    help: []const u8 = "",
    /// 输入框的单位后缀（旧标签末尾的“（秒）”）。
    unit: ?[]const u8 = null,
    /// 说明直接写在标签下而不收进“?”（旧 `critical`：易误用的字段）。
    inline_help: bool = false,
    /// 搜索时与标签、说明一起匹配的两段文字（旧 `matchesField(label, key, help)` 的后两个参数）。
    term: []const u8 = "",
    match: []const u8 = "",
    /// 动作行：按钮文字、按钮 test_id 与命令。
    button: []const u8 = "",
    command: ?intent.Command = null,
    /// 危险操作（按钮墨色用 `danger`）。
    danger: bool = false,
    /// 快捷键行（`.shortcut`）的动作。
    shortcut: ?keybinding_edit.Action = null,
    /// 只读行的值（静态时）；为空时由 view-model 从宿主状态读。
    value: []const u8 = "",
    ids: Ids = .{},

    pub const Ids = struct {
        row: []const u8 = "",
        field: []const u8 = "",
        err: []const u8 = "",
        help: []const u8 = "",
        help_tip: []const u8 = "",
        help_text: []const u8 = "",
        focus: []const u8 = "",
        button_tip: []const u8 = "",
        /// 快捷键行：单行“恢复默认”、冲突的“交换” / “取消”、“未保存”标记（P3 3e 第二批新增，均在 `settings.key.` 前缀下）。
        reset: []const u8 = "",
        reset_tip: []const u8 = "",
        swap: []const u8 = "",
        cancel: []const u8 = "",
        mark: []const u8 = "",
        /// 外观页（P3 3e 外观包）：选择框下拉面板的 test_id（`settings.chooser.<key>`）、滑块的 test_id（`settings.slider.<key>`）。
        chooser: []const u8 = "",
        slider: []const u8 = "",
    };
};

const SettingOptions = struct { help: []const u8 = "", unit: ?[]const u8 = null, inline_help: bool = false };

fn setting(comptime kind: Kind, comptime section: []const u8, comptime key: []const u8, comptime label: []const u8, comptime options: SettingOptions) Row {
    const field_id = ids.field(key);
    return .{
        .kind = kind,
        .key = .{ .section = section, .key = key },
        .label = label,
        .help = options.help,
        .unit = options.unit,
        .inline_help = options.inline_help,
        .term = key,
        .match = options.help,
        .ids = .{
            .row = ids.settingRow(key),
            .field = field_id,
            .err = ids.fieldError(key),
            .help = "settings.help." ++ key,
            .help_tip = "settings.help." ++ key ++ ".tooltip",
            .help_text = "settings.help.content." ++ key,
            .focus = focus_ids.legacy_field_prefix ++ field_id,
        },
    };
}
fn toggle(comptime section: []const u8, comptime key: []const u8, comptime label: []const u8, comptime options: SettingOptions) Row {
    return setting(.toggle, section, key, label, options);
}
fn input(comptime section: []const u8, comptime key: []const u8, comptime label: []const u8, comptime options: SettingOptions) Row {
    return setting(.input, section, key, label, options);
}
fn select(comptime section: []const u8, comptime key: []const u8, comptime label: []const u8, comptime options: SettingOptions) Row {
    return setting(.select, section, key, label, options);
}
fn info(comptime label: []const u8, comptime value: []const u8) Row {
    return .{ .kind = .info, .label = label, .value = value, .ids = .{ .field = "settings.path." ++ label, .help_tip = "settings.path." ++ label ++ ".tooltip" } };
}
fn action(comptime label: []const u8, comptime button: []const u8, comptime id: []const u8, comptime command: intent.Command, comptime danger: bool) Row {
    return .{ .kind = .action, .label = label, .term = id, .match = button, .button = button, .command = command, .danger = danger, .ids = .{ .field = id, .button_tip = id ++ ".tooltip" } };
}

pub const Pane = struct {
    id: []const u8,
    header_id: []const u8,
    summary_id: []const u8,
    page: u8,
    title: []const u8,
    /// 页头右侧的说明（旧 section 的 description）；`summary` 给出时显示草稿摘要。
    meta: []const u8,
    summary: ?catalog.Summary = null,
    /// 面板出现在搜索结果里的匹配词（旧 `binding.matches(query, "…")`）。
    terms: []const u8,
    rows: []const Row,
};

fn pane(comptime id: []const u8, comptime page: u8, comptime title: []const u8, comptime meta: []const u8, comptime summary: ?catalog.Summary, comptime terms: []const u8, comptime rows: []const Row) Pane {
    return .{ .id = id, .header_id = id ++ ".header", .summary_id = id ++ ".summary", .page = page, .title = title, .meta = meta, .summary = summary, .terms = terms, .rows = rows };
}

// ── 通知（第 6 类） ──
pub const notify = struct {
    pub const transfer_done = toggle("notify", "transfer_done", "后台传输完成", .{ .help = "仅离开应用时提醒。" });
    pub const reconnect = toggle("notify", "reconnect", "持续连接故障", .{ .help = "断线后自动重连停止并影响工作时提醒。" });
    pub const ai_ready = toggle("notify", "ai_ready", "后台 AI 任务完成", .{ .help = "默认关闭；仅最终答复完成且离开应用时提醒。" });
    pub const bell = toggle("notify", "bell", "终端 Bell 声音", .{});
    /// 系统通知权限行（状态 + 说明 + 授权按钮），状态来自宿主（`HostStatus.authorization_help`）。
    pub const permission: Row = .{ .kind = .permission, .label = "系统通知权限", .ids = .{ .row = "settings.notifications.permission", .help = "settings.notifications.permission.info", .help_tip = "settings.notifications.permission.info.tooltip", .field = "settings.notifications.permission.open" } };
    pub const tab_dot = toggle("notify", "tab_dot", "非活跃标签圆点", .{});
    pub const quiet_hours = input("notify", "quiet_hours", "勿扰时段", .{ .help = "24 小时制，如 22:00-08:00；留空关闭勿扰，不影响后台任务。" });

    pub const events = pane("settings.notifications.events", 6, "事件提醒", "后台事件与终端声音", null, "事件提醒 通知 传输完成 断线 重连 AI 助手 回合 结束 终端 Bell 声音 transfer_done reconnect ai_ready bell", &.{ transfer_done, reconnect, ai_ready, bell, permission });
    pub const attention = pane("settings.notifications.attention", 6, "注意标记与勿扰", "标签圆点与勿扰时段", null, "注意标记 勿扰 非活跃 标签 圆点 时段 tab_dot quiet_hours", &.{ tab_dot, quiet_hours });
};

// ── SSH 与网络（第 2 类） ──
pub const ssh = struct {
    pub const keepalive_sec = input("ssh", "keepalive_sec", "KeepAlive 间隔", .{ .unit = "秒", .help = "用于新连接和重连。" });
    pub const connect_timeout_sec = input("ssh", "connect_timeout_sec", "连接超时", .{ .unit = "秒" });
    pub const term = select("ssh", "term", "默认终端类型", .{ .help = "内置类型已做兼容性验证。自定义仅声明 TERM 名称，需远端提供对应终端描述。用于新连接和重连。" });
    pub const compression = toggle("ssh", "compression", "SSH 压缩", .{});
    pub const auto_shell_integration = toggle("ssh", "auto_shell_integration", "自动会话初始化", .{ .help = "每次连接 SSH 时在原 shell 内初始化文本钩子，以获取命令状态，不上传文件。主机高级选项可单独覆盖；下次新建会话或重连生效。" });
    pub const auto_reconnect = toggle("ssh", "auto_reconnect", "自动重连", .{});
    pub const reconnect_max = input("ssh", "reconnect_max", "最大重连次数", .{ .unit = "次", .help = "0 表示不重试。" });
    pub const reconnect_backoff = input("ssh", "reconnect_backoff", "重连间隔", .{ .unit = "秒", .help = "5 个间隔，以逗号分隔；每项 0–255 秒。" });
    pub const buffer_input = toggle("ssh", "buffer_input", "重连期间缓存输入", .{ .help = "恢复后回放缓存输入，关闭可避免意外执行。", .inline_help = true });
    pub const socks_port = input("ssh", "socks_port", "默认本地端口", .{});
    pub const socks_bind = select("ssh", "socks_bind", "默认绑定地址", .{ .help = "0.0.0.0 允许局域网内其他设备访问。", .inline_help = true });
    pub const otp_modal = toggle("ssh", "otp_modal", "专用验证码表单", .{ .help = "为六位验证码显示专用输入框。" });
    pub const totp_autofill = toggle("ssh", "totp_autofill", "TOTP 自动填充", .{ .help = "填入已配置主机的验证码，提交前仍需确认。" });

    pub const connection = pane("settings.ssh.connection", 2, "连接", "连接保活、超时与终端类型", null, "连接 保活 KeepAlive 超时 终端 TERM 压缩 keepalive_sec connect_timeout_sec term compression 自动 会话 初始化 命令 状态 shell integration auto_shell_integration", &.{ keepalive_sec, connect_timeout_sec, term, compression, auto_shell_integration });
    pub const reconnect = pane("settings.ssh.reconnect", 2, "断线重连", "自动重连与输入缓存", null, "断线 自动重连 最大次数 退避 输入缓存 auto_reconnect reconnect_max reconnect_backoff buffer_input", &.{ auto_reconnect, reconnect_max, reconnect_backoff, buffer_input });
    pub const socks = pane("settings.ssh.socks", 2, "SOCKS5 默认值", "用于下次开启的转发", null, "SOCKS5 默认值 本地端口 绑定地址 socks_port socks_bind", &.{ socks_port, socks_bind });
    pub const authentication = pane("settings.ssh.authentication", 2, "双因素认证", "验证码输入与自动填充", null, "双因素 认证 验证码 OTP TOTP 自动填充 otp_modal totp_autofill", &.{ otp_modal, totp_autofill });
};

// ── 文件传输（第 3 类） ──
pub const transfer = struct {
    pub const dedicated_connection = toggle("transfer", "dedicated_connection", "独立传输连接", .{ .help = "使用独立连接传输文件，减少对终端的影响。" });
    pub const shared_pacing_kbps = input("transfer", "shared_pacing_kbps", "共享通道限速", .{ .unit = "KiB/s", .help = "0 表示不限速；用于新任务的共享通道。" });
    pub const window_chunks = input("transfer", "window_chunks", "窗口分块数", .{ .unit = "块" });
    /// 配置值按 KiB（1024 字节）计，与 `shared/base/format` 的 IEC 写法一致。
    pub const chunk_kb = input("transfer", "chunk_kb", "分块大小", .{ .unit = "KiB" });
    pub const max_tasks = input("transfer", "max_tasks", "最大并发任务", .{ .unit = "个" });
    pub const @"resume" = toggle("transfer", "resume", "断点续传", .{});
    pub const verify_md5 = toggle("transfer", "verify_md5", "MD5 完成校验", .{});
    pub const download_dir: Row = blk: {
        var row = setting(.directory, "transfer", "download_dir", "默认下载目录", .{});
        row.ids.row = "";
        row.ids.err = "";
        break :blk row;
    };
    pub const conflict_policy = select("transfer", "conflict_policy", "同名文件处理", .{ .help = "覆盖、跳过或保留两者由每次冲突确认决定。" });

    pub const connection = pane("settings.transfer.connection", 3, "连接隔离", "独立传输与共享通道限速", connectionSummary, "连接隔离 独立传输连接 共享通道限速 dedicated_connection shared_pacing_kbps", &.{ dedicated_connection, shared_pacing_kbps });
    pub const engine = pane("settings.transfer.engine", 3, "SFTP 引擎", "窗口、分块与并发", engineSummary, "SFTP 引擎 滑动窗口 块大小 断点续传 MD5 完成校验 最大并发任务 window_chunks chunk_kb resume verify_md5 max_tasks", &.{ window_chunks, chunk_kb, max_tasks, @"resume", verify_md5 });
    pub const defaults = pane("settings.transfer.defaults", 3, "默认行为", "下载目录与同名文件处理", null, "默认行为 默认下载目录 同名 重命名 冲突 每次询问 download_dir conflict_policy", &.{ download_dir, conflict_policy });

    fn connectionSummary(value: config.Config, buffer: []u8) anyerror![]const u8 {
        const connection_text = if (value.transfer.dedicated_connection) "独立传输连接" else "共享终端连接";
        if (value.transfer.shared_pacing_kbps == 0) return std.fmt.bufPrint(buffer, "{s} · 共享通道不限速", .{connection_text});
        // 配置值按 KiB/s 计（`transfer_pacer` 按 × 1024 字节每秒换算）；显示按 `shared/base/format`。
        var rate: format.Buffer = undefined;
        return std.fmt.bufPrint(buffer, "{s} · 共享通道 {s}", .{ connection_text, format.rate(&rate, @as(u64, value.transfer.shared_pacing_kbps) * 1024) });
    }
    fn engineSummary(value: config.Config, buffer: []u8) anyerror![]const u8 {
        var size: format.Buffer = undefined;
        return std.fmt.bufPrint(buffer, "{d} × {s} · {d} 并发", .{ value.transfer.window_chunks, format.bytes(&size, @as(u64, value.transfer.chunk_kb) * 1024), value.transfer.max_tasks });
    }
};

// ── 数据与日志（第 7 类） ──
pub const data = struct {
    /// 路径行：值来自宿主（`HostStatus.paths`），配置文件 / 主机配置读不到时整行不显示。
    pub const config_path = info("配置文件", "");
    pub const hosts_path = info("主机配置", "");
    pub const cache_dir = info("缓存目录", "");
    pub const logs_dir = info("诊断日志目录", "");
    pub const keychain = info("密码与 API Key", "存储于 macOS 钥匙串");
    pub const credential_help = action("凭据访问状态", "检查凭据状态", "settings.data.credential_help", .credential_help, false);
    pub const permissions = info("配置文件权限", "仅当前用户可读写 · 600");
    /// 配置值按 MiB（1024 × 1024 字节）计（同 `chunk_kb`）。
    pub const ring_mb = input("log", "ring_mb", "每会话缓冲上限", .{ .unit = "MiB" });
    pub const checkpoint_sec = input("log", "checkpoint_sec", "快照间隔", .{ .unit = "秒" });
    pub const retention_days = input("log", "retention_days", "保留天数", .{ .unit = "天" });
    pub const export_format = select("log", "export_format", "会话导出格式", .{});
    pub const export_logs = action("应用诊断日志", "导出日志…", "settings.data.export_logs", .export_logs, false);
    pub const clear_logs = action("已结束会话记录", "清理记录…", "settings.data.clear_logs", .clear_logs, true);
    pub const clear_all = action("全部应用数据", "清除全部数据…", "settings.data.clear_all", .clear_all, true);

    pub const location = pane("settings.data.location", 7, "位置与凭据", "本地存储 · macOS 钥匙串", null, "位置 凭据 本地 配置目录 缓存 诊断 钥匙串 600 config_dir cache_dir logs_dir", &.{ config_path, hosts_path, cache_dir, logs_dir, keychain, credential_help, permissions });
    pub const history = pane("settings.data.history", 7, "会话记录", "缓冲、快照与保留策略", null, "会话记录 日志 缓冲 上限 快照 间隔 保留 天数 导出格式 ring_mb checkpoint_sec retention_days export_format", &.{ ring_mb, checkpoint_sec, retention_days, export_format });
    pub const actions = pane("settings.data.actions", 7, "导出与清理", "导出诊断信息与清理应用数据", null, "导出 清理 清空 清除 全部 应用 数据 删除 会话 诊断 日志 export clear", &.{ export_logs, clear_logs, clear_all });
};

// ── 快捷键（第 1 类） ──
pub const keys = struct {
    /// 一个动作一行（`settings.key.row.<动作>`）；键帽区 `settings.key.<动作>`（提示 `settings.key.tooltip.<动作>`），
    /// 固定动作的锁 `settings.key.fixed.<动作>`（提示 `….tooltip`），无效 / 冲突说明 `settings.key.error.<动作>`，
    /// 单行恢复默认 `settings.key.reset.<动作>`，冲突的交换 / 取消 `settings.key.swap.<动作>` / `settings.key.cancel.<动作>`，
    /// “未保存”标记 `settings.key.unsaved.<动作>`。搜索：动作名、面板标题、动作标签名；当前组合由 view-model 另外匹配。
    pub fn row(comptime which: keybinding_edit.Action) Row {
        const tag = @tagName(which);
        return .{
            .kind = .shortcut,
            .label = keybinding_edit.label(which),
            .term = tag,
            .shortcut = which,
            .ids = .{
                .row = "settings.key.row." ++ tag,
                .field = "settings.key." ++ tag,
                .help_tip = "settings.key.tooltip." ++ tag,
                .help = "settings.key.fixed." ++ tag,
                .button_tip = "settings.key.fixed." ++ tag ++ ".tooltip",
                .err = "settings.key.error." ++ tag,
                .focus = "focus:key." ++ tag,
                .reset = "settings.key.reset." ++ tag,
                .reset_tip = "settings.key.reset." ++ tag ++ ".tooltip",
                .swap = "settings.key.swap." ++ tag,
                .cancel = "settings.key.cancel." ++ tag,
                .mark = "settings.key.unsaved." ++ tag,
            },
        };
    }
    fn rows(comptime actions: []const keybinding_edit.Action) []const Row {
        comptime {
            var list: [actions.len]Row = undefined;
            for (actions, 0..) |which, i| list[i] = row(which);
            const final = list;
            return &final;
        }
    }
    pub const tab_rows = rows(keybinding_edit.tab_actions);
    pub const terminal_rows = rows(keybinding_edit.terminal_actions);

    pub const tabs = pane("settings.keys.tabs", 1, "页签与分栏", "16 个动作", null, "页签 分栏 新建 关闭 序号 直达 上一个 下一个 最近使用 split tab", tab_rows);
    pub const terminal = pane("settings.keys.terminal", 1, "终端与应用", "11 个动作 · Control 与 Tab 保留给远端", null, "终端 应用 复制 粘贴 搜索 补全 采纳 快速连接 立即重连 侧栏 AI 上传 广播 terminal", terminal_rows);
};

// ── 关于与更新（第 8 类） ──
pub const updates = struct {
    const version_terms = "ZeroWork 关于 更新 版本 检查 update version";
    const preference_terms = "自动 检查 更新 偏好 通道 正式版 来源 GitHub release auto_check channel";
    pub const auto_check = toggle("updates", "auto_check", "自动检查更新", .{ .help = "启动后检查，自动检查按 24 小时限频", .inline_help = true });
    /// 只读行：值来自宿主（`HostStatus.update`）。旧面板不按行过滤这两行与“发布来源”（面板命中就显示），
    /// 所以它们的搜索词就是面板的匹配词。
    pub const channel: Row = .{ .kind = .info, .label = "更新通道", .term = preference_terms, .ids = .{ .field = "settings.updates.channel" } };
    pub const last_check: Row = .{ .kind = .info, .label = "上次检查", .term = preference_terms, .ids = .{ .field = "settings.updates.last_check" } };
    pub const source: Row = .{ .kind = .action, .label = "发布来源", .term = preference_terms, .button = "GitHub / version-next / ZeroWork", .match = "发布来源：GitHub / version-next / ZeroWork", .command = .open_update_release, .ids = .{ .field = "settings.updates.source" } };

    /// 版本卡（应用图标、名称、版本 / 构建信息、状态徽标、检查更新）：没有设置行。
    pub const version = pane("settings.updates.version", 8, "ZeroWork", "", null, version_terms, &.{});
    pub const preferences = pane("settings.updates.preferences", 8, "更新偏好", "", null, preference_terms, &.{ auto_check, channel, last_check, source });
};

// ── 外观与主题（第 0 类，P3 3e 外观包） ──
pub const appearance = struct {
    /// 旧面板的匹配词（`appearance_view.mountContent` 的 `binding.matches(query, "…")`）。除“字体与排版”外，旧面板不按行过滤：
    /// 面板命中就显示全部行，所以这些行的搜索词就是面板的匹配词（同 `updates` 的只读行）。
    const theme_terms = "外观 主题 theme 主题库";
    const icon_terms = "应用图标 透明背景 黑底 白底 Dock icon_background";
    const material_terms = "背景 图片 目录 轮播 顺序 随机 间隔 source order interval_minutes 材质 模糊 透明度 fit 对齐 blur_px background enabled path alignment_x alignment_y transparency";
    const preview_terms = "预览 终端预览 字体 字号 行高 光标 font cursor font_family font_size font_weight line_height cursor_style";
    const font_terms = "字体 字号 行高 光标 font cursor font_family font_size font_weight line_height cursor_style";
    const aids_terms = "终端 工作区 最大显示行数 回滚 scrollback_limit 时间戳 侧栏 高亮 补全 timestamp_gutter sidebar_collapsed input_line_highlight command_info 命令信息 AI 返回码 耗时 completion enabled 右键 右键行为 弹出菜单 直接粘贴 粘贴 terminal_right_click 浮动卡片 切换动画 动画 收向 标签 淡出 缩小 float_card_transition";

    const Options = struct {
        help: []const u8 = "",
        unit: ?[]const u8 = null,
        /// “?”的 id 后缀（旧 `settings.appearance.help.<标签>`；个别字段用 key）。
        help_id: ?[]const u8 = null,
        /// 控件的 test_id（默认 `settings.field.<key>`；开关是 `settings.toggle.<key>`）。
        field_id: ?[]const u8 = null,
        /// 行搜索词（默认 key）与第二段匹配文字（默认说明）。
        term: ?[]const u8 = null,
        match: ?[]const u8 = null,
    };
    fn look(comptime kind: Kind, comptime section: []const u8, comptime key: ?[]const u8, comptime label: []const u8, comptime options: Options) Row {
        const field_id = options.field_id orelse "settings.field." ++ key.?;
        const help_id = "settings.appearance.help." ++ (options.help_id orelse label);
        return .{
            .kind = kind,
            .key = if (key) |name| .{ .section = section, .key = name } else null,
            .label = label,
            .help = options.help,
            .unit = options.unit,
            .term = options.term orelse (key orelse ""),
            .match = options.match orelse options.help,
            .ids = .{
                .field = field_id,
                .err = if (key) |name| "settings.error." ++ name else "",
                .help = if (options.help.len != 0) help_id else "",
                .help_tip = if (options.help.len != 0) help_id ++ ".tooltip" else "",
                .focus = if (kind == .input) focus_ids.legacy_field_prefix ++ field_id else "",
                .chooser = if (key) |name| "settings.chooser." ++ name else "settings.chooser.alignment",
                .slider = if (key) |name| "settings.slider." ++ name else "",
            },
        };
    }

    // 主题 / 应用图标
    pub const icon_background = look(.select, "ui", "icon_background", "图标背景", .{ .help = "保存后更新 Dock 图标，启动和退出后均使用此选择。", .help_id = "icon_background", .term = icon_terms });
    // 背景图片
    pub const background_enabled = look(.toggle, "ui.materials.background", "enabled", "开启背景图片", .{ .field_id = "settings.toggle.enabled", .term = material_terms });
    pub const order = look(.select, "ui.materials.background", "order", "轮播方式", .{ .help = "顺序按文件名排列；随机一轮内不重复。", .term = material_terms });
    pub const interval_minutes = look(.select, "ui.materials.background", "interval_minutes", "切换间隔", .{ .term = material_terms });
    pub const fit = look(.select, "ui.materials.background", "fit", "图片适配", .{ .term = material_terms });
    pub const alignment = look(.select, "ui.materials.background", null, "图片对齐", .{ .field_id = "settings.field.alignment", .term = material_terms });
    pub const transparency = look(.input, "ui.materials.background", "transparency", "全局透明度", .{ .unit = "%", .help = "数值越大，界面越透明，背景图片越明显；0% 隐藏图片，100% 完整显示图片。", .help_id = "transparency", .term = material_terms });
    pub const blur_px = look(.input, "ui.materials", "blur_px", "背景与浮层模糊", .{ .unit = "px", .term = material_terms });
    // 字体与排版（旧 `matchesFontField`：按 key / 标签 / 说明逐行匹配）
    pub const font_family = look(.input, "ui", "font_family", "字体族", .{ .help = "方盒图标：内置字体；显示器图标：系统已安装；警告图标：已保存但未安装。缺失字体使用替代字体。", .match = "未安装的字体使用系统替代字体。" });
    /// 自定义字体输入框的说明（同一行、同一个“?”，换成输入框时文字不同）。
    pub const font_family_custom_help = "未安装所选字体时将使用替代字体；缺失字符由系统补足。";
    pub const font_size = look(.input, "ui", "font_size", "字体大小", .{ .unit = "pt" });
    pub const font_weight = look(.input, "ui", "font_weight", "基准字重", .{ .help = "仅显示当前字体支持的字重；切换字体时保留可用字重，否则自动使用常规字重或首个可用字重。" });
    pub const line_height = look(.input, "ui", "line_height", "行高倍率", .{});
    pub const cursor_style = look(.select, "ui", "cursor_style", "光标形状", .{ .help = "选择形状，在终端预览中查看。", .help_id = "cursor_style", .term = font_terms });
    // 终端与工作区
    pub const timestamp_gutter = look(.toggle, "ui", "timestamp_gutter", "时间戳侧栏", .{ .field_id = "settings.toggle.timestamp_gutter", .help = "显示输出时间，不包含在复制的终端内容中。", .term = aids_terms });
    pub const command_info = look(.toggle, "ui", "command_info", "命令信息", .{ .field_id = "settings.toggle.command_info", .help = "在命令首行右缘显示 AI、返回码和运行时间；鼠标悬停在命令上时隐藏，不会包含在复制的内容中。仅本地终端和 SSH，主机高级选项可覆盖。", .term = aids_terms });
    pub const completion = look(.toggle, "completion", "enabled", "应用命令补全", .{ .field_id = "settings.toggle.enabled", .term = aids_terms });
    pub const input_line_highlight = look(.toggle, "ui", "input_line_highlight", "输入行相对高亮", .{ .field_id = "settings.toggle.input_line_highlight", .term = aids_terms });
    pub const sidebar_collapsed = look(.toggle, "ui", "sidebar_collapsed", "默认隐藏侧栏", .{ .field_id = "settings.toggle.sidebar_collapsed", .help = "保存侧栏显示偏好；" ++ keybinding_edit.factoryHint(.sidebar) ++ " 随时显示或隐藏。", .term = aids_terms });
    pub const terminal_right_click = look(.select, "ui", "terminal_right_click", "右键行为", .{ .help = "弹出菜单：右键在指针处打开粘贴、查找、复制、清屏等操作，误触不会把剪贴板送进远端 shell。直接粘贴：右键立即粘贴剪贴板（PuTTY 习惯）。中键始终打开完整终端菜单。", .help_id = "terminal_right_click", .term = aids_terms });
    pub const float_card_transition = look(.select, "ui", "float_card_transition", "浮动卡片切换动画", .{ .help = "切换顶部标签时，不属于当前标签的浮动卡片（AI、会话记录）怎样收起和展开：收向所属标签，或原地淡出并轻微缩小。系统开启“减少动态效果”时一律改为淡入淡出。", .help_id = "float_card_transition", .term = aids_terms });
    pub const scrollback_limit = look(.input, "ui", "scrollback_limit", "终端最大显示行数", .{ .help = "默认 25000 行；0 表示不限制。同步应用到已打开的本地终端和继承全局配置的 SSH 终端。", .term = aids_terms });

    /// 主题（主题条、当前主题、ANSI 色板）：没有设置行；页头说明是当前主题名（来自主题库，视图自己的页头）。
    pub const themes = pane("settings.appearance.themes", 0, "主题", "", null, theme_terms, &.{});
    pub const app_icon = pane("settings.appearance.app_icon", 0, "应用图标", "Dock 图标底色 · 保存后生效", null, icon_terms, &.{icon_background});
    /// 背景图片：页头右侧是摘要 + 开启开关（视图自己的页头）；正文的开关以外各行。
    pub const materials = pane("settings.appearance.materials", 0, "背景图片", "", materialSummary, material_terms, &.{ order, interval_minutes, fit, alignment, transparency, blur_px });
    /// 预览：实时终端预览（摘要由视图按字体校验结果写）。
    pub const preview = pane("settings.appearance.preview", 0, "预览", "", null, preview_terms, &.{});
    pub const font = pane("settings.appearance.font", 0, "字体与排版", "终端字体、行距与光标", fontSummary, font_terms, &.{ font_family, font_size, font_weight, line_height, cursor_style });
    pub const aids = pane("settings.appearance.aids", 0, "终端与工作区", "辅助显示、回滚缓冲与侧栏", null, aids_terms, &.{ timestamp_gutter, command_info, completion, input_line_highlight, sidebar_collapsed, terminal_right_click, float_card_transition, scrollback_limit });

    fn materialSummary(value: config.Config, buffer: []u8) anyerror![]const u8 {
        const background = value.ui.materials.background;
        return std.fmt.bufPrint(buffer, "{s} · {s}", .{ if (background.enabled) @as([]const u8, "已开启") else "已关闭", if (background.path.len == 0) @as([]const u8, "未选择图片") else background.path });
    }
    fn fontSummary(value: config.Config, buffer: []u8) anyerror![]const u8 {
        return std.fmt.bufPrint(buffer, "{s} · {d} pt", .{ value.ui.font_family, value.ui.font_size });
    }
};

// ── AI 辅助（第 4 类，F-set-ai） ──
/// 服务提供方（列表 → 详情两级）与技能与 MCP 的正文不是设置行（`view/panes/ai_providers.yix` / `ai_extensions.yix`），
/// 这里只登记面板（搜索词、显示规则）；行为与权限是普通设置行。文案与搜索词同旧 `panes/settings_ai.zig`。
pub const ai = struct {
    pub const permission_mode = select("ai", "permission_mode", "默认权限模式", .{ .help = "确认后执行：部分读取自动进行，其余按策略判断。自动执行：授权范围内可自动运行命令和工具，包括组内写操作；禁止项不可执行。", .inline_help = true });
    pub const execution_mode = select("ai", "execution_mode", "默认运行方式", .{ .help = "自行判断、每次询问、批处理、附加现有 PTY 或新建 PTY。仅影响下一次执行，权限独立，当前执行保持原选择。" });
    pub const session_retention = select("ai", "session_retention", "任务会话处理", .{ .help = "空闲后关闭、每次询问或保留任务会话。只作用于随后由 AI 创建的资源；已有终端和已创建资源保留原策略。" });
    pub const follow_up_mode = select("ai", "follow_up_mode", "跟进行为", .{ .help = "引导：补充到当前任务。排队：当前任务完成后依次处理。仅影响新发送的消息；" ++ keybinding_edit.followUpHint() ++ " 使用另一种行为。" });
    pub const child_context_mode = select("ai", "child_context_mode", "默认上下文", .{ .help = "独立上下文从任务材料开始；继承上下文复制创建时已消费的合法历史。显式创建参数优先。" });
    pub const child_reuse_policy = select("ai", "child_reuse_policy", "默认复用策略", .{ .help = "每次新建默认不可自动复用；优先复用会提示模型先列出并选择明确候选；模型决定默认保守，仍需显式设置可复用。宿主不会按名称悄悄替换。" });
    pub const redact_ip = toggle("ai", "redact_ip", "隐藏连接身份", .{ .help = "隐藏 SSH 连接的 IP、主机名和用户名。终端正文与附件仍按原文发送，请检查敏感内容。", .inline_help = true });
    pub const image_limit = info("图片上限", "最多 4 张 · 单张 " ++ format.comptimeBytes(@import("../../../ai/image_attachments.zig").max_bytes));
    pub const text_limit = info("本地文本上限", "UTF-8 · " ++ format.comptimeBytes(@import("../../../ai/local_text_attachments.zig").max_bytes));
    pub const default_provider = select("ai", "default_provider", "默认服务提供方", .{ .help = "新对话默认使用的模型服务。" });
    pub const step_display = select("ai", "step_display", "步骤默认显示", .{ .help = "只决定新步骤组的初始状态；已有组和手动收展状态保持不变。" });
    pub const error_hint = toggle("ai", "error_hint", "错误轻提示", .{ .help = "命令失败时显示助手入口。" });

    pub const providers = pane("settings.ai.providers", 4, "服务提供方", "模型服务与 API Key", null, "Provider 模型 API Key 地址 endpoint anthropic OpenAI 兼容 Ollama", &.{});
    pub const permissions = pane("settings.ai.permissions", 4, "权限", "执行前的默认确认方式", null, "权限 确认 执行 自动执行 permission_mode", &.{permission_mode});
    pub const execution = pane("settings.ai.execution", 4, "运行方式", "全局默认；对话可以单独调整", null, "运行方式 执行 批处理 交互 附加现有 PTY 新建 PTY 自行判断 每次询问 execution_mode 保留 任务结束 空闲后关闭 保留任务会话 session_retention", &.{ execution_mode, session_retention });
    pub const conversation = pane("settings.ai.conversation", 4, "对话", "AI 工作时如何处理新消息", null, "对话 跟进行为 排队 引导 follow_up_mode queue steer", &.{follow_up_mode});
    pub const children = pane("settings.ai.children", 4, "子 Agent", "只用于之后创建的子配置；已有子配置保持原选择", null, "子 Agent 默认上下文 独立 继承 复用策略 每次新建 优先复用 模型决定 child_context_mode child_reuse_policy", &.{ child_context_mode, child_reuse_policy });
    pub const context = pane("settings.ai.context", 4, "上下文", "连接身份与敏感信息", null, "上下文 来源 脱敏 隐私 IP 主机 用户 redact_ip", &.{redact_ip});
    pub const attachments = pane("settings.ai.attachments", 4, "附件", "图片和本地文本的大小限制", null, "附件 图片 本地 文本 文件 引用 attachment", &.{ image_limit, text_limit });
    pub const behavior = pane("settings.ai.behavior", 4, "其他行为", "默认服务提供方与错误提示", null, "其他行为 默认 Provider 错误 提示 error_hint default_provider 步骤默认显示 步骤 聚合 折叠 展开 step_display", &.{ default_provider, step_display, error_hint });
    pub const extensions = pane("settings.ai.extensions", 4, "技能与 MCP", "本地技能与 MCP 服务", null, "本地技能 技能 SKILL MCP 服务 工具 导入 stdio HTTP 环境变量 请求头", &.{});
};

/// 每个分类已改写的面板（`settings_pages.pages` 同序）；空表 = 该分类仍是旧实现。
pub const pages = [catalog.categories.len][]const *const Pane{
    &.{ &appearance.themes, &appearance.app_icon, &appearance.materials, &appearance.preview, &appearance.font, &appearance.aids },
    &.{ &keys.tabs, &keys.terminal },
    &.{ &ssh.connection, &ssh.reconnect, &ssh.socks, &ssh.authentication },
    &.{ &transfer.connection, &transfer.engine, &transfer.defaults },
    &.{ &ai.providers, &ai.permissions, &ai.execution, &ai.conversation, &ai.children, &ai.context, &ai.attachments, &ai.behavior, &ai.extensions },
    &.{},
    &.{ &notify.events, &notify.attention },
    &.{ &data.location, &data.history, &data.actions },
    &.{ &updates.version, &updates.preferences },
};

/// 查一个已改写的面板（按 test_id）。
pub fn findPane(id: []const u8) ?*const Pane {
    for (pages) |list| for (list) |item| if (std.mem.eql(u8, item.id, id)) return item;
    return null;
}
/// 查一个已改写面板里的输入框行（按输入框的 test_id `settings.field.<key>`；整窗 Escape 用它认出正在编辑的输入框）。
/// The input row whose control carries `focus_id` (`Row.ids.focus`, the `focusId` on its `W.Input`).
pub fn findInputByFocus(focus_id: []const u8) ?Row {
    if (focus_id.len == 0) return null;
    for (pages) |list| for (list) |item| for (item.rows) |row| {
        if (row.kind == .input and std.mem.eql(u8, row.ids.focus, focus_id)) return row;
    };
    return null;
}

// ── 搜索（规则同旧 `settings_content_view.mountCategory` / `settings_controls.Section`） ──

/// 某分类在搜索词下实际用来过滤的词：搜索词命中分类名时整类不过滤（旧 `mountCategory` 把搜索词清空）。
pub fn effectiveQuery(query: []const u8, page: usize) []const u8 {
    if (query.len != 0 and catalog.search.matches(query, catalog.pages.pages[page].name)) return "";
    return query;
}
pub fn paneMatches(query: []const u8, item: *const Pane) bool {
    return catalog.search.matches(effectiveQuery(query, item.page), item.terms);
}
pub fn rowMatches(query: []const u8, item: *const Pane, row: Row) bool {
    const q = effectiveQuery(query, item.page);
    const matches = catalog.search.matches;
    return matches(q, item.title) or matches(q, item.meta) or matches(q, row.label) or matches(q, row.term) or matches(q, row.match);
}
/// 分类里是否有面板出现在结果里（没有时该分类整块不显示）。
pub fn pageMatches(query: []const u8, page: usize) bool {
    for (pages[page]) |item| if (paneMatches(query, item)) return true;
    return false;
}

test "pane field table keeps the frozen test ids" {
    try std.testing.expectEqualStrings("settings.field.keepalive_sec", ssh.keepalive_sec.ids.field);
    try std.testing.expectEqualStrings("settings.help.content.buffer_input", ssh.buffer_input.ids.help_text);
    try std.testing.expectEqualStrings("settings.path.缓存目录.tooltip", data.cache_dir.ids.help_tip);
    try std.testing.expectEqualStrings("focus:field:settings.field.quiet_hours", notify.quiet_hours.ids.focus);
    for (pages) |list| for (list) |item| {
        try std.testing.expect(ids.isStatic(item.id));
        for (item.rows) |row| if (row.key) |key| try std.testing.expect(catalog.schema.find(key.section, key.key) != null);
    };
}
