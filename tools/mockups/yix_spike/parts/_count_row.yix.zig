// GENERATED FILE, do not edit: generated from count_row.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! V-1：子目录里的 Yix 组件，用 `../` 引用上层目录的 Zig 与 Yss（同一模块内，模块根是
//! tools/mockups/yix_spike.zig 所在目录 tools/mockups/）。
const ui = @import("ui");
const S = @import("../_styles.yss.zig");
const m = @import("../vm.zig");

fn countOf(vm: *m.ViewModel) i32 { return vm.count.get(); }

pub fn CountRow(args: anytype) ui.view.ComponentOf(__yix_CountRow) {
    return ui.view.component(__yix_CountRow, ui.reactive.props.coerce(CountRowProps, args));
}
pub const CountRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    label: ui.Source([]const u8) = .{ .value = "" },
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = CountRow;
    pub const __yix_preview_mount = __yix_CountRow;
};
fn __yix_CountRow(__yix_props: CountRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const label = __yix_props.label;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .label = label, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/parts/count_row.yix", .path = "CountRow", .receiver = "row", .tokens = "row testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v1.row\" ", .kind = .property, .literal = .{ .text = "spike.v1.row" } }, .{ .name = "style", .tokens = "S . section_row ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .label = __yix_view_ctx.label, .vm = __yix_view_ctx.vm, }, ui.view.row(.{ .test_id = "spike.v1.row", .style = S.section_row, }, .{
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/parts/count_row.yix", .path = "CountRow", .receiver = "text", .tokens = "text style = @static; label  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . body_text ", .kind = .style, .literal = null }, } }, .{ .label = __yix_view_ctx.label, }, ui.view.text(.{ .style = S.body_text, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_view_ctx.label), ""), .{ __yix_view_ctx.label, }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/parts/count_row.yix", .path = "CountRow", .receiver = "text", .tokens = "text testId = @static; style = @static; countOf ( vm )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v1.count\" ", .kind = .property, .literal = .{ .text = "spike.v1.count" } }, .{ .name = "style", .tokens = "S . body_text ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = "spike.v1.count", .style = S.body_text, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(countOf(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return countOf(__yix_ctx.vm.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(countOf(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return countOf(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }))),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "CountRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\x56\x2d\x31\xef\xbc\x9a\xe5\xad\x90\xe7\x9b\xae\xe5\xbd\x95\xe9\x87\x8c\xe7\x9a\x84\x20\x59\x69\x78\x20\xe7\xbb\x84\xe4\xbb\xb6\xef\xbc\x8c\xe7\x94\xa8\x20\x60\x2e\x2e\x2f\x60\x20\xe5\xbc\x95\xe7\x94\xa8\xe4\xb8\x8a\xe5\xb1\x82\xe7\x9b\xae\xe5\xbd\x95\xe7\x9a\x84\x20\x5a\x69\x67\x20\xe4\xb8\x8e\x20\x59\x73\x73\xef\xbc\x88\xe5\x90\x8c\xe4\xb8\x80\xe6\xa8\xa1\xe5\x9d\x97\xe5\x86\x85\xef\xbc\x8c\xe6\xa8\xa1\xe5\x9d\x97\xe6\xa0\xb9\xe6\x98\xaf\x0a\x2f\x2f\x21\x20\x74\x6f\x6f\x6c\x73\x2f\x6d\x6f\x63\x6b\x75\x70\x73\x2f\x79\x69\x78\x5f\x73\x70\x69\x6b\x65\x2e\x7a\x69\x67\x20\xe6\x89\x80\xe5\x9c\xa8\xe7\x9b\xae\xe5\xbd\x95\x20\x74\x6f\x6f\x6c\x73\x2f\x6d\x6f\x63\x6b\x75\x70\x73\x2f\xef\xbc\x89\xe3\x80\x82\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x53\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x73\x74\x79\x6c\x65\x73\x2e\x79\x73\x73\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x6d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x76\x6d\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x0a\x66\x6e\x20\x63\x6f\x75\x6e\x74\x4f\x66\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x69\x33\x32\x20\x7b\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x63\x6f\x75\x6e\x74\x2e\x67\x65\x74\x28\x29\x3b\x20\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x43\x6f\x75\x6e\x74\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x6c\x61\x62\x65\x6c\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x22\x22\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x31\x2e\x72\x6f\x77\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x63\x74\x69\x6f\x6e\x5f\x72\x6f\x77\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x5f\x74\x65\x78\x74\x7d\x3e\x7b\x6c\x61\x62\x65\x6c\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x31\x2e\x63\x6f\x75\x6e\x74\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x5f\x74\x65\x78\x74\x7d\x3e\x7b\x63\x6f\x75\x6e\x74\x4f\x66\x28\x76\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"S " = S, }) else void;

//# yix-map-data [[347,342]]

//# yix-map count_row.yix
