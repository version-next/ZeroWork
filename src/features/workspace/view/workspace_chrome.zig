//! Retained native chrome for the approved Mist workspace SVG.
//! Reparents existing controls; session, transfer and AI controllers stay owners.
const std = @import("std");
const ui = @import("ui");
const S = @import("../../shell/view/shell_styles.zig");
const Workspace = @import("workspace.zig").Workspace;
const tab_layout = @import("../../shell/model/tab_strip_layout.zig");
const TabId = @import("../model/workspace_model.zig").TabId;
/// The title bar tool group (shell `title_tools_view.zig`, design-r3 稿 5)
/// behind a seam: given the width the tabs leave, it settles its fold level
/// and reports the width it now takes.
pub const ToolFold = struct {
    context: *anyopaque,
    fit: *const fn (*anyopaque, f32) Fit,
    pub const Fit = struct { width: f32, changed: bool };
};
pub const View = struct {
    cx: *ui.Cx,
    workspace: *Workspace,
    bar: *ui.Node,
    tabs: *ui.Node,
    /// design-r3 稿 5 tool group; this view only reports the space the tabs leave.
    tools: ToolFold,
    identities: [2]?*ui.Node = .{ null, null },
    /// The tab the identity regions last settled on, and its region (`identityRegion`).
    settled: ?struct { tab: TabId, region: ?*ui.Node } = null,
    pub fn identitiesAtTabs(self: *View, remote: *ui.Node, local: *ui.Node) !void {
        self.identities = .{ remote, local };
        for (self.identities) |node| {
            try move(self.cx, self.bar, node.?);
            node.?.setStyleInline(self.cx.allocator, .{ .position = .absolute, .width = .{ .px = 28 }, .height = .{ .px = 28 }, .padding = .{}, .corner_radius = 14, .z_index = 5, .background = ui.Color.TRANSPARENT });
            // Geometry-only preview region over the active tab (see afterLayout):
            // never a hit target, never in the tab order.
            passThrough(node.?);
            node.?.setFocusable(false);
        }
    }
    /// The active tab's surface, from the tab strip's own tab-id → node binding (`Workspace.tab_nodes`,
    /// rebuilt with the strip): the explicit anchor for cards that belong to the active session.
    /// null while there is no active tab or its surface is not displayed.
    pub fn activeTabNode(self: *View) ?*ui.Node {
        if (self.workspace.active_tab == null) return null;
        const active_id = self.workspace.model.active;
        for (self.workspace.tab_nodes.items) |tab| if (tab.tab_id == active_id) {
            return if (tab.node.isDisplayedInTree()) tab.node else null;
        };
        return null;
    }
    /// `activeTabNode` as an opaque resolver (the shape `ssh_status_host.CardAnchor` takes).
    pub fn resolveActiveTab(raw: *anyopaque) ?*ui.Node {
        const self: *View = @ptrCast(@alignCast(raw));
        return self.activeTabNode();
    }
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, workspace: *Workspace, bar: *ui.Node, tabs: *ui.Node, tools: ToolFold) !*View {
        const self = try scope.createState(View, .{ .cx = cx, .workspace = workspace, .bar = bar, .tabs = tabs, .tools = tools });
        try cx.addAfterLayoutHook(self, afterLayout);
        try scope.onCleanup(View, self, cleanup);
        return self;
    }
    pub fn installFeedback(self: *View, scope: *ui.Scope) !void {
        const Feedback = @import("../../../shared/ui/components/icon_button_feedback/icon_button_feedback.zig").Binding;
        for (self.tabs.children.items) |button| if (button.behavior.interaction.a11y) |props| {
            if (props.role == .button) try Feedback.attach(self.cx, scope, button);
        };
        for (self.identities) |maybe| if (maybe) |button| try Feedback.attach(self.cx, scope, button);
    }
    /// Natural (uncompressed) width of the tab strip plus the new-tab slot.
    fn naturalTabs(self: *View) f32 {
        var total: f32 = 0;
        for (self.workspace.strip_advances.items, 0..) |advance, i| {
            const grouped = i < self.workspace.strip_grouped.items.len and self.workspace.strip_grouped.items[i];
            total += tab_layout.naturalWidth(advance, grouped);
            if (i > 0) total += tab_layout.gap;
        }
        return total;
    }
    /// Where the identity region for `tab` stands (the tab menu's “会话详情” opens through it).
    pub const Region = union(enum) {
        /// Not settled for this tab yet: it is not the active tab, its row is not mounted or laid out,
        /// a strip rebuild is pending, or the region was just moved over it and is not laid out there
        /// yet. Each of these ends by itself (layout round, row mount, rebuild) and runs the chrome
        /// again; nothing waits a number of frames.
        settling,
        /// Settled: the region over this tab, displayed and laid out at the tab's surface.
        shown: *ui.Node,
        /// Settled: this tab shows no identity region (its surface is outside the tab capsule).
        none,
    };
    pub fn identityRegion(self: *const View, tab: TabId) Region {
        const settled = self.settled orelse return .settling;
        if (settled.tab != tab) return .settling;
        return if (settled.region) |node| .{ .shown = node } else .none;
    }
    /// Shows the identity region of the active tab's kind over its surface and hides the other.
    /// Returns whether any display or geometry changed; the regions settle on a pass that
    /// changes nothing.
    fn placeIdentities(self: *View) bool {
        self.settled = null;
        const index = self.workspace.active_tab orelse return self.hideIdentities();
        if (index >= self.workspace.tabs.items.len) return self.hideIdentities();
        const local = self.workspace.isLocalSession(self.workspace.tabs.items[index].id);
        const active_id = self.workspace.model.active orelse return self.hideIdentities();
        // The active tab's mounted surface (Workspace.tab_nodes, bound when its row mounts; the
        // active tab is always in the strip). Until it is mounted and laid out no region stands over
        // a tab and the active tab is unsettled.
        const surface = self.activeTabNode() orelse return self.hideIdentities();
        const r = surface.globalRect();
        if (r.w <= 0 or r.h <= 0) return self.hideIdentities();
        const capsule = self.tabs.globalRect();
        const icon_visible = r.x + 12 >= capsule.x and r.x + 40 <= capsule.x + capsule.w;
        var changed = false;
        var region: ?*ui.Node = null;
        for (self.identities, 0..) |maybe, kind| if (maybe) |node| {
            const shown = icon_visible and (kind == 1) == local;
            const display: @TypeOf(node.style.display) = if (shown) .flex else .none;
            if (node.style.display != display) {
                node.setDisplay(display);
                changed = true;
            }
            if (shown) region = node;
            // The connection card's anchor region is the whole active tab surface (title-click: it
            // opens from the tab menu's “会话详情”, never on hover). Every pointer event passes
            // through to the tab (select, close, drag, menus).
            const parent = self.bar.globalRect();
            const left = r.x - parent.x;
            const top = r.y - parent.y;
            const ext = node.style.ensureExtPanic(self.cx.allocator);
            const same_size = node.style.width == .px and node.style.height == .px and @abs(node.style.width.px - r.w) <= 0.5 and @abs(node.style.height.px - r.h) <= 0.5;
            if (!same_size or ext.inset.left != .px or ext.inset.top != .px or @abs(ext.inset.left.px - left) > 0.5 or @abs(ext.inset.top.px - top) > 0.5) {
                node.setStyleInline(self.cx.allocator, .{ .inset = .{ .left = .{ .px = left }, .top = .{ .px = top } }, .width = .{ .px = r.w }, .height = .{ .px = r.h } });
                changed = true;
            }
        };
        // A pending strip rebuild may still move or re-mount the tab (Workspace's hook runs it and
        // asks for layout); the regions settle on the strip as rebuilt.
        if (!changed and !self.workspace.tab_rebuild_pending) self.settled = .{ .tab = active_id, .region = region };
        return changed;
    }
    fn hideIdentities(self: *View) bool {
        var changed = false;
        for (self.identities) |maybe| if (maybe) |node| if (node.style.display != .none) {
            node.setDisplay(.none);
            changed = true;
        };
        return changed;
    }
    fn afterLayout(raw: *anyopaque, _: u8, last_round: bool) ui.AfterLayoutResult {
        const self: *View = @ptrCast(@alignCast(raw));
        const strip_changed = self.fitStrip();
        // Display and geometry of the identity regions are layout inputs: a pass that changes them
        // asks for layout, so the hooks after it (the tab menu's “会话详情”, nav_host) read the
        // region laid out in this frame. Placed after the strip's budget so a budget change (which
        // queues a strip rebuild) keeps the regions unsettled.
        const regions_changed = self.placeIdentities();
        if (regions_changed and last_round) self.cx.requestRedraw();
        return if (strip_changed or regions_changed) .needs_layout else .done;
    }
    /// The tab gap, the tool group's fold level and the tabs' budget for the bar's width. Returns
    /// whether any of them changed.
    fn fitStrip(self: *View) bool {
        const width = self.bar.globalRect().w;
        if (width <= 0) return false;
        var changed = false;
        // An empty zero-width strip must not leave a gap before the sole +.
        const tab_gap: f32 = if (self.workspace.model.tabs.items.len == 0) 0 else 4;
        if (self.tabs.style.gap != tab_gap) {
            self.tabs.setStyle(self.cx.allocator, .gap, tab_gap);
            changed = true;
        }
        // 稿 5: tools fold only when the tabs, laid out at their natural
        // width (new-tab slot included), leave no room — tools enter the
        // overflow before any tab does. 24 of hysteresis on the way back.
        const fit = self.tools.fit(self.tools.context, width - self.naturalTabs() - new_tab_reserve - tools_gap);
        if (fit.changed) changed = true;
        const budget = @max(96, width - fit.width - tools_gap - new_tab_reserve);
        if (self.workspace.tab_budget == null or @abs(self.workspace.tab_budget.? - budget) > 0.5) {
            self.workspace.tab_budget = budget;
            self.workspace.reveal_active = true;
            self.workspace.tab_rebuild_pending = true;
            changed = true;
        }
        return changed;
    }
    fn cleanup(self: *View) void {
        self.cx.removeAfterLayoutHook(self);
    }
};
/// The new-tab slot after the strip and the gaps around it.
const new_tab_reserve: f32 = 40;
/// Minimum gap between the tab capsule and the tool group.
const tools_gap: f32 = 16;
fn passThrough(node: *ui.Node) void {
    node.setHitTestVisible(false);
    for (node.children.items) |child| passThrough(child);
}
fn contains(rect: ui.ComputedRect, x: f32, y: f32) bool {
    return rect.w > 0 and rect.h > 0 and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h;
}
pub fn move(cx: *ui.Cx, parent: *ui.Node, child: *ui.Node) !void {
    if (child.parent) |old| old.removeChild(child);
    try parent.appendChild(cx.allocator, child);
}
pub fn iconOnly(cx: *ui.Cx, button: *ui.Node, icon: *ui.Node, label: ?*ui.Node) void {
    // Folded status controls take the native md icon-button square (S.toolbar_icon_size).
    const size = S.toolbar_icon_size;
    button.setStyleInline(cx.allocator, .{ .width = .{ .px = size }, .height = .{ .px = size }, .padding = .{}, .gap = 0, .justify = .center, .align_items = .center });
    // Center the 16pt glyph ((32 - 16) / 2).
    icon.setStyleInline(cx.allocator, .{ .position = .absolute, .inset = .{ .left = .{ .px = (size - 16) / 2 }, .top = .{ .px = (size - 16) / 2 } }, .width = .{ .px = 16 }, .height = .{ .px = 16 } });
    if (label) |node| node.setDisplay(.none);
}
pub fn retainLegacy(cx: *ui.Cx, bar: *ui.Node) void {
    bar.setStyleInline(cx.allocator, .{ .position = .absolute, .width = .{ .px = 0 }, .height = .{ .px = 0 }, .min_height = 0, .padding = .{}, .overflow = .hidden, .shadow = .{ .color = ui.Color.TRANSPARENT } });
}
