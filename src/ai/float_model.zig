const std = @import("std");
const status = @import("status.zig");
const error_feedback = @import("error_feedback.zig");

const float_card = @import("../shared/base/float_card.zig");

/// The AI chat card's floating placement is the generic card float (shared/base/float_card.zig,
/// shared/ui/float_card/float_layer.zig); this file only declares the AI card type's parameters and
/// keeps the AI-specific presentation state (status, feedback, prompt).
pub const Rect = float_card.Rect;
pub const Size = float_card.Size;
pub const Edge = float_card.Edge;
pub const Corner = float_card.Corner;
pub const Origin = float_card.Origin;
pub const Placement = float_card.Placement;
pub const floatRegion = float_card.floatRegion;
/// #52: the width floor (also the resize minimum).
pub const minimum_width: f32 = 320;
pub const minimum_height: f32 = 354;
/// #52 default size: width = clamp(content.w × 0.42, 320, 420), height = clamp(content.h − 24, 280, 640).
pub const default_width_ratio: f32 = 0.42;
pub const default_width_max: f32 = 420;
pub const default_height_gap: f32 = 24;
pub const default_height_min: f32 = 280;
pub const default_height_max: f32 = 640;

/// #52 default size for the owner tab's content area.
pub fn defaultSize(content: Rect) Size {
    return .{
        .width = std.math.clamp(content.width * default_width_ratio, minimum_width, default_width_max),
        .height = std.math.clamp(content.height - default_height_gap, default_height_min, default_height_max),
    };
}

/// The `ai.chat` card type's floating declaration: the AI card never opens as its own tab; it floats
/// and (cards-float) docks into its tab's split (`dock_to_split` derived from the card type's
/// placements). The header's minimize folds the panel back into the tab's `ai.launcher` (the anchor),
/// the first open unfolds beside it.
pub const descriptor: float_card.Descriptor = .{
    .id = "ai.chat",
    .interactions = .initMany(&.{ .move, .resize, .maximize, .raise, .close, .fold_to_tab, .open_from_anchor, .remember_position, .minimize }),
    .min_size = .{ .width = minimum_width, .height = minimum_height },
    .default_size = defaultSize,
    .first_open = .beside_anchor,
};

pub fn defaultRect(origin: Origin, region: Rect) Rect {
    return float_card.defaultRect(descriptor, origin, region);
}

pub const Model = struct {
    visible: bool = false,
    expanded: bool = false,
    /// Per owner (tab) floating placement; swapped with the owner's presentation.
    placement: Placement = .{},
    /// cards-float: the owner tab's split leaf while the AI is docked into its card layout
    /// (`Workspace.dockCard`); null = floating. Swapped with the owner's presentation.
    docked_leaf: ?u64 = null,
    status: status.Status = .{},
    feedback: error_feedback.Feedback = .{},
    prompt: []const u8 = "",
    card_count: usize = 0,

    /// Where the owner tab shows its AI: open or not, where it floats, docked into its split. It
    /// belongs to the tab, not to the conversation the tab shows (LIFECYCLE.md §1): a tab that
    /// changes its conversation (restore, new, use a copy) keeps it, and the
    /// conversation that leaves the tab takes none of it along.
    pub const OwnerPresentation = struct {
        visible: bool = false,
        expanded: bool = false,
        placement: Placement = .{},
        docked_leaf: ?u64 = null,
    };

    pub fn ownerPresentation(self: Model) OwnerPresentation {
        return .{ .visible = self.visible, .expanded = self.expanded, .placement = self.placement, .docked_leaf = self.docked_leaf };
    }

    /// This model with `owner` as the tab's presentation; the conversation's own part (status,
    /// feedback, prompt, card count) stays.
    pub fn withOwnerPresentation(self: Model, owner: OwnerPresentation) Model {
        var next = self;
        next.visible = owner.visible;
        next.expanded = owner.expanded;
        next.placement = owner.placement;
        next.docked_leaf = owner.docked_leaf;
        return next;
    }

    pub fn toggle(self: *Model) void {
        self.visible = !self.visible;
    }
    pub fn setExpanded(self: *Model, expanded: bool) void {
        self.expanded = expanded;
    }
    pub fn setPrompt(self: *Model, prompt: []const u8) void {
        self.prompt = prompt;
    }

    pub fn setCardCount(self: *Model, count: usize) void {
        self.card_count = count;
    }
    pub fn rect(self: Model, origin: Origin, region: Rect) Rect {
        return self.placement.rect(descriptor, origin, region);
    }

    pub fn showError(self: *Model, info: @import("error.zig").Info) void {
        self.feedback.show(info);
        self.status.state = .failed;
        self.status.message = info.message;
        self.visible = true;
    }

    pub fn retryVisible(self: Model) bool {
        return self.feedback.retry_available and self.feedback.info != null;
    }

    pub fn beginRetry(self: *Model) bool {
        if (!self.retryVisible()) return false;
        self.status.state = .thinking;
        self.status.message = "Retrying";
        self.feedback.retry_available = false;
        return true;
    }

    pub fn markSuccess(self: *Model, message: []const u8) void {
        self.feedback.dismiss();
        self.status.state = .success;
        self.status.message = message;
    }

    pub fn dismissError(self: *Model) void {
        self.feedback.dismiss();
        self.status.state = .idle;
        self.status.message = "";
    }

    pub fn tick(self: *Model) void {
        status.nextPulse(&self.status);
    }
};

const test_region = floatRegion(1440, 900, 44, 240);
const test_content: Rect = .{ .x = 240, .y = 44, .width = 1200, .height = 820 };
fn testOrigin(corner: Corner) Origin {
    const x: f32 = if (corner.right()) test_content.x + test_content.width - 24 - 48 else test_content.x + 24;
    const y: f32 = if (corner.bottom()) test_content.y + test_content.height - 20 - 48 else test_content.y + 20;
    return .{ .corner = corner, .anchor = .{ .x = x, .y = y, .width = 48, .height = 48 }, .content = test_content };
}

test "AI default rectangle uses the #52 size and unfolds from the launcher corner" {
    const model: Model = .{ .expanded = true };
    for ([_]Corner{ .bottom_right, .bottom_left, .top_right, .top_left }) |corner| {
        const origin = testOrigin(corner);
        const r = model.rect(origin, test_region);
        try std.testing.expectEqual(@as(f32, 420), r.width); // 1200 × 0.42 = 504 → 420
        try std.testing.expectEqual(@as(f32, 640), r.height); // 820 − 24 = 796 → 640
        const l = origin.anchor.?;
        if (corner.right()) try std.testing.expectEqual(l.x + l.width, r.x + r.width) else try std.testing.expectEqual(l.x, r.x);
        if (corner.bottom()) try std.testing.expectEqual(l.y + l.height, r.y + r.height) else try std.testing.expectEqual(l.y, r.y);
        try std.testing.expect(r.x >= test_region.x and r.y >= test_region.y and r.x + r.width <= test_region.x + test_region.width and r.y + r.height <= test_region.y + test_region.height);
    }
    const small = defaultSize(.{ .x = 0, .y = 0, .width = 500, .height = 290 });
    try std.testing.expectEqual(@as(f32, 320), small.width);
    try std.testing.expectEqual(@as(f32, 280), small.height);
    const mid = defaultSize(.{ .x = 0, .y = 0, .width = 900, .height = 500 });
    try std.testing.expectEqual(@as(f32, 378), mid.width);
    try std.testing.expectEqual(@as(f32, 476), mid.height);
}

test "AI default rectangle stays inside the region in the smallest window" {
    const region = floatRegion(860, 480, 44, 240);
    const content: Rect = .{ .x = 240, .y = 44, .width = 620, .height = 400 };
    for ([_]Corner{ .bottom_right, .bottom_left, .top_right, .top_left }) |corner| {
        const x: f32 = if (corner.right()) content.x + content.width - 72 else content.x + 24;
        const y: f32 = if (corner.bottom()) content.y + content.height - 68 else content.y + 20;
        const r = defaultRect(.{ .corner = corner, .anchor = .{ .x = x, .y = y, .width = 48, .height = 48 }, .content = content }, region);
        try std.testing.expect(r.width >= minimum_width and r.height >= @min(minimum_height, region.height));
        try std.testing.expect(r.x >= region.x and r.y >= region.y and r.x + r.width <= region.x + region.width + 0.001 and r.y + r.height <= region.y + region.height + 0.001);
    }
}

test "AI card resize keeps the 320 minimum width" {
    const start: Rect = .{ .x = 600, .y = 180, .width = 700, .height = 500 };
    const minimum = float_card.resized(descriptor, start, .nw, 1000, 1000, test_region);
    try std.testing.expectEqual(@as(f32, 320), minimum.width);
    try std.testing.expectEqual(@as(f32, 354), minimum.height);
}

test "AI float model toggles and pulses status" {
    var model: Model = .{};
    model.toggle();
    try std.testing.expect(model.visible);
    model.status.state = .thinking;
    model.tick();
    try std.testing.expectEqual(@as(u8, 1), model.status.pulse);
    model.setExpanded(true);
    model.setCardCount(2);
    try std.testing.expect(model.expanded);
    try std.testing.expect(model.visible);
    try std.testing.expectEqual(@as(usize, 2), model.card_count);
    model.showError(.{ .kind = .network, .message = "offline" });
    try std.testing.expect(model.feedback.retry_available);
    try std.testing.expect(model.beginRetry());
    try std.testing.expectEqual(status.State.thinking, model.status.state);
    try std.testing.expect(!model.retryVisible());
    model.dismissError();
    try std.testing.expectEqual(status.State.idle, model.status.state);
    try std.testing.expect(!model.retryVisible());
    model.markSuccess("Done");
    model.setCardCount(0);
    try std.testing.expect(model.visible);
    model.toggle();
    try std.testing.expect(!model.visible);
}

test "retained response cards do not reopen a user collapsed AI panel" {
    var model: Model = .{};
    model.toggle();
    model.setCardCount(2);
    model.markSuccess("Done");
    model.toggle();
    model.setCardCount(2);
    try std.testing.expect(!model.visible);
    try std.testing.expectEqual(@as(usize, 2), model.card_count);
}

test "a tab that changes its conversation keeps its own presentation, the conversation keeps its own state" {
    // The tab's AI is open and docked into its split at leaf 7, floating placement moved.
    var shown: Model = .{ .visible = true, .expanded = true, .docked_leaf = 7, .placement = .{ .desired = .{ .x = 10, .y = 20, .width = 400, .height = 500 } } };
    shown.markSuccess("Done");
    // The conversation that comes in (restored from the list) was last shown floating somewhere else.
    var incoming: Model = .{ .placement = .{ .maximized = true } };
    incoming.showError(.{ .kind = .network, .message = "offline" });
    incoming.visible = false;
    const next = incoming.withOwnerPresentation(shown.ownerPresentation());
    try std.testing.expect(next.visible and next.expanded);
    try std.testing.expectEqual(@as(?u64, 7), next.docked_leaf);
    try std.testing.expect(!next.placement.maximized);
    try std.testing.expectEqual(@as(f32, 400), next.placement.desired.?.width);
    // The conversation's own status and feedback came with it.
    try std.testing.expectEqual(status.State.failed, next.status.state);
    try std.testing.expect(next.retryVisible());
    // The conversation that leaves the tab carries none of the tab's presentation.
    const left = shown.withOwnerPresentation(.{});
    try std.testing.expect(!left.visible and !left.expanded and left.docked_leaf == null and left.placement.desired == null);
    try std.testing.expectEqual(status.State.success, left.status.state);
}
