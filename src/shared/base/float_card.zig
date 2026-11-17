//! Floating placement of a content card (PLUGIN_ARCH_PLAN 2.5 / 2.5.7): the geometry model shared by
//! every card type that may float. "Floating" is one placement state of a card instance (next to
//! standalone tab and split); its interactions are a fixed, enumerable set that belongs to the card.
//! A card type only declares which interactions it supports and their parameters (`Descriptor`);
//! the behaviour is implemented once, here (geometry) and in `shared/ui/float_card/float_layer.zig`
//! (gestures, presentation, Z12 transitions).
//!
//! Coordinates are window content coordinates (origin at the content area's top-left), so a dropped
//! card stays put when the sidebar toggles or a split moves; region changes only re-clamp.
//! PL4a folds `Descriptor` into the card type registry (`placements.float`).
const std = @import("std");

pub const Rect = struct { x: f32, y: f32, width: f32, height: f32 };
pub const Size = struct { width: f32, height: f32 };

/// The enumerable interactions of a floating card.
pub const Interaction = enum {
    /// Drag by the grip anywhere inside the floating region.
    move,
    /// Eight-way resize between the declared minimum and maximum size.
    resize,
    /// Maximize to the whole floating region / restore.
    maximize,
    /// Pointer down brings the card above the other floating cards.
    raise,
    /// The card can be closed from the layer (the owner decides what closing means).
    close,
    /// Fold into the owner tab on the strip when another tab becomes current; unfold back (Z12).
    fold_to_tab,
    /// The first open unfolds from an anchor (e.g. the AI launcher) and closing folds back into it.
    open_from_anchor,
    /// Remember the dropped rectangle per card instance; without it a reopen starts from the default.
    remember_position,
    /// The header offers "open as tab": the owner moves the card (same content) into its own tab.
    open_as_tab,
    /// The header offers "minimize": the owner hides the card and keeps its content (e.g. the AI
    /// panel folds back into its launcher).
    minimize,
    /// The header offers "dock to split" (float-split): the owner moves the card (same content node)
    /// into its owner tab's tab body split as a pane, and back. Never declared by a card itself: the
    /// card type registry derives it from `placements.split` (`card_types.floatDescriptor`).
    dock_to_split,
    /// Swipe down to collapse (Pencil AveHg, `float_swipe.zig`): a downward fling (or a drag a third
    /// past the view bottom) on the grip of a bottom-docked card collapses it the way its
    /// `minimize` does. Never declared by a card itself: derived from `move` + `minimize`
    /// (`float_swipe.deriveInto`, applied by the floating layer and `card_types.floatDescriptor`).
    swipe_collapse,
};
pub const Interactions = std.EnumSet(Interaction);

/// The window actions of a floating card's header (`shared/ui/float_card/float_chrome`), in this
/// fixed order with one icon set for every card: 作为标签页打开 · 放入分屏 · 收起 · 放大 / 还原 · 关闭.
pub const HeaderAction = enum {
    open_as_tab,
    dock_to_split,
    minimize,
    maximize,
    close,

    pub fn interaction(self: HeaderAction) Interaction {
        return switch (self) {
            .open_as_tab => .open_as_tab,
            .dock_to_split => .dock_to_split,
            .minimize => .minimize,
            .maximize => .maximize,
            .close => .close,
        };
    }
    /// Every header action is shown on every floating card (float-split for the placement actions,
    /// cards-float for the window actions): a card type that does not support one shows the button
    /// disabled (native Button disabled, Tooltip with the reason, e.g. "终端不支持收起") instead of
    /// hiding it, so the header looks the same on every card.
    pub fn alwaysShown(self: HeaderAction) bool {
        _ = self;
        return true;
    }
};
pub const header_action_count = std.enums.values(HeaderAction).len;

/// The header actions of `descriptor`, in header order: all of them (unsupported ones disabled).
pub const HeaderActions = struct {
    buffer: [header_action_count]HeaderAction = undefined,
    len: usize = 0,
    pub fn slice(self: *const HeaderActions) []const HeaderAction {
        return self.buffer[0..self.len];
    }
};
pub fn headerActions(descriptor: Descriptor) HeaderActions {
    var result: HeaderActions = .{};
    for (std.enums.values(HeaderAction)) |action| if (action.alwaysShown() or descriptor.supports(action.interaction())) {
        result.buffer[result.len] = action;
        result.len += 1;
    };
    return result;
}
/// The Tooltip of a placement action the card type does not allow ("会话记录不支持分屏"); `title` is
/// what the card shows. One wording for every card (the registry and the chrome both use it).
pub fn refusalText(buffer: []u8, action: HeaderAction, title: []const u8) []const u8 {
    const tail = switch (action) {
        .dock_to_split => "不支持分屏",
        .open_as_tab => "不支持作为标签页打开",
        .minimize => "不支持收起",
        .maximize => "不支持放大",
        .close => "不支持从这里关闭",
    };
    return std.fmt.bufPrint(buffer, "{s}{s}", .{ title, tail }) catch tail;
}

/// Whether a shown header action can be pressed for the card type alone (before any owner state):
/// it needs the (declared or derived) interaction.
pub fn headerActionEnabled(descriptor: Descriptor, action: HeaderAction) bool {
    return descriptor.supports(action.interaction());
}

/// Where a never-moved card is placed on first open.
pub const FirstOpen = enum {
    /// Centered in the floating region.
    center,
    /// Beside the open anchor: the card's corner shares the anchor's outer corner (`Origin.corner`).
    beside_anchor,
};

/// What a card type declares about its floating placement.
pub const Descriptor = struct {
    /// Card type id (e.g. `ai.chat`, `history`).
    id: []const u8,
    interactions: Interactions,
    min_size: Size,
    /// null: only the floating region limits the size.
    max_size: ?Size = null,
    /// Default size for the owner tab's content area.
    default_size: *const fn (content: Rect) Size,
    first_open: FirstOpen = .center,

    pub fn supports(self: Descriptor, interaction: Interaction) bool {
        return self.interactions.contains(interaction);
    }
};

pub const Edge = enum {
    n,
    s,
    w,
    e,
    nw,
    ne,
    sw,
    se,

    pub fn west(self: Edge) bool {
        return self == .w or self == .nw or self == .sw;
    }
    pub fn east(self: Edge) bool {
        return self == .e or self == .ne or self == .se;
    }
    pub fn north(self: Edge) bool {
        return self == .n or self == .nw or self == .ne;
    }
    pub fn south(self: Edge) bool {
        return self == .s or self == .sw or self == .se;
    }
};

pub const Corner = enum {
    bottom_right,
    bottom_left,
    top_right,
    top_left,

    pub fn right(self: Corner) bool {
        return self == .bottom_right or self == .top_right;
    }
    pub fn bottom(self: Corner) bool {
        return self == .bottom_right or self == .bottom_left;
    }
};

/// The input of a first open: the owner tab's content area and, for `beside_anchor`, the anchor.
pub const Origin = struct { content: Rect, anchor: ?Rect = null, corner: Corner = .bottom_right };

/// Inset of the floating region from the window, the title bar and the sidebar.
pub const region_inset: f32 = 8;

/// Where floating cards can be dragged and parked (#62, user ruling 2026-11-13): everything below
/// the title bar (the tab header) — the expanded sidebar and the status bar included — inset 8.
pub fn dragRegion(viewport_width: f32, viewport_height: f32, title_height: f32) Rect {
    const top = title_height + region_inset;
    return .{ .x = region_inset, .y = top, .width = @max(0, viewport_width - 2 * region_inset), .height = @max(0, viewport_height - region_inset - top) };
}

/// The work area: window content minus the whole title bar and the expanded sidebar, inset 8 on
/// every side (the status bar is not excluded, Q20). Maximize fills it and default (first-open)
/// placements are computed in it, so tabs and title bar tools stay reachable.
pub fn floatRegion(viewport_width: f32, viewport_height: f32, title_height: f32, sidebar_right: f32) Rect {
    const left = @max(0, sidebar_right) + region_inset;
    const top = title_height + region_inset;
    return .{ .x = left, .y = top, .width = @max(0, viewport_width - region_inset - left), .height = @max(0, viewport_height - region_inset - top) };
}

/// Keep the whole card inside `region`: sizes first (never below the declared minimum unless the
/// region is smaller, never above the maximum), then the position.
pub fn clampRect(descriptor: Descriptor, value: Rect, region: Rect) Rect {
    const max_w = if (descriptor.max_size) |m| @min(m.width, region.width) else region.width;
    const max_h = if (descriptor.max_size) |m| @min(m.height, region.height) else region.height;
    const width = std.math.clamp(value.width, @min(descriptor.min_size.width, max_w), max_w);
    const height = std.math.clamp(value.height, @min(descriptor.min_size.height, max_h), max_h);
    return .{ .x = std.math.clamp(value.x, region.x, region.x + region.width - width), .y = std.math.clamp(value.y, region.y, region.y + region.height - height), .width = width, .height = height };
}

/// Resize from `edge` by (dx, dy) with the opposite edges fixed.
pub fn resized(descriptor: Descriptor, start: Rect, edge: Edge, dx: f32, dy: f32, region: Rect) Rect {
    const base = clampRect(descriptor, start, region);
    var left = base.x;
    var right = base.x + base.width;
    var top = base.y;
    var bottom = base.y + base.height;
    const min_w = @min(descriptor.min_size.width, region.width);
    const min_h = @min(descriptor.min_size.height, region.height);
    const max_w = if (descriptor.max_size) |m| m.width else std.math.inf(f32);
    const max_h = if (descriptor.max_size) |m| m.height else std.math.inf(f32);
    if (edge.west()) left = std.math.clamp(left + dx, @max(region.x, right - max_w), right - min_w);
    if (edge.east()) right = std.math.clamp(right + dx, left + min_w, @min(region.x + region.width, left + max_w));
    if (edge.north()) top = std.math.clamp(top + dy, @max(region.y, bottom - max_h), bottom - min_h);
    if (edge.south()) bottom = std.math.clamp(bottom + dy, top + min_h, @min(region.y + region.height, top + max_h));
    return .{ .x = left, .y = top, .width = right - left, .height = bottom - top };
}

/// A card of `size` beside the anchor: its corner shares the anchor's outer corner.
pub fn besideAnchor(origin: Origin, size: Size) Rect {
    const a = origin.anchor orelse return .{ .x = origin.content.x + (origin.content.width - size.width) / 2, .y = origin.content.y + (origin.content.height - size.height) / 2, .width = size.width, .height = size.height };
    return .{
        .x = if (origin.corner.right()) a.x + a.width - size.width else a.x,
        .y = if (origin.corner.bottom()) a.y + a.height - size.height else a.y,
        .width = size.width,
        .height = size.height,
    };
}

pub fn defaultRect(descriptor: Descriptor, origin: Origin, region: Rect) Rect {
    const size = descriptor.default_size(origin.content);
    const placed: Rect = switch (descriptor.first_open) {
        .beside_anchor => besideAnchor(origin, size),
        .center => .{ .x = region.x + (region.width - size.width) / 2, .y = region.y + (region.height - size.height) / 2, .width = size.width, .height = size.height },
    };
    return clampRect(descriptor, placed, region);
}

pub const Geometry = struct { desired: ?Rect, clamped: ?Rect, restore: ?Rect };

/// The floating placement of one card instance.
pub const Placement = struct {
    maximized: bool = false,
    /// The rectangle the user last dropped; null = never moved (or not remembered).
    desired: ?Rect = null,
    /// `desired` (or the default) clamped into the current region.
    clamped: ?Rect = null,
    /// `desired` while maximized (null when the card had never been moved).
    restore: ?Rect = null,

    /// Maximized: the whole region. Moved: the dropped rectangle clamped into the region. Otherwise
    /// the card type's default for its owner tab.
    pub fn rect(self: Placement, descriptor: Descriptor, origin: Origin, region: Rect) Rect {
        if (self.maximized) return region;
        if (self.desired) |value| return clampRect(descriptor, value, region);
        return defaultRect(descriptor, origin, region);
    }
    /// Region changes only re-clamp; they never erase the requested rectangle.
    pub fn updateBounds(self: *Placement, descriptor: Descriptor, origin: Origin, region: Rect) void {
        self.clamped = self.rect(descriptor, origin, region);
    }
    pub fn geometry(self: Placement) Geometry {
        return .{ .desired = self.desired, .clamped = self.clamped, .restore = self.restore };
    }
    pub fn restoreGeometry(self: *Placement, value: Geometry) void {
        self.desired = value.desired;
        self.clamped = value.clamped;
        self.restore = value.restore;
    }
    pub fn setRectangle(self: *Placement, descriptor: Descriptor, value: Rect, origin: Origin, region: Rect) void {
        self.desired = clampRect(descriptor, value, region);
        self.updateBounds(descriptor, origin, region);
    }
    /// Back to the first-open position, keeping the current size.
    pub fn resetPosition(self: *Placement, descriptor: Descriptor, origin: Origin, region: Rect) void {
        if (self.maximized) return;
        const current = self.rect(descriptor, origin, region);
        const size: Size = .{ .width = current.width, .height = current.height };
        const placed: Rect = switch (descriptor.first_open) {
            .beside_anchor => besideAnchor(origin, size),
            .center => .{ .x = region.x + (region.width - size.width) / 2, .y = region.y + (region.height - size.height) / 2, .width = size.width, .height = size.height },
        };
        self.setRectangle(descriptor, placed, origin, region);
    }
    pub fn toggleMaximized(self: *Placement, descriptor: Descriptor, origin: Origin, region: Rect) void {
        if (!descriptor.supports(.maximize) and !self.maximized) return;
        if (self.maximized) {
            self.desired = self.restore;
            self.restore = null;
        } else self.restore = self.desired;
        self.maximized = !self.maximized;
        self.updateBounds(descriptor, origin, region);
    }
    /// Closing: a card type without `remember_position` reopens at its default.
    pub fn closed(self: *Placement, descriptor: Descriptor) void {
        if (descriptor.supports(.remember_position)) return;
        self.* = .{};
    }
};

// ── Tests: every interaction's geometry, with a fixture card type ─────────────────────────────

fn fixtureSize(content: Rect) Size {
    return .{ .width = @min(400, content.width / 2), .height = 300 };
}
pub const fixture: Descriptor = .{
    .id = "fixture.card",
    .interactions = Interactions.full,
    .min_size = .{ .width = 200, .height = 120 },
    .max_size = .{ .width = 800, .height = 600 },
    .default_size = fixtureSize,
    .first_open = .center,
};
const test_region = floatRegion(1440, 900, 44, 240);
const test_content: Rect = .{ .x = 240, .y = 44, .width = 1200, .height = 820 };

test "drag region: everything below the title bar, sidebar included; the work area also excludes the sidebar" {
    const drag_region = dragRegion(1440, 900, 44);
    try std.testing.expectEqual(Rect{ .x = 8, .y = 52, .width = 1424, .height = 840 }, drag_region);
    const work = floatRegion(1440, 900, 44, 264);
    try std.testing.expect(work.x > drag_region.x and work.y == drag_region.y);
}

test "float card region excludes only the title bar and the expanded sidebar, covers the status bar" {
    try std.testing.expectEqualDeep(Rect{ .x = 248, .y = 52, .width = 1184, .height = 840 }, test_region);
    const collapsed = floatRegion(1440, 900, 44, 0);
    try std.testing.expectEqual(@as(f32, 8), collapsed.x);
    try std.testing.expectEqual(@as(f32, 892), collapsed.y + collapsed.height);
}

test "float card first open: centered or beside its anchor in each corner" {
    const placement: Placement = .{};
    const centered = placement.rect(fixture, .{ .content = test_content }, test_region);
    try std.testing.expectEqualDeep(Rect{ .x = 248 + (1184 - 400) / 2, .y = 52 + (840 - 300) / 2, .width = 400, .height = 300 }, centered);
    var beside = fixture;
    beside.first_open = .beside_anchor;
    for ([_]Corner{ .bottom_right, .bottom_left, .top_right, .top_left }) |corner| {
        const anchor: Rect = .{ .x = if (corner.right()) 1368 else 264, .y = if (corner.bottom()) 796 else 64, .width = 48, .height = 48 };
        const r = placement.rect(beside, .{ .content = test_content, .anchor = anchor, .corner = corner }, test_region);
        if (corner.right()) try std.testing.expectEqual(anchor.x + anchor.width, r.x + r.width) else try std.testing.expectEqual(anchor.x, r.x);
        if (corner.bottom()) try std.testing.expectEqual(anchor.y + anchor.height, r.y + r.height) else try std.testing.expectEqual(anchor.y, r.y);
    }
}

test "float card move: drops anywhere in the region, never into the title bar or sidebar; remembered across region changes" {
    var placement: Placement = .{};
    const origin: Origin = .{ .content = test_content };
    placement.setRectangle(fixture, .{ .x = 0, .y = 0, .width = 400, .height = 300 }, origin, test_region);
    try std.testing.expectEqual(@as(f32, 248), placement.desired.?.x);
    try std.testing.expectEqual(@as(f32, 52), placement.desired.?.y);
    placement.setRectangle(fixture, .{ .x = 2000, .y = 2000, .width = 400, .height = 300 }, origin, test_region);
    try std.testing.expectEqual(@as(f32, 892), placement.desired.?.y + placement.desired.?.height);
    try std.testing.expectEqual(@as(f32, 1432), placement.desired.?.x + placement.desired.?.width);
    const dropped: Rect = .{ .x = 700, .y = 400, .width = 400, .height = 300 };
    placement.setRectangle(fixture, dropped, origin, test_region);
    const small = floatRegion(860, 480, 44, 240);
    placement.updateBounds(fixture, origin, small);
    try std.testing.expectEqualDeep(dropped, placement.desired.?);
    const c = placement.clamped.?;
    try std.testing.expect(c.x >= small.x and c.y >= small.y and c.x + c.width <= small.x + small.width and c.y + c.height <= small.y + small.height);
    placement.updateBounds(fixture, origin, test_region);
    try std.testing.expectEqualDeep(dropped, placement.clamped.?);
}

test "float card resize: declared minimum and maximum with the opposite edges fixed" {
    const start: Rect = .{ .x = 600, .y = 200, .width = 500, .height = 400 };
    const small = resized(fixture, start, .nw, 1000, 1000, test_region);
    try std.testing.expectEqual(@as(f32, 200), small.width);
    try std.testing.expectEqual(@as(f32, 120), small.height);
    try std.testing.expectEqual(start.x + start.width, small.x + small.width);
    try std.testing.expectEqual(start.y + start.height, small.y + small.height);
    const large = resized(fixture, start, .se, 2000, 2000, test_region);
    try std.testing.expectEqual(@as(f32, 800), large.width);
    try std.testing.expectEqual(@as(f32, 600), large.height);
    try std.testing.expectEqual(start.x, large.x);
    try std.testing.expectEqual(start.y, large.y);
}

test "float card maximize fills the region (not limited by max size) and restores, also when never moved" {
    var placement: Placement = .{};
    const origin: Origin = .{ .content = test_content };
    const original = placement.rect(fixture, origin, test_region);
    placement.toggleMaximized(fixture, origin, test_region);
    try std.testing.expectEqualDeep(test_region, placement.rect(fixture, origin, test_region));
    placement.toggleMaximized(fixture, origin, test_region);
    try std.testing.expect(placement.desired == null);
    try std.testing.expectEqualDeep(original, placement.rect(fixture, origin, test_region));
    var fixed = fixture;
    fixed.interactions.remove(.maximize);
    placement.toggleMaximized(fixed, origin, test_region);
    try std.testing.expect(!placement.maximized);
}

test "float card remember_position: kept on close when declared, reset otherwise; reset keeps the size" {
    var placement: Placement = .{};
    const origin: Origin = .{ .content = test_content };
    placement.setRectangle(fixture, .{ .x = 300, .y = 100, .width = 500, .height = 350 }, origin, test_region);
    placement.closed(fixture);
    try std.testing.expect(placement.desired != null);
    placement.resetPosition(fixture, origin, test_region);
    try std.testing.expectEqual(@as(f32, 500), placement.desired.?.width);
    try std.testing.expectEqual(test_region.x + (test_region.width - 500) / 2, placement.desired.?.x);
    var forgetful = fixture;
    forgetful.interactions.remove(.remember_position);
    placement.closed(forgetful);
    try std.testing.expect(placement.desired == null);
}

test "header actions: all five always shown in one fixed order, enabled only when declared or derived" {
    const all = [_]HeaderAction{ .open_as_tab, .dock_to_split, .minimize, .maximize, .close };
    var descriptor = fixture;
    descriptor.interactions = .initMany(&.{ .close, .move, .open_as_tab, .maximize });
    try std.testing.expectEqualSlices(HeaderAction, &all, headerActions(descriptor).slice());
    try std.testing.expect(headerActionEnabled(descriptor, .open_as_tab) and !headerActionEnabled(descriptor, .dock_to_split));
    try std.testing.expect(!headerActionEnabled(descriptor, .minimize) and headerActionEnabled(descriptor, .maximize) and headerActionEnabled(descriptor, .close));
    descriptor.interactions = .initMany(&.{ .minimize, .close, .maximize, .dock_to_split });
    try std.testing.expectEqualSlices(HeaderAction, &all, headerActions(descriptor).slice());
    try std.testing.expect(!headerActionEnabled(descriptor, .open_as_tab) and headerActionEnabled(descriptor, .dock_to_split));
    descriptor.interactions = .initMany(&.{.move});
    try std.testing.expectEqualSlices(HeaderAction, &all, headerActions(descriptor).slice());
    for (all) |action| try std.testing.expect(!headerActionEnabled(descriptor, action));
    var buffer: [96]u8 = undefined;
    try std.testing.expectEqualStrings("终端不支持收起", refusalText(&buffer, .minimize, "终端"));
}
