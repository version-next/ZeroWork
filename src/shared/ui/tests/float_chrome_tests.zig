//! The floating cards' unified window chrome (`shared/ui/float_card/float_chrome`): one frame, grip
//! and header geometry for every card type; actions generated from the declared interactions in one
//! order; the narrow-header rule (bugfix-1: buttons never shrink, the subtitle gives way first); the
//! floating layer routes the header actions (maximize is the layer's, the rest go to the owner).
const std = @import("std");
const ui = @import("ui");
const model = @import("../../base/float_card.zig");
const chrome_mod = @import("../float_card/float_chrome.zig");
const layer_mod = @import("../float_card/float_layer.zig");

fn size(content: model.Rect) model.Size {
    return .{ .width = @min(420, content.width / 2), .height = 400 };
}
/// Like the AI chat card: minimize, maximize, close (no open-as-tab) and three slot buttons.
const chat: model.Descriptor = .{ .id = "fixture.chat", .interactions = .initMany(&.{ .move, .resize, .maximize, .raise, .close, .minimize }), .min_size = .{ .width = 320, .height = 280 }, .default_size = size };
/// Like the history card: open-as-tab, maximize, close, no slot buttons.
const records: model.Descriptor = .{ .id = "fixture.records", .interactions = .initMany(&.{ .move, .resize, .maximize, .raise, .close, .open_as_tab }), .min_size = .{ .width = 360, .height = 320 }, .default_size = size };

const slot_buttons = [_]chrome_mod.SlotButton{
    .{ .test_id = "fixture.slot.a", .tooltip_id = "fixture.slot.a.tooltip", .icon = ui.icons.plus, .label = "A" },
    .{ .test_id = "fixture.slot.b", .tooltip_id = "fixture.slot.b.tooltip", .icon = ui.icons.plus, .label = "B" },
    .{ .test_id = "fixture.slot.c", .tooltip_id = "fixture.slot.c.tooltip", .icon = ui.icons.plus, .label = "C" },
};

fn chatSpec() chrome_mod.Spec {
    return .{ .title = "AI 助手", .icon = ui.icons.sparkles, .accent_icon = true, .descriptor = chat, .ids = .{ .root = "fixture.chat" }, .slot_buttons = &slot_buttons };
}
fn recordsSpec() chrome_mod.Spec {
    return .{ .title = "会话记录", .icon = ui.icons.history, .descriptor = records, .ids = .{ .root = "fixture.records" } };
}

fn settle(cx: *ui.Cx) void {
    for (0..6) |_| {
        cx.layout();
        _ = cx.render();
    }
}

fn place(cx: *ui.Cx, chrome: *chrome_mod.Chrome, x: f32, width: f32) !void {
    const holder = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = x }, .top = .{ .px = 20 } }, .width = .{ .px = width }, .height = .{ .px = 406 }, .direction = .column }, .{});
    try holder.appendChild(cx.allocator, chrome.root);
    try cx.root.?.appendChild(cx.allocator, holder);
}

test "float chrome: every card type gets the same frame, grip and header geometry" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1400, 500);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const a = try chrome_mod.Chrome.mount(cx, scope, chatSpec());
    const b = try chrome_mod.Chrome.mount(cx, scope, recordsSpec());
    try place(cx, a, 20, 420);
    try place(cx, b, 500, 420);
    a.setSubtitle("本地终端");
    settle(cx);
    for ([_]*chrome_mod.Chrome{ a, b }) |c| {
        const root = c.root.globalRect();
        const grip = c.grip.globalRect();
        const header = c.header.globalRect();
        const body = c.body.globalRect();
        try std.testing.expectApproxEqAbs(@as(f32, chrome_mod.grip_height), grip.h, 0.1);
        try std.testing.expectApproxEqAbs(@as(f32, chrome_mod.header_height), header.h, 0.1);
        try std.testing.expectApproxEqAbs(root.y, grip.y, 0.6);
        try std.testing.expectApproxEqAbs(grip.y + grip.h, header.y, 0.1);
        try std.testing.expectApproxEqAbs(header.y + header.h, body.y, 0.1);
        try std.testing.expectApproxEqAbs(root.y + root.h, body.y + body.h, 0.6);
        try std.testing.expectApproxEqAbs(@as(f32, 420), root.w, 0.1);
    }
    // Same relative offsets in both cards.
    try std.testing.expectApproxEqAbs(a.header.globalRect().y - a.root.globalRect().y, b.header.globalRect().y - b.root.globalRect().y, 0.1);
    // Actions in the fixed order, one native button each (+ the chat card's slot buttons).
    // cards-float: all five actions are on every card in one order; an undeclared one is disabled.
    try std.testing.expectEqualSlices(chrome_mod.Action, &.{ .open_as_tab, .dock_to_split, .minimize, .maximize, .close }, a.vm.actions.slice());
    try std.testing.expectEqualSlices(chrome_mod.Action, &.{ .open_as_tab, .dock_to_split, .minimize, .maximize, .close }, b.vm.actions.slice());
    for ([_]chrome_mod.Action{ .open_as_tab, .dock_to_split, .minimize, .maximize, .close }) |action| try std.testing.expect(a.actionNode(action) != null and b.actionNode(action) != null);
    try std.testing.expect(b.vm.actionDisabled(.minimize) and !b.vm.actionDisabled(.maximize));
    try std.testing.expectEqualStrings("会话记录不支持收起", b.vm.actionTooltip(.minimize));
    // Order on screen follows the fixed order.
    for (a.vm.actions.slice()[1..], a.vm.actions.slice()[0 .. a.vm.actions.len - 1]) |action, previous| try std.testing.expect(a.actionNode(previous).?.globalRect().x < a.actionNode(action).?.globalRect().x);
    for (0..3) |index| {
        const slot = a.slotNode(index).?.globalRect();
        const first_action = a.actionNode(.open_as_tab).?.globalRect();
        // Slot buttons sit left of the actions, same size.
        try std.testing.expect(slot.x + slot.w <= first_action.x + 0.5);
        try std.testing.expectApproxEqAbs(first_action.w, slot.w, 0.1);
        try std.testing.expectApproxEqAbs(first_action.h, slot.h, 0.1);
    }
    try std.testing.expectApproxEqAbs(a.actionNode(.close).?.globalRect().w, b.actionNode(.close).?.globalRect().w, 0.1);
    // Labels: "<verb><title>", a space before a Latin title; the maximize label follows the state.
    try std.testing.expectEqualStrings("收起 AI 助手", a.vm.actionLabel(.minimize));
    try std.testing.expectEqualStrings("关闭会话记录", b.vm.actionLabel(.close));
    try std.testing.expectEqualStrings("放大会话记录", b.vm.actionLabel(.maximize));
    b.setMaximized(true);
    try std.testing.expectEqualStrings("还原会话记录", b.vm.actionLabel(.maximize));
    try std.testing.expect(std.meta.eql(ui.icons.minimize_2, b.vm.actionIcon(.maximize)));
    try std.testing.expect(std.meta.eql(ui.icons.panel_right, b.vm.actionIcon(.dock_to_split)));
}

/// The native Button inside an action's wrapper (Tooltip → Button).
fn actionButton(node: *ui.Node) ?*ui.Node {
    if (node.behavior.interaction.a11y) |a11y| if (a11y.role == .button) return node;
    for (node.children.items) |child| if (actionButton(child)) |found| return found;
    return null;
}

test "float chrome: refused placement actions are native disabled buttons with the reason as Tooltip" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1400, 500);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const a = try chrome_mod.Chrome.mount(cx, scope, chatSpec());
    const b = try chrome_mod.Chrome.mount(cx, scope, recordsSpec());
    var splittable = recordsSpec();
    splittable.descriptor.interactions.insert(.dock_to_split);
    splittable.ids = .{ .root = "fixture.split" };
    const c = try chrome_mod.Chrome.mount(cx, scope, splittable);
    try place(cx, a, 20, 420);
    try place(cx, b, 460, 420);
    try place(cx, c, 900, 420);
    settle(cx);
    // AI-like card: neither placement allowed.
    try std.testing.expect(a.vm.actionDisabled(.open_as_tab) and a.vm.actionDisabled(.dock_to_split) and !a.vm.actionDisabled(.minimize));
    try std.testing.expectEqualStrings("AI 助手不支持作为标签页打开", a.vm.actionTooltip(.open_as_tab));
    try std.testing.expectEqualStrings("AI 助手不支持分屏", a.vm.actionTooltip(.dock_to_split));
    try std.testing.expect(actionButton(a.actionNode(.dock_to_split).?).?.behavior.interaction.a11y.?.disabled);
    try std.testing.expect(!actionButton(a.actionNode(.close).?).?.behavior.interaction.a11y.?.disabled);
    try std.testing.expect(!a.actionEnabled(.dock_to_split) and a.actionEnabled(.close));
    // History-like card: open as tab yes, split no ("会话记录不支持分屏").
    try std.testing.expect(!b.vm.actionDisabled(.open_as_tab) and b.vm.actionDisabled(.dock_to_split));
    try std.testing.expectEqualStrings("作为标签页打开", b.vm.actionTooltip(.open_as_tab));
    try std.testing.expectEqualStrings("会话记录不支持分屏", b.vm.actionTooltip(.dock_to_split));
    // The card type's refusal wins over any owner state.
    b.setActionState(.dock_to_split, null);
    try std.testing.expectEqualStrings("会话记录不支持分屏", b.vm.actionTooltip(.dock_to_split));
    // A splittable card: the owner disables it for its state and enables it again.
    try std.testing.expect(c.actionEnabled(.dock_to_split));
    try std.testing.expectEqualStrings("放入分屏", c.vm.actionTooltip(.dock_to_split));
    c.setActionState(.dock_to_split, "所属标签页的分屏已满");
    settle(cx);
    try std.testing.expect(!c.actionEnabled(.dock_to_split));
    try std.testing.expectEqualStrings("所属标签页的分屏已满", c.vm.actionTooltip(.dock_to_split));
    try std.testing.expect(actionButton(c.actionNode(.dock_to_split).?).?.behavior.interaction.a11y.?.disabled);
    c.setActionState(.dock_to_split, null);
    settle(cx);
    try std.testing.expect(c.actionEnabled(.dock_to_split));
    try std.testing.expect(!actionButton(c.actionNode(.dock_to_split).?).?.behavior.interaction.a11y.?.disabled);
}

test "float chrome: buttons stay inside at 320; the subtitle ellipsizes, then hides, then returns" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1600, 500);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    var chromes: [3]*chrome_mod.Chrome = undefined;
    // float-split: the two placement actions add 2 × (24 + 6) to the header, so the "ellipsized but
    // readable" width moves from 380 to 440 (the rule itself is unchanged).
    for (&chromes, [_]f32{ 320, 440, 660 }, [_]f32{ 20, 360, 820 }) |*c, width, x| {
        c.* = try chrome_mod.Chrome.mount(cx, scope, chatSpec());
        c.*.setSubtitle("KVM Layout Fixture");
        try place(cx, c.*, x, width);
    }
    settle(cx);
    for (chromes) |c| {
        const header = c.header.globalRect();
        const close = c.actionNode(.close).?.globalRect();
        try std.testing.expect(close.x + close.w <= header.x + header.w + 0.5);
        // Eight buttons at 320 (three slots + five actions): none shrinks.
        for (c.vm.actions.slice()) |action| try std.testing.expectApproxEqAbs(c.actionNode(.close).?.globalRect().w, c.actionNode(action).?.globalRect().w, 0.1);
    }
    const narrow, const wide, const roomy = chromes;
    // 320: no room for a readable subtitle next to eight buttons → hidden, not squeezed to "…".
    try std.testing.expectEqual(ui.types.Display.none, narrow.slots.subtitle.?.style.display);
    // 440: the subtitle shrinks (ellipsized, still readable); 660: full.
    try std.testing.expect(wide.slots.subtitle.?.style.display != .none);
    try std.testing.expect(wide.slots.subtitle.?.globalRect().w >= chrome_mod.min_subtitle_width - 0.5);
    try std.testing.expect(wide.slots.subtitle.?.globalRect().w < roomy.slots.subtitle.?.globalRect().w);
    try std.testing.expect(roomy.slots.subtitle.?.style.display != .none);
    // A shorter subtitle that fits comes back (with eight buttons, once the card is a little wider).
    narrow.setSubtitle("本机");
    narrow.root.parent.?.setStyle(cx.allocator, .width, .{ .px = 380 });
    narrow.root.markLayoutDirty();
    settle(cx);
    try std.testing.expect(narrow.slots.subtitle.?.style.display != .none);
}

const Owner = struct {
    closed: usize = 0,
    minimized: usize = 0,
    slots: usize = 0,
    fn close(ctx: ?*anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(ctx.?));
        self.closed += 1;
    }
    fn action(ctx: ?*anyopaque, value: model.HeaderAction) bool {
        const self: *Owner = @ptrCast(@alignCast(ctx.?));
        if (value != .minimize) return false;
        self.minimized += 1;
        return true;
    }
    fn slot(ctx: ?*anyopaque, _: usize) void {
        const self: *Owner = @ptrCast(@alignCast(ctx.?));
        self.slots += 1;
    }
};

test "float chrome on the layer: maximize is the layer's, minimize goes to the owner, close closes" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1440, 900);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const layer = try layer_mod.FloatLayer.mount(cx, scope, cx.root.?);
    const region = model.floatRegion(1440, 900, 44, 240);
    layer.setRegion(region);
    var owner: Owner = .{};
    var placement: model.Placement = .{};
    const chrome = try chrome_mod.Chrome.mount(cx, scope, chatSpec());
    chrome.setSlotHandler(.{ .ctx = &owner, .slot = Owner.slot });
    const node = try ui.box(cx, .{ .position = .absolute, .direction = .column }, .{});
    try cx.root.?.appendChild(cx.allocator, node);
    const card = try layer.attach(scope, .{ .node = node, .chrome = chrome, .descriptor = chat, .placement = &placement, .callbacks = .{ .ctx = &owner, .close = Owner.close, .action = Owner.action } });
    try std.testing.expect(card.frame == chrome.root and card.grip.? == chrome.grip and chrome.root.parent == node);
    card.update(.{ .content = .{ .x = 240, .y = 44, .width = 1200, .height = 820 } }, true);
    settle(cx);
    chrome.vm.act(.maximize);
    try std.testing.expect(placement.maximized and chrome.vm.isMaximized());
    chrome.vm.act(.maximize);
    try std.testing.expect(!placement.maximized and !chrome.vm.isMaximized());
    chrome.vm.act(.minimize);
    try std.testing.expectEqual(@as(usize, 1), owner.minimized);
    try std.testing.expectEqual(@as(usize, 0), owner.closed);
    chrome.vm.act(.close);
    try std.testing.expectEqual(@as(usize, 1), owner.closed);
    chrome.vm.press(2);
    try std.testing.expectEqual(@as(usize, 1), owner.slots);
    // A disabled placement action never reaches the owner or the layer.
    chrome.vm.act(.dock_to_split);
    chrome.vm.act(.open_as_tab);
    try std.testing.expectEqual(@as(usize, 1), owner.minimized);
}
