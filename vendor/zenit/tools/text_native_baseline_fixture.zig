//! Fixed baseline fixture, shared with the native and HTML sample contract.
const std = @import("std");
const ui = @import("ui");
const samples = @import("text_baseline_samples");
pub var phase_px: f32 = 0;
var page: usize = 0;
var fixture_cx: *ui.Cx = undefined;
var labels: [8]*ui.Node = undefined;
fn update() void {
    const size = samples.sizes[page / 4];
    const weight = samples.weights[page % 4];
    for (&labels, 0..) |node, row| {
        node.setText(.{
            .content = samples.samples[row % 4],
            .font_size = size,
            .font_weight = weight,
            .line_height = 64 / size,
            .baseline_ratio = 44.0 / 64.0,
            .color = if (row >= 4) ui.Color.rgb(240, 240, 240) else ui.Color.rgb(24, 24, 24),
        });
        const line = fixture_cx.text.visualLine(.{ .text = samples.samples[row % 4], .font_family = "system", .font_size = size, .font_weight = weight }) catch @panic("baseline metrics failed");
        std.debug.print("TEXT_LAYOUT {{\"page\":{d},\"row\":{d},\"advance\":{d:.6},\"ascent\":{d:.6},\"descent\":{d:.6},\"leading\":{d:.6},\"fixture_baseline\":44,\"line_height\":64}}\n", .{ page, row, line.width, line.ascent, line.descent, line.leading });
    }
}
const Actions = struct {
    fn next(_: *@This()) void {
        page = (page + 1) % 24;
        update();
    }
};
pub fn mount(cx: *ui.Cx, scope: *ui.Scope) !*ui.Node {
    fixture_cx = cx;
    page = 0;
    const root = try ui.box(cx, .{ .width = .{ .px = 600 }, .height = .{ .px = 560 }, .direction = .column, .gap = 0, .background = ui.Color.WHITE }, .{});
    root.meta.ownership.meta.test_id = "text-baseline";
    for (&labels, 0..) |*slot, row| {
        const box = try ui.box(cx, .{ .width = .{ .px = 600 }, .height = .{ .px = 64 }, .flex_shrink = 0, .padding = .{ .left = 16 + phase_px / cx.window_scale }, .background = if (row >= 4) ui.Color.rgb(24, 24, 24) else ui.Color.WHITE }, .{});
        slot.* = try ui.text(cx, samples.samples[row % 4], .{});
        try box.appendChild(cx.allocator, slot.*);
        try root.appendChild(cx.allocator, box);
    }
    update();
    const actions = try scope.createState(Actions, .{});
    const next = try ui.widgets.Button(.{ .label = "Next sample", .on_click = cx.on(Actions, actions, Actions.next) }).mount(scope, cx);
    next.meta.ownership.meta.test_id = "text-baseline.next";
    try root.appendChild(cx.allocator, next);
    return root;
}
