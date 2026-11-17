//! 窗口级通知的 view-model（NATIVE_AUDIT 清单 4“Notification / Toast”）。
//!
//! 每个应用窗口两个 zenit 原生通知栈（`view/toast_stack.yix` 里的两个 `<W.NotificationHost>`），按用途分两条通道。
//! 分流规则只有一处，即本文件的纯函数 `laneFor`（用户判定）：**不带动作的成功或信息类消息走中下方轻提示，带动作或
//! 需要处理（警告、失败、待处理）的走右上角卡片**。
//!
//! - **卡片**（`cards`，右上角）：要用户处理、带动作 / 详情 / 生命条的卡片。
//!   - 全局提醒（协调器 `visibleNotifications` 每窗口一条）：协调器只在窗口里呈现待处理（`requires_action` 且
//!     `time_sensitive`、未解决）或操作失败（`operation_failed`）的事实，按 `laneFor` 都是“需要处理”，所以全部是卡片。
//!     固定一个原生 id（`banner_id`），换一条事实或同一事实改版本时就地转换（与旧实现复用卡片节点一致，不重放入场）。
//!     倒计时由原生生命条承担：时长取协调器给这条事实的剩余时间（4 秒，有动作 8 秒），显示期间协调器侧保持暂停，
//!     到期 / 关闭 / 点动作经 `Ports.cards.banner` 回到宿主。
//!   - 命令失败提示（终端）：一张卡片（“询问 AI”动作、8 秒），事件经 `showCommand` 登记的回调交回终端视图。
//! - **轻提示**（`toasts`，中下方，zenit 默认位置）：`notice`，一条原生文字提示（hint），原生默认 2 秒。
//!   - 本地回执（`acknowledgeAt`：已复制、目录已刷新）：成功标记。
//!   - 插件 / 内置内容的无动作反馈（窗口宿主的 `publishFeedback`）：信息样式。
//!   - 撤销提示（`undoToast`，`shared/ui/confirm` 的 `undoable`）：带“撤销”按钮的原生文字提示（原生默认 4 秒）。
//!     用户判定的“可撤销操作直接执行并弹带撤销的 Toast”就是它：它是本地操作的回执，所以和回执同栈（中下方），
//!     不按 `laneFor` 的“带动作走卡片”分流（那条规则管的是协调器的提醒）。结局经 `Ports.toasts.undo` 回报：
//!     点“撤销” = 回滚；到期、被关掉、被挤出或收起 = 提交。
//!
//! 视图只把两条通道各自原样换成 `NotificationPost`，不做判断。
//!
//! 层级与遮挡：两个栈都是 zenit 的 toast 层（overlay_stack 的 toast tier，挂在窗口浮层根上），高于宿主的弹出菜单 /
//! 面板（overlay tier）、对话框（dialog tier）以及整棵应用树。宿主算出右上角是否被设置面板 / 进度面板等浮层盖住，
//! 只用于卡片栈的 `suppressed`（原生栈整体隐藏、计时保持；只在有提醒时隐藏，操作失败 `host.operation_error` 例外、
//! 照常显示在浮层之上）。中下方轻提示栈**永远显示在最上层**：被浮层盖住时既不隐藏也不暂停计时（用户判定：传输
//! 管理器、文件右键菜单里“复制路径”的反馈要立刻可见），宿主也不为它算遮挡。悬停 / 焦点暂停是各栈原生自己的。
//!
//! 请求与 zenit 的 `NotificationPost` 同形（`seq` 每次加一）；字符串由本文件持有（每条通道双缓冲：新请求写入另一块，
//! 信号换值后再释放旧块），原生栈在收到请求时复制。只使用 zenit 的响应式子集。
const std = @import("std");
const ui = @import("ui");

pub const Tone = enum { info, success, warning, failure };

/// 两个原生栈：右上角卡片栈、中下方轻提示栈。
pub const Lane = enum { cards, toasts };

/// 分流时只看的三件事。
pub const Message = struct {
    tone: Tone,
    /// 消息带的动作按钮数。
    actions: usize = 0,
    /// 需要用户处理（待处理、失败 / 结果未知），即使没有动作按钮。
    needs_attention: bool = false,
};

/// 分流规则（纯函数，全应用唯一一处）：不带动作的成功或信息类消息走中下方轻提示；带动作或需要处理的
/// （警告、失败、待处理）走右上角卡片。
pub fn laneFor(message: Message) Lane {
    if (message.actions != 0 or message.needs_attention) return .cards;
    return switch (message.tone) {
        .info, .success => .toasts,
        .warning, .failure => .cards,
    };
}

/// 原生卡片最多三个动作（上游 G50）。
pub const max_actions = 3;

/// 原生栈里的 id 分区：协调器事实只占一个固定 id；命令失败提示、轻提示各用一段，互不相撞（两栈各自计 id，
/// 分区只为日志与测试好认）。
pub const banner_id: u64 = 1;
const notice_base: u64 = 1 << 62;
const command_base: u64 = 1 << 61;
const tip_base: u64 = 1 << 60;
const undo_base: u64 = 1 << 59;

/// 撤销提示按钮的文案。
pub const undo_label = "撤销";

pub const Kind = enum { banner, command };

/// 一张卡片的请求（视图按 `kind` 配 test_id）。
pub const Card = struct {
    id: u64,
    kind: Kind,
    tone: Tone = .info,
    title: []const u8,
    body: []const u8 = "",
    detail: []const u8 = "",
    detail_expanded: bool = false,
    actions: [max_actions][]const u8 = .{ "", "", "" },
    action_count: u8 = 0,
    duration_ms: u32,

    fn owned(self: Card, a: std.mem.Allocator) !Card {
        var copy = self;
        copy.title = try a.dupe(u8, self.title);
        copy.body = try a.dupe(u8, self.body);
        copy.detail = try a.dupe(u8, self.detail);
        for (copy.actions[0..self.action_count], self.actions[0..self.action_count]) |*dst, src| dst.* = try a.dupe(u8, src);
        return copy;
    }
};

/// 一条轻提示（原生文字提示；成功带成功标记，信息不带标记）。
/// `tip`：窗口自己的一次性使用提示（例如首次窄窗口时“可以收起侧栏”），视图给它单独的 test_id；`duration_ms` 为空时用原生默认时长。
pub const Notice = struct { id: u64, text: []const u8, tone: Tone = .success, tip: bool = false, duration_ms: ?u32 = null, undo: bool = false };

/// 卡片通道（右上角）的请求。
pub const CardOp = union(enum) {
    none,
    card: Card,
    dismiss: u64,

    fn owned(self: CardOp, a: std.mem.Allocator) !CardOp {
        return switch (self) {
            .none, .dismiss => self,
            .card => |c| .{ .card = try c.owned(a) },
        };
    }
};

/// 轻提示通道（中下方）的请求。
pub const ToastOp = union(enum) {
    none,
    notice: Notice,
    dismiss: u64,

    fn owned(self: ToastOp, a: std.mem.Allocator) !ToastOp {
        return switch (self) {
            .none, .dismiss => self,
            .notice => |n| .{ .notice = .{ .id = n.id, .text = try a.dupe(u8, n.text), .tone = n.tone, .tip = n.tip, .duration_ms = n.duration_ms, .undo = n.undo } },
        };
    }
};

/// 一次请求；`seq` 相同表示已处理。
pub fn Ask(comptime Op: type) type {
    return struct { seq: u64 = 0, op: Op = .none };
}
pub const CardAsk = Ask(CardOp);
pub const ToastAsk = Ask(ToastOp);

/// 原生栈回报的事件（视图把 zenit 的事件换成它）。
pub const Event = struct {
    id: u64,
    kind: enum { action, dismissed, expired, removed, other },
    index: u8 = 0,
};

/// 全局提醒卡片的回报：宿主据此更新协调器（关闭 / 到期 / 执行动作）。
pub const BannerEvent = union(enum) { dismissed: u64, expired: u64, action: struct { fact_id: u64, index: u8 } };
/// 命令失败提示的回报（终端视图）。
pub const CommandEvent = enum { dismissed, expired, action };

/// 卡片通道（右上角）的回报。轻提示没有回报：它们不对应宿主状态，离场不用处理。
pub const CardPorts = struct {
    banner: ?*const fn (context: ?*anyopaque, event: BannerEvent) void = null,
};

/// 撤销提示的结局：点“撤销” = `.revert`；到期、关掉、挤出、收起 = `.commit`。
pub const UndoOutcome = enum { revert, commit };

/// 轻提示通道（中下方）的回报：只有撤销提示有。
pub const ToastPorts = struct {
    undo: ?*const fn (context: ?*anyopaque, id: u64, outcome: UndoOutcome) void = null,
};

pub const Ports = struct {
    context: ?*anyopaque = null,
    cards: CardPorts = .{},
    toasts: ToastPorts = .{},
};

/// 协调器当前给本窗口的一条事实（宿主每帧投影；字符串只在调用期间有效）。
pub const Fact = struct {
    fact_id: u64,
    revision: u64,
    owner_ended: bool = false,
    tone: Tone,
    title: []const u8,
    /// 来源一行（会话 · 对象）。
    source: []const u8 = "",
    /// 标题与来源之外的详情；失败默认展开。
    detail: []const u8 = "",
    failure: bool = false,
    actions: []const []const u8 = &.{},
    remaining_ms: u64,
    /// 操作失败：被浮层遮挡时也照常显示。
    above_overlays: bool = false,
};

const CommandSlot = struct {
    id: u64,
    context: *anyopaque,
    callback: *const fn (context: *anyopaque, event: CommandEvent) void,
};

/// 一条通道：请求信号、遮挡信号（只有卡片栈接）、请求序号，以及持有请求字符串的双缓冲。
fn Channel(comptime Op: type) type {
    return struct {
        const Self = @This();
        post: ?*ui.Signal(Ask(Op)) = null,
        suppressed: ?*ui.Signal(bool) = null,
        seq: u64 = 0,
        arenas: [2]std.heap.ArenaAllocator,
        current: u1 = 0,

        fn init(allocator: std.mem.Allocator) Self {
            return .{ .arenas = .{ std.heap.ArenaAllocator.init(allocator), std.heap.ArenaAllocator.init(allocator) } };
        }

        fn attach(self: *Self, scope: *ui.Scope) !void {
            self.post = try scope.createSignal(Ask(Op), .{ .seq = self.seq });
            self.suppressed = try scope.createSignal(bool, false);
        }

        fn deinit(self: *Self) void {
            for (&self.arenas) |*arena| arena.deinit();
        }

        fn ask(self: *const Self) Ask(Op) {
            const signal = self.post orelse return .{};
            return signal.get();
        }

        fn isSuppressed(self: *const Self) bool {
            const signal = self.suppressed orelse return false;
            return signal.get();
        }

        fn setSuppressed(self: *Self, on: bool) void {
            const signal = self.suppressed orelse return;
            signal.set(on);
        }

        fn send(self: *Self, op: Op) !void {
            const next: u1 = self.current ^ 1;
            const arena = &self.arenas[next];
            _ = arena.reset(.retain_capacity);
            const owned = try op.owned(arena.allocator());
            self.seq +%= 1;
            self.current = next;
            if (self.post) |signal| signal.set(.{ .seq = self.seq, .op = owned });
        }
    };
}

pub const ViewModel = struct {
    allocator: std.mem.Allocator,
    ports: Ports = .{},
    /// 右上角卡片栈：全局提醒、命令失败提示。
    cards: Channel(CardOp),
    /// 中下方轻提示栈：本地回执、无动作反馈。永远在最上层，不随遮挡隐藏。
    toasts: Channel(ToastOp),
    shown: ?Shown = null,
    notice_seq: u64 = 0,
    command_seq: u64 = 0,
    tip_seq: u64 = 0,
    undo_seq: u64 = 0,
    commands: std.ArrayList(CommandSlot) = .empty,

    const Shown = struct { fact_id: u64, revision: u64, owner_ended: bool, above_overlays: bool };

    pub fn init(allocator: std.mem.Allocator, ports: Ports) ViewModel {
        return .{ .allocator = allocator, .ports = ports, .cards = Channel(CardOp).init(allocator), .toasts = Channel(ToastOp).init(allocator) };
    }

    /// 信号建在视图 scope 上（窗口销毁时随 scope 释放）。
    pub fn attach(self: *ViewModel, scope: *ui.Scope) !void {
        try self.cards.attach(scope);
        try self.toasts.attach(scope);
    }

    pub fn deinit(self: *ViewModel) void {
        self.commands.deinit(self.allocator);
        self.cards.deinit();
        self.toasts.deinit();
    }

    // ---- 选择器（模板读） ----

    pub fn cardAsk(self: *const ViewModel) CardAsk {
        return self.cards.ask();
    }

    pub fn toastAsk(self: *const ViewModel) ToastAsk {
        return self.toasts.ask();
    }

    pub fn cardsSuppressed(self: *const ViewModel) bool {
        return self.cards.isSuppressed();
    }

    /// 当前显示的全局提醒（测试与宿主用）。
    pub fn shownFact(self: *const ViewModel) ?u64 {
        return if (self.shown) |s| s.fact_id else null;
    }

    // ---- 宿主每帧投影（卡片通道） ----

    /// 把协调器给本窗口的事实（至多一条）同步到卡片栈：没有了就收起，换了 / 改版本就就地转换。
    /// 返回需要在协调器侧保持暂停的事实（原生栈在计时）。
    pub fn sync(self: *ViewModel, fact: ?Fact) !?u64 {
        const value = fact orelse {
            if (self.shown != null) {
                self.shown = null;
                try self.cards.send(.{ .dismiss = banner_id });
            }
            return null;
        };
        const changed = if (self.shown) |s| s.fact_id != value.fact_id or s.revision != value.revision or s.owner_ended != value.owner_ended else true;
        if (changed) {
            var card: Card = .{
                .id = banner_id,
                .kind = .banner,
                .tone = value.tone,
                .title = value.title,
                .body = value.source,
                .detail = value.detail,
                .detail_expanded = value.failure,
                .duration_ms = @intCast(@min(value.remaining_ms, std.math.maxInt(u32))),
            };
            for (value.actions[0..@min(value.actions.len, max_actions)], 0..) |label, i| card.actions[i] = label;
            card.action_count = @intCast(@min(value.actions.len, max_actions));
            self.shown = .{ .fact_id = value.fact_id, .revision = value.revision, .owner_ended = value.owner_ended, .above_overlays = value.above_overlays };
            try self.cards.send(.{ .card = card });
        }
        return value.fact_id;
    }

    /// 宿主算出的卡片栈遮挡（右上角被浮层盖住）。只在有提醒时隐藏；操作失败照常显示。
    pub fn setCardsCovered(self: *ViewModel, covered: bool) void {
        const above = if (self.shown) |s| s.above_overlays else false;
        self.cards.setSuppressed(covered and self.shown != null and !above);
    }

    // ---- 命令失败提示（卡片通道） ----

    /// 命令失败提示：登记回报对象，弹出卡片，返回卡片 id（之后用 `dismissCommand`）。
    pub fn showCommand(self: *ViewModel, context: *anyopaque, callback: *const fn (*anyopaque, CommandEvent) void, card_template: Card) !u64 {
        self.command_seq +%= 1;
        const id = command_base | (self.command_seq & (command_base - 1));
        try self.commands.append(self.allocator, .{ .id = id, .context = context, .callback = callback });
        errdefer _ = self.commands.pop();
        var card = card_template;
        card.id = id;
        card.kind = .command;
        try self.cards.send(.{ .card = card });
        return id;
    }

    pub fn dismissCommand(self: *ViewModel, id: u64) void {
        if (!self.forgetCommand(id)) return;
        self.cards.send(.{ .dismiss = id }) catch {};
    }

    /// 终端视图销毁时撤销登记（卡片也收起）。
    pub fn releaseCommands(self: *ViewModel, context: *anyopaque) void {
        var i: usize = 0;
        while (i < self.commands.items.len) {
            const slot = self.commands.items[i];
            if (slot.context != context) {
                i += 1;
                continue;
            }
            _ = self.commands.orderedRemove(i);
            self.cards.send(.{ .dismiss = slot.id }) catch {};
        }
    }

    fn forgetCommand(self: *ViewModel, id: u64) bool {
        for (self.commands.items, 0..) |slot, i| if (slot.id == id) {
            _ = self.commands.orderedRemove(i);
            return true;
        };
        return false;
    }

    // ---- 一次性使用提示（轻提示通道） ----

    /// 一条信息类、不带动作的使用提示（原生文字提示，一行）。按 `laneFor` 不带动作的信息类走中下方轻提示栈
    /// （design-r3 稿 2 的首次窄窗口提示，r3-tabs-toolbar 从右上角卡片栈改过来）：不随浮层遮挡隐藏，到时自己离场，
    /// 没有回报。返回提示 id。
    pub fn tip(self: *ViewModel, text: []const u8, duration_ms: u32) !u64 {
        std.debug.assert(laneFor(.{ .tone = .info }) == .toasts);
        if (text.len == 0) return error.EmptyTip;
        self.tip_seq +%= 1;
        const id = tip_base | (self.tip_seq & (tip_base - 1));
        try self.toasts.send(.{ .notice = .{ .id = id, .text = text, .tone = .info, .tip = true, .duration_ms = duration_ms } });
        return id;
    }

    // ---- 轻提示（轻提示通道） ----

    /// 一条不带动作的成功 / 信息类文字提示（本地回执、插件的无动作反馈）。只接受 `laneFor` 判给轻提示栈的语气：
    /// 警告、失败要用卡片，由调用方走协调器。
    pub fn notice(self: *ViewModel, tone: Tone, text: []const u8) !void {
        if (laneFor(.{ .tone = tone }) != .toasts) return error.NoticeNeedsCard;
        if (text.len == 0) return;
        self.notice_seq +%= 1;
        const id = notice_base | (self.notice_seq & (notice_base - 1));
        try self.toasts.send(.{ .notice = .{ .id = id, .text = text, .tone = tone } });
    }

    /// 本地回执：一条成功文字提示。
    pub fn receipt(self: *ViewModel, text: []const u8) !void {
        return self.notice(.success, text);
    }

    /// 撤销提示：一条带“撤销”的成功文字提示（`shared/ui/confirm` 的 `undoable`）。返回提示 id，结局按它回报。
    pub fn undoToast(self: *ViewModel, text: []const u8) !u64 {
        if (text.len == 0) return error.EmptyUndoText;
        self.undo_seq +%= 1;
        const id = undo_base | (self.undo_seq & (undo_base - 1));
        try self.toasts.send(.{ .notice = .{ .id = id, .text = text, .tone = .success, .undo = true } });
        return id;
    }

    pub fn isUndoToast(id: u64) bool {
        return id >= undo_base and id < tip_base;
    }

    // ---- 原生栈的回报 ----

    /// 轻提示栈（中下方）的回报：只有撤销提示要结局，其余轻提示离场不用处理。
    pub fn toastNotified(self: *ViewModel, event: Event) void {
        if (!isUndoToast(event.id)) return;
        const outcome: UndoOutcome = switch (event.kind) {
            .action => .revert,
            .dismissed, .expired, .removed => .commit,
            .other => return,
        };
        if (self.ports.toasts.undo) |undo| undo(self.ports.context, event.id, outcome);
    }

    /// 卡片栈（右上角）的回报。
    pub fn cardNotified(self: *ViewModel, event: Event) void {
        if (event.id == banner_id) {
            const shown = self.shown orelse return;
            const out: BannerEvent = switch (event.kind) {
                .dismissed => .{ .dismissed = shown.fact_id },
                .expired => .{ .expired = shown.fact_id },
                .action => .{ .action = .{ .fact_id = shown.fact_id, .index = event.index } },
                .removed, .other => return,
            };
            // 原生卡片已离场（关闭 / 到期）；点动作后由本文件收起。下一帧协调器给出新的事实时重新转换。
            if (event.kind != .action) self.shown = null;
            if (self.ports.cards.banner) |banner| banner(self.ports.context, out);
            if (event.kind == .action and self.shown != null) {
                self.shown = null;
                self.cards.send(.{ .dismiss = banner_id }) catch {};
            }
            return;
        }
        for (self.commands.items, 0..) |slot, i| if (slot.id == event.id) {
            const out: CommandEvent = switch (event.kind) {
                .dismissed => .dismissed,
                .expired => .expired,
                .action => .action,
                .removed, .other => return,
            };
            _ = self.commands.orderedRemove(i);
            if (out == .action) self.cards.send(.{ .dismiss = slot.id }) catch {};
            slot.callback(slot.context, out);
            return;
        };
    }

};

// ---- Tests ----

const testing = std.testing;

const Probe = struct {
    events: std.ArrayList(BannerEvent) = .empty,
    commands: std.ArrayList(CommandEvent) = .empty,
    fn banner(raw: ?*anyopaque, event: BannerEvent) void {
        const self: *Probe = @ptrCast(@alignCast(raw.?));
        self.events.append(testing.allocator, event) catch {};
    }
    fn command(raw: *anyopaque, event: CommandEvent) void {
        const self: *Probe = @ptrCast(@alignCast(raw));
        self.commands.append(testing.allocator, event) catch {};
    }
    fn ports(self: *Probe) Ports {
        return .{ .context = self, .cards = .{ .banner = banner } };
    }
    fn deinit(self: *Probe) void {
        self.events.deinit(testing.allocator);
        self.commands.deinit(testing.allocator);
    }
};

test "notification toast view-model: one banner id morphs between facts and revisions, dismisses when empty" {
    const cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    var probe: Probe = .{};
    defer probe.deinit();
    var vm = ViewModel.init(testing.allocator, probe.ports());
    defer vm.deinit();
    try vm.attach(scope);
    var title = "连接已断开".*;
    const first: Fact = .{ .fact_id = 7, .revision = 1, .tone = .warning, .title = &title, .source = "prod-web-01", .detail = "连接超时", .actions = &.{"查看来源"}, .remaining_ms = 8000 };
    try testing.expectEqual(@as(?u64, 7), try vm.sync(first));
    const a1 = vm.cardAsk();
    try testing.expectEqual(@as(u64, 1), a1.seq);
    const card = a1.op.card;
    try testing.expectEqual(banner_id, card.id);
    try testing.expectEqualStrings("连接已断开", card.title);
    try testing.expectEqualStrings("prod-web-01", card.body);
    try testing.expectEqualStrings("连接超时", card.detail);
    try testing.expectEqual(@as(u8, 1), card.action_count);
    try testing.expectEqual(@as(u32, 8000), card.duration_ms);
    try testing.expect(!card.detail_expanded);
    // Owned copy: the caller's buffer may change.
    title[0] = 'X';
    try testing.expectEqualStrings("连接已断开", vm.cardAsk().op.card.title);
    // Same fact and revision: no new request.
    _ = try vm.sync(first);
    try testing.expectEqual(@as(u64, 1), vm.cardAsk().seq);
    var next = first;
    next.revision = 2;
    next.failure = true;
    next.tone = .failure;
    _ = try vm.sync(next);
    try testing.expectEqual(@as(u64, 2), vm.cardAsk().seq);
    try testing.expect(vm.cardAsk().op.card.detail_expanded);
    try testing.expectEqual(banner_id, vm.cardAsk().op.card.id);
    _ = try vm.sync(null);
    try testing.expectEqual(CardOp{ .dismiss = banner_id }, vm.cardAsk().op);
    try testing.expectEqual(@as(?u64, null), vm.shownFact());
    // Banners never touch the toast channel.
    try testing.expectEqual(@as(u64, 0), vm.toastAsk().seq);
}

test "notification toast view-model: banner events map to the shown fact; an action also dismisses" {
    const cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    var probe: Probe = .{};
    defer probe.deinit();
    var vm = ViewModel.init(testing.allocator, probe.ports());
    defer vm.deinit();
    try vm.attach(scope);
    _ = try vm.sync(.{ .fact_id = 3, .revision = 1, .tone = .info, .title = "t", .actions = &.{ "a", "b", "c" }, .remaining_ms = 8000 });
    try testing.expectEqual(@as(u8, 3), vm.cardAsk().op.card.action_count);
    vm.cardNotified(.{ .id = banner_id, .kind = .action, .index = 2 });
    try testing.expectEqual(BannerEvent{ .action = .{ .fact_id = 3, .index = 2 } }, probe.events.items[0]);
    try testing.expectEqual(CardOp{ .dismiss = banner_id }, vm.cardAsk().op);
    _ = try vm.sync(.{ .fact_id = 4, .revision = 1, .tone = .info, .title = "t", .remaining_ms = 4000 });
    vm.cardNotified(.{ .id = banner_id, .kind = .expired });
    try testing.expectEqual(BannerEvent{ .expired = 4 }, probe.events.items[1]);
    _ = try vm.sync(.{ .fact_id = 5, .revision = 1, .tone = .info, .title = "t", .remaining_ms = 4000 });
    vm.cardNotified(.{ .id = banner_id, .kind = .dismissed });
    try testing.expectEqual(BannerEvent{ .dismissed = 5 }, probe.events.items[2]);
    // An event without a shown fact is ignored.
    vm.cardNotified(.{ .id = banner_id, .kind = .dismissed });
    try testing.expectEqual(@as(usize, 3), probe.events.items.len);
}

test "notification toast view-model: covered suppresses only a shown non-operation-error banner" {
    const cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    var vm = ViewModel.init(testing.allocator, .{});
    defer vm.deinit();
    try vm.attach(scope);
    vm.setCardsCovered(true);
    try testing.expect(!vm.cardsSuppressed());
    _ = try vm.sync(.{ .fact_id = 1, .revision = 1, .tone = .info, .title = "t", .remaining_ms = 4000 });
    vm.setCardsCovered(true);
    try testing.expect(vm.cardsSuppressed());
    vm.setCardsCovered(false);
    try testing.expect(!vm.cardsSuppressed());
    _ = try vm.sync(.{ .fact_id = 2, .revision = 1, .tone = .failure, .failure = true, .title = "保存失败", .remaining_ms = 4000, .above_overlays = true });
    vm.setCardsCovered(true);
    try testing.expect(!vm.cardsSuppressed());
}

test "notification lane rule: actionless success / info goes to the bottom toast, actions or attention go to the corner card" {
    try testing.expectEqual(Lane.toasts, laneFor(.{ .tone = .success }));
    try testing.expectEqual(Lane.toasts, laneFor(.{ .tone = .info }));
    // Anything that needs handling is a card, with or without a button.
    try testing.expectEqual(Lane.cards, laneFor(.{ .tone = .warning }));
    try testing.expectEqual(Lane.cards, laneFor(.{ .tone = .failure }));
    try testing.expectEqual(Lane.cards, laneFor(.{ .tone = .info, .needs_attention = true }));
    try testing.expectEqual(Lane.cards, laneFor(.{ .tone = .success, .needs_attention = true }));
    // An action always makes it a card.
    try testing.expectEqual(Lane.cards, laneFor(.{ .tone = .success, .actions = 1 }));
    try testing.expectEqual(Lane.cards, laneFor(.{ .tone = .info, .actions = 3 }));
}

test "notification toast view-model: notices go to the toast channel, command cards to the card channel" {
    const cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    var probe: Probe = .{};
    defer probe.deinit();
    var vm = ViewModel.init(testing.allocator, .{});
    defer vm.deinit();
    try vm.attach(scope);
    try vm.receipt("路径已复制");
    try testing.expectEqual(@as(u64, 0), vm.cardAsk().seq);
    const r = vm.toastAsk().op.notice;
    try testing.expect(r.id != banner_id and r.id >= notice_base);
    try testing.expectEqual(Tone.success, r.tone);
    try testing.expectEqualStrings("路径已复制", r.text);
    // An empty notice is not a request.
    try vm.receipt("");
    try testing.expectEqual(@as(u64, 1), vm.toastAsk().seq);
    // Plugin feedback without an action: an info notice in the same stack.
    try vm.notice(.info, "已同步");
    try testing.expectEqual(Tone.info, vm.toastAsk().op.notice.tone);
    try testing.expect(vm.toastAsk().op.notice.id != r.id);
    // Warnings and failures need a card: the toast channel refuses them.
    try testing.expectError(error.NoticeNeedsCard, vm.notice(.failure, "失败"));
    try testing.expectError(error.NoticeNeedsCard, vm.notice(.warning, "注意"));
    try testing.expectEqual(@as(u64, 2), vm.toastAsk().seq);
    const id = try vm.showCommand(&probe, Probe.command, .{ .id = 0, .kind = .command, .tone = .failure, .title = "命令执行失败", .duration_ms = 8000, .actions = .{ "询问 AI", "", "" }, .action_count = 1 });
    try testing.expect(id != banner_id and id >= command_base and id < notice_base);
    try testing.expectEqual(Kind.command, vm.cardAsk().op.card.kind);
    try testing.expectEqual(@as(u64, 2), vm.toastAsk().seq);
    // The notice's string survives a card request (each channel owns its own buffers).
    try testing.expectEqualStrings("已同步", vm.toastAsk().op.notice.text);
    vm.cardNotified(.{ .id = id, .kind = .action });
    try testing.expectEqual(CommandEvent.action, probe.commands.items[0]);
    try testing.expectEqual(CardOp{ .dismiss = id }, vm.cardAsk().op);
    // Released after its event: a late event is ignored.
    vm.cardNotified(.{ .id = id, .kind = .dismissed });
    try testing.expectEqual(@as(usize, 1), probe.commands.items.len);
    const second = try vm.showCommand(&probe, Probe.command, .{ .id = 0, .kind = .command, .title = "x", .duration_ms = 8000 });
    vm.releaseCommands(&probe);
    try testing.expectEqual(CardOp{ .dismiss = second }, vm.cardAsk().op);
    try testing.expectEqual(@as(usize, 0), vm.commands.items.len);
}

test "notification toast view-model: only the card stack has a suppression; toasts are never suppressed" {
    const cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    var vm = ViewModel.init(testing.allocator, .{});
    defer vm.deinit();
    try vm.attach(scope);
    try vm.receipt("已复制");
    _ = try vm.sync(.{ .fact_id = 1, .revision = 1, .tone = .warning, .title = "t", .remaining_ms = 4000 });
    vm.setCardsCovered(true);
    try testing.expect(vm.cardsSuppressed());
    try testing.expect(!vm.toasts.isSuppressed());
    // The toast channel keeps sending while the card stack is hidden.
    try vm.notice(.info, "已同步");
    try testing.expectEqual(@as(u64, 2), vm.toastAsk().seq);
    try testing.expect(!vm.toasts.isSuppressed());
}

test "notification toast view-model: an undo toast is a bottom toast with 撤销; 撤销 reverts, any other exit commits" {
    const cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const Sink = struct {
        got: [8]struct { id: u64, outcome: UndoOutcome } = undefined,
        n: usize = 0,
        fn undo(raw: ?*anyopaque, id: u64, outcome: UndoOutcome) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.got[self.n] = .{ .id = id, .outcome = outcome };
            self.n += 1;
        }
    };
    var sink: Sink = .{};
    var vm = ViewModel.init(testing.allocator, .{ .context = &sink, .toasts = .{ .undo = Sink.undo } });
    defer vm.deinit();
    try vm.attach(scope);
    const a = try vm.undoToast("已删除主机 prod-web");
    try testing.expect(ViewModel.isUndoToast(a));
    // The corner card stack stays empty: an undo toast is a local receipt.
    try testing.expectEqual(@as(u64, 0), vm.cardAsk().seq);
    const n = vm.toastAsk().op.notice;
    try testing.expect(n.undo and !n.tip);
    try testing.expectEqualStrings("已删除主机 prod-web", n.text);
    vm.toastNotified(.{ .id = a, .kind = .action });
    const b = try vm.undoToast("已删除会话记录");
    vm.toastNotified(.{ .id = b, .kind = .expired });
    const c = try vm.undoToast("x");
    vm.toastNotified(.{ .id = c, .kind = .removed });
    const d = try vm.undoToast("y");
    vm.toastNotified(.{ .id = d, .kind = .dismissed });
    try testing.expectEqual(@as(usize, 4), sink.n);
    try testing.expectEqual(UndoOutcome.revert, sink.got[0].outcome);
    try testing.expectEqual(a, sink.got[0].id);
    for (sink.got[1..4]) |g| try testing.expectEqual(UndoOutcome.commit, g.outcome);
    // Plain notices report nothing.
    try vm.receipt("已复制");
    vm.toastNotified(.{ .id = vm.toastAsk().op.notice.id, .kind = .expired });
    try testing.expectEqual(@as(usize, 4), sink.n);
    try testing.expectError(error.EmptyUndoText, vm.undoToast(""));
}

test "notification toast view-model: a tip is a one-line info toast (no actions), never a card" {
    const cx = try ui.Cx.init(testing.allocator, testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    var vm = ViewModel.init(testing.allocator, .{});
    defer vm.deinit();
    try vm.attach(scope);
    const id = try vm.tip("窗口较窄，可以收起侧栏 · 点标题栏左侧的侧栏开关", 8000);
    try testing.expect(id >= tip_base and id < command_base);
    // laneFor: no actions + info -> the bottom-centre toast stack; the corner card stack stays empty.
    try testing.expectEqual(@as(u64, 0), vm.cardAsk().seq);
    const notice = vm.toastAsk().op.notice;
    try testing.expect(notice.tip);
    try testing.expectEqual(Tone.info, notice.tone);
    try testing.expectEqual(@as(?u32, 8000), notice.duration_ms);
    try testing.expectEqualStrings("窗口较窄，可以收起侧栏 · 点标题栏左侧的侧栏开关", notice.text);
    // Toasts are never suppressed by host overlays, and the tip no longer hides the corner stack.
    vm.setCardsCovered(true);
    try testing.expect(!vm.cardsSuppressed());
    try testing.expect(!vm.toasts.isSuppressed());
    try testing.expectError(error.EmptyTip, vm.tip("", 8000));
}
