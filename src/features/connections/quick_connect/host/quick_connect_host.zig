//! 快速连接（⌘K）宿主 QuickConnectHost（P2 自 src/main.zig 原样拆出）。

const std = @import("std");
const ui = @import("ui");
const ws = @import("../../../workspace/view/workspace.zig");
const quick_connect_mod = @import("../model/quick_connect.zig");
const remote_editor = @import("../../../../plugins/remote/editor_factory.zig");
const AppNavHost = @import("../../../shell/host/nav_host.zig").AppNavHost;

/// Quick Connect (⌘K) host: live filter over the saved hosts registry with
/// keyboard/click connect, mirroring docs/SPEC/mockups/mockup-quickconnect.
/// The panel content is rebuilt from workspace.registry data on every query
/// change — no static mock rows.
pub const QuickConnectHost = struct {
    const QuickView = @import("../view/quick_connect_view.zig");
    allocator: std.mem.Allocator,
    cx: *ui.Cx,
    workspace: *ws.Workspace,
    view: *QuickView.View = undefined,
    nav: ?*AppNavHost = null,
    painted_revision: ?u64 = null,

    pub fn refreshAssets(self: *QuickConnectHost) !void {
        const revision = self.workspace.registry.revision;
        if (self.painted_revision == revision) return;
        var assets: std.ArrayList(QuickView.SavedAsset) = .empty;
        defer assets.deinit(self.allocator);
        for (self.workspace.registry.hosts) |host| {
            if (@backingInt(host.connection_id) == 0) continue;
            try assets.append(self.allocator, .{ .owner = host.owner(), .name = host.name, .host = host.host, .user = host.user, .port = host.port, .group = host.group, .hops = host.jump_chain.len, .protocol = host.protocol, .os = @import("../../../workspace/host/session_os_cache.zig").load(self.allocator, self.workspace.io, self.workspace.hosts_path, host) });
        }
        // Recency only reorders real saved identities; never fabricate fallback recent rows.
        var ordered: std.ArrayList(QuickView.SavedAsset) = .empty;
        defer ordered.deinit(self.allocator);
        for (0..self.workspace.recent_connections.len) |rank| {
            const owner = self.workspace.recent_connections.resolve(rank, &self.workspace.registry) orelse continue;
            for (assets.items) |entry| if (entry.owner.id == owner.id) {
                try ordered.append(self.allocator, entry);
                break;
            };
        }
        for (assets.items) |entry| {
            var present = false;
            for (ordered.items) |previous| if (previous.owner.id == entry.owner.id) {
                present = true;
                break;
            };
            if (!present) try ordered.append(self.allocator, entry);
        }
        try self.view.update(revision, ordered.items);
        self.painted_revision = revision;
    }
    pub fn show(self: *QuickConnectHost) !void {
        self.painted_revision = null;
        try self.refreshAssets();
        try self.view.show();
        if (self.nav) |nav| nav.quick.quick_connect_open = true;
    }
    pub fn close(self: *QuickConnectHost) void {
        self.view.hide();
    }
    pub fn closed(raw: *anyopaque) void {
        const self: *QuickConnectHost = @ptrCast(@alignCast(raw));
        if (self.nav) |nav| nav.quick.quick_connect_open = false;
    }
    pub fn saved(raw: *anyopaque, owner: @import("../../../../host/identity.zig").AssetOwner) !void {
        const self: *QuickConnectHost = @ptrCast(@alignCast(raw));
        _ = try self.workspace.registry.get(owner);
        const index = self.workspace.registry.indexOf(owner.id) orelse return error.AssetNotFound;
        try self.workspace.newSession(index);
    }
    pub fn local(raw: *anyopaque) !void {
        const self: *QuickConnectHost = @ptrCast(@alignCast(raw));
        try self.workspace.newLocalSession(null);
    }
    pub fn temporary(raw: *anyopaque, target: quick_connect_mod.ParsedTarget) !void {
        const self: *QuickConnectHost = @ptrCast(@alignCast(raw));
        const name = try std.fmt.allocPrint(self.allocator, "{s}:{d}", .{ target.host, target.port });
        defer self.allocator.free(name);
        try self.workspace.newTemporarySession(.{ .name = name, .host = target.host, .port = target.port, .user = target.user orelse return error.MissingUser });
    }
    pub fn newProfile(raw: *anyopaque, target: ?quick_connect_mod.ParsedTarget, query: []const u8) !void {
        const self: *QuickConnectHost = @ptrCast(@alignCast(raw));
        const nav = self.nav orelse return error.ApplicationUnavailable;
        const host = nav.wizard_host orelse return error.WizardUnavailable;
        if (host.wizard.isOpen()) {
            host.wizard.show();
            return error.WizardBusy;
        }
        host.selected_group = null;
        try host.refreshAssets();
        try remote_editor.loadDraft(host.wizard, if (target) |value| .{ .name = value.host, .host = value.host, .user = value.user orelse "", .port = value.port } else .{ .name = query });
        host.wizard.show();
    }
    pub fn cleanup(self: *QuickConnectHost) void {
        self.allocator.destroy(self);
    }
};
