// GENERATED FILE, do not edit: generated from card_floated.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! tab body 的空状态“卡片已浮动”（cards-float，Pencil MSg5W「Tab body · 卡片已浮动」）：单卡 tab 的卡片浮动
//! 出去、或分屏里所有卡片都浮动出去时，tab 仍在标签栏上，tab body 显示这一块：原生 `W.Empty`（图标 · 标题 ·
//! 说明 · 动作“放回标签页”，与浮动外框的“放入分屏”同一个动作：放回原位）。
const ui = @import("ui");
const W = ui.widgets;
const m = @import("card_floated_view.zig");
const S = @import("_card_floated.yss.zig");

pub fn CardFloated(args: anytype) ui.view.ComponentOf(__yix_CardFloated) {
    return ui.view.component(__yix_CardFloated, ui.reactive.props.coerce(CardFloatedProps, args));
}
pub const CardFloatedProps = struct {
    vm: ui.Source(*m.Vm),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = CardFloated;
    pub const __yix_preview_mount = __yix_CardFloated;
};
fn __yix_CardFloated(__yix_props: CardFloatedProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/workspace/view/card_floated.yix", .path = "CardFloated", .receiver = "box", .tokens = "box testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"workspace.card_floated\" ", .kind = .property, .literal = .{ .text = "workspace.card_floated" } }, .{ .name = "style", .tokens = "S . root ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = "workspace.card_floated", .style = S.root, }, .{
            ui.view.templateSite(.{ .module = "src/features/workspace/view/card_floated.yix", .path = "CardFloated", .receiver = "W.Empty", .tokens = "< W . Empty icon = { vm . icon } title = \"卡片已浮动\" description = { vm . detailText ( ) } actionLabel = \"放回标签页\" actionIconAsset = { vm . put_back_icon } onAction = { vm . putBack ( ) } titleTestId = \"workspace.card_floated.title\" descriptionTestId = \"workspace.card_floated.detail\" actionTestId = \"workspace.card_floated.put_back\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "icon", .tokens = "vm . icon ", .kind = .property, .literal = null }, .{ .name = "title", .tokens = "\"卡片已浮动\" ", .kind = .property, .literal = .{ .text = "卡片已浮动" } }, .{ .name = "description", .tokens = "vm . detailText ( ) ", .kind = .property, .literal = null }, .{ .name = "action_label", .tokens = "\"放回标签页\" ", .kind = .property, .literal = .{ .text = "放回标签页" } }, .{ .name = "action_icon_asset", .tokens = "vm . put_back_icon ", .kind = .property, .literal = null }, .{ .name = "on_action", .tokens = "vm . putBack ( ) ", .kind = .event, .literal = null }, .{ .name = "title_test_id", .tokens = "\"workspace.card_floated.title\" ", .kind = .property, .literal = .{ .text = "workspace.card_floated.title" } }, .{ .name = "description_test_id", .tokens = "\"workspace.card_floated.detail\" ", .kind = .property, .literal = .{ .text = "workspace.card_floated.detail" } }, .{ .name = "action_test_id", .tokens = "\"workspace.card_floated.put_back\" ", .kind = .property, .literal = .{ .text = "workspace.card_floated.put_back" } }, } }, .{ .vm = __yix_view_ctx.vm, }, __yix_builder_662: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Empty); break :__yix_builder_662 W.Empty(.{ .icon = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Empty, "icon")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().icon);
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().icon;
        } }.__yix_compute);
    }, .title = "卡片已浮动", .description = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Empty, "description")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().detailText());
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().detailText();
        } }.__yix_compute);
    }, .action_label = "放回标签页", .action_icon_asset = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Empty, "action_icon_asset")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().put_back_icon);
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().put_back_icon;
        } }.__yix_compute);
    }, .on_action = if (comptime ui.view.isEventProp(W.Empty, "on_action")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); __yix_ctx.vm.peek().putBack();  } }.__yix_run) else __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Empty, "on_action")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().putBack());
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().putBack();
        } }.__yix_compute);
    }, .title_test_id = "workspace.card_floated.title", .description_test_id = "workspace.card_floated.detail", .action_test_id = "workspace.card_floated.put_back", }); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "CardFloated";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\x74\x61\x62\x20\x62\x6f\x64\x79\x20\xe7\x9a\x84\xe7\xa9\xba\xe7\x8a\xb6\xe6\x80\x81\xe2\x80\x9c\xe5\x8d\xa1\xe7\x89\x87\xe5\xb7\xb2\xe6\xb5\xae\xe5\x8a\xa8\xe2\x80\x9d\xef\xbc\x88\x63\x61\x72\x64\x73\x2d\x66\x6c\x6f\x61\x74\xef\xbc\x8c\x50\x65\x6e\x63\x69\x6c\x20\x4d\x53\x67\x35\x57\xe3\x80\x8c\x54\x61\x62\x20\x62\x6f\x64\x79\x20\xc2\xb7\x20\xe5\x8d\xa1\xe7\x89\x87\xe5\xb7\xb2\xe6\xb5\xae\xe5\x8a\xa8\xe3\x80\x8d\xef\xbc\x89\xef\xbc\x9a\xe5\x8d\x95\xe5\x8d\xa1\x20\x74\x61\x62\x20\xe7\x9a\x84\xe5\x8d\xa1\xe7\x89\x87\xe6\xb5\xae\xe5\x8a\xa8\x0a\x2f\x2f\x21\x20\xe5\x87\xba\xe5\x8e\xbb\xe3\x80\x81\xe6\x88\x96\xe5\x88\x86\xe5\xb1\x8f\xe9\x87\x8c\xe6\x89\x80\xe6\x9c\x89\xe5\x8d\xa1\xe7\x89\x87\xe9\x83\xbd\xe6\xb5\xae\xe5\x8a\xa8\xe5\x87\xba\xe5\x8e\xbb\xe6\x97\xb6\xef\xbc\x8c\x74\x61\x62\x20\xe4\xbb\x8d\xe5\x9c\xa8\xe6\xa0\x87\xe7\xad\xbe\xe6\xa0\x8f\xe4\xb8\x8a\xef\xbc\x8c\x74\x61\x62\x20\x62\x6f\x64\x79\x20\xe6\x98\xbe\xe7\xa4\xba\xe8\xbf\x99\xe4\xb8\x80\xe5\x9d\x97\xef\xbc\x9a\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x45\x6d\x70\x74\x79\x60\xef\xbc\x88\xe5\x9b\xbe\xe6\xa0\x87\x20\xc2\xb7\x20\xe6\xa0\x87\xe9\xa2\x98\x20\xc2\xb7\x0a\x2f\x2f\x21\x20\xe8\xaf\xb4\xe6\x98\x8e\x20\xc2\xb7\x20\xe5\x8a\xa8\xe4\xbd\x9c\xe2\x80\x9c\xe6\x94\xbe\xe5\x9b\x9e\xe6\xa0\x87\xe7\xad\xbe\xe9\xa1\xb5\xe2\x80\x9d\xef\xbc\x8c\xe4\xb8\x8e\xe6\xb5\xae\xe5\x8a\xa8\xe5\xa4\x96\xe6\xa1\x86\xe7\x9a\x84\xe2\x80\x9c\xe6\x94\xbe\xe5\x85\xa5\xe5\x88\x86\xe5\xb1\x8f\xe2\x80\x9d\xe5\x90\x8c\xe4\xb8\x80\xe4\xb8\xaa\xe5\x8a\xa8\xe4\xbd\x9c\xef\xbc\x9a\xe6\x94\xbe\xe5\x9b\x9e\xe5\x8e\x9f\xe4\xbd\x8d\xef\xbc\x89\xe3\x80\x82\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x6d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x63\x61\x72\x64\x5f\x66\x6c\x6f\x61\x74\x65\x64\x5f\x76\x69\x65\x77\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x53\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x63\x61\x72\x64\x5f\x66\x6c\x6f\x61\x74\x65\x64\x2e\x79\x73\x73\x22\x29\x3b\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x43\x61\x72\x64\x46\x6c\x6f\x61\x74\x65\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x6d\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x77\x6f\x72\x6b\x73\x70\x61\x63\x65\x2e\x63\x61\x72\x64\x5f\x66\x6c\x6f\x61\x74\x65\x64\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x6f\x6f\x74\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x45\x6d\x70\x74\x79\x20\x69\x63\x6f\x6e\x3d\x7b\x76\x6d\x2e\x69\x63\x6f\x6e\x7d\x20\x74\x69\x74\x6c\x65\x3d\x22\xe5\x8d\xa1\xe7\x89\x87\xe5\xb7\xb2\xe6\xb5\xae\xe5\x8a\xa8\x22\x20\x64\x65\x73\x63\x72\x69\x70\x74\x69\x6f\x6e\x3d\x7b\x76\x6d\x2e\x64\x65\x74\x61\x69\x6c\x54\x65\x78\x74\x28\x29\x7d\x20\x61\x63\x74\x69\x6f\x6e\x4c\x61\x62\x65\x6c\x3d\x22\xe6\x94\xbe\xe5\x9b\x9e\xe6\xa0\x87\xe7\xad\xbe\xe9\xa1\xb5\x22\x20\x61\x63\x74\x69\x6f\x6e\x49\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x76\x6d\x2e\x70\x75\x74\x5f\x62\x61\x63\x6b\x5f\x69\x63\x6f\x6e\x7d\x20\x6f\x6e\x41\x63\x74\x69\x6f\x6e\x3d\x7b\x76\x6d\x2e\x70\x75\x74\x42\x61\x63\x6b\x28\x29\x7d\x20\x74\x69\x74\x6c\x65\x54\x65\x73\x74\x49\x64\x3d\x22\x77\x6f\x72\x6b\x73\x70\x61\x63\x65\x2e\x63\x61\x72\x64\x5f\x66\x6c\x6f\x61\x74\x65\x64\x2e\x74\x69\x74\x6c\x65\x22\x20\x64\x65\x73\x63\x72\x69\x70\x74\x69\x6f\x6e\x54\x65\x73\x74\x49\x64\x3d\x22\x77\x6f\x72\x6b\x73\x70\x61\x63\x65\x2e\x63\x61\x72\x64\x5f\x66\x6c\x6f\x61\x74\x65\x64\x2e\x64\x65\x74\x61\x69\x6c\x22\x20\x61\x63\x74\x69\x6f\x6e\x54\x65\x73\x74\x49\x64\x3d\x22\x77\x6f\x72\x6b\x73\x70\x61\x63\x65\x2e\x63\x61\x72\x64\x5f\x66\x6c\x6f\x61\x74\x65\x64\x2e\x70\x75\x74\x5f\x62\x61\x63\x6b\x22\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"S " = S, }) else void;

//# yix-map-data [[548,543]]

//# yix-map card_floated.yix
