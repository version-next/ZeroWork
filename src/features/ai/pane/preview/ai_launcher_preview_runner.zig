//! Isolated production `ai.launcher` state matrix (Pencil tfmv1 / cVXd5): one tab-body specimen per
//! state with the real launcher view resting 24 / 20 inside its bottom-right corner. Fabricated
//! states only; no application data, AI service or IO.
const std = @import("std");
const ui = @import("ui");
const App = @import("zenit_app").App;
const V = @import("../view/ai_launcher_view.zig");
const model = @import("../model/ai_launcher.zig");
const theme = @import("../../../../shared/ui/theme/app_theme.zig");

var selected_theme: []const u8 = "light";
const states = [_]model.State{ .idle, .approval, .working, .failed, .unknown, .success };
const titles = [_][]const u8{ "空闲", "待审批", "运行中", "失败", "结果待核实", "有新回答未读" };
const cell_ids = [_][]const u8{ "ai.launcher.preview.idle", "ai.launcher.preview.approval", "ai.launcher.preview.working", "ai.launcher.preview.failed", "ai.launcher.preview.unknown", "ai.launcher.preview.success" };

const Preview = struct {
    cx: *ui.Cx,
    cells: [states.len]*ui.Node = undefined,
    views: [states.len]*V.View = undefined,
    pinger: model.Pinger = .{},

    fn noop(_: *Preview) void {}
    fn noDrag(_: *Preview, _: V.ButtonDrag) void {}

    fn afterLayout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *Preview = @ptrCast(@alignCast(raw));
        for (self.cells, self.views, states) |cell, view, state| {
            const r = cell.globalRect();
            view.update(model.place(.bottom_right, .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h }, null), state, false, false);
        }
        // The approval pulse: twice on entry, then (preview only) every 4 s so a capture can see it.
        const now: i64 = @intFromFloat(self.cx.frame_time_ms);
        if (now - self.pinger.last >= 4000 or self.pinger.since == null) {
            self.views[1].ping(if (self.pinger.since == null) model.ping_entry_count else 1);
            self.pinger.since = now;
            self.pinger.last = now;
        }
        self.cx.scheduleRedrawAfterNs(500 * std.time.ns_per_ms);
        return .done;
    }
};

fn mount(cx: *ui.Cx, scope: *ui.Scope) !*ui.Node {
    theme.selectTokens(@import("../../../../config/theme_registry.zig").builtinTokens(selected_theme));
    cx.setTheme(theme.widgetTheme(theme.currentName()));
    const root = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .row, .padding = .{ .top = 16, .left = 16, .right = 16, .bottom = 16 }, .gap = 12, .background = theme.baseColors().app }, .{});
    root.meta.ownership.meta.test_id = "ai.launcher.preview";
    const state = try scope.createState(Preview, .{ .cx = cx });
    for (states, 0..) |_, i| {
        const column = try ui.box(cx, .{ .width = .{ .px = 168 }, .height = .fill(), .direction = .column, .gap = 8, .flex_shrink = 0 }, .{});
        const cell = try ui.box(cx, .{ .width = .fill(), .height = .{ .px = 120 }, .flex_shrink = 0, .background = theme.baseColors().surface_1.withAlpha(255), .border = .{ .radius = 8 } }, .{});
        cell.meta.ownership.meta.test_id = cell_ids[i];
        try column.appendChild(cx.allocator, cell);
        try column.appendChild(cx.allocator, try ui.text(cx, titles[i], .{ .font_size = 12, .font_weight = 600, .color = theme.current().fg_1 }));
        const view = try V.View.mount(cx, scope, cx.on(Preview, state, Preview.noop), cx.on(Preview, state, Preview.noDrag));
        try cell.appendChild(cx.allocator, view.ring);
        try cell.appendChild(cx.allocator, view.root);
        state.cells[i] = cell;
        state.views[i] = view;
        try root.appendChild(cx.allocator, column);
    }
    try cx.addAfterLayoutHook(state, Preview.afterLayout);
    return @import("../../../../shared/ui/window/fixture_window.zig").mount(cx, scope, root, .{ .background = theme.baseColors().app });
}

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--theme=")) selected_theme = try parseTheme(arg[8..]) else return error.InvalidOption;
    }
    try @import("../../../../platform/ui_fonts.zig").register();
    const app = try App.init(std.heap.c_allocator, .{ .io = init.io, .font = .{ .fallback_families = @import("../../../../platform/ui_fonts.zig").families }, .window = .{ .width = 1120, .height = 260, .title = "ZeroWork AI Launcher Preview", .chrome = @import("../../../../shared/ui/window/fixture_window.zig").chrome, .titlebar_height = @import("../../../../shared/ui/window/fixture_window.zig").title_height } });
    defer app.deinit();
    try app.runWith(mount);
}

fn parseTheme(id: []const u8) ![]const u8 {
    for (@import("../../../../config/theme_presets.zig").ids) |known| if (std.mem.eql(u8, id, known)) return known;
    return error.InvalidTheme;
}
