// GENERATED FILE, do not edit: generated from empty_saved_connections.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 空工作区的“已保存的连接”（Pencil hmCmB `vDyAK`）：空状态操作下方最多三条已保存连接。
//!
//! - 每行是原生 `W.Pressable`（焦点、回车 / 空格、按下与悬停状态由它负责）：图标、名称、路由（“SSH · 直连”）。
//!   点击走与侧栏行“连接”相同的新会话路径（宿主 `Workspace.savedConnect`）。
//! - 协议插件被禁用（PLUGIN_ARCH_PLAN 6.2.1 Q5）的主机按侧栏同一规则（qQaos）：图标与名称变淡，行尾用“已禁用”
//!   代替路由，原因与恢复路径在原生 `W.Tooltip` 里；这一行 `disabled`，点击 / 回车都不发起连接。
//! - 没有已保存的连接时整块隐藏。
//! 行数据、挑选规则与文案在 `empty_saved_connections.zig`（纯函数 + 单测）；这里只读它、把点击交给它。
const ui = @import("ui");
const W = ui.widgets;
const m = @import("empty_saved_connections.zig");
const S = @import("_empty_saved_connections.yss.zig");

fn rowIcon(row: m.Row) ui.SvgAsset {
    return if (row.sftp) ui.icons.folder else ui.icons.server;
}

pub fn SavedConnections(args: anytype) ui.view.ComponentOf(__yix_SavedConnections) {
    return ui.view.component(__yix_SavedConnections, ui.reactive.props.coerce(SavedConnectionsProps, args));
}
pub const SavedConnectionsProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = SavedConnections;
    pub const __yix_preview_mount = __yix_SavedConnections;
};
fn __yix_SavedConnections(__yix_props: SavedConnectionsProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections", .receiver = "col", .tokens = "col testId = m . ids . root ; style = @static; visible = vm . shown ( ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . ids . root ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . root ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . shown ( ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = m.ids.root, .style = S.root, .visible = __yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().shown());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().shown();
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections", .receiver = "row", .tokens = "row style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . heading ", .kind = .style, .literal = null }, } }, .{ }, ui.view.row(.{ .style = S.heading, }, .{
                ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "已保存的主机", .attributes = &.{ .{ .name = "style", .tokens = "S . heading_text ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.heading_text, }, ui.view.fmt("已保存的主机", .{ }))),
            })),
            ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections", .receiver = "col", .tokens = "col style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . rows ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .style = S.rows, }, .{
                ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections", .receiver = "control", .tokens = "for ( vm . rows ( ) ) | row | < W . Pressable key = { row . key } testId = { m . ids . row } a11yLabel = { row . name } disabled = { row . unavailable } onClick = { vm . connect ( row . index ) } style = { S . Row . of ( . { . unavailable = row . unavailable } ) } > < icon src = { rowIcon ( row ) } style = { S . Icon . of ( . { . unavailable = row . unavailable } ) } / > < text style = { S . Name . of ( . { . unavailable = row . unavailable } ) } box = { S . name_box } > { row . name } < / text > { if ( row . unavailable ) < box style = { S . meta_box } > < W . Tooltip text = { row . reason } position = { . top } parts = { . { . content = m . ids . tooltip } } > < text testId = { m . ids . unavailable } style = { S . meta } > 已禁用</text> < / W . Tooltip > < / box > else < text style = { S . meta } box = { S . meta_box } > { row . metaText ( ) } < / text > } < / W . Pressable > " }, .{ .vm = __yix_view_ctx.vm, }, __yix_e1: { const __yix_items_1 = __yix_d9: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().rows());
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().rows();
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ .vm = __yix_view_ctx.vm, }, __yix_items_1, struct { fn __yix_k(row: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(row.key); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, row: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections/keyword_for:1", .receiver = "W.Pressable", .tokens = "< W . Pressable key = { row . key } testId = { m . ids . row } a11yLabel = { row . name } disabled = { row . unavailable } onClick = { vm . connect ( row . index ) } style = { S . Row . of ( . { . unavailable = row . unavailable } ) } > < icon src = { rowIcon ( row ) } style = { S . Icon . of ( . { . unavailable = row . unavailable } ) } / > < text style = { S . Name . of ( . { . unavailable = row . unavailable } ) } box = { S . name_box } > { row . name } < / text > { if ( row . unavailable ) < box style = { S . meta_box } > < W . Tooltip text = { row . reason } position = { . top } parts = { . { . content = m . ids . tooltip } } > < text testId = { m . ids . unavailable } style = { S . meta } > 已禁用</text> < / W . Tooltip > < / box > else < text style = { S . meta } box = { S . meta_box } > { row . metaText ( ) } < / text > } < / W . Pressable > ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "row . key ", .kind = .property, .literal = null }, .{ .name = "test_id", .tokens = "m . ids . row ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "row . name ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "row . unavailable ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "vm . connect ( row . index ) ", .kind = .event, .literal = null }, .{ .name = "style", .tokens = "S . Row . of ( . { . unavailable = row . unavailable } ) ", .kind = .style, .literal = null }, } }, .{ .row = row, .vm = __yix_row_1.vm, }, ui.view.templateAttrs(.{ .test_id = m.ids.row, .style = S.Row.of(.{ .unavailable = __yix_d4: {
        const __yix_T = @TypeOf(row.peek().unavailable);
        break :__yix_d4 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().unavailable;
        } }.__yix_compute);
    } }), }, __yix_builder_22: { try ui.view.previewCheckBuilder(__yix_scope_1, W.Pressable); break :__yix_builder_22 ui.view.with(W.Pressable(.{ .a11y_label = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "a11y_label")) |__yix_A| __yix_A else @TypeOf(row.peek().name);
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().name;
        } }.__yix_compute);
    }, .disabled = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "disabled")) |__yix_A| __yix_A else @TypeOf(row.peek().unavailable);
        break :__yix_d2 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().unavailable;
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Pressable, "on_click")) try ui.on.bindAny(__yix_scope_1, .{ .vm = __yix_row_1.vm, .row = row, .__yix_owner = __yix_scope_1.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); __yix_ctx.vm.peek().connect(__yix_ctx.row.peek().index);  } }.__yix_run) else __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "on_click")) |__yix_A| __yix_A else @TypeOf(__yix_row_1.vm.peek().connect(row.peek().index));
        break :__yix_d3 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().connect(__yix_ctx.row.get().index);
        } }.__yix_compute);
    }, }), .{
                        ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections/keyword_for:1", .receiver = "icon", .tokens = "icon src = rowIcon ( row ) ; style = S . Icon . of ( . { . unavailable = row . unavailable } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "rowIcon ( row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . Icon . of ( . { . unavailable = row . unavailable } ) ", .kind = .style, .literal = null }, } }, .{ .row = row, }, ui.view.icon(.{ .style = S.Icon.of(.{ .unavailable = __yix_d6: {
        const __yix_T = @TypeOf(row.peek().unavailable);
        break :__yix_d6 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().unavailable;
        } }.__yix_compute);
    } }), }, __yix_d5: {
        const __yix_T = @TypeOf(rowIcon(row.peek()));
        break :__yix_d5 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return rowIcon(__yix_ctx.row.get());
        } }.__yix_compute);
    })),
                        ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections/keyword_for:1", .receiver = "text", .tokens = "text style = S . Name . of ( . { . unavailable = row . unavailable } ) ; box = S . name_box ; row . name  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . Name . of ( . { . unavailable = row . unavailable } ) ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . name_box ", .kind = .property, .literal = null }, } }, .{ .row = row, }, ui.view.text(.{ .style = S.Name.of(.{ .unavailable = __yix_d7: {
        const __yix_T = @TypeOf(row.peek().unavailable);
        break :__yix_d7 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().unavailable;
        } }.__yix_compute);
    } }), .box = S.name_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d8: {
        const __yix_T = @TypeOf(row.peek().name);
        break :__yix_d8 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().name;
        } }.__yix_compute);
    }), ""), .{ __yix_d8: {
        const __yix_T = @TypeOf(row.peek().name);
        break :__yix_d8 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().name;
        } }.__yix_compute);
    }, }))),
                        ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections/keyword_for:1", .receiver = "control", .tokens = "if ( row . unavailable ) < box style = { S . meta_box } > < W . Tooltip text = { row . reason } position = { . top } parts = { . { . content = m . ids . tooltip } } > < text testId = { m . ids . unavailable } style = { S . meta } > 已禁用</text> < / W . Tooltip > < / box > else < text style = { S . meta } box = { S . meta_box } > { row . metaText ( ) } < / text > " }, .{ .row = row, }, ui.view.lazyIf(__yix_d3: {
        const __yix_T = @TypeOf(row.peek().unavailable);
        break :__yix_d3 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().unavailable;
        } }.__yix_compute);
    }, .{ .row = row, }, struct { fn __yix_b(__yix_b2_0: anytype, __yix_bs2_0: *ui.Scope, __yix_bc2_0: *ui.Cx, __yix_bk2_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs2_0, __yix_bc2_0, __yix_bk2_0, .{ ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections/keyword_for:1/keyword_if:2/branch:0", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . meta_box ", .kind = .style, .literal = null }, } }, .{ .row = __yix_b2_0.row, }, ui.view.box(.{ .style = S.meta_box, }, .{
                                ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections/keyword_for:1/keyword_if:2/branch:0", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { row . reason } position = { . top } parts = { . { . content = m . ids . tooltip } } > < text testId = { m . ids . unavailable } style = { S . meta } > 已禁用</text> < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "row . reason ", .kind = .property, .literal = null }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, .{ .name = "parts", .tokens = ". { . content = m . ids . tooltip } ", .kind = .property, .literal = null }, } }, .{ .row = __yix_b2_0.row, }, ui.view.templateAttrs(.{ .parts = .{ .content = m.ids.tooltip }, }, __yix_builder_70: { try ui.view.previewCheckBuilder(__yix_bs2_0, W.Tooltip); break :__yix_builder_70 ui.view.with(W.Tooltip(.{ .text = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(__yix_b2_0.row.peek().reason);
        break :__yix_d1 try __yix_bs2_0.derive(__yix_T, .{ .row = __yix_b2_0.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().reason;
        } }.__yix_compute);
    }, .position = .top, }), .{
                                    ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections/keyword_for:1/keyword_if:2/branch:0", .receiver = "text", .tokens = "text testId = m . ids . unavailable ; style = @static; ", .literal_text = "已禁用", .attributes = &.{ .{ .name = "test_id", .tokens = "m . ids . unavailable ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . meta ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .test_id = m.ids.unavailable, .style = S.meta, }, ui.view.fmt("已禁用", .{ }))),
                                }); })),
                            })) }); } }.__yix_b, struct { fn __yix_b(__yix_b2_1: anytype, __yix_bs2_1: *ui.Scope, __yix_bc2_1: *ui.Cx, __yix_bk2_1: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs2_1, __yix_bc2_1, __yix_bk2_1, .{ ui.view.templateSite(.{ .module = "src/features/workspace/view/empty_saved_connections.yix", .path = "SavedConnections/keyword_for:1/keyword_if:2/branch:1", .receiver = "text", .tokens = "text style = @static; box = S . meta_box ; row . metaText ( )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . meta ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . meta_box ", .kind = .property, .literal = null }, } }, .{ .row = __yix_b2_1.row, }, ui.view.text(.{ .style = S.meta, .box = S.meta_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d2: {
        const __yix_T = @TypeOf(__yix_b2_1.row.peek().metaText());
        break :__yix_d2 try __yix_bs2_1.derive(__yix_T, .{ .row = __yix_b2_1.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().metaText();
        } }.__yix_compute);
    }), ""), .{ __yix_d2: {
        const __yix_T = @TypeOf(__yix_b2_1.row.peek().metaText());
        break :__yix_d2 try __yix_bs2_1.derive(__yix_T, .{ .row = __yix_b2_1.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().metaText();
        } }.__yix_compute);
    }, }))) }); } }.__yix_b)),
                    }); }))); } }.__yix_row); }),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "SavedConnections";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\xe7\xa9\xba\xe5\xb7\xa5\xe4\xbd\x9c\xe5\x8c\xba\xe7\x9a\x84\xe2\x80\x9c\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98\xe7\x9a\x84\xe8\xbf\x9e\xe6\x8e\xa5\xe2\x80\x9d\xef\xbc\x88\x50\x65\x6e\x63\x69\x6c\x20\x68\x6d\x43\x6d\x42\x20\x60\x76\x44\x79\x41\x4b\x60\xef\xbc\x89\xef\xbc\x9a\xe7\xa9\xba\xe7\x8a\xb6\xe6\x80\x81\xe6\x93\x8d\xe4\xbd\x9c\xe4\xb8\x8b\xe6\x96\xb9\xe6\x9c\x80\xe5\xa4\x9a\xe4\xb8\x89\xe6\x9d\xa1\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98\xe8\xbf\x9e\xe6\x8e\xa5\xe3\x80\x82\x0a\x2f\x2f\x21\x0a\x2f\x2f\x21\x20\x2d\x20\xe6\xaf\x8f\xe8\xa1\x8c\xe6\x98\xaf\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x60\xef\xbc\x88\xe7\x84\xa6\xe7\x82\xb9\xe3\x80\x81\xe5\x9b\x9e\xe8\xbd\xa6\x20\x2f\x20\xe7\xa9\xba\xe6\xa0\xbc\xe3\x80\x81\xe6\x8c\x89\xe4\xb8\x8b\xe4\xb8\x8e\xe6\x82\xac\xe5\x81\x9c\xe7\x8a\xb6\xe6\x80\x81\xe7\x94\xb1\xe5\xae\x83\xe8\xb4\x9f\xe8\xb4\xa3\xef\xbc\x89\xef\xbc\x9a\xe5\x9b\xbe\xe6\xa0\x87\xe3\x80\x81\xe5\x90\x8d\xe7\xa7\xb0\xe3\x80\x81\xe8\xb7\xaf\xe7\x94\xb1\xef\xbc\x88\xe2\x80\x9c\x53\x53\x48\x20\xc2\xb7\x20\xe7\x9b\xb4\xe8\xbf\x9e\xe2\x80\x9d\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x20\x20\xe7\x82\xb9\xe5\x87\xbb\xe8\xb5\xb0\xe4\xb8\x8e\xe4\xbe\xa7\xe6\xa0\x8f\xe8\xa1\x8c\xe2\x80\x9c\xe8\xbf\x9e\xe6\x8e\xa5\xe2\x80\x9d\xe7\x9b\xb8\xe5\x90\x8c\xe7\x9a\x84\xe6\x96\xb0\xe4\xbc\x9a\xe8\xaf\x9d\xe8\xb7\xaf\xe5\xbe\x84\xef\xbc\x88\xe5\xae\xbf\xe4\xb8\xbb\x20\x60\x57\x6f\x72\x6b\x73\x70\x61\x63\x65\x2e\x73\x61\x76\x65\x64\x43\x6f\x6e\x6e\x65\x63\x74\x60\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe5\x8d\x8f\xe8\xae\xae\xe6\x8f\x92\xe4\xbb\xb6\xe8\xa2\xab\xe7\xa6\x81\xe7\x94\xa8\xef\xbc\x88\x50\x4c\x55\x47\x49\x4e\x5f\x41\x52\x43\x48\x5f\x50\x4c\x41\x4e\x20\x36\x2e\x32\x2e\x31\x20\x51\x35\xef\xbc\x89\xe7\x9a\x84\xe4\xb8\xbb\xe6\x9c\xba\xe6\x8c\x89\xe4\xbe\xa7\xe6\xa0\x8f\xe5\x90\x8c\xe4\xb8\x80\xe8\xa7\x84\xe5\x88\x99\xef\xbc\x88\x71\x51\x61\x6f\x73\xef\xbc\x89\xef\xbc\x9a\xe5\x9b\xbe\xe6\xa0\x87\xe4\xb8\x8e\xe5\x90\x8d\xe7\xa7\xb0\xe5\x8f\x98\xe6\xb7\xa1\xef\xbc\x8c\xe8\xa1\x8c\xe5\xb0\xbe\xe7\x94\xa8\xe2\x80\x9c\xe5\xb7\xb2\xe7\xa6\x81\xe7\x94\xa8\xe2\x80\x9d\x0a\x2f\x2f\x21\x20\x20\x20\xe4\xbb\xa3\xe6\x9b\xbf\xe8\xb7\xaf\xe7\x94\xb1\xef\xbc\x8c\xe5\x8e\x9f\xe5\x9b\xa0\xe4\xb8\x8e\xe6\x81\xa2\xe5\xa4\x8d\xe8\xb7\xaf\xe5\xbe\x84\xe5\x9c\xa8\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x60\x20\xe9\x87\x8c\xef\xbc\x9b\xe8\xbf\x99\xe4\xb8\x80\xe8\xa1\x8c\x20\x60\x64\x69\x73\x61\x62\x6c\x65\x64\x60\xef\xbc\x8c\xe7\x82\xb9\xe5\x87\xbb\x20\x2f\x20\xe5\x9b\x9e\xe8\xbd\xa6\xe9\x83\xbd\xe4\xb8\x8d\xe5\x8f\x91\xe8\xb5\xb7\xe8\xbf\x9e\xe6\x8e\xa5\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe6\xb2\xa1\xe6\x9c\x89\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98\xe7\x9a\x84\xe8\xbf\x9e\xe6\x8e\xa5\xe6\x97\xb6\xe6\x95\xb4\xe5\x9d\x97\xe9\x9a\x90\xe8\x97\x8f\xe3\x80\x82\x0a\x2f\x2f\x21\x20\xe8\xa1\x8c\xe6\x95\xb0\xe6\x8d\xae\xe3\x80\x81\xe6\x8c\x91\xe9\x80\x89\xe8\xa7\x84\xe5\x88\x99\xe4\xb8\x8e\xe6\x96\x87\xe6\xa1\x88\xe5\x9c\xa8\x20\x60\x65\x6d\x70\x74\x79\x5f\x73\x61\x76\x65\x64\x5f\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x73\x2e\x7a\x69\x67\x60\xef\xbc\x88\xe7\xba\xaf\xe5\x87\xbd\xe6\x95\xb0\x20\x2b\x20\xe5\x8d\x95\xe6\xb5\x8b\xef\xbc\x89\xef\xbc\x9b\xe8\xbf\x99\xe9\x87\x8c\xe5\x8f\xaa\xe8\xaf\xbb\xe5\xae\x83\xe3\x80\x81\xe6\x8a\x8a\xe7\x82\xb9\xe5\x87\xbb\xe4\xba\xa4\xe7\xbb\x99\xe5\xae\x83\xe3\x80\x82\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x6d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x65\x6d\x70\x74\x79\x5f\x73\x61\x76\x65\x64\x5f\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x73\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x53\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x65\x6d\x70\x74\x79\x5f\x73\x61\x76\x65\x64\x5f\x63\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x73\x2e\x79\x73\x73\x22\x29\x3b\x0a\x0a\x66\x6e\x20\x72\x6f\x77\x49\x63\x6f\x6e\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x66\x20\x28\x72\x6f\x77\x2e\x73\x66\x74\x70\x29\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x66\x6f\x6c\x64\x65\x72\x20\x65\x6c\x73\x65\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x73\x65\x72\x76\x65\x72\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x53\x61\x76\x65\x64\x43\x6f\x6e\x6e\x65\x63\x74\x69\x6f\x6e\x73\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x69\x64\x73\x2e\x72\x6f\x6f\x74\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x6f\x6f\x74\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x73\x68\x6f\x77\x6e\x28\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x61\x64\x69\x6e\x67\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x61\x64\x69\x6e\x67\x5f\x74\x65\x78\x74\x7d\x3e\xe5\xb7\xb2\xe4\xbf\x9d\xe5\xad\x98\xe7\x9a\x84\xe4\xb8\xbb\xe6\x9c\xba\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x6f\x77\x73\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x76\x6d\x2e\x72\x6f\x77\x73\x28\x29\x29\x20\x7c\x72\x6f\x77\x7c\x20\x3c\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x20\x6b\x65\x79\x3d\x7b\x72\x6f\x77\x2e\x6b\x65\x79\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x69\x64\x73\x2e\x72\x6f\x77\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x72\x6f\x77\x2e\x6e\x61\x6d\x65\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x72\x6f\x77\x2e\x75\x6e\x61\x76\x61\x69\x6c\x61\x62\x6c\x65\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x76\x6d\x2e\x63\x6f\x6e\x6e\x65\x63\x74\x28\x72\x6f\x77\x2e\x69\x6e\x64\x65\x78\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x75\x6e\x61\x76\x61\x69\x6c\x61\x62\x6c\x65\x20\x3d\x20\x72\x6f\x77\x2e\x75\x6e\x61\x76\x61\x69\x6c\x61\x62\x6c\x65\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x72\x6f\x77\x49\x63\x6f\x6e\x28\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x49\x63\x6f\x6e\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x75\x6e\x61\x76\x61\x69\x6c\x61\x62\x6c\x65\x20\x3d\x20\x72\x6f\x77\x2e\x75\x6e\x61\x76\x61\x69\x6c\x61\x62\x6c\x65\x20\x7d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x4e\x61\x6d\x65\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x75\x6e\x61\x76\x61\x69\x6c\x61\x62\x6c\x65\x20\x3d\x20\x72\x6f\x77\x2e\x75\x6e\x61\x76\x61\x69\x6c\x61\x62\x6c\x65\x20\x7d\x29\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x6e\x61\x6d\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x72\x6f\x77\x2e\x6e\x61\x6d\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x72\x6f\x77\x2e\x75\x6e\x61\x76\x61\x69\x6c\x61\x62\x6c\x65\x29\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x65\x74\x61\x5f\x62\x6f\x78\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x72\x6f\x77\x2e\x72\x65\x61\x73\x6f\x6e\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x6d\x2e\x69\x64\x73\x2e\x74\x6f\x6f\x6c\x74\x69\x70\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x69\x64\x73\x2e\x75\x6e\x61\x76\x61\x69\x6c\x61\x62\x6c\x65\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x65\x74\x61\x7d\x3e\xe5\xb7\xb2\xe7\xa6\x81\xe7\x94\xa8\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x20\x65\x6c\x73\x65\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x65\x74\x61\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x6d\x65\x74\x61\x5f\x62\x6f\x78\x7d\x3e\x7b\x72\x6f\x77\x2e\x6d\x65\x74\x61\x54\x65\x78\x74\x28\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"S " = S, }) else void;

//# yix-map-data [[1117,1112]]

//# yix-map empty_saved_connections.yix
