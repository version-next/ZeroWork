//! V-2 / V-3 / V-4：spike 用的 view-model，形状照 ARCHITECTURE_PLAN §4.5 的
//! `ViewModel`（若干 `*ui.Signal(T)` 字段 + 一个 `ui.Memo` + `dispatch(Intent)`）。
//! 只依赖 `ui`；附带少量探针计数，供自检断言。
const std = @import("std");
const ui = @import("ui");

pub const Mode = enum { overview, panes, search };
pub const Row = struct { id: u32, title: []const u8 };

pub const Intent = union(enum) {
    back,
    forward,
    select: u8,
    toggle_flag,
    set_count: i32,
};

const rows_a = [_]Row{ .{ .id = 1, .title = "alpha" }, .{ .id = 2, .title = "beta" } };
const rows_b = [_]Row{ .{ .id = 3, .title = "gamma" }, .{ .id = 1, .title = "alpha" }, .{ .id = 4, .title = "delta" } };
pub const list_a: []const Row = &rows_a;
pub const list_b: []const Row = &rows_b;

pub const ViewModel = struct {
    // ── 数据下行 ──
    title: *ui.Signal([]const u8),
    mode: *ui.Signal(Mode),
    can_back: *ui.Signal(bool),
    count: *ui.Signal(i32),
    note: *ui.Signal(?[]const u8),
    rows: *ui.Signal([]const Row),
    /// `count * 2`，验证 `*ui.Memo(T)` 字段也能直接放进模板。
    doubled: *ui.Memo(i32),
    /// V-5：控制旧面板所在分支是否挂载。
    legacy_shown: *ui.Signal(bool),
    legacy_outer_shown: *ui.Signal(bool),

    // ── 探针（只给自检读，不是方案的一部分） ──
    /// 选择器 `titleOf` 被求值的次数（V-2：信号变化后应重跑）。
    selector_runs: usize = 0,
    /// dispatch 次数与最后一次 Intent（V-3）。
    dispatched: usize = 0,
    last: ?Intent = null,
    /// dispatch 执行时信号图上正在追踪的观察者层数（V-3：应为 0，即 peek 语义）。
    tracking_depth_in_dispatch: usize = std.math.maxInt(usize),
    /// `send` 被求值的次数（V-3：挂载时应为 0，每次点击 +1）。
    send_calls: usize = 0,

    pub fn init(scope: *ui.Scope) !*ViewModel {
        const self = try scope.createState(ViewModel, undefined);
        const count = try scope.createSignal(i32, 1);
        self.* = .{
            .title = try scope.createText("概览", .{}),
            .mode = try scope.createSignal(Mode, .overview),
            .can_back = try scope.createSignal(bool, false),
            .count = count,
            .note = try scope.createSignal(?[]const u8, null),
            .rows = try scope.createSignal([]const Row, list_a),
            .legacy_shown = try scope.createSignal(bool, true),
            .legacy_outer_shown = try scope.createSignal(bool, false),
            .doubled = try scope.createMemo(i32, .{ .count = count }, struct {
                fn run(ctx: anytype) i32 {
                    return ctx.count.get() * 2;
                }
            }.run),
        };
        return self;
    }

    /// 动作上行：处理器在点击时同步执行。这里**故意用 `.get()` 读信号**，
    /// 以便自检确认事件上下文里没有正在追踪的观察者（get 退化为 peek，不建立订阅）。
    pub fn dispatch(self: *ViewModel, intent: Intent) void {
        self.dispatched += 1;
        self.last = intent;
        self.tracking_depth_in_dispatch = self.count.owner.graph.tracking_stack.items.len;
        switch (intent) {
            .back => {
                self.title.set("概览");
                self.can_back.set(false);
                self.mode.set(.overview);
            },
            .forward => {
                self.title.set("子页面");
                self.can_back.set(true);
                self.mode.set(.panes);
            },
            .select => |i| self.mode.set(@enumFromInt(i % 3)),
            .toggle_flag => self.can_back.set(!self.can_back.get()),
            .set_count => |n| self.count.set(self.count.get() + n),
        }
    }
};
