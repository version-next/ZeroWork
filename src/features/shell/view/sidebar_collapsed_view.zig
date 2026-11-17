//! Top-left connection-library restore control, visible while the sidebar is hidden.
const ui = @import("ui");
const Sidebar = @import("sidebar_view.zig");
const theme = @import("../../../shared/ui/theme/app_theme.zig");
const Workspace = @import("../../workspace/view/workspace.zig").Workspace;
const identity = @import("../../../host/identity.zig");
pub const HostAction = enum { edit, connect };
pub const Actions = struct {
    context: *anyopaque,
    search: *const fn (*anyopaque) void,
    new_host: *const fn (*anyopaque) void,
    expand: *const fn (*anyopaque) void,
    host_action: ?*const fn (*anyopaque, identity.AssetOwner, HostAction) void = null,
};
pub const View = struct {
    cx: *ui.Cx,
    root: *ui.Node,
    tip: *Sidebar.ShortcutTip,
    pub fn mount(cx: *ui.Cx, scope: *ui.Scope, _: *Workspace, actions: Actions) !*View {
        const tint = try scope.createSignal(?ui.Color, theme.current().fg_2);
        const hover = try scope.createSignal(?ui.BoxStyle, .{ .background = theme.states().hover });
        const button = try Sidebar.iconButton(cx, scope, "panel-left", Sidebar.restore_name, "sidebar.restore", Sidebar.styles.restoreButton(), tint, hover, ui.Cx.simpleHandler(actions.expand, actions.context), null);
        const restore = try Sidebar.shortcutHint(cx, scope, button, Sidebar.restore_name, .bottom, "sidebar.restore.tooltip");
        const root = restore.wrapper;
        root.meta.ownership.meta.test_id = "workspace.sidebar.restore";
        // Pencil KBJoz / D8dPB: a plain ghost toggle beside the traffic lights, no floating pill.
        const capsule = try ui.box(cx, Sidebar.styles.restoreChrome(), .{});
        try capsule.appendChild(cx.allocator, root);
        capsule.meta.ownership.meta.test_id = "workspace.sidebar.restore.capsule";
        root.setStyleInline(cx.allocator, .{ .width = .{ .px = Sidebar.styles.restore_size }, .height = .{ .px = Sidebar.styles.restore_size }, .flex_shrink = 0 });
        capsule.setDisplay(.none);
        return scope.createState(View, .{ .cx = cx, .root = capsule, .tip = restore.tip });
    }
    /// “显示主机列表 · ⌘B”：快捷键文字来自路由。
    pub fn syncShortcut(self: *View, hint_text: []const u8) void {
        self.tip.sync(hint_text);
    }
    pub fn setCollapsed(self: *View, hidden: bool) void {
        self.root.setDisplay(if (hidden) .flex else .none);
        self.cx.requestRedraw();
    }
    pub fn ownsSidebar(_: *const View) bool {
        return false;
    }
    pub fn refresh(_: *View) !void {}
};
