// GENERATED FILE, do not edit: generated from popups.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Runtime fixture for the template forms of trigger components (YIX_COMPONENTS): Tooltip and Menu
//! take their trigger as children, Popover as the `trigger` named slot (children are its panel);
//! `parts={.{ .content = … }}` names the tooltip's hint panel.
const ui = @import("ui");
const W = ui.widgets;

pub fn Help(args: anytype) ui.view.ComponentOf(__yix_Help) {
    return ui.view.component(__yix_Help, ui.reactive.props.coerce(HelpProps, args));
}
pub const HelpProps = struct {
    tip: ui.Source([]const u8) = .{ .value = "" },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Help;
    pub const __yix_preview_mount = __yix_Help;
};
fn __yix_Help(__yix_props: HelpProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const tip = __yix_props.tip;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .tip = tip, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/popups.yix", .path = "Help", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { tip } openDelayMs = { 450 } testId = \"help.wrap\" parts = { . { . content = \"help.content\" } } > < W . Button label = \"?\" testId = \"help\" / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "tip ", .kind = .property, .literal = null }, .{ .name = "open_delay_ms", .tokens = "450 ", .kind = .property, .literal = .{ .number = 450 } }, .{ .name = "test_id", .tokens = "\"help.wrap\" ", .kind = .property, .literal = .{ .text = "help.wrap" } }, .{ .name = "parts", .tokens = ". { . content = \"help.content\" } ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .tip = __yix_view_ctx.tip, }, ui.view.templateAttrs(.{ .test_id = "help.wrap", .parts = .{ .content = "help.content" }, }, __yix_builder_375: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_375 ui.view.with(W.Tooltip(.{ .text = __yix_view_ctx.tip, .open_delay_ms = 450, }), .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/popups.yix", .path = "Help", .receiver = "W.Button", .tokens = "< W . Button label = \"?\" testId = \"help\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "label", .tokens = "\"?\" ", .kind = .property, .literal = .{ .text = "?" } }, .{ .name = "test_id", .tokens = "\"help\" ", .kind = .property, .literal = .{ .text = "help" } }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "help", }, __yix_builder_486: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_486 W.Button(.{ .label = "?", }); })),
        }); })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Help";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

pub fn More(args: anytype) ui.view.ComponentOf(__yix_More) {
    return ui.view.component(__yix_More, ui.reactive.props.coerce(MoreProps, args));
}
pub const MoreProps = struct {
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = More;
    pub const __yix_preview_mount = __yix_More;
};
fn __yix_More(__yix_props: MoreProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    _ = __yix_props;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    _ = __yix_view_ctx;
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/popups.yix", .path = "More", .receiver = "W.Menu", .tokens = "< W . Menu items = { & [ _ ] W . MenuItem { . { . label = \"Copy\" } } } > < W . Button label = \"More\" testId = \"more\" / > < / W . Menu > ", .literal_text = null, .attributes = &.{ .{ .name = "items", .tokens = "& [ _ ] W . MenuItem { . { . label = \"Copy\" } } ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ }, __yix_builder_596: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Menu); break :__yix_builder_596 ui.view.with(W.Menu(.{ .items = &[_]W.MenuItem{.{ .label = "Copy" }}, }), .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/popups.yix", .path = "More", .receiver = "W.Button", .tokens = "< W . Button label = \"More\" testId = \"more\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "label", .tokens = "\"More\" ", .kind = .property, .literal = .{ .text = "More" } }, .{ .name = "test_id", .tokens = "\"more\" ", .kind = .property, .literal = .{ .text = "more" } }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "more", }, __yix_builder_662: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_662 W.Button(.{ .label = "More", }); })),
        }); }));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "More";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

pub fn Info(args: anytype) ui.view.ComponentOf(__yix_Info) {
    return ui.view.component(__yix_Info, ui.reactive.props.coerce(InfoProps, args));
}
pub const InfoProps = struct {
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Info;
    pub const __yix_preview_mount = __yix_Info;
};
fn __yix_Info(__yix_props: InfoProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    _ = __yix_props;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    _ = __yix_view_ctx;
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/popups.yix", .path = "Info", .receiver = "W.Popover", .tokens = "< W . Popover trigger = { < W . Button label = \"Info\" testId = \"info\" / > } > < text testId = \"info.panel\" > details < / text > < / W . Popover > ", .literal_text = null, .attributes = &.{ .{ .name = "trigger", .tokens = "< W . Button label = \"Info\" testId = \"info\" / > ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ }, __yix_builder_772: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Popover); break :__yix_builder_772 ui.view.with(W.Popover(.{ }), .{
            ui.view.templateSite(.{ .module = "tests/yix_runtime/popups.yix", .path = "Info", .receiver = "text", .tokens = "text testId = @static; ", .literal_text = "details", .attributes = &.{ .{ .name = "test_id", .tokens = "\"info.panel\" ", .kind = .property, .literal = .{ .text = "info.panel" } }, } }, .{ }, ui.view.text(.{ .test_id = "info.panel", }, ui.view.fmt("details", .{ }))),
        }).slots(.{ .trigger = ui.view.templateSite(.{ .module = "tests/yix_runtime/popups.yix", .path = "Info/slot:trigger", .receiver = "W.Button", .tokens = "< W . Button label = \"Info\" testId = \"info\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "label", .tokens = "\"Info\" ", .kind = .property, .literal = .{ .text = "Info" } }, .{ .name = "test_id", .tokens = "\"info\" ", .kind = .property, .literal = .{ .text = "info" } }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "info", }, __yix_builder_0: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_0 W.Button(.{ .label = "Info", }); })), }); }));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Info";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\x52\x75\x6e\x74\x69\x6d\x65\x20\x66\x69\x78\x74\x75\x72\x65\x20\x66\x6f\x72\x20\x74\x68\x65\x20\x74\x65\x6d\x70\x6c\x61\x74\x65\x20\x66\x6f\x72\x6d\x73\x20\x6f\x66\x20\x74\x72\x69\x67\x67\x65\x72\x20\x63\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x73\x20\x28\x59\x49\x58\x5f\x43\x4f\x4d\x50\x4f\x4e\x45\x4e\x54\x53\x29\x3a\x20\x54\x6f\x6f\x6c\x74\x69\x70\x20\x61\x6e\x64\x20\x4d\x65\x6e\x75\x0a\x2f\x2f\x21\x20\x74\x61\x6b\x65\x20\x74\x68\x65\x69\x72\x20\x74\x72\x69\x67\x67\x65\x72\x20\x61\x73\x20\x63\x68\x69\x6c\x64\x72\x65\x6e\x2c\x20\x50\x6f\x70\x6f\x76\x65\x72\x20\x61\x73\x20\x74\x68\x65\x20\x60\x74\x72\x69\x67\x67\x65\x72\x60\x20\x6e\x61\x6d\x65\x64\x20\x73\x6c\x6f\x74\x20\x28\x63\x68\x69\x6c\x64\x72\x65\x6e\x20\x61\x72\x65\x20\x69\x74\x73\x20\x70\x61\x6e\x65\x6c\x29\x3b\x0a\x2f\x2f\x21\x20\x60\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\xe2\x80\xa6\x20\x7d\x7d\x60\x20\x6e\x61\x6d\x65\x73\x20\x74\x68\x65\x20\x74\x6f\x6f\x6c\x74\x69\x70\x27\x73\x20\x68\x69\x6e\x74\x20\x70\x61\x6e\x65\x6c\x2e\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x48\x65\x6c\x70\x28\x74\x69\x70\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x22\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x74\x69\x70\x7d\x20\x6f\x70\x65\x6e\x44\x65\x6c\x61\x79\x4d\x73\x3d\x7b\x34\x35\x30\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x68\x65\x6c\x70\x2e\x77\x72\x61\x70\x22\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x22\x68\x65\x6c\x70\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x22\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x6c\x61\x62\x65\x6c\x3d\x22\x3f\x22\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x68\x65\x6c\x70\x22\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x4d\x6f\x72\x65\x28\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x4d\x65\x6e\x75\x20\x69\x74\x65\x6d\x73\x3d\x7b\x26\x5b\x5f\x5d\x57\x2e\x4d\x65\x6e\x75\x49\x74\x65\x6d\x7b\x2e\x7b\x20\x2e\x6c\x61\x62\x65\x6c\x20\x3d\x20\x22\x43\x6f\x70\x79\x22\x20\x7d\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x6c\x61\x62\x65\x6c\x3d\x22\x4d\x6f\x72\x65\x22\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x6d\x6f\x72\x65\x22\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x4d\x65\x6e\x75\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x49\x6e\x66\x6f\x28\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x50\x6f\x70\x6f\x76\x65\x72\x20\x74\x72\x69\x67\x67\x65\x72\x3d\x7b\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x6c\x61\x62\x65\x6c\x3d\x22\x49\x6e\x66\x6f\x22\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x69\x6e\x66\x6f\x22\x20\x2f\x3e\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x69\x6e\x66\x6f\x2e\x70\x61\x6e\x65\x6c\x22\x3e\x64\x65\x74\x61\x69\x6c\x73\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x6f\x70\x6f\x76\x65\x72\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ }) else void;

//# yix-map-data [[317,317],[3171,558],[5539,734]]

//# yix-map popups.yix
