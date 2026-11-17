//! Actual Cx hit testing and retained widgets; synthetic frozen conflict data,
//! no transport, filesystem writes or native window.
const std = @import("std");
const ui = @import("ui");
const mod = @import("../view/transfer_conflict_view.zig");
const Conflict = mod.Conflict;
const domain = mod.domain;
const identity = @import("../../../host/identity.zig");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
const a = std.testing.allocator;
const owner: identity.SessionHandle = .{ .session_id = @fromBackingInt(101), .generation = 9 };
const key_: domain.Key = .{ .intent_id = 501, .owner = .{ .session = owner }, .original_owner = owner, .entry = 0, .job = 42, .attempt = 1, .revision = 1 };
const local: domain.Endpoint = .{ .local_fs = .{ .binding_id = 12, .binding_generation = 3 } };
const remote: domain.Endpoint = .{ .sftp = .{ .binding_id = 13, .binding_generation = 4, .resource_owner = .{ .session = owner }, .origin_session = owner } };
const context: Conflict.Context = .{ .intent_id = 501, .job = 42, .attempt = 1, .original_owner = owner, .resource_owner = .{ .session = owner }, .source_endpoint = local, .target_endpoint = remote };
const source_metadata: domain.Metadata = .{ .kind = .file, .size = 128 * 1024 * 1024, .modified_at = 1760523480 };
const target_version: domain.TargetVersion = .{ .revision = 7, .metadata = .{ .kind = .file, .size = 124 * 1024 * 1024, .modified_at = 1760459520 } };
fn source() Conflict.Snapshot {
    return .{ .engine_job = 7, .context = context, .pending = .{ .choice = .{ .key = key_, .direction = .upload, .source_endpoint = local, .target_endpoint = remote, .source_path = "/local/release.tar.gz", .source_metadata = source_metadata, .target_path = "/srv/releases/release.tar.gz", .target = .{ .present = target_version }, .selection = .{}, .suggested_path = null, .phase = .waiting, .issue = null } } };
}
fn confirmation(direction: @import("../../../transfer/manager.zig").Direction, ticket: u64, targets: []const domain.OverwriteTarget) Conflict.Snapshot {
    var value = source();
    if (direction == .download) {
        value.context.?.source_endpoint = remote;
        value.context.?.target_endpoint = local;
    }
    value.pending = .{ .overwrite_confirmation = .{ .ticket = .{ .intent_id = 501, .owner = .{ .session = owner }, .id = ticket }, .original_owner = owner, .direction = direction, .endpoint = if (direction == .upload) remote else local, .targets = targets } };
    return value;
}
const Fixture = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    view: *mod.View,
    decisions: usize = 0,
    pauses: usize = 0,
    last: ?Conflict.Request = null,
    paused: ?domain.Key = null,
    name: [4096]u8 = undefined,
    reject: bool = false,
    fn init(self: *Fixture) !void {
        self.* = .{ .cx = try ui.Cx.init(a, std.testing.io), .scope = undefined, .view = undefined };
        self.cx.setViewport(860, 480);
        self.cx.root = try ui.box(self.cx, .{ .width = .fill(), .height = .fill() }, .{});
        try self.cx.setTestFrameStep(100);
        self.cx.setTheme(theme.widgetTheme(theme.currentName()));
        // Mount-time transitions read the published frame clock. Publish this
        // Cx's clock before mounting, rather than inheriting a previous test's.
        self.cx.layout();
        _ = self.cx.render();
        self.scope = try ui.Scope.init(a, null, self.cx.owner);
        self.view = try mod.View.mount(self.cx, self.scope, .{ .context = self, .decision = decision, .defer_conflict = pause });
        try self.cx.root.?.appendChild(a, self.view.root);
        try self.view.show(source());
        self.settle();
    }
    fn deinit(self: *Fixture) void {
        self.cx.clearFocus();
        self.scope.dispose();
        self.cx.deinit();
    }
    fn decision(raw: *anyopaque, request: Conflict.Request) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        if (self.reject) return error.PermissionDenied;
        self.decisions += 1;
        self.last = request;
        if (request == .select) {
            const name = request.select.selection.rename;
            @memcpy(self.name[0..name.len], name);
            self.last.?.select.selection.rename = self.name[0..name.len];
        }
    }
    fn pause(raw: *anyopaque, key: domain.Key) !void {
        const self: *Fixture = @ptrCast(@alignCast(raw));
        self.pauses += 1;
        self.paused = key;
    }
    fn settle(self: *Fixture) void {
        self.cx.setTestFrameStep(100) catch unreachable;
        for (0..4) |_| {
            self.cx.advanceFrameClock();
            self.cx.layout();
            _ = self.cx.render();
        }
    }
    /// The shown node with this test id (tests locate by id; the view itself never does).
    fn node(self: *Fixture, id: []const u8) *ui.Node {
        return findId(self.cx.root.?, id) orelse std.debug.panic("no visible node {s}", .{id});
    }
    fn shown(self: *Fixture, id: []const u8) bool {
        return findId(self.cx.root.?, id) != null;
    }
    fn text(self: *Fixture, id: []const u8) []const u8 {
        return self.node(id).getText().?.content;
    }
    fn press(self: *Fixture, id: []const u8) void {
        self.click(self.node(id));
    }
    fn click(self: *Fixture, target: *ui.Node) void {
        const rect = target.globalRect();
        self.cx.handleMouseDown(rect.x + rect.w / 2, rect.y + rect.h / 2, .{});
        self.cx.handleMouseUp(rect.x + rect.w / 2, rect.y + rect.h / 2);
        self.settle();
    }
};

fn findId(node: *ui.Node, id: []const u8) ?*ui.Node {
    if (node.style.display == .none) return null;
    if (node.meta.ownership.meta.test_id) |value| if (std.mem.eql(u8, value, id)) return node;
    for (node.children.items) |child| if (findId(child, id)) |found| return found;
    return null;
}
fn findText(node: *ui.Node, text: []const u8) ?*ui.Node {
    if (node.getText()) |value| if (std.mem.eql(u8, value.content, text)) return node;
    for (node.children.items) |child| if (findText(child, text)) |found| return found;
    return null;
}
const option_ids = [_][]const u8{ "transfer.conflict.skip", "transfer.conflict.save_as", "transfer.conflict.keep_both", "transfer.conflict.overwrite" };

test "transfer conflict view opens with native controls, no automatic selection or decision" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try std.testing.expect(f.view.isVisible());
    try std.testing.expect(f.view.selected.peek() == null);
    try std.testing.expect(f.view.primary_disabled.peek());
    // Native disabled primary Button.
    try std.testing.expect(f.node("transfer.conflict.apply").behavior.interaction.a11y.?.disabled);
    // 480 wide in a window that has the room; the height follows the content and stays in the window.
    const dialog = f.node("transfer.conflict").globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 480), dialog.w, 0.1);
    try std.testing.expect(dialog.y >= 0 and dialog.y + dialog.h <= 480);
    // Compare: uploaded vs existing file, modified time and size; the newer side carries the native Tag.
    const source_card = f.node("transfer.conflict.compare.source");
    const target_card = f.node("transfer.conflict.compare.target");
    try std.testing.expect(findText(source_card, "上传的文件") != null);
    try std.testing.expect(findText(target_card, "服务器上的文件") != null);
    try std.testing.expect(findText(source_card, "release.tar.gz · /local") != null);
    try std.testing.expect(findText(source_card, "128 MiB") != null);
    try std.testing.expect(findText(target_card, "124 MiB") != null);
    try std.testing.expect(findText(source_card, "2025-10-15 10:18 UTC") != null);
    try std.testing.expect(findId(source_card, "transfer.conflict.compare.newer") != null);
    try std.testing.expect(findId(target_card, "transfer.conflict.compare.newer") == null);
    // The four decisions are the native RadioGroup's own options: radio role, none checked, below the cards.
    const cards = f.node("transfer.conflict.compare").globalRect();
    for (option_ids) |id| {
        const row = f.node(id);
        try std.testing.expectEqual(ui.A11yRole.radio, row.behavior.interaction.a11y.?.role);
        try std.testing.expect(!row.behavior.interaction.a11y.?.checked.?);
        try std.testing.expect(cards.y + cards.h <= row.globalRect().y);
        try std.testing.expect(row.globalRect().w <= 440.1);
    }
    // Overwrite states its consequence through the native option description.
    try std.testing.expectEqualStrings("选择覆盖后查看目标文件，点击一次确认即可执行。", f.node(option_ids[3]).behavior.interaction.a11y.?.description.?);
    try std.testing.expect(f.node(option_ids[0]).behavior.interaction.a11y.?.description == null);
    // Opening puts focus on the close button.
    try std.testing.expect(f.cx.focused_node == f.node("transfer.conflict.close"));
    f.press("transfer.conflict.apply");
    try std.testing.expectEqual(@as(usize, 0), f.decisions);
    try std.testing.expectEqual(@as(usize, 0), f.pauses);
}

test "transfer conflict view keeps rename draft across choices and same key polling then sends exact request once" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try std.testing.expect(!f.shown("transfer.conflict.name"));
    f.press(option_ids[1]);
    try std.testing.expect(f.node(option_ids[1]).behavior.interaction.a11y.?.checked.?);
    try std.testing.expect(f.view.primary_disabled.peek());
    // Choosing "save as" shows the native Input and moves focus into it.
    try std.testing.expect(f.cx.focused_node == f.node("transfer.conflict.name"));
    f.cx.handleTextInput("release-v2.tar.gz");
    f.settle();
    try std.testing.expect(!f.view.primary_disabled.peek());
    try std.testing.expect(!f.node("transfer.conflict.apply").behavior.interaction.a11y.?.disabled);
    f.press(option_ids[0]);
    try std.testing.expect(!f.shown("transfer.conflict.name"));
    f.press(option_ids[2]);
    f.press(option_ids[1]);
    try f.view.show(source());
    f.settle();
    try std.testing.expectEqualStrings("release-v2.tar.gz", f.view.rename.peek());
    try std.testing.expectEqualStrings("save_as", f.view.selected.peek().?);
    try std.testing.expectEqual(@as(usize, 0), f.decisions);
    f.press("transfer.conflict.remaining");
    f.press("transfer.conflict.apply");
    try std.testing.expectEqual(@as(usize, 1), f.decisions);
    try std.testing.expect(std.meta.eql(key_, f.last.?.key()));
    try std.testing.expectEqual(domain.Choice.save_as, f.last.?.select.selection.choice.?);
    try std.testing.expectEqualStrings("release-v2.tar.gz", f.last.?.select.selection.rename);
    try std.testing.expect(f.last.?.select.selection.apply_to_remaining);
    try f.view.show(source());
    f.press("transfer.conflict.apply");
    try std.testing.expectEqual(@as(usize, 1), f.decisions);
}

test "transfer conflict view selecting overwrite prepares targets then one confirmation click approves the exact ticket" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.press("transfer.conflict.remaining");
    f.press(option_ids[3]);
    try std.testing.expectEqual(@as(usize, 1), f.decisions);
    try std.testing.expectEqual(domain.Choice.overwrite, f.last.?.select.selection.choice.?);
    try std.testing.expect(f.last.?.select.selection.apply_to_remaining);
    try std.testing.expect(f.view.pending);
    f.press("transfer.conflict.apply");
    try std.testing.expectEqual(@as(usize, 1), f.decisions);
    const targets = [_]domain.OverwriteTarget{.{ .key = key_, .path = "/srv/releases/release.tar.gz", .version = target_version }};
    try f.view.show(confirmation(.upload, 23, &targets));
    f.settle();
    // The confirmation is a native error Alert plus the frozen target list; the decisions are gone.
    try std.testing.expectEqualStrings("覆盖远程文件？", f.text("transfer.conflict.confirm.heading"));
    try std.testing.expectEqualStrings("所列目标的现有文件将被替换。此操作无法撤销。", f.text("transfer.conflict.confirm.detail"));
    try std.testing.expect(std.mem.indexOf(u8, f.text("transfer.conflict.confirm.paths"), "/srv/releases/release.tar.gz") != null);
    try std.testing.expect(!f.shown(option_ids[3]));
    try std.testing.expect(!f.shown("transfer.conflict.pause"));
    try std.testing.expect(findText(f.node("transfer.conflict.apply"), "覆盖远程文件") != null);
    f.press("transfer.conflict.apply");
    try std.testing.expectEqual(@as(usize, 2), f.decisions);
    try std.testing.expectEqual(@as(u64, 23), f.last.?.confirm_overwrite.ticket.id);
    try std.testing.expect(std.meta.eql(key_, f.last.?.key()));
    f.press("transfer.conflict.apply");
    try std.testing.expectEqual(@as(usize, 2), f.decisions);
}

test "transfer conflict view pause and overwrite return carry original key ticket without cancelling" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.press("transfer.conflict.close");
    try std.testing.expectEqual(@as(usize, 1), f.pauses);
    try std.testing.expect(std.meta.eql(key_, f.paused.?));
    try std.testing.expect(!f.view.isVisible());
    const targets = [_]domain.OverwriteTarget{.{ .key = key_, .path = "/srv/releases/release.tar.gz", .version = target_version }};
    try f.view.show(confirmation(.upload, 23, &targets));
    f.settle();
    try std.testing.expectApproxEqAbs(@as(f32, 480), f.node("transfer.conflict").globalRect().w, 0.1);
    f.press("transfer.conflict.back");
    try std.testing.expectEqual(@as(usize, 1), f.decisions);
    try std.testing.expectEqual(@as(u64, 23), f.last.?.return_to_choice.ticket.id);
    try std.testing.expect(std.meta.eql(key_, f.last.?.key()));
    try std.testing.expectEqual(@as(usize, 1), f.pauses);
}

test "transfer conflict view pause button defers the original key" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.press("transfer.conflict.pause");
    try std.testing.expectEqual(@as(usize, 1), f.pauses);
    try std.testing.expect(std.meta.eql(key_, f.paused.?));
    try std.testing.expectEqual(@as(usize, 0), f.decisions);
}

test "transfer conflict view rejects old revisions and old pointer cannot approve a changed ticket" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    var next = source();
    next.pending.choice.key.revision = 2;
    try f.view.show(next);
    try std.testing.expectError(error.StaleConflict, f.view.show(source()));
    const targets = [_]domain.OverwriteTarget{.{ .key = next.pending.choice.key, .path = "/srv/releases/release.tar.gz", .version = target_version }};
    try f.view.show(confirmation(.upload, 23, &targets));
    f.settle();
    const primary = f.node("transfer.conflict.apply").globalRect();
    f.cx.handleMouseDown(primary.x + primary.w / 2, primary.y + primary.h / 2, .{});
    try f.view.show(confirmation(.upload, 24, &targets));
    f.cx.handleMouseUp(primary.x + primary.w / 2, primary.y + primary.h / 2);
    f.settle();
    try std.testing.expectEqual(@as(usize, 0), f.decisions);
    f.press("transfer.conflict.apply");
    try std.testing.expectEqual(@as(usize, 1), f.decisions);
    try std.testing.expectEqual(@as(u64, 24), f.last.?.confirm_overwrite.ticket.id);
    try std.testing.expectEqual(@as(u64, 2), f.last.?.key().revision);
}

test "transfer conflict view local confirmation fits its content and long batch targets scroll above fixed actions" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    const targets = [_]domain.OverwriteTarget{.{ .key = key_, .path = "/local/release.tar.gz", .version = target_version }};
    try f.view.show(confirmation(.download, 33, &targets));
    f.settle();
    try std.testing.expectApproxEqAbs(@as(f32, 480), f.node("transfer.conflict").globalRect().w, 0.1);
    try std.testing.expectEqualStrings("覆盖本地 release.tar.gz？", f.text("transfer.conflict.confirm.heading"));
    try std.testing.expectEqualStrings("替换本地文件，操作不可撤销；返回保留冲突等待，不删除远程源。", f.text("transfer.conflict.confirm.detail"));
    // One target: nothing to scroll, the dialog is as tall as its content plus header and footer.
    const viewport = f.node("transfer.conflict.viewport").globalRect();
    const short = f.node("transfer.conflict").globalRect();
    try std.testing.expectApproxEqAbs(viewport.h + 116, short.h, 0.6);
    try std.testing.expect(short.h < 464);
    var batch: [20]domain.OverwriteTarget = undefined;
    for (&batch, 0..) |*target, index| {
        target.* = targets[0];
        target.key.entry = @intCast(index);
        target.path = "/local/full-untruncated-directory-name/release-complete-target-name.tar.gz";
    }
    try f.view.show(confirmation(.download, 34, &batch));
    f.settle();
    // Twenty targets overflow the body: the dialog stops at the window (8 around), the body scrolls, the actions stay put.
    const tall = f.node("transfer.conflict").globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 464), tall.h, 0.6);
    try std.testing.expect(f.node("transfer.conflict.confirm.paths").globalRect().h > f.node("transfer.conflict.viewport").globalRect().h);
    const footer = f.node("transfer.conflict.footer").globalRect();
    const button = f.node("transfer.conflict.apply").globalRect();
    try std.testing.expect(button.y >= footer.y and button.y + button.h <= footer.y + footer.h);
    try std.testing.expect(button.y + button.h <= 480);
    try std.testing.expect(std.mem.indexOf(u8, f.text("transfer.conflict.confirm.paths"), batch[19].path) != null);
    // A narrower, shorter window: the native Modal follows (width and height cap come from the window).
    f.cx.setViewport(400, 300);
    f.settle();
    const small = f.node("transfer.conflict").globalRect();
    try std.testing.expectApproxEqAbs(@as(f32, 384), small.w, 0.6);
    try std.testing.expectApproxEqAbs(@as(f32, 284), small.h, 0.6);
    f.cx.setViewport(860, 480);
    f.settle();
    f.cx.setFocus(f.node("transfer.conflict.back"));
    _ = f.cx.handleKeyDown(.escape, .{});
    try std.testing.expectEqual(@as(usize, 1), f.decisions);
    try std.testing.expectEqual(@as(u64, 34), f.last.?.return_to_choice.ticket.id);
    try std.testing.expectEqual(@as(usize, 0), f.pauses);
}

test "transfer conflict view IME composition in the rename field keeps Escape and Enter to the input method" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.press(option_ids[1]);
    try std.testing.expect(f.cx.focused_node == f.node("transfer.conflict.name"));
    f.cx.handleTextInput("report");
    f.cx.handleImePreedit("中文", 2);
    f.settle();
    // Composing: Escape belongs to the input method. The dialog stays, nothing is paused, the draft is kept.
    _ = f.cx.handleKeyDown(.escape, .{});
    f.settle();
    try std.testing.expect(f.view.isVisible());
    try std.testing.expectEqual(@as(usize, 0), f.pauses);
    try std.testing.expectEqualStrings("report", f.view.rename.peek());
    // Composing again: Enter commits the composition, it does not submit the decision.
    f.cx.handleImePreedit("终稿", 2);
    _ = f.cx.handleKeyDown(.@"return", .{});
    f.cx.handleImeCommit("终稿");
    f.settle();
    try std.testing.expectEqual(@as(usize, 0), f.decisions);
    try std.testing.expectEqualStrings("report终稿", f.view.rename.peek());
    // Switching the decision while composing keeps what was committed and hides the field.
    f.cx.handleImePreedit("草", 1);
    f.press(option_ids[0]);
    try std.testing.expect(!f.shown("transfer.conflict.name"));
    try std.testing.expectEqualStrings("skip", f.view.selected.peek().?);
    try std.testing.expect(std.mem.startsWith(u8, f.view.rename.peek(), "report终稿"));
    // Not composing: Escape is the dialog's (pause the original task).
    _ = f.cx.handleKeyDown(.escape, .{});
    f.settle();
    try std.testing.expectEqual(@as(usize, 1), f.pauses);
    try std.testing.expect(!f.view.isVisible());
}

test "transfer conflict view native controls follow a theme switch while open" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    f.press(option_ids[2]);
    const before = theme.currentName();
    defer {
        theme.select(before);
    }
    const other: theme.Name = if (before == .dark) .light else .dark;
    theme.select(other);
    f.cx.setTheme(theme.widgetTheme(other));
    f.settle();
    // Still open, selection and focus scope intact; text and surfaces resolve from the new theme's tokens.
    try std.testing.expect(f.view.isVisible());
    try std.testing.expect(f.node(option_ids[2]).behavior.interaction.a11y.?.checked.?);
    const tokens = f.cx.tokens.tokens.color;
    const caption = f.node("transfer.conflict.caption").resolveTextProps().?;
    try std.testing.expect(ui.Color.eql(tokens.fg_primary, caption.color));
    const card = f.node("transfer.conflict.compare.source");
    try std.testing.expect(ui.Color.eql(tokens.zw_island_rest, card.getBackground()));
}

test "transfer conflict view initialization is independent of a previous Cx frame clock" {
    const previous = try ui.Cx.init(a, std.testing.io);
    previous.root = try ui.box(previous, .{ .width = .fill(), .height = .fill() }, .{});
    try previous.setTestFrameStep(100);
    for (0..3) |_| {
        previous.requestRedraw();
        previous.advanceFrameClock();
        previous.layout();
        _ = previous.render();
    }
    previous.deinit();
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    try std.testing.expect(f.node("transfer.conflict.apply").behavior.interaction.a11y.?.disabled);
}

test "transfer conflict compare cards add exact bytes only when both rounded sizes read the same" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();
    // Default fixture: 128 MiB vs 124 MiB already differ; no byte counts.
    try std.testing.expect(findText(f.node("transfer.conflict.compare.source"), "128 MiB") != null);
    var close = source();
    close.pending.choice.key.entry = 1; // next queued entry: a new frozen conflict
    close.pending.choice.source_metadata.size = 1_048_600;
    close.pending.choice.target = .{ .present = .{ .revision = 8, .metadata = .{ .kind = .file, .size = 1_048_900, .modified_at = 1760459520 } } };
    try f.view.show(close);
    f.settle();
    try std.testing.expect(findText(f.node("transfer.conflict.compare.source"), "1 MiB · 1048600 B") != null);
    try std.testing.expect(findText(f.node("transfer.conflict.compare.target"), "1 MiB · 1048900 B") != null);
    var buffer: [96]u8 = undefined;
    try std.testing.expectEqualStrings("—", mod.compareSizeText(&buffer, null, 5));
    try std.testing.expectEqualStrings("5 B", mod.compareSizeText(&buffer, 5, null));
    try std.testing.expectEqualStrings("5 B", mod.compareSizeText(&buffer, 5, 5));
    try std.testing.expectEqualStrings("1 KiB · 1024 B", mod.compareSizeText(&buffer, 1024, 1030));
    // Different rounded texts need no byte counts; below 1024 B the text already is exact.
    try std.testing.expectEqualStrings("1 KiB", mod.compareSizeText(&buffer, 1024, 1000));
    try std.testing.expectEqualStrings("1023 B", mod.compareSizeText(&buffer, 1023, 1023));
    try std.testing.expectEqualStrings("1.5 MiB · 1572864 B", mod.compareSizeText(&buffer, 1024 * 1024 * 3 / 2, 1024 * 1024 * 3 / 2 + 7));
}
