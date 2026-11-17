//! Auxiliary native windows owned by a ZeroWork main window (connection
//! wizard, settings, …). Island B v3 draws these as their own windows with
//! traffic lights in a 44pt custom title bar instead of in-window modals.
//! Each client marks its own title bar as the window drag region (see `Spec`).
//!
//! This file owns only the runtime-agnostic lifecycle; `main.zig` installs a
//! `Runtime` adapter over `MultiWindowApp`. Creation is always deferred to
//! the process loop boundary (`takePending`), because a native App must not
//! be created while the runtime iterates its windows.
//!
//! Usage (client side):
//!   var slot: aux_window.Slot = .{ .spec = .{...}, .client = .{...} };
//!   slot.owner = main_window_id;     // owner closes/raises its aux windows
//!   slot.present();                  // create once, or activate the existing one
//!   slot.close();                    // client finished (save / cancel)
//! Runtime side (main loop, between ticks):
//!   while (aux_window.takePending()) |slot| { create native window with
//!   slot.spec, owner = slot.owner, mount = aux_window.mount; then
//!   slot.opened(window_id) or slot.createFailed(err) }
//!   on_close_request(app)  → aux_window.closeRequest(app.windowId())
const std = @import("std");
const ui = @import("ui");

pub const WindowId = u64;

/// 窗口地面角色：窗口自身底色的语义，创建窗口时据此设置 clear color 与首帧前
/// 的 layer 背景（见 src/app/window_ground.zig）。`.panel` = 自绘面板底（设置
/// 窗口，zw-window-surface）；`.shell` = 外壳地面（向导窗口自绘 ground = 主题
/// app 色，同主窗口）。
pub const Ground = enum { panel, shell };

pub const Phase = enum {
    /// No native window and no request.
    closed,
    /// Waiting for the loop boundary to create the window.
    pending,
    /// Native window exists and the client UI is mounted.
    open,
    /// Close requested; waiting for the runtime to tear the window down.
    closing,
};

/// Native window parameters. Defaults match the Island B v3 auxiliary window
/// chrome: 44pt custom title bar, traffic lights centred at (20, 22).
///
/// The window uses zenit's window chrome (`WindowConfig.chrome`): the client
/// draws the title bar and declares where a press drags the window with
/// `windowRegion={.drag}` (Yix) / `node.behavior.interaction.window_region`;
/// interactive nodes inside a drag region stay clickable. Nothing drags
/// unless the client declares it.
pub const Spec = struct {
    title: [:0]const u8,
    width: u16,
    height: u16,
    min_width: u32 = 0,
    min_height: u32 = 0,
    /// Custom caption with the platform's own traffic lights.
    chrome: ui.widgets.window_chrome.chrome.Config = .{ .custom = .{} },
    /// Caption height handed to the platform (fullscreen header metrics); the
    /// drag area is whatever the client marks, not this band.
    titlebar_height: f32 = 44,
    traffic_light_x: f32 = 20,
    traffic_light_y: f32 = 22,
    traffic_light_diameter: f32 = 12,
    maximizable: bool = false,
    ground: Ground = .panel,
};

pub const Client = struct {
    context: *anyopaque,
    /// Build the window's UI in its own Cx/scope. Called inside the runtime's
    /// transactional create+mount.
    mount: *const fn (*anyopaque, *ui.Cx, *ui.Scope) anyerror!*ui.Node,
    /// Native close button / ⌘W. Return true to let the window close now; the
    /// client may also return false and call `Slot.close` later.
    close_request: *const fn (*anyopaque) bool,
    /// The window's Cx/scope is being destroyed (any reason, including owner
    /// or application shutdown). Client UI pointers become invalid.
    destroyed: ?*const fn (*anyopaque) void = null,
    /// Creation failed before any UI existed.
    failed: ?*const fn (*anyopaque, anyerror) void = null,
};

/// Process runtime adapter installed by main.zig (null in unit tests that do
/// not exercise native windows).
pub const Runtime = struct {
    context: *anyopaque,
    activate: *const fn (*anyopaque, WindowId) bool,
    close: *const fn (*anyopaque, WindowId) bool,
    /// Wake the loop so pending creation is drained promptly.
    wake: ?*const fn (*anyopaque) void = null,
    /// The window's UI was destroyed; `owner` is the window that owned it.
    /// Test-mode builds hand UI automation back to the owner here (the aux
    /// window's mount took it over, last one wins).
    destroyed: ?*const fn (*anyopaque, ?WindowId) void = null,
};
pub var runtime: ?Runtime = null;

pub const Slot = struct {
    spec: Spec,
    client: Client,
    owner: ?WindowId = null,
    phase: Phase = .closed,
    window_id: ?WindowId = null,
    /// Cleanup token registered on the window scope; cut by `deinit` so a
    /// window outliving its client never calls back into freed memory.
    token: ?*Token = null,
    /// Number of native windows created for this slot (diagnostics/tests).
    created: u32 = 0,

    pub const Presented = enum { queued, already_pending, activated };

    /// Show the client: queue creation once, or raise the existing window.
    pub fn present(self: *Slot) Presented {
        switch (self.phase) {
            .open => {
                if (runtime) |rt| if (self.window_id) |id| {
                    _ = rt.activate(rt.context, id);
                };
                return .activated;
            },
            .pending => return .already_pending,
            // A closing window is gone for the client; open a fresh one.
            .closed, .closing => {
                if (self.phase == .closing) self.forget();
                self.phase = .pending;
                enqueue(self);
                if (runtime) |rt| if (rt.wake) |wake| wake(rt.context);
                return .queued;
            },
        }
    }

    /// True while a window exists or is about to be created.
    pub fn active(self: *const Slot) bool {
        return self.phase == .pending or self.phase == .open;
    }

    /// Client finished: close the native window (or drop a pending request).
    pub fn close(self: *Slot) void {
        switch (self.phase) {
            .closed, .closing => {},
            .pending => {
                dequeue(self);
                self.phase = .closed;
            },
            .open => {
                self.phase = .closing;
                const id = self.window_id orelse return;
                if (runtime) |rt| _ = rt.close(rt.context, id);
            },
        }
    }

    /// Runtime: native window created and mounted.
    pub fn opened(self: *Slot, id: WindowId) void {
        self.window_id = id;
        self.created +%= 1;
        // `close()` while the window was being created wins.
        if (self.phase == .closing) {
            if (runtime) |rt| _ = rt.close(rt.context, id);
            return;
        }
        self.phase = .open;
        track(self);
    }

    /// Runtime: creation failed; nothing was mounted.
    pub fn createFailed(self: *Slot, err: anyerror) void {
        self.forget();
        if (self.client.failed) |failed| failed(self.client.context, err);
    }

    fn forget(self: *Slot) void {
        untrack(self);
        dequeue(self);
        self.phase = .closed;
        self.window_id = null;
    }

    fn destroyedNotify(self: *Slot) void {
        const owner = self.owner;
        self.forget();
        if (self.client.destroyed) |destroyed| destroyed(self.client.context);
        if (runtime) |rt| if (rt.destroyed) |destroyed| destroyed(rt.context, owner);
    }

    /// Cancel any request and forget the window (client teardown).
    pub fn deinit(self: *Slot) void {
        if (self.token) |token| token.slot = null;
        self.token = null;
        const id = self.window_id;
        const phase = self.phase;
        self.forget();
        if (phase == .open) if (runtime) |rt| if (id) |value| {
            _ = rt.close(rt.context, value);
        };
    }
};

// ── Process registry (main thread only) ─────────────────────────────────

const capacity = 16;
var pending_slots: [capacity]?*Slot = @splat(null);
var live_slots: [capacity]?*Slot = @splat(null);
var mounting: ?*Slot = null;

fn enqueue(slot: *Slot) void {
    for (pending_slots) |entry| if (entry == slot) return;
    for (&pending_slots) |*entry| if (entry.* == null) {
        entry.* = slot;
        return;
    };
    // Bounded like MultiWindowApp.max_windows: refuse rather than grow.
    slot.phase = .closed;
    if (slot.client.failed) |failed| failed(slot.client.context, error.TooManyWindows);
}
fn dequeue(slot: *Slot) void {
    for (&pending_slots) |*entry| if (entry.* == slot) {
        entry.* = null;
    };
}
fn track(slot: *Slot) void {
    for (live_slots) |entry| if (entry == slot) return;
    for (&live_slots) |*entry| if (entry.* == null) {
        entry.* = slot;
        return;
    };
}
fn untrack(slot: *Slot) void {
    for (&live_slots) |*entry| if (entry.* == slot) {
        entry.* = null;
    };
}

/// Runtime: next slot waiting for its native window (FIFO by slot order).
pub fn takePending() ?*Slot {
    for (&pending_slots) |*entry| if (entry.*) |slot| {
        entry.* = null;
        return slot;
    };
    return null;
}

/// Runtime: call immediately before `createWindowWith(..., aux_window.mount)`.
pub fn beginMount(slot: *Slot) void {
    mounting = slot;
}
/// Runtime: call after createWindowWith returned (success or failure).
pub fn endMount() void {
    mounting = null;
}

/// `App.MountFn` trampoline for auxiliary windows.
pub fn mount(cx: *ui.Cx, scope: *ui.Scope) anyerror!*ui.Node {
    const slot = mounting orelse return error.AuxWindowNotPending;
    const token = try cx.allocator.create(Token);
    token.* = .{ .slot = slot, .allocator = cx.allocator };
    scope.onCleanup(Token, token, Token.finish) catch |err| {
        cx.allocator.destroy(token);
        return err;
    };
    slot.token = token;
    return slot.client.mount(slot.client.context, cx, scope);
}

const Token = struct {
    slot: ?*Slot,
    allocator: std.mem.Allocator,
    fn finish(self: *Token) void {
        if (self.slot) |slot| {
            slot.token = null;
            slot.destroyedNotify();
        }
        self.allocator.destroy(self);
    }
};

pub fn find(id: WindowId) ?*Slot {
    for (live_slots) |entry| if (entry) |slot| if (slot.window_id == id) return slot;
    return null;
}

/// True for windows created through this module (they carry no AppNavHost).
pub fn owns(id: WindowId) bool {
    return find(id) != null;
}

/// Runtime `on_close_request` for auxiliary windows.
pub fn closeRequest(id: WindowId) bool {
    const slot = find(id) orelse return true;
    if (slot.phase == .closing) return true;
    const allow = slot.client.close_request(slot.client.context);
    if (allow) slot.phase = .closing;
    return allow;
}

// ── Tests ───────────────────────────────────────────────────────────────

const TestRuntime = struct {
    activated: u32 = 0,
    closed: u32 = 0,
    last_closed: ?WindowId = null,
    destroyed_owner: ?WindowId = null,
    destroyed_calls: u32 = 0,
    fn destroyed(raw: *anyopaque, owner: ?WindowId) void {
        const self: *TestRuntime = @ptrCast(@alignCast(raw));
        self.destroyed_calls += 1;
        self.destroyed_owner = owner;
    }
    fn activate(raw: *anyopaque, _: WindowId) bool {
        const self: *TestRuntime = @ptrCast(@alignCast(raw));
        self.activated += 1;
        return true;
    }
    fn close(raw: *anyopaque, id: WindowId) bool {
        const self: *TestRuntime = @ptrCast(@alignCast(raw));
        self.closed += 1;
        self.last_closed = id;
        return true;
    }
};
const TestClient = struct {
    allow_close: bool = true,
    close_requests: u32 = 0,
    destroyed_count: u32 = 0,
    fn mountUi(_: *anyopaque, cx: *ui.Cx, _: *ui.Scope) anyerror!*ui.Node {
        return ui.box(cx, .{}, .{});
    }
    fn closeRequested(raw: *anyopaque) bool {
        const self: *TestClient = @ptrCast(@alignCast(raw));
        self.close_requests += 1;
        return self.allow_close;
    }
    fn destroyedUi(raw: *anyopaque) void {
        const self: *TestClient = @ptrCast(@alignCast(raw));
        self.destroyed_count += 1;
    }
};

test "wizard aux window presents once, activates the existing window and closes through the runtime" {
    var rt: TestRuntime = .{};
    runtime = .{ .context = &rt, .activate = TestRuntime.activate, .close = TestRuntime.close, .destroyed = TestRuntime.destroyed };
    defer runtime = null;
    var client: TestClient = .{};
    var slot: Slot = .{ .spec = .{ .title = "t", .width = 720, .height = 600 }, .client = .{ .context = &client, .mount = TestClient.mountUi, .close_request = TestClient.closeRequested, .destroyed = TestClient.destroyedUi } };
    slot.owner = 3;
    defer slot.deinit();
    try std.testing.expectEqual(Slot.Presented.queued, slot.present());
    try std.testing.expectEqual(Slot.Presented.already_pending, slot.present());
    try std.testing.expectEqual(@as(?*Slot, &slot), takePending());
    try std.testing.expectEqual(@as(?*Slot, null), takePending());
    // Runtime mounts through the trampoline.
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    beginMount(&slot);
    cx.root = try mount(cx, scope);
    endMount();
    slot.opened(7);
    try std.testing.expect(owns(7));
    try std.testing.expectEqual(Slot.Presented.activated, slot.present());
    try std.testing.expectEqual(@as(u32, 1), rt.activated);
    try std.testing.expectEqual(@as(u32, 1), slot.created);
    slot.close();
    try std.testing.expectEqual(Phase.closing, slot.phase);
    try std.testing.expectEqual(@as(?WindowId, 7), rt.last_closed);
    scope.dispose();
    try std.testing.expectEqual(@as(u32, 1), client.destroyed_count);
    // The runtime learns which window owned it (test-mode automation goes back there).
    try std.testing.expectEqual(@as(u32, 1), rt.destroyed_calls);
    try std.testing.expectEqual(@as(?WindowId, 3), rt.destroyed_owner);
    try std.testing.expectEqual(Phase.closed, slot.phase);
    try std.testing.expect(!owns(7));
}

test "wizard aux window native close asks the client and a vetoed close keeps the window" {
    var rt: TestRuntime = .{};
    runtime = .{ .context = &rt, .activate = TestRuntime.activate, .close = TestRuntime.close };
    defer runtime = null;
    var client: TestClient = .{ .allow_close = false };
    var slot: Slot = .{ .spec = .{ .title = "t", .width = 720, .height = 600 }, .client = .{ .context = &client, .mount = TestClient.mountUi, .close_request = TestClient.closeRequested } };
    defer slot.deinit();
    _ = slot.present();
    _ = takePending();
    slot.opened(9);
    try std.testing.expect(!closeRequest(9));
    try std.testing.expectEqual(Phase.open, slot.phase);
    client.allow_close = true;
    try std.testing.expect(closeRequest(9));
    try std.testing.expectEqual(Phase.closing, slot.phase);
    // Unknown windows are not vetoed.
    try std.testing.expect(closeRequest(1234));
}

test "wizard aux window close before creation drops the request and a failed creation resets" {
    var client: TestClient = .{};
    var slot: Slot = .{ .spec = .{ .title = "t", .width = 720, .height = 600 }, .client = .{ .context = &client, .mount = TestClient.mountUi, .close_request = TestClient.closeRequested } };
    defer slot.deinit();
    _ = slot.present();
    slot.close();
    try std.testing.expectEqual(Phase.closed, slot.phase);
    try std.testing.expectEqual(@as(?*Slot, null), takePending());
    _ = slot.present();
    try std.testing.expectEqual(@as(?*Slot, &slot), takePending());
    slot.createFailed(error.OutOfMemory);
    try std.testing.expectEqual(Phase.closed, slot.phase);
    try std.testing.expectEqual(Slot.Presented.queued, slot.present());
}
