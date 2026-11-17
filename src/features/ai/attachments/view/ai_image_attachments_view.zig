//! Image attachments (Pencil Kaf7E A10): up to four native W.AttachmentChip 44 × 44 tiles — the
//! thumbnail (image glyph until it is ready), the remove button over the corner, a native Tooltip
//! naming the file and its state — with explicit processing / error lifecycle (a failed image adds
//! a native ghost xs retry Button beside its tile).
const std = @import("std");
const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const App = @import("zenit_app").App;
const images = @import("../../../../ai/image_attachments.zig");
const S = @import("ai_attachments_styles.zig");
const panel_header = @import("../../../../shared/ui/components/panel_header/panel_header.zig");
pub const Callbacks = struct {
    context: *anyopaque,
    preview_sent: ?*const fn (*anyopaque, images.ContentRef) anyerror!void = null,
    remove: ?*const fn (*anyopaque, images.Ticket) anyerror!void = null,
    retry: ?*const fn (*anyopaque, images.Ticket) anyerror!void = null,
    visibility: ?*const fn (*anyopaque, bool) void = null,
    on_error: ?*const fn (*anyopaque, anyerror) void = null,
};
const Card = struct {
    view: *View,
    ticket: ?images.Ticket = null,
    /// The slot (test id ai.image): the tile's Tooltip wrapper, then the retry Button.
    root: *ui.Node = undefined,
    /// The tile's Tooltip wrapper (test id ai.image.filename: its hint is the file name).
    filename: *ui.Node = undefined,
    /// The native AttachmentChip tile (test id ai.image.preview; click opens the preview).
    preview: *ui.Node = undefined,
    retry_button: *ui.Node = undefined,
    /// The tile's remove button (native, inside the chip; test id ai.image.remove).
    /// File name (the tile's accessible name) and the hint "name · state".
    label: *ui.Signal([]const u8) = undefined,
    hint: *ui.Signal([]const u8) = undefined,
    thumbnail: *ui.Signal(?u32) = undefined,
    removable: *ui.Signal(bool) = undefined,
    hint_buffer: [320]u8 = undefined,
    reference: images.ContentRef = .{},
    problem: ?anyerror = null,
    texture: ?u32 = null,
    fn open(self: *Card) void {
        self.view.open(self) catch |err| self.view.fail(err);
    }
    fn remove(self: *Card) void {
        if (self.ticket) |ticket| if (self.view.callbacks.remove) |callback| callback(self.view.callbacks.context, ticket) catch |err| self.view.fail(err);
    }
    fn retry(self: *Card) void {
        if (self.ticket) |ticket| if (self.view.callbacks.retry) |callback| callback(self.view.callbacks.context, ticket) catch |err| self.view.fail(err);
    }
    fn release(self: *Card) void {
        self.reference.release();
        if (self.texture) |texture| if (self.view.app) |app| app.renderer.image_renderer.unloadTexture(texture);
        self.texture = null;
    }
};
pub const View = struct {
    /// Test-id namespace of the surface this view is mounted in (main assistant / child dialog).
    space: IdSpace,
    cx: *ui.Cx,
    scope: *ui.Scope,
    callbacks: Callbacks,
    app: ?*App = null,
    root: *ui.Node = undefined,
    rail: ui.widgets.scroll_area.ScrollAreaResult = undefined,
    detached_wrapper: ?*ui.Node = null,
    keep_button: *ui.Node = undefined,
    preview_remove: *ui.Node = undefined,
    raster: *ui.Node = undefined,
    cards: [4]*Card = undefined,
    count: usize = 0,
    panel: *ui.Node = undefined,
    metadata: *ui.Node = undefined,
    preview_image: *ui.Node = undefined,
    preview_texture: ?u32 = null,
    preview_reference: images.ContentRef = .{},
    preview_ticket: ?images.Ticket = null,
    readonly: bool = false,
    preview_content: ?*ui.Node = null,
    modal: ui.widgets.ModalResult = undefined,
    modal_open: *ui.Signal(bool) = undefined,
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, callbacks: Callbacks, preview_parent: *ui.Node) !*View {
        const space = IdSpace.of(scope);
        const self = try scope.createState(View, .{ .space = space, .cx = cx, .scope = scope, .callbacks = callbacks });
        try scope.onCleanup(View, self, release);
        self.root = try ui.boxStyled(cx, S.wrapper, .{});
        self.rail = try ui.widgets.ScrollArea(.{ .direction = .horizontal, .height = S.tile_height }).mount(scope, cx);
        self.rail.container.setStyleInline(cx.allocator, S.viewport());
        self.rail.content.setStyleInline(cx.allocator, S.rail());
        // Own rail (sent images under a message): the 44 tiles set its height.
        self.rail.container.setStyleInline(cx.allocator, .{ .height = .{ .px = S.tile_height } });
        self.rail.content.setStyleInline(cx.allocator, .{ .height = .{ .px = S.tile_height } });
        self.root.setStyleInline(cx.allocator, .{ .height = .{ .px = S.tile_height } });
        try self.root.appendChild(cx.allocator, self.rail.container);
        self.root.meta.ownership.meta.test_id = space.id("ai.images");
        self.root.setDisplay(.none);
        for (&self.cards) |*slot| {
            const card = try scope.createState(Card, .{ .view = self });
            slot.* = card;
            card.label = try scope.createText("", .{});
            card.hint = try scope.createText("", .{});
            card.thumbnail = try scope.createSignal(?u32, null);
            card.removable = try scope.createSignal(bool, true);
            card.root = try ui.box(cx, S.chipSlot(), .{});
            card.root.setStyleInline(cx.allocator, .{ .gap = 4 });
            card.root.meta.ownership.meta.test_id = space.id("ai.image");
            card.root.setDisplay(.none);
            try self.rail.content.appendChild(cx.allocator, card.root);
            card.preview = try ui.view.render(scope, cx, ui.widgets.AttachmentChip(.{
                .label = card.label,
                .icon_asset = ui.icons.image,
                .thumbnail = card.thumbnail,
                .tile = true,
                .removable = card.removable,
                .remove_label = "移除图片",
                .remove_test_id = space.id("ai.image.remove"),
                .on_click = cx.on(Card, card, Card.open),
                .on_remove = cx.on(Card, card, Card.remove),
            }));
            card.preview.meta.ownership.meta.test_id = space.id("ai.image.preview");
            const tip = try ui.widgets.Tooltip(.{ .text = card.hint, .position = .top }).mount(scope, cx);
            try tip.trigger.appendChild(cx.allocator, card.preview);
            card.filename = tip.wrapper;
            card.filename.meta.ownership.meta.test_id = space.id("ai.image.filename");
            try card.root.appendChild(cx.allocator, tip.wrapper);
            card.retry_button = try ui.widgets.Button(.{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = ui.icons.get("rotate-cw").?, .a11y_label = "重试附件", .on_click = cx.on(Card, card, Card.retry) }).mount(scope, cx);
            card.retry_button.meta.ownership.meta.test_id = space.id("ai.image.retry");
            card.retry_button.setDisplay(.none);
            try card.root.appendChild(cx.allocator, card.retry_button);
        }
        _ = preview_parent;
        self.modal_open = try scope.createSignal(bool, false);
        self.modal = try ui.widgets.Modal(.{ .open = self.modal_open, .width = 800, .max_height = cx.viewport.height, .enter_transition = .none, .exit_transition = .none, .on_open_change = cx.on(View, self, openChanged) }).mount(scope, cx);
        if (!self.modal.portaled) if (cx.root) |root| try root.appendChild(cx.allocator, self.modal.overlay);
        self.panel = self.modal.dialog;
        const P = @import("ai_image_preview_styles.zig");
        self.modal.body.setStyleInline(cx.allocator, P.body());
        try cx.addAfterLayoutHook(self, afterLayout);
        self.panel.meta.ownership.meta.test_id = space.id("ai.image.preview.panel");

        // Pencil O10: header (图片预览 · close) · image well · footer (source · 移除图片 · 保留图片).
        const heading = try ui.boxStyled(cx, P.header, .{});
        try self.modal.body.appendChild(cx.allocator, heading);
        const title = try ui.textStyled(cx, P.title, "图片预览");
        title.setStyleInline(cx.allocator, P.fill());
        try heading.appendChild(cx.allocator, title);
        // panel-heads：统一关闭按钮（预览 Modal 的 Esc 同样关闭）。
        try heading.appendChild(cx.allocator, try panel_header.mountClose(self.scope, cx, .{ .label = "关闭预览", .test_id = space.id("ai.image.preview.close"), .on_close = cx.on(View, self, dismiss) }));
        self.preview_image = try ui.boxStyled(cx, P.well, .{});
        self.preview_image.meta.ownership.meta.test_id = space.id("ai.image.preview.raster");
        try self.modal.body.appendChild(cx.allocator, self.preview_image);
        const footer = try ui.boxStyled(cx, P.footer, .{});
        try self.modal.body.appendChild(cx.allocator, footer);
        self.metadata = try ui.textStyled(cx, P.meta, "");
        self.metadata.setStyleInline(cx.allocator, P.fill());
        try footer.appendChild(cx.allocator, self.metadata);
        self.preview_remove = try ui.widgets.Button(.{ .label = "移除图片", .variant = .secondary, .size = .sm, .on_click = cx.on(View, self, removePreview) }).mount(scope, cx);
        self.preview_remove.meta.ownership.meta.test_id = space.id("ai.image.preview.remove");
        try footer.appendChild(cx.allocator, self.preview_remove);
        self.keep_button = try ui.widgets.Button(.{ .label = "保留图片", .variant = .primary, .size = .sm, .on_click = cx.on(View, self, dismiss) }).mount(scope, cx);
        self.keep_button.meta.ownership.meta.test_id = space.id("ai.image.preview.keep");
        try footer.appendChild(cx.allocator, self.keep_button);
        self.raster = try ui.box(cx, .{}, .{});
        try self.preview_image.appendChild(cx.allocator, self.raster);
        return self;
    }
    /// Place the existing image card group in the shared captured-text rail.
    /// The parent owns scrolling; image refs and callbacks keep their own scope.
    pub fn shareRail(self: *View, parent: *ui.Node) !void {
        const space = self.space;
        self.rail.container.removeChild(self.rail.content);
        self.detached_wrapper = self.root;
        self.root = self.rail.content;
        self.root.meta.ownership.meta.test_id = space.id("ai.images");
        try parent.appendChild(self.cx.allocator, self.root);
    }
    pub fn update(self: *View, draft: ?*const images.Draft) !void {
        const count = if (draft) |value| value.items.items.len else 0;
        self.count = count;
        for (self.cards, 0..) |card, index| {
            if (index >= count) {
                card.root.setDisplay(.none);
                card.ticket = null;
                card.release();
                continue;
            }
            const item = draft.?.items.items[index];
            card.problem = item.problem;
            try self.updateCard(card, item.ticket, item.path, item.state, item.reference);
        }
        self.root.setDisplay(if (count > 0) .flex else .none);
        if (self.preview_ticket) |ticket| {
            var found = false;
            if (draft) |value| for (value.items.items) |item| {
                if (item.ticket.eql(ticket)) found = true;
            };
            if (!found) self.dismiss();
        }
    }
    pub fn updateSent(self: *View, bundle: *const images.Bundle) !void {
        self.readonly = true;
        self.count = bundle.items.len;
        for (self.cards, 0..) |card, index| {
            if (index >= bundle.items.len) {
                card.root.setDisplay(.none);
                card.ticket = null;
                card.release();
                continue;
            }
            const item = bundle.items[index];
            card.problem = null;
            const content = item.reference.content() orelse return error.EmptyAttachmentResult;
            try self.updateCard(card, .{ .owner = bundle.owner, .conversation_id = bundle.conversation_id, .draft_epoch = bundle.draft_epoch, .id = item.id }, content.path, .ready, item.reference);
        }
        self.root.setDisplay(if (self.count > 0) .flex else .none);
    }
    fn updateCard(self: *View, card: *Card, ticket: images.Ticket, path: []const u8, state: images.State, reference: images.ContentRef) !void {
        card.ticket = ticket;
        card.root.setDisplay(.flex);
        const name = std.fs.path.basename(path);
        card.label.set(name);
        var buffer: [160]u8 = undefined;
        const text = if (reference.content()) |content| try std.fmt.bufPrint(&buffer, "{s} {d}×{d} · {d} B", .{ @tagName(content.mime), content.width, content.height, content.bytes.len }) else if (state == .processing) "图片处理中" else "读取失败 · 可重试";
        card.hint.set(std.fmt.bufPrint(&card.hint_buffer, "{s} · {s}", .{ name, text }) catch name);
        card.removable.set(!self.readonly);
        card.retry_button.setDisplay(if (!self.readonly and state == .failed) .flex else .none);
        // Keep resource ownership independent of mutable draft/remove callbacks.
        if (card.reference.snapshot != reference.snapshot) {
            card.release();
            card.thumbnail.set(null);
            card.reference = reference.retain();
            if (reference.content()) |content| if (self.app) |app| {
                card.texture = try app.renderer.image_renderer.loadTexture(content.width, content.height, content.pixels);
                // The tile shows the actual raster instead of its image glyph.
                card.thumbnail.set(card.texture.?);
            };
        }
    }
    fn open(self: *View, card: *Card) !void {
        if (card.reference.content() == null) return card.problem orelse error.ImageNotReady;
        if (self.readonly) if (self.callbacks.preview_sent) |callback| return callback(self.callbacks.context, card.reference);
        try self.openPreview(card.reference, if (self.readonly) null else card.ticket);
    }
    pub fn openSentPreview(self: *View, reference: images.ContentRef) !void {
        try self.openPreview(reference, null);
    }
    fn openPreview(self: *View, reference: images.ContentRef, ticket: ?images.Ticket) !void {
        const content = reference.content() orelse return;
        self.preview_reference.release();
        self.preview_reference = reference.retain();
        self.preview_ticket = ticket;
        self.preview_remove.setDisplay(if (ticket == null) .none else .flex);
        self.keep_button.setDisplay(if (ticket == null) .none else .flex);
        var buffer: [320]u8 = undefined;
        var size: [32]u8 = undefined;
        try self.metadata.setTextContent(self.cx.allocator, try std.fmt.bufPrint(&buffer, "本地 · {s} · {d}×{d} · {s}", .{ std.fs.path.basename(content.path), content.width, content.height, @import("../../../../shared/base/format.zig").bytes(&size, content.bytes.len) }));
        if (self.preview_texture) |texture| if (self.app) |app| app.renderer.image_renderer.unloadTexture(texture);
        self.preview_texture = null;
        if (self.app) |app| {
            self.preview_texture = try app.renderer.image_renderer.loadTexture(content.width, content.height, content.pixels);
            self.raster.setImage(.{ .texture_id = self.preview_texture.? });
        }
        self.modal_open.set(true);
        self.layoutPreview();
        if (self.callbacks.visibility) |callback| callback(self.callbacks.context, true);
        self.cx.requestRedraw();
    }
    fn removePreview(self: *View) void {
        const ticket = self.preview_ticket orelse return;
        if (self.callbacks.remove) |callback| callback(self.callbacks.context, ticket) catch |err| {
            self.fail(err);
            return;
        };
        self.dismiss();
    }
    pub fn height(self: *const View) f32 {
        return if (self.count > 0) S.tile_height + S.input_gap else 0;
    }
    pub fn isPreviewOpen(self: *const View) bool {
        return self.modal_open.peek();
    }
    pub fn dismiss(self: *View) void {
        if (!self.isPreviewOpen() and self.preview_reference.content() == null) return;
        self.modal_open.set(false);
        self.preview_ticket = null;
        self.preview_reference.release();
        self.raster.setImage(null);
        if (self.preview_texture) |texture| if (self.app) |app| app.renderer.image_renderer.unloadTexture(texture);
        self.preview_texture = null;
        if (self.callbacks.visibility) |callback| callback(self.callbacks.context, false);
    }
    pub fn escapePreview(self: *View) bool {
        if (!self.isPreviewOpen()) return false;
        self.dismiss();
        return true;
    }
    fn openChanged(self: *View, visible: bool) void {
        if (!visible) self.dismiss();
    }
    fn layoutPreview(self: *View) void {
        const rect = @import("ai_preview_geometry.zig").bounds(self.cx, self.preview_content);
        self.panel.setStyleInline(self.cx.allocator, @import("ai_preview_geometry.zig").panel(rect, true));
        const content = self.preview_reference.content() orelse return;
        const viewport = self.preview_image.globalRect();
        const P = @import("ai_image_preview_styles.zig");
        const w = @max(1, if (viewport.w > 0) @min(viewport.w, rect.w) else rect.w);
        const h = @max(1, if (viewport.h > 0) @min(viewport.h, rect.h - P.header_height - P.footer_height) else rect.h - P.header_height - P.footer_height);
        const scale = @min(w / @as(f32, @floatFromInt(content.width)), h / @as(f32, @floatFromInt(content.height)));
        self.raster.setStyleInline(self.cx.allocator, .{ .width = .{ .px = @as(f32, @floatFromInt(content.width)) * scale }, .height = .{ .px = @as(f32, @floatFromInt(content.height)) * scale }, .flex_shrink = 0 });
    }
    fn afterLayout(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        if (!self.isPreviewOpen()) return .done;
        self.layoutPreview();
        return .done;
    }
    fn fail(self: *View, err: anyerror) void {
        if (self.callbacks.on_error) |callback| callback(self.callbacks.context, err);
    }
    fn release(self: *View) void {
        if (self.detached_wrapper) |node| self.cx.destroyDetached(node);
        self.cx.removeAfterLayoutHook(self);
        for (self.cards) |card| card.release();
        self.preview_reference.release();
        if (self.preview_texture) |texture| if (self.app) |app| app.renderer.image_renderer.unloadTexture(texture);
    }
};
