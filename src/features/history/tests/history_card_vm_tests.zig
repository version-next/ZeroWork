//! 会话记录卡片 view-model 的单测（PL4b）：列表读目录、“查看”在卡片内加载详情（不新开 tab）、
//! 选中行回写、窄卡片二选一、Esc 的分层、加载中再选另一条被拒绝。
const std = @import("std");
const ui = @import("ui");
const archive_mod = @import("../../../vt/session_archive.zig");
const loading = @import("../model/history_archive.zig");
const card_vm = @import("../model/view_model.zig");
const detail_vm = @import("../detail/model/view_model.zig");
const card_type = @import("../model/card_type.zig");

const Fake = struct {
    tabs: usize = 0,
    closes: usize = 0,
    mounted: usize = 0,
    released: usize = 0,
    marker: u8 = 0,
    fn host(self: *Fake) card_vm.Host {
        return .{ .context = self, .open_as_tab = openAsTab, .close = close, .export_record = exportRecord, .mount_replay = mount, .release_replay = release };
    }
    fn openAsTab(raw: *anyopaque, _: *card_vm.CardVm) void {
        const self: *Fake = @ptrCast(@alignCast(raw));
        self.tabs += 1;
    }
    fn close(raw: *anyopaque, _: *card_vm.CardVm) void {
        const self: *Fake = @ptrCast(@alignCast(raw));
        self.closes += 1;
    }
    fn exportRecord(_: *anyopaque, _: archive_mod.Descriptor) anyerror!void {}
    fn mount(raw: *anyopaque, document: *loading.Document) anyerror!detail_vm.Replay {
        const self: *Fake = @ptrCast(@alignCast(raw));
        if (document.timeline.frames.items.len == 0) return error.EmptyRecording;
        self.mounted += 1;
        return .{ .handle = &self.marker };
    }
    fn release(raw: *anyopaque, _: detail_vm.Replay) void {
        const self: *Fake = @ptrCast(@alignCast(raw));
        self.released += 1;
    }
};

fn seed(dir: std.Io.Dir, archive: *archive_mod.Archive) !void {
    try dir.createDirPath(std.testing.io, "logs/history");
    const bytes = "{\"version\":2,\"width\":12,\"height\":2}\n[0,\"o\",\"真实内容\\r\\n\"]\n";
    for ([_][]const u8{ "logs/history/a.cast", "logs/history/b.cast" }) |path| {
        const file = try dir.createFile(std.testing.io, path, .{});
        try file.writeStreamingAll(std.testing.io, bytes);
        file.close(std.testing.io);
    }
    try archive.append(.{ .id = 1, .started_ms = 1, .ended_ms = 2, .duration_ms = 1, .host = "alpha", .user = "u", .cast_path = "logs/history/a.cast", .source_kind = .local });
    try archive.append(.{ .id = 2, .started_ms = 3, .ended_ms = 4, .duration_ms = 1, .host = "beta", .user = "u", .cast_path = "logs/history/b.cast", .source_kind = .ssh, .saved_connection_id = 7 });
}

fn pump(vm: *card_vm.CardVm, done: *const fn (*card_vm.CardVm) bool) !void {
    var tries: usize = 0;
    while (!done(vm)) : (tries += 1) {
        if (tries > 2000) return error.Timeout;
        vm.poll();
        std.Io.sleep(std.testing.io, .fromNanoseconds(2 * std.time.ns_per_ms), .awake) catch {};
    }
}
fn listed(vm: *card_vm.CardVm) bool {
    return vm.list.records().len == 2;
}
fn ready(vm: *card_vm.CardVm) bool {
    return vm.detail.currentPhase() == .ready;
}

test "history card: View selects inside the card, the list marks it and the detail holds the replay" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var archive: archive_mod.Archive = .{ .allocator = a, .io = std.testing.io, .dir = tmp.dir };
    try seed(tmp.dir, &archive);
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(a, null, cx.owner);
    var fake: Fake = .{};
    {
        defer scope.dispose();
        const vm = try card_vm.CardVm.init(scope, a, &archive, fake.host(), .float);
        vm.show(null);
        try pump(vm, listed);
        try std.testing.expectEqualStrings("2 条", vm.list.countText());
        // 新的在前：第一行是 beta。
        try std.testing.expectEqualStrings("beta", vm.list.records()[0].title);
        try std.testing.expect(!vm.list.records()[0].selected);
        try std.testing.expectEqual(detail_vm.Phase.empty, vm.detail.currentPhase());
        vm.list.view(0);
        try std.testing.expectEqual(detail_vm.Phase.loading, vm.detail.currentPhase());
        // 加载中再查看另一条：沿用原目录浮层的“正在加载其他历史记录”。
        vm.list.view(1);
        try std.testing.expect(vm.list.messageShown() and vm.list.warning());
        try pump(vm, ready);
        try std.testing.expectEqual(@as(usize, 1), fake.mounted);
        try std.testing.expectEqualStrings("beta", vm.detail.recordTitle());
        vm.poll();
        try std.testing.expect(vm.list.records()[0].selected and !vm.list.records()[1].selected);
        try std.testing.expect(fake.tabs == 0);
        // 再查看已显示的那条：不重复加载。
        vm.list.view(0);
        try std.testing.expect(!vm.detail.isLoading());
        // 换一条：旧的回放表面释放、新的挂上。
        vm.list.clearMessage();
        vm.list.view(1);
        try pump(vm, struct {
            fn f(card: *card_vm.CardVm) bool {
                return !card.detail.isLoading();
            }
        }.f);
        try std.testing.expectEqual(@as(usize, 2), fake.mounted);
        try std.testing.expectEqual(@as(usize, 1), fake.released);
        try std.testing.expectEqualStrings("alpha", vm.detail.recordTitle());
        vm.poll();
        try std.testing.expect(vm.list.records()[1].selected and !vm.list.records()[0].selected);
    }
    // 卡片关闭（作用域释放）时回放表面一并释放。
    try std.testing.expectEqual(@as(usize, 2), fake.released);
}

test "history card: narrow width switches list and detail, Esc is layered and a tab card does not close on Esc" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var archive: archive_mod.Archive = .{ .allocator = a, .io = std.testing.io, .dir = tmp.dir };
    try seed(tmp.dir, &archive);
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    var fake: Fake = .{};
    const vm = try card_vm.CardVm.init(scope, a, &archive, fake.host(), .float);
    vm.show(null);
    try pump(vm, listed);
    vm.setWidth(820);
    try std.testing.expectEqual(card_vm.Layout.split, vm.currentLayout());
    vm.setWidth(card_type.split_min_width - 1);
    try std.testing.expectEqual(card_vm.Layout.list_only, vm.currentLayout());
    vm.list.view(0);
    try pump(vm, ready);
    try std.testing.expectEqual(card_vm.Layout.detail_only, vm.currentLayout());
    try std.testing.expect(vm.backShown() and !vm.listShown());
    vm.back();
    try std.testing.expectEqual(card_vm.Layout.list_only, vm.currentLayout());
    // Esc：卡片本身不归视图模型关（通用浮动层按卡片规则关闭，见 float_layer_tests）。
    try std.testing.expect(!vm.escape());
    try std.testing.expectEqual(@as(usize, 0), fake.closes);
    // 作为 tab：Esc 不关卡片，“作为 tab 打开”不再可用。
    vm.openAsTab();
    try std.testing.expectEqual(@as(usize, 1), fake.tabs);
    vm.setPlacement(.tab);
    try std.testing.expect(!vm.escape());
    vm.openAsTab();
    try std.testing.expectEqual(@as(usize, 1), fake.tabs);
}

test "history card: source filter from the host menu and type filters narrow the catalogue" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var archive: archive_mod.Archive = .{ .allocator = a, .io = std.testing.io, .dir = tmp.dir };
    try seed(tmp.dir, &archive);
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    var fake: Fake = .{};
    const vm = try card_vm.CardVm.init(scope, a, &archive, fake.host(), .float);
    vm.show(.{ .saved_connection = 7 });
    try pump(vm, struct {
        fn f(card: *card_vm.CardVm) bool {
            return card.list.loaded and !card.list.isLoading();
        }
    }.f);
    vm.poll();
    try std.testing.expectEqual(@as(usize, 1), vm.list.records().len);
    vm.show(null);
    try pump(vm, listed);
    vm.list.setFilter(.local);
    vm.poll();
    try std.testing.expectEqual(@as(usize, 1), vm.list.records().len);
    try std.testing.expectEqualStrings("alpha", vm.list.records()[0].title);
    vm.list.setQuery("zzz");
    vm.poll();
    try std.testing.expectEqual(@as(usize, 0), vm.list.records().len);
    try std.testing.expectEqualStrings("没有匹配的历史会话", vm.list.emptyTitle());
}

test "history limit messages are derived from the real byte limits" {
    try std.testing.expectEqualStrings("历史记录超过 128 MiB 读取或解码上限", loading.errorText(error.HistoryRecordingTooLarge));
    try std.testing.expectEqualStrings("历史索引超过 16 MiB 上限，无法读取", loading.errorText(error.HistoryIndexTooLarge));
    try std.testing.expectEqualStrings("已打开记录达到 256 MiB 预算，请先关闭一条历史记录", loading.errorText(error.HistoryDecodedBudgetExceeded));
    try std.testing.expectEqualStrings("历史目录元信息超过 16 MiB 或 16384 条上限", loading.errorText(error.CatalogLimit));
}

const confirm_ui = @import("../../../shared/ui/confirm/confirm.zig");
const ToastProbe = struct {
    posted: std.ArrayList(u64) = .empty,
    texts: [4][64]u8 = undefined,
    text_len: [4]usize = .{ 0, 0, 0, 0 },
    next: u64 = 10,
    fn post(raw: *anyopaque, value: []const u8) anyerror!u64 {
        const self: *ToastProbe = @ptrCast(@alignCast(raw));
        const i = self.posted.items.len % 4;
        @memcpy(self.texts[i][0..value.len], value);
        self.text_len[i] = value.len;
        self.next += 1;
        try self.posted.append(std.testing.allocator, self.next);
        return self.next;
    }
    fn textAt(self: *const ToastProbe, i: usize) []const u8 {
        return self.texts[i % 4][0..self.text_len[i % 4]];
    }
};
fn one(vm: *card_vm.CardVm) bool {
    return vm.list.records().len == 1 and !vm.list.isLoading() and vm.list.delete_job == null;
}

test "history card: deleting is undoable — the row hides at once, 撤销 brings it back, the toast leaving deletes the files" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var archive: archive_mod.Archive = .{ .allocator = a, .io = std.testing.io, .dir = tmp.dir };
    try seed(tmp.dir, &archive);
    const cx = try ui.Cx.init(a, std.testing.io);
    defer cx.deinit();
    var toasts: ToastProbe = .{};
    defer toasts.posted.deinit(a);
    confirm_ui.install(cx, .{ .context = &toasts, .post = ToastProbe.post });
    defer confirm_ui.uninstall(cx);
    const scope = try ui.Scope.init(a, null, cx.owner);
    defer scope.dispose();
    var fake: Fake = .{};
    const vm = try card_vm.CardVm.init(scope, a, &archive, fake.host(), .float);
    vm.list.undo = confirm_ui.port(cx);
    vm.show(null);
    try pump(vm, listed);
    // Delete the first row (beta): it disappears right away, nothing is deleted yet.
    vm.list.requestRowDelete(0);
    vm.poll();
    try std.testing.expectEqual(@as(usize, 1), vm.list.records().len);
    try std.testing.expectEqualStrings("alpha", vm.list.records()[0].title);
    try std.testing.expectEqualStrings("1 条", vm.list.countText());
    try std.testing.expectEqualStrings("已删除会话记录", toasts.textAt(0));
    try std.testing.expectEqual(@as(usize, 1), vm.list.undoPending());
    try std.testing.expect(vm.list.delete_job == null);
    // 撤销: the row is back, no job ever ran.
    confirm_ui.settle(cx, toasts.posted.items[0], .revert);
    vm.poll();
    try std.testing.expectEqual(@as(usize, 2), vm.list.records().len);
    try std.testing.expectEqual(@as(usize, 0), vm.list.undoPending());
    var reread = try archive.loadCatalog(a);
    try std.testing.expectEqual(@as(usize, 2), reread.entries.items.len);
    reread.deinit();
    // Delete again and let the toast expire: now the record and its recording are deleted.
    vm.list.requestRowDelete(0);
    confirm_ui.settle(cx, toasts.posted.items[1], .commit);
    try pump(vm, one);
    try std.testing.expectEqualStrings("alpha", vm.list.records()[0].title);
    reread = try archive.loadCatalog(a);
    defer reread.deinit();
    try std.testing.expectEqual(@as(usize, 1), reread.entries.items.len);
    try std.testing.expectEqualStrings("alpha", reread.entries.items[0].entry.host);
    // Clear the list: one toast for all of them.
    vm.list.requestClear();
    vm.poll();
    try std.testing.expectEqual(@as(usize, 0), vm.list.records().len);
    try std.testing.expectEqualStrings("已清空会话记录（1 条）", toasts.textAt(2));
    confirm_ui.settle(cx, toasts.posted.items[2], .revert);
    vm.poll();
    try std.testing.expectEqual(@as(usize, 1), vm.list.records().len);
}
