//! The leading status slot of step-like rows, and the activity glyph of a tool.
const std = @import("std");
const ui = @import("ui");
const visual = @import("../model/ai_step_visual.zig");

pub fn activityIcon(tool_name: ?[]const u8) ui.SvgAsset {
    const name = tool_name orelse return ui.icons.get("brain").?;
    var decoded: [128]u8 = undefined;
    const logical = @import("../../../../ai/plugin_tools.zig").decodeName(&decoded, name) catch name;
    if (std.mem.eql(u8, logical, "host.run_builtin")) return ui.icons.terminal;
    if (std.mem.eql(u8, logical, "host.request_user_input")) return ui.icons.get("message-circle").?;
    if (std.mem.startsWith(u8, logical, "bmc_ikvm.")) return ui.icons.get("monitor").?;
    if (std.mem.indexOf(u8, logical, "search") != null) return ui.icons.search;
    if (std.mem.endsWith(u8, logical, "run_command")) return ui.icons.get("code").?;
    if (std.mem.indexOf(u8, logical, "terminal") != null or std.mem.indexOf(u8, logical, "execution") != null or std.mem.endsWith(u8, logical, "attach_shell")) return ui.icons.terminal;
    if (std.mem.endsWith(u8, logical, "fetch_url")) return ui.icons.get("globe").?;
    if (std.mem.indexOf(u8, logical, "group") != null) return ui.icons.get("layers").?;
    if (std.mem.indexOf(u8, logical, "session") != null or (std.mem.startsWith(u8, logical, "host.") and (std.mem.indexOf(u8, logical[5..], "host") != null))) return ui.icons.get("server").?;
    return ui.icons.get("file-text").?;
}

/// The leading status box of a step-like row (step, tool result, execution result) on a step-group
/// rail (Pencil Kaf7E A6): a 12 status glyph by phase (spinner while running, check, circle-x, ban…),
/// no chevron — the whole row opens its details. The row's disclosure state is the row's own
/// (`W.Pressable.expanded`), not written here.
pub const Indicator = struct {
    slot: *ui.Node,
    status: *@import("ai_step_status.zig").Status,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, row: *ui.Node, state: visual.Visual, status_id: []const u8) !*Indicator {
        const status = try @import("ai_step_status.zig").Status.mount(cx, scope, 12, status_id);
        try status.set(state);
        try row.appendChild(cx.allocator, status.root);
        return scope.createState(Indicator, .{ .slot = status.root, .status = status });
    }

    pub fn set(self: *Indicator, state: visual.Visual) !void {
        try self.status.set(state);
    }
};

/// A step-like row's header: a native `W.Pressable` (button semantics: focus, Space / Enter, a11y
/// role button with its name and `expanded`) with the row look (`ai_step_row.yss`, theme-following);
/// the caller appends the row's content to it (its children slot).
pub fn header(cx: *ui.Cx, scope: *ui.Scope, test_id: []const u8, a11y_label: anytype, expanded: *ui.Signal(bool), on_click: ui.Handler(void)) !*ui.Node {
    return ui.view.render(scope, cx, ui.view.attrs(.{ .test_id = test_id }, ui.widgets.Pressable(.{ .a11y_label = a11y_label, .expanded = expanded, .look = Row.step_row, .on_click = on_click })));
}
const Row = @import("_ai_step_row.yss.zig");
