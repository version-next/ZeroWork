//! NotificationHost: the window's notification stack as an element (Yix `<W.NotificationHost …/>`).
//!
//! `Notifier.init(scope, cx, options)` + imperative `show` / `hint` needs the host to hold the
//! Notifier pointer. NotificationHost mounts the same Notifier from a template and lets a
//! view-model drive it through a source:
//!
//!   // view-model
//!   toast: *ui.Signal(ui.widgets.NotificationPost),
//!   fn saved(vm: *Vm) void { vm.toast.set(vm.toast.peek().next(.{ .hint = .{ .text = "Saved", .mark = .success } })); }
//!
//!   // template
//!   <W.NotificationHost post={vm.toast} position={.bottom_center} onNotification={|e| send(vm, .{ .notified = e })} />
//!
//! - `post`: each new `seq` runs its `op` once (`hint` / `show` / `dismiss` / `dismiss_all`).
//!   The value present when the host mounts is taken as already handled (a remounted host does
//!   not replay the last toast). Strings are copied by the Notifier.
//! - `position` follows its source; the other options are read at mount.
//! - `suppressed` follows its source: true hides the stack without dismissing anything (no input,
//!   timers hold), e.g. while a host surface covers the stack's corner (`Notifier.setSuppressed`).
//! - `on_notification`: button / undo / reply / dismissed / expired events (`Event`).
//! - `ref` / `ui.view.capture` gives the `NotificationHostResult` (`.notifier`) for imperative use.
//!
//! The stack is portaled over the window (no node in the parent) when the window has a popover
//! portal root, else (unit tests without a root) the container is the element's node.
const std = @import("std");
const core = @import("../../core.zig");
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;
const Source = reactive.Source;
const Cx = core.Cx;
const mod = @import("mod.zig");
const Notifier = mod.Notifier;

/// One request to the stack. Bump `seq` (`next`) for every request; equal seq = already handled.
pub const NotificationPost = struct {
    seq: u64 = 0,
    op: Op = .none,

    pub const Op = union(enum) {
        none,
        hint: mod.Hint,
        show: mod.Notification,
        dismiss: mod.Id,
        dismiss_all,
    };

    /// The post after `self` carrying `op`.
    pub fn next(self: NotificationPost, op: Op) NotificationPost {
        return .{ .seq = self.seq +% 1, .op = op };
    }
};

pub const NotificationHostProps = struct {
    post: Source(NotificationPost) = .{ .value = .{} },
    position: Source(mod.Position) = .{ .value = .bottom_center },
    suppressed: Source(bool) = .{ .value = false },
    /// Read at mount (see `Options`).
    max_visible: u8 = mod.model.Spec.default_max_visible,
    expand_on_hover: bool = true,
    content_insets: mod.Insets = .{},
    width: f32 = mod.model.Spec.card_width,
    strings: mod.Strings = .{},
    on_notification: ?core.Handler(mod.Event) = null,
    /// Test id of the stack's container (Yix `testId`), read at mount.
    test_id: ?[]const u8 = null,
};

pub fn NotificationHost(props: anytype) NotificationHostBuilder {
    return .{ .props = reactive.props.coerce(NotificationHostProps, props) };
}

pub const NotificationHostResult = struct {
    notifier: *Notifier,

    pub fn viewParts(self: NotificationHostResult) core.ViewParts {
        return .{ .root = if (self.notifier.portaled) null else self.notifier.container };
    }
};

const Host = struct {
    notifier: *Notifier,
    post: Source(NotificationPost),
    position: Source(mod.Position),
    suppressed: Source(bool),
    seen: u64,
    on_notification: ?core.Handler(mod.Event),

    fn listen(context: ?*anyopaque, _: *Notifier, event: mod.Event) void {
        const self: *Host = @ptrCast(@alignCast(context.?));
        if (self.on_notification) |h| h.call(event);
    }

    fn runPost(self: *Host) void {
        const p = self.post.get();
        if (p.seq == self.seen) return;
        self.seen = p.seq;
        const n = self.notifier;
        switch (p.op) {
            .none => {},
            .hint => |h| _ = n.hint(h) catch |err| std.log.warn("NotificationHost: hint dropped ({s})", .{@errorName(err)}),
            .show => |s| _ = n.show(s) catch |err| std.log.warn("NotificationHost: notification dropped ({s})", .{@errorName(err)}),
            .dismiss => |id| n.dismiss(id),
            .dismiss_all => n.dismissAll(),
        }
    }

    fn followPosition(self: *Host) void {
        self.notifier.setPosition(self.position.get());
    }

    fn followSuppressed(self: *Host) void {
        self.notifier.setSuppressed(self.suppressed.get());
    }
};

pub const NotificationHostBuilder = struct {
    props: NotificationHostProps,

    pub fn mount(self: NotificationHostBuilder, scope: *Scope, cx: *Cx) !NotificationHostResult {
        const p = self.props;
        const my_scope = try scope.childScope();
        errdefer my_scope.dispose();
        const notifier = try Notifier.init(my_scope, cx, .{
            .position = p.position.peek(),
            .max_visible = p.max_visible,
            .expand_on_hover = p.expand_on_hover,
            .content_insets = p.content_insets,
            .width = p.width,
            .strings = p.strings,
        });
        // Unportaled (no portal root), the container is ours until the view attaches it.
        errdefer if (!notifier.portaled) cx.freeNode(notifier.container);
        if (p.test_id) |id| notifier.container.meta.ownership.meta.test_id = id;
        const host = try my_scope.createState(Host, .{
            .notifier = notifier,
            .post = p.post,
            .position = p.position,
            .suppressed = p.suppressed,
            .seen = p.post.peek().seq,
            .on_notification = p.on_notification,
        });
        if (p.on_notification != null) notifier.setListener(.{ .context = @ptrCast(host), .callback = Host.listen });
        if (!p.post.isStatic()) try my_scope.createEffect(host, Host.runPost);
        if (!p.position.isStatic()) try my_scope.createEffect(host, Host.followPosition);
        if (p.suppressed.isStatic()) notifier.setSuppressed(p.suppressed.peek()) else try my_scope.createEffect(host, Host.followSuppressed);
        return .{ .notifier = notifier };
    }
};

// ===== Tests =====

const testing = std.testing;
const view = @import("../../view.zig");

test "NotificationHost: posts drive the stack once per seq; the mount-time post is not replayed; position follows" {
    const cx = try Cx.init(testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1200, 800);
    const root = try core.box(cx, .{ .width = .fixed(1200), .height = .fixed(800) }, .{});
    cx.root = root;
    const scope = try Scope.init(testing.allocator, null, cx.owner);
    defer scope.dispose();
    const post = try scope.createSignal(NotificationPost, NotificationPost.next(.{}, .{ .hint = .{ .text = "stale" } }));
    const position = try scope.createSignal(mod.Position, .bottom_center);
    const suppressed = try scope.createSignal(bool, false);
    const Log = struct {
        actions: usize = 0,
        fn on(self: *@This(), e: mod.Event) void {
            if (e.kind == .action) self.actions += 1;
        }
    };
    var log: Log = .{};
    var host: NotificationHostResult = undefined;
    try view.mount(scope, cx, root, view.capture(&host, NotificationHost(.{
        .test_id = "toasts",
        .post = post,
        .position = position,
        .suppressed = suppressed,
        .on_notification = cx.on(Log, &log, Log.on),
    })));
    const n = host.notifier;
    try testing.expectEqualStrings("toasts", n.container.meta.ownership.meta.test_id.?);
    try testing.expectEqual(@as(usize, 0), n.count());
    post.set(post.peek().next(.{ .hint = .{ .text = "Saved", .mark = .success } }));
    try testing.expectEqual(@as(usize, 1), n.count());
    // The same value again is not a new request.
    post.set(post.peek());
    try testing.expectEqual(@as(usize, 1), n.count());
    post.set(post.peek().next(.{ .show = .{ .title = "Synced", .body = "3 files" } }));
    try testing.expectEqual(@as(usize, 2), n.count());
    // Events reach on_notification: a hint with an action, triggered.
    post.set(post.peek().next(.{ .hint = .{ .text = "Deleted", .action = .{ .label = "Undo" } } }));
    cx.frame_time_ms = 100;
    cx.layout();
    Notifier.frameHookForTest()(n.container);
    try testing.expect(n.triggerHintAction());
    cx.frame_time_ms = 116;
    Notifier.frameHookForTest()(n.container);
    try testing.expectEqual(@as(usize, 1), log.actions);
    position.set(.top_right);
    try testing.expectEqual(mod.Position.top_right, n.options.position);
    suppressed.set(true);
    try testing.expect(n.isSuppressed());
    suppressed.set(false);
    try testing.expect(!n.isSuppressed());
    post.set(post.peek().next(.dismiss_all));
    try testing.expectEqual(@as(usize, 0), n.count());
}

test "NotificationHost: mount OOM sweep" {
    try @import("../oom_sweep.zig").sweepMount("notification_host", struct {
        fn mount(scope: *Scope, cx: *Cx) anyerror!?*core.Node {
            const post = try scope.createSignal(NotificationPost, .{});
            const r = try NotificationHost(.{ .post = post }).mount(scope, cx);
            return if (r.notifier.portaled) null else r.notifier.container;
        }
    }.mount);
}
