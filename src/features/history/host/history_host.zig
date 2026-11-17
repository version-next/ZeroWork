//! 窗口级会话记录宿主（PLUGIN_ARCH_PLAN 2.5.4、2.5.7、5.2 PL4b）。
//!
//! 持有本窗口的记录目录（`logs/history`），承载本窗口全部 `history` 卡片实例。每张卡片是一个
//! `CardVm`（列表 + 详情）加一棵 `history_card.yix` 视图；放置由这里决定：
//! - **浮动**（默认）：经通用卡片浮动层 `FloatLayer` 承载，可枚举交互（拖动、八向缩放、最大化、置顶、
//!   关闭、切 tab 收回 / 展开、记住位置）与首开位置由卡片类型的 `Descriptor` 声明（`model/card_type.zig`）。
//!   卡片属于打开它时的当前 tab（没有 tab 时属于窗口本身，不参与收回）；**每个 tab 最多一张浮动的
//!   会话记录卡片**（Q15 / Q21）：当前 tab 已有时再从入口打开只把它带到前台并按入口重置筛选。
//! - **独立 tab**：卡片头“作为 tab 打开”把同一张卡片（同一个 view-model 与视图节点）挪进一个新 tab，
//!   筛选、搜索词、滚动位置、选中记录与回放位置都保留；可以同时开多张 tab。
//! - **不进分屏**（Q11）：卡片类型 `split = false`，workspace 的入组判定读约束拒绝，拖到分屏落点时提示。
//!
//! 身份：每个实例由 `card_types.CardSlots` 分配带代次的 `CardId`，tab 的 owner 是 `.card`。
//! 入口：标题栏“回看日志”（含“⋯”菜单）与侧栏主机右键“查看历史会话日志”（按主机筛选）都调 `open`。
//! 没有全局快捷键入口（代码里没有）；终端里的 `@log` / “打开只读历史页”是终端卡片自己的状态（Q14），不在这里。
const std = @import("std");
const ui = @import("ui");
const identity = @import("../../../host/identity.zig");
const card_types = @import("../../../host/card_types.zig");
const archive_mod = @import("../../../vt/session_archive.zig");
const loading = @import("../model/history_archive.zig");
const catalog = @import("../model/history_list.zig");
const card_vm = @import("../model/view_model.zig");
const detail_vm = @import("../detail/model/view_model.zig");
const card_type = @import("../model/card_type.zig");
const ids = @import("../model/ids.zig");
const template = @import("../view/_history_card.yix.zig");
const float_layer = @import("../../../shared/ui/float_card/float_layer.zig");
const float_chrome = @import("../../../shared/ui/float_card/float_chrome.zig");
const float_card = @import("../../../shared/base/float_card.zig");
const floating_input = @import("../../../shared/ui/components/floating_input/floating_input.zig");
const Workspace = @import("../../workspace/view/workspace.zig").Workspace;
const ReplaySurface = @import("../../terminal/mod.zig").ReplaySurface;

pub const SourceFilter = catalog.SourceFilter;

pub const Host = struct {
    allocator: std.mem.Allocator,
    cx: *ui.Cx,
    scope: *ui.Scope,
    workspace: *Workspace,
    layer: *float_layer.FloatLayer,
    /// 卡片类型（已发布注册表里的 `history`，未登记时用内置声明）。
    definition: *const card_types.CardTypeDef,
    archive: archive_mod.Archive,
    archive_dir_owned: bool = true,
    slots: card_types.CardSlots = .{},
    instances: std.ArrayList(*Instance) = .empty,
    /// 入口按钮（标题栏“回看日志”）：打开时没有焦点就把焦点还给它（OverlayHost `card`）。
    entry_button: ?*ui.Node = null,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, directory: []const u8, workspace: *Workspace, layer: *float_layer.FloatLayer) !*Host {
        try std.Io.Dir.cwd().createDirPath(cx.io, directory);
        const dir = try std.Io.Dir.cwd().openDir(cx.io, directory, .{});
        errdefer dir.close(cx.io);
        const self = try cx.allocator.create(Host);
        errdefer cx.allocator.destroy(self);
        self.* = .{
            .allocator = cx.allocator,
            .cx = cx,
            .scope = scope,
            .workspace = workspace,
            .layer = layer,
            .definition = workspace.plugins.cardType(card_types.ids.history) orelse &card_type.def,
            .archive = .{ .allocator = cx.allocator, .io = cx.io, .dir = dir },
        };
        workspace.card_tab_port = .{ .context = self, .closed = cardTabClosed };
        try cx.addAfterLayoutHook(self, frame);
        try scope.onCleanup(Host, self, cleanup);
        return self;
    }

    // ── 入口 ──

    /// 从入口打开会话记录卡片（浮动）。当前 tab 已有浮动卡片（或窗口级的那张）时只把它带到前台，
    /// 并按入口重新读取目录、重置筛选（`source` 为侧栏主机的来源筛选，标题栏入口为 null）。
    pub fn open(self: *Host, source: ?SourceFilter) !void {
        self.cx.dispatcher.cancelScrollGesture();
        const current = self.currentTabId();
        for (self.instances.items) |instance| {
            if (instance.state != .live or instance.placement != .float) continue;
            const owner = instance.owner_tab;
            if (owner != null and current != null and owner.? != current.?) continue;
            if (owner != null and current == null) continue;
            instance.vm.show(source);
            if (instance.float) |float| self.layer.raise(float.card);
            self.cx.requestRedraw();
            return;
        }
        const instance = try self.createInstance(current);
        // 浮动卡片的焦点规则（OverlayHost `card`）：记下打开时的焦点，关闭时还回去。
        if (instance.float) |float| float.card.focusOpened(self.entry_button);
        instance.vm.show(source);
        self.cx.requestRedraw();
    }

    /// tab 菜单“导出会话记录”：导出这张卡片详情区正在显示的记录（原归档 tab 的导出）。
    pub fn exportShown(self: *Host, card: identity.CardId) !void {
        const instance = self.find(card) orelse return error.StaleCard;
        const detail = instance.vm.detail;
        const document = detail.document orelse return error.RecordingUnavailable;
        const descriptor = document.record.descriptor;
        try self.exportRecord(descriptor);
    }

    // ── 实例 ──

    fn createInstance(self: *Host, owner: ?u64) !*Instance {
        try self.instances.ensureUnusedCapacity(self.allocator, 1);
        const id = try self.slots.allocate(self.allocator);
        errdefer self.slots.release(self.allocator, id);
        const instance = try self.allocator.create(Instance);
        errdefer self.allocator.destroy(instance);
        const scope = try self.scope.childScope();
        errdefer scope.dispose();
        instance.* = .{ .host = self, .id = id, .scope = scope, .vm = undefined, .owner_tab = owner };
        // Registered first, so it runs last when the scope goes: after the view model's own cleanup (CardVm /
        // DetailVm: background job, replay surface). The instance's teardown is tied to its scope's lifetime, which
        // ends either through `destroy` (the card closes) or because the host scope is disposed with the window —
        // a child scope is disposed before its parent's cleanups run, so Host.cleanup can no longer reach it.
        try scope.onCleanup(Instance, instance, Instance.scopeEnded);
        instance.vm = try card_vm.CardVm.init(scope, self.allocator, &self.archive, .{
            .context = instance,
            .open_as_tab = Instance.requestTab,
            .close = Instance.requestClose,
            .export_record = Instance.exportRecord,
            .mount_replay = Instance.mountReplay,
            .release_replay = Instance.releaseReplay,
        }, .float);
        // 删除与清空走本窗口的撤销账本（`shared/ui/confirm` 的 `undoable`）。
        instance.vm.list.undo = @import("../../../shared/ui/confirm/confirm.zig").port(self.cx);
        instance.root = try ui.view.render(scope, self.cx, template.HistoryCard(.{ .vm = instance.vm, .slots = &instance.slots }));
        try instance.float_(self);
        self.instances.appendAssumeCapacity(instance);
        instance.adopted = true;
        return instance;
    }

    fn find(self: *Host, card: identity.CardId) ?*Instance {
        for (self.instances.items) |instance| if (instance.id.eql(card) and instance.state == .live) return instance;
        return null;
    }

    /// 当前 tab（顶部 tab 条上的 id；会话组视图时是组的 tab），没有 tab 时为 null。
    fn currentTabId(self: *Host) ?u64 {
        const workspace = self.workspace;
        if (workspace.active_group_view) |group| return if (workspace.groupTabId(group)) |tab| @backingInt(tab) else null;
        const index = workspace.active_tab orelse return null;
        return if (index < workspace.tabs.items.len) @backingInt(workspace.tabs.items[index].tab_id) else null;
    }

    fn tabExists(self: *Host, tab: u64) bool {
        return self.workspace.model.indexOf(@fromBackingInt(tab)) != null;
    }

    fn cardTabClosed(raw: *anyopaque, card: identity.CardId) void {
        const self: *Host = @ptrCast(@alignCast(raw));
        const instance = self.find(card) orelse return;
        // 内容节点已由 workspace 摘下；这里结束实例（作业、回放表面、视图）。
        instance.tab_closed = true;
        instance.state = .closing;
        self.cx.requestRedraw();
    }

    // ── 每帧 ──

    fn frame(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *Host = @ptrCast(@alignCast(raw));
        self.sync();
        return .done;
    }

    fn sync(self: *Host) void {
        const current = self.currentTabId();
        const content = self.workspace.terminal_area.globalRect();
        var index: usize = 0;
        while (index < self.instances.items.len) {
            const instance = self.instances.items[index];
            if (instance.state == .live and instance.placement == .float) if (instance.owner_tab) |owner| if (!self.tabExists(owner)) {
                // 所属 tab 已关闭：浮动卡片随它一起关闭，不播放动效。
                instance.state = .closing;
            };
            if (instance.state == .closing) {
                _ = self.instances.orderedRemove(index);
                instance.destroy();
                continue;
            }
            if (instance.move_to_tab) {
                instance.move_to_tab = false;
                instance.placeInTab() catch |err| self.workspace.statusFailure(@errorName(err));
            }
            instance.vm.poll();
            instance.syncSurface();
            if (instance.slots.viewport) |viewport| instance.vm.list.viewport_height = viewport.globalRect().h;
            instance.vm.replay_focused = if (instance.slots.surface) |slot| if (self.cx.focus_manager.getFocused()) |focused| focused == slot or focused.isDescendantOf(slot) else false else false;
            if (instance.root) |root| instance.vm.setWidth(root.globalRect().w);
            if (instance.float) |float| {
                const shown = instance.owner_tab == null or (current != null and instance.owner_tab.? == current.?);
                float.card.update(.{ .content = .{ .x = content.x, .y = content.y, .width = content.w, .height = content.h } }, shown);
                float.card.present(.{ .shown = shown, .tab = instance.owner_tab, .current_tab = current });
            }
            index += 1;
        }
    }

    // ── 导出（与原目录浮层相同） ──

    fn exportRecord(self: *Host, descriptor: archive_mod.Descriptor) !void {
        if (!descriptor.can_export) return error.RecordingUnavailable;
        const Export = @import("../../workspace/host/session_export.zig");
        const Jobs = @import("../../workspace/host/session_export_jobs.zig");
        const format: Export.Format = if (descriptor.replayability == .baseline_unavailable) .cast else try Export.Format.parse(self.workspace.app_config.log.export_format);
        const sdk = self.cx.system_sdk orelse return error.NativeDialogUnavailable;
        const captured = try Jobs.ArchiveRecord.capture(std.heap.c_allocator, self.archive, descriptor.archive_key, descriptor.manifest_revision);
        var owned = captured;
        var path_buffer: [4096]u8 = undefined;
        const target = @import("../../../platform/dialog_port.zig").run(sdk, .{ .kind = .save_file, .title = format.defaultFilename() }, &path_buffer) catch |err| {
            owned.deinit();
            return err;
        };
        const destination = target orelse {
            owned.deinit();
            return;
        };
        const manager = Jobs.Manager.forCx(self.cx) orelse {
            owned.deinit();
            return error.WorkspaceUnavailable;
        };
        try manager.start(.{ .archive_record = captured }, format, destination);
    }

    fn cleanup(self: *Host) void {
        self.cx.removeAfterLayoutHook(self);
        if (self.workspace.card_tab_port) |port| if (port.context == @as(*anyopaque, @ptrCast(self))) {
            self.workspace.card_tab_port = null;
        };
        // Every instance scope is a child of `self.scope` and was disposed before this cleanup (Instance.scopeEnded
        // removed each one from `instances`).
        std.debug.assert(self.instances.items.len == 0);
        self.instances.deinit(self.allocator);
        self.slots.deinit(self.allocator);
        if (self.archive_dir_owned) self.archive.dir.close(self.archive.io);
        self.allocator.destroy(self);
    }
};

const Float = struct {
    scope: *ui.Scope,
    /// 浮动层上的定位节点（统一窗口外观挂在它里面）。
    node: *ui.Node,
    /// 统一窗口外观（`history.panel` 外框、`history.float.drag`、头部）；卡片内容挂在它的内容区。
    chrome: *float_chrome.Chrome,
    card: *float_layer.Card,
};

/// 浮动时的统一窗口外观声明：标题、图标、条数副标题（列表的条数信号）与 test id（沿用 `history.*`）。
fn chromeSpec(instance: *Instance, descriptor: float_card.Descriptor) float_chrome.Spec {
    return .{
        .title = "会话记录",
        .icon = ui.icons.history,
        .descriptor = descriptor,
        .ids = .{ .root = ids.panel, .grip = "history.float.drag", .header = ids.header, .subtitle = ids.count, .open_as_tab = ids.open_as_tab, .dock_to_split = "history.dock_to_split", .dock_to_split_tooltip = "history.dock_to_split.tooltip", .minimize = "history.minimize", .minimize_tooltip = "history.minimize.tooltip", .maximize = "history.maximize", .close = ids.close, .open_as_tab_tooltip = "history.open_as_tab.tooltip", .maximize_tooltip = "history.maximize.tooltip", .close_tooltip = ids.close_tooltip },
        .labels = .{ .close_tooltip = @import("../../../shared/ui/components/panel_header/panel_header.zig").close_tooltip },
        .subtitle = instance.vm.list.count_text,
    };
}

const Instance = struct {
    host: *Host,
    id: identity.CardId,
    scope: *ui.Scope,
    vm: *card_vm.CardVm,
    slots: template.Slots = .{},
    /// 卡片内容根（列表 + 详情）；浮动时在统一窗口外观的内容区，作为 tab 时在 `tab_frame` 的插槽里。
    root: ?*ui.Node = null,
    tab_slots: template.TabSlots = .{},
    /// 作为 tab 时的卡片框（`history.panel`，原生 W.Card + 头部），首次放进 tab 时创建。
    tab_frame: ?*ui.Node = null,
    placement: card_vm.Placement = .float,
    /// 浮动时所属的 tab（tab 条 id）；null = 窗口本身（打开时没有任何 tab）。
    owner_tab: ?u64 = null,
    float: ?Float = null,
    /// 浮动位置（窗口内容坐标；`remember_position`，地址固定供浮动层引用）。
    float_placement: float_card.Placement = .{},
    attached_surface: ?*ReplaySurface = null,
    state: enum { live, closing } = .live,
    move_to_tab: bool = false,
    tab_closed: bool = false,
    /// Set once createInstance has handed the instance to the host. Before that, createInstance's own errdefers free
    /// it (scopeEnded leaves it alone).
    adopted: bool = false,

    fn float_(self: *Instance, host: *Host) !void {
        const root = self.root orelse return error.HistoryCardMissing;
        const float_scope = try self.scope.childScope();
        errdefer float_scope.dispose();
        const node = try ui.box(host.cx, .{ .position = .absolute, .direction = .column }, .{});
        errdefer {
            if (node.parent) |parent| host.cx.detachChild(parent, node);
            if (root.parent) |parent| host.cx.detachChild(parent, root);
            host.cx.destroyDetached(node);
        }
        const descriptor = card_types.floatDescriptor(host.definition) orelse card_type.float_descriptor;
        const chrome = try float_chrome.Chrome.mount(host.cx, float_scope, chromeSpec(self, descriptor));
        try chrome.body.appendChild(host.allocator, root);
        floating_input.protect(host.cx, node);
        // 外框也挡住指针与滚轮：空白处的滚动停在卡片上，不落到下面的终端。
        floating_input.protect(host.cx, chrome.root);
        const card = try host.layer.attach(float_scope, .{
            .node = node,
            .chrome = chrome,
            .descriptor = descriptor,
            .placement = &self.float_placement,
            .callbacks = .{ .ctx = self, .close = closeFloat, .action = headerAction },
            .grip_test_id = "history.float.drag",
            .handle_test_ids = .{ "history.float.resize.n", "history.float.resize.s", "history.float.resize.w", "history.float.resize.e", "history.float.resize.nw", "history.float.resize.ne", "history.float.resize.sw", "history.float.resize.se" },
        });
        host.layer.raise(card);
        self.float = .{ .scope = float_scope, .node = node, .chrome = chrome, .card = card };
        self.placement = .float;
    }
    /// 把同一张卡片从浮动层挪进一个新的独立 tab（卡片头“作为 tab 打开”）。
    fn placeInTab(self: *Instance) !void {
        const host = self.host;
        const root = self.root orelse return error.HistoryCardMissing;
        if (!host.definition.placements.allows(.standalone_tab)) return error.PlacementNotAllowed;
        const float = self.float orelse return;
        float.card.cancel();
        const frame = self.tab_frame orelse try ui.view.render(self.scope, host.cx, template.TabFrame(.{ .vm = self.vm, .slots = &self.tab_slots }));
        self.tab_frame = frame;
        const content = self.tab_slots.content orelse return error.HistoryCardMissing;
        if (root.parent) |parent| host.cx.detachChild(parent, root);
        try content.appendChild(host.allocator, root);
        _ = host.workspace.openCardTab(host.definition, self.id, frame, host.definition.title) catch |err| {
            // 放不进 tab：卡片内容回到浮动外框的原位。
            host.cx.detachChild(content, root);
            float.chrome.body.appendChild(host.allocator, root) catch {};
            return err;
        };
        self.float = null;
        float.scope.dispose();
        if (float.node.parent) |parent| host.cx.detachChild(parent, float.node);
        host.cx.destroyDetached(float.node);
        self.placement = .tab;
        self.owner_tab = null;
        self.vm.setPlacement(.tab);
        host.cx.requestRedraw();
    }
    /// 回放表面插槽：详情区就绪时把表面根放进来（终端表面不是 Yix 节点，见 YIX_EXCEPTIONS）。
    fn syncSurface(self: *Instance) void {
        const replay = self.vm.detail.replay orelse {
            self.attached_surface = null;
            return;
        };
        const surface: *ReplaySurface = @ptrCast(@alignCast(replay.handle));
        if (surface == self.attached_surface) return;
        const slot = self.slots.surface orelse return;
        const node = surface.root();
        if (node.parent != slot) {
            if (node.parent) |parent| self.host.cx.detachChild(parent, node);
            slot.appendChild(self.host.allocator, node) catch return;
        }
        self.attached_surface = surface;
        slot.markLayoutDirty();
        self.host.cx.requestRedraw();
    }

    /// The card closes (its tab closed, the person closed it): the host has already removed it from `instances`.
    /// Everything that needs the live view model or the floating frame happens here, before the scope goes; the rest
    /// is `scopeEnded`, run by the scope's disposal.
    fn destroy(self: *Instance) void {
        const cx = self.host.cx;
        self.vm.detail.cancel();
        if (self.float) |float| {
            // 焦点还在卡片里（或已无焦点）时回到打开时的焦点（触发按钮）。
            float.card.focusClosed();
            float.card.cancel();
            if (self.root) |root| if (root.parent) |parent| cx.detachChild(parent, root);
        }
        self.scope.dispose();
    }

    /// The instance scope's last cleanup (registered first): the view model has released its job and replay surface.
    /// Runs on `destroy` and when the host scope is disposed with the window (children before the parent's cleanups);
    /// on that path the floating frame's child scope is already gone, so nothing here touches `float.card`.
    fn scopeEnded(self: *Instance) void {
        if (!self.adopted) return;
        const host = self.host;
        const cx = host.cx;
        for (host.instances.items, 0..) |item, index| if (item == self) {
            _ = host.instances.orderedRemove(index);
            break;
        };
        // 内容根与卡片框 / 浮动框分开销毁：内容根先从它所在的框里摘下（否则随框一起释放）。
        if (self.root) |root| if (root.parent) |parent| cx.detachChild(parent, root);
        if (self.placement == .tab and !self.tab_closed) {
            // 宿主自己结束一张 tab 里的卡片（窗口关闭）：卡片框可能仍挂在 tab 的槽里。
            if (self.tab_frame) |frame| if (frame.parent) |parent| cx.detachChild(parent, frame);
        }
        if (self.float) |float| {
            if (float.node.parent) |parent| cx.detachChild(parent, float.node);
            cx.destroyDetached(float.node);
            self.float = null;
        }
        if (self.root) |root| cx.destroyDetached(root);
        self.root = null;
        if (self.tab_frame) |frame| cx.destroyDetached(frame);
        self.tab_frame = null;
        host.slots.release(host.allocator, self.id);
        host.allocator.destroy(self);
        cx.requestRedraw();
    }

    // ── CardVm.Host ──

    fn requestTab(raw: *anyopaque, _: *card_vm.CardVm) void {
        const self: *Instance = @ptrCast(@alignCast(raw));
        self.move_to_tab = true;
        self.host.cx.requestRedraw();
    }
    fn requestClose(raw: *anyopaque, _: *card_vm.CardVm) void {
        const self: *Instance = @ptrCast(@alignCast(raw));
        if (self.placement == .tab) {
            // tab 里的卡片：走 workspace 的关闭流程（与其他 tab 相同），完成后经 `cardTabClosed` 结束。
            if (self.host.workspace.cardTabIndex(self.id)) |index| self.host.workspace.requestCloseTab(index);
            return;
        }
        self.state = .closing;
        self.host.cx.requestRedraw();
    }
    /// 统一窗口外观的头部动作（放大 / 还原由浮动层处理；关闭交回浮动层，经 `closeFloat` 结束卡片）。
    fn headerAction(ctx: ?*anyopaque, action: float_card.HeaderAction) bool {
        const self: *Instance = @ptrCast(@alignCast(ctx orelse return false));
        if (action != .open_as_tab) return false;
        self.vm.openAsTab();
        return true;
    }
    fn closeFloat(ctx: ?*anyopaque) void {
        const self: *Instance = @ptrCast(@alignCast(ctx orelse return));
        self.state = .closing;
        self.host.cx.requestRedraw();
    }
    fn exportRecord(raw: *anyopaque, descriptor: archive_mod.Descriptor) anyerror!void {
        const self: *Instance = @ptrCast(@alignCast(raw));
        return self.host.exportRecord(descriptor);
    }
    fn mountReplay(raw: *anyopaque, document: *loading.Document) anyerror!detail_vm.Replay {
        const self: *Instance = @ptrCast(@alignCast(raw));
        const surface = try self.host.workspace.mountReplaySurface(self.scope, document);
        return .{ .handle = surface };
    }
    fn releaseReplay(raw: *anyopaque, replay: detail_vm.Replay) void {
        const self: *Instance = @ptrCast(@alignCast(raw));
        const surface: *ReplaySurface = @ptrCast(@alignCast(replay.handle));
        if (self.attached_surface == surface) self.attached_surface = null;
        self.host.workspace.releaseReplaySurface(surface);
    }
};

