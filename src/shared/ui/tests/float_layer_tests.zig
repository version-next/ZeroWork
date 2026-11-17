//! The generic floating card layer with a fixture (non-AI) card type: every enumerable interaction
//! (move, resize, maximize, raise, close, fold_to_tab, open_from_anchor, remember_position) on a
//! window-free Cx with real layout, drag bindings and Z12 transitions.
const std = @import("std");
const ui = @import("ui");
const model = @import("../../base/float_card.zig");
const layer_mod = @import("../float_card/float_layer.zig");
const tab_registration = @import("../../../features/workspace/view/tab_motion_anchor.zig");

fn fixtureSize(content: model.Rect) model.Size {
    return .{ .width = @min(400, content.width / 2), .height = 300 };
}
const fixture: model.Descriptor = .{
    .id = "fixture.card",
    .interactions = model.Interactions.full,
    .min_size = .{ .width = 200, .height = 120 },
    .max_size = .{ .width = 800, .height = 600 },
    .default_size = fixtureSize,
    .first_open = .beside_anchor,
};
const region = model.floatRegion(1440, 900, 44, 240);
const anchor: model.Rect = .{ .x = 1368, .y = 796, .width = 48, .height = 48 };
const origin: model.Origin = .{ .content = .{ .x = 240, .y = 44, .width = 1200, .height = 820 }, .anchor = anchor, .corner = .bottom_right };

const Owner = struct {
    closed: usize = 0,
    rests: usize = 0,
    fn close(ctx: ?*anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(ctx.?));
        self.closed += 1;
    }
    fn rest(ctx: ?*anyopaque, _: ui.fx.anchor_transition.Phase) void {
        const self: *Owner = @ptrCast(@alignCast(ctx.?));
        self.rests += 1;
    }
};

const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    layer: *layer_mod.FloatLayer,
    tabs: [2]*ui.Node,
    cards: [2]*layer_mod.Card,
    frames: [2]*ui.Node,
    grips: [2]*ui.Node,
    placements: [2]model.Placement = .{ .{}, .{} },
    owner: Owner = .{},
    shown: [2]bool = .{ true, false },

    fn init(self: *Fixture) !void {
        self.* = .{ .cx = try ui.Cx.init(std.testing.allocator, std.testing.io), .scope = undefined, .layer = undefined, .tabs = undefined, .cards = undefined, .frames = undefined, .grips = undefined };
        self.cx.setViewport(1440, 900);
        self.scope = try ui.Scope.init(std.testing.allocator, null, self.cx.owner);
        self.cx.root = try ui.box(self.cx, .{ .width = .fill(), .height = .fill() }, .{});
        // Two tabs on a strip, registered as Z12 anchors like the workspace does.
        for (&self.tabs, 0..) |*tab, index| {
            tab.* = try ui.box(self.cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 300 + 140 * @as(f32, @floatFromInt(index)) }, .top = .{ .px = 8 } }, .width = .{ .px = 120 }, .height = .{ .px = 30 } }, .{});
            try self.cx.root.?.appendChild(self.cx.allocator, tab.*);
            try tab_registration.register(self.scope, self.cx, 1 + index, tab.*);
        }
        self.layer = try layer_mod.FloatLayer.mount(self.cx, self.scope, self.cx.root.?);
        self.layer.setRegion(region);
        // Pointer samples on a frozen clock: these drags are placements, never flings (inertia has
        // its own tests in float_swipe_layer_tests).
        self.layer.clock = .{ .ctx = null, .now_ns = frozenClock };
        for (0..2) |index| {
            const node = try ui.box(self.cx, .{ .position = .absolute, .direction = .column }, .{});
            const visual = try ui.box(self.cx, .{ .direction = .column, .background = ui.Color.rgb(230, 236, 250), .hit_behavior = .@"opaque" }, .{});
            const grip = try ui.box(self.cx, .{ .width = .fill(), .height = .{ .px = 14 } }, .{});
            try visual.appendChild(self.cx.allocator, grip);
            try visual.appendChild(self.cx.allocator, try ui.box(self.cx, .{ .width = .fill(), .height = .{ .px = 40 }, .background = ui.Color.rgb(200, 210, 240) }, .{}));
            try node.appendChild(self.cx.allocator, visual);
            try self.cx.root.?.appendChild(self.cx.allocator, node);
            self.frames[index] = visual;
            self.grips[index] = grip;
            self.cards[index] = try self.layer.attach(self.scope, .{ .node = node, .frame = visual, .grip = grip, .descriptor = fixture, .placement = &self.placements[index], .callbacks = .{ .ctx = &self.owner, .close = Owner.close, .rest = Owner.rest } });
        }
        self.cards[1].hideNow();
        self.frame();
    }
    fn frozenClock(_: ?*anyopaque) u64 {
        return 0;
    }
    fn deinit(self: *Fixture) void {
        self.scope.dispose();
        self.cx.deinit();
    }
    fn frame(self: *Fixture) void {
        for (self.cards, self.shown) |card, shown| card.update(origin, shown);
        self.cx.frame_count += 1;
        self.cx.frame_time_ms += 16;
        _ = self.cx.render();
    }
    fn settle(self: *Fixture) void {
        for (0..60) |_| self.frame();
    }
    fn drag(self: *Fixture, node: *ui.Node, dx: f32, dy: f32) void {
        const r = node.globalRect();
        const x = r.x + r.w / 2;
        const y = r.y + r.h / 2;
        self.cx.handleMouseDown(x, y, .{});
        self.cx.handleMouseMove(x + dx, y + dy);
        self.frame();
        self.cx.handleMouseUp(x + dx, y + dy);
        self.frame();
    }
};

fn rectOf(node: *ui.Node) model.Rect {
    const r = node.globalRect();
    return .{ .x = r.x, .y = r.y, .width = r.w, .height = r.h };
}

test "float layer fixture card: first open beside its anchor, move inside the region, remembered" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const first = rectOf(f.frames[0]);
    try std.testing.expectEqual(anchor.x + anchor.width, first.x + first.width);
    try std.testing.expectEqual(anchor.y + anchor.height, first.y + first.height);
    try std.testing.expectEqual(@as(f32, 400), first.width);
    f.drag(f.grips[0], -300, -200);
    const moved = rectOf(f.frames[0]);
    try std.testing.expectEqual(first.x - 300, moved.x);
    try std.testing.expectEqual(first.y - 200, moved.y);
    try std.testing.expectEqualDeep(moved, f.placements[0].desired.?);
    // Far outside: stops at the region edges (title bar and sidebar are never entered).
    f.drag(f.grips[0], -3000, -3000);
    try std.testing.expectEqual(region.x, rectOf(f.frames[0]).x);
    try std.testing.expectEqual(region.y, rectOf(f.frames[0]).y);
    // Closing keeps a remembered rectangle; the next open returns there.
    const kept = f.placements[0].desired.?;
    f.cards[0].close();
    try std.testing.expectEqual(@as(usize, 1), f.owner.closed);
    try std.testing.expectEqualDeep(kept, f.placements[0].desired.?);
}

test "float layer fixture card: eight-way resize honours the declared min and max; maximize fills the region" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.placements[0].setRectangle(fixture, .{ .x = 600, .y = 200, .width = 400, .height = 300 }, origin, region);
    f.frame();
    for (f.cards[0].handles, 0..) |maybe, index| {
        const handle = maybe.?;
        try std.testing.expect(handle.isDisplayedInTree());
        const before = rectOf(f.frames[0]);
        const edge: model.Edge = @enumFromInt(index);
        const dx: f32 = if (edge.west()) -20 else if (edge.east()) 20 else 0;
        const dy: f32 = if (edge.north()) -10 else if (edge.south()) 10 else 0;
        f.drag(handle, dx, dy);
        const after = rectOf(f.frames[0]);
        try std.testing.expect(@abs(after.width - before.width) > 1 or @abs(after.height - before.height) > 1);
    }
    f.drag(f.cards[0].handles[7].?, 2000, 2000); // se: to the declared maximum
    try std.testing.expect(rectOf(f.frames[0]).width <= 800 and rectOf(f.frames[0]).height <= 600);
    f.drag(f.cards[0].handles[4].?, 2000, 2000); // nw: to the declared minimum
    try std.testing.expectEqual(@as(f32, 200), rectOf(f.frames[0]).width);
    try std.testing.expectEqual(@as(f32, 120), rectOf(f.frames[0]).height);
    const restored = rectOf(f.frames[0]);
    f.cards[0].toggleMaximized();
    f.frame();
    try std.testing.expectEqualDeep(region, rectOf(f.frames[0]));
    for (f.cards[0].handles) |handle| try std.testing.expect(!handle.?.isDisplayedInTree());
    f.cards[0].toggleMaximized();
    f.frame();
    try std.testing.expectEqualDeep(restored, rectOf(f.frames[0]));
}

test "float layer resize strips are wheel-transparent: a wheel over the east strip scrolls the list under it" {
    // ai-redesign-e: the card's outer 6 on the east is its resize strip, laid over the conversation's
    // scroll bar. The card swallows wheels (floating_input.protect), so a wheel routed from the strip
    // stopped at the card; the strip is wheel-transparent, so it reaches the list it covers.
    const Probe = struct {
        list_hits: u32 = 0,
        card_hits: u32 = 0,
        fn list(event: ui.events.Event, ctx: ?*anyopaque) ui.events.EventResult {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            if (event != .scroll) return .ignored;
            self.list_hits += 1;
            return .stop;
        }
        fn card(_: ui.events.ScrollEvent, ctx: ?*anyopaque) ui.events.EventResult {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.card_hits += 1;
            return .stop;
        }
    };
    var probe: Probe = .{};
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const visual = f.frames[0];
    visual.behavior.events.on_scroll = Probe.card;
    visual.behavior.events.event_context = &probe;
    const list = try ui.box(f.cx, .{ .width = .fill(), .height = .{ .px = 240 } }, .{});
    list.tag = .scroll;
    list.behavior.events.on_event = Probe.list;
    list.behavior.events.event_context = &probe;
    try visual.appendChild(f.cx.allocator, list);
    f.placements[0].setRectangle(fixture, .{ .x = 600, .y = 200, .width = 400, .height = 300 }, origin, region);
    f.frame();

    const east = f.cards[0].handles[@intFromEnum(model.Edge.e)].?;
    try std.testing.expect(east.isDisplayedInTree());
    try std.testing.expect(east.behavior.interaction.wheel_transparent);
    const r = east.globalRect();
    const lr = list.globalRect();
    const x = r.x + r.w / 2;
    const y = lr.y + lr.h / 2;
    try std.testing.expect(y > r.y and y < r.y + r.h);
    // Hover still finds the strip (resize cursor, press starts a resize) ...
    const hit = f.cx.hitTestQuery(.{ .kind = .pointer, .world_x = x, .world_y = y });
    try std.testing.expectEqual(east.id, hit.?.node_id);
    // ... and the wheel goes to the list under it, not to the card.
    f.cx.handleScroll(.{ .x = x, .y = y, .dx = 0, .dy = -40 });
    try std.testing.expectEqual(@as(u32, 1), probe.list_hits);
    try std.testing.expectEqual(@as(u32, 0), probe.card_hits);
    for (f.cards[0].handles) |handle| try std.testing.expect(handle.?.behavior.interaction.wheel_transparent);
}

test "float layer raise brings the pressed card above the other floating cards" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.placements[1].setRectangle(fixture, .{ .x = 400, .y = 150, .width = 300, .height = 200 }, origin, region);
    f.shown[1] = true;
    f.cards[1].present(.{ .shown = true, .tab = 2, .current_tab = 2, .explicit = true });
    f.settle();
    const a = f.cards[0].node;
    const b = f.cards[1].node;
    f.layer.raise(f.cards[0]);
    try std.testing.expect(a.style.z_index() > b.style.z_index());
    const r = f.frames[1].globalRect();
    f.cx.handleMouseDown(r.x + 30, r.y + 30, .{});
    f.cx.handleMouseUp(r.x + 30, r.y + 30);
    f.frame();
    try std.testing.expect(b.style.z_index() > a.style.z_index());
}

test "float layer presentation: open from the anchor, fold into the owner tab, unfold back, retarget, closed tab" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const card = f.cards[0];
    card.hideNow();
    f.settle();
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsed, card.phase());
    // Explicit open on tab 1 unfolds from the anchor.
    card.present(.{ .shown = true, .tab = 1, .current_tab = 1, .explicit = true, .anchor = anchor });
    try std.testing.expect(card.anchor_flight);
    f.settle();
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.expanded, card.phase());
    try std.testing.expect(!card.anchor_flight);
    const home = rectOf(f.frames[0]);
    // Tab 2 becomes current: fold into tab 1 on the strip.
    card.present(.{ .shown = false, .tab = 1, .current_tab = 2 });
    try std.testing.expectEqualStrings("workspace.tab.1", card.anchor_label);
    f.frame();
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsing, card.phase());
    // Rapid switch back: the run reverses mid flight (no queue) and lands at home.
    card.present(.{ .shown = true, .tab = 1, .current_tab = 1 });
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.expanding, card.phase());
    f.settle();
    try std.testing.expectEqualDeep(home, rectOf(f.frames[0]));
    // Fold fully, then the end frame rests in tab 1's anchor.
    card.present(.{ .shown = false, .tab = 1, .current_tab = 2 });
    f.settle();
    const folded = card.presentedRect();
    const tab = f.tabs[0].globalRect();
    try std.testing.expect(@abs(folded.x - tab.x) < 0.5 and @abs(folded.w - tab.w) < 0.5);
    // Unfold from tab 1 back to the remembered home.
    card.present(.{ .shown = true, .tab = 1, .current_tab = 1 });
    try std.testing.expectEqualStrings("workspace.tab.1", card.anchor_label);
    f.settle();
    try std.testing.expectEqualDeep(home, rectOf(f.frames[0]));
    // Explicit close folds into the anchor.
    card.present(.{ .shown = false, .tab = 1, .current_tab = 1, .explicit = true, .anchor = anchor });
    try std.testing.expectEqualStrings("anchor", card.anchor_label);
    f.settle();
    try std.testing.expectEqual(@as(?*ui.Node, null), if (f.cards[0].node.isDisplayedInTree()) f.cards[0].node else null);
    // A card whose tab is gone closes with it, without motion.
    card.present(.{ .shown = true, .tab = 1, .current_tab = 1, .explicit = true, .anchor = anchor });
    f.settle();
    card.present(.{ .shown = false, .tab = 9, .current_tab = 2 });
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsed, card.phase());
}

test "float layer fade mode and missing interactions" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    // The mode is read from the host's source when each run starts (ui.float_card_transition).
    const Source = struct {
        mode: layer_mod.TransitionMode = .fade,
        reads: usize = 0,
        fn read(ctx: ?*anyopaque) layer_mod.TransitionMode {
            const self: *@This() = @ptrCast(@alignCast(ctx.?));
            self.reads += 1;
            return self.mode;
        }
    };
    var source: Source = .{};
    f.layer.setModeSource(.{ .ctx = &source, .read = Source.read });
    const card = f.cards[0];
    card.hideNow();
    f.settle();
    const home = rectOf(f.frames[0]);
    card.present(.{ .shown = true, .tab = 1, .current_tab = 1, .explicit = true, .anchor = anchor });
    try std.testing.expectEqual(@as(usize, 1), source.reads);
    try std.testing.expectEqual(ui.fx.anchor_transition.Mode.fade_scale, card.transition.?.options.tokens.mode);
    try std.testing.expectEqualStrings("none", card.anchor_label);
    try std.testing.expect(!card.anchor_flight);
    f.settle();
    // Z12b: fades out in place, shrinking slightly around the card's own center (no anchor).
    card.present(.{ .shown = false, .tab = 1, .current_tab = 2 });
    try std.testing.expectEqualStrings("none", card.anchor_label);
    var smallest: f32 = std.math.inf(f32);
    for (0..40) |_| {
        f.frame();
        if (card.transition.?.currentFrame()) |frame| {
            smallest = @min(smallest, frame.rect.w);
            try std.testing.expect(@abs((frame.rect.x + frame.rect.w / 2) - (home.x + home.width / 2)) < 1);
        }
    }
    try std.testing.expect(smallest < home.width and smallest >= home.width * 0.95);
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsed, card.phase());
    // Switching the setting back applies from the next run.
    source.mode = .anchor;
    card.present(.{ .shown = true, .tab = 1, .current_tab = 1 });
    try std.testing.expectEqual(ui.fx.anchor_transition.Mode.anchor, card.transition.?.options.tokens.mode);
    try std.testing.expectEqualStrings("workspace.tab.1", card.anchor_label);
    f.settle();
    // A card type without close / maximize / remember_position.
    var fixed = fixture;
    fixed.interactions = model.Interactions.initMany(&.{ .move, .fold_to_tab });
    f.cards[1].descriptor = fixed;
    f.placements[1].setRectangle(fixed, .{ .x = 500, .y = 200, .width = 300, .height = 200 }, origin, region);
    f.cards[1].toggleMaximized();
    try std.testing.expect(!f.placements[1].maximized);
    f.cards[1].close();
    try std.testing.expectEqual(@as(usize, 0), f.owner.closed);
    f.placements[1].closed(fixed);
    try std.testing.expect(f.placements[1].desired == null);
}

test "float layer reduce motion: both modes fade in place instead of flying to the tab" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.cx.reduced_motion = true;
    const card = f.cards[0];
    const home = rectOf(f.frames[0]);
    for ([_]layer_mod.TransitionMode{ .anchor, .fade }) |mode| {
        f.layer.setMode(mode);
        card.present(.{ .shown = true, .tab = 1, .current_tab = 1, .explicit = true, .anchor = anchor });
        f.settle();
        card.present(.{ .shown = false, .tab = 1, .current_tab = 2 });
        var seen = false;
        for (0..30) |_| {
            f.frame();
            if (card.transition.?.currentFrame()) |frame| {
                seen = true;
                // Same rectangle as home: only the opacity changes.
                try std.testing.expect(@abs(frame.rect.x - home.x) < 0.5 and @abs(frame.rect.w - home.width) < 0.5);
            }
        }
        try std.testing.expect(seen);
        try std.testing.expectEqual(ui.fx.anchor_transition.Phase.collapsed, card.phase());
    }
}

test "float layer flight probe: presented opacity, and the flight covers the open anchor only when opaque over it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const card = f.cards[0];
    card.hideNow();
    f.settle();
    try std.testing.expectEqual(@as(f32, 0), card.presentedOpacity());
    try std.testing.expect(!card.flightCovers(anchor));
    // Opening from the anchor: visible from the first drawn frame (zenit expand clock), opaque later,
    // and once the card rests it is no flight any more.
    card.present(.{ .shown = true, .tab = 1, .current_tab = 1, .explicit = true, .anchor = anchor });
    f.frame();
    f.frame();
    try std.testing.expectEqual(ui.fx.anchor_transition.Phase.expanding, card.phase());
    try std.testing.expect(card.presentedOpacity() > 0.2);
    f.settle();
    try std.testing.expectEqual(@as(f32, 1), card.presentedOpacity());
    try std.testing.expect(!card.flightCovers(anchor));
    // Closing into the anchor: the first frames still draw the opaque card over its home, which
    // holds the anchor (bottom-right corner); near the end the shrinking, fading card no longer does.
    const home = rectOf(f.frames[0]);
    const inside: model.Rect = .{ .x = home.x + home.width - 60, .y = home.y + home.height - 60, .width = 48, .height = 48 };
    card.present(.{ .shown = false, .tab = 1, .current_tab = 1, .explicit = true, .anchor = anchor });
    f.frame();
    try std.testing.expect(card.flightCovers(inside));
    var uncovered = false;
    for (0..40) |_| {
        f.frame();
        if (card.phase() == .collapsing and !card.flightCovers(inside)) uncovered = true;
    }
    try std.testing.expect(uncovered);
    try std.testing.expectEqual(@as(f32, 0), card.presentedOpacity());
}

fn focusFixture(f: *Fixture, trigger: **ui.Node, elsewhere: **ui.Node, controls: *[2]*ui.Node) !void {
    const cx = f.cx;
    trigger.* = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 10 }, .top = .{ .px = 10 } }, .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{});
    trigger.*.setFocusable(true);
    try cx.root.?.appendChild(cx.allocator, trigger.*);
    elsewhere.* = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 10 }, .top = .{ .px = 600 } }, .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{});
    elsewhere.*.setFocusable(true);
    try cx.root.?.appendChild(cx.allocator, elsewhere.*);
    for (controls) |*control| {
        control.* = try ui.box(cx, .{ .width = .{ .px = 60 }, .height = .{ .px = 20 } }, .{});
        control.*.setFocusable(true);
        try f.frames[0].appendChild(cx.allocator, control.*);
    }
    f.settle();
}

test "card focus protocol: an owner that placed focus itself keeps it; with nobody placing it the first control gets it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    var trigger: *ui.Node = undefined;
    var elsewhere: *ui.Node = undefined;
    var controls: [2]*ui.Node = undefined;
    try focusFixture(&f, &trigger, &elsewhere, &controls);
    const card = f.cards[0];

    // The owner puts focus on its own control in the same step as the open (its content is in the
    // window by then — LIFECYCLE.md §3; there is no deferred request to wait for any more).
    cx.setFocus(trigger);
    card.focusOpened(null);
    cx.setFocus(controls[1]);
    for (0..10) |_| f.frame();
    try std.testing.expect(cx.focus_manager.getFocused() == controls[1]);
    card.focusClosed();
    try std.testing.expect(cx.focus_manager.getFocused() == trigger);

    // Nobody places focus: the first control gets it on the frame the card shows.
    card.focusOpened(null);
    f.frame();
    try std.testing.expect(cx.focus_manager.getFocused() == controls[0]);
    card.focusClosed();
}

test "card focus protocol: focus moved outside after the card showed ends the entry" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    var trigger: *ui.Node = undefined;
    var elsewhere: *ui.Node = undefined;
    var controls: [2]*ui.Node = undefined;
    try focusFixture(&f, &trigger, &elsewhere, &controls);
    const card = f.cards[0];
    cx.setFocus(trigger);
    card.focusOpened(null);
    f.frame();
    try std.testing.expect(cx.focus_manager.getFocused() == controls[0]);
    // The user clicks elsewhere: the card does not take focus back, on any later frame.
    cx.setFocus(elsewhere);
    for (0..10) |_| f.frame();
    try std.testing.expect(cx.focus_manager.getFocused() == elsewhere);
}

test "card focus protocol: a hidden return target gets focus on the frame it shows, with no frame budget; focus placed elsewhere cancels it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    var trigger: *ui.Node = undefined;
    var elsewhere: *ui.Node = undefined;
    var controls: [2]*ui.Node = undefined;
    try focusFixture(&f, &trigger, &elsewhere, &controls);
    const card = f.cards[0];

    cx.setFocus(trigger);
    card.focusOpened(null);
    f.frame();
    try std.testing.expect(cx.focus_manager.getFocused() == controls[0]);
    // The entry (a launcher the card folds back into) is hidden when the card closes.
    trigger.setDisplay(.none);
    f.frame();
    card.focusClosed();
    // Well past the old 180-frame budget: still waiting, focus nowhere.
    for (0..400) |_| f.frame();
    try std.testing.expect(cx.focus_manager.getFocused() == null);
    trigger.setDisplay(.flex);
    f.frame();
    f.frame();
    try std.testing.expect(cx.focus_manager.getFocused() == trigger);

    // Again, but the user focuses something else while the target is hidden: that focus stays.
    card.focusOpened(null);
    f.frame();
    try std.testing.expect(cx.focus_manager.getFocused() == controls[0]);
    trigger.setDisplay(.none);
    f.frame();
    card.focusClosed();
    f.frame();
    cx.setFocus(elsewhere);
    f.frame();
    trigger.setDisplay(.flex);
    for (0..4) |_| f.frame();
    try std.testing.expect(cx.focus_manager.getFocused() == elsewhere);
}

test "card focus protocol: Escape during an IME composition in the card cancels the composition, the next Escape closes the card" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    const text = try f.scope.createText("draft", .{});
    const input = try ui.widgets.Textarea(.{ .value = text }).mountResult(f.scope, cx);
    try f.frames[0].appendChild(cx.allocator, input.wrapper);
    f.settle();
    const card = f.cards[0];
    card.focusOpened(null);
    f.frame();
    cx.setFocus(input.input);
    f.frame();
    cx.handleImePreedit("候选", "候选".len);
    try std.testing.expect(input.state.imeIsComposing());
    cx.handleKeyDown(.escape, .{});
    f.frame();
    // The composition owned that Escape: the card is still open.
    try std.testing.expectEqual(@as(usize, 0), f.owner.closed);
    cx.handleImePreedit("", 0);
    f.frame();
    try std.testing.expect(!input.state.imeIsComposing());
    cx.handleKeyDown(.escape, .{});
    f.frame();
    try std.testing.expectEqual(@as(usize, 1), f.owner.closed);
}

test "float layer card focus (OverlayHost card): focus enters, Tab stays, Escape only from inside, outside click keeps the card, focus returns" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const cx = f.cx;
    // A trigger outside the card, and two controls inside it.
    const trigger = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 10 }, .top = .{ .px = 10 } }, .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{});
    trigger.setFocusable(true);
    try cx.root.?.appendChild(cx.allocator, trigger);
    const elsewhere = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 10 }, .top = .{ .px = 600 } }, .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{});
    elsewhere.setFocusable(true);
    try cx.root.?.appendChild(cx.allocator, elsewhere);
    var controls: [2]*ui.Node = undefined;
    for (&controls) |*control| {
        control.* = try ui.box(cx, .{ .width = .{ .px = 60 }, .height = .{ .px = 20 } }, .{});
        control.*.setFocusable(true);
        try f.frames[0].appendChild(cx.allocator, control.*);
    }
    f.settle();
    const card = f.cards[0];
    cx.setFocus(trigger);
    card.focusOpened(null);
    // No owner request: the first frame the card shows puts focus in (nothing is counted).
    f.frame();
    // Focus entered the card's first control.
    try std.testing.expect(cx.focus_manager.getFocused() == controls[0]);
    // Tab stays inside the card.
    for (0..4) |_| {
        cx.handleKeyDown(.tab, .{});
        f.frame();
        const now = cx.focus_manager.getFocused().?;
        try std.testing.expect(now == controls[0] or now == controls[1]);
    }
    // Focus elsewhere (an outside click): the card stays open and Escape does not close it.
    cx.setFocus(elsewhere);
    f.frame();
    cx.handleKeyDown(.escape, .{});
    try std.testing.expectEqual(@as(usize, 0), f.owner.closed);
    // Back inside: Escape closes it; the owner's close gives focus back to the trigger.
    cx.setFocus(controls[1]);
    f.frame();
    cx.handleKeyDown(.escape, .{});
    try std.testing.expectEqual(@as(usize, 1), f.owner.closed);
    card.focusClosed();
    try std.testing.expect(cx.focus_manager.getFocused() == trigger);
    // Closed while focus is elsewhere: it stays there.
    cx.setFocus(trigger);
    card.focusOpened(null);
    f.frame();
    cx.setFocus(elsewhere);
    card.focusClosed();
    try std.testing.expect(cx.focus_manager.getFocused() == elsewhere);
}
