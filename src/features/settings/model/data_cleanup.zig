//! “数据与日志 › 清除全部数据…”的确认流程（S-12）：纯状态机 + 文案投影，带单元测试。
//!
//! 宿主持有一切 I/O 与跨窗口检查（`SettingsHost.dataCleanupBlocked` / `performDataCleanup`），把结果以事件喂进来；
//! 用户在对话框里的选择变成 `Action`，由 view-model 发 `Effect.data_cleanup` 交宿主执行。对话框本身是 `.yix` 的原生
//! `W.Modal`（`view/data_cleanup.yix`），开合与文案全部读这里的投影。本文件不依赖 zenit `ui`、不做 I/O。
//!
//! | 当前 | 事件 | 下一个 | 动作 |
//! |---|---|---|---|
//! | 任意 | show(reason) | confirm（带阻塞原因） | 无（宿主在打开时、以及清除前复查失败撤回 owner 后发） |
//! | confirm | blocked(reason) | confirm（更新原因） | 无 |
//! | confirm | confirm（未阻塞） | 不变 | confirm（宿主再检查一次，通过后回 working） |
//! | confirm | confirm（阻塞中） | 不变 | 无 |
//! | confirm | cancel | closed | dismiss（宿主恢复滚动与焦点） |
//! | 任意打开 | working | working | 无 |
//! | working | cancel / confirm | 不变 | 无（清除开始后不可取消） |
//! | 任意打开 | failed(message, retryable) | failed | 无 |
//! | failed | confirm（可重试且未阻塞） | 不变 | retry |
//! | failed | cancel（按钮“退出应用” / Escape / 关闭） | closed | dismiss（宿主：清除已开始 → 退出应用） |
//! | closed | 除 show 以外 | 不变 | 无 |
const std = @import("std");

pub const Mode = enum { closed, confirm, working, failed };

/// 宿主喂进来的事件与对话框里的选择。字符串只在派发期间有效（view-model 复制）。
pub const Event = union(enum) {
    /// 宿主打开（或清除前复查失败后回到）确认态；`blocked` 是当时的阻塞原因（null = 可以清除）。
    show: ?[]const u8,
    /// 宿主复查的阻塞原因（确认态每帧轮询；只在确认态生效）。
    blocked: ?[]const u8,
    /// 宿主已接手清除（`data_cleanup_owner` 已设）。
    working,
    /// 清除失败：具体原因；`retryable` 为假时不再提供“重试清除”。
    failed: Failure,
    /// 主按钮（动词 + 对象）：“清除全部数据” / “重试清除”。
    confirm,
    /// 次按钮（“取消” / “退出应用”）、Escape、标题栏关闭。
    cancel,
};
pub const Failure = struct { message: []const u8, retryable: bool = true };

/// 要宿主执行的事。
pub const Action = enum { none, confirm, retry, dismiss };

pub const max_text = 256;

/// 流程状态（值语义；文字存在自己的缓冲里）。
pub const State = struct {
    mode: Mode = .closed,
    /// 确认态的阻塞原因（宿主的静态文案，复制进来）。
    blocked_buf: [max_text]u8 = undefined,
    blocked_len: u16 = 0,
    is_blocked: bool = false,
    /// 失败原因。
    failure_buf: [max_text]u8 = undefined,
    failure_len: u16 = 0,
    retryable: bool = false,

    pub fn blockedReason(self: *const State) ?[]const u8 {
        return if (self.is_blocked) self.blocked_buf[0..self.blocked_len] else null;
    }
    pub fn failure(self: *const State) []const u8 {
        return self.failure_buf[0..self.failure_len];
    }
    fn setBlocked(self: *State, reason: ?[]const u8) void {
        self.is_blocked = reason != null;
        self.blocked_len = copy(&self.blocked_buf, reason orelse "");
    }
    fn setFailure(self: *State, value: Failure) void {
        self.failure_len = copy(&self.failure_buf, value.message);
        self.retryable = value.retryable;
    }
    /// 两份状态显示上是否相同（view-model 只在变化时写信号）。
    pub fn same(a: *const State, b: *const State) bool {
        if (a.mode != b.mode or a.is_blocked != b.is_blocked or a.retryable != b.retryable) return false;
        if (!std.mem.eql(u8, a.blocked_buf[0..a.blocked_len], b.blocked_buf[0..b.blocked_len])) return false;
        return std.mem.eql(u8, a.failure(), b.failure());
    }
};

fn copy(buffer: *[max_text]u8, text: []const u8) u16 {
    // 按 UTF-8 边界截断，不留半个字符。
    var n = @min(text.len, buffer.len);
    while (n > 0 and n < text.len and (text[n] & 0xC0) == 0x80) n -= 1;
    @memcpy(buffer[0..n], text[0..n]);
    return @intCast(n);
}

/// 状态转移（见文件头的表）。
pub fn step(state: *State, event: Event) Action {
    switch (event) {
        .show => |reason| {
            state.mode = .confirm;
            state.retryable = false;
            state.failure_len = 0;
            state.setBlocked(reason);
            return .none;
        },
        .blocked => |reason| {
            if (state.mode == .confirm) state.setBlocked(reason);
            return .none;
        },
        .working => {
            if (state.mode == .closed) return .none;
            state.mode = .working;
            return .none;
        },
        .failed => |value| {
            if (state.mode == .closed) return .none;
            state.mode = .failed;
            state.setFailure(value);
            return .none;
        },
        .confirm => return switch (state.mode) {
            .confirm => if (state.is_blocked) .none else .confirm,
            .failed => if (state.retryable and !state.is_blocked) .retry else .none,
            .closed, .working => .none,
        },
        .cancel => switch (state.mode) {
            .confirm, .failed => {
                state.mode = .closed;
                return .dismiss;
            },
            .closed, .working => return .none,
        },
    }
}

// ── 投影（对话框读的文案与可用性；与旧 `application_data_cleanup_view` 逐字相同） ──

pub const scope_text = "删除本应用的配置、主机、会话记录、缓存与诊断日志。\n同时删除此应用范围的钥匙串凭据，以及旧 ~/.zerowork\n中的迁移残余。";
pub const preserved_text = "保留共享 ~/.ssh/known_hosts、外部私钥，\n以及用户下载或导出的文件。";
pub const outcome_text = "不可撤销。清除后退出应用，重启恢复初始状态。";

pub fn open(state: *const State) bool {
    return state.mode != .closed;
}
pub fn title(state: *const State) []const u8 {
    return if (state.mode == .confirm) "清除全部应用数据？" else "清除应用数据";
}
pub fn headline(state: *const State) []const u8 {
    return switch (state.mode) {
        .closed, .confirm => "将清除全部应用数据",
        .working => "正在清除应用数据…",
        .failed => "清除未完成，应用尚未退出",
    };
}
/// 标题行用警告色（工作中是普通墨色）。
pub fn headlineWarning(state: *const State) bool {
    return state.mode != .working;
}
/// 状态行：确认态是阻塞原因（无则为空），工作中是说明，失败是具体原因。
pub fn message(state: *const State) []const u8 {
    return switch (state.mode) {
        .closed => "",
        .confirm => state.blockedReason() orelse "",
        .working => "请稍候。全部清除成功后，应用将退出。",
        .failed => state.failure(),
    };
}
pub fn messageWarning(state: *const State) bool {
    return state.mode == .failed or (state.mode == .confirm and state.is_blocked);
}
pub fn cancelLabel(state: *const State) []const u8 {
    return if (state.mode == .failed) "退出应用" else "取消";
}
pub fn cancelA11y(state: *const State) []const u8 {
    return if (state.mode == .failed) "退出应用" else "取消清除并返回设置";
}
/// 工作中不可取消（按钮、Escape、标题栏关闭都不接）。
pub fn cancelDisabled(state: *const State) bool {
    return state.mode == .working;
}
pub fn primaryLabel(state: *const State) []const u8 {
    return switch (state.mode) {
        .closed, .confirm => "清除全部数据",
        .working => "正在清除…",
        .failed => "重试清除",
    };
}
pub fn primaryA11y(state: *const State) []const u8 {
    return if (state.mode == .failed) "重试清除全部应用数据并退出" else "清除全部应用数据并退出";
}
/// 失败且不可重试时不显示主按钮。
pub fn primaryShown(state: *const State) bool {
    return !(state.mode == .failed and !state.retryable);
}
pub fn primaryDisabled(state: *const State) bool {
    return switch (state.mode) {
        .closed, .working => true,
        .confirm => state.is_blocked,
        .failed => state.is_blocked or !state.retryable,
    };
}
pub fn primaryBusy(state: *const State) bool {
    return state.mode == .working;
}

// ── 单元测试 ──

const testing = std.testing;

test "data cleanup: open, blocked recheck, confirm only when idle, cancel dismisses" {
    var s: State = .{};
    try testing.expect(!open(&s));
    try testing.expectEqual(Action.none, step(&s, .confirm));
    try testing.expectEqual(Action.none, step(&s, .cancel));
    try testing.expectEqual(Action.none, step(&s, .{ .show = "请先结束所有窗口的活动会话与后台连接" }));
    try testing.expect(open(&s));
    try testing.expectEqualStrings("清除全部应用数据？", title(&s));
    try testing.expectEqualStrings("请先结束所有窗口的活动会话与后台连接", message(&s));
    try testing.expect(messageWarning(&s) and primaryDisabled(&s) and !cancelDisabled(&s));
    try testing.expectEqual(Action.none, step(&s, .confirm));
    try testing.expectEqual(Action.none, step(&s, .{ .blocked = null }));
    try testing.expectEqualStrings("", message(&s));
    try testing.expect(!messageWarning(&s) and !primaryDisabled(&s));
    try testing.expectEqual(Action.confirm, step(&s, .confirm));
    try testing.expect(open(&s));
    try testing.expectEqual(Action.dismiss, step(&s, .cancel));
    try testing.expect(!open(&s));
    // 关着时宿主的复查不打开对话框。
    _ = step(&s, .{ .blocked = "x" });
    try testing.expect(!open(&s));
}

test "data cleanup: working ignores every user choice and host recheck; failure offers retry and exit" {
    var s: State = .{};
    _ = step(&s, .{ .show = null });
    _ = step(&s, .working);
    try testing.expectEqual(Mode.working, s.mode);
    try testing.expectEqualStrings("清除应用数据", title(&s));
    try testing.expectEqualStrings("正在清除应用数据…", headline(&s));
    try testing.expectEqualStrings("正在清除…", primaryLabel(&s));
    try testing.expect(primaryDisabled(&s) and primaryBusy(&s) and cancelDisabled(&s) and !headlineWarning(&s));
    try testing.expectEqual(Action.none, step(&s, .cancel));
    try testing.expectEqual(Action.none, step(&s, .confirm));
    _ = step(&s, .{ .blocked = "x" });
    try testing.expectEqual(Mode.working, s.mode);
    _ = step(&s, .{ .failed = .{ .message = "钥匙串清除失败：AccessDenied。部分内容可能已删除；可重试或退出，应用不会继续保存配置。" } });
    try testing.expectEqual(Mode.failed, s.mode);
    try testing.expectEqualStrings("清除未完成，应用尚未退出", headline(&s));
    try testing.expectEqualStrings("退出应用", cancelLabel(&s));
    try testing.expectEqualStrings("退出应用", cancelA11y(&s));
    try testing.expectEqualStrings("重试清除", primaryLabel(&s));
    try testing.expectEqualStrings("重试清除全部应用数据并退出", primaryA11y(&s));
    try testing.expect(primaryShown(&s) and !primaryDisabled(&s) and messageWarning(&s));
    try testing.expect(std.mem.startsWith(u8, message(&s), "钥匙串清除失败"));
    try testing.expectEqual(Action.retry, step(&s, .confirm));
    // 失败态里宿主的复查不改状态行（同旧 `setBlocked` 只在确认态写消息）。
    _ = step(&s, .{ .blocked = "另一窗口正在清除应用数据" });
    try testing.expect(std.mem.startsWith(u8, message(&s), "钥匙串清除失败"));
    _ = step(&s, .{ .failed = .{ .message = "目录验证失败。未继续删除，请重新启动应用。", .retryable = false } });
    try testing.expect(!primaryShown(&s) and primaryDisabled(&s));
    try testing.expectEqual(Action.none, step(&s, .confirm));
    try testing.expectEqual(Action.dismiss, step(&s, .cancel));
    try testing.expect(!open(&s));
}

test "data cleanup: host returns a blocked dispatch to the confirmation; long text truncates on a UTF-8 boundary" {
    var s: State = .{};
    _ = step(&s, .{ .show = null });
    _ = step(&s, .working);
    // `performDataCleanup` 动手前复查失败：宿主撤回 owner，回到确认态并显示原因（同旧 `showConfirmation` + `setBlocked`）。
    _ = step(&s, .{ .show = "请等待新窗口创建完成" });
    try testing.expectEqual(Mode.confirm, s.mode);
    try testing.expectEqualStrings("请等待新窗口创建完成", message(&s));
    try testing.expectEqualStrings("清除全部数据", primaryLabel(&s));
    var long: [360]u8 = undefined;
    for (0..120) |i| @memcpy(long[i * 3 ..][0..3], "清");
    _ = step(&s, .{ .blocked = &long });
    try testing.expect(message(&s).len <= max_text);
    try testing.expect(std.unicode.utf8ValidateSlice(message(&s)));
    var t = s;
    try testing.expect(State.same(&s, &t));
    _ = step(&t, .{ .blocked = null });
    try testing.expect(!State.same(&s, &t));
}
