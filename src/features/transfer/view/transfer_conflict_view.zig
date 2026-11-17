//! Frozen conflict decisions only. The host owns re-stat, authorization, IO,
//! pause and receipts. Selecting overwrite prepares its frozen target list;
//! only the confirmation button authorizes replacement.
//!
//! This file is the dialog's state (signals) and decisions. The view is
//! `transfer_conflict.yix`: zenit's native Modal / ScrollArea / RadioGroup /
//! Input / Checkbox / Alert / Tag / Button with their default appearance. The
//! view reads the signals below; user edits come back as proposals
//! (`choose`, `renamed`, `setApplyRemaining`, `openChanged`) and land here.
const std = @import("std");
const ui = @import("ui");
const shared_format = @import("../../../shared/base/format.zig");
const transfer = @import("../../../transfer/manager.zig");
pub const Conflict = transfer.Conflict;
pub const domain = @import("../../../transfer/conflict.zig");
const Name = @import("../../../host/directory_name.zig");
const S = @import("_transfer_conflict_styles.yss.zig");
const dialog_view = @import("_transfer_conflict.yix.zig");
const file_icons = @import("../../files/view/file_workspace_icons.zig");

pub const Callbacks = struct {
    context: *anyopaque,
    /// Request strings borrow the View until this callback returns.
    decision: *const fn (*anyopaque, Conflict.Request) anyerror!void,
    defer_conflict: *const fn (*anyopaque, domain.Key) anyerror!void,
};
const values = [_][]const u8{ "skip", "save_as", "keep_both", "overwrite" };
/// The four decisions as native RadioGroup options. Overwrite is the only
/// destructive one: what it leads to is its option description (the native
/// second line, also the option's accessibility description).
pub const options = [_]ui.widgets.checkbox.RadioOption{
    .{ .value = values[0], .label = "跳过", .test_id = "transfer.conflict.skip" },
    .{ .value = values[1], .label = "另存为", .test_id = "transfer.conflict.save_as" },
    .{ .value = values[2], .label = "双方保留", .test_id = "transfer.conflict.keep_both" },
    .{ .value = values[3], .label = "覆盖", .test_id = "transfer.conflict.overwrite", .description = "选择覆盖后查看目标文件，点击一次确认即可执行。" },
};
/// Declarative focus targets inside the dialog.
pub const focus_close = "transfer.conflict.close";
pub const focus_name = "transfer.conflict.name";

pub const Stage = enum { choice, context_required, confirmation };
/// Compare cards: the incoming file and the file already at the target.
pub const Side = enum { source, existing };
const CardState = struct {
    title: *ui.Signal([]const u8),
    place: *ui.Signal([]const u8),
    modified: *ui.Signal([]const u8),
    size: *ui.Signal([]const u8),
    icon: *ui.Signal(ui.SvgAsset),
    newer: *ui.Signal(bool),
    fn init(scope: *ui.Scope) !CardState {
        return .{
            .title = try scope.createText("", .{}),
            .place = try scope.createText("", .{}),
            .modified = try scope.createText("—", .{}),
            .size = try scope.createText("—", .{}),
            .icon = try scope.createSignal(ui.SvgAsset, ui.icons.file),
            .newer = try scope.createSignal(bool, false),
        };
    }
    fn set(self: CardState, title_: []const u8, path: []const u8, metadata_: ?domain.Metadata, other: ?domain.Metadata, newer: bool) void {
        self.title.set(title_);
        // Name · directory.
        var place_buffer: [1024]u8 = undefined;
        self.place.set(std.fmt.bufPrint(&place_buffer, "{s} · {s}", .{ std.fs.path.basename(path), std.fs.path.dirname(path) orelse "/" }) catch path);
        self.icon.set(file_icons.asset(std.fs.path.basename(path)));
        var time_buffer: [64]u8 = undefined;
        self.modified.set(timeText(&time_buffer, if (metadata_) |m| m.modified_at else null));
        var size_buffer: [96]u8 = undefined;
        self.size.set(compareSizeText(&size_buffer, if (metadata_) |m| m.size else null, if (other) |m| m.size else null));
        self.newer.set(newer);
    }
};

pub const View = struct {
    cx: *ui.Cx,
    callbacks: Callbacks,
    /// The dialog's place in the tree (a zero-size anchor; the native Modal
    /// presents through the window's overlay layer). The caller attaches it.
    root: *ui.Node,
    /// The dialog's content column (set when the view mounts): pointer and
    /// focus inside it belong to the conflict being shown.
    form: ?*ui.Node = null,
    open: *ui.Signal(bool),
    stage: *ui.Signal(Stage),
    selected: *ui.Signal(?[]const u8),
    rename: *ui.Signal([]const u8),
    apply_remaining: *ui.Signal(bool),
    disabled: *ui.Signal(bool),
    primary_disabled: *ui.Signal(bool),
    primary_label: *ui.Signal([]const u8),
    primary_variant: *ui.Signal(ui.widgets.ButtonVariant),
    title_text: *ui.Signal([]const u8),
    close_label: *ui.Signal([]const u8),
    caption_text: *ui.Signal([]const u8),
    target_text: *ui.Signal([]const u8),
    metadata_text: *ui.Signal([]const u8),
    hint_text: *ui.Signal([]const u8),
    issue_text: *ui.Signal([]const u8),
    confirm_heading: *ui.Signal([]const u8),
    confirm_message: *ui.Signal([]const u8),
    confirm_paths: *ui.Signal([]const u8),
    confirm_metadata: *ui.Signal([]const u8),
    cards: [2]CardState,
    /// Window size the dialog is fitted into (followed while visible).
    viewport: *ui.Signal(ui.Size),
    /// Body scroll offset: kept here so a new conflict starts at the top.
    scroll_y: *ui.Signal(f32),
    focus: *ui.Signal(ui.view.FocusRequest),
    source: ?Conflict.OwnedSnapshot = null,
    draft_key: ?domain.Key = null,
    source_metadata: ?domain.Metadata = null,
    visible: bool = false,
    pending: bool = false,
    failure: ?anyerror = null,

    /// The caller attaches `root` to its tree.
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, callbacks: Callbacks) !*View {
        const self = try cx.allocator.create(View);
        var registered = false;
        errdefer if (!registered) cx.allocator.destroy(self);
        self.* = .{
            .cx = cx,
            .callbacks = callbacks,
            .root = undefined,
            .open = try scope.createSignal(bool, false),
            .stage = try scope.createSignal(Stage, .choice),
            .selected = try scope.createSignal(?[]const u8, null),
            .rename = try scope.createText("", .{}),
            .apply_remaining = try scope.createSignal(bool, false),
            .disabled = try scope.createSignal(bool, true),
            .primary_disabled = try scope.createSignal(bool, true),
            .primary_label = try scope.createText("应用选择", .{}),
            .primary_variant = try scope.createSignal(ui.widgets.ButtonVariant, .primary),
            .title_text = try scope.createText("同名文件处理", .{}),
            .close_label = try scope.createText("暂不处理，暂停原任务", .{}),
            .caption_text = try scope.createText("", .{}),
            .target_text = try scope.createText("", .{}),
            .metadata_text = try scope.createText("", .{}),
            .hint_text = try scope.createText("", .{}),
            .issue_text = try scope.createText("", .{}),
            .confirm_heading = try scope.createText("", .{}),
            .confirm_message = try scope.createText("", .{}),
            .confirm_paths = try scope.createText("", .{}),
            .confirm_metadata = try scope.createText("", .{}),
            .cards = .{ try CardState.init(scope), try CardState.init(scope) },
            .viewport = try scope.createSignal(ui.Size, cx.viewport),
            .scroll_y = try scope.createSignal(f32, 0),
            .focus = try scope.createSignal(ui.view.FocusRequest, .{}),
        };
        try scope.onCleanup(View, self, cleanup);
        registered = true;
        self.root = try ui.view.render(scope, cx, dialog_view.ConflictDialog(.{ .view = self }));
        try cx.addAfterLayoutHook(self, afterLayout);
        return self;
    }

    /// Copies all borrowed paths before returning. Same-key polling preserves
    /// the editable draft. A new revision invalidates old pointer approval.
    pub fn show(self: *View, value: Conflict.Snapshot) !void {
        try validate(value);
        const next_key = keyOf(value);
        const current = if (self.source) |owned| owned.value else null;
        const same = if (current) |old| sameCapture(old, value) else false;
        if (current) |old| try rejectOld(old, value);
        if (current) |old| if (snapshotEqual(old, value)) {
            if (!self.visible) {
                self.visible = true;
                self.open.set(true);
                self.requestFocus(focus_close);
                try self.refresh();
            }
            return;
        };
        var owned = try Conflict.OwnedSnapshot.clone(self.cx.allocator, value);
        var consumed = false;
        errdefer if (!consumed) owned.deinit();
        const changed_stage = current == null or std.meta.activeTag(current.?.pending) != std.meta.activeTag(value.pending);
        const changed_ticket = current != null and current.?.pending == .overwrite_confirmation and value.pending == .overwrite_confirmation and !std.meta.eql(current.?.pending.overwrite_confirmation.ticket, value.pending.overwrite_confirmation.ticket);
        if (!same or changed_stage or changed_ticket) self.cancelOldInteraction();
        if (!same) {
            self.selected.set(null);
            self.rename.set("");
            self.apply_remaining.set(false);
            self.source_metadata = null;
            self.draft_key = next_key;
            self.failure = null;
            self.pending = false;
            self.requestFocus(focus_close);
            self.scroll_y.set(0);
        } else if (changed_stage or changed_ticket) {
            self.pending = false;
            self.failure = null;
        }
        switch (value.pending) {
            .choice => |prompt| {
                if (!same) {
                    self.selected.set(if (prompt.selection.choice) |selection| values[@backingInt(selection)] else null);
                    self.rename.set(prompt.selection.rename);
                    self.apply_remaining.set(prompt.selection.apply_to_remaining);
                }
                self.source_metadata = prompt.source_metadata;
                self.draft_key = prompt.key;
                if (prompt.issue != null or value.issue != null) self.pending = false;
            },
            .context_required => self.pending = false,
            .overwrite_confirmation => {},
        }
        if (self.source) |*old| old.deinit();
        self.source = owned;
        consumed = true;
        self.visible = true;
        self.open.set(true);
        try self.refresh();
        self.cx.requestRedraw();
    }
    pub fn hide(self: *View) void {
        self.cancelOldInteraction();
        self.visible = false;
        self.open.set(false);
        self.cx.requestRedraw();
    }
    pub fn isVisible(self: *const View) bool {
        return self.visible;
    }
    pub fn setError(self: *View, key: domain.Key, cause: anyerror) bool {
        const current = if (self.source) |owned| keyOf(owned.value) else return false;
        if (current == null or !std.meta.eql(current.?, key)) return false;
        self.failure = cause;
        self.pending = false;
        self.refresh() catch {};
        self.cx.requestRedraw();
        return true;
    }
    /// Follows the window while the dialog is up: the native Modal takes its
    /// width and height cap from `viewport`.
    fn afterLayout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        if (!self.visible or std.meta.eql(self.viewport.peek(), self.cx.viewport)) return .done;
        self.viewport.set(self.cx.viewport);
        return .needs_layout;
    }
    fn cleanup(self: *View) void {
        self.cx.removeAfterLayoutHook(self);
        if (self.source) |*source| source.deinit();
        self.cx.allocator.destroy(self);
    }
    fn requestFocus(self: *View, id: []const u8) void {
        self.focus.set(self.focus.peek().to(id));
    }
    /// A press or focus that began on the previous conflict must not land on
    /// the next one (an old pointer cannot approve a changed ticket).
    fn cancelOldInteraction(self: *View) void {
        const form = self.form orelse return;
        if (self.cx.pressed_node) |node| if (node == form or node.isDescendantOf(form)) self.cx.cancelPointerInteractions(.explicit);
        if (self.cx.focused_node) |node| if (node == form or node.isDescendantOf(form)) self.cx.clearFocus();
    }
    fn choice(self: *const View) ?domain.Choice {
        const selected_ = self.selected.peek() orelse return null;
        for (values, 0..) |value, index| if (std.mem.eql(u8, selected_, value)) return @fromBackingInt(@intCast(index));
        return null;
    }
    fn send(self: *View, request: Conflict.Request) void {
        self.callbacks.decision(self.callbacks.context, request) catch |err| {
            _ = self.setError(request.key(), err);
            return;
        };
        self.pending = true;
        self.failure = null;
        self.refresh() catch {};
    }
    /// Projects the frozen snapshot and the local draft onto the signals.
    fn refresh(self: *View) !void {
        const source = (self.source orelse return).value;
        const confirmation = source.pending == .overwrite_confirmation;
        const invalid_context = source.pending == .context_required;
        self.stage.set(if (confirmation) .confirmation else if (invalid_context) .context_required else .choice);
        const prompt_locked = source.pending == .choice and source.pending.choice.phase != .waiting;
        self.disabled.set(self.pending or invalid_context or prompt_locked);
        var invalid_name = false;
        if (self.choice() == .save_as) Name.validate(self.rename.peek()) catch {
            invalid_name = true;
        };
        self.primary_disabled.set(self.pending or invalid_context or prompt_locked or (!confirmation and (self.choice() == null or invalid_name)));
        var buffer: [8192]u8 = undefined;
        if (confirmation) {
            try self.projectConfirmation(source.pending.overwrite_confirmation);
        } else if (invalid_context) {
            const entry = source.pending.context_required;
            self.title_text.set("同名文件处理");
            self.caption_text.set("原连接身份不可用");
            self.target_text.set(try std.fmt.bufPrint(&buffer, "目标 {s}", .{entry.target_path}));
            self.metadata_text.set("任务仍在等待处理，当前不能批准文件写入。");
            self.hint_text.set("请从原传输任务重新打开处理。");
            self.primary_label.set("应用选择");
        } else {
            const prompt = source.pending.choice;
            self.title_text.set("同名文件处理");
            self.caption_text.set(try std.fmt.bufPrint(&buffer, "{s}冲突 · {s} · 会话#{d}", .{ if (prompt.direction == .upload) @as([]const u8, "上传") else "下载", std.fs.path.basename(prompt.target_path), @backingInt(prompt.key.original_owner.session_id) }));
            self.target_text.set(try std.fmt.bufPrint(&buffer, "目标 {s}", .{prompt.target_path}));
            const existing: ?domain.Metadata = if (prompt.target == .present) prompt.target.present.metadata else null;
            const pair = try metadataPair(self.cx.allocator, prompt.direction, prompt.source_metadata, existing);
            defer self.cx.allocator.free(pair);
            self.metadata_text.set(pair);
            const source_time = prompt.source_metadata.modified_at;
            const target_time = if (existing) |m| m.modified_at else null;
            const upload = prompt.direction == .upload;
            self.cards[0].set(if (upload) "上传的文件" else "下载的文件", prompt.source_path, prompt.source_metadata, existing, source_time != null and target_time != null and source_time.? > target_time.?);
            self.cards[1].set(if (upload) "服务器上的文件" else "本地已有的文件", prompt.target_path, existing, prompt.source_metadata, source_time != null and target_time != null and target_time.? > source_time.?);
            if (self.choice() == .keep_both and prompt.suggested_path != null) {
                self.hint_text.set(try std.fmt.bufPrint(&buffer, "将保留为 {s}", .{prompt.suggested_path.?}));
            } else self.hint_text.set(if (self.pending) "正在核对原目标…" else "");
            self.primary_label.set("应用选择");
        }
        self.primary_variant.set(if (confirmation) .danger else .primary);
        self.close_label.set(if (confirmation) "返回选择" else if (invalid_context) "关闭提示" else "暂不处理，暂停原任务");
        self.issue_text.set(self.issueText());
        self.cx.requestRedraw();
    }
    fn projectConfirmation(self: *View, confirmation: domain.Confirmation) !void {
        const remote = confirmation.direction == .upload;
        const first = confirmation.targets[0];
        var buffer: [8192]u8 = undefined;
        self.title_text.set(if (remote) "确认覆盖远程文件" else "确认覆盖本地文件");
        self.primary_label.set(if (remote) "覆盖远程文件" else "覆盖本地文件");
        self.confirm_heading.set(if (remote) "覆盖远程文件？" else try std.fmt.bufPrint(&buffer, "覆盖本地 {s}？", .{std.fs.path.basename(first.path)}));
        self.confirm_message.set(if (remote) "所列目标的现有文件将被替换。此操作无法撤销。" else "替换本地文件，操作不可撤销；返回保留冲突等待，不删除远程源。");
        var paths = std.Io.Writer.Allocating.init(self.cx.allocator);
        defer paths.deinit();
        if (remote) try paths.writer.print("上传 · 会话#{d}\n远程目标\n", .{@backingInt(confirmation.original_owner.session_id)});
        if (confirmation.targets.len > 1) try paths.writer.print("本次覆盖 {d} 个文件\n", .{confirmation.targets.len});
        for (confirmation.targets, 0..) |target_, index| {
            if (index != 0) try paths.writer.writeAll("\n");
            try paths.writer.writeAll(target_.path);
            if (confirmation.targets.len > 1) {
                const value = try metadataText(self.cx.allocator, target_.version.metadata);
                defer self.cx.allocator.free(value);
                try paths.writer.print("\n现有 {s}", .{value});
            }
        }
        self.confirm_paths.set(paths.writer.buffered());
        const from = try sizeText(self.cx.allocator, if (self.source_metadata) |value| value.size else null);
        defer self.cx.allocator.free(from);
        const to = try sizeText(self.cx.allocator, first.version.metadata.size);
        defer self.cx.allocator.free(to);
        const size = try std.fmt.allocPrint(self.cx.allocator, "{s} {s} → {s}现有 {s}", .{ if (remote) @as([]const u8, "本地") else "远程源", from, if (remote) @as([]const u8, "远程") else "本地", to });
        defer self.cx.allocator.free(size);
        self.confirm_metadata.set(try std.fmt.bufPrint(&buffer, "{s} · 会话#{d}", .{ size, @backingInt(confirmation.original_owner.session_id) }));
    }
    fn issueText(self: *const View) []const u8 {
        if (self.failure) |failure| return switch (failure) {
            error.InvalidName => "名称不能为空，不能为 . 或 ..，不能包含路径分隔符或 NUL。",
            error.StaleConflict, error.StaleConfirmation, error.StaleAttempt, error.UnknownJob, error.InvalidState => "原任务或目标已变化，请重新核对当前冲突。",
            error.AccessDenied, error.PermissionDenied => "没有目标文件的写入权限，原选择与名称已保留。",
            else => "操作未被接受，原选择与名称已保留，可重新处理。",
        };
        const source = self.source orelse return "";
        if (source.value.issue) |issue_| return switch (issue_) {
            .invalid_name => "文件名无效，输入已保留，请修改。",
            .invalid_decision => "原任务或目标已变化，请重新核对。",
            .permission_denied => "没有目标文件的写入权限。",
            .io => "无法核对目标文件，原选择与名称已保留。",
            .unsupported => "当前连接暂不支持此操作。",
        };
        if (source.value.pending == .choice) if (source.value.pending.choice.issue) |issue_| return switch (issue_) {
            .target_changed => "目标文件已变化，请重新选择处理方式。",
            .name_exists => "该名称已存在，请修改另存文件名。",
            .invalid_name => "文件名无效，输入已保留，请修改。",
            .io_failed => "无法核对目标文件，原选择与名称已保留。",
        };
        return "";
    }
};

// ---- What the view reads (reactive: each call subscribes to the signals it reads) ----
pub fn isOpen(view: *View) bool {
    return view.open.get();
}
pub fn dialogWidth(view: *View) f32 {
    return @min(S.dialog_width, @max(0, view.viewport.get().width - S.window_gutter));
}
pub fn dialogMaxHeight(view: *View) f32 {
    return @max(0, view.viewport.get().height - S.window_gutter);
}
/// Height left for the scrolling body once the header and footer are placed.
pub fn bodyMaxHeight(view: *View) f32 {
    return @max(0, dialogMaxHeight(view) - S.chrome_height);
}
pub fn focusRequest(view: *View) ui.view.FocusRequest {
    return view.focus.get();
}
pub fn scrollY(view: *View) f32 {
    return view.scroll_y.get();
}
pub fn title(view: *View) []const u8 {
    return view.title_text.get();
}
pub fn closeLabel(view: *View) []const u8 {
    return view.close_label.get();
}
pub fn headerIcon(view: *View) ui.SvgAsset {
    return if (view.stage.get() == .confirmation) ui.icons.triangle_alert else ui.icons.files;
}
pub fn choiceShown(view: *View) bool {
    return view.stage.get() != .confirmation;
}
pub fn confirmationShown(view: *View) bool {
    return view.stage.get() == .confirmation;
}
/// The four decisions and "apply to the rest": not offered when the original
/// connection identity is gone.
pub fn decisionShown(view: *View) bool {
    return view.stage.get() == .choice;
}
pub fn pauseShown(view: *View) bool {
    return view.stage.get() == .choice;
}
fn savingAs(view: *View) bool {
    const value = view.selected.get() orelse return false;
    return std.mem.eql(u8, value, values[@backingInt(domain.Choice.save_as)]);
}
pub fn renameShown(view: *View) bool {
    return view.stage.get() == .choice and savingAs(view);
}
/// Compare cards while choosing; the rename step needs the room for its field
/// and keeps the one-line summary, as does the missing-identity notice.
pub fn compareShown(view: *View) bool {
    return view.stage.get() == .choice and !savingAs(view);
}
pub fn summaryShown(view: *View) bool {
    return view.stage.get() != .confirmation and !compareShown(view);
}
pub fn caption(view: *View) []const u8 {
    return view.caption_text.get();
}
pub fn summaryTarget(view: *View) []const u8 {
    return view.target_text.get();
}
pub fn summaryMetadata(view: *View) []const u8 {
    return view.metadata_text.get();
}
pub fn hint(view: *View) []const u8 {
    return view.hint_text.get();
}
pub fn hintShown(view: *View) bool {
    return view.stage.get() != .confirmation and !savingAs(view) and view.hint_text.get().len != 0;
}
pub fn issue(view: *View) []const u8 {
    return view.issue_text.get();
}
pub fn issueShown(view: *View) bool {
    return view.issue_text.get().len != 0;
}
pub fn selected(view: *View) ?[]const u8 {
    return view.selected.get();
}
pub fn rename(view: *View) []const u8 {
    return view.rename.get();
}
pub fn applyRemaining(view: *View) bool {
    return view.apply_remaining.get();
}
pub fn locked(view: *View) bool {
    return view.disabled.get();
}
pub fn primaryDisabled(view: *View) bool {
    return view.primary_disabled.get();
}
pub fn primaryLabel(view: *View) []const u8 {
    return view.primary_label.get();
}
pub fn primaryVariant(view: *View) ui.widgets.ButtonVariant {
    return view.primary_variant.get();
}
pub fn confirmHeading(view: *View) []const u8 {
    return view.confirm_heading.get();
}
pub fn confirmMessage(view: *View) []const u8 {
    return view.confirm_message.get();
}
pub fn confirmPaths(view: *View) []const u8 {
    return view.confirm_paths.get();
}
pub fn confirmMetadata(view: *View) []const u8 {
    return view.confirm_metadata.get();
}
pub fn cardId(side: Side) []const u8 {
    return switch (side) {
        .source => "transfer.conflict.compare.source",
        .existing => "transfer.conflict.compare.target",
    };
}
pub fn cardTitle(view: *View, side: Side) []const u8 {
    return view.cards[@intFromEnum(side)].title.get();
}
pub fn cardPlace(view: *View, side: Side) []const u8 {
    return view.cards[@intFromEnum(side)].place.get();
}
pub fn cardModified(view: *View, side: Side) []const u8 {
    return view.cards[@intFromEnum(side)].modified.get();
}
pub fn cardSize(view: *View, side: Side) []const u8 {
    return view.cards[@intFromEnum(side)].size.get();
}
pub fn cardIcon(view: *View, side: Side) ui.SvgAsset {
    return view.cards[@intFromEnum(side)].icon.get();
}
pub fn cardNewer(view: *View, side: Side) bool {
    return view.cards[@intFromEnum(side)].newer.get();
}

// ---- What the view proposes ----
pub fn attach(view: *View, form: *ui.view.Ref(*ui.Node)) void {
    view.form = form.get();
}
/// The native Modal proposes closing (Esc, focus leaving through its own
/// dismissal): the conflict decides what closing means at this stage.
pub fn openChanged(view: *View, open_: bool) void {
    if (!open_ and view.visible) dismiss(view);
}
pub fn scrolled(view: *View, y: f32) void {
    view.scroll_y.set(y);
}
pub fn choose(view: *View, value: []const u8) void {
    if (!view.visible or view.pending) return;
    for (values) |known| if (std.mem.eql(u8, known, value)) view.selected.set(known);
    view.failure = null;
    view.refresh() catch {};
    if (view.choice() == .save_as) view.requestFocus(focus_name);
    if (view.choice() == .overwrite) submit(view);
}
pub fn renamed(view: *View, text: []const u8) void {
    if (!view.visible or view.pending) return;
    view.rename.set(text);
    view.failure = null;
    view.refresh() catch {};
}
pub fn setApplyRemaining(view: *View, on: bool) void {
    if (!view.visible or view.pending) return;
    view.apply_remaining.set(on);
    view.failure = null;
    view.refresh() catch {};
}
pub fn submitted(view: *View, _: []const u8) void {
    submit(view);
}
pub fn submit(view: *View) void {
    if (!view.visible or view.pending or view.primary_disabled.peek()) return;
    const source = view.source orelse return;
    const request: Conflict.Request = switch (source.value.pending) {
        .context_required => return,
        .choice => |prompt| blk: {
            const picked = view.choice() orelse return;
            if (picked == .save_as) Name.validate(view.rename.peek()) catch {
                view.failure = error.InvalidName;
                view.refresh() catch {};
                return;
            };
            break :blk .{ .select = .{ .key = prompt.key, .selection = .{ .choice = picked, .rename = view.rename.peek(), .apply_to_remaining = view.apply_remaining.peek() } } };
        },
        .overwrite_confirmation => |confirmation| .{ .confirm_overwrite = .{ .key = confirmation.targets[0].key, .ticket = confirmation.ticket } },
    };
    view.send(request);
}
pub fn returnToChoice(view: *View) void {
    if (!view.visible or view.pending) return;
    const source = view.source orelse return;
    const confirmation = switch (source.value.pending) {
        .overwrite_confirmation => |value| value,
        else => return,
    };
    view.send(.{ .return_to_choice = .{ .key = confirmation.targets[0].key, .ticket = confirmation.ticket } });
}
pub fn postpone(view: *View) void {
    if (!view.visible) return;
    const source = view.source orelse return;
    const prompt = switch (source.value.pending) {
        .choice => |value| value,
        else => return,
    };
    view.callbacks.defer_conflict(view.callbacks.context, prompt.key) catch |err| {
        _ = view.setError(prompt.key, err);
        return;
    };
    view.hide();
}
/// Close button and Esc: pause while choosing, go back from the overwrite
/// confirmation, just close the missing-identity notice.
pub fn dismiss(view: *View) void {
    const source = view.source orelse return;
    switch (source.value.pending) {
        .choice => postpone(view),
        .overwrite_confirmation => returnToChoice(view),
        .context_required => view.hide(),
    }
}

fn keyOf(snapshot: Conflict.Snapshot) ?domain.Key {
    return switch (snapshot.pending) {
        .choice => |value| value.key,
        .overwrite_confirmation => |value| if (value.targets.len != 0) value.targets[0].key else null,
        .context_required => null,
    };
}
fn sameCapture(a: Conflict.Snapshot, b: Conflict.Snapshot) bool {
    if (a.engine_job != b.engine_job or !std.meta.eql(a.context, b.context)) return false;
    const ak = keyOf(a);
    const bk = keyOf(b);
    if (ak != null or bk != null) return ak != null and bk != null and std.meta.eql(ak.?, bk.?);
    return a.pending.context_required.entry == b.pending.context_required.entry and a.pending.context_required.revision == b.pending.context_required.revision;
}
fn rejectOld(old: Conflict.Snapshot, next: Conflict.Snapshot) !void {
    const ak = keyOf(old) orelse return;
    const bk = keyOf(next) orelse return;
    if (ak.intent_id == bk.intent_id and ak.job == bk.job and std.meta.eql(ak.owner, bk.owner) and ak.original_owner.eql(bk.original_owner)) {
        if (bk.attempt < ak.attempt or (bk.attempt == ak.attempt and (bk.entry < ak.entry or (bk.entry == ak.entry and bk.revision < ak.revision)))) return error.StaleConflict;
    }
    if (std.meta.eql(ak, bk) and old.pending == .choice and next.pending == .choice) {
        const before = old.pending.choice;
        const after = next.pending.choice;
        if (!std.mem.eql(u8, before.source_path, after.source_path) or !std.mem.eql(u8, before.target_path, after.target_path) or !before.source_endpoint.eql(after.source_endpoint) or !before.target_endpoint.eql(after.target_endpoint) or !std.meta.eql(before.target, after.target)) return error.FrozenConflictChanged;
    }
    if (old.pending == .overwrite_confirmation and next.pending == .overwrite_confirmation and std.meta.eql(old.pending.overwrite_confirmation.ticket, next.pending.overwrite_confirmation.ticket) and !confirmationEqual(old.pending.overwrite_confirmation, next.pending.overwrite_confirmation)) return error.FrozenConflictChanged;
}
fn snapshotEqual(a_: Conflict.Snapshot, b: Conflict.Snapshot) bool {
    if (a_.engine_job != b.engine_job or !std.meta.eql(a_.context, b.context) or a_.issue != b.issue or std.meta.activeTag(a_.pending) != std.meta.activeTag(b.pending)) return false;
    return switch (a_.pending) {
        .choice => |left| blk: {
            const right = b.pending.choice;
            break :blk std.meta.eql(left.key, right.key) and left.direction == right.direction and left.source_endpoint.eql(right.source_endpoint) and left.target_endpoint.eql(right.target_endpoint) and std.mem.eql(u8, left.source_path, right.source_path) and std.mem.eql(u8, left.target_path, right.target_path) and std.meta.eql(left.source_metadata, right.source_metadata) and std.meta.eql(left.target, right.target) and left.selection.choice == right.selection.choice and left.selection.apply_to_remaining == right.selection.apply_to_remaining and std.mem.eql(u8, left.selection.rename, right.selection.rename) and optionalTextEqual(left.suggested_path, right.suggested_path) and left.phase == right.phase and left.issue == right.issue;
        },
        .context_required => |left| blk: {
            const right = b.pending.context_required;
            break :blk left.entry == right.entry and left.revision == right.revision and std.mem.eql(u8, left.source_path, right.source_path) and std.mem.eql(u8, left.target_path, right.target_path) and std.meta.eql(left.source_metadata, right.source_metadata) and std.meta.eql(left.target, right.target);
        },
        .overwrite_confirmation => |left| confirmationEqual(left, b.pending.overwrite_confirmation),
    };
}
fn confirmationEqual(a_: domain.Confirmation, b: domain.Confirmation) bool {
    if (!std.meta.eql(a_.ticket, b.ticket) or !a_.original_owner.eql(b.original_owner) or a_.direction != b.direction or !a_.endpoint.eql(b.endpoint) or a_.targets.len != b.targets.len) return false;
    for (a_.targets, b.targets) |left, right| if (!std.meta.eql(left.key, right.key) or !std.mem.eql(u8, left.path, right.path) or !std.meta.eql(left.version, right.version)) return false;
    return true;
}
fn optionalTextEqual(a_: ?[]const u8, b: ?[]const u8) bool {
    return if (a_) |left| if (b) |right| std.mem.eql(u8, left, right) else false else b == null;
}
fn validate(value: Conflict.Snapshot) !void {
    if (value.engine_job == 0) return error.InvalidConflictIdentity;
    const key = keyOf(value) orelse {
        if (value.pending != .context_required or value.pending.context_required.revision == 0) return error.InvalidConflictIdentity;
        return;
    };
    if (key.intent_id == 0 or key.job == 0 or key.attempt == 0 or key.revision == 0 or @backingInt(key.original_owner.session_id) == 0 or key.original_owner.generation == 0) return error.InvalidConflictIdentity;
    const context = value.context orelse return error.ConflictContextRequired;
    if (context.intent_id != key.intent_id or context.job != key.job or context.attempt != key.attempt or !context.original_owner.eql(key.original_owner) or !std.meta.eql(context.resource_owner, key.owner)) return error.ConflictOwnerMismatch;
    if (value.pending == .choice) {
        const prompt = value.pending.choice;
        if (!prompt.source_endpoint.eql(context.source_endpoint) or !prompt.target_endpoint.eql(context.target_endpoint)) return error.ConflictOwnerMismatch;
    }
    if (value.pending == .overwrite_confirmation) {
        const confirmation = value.pending.overwrite_confirmation;
        if (confirmation.ticket.id == 0 or confirmation.ticket.intent_id != key.intent_id or !std.meta.eql(confirmation.ticket.owner, key.owner) or !confirmation.original_owner.eql(key.original_owner) or !confirmation.endpoint.eql(context.target_endpoint)) return error.ConflictOwnerMismatch;
        for (confirmation.targets) |target| if (target.key.intent_id != key.intent_id or target.key.job != key.job or target.key.attempt != key.attempt or !std.meta.eql(target.key.owner, key.owner) or !target.key.original_owner.eql(key.original_owner)) return error.ConflictOwnerMismatch;
    }
}
fn metadataText(allocator: std.mem.Allocator, metadata: ?domain.Metadata) ![]u8 {
    const size = if (metadata) |m| m.size else null;
    const modified = if (metadata) |m| m.modified_at else null;
    var buffer = std.Io.Writer.Allocating.init(allocator);
    errdefer buffer.deinit();
    if (size) |n| {
        var size_buffer: [48]u8 = undefined;
        try buffer.writer.writeAll(shared_format.bytes(&size_buffer, n));
    } else try buffer.writer.writeAll("大小未知");
    if (modified) |seconds| {
        if (seconds <= 253402300799) {
            const epoch: std.time.epoch.EpochSeconds = .{ .secs = seconds };
            const yd = epoch.getEpochDay().calculateYearDay();
            const md = yd.calculateMonthDay();
            const day = epoch.getDaySeconds();
            try buffer.writer.print(" · {d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{ yd.year, @backingInt(md.month), md.day_index + 1, day.getHoursIntoDay(), day.getMinutesIntoHour(), day.getSecondsIntoMinute() });
        } else try buffer.writer.print(" · {d} s (UTC)", .{seconds});
    } else try buffer.writer.writeAll(" · 修改时间未知");
    return buffer.toOwnedSlice();
}
fn sizeText(allocator: std.mem.Allocator, value: ?u64) ![]u8 {
    const n = value orelse return allocator.dupe(u8, "大小未知");
    return shared_format.allocBytes(allocator, n);
}
fn metadataPair(allocator: std.mem.Allocator, direction: transfer.Direction, source: ?domain.Metadata, target: ?domain.Metadata) ![]u8 {
    const from = try metadataText(allocator, source);
    defer allocator.free(from);
    const to = try metadataText(allocator, target);
    defer allocator.free(to);
    return std.fmt.allocPrint(allocator, "来源 {s}{s} → 现有目标 {s}{s}", .{ if (direction == .upload) @as([]const u8, "本地 ") else "远程 ", from, if (direction == .upload) @as([]const u8, "远程 ") else "本地 ", to });
}
/// Compare card size: the shared rounded size; when both cards would read the same rounded text,
/// the exact byte count follows so the two files stay distinguishable (“1 MiB · 1048600 B”).
pub fn compareSizeText(buffer: []u8, size: ?u64, other: ?u64) []const u8 {
    const n = size orelse return "—";
    var mine: shared_format.Buffer = undefined;
    const text = shared_format.bytes(&mine, n);
    // Below 1024 B the rounded text already is the exact count.
    const m = (if (n < 1024) null else other) orelse return std.fmt.bufPrint(buffer, "{s}", .{text}) catch "—";
    var theirs: shared_format.Buffer = undefined;
    if (!std.mem.eql(u8, text, shared_format.bytes(&theirs, m))) return std.fmt.bufPrint(buffer, "{s}", .{text}) catch "—";
    return std.fmt.bufPrint(buffer, "{s} · {d} B", .{ text, n }) catch "—";
}

/// "YYYY-MM-DD HH:MM UTC", or "—" when the observation has no time.
fn timeText(buffer: []u8, modified: ?u64) []const u8 {
    const seconds = modified orelse return "—";
    if (seconds > 253402300799) return "—";
    const epoch: std.time.epoch.EpochSeconds = .{ .secs = seconds };
    const yd = epoch.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const day = epoch.getDaySeconds();
    return std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2} UTC", .{ yd.year, @backingInt(md.month), md.day_index + 1, day.getHoursIntoDay(), day.getMinutesIntoHour() }) catch "—";
}