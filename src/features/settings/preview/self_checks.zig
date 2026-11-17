//! 设置预览 runner 的进程内自检（F-set-preview；docs/ui-revamp/YIX_SPIKE.md V-7、V-11）。
//!
//! 输出约定：每条判定一行 `PASS <id> <说明>` 或 `FAIL <id> <说明>`；观察值（不判定）一行
//! `INFO <id> <说明>`。最后一行 `SELF-CHECK <id> passed=<n> failed=<n>`；有 FAIL 时以退出码 1 结束。
//! Harness 没有 `windowRegionAt` 的 RPC，所以 V-11 的命中判定在这里直接调 `Cx.windowRegionAt`
//! （原生层在 mouseDown 时调用的同一个函数）。
const std = @import("std");
const ui = @import("ui");
const zenit_app = @import("zenit_app");
const App = zenit_app.App;
const m = @import("../model/view_model.zig");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
const settings_shell = @import("../view/settings_shell.zig");
const preview_host = @import("preview_host.zig");
const runner = @import("settings_preview_runner.zig");
const Host = preview_host.Host;
const findTestId = preview_host.findTestId;
const countTestId = preview_host.countTestId;

// ── 报告 ──

var passed: u32 = 0;
var failed: u32 = 0;
var check_id: []const u8 = "V-?";

pub fn report(id: []const u8, ok: bool, comptime fmt: []const u8, args: anytype) void {
    check_id = id;
    if (ok) passed += 1 else failed += 1;
    std.debug.print("{s} {s} " ++ fmt ++ "\n", .{ if (ok) "PASS" else "FAIL", id } ++ args);
}
pub fn info(id: []const u8, comptime fmt: []const u8, args: anytype) void {
    std.debug.print("INFO {s} " ++ fmt ++ "\n", .{id} ++ args);
}
pub fn finish() void {
    std.debug.print("SELF-CHECK {s} passed={d} failed={d}\n", .{ check_id, passed, failed });
    if (failed != 0) std.process.exit(1);
}

// ── 计数分配器：存活字节 / 存活块数（线程安全） ──

pub const CountingAllocator = struct {
    child: std.mem.Allocator,
    live_bytes: std.atomic.Value(isize) = .init(0),
    live_blocks: std.atomic.Value(isize) = .init(0),

    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    pub fn bytes(self: *const CountingAllocator) isize {
        return self.live_bytes.load(.acquire);
    }
    pub fn blocks(self: *const CountingAllocator) isize {
        return self.live_blocks.load(.acquire);
    }
    fn alloc(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(raw));
        const ptr = self.child.rawAlloc(len, alignment, ret) orelse return null;
        _ = self.live_bytes.fetchAdd(@intCast(len), .acq_rel);
        _ = self.live_blocks.fetchAdd(1, .acq_rel);
        return ptr;
    }
    fn resize(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(raw));
        if (!self.child.rawResize(memory, alignment, new_len, ret)) return false;
        _ = self.live_bytes.fetchAdd(@as(isize, @intCast(new_len)) - @as(isize, @intCast(memory.len)), .acq_rel);
        return true;
    }
    fn remap(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(raw));
        const ptr = self.child.rawRemap(memory, alignment, new_len, ret) orelse return null;
        _ = self.live_bytes.fetchAdd(@as(isize, @intCast(new_len)) - @as(isize, @intCast(memory.len)), .acq_rel);
        return ptr;
    }
    fn free(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(raw));
        self.child.rawFree(memory, alignment, ret);
        _ = self.live_bytes.fetchSub(@intCast(memory.len), .acq_rel);
        _ = self.live_blocks.fetchSub(1, .acq_rel);
    }
};

// ── V-7 探针 ──

/// 主窗口 scope 上的信号与 effect。
pub const MainProbe = struct {
    scope: *ui.Scope,
    signal: *ui.Signal(u32),
    runs: u32 = 0,
    cross_scope: ?*ui.Scope = null,
    cross_source: ?*ui.Signal(m.Location) = null,
    cross_runs: u32 = 0,

    pub fn create(scope: *ui.Scope) !*MainProbe {
        const self = try scope.createState(MainProbe, .{ .scope = scope, .signal = undefined });
        self.signal = try scope.createSignal(u32, 0);
        try scope.createEffect(self, run);
        return self;
    }
    fn run(self: *MainProbe) void {
        _ = self.signal.get();
        self.runs += 1;
    }
    /// 主窗口子 scope 上的 effect，故意读设置窗口的信号（跨窗口读取）。
    pub fn watchSettings(self: *MainProbe, location: *ui.Signal(m.Location)) !void {
        const scope = try self.scope.childScope();
        self.cross_scope = scope;
        self.cross_source = location;
        try scope.createEffect(self, crossRun);
    }
    fn crossRun(self: *MainProbe) void {
        if (self.cross_source) |source| _ = source.get();
        self.cross_runs += 1;
    }
    pub fn unwatch(self: *MainProbe) void {
        if (self.cross_scope) |scope| scope.dispose();
        self.cross_scope = null;
        self.cross_source = null;
    }
};

/// 设置窗口 scope 上的 effect（读 view-model 投影信号）；随窗口 scope 释放。
const SettingsProbe = struct {
    vm: *m.ViewModel,
    runs: u32 = 0,
    var current: ?*SettingsProbe = null;
    var cleanups: u32 = 0;
    var created: u32 = 0;

    fn mounted(host: *Host, _: *ui.Cx, scope: *ui.Scope) anyerror!void {
        const self = try scope.createState(SettingsProbe, .{ .vm = &host.vm });
        try scope.onCleanup(SettingsProbe, self, cleanup);
        try scope.createEffect(self, run);
        current = self;
        created += 1;
    }
    fn run(self: *SettingsProbe) void {
        const signals = self.vm.signals orelse return;
        _ = signals.location.get();
        _ = signals.title.get();
        self.runs += 1;
    }
    fn cleanup(self: *SettingsProbe) void {
        if (current == self) current = null;
        cleanups += 1;
    }
};

fn locationEql(a: m.Location, b: m.Location) bool {
    return a.page == b.page and a.sub == b.sub;
}

fn openSettings(rt: *runner.Runtime) !*App {
    _ = rt.host.slot.present();
    if (!try rt.ticks(30)) return error.ApplicationEnded;
    const app = rt.settingsApp() orelse return error.SettingsWindowMissing;
    app.rebindTestHarness();
    return app;
}

/// 原生关闭有约 250 ms 的保留期（macos_window_close_complete retention），App 与窗口 scope 在那之后
/// 才销毁：一直 tick 到 aux 槽回到 .closed（destroyed 回调已执行）为止。
fn closeSettings(rt: *runner.Runtime) !void {
    const before = rt.app.windowCount();
    rt.host.slot.close();
    var waited: usize = 0;
    while (rt.host.slot.phase != .closed or rt.app.windowCount() >= before) : (waited += 1) {
        if (waited > 600) return error.SettingsWindowDidNotClose;
        if (!try rt.ticks(1)) return error.ApplicationEnded;
    }
    if (!try rt.ticks(3)) return error.ApplicationEnded;
}

pub fn runV7(rt: *runner.Runtime) !void {
    const id = "V-7";
    const host = rt.host;
    const counting = rt.counting;
    host.on_mounted = SettingsProbe.mounted;
    // 窗口已在 runWindow 里创建：探针从第二次挂载起自动挂上；第一次在这里补挂到窗口 scope。
    if (!try rt.ticks(30)) return error.ApplicationEnded;
    const main_app = rt.app.window(rt.main_id orelse return error.MainWindowMissing) orelse return error.MainWindowMissing;
    const settings_app = rt.settingsApp() orelse return error.SettingsWindowMissing;
    try SettingsProbe.mounted(host, settings_app.cx, host.scope.?);
    if (!try rt.ticks(5)) return error.ApplicationEnded;
    const main_probe = runner.MainWindow.probe orelse return error.MainProbeMissing;
    const probe = SettingsProbe.current orelse return error.SettingsProbeMissing;
    const signals = host.vm.signals orelse return error.ViewModelDetached;

    // 1. 两个窗口、两套反应式所有者
    report(id, settings_app.cx != main_app.cx and settings_app.cx.owner != main_app.cx.owner, "主窗口与设置窗口各有自己的 Cx 与 SignalOwner（window_id 主={d} 设置={d}）", .{ main_app.windowId(), settings_app.windowId() });
    report(id, host.vm.attached() and host.counters.attach == 1, "view-model 投影信号 attach 在设置窗口的 root scope 上（attach={d}）", .{host.counters.attach});
    report(id, signals.location.owner == settings_app.cx.owner and signals.location.owner != main_app.cx.owner, "投影信号归设置窗口的 SignalOwner 所有，不归主窗口", .{});

    // 2. 设置信号变化：设置侧 effect 重算；主窗口 effect（含故意跨窗口读取的 effect）不重算
    try main_probe.watchSettings(signals.location);
    const s0 = probe.runs;
    const m0 = main_probe.runs;
    const c0 = main_probe.cross_runs;
    host.vm.dispatch(m.Intent.selectCategory(2));
    if (!try rt.ticks(10)) return error.ApplicationEnded;
    report(id, probe.runs > s0, "设置窗口 scope 上的 effect 随投影信号重算（{d} → {d}）", .{ s0, probe.runs });
    report(id, main_probe.runs == m0, "主窗口自己的 effect 不因设置信号变化重算（{d} → {d}）", .{ m0, main_probe.runs });
    report(id, main_probe.cross_runs == c0, "主窗口 effect 即使读了设置窗口的信号也不被订阅（{d} → {d}；跨 SignalOwner 读取不建立依赖）", .{ c0, main_probe.cross_runs });
    main_probe.unwatch();

    // 3. 主窗口信号变化：只重算主窗口 effect
    const s1 = probe.runs;
    main_probe.signal.set(main_probe.signal.peek() + 1);
    if (!try rt.ticks(5)) return error.ApplicationEnded;
    report(id, main_probe.runs == m0 + 1, "主窗口信号变化重算主窗口 effect（{d} → {d}）", .{ m0, main_probe.runs });
    report(id, probe.runs == s1, "主窗口信号变化不触发设置窗口 effect（{d} → {d}）", .{ s1, probe.runs });

    // 4. 主题：app_theme 的选择是进程级全局，设置窗口每帧跟随它
    const selected = theme.currentName();
    const other: theme.Name = if (selected == .dark) .light else .dark;
    const republish0 = host.counters.theme_republish;
    theme.select(other);
    settings_app.cx.requestRedraw();
    if (!try rt.ticks(10)) return error.ApplicationEnded;
    info(id, "主题是进程级全局（app_theme.select）：在主窗口侧切到 {s} 后，设置窗口重新发布主题 {d} 次并跟随；两个窗口不能各用一个主题", .{ @tagName(other), host.counters.theme_republish - republish0 });
    report(id, host.counters.theme_republish > republish0, "设置窗口跟随进程主题（与生产 WindowHook 相同）", .{});
    theme.select(selected);
    if (!try rt.ticks(10)) return error.ApplicationEnded;

    // 5. 关闭前：持久状态（位置、草稿）与瞬时状态（搜索词、搜索框文字）
    host.vm.dispatch(m.Intent.editValue(.{ .section = "ssh", .key = "keepalive_sec" }, .{ .unsigned = 45 }));
    host.vm.dispatch(m.Intent.searchFor("超时"));
    if (!try rt.ticks(10)) return error.ApplicationEnded;
    const location_before = host.controller.location();
    const reopen_page = host.controller.search_return_page;
    report(id, host.controller.model.dirty and host.vm.signals.?.dirty.peek(), "关闭前：草稿已改（ssh.keepalive_sec=45，dirty 信号为真）", .{});
    report(id, host.vm.signals.?.query.peek().len != 0, "关闭前：搜索中（query 信号 = \"{s}\"）", .{host.vm.signals.?.query.peek()});
    const live_open = counting.bytes();
    const blocks_open = counting.blocks();
    const cleanups0 = SettingsProbe.cleanups;
    const window_cleanups0 = host.counters.window_cleanups;

    // 6. 关闭设置窗口
    try closeSettings(rt);
    report(id, rt.app.windowCount() == 1 and rt.app.window(main_app.windowId()) != null, "关闭设置窗口后只剩主窗口（windowCount={d}）", .{rt.app.windowCount()});
    report(id, !host.vm.attached() and host.counters.detach == 1, "窗口 scope 销毁时执行 ViewModel.detach（detach={d}）", .{host.counters.detach});
    report(id, host.counters.window_cleanups == window_cleanups0 + 1 and SettingsProbe.cleanups == cleanups0 + 1 and SettingsProbe.current == null, "窗口 scope 的 cleanup 全部执行（宿主钩子 +1、探针 +1）", .{});
    const live_closed = counting.bytes();
    const blocks_closed = counting.blocks();
    report(id, live_closed < live_open and blocks_closed < blocks_open, "关闭后存活内存下降：{d} B / {d} 块 → {d} B / {d} 块（窗口 Cx、scope、投影信号一并释放）", .{ live_open, blocks_open, live_closed, blocks_closed });
    const m1 = main_probe.runs;
    main_probe.signal.set(main_probe.signal.peek() + 1);
    if (!try rt.ticks(3)) return error.ApplicationEnded;
    report(id, main_probe.runs == m1 + 1, "设置窗口关闭后主窗口的信号与 effect 照常工作", .{});

    // 7. 再次打开：全新的信号，状态来自 Controller
    host.reopenLocation();
    const reopened = try openSettings(rt);
    _ = reopened;
    const fresh = host.vm.signals orelse return error.ViewModelDetached;
    report(id, host.counters.attach == 2 and SettingsProbe.created == 2 and SettingsProbe.current != null, "再次打开：重新 attach，窗口 scope 上的探针是新实例（attach={d}）", .{host.counters.attach});
    const expected: m.Location = if (reopen_page) |page| .{ .page = @intCast(page), .sub = host.controller.search_return_subpage } else location_before;
    report(id, locationEql(fresh.location.peek(), expected) and locationEql(fresh.location.peek(), host.controller.location()), "持久：位置来自 Controller（page={d}；关闭前在搜索，回到搜索起点）", .{fresh.location.peek().page});
    report(id, fresh.dirty.peek() and host.controller.model.dirty and host.controller.model.value.ssh.keepalive_sec == 45, "持久：未保存草稿保留（dirty 信号为真，keepalive_sec=45）", .{});
    const field_text = host.searchFieldText();
    report(id, fresh.query.peek().len == 0 and field_text.len == 0, "瞬时：搜索词与搜索框文字复位（query=\"{s}\"，输入框=\"{s}\"）", .{ fresh.query.peek(), field_text });
    report(id, !fresh.can_back.peek() and !fresh.can_forward.peek(), "瞬时：历史从当前位置重新开始（后退 / 前进不可用）", .{});

    // 8. 反复开关：存活内存不随轮次增长
    var closed_samples: [4]isize = undefined;
    for (&closed_samples, 0..) |*sample, round| {
        try closeSettings(rt);
        sample.* = counting.bytes();
        if (round + 1 < closed_samples.len) {
            host.reopenLocation();
            _ = try openSettings(rt);
        }
    }
    var low = closed_samples[0];
    var high = closed_samples[0];
    for (closed_samples) |sample| {
        low = @min(low, sample);
        high = @max(high, sample);
    }
    info(id, "关闭态存活字节（4 轮）：{d} / {d} / {d} / {d}", .{ closed_samples[0], closed_samples[1], closed_samples[2], closed_samples[3] });
    report(id, high - low <= 64 * 1024, "反复开关 4 轮，关闭态存活内存波动 {d} B（阈值 64 KiB，不随轮次累积）", .{high - low});
    report(id, host.counters.detach == host.counters.attach, "attach / detach 成对（{d} / {d}）", .{ host.counters.attach, host.counters.detach });

    // 结束：关主窗口，循环退出；DebugAllocator 的泄漏判定在 runWindow 的 defer 里。
    _ = rt.app.closeWindow(main_app.windowId());
    while (try rt.ticks(1)) {}
}

// ── V-11 ──

const Point = struct { name: []const u8, x: f32, y: f32, expect: ?zenit_app.window_chrome.Region };

fn center(root: *ui.Node, test_id: []const u8) ?struct { x: f32, y: f32 } {
    const node = findTestId(root, test_id) orelse return null;
    const r = node.globalRect();
    return .{ .x = r.x + r.w / 2, .y = r.y + r.h / 2 };
}

fn printRect(id: []const u8, root: *ui.Node, test_id: []const u8) void {
    const node = findTestId(root, test_id) orelse {
        info(id, "rect {s} = <missing>", .{test_id});
        return;
    };
    const r = node.globalRect();
    info(id, "rect {s} = {d:.1},{d:.1} {d:.1}x{d:.1}", .{ test_id, r.x, r.y, r.w, r.h });
}

/// 指针命中的交互目标是不是一个真正的控件（排除整窗卡片：宿主让它 focusable 只为接住按键；也排除声明为拖动区的
/// 节点——浮动页头拦截命中只为挡住滚到它底下的正文，空白处是标题栏拖动带，见 `view/header.yix`）。
fn controlAt(cx: *ui.Cx, card: *ui.Node, x: f32, y: f32) bool {
    const target = cx.hitTest(x, y) orelse return false;
    return target != card and target.behavior.interaction.window_region != .drag;
}

const Grid = struct {
    count: u32 = 0,
    box: [4]f32 = .{ 1e9, 1e9, -1, -1 },
    fn add(self: *Grid, x: f32, y: f32) void {
        self.count += 1;
        self.box = .{ @min(self.box[0], x), @min(self.box[1], y), @max(self.box[2], x), @max(self.box[3], y) };
    }
};
const step_x: f32 = 4;
const step_y: f32 = 2;

pub fn runV11(rt: *runner.Runtime) !void {
    const id = "V-11";
    if (!try rt.ticks(40)) return error.ApplicationEnded;
    const app = rt.settingsApp() orelse return error.SettingsWindowMissing;
    const cx = app.cx;
    const root = cx.root orelse return error.SettingsWindowShape;
    const card = rt.host.card orelse return error.SettingsWindowShape;
    const state = app.chromeState();
    info(id, "requested={s} effective={s} controls={s} native_titlebar_height={d:.1} maximizable={}", .{ @tagName(state.requested_mode), @tagName(state.effective_mode), @tagName(state.controls_owner), app.win.getTitlebarHeight(), state.capabilities.maximize });
    info(id, "viewport={d:.0}x{d:.0}", .{ app.viewport_w, app.viewport_h });
    for ([_][]const u8{ "settings.window", "settings.panel", "settings.navigation", "settings.header", "settings.header.traffic_lights", "settings.search", "settings.island", "settings.page.intro", "settings.page.title", "settings.history.back", "settings.help", "settings.viewport" }) |test_id| printRect(id, root, test_id);
    report(id, state.requested_mode == .custom and state.effective_mode == .custom and state.controls_owner == .native, "window chrome：请求 / 生效 .custom，红绿灯归原生（{s} / {s} / {s}）", .{ @tagName(state.requested_mode), @tagName(state.effective_mode), @tagName(state.controls_owner) });
    report(id, app.viewport_w == 960 and app.viewport_h == 780, "窗口内容尺寸与生产一致 960x780（实际 {d:.0}x{d:.0}）", .{ app.viewport_w, app.viewport_h });

    cx.publishWindowRegions();
    const width = app.viewport_w;
    var points: [16]Point = undefined;
    var count: usize = 0;
    const header = findTestId(root, "settings.header") orelse return error.SettingsWindowShape;
    const hr = header.globalRect();
    const lights = (findTestId(root, "settings.header.traffic_lights") orelse return error.SettingsWindowShape).globalRect();
    const intro = (findTestId(root, "settings.page.intro") orelse return error.SettingsWindowShape).globalRect();
    const title = (findTestId(root, "settings.page.title") orelse return error.SettingsWindowShape).globalRect();
    const help = (findTestId(root, "settings.help") orelse return error.SettingsWindowShape).globalRect();
    const drag: zenit_app.window_chrome.Region = .drag;
    const client: zenit_app.window_chrome.Region = .client;
    points[count] = .{ .name = "导航窗口顶空白（红绿灯右侧）", .x = hr.x + hr.w - 12, .y = hr.y + hr.h / 2, .expect = drag };
    count += 1;
    points[count] = .{ .name = "导航上方的窗口顶边", .x = hr.x + hr.w - 12, .y = 3, .expect = drag };
    count += 1;
    points[count] = .{ .name = "红绿灯占位中心（原生按钮优先）", .x = lights.x + lights.w / 2, .y = lights.y + lights.h / 2, .expect = drag };
    count += 1;
    points[count] = .{ .name = "页头标题文字", .x = title.x + @min(title.w / 2, 20), .y = title.y + title.h / 2, .expect = drag };
    count += 1;
    points[count] = .{ .name = "页头标题与帮助之间的空白", .x = (title.x + title.w + help.x) / 2, .y = intro.y + intro.h / 2, .expect = drag };
    count += 1;
    inline for (.{ .{ "搜索框", "settings.search" }, .{ "导航行（SSH 与网络）", "settings.nav.ssh" }, .{ "后退按钮", "settings.history.back" }, .{ "前进按钮", "settings.history.forward" }, .{ "帮助按钮", "settings.help" }, .{ "内容视口", "settings.viewport" } }) |entry| {
        if (center(root, entry[1])) |c| {
            points[count] = .{ .name = entry[0], .x = c.x, .y = c.y, .expect = client };
            count += 1;
        } else info(id, "missing {s}", .{entry[1]});
    }
    for (points[0..count]) |p| {
        const region = cx.windowRegionAt(p.x, p.y);
        report(id, region == p.expect.?, "windowRegionAt {s} ({d:.0},{d:.0}) = .{s}（期望 .{s}）", .{ p.name, p.x, p.y, @tagName(region), @tagName(p.expect.?) });
    }

    // 整窗网格：拖动点都在标题栏高度内（页头底边以上），且没有一个落在真正的控件上。
    var region: Grid = .{};
    var conflicts: Grid = .{};
    var below: Grid = .{};
    const title_bottom = intro.y + intro.h;
    var y: f32 = 0;
    while (y < app.viewport_h) : (y += step_y) {
        var x: f32 = 0;
        while (x < width) : (x += step_x) {
            if (cx.windowRegionAt(x, y) != .drag) continue;
            region.add(x, y);
            if (controlAt(cx, card, x, y)) conflicts.add(x, y);
            if (y >= title_bottom) below.add(x, y);
        }
    }
    info(id, "网格步长 {d:.0}x{d:.0}：拖动 {d} 点（x {d:.0}..{d:.0}, y {d:.0}..{d:.0}）", .{ step_x, step_y, region.count, region.box[0], region.box[2], region.box[1], region.box[3] });
    report(id, region.count > 0, "标题栏有拖动点（{d}）", .{region.count});
    report(id, conflicts.count == 0, "拖动区内没有交互控件（指针命中目标是按钮 / 输入框 / 导航行的点 = {d}）", .{conflicts.count});
    report(id, below.count == 0, "页头底边（y = {d:.0}）以下没有拖动点（{d}）", .{ title_bottom, below.count });
    _ = rt.app.closeWindow(app.windowId());
    while (try rt.ticks(1)) {}
}
