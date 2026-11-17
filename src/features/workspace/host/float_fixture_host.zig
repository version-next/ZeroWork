//! 测试卡片 `fixture.float` 的窗口级宿主（float-split，只在 -Dtest-mode=true 构建里由组合根装配）。
//!
//! 环境变量 `ZEROWORK_TEST_FLOAT_FIXTURE` 存在时，窗口里出现第一个 tab 后打开一张浮动的测试卡片（属于
//! 当时的当前 tab）。它和会话记录卡片一样经通用浮动层与统一外框承载，头部“放入分屏”把同一个内容节点放进
//! 所属 tab 的分屏（`Workspace.dockCard`），窗格头部“浮动”再把它送回上次的浮动位置。每次放入 / 浮动回来
//! 在标准输出打一行 `ZW_FLOAT_SPLIT {...}`（动作、方式、起止矩形），e2e 据此核对飞行的起点与终点。
const std = @import("std");
const ui = @import("ui");
const card_types = @import("../../../host/card_types.zig");
const float_layer = @import("../../../shared/ui/float_card/float_layer.zig");
const float_chrome = @import("../../../shared/ui/float_card/float_chrome.zig");
const float_card = @import("../../../shared/base/float_card.zig");
const float_card_motion = @import("../../../shared/ui/styles/float_card_motion.zig");
const floating_input = @import("../../../shared/ui/components/floating_input/floating_input.zig");
const fixture = @import("../model/float_fixture.zig");
const content_view = @import("../view/float_fixture_view.zig");
const Workspace = @import("../view/workspace.zig").Workspace;

extern "c" fn getenv([*:0]const u8) ?[*:0]const u8;

pub const env_name = "ZEROWORK_TEST_FLOAT_FIXTURE";

pub const Host = struct {
    cx: *ui.Cx,
    scope: *ui.Scope,
    workspace: *Workspace,
    layer: *float_layer.FloatLayer,
    definition: *const card_types.CardTypeDef = &fixture.def,
    enabled: bool,
    opened: bool = false,
    card: ?*Card = null,

    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, workspace: *Workspace, layer: *float_layer.FloatLayer) !*Host {
        const self = try scope.createState(Host, .{ .cx = cx, .scope = scope, .workspace = workspace, .layer = layer, .enabled = getenv(env_name) != null });
        try cx.addAfterLayoutHook(self, frame);
        try scope.onCleanup(Host, self, cleanup);
        return self;
    }

    fn cleanup(self: *Host) void {
        self.cx.removeAfterLayoutHook(self);
        if (self.card) |card| card.destroy();
        self.card = null;
    }

    fn currentTab(self: *Host) ?u64 {
        const workspace = self.workspace;
        if (workspace.active_group_view) |group| return if (workspace.groupTabId(group)) |tab| @backingInt(tab) else null;
        const index = workspace.active_tab orelse return null;
        return if (index < workspace.tabs.items.len) @backingInt(workspace.tabs.items[index].tab_id) else null;
    }

    fn frame(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *Host = @ptrCast(@alignCast(raw));
        if (self.enabled and !self.opened) if (self.currentTab()) |tab| {
            self.opened = true;
            self.card = Card.create(self, tab) catch |err| blk: {
                self.workspace.statusFailure(@errorName(err));
                break :blk null;
            };
        };
        const card = self.card orelse return .done;
        if (card.closing) {
            card.destroy();
            self.card = null;
            self.cx.requestRedraw();
            return .done;
        }
        card.sync();
        return .done;
    }
};

const Card = struct {
    host: *Host,
    scope: *ui.Scope,
    content: *content_view.Content,
    node: *ui.Node,
    chrome: *float_chrome.Chrome,
    float: *float_layer.Card,
    placement: float_card.Placement = .{},
    owner_tab: ?u64,
    /// The split leaf while docked.
    leaf: ?u64 = null,
    dock_requested: bool = false,
    float_requested: bool = false,
    close_requested: bool = false,
    closing: bool = false,
    refusal_buffer: [128]u8 = undefined,

    fn create(host: *Host, owner: u64) !*Card {
        const cx = host.cx;
        const scope = try host.scope.childScope();
        errdefer scope.dispose();
        const descriptor = card_types.floatDescriptor(host.definition).?;
        const content = try content_view.Content.mount(cx, scope);
        const node = try ui.box(cx, .{ .position = .absolute, .direction = .column }, .{});
        const chrome = try float_chrome.Chrome.mount(cx, scope, .{
            .title = fixture.title,
            .icon = ui.icons.flask_conical,
            .descriptor = descriptor,
            .ids = .{ .root = "fixture.float.panel", .grip = "fixture.float.drag", .header = "fixture.float.header", .subtitle = "fixture.float.subtitle", .open_as_tab = "fixture.float.open_as_tab", .dock_to_split = "fixture.float.dock_to_split", .minimize = "fixture.float.minimize", .maximize = "fixture.float.maximize", .close = "fixture.float.close", .open_as_tab_tooltip = "fixture.float.open_as_tab.tooltip", .dock_to_split_tooltip = "fixture.float.dock_to_split.tooltip", .minimize_tooltip = "fixture.float.minimize.tooltip", .maximize_tooltip = "fixture.float.maximize.tooltip", .close_tooltip = "fixture.float.close.tooltip" },
        });
        try chrome.body.appendChild(cx.allocator, content.root);
        floating_input.protect(cx, node);
        floating_input.protect(cx, chrome.root);
        const self = try scope.createState(Card, .{ .host = host, .scope = scope, .content = content, .node = node, .chrome = chrome, .float = undefined, .owner_tab = owner });
        self.float = try host.layer.attach(scope, .{
            .node = node,
            .chrome = chrome,
            .descriptor = descriptor,
            .placement = &self.placement,
            .callbacks = .{ .ctx = self, .close = closeFloat, .action = headerAction },
            .grip_test_id = "fixture.float.drag",
            .handle_test_ids = .{ "fixture.float.resize.n", "fixture.float.resize.s", "fixture.float.resize.w", "fixture.float.resize.e", "fixture.float.resize.nw", "fixture.float.resize.ne", "fixture.float.resize.sw", "fixture.float.resize.se" },
        });
        host.layer.raise(self.float);
        return self;
    }

    fn destroy(self: *Card) void {
        const cx = self.host.cx;
        self.float.cancel();
        if (self.leaf) |leaf| _ = self.host.workspace.undockCard(leaf, null);
        self.leaf = null;
        if (self.content.root.parent) |parent| cx.detachChild(parent, self.content.root);
        const root = self.content.root;
        const node = self.node;
        self.scope.dispose();
        if (node.parent) |parent| cx.detachChild(parent, node);
        cx.destroyDetached(node);
        cx.destroyDetached(root);
        cx.requestRedraw();
    }

    fn sync(self: *Card) void {
        const host = self.host;
        if (self.close_requested) {
            self.close_requested = false;
            self.closing = true;
            return;
        }
        if (self.dock_requested) {
            self.dock_requested = false;
            self.dock() catch |err| host.workspace.statusFailure(@errorName(err));
        }
        if (self.float_requested) {
            self.float_requested = false;
            self.floatBack();
        }
        if (self.leaf) |leaf| {
            if (host.workspace.dockedCardFlight(leaf)) |f| traceFrame("pane", f.rect.x, f.rect.y, f.rect.w, f.rect.h, f.opacity);
            // Docked: the pane is the card; the floating frame stays hidden.
            if (host.workspace.dockedCardTab(leaf)) |tab| self.owner_tab = tab;
            const content = host.workspace.terminal_area.globalRect();
            self.float.update(.{ .content = .{ .x = content.x, .y = content.y, .width = content.w, .height = content.h } }, false);
            return;
        }
        if (self.owner_tab) |owner| if (host.workspace.model.indexOf(@fromBackingInt(owner)) == null) {
            // The owner tab closed: the floating card closes with it (no motion), like the history card.
            self.closing = true;
            return;
        };
        const current = host.currentTab();
        const shown = self.owner_tab == null or (current != null and self.owner_tab.? == current.?);
        const content = host.workspace.terminal_area.globalRect();
        self.float.update(.{ .content = .{ .x = content.x, .y = content.y, .width = content.w, .height = content.h } }, shown);
        self.float.present(.{ .shown = shown, .tab = self.owner_tab, .current_tab = current });
        if (self.float.phase() == .expanding) {
            const r = self.float.presentedRect();
            traceFrame("float", r.x, r.y, r.w, r.h, self.float.presentedOpacity());
        }
        const refusal = host.workspace.dockRefusal(self.owner_tab);
        self.chrome.setActionState(.dock_to_split, if (refusal) |value| value.text() else null);
    }

    fn mode(self: *Card) float_layer.TransitionMode {
        return self.host.layer.currentMode();
    }

    fn dock(self: *Card) !void {
        const host = self.host;
        if (!self.chrome.actionEnabled(.dock_to_split)) return;
        if (!host.definition.placements.split) return error.PlacementNotAllowed;
        const from = self.chrome.root.globalRect();
        const transition = self.mode();
        const docked = try host.workspace.dockCard(.{
            .owner_tab = self.owner_tab,
            .content = self.content.root,
            .title = fixture.title,
            .icon = ui.icons.flask_conical,
            .ids = .{ .pane = "fixture.float.pane", .header = "fixture.float.pane.header", .title = "fixture.float.pane.title", .float = "fixture.float.pane.float", .float_tooltip = "fixture.float.pane.float.tooltip", .grip = "fixture.float.pane.drag", .more = "fixture.float.pane.more", .menu = "fixture.float.pane.menu" },
            .port = .{ .ctx = self, .float_back = if (host.definition.placements.float) requestFloat else null, .closed = paneClosed, .close = requestClose },
            .from = from,
            .flight = .{ .anchor = if (transition == .anchor) .{ .rect = .{ .x = from.x, .y = from.y, .w = from.w, .h = from.h } } else .none, .tokens = float_card_motion.placeTokens(transition) },
        });
        self.float.hideForDock();
        self.leaf = docked.leaf;
        self.owner_tab = docked.tab;
        trace("dock", transition, from, null);
    }

    fn floatBack(self: *Card) void {
        const host = self.host;
        const leaf = self.leaf orelse return;
        const undocked = host.workspace.undockCard(leaf, .{ .parent = self.chrome.body });
        const pane = undocked.rect;
        if (undocked.tab) |tab| self.owner_tab = tab;
        self.leaf = null;
        if (self.content.root.parent != self.chrome.body) {
            host.workspace.statusFailure("FloatCardContentLost");
            self.closing = true;
            return;
        }
        const content = host.workspace.terminal_area.globalRect();
        self.float.update(.{ .content = .{ .x = content.x, .y = content.y, .width = content.w, .height = content.h } }, true);
        const from: ?float_layer.Rect = if (pane) |r| .{ .x = r.x, .y = r.y, .width = r.w, .height = r.h } else null;
        self.float.unfoldFrom(self.owner_tab, from);
        host.layer.raise(self.float);
        const to = self.float.rect();
        trace("float", self.mode(), pane, .{ .x = to.x, .y = to.y, .w = to.width, .h = to.height });
        host.cx.requestRedraw();
    }

    fn trace(action: []const u8, mode_: float_layer.TransitionMode, from: ?ui.ComputedRect, to: ?ui.ComputedRect) void {
        const r = from orelse ui.ComputedRect{ .x = 0, .y = 0, .w = 0, .h = 0 };
        const t = to orelse ui.ComputedRect{ .x = 0, .y = 0, .w = 0, .h = 0 };
        std.debug.print("ZW_FLOAT_SPLIT {{\"action\":\"{s}\",\"mode\":\"{s}\",\"from\":[{d:.1},{d:.1},{d:.1},{d:.1}],\"to\":[{d:.1},{d:.1},{d:.1},{d:.1}]}}\n", .{ action, @tagName(mode_), r.x, r.y, r.w, r.h, t.x, t.y, t.w, t.h });
    }

    fn traceFrame(kind: []const u8, x: f32, y: f32, w: f32, h: f32, opacity: f32) void {
        std.debug.print("ZW_FLOAT_SPLIT_FRAME {{\"kind\":\"{s}\",\"rect\":[{d:.1},{d:.1},{d:.1},{d:.1}],\"opacity\":{d:.3}}}\n", .{ kind, x, y, w, h, opacity });
    }

    fn headerAction(ctx: ?*anyopaque, action: float_card.HeaderAction) bool {
        const self: *Card = @ptrCast(@alignCast(ctx orelse return false));
        if (action != .dock_to_split) return false;
        self.dock_requested = true;
        self.host.cx.requestRedraw();
        return true;
    }
    fn closeFloat(ctx: ?*anyopaque) void {
        const self: *Card = @ptrCast(@alignCast(ctx orelse return));
        self.closing = true;
        self.host.cx.requestRedraw();
    }
    fn requestFloat(raw: *anyopaque) void {
        const self: *Card = @ptrCast(@alignCast(raw));
        self.float_requested = true;
        self.host.cx.requestRedraw();
    }
    fn requestClose(raw: *anyopaque) void {
        const self: *Card = @ptrCast(@alignCast(raw));
        self.close_requested = true;
        self.host.cx.requestRedraw();
    }
    fn paneClosed(raw: *anyopaque) void {
        const self: *Card = @ptrCast(@alignCast(raw));
        // The tab holding the pane closed: the content node was detached; end the card.
        self.leaf = null;
        self.closing = true;
        self.host.cx.requestRedraw();
    }
};
