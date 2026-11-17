//! 内置工具 `host.tab_context`（PLUGIN_ARCH_PLAN 2.5.8"拉取式 tab 上下文"、2.9 的 M11）。
//!
//! 第一个直接按统一 `ToolDef` 写的工具：`target = tab`、只读免审批、走统一流水线
//! （`tool_pipeline.invoke`）。它返回当前对话绑定的 tab 里每张声明了 AI 的卡片一条概览：
//! 卡片引用、类型、身份、放置、是否可用、一段有上限的摘要，以及"读细节用哪些工具"。
//!
//! 每种卡片类型自己实现取数与组装（`CardAi.summary`：终端取最近的输出行与当前目录、文件取当前
//! 目录与选中项、KVM 取最近画面的元信息）；这里只负责筛选、按预算分配、截断标记与结构化输出。
//! 预算规则沿用 `group_context.Context.assemble`：身份先预留、剩余平均分配、钉住的卡片排最前、
//! 最多 16 张。
//!
//! 查询参数（ai-followup，用户要求"每种 card type 自己内部实现怎么 query 和组装信息"）：保留参数
//! `max_lines`（取多少历史）、`limit`、`cursor`，`next_cursor` 只出现在结果里。每种卡片类型在
//! `CardAi.query` 里声明支持哪些参数、各自含义，并自己实现取数；概览条目的 `params` 列出该卡片
//! 支持的参数。给某张卡片传了它不支持的参数时，流水线第 3 步返回 `Unsupported`，提示里写明哪张
//! 卡片不支持、它支持什么、哪些卡片支持这个参数（`validateParams`）。不带参数时行为与 M11 相同。
//! 游标只用于分页卡片自己的内存快照（文件目录项）：编码卡片引用的摘要、偏移与内容修订号；修订号
//! 变化时返回 `SnapshotChanged`。游标不授予任何权限（目标仍按冻结作用域校验），所以不做签名。
//!
//! 不自动注入（Q22 / Q24 已判定）：系统提示里只有元数据，模型按需调用本工具。
const std = @import("std");
const tool_def = @import("tool_def.zig");

pub const name = "host.tab_context";
pub const default_max_bytes: usize = 8192;
pub const limit_max_bytes: usize = 65536;
pub const max_cards = tool_def.max_target_refs;
/// 与 `tool_def.reserved_parameters` 的形状一致（`checkConventions` 强制）。
pub const limit_max_lines: u16 = 500;
pub const limit_limit: u16 = 200;
pub const cursor_max_len: usize = 128;

pub const description =
    "Read a bounded overview of every AI-capable card in this conversation's tab (a single-card tab has one entry; a split tab has one per card). " ++
    "Each entry has card_ref (for session cards this is the exact session_ref), card_type, identity, placement, availability, a bounded summary of its current content, " ++
    "params (the query parameters that card supports) and detail_tools: the tools that read that card in detail. Call it when a question concerns the current tab's terminal output, files or device state and you do not already have that content. " ++
    "Optional card_refs limits the overview to some cards; optional max_bytes (default 8192, at most 65536) bounds all summaries together. " ++
    "Optional query parameters apply to every selected card and each card type implements them itself: max_lines (terminal: the most recent N output lines), " ++
    "limit (terminal: the most recent N shell commands; file: at most N entries of the current remote directory), cursor (file: continue a directory listing from an entry's next_cursor; card_refs may be omitted or must name that card). " ++
    "A card that does not support a given parameter (for example a KVM card, which only returns metadata) makes the call fail with Unsupported; the hint names the cards that do support it, so retry with card_refs limited to them. " ++
    "A truncated summary only shows the most relevant part: use the card's detail_tools for full text, history ranges or search. " ++
    "Unavailable cards are listed with available=false and no summary. Errors: CardNotInTab means a card_ref is not in this tab; call host.tab_context without card_refs to list them. SnapshotChanged on a cursor means the listing changed; call again without cursor.";

pub const input_schema =
    "{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{" ++
    "\"card_refs\":{\"type\":\"array\",\"maxItems\":16,\"uniqueItems\":true,\"items\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":128},\"description\":\"Only these cards (card_ref values from this tab). Default: every AI card in the tab.\"}," ++
    "\"max_bytes\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":65536,\"description\":\"Upper bound for all summaries together. Default 8192.\"}," ++
    "\"max_lines\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":500,\"description\":\"History depth: the most recent N output lines. Terminal cards only; see each entry's params.\"}," ++
    "\"limit\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":200,\"description\":\"At most N items: terminal cards list the most recent N shell commands, file cards at most N directory entries. See each entry's params.\"}," ++
    "\"cursor\":{\"type\":\"string\",\"minLength\":1,\"maxLength\":128,\"description\":\"A next_cursor value from an earlier host.tab_context result, to read the next page of that card. File cards only.\"}" ++
    "}}";

/// 工具定义（handler 由宿主在登记时给出）。结果上限与流水线的 64 KiB 一致；`assemble` 保证不超过。
pub fn definition(handler: tool_def.NativeHandler) tool_def.ToolDef {
    return .{
        .name = name,
        .description = description,
        .input_schema = input_schema,
        .output = .structured,
        .handler = .{ .native = handler },
        .owner = .host,
        .approval = .read_only,
        .effect = .read_state,
        .target = .tab,
        .budget = .{ .max_argument_bytes = 4096, .max_result_bytes = 64 * 1024, .truncate = .reject },
    };
}

/// 登记进统一注册表的定义：宿主调用时由 AiHost 带上请求期环境执行（`ai_tab_context.Tool`），
/// 注册表这一份只用于列出工具与核对契约（`ToolDef.sameContract`），直接调用它会失败。
pub fn registered() tool_def.ToolDef {
    return definition(.{ .context = @ptrCast(@constCast(&unbound_context)), .call = unbound });
}
const unbound_context: u8 = 0;
fn unbound(_: *anyopaque, _: tool_def.Call, _: std.mem.Allocator) anyerror!tool_def.Output {
    return error.ContextUnavailable;
}

pub const Request = struct {
    /// 借用自调用参数。null 表示 tab 里的全部 AI 卡片。
    card_refs: ?[]const []const u8 = null,
    max_bytes: usize = default_max_bytes,
    max_lines: ?u16 = null,
    limit: ?u16 = null,
    /// 借用自调用参数。
    cursor: ?[]const u8 = null,

    pub fn hasQuery(self: Request) bool {
        return self.max_lines != null or self.limit != null or self.cursor != null;
    }
};
/// 参数已经过 schema 校验（流水线第 2 步）；这里只取值。
pub fn parseRequest(allocator: std.mem.Allocator, arguments: std.json.Value) !Request {
    var request: Request = .{};
    if (arguments != .object) return error.InvalidArguments;
    if (arguments.object.get("max_bytes")) |value| {
        if (value != .integer or value.integer < 1 or value.integer > limit_max_bytes) return error.InvalidArguments;
        request.max_bytes = @intCast(value.integer);
    }
    if (arguments.object.get("max_lines")) |value| {
        if (value != .integer or value.integer < 1 or value.integer > limit_max_lines) return error.InvalidArguments;
        request.max_lines = @intCast(value.integer);
    }
    if (arguments.object.get("limit")) |value| {
        if (value != .integer or value.integer < 1 or value.integer > limit_limit) return error.InvalidArguments;
        request.limit = @intCast(value.integer);
    }
    if (arguments.object.get("cursor")) |value| {
        if (value != .string or value.string.len == 0 or value.string.len > cursor_max_len) return error.InvalidArguments;
        request.cursor = value.string;
    }
    if (arguments.object.get("card_refs")) |value| {
        if (value != .array or value.array.items.len > max_cards) return error.InvalidArguments;
        const refs = try allocator.alloc([]const u8, value.array.items.len);
        for (value.array.items, refs) |item, *ref| {
            if (item != .string) return error.InvalidArguments;
            ref.* = item.string;
        }
        request.card_refs = refs;
    }
    return request;
}

/// 卡片类型声明的查询参数（`CardAi.query` 的投影）：非 null 表示支持，值是写给模型看的含义。
pub const Params = struct {
    max_lines: ?[]const u8 = null,
    limit: ?[]const u8 = null,
    cursor: ?[]const u8 = null,
    /// 不支持参数时的说明（告诉模型改用什么）。
    note: []const u8 = "",

    pub const Param = enum { max_lines, limit, cursor };
    pub fn meaning(self: Params, param: Param) ?[]const u8 {
        return switch (param) {
            .max_lines => self.max_lines,
            .limit => self.limit,
            .cursor => self.cursor,
        };
    }
};

pub const Placement = enum { standalone_tab, split, float };
/// 一张卡片的身份与状态（不含内容）。字符串借用自调用方。
pub const Card = struct {
    card_ref: []const u8,
    card_type: []const u8,
    title: []const u8,
    protocol: []const u8,
    placement: Placement,
    available: bool,
    unavailable_reason: ?[]const u8 = null,
    /// 钉住的卡片只影响顺序（排最前），不是隐含的执行目标。
    pinned: bool = false,
    detail_tools: []const []const u8 = &.{},
    params: Params = .{},
};
/// 交给卡片类型实现的查询（`Source.summary`）：预算与已校验的参数。没有任何参数时，实现走
/// 与 M11 相同的默认摘要。
pub const Query = struct {
    budget_bytes: usize,
    max_lines: ?u16 = null,
    limit: ?u16 = null,
    /// 已解出的游标：卡片内偏移与签发时的内容修订号。
    cursor: ?Cursor = null,

    pub fn any(self: Query) bool {
        return self.max_lines != null or self.limit != null or self.cursor != null;
    }
};
pub const Summary = struct {
    /// 由 `Source.summary` 用给定 allocator 分配。
    text: []const u8,
    /// 卡片类型自己在组装时已截断（例如终端只取最近若干行）。
    truncated: bool = false,
    /// 还有下一页时：下一页的卡片内偏移与当前内容修订号（宿主据此签出 `next_cursor`）。
    next_offset: ?u64 = null,
    revision: u64 = 0,
};
/// 宿主提供的卡片目录与各卡片类型的摘要函数。
pub const Source = struct {
    context: *anyopaque,
    cards: []const Card,
    /// 取第 `index` 张卡片的摘要；`query.budget_bytes` 是建议上限，超出部分由这里截断。
    summary: *const fn (context: *anyopaque, index: usize, query: Query, allocator: std.mem.Allocator) anyerror!Summary,
};

/// 游标：`tc1.<卡片引用摘要 16 位十六进制>.<偏移>.<修订号>`。只做定位，不授予权限。
pub const Cursor = struct {
    card: [8]u8,
    offset: u64,
    revision: u64,

    pub fn forCard(card_ref: []const u8) [8]u8 {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(card_ref, &digest, .{});
        return digest[0..8].*;
    }
    pub fn encode(self: Cursor, buffer: []u8) ![]const u8 {
        return std.fmt.bufPrint(buffer, "tc1.{s}.{d}.{d}", .{ std.fmt.bytesToHex(self.card, .lower), self.offset, self.revision });
    }
    pub fn decode(text: []const u8) !Cursor {
        var parts = std.mem.splitScalar(u8, text, '.');
        if (!std.mem.eql(u8, parts.next() orelse return error.InvalidCursor, "tc1")) return error.InvalidCursor;
        const card_hex = parts.next() orelse return error.InvalidCursor;
        if (card_hex.len != 16) return error.InvalidCursor;
        var card: [8]u8 = undefined;
        _ = std.fmt.hexToBytes(&card, card_hex) catch return error.InvalidCursor;
        const offset = std.fmt.parseInt(u64, parts.next() orelse return error.InvalidCursor, 10) catch return error.InvalidCursor;
        const revision = std.fmt.parseInt(u64, parts.next() orelse return error.InvalidCursor, 10) catch return error.InvalidCursor;
        if (parts.next() != null) return error.InvalidCursor;
        return .{ .card = card, .offset = offset, .revision = revision };
    }
    pub fn belongsTo(self: Cursor, card_ref: []const u8) bool {
        return std.mem.eql(u8, &self.card, &forCard(card_ref));
    }
};

/// 第 3 步的参数校验失败时给模型的提示（由调用方提供缓冲区，流水线把它放进错误结构）。
pub const Diagnostic = struct {
    buffer: []u8,
    len: usize = 0,
    pub fn text(self: *const Diagnostic) ?[]const u8 {
        return if (self.len == 0) null else self.buffer[0..self.len];
    }
    fn set(self: *Diagnostic, comptime format: []const u8, args: anytype) void {
        // 放不下时保留开头（错误码本身已经可操作）。
        var writer: std.Io.Writer = .fixed(self.buffer);
        writer.print(format, args) catch {};
        var end = writer.end;
        while (end > 0 and !std.unicode.utf8ValidateSlice(self.buffer[0..end])) end -= 1;
        self.len = end;
    }
};

/// 选中的卡片：`card_refs` 指名的（每个都必须在本 tab 里），否则全部；有游标且没有 `card_refs` 时
/// 是游标所属的那一张。返回的下标按 tab 内顺序，钉住的排最前。
pub fn select(allocator: std.mem.Allocator, request: Request, cards: []const Card) ![]usize {
    var selected: std.ArrayList(usize) = .empty;
    errdefer selected.deinit(allocator);
    if (request.card_refs) |refs| {
        for (refs, 0..) |ref, i| {
            for (refs[0..i]) |prior| if (std.mem.eql(u8, prior, ref)) return error.InvalidArguments;
            const index = for (cards, 0..) |card, at| {
                if (std.mem.eql(u8, card.card_ref, ref)) break at;
            } else return error.CardNotInTab;
            try selected.append(allocator, index);
        }
    } else if (request.cursor) |text| {
        const cursor = Cursor.decode(text) catch return error.InvalidCursor;
        const index = for (cards, 0..) |card, at| {
            if (cursor.belongsTo(card.card_ref)) break at;
        } else return error.InvalidCursor;
        try selected.append(allocator, index);
    } else for (cards, 0..) |_, index| try selected.append(allocator, index);
    // 钉住的卡片排最前，其余保持 tab 内的顺序。
    std.mem.sort(usize, selected.items, cards, struct {
        fn less(context: []const Card, left: usize, right: usize) bool {
            const lp = context[left].pinned;
            const rp = context[right].pinned;
            if (lp != rp) return lp;
            return left < right;
        }
    }.less);
    return selected.toOwnedSlice(allocator);
}

/// 参数校验（流水线第 3 步）：每张选中卡片的类型都必须支持请求里的每个查询参数；游标只能配一张
/// 卡片且属于它。失败时 `diagnostic` 写入可操作的提示。
pub fn validateParams(allocator: std.mem.Allocator, request: Request, cards: []const Card, diagnostic: ?*Diagnostic) !void {
    const selected = select(allocator, request, cards) catch |err| {
        if (err == error.InvalidCursor) if (diagnostic) |d| d.set("cursor is not a next_cursor of any card in this tab. Call host.tab_context without cursor to start over.", .{});
        return err;
    };
    defer allocator.free(selected);
    if (request.cursor) |text| {
        const cursor = Cursor.decode(text) catch {
            if (diagnostic) |d| d.set("cursor is not a next_cursor value. Call host.tab_context without cursor to start over.", .{});
            return error.InvalidCursor;
        };
        if (selected.len != 1 or !cursor.belongsTo(cards[selected[0]].card_ref)) {
            if (diagnostic) |d| {
                const owner = for (cards) |card| {
                    if (cursor.belongsTo(card.card_ref)) break card.card_ref;
                } else null;
                if (owner) |ref| d.set("cursor belongs to card {s}; pass card_refs [\"{s}\"] (or omit card_refs) together with it.", .{ ref, ref }) else d.set("cursor is not a next_cursor of any card in this tab. Call host.tab_context without cursor to start over.", .{});
            }
            return error.InvalidCursor;
        }
    }
    const checks = [_]struct { param: Params.Param, given: bool }{
        .{ .param = .max_lines, .given = request.max_lines != null },
        .{ .param = .limit, .given = request.limit != null },
        .{ .param = .cursor, .given = request.cursor != null },
    };
    for (checks) |check| {
        if (!check.given) continue;
        for (selected) |index| {
            const card = cards[index];
            if (card.params.meaning(check.param) != null) continue;
            if (diagnostic) |d| {
                var supported: std.ArrayList(u8) = .empty;
                defer supported.deinit(allocator);
                for (cards) |other| if (other.params.meaning(check.param) != null) {
                    if (supported.items.len != 0) try supported.appendSlice(allocator, ", ");
                    try supported.print(allocator, "{s} ({s})", .{ other.card_ref, other.card_type });
                };
                var own: std.ArrayList(u8) = .empty;
                defer own.deinit(allocator);
                inline for (.{ Params.Param.max_lines, Params.Param.limit, Params.Param.cursor }) |param| if (card.params.meaning(param) != null) {
                    if (own.items.len != 0) try own.appendSlice(allocator, ", ");
                    try own.appendSlice(allocator, @tagName(param));
                };
                const own_text: []const u8 = if (own.items.len == 0) "no query parameters" else own.items;
                const note: []const u8 = if (card.params.note.len == 0) "" else card.params.note;
                if (supported.items.len == 0)
                    d.set("Card {s} ({s}) does not support {s}; it accepts {s}. {s} No card in this tab supports {s}: call host.tab_context without it.", .{ card.card_ref, card.card_type, @tagName(check.param), own_text, note, @tagName(check.param) })
                else
                    d.set("Card {s} ({s}) does not support {s}; it accepts {s}. {s} Cards that support {s}: {s}. Retry with card_refs limited to those cards, or drop {s}.", .{ card.card_ref, card.card_type, @tagName(check.param), own_text, note, @tagName(check.param), supported.items, @tagName(check.param) });
            }
            return error.UnsupportedParameter;
        }
    }
}

const Entry = struct {
    card_ref: []const u8,
    card_type: []const u8,
    title: []const u8,
    protocol: []const u8,
    placement: []const u8,
    available: bool,
    unavailable_reason: ?[]const u8,
    pinned: bool,
    summary: ?[]const u8,
    truncated: bool,
    next_cursor: ?[]const u8,
    params: []const []const u8,
    detail_tools: []const []const u8,
};
const Output = struct {
    tab: struct { kind: []const u8, card_count: usize },
    cards: []const Entry,
    max_bytes: usize,
    truncated: bool,
    hint: ?[]const u8,
};
const truncated_hint = "Some summaries were truncated. Call that card's detail_tools (for terminals host.read_terminal with a line range or cursor, host.search_terminal) to read more.";

/// 按请求组装概览 JSON。`global_budget_bytes` 是会话级上限（`card.contextBudget(window) * 4`）；
/// 摘要总预算取 `max_bytes` 与它的较小值。`card_refs` 含不属于本 tab 的引用时返回
/// `error.CardNotInTab`；查询参数不被某张选中卡片支持时返回 `error.UnsupportedParameter`。
/// 返回值由 `allocator` 分配。
pub fn assemble(allocator: std.mem.Allocator, request: Request, source: Source, global_budget_bytes: usize, split: bool) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    if (source.cards.len > max_cards) return error.TooManyCards;
    try validateParams(a, request, source.cards, null);
    const selected = try select(a, request, source.cards);
    const cursor: ?Cursor = if (request.cursor) |text| try Cursor.decode(text) else null;
    // 身份先预留：每张卡片的身份与状态都会输出；剩余按可用卡片平均分配给摘要。
    const total_budget = @min(request.max_bytes, global_budget_bytes, limit_max_bytes);
    var reserved: usize = 0;
    var available_count: usize = 0;
    for (selected) |index| {
        const card = source.cards[index];
        reserved += 200 + card.card_ref.len + card.card_type.len + card.title.len + card.protocol.len + (if (card.unavailable_reason) |reason| reason.len else 0);
        for (card.detail_tools) |tool| reserved += tool.len + 3;
        if (card.available) available_count += 1;
    }
    const summary_total = if (total_budget > reserved) total_budget - reserved else 0;
    const per_card = summary_total / @max(available_count, 1);
    const entries = try a.alloc(Entry, selected.len);
    var any_truncated = false;
    for (selected, entries) |index, *entry| {
        const card = source.cards[index];
        var summary: ?[]const u8 = null;
        var truncated = false;
        var next_cursor: ?[]const u8 = null;
        if (card.available) {
            const query: Query = .{ .budget_bytes = per_card, .max_lines = request.max_lines, .limit = request.limit, .cursor = cursor };
            const produced = source.summary(source.context, index, query, a) catch |err| blk: {
                // 游标对应的内容已变化：整个调用失败，让模型从头再读（不悄悄给出别的页）。
                if (err == error.SnapshotChanged and cursor != null) return err;
                break :blk Summary{ .text = try std.fmt.allocPrint(a, "summary unavailable: {s}", .{@errorName(err)}), .truncated = true };
            };
            const kept = if (produced.next_offset != null) head(produced.text, per_card) else tail(produced.text, per_card);
            summary = kept;
            truncated = produced.truncated or kept.len < produced.text.len;
            if (truncated) any_truncated = true;
            // 分页实现自己按 `budget_bytes` 停在条目边界并给出下一页的偏移；万一结果仍被这里截断，
            // 不签发游标（否则下一页会跳过被截掉的条目），只标记截断。
            if (produced.next_offset) |offset| if (kept.len == produced.text.len) {
                const buffer = try a.alloc(u8, cursor_max_len);
                next_cursor = try (Cursor{ .card = Cursor.forCard(card.card_ref), .offset = offset, .revision = produced.revision }).encode(buffer);
            };
        }
        var names: std.ArrayList([]const u8) = .empty;
        inline for (.{ Params.Param.max_lines, Params.Param.limit, Params.Param.cursor }) |param| if (card.params.meaning(param) != null) try names.append(a, @tagName(param));
        entry.* = .{
            .card_ref = card.card_ref,
            .card_type = card.card_type,
            .title = card.title,
            .protocol = card.protocol,
            .placement = @tagName(card.placement),
            .available = card.available,
            .unavailable_reason = if (card.available) null else card.unavailable_reason orelse "unavailable",
            .pinned = card.pinned,
            .summary = summary,
            .truncated = truncated,
            .next_cursor = next_cursor,
            .params = names.items,
            .detail_tools = card.detail_tools,
        };
    }
    const out: Output = .{
        .tab = .{ .kind = if (split) "split" else "single", .card_count = source.cards.len },
        .cards = entries,
        .max_bytes = total_budget,
        .truncated = any_truncated,
        .hint = if (any_truncated) truncated_hint else null,
    };
    const body = try std.json.Stringify.valueAlloc(allocator, out, .{});
    if (body.len > 64 * 1024) {
        allocator.free(body);
        return error.ToolResultTooLarge;
    }
    return body;
}

/// 保留末尾（终端输出最近的部分最相关），从行首开始，不切断 UTF-8。
fn tail(text: []const u8, limit: usize) []const u8 {
    if (text.len <= limit) return text;
    var start = text.len - limit;
    while (start < text.len and (text[start] & 0xC0) == 0x80) start += 1;
    if (std.mem.indexOfScalarPos(u8, text, start, '\n')) |newline| {
        if (newline + 1 < text.len and text.len - (newline + 1) >= limit / 2) start = newline + 1;
    }
    return text[start..];
}
/// 保留开头（分页列表按顺序读），在行尾截断，不切断 UTF-8。
fn head(text: []const u8, limit: usize) []const u8 {
    if (text.len <= limit) return text;
    var end = limit;
    while (end > 0 and (text[end] & 0xC0) == 0x80) end -= 1;
    if (std.mem.lastIndexOfScalar(u8, text[0..end], '\n')) |newline| {
        if (newline + 1 >= limit / 2) end = newline + 1;
    }
    return text[0..end];
}

// ─── 单测 ────────────────────────────────────────────────────────────────

const Fixture = struct {
    texts: []const []const u8,
    calls: usize = 0,
    budgets: [16]usize = @splat(0),
    queries: [16]Query = undefined,
    /// 分页：每页 2 项，修订号固定为 `revision`。
    pages: ?[]const []const u8 = null,
    revision: u64 = 7,
    fn summary(raw: *anyopaque, index: usize, query: Query, allocator: std.mem.Allocator) anyerror!Summary {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.budgets[self.calls] = query.budget_bytes;
        self.queries[self.calls] = query;
        self.calls += 1;
        if (self.pages) |items| if (query.limit != null or query.cursor != null) {
            const start: usize = if (query.cursor) |cursor| blk: {
                if (cursor.revision != self.revision) return error.SnapshotChanged;
                break :blk @intCast(cursor.offset);
            } else 0;
            const end = @min(items.len, start + (query.limit orelse 2));
            var text: std.ArrayList(u8) = .empty;
            for (items[start..end]) |item| try text.print(allocator, "{s}\n", .{item});
            return .{ .text = text.items, .next_offset = if (end < items.len) end else null, .revision = self.revision };
        };
        return .{ .text = try allocator.dupe(u8, self.texts[index]) };
    }
};
const terminal_params: Params = .{ .max_lines = "the most recent N output lines", .limit = "the most recent N shell commands" };
fn testCard(ref: []const u8, available: bool) Card {
    return .{ .card_ref = ref, .card_type = "terminal", .title = "本机", .protocol = "local", .placement = .standalone_tab, .available = available, .detail_tools = &.{ "host.read_terminal", "host.search_terminal" }, .params = terminal_params };
}

test "tab context golden: single card tab returns one structured entry" {
    const a = std.testing.allocator;
    var fixture: Fixture = .{ .texts = &.{"$ make\nok\n"} };
    const cards = [_]Card{testCard("s1:aa:1:1", true)};
    const body = try assemble(a, .{}, .{ .context = &fixture, .cards = &cards, .summary = Fixture.summary }, 16384, false);
    defer a.free(body);
    try std.testing.expectEqualStrings("{\"tab\":{\"kind\":\"single\",\"card_count\":1},\"cards\":[{\"card_ref\":\"s1:aa:1:1\",\"card_type\":\"terminal\",\"title\":\"本机\",\"protocol\":\"local\",\"placement\":\"standalone_tab\",\"available\":true,\"unavailable_reason\":null,\"pinned\":false,\"summary\":\"$ make\\nok\\n\",\"truncated\":false,\"next_cursor\":null,\"params\":[\"max_lines\",\"limit\"],\"detail_tools\":[\"host.read_terminal\",\"host.search_terminal\"]}],\"max_bytes\":8192,\"truncated\":false,\"hint\":null}", body);
}

test "tab context split tab lists unavailable cards, orders the pin first and splits the budget" {
    const a = std.testing.allocator;
    var fixture: Fixture = .{ .texts = &.{ "one", "two", "three" } };
    var cards = [_]Card{ testCard("r1", true), testCard("r2", false), testCard("r3", true) };
    cards[1].unavailable_reason = "terminal ended (EOF)";
    cards[2].pinned = true;
    for (&cards) |*card| card.placement = .split;
    const body = try assemble(a, .{ .max_bytes = 4096 }, .{ .context = &fixture, .cards = &cards, .summary = Fixture.summary }, 16384, true);
    defer a.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
    defer parsed.deinit();
    const list = parsed.value.object.get("cards").?.array.items;
    try std.testing.expectEqualStrings("split", parsed.value.object.get("tab").?.object.get("kind").?.string);
    try std.testing.expectEqualStrings("r3", list[0].object.get("card_ref").?.string);
    try std.testing.expectEqualStrings("r1", list[1].object.get("card_ref").?.string);
    try std.testing.expect(!list[2].object.get("available").?.bool and list[2].object.get("summary").? == .null);
    try std.testing.expectEqualStrings("terminal ended (EOF)", list[2].object.get("unavailable_reason").?.string);
    // 只有可用卡片取摘要，两张平均分到同样的预算。
    try std.testing.expectEqual(@as(usize, 2), fixture.calls);
    try std.testing.expectEqual(fixture.budgets[0], fixture.budgets[1]);
}

test "tab context budget takes the smaller of max_bytes and the global budget and marks truncation" {
    const a = std.testing.allocator;
    const long_array = comptime blk: {
        const filler: [3000]u8 = @splat('x');
        break :blk filler ++ "\nlatest line\n".*;
    };
    const long: []const u8 = &long_array;
    var fixture: Fixture = .{ .texts = &.{long} };
    const cards = [_]Card{testCard("r1", true)};
    const body = try assemble(a, .{ .max_bytes = 65536 }, .{ .context = &fixture, .cards = &cards, .summary = Fixture.summary }, 1024, false);
    defer a.free(body);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, body, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 1024), parsed.value.object.get("max_bytes").?.integer);
    const entry = parsed.value.object.get("cards").?.array.items[0].object;
    try std.testing.expect(entry.get("truncated").?.bool and parsed.value.object.get("truncated").?.bool);
    try std.testing.expect(std.mem.endsWith(u8, entry.get("summary").?.string, "latest line\n"));
    try std.testing.expect(entry.get("summary").?.string.len < 1024);
    try std.testing.expect(parsed.value.object.get("hint").? == .string);
    // max_bytes 小于全局预算时取 max_bytes。
    var small: Fixture = .{ .texts = &.{long} };
    const narrow = try assemble(a, .{ .max_bytes = 512 }, .{ .context = &small, .cards = &cards, .summary = Fixture.summary }, 16384, false);
    defer a.free(narrow);
    try std.testing.expect(std.mem.indexOf(u8, narrow, "\"max_bytes\":512") != null);
}

test "tab context card_refs select cards and reject references outside the tab" {
    const a = std.testing.allocator;
    var fixture: Fixture = .{ .texts = &.{ "one", "two" } };
    const cards = [_]Card{ testCard("r1", true), testCard("r2", true) };
    const source: Source = .{ .context = &fixture, .cards = &cards, .summary = Fixture.summary };
    const body = try assemble(a, .{ .card_refs = &.{"r2"} }, source, 16384, true);
    defer a.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"r2\"") != null and std.mem.indexOf(u8, body, "\"r1\"") == null);
    try std.testing.expectError(error.CardNotInTab, assemble(a, .{ .card_refs = &.{"r9"} }, source, 16384, true));
    try std.testing.expectError(error.InvalidArguments, assemble(a, .{ .card_refs = &.{ "r1", "r1" } }, source, 16384, true));
}

test "tab context tool definition follows the ToolDef conventions and rejects unknown parameters" {
    const Noop = struct {
        fn call(_: *anyopaque, _: tool_def.Call, _: std.mem.Allocator) anyerror!tool_def.Output {
            return .{};
        }
    };
    var context: u8 = 0;
    const def = definition(.{ .context = &context, .call = Noop.call });
    try tool_def.checkConventions(def);
    try std.testing.expect(def.approval == .read_only and def.effect == .read_state and def.target == .tab);
    const pipeline = @import("tool_pipeline.zig");
    try std.testing.expectError(error.InvalidToolArguments, pipeline.parseArguments(std.testing.allocator, def.input_schema, def.budget.max_argument_bytes, null, "{\"history\":10}"));
    try std.testing.expectError(error.InvalidToolArguments, pipeline.parseArguments(std.testing.allocator, def.input_schema, def.budget.max_argument_bytes, null, "{\"max_bytes\":70000}"));
    // 保留参数的形状与 `tool_def.reserved_parameters` 一致；next_cursor 只出现在结果里，作为参数被拒绝。
    try std.testing.expectError(error.InvalidToolArguments, pipeline.parseArguments(std.testing.allocator, def.input_schema, def.budget.max_argument_bytes, null, "{\"next_cursor\":\"tc1.0.0.0\"}"));
    try std.testing.expectError(error.InvalidToolArguments, pipeline.parseArguments(std.testing.allocator, def.input_schema, def.budget.max_argument_bytes, null, "{\"max_lines\":501}"));
    try std.testing.expectError(error.InvalidToolArguments, pipeline.parseArguments(std.testing.allocator, def.input_schema, def.budget.max_argument_bytes, null, "{\"limit\":0}"));
    try std.testing.expectError(error.InvalidToolArguments, pipeline.parseArguments(std.testing.allocator, def.input_schema, def.budget.max_argument_bytes, null, "{\"cursor\":\"\"}"));
    var query = try pipeline.parseArguments(std.testing.allocator, def.input_schema, def.budget.max_argument_bytes, null, "{\"max_lines\":40,\"limit\":5,\"cursor\":\"tc1.00.1.2\"}");
    defer query.deinit();
    const parsed_query = try parseRequest(std.testing.allocator, query.value);
    try std.testing.expect(parsed_query.max_lines.? == 40 and parsed_query.limit.? == 5 and std.mem.eql(u8, parsed_query.cursor.?, "tc1.00.1.2") and parsed_query.hasQuery());
    var ok = try pipeline.parseArguments(std.testing.allocator, def.input_schema, def.budget.max_argument_bytes, null, "{\"card_refs\":[\"r1\"],\"max_bytes\":100}");
    defer ok.deinit();
    const request = try parseRequest(std.testing.allocator, ok.value);
    defer std.testing.allocator.free(request.card_refs.?);
    try std.testing.expectEqual(@as(usize, 100), request.max_bytes);
}

test "tab context query parameters reach the card type and unsupported ones fail with an actionable hint" {
    const a = std.testing.allocator;
    var fixture: Fixture = .{ .texts = &.{ "term", "kvm" } };
    var cards = [_]Card{ testCard("t1", true), testCard("k1", true) };
    cards[1].card_type = "kvm";
    cards[1].params = .{ .note = "KVM cards only return metadata (no pixels); use describe_frame or screenshot for the picture." };
    cards[0].placement = .split;
    cards[1].placement = .split;
    const source: Source = .{ .context = &fixture, .cards = &cards, .summary = Fixture.summary };
    // 所有选中卡片都会收到参数；KVM 不支持 max_lines，整个调用被拒绝并给出提示。
    var buffer: [512]u8 = undefined;
    var diagnostic: Diagnostic = .{ .buffer = &buffer };
    try std.testing.expectError(error.UnsupportedParameter, validateParams(a, .{ .max_lines = 20 }, &cards, &diagnostic));
    const hint = diagnostic.text().?;
    try std.testing.expect(std.mem.indexOf(u8, hint, "k1 (kvm) does not support max_lines") != null);
    try std.testing.expect(std.mem.indexOf(u8, hint, "accepts no query parameters") != null);
    try std.testing.expect(std.mem.indexOf(u8, hint, "only return metadata") != null);
    try std.testing.expect(std.mem.indexOf(u8, hint, "Cards that support max_lines: t1 (terminal)") != null);
    try std.testing.expectError(error.UnsupportedParameter, assemble(a, .{ .max_lines = 20 }, source, 16384, true));
    // 只选支持的卡片：参数原样交给卡片类型的实现。
    const body = try assemble(a, .{ .card_refs = &.{"t1"}, .max_lines = 20, .limit = 3 }, source, 16384, true);
    defer a.free(body);
    try std.testing.expectEqual(@as(usize, 1), fixture.calls);
    try std.testing.expect(fixture.queries[0].max_lines.? == 20 and fixture.queries[0].limit.? == 3 and fixture.queries[0].cursor == null);
    // 不带参数时实现收到的是空查询（与 M11 相同的默认摘要），条目列出每张卡片支持的参数。
    const plain = try assemble(a, .{}, source, 16384, true);
    defer a.free(plain);
    try std.testing.expect(!fixture.queries[1].any() and !fixture.queries[2].any());
    try std.testing.expect(std.mem.indexOf(u8, plain, "\"params\":[\"max_lines\",\"limit\"]") != null and std.mem.indexOf(u8, plain, "\"params\":[]") != null);
}

test "tab context cursor pages one card, is bound to it and rejects a changed listing" {
    const a = std.testing.allocator;
    var fixture: Fixture = .{ .texts = &.{ "dir", "term" }, .pages = &.{ "a", "b", "c", "d", "e" } };
    var cards = [_]Card{ testCard("f1", true), testCard("t1", true) };
    cards[0].card_type = "file";
    cards[0].params = .{ .limit = "at most N directory entries", .cursor = "continue the directory listing" };
    const source: Source = .{ .context = &fixture, .cards = &cards, .summary = Fixture.summary };
    const first = try assemble(a, .{ .card_refs = &.{"f1"}, .limit = 2 }, source, 16384, true);
    defer a.free(first);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, first, .{});
    defer parsed.deinit();
    const entry = parsed.value.object.get("cards").?.array.items[0].object;
    try std.testing.expectEqualStrings("a\nb\n", entry.get("summary").?.string);
    const next = entry.get("next_cursor").?.string;
    // 游标单独使用即可定位到它的卡片；给出的就是下一页。
    const second = try assemble(a, .{ .cursor = next, .limit = 2 }, source, 16384, true);
    defer a.free(second);
    try std.testing.expect(std.mem.indexOf(u8, second, "\"summary\":\"c\\nd\\n\"") != null and std.mem.indexOf(u8, second, "\"t1\"") == null);
    try std.testing.expectEqual(@as(u64, 2), fixture.queries[1].cursor.?.offset);
    // 游标配了别的卡片、或配了多张卡片：拒绝并指出它属于哪张。
    var buffer: [512]u8 = undefined;
    var diagnostic: Diagnostic = .{ .buffer = &buffer };
    try std.testing.expectError(error.InvalidCursor, validateParams(a, .{ .cursor = next, .card_refs = &.{"t1"} }, &cards, &diagnostic));
    try std.testing.expect(std.mem.indexOf(u8, diagnostic.text().?, "cursor belongs to card f1") != null);
    try std.testing.expectError(error.InvalidCursor, validateParams(a, .{ .cursor = "tc1.zz.1.1" }, &cards, null));
    try std.testing.expectError(error.InvalidCursor, validateParams(a, .{ .cursor = "something" }, &cards, null));
    // 终端卡片不支持 cursor。
    var t_cursor_buffer: [128]u8 = undefined;
    const t_cursor = try (Cursor{ .card = Cursor.forCard("t1"), .offset = 1, .revision = 1 }).encode(&t_cursor_buffer);
    try std.testing.expectError(error.UnsupportedParameter, validateParams(a, .{ .cursor = t_cursor }, &cards, null));
    // 列表已变化：游标的修订号对不上，整个调用返回 SnapshotChanged。
    fixture.revision = 8;
    try std.testing.expectError(error.SnapshotChanged, assemble(a, .{ .cursor = next }, source, 16384, true));
    // 最后一页没有 next_cursor。
    fixture.revision = 7;
    var last_buffer: [128]u8 = undefined;
    const last_cursor = try (Cursor{ .card = Cursor.forCard("f1"), .offset = 4, .revision = 7 }).encode(&last_buffer);
    const last = try assemble(a, .{ .cursor = last_cursor }, source, 16384, true);
    defer a.free(last);
    try std.testing.expect(std.mem.indexOf(u8, last, "\"next_cursor\":null") != null);
}
