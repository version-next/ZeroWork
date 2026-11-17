//! Connection details card extras (Pencil lBTBA): live SOCKS forward phase
//! and group input broadcast for the card's own session. Read-only facts from
//! their owners; the switches run the existing actions (SOCKS panel, member
//! broadcast toggle). Nothing is shown for facts that do not exist.
const std = @import("std");
const Info = @import("../view/status_connection_view.zig");
const routes = @import("../../../host/socks_route_host.zig");
const Workspace = @import("../../workspace/view/workspace.zig").Workspace;
const ApplicationHost = @import("../host/application_host.zig").ApplicationHost;
const Socks = @import("../../connections/socks/host/socks_application_host.zig").Host;

pub const Provider = struct {
    workspace: *Workspace,
    application: *ApplicationHost,
    socks: *Socks,
    key: ?Info.OperationKey = null,

    pub fn provider(self: *Provider) Info.ExtrasProvider {
        return .{ .context = self, .read = read, .open_forward = openForward, .toggle_broadcast = toggleBroadcast };
    }
    fn read(raw: *anyopaque, key: Info.OperationKey) Info.Extras {
        const self: *Provider = @ptrCast(@alignCast(raw));
        self.key = key;
        if (key.owner != .session) return .{};
        const owner = key.owner.session;
        var result: Info.Extras = .{};
        var forward: Info.Extras.Forward = .{ .active = false };
        if (self.socks.backend.snapshot(owner)) |snapshot| {
            forward.active = snapshot.phase == .ready;
            var buffer: [64]u8 = undefined;
            const text = forwardText(&buffer, snapshot.phase, snapshot.bind127, snapshot.local_port, snapshot.failure != null);
            forward.detail = @TypeOf(forward.detail).init(text) catch .{};
        }
        result.forward = forward;
        if (self.application.legacyForHandle(owner)) |legacy| if (self.workspace.sessionBroadcast(legacy)) |fact| {
            result.broadcast = .{ .enabled = fact.enabled };
        };
        return result;
    }
    fn openForward(raw: *anyopaque) void {
        const self: *Provider = @ptrCast(@alignCast(raw));
        self.socks.showInfo();
    }
    fn toggleBroadcast(raw: *anyopaque) void {
        const self: *Provider = @ptrCast(@alignCast(raw));
        const key = self.key orelse return;
        if (key.owner != .session) return;
        const legacy = self.application.legacyForHandle(key.owner.session) orelse return;
        self.workspace.toggleSessionBroadcast(legacy);
    }
};

/// "SOCKS5 · 127.0.0.1:1080" while running; the phase otherwise.
pub fn forwardText(buffer: []u8, phase: routes.Phase, bind127: bool, port: u16, failed: bool) []const u8 {
    const address = if (bind127) "127.0.0.1" else "0.0.0.0";
    if (phase == .ready) return std.fmt.bufPrint(buffer, "SOCKS5 · {s}:{d}", .{ address, port }) catch "SOCKS5";
    return @import("../../../shared/base/connection_presenter.zig").presentForward(routes.forwardPhase(phase, failed)).label;
}

test "connection details forward text follows the live SOCKS phase" {
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("SOCKS5 · 127.0.0.1:1080", forwardText(&buffer, .ready, true, 1080, false));
    try std.testing.expectEqualStrings("启动中", forwardText(&buffer, .connecting, true, 1080, false));
    try std.testing.expectEqualStrings("启动失败", forwardText(&buffer, .closed, true, 0, true));
}
