//! “AI 辅助”面板正文的 view-model 部分（F-set-ai，人工验收反馈第 10 条后半）：服务提供方列表 → 提供方详情（两级）、
//! 模型编辑器与删除确认（原生 `W.Modal`）、技能与 MCP。视图在 `view/panes/ai*.yix`。
//!
//! - 状态的唯一真相仍是 `Controller`（草稿里的提供方表、`ai_fields` 原文与问题、扩展表）；这里的 `Ui` 只存视图状态
//!   （打开的对话框、编辑器里的表单、显示 API Key、MCP 编辑表单、提供方级的提示）。
//! - 动作经 `ViewModel.dispatch(Intent.ai(...))` 进来（`run`），草稿操作与旧 `ai_provider_settings.Click.run` /
//!   `ai_model_editor.commit` / `provider_delete_dialog` / `ai_extensions_settings.Button.run` 逐分支相同；
//!   要宿主做的（获取模型清单、测试模型、技能导入 / 查看、MCP 测试 / 网页登录 / 退出授权）发 `Effect.ai_*`，
//!   结果经 `HostStatus.ai`（`HostAi`）回来。
//! - 选择器收 `vm: anytype`（`*ViewModel`），读 `revision` 建依赖；返回给视图的动态文字都写进这里的双缓冲槽
//!   （草稿快照每次编辑都会换，不能把草稿里的切片交给视图）。
//!
//! 本文件不依赖 zenit `ui`。
const std = @import("std");
const error_catalog = @import("../../../shared/base/error_text.zig");
const catalog = @import("catalog.zig");
const config = catalog.config;
const runtime = @import("../../../config/runtime_config.zig");
const ext = @import("../../../config/ai_extensions.zig");
const draft = @import("settings_ai_draft.zig");
const oauth = @import("../../../ai/mcp_oauth.zig");
const allowsNoAuth = @import("../../../ai/provider_config.zig").allowsNoAuth;
const Controller = @import("settings_controller.zig").Controller;

pub const page: u8 = 4;
pub const providers_sub: u8 = 0;
pub const behavior_sub: u8 = 1;
pub const extensions_sub: u8 = 2;

/// 有 test_id / 焦点标识的提供方与模型数上限（id 是编译期表）；超出的行照常显示，只是没有 test_id。
pub const id_providers = 32;
pub const id_models = 32;
/// 列表 / 文字槽的上限。
const max_rows = 64;
const max_models = 64;
const max_skills = 64;
const max_servers = 16;

pub const Field = draft.Field;
pub const Pair = struct { provider: u8, model: u8 };
pub const Capability = enum { reasoning, vision };
pub const Source = enum { api, manual, missing };
pub const Transport = enum { stdio, http };

/// MCP 编辑表单的字段（旧 `ai_extensions_settings.Field`，顺序相同）。
pub const McpField = enum { name, program, arguments, cwd, environment, endpoint, headers, timeout, bindings, roots, oauth_client_id, oauth_scope };
const mcp_field_count = std.enums.values(McpField).len;

// ── 动作 ──

pub const EditText = struct { provider: u8, field: Field, text: []const u8 };
pub const Kind = struct { provider: u8, kind: ?[]const u8 };
pub const Effort = struct { index: u8, on: bool };
pub const CapabilityPick = struct { which: Capability, value: ?[]const u8 };
pub const McpText = struct { field: McpField, text: []const u8 };

pub const Command = union(enum) {
    // ── 服务提供方 ──
    /// 列表行：进入这个提供方的详情页。
    open_provider: u8,
    /// 新增一个提供方（草稿）并进入它的详情页。
    add_provider,
    /// 删除提供方：先确认（`delete_*`）。新增中的提供方“取消新增”直接移除。
    delete_provider: u8,
    cancel_provider: u8,
    toggle_provider: u8,
    set_kind: Kind,
    edit_text: EditText,
    reveal_key,
    fetch_models: u8,
    default_model: Pair,
    delete_model: Pair,
    confirm_delete,
    cancel_delete,
    // ── 模型编辑器 ──
    add_model: u8,
    edit_model: Pair,
    editor_id: []const u8,
    /// 在“模型 ID”里按回车：与 `editor_id` 相同，另外手输的 ID 恰好是清单里的某个模型时按选中它处理
    /// （带出上下文窗口与能力；清单下拉只列前 `choice_limit` 项，之后的模型也能这样带出元数据）。
    editor_id_submit: []const u8,
    editor_context: []const u8,
    editor_pick: ?[]const u8,
    editor_capability: CapabilityPick,
    editor_effort: Effort,
    editor_default: bool,
    editor_fetch,
    editor_test,
    editor_save,
    editor_cancel,
    // ── 技能与 MCP ──
    add_skill,
    reimport_skill: u8,
    toggle_skill: u8,
    remove_skill: u8,
    view_skill: u8,
    /// 拖到“本地技能”上的路径（拖拽载荷原文，换行分隔）；`drop_invalid` = 载荷不是文件 / 被截断。
    drop_skill: []const u8,
    drop_invalid,
    cancel_job,
    new_server,
    edit_server: u8,
    toggle_server: u8,
    remove_server: u8,
    test_server: u8,
    view_server: u8,
    authorize_server: u8,
    logout_server: u8,
    mcp_transport: Transport,
    mcp_text: McpText,
    mcp_apply,
    mcp_cancel,
    clear_environment,
    clear_headers,
    /// 技能 / 服务的“更多”菜单（`W.Menu onSelect` 交来菜单项 id）。
    skill_menu: struct { index: u8, id: []const u8 },
    server_menu: struct { index: u8, id: []const u8 },
};

/// `run` 之后 view-model 要做的导航。
pub const Outcome = union(enum) {
    none,
    /// 进入第 n 个提供方的详情页（用户发起：同一作用域，不确认）。
    open_detail: u8,
    /// 回到服务提供方列表页（提供方被删除 / 取消新增）。
    open_list,
};

// ── 宿主侧（`Effect.ai_*` 与 `HostStatus.ai`） ──

/// 宿主要做的事（`Effect.ai`）。
pub const Job = union(enum) {
    /// 获取模型清单（按当前草稿里这个提供方的连接配置；进行中再请求 = 取消）。
    fetch_models: usize,
    /// 测试模型（`signature` 是编辑器发起时的表单签名，结果只对同一表单有效；进行中再请求 = 取消）。
    test_model: struct { provider: usize, model: config.AiModel, signature: u64 },
    /// 编辑器关闭：取消它发起的测试。
    cancel_test,
    /// 选择技能文件 / 文件夹并导入（`index` 给出时为重新导入这一项）。
    pick_skill: ?usize,
    /// 拖入的技能路径。
    import_skill: []const u8,
    read_skill: usize,
    test_server: usize,
    authorize_server: usize,
    logout_server: usize,
    cancel_job,
    /// 收起技能 / 服务的详情。
    close_detail,
    /// 显示某个服务上次测试的工具清单。
    show_server_detail: usize,
};

/// MCP 服务最近一次测试的结果（宿主持有）。
pub const ServerResult = struct { id: []const u8 = "", revision: u64 = 0, label: []const u8 = "", failed: bool = false };
pub const DetailTarget = union(enum) { none, skill: struct { id: []const u8, revision: []const u8 }, server: struct { id: []const u8, revision: u64 } };

/// 宿主持有、AI 面板要显示的状态（`HostStatus.ai`）。文字由宿主持有，view-model 读出后复制进自己的槽。
pub const HostAi = struct {
    /// 模型清单：属于哪个提供方（按发起时的连接签名，连接变了就作废）、是否进行中、状态文字、清单与能力是否已知。
    catalog_provider: ?usize = null,
    catalog_signature: u64 = 0,
    catalog_busy: bool = false,
    catalog_message: []const u8 = "",
    catalog_models: []const config.AiModel = &.{},
    /// 与 `catalog_models` 同序：接口是否返回了推理 / 识图能力。
    catalog_known: []const [2]bool = &.{},
    /// 模型测试：进行中、结果文字、对应的表单签名。
    test_busy: bool = false,
    test_message: []const u8 = "",
    test_signature: ?u64 = null,
    /// 扩展：后台任务（导入 / 查看 / 测试 / 授权）进行中、状态文字（失败时显示）、属于哪块、详情。
    job_busy: bool = false,
    status: []const u8 = "",
    status_error: bool = false,
    status_mcp: bool = false,
    detail: []const u8 = "",
    detail_open: bool = false,
    detail_target: DetailTarget = .none,
    server_results: []const ServerResult = &.{},
    /// 宿主拒绝开始获取 / 测试时的提供方级提示（“无法开始获取模型清单，请重试。”）。
    provider_error: []const u8 = "",
};

// ── 视图状态 ──

fn Slot(comptime n: usize) type {
    return struct { flip: u1 = 0, len: [2]usize = .{ 0, 0 }, buffers: [2][n]u8 = undefined };
}
/// 把文字写进槽里两份缓冲中的另一份再返回（内容没变时返回原切片），同 `view_model.swapIn`。
fn swapIn(slot: anytype, text: []const u8) []const u8 {
    const n = @min(text.len, slot.buffers[0].len);
    const current = slot.buffers[slot.flip][0..slot.len[slot.flip]];
    if (std.mem.eql(u8, current, text[0..n])) return current;
    slot.flip +%= 1;
    @memcpy(slot.buffers[slot.flip][0..n], text[0..n]);
    slot.len[slot.flip] = n;
    return slot.buffers[slot.flip][0..n];
}

/// 编辑器的文字字段：同一字段两份缓冲交替（程序写入时换地址，受控输入框才能判出变化）。
const EditorText = Slot(256);

pub const Editor = struct {
    provider: usize = 0,
    /// null = 添加模型。
    index: ?usize = null,
    model: config.AiModel = .{},
    id: EditorText = .{},
    context: Slot(32) = .{},
    /// 接口是否返回了推理 / 识图能力（编辑已有模型时视为已知）。
    known: [2]bool = .{ false, false },
    sources: [2]Source = .{ .missing, .missing },
    context_source: Source = .missing,
    /// 当前 ID 来自清单里的这一项（手动改 ID 后作废）。
    picked: bool = false,
    error_text: []const u8 = "",
    error_slot: Slot(256) = .{},
    name: Slot(128) = .{},
};

pub const Delete = struct {
    provider: usize,
    model: ?usize = null,
    name: Slot(128) = .{},
    model_id: Slot(256) = .{},
    problem: []const u8 = "",
};

pub const Mcp = struct {
    editing: bool = false,
    edit_index: ?usize = null,
    transport: Transport = .stdio,
    values: [mcp_field_count]Slot(2048) = @splat(.{}),
};

pub const ProviderItem = struct { key: u64, index: u8, last: bool };
pub const ModelItem = struct { key: u64, index: u8, last: bool };
pub const SkillItem = struct { key: u64, index: u8, last: bool };
pub const ServerItem = struct { key: u64, index: u8, last: bool };

pub const Ui = struct {
    /// 提供方级的提示（`settings.ai.provider_error`；静态文字）。
    error_text: []const u8 = "",
    /// 详情页上的 API Key 明文显示（离开详情页即复位）。
    reveal_key: bool = false,
    editor_open: bool = false,
    editor: Editor = .{},
    delete: ?Delete = null,
    mcp: Mcp = .{},
    /// 扩展的提示（同步操作失败，如“请先应用或取消 MCP 编辑”）；宿主任务的提示在 `HostAi.status`。
    ext_error: []const u8 = "",
    ext_error_mcp: bool = false,

    provider_items: [2][max_rows]ProviderItem = undefined,
    provider_flip: u1 = 0,
    model_items: [2][max_models]ModelItem = undefined,
    model_flip: u1 = 0,
    skill_items: [2][max_skills]SkillItem = undefined,
    skill_flip: u1 = 0,
    server_items: [2][max_servers]ServerItem = undefined,
    server_flip: u1 = 0,

    names: [max_rows]Slot(128) = @splat(.{}),
    summaries: [max_rows]Slot(96) = @splat(.{}),
    fields: [3]Slot(512) = @splat(.{}),
    model_names: [max_models]Slot(256) = @splat(.{}),
    model_contexts: [max_models]Slot(32) = @splat(.{}),
    model_numbers: [max_models]Slot(32) = @splat(.{}),
    catalog_text: Slot(1400) = .{},
    test_text: Slot(1400) = .{},
    skill_names: [max_skills]Slot(160) = @splat(.{}),
    skill_texts: [max_skills]Slot(1100) = @splat(.{}),
    server_names: [max_servers]Slot(160) = @splat(.{}),
    server_meta: [max_servers]Slot(512) = @splat(.{}),
    server_notes: [max_servers]Slot(512) = @splat(.{}),
    /// 开关的读屏文字（“停用 <名称>”，同旧 `ai_extensions_settings` 的开关标签）。
    skill_toggles: [max_skills]Slot(176) = @splat(.{}),
    server_toggles: [max_servers]Slot(176) = @splat(.{}),
    skill_summary: Slot(64) = .{},
    status_text: Slot(1400) = .{},
    detail_text: Slot(16 * 1024) = .{},
    default_options_names: [max_rows]Slot(128) = @splat(.{}),
    choices: [2][max_rows]Choice = undefined,
    choice_flip: u1 = 0,
    catalog_choices: [2][choice_limit]Choice = undefined,
    catalog_names: [choice_limit]Slot(160) = @splat(.{}),
    catalog_flip: u1 = 0,

    /// 有原生对话框（模型编辑器 / 删除确认）打开：整窗按键放行给它（Escape 由浮层栈收起）。
    pub fn modalOpen(self: *const Ui) bool {
        return self.editor_open or self.delete != null;
    }
    /// 离开详情页 / 重新打开窗口时复位的视图状态（草稿不变）。
    pub fn leaveDetail(self: *Ui) void {
        self.reveal_key = false;
        self.error_text = "";
    }
    /// MCP 编辑表单里的秘密（环境变量 / 请求头）在收起时清零。
    fn clearMcp(self: *Ui) void {
        for (&self.mcp.values) |*slot| for (&slot.buffers) |*buffer| std.crypto.secureZero(u8, buffer);
        self.mcp = .{};
    }
};

// ── test_id / 焦点标识（编译期表，与旧视图拼出来的字符串逐字节相同） ──

/// 0..255 的十进制文字（编译期拼 id 用，`++` 比 `comptimePrint` 便宜得多）。
const numbers = blk: {
    @setEvalBranchQuota(200_000);
    var list: [256][]const u8 = undefined;
    for (&list, 0..) |*item, i| item.* = std.fmt.comptimePrint("{d}", .{i});
    break :blk list;
};

pub fn providerId(index: usize, comptime suffix: []const u8) []const u8 {
    const table = comptime blk: {
        @setEvalBranchQuota(100_000);
        var list: [id_providers][]const u8 = undefined;
        for (&list, 0..) |*item, i| item.* = "settings.ai.provider." ++ numbers[i] ++ "." ++ suffix;
        break :blk list;
    };
    return if (index < id_providers) table[index] else "";
}
pub fn modelId(provider: usize, model: usize, comptime suffix: []const u8) []const u8 {
    const table = comptime blk: {
        @setEvalBranchQuota(400_000);
        var list: [id_providers * id_models][]const u8 = undefined;
        for (0..id_providers) |i| for (0..id_models) |j| {
            list[i * id_models + j] = "settings.ai.provider." ++ numbers[i] ++ ".model." ++ numbers[j] ++ "." ++ suffix;
        };
        break :blk list;
    };
    return if (provider < id_providers and model < id_models) table[provider * id_models + model] else "";
}
/// 提供方详情页输入框的焦点标识（`locate_problem` / `focusRestore`）。
pub fn providerFocus(index: usize, field: Field) []const u8 {
    return switch (field) {
        inline .name, .endpoint, .api_key => |which| focusTable(index, which),
        else => "",
    };
}
fn focusTable(index: usize, comptime field: Field) []const u8 {
    const table = comptime blk: {
        @setEvalBranchQuota(100_000);
        var list: [id_providers][]const u8 = undefined;
        for (&list, 0..) |*item, i| item.* = "focus:ai.provider." ++ numbers[i] ++ "." ++ @tagName(field);
        break :blk list;
    };
    return if (index < id_providers) table[index] else "";
}
pub fn skillId(index: usize, comptime suffix: []const u8) []const u8 {
    const table = comptime blk: {
        @setEvalBranchQuota(100_000);
        var list: [max_skills][]const u8 = undefined;
        for (&list, 0..) |*item, i| item.* = "settings.skill." ++ numbers[i] ++ "." ++ suffix;
        break :blk list;
    };
    return if (index < max_skills) table[index] else "";
}
pub fn serverId(index: usize, comptime suffix: []const u8) []const u8 {
    const table = comptime blk: {
        @setEvalBranchQuota(100_000);
        var list: [max_servers][]const u8 = undefined;
        for (&list, 0..) |*item, i| item.* = "settings.mcp." ++ numbers[i] ++ "." ++ suffix;
        break :blk list;
    };
    return if (index < max_servers) table[index] else "";
}
pub fn mcpFieldId(field: McpField) []const u8 {
    return switch (field) {
        inline else => |which| "settings.mcp.field." ++ @tagName(which),
    };
}
pub fn catalogOptionId(index: usize) []const u8 {
    const table = comptime blk: {
        @setEvalBranchQuota(100_000);
        var list: [256][]const u8 = undefined;
        for (&list, 0..) |*item, i| item.* = "settings.ai.model.catalog.option." ++ numbers[i];
        break :blk list;
    };
    return if (index < 256) table[index] else "";
}
/// 输入框的 test_id（`settings.ai.provider.<i>.<field>`）→ 提供方与字段（整窗 Escape 撤回原文用）。
pub fn parseFieldId(id: []const u8) ?struct { provider: usize, field: Field } {
    const prefix = "settings.ai.provider.";
    if (!std.mem.startsWith(u8, id, prefix)) return null;
    const rest = id[prefix.len..];
    const dot = std.mem.indexOfScalar(u8, rest, '.') orelse return null;
    const index = std.fmt.parseInt(usize, rest[0..dot], 10) catch return null;
    const name = rest[dot + 1 ..];
    inline for (.{ Field.name, Field.endpoint, Field.api_key }) |field| if (std.mem.eql(u8, name, @tagName(field))) return .{ .provider = index, .field = field };
    return null;
}

// ── 纯辅助（与旧视图相同） ──

pub fn displayName(p: config.AiProvider) []const u8 {
    if (p.name.len == 0) return "新服务提供方";
    return if (!std.mem.eql(u8, p.name, @tagName(p.kind))) p.name else protocolName(p.kind);
}
pub fn protocolName(kind: config.ProviderKind) []const u8 {
    return switch (kind) {
        .anthropic => "Anthropic",
        .openai_compat => "OpenAI 兼容",
        .ollama => "Ollama",
    };
}
pub fn numberText(value: u32, buffer: []u8) ![]const u8 {
    var plain: [16]u8 = undefined;
    const text = try std.fmt.bufPrint(&plain, "{d}", .{value});
    var n: usize = 0;
    for (text, 0..) |char, index| {
        if (index > 0 and (text.len - index) % 3 == 0) {
            buffer[n] = ',';
            n += 1;
        }
        buffer[n] = char;
        n += 1;
    }
    return buffer[0..n];
}
pub fn contextText(value: u32, buffer: []u8) ![]const u8 {
    if (value >= 1_000_000) return std.fmt.bufPrint(buffer, "{d:.1}M 上下文", .{@as(f64, @floatFromInt(value)) / 1_000_000});
    if (value >= 1000) return std.fmt.bufPrint(buffer, "{d:.0}K 上下文", .{@as(f64, @floatFromInt(value)) / 1000});
    return std.fmt.bufPrint(buffer, "{d} 上下文", .{value});
}
pub fn connectionSignature(p: config.AiProvider) u64 {
    var h = std.hash.Wyhash.init(0);
    h.update(p.name);
    h.update(p.endpoint);
    h.update(p.api_key);
    std.hash.autoHash(&h, p.kind);
    return h.final();
}
/// 推理等级的显示顺序与标签（存储下标不变）：none、low、medium、high、xhigh、max、ultra。
pub const effort_order = [_]u8{ 5, 0, 1, 2, 3, 4, 6 };
pub const effort_labels = [_][]const u8{ "low", "medium", "high", "xhigh", "max", "none", "ultra" };
pub fn effortId(index: usize) []const u8 {
    return ([_][]const u8{ "settings.ai.model.effort.low", "settings.ai.model.effort.medium", "settings.ai.model.effort.high", "settings.ai.model.effort.xhigh", "settings.ai.model.effort.max", "settings.ai.model.effort.none", "settings.ai.model.effort.ultra" })[index];
}

// ── 选择器（`vm: *ViewModel`） ──

fn rev(vm: anytype) void {
    _ = vm.signals.?.revision.get();
}
fn aiOf(vm: anytype) config.Ai {
    return vm.controller.model.value.ai;
}
fn host(vm: anytype) HostAi {
    return vm.ports.hostStatus().ai;
}
fn providerAt(vm: anytype, index: usize) ?config.AiProvider {
    const ai = aiOf(vm);
    return if (index < ai.provider_count) ai.providers[index] else null;
}
pub fn saving(vm: anytype) bool {
    rev(vm);
    return vm.controller.state() == .saving;
}

// 列表页

pub fn providerCount(vm: anytype) usize {
    rev(vm);
    return aiOf(vm).provider_count;
}
pub fn providerCountText(vm: anytype) []const u8 {
    return countText(providerCount(vm));
}
fn countText(count: usize) []const u8 {
    const table = comptime blk: {
        var list: [max_rows + 1][]const u8 = undefined;
        for (&list, 0..) |*item, i| item.* = numbers[i] ++ " 个";
        break :blk list;
    };
    return if (count <= max_rows) table[count] else "多个";
}
pub fn hasProviders(vm: anytype) bool {
    return providerCount(vm) != 0;
}
pub fn noProviders(vm: anytype) bool {
    return providerCount(vm) == 0;
}
/// `{for}` 行的 key：下标 + 是否最后一行。行的 `last`（决定底部发丝线）是挂载期参数，增删一行时“最后一行”换人，
/// key 跟着变才会重挂那一行，不会留下两行都没有分隔线 / 末行多一条分隔线。
fn rowKey(index: usize, last: bool) u64 {
    return @as(u64, index) * 2 + @intFromBool(last);
}
pub fn providerItems(vm: anytype) []const ProviderItem {
    const count = @min(providerCount(vm), max_rows);
    const ui = &vm.ai;
    ui.provider_flip +%= 1;
    const list = &ui.provider_items[ui.provider_flip];
    for (list[0..count], 0..) |*item, i| item.* = .{ .key = rowKey(i, i + 1 == count), .index = @intCast(i), .last = i + 1 == count };
    return list[0..count];
}
pub fn providerName(vm: anytype, index: usize) []const u8 {
    rev(vm);
    const p = providerAt(vm, index) orelse return "";
    return swapIn(&vm.ai.names[@min(index, max_rows - 1)], displayName(p));
}
/// 头像里的字（“AI” / 本机 Ollama 用“O”）：取名称的首字。
pub fn providerInitial(vm: anytype, index: usize) []const u8 {
    rev(vm);
    const p = providerAt(vm, index) orelse return "AI";
    return if (p.kind == .ollama) "O" else "AI";
}
pub fn providerSummary(vm: anytype, index: usize) []const u8 {
    rev(vm);
    const p = providerAt(vm, index) orelse return "";
    var buffer: [96]u8 = undefined;
    const text = if (p.model_count == 0) std.fmt.bufPrint(&buffer, "{s} · 尚未添加模型", .{protocolName(p.kind)}) catch "" else std.fmt.bufPrint(&buffer, "{s} · {d} 个模型", .{ protocolName(p.kind), p.model_count }) catch "";
    return swapIn(&vm.ai.summaries[@min(index, max_rows - 1)], text);
}
/// 列表行上的“默认”：这个提供方是默认服务提供方（且已启用）。
pub fn providerIsDefault(vm: anytype, index: usize) bool {
    rev(vm);
    const p = providerAt(vm, index) orelse return false;
    return p.enabled and std.mem.eql(u8, aiOf(vm).default_provider, draft.providerName(p));
}
/// 状态文字（旧详情页徽标）：已启用 / 已停用 / 待配置。
pub fn providerStatus(vm: anytype, index: usize) []const u8 {
    rev(vm);
    const p = providerAt(vm, index) orelse return "";
    return if (p.enabled) "已启用" else if (draft.eligible(p)) "已停用" else "待配置";
}
pub fn providerEnabled(vm: anytype, index: usize) bool {
    rev(vm);
    const p = providerAt(vm, index) orelse return false;
    return p.enabled;
}
pub fn providerDisabledShown(vm: anytype, index: usize) bool {
    return !providerEnabled(vm, index);
}
pub fn errorText(vm: anytype) []const u8 {
    rev(vm);
    if (vm.ai.error_text.len != 0) return vm.ai.error_text;
    return host(vm).provider_error;
}
pub fn errorShown(vm: anytype) bool {
    return errorText(vm).len != 0;
}

// 详情页

/// 当前详情页的提供方（列表页为 null）。内容页按位置整页重挂，这里不建依赖。
pub fn detail(vm: anytype) ?u8 {
    return vm.controller.aiProviderDetail();
}
pub fn detailShown(vm: anytype) bool {
    return detail(vm) != null;
}
pub fn listShown(vm: anytype) bool {
    return detail(vm) == null;
}
pub fn detailIndex(vm: anytype) u8 {
    return detail(vm) orelse 0;
}
pub fn enableHint(vm: anytype, index: usize) []const u8 {
    return if (providerEnabled(vm, index)) "已启用，可在 AI 助手中选择此服务提供方。" else "配置完成后打开开关启用。";
}
/// 连接字段的显示文字：用户打的原文（含无效的），否则是草稿值。
pub fn fieldText(vm: anytype, index: usize, field: Field) []const u8 {
    rev(vm);
    const c: *Controller = vm.controller;
    var buffer: [32]u8 = undefined;
    const text = if (c.ai_fields.get(.{ .provider = index, .field = field })) |raw| raw.input else draft.fieldValue(c.model.value.ai, .{ .provider = index, .field = field }, &buffer) catch "";
    const slot: usize = switch (field) {
        .name => 0,
        .endpoint => 1,
        else => 2,
    };
    return swapIn(&vm.ai.fields[slot], text);
}
/// 连接字段的校验提示（旧 `Field.refresh`：原文的问题，或保存校验指到这个已启用提供方的这一格）。
pub fn fieldProblem(vm: anytype, index: usize, field: Field) []const u8 {
    rev(vm);
    const c: *Controller = vm.controller;
    const address: draft.Address = .{ .provider = index, .field = field };
    var problem = if (c.ai_fields.get(address)) |raw| raw.problem else null;
    if (problem == null and c.validationProblem() != null) {
        const ai = c.model.value.ai;
        if (index < ai.provider_count and ai.providers[index].enabled) {
            if (draft.connectionProblem(ai.providers[index], index)) |missing| {
                if (address.eql(missing.address)) problem = missing.err;
            }
        }
    }
    return if (problem) |err| draft.problemText(err) else "";
}
pub fn fieldInvalid(vm: anytype, index: usize, field: Field) bool {
    return fieldProblem(vm, index, field).len != 0;
}
pub fn apiKeyLabel(vm: anytype, index: usize) []const u8 {
    rev(vm);
    const p = providerAt(vm, index) orelse return "API Key *";
    return if (allowsNoAuth(p.kind, p.endpoint)) "API Key（可选）" else "API Key *";
}
pub fn kindValue(vm: anytype, index: usize) ?[]const u8 {
    rev(vm);
    const p = providerAt(vm, index) orelse return null;
    return @tagName(p.kind);
}
pub fn revealed(vm: anytype) bool {
    rev(vm);
    return vm.ai.reveal_key;
}
pub fn concealed(vm: anytype) bool {
    return !revealed(vm);
}
pub fn revealLabel(vm: anytype) []const u8 {
    return if (revealed(vm)) "隐藏 API Key" else "显示 API Key";
}
pub fn isNewProvider(vm: anytype, index: usize) bool {
    rev(vm);
    return vm.controller.ai_fields.new_provider == index;
}
pub fn isExistingProvider(vm: anytype, index: usize) bool {
    return !isNewProvider(vm, index);
}
/// 删除提供方不可点：已启用的默认服务提供方（先选替代项）。
pub fn deleteProviderBlocked(vm: anytype, index: usize) bool {
    rev(vm);
    const p = providerAt(vm, index) orelse return true;
    return saving(vm) or (p.enabled and std.mem.eql(u8, aiOf(vm).default_provider, draft.providerName(p)));
}

// 模型

pub fn modelCount(vm: anytype, index: usize) usize {
    rev(vm);
    const p = providerAt(vm, index) orelse return 0;
    return p.model_count;
}
pub fn modelCountText(vm: anytype, index: usize) []const u8 {
    return countText(modelCount(vm, index));
}
pub fn hasModels(vm: anytype, index: usize) bool {
    return modelCount(vm, index) != 0;
}
pub fn noModels(vm: anytype, index: usize) bool {
    return modelCount(vm, index) == 0;
}
pub fn modelItems(vm: anytype, index: usize) []const ModelItem {
    const count = @min(modelCount(vm, index), max_models);
    const ui = &vm.ai;
    ui.model_flip +%= 1;
    const list = &ui.model_items[ui.model_flip];
    for (list[0..count], 0..) |*item, j| item.* = .{ .key = rowKey(j, j + 1 == count), .index = @intCast(j), .last = j + 1 == count };
    return list[0..count];
}
fn modelAt(vm: anytype, index: usize, j: usize) ?config.AiModel {
    const p = providerAt(vm, index) orelse return null;
    return if (j < p.model_count) p.models[j] else null;
}
pub fn modelName(vm: anytype, index: usize, j: usize) []const u8 {
    rev(vm);
    const model = modelAt(vm, index, j) orelse return "";
    return swapIn(&vm.ai.model_names[@min(j, max_models - 1)], if (model.id.len != 0) model.id else "未命名模型");
}
pub fn modelContext(vm: anytype, index: usize, j: usize) []const u8 {
    rev(vm);
    const model = modelAt(vm, index, j) orelse return "";
    var buffer: [32]u8 = undefined;
    return swapIn(&vm.ai.model_contexts[@min(j, max_models - 1)], contextText(model.context_window, &buffer) catch "");
}
/// 上下文窗口的完整数字（悬停提示：“200,000 tokens”）。
pub fn modelContextFull(vm: anytype, index: usize, j: usize) []const u8 {
    rev(vm);
    const model = modelAt(vm, index, j) orelse return "";
    var number: [24]u8 = undefined;
    var buffer: [32]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{s} tokens", .{numberText(model.context_window, &number) catch ""}) catch "";
    return swapIn(&vm.ai.model_numbers[@min(j, max_models - 1)], text);
}
pub fn modelReasoning(vm: anytype, index: usize, j: usize) bool {
    rev(vm);
    return if (modelAt(vm, index, j)) |model| model.reasoning else false;
}
pub fn modelVision(vm: anytype, index: usize, j: usize) bool {
    rev(vm);
    return if (modelAt(vm, index, j)) |model| model.vision else false;
}
pub fn modelTextOnly(vm: anytype, index: usize, j: usize) bool {
    return !modelReasoning(vm, index, j) and !modelVision(vm, index, j);
}
pub fn modelIsDefault(vm: anytype, index: usize, j: usize) bool {
    rev(vm);
    return if (modelAt(vm, index, j)) |model| model.default else false;
}
/// 星标不可点：已是默认，或模型配置不完整（旧 `ButtonState.refresh` 的 `.default_model`）。
pub fn defaultModelBlocked(vm: anytype, index: usize, j: usize) bool {
    rev(vm);
    const model = modelAt(vm, index, j) orelse return true;
    return saving(vm) or model.default or !draft.modelValid(model);
}
pub fn defaultModelTip(vm: anytype, index: usize, j: usize) []const u8 {
    return if (modelIsDefault(vm, index, j)) "默认模型" else "设为默认模型";
}
fn modelProtected(p: config.AiProvider, j: usize) bool {
    return (p.enabled and p.model_count <= 1) or (p.model_count > 1 and p.models[j].default);
}
/// 删除模型不可点：已启用提供方的最后一个模型，或默认模型（先选替代项）。
pub fn deleteModelBlocked(vm: anytype, index: usize, j: usize) bool {
    rev(vm);
    const p = providerAt(vm, index) orelse return true;
    if (j >= p.model_count) return true;
    return saving(vm) or modelProtected(p, j);
}
pub fn deleteModelTip(vm: anytype, index: usize, j: usize) []const u8 {
    return if (deleteModelBlocked(vm, index, j)) "删除模型前须选择默认替代项" else "删除模型";
}

/// 下拉选项的数据（视图换成原生 `W.SelectOption`；文字在槽里，稳定到下一次换文字）。
pub const Choice = struct { value: []const u8, label: []const u8, disabled: bool = false, test_id: ?[]const u8 = null };
pub const choice_limit = 200;
/// “默认服务提供方”的选项：每个提供方一项，未启用 / 连接不完整 / 没有模型的不可选（旧 `settings_ai.mountContent`）。
pub fn providerChoices(vm: anytype) []const Choice {
    rev(vm);
    const value = aiOf(vm);
    const count = @min(value.provider_count, max_rows);
    const ui = &vm.ai;
    ui.choice_flip +%= 1;
    const list = &ui.choices[ui.choice_flip];
    for (value.providers[0..count], 0..) |provider, i| {
        const name = swapIn(&ui.default_options_names[i], if (provider.name.len != 0) provider.name else @tagName(provider.kind));
        list[i] = .{ .value = name, .label = name, .disabled = !provider.enabled or provider.endpoint.len == 0 or provider.model_count == 0 };
    }
    return list[0..count];
}
/// 模型编辑器里“从清单选择”的选项（宿主获取的模型清单，属于编辑中的提供方）。
pub fn catalogChoices(vm: anytype) []const Choice {
    const models = candidates(vm);
    const count = @min(models.len, choice_limit);
    const ui = &vm.ai;
    ui.catalog_flip +%= 1;
    const list = &ui.catalog_choices[ui.catalog_flip];
    for (models[0..count], 0..) |model, i| {
        const id = swapIn(&ui.catalog_names[i], model.id);
        list[i] = .{ .value = id, .label = id, .test_id = catalogOptionId(i) };
    }
    return list[0..count];
}

// 模型清单（获取）

fn catalogValid(vm: anytype, index: usize) bool {
    const status = host(vm);
    const owner = status.catalog_provider orelse return false;
    const p = providerAt(vm, index) orelse return false;
    return owner == index and status.catalog_signature == connectionSignature(p);
}
pub fn fetching(vm: anytype, index: usize) bool {
    rev(vm);
    const status = host(vm);
    return status.catalog_busy and status.catalog_provider == index;
}
pub fn fetchLabel(vm: anytype, index: usize) []const u8 {
    return if (fetching(vm, index)) "取消获取" else "获取模型清单";
}
/// 另一个提供方正在获取时不可点（旧 `.fetch_models`）。
pub fn fetchBlocked(vm: anytype, index: usize) bool {
    rev(vm);
    const status = host(vm);
    return saving(vm) or (status.catalog_busy and status.catalog_provider != index);
}
pub fn catalogMessage(vm: anytype, index: usize) []const u8 {
    rev(vm);
    const status = host(vm);
    if (status.catalog_provider != index) return "";
    if (!status.catalog_busy and !catalogValid(vm, index) and status.catalog_message.len != 0) return "连接配置已变化，请重新获取模型清单。";
    return swapIn(&vm.ai.catalog_text, status.catalog_message);
}
pub fn catalogShown(vm: anytype, index: usize) bool {
    return catalogMessage(vm, index).len != 0;
}
/// 编辑器下拉里的候选模型（属于编辑中的提供方、连接签名一致）。
pub fn candidates(vm: anytype) []const config.AiModel {
    rev(vm);
    if (!vm.ai.editor_open or !catalogValid(vm, vm.ai.editor.provider)) return &.{};
    return host(vm).catalog_models;
}

// 模型编辑器

pub fn editorOpen(vm: anytype) bool {
    rev(vm);
    return vm.ai.editor_open;
}
pub fn editorTitle(vm: anytype) []const u8 {
    rev(vm);
    return if (vm.ai.editor.index == null) "添加模型" else "编辑模型";
}
pub fn editorSaveLabel(vm: anytype) []const u8 {
    rev(vm);
    return if (vm.ai.editor.index == null) "添加模型" else "保存模型";
}
pub fn editorProvider(vm: anytype) []const u8 {
    rev(vm);
    const e = &vm.ai.editor;
    return e.name.buffers[e.name.flip][0..e.name.len[e.name.flip]];
}
pub fn editorId(vm: anytype) []const u8 {
    rev(vm);
    const slot = &vm.ai.editor.id;
    return slot.buffers[slot.flip][0..slot.len[slot.flip]];
}
pub fn editorContext(vm: anytype) []const u8 {
    rev(vm);
    const slot = &vm.ai.editor.context;
    return slot.buffers[slot.flip][0..slot.len[slot.flip]];
}
/// 清单下拉的当前值：编辑器里的 ID 正好是一个候选时选中它。
pub fn editorPicked(vm: anytype) ?[]const u8 {
    const id = editorId(vm);
    for (candidates(vm)) |candidate| if (std.mem.eql(u8, candidate.id, id)) return id;
    return null;
}
pub fn catalogEmpty(vm: anytype) bool {
    return candidates(vm).len == 0;
}
pub fn catalogPlaceholder(vm: anytype) []const u8 {
    return if (catalogEmpty(vm)) "先获取模型清单" else "从清单选择";
}
pub fn editorCatalogStatus(vm: anytype) []const u8 {
    rev(vm);
    const message = catalogMessage(vm, vm.ai.editor.provider);
    return if (message.len != 0) message else "从清单选择，或手动输入模型 ID";
}
pub fn editorFetchLabel(vm: anytype) []const u8 {
    return fetchLabel(vm, vm.ai.editor.provider);
}
pub fn capabilityValue(vm: anytype, which: Capability) ?[]const u8 {
    rev(vm);
    const e = &vm.ai.editor;
    const k = @intFromEnum(which);
    if (!e.known[k]) return "unknown";
    const on = if (which == .reasoning) e.model.reasoning else e.model.vision;
    return if (on) "yes" else "no";
}
pub fn capabilitySource(vm: anytype, which: Capability) Source {
    rev(vm);
    return vm.ai.editor.sources[@intFromEnum(which)];
}
pub fn contextSource(vm: anytype) Source {
    rev(vm);
    return vm.ai.editor.context_source;
}
pub fn sourceText(source: Source) []const u8 {
    return switch (source) {
        .api => "接口已返回",
        .manual => "手动设置",
        .missing => "接口未返回，请补充",
    };
}
pub fn effortsShown(vm: anytype) bool {
    rev(vm);
    return vm.ai.editor.model.reasoning and vm.ai.editor.known[0];
}
pub fn effortChecked(vm: anytype, index: usize) bool {
    rev(vm);
    return vm.ai.editor.model.efforts[index];
}
pub fn editorDefault(vm: anytype) bool {
    rev(vm);
    return vm.ai.editor.model.default;
}
pub fn editorError(vm: anytype) []const u8 {
    rev(vm);
    return vm.ai.editor.error_text;
}
pub fn editorErrorShown(vm: anytype) bool {
    return editorError(vm).len != 0;
}
/// 编辑器表单的签名（测试结果只对发起时的同一表单有效，旧 `testSignature`）。
fn editorSignature(e: *const Editor) u64 {
    var hash = std.hash.Wyhash.init(0);
    hash.update(e.id.buffers[e.id.flip][0..e.id.len[e.id.flip]]);
    hash.update(e.context.buffers[e.context.flip][0..e.context.len[e.context.flip]]);
    std.hash.autoHash(&hash, e.model.reasoning);
    std.hash.autoHash(&hash, e.model.vision);
    for (e.model.efforts) |effort| std.hash.autoHash(&hash, effort);
    return hash.final();
}
pub fn testStatus(vm: anytype) []const u8 {
    rev(vm);
    const status = host(vm);
    const signature = status.test_signature orelse return "未测试";
    if (signature != editorSignature(&vm.ai.editor)) return "未测试";
    return swapIn(&vm.ai.test_text, if (status.test_busy) "测试中…" else status.test_message);
}
pub fn testLabel(vm: anytype) []const u8 {
    rev(vm);
    return if (host(vm).test_busy) "取消测试" else "测试模型";
}

// 删除确认

pub fn deleteOpen(vm: anytype) bool {
    rev(vm);
    return vm.ai.delete != null;
}
pub fn deleteTitle(vm: anytype) []const u8 {
    rev(vm);
    const target = vm.ai.delete orelse return "";
    return if (target.model == null) "删除服务提供方？" else "删除模型？";
}
pub fn deleteMessage(vm: anytype) []const u8 {
    rev(vm);
    const target = &(vm.ai.delete orelse return "");
    var buffer: [512]u8 = undefined;
    const name = target.name.buffers[target.name.flip][0..target.name.len[target.name.flip]];
    const model_id = target.model_id.buffers[target.model_id.flip][0..target.model_id.len[target.model_id.flip]];
    const text = if (target.model == null) std.fmt.bufPrint(&buffer, "将删除“{s}”及其模型配置。", .{name}) catch "" else std.fmt.bufPrint(&buffer, "将删除“{s}”的模型“{s}”的配置。", .{ name, model_id }) catch "";
    return swapIn(&vm.ai.catalog_text, text);
}
pub fn deleteProblem(vm: anytype) []const u8 {
    rev(vm);
    const target = vm.ai.delete orelse return "";
    return target.problem;
}
/// 删除确认的危险按钮（动词 + 对象，`shared/ui/confirm`）。
pub fn deleteLabel(vm: anytype) []const u8 {
    rev(vm);
    const target = vm.ai.delete orelse return confirm_labels.delete_provider;
    return if (target.model == null) confirm_labels.delete_provider else confirm_labels.delete_model;
}
const confirm_labels = struct {
    const C = @import("../../../shared/base/confirm_label.zig");
    const delete_provider = C.label(.delete, "服务提供方");
    const delete_model = C.label(.delete, "模型");
};
pub fn deleteProblemShown(vm: anytype) bool {
    return deleteProblem(vm).len != 0;
}

// 技能与 MCP

fn extensionsOf(vm: anytype) ext.Extensions {
    return aiOf(vm).extensions;
}
pub fn extBusy(vm: anytype) bool {
    rev(vm);
    return saving(vm) or host(vm).job_busy;
}
pub fn jobBusy(vm: anytype) bool {
    rev(vm);
    return host(vm).job_busy;
}
pub fn skillItems(vm: anytype) []const SkillItem {
    rev(vm);
    const count = @min(extensionsOf(vm).skills.len, max_skills);
    const ui = &vm.ai;
    ui.skill_flip +%= 1;
    const list = &ui.skill_items[ui.skill_flip];
    for (list[0..count], 0..) |*item, i| item.* = .{ .key = rowKey(i, i + 1 == count), .index = @intCast(i), .last = i + 1 == count };
    return list[0..count];
}
fn skillAt(vm: anytype, index: usize) ?ext.Skill {
    const skills = extensionsOf(vm).skills;
    return if (index < skills.len) skills[index] else null;
}
pub fn skillSummary(vm: anytype) []const u8 {
    rev(vm);
    const skills = extensionsOf(vm).skills;
    var enabled: usize = 0;
    for (skills) |skill| if (skill.enabled) {
        enabled += 1;
    };
    var buffer: [64]u8 = undefined;
    return swapIn(&vm.ai.skill_summary, std.fmt.bufPrint(&buffer, "{d} 个技能 · {d} 个启用", .{ skills.len, enabled }) catch "");
}
pub fn skillName(vm: anytype, index: usize) []const u8 {
    rev(vm);
    const skill = skillAt(vm, index) orelse return "";
    return swapIn(&vm.ai.skill_names[@min(index, max_skills - 1)], skill.name);
}
pub fn skillDescription(vm: anytype, index: usize) []const u8 {
    rev(vm);
    const skill = skillAt(vm, index) orelse return "";
    return swapIn(&vm.ai.skill_texts[@min(index, max_skills - 1)], skill.description);
}
pub fn skillEnabled(vm: anytype, index: usize) bool {
    rev(vm);
    return if (skillAt(vm, index)) |skill| skill.enabled else false;
}
pub fn skillExpanded(vm: anytype, index: usize) bool {
    rev(vm);
    const skill = skillAt(vm, index) orelse return false;
    const status = host(vm);
    if (!status.detail_open) return false;
    return switch (status.detail_target) {
        .skill => |owner| std.mem.eql(u8, owner.id, skill.id) and std.mem.eql(u8, owner.revision, skill.revision),
        else => false,
    };
}
pub fn skillViewLabel(vm: anytype, index: usize) []const u8 {
    return if (skillExpanded(vm, index)) "收起" else "查看";
}
/// 开关的读屏文字带技能名（“停用 <名称>”，同旧视图）。
pub fn skillToggleLabel(vm: anytype, index: usize) []const u8 {
    const verb = if (skillEnabled(vm, index)) "停用 " else "启用 ";
    var buffer: [176]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{s}{s}", .{ verb, skillName(vm, index) }) catch verb;
    return swapIn(&vm.ai.skill_toggles[@min(index, max_skills - 1)], text);
}
pub fn serverItems(vm: anytype) []const ServerItem {
    rev(vm);
    const count = @min(extensionsOf(vm).servers.len, max_servers);
    const ui = &vm.ai;
    ui.server_flip +%= 1;
    const list = &ui.server_items[ui.server_flip];
    for (list[0..count], 0..) |*item, i| item.* = .{ .key = rowKey(i, i + 1 == count), .index = @intCast(i), .last = i + 1 == count };
    return list[0..count];
}
fn serverAt(vm: anytype, index: usize) ?ext.Server {
    const servers = extensionsOf(vm).servers;
    return if (index < servers.len) servers[index] else null;
}
pub fn serverName(vm: anytype, index: usize) []const u8 {
    rev(vm);
    const server = serverAt(vm, index) orelse return "";
    return swapIn(&vm.ai.server_names[@min(index, max_servers - 1)], server.name);
}
pub fn serverHttp(vm: anytype, index: usize) bool {
    rev(vm);
    return if (serverAt(vm, index)) |server| server.transport == .http else false;
}
pub fn serverEnabled(vm: anytype, index: usize) bool {
    rev(vm);
    return if (serverAt(vm, index)) |server| server.enabled else false;
}
/// 开关的读屏文字带服务名（“停用 <名称>”，同旧视图）。
pub fn serverToggleLabel(vm: anytype, index: usize) []const u8 {
    const verb = if (serverEnabled(vm, index)) "停用 " else "启用 ";
    var buffer: [176]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{s}{s}", .{ verb, serverName(vm, index) }) catch verb;
    return swapIn(&vm.ai.server_toggles[@min(index, max_servers - 1)], text);
}
pub fn serverAuthorized(vm: anytype, index: usize) bool {
    rev(vm);
    const server = serverAt(vm, index) orelse return false;
    return server.transport == .http and oauth.authorized(server);
}
fn serverResult(vm: anytype, index: usize) ?ServerResult {
    const server = serverAt(vm, index) orelse return null;
    const results = host(vm).server_results;
    if (index >= results.len) return null;
    const result = results[index];
    if (!std.mem.eql(u8, result.id, server.id) or result.revision != server.revision or result.label.len == 0) return null;
    return result;
}
/// 服务行的第二行：“本地 · <程序名> · 未测试 / MCP 2025-06-18 · 3 个工具”（失败时只有地址，原因另起一行）。
pub fn serverMeta(vm: anytype, index: usize) []const u8 {
    rev(vm);
    const server = serverAt(vm, index) orelse return "";
    var address_buffer: [256]u8 = undefined;
    const address = if (server.transport == .stdio) std.fmt.bufPrint(&address_buffer, "本地 · {s}", .{std.fs.path.basename(server.program)}) catch "本地" else server.endpoint[0 .. std.mem.indexOfScalar(u8, server.endpoint, '?') orelse server.endpoint.len];
    const result = serverResult(vm, index);
    var buffer: [512]u8 = undefined;
    const text = if (result) |value| (if (value.failed) address else std.fmt.bufPrint(&buffer, "{s} · {s}", .{ address, value.label }) catch address) else std.fmt.bufPrint(&buffer, "{s} · 未测试", .{address}) catch address;
    return swapIn(&vm.ai.server_meta[@min(index, max_servers - 1)], text);
}
pub fn serverFailure(vm: anytype, index: usize) []const u8 {
    rev(vm);
    const result = serverResult(vm, index) orelse return "";
    if (!result.failed) return "";
    return swapIn(&vm.ai.server_notes[@min(index, max_servers - 1)], result.label);
}
pub fn serverFailed(vm: anytype, index: usize) bool {
    return serverFailure(vm, index).len != 0;
}
pub fn serverExpanded(vm: anytype, index: usize) bool {
    rev(vm);
    const server = serverAt(vm, index) orelse return false;
    const status = host(vm);
    if (!status.detail_open) return false;
    return switch (status.detail_target) {
        .server => |owner| std.mem.eql(u8, owner.id, server.id) and owner.revision == server.revision,
        else => false,
    };
}
/// “查看”只在测试成功后可点（旧 `view_button.disabled`）。
pub fn serverViewBlocked(vm: anytype, index: usize) bool {
    if (extBusy(vm)) return true;
    const result = serverResult(vm, index) orelse return true;
    return result.failed;
}
pub fn serverViewLabel(vm: anytype, index: usize) []const u8 {
    return if (serverExpanded(vm, index)) "收起" else "查看";
}
/// “查看 / 收起”的读屏文字（同旧视图的“查看工具详情 / 收起工具详情”）。
pub fn serverViewA11y(vm: anytype, index: usize) []const u8 {
    return if (serverExpanded(vm, index)) "收起工具详情" else "查看工具详情";
}
pub fn detailText(vm: anytype) []const u8 {
    rev(vm);
    return swapIn(&vm.ai.detail_text, host(vm).detail);
}
/// 扩展的提示（失败时显示在出错的那一块下面）。
pub fn extStatus(vm: anytype) []const u8 {
    rev(vm);
    if (vm.ai.ext_error.len != 0) return vm.ai.ext_error;
    const status = host(vm);
    if (!status.status_error) return "";
    return swapIn(&vm.ai.status_text, status.status);
}
fn extStatusMcp(vm: anytype) bool {
    if (vm.ai.ext_error.len != 0) return vm.ai.ext_error_mcp;
    return host(vm).status_mcp;
}
pub fn extStatusShown(vm: anytype) bool {
    return extStatus(vm).len != 0;
}
pub fn skillsStatusShown(vm: anytype) bool {
    return extStatus(vm).len != 0 and !extStatusMcp(vm);
}
pub fn mcpStatusShown(vm: anytype) bool {
    return extStatus(vm).len != 0 and extStatusMcp(vm);
}
pub fn mcpEditing(vm: anytype) bool {
    rev(vm);
    return vm.ai.mcp.editing;
}
pub fn mcpIdle(vm: anytype) bool {
    return !mcpEditing(vm);
}
pub fn mcpEditingExisting(vm: anytype) bool {
    rev(vm);
    return vm.ai.mcp.editing and vm.ai.mcp.edit_index != null;
}
pub fn mcpTransport(vm: anytype) Transport {
    rev(vm);
    return vm.ai.mcp.transport;
}
pub fn mcpStdio(vm: anytype) bool {
    return mcpTransport(vm) == .stdio;
}
pub fn mcpHttp(vm: anytype) bool {
    return mcpTransport(vm) == .http;
}
pub fn mcpValue(vm: anytype, field: McpField) []const u8 {
    rev(vm);
    const slot = &vm.ai.mcp.values[@intFromEnum(field)];
    return slot.buffers[slot.flip][0..slot.len[slot.flip]];
}
pub fn mcpLabel(field: McpField) []const u8 {
    return switch (field) {
        .name => "服务名称",
        .program => "程序绝对路径",
        .arguments => "参数 · 每行一个，不解析引号和 shell",
        .cwd => "工作目录 · 留空使用应用工作目录",
        .environment => "环境变量 · 每行 NAME=value；作为秘密保存；留空保留原值",
        .endpoint => "HTTP 地址 · HTTPS 或本机 HTTP",
        .headers => "请求头 · 每行 Name:value；作为秘密保存；留空保留原值",
        .timeout => "超时（毫秒，100–120000）",
        .bindings => "允许助手调用的工具 · 每行一个工具名",
        .roots => "共享根目录 · 每行一个 file:/// URI；留空不共享",
        .oauth_client_id => "OAuth Client ID · 可留空自动注册",
        .oauth_scope => "OAuth Scope · 留空使用服务声明",
    };
}

// ── 动作 ──

/// 执行一个 AI 面板动作；返回 view-model 要做的导航。`vm: *ViewModel`（`emit` 发 Effect）。
pub fn run(vm: anytype, command: Command) Outcome {
    const c: *Controller = vm.controller;
    const ui: *Ui = &vm.ai;
    if (c.state() == .saving) switch (command) {
        .editor_cancel, .cancel_delete, .open_provider, .cancel_job => {},
        else => return .none,
    };
    switch (command) {
        .open_provider => |index| {
            if (index >= c.model.value.ai.provider_count) return .none;
            ui.leaveDetail();
            return .{ .open_detail = index };
        },
        .add_provider => return addProvider(c, ui),
        .delete_provider => |index| {
            if (ui.modalOpen()) return .none;
            const ai = c.model.value.ai;
            if (index >= ai.provider_count) return .none;
            if (ai.providers[index].enabled and std.mem.eql(u8, ai.default_provider, draft.providerName(ai.providers[index]))) {
                ui.error_text = draft.problemText(error.DefaultProtected);
                return .none;
            }
            openDelete(ui, ai, index, null);
        },
        .cancel_provider => |index| {
            if (removeProvider(c, index)) {
                ui.error_text = "";
                return .open_list;
            }
        },
        .delete_model => |pair| {
            if (ui.modalOpen()) return .none;
            const ai = c.model.value.ai;
            if (pair.provider >= ai.provider_count or pair.model >= ai.providers[pair.provider].model_count) return .none;
            if (modelProtected(ai.providers[pair.provider], pair.model)) {
                ui.error_text = draft.problemText(error.DefaultProtected);
                return .none;
            }
            openDelete(ui, ai, pair.provider, pair.model);
        },
        .cancel_delete => ui.delete = null,
        .confirm_delete => return confirmDelete(c, ui),
        .toggle_provider => |index| toggleProvider(c, ui, index),
        .set_kind => |change| {
            const kind = std.meta.stringToEnum(config.ProviderKind, change.kind orelse return .none) orelse return .none;
            if (change.provider >= c.model.value.ai.provider_count or c.model.value.ai.providers[change.provider].kind == kind) return .none;
            var owned = runtime.Snapshot.init(c.allocator, c.model.value) catch return .none;
            defer owned.deinit();
            owned.value.ai.providers[change.provider].kind = kind;
            c.editProviders(owned.value.ai) catch |err| {
                ui.error_text = draft.problemText(err);
                return .none;
            };
            ui.error_text = "";
        },
        .edit_text => |edit| {
            c.editAiRaw(.{ .provider = edit.provider, .field = edit.field }, edit.text) catch {};
            ui.error_text = "";
        },
        .reveal_key => ui.reveal_key = !ui.reveal_key,
        .fetch_models => |index| fetchModels(vm, index),
        .default_model => |pair| {
            const ai = c.model.value.ai;
            if (pair.provider >= ai.provider_count) return .none;
            const p = ai.providers[pair.provider];
            if (pair.model >= p.model_count or !draft.modelValid(p.models[pair.model])) return .none;
            var owned = runtime.Snapshot.init(c.allocator, c.model.value) catch return .none;
            defer owned.deinit();
            const target = &owned.value.ai.providers[pair.provider];
            for (target.models[0..target.model_count], 0..) |*model, j| model.default = j == pair.model;
            c.editProviders(owned.value.ai) catch return .none;
            ui.error_text = "";
        },
        .add_model => |index| openEditor(c, ui, index, null),
        .edit_model => |pair| openEditor(c, ui, pair.provider, pair.model),
        .editor_id => |text| {
            const e = &ui.editor;
            _ = swapIn(&e.id, text);
            // 手动改了 ID：清单带来的能力与上下文作废（旧“使用输入的模型 ID”）。
            if (e.picked) {
                var still = false;
                for (candidates(vm)) |candidate| if (std.mem.eql(u8, candidate.id, std.mem.trim(u8, text, " \t"))) {
                    still = true;
                };
                if (!still) {
                    e.picked = false;
                    e.model = .{ .default = e.model.default, .context_window = 0, .efforts = @splat(false) };
                    _ = swapIn(&e.context, "");
                    e.context_source = .missing;
                    e.known = .{ false, false };
                    e.sources = .{ .missing, .missing };
                }
            }
            e.error_text = "";
        },
        .editor_id_submit => |text| {
            const typed = std.mem.trim(u8, text, " \t");
            // 已从清单选中（之后可能手改过上下文 / 能力）就不再覆盖；没选中时按选中处理。
            if (!ui.editor.picked) for (candidates(vm)) |candidate| if (std.mem.eql(u8, candidate.id, typed)) {
                pickCandidate(vm, candidate.id);
                return .none;
            };
            return run(vm, .{ .editor_id = text });
        },
        .editor_context => |text| {
            _ = swapIn(&ui.editor.context, text);
            ui.editor.context_source = .manual;
            ui.editor.error_text = "";
        },
        .editor_pick => |value| pickCandidate(vm, value orelse return .none),
        .editor_capability => |pick| {
            const selected = pick.value orelse return .none;
            if (std.mem.eql(u8, selected, "unknown")) return .none;
            const e = &ui.editor;
            const k = @intFromEnum(pick.which);
            e.known[k] = true;
            e.sources[k] = .manual;
            const on = std.mem.eql(u8, selected, "yes");
            switch (pick.which) {
                .reasoning => e.model.reasoning = on,
                .vision => e.model.vision = on,
            }
        },
        .editor_effort => |effort| if (effort.index < ui.editor.model.efforts.len) {
            ui.editor.model.efforts[effort.index] = effort.on;
        },
        .editor_default => |on| ui.editor.model.default = on,
        .editor_fetch => fetchModels(vm, ui.editor.provider),
        .editor_test => testModel(vm),
        .editor_save => commitEditor(c, ui),
        .editor_cancel => closeEditor(vm),
        // ── 技能与 MCP ──
        .add_skill => extensionJob(vm, .{ .pick_skill = null }),
        .reimport_skill => |index| extensionJob(vm, .{ .pick_skill = index }),
        .drop_skill => |payload| {
            var decoded = @import("../../../local/path_input.zig").decodeDropPaths(c.allocator, payload) catch |err| {
                ui.ext_error = extensionError(err);
                ui.ext_error_mcp = false;
                return .none;
            };
            defer decoded.deinit();
            if (decoded.paths.len != 1) {
                ui.ext_error = extensionError(error.ImportOneSkillAtATime);
                ui.ext_error_mcp = false;
                return .none;
            }
            extensionJob(vm, .{ .import_skill = decoded.paths[0] });
        },
        .drop_invalid => {
            ui.ext_error = extensionError(error.InvalidFileDrop);
            ui.ext_error_mcp = false;
        },
        .view_skill => |index| {
            if (skillExpanded(vm, index)) vm.ports.emit(.{ .ai = .close_detail }) else extensionJob(vm, .{ .read_skill = index });
        },
        .toggle_skill, .remove_skill => |index| {
            if (host(vm).job_busy) return .none;
            var extensions = c.model.value.ai.extensions;
            if (index >= extensions.skills.len) return .none;
            var list: std.ArrayList(ext.Skill) = .empty;
            defer list.deinit(c.allocator);
            list.appendSlice(c.allocator, extensions.skills) catch return .none;
            if (command == .remove_skill) _ = list.orderedRemove(index) else list.items[index].enabled = !list.items[index].enabled;
            extensions.skills = list.items;
            setExtensions(c, ui, extensions, false);
        },
        .cancel_job => vm.ports.emit(.{ .ai = .cancel_job }),
        .new_server, .edit_server => {
            if (host(vm).job_busy) return .none;
            const servers = c.model.value.ai.extensions.servers;
            const edit_index: ?usize = if (command == .edit_server) command.edit_server else null;
            if (edit_index) |i| if (i >= servers.len) return .none;
            ui.clearMcp();
            ui.mcp.editing = true;
            ui.mcp.edit_index = edit_index;
            ui.mcp.transport = if (edit_index) |i| (if (servers[i].transport == .http) .http else .stdio) else .stdio;
            const server: ?ext.Server = if (edit_index) |i| servers[i] else null;
            inline for (comptime std.enums.values(McpField)) |field| loadMcpField(ui, server, field);
            ui.ext_error = "";
        },
        .mcp_cancel => ui.clearMcp(),
        .mcp_transport => |transport| ui.mcp.transport = transport,
        .mcp_text => |edit| _ = swapIn(&ui.mcp.values[@intFromEnum(edit.field)], edit.text),
        .mcp_apply => applyMcp(c, ui) catch |err| {
            ui.ext_error = extensionError(err);
            ui.ext_error_mcp = true;
        },
        .toggle_server, .remove_server => |index| {
            if (host(vm).job_busy) return .none;
            if (ui.mcp.editing) {
                ui.ext_error = extensionError(error.ApplyOrCancelMcpEditor);
                ui.ext_error_mcp = true;
                return .none;
            }
            var arena = std.heap.ArenaAllocator.init(c.allocator);
            defer arena.deinit();
            var extensions = c.model.value.ai.extensions.clone(arena.allocator()) catch return .none;
            if (index >= extensions.servers.len) return .none;
            var list: std.ArrayList(ext.Server) = .empty;
            list.appendSlice(arena.allocator(), extensions.servers) catch return .none;
            if (command == .remove_server) _ = list.orderedRemove(index) else list.items[index].enabled = !list.items[index].enabled;
            extensions.servers = list.items;
            setExtensions(c, ui, extensions, true);
        },
        .test_server => |index| extensionJob(vm, .{ .test_server = index }),
        .authorize_server => |index| extensionJob(vm, .{ .authorize_server = index }),
        .logout_server => |index| {
            if (index < c.model.value.ai.extensions.servers.len) vm.ports.emit(.{ .ai = .{ .logout_server = index } });
        },
        .view_server => |index| {
            if (serverViewBlocked(vm, index)) return .none;
            vm.ports.emit(.{ .ai = if (serverExpanded(vm, index)) .close_detail else .{ .show_server_detail = index } });
        },
        .clear_environment, .clear_headers => if (ui.mcp.edit_index) |i| {
            var arena = std.heap.ArenaAllocator.init(c.allocator);
            defer arena.deinit();
            var extensions = c.model.value.ai.extensions.clone(arena.allocator()) catch return .none;
            if (i >= extensions.servers.len) return .none;
            if (command == .clear_environment) extensions.servers[i].environment = &.{} else extensions.servers[i].headers = &.{};
            extensions.servers[i].revision += 1;
            setExtensions(c, ui, extensions, true);
        },
        .skill_menu => |pick| {
            if (std.mem.eql(u8, pick.id, "reimport")) return run(vm, .{ .reimport_skill = pick.index });
            if (std.mem.eql(u8, pick.id, "remove")) return run(vm, .{ .remove_skill = pick.index });
        },
        .server_menu => |pick| {
            if (std.mem.eql(u8, pick.id, "edit")) return run(vm, .{ .edit_server = pick.index });
            if (std.mem.eql(u8, pick.id, "authorize")) return run(vm, .{ .authorize_server = pick.index });
            if (std.mem.eql(u8, pick.id, "logout")) return run(vm, .{ .logout_server = pick.index });
            if (std.mem.eql(u8, pick.id, "remove")) return run(vm, .{ .remove_server = pick.index });
        },
    }
    return .none;
}

fn addProvider(c: *Controller, ui: *Ui) Outcome {
    if (c.ai_fields.new_provider != null) {
        // 已有一个新增中的提供方：回到它（旧实现忽略第二次新增）。
        return .{ .open_detail = @intCast(c.ai_fields.new_provider.?) };
    }
    var owned = runtime.Snapshot.init(c.allocator, c.model.value) catch return .none;
    defer owned.deinit();
    const a = owned.arena.allocator();
    const ai = &owned.value.ai;
    const i = ai.provider_count;
    const next = a.alloc(config.AiProvider, i + 1) catch return .none;
    @memcpy(next[0..i], ai.providers[0..i]);
    next[i] = .{ .enabled = true };
    ai.providers = next;
    ai.provider_count += 1;
    c.editProviders(ai.*) catch return .none;
    c.ai_fields.new_provider = i;
    c.editAiRaw(.{ .provider = i, .field = .name }, "") catch {};
    ui.error_text = "";
    if (i > std.math.maxInt(u8)) return .none;
    return .{ .open_detail = @intCast(i) };
}
fn removeProvider(c: *Controller, index: usize) bool {
    var owned = runtime.Snapshot.init(c.allocator, c.model.value) catch return false;
    defer owned.deinit();
    const ai = &owned.value.ai;
    if (index >= ai.provider_count) return false;
    std.mem.copyForwards(config.AiProvider, ai.providers[index..], ai.providers[index + 1 .. ai.provider_count]);
    ai.provider_count -= 1;
    ai.providers = ai.providers[0..ai.provider_count];
    c.editProviders(ai.*) catch return false;
    c.ai_fields.removeProvider(c.allocator, index);
    c.refreshDirty();
    return true;
}
fn openDelete(ui: *Ui, ai: config.Ai, index: usize, model: ?usize) void {
    var target: Delete = .{ .provider = index, .model = model };
    const p = ai.providers[index];
    _ = swapIn(&target.name, draft.providerName(p));
    if (model) |j| _ = swapIn(&target.model_id, p.models[j].id);
    ui.delete = target;
    ui.error_text = "";
}
/// 删除确认里的“删除”（旧 `acceptDelete`：配置在确认期间变了就拒绝）。
fn confirmDelete(c: *Controller, ui: *Ui) Outcome {
    const target = &(ui.delete orelse return .none);
    const ai = c.model.value.ai;
    const name = target.name.buffers[target.name.flip][0..target.name.len[target.name.flip]];
    if (target.provider >= ai.provider_count or !std.mem.eql(u8, name, draft.providerName(ai.providers[target.provider]))) {
        target.problem = "配置已改变，请关闭后重新选择。";
        return .none;
    }
    const p = ai.providers[target.provider];
    if (target.model) |j| {
        const model_id = target.model_id.buffers[target.model_id.flip][0..target.model_id.len[target.model_id.flip]];
        if (j >= p.model_count or !std.mem.eql(u8, model_id, p.models[j].id)) {
            target.problem = "模型已改变，请关闭后重新选择。";
            return .none;
        }
        if (modelProtected(p, j)) {
            target.problem = draft.problemText(error.DefaultProtected);
            return .none;
        }
        var owned = runtime.Snapshot.init(c.allocator, c.model.value) catch return .none;
        defer owned.deinit();
        const q = &owned.value.ai.providers[target.provider];
        std.mem.copyForwards(config.AiModel, q.models[j..], q.models[j + 1 .. q.model_count]);
        q.model_count -= 1;
        q.models = q.models[0..q.model_count];
        c.editProviders(owned.value.ai) catch {
            target.problem = "当前配置不能删除，请先选择合法替代项。";
            return .none;
        };
        c.ai_fields.removeModel(c.allocator, target.provider, j);
        c.refreshDirty();
        ui.delete = null;
        ui.error_text = "";
        return .none;
    }
    if (p.enabled and std.mem.eql(u8, ai.default_provider, draft.providerName(p))) {
        target.problem = draft.problemText(error.DefaultProtected);
        return .none;
    }
    const index = target.provider;
    if (!removeProvider(c, index)) {
        target.problem = "当前配置不能删除，请先选择合法替代项。";
        return .none;
    }
    ui.delete = null;
    ui.error_text = "";
    return .open_list;
}
fn toggleProvider(c: *Controller, ui: *Ui, index: usize) void {
    if (index >= c.model.value.ai.provider_count) return;
    const p = c.model.value.ai.providers[index];
    if (!p.enabled) for (c.ai_fields.fields.items) |raw| {
        if (raw.address.provider == index and raw.problem != null) {
            ui.error_text = draft.problemText(raw.problem.?);
            return;
        }
    };
    var owned = runtime.Snapshot.init(c.allocator, c.model.value) catch return;
    defer owned.deinit();
    draft.setEnabled(&owned.value.ai, index, !p.enabled) catch |err| {
        ui.error_text = draft.problemText(err);
        return;
    };
    c.editProviders(owned.value.ai) catch |err| {
        ui.error_text = draft.problemText(err);
        return;
    };
    ui.error_text = "";
}
fn fetchModels(vm: anytype, index: usize) void {
    const c: *Controller = vm.controller;
    const status = host(vm);
    if (status.catalog_busy) {
        vm.ports.emit(.{ .ai = .{ .fetch_models = index } });
        return;
    }
    if (index >= c.model.value.ai.provider_count) return;
    if (!draft.endpointValid(c.model.value.ai.providers[index].endpoint)) {
        vm.ai.error_text = "请先填写有效的 API 地址。";
        if (vm.ai.editor_open) vm.ai.editor.error_text = "请先填写有效的 API 地址。";
        return;
    }
    vm.ai.error_text = "";
    vm.ports.emit(.{ .ai = .{ .fetch_models = index } });
}
fn openEditor(c: *Controller, ui: *Ui, index: usize, model_index: ?usize) void {
    if (ui.modalOpen()) return;
    const ai = c.model.value.ai;
    if (index >= ai.provider_count) return;
    const p = ai.providers[index];
    if (model_index) |j| if (j >= p.model_count) return;
    var e: Editor = .{ .provider = index, .index = model_index };
    e.model = if (model_index) |j| p.models[j] else .{ .default = p.model_count == 0, .context_window = 0, .efforts = @splat(false) };
    _ = swapIn(&e.id, e.model.id);
    var buffer: [32]u8 = undefined;
    _ = swapIn(&e.context, if (e.model.context_window == 0) "" else std.fmt.bufPrint(&buffer, "{d}", .{e.model.context_window}) catch "");
    e.model.id = "";
    const known = model_index != null;
    e.known = .{ known, known };
    e.sources = if (known) .{ .manual, .manual } else .{ .missing, .missing };
    e.context_source = if (known) .manual else .missing;
    _ = swapIn(&e.name, draft.providerName(p));
    ui.editor = e;
    ui.editor_open = true;
    ui.error_text = "";
}
fn closeEditor(vm: anytype) void {
    const status = host(vm);
    if (status.test_busy) vm.ports.emit(.{ .ai = .cancel_test });
    vm.ai.editor_open = false;
}
fn pickCandidate(vm: anytype, id: []const u8) void {
    const e = &vm.ai.editor;
    const list = candidates(vm);
    const known_list = host(vm).catalog_known;
    for (list, 0..) |candidate, index| if (std.mem.eql(u8, candidate.id, id)) {
        const was_default = e.model.default;
        e.model = candidate;
        e.model.default = was_default;
        e.model.id = "";
        const known: [2]bool = if (index < known_list.len) known_list[index] else .{ false, false };
        e.known = known;
        e.sources = .{ if (known[0]) .api else .missing, if (known[1]) .api else .missing };
        _ = swapIn(&e.id, candidate.id);
        var buffer: [32]u8 = undefined;
        _ = swapIn(&e.context, if (candidate.context_window == 0) "" else std.fmt.bufPrint(&buffer, "{d}", .{candidate.context_window}) catch "");
        e.context_source = if (candidate.context_window == 0) .missing else .api;
        e.picked = true;
        e.error_text = "";
        return;
    };
}
fn testModel(vm: anytype) void {
    const e = &vm.ai.editor;
    const status = host(vm);
    if (status.test_busy) {
        vm.ports.emit(.{ .ai = .cancel_test });
        return;
    }
    const id = std.mem.trim(u8, editorId(vm), " \t");
    if (id.len == 0) {
        e.error_text = "先选择或输入模型 ID，再测试。";
        return;
    }
    var model = e.model;
    model.id = id;
    model.context_window = std.fmt.parseInt(u32, std.mem.trim(u8, editorContext(vm), " \t"), 10) catch 0;
    vm.ports.emit(.{ .ai = .{ .test_model = .{ .provider = e.provider, .model = model, .signature = editorSignature(e) } } });
}
/// 编辑器的“添加模型 / 保存模型”（旧 `Editor.commit` + `ProviderView.commitModel`）：校验不过时留在对话框里给出原因，草稿不变。
fn commitEditor(c: *Controller, ui: *Ui) void {
    const e = &ui.editor;
    if (!e.known[0] or !e.known[1]) {
        e.error_text = if (!e.known[0]) "接口未返回推理能力，请手动选择。" else "接口未返回识图能力，请手动选择。";
        return;
    }
    var model = e.model;
    model.id = e.id.buffers[e.id.flip][0..e.id.len[e.id.flip]];
    const context = e.context.buffers[e.context.flip][0..e.context.len[e.context.flip]];
    model.context_window = std.fmt.parseInt(u32, std.mem.trim(u8, context, " \t"), 10) catch {
        e.error_text = draft.problemText(error.InvalidContextWindow);
        return;
    };
    commitModel(c, e.provider, e.index, model) catch |err| {
        e.error_text = draft.problemText(err);
        return;
    };
    ui.editor_open = false;
    ui.error_text = "";
}
fn commitModel(c: *Controller, i: usize, index: ?usize, model: config.AiModel) !void {
    var owned = try runtime.Snapshot.init(c.allocator, c.model.value);
    defer owned.deinit();
    if (i >= owned.value.ai.provider_count) return error.UnknownProvider;
    const p = &owned.value.ai.providers[i];
    const j = index orelse p.model_count;
    if (index == null) {
        const next = try owned.arena.allocator().alloc(config.AiModel, p.model_count + 1);
        @memcpy(next[0..p.model_count], p.models[0..p.model_count]);
        next[j] = model;
        p.models = next;
        p.model_count += 1;
    } else p.models[j] = model;
    try draft.assign(&owned.value.ai, .{ .provider = i, .model = j, .field = .model_id }, model.id);
    if (model.context_window == 0) return error.InvalidContextWindow;
    if (!draft.modelValid(model)) return error.LastEffortRequired;
    if (model.default) for (p.models[0..p.model_count], 0..) |*other, k| {
        other.default = k == j;
    };
    var defaults: usize = 0;
    for (p.models[0..p.model_count]) |other| if (other.default) {
        defaults += 1;
    };
    if (defaults != 1) return error.DefaultProtected;
    try c.editProviders(owned.value.ai);
    if (c.ai_fields.new_model) |new| if (new.provider == i and new.model == j) {
        c.ai_fields.new_model = null;
    };
}

fn extensionJob(vm: anytype, job: Job) void {
    if (host(vm).job_busy or vm.controller.state() == .saving) return;
    vm.ai.ext_error = "";
    vm.ports.emit(.{ .ai = job });
}
fn setExtensions(c: *Controller, ui: *Ui, extensions: ext.Extensions, mcp: bool) void {
    c.setExtensions(extensions) catch |err| {
        ui.ext_error = extensionError(err);
        ui.ext_error_mcp = mcp;
        return;
    };
    ui.ext_error = "";
}
fn loadMcpField(ui: *Ui, server: ?ext.Server, comptime field: McpField) void {
    var buffer: [2048]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&buffer);
    const a = fixed.allocator();
    const s = server orelse ext.Server{ .id = "new", .name = "" };
    const text: []const u8 = switch (field) {
        .name => s.name,
        .program => s.program,
        .arguments => std.mem.join(a, "\n", s.args) catch "",
        .cwd => s.cwd,
        .environment, .headers => "",
        .endpoint => s.endpoint,
        .roots => std.mem.join(a, "\n", s.roots) catch "",
        .oauth_client_id => s.oauth_client_id,
        .oauth_scope => s.oauth_scope,
        .timeout => std.fmt.allocPrint(a, "{d}", .{s.timeout_ms}) catch "",
        .bindings => blk: {
            var out: std.ArrayList(u8) = .empty;
            for (s.bindings, 0..) |binding, i| {
                if (i != 0) out.append(a, '\n') catch break;
                out.appendSlice(a, binding.name) catch break;
            }
            break :blk out.items;
        },
    };
    _ = swapIn(&ui.mcp.values[@intFromEnum(field)], text);
}
fn mcpText(ui: *const Ui, field: McpField) []const u8 {
    const slot = &ui.mcp.values[@intFromEnum(field)];
    return slot.buffers[slot.flip][0..slot.len[slot.flip]];
}
pub fn lines(a: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        const value = std.mem.trim(u8, line, " \t\r");
        if (value.len != 0) try result.append(a, value);
    }
    return result.toOwnedSlice(a);
}
pub fn parseValues(a: std.mem.Allocator, text: []const u8, delimiter: u8) ![]ext.Value {
    var values: std.ArrayList(ext.Value) = .empty;
    for (try lines(a, text)) |line| {
        const at = std.mem.indexOfScalar(u8, line, delimiter) orelse return error.InvalidMcpSecret;
        try values.append(a, .{ .name = std.mem.trim(u8, line[0..at], " \t"), .value = std.mem.trim(u8, line[at + 1 ..], " \t"), .secret = true });
    }
    return values.toOwnedSlice(a);
}
/// “应用到草稿”（旧 `View.apply`）。
fn applyMcp(c: *Controller, ui: *Ui) !void {
    var arena = std.heap.ArenaAllocator.init(c.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var extensions = try c.model.value.ai.extensions.clone(a);
    const index = ui.mcp.edit_index orelse extensions.servers.len;
    var server: ext.Server = if (ui.mcp.edit_index) |i| extensions.servers[i] else .{ .id = try std.fmt.allocPrint(a, "{s}", .{std.fmt.bytesToHex(@import("../../../host/identity.zig").TaskId.generate().bytes, .lower)}), .name = "" };
    server.name = mcpText(ui, .name);
    server.transport = if (ui.mcp.transport == .http) .http else .stdio;
    server.timeout_ms = std.fmt.parseInt(u32, std.mem.trim(u8, mcpText(ui, .timeout), " \t"), 10) catch return error.InvalidMcpTimeout;
    server.roots = try lines(a, mcpText(ui, .roots));
    server.oauth_client_id = mcpText(ui, .oauth_client_id);
    server.oauth_scope = mcpText(ui, .oauth_scope);
    const names = try lines(a, mcpText(ui, .bindings));
    const bindings = try a.alloc(ext.Binding, names.len);
    for (names, bindings) |name, *entry| entry.* = .{ .name = name };
    server.bindings = bindings;
    if (ui.mcp.transport == .stdio) {
        server.program = mcpText(ui, .program);
        server.args = try lines(a, mcpText(ui, .arguments));
        server.cwd = mcpText(ui, .cwd);
        if (mcpText(ui, .environment).len != 0) server.environment = try parseValues(a, mcpText(ui, .environment), '=');
        server.endpoint = "";
        server.headers = &.{};
    } else {
        server.endpoint = mcpText(ui, .endpoint);
        if (mcpText(ui, .headers).len != 0) server.headers = try parseValues(a, mcpText(ui, .headers), ':');
        server.program = "";
        server.args = &.{};
        server.cwd = "";
        server.environment = &.{};
    }
    if (ui.mcp.edit_index != null) server.revision = try std.math.add(u64, server.revision, 1);
    var list: std.ArrayList(ext.Server) = .empty;
    try list.appendSlice(a, extensions.servers);
    if (index == list.items.len) try list.append(a, server) else list.items[index] = server;
    extensions.servers = list.items;
    try c.setExtensions(extensions);
    ui.clearMcp();
    ui.ext_error = "";
}

/// 焦点是否在提供方的连接输入框（`settings.ai.provider.<i>.<字段>`）上：整窗 Esc 让它失焦。改过的值回到
/// 聚焦时的值由原生 Input 统一处理（OverlayHost → `Cx.input_escape`）。对话框（编辑器 / 删除确认）是原生
/// `W.Modal`，Escape 归浮层栈，不到这里。
/// `focus_id` is one of the provider connection inputs' focus ids (`providerFocus`).
pub fn isProviderFocus(focus_id: ?[]const u8) bool {
    const id = focus_id orelse return false;
    const prefix = "focus:ai.provider.";
    if (!std.mem.startsWith(u8, id, prefix)) return false;
    const rest = id[prefix.len..];
    const dot = std.mem.indexOfScalar(u8, rest, '.') orelse return false;
    const index = std.fmt.parseInt(usize, rest[0..dot], 10) catch return false;
    inline for (.{ Field.name, Field.endpoint, Field.api_key }) |field| {
        if (std.mem.eql(u8, rest[dot + 1 ..], @tagName(field))) return std.mem.eql(u8, providerFocus(index, field), id);
    }
    return false;
}

/// 扩展操作失败的提示：只查 `shared/base/error_text.zig` 的 AI 扩展目录；目录里没有时给通用说法，
/// 原始错误名由宿主（`ai_settings_host`）写进应用日志。
pub fn extensionError(err: anyerror) []const u8 {
    return error_catalog.lineFrom(error_catalog.aiExtension(err), "扩展操作未完成" ++ error_catalog.log_suffix);
}

test "ai pane ids match the frozen provider / model / extension ids" {
    try std.testing.expectEqualStrings("settings.ai.provider.3.header", providerId(3, "header"));
    try std.testing.expectEqualStrings("settings.ai.provider.1.model.2.delete_model", modelId(1, 2, "delete_model"));
    try std.testing.expectEqualStrings("settings.skill.0.toggle", skillId(0, "toggle"));
    try std.testing.expectEqualStrings("settings.mcp.field.oauth_scope", mcpFieldId(.oauth_scope));
    try std.testing.expectEqualStrings("", providerId(id_providers, "header"));
    const parsed = parseFieldId("settings.ai.provider.12.endpoint").?;
    try std.testing.expectEqual(@as(usize, 12), parsed.provider);
    try std.testing.expectEqual(Field.endpoint, parsed.field);
    try std.testing.expect(parseFieldId("settings.ai.provider.1.kind") == null);
}
