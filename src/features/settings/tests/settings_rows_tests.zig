//! 3c 行组件（`view/components/rows.yix`）的组件测试：真 `ViewModel` + Ports 替身，
//! 按 test_id 断言结构、值与上行的 Intent（3e：夹具挂的是四个已改写分类的真实面板）。
const std = @import("std");
const ui = @import("ui");
const kit = @import("../../../shared/testing/ui_kit.zig");
const Controller = @import("../model/settings_controller.zig").Controller;
const RuntimeConfig = @import("../../../config/runtime_config.zig").RuntimeConfig;
const m = @import("../model/view_model.zig");
const values = @import("../model/settings_values.zig");
const fixture = @import("_rows_fixture.yix.zig");

const Rows = struct {
    env: kit.Headless,
    tmp: std.testing.TmpDir,
    runtime: RuntimeConfig,
    controller: Controller,
    vm: m.ViewModel,
    effects: std.ArrayList(std.meta.Tag(m.Effect)) = .empty,
    root: *ui.Node = undefined,

    fn init(self: *Rows) !void {
        const a = std.testing.allocator;
        self.* = .{ .env = try kit.headless(a, .{ .width = 760, .height = 3200, .root_style = .{ .width = .fill(), .height = .fill(), .direction = .column } }), .tmp = std.testing.tmpDir(.{}), .runtime = undefined, .controller = undefined, .vm = undefined };
        self.runtime = try RuntimeConfig.loadOrDefault(std.testing.io, self.tmp.dir, a, "config.toml");
        self.controller = try Controller.init(a, self.runtime.value);
        self.vm = m.ViewModel.init(&self.controller, .{ .context = self, .run = run, .allow = allow });
        try self.vm.attach(self.env.scope);
        self.root = try ui.view.render(self.env.scope, self.env.cx, fixture.RowsFixture(.{ .vm = &self.vm }));
        try self.env.mount(self.root);
        self.env.frames(2);
    }
    fn deinit(self: *Rows) void {
        self.env.deinit();
        self.effects.deinit(std.testing.allocator);
        self.controller.deinit();
        self.runtime.deinit();
        self.tmp.cleanup();
    }
    fn run(raw: *anyopaque, effect: m.Effect) void {
        const self: *Rows = @ptrCast(@alignCast(raw));
        self.effects.append(std.testing.allocator, effect) catch {};
    }
    fn allow(_: *anyopaque, _: m.Gate) bool {
        return true;
    }
    fn click(self: *Rows, id: []const u8) !void {
        const rect = (try kit.expectByTestId(self.root, id)).globalRect();
        self.env.cx.handleClick(rect.x + rect.w / 2, rect.y + rect.h / 2);
        self.env.frame();
    }
    fn read(self: *Rows, section: []const u8, key: []const u8) values.Value {
        return values.read(self.controller.model.value, section, key).?;
    }
};

fn textOf(node: *ui.Node, buffer: []u8) []const u8 {
    var used: usize = 0;
    collect(node, buffer, &used);
    return buffer[0..used];
}
fn collect(node: *ui.Node, buffer: []u8, used: *usize) void {
    if (node.style.display == .none) return;
    if (node.getText()) |value| {
        const n = @min(value.content.len, buffer.len - used.*);
        @memcpy(buffer[used.*..][0..n], value.content[0..n]);
        used.* += n;
    }
    for (node.children.items) |child| collect(child, buffer, used);
}

test "settings rows: Pane holds its rows under the pane id with the header text" {
    var r: Rows = undefined;
    try r.init();
    defer r.deinit();
    const pane = try kit.expectByTestId(r.root, "settings.data.history");
    var buffer: [512]u8 = undefined;
    const text = textOf(pane, &buffer);
    try std.testing.expect(std.mem.startsWith(u8, text, "会话记录缓冲、快照与保留策略"));
    for ([_][]const u8{ "settings.row.ring_mb", "settings.row.checkpoint_sec", "settings.row.retention_days", "settings.row.export_format" }) |id| {
        const row = try kit.expectByTestId(pane, id);
        try std.testing.expect(row.globalRect().h > 0);
    }
}

test "settings rows: ToggleRow switch reflects the draft and dispatches an edit" {
    var r: Rows = undefined;
    try r.init();
    defer r.deinit();
    const before = r.read("notify", "tab_dot").boolean;
    const field = try kit.expectByTestId(r.root, m.ids.field("tab_dot"));
    try std.testing.expectEqual(before, field.behavior.interaction.a11y.?.checked.?);
    try r.click(m.ids.field("tab_dot"));
    try std.testing.expectEqual(!before, r.read("notify", "tab_dot").boolean);
    try std.testing.expect(r.controller.model.dirty);
    try std.testing.expectEqual(!before, field.behavior.interaction.a11y.?.checked.?);
    // 易误用字段的说明直接写在标签下（`settings.help.content.<key>`）。
    var buffer: [256]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, textOf(try kit.expectByTestId(r.root, "settings.help.content.buffer_input"), &buffer), "恢复后回放缓存输入") != null);
}

test "settings rows: InputRow hands the raw text to the controller through the view-model" {
    var r: Rows = undefined;
    try r.init();
    defer r.deinit();
    const field = try kit.expectByTestId(r.root, m.ids.field("keepalive_sec"));
    r.env.cx.setFocus(field);
    r.env.cx.handleKeyDown(.a, .{ .super = true });
    r.env.cx.handleTextInput("45");
    r.env.frame();
    try std.testing.expectEqual(@as(u32, 45), r.read("ssh", "keepalive_sec").unsigned);
    try std.testing.expect(r.controller.model.dirty);
}

test "settings rows: SelectRow and ActionRow expose their controls and dispatch" {
    var r: Rows = undefined;
    try r.init();
    defer r.deinit();
    _ = try kit.expectByTestId(r.root, m.ids.field("export_format"));
    try r.click("settings.data.export_logs");
    var found = false;
    for (r.effects.items) |effect| found = found or effect == .export_logs;
    try std.testing.expect(found);
}
