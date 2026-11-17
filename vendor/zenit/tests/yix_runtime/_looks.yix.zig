// GENERATED FILE, do not edit: generated from looks.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! Runtime fixture for `look` on W.Button (ui.view.Look): a style with token colors and state
//! blocks, and a recipe part whose dimension reads a parameter (derived, then carried).
const ui = @import("ui");
const W = ui.widgets;

pub const glass = ui.css(.{ .background = .bg_secondary, ._hover = .{ .background = .bg_hover } });

const Tint = ui.cva(.{
    .base = .{ .background = .bg_secondary },
    .variants = .{ .on = .{ .false = .{}, .true = .{ .background = .accent } } },
    .defaults = .{ .on = false },
});

pub fn Glass(args: anytype) ui.view.ComponentOf(__yix_Glass) {
    return ui.view.component(__yix_Glass, ui.reactive.props.coerce(GlassProps, args));
}
pub const GlassProps = struct {
    off: ui.Source(bool) = .{ .value = false },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Glass;
    pub const __yix_preview_mount = __yix_Glass;
};
fn __yix_Glass(__yix_props: GlassProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const off = __yix_props.off;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .off = off, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/looks.yix", .path = "Glass", .receiver = "W.Button", .tokens = "< W . Button label = \"Glass\" variant = { . ghost } disabled = { off } look = { glass } / > ", .literal_text = null, .attributes = &.{ .{ .name = "label", .tokens = "\"Glass\" ", .kind = .property, .literal = .{ .text = "Glass" } }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "disabled", .tokens = "off ", .kind = .property, .literal = null }, .{ .name = "look", .tokens = "glass ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .off = __yix_view_ctx.off, }, __yix_builder_574: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_574 W.Button(.{ .label = "Glass", .variant = .ghost, .disabled = __yix_view_ctx.off, .look = glass, }); }));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Glass";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

pub fn Tinted(args: anytype) ui.view.ComponentOf(__yix_Tinted) {
    return ui.view.component(__yix_Tinted, ui.reactive.props.coerce(TintedProps, args));
}
pub const TintedProps = struct {
    on: ui.Source(bool) = .{ .value = false },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Tinted;
    pub const __yix_preview_mount = __yix_Tinted;
};
fn __yix_Tinted(__yix_props: TintedProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const on = __yix_props.on;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .on = on, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/looks.yix", .path = "Tinted", .receiver = "W.Button", .tokens = "< W . Button label = \"Tinted\" variant = { . ghost } look = { Tint . of ( . { . on = on } ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "label", .tokens = "\"Tinted\" ", .kind = .property, .literal = .{ .text = "Tinted" } }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "look", .tokens = "Tint . of ( . { . on = on } ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .on = __yix_view_ctx.on, }, __yix_builder_700: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_700 W.Button(.{ .label = "Tinted", .variant = .ghost, .look = Tint.of(.{ .on = __yix_view_ctx.on }), }); }));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Tinted";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

pub fn TintedNot(args: anytype) ui.view.ComponentOf(__yix_TintedNot) {
    return ui.view.component(__yix_TintedNot, ui.reactive.props.coerce(TintedNotProps, args));
}
pub const TintedNotProps = struct {
    on: ui.Source(bool) = .{ .value = false },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = TintedNot;
    pub const __yix_preview_mount = __yix_TintedNot;
};
fn __yix_TintedNot(__yix_props: TintedNotProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const on = __yix_props.on;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .on = on, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tests/yix_runtime/looks.yix", .path = "TintedNot", .receiver = "W.Button", .tokens = "< W . Button label = \"Tinted\" variant = { . ghost } look = { Tint . of ( . { . on = ! on } ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "label", .tokens = "\"Tinted\" ", .kind = .property, .literal = .{ .text = "Tinted" } }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "look", .tokens = "Tint . of ( . { . on = ! on } ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .on = __yix_view_ctx.on, }, __yix_builder_832: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_832 W.Button(.{ .label = "Tinted", .variant = .ghost, .look = Tint.of(.{ .on = __yix_d1: {
        const __yix_T = @TypeOf(!__yix_view_ctx.on.peek());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .on = __yix_view_ctx.on, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !__yix_ctx.on.get();
        } }.__yix_compute);
    } }), }); }));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "TintedNot";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\x52\x75\x6e\x74\x69\x6d\x65\x20\x66\x69\x78\x74\x75\x72\x65\x20\x66\x6f\x72\x20\x60\x6c\x6f\x6f\x6b\x60\x20\x6f\x6e\x20\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x28\x75\x69\x2e\x76\x69\x65\x77\x2e\x4c\x6f\x6f\x6b\x29\x3a\x20\x61\x20\x73\x74\x79\x6c\x65\x20\x77\x69\x74\x68\x20\x74\x6f\x6b\x65\x6e\x20\x63\x6f\x6c\x6f\x72\x73\x20\x61\x6e\x64\x20\x73\x74\x61\x74\x65\x0a\x2f\x2f\x21\x20\x62\x6c\x6f\x63\x6b\x73\x2c\x20\x61\x6e\x64\x20\x61\x20\x72\x65\x63\x69\x70\x65\x20\x70\x61\x72\x74\x20\x77\x68\x6f\x73\x65\x20\x64\x69\x6d\x65\x6e\x73\x69\x6f\x6e\x20\x72\x65\x61\x64\x73\x20\x61\x20\x70\x61\x72\x61\x6d\x65\x74\x65\x72\x20\x28\x64\x65\x72\x69\x76\x65\x64\x2c\x20\x74\x68\x65\x6e\x20\x63\x61\x72\x72\x69\x65\x64\x29\x2e\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x0a\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x67\x6c\x61\x73\x73\x20\x3d\x20\x75\x69\x2e\x63\x73\x73\x28\x2e\x7b\x20\x2e\x62\x61\x63\x6b\x67\x72\x6f\x75\x6e\x64\x20\x3d\x20\x2e\x62\x67\x5f\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x2c\x20\x2e\x5f\x68\x6f\x76\x65\x72\x20\x3d\x20\x2e\x7b\x20\x2e\x62\x61\x63\x6b\x67\x72\x6f\x75\x6e\x64\x20\x3d\x20\x2e\x62\x67\x5f\x68\x6f\x76\x65\x72\x20\x7d\x20\x7d\x29\x3b\x0a\x0a\x63\x6f\x6e\x73\x74\x20\x54\x69\x6e\x74\x20\x3d\x20\x75\x69\x2e\x63\x76\x61\x28\x2e\x7b\x0a\x20\x20\x20\x20\x2e\x62\x61\x73\x65\x20\x3d\x20\x2e\x7b\x20\x2e\x62\x61\x63\x6b\x67\x72\x6f\x75\x6e\x64\x20\x3d\x20\x2e\x62\x67\x5f\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x20\x7d\x2c\x0a\x20\x20\x20\x20\x2e\x76\x61\x72\x69\x61\x6e\x74\x73\x20\x3d\x20\x2e\x7b\x20\x2e\x6f\x6e\x20\x3d\x20\x2e\x7b\x20\x2e\x66\x61\x6c\x73\x65\x20\x3d\x20\x2e\x7b\x7d\x2c\x20\x2e\x74\x72\x75\x65\x20\x3d\x20\x2e\x7b\x20\x2e\x62\x61\x63\x6b\x67\x72\x6f\x75\x6e\x64\x20\x3d\x20\x2e\x61\x63\x63\x65\x6e\x74\x20\x7d\x20\x7d\x20\x7d\x2c\x0a\x20\x20\x20\x20\x2e\x64\x65\x66\x61\x75\x6c\x74\x73\x20\x3d\x20\x2e\x7b\x20\x2e\x6f\x6e\x20\x3d\x20\x66\x61\x6c\x73\x65\x20\x7d\x2c\x0a\x7d\x29\x3b\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x47\x6c\x61\x73\x73\x28\x6f\x66\x66\x3a\x20\x62\x6f\x6f\x6c\x20\x3d\x20\x66\x61\x6c\x73\x65\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x6c\x61\x62\x65\x6c\x3d\x22\x47\x6c\x61\x73\x73\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x6f\x66\x66\x7d\x20\x6c\x6f\x6f\x6b\x3d\x7b\x67\x6c\x61\x73\x73\x7d\x20\x2f\x3e\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x54\x69\x6e\x74\x65\x64\x28\x6f\x6e\x3a\x20\x62\x6f\x6f\x6c\x20\x3d\x20\x66\x61\x6c\x73\x65\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x6c\x61\x62\x65\x6c\x3d\x22\x54\x69\x6e\x74\x65\x64\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x6c\x6f\x6f\x6b\x3d\x7b\x54\x69\x6e\x74\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6f\x6e\x20\x3d\x20\x6f\x6e\x20\x7d\x29\x7d\x20\x2f\x3e\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x54\x69\x6e\x74\x65\x64\x4e\x6f\x74\x28\x6f\x6e\x3a\x20\x62\x6f\x6f\x6c\x20\x3d\x20\x66\x61\x6c\x73\x65\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x6c\x61\x62\x65\x6c\x3d\x22\x54\x69\x6e\x74\x65\x64\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x6c\x6f\x6f\x6b\x3d\x7b\x54\x69\x6e\x74\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6f\x6e\x20\x3d\x20\x21\x6f\x6e\x20\x7d\x29\x7d\x20\x2f\x3e\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"glass " = glass, }) else void;

//# yix-map-data [[528,528],[2561,654],[4553,783]]

//# yix-map looks.yix
