//! 错误码 / 错误名 → 用户文案的唯一目录（docs/ui-revamp/CONSISTENCY_AUDIT.md #7，copy-terms）。
//!
//! - 每条文案分三部分：标题（一句话说明发生了什么）· 说明（为什么，可空）· 建议（下一步怎么做，可空）。
//!   `line` 是单行展示用的完整句子（标题，必要时接上建议与“详情见应用日志”），在编译期拼好。
//! - 进度页、日志页、通知、插件提示等凡是要把错误给用户看的地方，都从这里取；不再各自复制一份映射表。
//! - 原始错误名（`@errorName`）不直接拼进用户可见文字，只放在可展开的“详情”或日志里。
//!   目录里没有的错误，调用方用 `lineOr` 给出本领域的通用说法，并把原始错误名写进日志或详情。
//! - 术语按 docs/ui-revamp/GLOSSARY.md：统一用“认证”，不用“鉴权”。
const std = @import("std");
/// 字节上限的写法统一走 `format.comptimeBytes`（1024 进制 IEC：KiB / MiB；units-iec）。
const bytes = @import("format.zig").comptimeBytes;

pub const Text = struct {
    title: []const u8,
    detail: []const u8 = "",
    hint: []const u8 = "",
    /// 单行完整句子：标题，可能接“，建议”和“（详情见应用日志）”。
    line: []const u8,
    /// 这类错误另有诊断写进应用日志；`line` 以“（详情见应用日志）”结尾。
    in_log: bool = false,
};

/// 日志里另有详情时，单行文案的固定结尾（进度页有诊断可展开时会去掉它）。
pub const log_suffix = "（详情见应用日志）";

const Options = struct {
    detail: []const u8 = "",
    hint: []const u8 = "",
    /// 建议是否写进单行句子（“标题，建议”）。
    inline_hint: bool = false,
    in_log: bool = false,
};

fn text(comptime title: []const u8, comptime options: Options) Text {
    const with_hint = if (options.inline_hint and options.hint.len != 0) title ++ "，" ++ options.hint else title;
    return .{
        .title = title,
        .detail = options.detail,
        .hint = options.hint,
        .line = if (options.in_log) with_hint ++ log_suffix else with_hint,
        .in_log = options.in_log,
    };
}

// ── SSH 连接与认证 ─────────────────────────────────────────────────
const authentication_rejected = text("服务器未接受认证信息", .{ .detail = "服务器拒绝了本次提供的密码、私钥或 Agent 身份。", .hint = "请核对用户名与认证方式后重试" });
const identity_unreadable = text("无法读取私钥文件", .{ .detail = "私钥路径不存在，或当前用户没有读取权限。", .hint = "请检查路径与权限", .inline_hint = true });
const identity_invalid = text("私钥文件格式无效、已损坏或当前不支持", .{ .hint = "请换用 OpenSSH 格式的私钥，或重新导出私钥" });
const timed_out = text("连接超时", .{ .detail = "在设定的超时时间内没有收到对端回应。", .hint = "请检查网络、VPN 与防火墙，或适当延长连接超时" });
const connect_failed = text("无法建立 TCP 连接", .{ .detail = "目标地址不可达，或网络中途被阻断。", .hint = "请检查地址、端口与网络", .inline_hint = true });
const refused = text("连接被拒绝", .{ .detail = "目标端口没有服务在监听，或被防火墙拒绝。", .hint = "请确认端口号与服务端 SSH 服务状态" });
const host_key_changed = text("服务器主机密钥已变化", .{ .detail = "服务器给出的主机密钥与已信任的记录不一致。", .hint = "请通过可信渠道核对指纹后再决定是否信任新密钥" });
const host_key_unconfirmed = text("主机身份尚未确认", .{ .hint = "请核对服务器指纹后再继续" });
const host_key_revoked = text("服务器主机密钥已被撤销", .{ .hint = "请联系服务器管理员确认主机身份" });
const cancelled = text("已取消", .{});
const sftp_denied = text("服务器拒绝 SFTP 子系统", .{ .hint = "请确认服务端已启用 sftp-server 或 internal-sftp" });

// SSH 握手（libssh2 错误码，见 proto/ssh/handshake_failure.zig `fromCode`）：诊断另写进应用日志。
const handshake_receive = text("SSH 握手接收失败", .{ .hint = "请检查网络或服务端日志", .inline_hint = true, .in_log = true });
const handshake_send = text("SSH 握手发送失败", .{ .hint = "请检查网络或服务端日志", .inline_hint = true, .in_log = true });
const handshake_disconnected = text("SSH 握手期间连接已断开", .{ .in_log = true });
const handshake_banner = text("未能读取 SSH 服务标识", .{ .hint = "请检查目标端口", .inline_hint = true, .in_log = true });
const handshake_negotiation = text("SSH 密钥交换或算法协商失败", .{ .in_log = true });
const handshake_timeout = text("SSH 握手超时", .{ .hint = "请检查网络与服务端状态", .inline_hint = true, .in_log = true });
const handshake_failed = text("SSH 握手失败，尚未进行登录认证", .{ .in_log = true });

// ── 系统与文件 ─────────────────────────────────────────────────────
const access_denied = text("没有访问权限", .{ .detail = "系统拒绝了本次读写或网络访问。", .hint = "请检查文件、目录或网络权限" });
const file_not_found = text("文件不存在", .{ .detail = "目标文件可能已被移动或删除。", .hint = "请确认路径后重试" });
const no_space = text("磁盘空间不足", .{ .hint = "请清理磁盘空间后重试" });
const out_of_memory = text("内存不足", .{ .hint = "请关闭不需要的会话或窗口后重试" });
const read_only = text("目标位置只读", .{ .hint = "请换一个可写入的目录" });
const already_exists = text("同名文件已存在", .{ .hint = "请换一个名称或先处理已有文件" });
const name_too_long = text("文件名过长", .{ .hint = "请缩短文件名后重试" });
const not_dir = text("路径不是目录", .{ .hint = "请选择一个目录" });
const is_dir = text("路径是目录，不是文件", .{ .hint = "请选择一个文件" });
const network_unreachable = text("网络不可达", .{ .hint = "请检查网络连接、代理或 VPN" });
const connection_reset = text("对端中断了连接", .{ .hint = "请稍后重试" });
const record_cleanup_failed = text("部分记录未清理", .{ .hint = "请检查目录权限后重试" });
const record_busy = text("记录正被读取", .{ .hint = "请关闭预览或等待导出结束后重试" });
const live_session_active = text("仍有活动会话", .{ .hint = "请先结束活动会话", .inline_hint = true });
const recording_changed = text("记录内容已变化", .{ .detail = "本次不会删除被替换的文件。" });

// ── 偏好设置（settings-copy）──────────────────────────────────────
const settings_busy = text("设置正在保存", .{ .hint = "请稍候再操作", .inline_hint = true });
const invalid_draft = text("还有未通过校验的设置", .{ .hint = "请先修正标出的设置项", .inline_hint = true });
const invalid_value = text("取值无效", .{ .hint = "请检查后重新填写", .inline_hint = true });
const unknown_setting = text("此设置项已不可用", .{ .hint = "请重新打开偏好设置", .inline_hint = true });
const config_changed = text("配置文件已被其他操作修改", .{ .hint = "请重新打开偏好设置后再保存", .inline_hint = true });
const resource_not_ready = text("外观资源尚未准备好", .{ .hint = "请等待加载完成后再保存", .inline_hint = true });
const background_not_ready = text("背景图片尚未准备好", .{ .hint = "请等待加载完成后再保存", .inline_hint = true });
const image_invalid = text("无法识别此图片", .{ .hint = "请选择有效的 PNG 或 JPEG 图片", .inline_hint = true });
const image_unsupported = text("不支持此图片格式", .{ .hint = "请选择 PNG 或 JPEG 图片", .inline_hint = true });
const image_too_large = text("图片超过大小或尺寸限制", .{ .hint = "请缩小后重试", .inline_hint = true });
const no_usable_images = text("目录里没有可用的图片", .{ .hint = "请选择包含 PNG 或 JPEG 图片的目录", .inline_hint = true });
const theme_missing = text("主题已不存在", .{ .hint = "请重新选择主题", .inline_hint = true });
const plugin_missing = text("插件已不存在", .{ .hint = "请重新打开偏好设置", .inline_hint = true });
const plugin_required = text("有其他已启用的插件依赖它，不能禁用", .{});
const plugin_not_disableable = text("此插件不能禁用", .{});
const dialog_unavailable = text("无法打开系统对话框", .{ .hint = "请稍后重试", .inline_hint = true });
const no_diagnostic_logs = text("暂无可导出的诊断日志", .{});
const cleanup_expired = text("清除确认已失效", .{ .hint = "请重新发起清除", .inline_hint = true });
const cleanup_running = text("清除仍在进行", .{ .hint = "请等待完成后再操作", .inline_hint = true });
const notification_pending = text("正在等待系统通知授权结果…", .{});
const exhausted = text("本次运行的操作次数已用尽", .{ .hint = "请重新启动应用", .inline_hint = true });

// 主题导入 / 删除：同名错误在这里有更贴切的说法（原草稿保留）。
/// 与 `config/theme_registry.zig` 的 `max_import_bytes` 同值（shared/base 不反向依赖 config；设置测试核对两者一致）。
pub const theme_max_bytes = 2 * 1024 * 1024;
const theme_missing_colors = text("导入失败：缺少 ANSI 0–15 或必要颜色", .{});
const theme_too_large = text("导入失败：文件超过 " ++ bytes(theme_max_bytes), .{});
const theme_invalid = text("导入失败：主题格式或颜色无效", .{});
const theme_builtin = text("内置主题不可删除", .{});
const theme_in_use = text("先选择其他主题并保存，再删除此主题", .{});
const theme_previewing = text("先切换待选主题，再删除此主题", .{});
const theme_file_missing = text("文件已移动或不存在，原草稿已保留", .{});
const theme_access_denied = text("权限不足，原草稿已保留", .{});

/// 主题导入与删除（设置 › 外观 › 主题）。目录里没有的返回 null。
pub fn theme(err: anyerror) ?Text {
    return switch (err) {
        error.MissingColors => theme_missing_colors,
        error.ThemeTooLarge, error.StreamTooLong => theme_too_large,
        error.InvalidPlist, error.InvalidComponent, error.InvalidThemeName => theme_invalid,
        error.BuiltinThemeProtected => theme_builtin,
        error.CurrentThemeProtected => theme_in_use,
        error.DraftThemeProtected => theme_previewing,
        error.FileNotFound => theme_file_missing,
        error.AccessDenied, error.PermissionDenied => theme_access_denied,
        else => describe(err),
    };
}

// ── AI 扩展：MCP 服务与技能（设置 › AI › 扩展）──────────────────────
/// 与 `ai/mcp_client.zig` 的 `max_response_bytes` 同值（设置测试核对两者一致）。
pub const mcp_response_max_bytes = 32 * 1024 * 1024;
const ext = struct {
    const picker = text("无法打开技能选择器", .{ .hint = "请重试或拖入技能文件／文件夹", .inline_hint = true });
    const replace_collection = text("重新导入时请选择单个技能文件夹", .{});
    const one_at_a_time = text("一次只能导入一个技能", .{ .hint = "请只拖入一个技能文件或文件夹", .inline_hint = true });
    const invalid_drop = text("无法导入拖入的内容", .{ .hint = "请拖入技能文件或文件夹", .inline_hint = true });
    const limit = text("最多支持 16 个 MCP 服务", .{});
    const missing_skill = text("未找到 SKILL.md", .{ .hint = "请选择技能文件或包含技能的目录", .inline_hint = true });
    const duplicate = text("同名技能已存在", .{ .hint = "请使用原条目的重新导入", .inline_hint = true });
    const metadata = text("技能缺少有效的 name / description 元数据", .{});
    const missing_resource = text("技能引用了缺失的文件", .{ .hint = "请导入完整文件夹", .inline_hint = true });
    const unsupported_file = text("技能包包含符号链接或不支持的文件类型", .{});
    const no_space = text("磁盘空间不足，无法导入技能", .{});
    const access = text("无法访问此文件", .{ .hint = "请检查读取权限", .inline_hint = true });
    const bad_path = text("技能引用包含不支持的路径", .{});
    const not_found = text("未找到本地路径或技能包", .{ .hint = "请检查路径", .inline_hint = true });
    const authorization_required = text("需要授权", .{ .hint = "请在更多菜单中网页登录", .inline_hint = true });
    const insufficient_scope = text("MCP 授权范围不足", .{ .hint = "请调整 OAuth Scope 并重新网页登录", .inline_hint = true });
    const token_failed = text("无法获取或刷新授权令牌", .{ .hint = "请重新网页登录", .inline_hint = true });
    const registration_failed = text("OAuth 自动注册失败", .{ .hint = "请检查服务配置或填写预注册的 Client ID", .inline_hint = true });
    const mismatch = text("OAuth 资源地址或授权服务标识不匹配，已停止授权", .{});
    const pkce = text("授权服务未声明支持 PKCE S256，无法安全完成网页登录", .{});
    const callback = text("无法接收有效的本机授权回调", .{ .hint = "请重新网页登录", .inline_hint = true });
    const oauth_response_limit = text("OAuth 响应超过 " ++ bytes(2 * 1024 * 1024), .{});
    const browser = text("无法打开默认浏览器", .{ .hint = "请检查系统默认浏览器设置", .inline_hint = true });
    const client_id = text("服务未提供自动注册", .{ .hint = "请填入预注册的 OAuth Client ID", .inline_hint = true });
    const public_client = text("此注册配置不支持公开客户端（token_endpoint_auth_method=none）", .{});
    const denied = text("已拒绝 MCP 网页授权", .{});
    const authorization_timeout = text("网页授权等待超时", .{ .hint = "请重新登录", .inline_hint = true });
    const state_mismatch = text("网页授权回调校验失败", .{ .hint = "请重新登录", .inline_hint = true });
    const discovery = text("无法发现有效的 MCP OAuth 授权配置", .{});
    const root = text("共享根目录需为 file:/// 开头的本地目录 URI", .{});
    const program = text("stdio 程序和非空工作目录必须使用绝对路径", .{});
    const endpoint = text("HTTP 地址需使用 HTTPS 或本机 HTTP，且不能包含用户名、密码或片段", .{});
    const timeout = text("超时需为 100–120000 毫秒", .{});
    const version = text("服务返回了不支持的 MCP 协议版本", .{});
    const schema = text("MCP 工具参数 schema 无效或引用无法解析", .{});
    const schema_limit = text("MCP 单个工具 schema 超过 " ++ bytes(256 * 1024) ++ "，或工具目录超过 " ++ bytes(4 * 1024 * 1024), .{});
    const arguments_limit = text("MCP 调用参数超过 " ++ bytes(32 * 1024), .{});
    const response_limit = text("MCP 响应超过 " ++ bytes(mcp_response_max_bytes), .{});
    const mcp_timeout = text("MCP 服务响应超时", .{});
    const process_start = text("无法启动 MCP 服务", .{ .hint = "请检查程序路径与执行权限", .inline_hint = true });
    const transport = text("MCP 连接中断", .{ .hint = "请检查服务状态", .inline_hint = true });
    const http_status = text("MCP 服务返回了异常 HTTP 状态", .{});
    const secret = text("服务响应包含秘密配置，已阻止展示", .{});
    const editor_open = text("请先应用或取消 MCP 编辑", .{});
    const busy = text("请等待当前操作完成", .{});
    const cancelled_op = text("操作已取消", .{});
};

/// AI 扩展（MCP 服务与技能）的操作失败。目录里没有的返回 null。
pub fn aiExtension(err: anyerror) ?Text {
    return switch (err) {
        error.FilePickerUnavailable => ext.picker,
        error.SkillReplaceCollection => ext.replace_collection,
        error.ImportOneSkillAtATime => ext.one_at_a_time,
        error.InvalidFileDrop => ext.invalid_drop,
        error.ExtensionLimit => ext.limit,
        error.MissingSkillFile => ext.missing_skill,
        error.DuplicateSkill => ext.duplicate,
        error.InvalidSkillMetadata => ext.metadata,
        error.MissingSkillResource => ext.missing_resource,
        error.UnsupportedSkillFile => ext.unsupported_file,
        error.Cancelled, error.CancelledBeforeDispatch => ext.cancelled_op,
        error.NoSpaceLeft, error.DiskQuota => ext.no_space,
        error.AccessDenied => ext.access,
        error.InvalidSkillPath => ext.bad_path,
        error.FileNotFound => ext.not_found,
        error.McpAuthorizationRequired => ext.authorization_required,
        error.McpInsufficientScope => ext.insufficient_scope,
        error.McpOAuthTokenFailed => ext.token_failed,
        error.McpOAuthRegistrationFailed => ext.registration_failed,
        error.McpOAuthResourceMismatch, error.McpOAuthIssuerMismatch => ext.mismatch,
        error.McpOAuthPkceRequired => ext.pkce,
        error.McpOAuthCallbackFailed, error.InvalidMcpOAuthCallback => ext.callback,
        error.McpOAuthResponseLimit => ext.oauth_response_limit,
        error.BrowserOpenFailed => ext.browser,
        error.McpOAuthClientIdRequired => ext.client_id,
        error.McpOAuthPublicClientRequired => ext.public_client,
        error.McpAuthorizationDenied => ext.denied,
        error.McpAuthorizationTimeout => ext.authorization_timeout,
        error.McpOAuthStateMismatch => ext.state_mismatch,
        error.McpOAuthDiscoveryFailed, error.InvalidMcpOAuthMetadata => ext.discovery,
        error.InvalidMcpRoot => ext.root,
        error.InvalidMcpProgram => ext.program,
        error.InvalidMcpEndpoint => ext.endpoint,
        error.InvalidMcpTimeout => ext.timeout,
        error.UnsupportedMcpVersion => ext.version,
        error.InvalidMcpSchema => ext.schema,
        error.McpSchemaLimit => ext.schema_limit,
        error.McpArgumentsLimit => ext.arguments_limit,
        error.McpResponseLimit, error.McpResultLimit => ext.response_limit,
        error.McpTimeout => ext.mcp_timeout,
        error.McpProcessStartFailed => ext.process_start,
        error.McpTransportFailure => ext.transport,
        error.McpHttpStatus => ext.http_status,
        error.McpSecretReflected => ext.secret,
        error.ApplyOrCancelMcpEditor => ext.editor_open,
        error.SettingsBusy => ext.busy,
        else => describe(err),
    };
}

/// 分领域查询后的单行文案；都没有时用调用方给的本领域通用说法。
pub fn lineFrom(value: ?Text, fallback: []const u8) []const u8 {
    return if (value) |found| found.line else fallback;
}

/// 目录查询：没有收录的错误返回 null，由调用方给出本领域的通用说法（原始错误名进日志或详情）。
pub fn describe(err: anyerror) ?Text {
    return switch (err) {
        error.AuthenticationFailed, error.AgentIdentityNotAccepted => authentication_rejected,
        error.IdentityFileUnreadable => identity_unreadable,
        error.IdentityFileInvalid => identity_invalid,
        error.ConnectionTimedOut, error.ConnectionTimeout, error.ConnectTimeout, error.Timeout => timed_out,
        error.ConnectFailed => connect_failed,
        error.ConnectionRefused => refused,
        error.HostKeyChanged => host_key_changed,
        error.HostKeyConfirmationRequired => host_key_unconfirmed,
        error.HostKeyRevoked => host_key_revoked,
        error.Cancelled => cancelled,
        error.SftpSubsystemDenied => sftp_denied,
        error.SshHandshakeReceiveFailed => handshake_receive,
        error.SshHandshakeSendFailed => handshake_send,
        error.SshHandshakeDisconnected => handshake_disconnected,
        error.SshHandshakeBannerFailed => handshake_banner,
        error.SshHandshakeNegotiationFailed => handshake_negotiation,
        error.SshHandshakeTimedOut => handshake_timeout,
        error.HandshakeFailed => handshake_failed,
        error.AccessDenied, error.PermissionDenied => access_denied,
        error.FileNotFound => file_not_found,
        error.NoSpaceLeft, error.DiskQuota => no_space,
        error.OutOfMemory => out_of_memory,
        error.ReadOnlyFileSystem => read_only,
        error.PathAlreadyExists => already_exists,
        error.NameTooLong => name_too_long,
        error.NotDir => not_dir,
        error.IsDir => is_dir,
        error.NetworkUnreachable, error.HostUnreachable => network_unreachable,
        error.ConnectionResetByPeer, error.BrokenPipe => connection_reset,
        error.RecordCleanupFailed => record_cleanup_failed,
        error.RecordBusy => record_busy,
        error.LiveSessionActive => live_session_active,
        error.RecordingChanged => recording_changed,
        error.SettingsBusy => settings_busy,
        error.InvalidDraft => invalid_draft,
        error.InvalidValue, error.OutOfRange, error.InvalidCursor, error.InvalidWeight => invalid_value,
        error.UnknownKey => unknown_setting,
        error.StaleConfigRevision, error.RevisionConflict, error.FileConflict, error.StaleRegistryRevision, error.StaleThemeInstallation => config_changed,
        error.ThemeNotPrepared, error.FontNotPrepared, error.MismatchedAppearance => resource_not_ready,
        error.BackgroundNotPrepared => background_not_ready,
        error.InvalidImage, error.InvalidImagePath => image_invalid,
        error.UnsupportedImage => image_unsupported,
        error.ImageTooLarge => image_too_large,
        error.NoUsableImages => no_usable_images,
        error.UnknownTheme => theme_missing,
        error.UnknownPlugin => plugin_missing,
        error.PluginRequired => plugin_required,
        error.PluginNotDisableable => plugin_not_disableable,
        error.NativeDialogUnavailable => dialog_unavailable,
        error.NoDiagnosticLogs => no_diagnostic_logs,
        error.CleanupConfirmationExpired => cleanup_expired,
        error.CleanupAlreadyRunning => cleanup_running,
        error.AuthorizationRequestPending => notification_pending,
        error.OperationIdExhausted, error.DiagnosticOperationExhausted, error.AssetRevisionExhausted, error.RevisionExhausted, error.RegistryRevisionExhausted => exhausted,
        else => null,
    };
}

/// 单行文案；目录里没有时返回 null。
pub fn line(err: anyerror) ?[]const u8 {
    return if (describe(err)) |value| value.line else null;
}

/// 单行文案；目录里没有时用调用方给的通用说法（不暴露原始错误名）。
pub fn lineOr(err: anyerror, fallback: []const u8) []const u8 {
    return line(err) orelse fallback;
}

/// 可展开“详情”里的原始错误码一行，例如“错误码：ConnectionRefused”。
pub fn detailCode(buffer: []u8, err: anyerror) []const u8 {
    return std.fmt.bufPrint(buffer, "错误码：{s}", .{@errorName(err)}) catch "错误码：未知";
}

/// HTTP 状态码 → 用户文案（模型服务等 HTTP 接口共用）。
pub fn httpStatus(status: u16) []const u8 {
    return switch (status) {
        300...399 => "接口发生重定向，请检查 HTTPS 和 API 路径",
        400, 422 => "服务端拒绝请求参数",
        401 => "认证失败，请检查 API Key",
        403 => "当前凭据无访问权限",
        404 => "接口或模型不存在",
        408, 504 => "服务端请求超时",
        429 => "请求被限流，请稍后重试",
        500...503, 505...599 => "模型服务暂不可用",
        else => "请求失败",
    };
}

const testing = std.testing;

test "error catalog: every entry carries a title and a single-line sentence" {
    const samples = [_]anyerror{
        error.AuthenticationFailed,     error.IdentityFileUnreadable, error.IdentityFileInvalid, error.ConnectionTimeout,
        error.ConnectFailed,            error.ConnectionRefused,      error.HostKeyChanged,      error.HostKeyRevoked,
        error.SshHandshakeReceiveFailed, error.HandshakeFailed,       error.AccessDenied,        error.FileNotFound,
        error.NoSpaceLeft,              error.OutOfMemory,            error.RecordCleanupFailed,
    };
    for (samples) |err| {
        const value = describe(err).?;
        try testing.expect(value.title.len != 0);
        try testing.expect(std.mem.startsWith(u8, value.line, value.title));
        try testing.expect(std.mem.indexOf(u8, value.line, @errorName(err)) == null);
        try testing.expect(std.mem.indexOfScalar(u8, value.line, '\n') == null);
        try testing.expectEqual(value.in_log, std.mem.endsWith(u8, value.line, log_suffix));
    }
}

test "error catalog: the progress and log pages share one wording" {
    try testing.expectEqualStrings("服务器未接受认证信息", line(error.AuthenticationFailed).?);
    try testing.expectEqualStrings("无法读取私钥文件，请检查路径与权限", line(error.IdentityFileUnreadable).?);
    try testing.expectEqualStrings("连接超时", line(error.ConnectTimeout).?);
    try testing.expectEqualStrings("服务器主机密钥已变化", line(error.HostKeyChanged).?);
    try testing.expectEqualStrings("SSH 握手接收失败，请检查网络或服务端日志（详情见应用日志）", line(error.SshHandshakeReceiveFailed).?);
    try testing.expectEqualStrings("SSH 握手失败，尚未进行登录认证（详情见应用日志）", line(error.HandshakeFailed).?);
}

test "error catalog: settings, theme and AI extension domains" {
    try testing.expectEqualStrings("设置正在保存，请稍候再操作", line(error.SettingsBusy).?);
    try testing.expectEqualStrings("仍有活动会话，请先结束活动会话", line(error.LiveSessionActive).?);
    // 主题：同名错误给本领域说法；没有特例的回落到通用目录。
    try testing.expectEqualStrings("文件已移动或不存在，原草稿已保留", theme(error.FileNotFound).?.line);
    try testing.expectEqualStrings("先选择其他主题并保存，再删除此主题", theme(error.CurrentThemeProtected).?.line);
    try testing.expectEqualStrings("磁盘空间不足", theme(error.NoSpaceLeft).?.title);
    // AI 扩展：同上。
    try testing.expectEqualStrings("磁盘空间不足，无法导入技能", aiExtension(error.NoSpaceLeft).?.line);
    try testing.expectEqualStrings("一次只能导入一个技能，请只拖入一个技能文件或文件夹", aiExtension(error.ImportOneSkillAtATime).?.line);
    try testing.expectEqualStrings("连接超时", aiExtension(error.ConnectTimeout).?.line);
    try testing.expectEqualStrings("导入主题失败", lineFrom(theme(error.SomethingNobodyMapped), "导入主题失败"));
    // 不把原始错误名拼进文案，不用“移除”指删除导入主题。
    const samples = [_]anyerror{ error.MissingColors, error.CurrentThemeProtected, error.DraftThemeProtected, error.McpTimeout, error.InvalidMcpRoot, error.UnknownPlugin, error.InvalidDraft };
    for (samples) |err| {
        const value = theme(err) orelse aiExtension(err).?;
        try testing.expect(std.mem.indexOf(u8, value.line, @errorName(err)) == null);
        try testing.expect(std.mem.indexOf(u8, value.line, "移除") == null);
    }
}

test "error catalog: unknown errors fall back without exposing the raw name" {
    try testing.expect(describe(error.SomethingNobodyMapped) == null);
    try testing.expectEqualStrings("操作失败", lineOr(error.SomethingNobodyMapped, "操作失败"));
    var buffer: [64]u8 = undefined;
    try testing.expectEqualStrings("错误码：SomethingNobodyMapped", detailCode(&buffer, error.SomethingNobodyMapped));
    try testing.expectEqualStrings("认证失败，请检查 API Key", httpStatus(401));
}
