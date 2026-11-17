//! 内容卡片类型（PLUGIN_ARCH_PLAN 2.5、PL4a M1–M9）。
//!
//! 内容卡片是唯一的内容抽象：终端、文件、KVM 画面、会话记录、AI 对话都是某种卡片类型的实例。
//! tab 是一组卡片的容器（分屏树的叶子是卡片；单卡 tab 只是只有一个叶子的特例），浮动是卡片实例
//! 的另一种放置状态。每个卡片类型在这里声明：
//! - 允许的放置（`standalone_tab` / `split` / `float`），宿主在每次放置和移动时校验；
//! - 浮动时可枚举的交互与几何参数（`float`，即通用卡片浮动层的 `float_card.Descriptor`）；
//! - AI 能力（`ai`）：上下文摘要函数与工具名引用。AI 只在卡片上配置，tab 能否启动 AI 由
//!   tab 里卡片的声明派生（2.5.8），与卡片在 tab 内还是浮动无关。
//!
//! 卡片类型只在组合根登记（`plugin_registry.PluginHost.registerCardType` 与插件清单的
//! `cards`），在创建第一个窗口之前随插件注册表一次性发布为不可变快照，此后不接受登记。
const std = @import("std");
const identity = @import("identity.zig");
const float_card = @import("../shared/base/float_card.zig");
const float_swipe = @import("../shared/base/float_swipe.zig");
const legacy_adapter = @import("../ai/legacy_adapter.zig");

pub const Placement = enum { standalone_tab, split, float };

pub const Placements = struct {
    /// 作为某个 tab 里唯一的一张卡片。
    standalone_tab: bool = false,
    /// 进入某个 tab 的分屏树，与其他卡片并排。
    split: bool = false,
    /// 窗口级浮动层上的浮动卡片，归属打开它的 tab。
    float: bool = false,

    pub fn allows(self: Placements, placement: Placement) bool {
        return switch (placement) {
            .standalone_tab => self.standalone_tab,
            .split => self.split,
            .float => self.float,
        };
    }
    pub fn any(self: Placements) bool {
        return self.standalone_tab or self.split or self.float;
    }
};

/// 卡片实例绑定什么：`session` 需要 SessionHandle（会话卡片，roster 成员）；`standalone` 不绑定
/// 会话；`tab` 绑定所属 tab（只有 `ai.chat`）。
pub const Binding = enum { session, standalone, tab };

/// 会话卡片的 AI 工具引擎（过渡：统一工具接口 2.9 的 T2 落地前，会话工具由各协议的兼容引擎执行）。
pub const SessionEngine = struct {
    plugin_id: []const u8,
    factory: legacy_adapter.Factory,
};

/// 卡片类型的 AI 声明（2.5.8 / 2.9 简化版）：上下文摘要函数 + 工具名引用。
pub const CardAi = struct {
    summary: Summary,
    tools: Tools = .none,
    /// 宿主查询类细节工具（如 `host.read_terminal`），按名字引用，必须是已登记的宿主工具。
    host_tools: []const []const u8 = &.{},
    /// `host.tab_context` 的查询参数（保留参数 `max_lines` / `limit` / `cursor` 的子集）：这张卡片
    /// 类型支持哪些、各自含义，以及按参数取数与组装的实现。不支持的参数由流水线第 3 步拒绝
    /// （`Unsupported` + 可操作提示），不会悄悄忽略。
    query: Query = .{},

    /// 卡片类型声明的查询参数。字段非 null 表示支持，值是写给模型看的含义（出现在概览与错误提示里）。
    pub const Query = struct {
        max_lines: ?[]const u8 = null,
        limit: ?[]const u8 = null,
        cursor: ?[]const u8 = null,
        /// 不支持任何参数（或部分参数）时的说明，写进错误提示，告诉模型改用什么。
        note: []const u8 = "",
        /// 带了查询参数时的取数与组装（没有参数时仍走 `summary`，行为不变）。声明了任一参数就必须提供。
        run: ?*const fn (app: *anyopaque, owner: identity.SessionHandle, args: QueryArgs, allocator: std.mem.Allocator) anyerror!QueryResult = null,

        pub const Param = enum { max_lines, limit, cursor };
        pub fn supports(self: Query, param: Param) bool {
            return self.meaning(param) != null;
        }
        pub fn meaning(self: Query, param: Param) ?[]const u8 {
            return switch (param) {
                .max_lines => self.max_lines,
                .limit => self.limit,
                .cursor => self.cursor,
            };
        }
        pub fn any(self: Query) bool {
            return self.max_lines != null or self.limit != null or self.cursor != null;
        }
    };
    /// 已经过 schema 与卡片类型校验的查询参数；`cursor` 是宿主解出的卡片内偏移（游标的卡片与修订号已核对）。
    pub const QueryArgs = struct {
        max_lines: ?u16 = null,
        limit: ?u16 = null,
        cursor: ?u64 = null,
        /// 游标签发时的内容修订号；实现发现内容已变化时返回 `error.SnapshotChanged`。
        cursor_revision: ?u64 = null,
        budget_bytes: usize,
        redact: bool,
        context_window: u32,
        /// 宿主的文件工作区（`file_application_host.Host`，文件卡片读目录投影用）；没有时为 null。
        /// 由持有它的 AI 宿主给出，不从插件上下文猜类型。
        file_host: ?*anyopaque = null,
    };
    pub const QueryResult = struct {
        /// 由调用方给的 allocator 分配。
        text: []const u8,
        truncated: bool = false,
        /// 还有下一页时给出下一页的卡片内偏移与当时的内容修订号；宿主据此签出 `next_cursor`。
        next_offset: ?u64 = null,
        revision: u64 = 0,
    };

    pub const Summary = union(enum) {
        /// 会话卡片：由该会话所属协议的引擎组装（`SessionEngine.factory` 的 `assemble_context`）。
        session_engine,
        /// 由提供者给出身份与可选摘要，拼成 `provider=… session_id=… generation=…` 加摘要。
        provider: ProviderSummary,
    };
    pub const ProviderSummary = struct {
        identity: []const u8,
        context: ?*anyopaque = null,
        summarize: ?*const fn (?*anyopaque, identity.SessionHandle, std.mem.Allocator) anyerror![]const u8 = null,
    };
    /// 这张卡片能作为哪些工具的目标。
    pub const Tools = union(enum) {
        none,
        /// 会话卡片：取会话所属插件登记的工具（按该会话实际可用的服务过滤），由对应协议的引擎执行。
        session_tools: []const SessionEngine,
        /// 插件定义的卡片：只列本插件登记的工具 ID（必须在该插件的 `tools` 绑定里）。
        own: []const []const u8,
    };

    /// 会话卡片在给定协议下的工具引擎；不是会话工具卡片或该协议未声明引擎时为 null。
    pub fn engineFor(self: CardAi, plugin_id: []const u8) ?legacy_adapter.Factory {
        return switch (self.tools) {
            .session_tools => |engines| for (engines) |engine| {
                if (std.mem.eql(u8, engine.plugin_id, plugin_id)) break engine.factory;
            } else null,
            else => null,
        };
    }
};

pub const CardTypeDef = struct {
    id: []const u8,
    title: []const u8,
    binding: Binding,
    placements: Placements,
    default_placement: Placement,
    /// 浮动声明（可枚举交互、尺寸、首次打开位置）；`placements.float` 为真时必须提供。
    float: ?float_card.Descriptor = null,
    /// 每个所属 tab 最多几张浮动实例（Q15 / Q21：history 为 1）。
    float_per_tab: ?u8 = null,
    /// AI 能力只在这里声明；null 表示这张卡片不参与 tab 的 AI。
    ai: ?CardAi = null,
    /// 这张卡片所在的 tab 能否整体移交到另一个窗口（窗口移交只移视图，不复制网络；V0.2 §6）。
    /// 今天只有插件渲染器呈现的会话卡片支持；渲染器自己仍要声明 `supports_window_transfer`。
    supports_window_transfer: bool = false,
};

/// 内置卡片类型的 id。插件定义的类型（如 `kvm`）由插件清单的 `cards` 登记。
pub const ids = struct {
    pub const terminal = "terminal";
    pub const file = "file";
    pub const kvm = "kvm";
    pub const ai_chat = "ai.chat";
    pub const history = "history";
    /// 通用会话卡片：没有声明 `card_type` 的插件会话（例如测试插件）呈现为它。可独立成 tab、
    /// 可进分屏，不声明 AI——与今天"任何会话 tab 都能入组"的规则一致。
    pub const session = "session";
};

/// 非会话卡片实例的身份分配（PLUGIN_ARCH_PLAN 2.5.3 第 4 点）：卡片宿主按槽位分配带代次的
/// `CardId`。释放的槽位复用时代次加一，所以旧实例的身份（例如已排队的关闭回执、通知目标）
/// 与新实例逐字段比较一定不等。代次用尽（u32 回绕）的槽位不再复用。
pub const CardSlots = struct {
    generations: std.ArrayList(u32) = .empty,
    free: std.ArrayList(u32) = .empty,

    pub fn deinit(self: *CardSlots, allocator: std.mem.Allocator) void {
        self.generations.deinit(allocator);
        self.free.deinit(allocator);
    }
    pub fn allocate(self: *CardSlots, allocator: std.mem.Allocator) !identity.CardId {
        if (self.free.pop()) |slot| {
            self.generations.items[slot] += 1;
            return .{ .slot = slot, .generation = self.generations.items[slot] };
        }
        const slot = std.math.cast(u32, self.generations.items.len) orelse return error.IdentityExhausted;
        try self.generations.append(allocator, 1);
        return .{ .slot = slot, .generation = 1 };
    }
    /// 只有当前代次的身份能释放槽位；重复释放与过期身份被忽略。
    pub fn release(self: *CardSlots, allocator: std.mem.Allocator, id: identity.CardId) void {
        if (!self.live(id)) return;
        // 代次用尽或记不下空闲槽位：槽位退役（代次置 0，此后没有身份能匹配它），不再复用。
        if (id.generation == std.math.maxInt(u32)) {
            self.generations.items[id.slot] = 0;
            return;
        }
        self.free.append(allocator, id.slot) catch {
            self.generations.items[id.slot] = 0;
        };
    }
    pub fn live(self: *const CardSlots, id: identity.CardId) bool {
        if (!id.valid() or id.slot >= self.generations.items.len) return false;
        if (self.generations.items[id.slot] != id.generation) return false;
        for (self.free.items) |slot| if (slot == id.slot) return false;
        return true;
    }
};

pub const ValidationError = error{
    InvalidCardType,
    EmptyCardPlacements,
    CardDefaultPlacementNotAllowed,
    MissingCardFloatDescriptor,
    UnexpectedCardFloatDescriptor,
    CardFloatDescriptorMismatch,
    CardOpenAsTabNotAllowed,
    CardDockToSplitNotAllowed,
    InvalidCardFloatLimit,
    TabBoundCardDeclaresAi,
    UnknownCardHostTool,
    CardQueryWithoutImplementation,
};

/// 单个类型的约束校验（注册时调用）。`known_host_tool` 判断宿主工具名是否已登记。
pub fn validate(def: CardTypeDef, known_host_tool: *const fn ([]const u8) bool) ValidationError!void {
    if (!validId(def.id) or def.title.len == 0) return error.InvalidCardType;
    if (!def.placements.any()) return error.EmptyCardPlacements;
    if (!def.placements.allows(def.default_placement)) return error.CardDefaultPlacementNotAllowed;
    if (def.placements.float) {
        const descriptor = def.float orelse return error.MissingCardFloatDescriptor;
        if (!std.mem.eql(u8, descriptor.id, def.id)) return error.CardFloatDescriptorMismatch;
        // The header's "open as tab" needs a tab to open into.
        if (descriptor.supports(.open_as_tab) and !def.placements.standalone_tab) return error.CardOpenAsTabNotAllowed;
        // "Dock to split" needs a tab body split to dock into (and is derived, see `floatDescriptor`).
        if (descriptor.supports(.dock_to_split) and !def.placements.split) return error.CardDockToSplitNotAllowed;
    } else if (def.float != null) return error.UnexpectedCardFloatDescriptor;
    if (def.float_per_tab) |limit| if (limit == 0 or !def.placements.float) return error.InvalidCardFloatLimit;
    if (def.ai) |ai| {
        // AI 对话是上下文的消费者；把自己的对话当作上下文会自我引用（2.5.8 表）。
        if (def.binding == .tab) return error.TabBoundCardDeclaresAi;
        for (ai.host_tools) |name| if (!known_host_tool(name)) return error.UnknownCardHostTool;
        // 声明了查询参数就必须自己实现取数（`host.tab_context` 把参数交给它）。
        if (ai.query.any() and ai.query.run == null) return error.CardQueryWithoutImplementation;
    }
}

/// The floating declaration a floating card uses (float-split): the card type's `float` with the
/// placement actions of the unified header derived from its placements, never declared per card:
/// `open_as_tab` ⇔ `standalone_tab`, `dock_to_split` ⇔ `split`. The header shows both on every
/// floating card; an underived one is drawn disabled with the reason (`placementRefusal`).
pub fn floatDescriptor(def: *const CardTypeDef) ?float_card.Descriptor {
    var descriptor = def.float orelse return null;
    descriptor.interactions.setPresent(.open_as_tab, def.placements.standalone_tab);
    descriptor.interactions.setPresent(.dock_to_split, def.placements.split);
    // Swipe down to collapse (AveHg) follows `minimize`: only a card that can collapse does.
    float_swipe.deriveInto(&descriptor);
    return descriptor;
}

/// Why the card type itself refuses a placement action (the Tooltip of the disabled button), or
/// null when it allows it. `title` is what the card shows (e.g. "会话记录").
pub fn placementRefusal(buffer: []u8, def: *const CardTypeDef, placement: Placement, title: []const u8) ?[]const u8 {
    if (def.placements.allows(placement)) return null;
    return switch (placement) {
        .split => float_card.refusalText(buffer, .dock_to_split, title),
        .standalone_tab => float_card.refusalText(buffer, .open_as_tab, title),
        .float => std.fmt.bufPrint(buffer, "{s}不支持浮动", .{title}) catch "不支持浮动",
    };
}

/// One axis of a floating card's default size (#52 form): clamp(content × ratio, min, max). `min` is
/// also the resize minimum on that axis.
pub const SizeAxis = struct {
    ratio: f32,
    min: f32,
    max: f32,
    pub fn of(self: SizeAxis, content: f32) f32 {
        return @round(std.math.clamp(content * self.ratio, self.min, self.max));
    }
};
pub const FloatSize = struct { width: SizeAxis, height: SizeAxis };

/// The interactions of a floating session card (cards-float): move, resize, maximize, raise, close
/// (the card's session closes, with its confirmation), fold into the owner tab on a tab switch (Z12)
/// and remember the dropped rectangle. No minimize: a session card has no launcher to fold into.
/// The placement actions are derived (`floatDescriptor`).
pub const session_float_interactions: float_card.Interactions = .initMany(&.{ .move, .resize, .maximize, .raise, .close, .fold_to_tab, .remember_position });

/// The floating declaration of a session card type (terminal / file / KVM / generic session): first
/// open centred in the floating region, the default size from `size` for the owner tab's content.
pub fn sessionFloat(comptime id: []const u8, comptime size: FloatSize) float_card.Descriptor {
    const Size = struct {
        fn default(content: float_card.Rect) float_card.Size {
            return .{ .width = size.width.of(content.width), .height = size.height.of(content.height) };
        }
    };
    return .{ .id = id, .interactions = session_float_interactions, .min_size = .{ .width = size.width.min, .height = size.height.min }, .default_size = Size.default, .first_open = .center };
}

/// Floating sizes of the session card types (cards-float, Pencil MSg5W; the #52 clamp form).
pub const float_sizes = struct {
    /// Terminal and generic session cards: about 80 × 20 cells at the default font at minimum.
    pub const terminal: FloatSize = .{ .width = .{ .ratio = 0.55, .min = 480, .max = 960 }, .height = .{ .ratio = 0.6, .min = 300, .max = 640 } };
    /// File workspace (SFTP): the list with its toolbar and path bar.
    pub const file: FloatSize = .{ .width = .{ .ratio = 0.6, .min = 560, .max = 1040 }, .height = .{ .ratio = 0.65, .min = 360, .max = 720 } };
    /// KVM picture with its toolbar.
    pub const kvm: FloatSize = .{ .width = .{ .ratio = 0.6, .min = 520, .max = 1024 }, .height = .{ .ratio = 0.7, .min = 360, .max = 768 } };
};

pub fn find(defs: []const CardTypeDef, id: []const u8) ?*const CardTypeDef {
    for (defs) |*def| if (std.mem.eql(u8, def.id, id)) return def;
    return null;
}

fn validId(value: []const u8) bool {
    if (value.len == 0 or value.len > 128) return false;
    for (value) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-' and byte != '.') return false;
    return true;
}

fn anyHostTool(_: []const u8) bool {
    return true;
}
fn noHostTool(_: []const u8) bool {
    return false;
}
fn testSize(_: float_card.Rect) float_card.Size {
    return .{ .width = 400, .height = 300 };
}
const test_float: float_card.Descriptor = .{ .id = "probe", .interactions = .initMany(&.{.move}), .min_size = .{ .width = 100, .height = 100 }, .default_size = testSize };

test "card type validation rejects empty, disallowed default and inconsistent float declarations" {
    const base: CardTypeDef = .{ .id = "probe", .title = "Probe", .binding = .standalone, .placements = .{ .standalone_tab = true }, .default_placement = .standalone_tab };
    try validate(base, noHostTool);
    var def = base;
    def.placements = .{};
    try std.testing.expectError(error.EmptyCardPlacements, validate(def, noHostTool));
    def = base;
    def.default_placement = .split;
    try std.testing.expectError(error.CardDefaultPlacementNotAllowed, validate(def, noHostTool));
    def = base;
    def.placements.float = true;
    try std.testing.expectError(error.MissingCardFloatDescriptor, validate(def, noHostTool));
    def.float = test_float;
    try validate(def, noHostTool);
    def.float.?.id = "other";
    try std.testing.expectError(error.CardFloatDescriptorMismatch, validate(def, noHostTool));
    def.float.?.id = "probe";
    def.float.?.interactions.insert(.open_as_tab);
    try validate(def, noHostTool);
    def.placements.standalone_tab = false;
    def.default_placement = .float;
    try std.testing.expectError(error.CardOpenAsTabNotAllowed, validate(def, noHostTool));
    def = base;
    def.float = test_float;
    try std.testing.expectError(error.UnexpectedCardFloatDescriptor, validate(def, noHostTool));
    def = base;
    def.float_per_tab = 1;
    try std.testing.expectError(error.InvalidCardFloatLimit, validate(def, noHostTool));
    def = base;
    def.id = "bad id";
    try std.testing.expectError(error.InvalidCardType, validate(def, noHostTool));
}

test "floating placement actions derive from placements and declared ones must agree" {
    var def: CardTypeDef = .{ .id = "probe", .title = "Probe", .binding = .standalone, .placements = .{ .standalone_tab = true, .float = true }, .default_placement = .float, .float = test_float };
    try validate(def, noHostTool);
    const derived = floatDescriptor(&def).?;
    try std.testing.expect(derived.supports(.open_as_tab) and !derived.supports(.dock_to_split) and derived.supports(.move));
    def.float.?.interactions.insert(.dock_to_split);
    try std.testing.expectError(error.CardDockToSplitNotAllowed, validate(def, noHostTool));
    try std.testing.expect(!floatDescriptor(&def).?.supports(.dock_to_split));
    def.placements.split = true;
    try validate(def, noHostTool);
    try std.testing.expect(floatDescriptor(&def).?.supports(.dock_to_split));
    var buffer: [96]u8 = undefined;
    try std.testing.expect(placementRefusal(&buffer, &def, .split, "Probe") == null);
    def.placements.split = false;
    try std.testing.expectEqualStrings("会话记录不支持分屏", placementRefusal(&buffer, &def, .split, "会话记录").?);
    def.placements.standalone_tab = false;
    try std.testing.expectEqualStrings("AI 助手不支持作为标签页打开", placementRefusal(&buffer, &def, .standalone_tab, "AI 助手").?);
    const tab_only: CardTypeDef = .{ .id = "tab", .title = "Tab", .binding = .standalone, .placements = .{ .standalone_tab = true }, .default_placement = .standalone_tab };
    try std.testing.expect(floatDescriptor(&tab_only) == null);
}

test "card AI is consumer-free on tab-bound cards and host tool references must exist" {
    const chat: CardTypeDef = .{ .id = "chat", .title = "Chat", .binding = .tab, .placements = .{ .float = true }, .default_placement = .float, .float = blk: {
        var descriptor = test_float;
        descriptor.id = "chat";
        break :blk descriptor;
    }, .ai = .{ .summary = .session_engine } };
    try std.testing.expectError(error.TabBoundCardDeclaresAi, validate(chat, anyHostTool));
    const terminal: CardTypeDef = .{ .id = "term", .title = "Term", .binding = .session, .placements = .{ .standalone_tab = true, .split = true }, .default_placement = .standalone_tab, .ai = .{ .summary = .session_engine, .host_tools = &.{"host.read_terminal"} } };
    try validate(terminal, anyHostTool);
    try std.testing.expectError(error.UnknownCardHostTool, validate(terminal, noHostTool));
}

test "card query parameters must come with the card type's own implementation" {
    const Impl = struct {
        fn run(_: *anyopaque, _: identity.SessionHandle, _: CardAi.QueryArgs, _: std.mem.Allocator) anyerror!CardAi.QueryResult {
            return .{ .text = "" };
        }
    };
    var def: CardTypeDef = .{ .id = "term", .title = "Term", .binding = .session, .placements = .{ .standalone_tab = true }, .default_placement = .standalone_tab, .ai = .{ .summary = .session_engine, .query = .{ .max_lines = "recent lines" } } };
    try std.testing.expectError(error.CardQueryWithoutImplementation, validate(def, anyHostTool));
    def.ai.?.query.run = Impl.run;
    try validate(def, anyHostTool);
    try std.testing.expect(def.ai.?.query.supports(.max_lines) and !def.ai.?.query.supports(.limit) and !def.ai.?.query.supports(.cursor));
    // 不声明参数（KVM 一类只给元信息）不需要实现。
    const meta: CardTypeDef = .{ .id = "kvm", .title = "KVM", .binding = .session, .placements = .{ .standalone_tab = true }, .default_placement = .standalone_tab, .ai = .{ .summary = .{ .provider = .{ .identity = "x" } }, .query = .{ .note = "metadata only" } } };
    try validate(meta, anyHostTool);
}

test "session engines resolve only for the declared protocol" {
    const Engines = struct {
        fn create(_: std.mem.Allocator) anyerror!legacy_adapter.Adapter {
            return error.Unused;
        }
    };
    const ai: CardAi = .{ .summary = .session_engine, .tools = .{ .session_tools = &.{.{ .plugin_id = "local", .factory = Engines.create }} } };
    try std.testing.expect(ai.engineFor("local").? == Engines.create);
    try std.testing.expect(ai.engineFor("ssh") == null);
    const own: CardAi = .{ .summary = .{ .provider = .{ .identity = "x" } }, .tools = .{ .own = &.{"x.read"} } };
    try std.testing.expect(own.engineFor("local") == null);
}

test "card slots reuse a released slot with a new generation and reject stale identities" {
    const a = std.testing.allocator;
    var slots: CardSlots = .{};
    defer slots.deinit(a);
    const first = try slots.allocate(a);
    const second = try slots.allocate(a);
    try std.testing.expect(slots.live(first) and slots.live(second) and !first.eql(second));
    slots.release(a, first);
    try std.testing.expect(!slots.live(first));
    slots.release(a, first); // 重复释放被忽略
    const reused = try slots.allocate(a);
    try std.testing.expectEqual(first.slot, reused.slot);
    try std.testing.expect(reused.generation == first.generation + 1);
    // 同一槽位、不同代次：ContentOwner 判为不等。
    const old_owner: identity.ContentOwner = .{ .card = first };
    try std.testing.expect(!old_owner.eql(.{ .card = reused }));
    try std.testing.expect(!slots.live(first) and slots.live(reused));
    const fresh = try slots.allocate(a);
    try std.testing.expect(fresh.slot != reused.slot);
}

test "cards-float: a session card type floats with every placement action derived, no minimize; sizes follow the #52 clamp form" {
    const terminal: CardTypeDef = .{ .id = "terminal", .title = "终端", .binding = .session, .placements = .{ .standalone_tab = true, .split = true, .float = true }, .default_placement = .standalone_tab, .float = sessionFloat("terminal", float_sizes.terminal) };
    try validate(terminal, anyHostTool);
    const derived = floatDescriptor(&terminal).?;
    for ([_]float_card.Interaction{ .open_as_tab, .dock_to_split, .move, .resize, .maximize, .raise, .close, .fold_to_tab, .remember_position }) |interaction| try std.testing.expect(derived.supports(interaction));
    try std.testing.expect(!derived.supports(.minimize) and !derived.supports(.open_from_anchor));
    // swipe-collapse: no minimize, so a downward fling only springs back.
    try std.testing.expect(!derived.supports(.swipe_collapse));
    var buffer: [96]u8 = undefined;
    try std.testing.expectEqualStrings("终端不支持收起", float_card.refusalText(&buffer, .minimize, terminal.title));
    for (std.enums.values(Placement)) |placement| try std.testing.expect(placementRefusal(&buffer, &terminal, placement, terminal.title) == null);
    // Default size for a 1440 × 900 window's tab body (≈ 1170 × 834), the minimum on small bodies, the cap on large.
    const body = derived.default_size(.{ .x = 268, .y = 48, .width = 1170, .height = 834 });
    try std.testing.expectEqual(@as(f32, 644), body.width);
    try std.testing.expectEqual(@as(f32, 500), body.height);
    const small = derived.default_size(.{ .x = 0, .y = 0, .width = 400, .height = 300 });
    try std.testing.expectEqual(float_sizes.terminal.width.min, small.width);
    try std.testing.expectEqual(derived.min_size.height, small.height);
    const large = derived.default_size(.{ .x = 0, .y = 0, .width = 4000, .height = 3000 });
    try std.testing.expectEqual(@as(f32, 960), large.width);
    try std.testing.expectEqual(@as(f32, 640), large.height);
    for ([_]FloatSize{ float_sizes.terminal, float_sizes.file, float_sizes.kvm }) |size| {
        try std.testing.expect(size.width.min <= size.width.max and size.height.min <= size.height.max);
        try std.testing.expect(size.width.min >= 480 and size.height.min >= 300);
    }
}

test "cards-float: AI floats and splits but never opens as a tab; history opens as a tab and floats but never splits" {
    var ai_float = test_float;
    ai_float.id = "ai.chat";
    ai_float.interactions.insert(.minimize);
    const chat: CardTypeDef = .{ .id = "ai.chat", .title = "AI 助手", .binding = .tab, .placements = .{ .split = true, .float = true }, .default_placement = .float, .float = ai_float };
    try validate(chat, anyHostTool);
    const derived = floatDescriptor(&chat).?;
    try std.testing.expect(derived.supports(.dock_to_split) and !derived.supports(.open_as_tab) and derived.supports(.minimize));
    // swipe-collapse is derived from minimize + move.
    try std.testing.expect(derived.supports(.swipe_collapse));
    var buffer: [96]u8 = undefined;
    try std.testing.expectEqualStrings("AI 助手不支持作为标签页打开", placementRefusal(&buffer, &chat, .standalone_tab, chat.title).?);
    try std.testing.expect(placementRefusal(&buffer, &chat, .split, chat.title) == null);
    var history_float = test_float;
    history_float.id = "history";
    const history: CardTypeDef = .{ .id = "history", .title = "会话记录", .binding = .standalone, .placements = .{ .standalone_tab = true, .float = true }, .default_placement = .float, .float = history_float };
    const h = floatDescriptor(&history).?;
    try std.testing.expect(h.supports(.open_as_tab) and !h.supports(.dock_to_split));
}
