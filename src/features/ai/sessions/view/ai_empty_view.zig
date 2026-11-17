const ui = @import("ui");
const IdSpace = @import("../../shared/view/ai_id_space.zig").IdSpace;
const S = @import("ai_empty_styles.zig");
const RowView = @import("ai_session_row.zig");
pub const Recent = RowView.Entry;
pub const Actions = struct {
    logo_texture: ?u32 = null,
    recent: []const Recent = &.{},
    session_hooks: ?RowView.Hooks = null,
    context: *anyopaque,
    summarize: *const fn (*anyopaque) void,
    logs: *const fn (*anyopaque) void,
    settings: *const fn (*anyopaque) void,
    ollama: *const fn (*anyopaque) void,
    history: ?*const fn (*anyopaque) void = null,
};
const Click = struct {
    context: *anyopaque,
    run: *const fn (*anyopaque) void,
    fn click(self: *Click) void {
        self.run(self.context);
    }
};
/// The welcome page (Pencil A2 `ZF1PS` / `SY7dA`, ai-redesign-c): sparkles 20 · 有什么可以帮你？(16/600),
/// two native secondary block Buttons with Tooltips (概括终端报错 / 分析应用日志), and up to two recent
/// sessions (the shared ai_session_row). Without a usable model: the setup guide (`mountSetup`).
pub fn mount(cx: *ui.Cx, scope: *ui.Scope, configured: bool, actions: Actions) !*ui.Node {
    const space = IdSpace.of(scope);
    if (!configured) return mountSetup(cx, scope, actions);
    const root = try ui.boxStyled(cx, S.root, .{});
    root.meta.ownership.meta.test_id = space.id("ai.empty.configured");
    const welcome = try ui.boxStyled(cx, S.welcome, .{});
    try root.appendChild(cx.allocator, welcome);
    const logo = try ui.iconTint(cx, ui.icons.sparkles, cx.tokens.tokens.color.accent, S.welcomeIcon());
    logo.meta.ownership.meta.test_id = space.id("ai.empty.logo");
    try welcome.appendChild(cx.allocator, logo);
    const title = try ui.textStyled(cx, S.welcomeTitle, "有什么可以帮你？");
    title.meta.ownership.meta.test_id = space.id("ai.empty.title");
    try welcome.appendChild(cx.allocator, title);
    const row = try ui.boxStyled(cx, S.row, .{});
    try root.appendChild(cx.allocator, row);
    const labels = [_][]const u8{ "概括终端报错", "分析应用日志" };
    const handlers = [_]*const fn (*anyopaque) void{ actions.summarize, actions.logs };
    const ids = [_][]const u8{ space.id("ai.empty.summarize"), space.id("ai.empty.logs") };
    for (labels, handlers, ids, 0..) |label, run, id, i| {
        const click = try scope.createState(Click, .{ .context = actions.context, .run = run });
        // Two quick prompts on one row, half the row each: a native secondary block Button with the
        // source icon; the help text is its native Tooltip. The Tooltip's wrapper takes the half.
        const button = try ui.widgets.Button(.{ .label = label, .block = true, .variant = .secondary, .icon_asset = ui.icons.get(if (i == 0) "terminal" else "file-text").?, .on_click = cx.on(Click, click, Click.click) }).mount(scope, cx);
        button.meta.ownership.meta.test_id = id;
        const hint = try ui.widgets.Tooltip(.{ .text = if (i == 0) "填入问题，发送后分析所选文字或最近输出。" else "选择日志文件，附加到问题。" }).mount(scope, cx);
        hint.wrapper.setStyleInline(cx.allocator, S.starterSlot());
        hint.trigger.setStyleInline(cx.allocator, S.starterSlot());
        try hint.trigger.appendChild(cx.allocator, button);
        try row.appendChild(cx.allocator, hint.wrapper);
    }
    if (actions.recent.len > 0 and actions.session_hooks != null) {
        const recent = try ui.boxStyled(cx, S.recentGroup, .{});
        recent.meta.ownership.meta.test_id = space.id("ai.empty.recent");
        const heading = try ui.textStyled(cx, S.recentHeading, "最近会话");
        heading.setStyleInline(cx.allocator, S.recentHeadingBox());
        try recent.appendChild(cx.allocator, heading);
        for (actions.recent[0..@min(2, actions.recent.len)]) |entry| {
            try recent.appendChild(cx.allocator, try RowView.mount(cx, scope, entry, actions.session_hooks.?, null, null));
        }
        try root.appendChild(cx.allocator, recent);
    }
    return root;
}

/// Centers the setup guide vertically in the conversation viewport (the native Empty fills what it is
/// given; the transcript's content box only fits its children).
const SetupLayout = struct {
    cx: *ui.Cx,
    root: *ui.Node,
    fn release(self: *SetupLayout) void {
        self.cx.removeAfterLayoutHook(self);
    }
    fn frame(raw: *anyopaque, _: u8, _: bool) ui.AfterLayoutResult {
        const self: *SetupLayout = @ptrCast(@alignCast(raw));
        var ancestor = self.root.parent;
        while (ancestor) |node| : (ancestor = node.parent) {
            if (node.tag != .scroll) continue;
            const available = node.globalRect().h;
            const natural = self.root.globalRect().h - self.root.style.padding.top - self.root.style.padding.bottom;
            const inset = @max(0, (available - natural) / 2 - 24);
            if (@abs(self.root.style.padding.top - inset) < 0.1) return .done;
            self.root.setStyleInline(self.cx.allocator, .{ .padding = .{ .top = inset, .bottom = inset } });
            return .needs_layout;
        }
        return .done;
    }
};
/// Pencil A1 `iDZz1` / `T0ZRvt`: no usable model — the native W.Empty (sparkles · 配置模型，开始对话 · what to
/// do · 配置 AI 服务), centered. The only unconfigured guide while the conversation is empty (主会话判定:
/// the composer's Alert appears only once the conversation has history).
fn mountSetup(cx: *ui.Cx, scope: *ui.Scope, actions: Actions) !*ui.Node {
    const space = IdSpace.of(scope);
    const root = try ui.box(cx, S.setup(), .{});
    root.meta.ownership.meta.test_id = space.id("ai.empty.unconfigured");
    const click = try scope.createState(Click, .{ .context = actions.context, .run = actions.settings });
    const empty = try ui.view.render(scope, cx, ui.widgets.Empty(.{
        .icon = ui.icons.sparkles,
        .title = "配置模型，开始对话",
        .description = "添加并启用一个模型服务提供方。",
        .action_label = "配置 AI 服务",
        .on_action = cx.on(Click, click, Click.click),
        .title_test_id = space.id("ai.empty.title"),
        .action_test_id = space.id("ai.empty.settings"),
    }));
    try root.appendChild(cx.allocator, empty);
    const layout = try scope.createState(SetupLayout, .{ .cx = cx, .root = root });
    try cx.addAfterLayoutHook(layout, SetupLayout.frame);
    try scope.onCleanup(SetupLayout, layout, SetupLayout.release);
    return root;
}
