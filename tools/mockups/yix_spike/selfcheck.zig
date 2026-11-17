//! yix_spike 自检：`YIX_SPIKE_SELFCHECK=1 mockup-yix_spike` 启动后在无窗口 Cx 上逐项断言，
//! 输出 `PASS/FAIL V-x …` 行，最后一行是 `SELFCHECK <pass>/<total>`，然后退出（失败时退出码 1）。
//! 写法与 vendor/zenit/tests/yix/runtime_tests.zig 的 `Env` 一致：`ui.Cx.init` + `ui.view.render`，
//! 信号 `set` 同步传播，所以断言可以紧跟在 `set` 之后。
const std = @import("std");
const ui = @import("ui");
const views = @import("_views.yix.zig");
const m = @import("vm.zig");
const legacy = @import("legacy.zig");

var passed: usize = 0;
var total: usize = 0;

fn check(comptime id: []const u8, ok: bool, comptime what: []const u8, args: anytype) void {
    total += 1;
    if (ok) passed += 1;
    std.debug.print("{s} {s} " ++ what ++ "\n", .{ if (ok) "PASS" else "FAIL", id } ++ args);
}

const Env = struct {
    gpa: *std.heap.DebugAllocator(.{}),
    cx: *ui.Cx,
    scope: *ui.Scope,
    root: ?*ui.Node = null,

    fn init(io: std.Io) !Env {
        const gpa = try std.heap.c_allocator.create(std.heap.DebugAllocator(.{}));
        gpa.* = .init;
        const a = gpa.allocator();
        const cx = try ui.Cx.init(a, io);
        return .{ .gpa = gpa, .cx = cx, .scope = try ui.Scope.init(a, null, cx.owner) };
    }
    /// 返回 DebugAllocator 是否检测到泄漏。
    fn deinit(e: *Env) bool {
        e.cx.root = null;
        e.scope.dispose();
        if (e.root) |r| e.cx.freeNode(r);
        e.cx.deinit();
        const leaked = e.gpa.deinit() == .leak;
        std.heap.c_allocator.destroy(e.gpa);
        return leaked;
    }
    fn mount(e: *Env, element: anytype) !void {
        e.root = try ui.view.render(e.scope, e.cx, element);
    }
    fn find(e: *Env, id: []const u8) ?*ui.Node {
        return findId(e.root orelse return null, id);
    }
    fn text(e: *Env, id: []const u8) []const u8 {
        const n = e.find(id) orelse return "<missing>";
        return firstText(n) orelse "<no text>";
    }
    fn click(e: *Env, id: []const u8) bool {
        var n = e.find(id) orelse return false;
        while (n.behavior.events.on_click == null) n = n.parent orelse return false;
        n.behavior.events.on_click.?.invoke();
        return true;
    }
    fn shown(e: *Env, id: []const u8) bool {
        const n = e.find(id) orelse return false;
        return n.style.display != .none;
    }
};

fn findId(n: *ui.Node, id: []const u8) ?*ui.Node {
    if (n.meta.ownership.meta.test_id) |t| if (std.mem.eql(u8, t, id)) return n;
    for (n.children.items) |c| if (findId(c, id)) |r| return r;
    return null;
}
fn firstText(n: *ui.Node) ?[]const u8 {
    if (n.getText()) |t| return t.content;
    for (n.children.items) |c| if (firstText(c)) |r| return r;
    return null;
}
fn countText(n: *ui.Node) usize {
    var k: usize = if (n.getText() != null) 1 else 0;
    for (n.children.items) |c| k += countText(c);
    return k;
}
fn eqs(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}
fn a11yDisabled(n: ?*ui.Node) ?bool {
    const node = n orelse return null;
    const a = node.behavior.interaction.a11y orelse return null;
    return a.disabled;
}

pub fn run(io: std.Io) u8 {
    runAll(io) catch |err| {
        check("ERR", false, "selfcheck aborted: {s}", .{@errorName(err)});
    };
    std.debug.print("SELFCHECK {d}/{d}\n", .{ passed, total });
    return if (passed == total) 0 else 1;
}

fn runAll(io: std.Io) !void {
    try checkV1(io);
    try checkV2(io);
    try checkV3(io);
    try checkV4(io);
    try checkV5(io);
    try checkV11(io);
}

// ── V-1：子目录组件经 ../ import 后可编译、可响应 ──
fn checkV1(io: std.Io) !void {
    var e = try Env.init(io);
    const vm = try m.ViewModel.init(e.scope);
    try e.mount(views.ImportPanel(.{ .vm = vm }));
    check("V-1", eqs(e.text("spike.v1.count"), "1"), "parts/count_row.yix (imports ../vm.zig, ../styles.yss) renders count={s}", .{e.text("spike.v1.count")});
    vm.count.set(7);
    check("V-1", eqs(e.text("spike.v1.count"), "7"), "subdirectory component follows vm.count -> {s}", .{e.text("spike.v1.count")});
    check("V-1", !e.deinit(), "no leak", .{});
}

// ── V-2：*ViewModel 参数 + 选择器函数跟随信号 ──
fn checkV2(io: std.Io) !void {
    var e = try Env.init(io);
    const vm = try m.ViewModel.init(e.scope);
    try e.mount(views.SelectorPanel(.{ .vm = vm }));
    const runs0 = vm.selector_runs;
    check("V-2", eqs(e.text("spike.v2.title"), "概览"), "titleOf(vm) initial = {s} (selector runs at mount = {d})", .{ e.text("spike.v2.title"), runs0 });
    vm.title.set("子页面");
    check("V-2", eqs(e.text("spike.v2.title"), "子页面") and vm.selector_runs == runs0 + 1, "vm.title.set -> text={s}, selector re-ran {d}x", .{ e.text("spike.v2.title"), vm.selector_runs - runs0 });
    vm.title.set("子页面");
    check("V-2", vm.selector_runs == runs0 + 1, "same content set() does not re-run selector (runs={d})", .{vm.selector_runs - runs0});
    vm.count.set(99);
    check("V-2", vm.selector_runs == runs0 + 1, "unrelated signal (count) does not re-run titleOf (runs={d})", .{vm.selector_runs - runs0});
    const hint_before = e.shown("spike.v2.back_hint");
    vm.can_back.set(true);
    check("V-2", hint_before and !e.shown("spike.v2.back_hint"), "visible={{cannotBack(vm)}} follows can_back ({} -> {})", .{ hint_before, e.shown("spike.v2.back_hint") });
    const mode_before = try std.heap.c_allocator.dupe(u8, e.text("spike.v2.mode"));
    defer std.heap.c_allocator.free(mode_before);
    vm.mode.set(.panes);
    check("V-2", eqs(mode_before, "overview") and eqs(e.text("spike.v2.mode"), "panes"), "switch (modeOf(vm)) re-branches {s} -> {s}", .{ mode_before, e.text("spike.v2.mode") });
    check("V-2", !e.deinit(), "no leak", .{});
}

// ── V-3：onClick={send(vm, .back)} 在点击时求值，处理器里无追踪观察者 ──
fn checkV3(io: std.Io) !void {
    var e = try Env.init(io);
    const vm = try m.ViewModel.init(e.scope);
    try e.mount(views.EventPanel(.{ .vm = vm }));
    check("V-3", vm.send_calls == 0 and vm.dispatched == 0, "mount does not evaluate handlers (send_calls={d})", .{vm.send_calls});
    check("V-3", a11yDisabled(e.find("spike.v3.back")) == true, "back disabled={{cannotBack(vm)}} initially disabled={?}", .{a11yDisabled(e.find("spike.v3.back"))});
    _ = e.click("spike.v3.forward");
    check("V-3", vm.send_calls == 1 and vm.last != null and vm.last.? == .forward, "click forward -> send(vm, .forward) once, last={s}", .{if (vm.last) |l| @tagName(l) else "null"});
    check("V-3", vm.tracking_depth_in_dispatch == 0, "inside handler tracking_stack depth={d} (0 = .get() acts as peek, no subscription)", .{vm.tracking_depth_in_dispatch});
    check("V-3", a11yDisabled(e.find("spike.v3.back")) == false, "state written by handler propagates (back disabled -> {?})", .{a11yDisabled(e.find("spike.v3.back"))});
    const before = vm.send_calls;
    vm.count.set(42);
    vm.title.set("外部修改");
    check("V-3", vm.send_calls == before, "signals read in handler do not re-run it (send_calls still {d})", .{vm.send_calls});
    _ = e.click("spike.v3.add");
    check("V-3", vm.last != null and vm.last.? == .set_count and vm.count.peek() == 47, "@unionInit(m.Intent, \"set_count\", 5) payload -> count={d}", .{vm.count.peek()});
    _ = e.click("spike.v3.host");
    check("V-3", vm.last != null and vm.last.? == .toggle_flag, "host <box onClick={{send(vm, .toggle_flag)}}> works, last={s}", .{if (vm.last) |l| @tagName(l) else "null"});
    // toggle_flag 让 can_back=false，后退按钮此时禁用：禁用的 W.Button 不触发处理器。
    const disabled_back = a11yDisabled(e.find("spike.v3.back")) == true;
    _ = e.click("spike.v3.back");
    check("V-3", disabled_back and vm.send_calls == 3, "disabled W.Button swallows the click (send_calls stays {d})", .{vm.send_calls});
    _ = e.click("spike.v3.forward");
    _ = e.click("spike.v3.back");
    check("V-3", vm.send_calls == 5 and vm.last.? == .back, "each click re-evaluates the call (send_calls={d}, expected 5)", .{vm.send_calls});
    check("V-3", !e.deinit(), "no leak", .{});
}

// ── V-4：模板里直接写 vm.<信号字段> ──
fn checkV4(io: std.Io) !void {
    var e = try Env.init(io);
    const vm = try m.ViewModel.init(e.scope);
    try e.mount(ui.view.col(.{}, .{
        views.DirectPanel(.{ .vm = vm }),
        views.DirectIf(.{ .vm = vm }),
        views.DirectSwitch(.{ .vm = vm }),
        views.DirectOptional(.{ .vm = vm }),
        views.DirectFor(.{ .vm = vm }),
    }));
    // 直接插值 {vm.field} 现在编译期就被 zenit 拒绝（反例无法再写进视图），视图改为内联 .get()：渲染的是值、随 set 更新。
    inline for (.{ "spike.v4.title", "spike.v4.count", "spike.v4.doubled", "spike.v4.mode", "spike.v4.flag" }) |id| {
        const t = e.text(id);
        check("V-4", !isDump(t), "{{vm.field.get()}} " ++ id ++ " renders a value: {s}", .{t[0..@min(t.len, 48)]});
    }
    vm.title.set("改名");
    vm.count.set(5);
    vm.mode.set(.search);
    vm.can_back.set(true);
    check("V-4", eqs(e.text("spike.v4.title"), "改名"), "{{vm.title.get()}} tracks set -> {s}", .{e.text("spike.v4.title")});
    check("V-4", eqs(e.text("spike.v4.count"), "count=5"), "count={{vm.count.get()}} tracks set -> {s}", .{e.text("spike.v4.count")});
    check("V-4", eqs(e.text("spike.v4.inline_get"), "105"), "{{vm.count.get() + 100}} inline .get() tracks -> {s}", .{e.text("spike.v4.inline_get")});
    check("V-4", e.shown("spike.v4.visible"), "visible={{vm.can_back.get()}} follows -> shown={}", .{e.shown("spike.v4.visible")});
    check("V-4", a11yDisabled(e.find("spike.v4.disabled")) == true, "W.Button disabled={{vm.can_back.get()}} follows -> {?}", .{a11yDisabled(e.find("spike.v4.disabled"))});
    check("V-4", eqs(e.text("spike.v4.if"), "yes"), "{{if (vm.can_back.get())}} re-branches -> {s}", .{e.text("spike.v4.if")});
    check("V-4", eqs(e.text("spike.v4.switch"), "search"), "{{switch (vm.mode.get())}} re-branches -> {s}", .{e.text("spike.v4.switch")});
    const opt0 = try std.heap.c_allocator.dupe(u8, e.text("spike.v4.opt"));
    defer std.heap.c_allocator.free(opt0);
    vm.note.set("有备注");
    check("V-4", eqs(opt0, "none") and eqs(e.text("spike.v4.opt"), "有备注"), "{{if (vm.note.get()) |n|}} capture {s} -> {s}", .{ opt0, e.text("spike.v4.opt") });
    const rows0 = countText(e.find("spike.v4.for_root").?);
    vm.rows.set(m.list_b);
    const rows1 = countText(e.find("spike.v4.for_root").?);
    vm.rows.set(&.{});
    const rows2 = try std.heap.c_allocator.dupe(u8, e.text("spike.v4.for_root"));
    defer std.heap.c_allocator.free(rows2);
    check("V-4", rows0 == 2 and rows1 == 3 and eqs(rows2, "empty"), "{{for (vm.rows.get()) |r|}} rows {d} -> {d} -> {s}", .{ rows0, rows1, rows2 });
    check("V-4", !e.deinit(), "no leak", .{});
}

// ── V-5：旧命令式面板经 ComponentOf 嵌入 ──
fn checkV5(io: std.Io) !void {
    var e = try Env.init(io);
    legacy.probe = .{};
    const vm = try m.ViewModel.init(e.scope);
    const hooks0 = e.cx.after_layout_hooks.items.len;
    try e.mount(views.LegacyHost(.{ .vm = vm }));
    e.cx.root = e.root;
    const ids = [_][]const u8{ "spike.v5.legacy", "spike.v5.legacy.title", "spike.v5.legacy.badge", "spike.v5.legacy.swatch", "spike.v5.legacy.button" };
    var found: usize = 0;
    for (ids) |id| found += @intFromBool(e.find(id) != null);
    check("V-5", legacy.probe.mounts == 1 and found == ids.len, "embedded legacy panel mounted once; {d}/{d} legacy test_ids found by tree walk", .{ found, ids.len });

    for ([_]*const ui.ThemeTokens{ &ui.theme.modes.dark, &ui.theme.modes.light, &ui.theme.modes.dark }) |t| {
        const effects0 = legacy.probe.theme_effect_runs;
        const ink0 = legacy.probe.ink_hook_runs;
        e.cx.setTheme(t);
        const c = t.tokens.color;
        const pane = e.find("spike.v5.legacy").?;
        const title = e.find("spike.v5.legacy.title").?;
        const badge = e.find("spike.v5.legacy.badge").?;
        const swatch = e.find("spike.v5.legacy.swatch").?;
        const ok = ui.Color.eql(pane.getBackground(), c.bg_secondary) and
            ui.Color.eql(title.getText().?.color, c.fg_primary) and
            ui.Color.eql(badge.getText().?.color, c.fg_secondary) and
            ui.Color.eql(swatch.getBackground(), c.bg_tertiary) and
            legacy.probe.theme_effect_runs == effects0 + 1 and legacy.probe.ink_hook_runs == ink0 + 1;
        check("V-5", ok, "setTheme({s}): boxStyled/textStyled replay, on_theme hook (+{d}), themeSignal effect (+{d}) all follow", .{ if (t == &ui.theme.modes.dark) "dark" else "light", legacy.probe.ink_hook_runs - ink0, legacy.probe.theme_effect_runs - effects0 });
    }
    check("V-5", e.click("spike.v5.legacy.button") and legacy.probe.clicks == 1, "legacy W.Button cx.on handler fires (clicks={d})", .{legacy.probe.clicks});
    check("V-5", e.cx.after_layout_hooks.items.len == hooks0 + 1, "legacy addAfterLayoutHook registered (hooks {d} -> {d})", .{ hooks0, e.cx.after_layout_hooks.items.len });

    // 卸载分支
    _ = e.click("spike.v5.toggle");
    check("V-5", !vm.legacy_shown.peek() and legacy.probe.cleanups == 1 and legacy.probe.live == 0 and e.find("spike.v5.legacy") == null, "branch unmount -> scope.onCleanup ran (cleanups={d}, live={d}), node gone", .{ legacy.probe.cleanups, legacy.probe.live });
    check("V-5", e.cx.after_layout_hooks.items.len == hooks0, "after-layout hook removed by cleanup (hooks={d})", .{e.cx.after_layout_hooks.items.len});
    const effects1 = legacy.probe.theme_effect_runs;
    const ink1 = legacy.probe.ink_hook_runs;
    e.cx.setTheme(&ui.theme.modes.light);
    check("V-5", legacy.probe.theme_effect_runs == effects1 and legacy.probe.ink_hook_runs == ink1, "after unmount theme effect / hook no longer run (effects +{d}, hooks +{d})", .{ legacy.probe.theme_effect_runs - effects1, legacy.probe.ink_hook_runs - ink1 });

    // 反复挂载 / 卸载
    for (0..20) |_| {
        _ = e.click("spike.v5.toggle");
        _ = e.click("spike.v5.toggle");
    }
    check("V-5", legacy.probe.mounts == 21 and legacy.probe.cleanups == 21 and legacy.probe.live == 0 and e.cx.after_layout_hooks.items.len == hooks0, "20 more mount/unmount cycles: mounts={d} cleanups={d} live={d}", .{ legacy.probe.mounts, legacy.probe.cleanups, legacy.probe.live });
    _ = e.click("spike.v5.toggle");
    check("V-5", e.find("spike.v5.legacy.button") != null and legacy.probe.live == 1, "remount: test_ids queryable again", .{});

    // 反例：旧面板沿用外部长寿命 Binding.scope（真实旧代码的 bound.scope）
    const outer_scope = try ui.Scope.init(e.cx.allocator, null, e.cx.owner);
    const outer = try outer_scope.createState(legacy.Binding, .{ .scope = outer_scope, .label = "outer" });
    legacy.outer_binding = outer;
    const cleanups_before = legacy.probe.cleanups;
    vm.legacy_outer_shown.set(true);
    vm.legacy_outer_shown.set(false);
    check("V-5", legacy.probe.cleanups == cleanups_before and legacy.probe.live == 2 and e.cx.after_layout_hooks.items.len == hooks0 + 2, "COUNTER-EXAMPLE outer Binding.scope: branch unmount does NOT run cleanup (cleanups +{d}, live={d}) -> must pass the component scope", .{ legacy.probe.cleanups - cleanups_before, legacy.probe.live });
    outer_scope.dispose();
    legacy.outer_binding = null;
    check("V-5", legacy.probe.live == 1, "counter-example released only when the outer scope is disposed (live={d})", .{legacy.probe.live});
    check("V-5", !e.deinit(), "no leak (DebugAllocator) after all cycles", .{});
}

// ── V-11：windowRegion 的命中语义（无窗口） ──
fn center(n: *ui.Node) [2]f32 {
    const r = n.globalRect();
    return .{ r.x + r.w / 2, r.y + r.h / 2 };
}
fn checkV11(io: std.Io) !void {
    var e = try Env.init(io);
    e.cx.setViewport(960, 200);
    try e.mount(ui.view.col(.{ .style = ui.css(.{ .width = .{ .px = 960 }, .height = .{ .px = 200 } }) }, .{views.ChromeHeader(.{})}));
    e.cx.root = e.root;
    const header = e.find("spike.v11.header").?;
    check("V-11", header.behavior.interaction.window_region == .drag, "Yix windowRegion={{.drag}} sets node.behavior.interaction.window_region = {s}", .{@tagName(header.behavior.interaction.window_region)});
    // window chrome（WindowConfig.chrome = .custom，mockup runner 与所有生产窗口都用它）下的命中：windowRegionAt
    (try e.cx.windowChrome()).set(.{ .effective_mode = .custom, .controls_owner = .framework });
    e.cx.layout();
    e.cx.publishWindowRegions();
    const hr = header.globalRect();
    const blank = [2]f32{ hr.x + 40, hr.y + hr.h / 2 };
    const points = [_]struct { name: []const u8, p: [2]f32 }{
        .{ .name = "blank", .p = blank },
        .{ .name = "button", .p = center(e.find("spike.v11.button").?) },
        .{ .name = "client", .p = center(e.find("spike.v11.client").?) },
        .{ .name = "plain", .p = center(e.find("spike.v11.plain").?) },
        .{ .name = "close", .p = center(e.find("spike.v11.close").?) },
        .{ .name = "below", .p = .{ 400, 150 } },
    };
    const want = [_]@TypeOf(e.cx.windowRegionAt(0, 0)){ .drag, .client, .client, .drag, .close, .client };
    for (points, want) |pt, w| {
        const got = e.cx.windowRegionAt(pt.p[0], pt.p[1]);
        check("V-11", got == w, "{s} @({d:.0},{d:.0}): windowRegionAt={s} (want {s})", .{ pt.name, pt.p[0], pt.p[1], @tagName(got), @tagName(w) });
    }
    check("V-11", !e.deinit(), "no leak", .{});
}

/// `{vm.field}` 插值得到的文本形如 `.{ .base = .{ .vtable = …` 或 `count=.{ .base = …`。
fn isDump(t: []const u8) bool {
    return std.mem.indexOf(u8, t, ".{ .") != null;
}
