//! Window-local workspace state. No widgets, transports or borrowed view pointers.
const std = @import("std");
const identity = @import("../../../host/identity.zig");
/// The tab set, each tab's owner and container, and the current tab are part of the AI's
/// environment (LIFECYCLE.md §5.2–5.3): every change of them publishes, unchanged writes do not.
const environment = @import("../../../host/environment.zig");

/// The workspace view keeps part of the AI's environment beside this model: the current tab index
/// and group view, each tab's content owner / closing / renderer / runtime / floating state, the
/// tab bodies and the cards docked in them. The view reports each actual change of them here (the
/// view layer reaches the process-level revision through its model, not directly).
pub fn publishEnvironment() void {
    environment.publish();
}

pub const TabId = identity.TabId;
pub const Owner = identity.ContentOwner;
pub const Tab = struct {
    id: TabId,
    owner: Owner,
    title: [64]u8 = @splat(0),
    title_len: u8 = 0,
    revision: u64 = 1,
    /// Presentation clock survives strip rebuilds; no repeated animation for old unread output.
    attention_started_ms: ?f64 = null,
    /// A session created inside a group retains its owner but has one visual entry.
    container: ?TabId = null,
    details: []const u8 = "",
    /// The title is a user rename (稿 3: 自定义名称 > 主机名 > 本地目录).
    custom: bool = false,
    /// Derived display name (`tab_naming.resolve`); empty means the title is shown as is.
    display: [96]u8 = @splat(0),
    display_len: u8 = 0,

    /// What every surface shows: the derived display name, else the title.
    pub fn name(self: *const Tab) []const u8 {
        if (self.display_len != 0) return self.display[0..self.display_len];
        return self.title[0..self.title_len];
    }
    /// The stored title (user rename, host name or content title), without derivation.
    pub fn baseName(self: *const Tab) []const u8 {
        return self.title[0..self.title_len];
    }
    fn setName(self: *Tab, raw: []const u8) !void {
        const value = std.mem.trim(u8, raw, " \t\r\n");
        if (value.len == 0) return error.EmptyName;
        if (value.len > self.title.len) return error.NameTooLong;
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidName;
        for (value) |byte| if (byte < 0x20 or byte == 0x7f) return error.InvalidName;
        @memcpy(self.title[0..value.len], value);
        self.title_len = @intCast(value.len);
    }
};

pub const Rename = struct { tab: TabId, owner: Owner, revision: u64 };
pub const CloseTarget = struct { tab: TabId, owner: Owner };
pub const Model = struct {
    allocator: std.mem.Allocator,
    window: identity.WindowId,
    workspace: identity.WorkspaceId,
    tabs: std.ArrayList(Tab) = .empty,
    active: ?TabId = null,
    recent: std.ArrayList(TabId) = .empty,
    recent_cycle: std.ArrayList(TabId) = .empty,
    recent_cursor: ?usize = null,
    order_revision: u64 = 0,
    drag_order: std.ArrayList(TabId) = .empty,
    dragging: bool = false,
    window_close: ?u64 = null,

    pub fn deinit(self: *Model) void {
        for (self.tabs.items) |tab| if (tab.details.len > 0) self.allocator.free(tab.details);
        self.tabs.deinit(self.allocator);
        self.recent.deinit(self.allocator);
        self.recent_cycle.deinit(self.allocator);
        self.drag_order.deinit(self.allocator);
    }
    pub fn indexOf(self: *const Model, id: TabId) ?usize {
        for (self.tabs.items, 0..) |tab, index| if (tab.id == id) return index;
        return null;
    }

    pub fn visibleCount(self: *const Model) usize {
        var count: usize = 0;
        for (self.tabs.items) |tab| if (tab.container == null) {
            count += 1;
        };
        return count;
    }
    pub fn visibleAt(self: *const Model, ordinal: usize) ?usize {
        var next: usize = 0;
        for (self.tabs.items, 0..) |tab, index| if (tab.container == null) {
            if (next == ordinal) return index;
            next += 1;
        };
        return null;
    }
    pub fn visibleIndexOf(self: *const Model, id: TabId) ?usize {
        var next: usize = 0;
        for (self.tabs.items) |tab| if (tab.container == null) {
            if (tab.id == id) return next;
            next += 1;
        };
        return null;
    }
    pub fn setContainer(self: *Model, id: TabId, container: ?TabId) !void {
        const index = self.indexOf(id) orelse return error.TabClosed;
        if (container) |parent| {
            const at = self.indexOf(parent) orelse return error.TabClosed;
            if (self.tabs.items[at].owner != .group or parent == id) return error.InvalidIdentity;
        }
        if (self.tabs.items[index].container != container) {
            self.tabs.items[index].container = container;
            environment.publish();
        }
        self.recent_cursor = null;
        self.recent_cycle.clearRetainingCapacity();
        if (self.active == id and container != null) try self.activate(container.?);
    }

    /// A retry keeps the tab but changes the exact attempt owner. Captured
    /// rename/menu/close requests from the old generation remain stale.
    pub fn replaceOwner(self: *Model, id: TabId, expected: Owner, next: Owner) !void {
        const index = self.indexOf(id) orelse return error.UnknownTab;
        const tab = &self.tabs.items[index];
        if (!tab.owner.eql(expected)) return error.StaleOwner;
        if (tab.owner.eql(next)) return;
        if (tab.revision == std.math.maxInt(u64)) return error.RevisionExhausted;
        tab.owner = next;
        tab.revision += 1;
        environment.publish();
    }
    pub fn append(self: *Model, id: TabId, owner: Owner, name: []const u8) !void {
        if (self.window_close != null) return error.WindowClosing;
        if (@backingInt(id) == 0) return error.InvalidIdentity;
        const valid_owner = switch (owner) {
            .session => |handle| @backingInt(handle.session_id) != 0 and handle.generation != 0,
            .group => |group| @backingInt(group.id) != 0 and group.revision != 0,
            .card => |card| card.valid(),
        };
        if (!valid_owner or @backingInt(self.window) == 0 or @backingInt(self.workspace) == 0) return error.InvalidIdentity;
        if (self.indexOf(id) != null) return error.DuplicateTab;
        if (self.order_revision == std.math.maxInt(u64)) return error.RevisionExhausted;
        var tab: Tab = .{ .id = id, .owner = owner };
        try tab.setName(name);
        try self.recent.ensureUnusedCapacity(self.allocator, 1);
        try self.tabs.append(self.allocator, tab);
        self.order_revision += 1;
        self.recent.appendAssumeCapacity(id);
        environment.publish();
        try self.activate(id);
    }
    /// Host/type metadata is display/search data, never the tab's primary key.
    pub fn setDetails(self: *Model, id: TabId, details: []const u8) !void {
        const tab = &self.tabs.items[self.indexOf(id) orelse return error.TabClosed];
        const owned = if (details.len > 0) try self.allocator.dupe(u8, details) else "";
        if (tab.details.len > 0) self.allocator.free(tab.details);
        tab.details = owned;
    }
    pub fn activate(self: *Model, id: TabId) !void {
        const index = self.indexOf(id) orelse return error.TabClosed;
        if (self.tabs.items[index].container) |parent| return self.activate(parent);
        self.recent_cursor = null;
        self.recent_cycle.clearRetainingCapacity();
        self.setActive(id);
        self.touchRecent(id);
    }
    fn setActive(self: *Model, id: ?TabId) void {
        if (self.active == id) return;
        self.active = id;
        environment.publish();
    }
    fn touchRecent(self: *Model, id: TabId) void {
        const at = std.mem.indexOfScalar(TabId, self.recent.items, id) orelse return;
        _ = self.recent.orderedRemove(at);
        self.recent.insertAssumeCapacity(0, id);
    }
    /// Ctrl remains held across previews. Freeze MRU order until release so
    /// repeated Tab visits every surviving tab rather than toggling two tabs.
    pub fn cycleRecent(self: *Model, reverse: bool, excluded: []const TabId) !?TabId {
        if (self.recent_cursor == null) {
            try self.recent_cycle.ensureTotalCapacity(self.allocator, self.recent.items.len);
            self.recent_cycle.clearRetainingCapacity();
            for (self.recent.items) |id| {
                if (self.visibleIndexOf(id) == null or std.mem.indexOfScalar(TabId, excluded, id) != null) continue;
                self.recent_cycle.appendAssumeCapacity(id);
            }
            if (self.recent_cycle.items.len == 0) return null;
            self.recent_cursor = if (self.active) |id| std.mem.indexOfScalar(TabId, self.recent_cycle.items, id) else null;
        }
        const count = self.recent_cycle.items.len;
        if (count == 0) return null;
        var cursor = self.recent_cursor orelse if (reverse) @as(usize, 0) else count - 1;
        for (0..count) |_| {
            cursor = if (reverse) (if (cursor == 0) count - 1 else cursor - 1) else (if (cursor + 1 == count) 0 else cursor + 1);
            const id = self.recent_cycle.items[cursor];
            if (self.visibleIndexOf(id) == null or std.mem.indexOfScalar(TabId, excluded, id) != null) continue;
            self.recent_cursor = cursor;
            self.setActive(id);
            return id;
        }
        return null;
    }
    pub fn finishRecentSwitch(self: *Model) void {
        if (self.recent_cursor != null) if (self.active) |id| self.touchRecent(id);
        self.recent_cursor = null;
        self.recent_cycle.clearRetainingCapacity();
    }
    pub fn beginRename(self: *const Model, id: TabId) !Rename {
        const tab = self.tabs.items[self.indexOf(id) orelse return error.TabClosed];
        return .{ .tab = id, .owner = tab.owner, .revision = tab.revision };
    }
    /// Own this snapshot until the batch finishes. Later tabs never join the
    /// batch; each item is still revalidated before requesting resource close.
    /// Group membership exclusions are supplied by the V0.1.6 coordinator.
    pub fn freezeCloseTargets(self: *const Model, keep: ?TabId, excluded_groups: []const identity.GroupId) ![]CloseTarget {
        if (keep) |id| if (self.indexOf(id) == null) return error.TabClosed;
        var targets: std.ArrayList(CloseTarget) = .empty;
        errdefer targets.deinit(self.allocator);
        for (self.tabs.items) |tab| {
            if (tab.id == keep) continue;
            if (tab.container) |parent| {
                if (parent == keep) continue;
                if (self.indexOf(parent)) |at| if (self.tabs.items[at].owner == .group) {
                    var retained = false;
                    for (excluded_groups) |group| if (group == self.tabs.items[at].owner.group.id) {
                        retained = true;
                        break;
                    };
                    if (retained) continue;
                };
            }
            if (tab.owner == .group) {
                var excluded = false;
                for (excluded_groups) |group| if (group == tab.owner.group.id) {
                    excluded = true;
                    break;
                };
                if (excluded) continue;
            }
            try targets.append(self.allocator, .{ .tab = tab.id, .owner = tab.owner });
        }
        return targets.toOwnedSlice(self.allocator);
    }
    pub fn isCurrentTarget(self: *const Model, target: CloseTarget) bool {
        const index = self.indexOf(target.tab) orelse return false;
        return self.tabs.items[index].owner.eql(target.owner);
    }
    pub fn beginWindowClose(self: *Model, ticket: @import("../../../host/window_host.zig").Close) ![]CloseTarget {
        if (ticket.window != self.window or ticket.workspace != self.workspace or ticket.request == 0) return error.WrongWorkspace;
        if (self.window_close != null) return error.WindowClosing;
        const targets = try self.freezeCloseTargets(null, &.{});
        self.window_close = ticket.request;
        return targets;
    }
    pub fn cancelWindowClose(self: *Model, request: u64) !void {
        if (self.window_close != request) return error.StaleClose;
        self.window_close = null;
    }
    pub fn rename(self: *Model, request: Rename, raw: []const u8) !void {
        const tab = &self.tabs.items[self.indexOf(request.tab) orelse return error.TabClosed];
        if (!std.meta.eql(tab.owner, request.owner) or tab.revision != request.revision) return error.StaleRename;
        if (tab.revision == std.math.maxInt(u64)) return error.RevisionExhausted;
        try tab.setName(raw);
        tab.revision += 1;
        environment.publish();
    }
    /// A user rename: the name wins over every derived name from now on.
    pub fn renameCustom(self: *Model, request: Rename, raw: []const u8) !void {
        try self.rename(request, raw);
        const tab = &self.tabs.items[self.indexOf(request.tab).?];
        tab.custom = true;
        tab.display_len = 0;
    }
    /// Presentation only: never bumps the rename revision, so an in-flight
    /// rename is not invalidated by a cwd / program change. Returns true when
    /// the shown name changed. An empty value falls back to the title.
    pub fn setDisplayName(self: *Model, id: TabId, value: []const u8) bool {
        const tab = &self.tabs.items[self.indexOf(id) orelse return false];
        var n = @min(value.len, tab.display.len);
        while (n > 0 and !std.unicode.utf8ValidateSlice(value[0..n])) n -= 1;
        const next: []const u8 = if (n == 0 or std.mem.eql(u8, value[0..n], tab.baseName())) "" else value[0..n];
        if (std.mem.eql(u8, tab.display[0..tab.display_len], next)) return false;
        @memcpy(tab.display[0..next.len], next);
        tab.display_len = @intCast(next.len);
        environment.publish();
        return true;
    }
    /// Called only after the owning controller acknowledges resource cleanup.
    /// Group confirmation/close coordination happens before this method.
    pub fn completeClose(self: *Model, id: TabId, owner: Owner) !void {
        const index = self.indexOf(id) orelse return error.TabClosed;
        if (!std.meta.eql(self.tabs.items[index].owner, owner)) return error.StaleOwner;
        if (self.order_revision == std.math.maxInt(u64)) return error.RevisionExhausted;
        const removed = self.tabs.orderedRemove(index);
        for (self.tabs.items) |*tab| if (tab.container == id) {
            tab.container = null;
        };
        if (std.mem.indexOfScalar(TabId, self.recent.items, id)) |recent_index| _ = self.recent.orderedRemove(recent_index);
        if (removed.details.len > 0) self.allocator.free(removed.details);
        self.order_revision += 1;
        environment.publish();
        if (self.active == id) {
            // zeditor file tabs (tab_manager.zig closeTab / e2e file_tabs_vscode):
            // closing the active tab reveals the most recently used survivor;
            // only when none was ever used does the left neighbour take over.
            self.active = null;
            for (self.recent.items) |candidate| {
                const at = self.indexOf(candidate) orelse continue;
                if (self.tabs.items[at].container == null) {
                    self.active = candidate;
                    break;
                }
            }
            if (self.active == null and self.tabs.items.len > 0) {
                const start = if (index == 0) 0 else @min(index - 1, self.tabs.items.len - 1);
                for (0..self.tabs.items.len) |offset| {
                    const at = (start + self.tabs.items.len - offset) % self.tabs.items.len;
                    if (self.tabs.items[at].container == null) {
                        self.active = self.tabs.items[at].id;
                        break;
                    }
                }
            }
            if (self.active) |active| self.touchRecent(active);
        }
    }
    pub fn beginDrag(self: *Model) !void {
        if (self.dragging) return error.DragInProgress;
        try self.drag_order.ensureTotalCapacity(self.allocator, self.tabs.items.len);
        self.drag_order.clearRetainingCapacity();
        for (self.tabs.items) |tab| self.drag_order.appendAssumeCapacity(tab.id);
        self.dragging = true;
    }
    pub fn moveTab(self: *Model, id: TabId, to: usize) !void {
        const from = self.indexOf(id) orelse return error.TabClosed;
        if (to >= self.tabs.items.len) return error.InvalidPosition;
        if (from == to) return;
        if (self.order_revision == std.math.maxInt(u64)) return error.RevisionExhausted;
        const tab = self.tabs.orderedRemove(from);
        self.tabs.insertAssumeCapacity(to, tab);
        self.order_revision += 1;
    }
    pub fn endDrag(self: *Model, cancel: bool) !void {
        if (!self.dragging) return;
        if (cancel) {
            if (self.order_revision == std.math.maxInt(u64)) return error.RevisionExhausted;
            // Restore surviving original tabs; new tabs stay after that snapshot.
            var next: usize = 0;
            for (self.drag_order.items) |id| {
                const at = self.indexOf(id) orelse continue;
                const tab = self.tabs.orderedRemove(at);
                self.tabs.insertAssumeCapacity(next, tab);
                next += 1;
            }
            self.order_revision += 1;
        }
        self.dragging = false;
        self.drag_order.clearRetainingCapacity();
    }
};

fn testModel() Model {
    return .{ .allocator = std.testing.allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) };
}
fn session(id: u64) Owner {
    return .{ .session = .{ .session_id = @fromBackingInt(id), .generation = 1 } };
}

test "recent tab cycle freezes MRU order until Control release" {
    var model = testModel();
    defer model.deinit();
    const a: TabId = @fromBackingInt(1);
    const b: TabId = @fromBackingInt(2);
    const c: TabId = @fromBackingInt(3);
    try model.append(a, session(1), "same");
    try model.append(b, session(2), "same");
    try model.append(c, session(3), "same");
    try model.activate(a);
    try model.moveTab(c, 0);
    try std.testing.expectEqual(c, (try model.cycleRecent(false, &.{})).?);
    try std.testing.expectEqual(b, (try model.cycleRecent(false, &.{})).?);
    try std.testing.expectEqual(c, (try model.cycleRecent(true, &.{})).?);
    try std.testing.expectEqualSlices(TabId, &.{ a, c, b }, model.recent.items);
    model.finishRecentSwitch();
    try std.testing.expectEqualSlices(TabId, &.{ c, a, b }, model.recent.items);
    try std.testing.expectEqual(a, (try model.cycleRecent(false, &.{})).?);
    model.finishRecentSwitch();
    try std.testing.expectEqual(c, (try model.cycleRecent(false, &.{})).?);
    try std.testing.expectEqual(@as(?TabId, c), model.active);
}

test "recent tab cycle skips closed and pending close identities" {
    var model = testModel();
    defer model.deinit();
    const a: TabId = @fromBackingInt(1);
    const b: TabId = @fromBackingInt(2);
    const c: TabId = @fromBackingInt(3);
    const d: TabId = @fromBackingInt(4);
    for ([_]TabId{ a, b, c, d }) |id| try model.append(id, session(@backingInt(id)), "same");
    try std.testing.expectEqual(c, (try model.cycleRecent(false, &.{})).?);
    try model.completeClose(b, session(2));
    try std.testing.expectEqual(a, (try model.cycleRecent(false, &.{})).?);
    try std.testing.expectEqual(d, (try model.cycleRecent(false, &.{c})).?);
    try model.completeClose(c, session(3));
    model.finishRecentSwitch();
    try std.testing.expectEqualSlices(TabId, &.{ d, a }, model.recent.items);
    try std.testing.expectEqual(a, (try model.cycleRecent(true, &.{})).?);
    try model.completeClose(a, session(1));
    try std.testing.expectEqual(d, (try model.cycleRecent(false, &.{})).?);
    try model.completeClose(d, session(4));
    try std.testing.expect((try model.cycleRecent(false, &.{})) == null);
    model.finishRecentSwitch();
    try std.testing.expect(model.active == null);
}

test "same names keep identity; late rename cannot touch surviving tab" {
    var model = testModel();
    defer model.deinit();
    const a: TabId = @fromBackingInt(1);
    const b: TabId = @fromBackingInt(2);
    try model.append(a, session(7), "same");
    try model.append(b, session(8), "same");
    const draft = try model.beginRename(a);
    try model.completeClose(a, session(7));
    try std.testing.expectError(error.TabClosed, model.rename(draft, "changed"));
    try std.testing.expectEqualStrings("same", model.tabs.items[0].name());
    const edit = try model.beginRename(b);
    try std.testing.expectError(error.InvalidName, model.rename(edit, "\xff"));
    try std.testing.expectError(error.NameTooLong, model.rename(edit, "界界界界界界界界界界界界界界界界界界界界界界"));
    try model.rename(edit, "生产");
    try std.testing.expectError(error.StaleRename, model.rename(edit, "late"));
}

test "retry replaces only the attempt owner and invalidates captured tab requests" {
    var model = testModel();
    defer model.deinit();
    const id: TabId = @fromBackingInt(5);
    const old = session(91);
    const next: Owner = .{ .session = try old.session.nextGeneration() };
    try model.append(id, old, "我的本地会话");
    const rename = try model.beginRename(id);
    const captured = try model.freezeCloseTargets(null, &.{});
    defer model.allocator.free(captured);
    try model.replaceOwner(id, old, next);
    try std.testing.expectEqual(id, model.active.?);
    try std.testing.expectEqualStrings("我的本地会话", model.tabs.items[0].name());
    try std.testing.expect(model.tabs.items[0].owner.eql(next));
    try std.testing.expect(!model.isCurrentTarget(captured[0]));
    try std.testing.expectError(error.StaleRename, model.rename(rename, "迟到的重命名"));
    try std.testing.expectError(error.StaleOwner, model.completeClose(id, old));
    try std.testing.expectError(error.StaleOwner, model.replaceOwner(id, old, next));
    const revision = model.tabs.items[0].revision;
    try model.replaceOwner(id, next, next);
    try std.testing.expectEqual(revision, model.tabs.items[0].revision);
    try model.completeClose(id, next);
    try std.testing.expect(model.active == null);
}

test "close acknowledgment keeps background active and reveals the most recently used tab" {
    var model = testModel();
    defer model.deinit();
    for (1..5) |id| try model.append(@fromBackingInt(@as(u64, @intCast(id))), session(@intCast(id)), "tab");
    try model.activate(@fromBackingInt(2));
    try std.testing.expectError(error.StaleOwner, model.completeClose(@fromBackingInt(1), session(9)));
    // Closing a background tab never moves the active tab.
    try model.completeClose(@fromBackingInt(1), session(1));
    try std.testing.expectEqual(@as(?TabId, @fromBackingInt(2)), model.active);
    // MRU is 2, 4, 3: closing 2 reveals 4, not its right neighbour 3.
    try model.completeClose(@fromBackingInt(2), session(2));
    try std.testing.expectEqual(@as(?TabId, @fromBackingInt(4)), model.active);
    try model.activate(@fromBackingInt(3));
    try model.activate(@fromBackingInt(4));
    try model.completeClose(@fromBackingInt(4), session(4));
    try std.testing.expectEqual(@as(?TabId, @fromBackingInt(3)), model.active);
    try model.completeClose(@fromBackingInt(3), session(3));
    try std.testing.expect(model.active == null);
}

test "drag cancel restores surviving snapshot without retargeting owner or active" {
    var model = testModel();
    defer model.deinit();
    for (1..4) |id| try model.append(@fromBackingInt(@as(u64, @intCast(id))), session(@intCast(id)), "tab");
    try model.beginDrag();
    try model.moveTab(@fromBackingInt(3), 0);
    try model.completeClose(@fromBackingInt(2), session(2));
    try model.append(@fromBackingInt(4), session(4), "new");
    try model.endDrag(true);
    try std.testing.expectEqual(@as(TabId, @fromBackingInt(1)), model.tabs.items[0].id);
    try std.testing.expectEqual(@as(TabId, @fromBackingInt(3)), model.tabs.items[1].id);
    try std.testing.expectEqual(@as(TabId, @fromBackingInt(4)), model.tabs.items[2].id);
    try std.testing.expectEqual(@as(?TabId, @fromBackingInt(4)), model.active);
    try std.testing.expect(std.meta.eql(session(3), model.tabs.items[1].owner));
}

test "close batch freezes ordered targets and excludes groups containing retained session" {
    var model = testModel();
    defer model.deinit();
    try model.append(@fromBackingInt(1), session(1), "keep");
    try model.append(@fromBackingInt(2), .{ .group = .{ .id = @fromBackingInt(1) } }, "group sharing keep");
    try model.append(@fromBackingInt(3), session(3), "close");
    const targets = try model.freezeCloseTargets(@fromBackingInt(1), &.{@fromBackingInt(1)});
    defer model.allocator.free(targets);
    try model.append(@fromBackingInt(4), session(4), "arrived later");
    try std.testing.expectEqual(@as(usize, 1), targets.len);
    try std.testing.expectEqual(@as(TabId, @fromBackingInt(3)), targets[0].tab);
    try std.testing.expect(model.isCurrentTarget(targets[0]));
    try model.completeClose(targets[0].tab, targets[0].owner);
    try std.testing.expect(!model.isCurrentTarget(targets[0]));
    try std.testing.expectEqual(@as(usize, 3), model.tabs.items.len);
}

test "window close freezes owners and gates new content until matching cancellation" {
    var model = testModel();
    defer model.deinit();
    try model.append(@fromBackingInt(1), session(1), "existing");
    const targets = try model.beginWindowClose(.{ .window = model.window, .workspace = model.workspace, .request = 7 });
    defer model.allocator.free(targets);
    try std.testing.expectEqual(@as(usize, 1), targets.len);
    try std.testing.expectError(error.WindowClosing, model.append(@fromBackingInt(2), session(2), "new"));
    try std.testing.expectError(error.StaleClose, model.cancelWindowClose(6));
    try model.cancelWindowClose(7);
    try model.append(@fromBackingInt(2), session(2), "new");
}

test "group created sessions have one visible entry and recover their own tab when detached" {
    var model = testModel();
    defer model.deinit();
    const original: TabId = @fromBackingInt(1);
    const group: TabId = @fromBackingInt(2);
    const created: TabId = @fromBackingInt(3);
    try model.append(original, session(1), "source");
    try model.append(group, .{ .group = .{ .id = @fromBackingInt(7) } }, "group");
    try model.append(created, session(3), "created");
    try model.setContainer(created, group);
    try std.testing.expectEqual(@as(usize, 3), model.tabs.items.len);
    try std.testing.expectEqual(@as(usize, 2), model.visibleCount());
    try std.testing.expect(model.visibleIndexOf(created) == null);
    try model.activate(created);
    try std.testing.expectEqual(group, model.active.?);
    const excluded = try model.freezeCloseTargets(original, &.{@fromBackingInt(7)});
    defer model.allocator.free(excluded);
    try std.testing.expectEqual(@as(usize, 0), excluded.len);
    _ = try model.cycleRecent(false, &.{});
    try std.testing.expect(model.active != created);
    model.finishRecentSwitch();
    try model.setContainer(created, null);
    try std.testing.expectEqual(@as(usize, 3), model.visibleCount());
    try model.activate(created);
    try std.testing.expectEqual(created, model.active.?);
    try model.setContainer(created, group);
    try model.completeClose(group, .{ .group = .{ .id = @fromBackingInt(7) } });
    try std.testing.expectEqual(@as(?TabId, null), model.tabs.items[model.indexOf(created).?].container);
    try std.testing.expect(model.isCurrentTarget(.{ .tab = created, .owner = session(3) }));
}

test "tab display name is presentation only; a user rename wins" {
    var model: Model = .{ .allocator = std.testing.allocator, .window = @fromBackingInt(1), .workspace = @fromBackingInt(1) };
    defer model.deinit();
    const id: TabId = @fromBackingInt(7);
    try model.append(id, .{ .session = .{ .session_id = @fromBackingInt(70), .generation = 1 } }, "本地终端");
    const pending = try model.beginRename(id);
    try std.testing.expect(model.setDisplayName(id, "zerowork"));
    try std.testing.expect(!model.setDisplayName(id, "zerowork"));
    try std.testing.expectEqualStrings("zerowork", model.tabs.items[0].name());
    try std.testing.expectEqualStrings("本地终端", model.tabs.items[0].baseName());
    // Derived names never invalidate an in-flight rename.
    try model.renameCustom(pending, "构建机");
    try std.testing.expect(model.tabs.items[0].custom);
    try std.testing.expectEqualStrings("构建机", model.tabs.items[0].name());
    // Same as the title: no separate display copy.
    try std.testing.expect(!model.setDisplayName(id, "构建机"));
    try std.testing.expect(model.setDisplayName(id, "构建机 · 2"));
    try std.testing.expectEqualStrings("构建机 · 2", model.tabs.items[0].name());
}

test "tab set owner container and current tab changes publish the environment and same-value writes do not" {
    var model = testModel();
    defer model.deinit();
    const a: TabId = @fromBackingInt(1);
    const group: TabId = @fromBackingInt(2);
    var before = environment.revision();
    try model.append(a, session(1), "a");
    try std.testing.expect(environment.revision() > before);
    try model.append(group, .{ .group = .{ .id = @fromBackingInt(7), .revision = 1 } }, "group");
    before = environment.revision();
    try model.activate(group);
    try model.setContainer(a, null);
    try model.replaceOwner(a, session(1), session(1));
    try std.testing.expectEqual(before, environment.revision());
    try model.activate(a);
    try std.testing.expect(environment.revision() > before);
    before = environment.revision();
    try model.setContainer(a, group);
    try std.testing.expect(environment.revision() > before);
    try std.testing.expectEqual(@as(?TabId, group), model.active);
    before = environment.revision();
    const next: Owner = .{ .session = .{ .session_id = @fromBackingInt(1), .generation = 2 } };
    try model.replaceOwner(a, session(1), next);
    try std.testing.expect(environment.revision() > before);
    // Names: a rename and a changed derived name publish; the same derived name does not.
    before = environment.revision();
    try model.rename(try model.beginRename(a), "renamed");
    try std.testing.expect(environment.revision() > before);
    before = environment.revision();
    try std.testing.expect(model.setDisplayName(a, "derived"));
    try std.testing.expect(environment.revision() > before);
    before = environment.revision();
    try std.testing.expect(!model.setDisplayName(a, "derived"));
    try std.testing.expectEqual(before, environment.revision());
    try model.completeClose(a, next);
    try std.testing.expect(environment.revision() > before);
}
