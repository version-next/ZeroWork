//! Window frame shared by the preview / fixture runners (one native window that
//! mounts a single component or page for acceptance and e2e).
//!
//! The runners use zenit's window chrome like the production windows: a custom
//! caption with the platform's traffic lights. A fixture has no title bar of its
//! own, so this frame provides one: zenit's `W.WindowHeader` (a drag region that
//! keeps clear of the native controls) above the fixture's content. The content
//! therefore starts below the title bar and never sits under the traffic lights;
//! nothing below the title bar drags the window.
//!
//!   const app = try App.init(alloc, .{ .window = .{ ..., .chrome = fixture_window.chrome,
//!       .titlebar_height = fixture_window.title_height } });
//!   fn mount(cx, scope) !*ui.Node {
//!       const root = ...;                       // the fixture's own root (fills its parent)
//!       return fixture_window.mount(cx, scope, root, .{ .background = ... });
//!   }
const std = @import("std");
const ui = @import("ui");
const W = ui.widgets;

/// `WindowConfig.chrome` of every fixture window.
pub const chrome: W.window_chrome.chrome.Config = .{ .custom = .{} };
/// `WindowConfig.titlebar_height`: the header's height (the traffic lights are centred in it).
pub const title_height: f32 = 40;

pub const ids = struct {
    pub const titlebar = "fixture.titlebar";
};

pub const Options = struct {
    /// Painted behind the header and the content (normally the content root's own
    /// background, so the title bar reads as part of the fixture).
    background: ?ui.Color = null,
    /// Fixture controls that belong in the title bar (a row of buttons). They are
    /// laid out after the traffic lights and stay clickable.
    bar: ?*ui.Node = null,
};

/// Wrap `content` (the fixture's root) in the fixture window frame and return the window root.
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, content: *ui.Node, options: Options) !*ui.Node {
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .background = options.background }, .{});
    errdefer cx.destroyDetached(root);
    const header = try W.WindowHeader(.{ .test_id = ids.titlebar, .style = .{ .width = .fill, .height = ui.arb.px(title_height), .flex_shrink = 0, .align_items = .center, .gap = 6, .padding = .{ .right = 8 } } }, .{options.bar}).mount(scope, cx);
    try root.appendChild(cx.allocator, header);
    // The content fills what is left under the header.
    const body = try ui.box(cx, .{ .width = .fill(), .height = .{ .grow = .{ .min = 0 } }, .min_height = 0, .direction = .column, .overflow = .hidden }, .{});
    try root.appendChild(cx.allocator, body);
    // A positioned slot gives the content the definite size a window root has: `fill` resolves
    // to the slot, and content taller than the window overflows inside it instead of
    // stretching the frame.
    const slot = try ui.box(cx, .{ .position = .absolute, .inset = .{ .top = .{ .px = 0 }, .left = .{ .px = 0 } }, .width = .fill(), .height = .fill(), .direction = .column, .overflow = .hidden }, .{});
    try body.appendChild(cx.allocator, slot);
    try slot.appendChild(cx.allocator, content);
    return root;
}

test "fixture window: the header drags the window, its controls and the content below do not" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(600, 400);
    // Custom chrome with three native controls at the default inset, as the runtime reports them.
    var state: W.window_chrome.chrome.State = .{ .requested_mode = .custom, .effective_mode = .custom, .controls_owner = .native, .width = 600, .height = 400, .native_controls_count = 3 };
    for (&state.native_controls, 0..) |*rect, i| rect.* = .{ .x = 7 + 20 * @as(f32, @floatFromInt(i)), .y = 13, .w = 14, .h = 14 };
    (try cx.windowChrome()).set(state);
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const button = try ui.box(cx, .{ .width = .{ .px = 60 }, .height = .{ .px = 24 } }, .{});
    button.behavior.interaction.focusable = true;
    const content_button = try ui.box(cx, .{ .width = .{ .px = 60 }, .height = .{ .px = 24 } }, .{});
    content_button.behavior.interaction.focusable = true;
    // Taller than the window: the frame must still end at the window's bottom edge.
    const tall = try ui.box(cx, .{ .width = .{ .px = 10 }, .height = .{ .px = 1000 }, .flex_shrink = 0 }, .{});
    const content = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .padding = ui.Padding.all(16) }, .{ content_button, tall });
    cx.root = try mount(cx, scope, content, .{ .bar = button });
    cx.layout();
    cx.publishWindowRegions();
    const Region = W.window_chrome.chrome.Region;
    const header = cx.window_header_node.?;
    const hr = header.globalRect();
    try std.testing.expectEqual(@as(f32, 0), hr.y);
    try std.testing.expectEqual(title_height, hr.h);
    try std.testing.expectEqual(@as(f32, 600), hr.w);
    // The fixture's title-bar control starts right of the last traffic light, and is a client point.
    const br = button.globalRect();
    try std.testing.expect(br.x >= 7 + 20 * 2 + 14);
    try std.testing.expectEqual(Region.client, cx.windowRegionAt(br.x + br.w / 2, br.y + br.h / 2));
    // Empty header space drags; so does the space around the native controls (AppKit keeps the buttons themselves).
    try std.testing.expectEqual(Region.drag, cx.windowRegionAt(400, 20));
    try std.testing.expectEqual(Region.drag, cx.windowRegionAt(3, 3));
    // The content fills the rest of the window below the header and never drags.
    try std.testing.expectEqual(@as(f32, 400), cx.root.?.globalRect().h);
    const slot = content.parent.?.globalRect();
    try std.testing.expectEqual(title_height, slot.y);
    try std.testing.expectEqual(@as(f32, 400) - title_height, slot.h);
    try std.testing.expectEqual(@as(f32, 600), slot.w);
    const cr = content.globalRect();
    try std.testing.expectEqual(title_height, cr.y);
    try std.testing.expect(cr.h >= slot.h); // overflows inside the slot (clipped), like content taller than a window
    try std.testing.expectEqual(Region.client, cx.windowRegionAt(300, 300));
    const cb = content_button.globalRect();
    try std.testing.expectEqual(Region.client, cx.windowRegionAt(cb.x + cb.w / 2, cb.y + cb.h / 2));
}
