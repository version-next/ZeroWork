/// Disclosure Component.
///
/// A one-line trigger that shows and hides its content: chevron, a status icon (or a `status`
/// slot), title, detail (count / status), and a trailing text (duration). The open content hangs
/// on a 1px rail at the left rather than inside a card — process details that stay out of the
/// way (AI chat step groups, "thinking"). View in disclosure.yix; styles in styles.yss.
const std = @import("std");
const core = @import("../../core.zig");
const Cx = core.Cx;
const Node = core.Node;
const Color = core.Color;
const reactive = @import("../../reactive.zig");
const Scope = reactive.Scope;

/// Ink of the status icon / detail text.
pub const DisclosureTone = enum { neutral, accent, success, warning, danger };

/// Create Disclosure: `ui.view.with(W.Disclosure(.{ .title = "Read PDU log", .trailing = "9.4s" }),
/// .{ …rows… })`; Yix `<W.Disclosure title="…" trailing="9.4s">…</W.Disclosure>`.
pub const Disclosure = @import("_disclosure.yix.zig").Disclosure;

// ========== Tests ==========

const view = @import("../../view.zig");
const icons = @import("zenit_icons");

const Fixture = struct {
    cx: *Cx,
    scope: *Scope,
    root: *Node,

    fn init() !Fixture {
        const cx = try Cx.init(std.testing.allocator, std.testing.io);
        cx.setViewport(420, 400);
        const root = try core.box(cx, .{ .width = .{ .px = 388 }, .height = .{ .px = 400 }, .direction = .column }, .{});
        cx.root = root;
        return .{ .cx = cx, .scope = try Scope.init(std.testing.allocator, null, cx.owner), .root = root };
    }

    fn deinit(f: Fixture) void {
        f.scope.dispose();
        f.cx.deinit();
    }
};

fn findText(n: *Node, text: []const u8) ?*Node {
    if (n.getText()) |t| if (std.mem.eql(u8, t.content, text)) return n;
    for (n.children.items) |c| if (findText(c, text)) |r| return r;
    return null;
}

const Glyphs = struct {
    items: [4]*Node = undefined,
    len: usize = 0,
};

/// Icon nodes among a row's direct children, in order.
fn iconsOf(row: *Node) Glyphs {
    var out: Glyphs = .{};
    for (row.children.items) |c| if (c.getIcon() != null and out.len < 4) {
        out.items[out.len] = c;
        out.len += 1;
    };
    return out;
}

const Toggles = struct {
    count: u32 = 0,
    last: bool = false,
    fn changed(self: *Toggles, open: bool) void {
        self.count += 1;
        self.last = open;
    }
};

test "Disclosure: one-line trigger (28, chevron, status, title, detail, trailing); content on a left rail, hidden until opened" {
    const f = try Fixture.init();
    defer f.deinit();
    var toggles: Toggles = .{};
    const node = try view.render(f.scope, f.cx, view.with(Disclosure(.{
        .title = "Read PDU log",
        .icon_asset = icons.circle_x,
        .icon_tone = .danger,
        .detail = "· 5 steps · 1 failed",
        .detail_tone = .danger,
        .trailing = "9.4s",
        .trigger_test_id = "d.trigger",
        .content_test_id = "d.content",
        .on_open_change = core.Handler(bool).from(Toggles, &toggles, Toggles.changed),
    }), .{view.text(.{}, "step one"), view.text(.{}, "step two")}));
    try f.root.appendChild(std.testing.allocator, node);
    f.cx.layout();
    const k = f.cx.tokens.tokens;
    try std.testing.expectEqualStrings("Disclosure", node.meta.ownership.meta.component_name.?);
    const trigger = node.children.items[0];
    const rail = node.children.items[1];
    try std.testing.expectEqualStrings("d.trigger", trigger.meta.ownership.meta.test_id.?);
    try std.testing.expectEqualStrings("d.content", rail.meta.ownership.meta.test_id.?);
    try std.testing.expectApproxEqAbs(@as(f32, 28), trigger.globalRect().h, 0.5);
    try std.testing.expectApproxEqAbs(@as(f32, 388), trigger.globalRect().w, 0.5);
    // chevron 12, status 14 (danger), title 12/500 fg-secondary, detail danger, trailing 11 fg-tertiary at the right.
    const glyphs = iconsOf(trigger);
    try std.testing.expectEqual(@as(usize, 2), glyphs.len);
    try std.testing.expectEqual(@as(f32, 12), glyphs.items[0].globalRect().w);
    const status = glyphs.items[1];
    try std.testing.expectEqual(@as(f32, 14), status.globalRect().w);
    try std.testing.expect(Color.eql(status.getIcon().?.tint, k.color.danger));
    const title = findText(trigger, "Read PDU log").?.getText().?;
    try std.testing.expect(Color.eql(title.color, k.color.fg_secondary));
    try std.testing.expectEqual(@as(u16, 500), title.font_weight);
    try std.testing.expectEqual(k.font_size.sm, title.font_size);
    try std.testing.expect(Color.eql(findText(trigger, "· 5 steps · 1 failed").?.getText().?.color, k.color.danger));
    const trailing = findText(trigger, "9.4s").?;
    try std.testing.expect(Color.eql(trailing.getText().?.color, k.color.fg_tertiary));
    try std.testing.expectEqual(k.font_size.xs, trailing.getText().?.font_size);
    try std.testing.expectApproxEqAbs(trigger.globalRect().x + trigger.globalRect().w - 6, trailing.globalRect().x + trailing.globalRect().w, 0.5);
    // a11y: a collapsed button; the rail is hidden.
    const a = trigger.behavior.interaction.a11y.?;
    try std.testing.expectEqual(core.A11yRole.button, a.role);
    try std.testing.expectEqual(@as(?bool, false), a.expanded);
    try std.testing.expect(trigger.behavior.interaction.focusable);
    try std.testing.expectEqual(core.Display.none, rail.style.display);

    // Click: opens, reports, fills the trigger; the rail shows with its 1px left line.
    trigger.behavior.events.on_click.?.invoke();
    f.cx.layout();
    try std.testing.expectEqual(@as(?bool, true), trigger.behavior.interaction.a11y.?.expanded);
    try std.testing.expectEqual(core.Display.flex, rail.style.display);
    try std.testing.expectEqual(@as(u32, 1), toggles.count);
    try std.testing.expect(toggles.last);
    try std.testing.expectEqual(@as(f32, 1), rail.style.border.resolvedWidths()[3]);
    try std.testing.expectEqual(@as(f32, 0), rail.style.border.resolvedWidths()[0]);
    try std.testing.expectEqual(@as(f32, 12), rail.style.padding.left);
    try std.testing.expect(rail.getBackground().a == 0);
    try std.testing.expectEqual(@as(usize, 2), rail.children.items.len);

    // Keyboard: Enter / Space on the focused trigger toggle it.
    f.cx.setFocus(trigger);
    f.cx.handleKeyDown(.@"return", .{});
    try std.testing.expectEqual(@as(?bool, false), trigger.behavior.interaction.a11y.?.expanded);
    f.cx.handleKeyDown(.space, .{});
    try std.testing.expectEqual(@as(?bool, true), trigger.behavior.interaction.a11y.?.expanded);
    try std.testing.expectEqual(@as(u32, 3), toggles.count);
}

test "Disclosure: open is a Model (a signal opens it from outside); disabled does not toggle" {
    const f = try Fixture.init();
    defer f.deinit();
    const open = try f.scope.createSignal(bool, false);
    const node = try view.render(f.scope, f.cx, view.with(Disclosure(.{ .title = "Thinking", .open = open }), .{view.text(.{}, "…")}));
    try f.root.appendChild(std.testing.allocator, node);
    open.set(true);
    try std.testing.expectEqual(core.Display.flex, node.children.items[1].style.display);
    node.children.items[0].behavior.events.on_click.?.invoke();
    try std.testing.expect(!open.peek());

    const off = try view.render(f.scope, f.cx, view.with(Disclosure(.{ .title = "Locked", .disabled = true }), .{view.text(.{}, "x")}));
    try f.root.appendChild(std.testing.allocator, off);
    const trigger = off.children.items[0];
    try std.testing.expect(!trigger.behavior.interaction.focusable);
    if (trigger.behavior.events.on_click) |h| h.invoke();
    try std.testing.expectEqual(core.Display.none, off.children.items[1].style.display);
    try std.testing.expectEqual(@as(?bool, true), trigger.behavior.interaction.a11y.?.disabled);
}

test "Disclosure: a status slot takes the status box (a spinner while running)" {
    const f = try Fixture.init();
    defer f.deinit();
    const node = try view.render(f.scope, f.cx, view.with(Disclosure(.{ .title = "Running" }), .{view.text(.{}, "step")}).slots(.{
        .status = view.box(.{ .style = .{ .width = .{ .px = 12 }, .height = .{ .px = 12 } } }, {}),
    }));
    try f.root.appendChild(std.testing.allocator, node);
    f.cx.layout();
    var slot: *Node = undefined;
    for (node.children.items[0].children.items) |c| {
        if (c.getIcon() == null and c.children.items.len == 1 and c.children.items[0].getText() == null) slot = c;
    }
    try std.testing.expectEqual(@as(f32, 14), slot.globalRect().w);
    try std.testing.expectEqual(@as(usize, 1), slot.children.items.len);
}

fn findId(n: *Node, id: []const u8) ?*Node {
    if (n.meta.ownership.meta.test_id) |t| if (std.mem.eql(u8, t, id)) return n;
    for (n.children.items) |c| if (findId(c, id)) |r| return r;
    return null;
}

test "Disclosure: part test ids name the chevron, title, detail and trailing (also when they appear later)" {
    const f = try Fixture.init();
    defer f.deinit();
    const detail = try f.scope.createText("", .{});
    const trailing = try f.scope.createText("1.2s", .{});
    const node = try view.render(f.scope, f.cx, view.with(Disclosure(.{ .title = "Steps", .detail = detail, .trailing = trailing, .chevron_test_id = "d.chevron", .title_test_id = "d.title", .detail_test_id = "d.detail", .trailing_test_id = "d.trailing" }), .{view.text(.{}, "a")}));
    try f.root.appendChild(std.testing.allocator, node);
    try std.testing.expect(findId(node, "d.chevron").?.getIcon() != null);
    try std.testing.expectEqualStrings("Steps", findId(node, "d.title").?.getText().?.content);
    try std.testing.expectEqualStrings("1.2s", findId(node, "d.trailing").?.getText().?.content);
    try std.testing.expect(findId(node, "d.detail") == null);
    detail.set("· 3 个步骤");
    f.cx.layout();
    try std.testing.expectEqualStrings("· 3 个步骤", findId(node, "d.detail").?.getText().?.content);
}

test "disclosure: mount 在任意分配点失败时不泄漏（sweep）" {
    try @import("../oom_sweep.zig").sweepMount("disclosure", struct {
        fn m(scope: *Scope, cx: *Cx) anyerror!?*Node {
            const open = try scope.createSignal(bool, true);
            return try view.render(scope, cx, view.with(Disclosure(.{ .title = "Steps", .open = open, .icon_asset = icons.check, .detail = "· 3", .trailing = "1.2s" }), .{view.text(.{}, "a")}));
        }
    }.m);
}

// test collection for styles.yss, this line required, see docs/STYLING.md
test {
    _ = @import("_styles.yss.zig");
}
