const std = @import("std");
const ui = @import("ui");
pub const sizing = @import("../model/group_layout.zig");
pub const Layout = sizing.Layout;
pub const Member = @import("../../../host/group_close_controller.zig").Member;
pub const ClosePhase = @import("../../../host/group_close_controller.zig").ClosePhase;
pub const ClosePlan = @import("../../../host/group_close_controller.zig").Plan;
/// A split pane: its session and node, and its header (`pane_header.yix`) for focus / meta updates.
pub const Pane = struct { session: u64, node: *ui.Node, header: ?*@import("pane_header_view.zig").Vm = null };
pub const card_dock = @import("../model/card_dock.zig");
/// Test ids of a docked card's pane (float-split / cards-float). The pane header is the session
/// pane header (ZW2 / Pane Header QGtx5, `Workspace.mountCardPaneHeader`), so a card names each part.
pub const CardIds = struct {
    pane: []const u8,
    header: []const u8,
    title: []const u8,
    float: []const u8,
    float_tooltip: []const u8,
    grip: []const u8 = "",
    more: []const u8 = "",
    menu: []const u8 = "",
};
/// A card's own action in the docked pane's "更多" menu (e.g. the AI's 子智能体 / 会话列表 / 新建).
pub const CardMenuItem = struct { label: []const u8, icon: []const u8 = "" };
/// What the owner of a docked floating card hands the split (float-split / cards-float). Every
/// callback only records the request: the owner acts on its next frame (the split is rebuilt then).
pub const CardPort = struct {
    ctx: *anyopaque,
    /// The pane header's "浮动"; null when the card type cannot float (button disabled).
    float_back: ?*const fn (ctx: *anyopaque) void = null,
    /// The tab holding the pane closed: the content node is already detached; the owner ends the card.
    closed: *const fn (ctx: *anyopaque) void,
    /// The pane header's "关闭" (in "更多"); null = not offered.
    close: ?*const fn (ctx: *anyopaque) void = null,
    /// Card actions listed in "更多" between 浮动 and 关闭; `menu_action` gets the index.
    menu: []const CardMenuItem = &.{},
    menu_action: ?*const fn (ctx: *anyopaque, index: usize) void = null,
    /// The card's icon is the accent one (AI).
    accent_icon: bool = false,
};
/// The flight of a freshly docked pane: unfold from the floating rectangle (Z12 anchor mode) or fade.
pub const Flight = struct { anchor: ui.fx.anchor_transition.Anchor, tokens: ui.fx.anchor_transition.Tokens };
/// A non-session card leaf of the split (not a roster member, M6).
pub const CardLeaf = struct {
    leaf: u64,
    content: *ui.Node,
    title: []const u8,
    icon: ui.SvgAsset,
    ids: CardIds,
    port: CardPort,
    edge: sizing.Edge,
    placed: bool = false,
    /// The presented pane (same frame as a session pane) and the slot the content goes in.
    pane: ?*ui.Node = null,
    body: ?*ui.Node = null,
    /// The pane header's 更多 button (where the card's own popovers open while docked).
    more: ?*ui.Node = null,
    flight: ?Flight = null,
    /// The pane's flight in progress (owned by the presentation scope).
    transition: ?*ui.fx.AnchorTransition = null,
};
/// A floating session card coming back into its split (cards-float): placed at `edge` of the whole
/// tree (like a docked card) and flown in from the floating rectangle.
pub const Redock = struct { session: u64, edge: sizing.Edge, flight: ?Flight = null };
/// One mounted split as presented (稿 2: a left-right row that cannot give each
/// card 320 is shown top-bottom; the saved tree keeps its own axis).
pub const PresentedSplit = struct { split: u32, container: *ui.Node, divider: *ui.Node, axis: Layout };
pub const View = struct {
    id: u32,
    layout: Layout = .side_by_side,
    root: ?*ui.Node = null,
    scope: ?*ui.Scope = null,
    dirty: bool = true,
    panes: std.ArrayList(Pane) = .empty,
    /// Docked floating cards (float-split), in dock order.
    cards: std.ArrayList(CardLeaf) = .empty,
    /// Floating session members coming back (cards-float), placed on the next presentation.
    redock: std.ArrayList(Redock) = .empty,
    /// The session whose single-card tab became this group when a card was docked into it
    /// (float-split); when the last docked card leaves and only that session remains, the group is
    /// dissolved back into the original single-card tab.
    dock_origin: ?u64 = null,
    splits: std.ArrayList(PresentedSplit) = .empty,
    /// Inner width of the group root at the last reflow (0 before the first layout).
    presented_width: f32 = 0,
    drag_source: ?u64 = null,
    drag_target: ?u64 = null,
    focused: ?u64 = null,
    tree: sizing.Tree = .{},
    saved_layout: ?sizing.Snapshot = null,
    pending_placement: ?struct { source: u64, session: u64, axis: Layout } = null,
    layout_loaded: bool = false,
    resizing: bool = false,
    persist_pending: bool = false,
    drop_marker: ?*ui.Node = null,
    presented_pin: ?u64 = null,
    drop_edge: sizing.Edge = .right,
    state_hash: u64 = 0,
    close: ?ClosePlan = null,
    dialog: ?*ui.Node = null,
    dialog_scope: ?*ui.Scope = null,
    dialog_open: ?*ui.Signal(bool) = null,
    pub fn deinit(self: *View, allocator: std.mem.Allocator) void {
        if (self.close) |*plan| plan.members.deinit(allocator);
        self.panes.deinit(allocator);
        self.cards.deinit(allocator);
        self.redock.deinit(allocator);
        self.splits.deinit(allocator);
        self.tree.deinit(allocator);
        if (self.saved_layout) |snapshot| allocator.free(snapshot.nodes);
    }
    pub fn presentedAxis(self: *const View, split: u32) Layout {
        for (self.splits.items) |entry| if (entry.split == split) return entry.axis;
        return self.tree.nodes.items[split].split.axis;
    }
};
