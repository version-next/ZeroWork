const std = @import("std");
const ui = @import("ui");
const View = @import("../view/ai_children_view.zig").View;
const projection = @import("../../../../ai/child_projection.zig");
const identity = @import("../../../../host/identity.zig");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");
const a = std.testing.allocator;
const Selection = struct {
    agent: ?identity.AgentId = null,
    revision: u64 = 0,
    fn select(raw: *anyopaque, agent: identity.AgentId, revision: u64) void {
        const self: *Selection = @ptrCast(@alignCast(raw));
        self.* = .{ .agent = agent, .revision = revision };
    }
};
fn find(node: *ui.Node, key: []const u8) ?*ui.Node {
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, key)) return node;
    for (node.children.items) |child| if (find(child, key)) |found| return found;
    return null;
}
test "v0.4 child list retains exact identity under updates, hides removed rows and follows theme" {
    defer theme.select(.sauber);
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    defer cx.clearFocus();
    const button = try ui.widgets.Button(.{ .label = "子智能体" }).mount(scope, cx);
    try cx.root.?.appendChild(a, button);
    var selection: Selection = .{};
    const view = try View.mount(cx, scope, button, .{ .context = &selection, .select = Selection.select });
    try cx.root.?.appendChild(a, view.root);
    view.open.set(true);
    try view.update(&.{});
    try std.testing.expectEqualStrings("暂无子智能体", view.content.children.items[0].getText().?.content);
    const first: projection.Entry = .{ .agent = .generate(), .conversation = .generate(), .revision = 1, .name = "很长的日志核验名称 / 包含多字节 UTF-8 的独立任务", .summary = "核验明确授权范围", .status = "等待用户", .group = .attention, .running = false, .reusable = false };
    const second: projection.Entry = .{ .agent = .generate(), .conversation = .generate(), .revision = 1, .name = "运行任务", .status = "运行中", .group = .active, .running = true, .reusable = true };
    view.open.set(false);
    try view.update(&.{ first, second });
    try std.testing.expectEqualStrings("1", view.badge.getText().?.content);
    try std.testing.expect(view.badge.style.display == .flex);
    try view.updateWithCount(&.{ first, second }, 0);
    try std.testing.expect(view.badge.style.display == .none);
    try view.updateWithCount(&.{first}, 2);
    try std.testing.expectEqualStrings("2", view.badge.getText().?.content);
    view.open.set(true);
    try view.update(&.{ first, second });
    var key: [64]u8 = undefined;
    const row = find(view.content, try std.fmt.bufPrint(&key, "ai.child.{s}", .{std.fmt.bytesToHex(first.agent.bytes, .lower)})).?;
    for (0..8) |_| cx.layout();
    var second_key: [64]u8 = undefined;
    const second_row = find(view.content, try std.fmt.bufPrint(&second_key, "ai.child.{s}", .{std.fmt.bytesToHex(second.agent.bytes, .lower)})).?;
    const logo = find(row, "ai.child.logo").?.globalRect();
    const name = find(row, "ai.child.row.name").?.globalRect();
    const status = find(row, "ai.child.row.status").?.globalRect();
    // Pencil O8 (ai-redesign-c): logo 24, name 10 after it; rows 44 high; the header title follows the
    // 14 icon at the row's logo inset.
    try std.testing.expectApproxEqAbs(@as(f32, 24), logo.w, 0.1);
    try std.testing.expectApproxEqAbs(logo.x + logo.w + 10, name.x, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 44), row.globalRect().h, 0.1);
    try std.testing.expectApproxEqAbs(name.x, find(second_row, "ai.child.row.name").?.globalRect().x, 0.1);
    try std.testing.expectApproxEqAbs(logo.x + 20, find(cx.root.?, "ai.children.title").?.globalRect().x, 0.1);
    try std.testing.expect(find(cx.root.?, "ai.children.close") != null);
    try std.testing.expectApproxEqAbs(status.x, find(second_row, "ai.child.row.status").?.globalRect().x, 0.1);
    try std.testing.expectApproxEqAbs(logo.y + logo.h / 2, status.y + status.h / 2, 0.1);
    try std.testing.expect(name.x + name.w <= status.x);
    try std.testing.expect(find(row, "ai.child.status.icon").?.getText() == null);
    const old_logo = find(row, "ai.child.logo").?;
    const old_icon = old_logo.children.items[0].getIcon().?.icon_id;
    var changed = first;
    changed.revision = 2;
    changed.group = .recent;
    changed.status = "已完成";
    changed.name = "改名后保留原标识";
    try view.update(&.{ second, changed });
    try std.testing.expect(row == find(view.content, key[0..41]).?);
    try std.testing.expect(old_logo == find(row, "ai.child.logo").?);
    try std.testing.expectEqual(old_icon, old_logo.children.items[0].getIcon().?.icon_id);
    for (0..8) |_| cx.layout();
    cx.setFocus(row);
    cx.handleKeyDown(.@"return", .{});
    try std.testing.expect(selection.agent != null and selection.agent.?.eql(first.agent));
    try std.testing.expectEqual(@as(u64, 2), selection.revision);
    view.open.set(true);
    try view.update(&.{second});
    try std.testing.expect(row.style.display == .none);
    theme.select(.light);
    try view.update(&.{second});
    // The popover panel is zenit's default surface (no app overlay override any more).
    try std.testing.expectEqualDeep(cx.tokens.tokens.color.bg_primary, view.chrome.getBackground());
    cx.clearFocus();
}

test "shared assistant header retains its geometry and child settings keep the native popover material" {
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1280, 720);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .row }, .{});
    const child_styles = @import("../view/ai_children_styles.zig");
    const Header = @import("../../pane/view/ai_assistant_header.zig");
    const panel_box: ui.BoxStyle = .{ .width = .{ .px = 600 }, .height = .{ .px = 456 }, .direction = .column };
    const parent_panel = try ui.box(cx, panel_box, .{});
    const child_panel = try ui.box(cx, panel_box, .{});
    try cx.root.?.appendChild(a, parent_panel);
    try cx.root.?.appendChild(a, child_panel);
    const header_scope = try ui.Scope.init(a, null, cx.owner);
    defer header_scope.dispose();
    const parent = try Header.mount(cx, header_scope, parent_panel, "Local Terminal");
    const child = try Header.mount(cx, header_scope, child_panel, "日志核验");
    for (0..8) |_| cx.layout();
    try std.testing.expectApproxEqAbs(parent.bar.globalRect().y, child.bar.globalRect().y, 0.1);
    try std.testing.expectApproxEqAbs(parent.bar.globalRect().h, child.bar.globalRect().h, 0.1);
    try std.testing.expectApproxEqAbs(parent.owner.globalRect().y, child.owner.globalRect().y, 0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 456), child_panel.globalRect().h, 0.1);
    // O9 (ai-redesign-c): the child dialog header is the float_chrome spec — 36 high, title 12/600.
    try std.testing.expectApproxEqAbs(@as(f32, 36), child.bar.globalRect().h, 0.1);
    try std.testing.expectEqual(@as(u16, 600), child.owner.getText().?.font_weight);
    try std.testing.expectApproxEqAbs(@as(f32, 12), child.owner.getText().?.font_size, 0.01);
    const settings_open = try header_scope.createSignal(bool, false);
    const settings = try ui.widgets.Popover(.{ .open = settings_open, .trigger = .manual, .anchor = .{ .node = child.owner }, .width = 320 }).mount(header_scope, cx);
    try child.bar.appendChild(a, settings.wrapper);
    settings.chrome.setStyleInline(a, child_styles.settings(cx.tokens));
    try std.testing.expect(settings.chrome.style.overflow_hidden);
    try std.testing.expectEqualDeep(cx.tokens.tokens.color.bg_primary, settings.chrome.getBackground());
    const shadows = settings.chrome.style.shadowSlice();
    try std.testing.expectEqual(@as(usize, 1), shadows.len);
    try std.testing.expectEqualDeep(cx.tokens.tokens.shadow.md, shadows[0]);
}

test "child dialog header gives way at narrow dialog widths: the meta pill shrinks and its subtitle ellipsizes, buttons stay whole" {
    const H = @import("../../pane/view/ai_child_header_styles.zig");
    const Header = @import("../../pane/view/ai_assistant_header.zig");
    var button_width: ?f32 = null;
    for ([_]f32{ 600, 320 }) |width| {
        const cx = try ui.Cx.init(a, std.testing.io);
        defer cx.deinit();
        cx.setViewport(width + 40, 400);
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .row }, .{});
        const scope = try ui.Scope.init(a, null, cx.owner);
        defer scope.dispose();
        // The child dialog is a fixed-width Modal; its body column holds the header bar.
        const panel = try ui.box(cx, .{ .width = .{ .px = width }, .height = .{ .px = 300 }, .direction = .column }, .{});
        try cx.root.?.appendChild(a, panel);
        const shell = try Header.mount(cx, scope, panel, "日志核验与归档子智能体");
        const tag = try ui.view.render(scope, cx, ui.widgets.Tag(.{ .label = "运行中", .color = .accent, .size = .sm }));
        try shell.owner_pill.appendChild(a, tag);
        const subtitle = try ui.textStyled(cx, H.subtitle, "父对话 0123abcd · 继承上下文（很长的说明文字让副标题必须截断）");
        subtitle.setStyleInline(a, H.subtitleBox());
        try shell.owner_pill.appendChild(a, subtitle);
        var buttons: [4]*ui.Node = undefined;
        for (&buttons) |*button| {
            button.* = try ui.widgets.Button(.{ .icon_only = true, .icon_asset = ui.icons.minus, .icon_size = 14, .a11y_label = "按钮", .variant = .ghost, .size = .sm }).mount(scope, cx);
            try shell.bar.appendChild(a, button.*);
        }
        for (0..6) |_| {
            cx.layout();
            _ = cx.render();
        }
        const bar = shell.bar.globalRect();
        const pill = shell.owner_pill.globalRect();
        try std.testing.expectApproxEqAbs(width, bar.w, 0.5);
        // The pill never hides; at 320 it gives way (narrower than its content) without overlapping.
        try std.testing.expect(shell.owner_pill.style.display != .none);
        try std.testing.expect(pill.w > 0);
        try std.testing.expect(pill.x + pill.w <= buttons[0].globalRect().x + 0.5);
        try std.testing.expect(shell.owner.globalRect().x + shell.owner.globalRect().w <= pill.x + 0.5);
        for (buttons) |button| {
            const rect = button.globalRect();
            // Native ghost sm icon buttons keep their own size at every width.
            if (button_width == null) button_width = rect.w;
            try std.testing.expect(rect.w >= 24);
            try std.testing.expectApproxEqAbs(button_width.?, rect.w, 0.01);
            try std.testing.expect(rect.x + rect.w <= bar.x + bar.w + 0.5);
        }
        const sub = subtitle.globalRect();
        const natural = cx.text.measureTextWidth(subtitle.getText().?.content, 11, 400, false);
        try std.testing.expectEqual(ui.TextOverflow.ellipsis, subtitle.getText().?.text_overflow);
        try std.testing.expect(shell.owner_pill.style.overflow_hidden or shell.owner_pill.style.overflow.clips());
        if (width == 600) {
            // The dialog's real width (min(600, window - 32), main window ≥ 860): Tag and subtitle show,
            // the subtitle ellipsized at its 240 cap inside the pill.
            try std.testing.expect(sub.x + sub.w <= pill.x + pill.w + 0.5);
            try std.testing.expect(sub.w > 0 and sub.w <= 240.5 and sub.w < natural);
        } else {
            // Degenerate width: the pill gives way to almost nothing (clipped), the subtitle first.
            try std.testing.expect(pill.w < tag.globalRect().w);
            try std.testing.expect(sub.w < natural - 1);
        }
    }
}

test "header count badge belongs to the view: released with the view's Scope, a remount adds exactly one" {
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    cx.setViewport(860, 480);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const chrome_scope = try ui.Scope.init(a, null, cx.owner);
    defer chrome_scope.dispose();
    defer cx.clearFocus();
    // The chrome's slot button outlives the content view (LIFECYCLE.md §3).
    const button = try ui.widgets.Button(.{ .label = "子智能体" }).mount(chrome_scope, cx);
    try cx.root.?.appendChild(a, button);
    const badges = struct {
        fn count(node: *ui.Node) usize {
            var n: usize = 0;
            for (node.children.items) |child| {
                if (child.meta.ownership.meta.test_id) |id| if (std.mem.eql(u8, id, "ai.children.count")) {
                    n += 1;
                };
            }
            return n;
        }
    };
    var selection: Selection = .{};
    for (0..3) |_| {
        const view_scope = try chrome_scope.childScope();
        const view = try View.mount(cx, view_scope, button, .{ .context = &selection, .select = Selection.select });
        try cx.root.?.appendChild(a, view.root);
        _ = cx.render();
        try std.testing.expectEqual(@as(usize, 1), badges.count(button));
        // The content view is released: its nodes first, then its Scope (the badge goes with it).
        cx.detachChild(cx.root.?, view.root);
        cx.destroyDetached(view.root);
        view_scope.dispose();
        try std.testing.expectEqual(@as(usize, 0), badges.count(button));
    }
}
