//! `host.tab_context` 的宿主一侧（M11）：从当前对话冻结的作用域里取出 tab 的 AI 卡片，交给
//! `ai/tab_context.zig` 按预算组装。每张卡片的内容由它的卡片类型实现（`CardAi.summary`）：
//! - `session_engine`：会话所属协议的引擎组装（终端：最近的输出行、当前目录与选区；文件：当前目录与选中项）；
//! - `provider`：插件卡片自己的摘要函数（KVM：最近画面与连接的元信息，不含像素）。
//! 取代只在测试里使用的 `ai_session_context` / `ai_group_context` 推送式组装。
//!
//! 只读：不发起连接、不执行命令、不改变任何状态；在 UI 线程上对内存快照取数。
const std = @import("std");
const tab_context = @import("../../../../ai/tab_context.zig");
const tool_def = @import("../../../../ai/tool_def.zig");
const scope_mod = @import("../../../../ai/tool_scope.zig");
const host = @import("../../../../ai/host_tools.zig");
const queries = @import("../../../../ai/host_queries.zig");
const identity = @import("../../../../host/identity.zig");
const card_types = @import("../../../../host/card_types.zig");

/// 环境由 AiHost 实例化（`Env(ApplicationHost, Roster)`）；这里不跨 feature import 工作区与外壳。
pub fn Env(comptime App: type, comptime Roster: type) type {
    return struct {
        app: *App,
        roster: ?*Roster,
        context: host.Context,
        scope: scope_mod.Scope,
        /// 本次请求模型的上下文窗口（会话级预算 = `card.contextBudget(window) * 4`）。
        context_window: u32,
        /// 宿主的文件工作区（文件卡片的查询用），类型擦除后原样交给卡片类型的实现。
        file_host: ?*anyopaque = null,
        /// 第 3 步参数校验失败时的可操作提示（流水线放进错误结构的 `hint`）。
        diagnostic_buffer: [768]u8 = undefined,
        diagnostic_len: usize = 0,

        pub fn diagnostic(self: *const @This()) ?[]const u8 {
            return if (self.diagnostic_len == 0) null else self.diagnostic_buffer[0..self.diagnostic_len];
        }
    };
}

/// 卡片的运行状态门禁（PLUGIN_ARCH_PLAN 2.5.8 第 8 条）：返回不可用的原因，可用时为 null。
/// `host.tab_context` 用它标出 `available=false`，`AiHost.assistantToolsAvailable` 用它判断 tab 级
/// "工具可用"（单卡 tab 看这张卡片，分屏 tab 看是否至少一张 AI 卡片可用），两处同一组条件。
pub fn unavailableReason(app: anytype, tab: anytype) ?[]const u8 {
    if (tab.content_owner != .session) return "not a session card";
    if (tab.card_type.ai == null) return "card type declares no AI";
    if (tab.closing) return "closing";
    if (tab.failed) return "failed";
    if (tab.local and tab.local_state != .running) return "local process not running";
    if (tab.terminal) |view| if (view.terminal_surface) |surface| if (surface.snapshot) |snapshot| {
        if (snapshot.eof_seen) return "terminal ended (EOF)";
    };
    if (tab.runtime) |runtime| if (!runtime.isConnected()) return "disconnected";
    const state = app.sessions.queryState(tab.content_owner.session) orelse return "session unavailable";
    if (state.lifecycle != .attached and state.lifecycle != .ready) return "not ready";
    return null;
}

/// 分屏（会话组）tab 的"工具可用"（2.5.8 第 8 条）：组内至少一张仍在组里的 AI 卡片运行状态可用。
/// 全部断开、关闭中、失败或已结束时为假：这一轮请求不带工具，对话与入口照样保留。
pub fn groupToolsAvailable(app: anytype, group: anytype) bool {
    for (group.members.items) |member| {
        if (!member.active) continue;
        for (app.workspace.tabs.items) |tab| {
            if (tab.id == member.pane_id and unavailableReason(app, tab) == null) return true;
        }
    }
    return false;
}


/// 请求期环境与 handler（流水线把环境作为 `Call.env` 交给 handler）。
pub fn Tool(comptime App: type, comptime Roster: type) type {
    return struct {
        pub const E = Env(App, Roster);
        fn noContext() *anyopaque {
            return @ptrCast(@constCast(&static_context));
        }
        const static_context: u8 = 0;

        /// 登记进统一注册表的定义（组合根调用）。handler 只依赖 `Call.env`。
        pub fn definition() tool_def.ToolDef {
            return tab_context.definition(.{ .context = noContext(), .call = handle });
        }

        const Collected = struct {
            cards: []tab_context.Card,
            handles: []identity.SessionHandle,
            split: bool,
        };

        /// 第 3 步（作用域与参数）：`card_refs` 里的每个引用都必须是本 tab 的卡片；查询参数必须被每张
        /// 选中卡片的类型支持（`CardAi.query`），游标必须属于它配的那张卡片。失败时把可操作的提示
        /// 写进 `env.diagnostic`。
        pub fn validateScope(env: *E, arguments: std.json.Value, allocator: std.mem.Allocator) !void {
            env.diagnostic_len = 0;
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const a = arena.allocator();
            const request = try tab_context.parseRequest(a, arguments);
            if (request.card_refs == null and !request.hasQuery()) return;
            const collected = try collect(env, a);
            if (request.card_refs) |refs| for (refs) |ref| {
                for (collected.cards) |card| {
                    if (std.mem.eql(u8, card.card_ref, ref)) break;
                } else return error.CardNotInTab;
            };
            var diagnostic: tab_context.Diagnostic = .{ .buffer = &env.diagnostic_buffer };
            defer env.diagnostic_len = diagnostic.len;
            try tab_context.validateParams(a, request, collected.cards, &diagnostic);
        }

        /// 概览 JSON（handler 的全部工作；单测直接调用它）。
        pub fn overview(env: *const E, arguments: std.json.Value, allocator: std.mem.Allocator) ![]u8 {
            var arena = std.heap.ArenaAllocator.init(allocator);
            defer arena.deinit();
            const a = arena.allocator();
            const request = try tab_context.parseRequest(a, arguments);
            const collected = try collect(env, a);
            var producer: Producer = .{ .env = env, .handles = collected.handles };
            return tab_context.assemble(allocator, request, .{ .context = &producer, .cards = collected.cards, .summary = Producer.summary }, @import("../../../../ai/card.zig").contextBudget(env.context_window) * 4, collected.split);
        }
        fn handle(_: *anyopaque, call: tool_def.Call, allocator: std.mem.Allocator) anyerror!tool_def.Output {
            const env: *const E = @ptrCast(@alignCast(call.env orelse return error.ContextUnavailable));
            const body = try overview(env, call.arguments, allocator);
            errdefer allocator.free(body);
            const content = try allocator.alloc(tool_def.Content, 1);
            content[0] = .{ .structured = body };
            return .{ .content = content };
        }

        /// tab 里声明了 AI 的会话卡片：就是冻结作用域的成员（单卡 tab 是它自己，组 tab 是组内成员）。
        fn collect(env: *const E, a: std.mem.Allocator) !Collected {
            const app = env.app;
            const held = env.context.contentOf();
            const group = if (held == .group) if (env.roster) |roster| roster.findById(std.math.cast(u32, held.group) orelse return error.ScopeChanged) else null else null;
            if (held == .group and group == null) return error.ScopeChanged;
            var cards: std.ArrayList(tab_context.Card) = .empty;
            var handles: std.ArrayList(identity.SessionHandle) = .empty;
            const redact = app.workspace.app_config.ai.redact_ip;
            for (env.scope.memberIds()) |id| {
                if (cards.items.len == tab_context.max_cards) break;
                const tab = for (app.workspace.tabs.items) |item| {
                    if (item.content_owner == .session and @backingInt(item.content_owner.session.session_id) == id) break item;
                } else continue;
                const owner = tab.content_owner.session;
                const ai = tab.card_type.ai orelse continue;
                const protocol = if (app.sessions.queryState(owner)) |state| state.protocol_id else "";
                // 运行状态门禁：不可用的卡片照样列出、不取摘要。
                const unavailable = unavailableReason(app, tab);
                var tools: std.ArrayList([]const u8) = .empty;
                switch (ai.tools) {
                    .none => {},
                    .session_tools => if (app.sessions.manifestFor(owner)) |manifest| for (manifest.tools) |binding| try tools.append(a, binding.definition_id),
                    .own => |ids| try tools.appendSlice(a, ids),
                }
                try tools.appendSlice(a, ai.host_tools);
                try cards.append(a, .{
                    .card_ref = try queries.sessionRef(a, env.context, owner),
                    .card_type = tab.card_type.id,
                    .title = if (redact) "<redacted>" else tab.titleSlice(),
                    .protocol = protocol,
                    .placement = if (held == .group) .split else .standalone_tab,
                    .available = unavailable == null,
                    .unavailable_reason = unavailable,
                    .pinned = if (group) |value| value.pinned_pane == tab.id else false,
                    .detail_tools = tools.items,
                    .params = .{ .max_lines = ai.query.max_lines, .limit = ai.query.limit, .cursor = ai.query.cursor, .note = ai.query.note },
                });
                try handles.append(a, owner);
            }
            return .{ .cards = cards.items, .handles = handles.items, .split = held == .group };
        }


        const Producer = struct {
            env: *const E,
            handles: []const identity.SessionHandle,
            /// 每种卡片类型自己的取数与组装：没有查询参数时是 `CardAi.summary`（与 M11 相同），带参数时
            /// 交给卡片类型自己的 `CardAi.query.run`（参数已在第 3 步按卡片类型校验）。
            fn summary(raw: *anyopaque, index: usize, query: tab_context.Query, allocator: std.mem.Allocator) anyerror!tab_context.Summary {
                const self: *Producer = @ptrCast(@alignCast(raw));
                const app = self.env.app;
                const owner = self.handles[index];
                const ai = app.sessions.cardAiFor(owner) orelse return error.AssistantUnavailable;
                const redact = app.workspace.app_config.ai.redact_ip;
                const budget = query.budget_bytes;
                if (query.any()) {
                    const run = ai.query.run orelse return error.UnsupportedParameter;
                    const result = try run(@ptrCast(app), owner, .{
                        .max_lines = query.max_lines,
                        .limit = query.limit,
                        .cursor = if (query.cursor) |cursor| cursor.offset else null,
                        .cursor_revision = if (query.cursor) |cursor| cursor.revision else null,
                        .budget_bytes = budget,
                        .redact = redact,
                        .context_window = self.env.context_window,
                        .file_host = self.env.file_host,
                    }, allocator);
                    return .{ .text = result.text, .truncated = result.truncated or result.text.len > budget, .next_offset = result.next_offset, .revision = result.revision };
                }
                switch (ai.summary) {
                    .session_engine => {
                        const factory = app.sessions.aiEngineFor(owner) orelse return error.AssistantContextUnavailable;
                        const bridge = try factory(allocator);
                        defer bridge.vtable.destroy(bridge.context, allocator);
                        var assembled = try bridge.vtable.assemble_context(allocator, app, owner, self.env.context_window, redact);
                        defer assembled.deinit(allocator);
                        return .{ .text = try allocator.dupe(u8, assembled.text), .truncated = assembled.truncated or assembled.text.len > budget };
                    },
                    .provider => |provider| {
                        const text = if (provider.summarize) |summarize| try summarize(provider.context, owner, allocator) else try allocator.dupe(u8, provider.identity);
                        return .{ .text = text, .truncated = text.len > budget };
                    },
                }
            }
        };

    };
}
