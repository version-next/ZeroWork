//! Original-card context/history menus: native `W.Menu` through the one menu entry (`shell/view/app_menu.zig`,
//! menus 包). Every action carries the frozen controller envelope; later navigation or selection cannot
//! retarget it. A failed action reports through the pane (status line), like every other file action.
const std = @import("std");
const ui = @import("ui");
const Files = @import("file_workspace_view.zig");
const Controller = @import("../../../host/file_workspace_controller.zig");
const app_menu = @import("../../shell/mod.zig").app_menu;
const receipts = @import("../../notifications/mod.zig");
const Frozen = struct { arena: std.heap.ArenaAllocator, envelope: Files.Envelope, directory: []const u8, destination: Files.Stamp, target: []const u8, history: []const Controller.HistoryEntry };
pub const View = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    pane: *Files.Pane,
    model: *Controller.Controller,
    /// 挂载点（零尺寸）；两个原生菜单的面板在窗口浮层根。
    root: *ui.Node = undefined,
    context_menu: *app_menu.AppMenu = undefined,
    history_menu: *app_menu.AppMenu = undefined,
    frozen: ?Frozen = null,
    pending: ?Frozen = null,
    history: bool = false,
    rebuild: bool = false,
    entries: [max_entries]app_menu.Entry = undefined,
    ids: [max_entries][24]u8 = undefined,
    /// Strings the rows borrow (frozen paths, “path · failure” labels) stay alive one generation past
    /// their menu: a mounted native menu keeps its rows (and their a11y labels) until it is rebuilt.
    labels: [2]std.heap.ArenaAllocator = undefined,
    label_slot: u1 = 0,
    retired: ?Frozen = null,

    const max_entries = 48;
    const no_keys: @import("../../shell/mod.zig").shortcut_router.Map = .{};

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, pane: *Files.Pane, model: *Controller.Controller) !*View {
        const self = try scope.createState(View, .{ .cx = cx, .scope = scope, .pane = pane, .model = model, .labels = .{ .init(cx.allocator), .init(cx.allocator) } });
        try scope.onCleanup(View, self, cleanup);
        self.root = try ui.box(cx, .{ .position = .absolute, .width = .{ .px = 0 }, .height = .{ .px = 0 } }, .{});
        const hooks: app_menu.Hooks = .{ .context = self, .select = selected };
        self.context_menu = try app_menu.AppMenu.mountContext(cx, scope, self.root, .{ .panel_test_id = "files.context.menu" }, hooks);
        // PLfO1: path history shows up to about five rows, then scrolls inside the native menu.
        self.history_menu = try app_menu.AppMenu.mountContext(cx, scope, self.root, .{ .panel_test_id = "files.history.menu", .max_height = 200 }, hooks);
        return self;
    }
    pub fn show(self: *View, envelope: Files.Envelope, entries: ?[]const Controller.HistoryEntry) !void {
        const projection = self.model.projection() orelse return error.FileProjectionUnavailable;
        var arena = std.heap.ArenaAllocator.init(self.cx.allocator);
        errdefer arena.deinit();
        const a = arena.allocator();
        var frozen = envelope;
        if (envelope.action == .context) {
            var selected_keys = envelope.action.context;
            const keys = try a.alloc([]const u8, selected_keys.keys.len);
            for (selected_keys.keys, keys) |key, *copy| copy.* = try a.dupe(u8, key);
            selected_keys.keys = keys;
            if (selected_keys.anchor) |key| selected_keys.anchor = try a.dupe(u8, key);
            if (selected_keys.focused_key) |key| selected_keys.focused_key = try a.dupe(u8, key);
            frozen.action = .{ .context = selected_keys };
        }
        const history = try a.alloc(Controller.HistoryEntry, if (entries) |values| values.len else 0);
        if (entries) |values| {
            for (values, history) |value, *copy| copy.* = .{ .path = try a.dupe(u8, value.path), .succeeded = value.succeeded, .failure = try a.dupe(u8, value.failure) };
        }
        const opposite = projection.panes[if (envelope.side == .local) 1 else 0];
        const directory = try a.dupe(u8, projection.panes[@backingInt(envelope.side)].resolved_path);
        const target = try a.dupe(u8, opposite.resolved_path);
        const next: Frozen = .{ .arena = arena, .envelope = frozen, .directory = directory, .destination = opposite.stamp, .target = target, .history = history };
        if (self.pending) |*old| old.arena.deinit();
        self.pending = next;
        self.history = entries != null;
        self.rebuild = true;
        self.context_menu.hide();
        self.history_menu.hide();
        self.cx.requestRedraw();
    }
    /// Presentation calls only after handlers unwind: freeze the new envelope and open its native menu.
    pub fn sync(self: *View) !void {
        if (!self.rebuild) return;
        self.rebuild = false;
        if (self.retired) |*old| old.arena.deinit();
        self.retired = self.frozen;
        self.frozen = self.pending;
        self.pending = null;
        const frozen = if (self.frozen) |*value| value else return;
        self.label_slot ^= 1;
        _ = self.labels[self.label_slot].reset(.retain_capacity);
        var n: usize = 0;
        if (self.history) {
            self.entries[n] = .{ .label = if (self.pane.side == .local) "本地路径历史" else "远程路径历史", .kind = .header };
            n += 1;
            if (frozen.history.len == 0) {
                self.entries[n] = .{ .id = "none", .label = "暂无路径历史", .disabled = true, .test_id = "files.history.empty" };
                n += 1;
            }
            var position = frozen.history.len;
            while (position > 0 and n + 2 <= max_entries) {
                position -= 1;
                const entry = frozen.history[position];
                const label = if (entry.succeeded) entry.path else try std.fmt.allocPrint(self.labels[self.label_slot].allocator(), "{s} · {s}", .{ entry.path, entry.failure });
                self.entries[n] = .{ .id = try std.fmt.bufPrint(&self.ids[n], "navigate.{d}", .{position}), .label = label, .test_id = "files.history.navigate" };
                n += 1;
                if (!entry.succeeded) {
                    self.entries[n] = .{ .id = try std.fmt.bufPrint(&self.ids[n], "remove.{d}", .{position}), .label = "移除当前记录", .icon = "x", .test_id = "files.history.remove" };
                    n += 1;
                }
            }
            self.context_menu.clear();
            self.history_menu.show(self.entries[0..n], .{ .keys = &no_keys }, self.pane.history_button.globalRect());
            return;
        }
        const source = self.model.projection().?.panes[@backingInt(self.pane.side)];
        const none_selected = frozen.envelope.action.context.keys.len == 0;
        self.entries[0] = .{ .id = "transfer", .label = if (self.pane.side == .local) "上传所选…" else "下载所选…", .icon = if (self.pane.side == .local) "arrow-up-from-line" else "arrow-down-to-line", .test_id = "files.context.transfer", .disabled = !source.can_transfer, .disabled_reason = if (none_selected) "未选中文件" else null };
        self.entries[1] = .{ .id = "copy", .label = "复制完整路径", .icon = "copy", .test_id = "files.context.copy", .disabled_reason = if (none_selected) "未选中文件" else null };
        self.entries[2] = .{ .id = "rename", .label = "重命名", .icon = "pencil", .test_id = "files.context.rename", .group = 1, .disabled = true };
        self.entries[3] = .{ .id = "mkdir", .label = "新建文件夹…", .icon = "folder-plus", .test_id = "files.context.mkdir", .group = 1, .disabled = !source.can_mkdir };
        const anchor_rect = self.pane.context_anchor orelse self.pane.context_button.globalRect();
        self.history_menu.clear();
        self.context_menu.show(self.entries[0..4], .{ .keys = &no_keys }, anchor_rect);
    }
    const Kind = enum { transfer, copy, mkdir, navigate, remove };
    /// Tests pick a row the way the native menu does (its `on_select` id).
    pub fn selectForTest(self: *View, id: []const u8) void {
        selected(self, id);
    }
    fn selected(raw: *anyopaque, id: []const u8) void {
        const self: *View = @ptrCast(@alignCast(raw));
        const frozen = self.frozen orelse return;
        const split = std.mem.indexOfScalar(u8, id, '.');
        const kind = std.meta.stringToEnum(Kind, if (split) |at| id[0..at] else id) orelse return;
        const path: ?[]const u8 = if (split) |at| blk: {
            const index = std.fmt.parseInt(usize, id[at + 1 ..], 10) catch return;
            if (index >= frozen.history.len) return;
            break :blk frozen.history[index].path;
        } else null;
        const clicked_rect = self.pane.context_button.globalRect();
        var envelope = frozen.envelope;
        envelope.action = switch (kind) {
            .transfer => .{ .transfer = .{ .selection = frozen.envelope.action.context, .destination = frozen.destination, .directory = frozen.target } },
            .copy => .{ .copy_paths = frozen.envelope.action.context },
            .mkdir => .new_folder,
            .navigate => .{ .navigate = .{ .requested_path = path.?, .base_directory = frozen.directory } },
            .remove => {
                self.model.removeHistory(envelope, path.?) catch |err| self.pane.report(err);
                return;
            },
        };
        self.model.handle(envelope) catch |err| {
            self.pane.report(err);
            return;
        };
        if (kind == .copy) receipts.acknowledgeAt(self.cx, clicked_rect, "路径已复制") catch {};
        self.cx.requestRedraw();
    }
    fn cleanup(self: *View) void {
        for (&self.labels) |*arena| arena.deinit();
        if (self.retired) |*value| value.arena.deinit();
        if (self.pending) |*value| value.arena.deinit();
        if (self.frozen) |*value| value.arena.deinit();
    }
};
