/// Alert Component
///
/// Alert: static message banner (for global notifications see components/notification, Notifier)
///
/// Features:
/// - info/success/warning/error four variants
/// - closable
/// - Signal-first: `variant` / `title` / `message` can take signal / derived; dynamic message syncs
///   to live region, AT announces new content
const std = @import("std");
const Allocator = std.mem.Allocator;
const core = @import("../../core.zig");
const Cx = core.Cx;
const Node = core.Node;
const box = core.box;
const Color = core.Color;
const theme = core.theme;
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;

/// Alert variant
pub const AlertVariant = enum {
    info,
    success,
    warning,
    @"error",
};

/// Create Alert: `W.Alert(.{ .variant = .warning, .message = status_text })`. props: variant /
/// title (empty = no title) / message (empty = no message) / closable / on_close /
/// close_icon_asset / action_label / on_action / action_test_id (names the action row); variant /
/// title / message take signals, new content announced via live region
/// (error / warning assertive). View in alert.yix, styles in styles.yss.
pub const Alert = @import("_alert.yix.zig").Alert;

// ========== Testing ==========

test "Alert: basic" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 200 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const alert = try Alert(.{ .variant = .info, .message = "This is an info alert" }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, alert);

    // alert has 2 children: status icon + content
    try std.testing.expectEqual(@as(usize, 2), alert.children.items.len);
}

test "Alert: with title" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 200 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const alert = try Alert(.{ .variant = .success, .title = "Success!", .message = "Operation completed" }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, alert);

    // content has 2 children: title + message
    const content = alert.children.items[1];
    try std.testing.expectEqual(@as(usize, 2), content.children.items.len);
}

test "Alert: closable" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 200 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const alert = try Alert(.{ .variant = .warning, .message = "Warning!", .closable = true }).mount(scope, ctx);

    try root.appendChild(std.testing.allocator, alert);

    // status icon + content area + close button
    try std.testing.expectEqual(@as(usize, 3), alert.children.items.len);
    try std.testing.expectEqualStrings("Dismiss", alert.children.items[2].behavior.interaction.a11y.?.label.?);
}

test "Alert: all variants" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const root = try box(ctx, .{ .width = .{ .px = 400 }, .height = .{ .px = 400 } }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    inline for (.{ AlertVariant.info, AlertVariant.success, AlertVariant.warning, AlertVariant.@"error" }) |v| {
        const a = try Alert(.{ .variant = v, .message = "Test" }).mount(scope, ctx);
        try root.appendChild(std.testing.allocator, a);
    }

    try std.testing.expectEqual(@as(usize, 4), root.children.items.len);
}

test "Alert: variant backgrounds stay visually distinct" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const info = try Alert(.{ .variant = .info, .message = "a" }).mount(scope, ctx);
    defer ctx.freeNode(info);
    const warn = try Alert(.{ .variant = .warning, .message = "b" }).mount(scope, ctx);
    defer ctx.freeNode(warn);
    try std.testing.expect(!Color.eql(info.getBackground(), warn.getBackground()));
}

test "Alert: render emits leading status icon" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    ctx.setViewport(360, 80);

    const root = try box(ctx, .{
        .width = .{ .px = 360 },
        .height = .{ .px = 80 },
        .background = ctx.tokens.tokens.color.bg_primary,
    }, .{});
    ctx.root = root;

    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const alert = try Alert(.{
        .variant = .warning,
        .message = "Careful",
    }).mount(scope, ctx);
    try root.appendChild(std.testing.allocator, alert);

    ctx.layout();
    _ = ctx.render();
    const commands = ctx.lowerForEncoderPaintTable();

    // COMPONENTS.json Alert / warning: 16px icon inside a 20x22 alignment slot.
    const icon = alert.children.items[0].children.items[0];
    try std.testing.expectEqual(@as(f32, 16), icon.rectFromWorldOrFallback().w);
    try std.testing.expect(Color.eql(icon.getIcon().?.tint, ctx.tokens.tokens.color.warning));
    var emitted = false;
    for (commands) |cmd| {
        if (cmd.icon_rep_ptr != null and std.meta.eql(cmd.icon_rep_ptr.?.*, icon.getIcon().?.rep) and cmd.icon_tint.r == icon.getIcon().?.tint.r and
            cmd.icon_tint.g == icon.getIcon().?.tint.g and cmd.icon_tint.b == icon.getIcon().?.tint.b)
        {
            emitted = true;
        }
    }
    try std.testing.expect(emitted);
}

test "Alert: dynamic message and variant update the view and the live region" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();

    const msg = try scope.createText("Saving…", .{});
    const level = try scope.createSignal(AlertVariant, .info);
    const alert = try Alert(.{ .variant = level, .message = msg }).mount(scope, ctx);
    defer ctx.freeNode(alert);
    try std.testing.expectEqualStrings("polite", alert.behavior.interaction.a11y.?.live.?);
    try std.testing.expectEqualStrings("Saving…", alert.behavior.interaction.a11y.?.live_text.?);

    msg.set("Save failed: disk full");
    level.set(.@"error");
    try std.testing.expectEqualStrings("Save failed: disk full", findText(alert, "Save failed: disk full").?.getText().?.content);
    try std.testing.expectEqualStrings("Save failed: disk full", alert.behavior.interaction.a11y.?.live_text.?);
    try std.testing.expectEqualStrings("assertive", alert.behavior.interaction.a11y.?.live.?);
    const k = ctx.tokens.tokens.color;
    try std.testing.expect(Color.eql(alert.getBackground(), k.danger_alert_bg));
}

test "alert: 动态变体 / 消息的 mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("alert(dynamic)", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const msg = try scope.createText("message", .{});
            const level = try scope.createSignal(AlertVariant, .warning);
            return try Alert(.{ .variant = level, .title = "Title", .message = msg, .closable = true }).mount(scope, cx);
        }
    }.m);
}

fn findText(n: *Node, text: []const u8) ?*Node {
    if (n.getText()) |t| if (std.mem.eql(u8, t.content, text)) return n;
    for (n.children.items) |c| if (findText(c, text)) |r| return r;
    return null;
}

test "Alert: 静态 props 不建 memo、effect；只有标题时播报标题" {
    var ctx = try Cx.init(std.testing.allocator, std.testing.io);
    defer ctx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, ctx.owner);
    defer scope.dispose();
    const before = ctx.owner.graph.countByKind();
    const a = try Alert(.{ .variant = .success, .title = "Done" }).mount(scope, ctx);
    defer ctx.freeNode(a);
    const after = ctx.owner.graph.countByKind();
    try std.testing.expectEqual(before.get(.effect), after.get(.effect));
    try std.testing.expectEqual(before.get(.memo), after.get(.memo));
    try std.testing.expectEqualStrings("Done", a.behavior.interaction.a11y.?.live_text.?);
    try std.testing.expectEqual(core.AlignItems.start, a.style.align_items);
    try std.testing.expectEqualStrings("Alert", a.meta.ownership.meta.component_name.?);
}

// test collection for styles.yss, this line required, see docs/STYLING.md
test {
    _ = @import("_styles.yss.zig");
}

// per-allocation OOM sweep, see src/ui/components/oom_sweep.zig
test "alert(closable): mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("alert(closable)", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            return try Alert(.{ .variant = .warning, .title = "Title", .message = "message body", .closable = true }).mount(scope, cx);
        }
    }.m);
}

test "Alert: contextual action is focusable and invokes its handler" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    var calls: u32 = 0;
    const alert = try Alert(.{ .title = "Offline", .action_label = "Retry", .on_action = cx.on(u32, &calls, struct {
        fn run(n: *u32) void {
            n.* += 1;
        }
    }.run) }).mount(scope, cx);
    defer cx.freeNode(alert);
    const action = alert.children.items[1].children.items[1].children.items[0];
    try std.testing.expect(action.behavior.interaction.focusable);
    try std.testing.expectEqualStrings("Retry", action.behavior.interaction.a11y.?.label.?);
    action.behavior.events.on_click.?.invoke();
    try std.testing.expectEqual(@as(u32, 1), calls);
}

test "Alert: action_test_id names the action row; without it no id is written" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const named = try Alert(.{ .title = "Restart pending", .action_label = "Restart now", .action_test_id = "alert.restart" }).mount(scope, cx);
    defer cx.freeNode(named);
    const action = named.children.items[1].children.items[1].children.items[0];
    try std.testing.expectEqualStrings("alert.restart", action.meta.ownership.meta.test_id.?);
    try std.testing.expectEqualStrings("Restart now", action.behavior.interaction.a11y.?.label.?);
    const plain = try Alert(.{ .title = "Offline", .action_label = "Retry" }).mount(scope, cx);
    defer cx.freeNode(plain);
    try std.testing.expect(plain.children.items[1].children.items[1].children.items[0].meta.ownership.meta.test_id == null);
}

test "Alert: a long message wraps inside the banner instead of overflowing it" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(240, 400);
    const root = try box(cx, .{ .width = .{ .px = 240 }, .height = .{ .px = 400 }, .direction = .column }, .{});
    cx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const alert = try Alert(.{ .variant = .info, .title = "A fairly long alert title that must wrap", .message = "This message is much longer than the banner is wide, so it has to wrap onto several lines." }).mount(scope, cx);
    try root.appendChild(std.testing.allocator, alert);
    cx.layout();
    const content = alert.children.items[1];
    const message = content.children.items[1];
    try std.testing.expect(alert.globalRect().w <= 240.5);
    try std.testing.expect(content.globalRect().x + content.globalRect().w <= alert.globalRect().x + alert.globalRect().w + 0.5);
    try std.testing.expect(message.globalRect().w <= content.globalRect().w + 0.5);
    try std.testing.expect(message.globalRect().h > 30);
}

const view = @import("../../view.zig");

fn findTestId(n: *Node, id: []const u8) ?*Node {
    if (n.meta.ownership.meta.test_id) |t| if (std.mem.eql(u8, t, id)) return n;
    for (n.children.items) |c| if (findTestId(c, id)) |r| return r;
    return null;
}

test "Alert: actions slot is a row of native buttons under the message; details fold under a toggle" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(420, 400);
    const root = try box(cx, .{ .width = .{ .px = 388 }, .height = .{ .px = 400 }, .direction = .column }, .{});
    cx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const Button = @import("../button/mod.zig").Button;
    const open = try scope.createSignal(bool, false);
    const alert = try view.render(scope, cx, view.with(Alert(.{
        .variant = .@"error",
        .title = "Request failed · 429",
        .message = "Cooling down; retry in 12 s.",
        .details_open = open,
        .details_test_id = "a.details",
        .details_toggle_test_id = "a.toggle",
    }), .{}).slots(.{
        .actions = .{
            view.attrs(.{ .test_id = "a.retry" }, Button(.{ .label = "Retry", .size = .sm })),
            Button(.{ .label = "Edit", .variant = .secondary, .size = .sm }),
        },
        .details = view.text(.{}, "HTTP 429 Too Many Requests\nretry-after: 12"),
    }));
    try root.appendChild(std.testing.allocator, alert);
    cx.layout();
    const content = alert.children.items[1];
    const message = findText(content, "Cooling down; retry in 12 s.").?;
    const retry = findTestId(alert, "a.retry").?;
    try std.testing.expectEqualStrings("Button", retry.meta.ownership.meta.component_name.?);
    const actions = retry.parent.?;
    try std.testing.expectEqual(@as(usize, 2), actions.children.items.len);
    try std.testing.expect(actions.globalRect().y >= message.globalRect().y + message.globalRect().h);
    try std.testing.expectApproxEqAbs(@as(f32, 6), actions.children.items[1].globalRect().x - (retry.globalRect().x + retry.globalRect().w), 0.5);
    // Details: folded; the toggle opens them (and the Model follows).
    const details = findTestId(alert, "a.details").?;
    const toggle = findTestId(alert, "a.toggle").?;
    try std.testing.expectEqual(core.Display.none, details.style.display);
    try std.testing.expectEqualStrings("Show details", toggle.behavior.interaction.a11y.?.label.?);
    try std.testing.expect(toggle.globalRect().y >= actions.globalRect().y + actions.globalRect().h);
    toggle.behavior.events.on_click.?.invoke();
    try std.testing.expect(open.peek());
    try std.testing.expectEqual(core.Display.flex, details.style.display);
    try std.testing.expectEqualStrings("Hide details", findTestId(alert, "a.toggle").?.behavior.interaction.a11y.?.label.?);
    open.set(false);
    try std.testing.expectEqual(core.Display.none, details.style.display);
    cx.root = null;
    cx.freeNode(root);
}

test "Alert: title / message test ids and localised details labels" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const alert = try view.render(scope, cx, view.with(Alert(.{
        .variant = .@"error",
        .title = "请求失败",
        .message = "服务冷却中",
        .title_test_id = "a.title",
        .message_test_id = "a.message",
        .details_text = "详情",
        .show_details_label = "展开错误详情",
        .hide_details_label = "收起错误详情",
        .details_toggle_test_id = "a.toggle",
    }), .{}).slots(.{ .details = view.text(.{}, "HTTP 429") }));
    defer cx.freeNode(alert);
    try std.testing.expectEqualStrings("请求失败", findTestId(alert, "a.title").?.getText().?.content);
    try std.testing.expectEqualStrings("服务冷却中", findTestId(alert, "a.message").?.getText().?.content);
    const toggle = findTestId(alert, "a.toggle").?;
    try std.testing.expect(findText(toggle, "详情") != null);
    try std.testing.expectEqualStrings("展开错误详情", toggle.behavior.interaction.a11y.?.label.?);
    toggle.behavior.events.on_click.?.invoke();
    try std.testing.expectEqualStrings("收起错误详情", findTestId(alert, "a.toggle").?.behavior.interaction.a11y.?.label.?);
}

test "Alert: without the slots nothing extra is built" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const alert = try Alert(.{ .variant = .@"error", .title = "T", .message = "M" }).mount(scope, cx);
    defer cx.freeNode(alert);
    try std.testing.expectEqual(@as(usize, 2), alert.children.items.len);
    try std.testing.expectEqual(@as(usize, 2), alert.children.items[1].children.items.len);
}

test "alert(actions + details): mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("alert(slots)", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const Button = @import("../button/mod.zig").Button;
            return try view.render(scope, cx, view.with(Alert(.{ .variant = .@"error", .title = "Failed", .message = "m", .details_open = true }), .{}).slots(.{
                .actions = Button(.{ .label = "Retry", .size = .sm }),
                .details = view.text(.{}, "body"),
            }));
        }
    }.m);
}

test "Alert: an actions row wider than the alert wraps inside it" {
    var cx = try Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(300, 400);
    const root = try box(cx, .{ .width = .{ .px = 300 }, .height = .{ .px = 400 }, .direction = .column }, .{});
    cx.root = root;
    const scope = try Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const Button = @import("../button/mod.zig").Button;
    const alert = try view.render(scope, cx, view.with(Alert(.{ .variant = .@"error", .title = "Failed", .message = "m" }), .{}).slots(.{
        .actions = .{
            Button(.{ .label = "Retry reply only · 12s", .size = .sm }),
            Button(.{ .label = "Edit question", .size = .sm }),
            view.attrs(.{ .test_id = "a.last" }, Button(.{ .label = "New plan", .size = .sm })),
        },
    }));
    try root.appendChild(std.testing.allocator, alert);
    cx.layout();
    const last = findTestId(alert, "a.last").?;
    try std.testing.expect(last.globalRect().x + last.globalRect().w <= alert.globalRect().x + alert.globalRect().w + 0.5);
    try std.testing.expect(last.globalRect().y > last.parent.?.children.items[0].globalRect().y);
    cx.root = null;
    cx.freeNode(root);
}
