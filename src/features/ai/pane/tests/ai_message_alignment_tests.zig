const std = @import("std");
const ui = @import("ui");
const S = @import("../view/ai_assistant_styles.zig");

test "AI user messages align to V3 content with overlay scrollbars" {
    for ([_]f32{ 520, 600, 1100 }) |width| {
        const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
        defer cx.deinit();
        cx.setViewport(width, 900);
        cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
        const conversation = try ui.box(cx, S.conversation(cx.tokens), .{});
        try cx.root.?.appendChild(cx.allocator, conversation);
        const content_width = S.contentWidth(width);
        for ([_][]const u8{ "简短问题", "This is a long user prompt which must wrap within the seventy five percent bubble limit and remain aligned to the right edge rather than falling back to the left because of its unwrapped intrinsic width. This also represents a restored conversation message." }) |prompt| {
            const row = try ui.box(cx, S.messageRow(true), .{});
            try conversation.appendChild(cx.allocator, row);
            // The native W.Card bubble (Kaf7E A3), capped through its text column at 85%.
            const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
            defer scope.dispose();
            const card = try @import("../view/ai_user_message_view.zig").mountBubble(cx, scope, try scope.createSignal(f32, content_width));
            const bubble = card.root;
            try row.appendChild(cx.allocator, bubble);
            try card.body.appendChild(cx.allocator, try ui.textStyled(cx, S.userText, prompt));
            cx.layout();
            const bounds = bubble.globalRect();
            const parent = row.globalRect();
            try std.testing.expectApproxEqAbs(content_width, parent.w, 0.1);
            try std.testing.expectApproxEqAbs(width - S.conversation_inset, bounds.x + bounds.w, 0.1);
            try std.testing.expect(bounds.w > 0 and bounds.w <= S.userBubbleMaxWidth(content_width) + 0.1);
            // The card holds every line of its text.
            try std.testing.expect(card.body.globalRect().y + card.body.globalRect().h <= bounds.y + bounds.h + 0.1);
            try std.testing.expectApproxEqAbs(parent.x + parent.w, bounds.x + bounds.w, 0.1);
        }
        const reply_row = try ui.box(cx, S.messageRow(false), .{});
        try conversation.appendChild(cx.allocator, reply_row);
        const reply = try ui.box(cx, .{ .max_width = 480 }, .{});
        try reply.appendChild(cx.allocator, try ui.text(cx, "Assistant reply", .{ .font_size = 12.5 }));
        try reply_row.appendChild(cx.allocator, reply);
        cx.layout();
        try std.testing.expectApproxEqAbs(reply_row.globalRect().x, reply.globalRect().x, 0.1);
    }
}

test "user actions follow the row's native hover and focus-within, not the pointer rectangle" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    cx.setViewport(400, 300);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill() }, .{});
    const a = cx.allocator;
    const row = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 20 }, .top = .{ .px = 20 } }, .width = .{ .px = 200 }, .direction = .column, .gap = 4 }, .{});
    const bubble = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 50 }, .background = ui.Color.rgb(200, 200, 200), .hit_behavior = .@"opaque" }, .{});
    const actions = try ui.box(cx, .{ .width = .{ .px = 200 }, .height = .{ .px = 22 }, .direction = .row }, .{});
    const action = try ui.box(cx, .{ .width = .{ .px = 22 }, .height = .{ .px = 22 }, .background = ui.Color.rgb(90, 90, 90), .hit_behavior = .@"opaque" }, .{});
    action.setFocusable(true);
    try actions.appendChild(a, action);
    try row.appendChild(a, bubble);
    try row.appendChild(a, actions);
    try cx.root.?.appendChild(a, row);
    const outside = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 300 }, .top = .{ .px = 200 } }, .width = .{ .px = 40 }, .height = .{ .px = 20 } }, .{});
    outside.setFocusable(true);
    try cx.root.?.appendChild(a, outside);
    // Something lying over the turn (a toast, a popover, the header a row scrolled under).
    const cover = try ui.box(cx, .{ .position = .absolute, .inset = .{ .left = .{ .px = 0 }, .top = .{ .px = 0 } }, .width = .{ .px = 400 }, .height = .{ .px = 150 }, .background = ui.Color.rgb(0, 0, 0), .hit_behavior = .@"opaque", .z_index = 5 }, .{});
    cover.setDisplay(.none);
    try cx.root.?.appendChild(a, cover);
    try @import("../view/ai_user_message_view.zig").Reveal.attach(cx, scope, row, actions, false);
    const frames = struct {
        fn run(c: *ui.Cx) void {
            for (0..3) |_| {
                c.frame_count += 1;
                c.frame_time_ms += 16;
                _ = c.render();
            }
        }
    }.run;
    frames(cx);
    try std.testing.expectEqual(@as(f32, 0), actions.getOpacity());
    // Over the bubble, then from the bubble onto an action: shown throughout (same hovered path).
    cx.handleMouseMove(60, 40);
    frames(cx);
    try std.testing.expectEqual(@as(f32, 1), actions.getOpacity());
    cx.handleMouseMove(30, 84);
    frames(cx);
    try std.testing.expectEqual(@as(f32, 1), actions.getOpacity());
    // Covered under a resting pointer: the pointer is still inside the row's rectangle, but the
    // row is not what it is over.
    cover.setDisplay(.flex);
    frames(cx);
    try std.testing.expectEqual(@as(f32, 0), actions.getOpacity());
    cover.setDisplay(.none);
    frames(cx);
    try std.testing.expectEqual(@as(f32, 1), actions.getOpacity());
    cx.handleMouseMove(350, 280);
    frames(cx);
    try std.testing.expectEqual(@as(f32, 0), actions.getOpacity());
    // Keyboard focus inside the turn shows them; focus leaving hides them.
    cx.setFocus(action);
    frames(cx);
    try std.testing.expectEqual(@as(f32, 1), actions.getOpacity());
    cx.setFocus(outside);
    frames(cx);
    try std.testing.expectEqual(@as(f32, 0), actions.getOpacity());
}

test "AI user bubble and sent attachments follow the message-width model" {
    const V = @import("../view/ai_user_message_view.zig");
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(800, 900);
    cx.root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column }, .{});
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    // The host's model: the message column's width.
    const width = try scope.createSignal(f32, S.contentWidth(640));
    const row = try ui.box(cx, S.messageRow(true), .{});
    try cx.root.?.appendChild(cx.allocator, row);
    const rail = try V.mountAttachments(cx, scope, width);
    try rail.appendChild(cx.allocator, try ui.box(cx, .{ .width = .{ .px = 900 }, .height = .{ .px = 40 }, .flex_shrink = 1, .min_width = 0 }, .{}));
    try row.appendChild(cx.allocator, rail);
    const card = try V.mountBubble(cx, scope, width);
    try card.body.appendChild(cx.allocator, try ui.textStyled(cx, S.userText, "https://example.com/averyveryverylongpathsegmentaveryveryverylongpathsegmentaveryveryverylongpathsegmentaveryveryverylongpathsegmentaveryveryverylongpathsegmentaveryveryverylongpathsegmentaveryveryverylongpathsegmentaveryveryverylongpathsegmentaveryveryverylongpathsegmentaveryveryverylongpathsegmentaveryveryverylongpathsegmentaveryveryverylongpathsegment"));
    try row.appendChild(cx.allocator, card.root);
    for ([_]f32{ 640, 320, 420, 800, 560 }) |panel| {
        // Floating 320–640 and docked 560 / 800: one write to the model, no tree lookup.
        width.set(S.contentWidth(panel));
        cx.layout();
        const cap = S.userBubbleMaxWidth(S.contentWidth(panel));
        try std.testing.expectEqual(S.userBubbleTextMaxWidth(S.contentWidth(panel)), card.body.style.getExt().max_width);
        try std.testing.expectEqual(cap, rail.style.getExt().max_width);
        // 85% of the column (at most 560); the long run breaks inside the bubble.
        try std.testing.expect(card.root.globalRect().w <= cap + 0.1);
        try std.testing.expect(rail.globalRect().w <= cap + 0.1);
        try std.testing.expect(card.body.globalRect().w <= S.userBubbleTextMaxWidth(S.contentWidth(panel)) + 0.1);
    }
    try std.testing.expectEqual(@as(f32, 560), S.userBubbleMaxWidth(S.contentWidth(800)));
}
