// GENERATED FILE, do not edit: generated from chrome.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Runtime fixture for window chrome written as templates (ZeroWork G28 / G29): a glass sidebar
//! that fills its column with a flexible scroll list (`W.GlassBox fill`), and a content page whose
//! viewport carries its own scroll edge effect (`W.ScrollArea scrollEdge`) under a titlebar edge
//! (`W.TitlebarEdge`). Lives outside tests/yix so it is not an LP3 equivalence input.
const ui = @import("ui");
const W = ui.widgets;

pub fn Sidebar(args: anytype) ui.view.ComponentOf(__yix_Sidebar) {
    return ui.view.component(__yix_Sidebar, ui.reactive.props.coerce(SidebarProps, args));
}
pub const SidebarProps = struct {
    rows: ui.Source(usize) = .{ .value = 3 },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Sidebar;
    pub const __yix_preview_mount = __yix_Sidebar;
};
fn __yix_Sidebar(__yix_props: SidebarProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const rows = __yix_props.rows;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .rows = rows, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Sidebar", .receiver = "W.GlassBox", .tokens = "< W . GlassBox testId = \"chrome.nav\" width = { 216 } fill = { . height } padding = { . { . top = 10 , . right = 8 , . bottom = 10 , . left = 8 } } bodyGap = { 12 } > < box testId = \"chrome.nav.top\" style = { . { . height = . { . px = 28 } } } / > < W . ScrollArea testId = \"chrome.nav.list\" direction = { . vertical } style = { . { . height = . { . grow = . { . min = 0 } } } } > < text > { rows } < / text > < / W . ScrollArea > < box testId = \"chrome.nav.note\" style = { . { . height = . { . px = 20 } } } / > < / W . GlassBox > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.nav\" ", .kind = .property, .literal = .{ .text = "chrome.nav" } }, .{ .name = "width", .tokens = "216 ", .kind = .property, .literal = .{ .number = 216 } }, .{ .name = "fill", .tokens = ". height ", .kind = .property, .literal = .{ .enum_name = "height" } }, .{ .name = "padding", .tokens = ". { . top = 10 , . right = 8 , . bottom = 10 , . left = 8 } ", .kind = .property, .literal = null }, .{ .name = "body_gap", .tokens = "12 ", .kind = .property, .literal = .{ .number = 12 } }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .rows = __yix_view_ctx.rows, }, ui.view.templateAttrs(.{ .test_id = "chrome.nav", }, __yix_builder_491: { try ui.view.previewCheckBuilder(__yix_view_scope, W.GlassBox); break :__yix_builder_491 ui.view.with(W.GlassBox(.{ .width = 216, .fill = .height, .padding = .{ .top = 10, .right = 8, .bottom = 10, .left = 8 }, .body_gap = 12, }), .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Sidebar", .receiver = "box", .tokens = "box testId = @static; style = . { . height = . { . px = 28 } } ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.nav.top\" ", .kind = .property, .literal = .{ .text = "chrome.nav.top" } }, .{ .name = "style", .tokens = ". { . height = . { . px = 28 } } ", .kind = .style, .literal = null }, } }, .{ }, ui.view.box(.{ .test_id = "chrome.nav.top", .style = .{ .height = .{ .px = 28 } }, }, .{ })),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Sidebar", .receiver = "W.ScrollArea", .tokens = "< W . ScrollArea testId = \"chrome.nav.list\" direction = { . vertical } style = { . { . height = . { . grow = . { . min = 0 } } } } > < text > { rows } < / text > < / W . ScrollArea > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.nav.list\" ", .kind = .property, .literal = .{ .text = "chrome.nav.list" } }, .{ .name = "direction", .tokens = ". vertical ", .kind = .property, .literal = .{ .enum_name = "vertical" } }, .{ .name = "style", .tokens = ". { . height = . { . grow = . { . min = 0 } } } ", .kind = .style, .literal = null }, } }, .{ .rows = __yix_view_ctx.rows, }, ui.view.templateAttrs(.{ .test_id = "chrome.nav.list", .style = .{ .height = .{ .grow = .{ .min = 0 } } }, }, __yix_builder_719: { try ui.view.previewCheckBuilder(__yix_view_scope, W.ScrollArea); break :__yix_builder_719 ui.view.with(W.ScrollArea(.{ .direction = .vertical, }), .{
                ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Sidebar", .receiver = "text", .tokens = "text rows  @interpolation ", .literal_text = null, .attributes = &.{ } }, .{ .rows = __yix_view_ctx.rows, }, ui.view.text(.{ }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_view_ctx.rows), ""), .{ __yix_view_ctx.rows, }))),
            }); })),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Sidebar", .receiver = "box", .tokens = "box testId = @static; style = . { . height = . { . px = 20 } } ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.nav.note\" ", .kind = .property, .literal = .{ .text = "chrome.nav.note" } }, .{ .name = "style", .tokens = ". { . height = . { . px = 20 } } ", .kind = .style, .literal = null }, } }, .{ }, ui.view.box(.{ .test_id = "chrome.nav.note", .style = .{ .height = .{ .px = 20 } }, }, .{ })),
        }); })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Sidebar";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

pub fn Page(args: anytype) ui.view.ComponentOf(__yix_Page) {
    return ui.view.component(__yix_Page, ui.reactive.props.coerce(PageProps, args));
}
pub const PageProps = struct {
    edge_height: ui.Source(f32) = .{ .value = 48 },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Page;
    pub const __yix_preview_mount = __yix_Page;
};
fn __yix_Page(__yix_props: PageProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const edgeHeight = __yix_props.edge_height;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .edgeHeight = edgeHeight, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Page", .receiver = "box", .tokens = "box testId = @static; style = . { . width = . { . grow = . { } } , . height = . { . grow = . { } } , . position = . relative } ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.page\" ", .kind = .property, .literal = .{ .text = "chrome.page" } }, .{ .name = "style", .tokens = ". { . width = . { . grow = . { } } , . height = . { . grow = . { } } , . position = . relative } ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .edgeHeight = __yix_view_ctx.edgeHeight, }, ui.view.box(.{ .test_id = "chrome.page", .style = .{ .width = .{ .grow = .{} }, .height = .{ .grow = .{} }, .position = .relative }, }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Page", .receiver = "W.ScrollArea", .tokens = "< W . ScrollArea testId = \"chrome.viewport\" direction = { . vertical } scrollEdge = { . { . edge = . top , . style = . soft , . height = edgeHeight } } > < box style = { . { . height = . { . px = 2000 } } } / > < / W . ScrollArea > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.viewport\" ", .kind = .property, .literal = .{ .text = "chrome.viewport" } }, .{ .name = "direction", .tokens = ". vertical ", .kind = .property, .literal = .{ .enum_name = "vertical" } }, .{ .name = "scroll_edge", .tokens = ". { . edge = . top , . style = . soft , . height = edgeHeight } ", .kind = .property, .literal = null }, } }, .{ .edgeHeight = __yix_view_ctx.edgeHeight, }, ui.view.templateAttrs(.{ .test_id = "chrome.viewport", }, __yix_builder_1200: { try ui.view.previewCheckBuilder(__yix_view_scope, W.ScrollArea); break :__yix_builder_1200 ui.view.with(W.ScrollArea(.{ .direction = .vertical, .scroll_edge = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.ScrollArea, "scroll_edge")) |__yix_A| __yix_A else @TypeOf(.{ .edge = .top, .style = .soft, .height = __yix_view_ctx.edgeHeight.peek() });
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .edgeHeight = __yix_view_ctx.edgeHeight, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return .{ .edge = .top, .style = .soft, .height = __yix_ctx.edgeHeight.get() };
        } }.__yix_compute);
    }, }), .{
                ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Page", .receiver = "box", .tokens = "box style = . { . height = . { . px = 2000 } } ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = ". { . height = . { . px = 2000 } } ", .kind = .style, .literal = null }, } }, .{ }, ui.view.box(.{ .style = .{ .height = .{ .px = 2000 } }, }, .{ })),
            }); })),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Page", .receiver = "W.TitlebarEdge", .tokens = "< W . TitlebarEdge testId = \"chrome.edge\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.edge\" ", .kind = .property, .literal = .{ .text = "chrome.edge" } }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "chrome.edge", }, __yix_builder_1434: { try ui.view.previewCheckBuilder(__yix_view_scope, W.TitlebarEdge); break :__yix_builder_1434 W.TitlebarEdge(.{ }); })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Page";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

pub fn Shell(args: anytype) ui.view.ComponentOf(__yix_Shell) {
    return ui.view.component(__yix_Shell, ui.reactive.props.coerce(ShellProps, args));
}
pub const ShellProps = struct {
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Shell;
    pub const __yix_preview_mount = __yix_Shell;
};
fn __yix_Shell(__yix_props: ShellProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    _ = __yix_props;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    _ = __yix_view_ctx;
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Shell", .receiver = "row", .tokens = "row testId = @static; style = . { . width = . { . px = 900 } , . height = . { . px = 600 } } ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.shell\" ", .kind = .property, .literal = .{ .text = "chrome.shell" } }, .{ .name = "style", .tokens = ". { . width = . { . px = 900 } , . height = . { . px = 600 } } ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ }, ui.view.row(.{ .test_id = "chrome.shell", .style = .{ .width = .{ .px = 900 }, .height = .{ .px = 600 } }, }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Shell", .receiver = "Sidebar", .tokens = "< Sidebar / > ", .literal_text = null, .attributes = &.{ } }, .{ }, __yix_builder_1645: { try ui.view.previewCheckBuilder(__yix_view_scope, Sidebar); break :__yix_builder_1645 Sidebar(.{ }); }),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Shell", .receiver = "Page", .tokens = "< Page / > ", .literal_text = null, .attributes = &.{ } }, .{ }, __yix_builder_1669: { try ui.view.previewCheckBuilder(__yix_view_scope, Page); break :__yix_builder_1669 Page(.{ }); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Shell";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// G27: history buttons as a toolbar group in a header row; back is disabled by a parameter.
pub fn Header(args: anytype) ui.view.ComponentOf(__yix_Header) {
    return ui.view.component(__yix_Header, ui.reactive.props.coerce(HeaderProps, args));
}
pub const HeaderProps = struct {
    can_back: ui.Source(bool) = .{ .value = false },
    on_back: ?ui.Handler(void) = null,
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Header;
    pub const __yix_preview_mount = __yix_Header;
};
fn __yix_Header(__yix_props: HeaderProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const canBack = __yix_props.can_back;
    const onBack = __yix_props.on_back;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .canBack = canBack, .onBack = onBack, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Header", .receiver = "row", .tokens = "row testId = @static; style = . { . width = . { . px = 600 } , . height = . { . px = 48 } , . align_items = . center } ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.header\" ", .kind = .property, .literal = .{ .text = "chrome.header" } }, .{ .name = "style", .tokens = ". { . width = . { . px = 600 } , . height = . { . px = 48 } , . align_items = . center } ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .canBack = __yix_view_ctx.canBack, .onBack = __yix_view_ctx.onBack, }, ui.view.row(.{ .test_id = "chrome.header", .style = .{ .width = .{ .px = 600 }, .height = .{ .px = 48 }, .align_items = .center }, }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Header", .receiver = "W.GlassToolbarGroup", .tokens = "< W . GlassToolbarGroup testId = \"chrome.history\" label = \"History\" > < W . GlassToolbarButton testId = \"chrome.history.back\" icon = { ui . icons . chevron_left } label = \"Back\" disabled = { ! canBack } onClick = { onBack } / > < W . GlassToolbarButton testId = \"chrome.history.forward\" icon = { ui . icons . chevron_right } label = \"Forward\" disabled = { true } / > < / W . GlassToolbarGroup > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.history\" ", .kind = .property, .literal = .{ .text = "chrome.history" } }, .{ .name = "label", .tokens = "\"History\" ", .kind = .property, .literal = .{ .text = "History" } }, } }, .{ .canBack = __yix_view_ctx.canBack, .onBack = __yix_view_ctx.onBack, }, ui.view.templateAttrs(.{ .test_id = "chrome.history", }, __yix_builder_2020: { try ui.view.previewCheckBuilder(__yix_view_scope, W.GlassToolbarGroup); break :__yix_builder_2020 ui.view.with(W.GlassToolbarGroup(.{ .label = "History", }), .{
                ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Header", .receiver = "W.GlassToolbarButton", .tokens = "< W . GlassToolbarButton testId = \"chrome.history.back\" icon = { ui . icons . chevron_left } label = \"Back\" disabled = { ! canBack } onClick = { onBack } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.history.back\" ", .kind = .property, .literal = .{ .text = "chrome.history.back" } }, .{ .name = "icon", .tokens = "ui . icons . chevron_left ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"Back\" ", .kind = .property, .literal = .{ .text = "Back" } }, .{ .name = "disabled", .tokens = "! canBack ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "onBack ", .kind = .event, .literal = null }, } }, .{ .canBack = __yix_view_ctx.canBack, .onBack = __yix_view_ctx.onBack, }, ui.view.templateAttrs(.{ .test_id = "chrome.history.back", }, __yix_builder_2098: { try ui.view.previewCheckBuilder(__yix_view_scope, W.GlassToolbarButton); break :__yix_builder_2098 W.GlassToolbarButton(.{ .icon = ui.icons.chevron_left, .label = "Back", .disabled = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.GlassToolbarButton, "disabled")) |__yix_A| __yix_A else @TypeOf(!__yix_view_ctx.canBack.peek());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .canBack = __yix_view_ctx.canBack, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !__yix_ctx.canBack.get();
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.GlassToolbarButton, "on_click")) __yix_view_ctx.onBack else __yix_view_ctx.onBack, }); })),
                ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Header", .receiver = "W.GlassToolbarButton", .tokens = "< W . GlassToolbarButton testId = \"chrome.history.forward\" icon = { ui . icons . chevron_right } label = \"Forward\" disabled = { true } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.history.forward\" ", .kind = .property, .literal = .{ .text = "chrome.history.forward" } }, .{ .name = "icon", .tokens = "ui . icons . chevron_right ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"Forward\" ", .kind = .property, .literal = .{ .text = "Forward" } }, .{ .name = "disabled", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "chrome.history.forward", }, __yix_builder_2247: { try ui.view.previewCheckBuilder(__yix_view_scope, W.GlassToolbarButton); break :__yix_builder_2247 W.GlassToolbarButton(.{ .icon = ui.icons.chevron_right, .label = "Forward", .disabled = true, }); })),
            }); })),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Header", .receiver = "spacer", .tokens = "spacer ", .literal_text = null, .attributes = &.{ } }, .{ }, ui.view.spacer()),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Header", .receiver = "W.GlassToolbar", .tokens = "< W . GlassToolbar testId = \"chrome.toolbar\" > < W . GlassToolbarGroup > < W . GlassToolbarButton icon = { ui . icons . search } label = \"Search\" / > < / W . GlassToolbarGroup > < / W . GlassToolbar > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.toolbar\" ", .kind = .property, .literal = .{ .text = "chrome.toolbar" } }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "chrome.toolbar", }, __yix_builder_2436: { try ui.view.previewCheckBuilder(__yix_view_scope, W.GlassToolbar); break :__yix_builder_2436 ui.view.with(W.GlassToolbar(.{ }), .{
                ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Header", .receiver = "W.GlassToolbarGroup", .tokens = "< W . GlassToolbarGroup > < W . GlassToolbarButton icon = { ui . icons . search } label = \"Search\" / > < / W . GlassToolbarGroup > ", .literal_text = null, .attributes = &.{ } }, .{ }, __yix_builder_2493: { try ui.view.previewCheckBuilder(__yix_view_scope, W.GlassToolbarGroup); break :__yix_builder_2493 ui.view.with(W.GlassToolbarGroup(.{ }), .{
                    ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Header", .receiver = "W.GlassToolbarButton", .tokens = "< W . GlassToolbarButton icon = { ui . icons . search } label = \"Search\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "icon", .tokens = "ui . icons . search ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"Search\" ", .kind = .property, .literal = .{ .text = "Search" } }, } }, .{ }, __yix_builder_2535: { try ui.view.previewCheckBuilder(__yix_view_scope, W.GlassToolbarButton); break :__yix_builder_2535 W.GlassToolbarButton(.{ .icon = ui.icons.search, .label = "Search", }); }),
                }); }),
            }); })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Header";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// G32 / G33: a shortcut row (keycaps following parameters) and an external link button with a
/// trailing icon.
pub fn ShortcutRow(args: anytype) ui.view.ComponentOf(__yix_ShortcutRow) {
    return ui.view.component(__yix_ShortcutRow, ui.reactive.props.coerce(ShortcutRowProps, args));
}
pub const ShortcutRowProps = struct {
    caps: ui.Source([]const []const u8) = .{ .value = &.{} },
    tone: ui.Source(W.KbdTone) = .{ .value = .neutral },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ShortcutRow;
    pub const __yix_preview_mount = __yix_ShortcutRow;
};
fn __yix_ShortcutRow(__yix_props: ShortcutRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const caps = __yix_props.caps;
    const tone = __yix_props.tone;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .caps = caps, .tone = tone, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "ShortcutRow", .receiver = "row", .tokens = "row testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.shortcut\" ", .kind = .property, .literal = .{ .text = "chrome.shortcut" } }, .{ .name = "style", .tokens = ". { . align_items = . center } ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .caps = __yix_view_ctx.caps, .tone = __yix_view_ctx.tone, }, ui.view.row(.{ .test_id = "chrome.shortcut", .style = .{ .align_items = .center }, }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "ShortcutRow", .receiver = "W.Kbd", .tokens = "< W . Kbd testId = \"chrome.kbd\" keys = { caps } tone = { tone } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.kbd\" ", .kind = .property, .literal = .{ .text = "chrome.kbd" } }, .{ .name = "keys", .tokens = "caps ", .kind = .property, .literal = null }, .{ .name = "tone", .tokens = "tone ", .kind = .property, .literal = null }, } }, .{ .caps = __yix_view_ctx.caps, .tone = __yix_view_ctx.tone, }, ui.view.templateAttrs(.{ .test_id = "chrome.kbd", }, __yix_builder_2994: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Kbd); break :__yix_builder_2994 W.Kbd(.{ .keys = __yix_view_ctx.caps, .tone = __yix_view_ctx.tone, }); })),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "ShortcutRow", .receiver = "W.Button", .tokens = "< W . Button testId = \"chrome.link\" label = \"GitHub\" variant = { . link } iconAsset = { ui . icons . external_link } iconPosition = { . trailing } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.link\" ", .kind = .property, .literal = .{ .text = "chrome.link" } }, .{ .name = "label", .tokens = "\"GitHub\" ", .kind = .property, .literal = .{ .text = "GitHub" } }, .{ .name = "variant", .tokens = ". link ", .kind = .property, .literal = .{ .enum_name = "link" } }, .{ .name = "icon_asset", .tokens = "ui . icons . external_link ", .kind = .property, .literal = null }, .{ .name = "icon_position", .tokens = ". trailing ", .kind = .property, .literal = .{ .enum_name = "trailing" } }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "chrome.link", }, __yix_builder_3060: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_3060 W.Button(.{ .label = "GitHub", .variant = .link, .icon_asset = ui.icons.external_link, .icon_position = .trailing, }); })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ShortcutRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// G38: the window's notification stack declared in a template, driven by a post source.
pub fn Toasts(args: anytype) ui.view.ComponentOf(__yix_Toasts) {
    return ui.view.component(__yix_Toasts, ui.reactive.props.coerce(ToastsProps, args));
}
pub const ToastsProps = struct {
    post: ui.Source(W.NotificationPost) = .{ .value = .{} },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Toasts;
    pub const __yix_preview_mount = __yix_Toasts;
};
fn __yix_Toasts(__yix_props: ToastsProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const post = __yix_props.post;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .post = post, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Toasts", .receiver = "box", .tokens = "box testId = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.toasts\" ", .kind = .property, .literal = .{ .text = "chrome.toasts" } }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .post = __yix_view_ctx.post, }, ui.view.box(.{ .test_id = "chrome.toasts", }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "Toasts", .receiver = "W.NotificationHost", .tokens = "< W . NotificationHost post = { post } position = { . top_right } / > ", .literal_text = null, .attributes = &.{ .{ .name = "post", .tokens = "post ", .kind = .property, .literal = null }, .{ .name = "position", .tokens = ". top_right ", .kind = .property, .literal = .{ .enum_name = "top_right" } }, } }, .{ .post = __yix_view_ctx.post, }, __yix_builder_3392: { try ui.view.previewCheckBuilder(__yix_view_scope, W.NotificationHost); break :__yix_builder_3392 W.NotificationHost(.{ .post = __yix_view_ctx.post, .position = .top_right, }); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Toasts";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// G35: builders whose Props declare `test_id` (Slider: the track) take `testId` there.
/// G35 with a `ref` on the element (the builder is wrapped): `testId` still lands on the track.
pub fn SliderRefRow(args: anytype) ui.view.ComponentOf(__yix_SliderRefRow) {
    return ui.view.component(__yix_SliderRefRow, ui.reactive.props.coerce(SliderRefRowProps, args));
}
pub const SliderRefRowProps = struct {
    id: ui.Source([]const u8) = .{ .value = "chrome.slider.ref" },
    slider: ui.Source(*ui.view.Ref(W.slider.SliderResult)),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = SliderRefRow;
    pub const __yix_preview_mount = __yix_SliderRefRow;
};
fn __yix_SliderRefRow(__yix_props: SliderRefRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const id = __yix_props.id;
    const slider = __yix_props.slider;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .id = id, .slider = slider, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "SliderRefRow", .receiver = "row", .tokens = "row testId = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.slider.ref.row\" ", .kind = .property, .literal = .{ .text = "chrome.slider.ref.row" } }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .id = __yix_view_ctx.id, .slider = __yix_view_ctx.slider, }, ui.view.row(.{ .test_id = "chrome.slider.ref.row", }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "SliderRefRow", .receiver = "W.Slider", .tokens = "< W . Slider ref = { slider } testId = { id } value = { 0.5 } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "slider ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "id ", .kind = .property, .literal = null }, .{ .name = "value", .tokens = "0.5 ", .kind = .property, .literal = .{ .number = 0.5 } }, } }, .{ .id = __yix_view_ctx.id, .slider = __yix_view_ctx.slider, }, ui.view.templateAttrs(.{ .test_id = __yix_view_ctx.id, }, ui.view.ref(__yix_view_ctx.slider, __yix_builder_3825: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Slider); break :__yix_builder_3825 W.Slider(.{ .value = 0.5, }); }))),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "SliderRefRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

pub fn SliderRow(args: anytype) ui.view.ComponentOf(__yix_SliderRow) {
    return ui.view.component(__yix_SliderRow, ui.reactive.props.coerce(SliderRowProps, args));
}
pub const SliderRowProps = struct {
    id: ui.Source([]const u8) = .{ .value = "chrome.slider" },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = SliderRow;
    pub const __yix_preview_mount = __yix_SliderRow;
};
fn __yix_SliderRow(__yix_props: SliderRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const id = __yix_props.id;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .id = id, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "SliderRow", .receiver = "row", .tokens = "row testId = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.slider.row\" ", .kind = .property, .literal = .{ .text = "chrome.slider.row" } }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .id = __yix_view_ctx.id, }, ui.view.row(.{ .test_id = "chrome.slider.row", }, .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "SliderRow", .receiver = "W.Slider", .tokens = "< W . Slider testId = { id } value = { 0.5 } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "id ", .kind = .property, .literal = null }, .{ .name = "value", .tokens = "0.5 ", .kind = .property, .literal = .{ .number = 0.5 } }, } }, .{ .id = __yix_view_ctx.id, }, ui.view.templateAttrs(.{ .test_id = __yix_view_ctx.id, }, __yix_builder_4024: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Slider); break :__yix_builder_4024 W.Slider(.{ .value = 0.5, }); })),
            ui.view.templateSite(.{ .module = "tests/yix_runtime/chrome.yix", .path = "SliderRow", .receiver = "W.GlassToolbar", .tokens = "< W . GlassToolbar testId = \"chrome.slider.toolbar\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"chrome.slider.toolbar\" ", .kind = .property, .literal = .{ .text = "chrome.slider.toolbar" } }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "chrome.slider.toolbar", }, __yix_builder_4073: { try ui.view.previewCheckBuilder(__yix_view_scope, W.GlassToolbar); break :__yix_builder_4073 W.GlassToolbar(.{ }); })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "SliderRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\x52\x75\x6e\x74\x69\x6d\x65\x20\x66\x69\x78\x74\x75\x72\x65\x20\x66\x6f\x72\x20\x77\x69\x6e\x64\x6f\x77\x20\x63\x68\x72\x6f\x6d\x65\x20\x77\x72\x69\x74\x74\x65\x6e\x20\x61\x73\x20\x74\x65\x6d\x70\x6c\x61\x74\x65\x73\x20\x28\x5a\x65\x72\x6f\x57\x6f\x72\x6b\x20\x47\x32\x38\x20\x2f\x20\x47\x32\x39\x29\x3a\x20\x61\x20\x67\x6c\x61\x73\x73\x20\x73\x69\x64\x65\x62\x61\x72\x0a\x2f\x2f\x21\x20\x74\x68\x61\x74\x20\x66\x69\x6c\x6c\x73\x20\x69\x74\x73\x20\x63\x6f\x6c\x75\x6d\x6e\x20\x77\x69\x74\x68\x20\x61\x20\x66\x6c\x65\x78\x69\x62\x6c\x65\x20\x73\x63\x72\x6f\x6c\x6c\x20\x6c\x69\x73\x74\x20\x28\x60\x57\x2e\x47\x6c\x61\x73\x73\x42\x6f\x78\x20\x66\x69\x6c\x6c\x60\x29\x2c\x20\x61\x6e\x64\x20\x61\x20\x63\x6f\x6e\x74\x65\x6e\x74\x20\x70\x61\x67\x65\x20\x77\x68\x6f\x73\x65\x0a\x2f\x2f\x21\x20\x76\x69\x65\x77\x70\x6f\x72\x74\x20\x63\x61\x72\x72\x69\x65\x73\x20\x69\x74\x73\x20\x6f\x77\x6e\x20\x73\x63\x72\x6f\x6c\x6c\x20\x65\x64\x67\x65\x20\x65\x66\x66\x65\x63\x74\x20\x28\x60\x57\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x20\x73\x63\x72\x6f\x6c\x6c\x45\x64\x67\x65\x60\x29\x20\x75\x6e\x64\x65\x72\x20\x61\x20\x74\x69\x74\x6c\x65\x62\x61\x72\x20\x65\x64\x67\x65\x0a\x2f\x2f\x21\x20\x28\x60\x57\x2e\x54\x69\x74\x6c\x65\x62\x61\x72\x45\x64\x67\x65\x60\x29\x2e\x20\x4c\x69\x76\x65\x73\x20\x6f\x75\x74\x73\x69\x64\x65\x20\x74\x65\x73\x74\x73\x2f\x79\x69\x78\x20\x73\x6f\x20\x69\x74\x20\x69\x73\x20\x6e\x6f\x74\x20\x61\x6e\x20\x4c\x50\x33\x20\x65\x71\x75\x69\x76\x61\x6c\x65\x6e\x63\x65\x20\x69\x6e\x70\x75\x74\x2e\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x53\x69\x64\x65\x62\x61\x72\x28\x72\x6f\x77\x73\x3a\x20\x75\x73\x69\x7a\x65\x20\x3d\x20\x33\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x47\x6c\x61\x73\x73\x42\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x6e\x61\x76\x22\x20\x77\x69\x64\x74\x68\x3d\x7b\x32\x31\x36\x7d\x20\x66\x69\x6c\x6c\x3d\x7b\x2e\x68\x65\x69\x67\x68\x74\x7d\x20\x70\x61\x64\x64\x69\x6e\x67\x3d\x7b\x2e\x7b\x20\x2e\x74\x6f\x70\x20\x3d\x20\x31\x30\x2c\x20\x2e\x72\x69\x67\x68\x74\x20\x3d\x20\x38\x2c\x20\x2e\x62\x6f\x74\x74\x6f\x6d\x20\x3d\x20\x31\x30\x2c\x20\x2e\x6c\x65\x66\x74\x20\x3d\x20\x38\x20\x7d\x7d\x20\x62\x6f\x64\x79\x47\x61\x70\x3d\x7b\x31\x32\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x6e\x61\x76\x2e\x74\x6f\x70\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x2e\x7b\x20\x2e\x68\x65\x69\x67\x68\x74\x20\x3d\x20\x2e\x7b\x20\x2e\x70\x78\x20\x3d\x20\x32\x38\x20\x7d\x20\x7d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x6e\x61\x76\x2e\x6c\x69\x73\x74\x22\x20\x64\x69\x72\x65\x63\x74\x69\x6f\x6e\x3d\x7b\x2e\x76\x65\x72\x74\x69\x63\x61\x6c\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x2e\x7b\x20\x2e\x68\x65\x69\x67\x68\x74\x20\x3d\x20\x2e\x7b\x20\x2e\x67\x72\x6f\x77\x20\x3d\x20\x2e\x7b\x20\x2e\x6d\x69\x6e\x20\x3d\x20\x30\x20\x7d\x20\x7d\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x3e\x7b\x72\x6f\x77\x73\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x6e\x61\x76\x2e\x6e\x6f\x74\x65\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x2e\x7b\x20\x2e\x68\x65\x69\x67\x68\x74\x20\x3d\x20\x2e\x7b\x20\x2e\x70\x78\x20\x3d\x20\x32\x30\x20\x7d\x20\x7d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x47\x6c\x61\x73\x73\x42\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x50\x61\x67\x65\x28\x65\x64\x67\x65\x48\x65\x69\x67\x68\x74\x3a\x20\x66\x33\x32\x20\x3d\x20\x34\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x70\x61\x67\x65\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x2e\x7b\x20\x2e\x77\x69\x64\x74\x68\x20\x3d\x20\x2e\x7b\x20\x2e\x67\x72\x6f\x77\x20\x3d\x20\x2e\x7b\x7d\x20\x7d\x2c\x20\x2e\x68\x65\x69\x67\x68\x74\x20\x3d\x20\x2e\x7b\x20\x2e\x67\x72\x6f\x77\x20\x3d\x20\x2e\x7b\x7d\x20\x7d\x2c\x20\x2e\x70\x6f\x73\x69\x74\x69\x6f\x6e\x20\x3d\x20\x2e\x72\x65\x6c\x61\x74\x69\x76\x65\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x76\x69\x65\x77\x70\x6f\x72\x74\x22\x20\x64\x69\x72\x65\x63\x74\x69\x6f\x6e\x3d\x7b\x2e\x76\x65\x72\x74\x69\x63\x61\x6c\x7d\x20\x73\x63\x72\x6f\x6c\x6c\x45\x64\x67\x65\x3d\x7b\x2e\x7b\x20\x2e\x65\x64\x67\x65\x20\x3d\x20\x2e\x74\x6f\x70\x2c\x20\x2e\x73\x74\x79\x6c\x65\x20\x3d\x20\x2e\x73\x6f\x66\x74\x2c\x20\x2e\x68\x65\x69\x67\x68\x74\x20\x3d\x20\x65\x64\x67\x65\x48\x65\x69\x67\x68\x74\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x2e\x7b\x20\x2e\x68\x65\x69\x67\x68\x74\x20\x3d\x20\x2e\x7b\x20\x2e\x70\x78\x20\x3d\x20\x32\x30\x30\x30\x20\x7d\x20\x7d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x69\x74\x6c\x65\x62\x61\x72\x45\x64\x67\x65\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x65\x64\x67\x65\x22\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x53\x68\x65\x6c\x6c\x28\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x73\x68\x65\x6c\x6c\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x2e\x7b\x20\x2e\x77\x69\x64\x74\x68\x20\x3d\x20\x2e\x7b\x20\x2e\x70\x78\x20\x3d\x20\x39\x30\x30\x20\x7d\x2c\x20\x2e\x68\x65\x69\x67\x68\x74\x20\x3d\x20\x2e\x7b\x20\x2e\x70\x78\x20\x3d\x20\x36\x30\x30\x20\x7d\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x53\x69\x64\x65\x62\x61\x72\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x50\x61\x67\x65\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x47\x32\x37\x3a\x20\x68\x69\x73\x74\x6f\x72\x79\x20\x62\x75\x74\x74\x6f\x6e\x73\x20\x61\x73\x20\x61\x20\x74\x6f\x6f\x6c\x62\x61\x72\x20\x67\x72\x6f\x75\x70\x20\x69\x6e\x20\x61\x20\x68\x65\x61\x64\x65\x72\x20\x72\x6f\x77\x3b\x20\x62\x61\x63\x6b\x20\x69\x73\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x20\x62\x79\x20\x61\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x48\x65\x61\x64\x65\x72\x28\x63\x61\x6e\x42\x61\x63\x6b\x3a\x20\x62\x6f\x6f\x6c\x20\x3d\x20\x66\x61\x6c\x73\x65\x2c\x20\x6f\x6e\x42\x61\x63\x6b\x3a\x20\x3f\x48\x61\x6e\x64\x6c\x65\x72\x28\x76\x6f\x69\x64\x29\x20\x3d\x20\x6e\x75\x6c\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x68\x65\x61\x64\x65\x72\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x2e\x7b\x20\x2e\x77\x69\x64\x74\x68\x20\x3d\x20\x2e\x7b\x20\x2e\x70\x78\x20\x3d\x20\x36\x30\x30\x20\x7d\x2c\x20\x2e\x68\x65\x69\x67\x68\x74\x20\x3d\x20\x2e\x7b\x20\x2e\x70\x78\x20\x3d\x20\x34\x38\x20\x7d\x2c\x20\x2e\x61\x6c\x69\x67\x6e\x5f\x69\x74\x65\x6d\x73\x20\x3d\x20\x2e\x63\x65\x6e\x74\x65\x72\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x47\x6c\x61\x73\x73\x54\x6f\x6f\x6c\x62\x61\x72\x47\x72\x6f\x75\x70\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x68\x69\x73\x74\x6f\x72\x79\x22\x20\x6c\x61\x62\x65\x6c\x3d\x22\x48\x69\x73\x74\x6f\x72\x79\x22\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x47\x6c\x61\x73\x73\x54\x6f\x6f\x6c\x62\x61\x72\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x68\x69\x73\x74\x6f\x72\x79\x2e\x62\x61\x63\x6b\x22\x20\x69\x63\x6f\x6e\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x68\x65\x76\x72\x6f\x6e\x5f\x6c\x65\x66\x74\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\x42\x61\x63\x6b\x22\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x21\x63\x61\x6e\x42\x61\x63\x6b\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x6f\x6e\x42\x61\x63\x6b\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x47\x6c\x61\x73\x73\x54\x6f\x6f\x6c\x62\x61\x72\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x68\x69\x73\x74\x6f\x72\x79\x2e\x66\x6f\x72\x77\x61\x72\x64\x22\x20\x69\x63\x6f\x6e\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x68\x65\x76\x72\x6f\x6e\x5f\x72\x69\x67\x68\x74\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\x46\x6f\x72\x77\x61\x72\x64\x22\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x74\x72\x75\x65\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x47\x6c\x61\x73\x73\x54\x6f\x6f\x6c\x62\x61\x72\x47\x72\x6f\x75\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x73\x70\x61\x63\x65\x72\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x47\x6c\x61\x73\x73\x54\x6f\x6f\x6c\x62\x61\x72\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x74\x6f\x6f\x6c\x62\x61\x72\x22\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x47\x6c\x61\x73\x73\x54\x6f\x6f\x6c\x62\x61\x72\x47\x72\x6f\x75\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x47\x6c\x61\x73\x73\x54\x6f\x6f\x6c\x62\x61\x72\x42\x75\x74\x74\x6f\x6e\x20\x69\x63\x6f\x6e\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x73\x65\x61\x72\x63\x68\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\x53\x65\x61\x72\x63\x68\x22\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x47\x6c\x61\x73\x73\x54\x6f\x6f\x6c\x62\x61\x72\x47\x72\x6f\x75\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x47\x6c\x61\x73\x73\x54\x6f\x6f\x6c\x62\x61\x72\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x47\x33\x32\x20\x2f\x20\x47\x33\x33\x3a\x20\x61\x20\x73\x68\x6f\x72\x74\x63\x75\x74\x20\x72\x6f\x77\x20\x28\x6b\x65\x79\x63\x61\x70\x73\x20\x66\x6f\x6c\x6c\x6f\x77\x69\x6e\x67\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x73\x29\x20\x61\x6e\x64\x20\x61\x6e\x20\x65\x78\x74\x65\x72\x6e\x61\x6c\x20\x6c\x69\x6e\x6b\x20\x62\x75\x74\x74\x6f\x6e\x20\x77\x69\x74\x68\x20\x61\x0a\x2f\x2f\x2f\x20\x74\x72\x61\x69\x6c\x69\x6e\x67\x20\x69\x63\x6f\x6e\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x53\x68\x6f\x72\x74\x63\x75\x74\x52\x6f\x77\x28\x63\x61\x70\x73\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x26\x2e\x7b\x7d\x2c\x20\x74\x6f\x6e\x65\x3a\x20\x57\x2e\x4b\x62\x64\x54\x6f\x6e\x65\x20\x3d\x20\x2e\x6e\x65\x75\x74\x72\x61\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x73\x68\x6f\x72\x74\x63\x75\x74\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x2e\x7b\x20\x2e\x61\x6c\x69\x67\x6e\x5f\x69\x74\x65\x6d\x73\x20\x3d\x20\x2e\x63\x65\x6e\x74\x65\x72\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x4b\x62\x64\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x6b\x62\x64\x22\x20\x6b\x65\x79\x73\x3d\x7b\x63\x61\x70\x73\x7d\x20\x74\x6f\x6e\x65\x3d\x7b\x74\x6f\x6e\x65\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x6c\x69\x6e\x6b\x22\x20\x6c\x61\x62\x65\x6c\x3d\x22\x47\x69\x74\x48\x75\x62\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x6c\x69\x6e\x6b\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x65\x78\x74\x65\x72\x6e\x61\x6c\x5f\x6c\x69\x6e\x6b\x7d\x20\x69\x63\x6f\x6e\x50\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x72\x61\x69\x6c\x69\x6e\x67\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x47\x33\x38\x3a\x20\x74\x68\x65\x20\x77\x69\x6e\x64\x6f\x77\x27\x73\x20\x6e\x6f\x74\x69\x66\x69\x63\x61\x74\x69\x6f\x6e\x20\x73\x74\x61\x63\x6b\x20\x64\x65\x63\x6c\x61\x72\x65\x64\x20\x69\x6e\x20\x61\x20\x74\x65\x6d\x70\x6c\x61\x74\x65\x2c\x20\x64\x72\x69\x76\x65\x6e\x20\x62\x79\x20\x61\x20\x70\x6f\x73\x74\x20\x73\x6f\x75\x72\x63\x65\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x54\x6f\x61\x73\x74\x73\x28\x70\x6f\x73\x74\x3a\x20\x57\x2e\x4e\x6f\x74\x69\x66\x69\x63\x61\x74\x69\x6f\x6e\x50\x6f\x73\x74\x20\x3d\x20\x2e\x7b\x7d\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x74\x6f\x61\x73\x74\x73\x22\x3e\x3c\x57\x2e\x4e\x6f\x74\x69\x66\x69\x63\x61\x74\x69\x6f\x6e\x48\x6f\x73\x74\x20\x70\x6f\x73\x74\x3d\x7b\x70\x6f\x73\x74\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x5f\x72\x69\x67\x68\x74\x7d\x20\x2f\x3e\x3c\x2f\x62\x6f\x78\x3e\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x47\x33\x35\x3a\x20\x62\x75\x69\x6c\x64\x65\x72\x73\x20\x77\x68\x6f\x73\x65\x20\x50\x72\x6f\x70\x73\x20\x64\x65\x63\x6c\x61\x72\x65\x20\x60\x74\x65\x73\x74\x5f\x69\x64\x60\x20\x28\x53\x6c\x69\x64\x65\x72\x3a\x20\x74\x68\x65\x20\x74\x72\x61\x63\x6b\x29\x20\x74\x61\x6b\x65\x20\x60\x74\x65\x73\x74\x49\x64\x60\x20\x74\x68\x65\x72\x65\x2e\x0a\x2f\x2f\x2f\x20\x47\x33\x35\x20\x77\x69\x74\x68\x20\x61\x20\x60\x72\x65\x66\x60\x20\x6f\x6e\x20\x74\x68\x65\x20\x65\x6c\x65\x6d\x65\x6e\x74\x20\x28\x74\x68\x65\x20\x62\x75\x69\x6c\x64\x65\x72\x20\x69\x73\x20\x77\x72\x61\x70\x70\x65\x64\x29\x3a\x20\x60\x74\x65\x73\x74\x49\x64\x60\x20\x73\x74\x69\x6c\x6c\x20\x6c\x61\x6e\x64\x73\x20\x6f\x6e\x20\x74\x68\x65\x20\x74\x72\x61\x63\x6b\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x53\x6c\x69\x64\x65\x72\x52\x65\x66\x52\x6f\x77\x28\x69\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x63\x68\x72\x6f\x6d\x65\x2e\x73\x6c\x69\x64\x65\x72\x2e\x72\x65\x66\x22\x2c\x20\x73\x6c\x69\x64\x65\x72\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x57\x2e\x73\x6c\x69\x64\x65\x72\x2e\x53\x6c\x69\x64\x65\x72\x52\x65\x73\x75\x6c\x74\x29\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x73\x6c\x69\x64\x65\x72\x2e\x72\x65\x66\x2e\x72\x6f\x77\x22\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x6c\x69\x64\x65\x72\x20\x72\x65\x66\x3d\x7b\x73\x6c\x69\x64\x65\x72\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x7d\x20\x76\x61\x6c\x75\x65\x3d\x7b\x30\x2e\x35\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x53\x6c\x69\x64\x65\x72\x52\x6f\x77\x28\x69\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x63\x68\x72\x6f\x6d\x65\x2e\x73\x6c\x69\x64\x65\x72\x22\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x73\x6c\x69\x64\x65\x72\x2e\x72\x6f\x77\x22\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x6c\x69\x64\x65\x72\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x64\x7d\x20\x76\x61\x6c\x75\x65\x3d\x7b\x30\x2e\x35\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x47\x6c\x61\x73\x73\x54\x6f\x6f\x6c\x62\x61\x72\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x63\x68\x72\x6f\x6d\x65\x2e\x73\x6c\x69\x64\x65\x72\x2e\x74\x6f\x6f\x6c\x62\x61\x72\x22\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ }) else void;

//# yix-map-data [[435,435],[5758,1013],[10259,1503],[12749,1801],[21025,2811],[25041,3304],[27509,3649],[30139,3904]]

//# yix-map chrome.yix
