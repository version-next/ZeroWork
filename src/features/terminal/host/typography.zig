//! 终端排版与命令信息设置的应用（P2 自 src/main.zig 原样拆出）。

const ws = @import("../../workspace/view/workspace.zig");
const TerminalViewNode = @import("../view/terminal_view.zig").TerminalViewNode;
const process_state = @import("../../../app/process_state.zig");

pub fn terminalFamilyId(name: []const u8) u16 {
    const registry = process_state.app_font_registry orelse return 0;
    return @backingInt(registry.intern(name) catch return 0);
}
pub fn applyResolvedTerminalTypography(terminal: *TerminalViewNode, setting: @import("../../../config/config.zig").Ui) anyerror!void {
    const registry = process_state.app_font_registry orelse return error.FontUnavailable;
    var font = try @import("../../../config/appearance_font.zig").resolve(terminal.cx.allocator, registry, .{ .family = setting.font_family, .size = @floatFromInt(setting.font_size), .weight = setting.font_weight });
    defer font.deinit(terminal.cx.allocator);
    try terminal.setTypographyFamily(setting.font_size, setting.line_height, @backingInt(font.actual_weight), font.actual_family, font.family_id);
}
pub fn applyCommandInfoSettings(workspace: *ws.Workspace, global: bool) void {
    for (workspace.tabs.items) |tab| {
        const terminal = if (tab.terminal) |*value| value else continue;
        const snapshot = if (tab.host_snapshot) |saved| saved.value else null;
        terminal.setCommandInfoVisible(@import("../../../config/command_info.zig").enabled(global, tab.local, snapshot, &workspace.registry));
    }
}
