// GENERATED FILE, do not edit: generated from float_fixture.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 测试卡片 `fixture.float` 的内容（float-split，只在 test-mode 构建里出现）：原生 Input、原生 ScrollArea
//! 里的一列原生 Button（选中行是 secondary，其余 ghost）。卡片外框由通用浮动外框或分屏窗格提供，这里只有内容。
const ui = @import("ui");
const W = ui.widgets;
const m = @import("float_fixture_view.zig");
const S = @import("_float_fixture.yss.zig");

pub fn FixtureCard(args: anytype) ui.view.ComponentOf(__yix_FixtureCard) {
    return ui.view.component(__yix_FixtureCard, ui.reactive.props.coerce(FixtureCardProps, args));
}
pub const FixtureCardProps = struct {
    vm: ui.Source(*m.Vm),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = FixtureCard;
    pub const __yix_preview_mount = __yix_FixtureCard;
};
fn __yix_FixtureCard(__yix_props: FixtureCardProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/workspace/view/float_fixture.yix", .path = "FixtureCard", .receiver = "col", .tokens = "col testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"fixture.float.content\" ", .kind = .property, .literal = .{ .text = "fixture.float.content" } }, .{ .name = "style", .tokens = "S . root ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = "fixture.float.content", .style = S.root, }, .{
            ui.view.templateSite(.{ .module = "src/features/workspace/view/float_fixture.yix", .path = "FixtureCard", .receiver = "W.Input", .tokens = "< W . Input testId = \"fixture.float.input\" value = { vm . text ( ) } placeholder = \"输入一些文字\" size = { . sm } onChange = { | t | vm . edit ( t ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"fixture.float.input\" ", .kind = .property, .literal = .{ .text = "fixture.float.input" } }, .{ .name = "value", .tokens = "vm . text ( ) ", .kind = .property, .literal = null }, .{ .name = "placeholder", .tokens = "\"输入一些文字\" ", .kind = .property, .literal = .{ .text = "输入一些文字" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "on_change", .tokens = "| t | vm . edit ( t ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = "fixture.float.input", }, __yix_builder_540: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Input); break :__yix_builder_540 W.Input(.{ .value = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Input, "value")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().text());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().text();
        } }.__yix_compute);
    }, .placeholder = "输入一些文字", .size = .sm, .on_change = ui.view.eventProp(W.Input, "on_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, t: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); __yix_ctx.vm.peek().edit(t);  } }.__yix_run)), }); })),
            ui.view.templateSite(.{ .module = "src/features/workspace/view/float_fixture.yix", .path = "FixtureCard", .receiver = "text", .tokens = "text testId = @static; style = @static; vm . selectionText ( )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"fixture.float.selection\" ", .kind = .property, .literal = .{ .text = "fixture.float.selection" } }, .{ .name = "style", .tokens = "S . status ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = "fixture.float.selection", .style = S.status, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d2: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().selectionText());
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().selectionText();
        } }.__yix_compute);
    }), ""), .{ __yix_d2: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().selectionText());
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().selectionText();
        } }.__yix_compute);
    }, }))),
            ui.view.templateSite(.{ .module = "src/features/workspace/view/float_fixture.yix", .path = "FixtureCard", .receiver = "W.ScrollArea", .tokens = "< W . ScrollArea direction = { . vertical } testId = \"fixture.float.list\" style = { S . list } > { for ( vm . rows ) | row | < W . Button key = { row . test_id } testId = { row . test_id } label = { row . label } variant = { vm . rowVariant ( row . index ) } size = { . sm } block = { true } onClick = { vm . select ( row . index ) } / > } < / W . ScrollArea > ", .literal_text = null, .attributes = &.{ .{ .name = "direction", .tokens = ". vertical ", .kind = .property, .literal = .{ .enum_name = "vertical" } }, .{ .name = "test_id", .tokens = "\"fixture.float.list\" ", .kind = .property, .literal = .{ .text = "fixture.float.list" } }, .{ .name = "style", .tokens = "S . list ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = "fixture.float.list", .style = S.list, }, __yix_builder_777: { try ui.view.previewCheckBuilder(__yix_view_scope, W.ScrollArea); break :__yix_builder_777 ui.view.with(W.ScrollArea(.{ .direction = .vertical, }), .{
                ui.view.templateSite(.{ .module = "src/features/workspace/view/float_fixture.yix", .path = "FixtureCard", .receiver = "control", .tokens = "for ( vm . rows ) | row | < W . Button key = { row . test_id } testId = { row . test_id } label = { row . label } variant = { vm . rowVariant ( row . index ) } size = { . sm } block = { true } onClick = { vm . select ( row . index ) } / > " }, .{ .vm = __yix_view_ctx.vm, }, __yix_e1: { const __yix_items_1 = __yix_d5: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().rows);
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().rows;
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ .vm = __yix_view_ctx.vm, }, __yix_items_1, struct { fn __yix_k(row: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(row.test_id); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, row: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "src/features/workspace/view/float_fixture.yix", .path = "FixtureCard/keyword_for:1", .receiver = "W.Button", .tokens = "< W . Button key = { row . test_id } testId = { row . test_id } label = { row . label } variant = { vm . rowVariant ( row . index ) } size = { . sm } block = { true } onClick = { vm . select ( row . index ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "row . test_id ", .kind = .property, .literal = null }, .{ .name = "test_id", .tokens = "row . test_id ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "row . label ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = "vm . rowVariant ( row . index ) ", .kind = .property, .literal = null }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "block", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "on_click", .tokens = "vm . select ( row . index ) ", .kind = .event, .literal = null }, } }, .{ .row = row, .vm = __yix_row_1.vm, }, ui.view.templateAttrs(.{ .test_id = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(row.peek().test_id);
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().test_id;
        } }.__yix_compute);
    }, }, __yix_builder_20: { try ui.view.previewCheckBuilder(__yix_scope_1, W.Button); break :__yix_builder_20 W.Button(.{ .label = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Button, "label")) |__yix_A| __yix_A else @TypeOf(row.peek().label);
        break :__yix_d2 try __yix_scope_1.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().label;
        } }.__yix_compute);
    }, .variant = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Button, "variant")) |__yix_A| __yix_A else @TypeOf(__yix_row_1.vm.peek().rowVariant(row.peek().index));
        break :__yix_d3 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().rowVariant(__yix_ctx.row.get().index);
        } }.__yix_compute);
    }, .size = .sm, .block = true, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_scope_1, .{ .vm = __yix_row_1.vm, .row = row, .__yix_owner = __yix_scope_1.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); __yix_ctx.vm.peek().select(__yix_ctx.row.peek().index);  } }.__yix_run) else __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(__yix_row_1.vm.peek().select(row.peek().index));
        break :__yix_d4 try __yix_scope_1.derive(__yix_T, .{ .vm = __yix_row_1.vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().select(__yix_ctx.row.get().index);
        } }.__yix_compute);
    }, }); }))); } }.__yix_row); }),
            }); })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "FixtureCard";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\xe6\xb5\x8b\xe8\xaf\x95\xe5\x8d\xa1\xe7\x89\x87\x20\x60\x66\x69\x78\x74\x75\x72\x65\x2e\x66\x6c\x6f\x61\x74\x60\x20\xe7\x9a\x84\xe5\x86\x85\xe5\xae\xb9\xef\xbc\x88\x66\x6c\x6f\x61\x74\x2d\x73\x70\x6c\x69\x74\xef\xbc\x8c\xe5\x8f\xaa\xe5\x9c\xa8\x20\x74\x65\x73\x74\x2d\x6d\x6f\x64\x65\x20\xe6\x9e\x84\xe5\xbb\xba\xe9\x87\x8c\xe5\x87\xba\xe7\x8e\xb0\xef\xbc\x89\xef\xbc\x9a\xe5\x8e\x9f\xe7\x94\x9f\x20\x49\x6e\x70\x75\x74\xe3\x80\x81\xe5\x8e\x9f\xe7\x94\x9f\x20\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x0a\x2f\x2f\x21\x20\xe9\x87\x8c\xe7\x9a\x84\xe4\xb8\x80\xe5\x88\x97\xe5\x8e\x9f\xe7\x94\x9f\x20\x42\x75\x74\x74\x6f\x6e\xef\xbc\x88\xe9\x80\x89\xe4\xb8\xad\xe8\xa1\x8c\xe6\x98\xaf\x20\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\xef\xbc\x8c\xe5\x85\xb6\xe4\xbd\x99\x20\x67\x68\x6f\x73\x74\xef\xbc\x89\xe3\x80\x82\xe5\x8d\xa1\xe7\x89\x87\xe5\xa4\x96\xe6\xa1\x86\xe7\x94\xb1\xe9\x80\x9a\xe7\x94\xa8\xe6\xb5\xae\xe5\x8a\xa8\xe5\xa4\x96\xe6\xa1\x86\xe6\x88\x96\xe5\x88\x86\xe5\xb1\x8f\xe7\xaa\x97\xe6\xa0\xbc\xe6\x8f\x90\xe4\xbe\x9b\xef\xbc\x8c\xe8\xbf\x99\xe9\x87\x8c\xe5\x8f\xaa\xe6\x9c\x89\xe5\x86\x85\xe5\xae\xb9\xe3\x80\x82\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x6d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x66\x6c\x6f\x61\x74\x5f\x66\x69\x78\x74\x75\x72\x65\x5f\x76\x69\x65\x77\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x53\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x66\x6c\x6f\x61\x74\x5f\x66\x69\x78\x74\x75\x72\x65\x2e\x79\x73\x73\x22\x29\x3b\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x46\x69\x78\x74\x75\x72\x65\x43\x61\x72\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x6d\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x66\x69\x78\x74\x75\x72\x65\x2e\x66\x6c\x6f\x61\x74\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x6f\x6f\x74\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x49\x6e\x70\x75\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x66\x69\x78\x74\x75\x72\x65\x2e\x66\x6c\x6f\x61\x74\x2e\x69\x6e\x70\x75\x74\x22\x20\x76\x61\x6c\x75\x65\x3d\x7b\x76\x6d\x2e\x74\x65\x78\x74\x28\x29\x7d\x20\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x3d\x22\xe8\xbe\x93\xe5\x85\xa5\xe4\xb8\x80\xe4\xba\x9b\xe6\x96\x87\xe5\xad\x97\x22\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x74\x7c\x20\x76\x6d\x2e\x65\x64\x69\x74\x28\x74\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x66\x69\x78\x74\x75\x72\x65\x2e\x66\x6c\x6f\x61\x74\x2e\x73\x65\x6c\x65\x63\x74\x69\x6f\x6e\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x74\x61\x74\x75\x73\x7d\x3e\x7b\x76\x6d\x2e\x73\x65\x6c\x65\x63\x74\x69\x6f\x6e\x54\x65\x78\x74\x28\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x20\x64\x69\x72\x65\x63\x74\x69\x6f\x6e\x3d\x7b\x2e\x76\x65\x72\x74\x69\x63\x61\x6c\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x66\x69\x78\x74\x75\x72\x65\x2e\x66\x6c\x6f\x61\x74\x2e\x6c\x69\x73\x74\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6c\x69\x73\x74\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x76\x6d\x2e\x72\x6f\x77\x73\x29\x20\x7c\x72\x6f\x77\x7c\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x6b\x65\x79\x3d\x7b\x72\x6f\x77\x2e\x74\x65\x73\x74\x5f\x69\x64\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x72\x6f\x77\x2e\x74\x65\x73\x74\x5f\x69\x64\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x72\x6f\x77\x2e\x6c\x61\x62\x65\x6c\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x76\x6d\x2e\x72\x6f\x77\x56\x61\x72\x69\x61\x6e\x74\x28\x72\x6f\x77\x2e\x69\x6e\x64\x65\x78\x29\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x62\x6c\x6f\x63\x6b\x3d\x7b\x74\x72\x75\x65\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x76\x6d\x2e\x73\x65\x6c\x65\x63\x74\x28\x72\x6f\x77\x2e\x69\x6e\x64\x65\x78\x29\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"S " = S, }) else void;

//# yix-map-data [[427,422]]

//# yix-map float_fixture.yix
