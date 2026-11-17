/// multi_window: demo of two true native windows coexisting
///
/// Verification points:
///   - `MultiWindowApp` manages two windows (each Window/GPU surface/SystemSdk/Cx)
///   - Second Cx.init doesn't panic (no concurrency guard)
///   - Events route per window: each window's button counts independently, no cross-talk
///   - Text measure is per-App context: two windows measure fonts independently
///   - a11y C ABI routes per window_id (registered at init, no mutual override)
///   - Close A, B continues pump/render; closing the last window exits
///
/// Main loop is driven by public `MultiWindowApp.run()`: first window pump can block, other windows
/// drain non-blocking, events and menu commands route per native window_id.
///
/// Each window's UI is in view.yix (`WindowUi`, props distinguish A/B).
///
/// Smoke test: ZENIT_SMOKE_FRAMES=N runs N frames then auto-exits (exit 0), so scripts/CI can
/// assert "both windows truly rendered" without manual close. It also checks frame-first
/// delivery across real windows: a background thread's `Inbox.notify` wakes a loop blocked on a
/// long idle wait and only the inbox's window renders (ZENIT_SMOKE_INBOX=1, `verifyInboxWake`).
const std = @import("std");
const ui = @import("ui");
const zenit_app = @import("zenit_app");
const MultiWindowApp = zenit_app.MultiWindowApp;
const WindowUi = @import("_view.yix.zig").WindowUi;

fn mountWindowA(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
    return ui.view.render(scope, cx, WindowUi(.{ .tag = "A", .heading = "zenit multi-window: A", .button = "Click me (A)" }));
}

fn mountWindowB(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
    return ui.view.render(scope, cx, WindowUi(.{ .tag = "B", .heading = "zenit multi-window: B", .button = "Click me (B)" }));
}

const InboxProbe = struct {
    var inbox_a: ui.Inbox = .none;
    var inbox_b: ui.Inbox = .none;
    var hits_a: u32 = 0;
    var hits_b: u32 = 0;

    const Hit = struct {
        hits: *u32,
        fn run(self: *Hit) void {
            self.hits.* += 1;
        }
    };

    fn mountA(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
        const hit = try scope.createState(Hit, .{ .hits = &hits_a });
        inbox_a = try cx.createInbox(scope, cx.on(Hit, hit, Hit.run));
        return mountWindowA(cx, scope);
    }

    fn mountB(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
        const hit = try scope.createState(Hit, .{ .hits = &hits_b });
        inbox_b = try cx.createInbox(scope, cx.on(Hit, hit, Hit.run));
        return mountWindowB(cx, scope);
    }

    fn notifyLater(io: std.Io, inbox: ui.Inbox, delay_ms: u64) void {
        std.Io.sleep(io, .fromNanoseconds(delay_ms * std.time.ns_per_ms), .awake) catch {};
        inbox.notify();
    }
};

fn elapsedMs(io: std.Io, start: std.Io.Timestamp) i96 {
    return @divTrunc(std.Io.Clock.awake.now(io).nanoseconds - start.nanoseconds, std.time.ns_per_ms);
}

/// Real windows, real event loop: both windows idle, the loop blocked in its native wait; a
/// background thread notifies A's inbox. The blocked wait must end at once, A's callback run and
/// only A render (an occluded A delivers without rendering).
fn verifyInboxWake(allocator: std.mem.Allocator, io: std.Io) !void {
    var application = MultiWindowApp.init(allocator, .{});
    defer application.deinit();
    const config: zenit_app.runtime.Config = .{ .io = io, .window = .{ .width = 360, .height = 240, .title = "zenit inbox" }, .idle_wait_ms = 3_000 };
    var config_b = config;
    config_b.window.title = "zenit inbox B";
    const a = try application.createWindowWith(config, InboxProbe.mountA);
    const b = try application.createWindowWith(config_b, InboxProbe.mountB);
    // Settle until an idle tick really blocks in the native wait (first frames, display links
    // stopping, idle trims and other deadlines all past).
    var idle_tick_ms: i96 = 0;
    for (0..60) |_| {
        const tick_start = std.Io.Clock.awake.now(io);
        _ = try application.tick();
        idle_tick_ms = elapsedMs(io, tick_start);
        if (idle_tick_ms >= 300 and !a.cx.wantsFrame() and !b.cx.wantsFrame()) break;
    }
    if (idle_tick_ms < 300) return error.InboxProbeLoopNeverBlocks;
    const a_frames = a.renderer.frame_count;
    const b_frames = b.renderer.frame_count;

    const start = std.Io.Clock.awake.now(io);
    const thread = try std.Thread.spawn(.{}, InboxProbe.notifyLater, .{ io, InboxProbe.inbox_a, 100 });
    var ticks: usize = 0;
    while (InboxProbe.hits_a == 0 and ticks < 20) : (ticks += 1) _ = try application.tick();
    thread.join();
    const elapsed_ms = elapsedMs(io, start);
    if (InboxProbe.hits_a != 1) return error.InboxNotDelivered;
    // The blocked wait ended with the notify (~100 ms), not at its deadline; with display-link
    // pacing the frame (and so the delivery) is the next vsync after the woken tick.
    if (elapsed_ms > 1_000 or elapsed_ms * 2 > idle_tick_ms) {
        std.log.err("[multi_window] inbox wake late: idle tick {d} ms, delivered after {d} ms in {d} ticks, wake handler set={}", .{ idle_tick_ms, elapsed_ms, ticks, a.cx.inbox_hub.wake != null });
        return error.InboxWakeTooLate;
    }
    if (a.renderer.frame_count <= a_frames and !a.occluded) return error.InboxWindowDidNotRender;
    // Only the inbox's window rendered.
    if (b.renderer.frame_count != b_frames or InboxProbe.hits_b != 0) return error.InboxWokeOtherWindow;
    std.log.info("[multi_window] inbox ok: idle tick blocked {d} ms; notify at 100 ms delivered after {d} ms in {d} ticks, A frames {d}->{d} (occluded={}), B frames {d}->{d}", .{ idle_tick_ms, elapsed_ms, ticks, a_frames, a.renderer.frame_count, a.occluded, b_frames, b.renderer.frame_count });

    // Windows gone: a late notify from another thread does nothing. A native close may complete
    // on a later pump; the inboxes close when the window is torn down.
    _ = application.closeWindow(a.windowId());
    _ = application.closeWindow(b.windowId());
    var pumps: usize = 0;
    while (application.windowCount() != 0 and pumps < 200) : (pumps += 1) _ = application.tick() catch break;
    if (application.windowCount() != 0) return error.InboxProbeWindowsDidNotClose;
    if (InboxProbe.inbox_a.isOpen() or InboxProbe.inbox_b.isOpen()) return error.InboxOpenAfterClose;
    const late = try std.Thread.spawn(.{}, InboxProbe.notifyLater, .{ io, InboxProbe.inbox_a, 0 });
    late.join();
    std.log.info("[multi_window] inbox closed ok", .{});
}

fn verifyApplicationQuitContract(allocator: std.mem.Allocator, io: std.Io) !void {
    var application = MultiWindowApp.init(allocator, .{ .pump_timeout_ms = 0 });
    defer application.deinit();

    // Exercise both public creation styles in the real native lifecycle.
    const app_a = try application.createWindow(.{
        .io = io,
        .window = .{ .width = 420, .height = 300, .title = "zenit quit-contract A" },
        .frame_pacing = .poll,
        .idle_skip_frames = false,
    });
    try app_a.mount(mountWindowA);
    const app_b = try application.createWindowWith(.{
        .io = io,
        .window = .{ .width = 420, .height = 300, .title = "zenit quit-contract B" },
        .frame_pacing = .poll,
        .idle_skip_frames = false,
    }, mountWindowB);

    if (!application.activateWindow(app_a.windowId()) or
        application.activeWindow() == null or
        application.activeWindow().?.windowId() != app_a.windowId())
        return error.ActivationFailed;
    if (!application.activateWindow(app_b.windowId()) or
        application.activeWindow() == null or
        application.activeWindow().?.windowId() != app_b.windowId())
        return error.ActivationFailed;

    _ = try application.tick();
    application.quit();
    try application.run();

    // Application-wide quit ends pumping. It deliberately leaves ownership in
    // place so the deferred manager deinit performs one ordered teardown pass.
    if (application.windowCount() != 2 or MultiWindowApp.nativeWindowCount() != 2)
        return error.QuitDestroyedWindowsEarly;
}

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // ZENIT_SMOKE_INBOX=1: only the frame-first delivery check (verifyInboxWake).
    if (@import("zenit_environment").getBorrowed("ZENIT_SMOKE_INBOX") != null) {
        try verifyInboxWake(allocator, init.io);
        if (MultiWindowApp.nativeWindowCount() != 0) return error.InboxProbeCleanupFailed;
        return;
    }

    const smoke_frames: ?u64 = blk: {
        const env = @import("zenit_environment").getBorrowed("ZENIT_SMOKE_FRAMES") orelse break :blk null;
        break :blk std.fmt.parseInt(u64, env, 10) catch null;
    };
    const frame_pacing: zenit_app.runtime.FramePacing = if (smoke_frames != null) .poll else .display_link;
    const idle_skip_frames = smoke_frames == null;

    var application = MultiWindowApp.init(allocator, .{ .pump_timeout_ms = 16 });
    defer application.deinit();

    const app_a = try application.createWindowWith(.{
        .io = init.io,
        .window = .{ .width = 520, .height = 380, .title = "zenit A" },
        .frame_pacing = frame_pacing,
        .idle_skip_frames = idle_skip_frames,
    }, mountWindowA);

    const app_b = try application.createWindowWith(.{
        .io = init.io,
        .window = .{ .width = 520, .height = 380, .title = "zenit B" },
        .frame_pacing = frame_pacing,
        .idle_skip_frames = idle_skip_frames,
    }, mountWindowB);

    std.log.info("[multi_window] two windows up: a11y window_id A={d} B={d}", .{
        app_a.cx.window_id, app_b.cx.window_id,
    });
    if (app_a.cx.window_id == app_b.cx.window_id) {
        std.log.err("[multi_window] window_id collision — a11y/system API 路由会互相覆盖", .{});
        return error.WindowIdCollision;
    }

    if (smoke_frames) |limit| {
        const a_id = app_a.windowId();
        const b_id = app_b.windowId();
        for (0..@max(limit, 1)) |_| _ = try application.tick();
        const a_frames = app_a.renderer.frame_count;
        const b_frames_before_close = app_b.renderer.frame_count;
        if (a_frames == 0 or b_frames_before_close == 0) return error.WindowDidNotRender;
        std.log.info("[multi_window] smoke ok: A={d} B={d} rendered", .{ a_frames, b_frames_before_close });

        // The pointer for A becomes invalid at this explicit teardown boundary.
        if (!application.closeWindow(a_id)) return error.CloseFailed;
        if (application.windowCount() != 1 or MultiWindowApp.nativeWindowCount() != 1 or application.window(a_id) != null or application.window(b_id) == null)
            return error.SingleWindowCloseFailed;
        for (0..@max(limit / 4, 1)) |_| _ = try application.tick();
        const b_live = application.window(b_id) orelse return error.SurvivorMissing;
        if (b_live.renderer.frame_count <= b_frames_before_close) return error.SurvivorDidNotRender;
        std.log.info("[multi_window] single-close ok: native=1 B continued to frame {d}", .{b_live.renderer.frame_count});

        if (!application.closeWindow(b_id)) return error.CloseFailed;
        if (application.windowCount() != 0 or MultiWindowApp.nativeWindowCount() != 0 or application.shouldContinue())
            return error.LastWindowDidNotExit;
        std.log.info("[multi_window] last-window exit ok: native=0", .{});

        try verifyApplicationQuitContract(allocator, init.io);
        if (MultiWindowApp.nativeWindowCount() != 0) return error.ApplicationQuitCleanupFailed;
        std.log.info("[multi_window] app-quit cleanup ok: create styles + activation + native=0", .{});
        return;
    }

    try application.run();
}
