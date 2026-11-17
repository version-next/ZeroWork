//! Empty workspace "已保存的连接" (Pencil hmCmB `vDyAK`): up to three saved
//! connections under the empty-state actions. The view is
//! `empty_saved_connections.yix` (native `W.Pressable` rows); this file holds the
//! pick / label rules and the view-model. A click runs the same new-session path
//! as the sidebar row's connect action. The list hides when nothing is saved.
const std = @import("std");
const ui = @import("ui");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
const template = @import("_empty_saved_connections.yix.zig");
const hosts = @import("../../../config/hosts.zig");
const identity = @import("../../../host/identity.zig");

pub const max_rows: usize = 3;
pub const width: f32 = 440;

pub const Entry = struct {
    index: usize,
    name: []const u8,
    protocol: []const u8,
    sftp: bool,
    hops: usize,
    /// 协议插件被禁用（Q5）时的原因与恢复路径（侧栏 qQaos 的同一段文案）；null = 可连接。
    unavailable: ?[]const u8 = null,
};

/// Most recently used first (when recency is known), then registry order.
/// `recency(connection_id)` returns a larger value for a newer connect.
pub fn pick(registry_hosts: []const hosts.HostConfig, recency: anytype, out: *[max_rows]usize) []usize {
    var count: usize = 0;
    // Recent hosts by descending recency.
    while (count < max_rows) {
        var best: ?usize = null;
        var best_seq: u64 = 0;
        for (registry_hosts, 0..) |host, index| {
            const seq = recency.seqOf(host.connection_id) orelse continue;
            if (std.mem.indexOfScalar(usize, out[0..count], index) != null) continue;
            if (best == null or seq > best_seq) {
                best = index;
                best_seq = seq;
            }
        }
        out[count] = best orelse break;
        count += 1;
    }
    for (registry_hosts, 0..) |_, index| {
        if (count == max_rows) break;
        if (std.mem.indexOfScalar(usize, out[0..count], index) != null) continue;
        out[count] = index;
        count += 1;
    }
    return out[0..count];
}

/// "SSH · 直连" / "SSH · 1 跳" / "SFTP · 直连" (hmCmB row meta).
pub fn metaLabel(buffer: []u8, protocol: []const u8, hops: usize) []const u8 {
    var upper: [16]u8 = undefined;
    const name = std.ascii.upperString(upper[0..@min(upper.len, protocol.len)], protocol[0..@min(upper.len, protocol.len)]);
    if (hops == 0) return std.fmt.bufPrint(buffer, "{s} · 直连", .{name}) catch name;
    return std.fmt.bufPrint(buffer, "{s} · {d} 跳", .{ name, hops }) catch name;
}

pub const ids = struct {
    pub const root = "workspace.empty.saved";
    pub const row = "workspace.empty.saved.row";
    pub const unavailable = "workspace.empty.saved.unavailable";
    pub const tooltip = "workspace.empty.saved.unavailable.tooltip";
};

pub const Connect = struct {
    context: *anyopaque,
    run: *const fn (*anyopaque, usize) void,
};

/// One shown row. Strings live in the view-model's arena for this generation.
pub const Row = struct {
    /// Fresh per refresh: rows remount with the new strings.
    key: u64,
    index: usize,
    name: []const u8,
    meta: []const u8,
    sftp: bool,
    /// 被禁用协议的主机（与侧栏同规则）：变淡、行尾“已禁用”（Tooltip 写原因）、不能连接。
    unavailable: bool = false,
    reason: []const u8 = "",

    pub fn metaText(self: Row) []const u8 {
        return self.meta;
    }
};

/// View-model behind `empty_saved_connections.yix`. Rows are copied (registry names may be
/// replaced before the next refresh) into one of two arenas: the signal keeps the previous
/// generation alive until the new one replaces it.
pub const ViewModel = struct {
    cx: *ui.Cx,
    root: *ui.Node = undefined,
    connect_hook: Connect,
    list: *ui.Signal([]const Row),
    arenas: [2]std.heap.ArenaAllocator,
    current: u1 = 0,
    generation: u64 = 0,

    pub fn shown(self: *const ViewModel) bool {
        return self.list.get().len != 0;
    }
    pub fn rows(self: *const ViewModel) []const Row {
        return self.list.get();
    }
    pub fn connect(self: *ViewModel, index: usize) void {
        for (self.list.peek()) |row| if (row.index == index and row.unavailable) return;
        self.connect_hook.run(self.connect_hook.context, index);
    }

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, parent: *ui.Node, hook: Connect) !*ViewModel {
        const self = try scope.createState(ViewModel, .{
            .cx = cx,
            .connect_hook = hook,
            .list = try scope.createSignal([]const Row, &.{}),
            .arenas = .{ std.heap.ArenaAllocator.init(cx.allocator), std.heap.ArenaAllocator.init(cx.allocator) },
        });
        try scope.onCleanup(ViewModel, self, cleanup);
        self.root = try ui.view.render(scope, cx, template.SavedConnections(.{ .vm = self }));
        try parent.appendChild(cx.allocator, self.root);
        return self;
    }

    fn cleanup(self: *ViewModel) void {
        for (&self.arenas) |*arena| arena.deinit();
    }

    /// Replaces the rows (at most `max_rows`); the list hides when empty.
    pub fn update(self: *ViewModel, entries: []const Entry) !void {
        const next: u1 = self.current ^ 1;
        const arena_state = &self.arenas[next];
        _ = arena_state.reset(.retain_capacity);
        const arena = arena_state.allocator();
        const shown_entries = entries[0..@min(entries.len, max_rows)];
        const out = try arena.alloc(Row, shown_entries.len);
        self.generation +%= 1;
        for (shown_entries, out, 0..) |entry, *row, position| {
            var buffer: [64]u8 = undefined;
            row.* = .{ .key = self.generation *% max_rows + position, .index = entry.index, .name = try arena.dupe(u8, entry.name), .meta = try arena.dupe(u8, metaLabel(&buffer, entry.protocol, entry.hops)), .sftp = entry.sftp, .unavailable = entry.unavailable != null, .reason = if (entry.unavailable) |text| try arena.dupe(u8, text) else "" };
        }
        self.current = next;
        self.list.set(out);
        self.cx.requestRedraw();
    }
};
pub const View = ViewModel;

test "saved connections pick recent first then registry order and label routes" {
    const Recency = struct {
        newest: identity.ConnectionId,
        fn seqOf(self: @This(), id: identity.ConnectionId) ?u64 {
            return if (id == self.newest) 9 else null;
        }
    };
    const list = [_]hosts.HostConfig{
        .{ .connection_id = @fromBackingInt(1), .name = "a", .host = "192.0.2.1", .user = "u" },
        .{ .connection_id = @fromBackingInt(2), .name = "b", .host = "192.0.2.2", .user = "u" },
        .{ .connection_id = @fromBackingInt(3), .name = "c", .host = "192.0.2.3", .user = "u" },
        .{ .connection_id = @fromBackingInt(4), .name = "d", .host = "192.0.2.4", .user = "u" },
    };
    var out: [max_rows]usize = undefined;
    const picked = pick(&list, Recency{ .newest = @fromBackingInt(3) }, &out);
    try std.testing.expectEqualSlices(usize, &.{ 2, 0, 1 }, picked);
    try std.testing.expectEqual(@as(usize, 0), pick(list[0..0], Recency{ .newest = @fromBackingInt(3) }, &out).len);
    var buffer: [32]u8 = undefined;
    try std.testing.expectEqualStrings("SSH · 直连", metaLabel(&buffer, "ssh", 0));
    try std.testing.expectEqualStrings("SFTP · 1 跳", metaLabel(&buffer, "sftp", 1));
}

test "saved connections list shows rows for saved hosts connects on click and hides when empty" {
    const cx = try ui.Cx.init(std.testing.allocator, std.testing.io);
    defer cx.deinit();
    cx.setViewport(1176, 856);
    cx.setTheme(theme.widgetTheme(theme.currentName()));
    const scope = try ui.Scope.init(std.testing.allocator, null, cx.owner);
    defer scope.dispose();
    const parent = try ui.box(cx, .{ .width = .fill(), .height = .fill(), .direction = .column, .align_items = .center }, .{});
    cx.root = parent;
    const Sink = struct {
        calls: usize = 0,
        last: ?usize = null,
        fn run(raw: *anyopaque, index: usize) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            self.last = index;
        }
    };
    var sink: Sink = .{};
    // The test finds the rendered rows by their test id (production code never does).
    const collectRows = struct {
        fn run(node: *ui.Node, out: []*ui.Node, start: usize) usize {
            var count = start;
            if (std.mem.eql(u8, node.meta.ownership.meta.test_id orelse "", ids.row) and node.isDisplayedInTree()) {
                if (count < out.len) out[count] = node;
                count += 1;
            }
            for (node.children.items) |child| count = run(child, out, count);
            return count;
        }
    }.run;
    const view = try View.mount(cx, scope, parent, .{ .context = &sink, .run = Sink.run });
    const frames = struct {
        fn run(c: *ui.Cx) void {
            for (0..4) |_| {
                c.frame_count += 1;
                c.frame_time_ms += 16;
                c.bindFrameClock();
                _ = c.render();
            }
        }
    }.run;
    // No saved hosts: the section stays hidden.
    try view.update(&.{});
    frames(cx);
    try std.testing.expect(view.root.style.display == .none);
    try view.update(&.{
        .{ .index = 4, .name = "beta-api-01", .protocol = "ssh", .sftp = false, .hops = 0 },
        .{ .index = 7, .name = "beta-assets", .protocol = "sftp", .sftp = true, .hops = 1 },
    });
    frames(cx);
    try std.testing.expect(view.root.style.display != .none);
    var found: [max_rows]*ui.Node = undefined;
    try std.testing.expectEqual(@as(usize, 2), collectRows(view.root, &found, 0));
    // hmCmB: 440 wide list, ZW4 / Project Row rows 28 high.
    try std.testing.expectApproxEqAbs(width, view.root.globalRect().w, 0.1);
    const row = found[1];
    try std.testing.expectApproxEqAbs(@as(f32, 28), row.globalRect().h, 0.1);
    const r = row.globalRect();
    cx.handleMouseDown(r.x + r.w / 2, r.y + r.h / 2, .{});
    cx.handleMouseUp(r.x + r.w / 2, r.y + r.h / 2);
    frames(cx);
    try std.testing.expectEqual(@as(usize, 1), sink.calls);
    try std.testing.expectEqual(@as(?usize, 7), sink.last);
    // 协议插件被禁用的主机：行仍在原位，点击不连接。
    try view.update(&.{
        .{ .index = 4, .name = "beta-api-01", .protocol = "ssh", .sftp = false, .hops = 0 },
        .{ .index = 9, .name = "q5-kvm", .protocol = "fixture_probe", .sftp = false, .hops = 0, .unavailable = "Fixture 已禁用，不可连接。" },
    });
    frames(cx);
    try std.testing.expectEqual(@as(usize, 2), collectRows(view.root, &found, 0));
    try std.testing.expect(view.rows()[1].unavailable);
    try std.testing.expectEqualStrings("Fixture 已禁用，不可连接。", view.rows()[1].reason);
    const off = found[1].globalRect();
    cx.handleMouseDown(off.x + off.w / 2, off.y + off.h / 2, .{});
    cx.handleMouseUp(off.x + off.w / 2, off.y + off.h / 2);
    frames(cx);
    view.connect(9);
    try std.testing.expectEqual(@as(usize, 1), sink.calls);
    try view.update(&.{});
    frames(cx);
    try std.testing.expect(view.root.style.display == .none);
    try std.testing.expectEqual(@as(usize, 0), collectRows(view.root, &found, 0));
}
