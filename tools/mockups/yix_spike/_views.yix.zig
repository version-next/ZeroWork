// GENERATED FILE, do not edit: generated from views.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! yix_spike 的 Yix 视图：每个组件对应一个 V 项。
const std = @import("std");
const ui = @import("ui");
const W = ui.widgets;
const S = @import("_styles.yss.zig");
const m = @import("vm.zig");

// ── V-2：选择器函数，参数是 *ViewModel，内部 .get() 读信号 ──
fn titleOf(vm: *m.ViewModel) []const u8 {
    vm.selector_runs += 1;
    return vm.title.get();
}
fn cannotBack(vm: *m.ViewModel) bool { return !vm.can_back.get(); }
fn modeOf(vm: *m.ViewModel) m.Mode { return vm.mode.get(); }

// 注意：Yix 不支持多值分支 `.panes, .search =>`（yix gen 报 "unexpected token"），拆开写或用 else。
// 另外 `//` 注释写在标签内部会变成文本节点，注释只能放在模板外。
pub fn SelectorPanel(args: anytype) ui.view.ComponentOf(__yix_SelectorPanel) {
    return ui.view.component(__yix_SelectorPanel, ui.reactive.props.coerce(SelectorPanelProps, args));
}
pub const SelectorPanelProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = SelectorPanel;
    pub const __yix_preview_mount = __yix_SelectorPanel;
};
fn __yix_SelectorPanel(__yix_props: SelectorPanelProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "SelectorPanel", .receiver = "col", .tokens = "col testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v2\" ", .kind = .property, .literal = .{ .text = "spike.v2" } }, .{ .name = "style", .tokens = "S . section ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = "spike.v2", .style = S.section, }, .{
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "SelectorPanel", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "V-2 选择器(vm)", .attributes = &.{ .{ .name = "style", .tokens = "S . heading ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.heading, }, ui.view.fmt("V-2 选择器(vm)", .{ }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "SelectorPanel", .receiver = "text", .tokens = "text testId = @static; style = @static; titleOf ( vm )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v2.title\" ", .kind = .property, .literal = .{ .text = "spike.v2.title" } }, .{ .name = "style", .tokens = "S . body_text ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = "spike.v2.title", .style = S.body_text, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(titleOf(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return titleOf(__yix_ctx.vm.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(titleOf(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return titleOf(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "SelectorPanel", .receiver = "box", .tokens = "box testId = @static; visible = cannotBack ( vm ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v2.back_hint\" ", .kind = .property, .literal = .{ .text = "spike.v2.back_hint" } }, .{ .name = "visible", .tokens = "cannotBack ( vm ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = "spike.v2.back_hint", .visible = __yix_d2: {
        const __yix_T = @TypeOf(cannotBack(__yix_view_ctx.vm.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return cannotBack(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }, .{
                ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "SelectorPanel", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "已在最前", .attributes = &.{ .{ .name = "style", .tokens = "S . muted ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.muted, }, ui.view.fmt("已在最前", .{ }))),
            })),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "SelectorPanel", .receiver = "control", .tokens = "switch ( modeOf ( vm ) ) { . overview => < text testId = \"spike.v2.mode\" style = { S . muted } > overview < / text > , . panes => < text testId = \"spike.v2.mode\" style = { S . muted } > panes < / text > , . search => < text testId = \"spike.v2.mode\" style = { S . muted } > search < / text > , } " }, .{ .vm = __yix_view_ctx.vm, }, ui.view.lazySwitch(__yix_d1: {
        const __yix_T = @TypeOf(modeOf(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return modeOf(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .{ }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bt1_0: anytype, __yix_bv1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { _ = __yix_b1_0; _ = __yix_bv1_0; switch (__yix_bt1_0) { .overview => { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "SelectorPanel/keyword_switch:1/case:.overview", .receiver = "text", .tokens = "text testId = @static; style = @static; ", .literal_text = "overview", .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v2.mode\" ", .kind = .property, .literal = .{ .text = "spike.v2.mode" } }, .{ .name = "style", .tokens = "S . muted ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .test_id = "spike.v2.mode", .style = S.muted, }, ui.view.fmt("overview", .{ }))) }); }, .panes => { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "SelectorPanel/keyword_switch:1/case:.panes", .receiver = "text", .tokens = "text testId = @static; style = @static; ", .literal_text = "panes", .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v2.mode\" ", .kind = .property, .literal = .{ .text = "spike.v2.mode" } }, .{ .name = "style", .tokens = "S . muted ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .test_id = "spike.v2.mode", .style = S.muted, }, ui.view.fmt("panes", .{ }))) }); }, .search => { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "SelectorPanel/keyword_switch:1/case:.search", .receiver = "text", .tokens = "text testId = @static; style = @static; ", .literal_text = "search", .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v2.mode\" ", .kind = .property, .literal = .{ .text = "spike.v2.mode" } }, .{ .name = "style", .tokens = "S . muted ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .test_id = "spike.v2.mode", .style = S.muted, }, ui.view.fmt("search", .{ }))) }); }, } } }.__yix_b)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "SelectorPanel";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

// ── V-3：事件里调用带参数的函数，实参含枚举字面量 / 带载荷的 Intent ──
// 注意：实参里写结构体字面量 `.{ .set_count = 5 }` 或 `m.Intent{ .set_count = 5 }` 会被 yix gen 拒绝
// （"field writes and nested event statements are not implemented"），载荷用 @unionInit 或构造函数。
fn send(vm: *m.ViewModel, intent: m.Intent) void {
    vm.send_calls += 1;
    vm.dispatch(intent);
}

pub fn EventPanel(args: anytype) ui.view.ComponentOf(__yix_EventPanel) {
    return ui.view.component(__yix_EventPanel, ui.reactive.props.coerce(EventPanelProps, args));
}
pub const EventPanelProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = EventPanel;
    pub const __yix_preview_mount = __yix_EventPanel;
};
fn __yix_EventPanel(__yix_props: EventPanelProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "EventPanel", .receiver = "col", .tokens = "col testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v3\" ", .kind = .property, .literal = .{ .text = "spike.v3" } }, .{ .name = "style", .tokens = "S . section ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = "spike.v3", .style = S.section, }, .{
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "EventPanel", .receiver = "text", .tokens = "text style = @static; \"{send(vm, .back)}\"  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . heading ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.heading, }, ui.view.fmt("V-3 onClick=" ++ ui.view.yixFormat(@TypeOf("{send(vm, .back)}"), ""), .{ "{send(vm, .back)}", }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "EventPanel", .receiver = "row", .tokens = "row style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . section_row ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.row(.{ .style = S.section_row, }, .{
                ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "EventPanel", .receiver = "W.Button", .tokens = "< W . Button testId = \"spike.v3.back\" label = \"后退\" disabled = { cannotBack ( vm ) } onClick = { send ( vm , . back ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v3.back\" ", .kind = .property, .literal = .{ .text = "spike.v3.back" } }, .{ .name = "label", .tokens = "\"后退\" ", .kind = .property, .literal = .{ .text = "后退" } }, .{ .name = "disabled", .tokens = "cannotBack ( vm ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , . back ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = "spike.v3.back", }, __yix_builder_2126: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_2126 W.Button(.{ .label = "后退", .disabled = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(cannotBack(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return cannotBack(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .back);  } }.__yix_run) else __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), .back));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), .back);
        } }.__yix_compute);
    }, }); })),
                ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "EventPanel", .receiver = "W.Button", .tokens = "< W . Button testId = \"spike.v3.forward\" label = \"前进\" onClick = { send ( vm , . forward ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v3.forward\" ", .kind = .property, .literal = .{ .text = "spike.v3.forward" } }, .{ .name = "label", .tokens = "\"前进\" ", .kind = .property, .literal = .{ .text = "前进" } }, .{ .name = "on_click", .tokens = "send ( vm , . forward ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = "spike.v3.forward", }, __yix_builder_2245: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_2245 W.Button(.{ .label = "前进", .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .forward);  } }.__yix_run) else __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), .forward));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), .forward);
        } }.__yix_compute);
    }, }); })),
                ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "EventPanel", .receiver = "W.Button", .tokens = "< W . Button testId = \"spike.v3.add\" label = \"+5\" onClick = { send ( vm , @unionInit ( m . Intent , \"set_count\" , 5 ) ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v3.add\" ", .kind = .property, .literal = .{ .text = "spike.v3.add" } }, .{ .name = "label", .tokens = "\"+5\" ", .kind = .property, .literal = .{ .text = "+5" } }, .{ .name = "on_click", .tokens = "send ( vm , @unionInit ( m . Intent , \"set_count\" , 5 ) ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = "spike.v3.add", }, __yix_builder_2344: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_2344 W.Button(.{ .label = "+5", .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), @unionInit(m.Intent, "set_count", 5));  } }.__yix_run) else __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), @unionInit(m.Intent, "set_count", 5)));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), @unionInit(m.Intent, "set_count", 5));
        } }.__yix_compute);
    }, }); })),
                ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "EventPanel", .receiver = "box", .tokens = "box testId = @static; onClick = send ( vm , . toggle_flag ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v3.host\" ", .kind = .property, .literal = .{ .text = "spike.v3.host" } }, .{ .name = "on_click", .tokens = "send ( vm , . toggle_flag ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = "spike.v3.host", .on_click = try ui.on.bind(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), .toggle_flag);  } }.__yix_run), }, .{
                    ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "EventPanel", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "宿主 box", .attributes = &.{ .{ .name = "style", .tokens = "S . body_text ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.body_text, }, ui.view.fmt("宿主 box", .{ }))),
                })),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "EventPanel";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

// ── V-4：模板里直接写 vm.<信号字段> ──
// 原先前五行是反例：{vm.field} 能编译，但渲染出 Signal / Memo 结构体的调试转储。zenit 现在在编译期拒绝
// 把响应式源直接插进 {…}（view.zig：“the interpolated value is a reactive source”），反例已无法编译，改为内联 .get()。
// 直接写进 visible / if / switch / for / 组件属性同样编译失败；可用写法是内联 .get()。
pub fn DirectPanel(args: anytype) ui.view.ComponentOf(__yix_DirectPanel) {
    return ui.view.component(__yix_DirectPanel, ui.reactive.props.coerce(DirectPanelProps, args));
}
pub const DirectPanelProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = DirectPanel;
    pub const __yix_preview_mount = __yix_DirectPanel;
};
fn __yix_DirectPanel(__yix_props: DirectPanelProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectPanel", .receiver = "col", .tokens = "col testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4\" ", .kind = .property, .literal = .{ .text = "spike.v4" } }, .{ .name = "style", .tokens = "S . section ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = "spike.v4", .style = S.section, }, .{
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectPanel", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "V-4 直接写 vm.field", .attributes = &.{ .{ .name = "style", .tokens = "S . heading ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.heading, }, ui.view.fmt("V-4 直接写 vm.field", .{ }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectPanel", .receiver = "text", .tokens = "text testId = @static; style = @static; vm . title . get ( )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.title\" ", .kind = .property, .literal = .{ .text = "spike.v4.title" } }, .{ .name = "style", .tokens = "S . body_text ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = "spike.v4.title", .style = S.body_text, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().title.get());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().title.get();
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().title.get());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().title.get();
        } }.__yix_compute);
    }, }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectPanel", .receiver = "text", .tokens = "text testId = @static; style = @static; vm . count . get ( )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.count\" ", .kind = .property, .literal = .{ .text = "spike.v4.count" } }, .{ .name = "style", .tokens = "S . body_text ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = "spike.v4.count", .style = S.body_text, }, ui.view.fmt("count=" ++ ui.view.yixFormat(@TypeOf(__yix_d2: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().count.get());
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().count.get();
        } }.__yix_compute);
    }), ""), .{ __yix_d2: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().count.get());
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().count.get();
        } }.__yix_compute);
    }, }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectPanel", .receiver = "text", .tokens = "text testId = @static; style = @static; vm . doubled . get ( )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.doubled\" ", .kind = .property, .literal = .{ .text = "spike.v4.doubled" } }, .{ .name = "style", .tokens = "S . body_text ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = "spike.v4.doubled", .style = S.body_text, }, ui.view.fmt("doubled=" ++ ui.view.yixFormat(@TypeOf(__yix_d3: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().doubled.get());
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().doubled.get();
        } }.__yix_compute);
    }), ""), .{ __yix_d3: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().doubled.get());
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().doubled.get();
        } }.__yix_compute);
    }, }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectPanel", .receiver = "text", .tokens = "text testId = @static; style = @static; vm . mode . get ( )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.mode\" ", .kind = .property, .literal = .{ .text = "spike.v4.mode" } }, .{ .name = "style", .tokens = "S . body_text ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = "spike.v4.mode", .style = S.body_text, }, ui.view.fmt("mode=" ++ ui.view.yixFormat(@TypeOf(__yix_d4: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().mode.get());
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().mode.get();
        } }.__yix_compute);
    }), ""), .{ __yix_d4: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().mode.get());
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().mode.get();
        } }.__yix_compute);
    }, }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectPanel", .receiver = "text", .tokens = "text testId = @static; style = @static; vm . can_back . get ( )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.flag\" ", .kind = .property, .literal = .{ .text = "spike.v4.flag" } }, .{ .name = "style", .tokens = "S . body_text ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = "spike.v4.flag", .style = S.body_text, }, ui.view.fmt("can_back=" ++ ui.view.yixFormat(@TypeOf(__yix_d5: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().can_back.get());
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().can_back.get();
        } }.__yix_compute);
    }), ""), .{ __yix_d5: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().can_back.get());
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().can_back.get();
        } }.__yix_compute);
    }, }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectPanel", .receiver = "box", .tokens = "box testId = @static; visible = vm . can_back . get ( ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.visible\" ", .kind = .property, .literal = .{ .text = "spike.v4.visible" } }, .{ .name = "visible", .tokens = "vm . can_back . get ( ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = "spike.v4.visible", .visible = __yix_d6: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().can_back.get());
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().can_back.get();
        } }.__yix_compute);
    }, }, .{
                ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectPanel", .receiver = "text", .tokens = "text style = @static; \"{vm.can_back.get()}\"  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . muted ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.muted, }, ui.view.fmt("visible=" ++ ui.view.yixFormat(@TypeOf("{vm.can_back.get()}"), ""), .{ "{vm.can_back.get()}", }))),
            })),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectPanel", .receiver = "W.Button", .tokens = "< W . Button testId = \"spike.v4.disabled\" label = \"disabled={vm.can_back.get()}\" disabled = { vm . can_back . get ( ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.disabled\" ", .kind = .property, .literal = .{ .text = "spike.v4.disabled" } }, .{ .name = "label", .tokens = "\"disabled={vm.can_back.get()}\" ", .kind = .property, .literal = .{ .text = "disabled={vm.can_back.get()}" } }, .{ .name = "disabled", .tokens = "vm . can_back . get ( ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = "spike.v4.disabled", }, __yix_builder_3864: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_3864 W.Button(.{ .label = "disabled={vm.can_back.get()}", .disabled = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().can_back.get());
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().can_back.get();
        } }.__yix_compute);
    }, }); })),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectPanel", .receiver = "text", .tokens = "text testId = @static; style = @static; vm . count . get ( ) + 100  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.inline_get\" ", .kind = .property, .literal = .{ .text = "spike.v4.inline_get" } }, .{ .name = "style", .tokens = "S . body_text ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = "spike.v4.inline_get", .style = S.body_text, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d8: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().count.get() + 100);
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().count.get() + 100;
        } }.__yix_compute);
    }), ""), .{ __yix_d8: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().count.get() + 100);
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().count.get() + 100;
        } }.__yix_compute);
    }, }))),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "DirectPanel";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

// V-4 控制流：条件 / switch（含 else 分支）/ 可选捕获 / 列表，用内联 .get()（直接写 vm.field 编译失败）
pub fn DirectIf(args: anytype) ui.view.ComponentOf(__yix_DirectIf) {
    return ui.view.component(__yix_DirectIf, ui.reactive.props.coerce(DirectIfProps, args));
}
pub const DirectIfProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = DirectIf;
    pub const __yix_preview_mount = __yix_DirectIf;
};
fn __yix_DirectIf(__yix_props: DirectIfProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectIf", .receiver = "col", .tokens = "col testId = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.if_root\" ", .kind = .property, .literal = .{ .text = "spike.v4.if_root" } }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = "spike.v4.if_root", }, .{
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectIf", .receiver = "control", .tokens = "if ( vm . can_back . get ( ) ) < text testId = \"spike.v4.if\" > yes < / text > else < text testId = \"spike.v4.if\" > no < / text > " }, .{ .vm = __yix_view_ctx.vm, }, ui.view.lazyIf(__yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().can_back.get());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().can_back.get();
        } }.__yix_compute);
    }, .{ }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { _ = __yix_b1_0; return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectIf/keyword_if:1/branch:0", .receiver = "text", .tokens = "text testId = @static; ", .literal_text = "yes", .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.if\" ", .kind = .property, .literal = .{ .text = "spike.v4.if" } }, } }, .{ }, ui.view.text(.{ .test_id = "spike.v4.if", }, ui.view.fmt("yes", .{ }))) }); } }.__yix_b, struct { fn __yix_b(__yix_b1_1: anytype, __yix_bs1_1: *ui.Scope, __yix_bc1_1: *ui.Cx, __yix_bk1_1: ui.view.Sink) anyerror!void { _ = __yix_b1_1; return ui.view.emit(__yix_bs1_1, __yix_bc1_1, __yix_bk1_1, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectIf/keyword_if:1/branch:1", .receiver = "text", .tokens = "text testId = @static; ", .literal_text = "no", .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.if\" ", .kind = .property, .literal = .{ .text = "spike.v4.if" } }, } }, .{ }, ui.view.text(.{ .test_id = "spike.v4.if", }, ui.view.fmt("no", .{ }))) }); } }.__yix_b)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "DirectIf";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}
pub fn DirectSwitch(args: anytype) ui.view.ComponentOf(__yix_DirectSwitch) {
    return ui.view.component(__yix_DirectSwitch, ui.reactive.props.coerce(DirectSwitchProps, args));
}
pub const DirectSwitchProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = DirectSwitch;
    pub const __yix_preview_mount = __yix_DirectSwitch;
};
fn __yix_DirectSwitch(__yix_props: DirectSwitchProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectSwitch", .receiver = "col", .tokens = "col testId = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.switch_root\" ", .kind = .property, .literal = .{ .text = "spike.v4.switch_root" } }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = "spike.v4.switch_root", }, .{
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectSwitch", .receiver = "control", .tokens = "switch ( vm . mode . get ( ) ) { . overview => < text testId = \"spike.v4.switch\" > overview < / text > , . panes => < text testId = \"spike.v4.switch\" > panes < / text > , else => < text testId = \"spike.v4.switch\" > search < / text > } " }, .{ .vm = __yix_view_ctx.vm, }, ui.view.lazySwitch(__yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().mode.get());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().mode.get();
        } }.__yix_compute);
    }, .{ }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bt1_0: anytype, __yix_bv1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { _ = __yix_b1_0; _ = __yix_bv1_0; switch (__yix_bt1_0) { .overview => { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectSwitch/keyword_switch:1/case:.overview", .receiver = "text", .tokens = "text testId = @static; ", .literal_text = "overview", .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.switch\" ", .kind = .property, .literal = .{ .text = "spike.v4.switch" } }, } }, .{ }, ui.view.text(.{ .test_id = "spike.v4.switch", }, ui.view.fmt("overview", .{ }))) }); }, .panes => { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectSwitch/keyword_switch:1/case:.panes", .receiver = "text", .tokens = "text testId = @static; ", .literal_text = "panes", .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.switch\" ", .kind = .property, .literal = .{ .text = "spike.v4.switch" } }, } }, .{ }, ui.view.text(.{ .test_id = "spike.v4.switch", }, ui.view.fmt("panes", .{ }))) }); }, else => { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectSwitch/keyword_switch:1/case:else", .receiver = "text", .tokens = "text testId = @static; ", .literal_text = "search", .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.switch\" ", .kind = .property, .literal = .{ .text = "spike.v4.switch" } }, } }, .{ }, ui.view.text(.{ .test_id = "spike.v4.switch", }, ui.view.fmt("search", .{ }))) }); }, } } }.__yix_b)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "DirectSwitch";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}
pub fn DirectOptional(args: anytype) ui.view.ComponentOf(__yix_DirectOptional) {
    return ui.view.component(__yix_DirectOptional, ui.reactive.props.coerce(DirectOptionalProps, args));
}
pub const DirectOptionalProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = DirectOptional;
    pub const __yix_preview_mount = __yix_DirectOptional;
};
fn __yix_DirectOptional(__yix_props: DirectOptionalProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectOptional", .receiver = "col", .tokens = "col testId = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.opt_root\" ", .kind = .property, .literal = .{ .text = "spike.v4.opt_root" } }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = "spike.v4.opt_root", }, .{
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectOptional", .receiver = "control", .tokens = "if ( vm . note . get ( ) ) | n | < text testId = \"spike.v4.opt\" > { n } < / text > else < text testId = \"spike.v4.opt\" > none < / text > " }, .{ .vm = __yix_view_ctx.vm, }, ui.view.lazyIfSome(__yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().note.get());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().note.get();
        } }.__yix_compute);
    }, .{ }, struct { fn __yix_b(__yix_b1_0: anytype, n: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { _ = __yix_b1_0; return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectOptional/keyword_if:1/branch:0", .receiver = "text", .tokens = "text testId = @static; n  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.opt\" ", .kind = .property, .literal = .{ .text = "spike.v4.opt" } }, } }, .{ .n = n, }, ui.view.text(.{ .test_id = "spike.v4.opt", }, ui.view.fmt(ui.view.yixFormat(@TypeOf(n), ""), .{ n, }))) }); } }.__yix_b, struct { fn __yix_b(__yix_b1_1: anytype, __yix_bs1_1: *ui.Scope, __yix_bc1_1: *ui.Cx, __yix_bk1_1: ui.view.Sink) anyerror!void { _ = __yix_b1_1; return ui.view.emit(__yix_bs1_1, __yix_bc1_1, __yix_bk1_1, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectOptional/keyword_if:1/branch:1", .receiver = "text", .tokens = "text testId = @static; ", .literal_text = "none", .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.opt\" ", .kind = .property, .literal = .{ .text = "spike.v4.opt" } }, } }, .{ }, ui.view.text(.{ .test_id = "spike.v4.opt", }, ui.view.fmt("none", .{ }))) }); } }.__yix_b)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "DirectOptional";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}
pub fn DirectFor(args: anytype) ui.view.ComponentOf(__yix_DirectFor) {
    return ui.view.component(__yix_DirectFor, ui.reactive.props.coerce(DirectForProps, args));
}
pub const DirectForProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = DirectFor;
    pub const __yix_preview_mount = __yix_DirectFor;
};
fn __yix_DirectFor(__yix_props: DirectForProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectFor", .receiver = "col", .tokens = "col testId = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v4.for_root\" ", .kind = .property, .literal = .{ .text = "spike.v4.for_root" } }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = "spike.v4.for_root", }, .{
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectFor", .receiver = "control", .tokens = "for ( vm . rows . get ( ) ) | r | < text key = { r . id } > { r . title } < / text > else < text > empty < / text > " }, .{ .vm = __yix_view_ctx.vm, }, ui.view.lazyIf(__yix_d3: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().rows.get().len != 0);
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().rows.get().len != 0;
        } }.__yix_compute);
    }, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ __yix_e1: { const __yix_items_1 = __yix_d2: {
        const __yix_T = @TypeOf(__yix_b1_0.vm.peek().rows.get());
        break :__yix_d2 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().rows.get();
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ }, __yix_items_1, struct { fn __yix_k(r: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(r.id); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, r: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { _ = __yix_row_1; return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectFor/keyword_for:1", .receiver = "text", .tokens = "text key = r . id ; r . title  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "r . id ", .kind = .property, .literal = null }, } }, .{ .r = r, }, ui.view.text(.{ }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(r.peek().title);
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .r = r, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.r.get().title;
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(r.peek().title);
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .r = r, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.r.get().title;
        } }.__yix_compute);
    }, })))); } }.__yix_row); } }); } }.__yix_b, struct { fn __yix_b(__yix_b1_1: anytype, __yix_bs1_1: *ui.Scope, __yix_bc1_1: *ui.Cx, __yix_bk1_1: ui.view.Sink) anyerror!void { _ = __yix_b1_1; return ui.view.emit(__yix_bs1_1, __yix_bc1_1, __yix_bk1_1, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "DirectFor/keyword_for:1/branch:1", .receiver = "text", .tokens = "text ", .literal_text = "empty", .attributes = &.{ } }, .{ }, ui.view.text(.{ }, ui.view.fmt("empty", .{ }))) }); } }.__yix_b)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "DirectFor";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

// ── V-1：import 子目录组件（parts/count_row.yix 内部再用 ../ 引回上层） ──
const Rows = @import("parts/_count_row.yix.zig");
pub fn ImportPanel(args: anytype) ui.view.ComponentOf(__yix_ImportPanel) {
    return ui.view.component(__yix_ImportPanel, ui.reactive.props.coerce(ImportPanelProps, args));
}
pub const ImportPanelProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ImportPanel;
    pub const __yix_preview_mount = __yix_ImportPanel;
};
fn __yix_ImportPanel(__yix_props: ImportPanelProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, true);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ImportPanel", .receiver = "col", .tokens = "col testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v1\" ", .kind = .property, .literal = .{ .text = "spike.v1" } }, .{ .name = "style", .tokens = "S . section ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = "spike.v1", .style = S.section, }, .{
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ImportPanel", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "V-1 子目录组件 + ../ import", .attributes = &.{ .{ .name = "style", .tokens = "S . heading ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.heading, }, ui.view.fmt("V-1 子目录组件 + ../ import", .{ }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ImportPanel", .receiver = "Rows.CountRow", .tokens = "< Rows . CountRow vm = { vm } label = \"count（来自 parts/count_row.yix）\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"count（来自 parts/count_row.yix）\" ", .kind = .property, .literal = .{ .text = "count（来自 parts/count_row.yix）" } }, } }, .{ .vm = __yix_view_ctx.vm, }, __yix_builder_5450: { try ui.view.previewCheckBuilder(__yix_view_scope, Rows.CountRow); break :__yix_builder_5450 Rows.CountRow(.{ .vm = __yix_view_ctx.vm, .label = "count（来自 parts/count_row.yix）", }); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ImportPanel";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

// ── V-5：旧命令式面板经 ComponentOf 嵌入，放在可卸载的条件分支里 ──
const legacy = @import("legacy.zig");
fn legacyShown(vm: *m.ViewModel) bool { return vm.legacy_shown.get(); }
fn legacyOuterShown(vm: *m.ViewModel) bool { return vm.legacy_outer_shown.get(); }
fn toggleLegacy(vm: *m.ViewModel) void { vm.legacy_shown.set(!vm.legacy_shown.peek()); }
pub fn LegacyHost(args: anytype) ui.view.ComponentOf(__yix_LegacyHost) {
    return ui.view.component(__yix_LegacyHost, ui.reactive.props.coerce(LegacyHostProps, args));
}
pub const LegacyHostProps = struct {
    vm: ui.Source(*m.ViewModel),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = LegacyHost;
    pub const __yix_preview_mount = __yix_LegacyHost;
};
fn __yix_LegacyHost(__yix_props: LegacyHostProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "LegacyHost", .receiver = "col", .tokens = "col testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v5\" ", .kind = .property, .literal = .{ .text = "spike.v5" } }, .{ .name = "style", .tokens = "S . section ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, }, ui.view.col(.{ .test_id = "spike.v5", .style = S.section, }, .{
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "LegacyHost", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "V-5 ComponentOf(旧 mountContent)", .attributes = &.{ .{ .name = "style", .tokens = "S . heading ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.heading, }, ui.view.fmt("V-5 ComponentOf(旧 mountContent)", .{ }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "LegacyHost", .receiver = "W.Button", .tokens = "< W . Button testId = \"spike.v5.toggle\" label = \"挂载 / 卸载旧面板\" onClick = { toggleLegacy ( vm ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v5.toggle\" ", .kind = .property, .literal = .{ .text = "spike.v5.toggle" } }, .{ .name = "label", .tokens = "\"挂载 / 卸载旧面板\" ", .kind = .property, .literal = .{ .text = "挂载 / 卸载旧面板" } }, .{ .name = "on_click", .tokens = "toggleLegacy ( vm ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = "spike.v5.toggle", }, __yix_builder_6124: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_6124 W.Button(.{ .label = "挂载 / 卸载旧面板", .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); toggleLegacy(__yix_ctx.vm.peek());  } }.__yix_run) else __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(toggleLegacy(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return toggleLegacy(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, }); })),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "LegacyHost", .receiver = "control", .tokens = "if ( legacyShown ( vm ) ) < legacy . LegacyPanel label = \"旧面板（子 scope）\" / > " }, .{ .vm = __yix_view_ctx.vm, }, ui.view.lazyIf(__yix_d1: {
        const __yix_T = @TypeOf(legacyShown(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return legacyShown(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .{ }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { _ = __yix_b1_0; return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "LegacyHost/keyword_if:1/branch:0", .receiver = "legacy.LegacyPanel", .tokens = "< legacy . LegacyPanel label = \"旧面板（子 scope）\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "label", .tokens = "\"旧面板（子 scope）\" ", .kind = .property, .literal = .{ .text = "旧面板（子 scope）" } }, } }, .{ }, __yix_builder_21: { try ui.view.previewCheckBuilder(__yix_bs1_0, legacy.LegacyPanel); break :__yix_builder_21 legacy.LegacyPanel(.{ .label = "旧面板（子 scope）", }); }) }); } }.__yix_b, null)),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "LegacyHost", .receiver = "control", .tokens = "if ( legacyOuterShown ( vm ) ) < legacy . LegacyPanelOuterScope label = \"旧面板（外部 scope，反例）\" / > " }, .{ .vm = __yix_view_ctx.vm, }, ui.view.lazyIf(__yix_d1: {
        const __yix_T = @TypeOf(legacyOuterShown(__yix_view_ctx.vm.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return legacyOuterShown(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .{ }, struct { fn __yix_b(__yix_b2_0: anytype, __yix_bs2_0: *ui.Scope, __yix_bc2_0: *ui.Cx, __yix_bk2_0: ui.view.Sink) anyerror!void { _ = __yix_b2_0; return ui.view.emit(__yix_bs2_0, __yix_bc2_0, __yix_bk2_0, .{ ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "LegacyHost/keyword_if:2/branch:0", .receiver = "legacy.LegacyPanelOuterScope", .tokens = "< legacy . LegacyPanelOuterScope label = \"旧面板（外部 scope，反例）\" / > ", .literal_text = null, .attributes = &.{ .{ .name = "label", .tokens = "\"旧面板（外部 scope，反例）\" ", .kind = .property, .literal = .{ .text = "旧面板（外部 scope，反例）" } }, } }, .{ }, __yix_builder_26: { try ui.view.previewCheckBuilder(__yix_bs2_0, legacy.LegacyPanelOuterScope); break :__yix_builder_26 legacy.LegacyPanelOuterScope(.{ .label = "旧面板（外部 scope，反例）", }); }) }); } }.__yix_b, null)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "LegacyHost";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

// ── V-11：windowRegion 属性 ──
fn noop() void {}
pub fn ChromeHeader(args: anytype) ui.view.ComponentOf(__yix_ChromeHeader) {
    return ui.view.component(__yix_ChromeHeader, ui.reactive.props.coerce(ChromeHeaderProps, args));
}
pub const ChromeHeaderProps = struct {
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ChromeHeader;
    pub const __yix_preview_mount = __yix_ChromeHeader;
};
fn __yix_ChromeHeader(__yix_props: ChromeHeaderProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    _ = __yix_props;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    _ = __yix_view_ctx;
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ChromeHeader", .receiver = "row", .tokens = "row testId = @static; windowRegion = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v11.header\" ", .kind = .property, .literal = .{ .text = "spike.v11.header" } }, .{ .name = "window_region", .tokens = ". drag ", .kind = .property, .literal = .{ .enum_name = "drag" } }, .{ .name = "style", .tokens = "S . header ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ }, ui.view.row(.{ .test_id = "spike.v11.header", .window_region = .drag, .style = S.header, }, .{
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ChromeHeader", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "V-11 windowRegion=.drag", .attributes = &.{ .{ .name = "style", .tokens = "S . body_text ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.body_text, }, ui.view.fmt("V-11 windowRegion=.drag", .{ }))),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ChromeHeader", .receiver = "W.Button", .tokens = "< W . Button testId = \"spike.v11.button\" label = \"按钮\" onClick = { noop ( ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v11.button\" ", .kind = .property, .literal = .{ .text = "spike.v11.button" } }, .{ .name = "label", .tokens = "\"按钮\" ", .kind = .property, .literal = .{ .text = "按钮" } }, .{ .name = "on_click", .tokens = "noop ( ) ", .kind = .event, .literal = null }, } }, .{ }, ui.view.templateAttrs(.{ .test_id = "spike.v11.button", }, __yix_builder_6719: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_6719 W.Button(.{ .label = "按钮", .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); noop();  } }.__yix_run) else __yix_call2: {
        const __yix_Raw = @TypeOf(noop());
        break :__yix_call2 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) noop() else __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(noop());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return noop();
        } }.__yix_compute);
    };
    }, }); })),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ChromeHeader", .receiver = "box", .tokens = "box testId = @static; windowRegion = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v11.client\" ", .kind = .property, .literal = .{ .text = "spike.v11.client" } }, .{ .name = "window_region", .tokens = ". client ", .kind = .property, .literal = .{ .enum_name = "client" } }, .{ .name = "style", .tokens = "S . chip ", .kind = .style, .literal = null }, } }, .{ }, ui.view.box(.{ .test_id = "spike.v11.client", .window_region = .client, .style = S.chip, }, .{
                ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ChromeHeader", .receiver = "text", .tokens = "text style = @static; ", .literal_text = ".client", .attributes = &.{ .{ .name = "style", .tokens = "S . muted ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.muted, }, ui.view.fmt(".client", .{ }))),
            })),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ChromeHeader", .receiver = "box", .tokens = "box testId = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v11.plain\" ", .kind = .property, .literal = .{ .text = "spike.v11.plain" } }, .{ .name = "style", .tokens = "S . chip ", .kind = .style, .literal = null }, } }, .{ }, ui.view.box(.{ .test_id = "spike.v11.plain", .style = S.chip, }, .{
                ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ChromeHeader", .receiver = "text", .tokens = "text style = @static; ", .literal_text = "inherit", .attributes = &.{ .{ .name = "style", .tokens = "S . muted ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.muted, }, ui.view.fmt("inherit", .{ }))),
            })),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ChromeHeader", .receiver = "spacer", .tokens = "spacer ", .literal_text = null, .attributes = &.{ } }, .{ }, ui.view.spacer()),
            ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ChromeHeader", .receiver = "box", .tokens = "box testId = @static; windowRegion = @static; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"spike.v11.close\" ", .kind = .property, .literal = .{ .text = "spike.v11.close" } }, .{ .name = "window_region", .tokens = ". close ", .kind = .property, .literal = .{ .enum_name = "close" } }, .{ .name = "style", .tokens = "S . chip ", .kind = .style, .literal = null }, } }, .{ }, ui.view.box(.{ .test_id = "spike.v11.close", .window_region = .close, .style = S.chip, }, .{
                ui.view.templateSite(.{ .module = "tools/mockups/yix_spike/views.yix", .path = "ChromeHeader", .receiver = "text", .tokens = "text style = @static; ", .literal_text = ".close", .attributes = &.{ .{ .name = "style", .tokens = "S . muted ", .kind = .style, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.muted, }, ui.view.fmt(".close", .{ }))),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ChromeHeader";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\x79\x69\x78\x5f\x73\x70\x69\x6b\x65\x20\xe7\x9a\x84\x20\x59\x69\x78\x20\xe8\xa7\x86\xe5\x9b\xbe\xef\xbc\x9a\xe6\xaf\x8f\xe4\xb8\xaa\xe7\xbb\x84\xe4\xbb\xb6\xe5\xaf\xb9\xe5\xba\x94\xe4\xb8\x80\xe4\xb8\xaa\x20\x56\x20\xe9\xa1\xb9\xe3\x80\x82\x0a\x63\x6f\x6e\x73\x74\x20\x73\x74\x64\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x73\x74\x64\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x53\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x73\x74\x79\x6c\x65\x73\x2e\x79\x73\x73\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x6d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x76\x6d\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\x56\x2d\x32\xef\xbc\x9a\xe9\x80\x89\xe6\x8b\xa9\xe5\x99\xa8\xe5\x87\xbd\xe6\x95\xb0\xef\xbc\x8c\xe5\x8f\x82\xe6\x95\xb0\xe6\x98\xaf\x20\x2a\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\xef\xbc\x8c\xe5\x86\x85\xe9\x83\xa8\x20\x2e\x67\x65\x74\x28\x29\x20\xe8\xaf\xbb\xe4\xbf\xa1\xe5\x8f\xb7\x20\xe2\x94\x80\xe2\x94\x80\x0a\x66\x6e\x20\x74\x69\x74\x6c\x65\x4f\x66\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x73\x65\x6c\x65\x63\x74\x6f\x72\x5f\x72\x75\x6e\x73\x20\x2b\x3d\x20\x31\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x74\x69\x74\x6c\x65\x2e\x67\x65\x74\x28\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x63\x61\x6e\x6e\x6f\x74\x42\x61\x63\x6b\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x20\x72\x65\x74\x75\x72\x6e\x20\x21\x76\x6d\x2e\x63\x61\x6e\x5f\x62\x61\x63\x6b\x2e\x67\x65\x74\x28\x29\x3b\x20\x7d\x0a\x66\x6e\x20\x6d\x6f\x64\x65\x4f\x66\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x6d\x2e\x4d\x6f\x64\x65\x20\x7b\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x6d\x6f\x64\x65\x2e\x67\x65\x74\x28\x29\x3b\x20\x7d\x0a\x0a\x2f\x2f\x20\xe6\xb3\xa8\xe6\x84\x8f\xef\xbc\x9a\x59\x69\x78\x20\xe4\xb8\x8d\xe6\x94\xaf\xe6\x8c\x81\xe5\xa4\x9a\xe5\x80\xbc\xe5\x88\x86\xe6\x94\xaf\x20\x60\x2e\x70\x61\x6e\x65\x73\x2c\x20\x2e\x73\x65\x61\x72\x63\x68\x20\x3d\x3e\x60\xef\xbc\x88\x79\x69\x78\x20\x67\x65\x6e\x20\xe6\x8a\xa5\x20\x22\x75\x6e\x65\x78\x70\x65\x63\x74\x65\x64\x20\x74\x6f\x6b\x65\x6e\x22\xef\xbc\x89\xef\xbc\x8c\xe6\x8b\x86\xe5\xbc\x80\xe5\x86\x99\xe6\x88\x96\xe7\x94\xa8\x20\x65\x6c\x73\x65\xe3\x80\x82\x0a\x2f\x2f\x20\xe5\x8f\xa6\xe5\xa4\x96\x20\x60\x2f\x2f\x60\x20\xe6\xb3\xa8\xe9\x87\x8a\xe5\x86\x99\xe5\x9c\xa8\xe6\xa0\x87\xe7\xad\xbe\xe5\x86\x85\xe9\x83\xa8\xe4\xbc\x9a\xe5\x8f\x98\xe6\x88\x90\xe6\x96\x87\xe6\x9c\xac\xe8\x8a\x82\xe7\x82\xb9\xef\xbc\x8c\xe6\xb3\xa8\xe9\x87\x8a\xe5\x8f\xaa\xe8\x83\xbd\xe6\x94\xbe\xe5\x9c\xa8\xe6\xa8\xa1\xe6\x9d\xbf\xe5\xa4\x96\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x53\x65\x6c\x65\x63\x74\x6f\x72\x50\x61\x6e\x65\x6c\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x32\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x63\x74\x69\x6f\x6e\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x61\x64\x69\x6e\x67\x7d\x3e\x56\x2d\x32\x20\xe9\x80\x89\xe6\x8b\xa9\xe5\x99\xa8\x28\x76\x6d\x29\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x32\x2e\x74\x69\x74\x6c\x65\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x5f\x74\x65\x78\x74\x7d\x3e\x7b\x74\x69\x74\x6c\x65\x4f\x66\x28\x76\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x32\x2e\x62\x61\x63\x6b\x5f\x68\x69\x6e\x74\x22\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x63\x61\x6e\x6e\x6f\x74\x42\x61\x63\x6b\x28\x76\x6d\x29\x7d\x3e\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x75\x74\x65\x64\x7d\x3e\xe5\xb7\xb2\xe5\x9c\xa8\xe6\x9c\x80\xe5\x89\x8d\x3c\x2f\x74\x65\x78\x74\x3e\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x73\x77\x69\x74\x63\x68\x20\x28\x6d\x6f\x64\x65\x4f\x66\x28\x76\x6d\x29\x29\x20\x7b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x20\x3d\x3e\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x32\x2e\x6d\x6f\x64\x65\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x75\x74\x65\x64\x7d\x3e\x6f\x76\x65\x72\x76\x69\x65\x77\x3c\x2f\x74\x65\x78\x74\x3e\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x70\x61\x6e\x65\x73\x20\x3d\x3e\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x32\x2e\x6d\x6f\x64\x65\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x75\x74\x65\x64\x7d\x3e\x70\x61\x6e\x65\x73\x3c\x2f\x74\x65\x78\x74\x3e\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x73\x65\x61\x72\x63\x68\x20\x3d\x3e\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x32\x2e\x6d\x6f\x64\x65\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x75\x74\x65\x64\x7d\x3e\x73\x65\x61\x72\x63\x68\x3c\x2f\x74\x65\x78\x74\x3e\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7d\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\x56\x2d\x33\xef\xbc\x9a\xe4\xba\x8b\xe4\xbb\xb6\xe9\x87\x8c\xe8\xb0\x83\xe7\x94\xa8\xe5\xb8\xa6\xe5\x8f\x82\xe6\x95\xb0\xe7\x9a\x84\xe5\x87\xbd\xe6\x95\xb0\xef\xbc\x8c\xe5\xae\x9e\xe5\x8f\x82\xe5\x90\xab\xe6\x9e\x9a\xe4\xb8\xbe\xe5\xad\x97\xe9\x9d\xa2\xe9\x87\x8f\x20\x2f\x20\xe5\xb8\xa6\xe8\xbd\xbd\xe8\x8d\xb7\xe7\x9a\x84\x20\x49\x6e\x74\x65\x6e\x74\x20\xe2\x94\x80\xe2\x94\x80\x0a\x2f\x2f\x20\xe6\xb3\xa8\xe6\x84\x8f\xef\xbc\x9a\xe5\xae\x9e\xe5\x8f\x82\xe9\x87\x8c\xe5\x86\x99\xe7\xbb\x93\xe6\x9e\x84\xe4\xbd\x93\xe5\xad\x97\xe9\x9d\xa2\xe9\x87\x8f\x20\x60\x2e\x7b\x20\x2e\x73\x65\x74\x5f\x63\x6f\x75\x6e\x74\x20\x3d\x20\x35\x20\x7d\x60\x20\xe6\x88\x96\x20\x60\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x7b\x20\x2e\x73\x65\x74\x5f\x63\x6f\x75\x6e\x74\x20\x3d\x20\x35\x20\x7d\x60\x20\xe4\xbc\x9a\xe8\xa2\xab\x20\x79\x69\x78\x20\x67\x65\x6e\x20\xe6\x8b\x92\xe7\xbb\x9d\x0a\x2f\x2f\x20\xef\xbc\x88\x22\x66\x69\x65\x6c\x64\x20\x77\x72\x69\x74\x65\x73\x20\x61\x6e\x64\x20\x6e\x65\x73\x74\x65\x64\x20\x65\x76\x65\x6e\x74\x20\x73\x74\x61\x74\x65\x6d\x65\x6e\x74\x73\x20\x61\x72\x65\x20\x6e\x6f\x74\x20\x69\x6d\x70\x6c\x65\x6d\x65\x6e\x74\x65\x64\x22\xef\xbc\x89\xef\xbc\x8c\xe8\xbd\xbd\xe8\x8d\xb7\xe7\x94\xa8\x20\x40\x75\x6e\x69\x6f\x6e\x49\x6e\x69\x74\x20\xe6\x88\x96\xe6\x9e\x84\xe9\x80\xa0\xe5\x87\xbd\xe6\x95\xb0\xe3\x80\x82\x0a\x66\x6e\x20\x73\x65\x6e\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x74\x65\x6e\x74\x3a\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x73\x65\x6e\x64\x5f\x63\x61\x6c\x6c\x73\x20\x2b\x3d\x20\x31\x3b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x69\x6e\x74\x65\x6e\x74\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x45\x76\x65\x6e\x74\x50\x61\x6e\x65\x6c\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x33\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x63\x74\x69\x6f\x6e\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x61\x64\x69\x6e\x67\x7d\x3e\x56\x2d\x33\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x22\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x2e\x62\x61\x63\x6b\x29\x7d\x22\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x63\x74\x69\x6f\x6e\x5f\x72\x6f\x77\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x33\x2e\x62\x61\x63\x6b\x22\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe5\x90\x8e\xe9\x80\x80\x22\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x63\x61\x6e\x6e\x6f\x74\x42\x61\x63\x6b\x28\x76\x6d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x2e\x62\x61\x63\x6b\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x33\x2e\x66\x6f\x72\x77\x61\x72\x64\x22\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe5\x89\x8d\xe8\xbf\x9b\x22\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x2e\x66\x6f\x72\x77\x61\x72\x64\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x33\x2e\x61\x64\x64\x22\x20\x6c\x61\x62\x65\x6c\x3d\x22\x2b\x35\x22\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x40\x75\x6e\x69\x6f\x6e\x49\x6e\x69\x74\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2c\x20\x22\x73\x65\x74\x5f\x63\x6f\x75\x6e\x74\x22\x2c\x20\x35\x29\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x33\x2e\x68\x6f\x73\x74\x22\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x2e\x74\x6f\x67\x67\x6c\x65\x5f\x66\x6c\x61\x67\x29\x7d\x3e\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x5f\x74\x65\x78\x74\x7d\x3e\xe5\xae\xbf\xe4\xb8\xbb\x20\x62\x6f\x78\x3c\x2f\x74\x65\x78\x74\x3e\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\x56\x2d\x34\xef\xbc\x9a\xe6\xa8\xa1\xe6\x9d\xbf\xe9\x87\x8c\xe7\x9b\xb4\xe6\x8e\xa5\xe5\x86\x99\x20\x76\x6d\x2e\x3c\xe4\xbf\xa1\xe5\x8f\xb7\xe5\xad\x97\xe6\xae\xb5\x3e\x20\xe2\x94\x80\xe2\x94\x80\x0a\x2f\x2f\x20\xe5\x8e\x9f\xe5\x85\x88\xe5\x89\x8d\xe4\xba\x94\xe8\xa1\x8c\xe6\x98\xaf\xe5\x8f\x8d\xe4\xbe\x8b\xef\xbc\x9a\x7b\x76\x6d\x2e\x66\x69\x65\x6c\x64\x7d\x20\xe8\x83\xbd\xe7\xbc\x96\xe8\xaf\x91\xef\xbc\x8c\xe4\xbd\x86\xe6\xb8\xb2\xe6\x9f\x93\xe5\x87\xba\x20\x53\x69\x67\x6e\x61\x6c\x20\x2f\x20\x4d\x65\x6d\x6f\x20\xe7\xbb\x93\xe6\x9e\x84\xe4\xbd\x93\xe7\x9a\x84\xe8\xb0\x83\xe8\xaf\x95\xe8\xbd\xac\xe5\x82\xa8\xe3\x80\x82\x7a\x65\x6e\x69\x74\x20\xe7\x8e\xb0\xe5\x9c\xa8\xe5\x9c\xa8\xe7\xbc\x96\xe8\xaf\x91\xe6\x9c\x9f\xe6\x8b\x92\xe7\xbb\x9d\x0a\x2f\x2f\x20\xe6\x8a\x8a\xe5\x93\x8d\xe5\xba\x94\xe5\xbc\x8f\xe6\xba\x90\xe7\x9b\xb4\xe6\x8e\xa5\xe6\x8f\x92\xe8\xbf\x9b\x20\x7b\xe2\x80\xa6\x7d\xef\xbc\x88\x76\x69\x65\x77\x2e\x7a\x69\x67\xef\xbc\x9a\xe2\x80\x9c\x74\x68\x65\x20\x69\x6e\x74\x65\x72\x70\x6f\x6c\x61\x74\x65\x64\x20\x76\x61\x6c\x75\x65\x20\x69\x73\x20\x61\x20\x72\x65\x61\x63\x74\x69\x76\x65\x20\x73\x6f\x75\x72\x63\x65\xe2\x80\x9d\xef\xbc\x89\xef\xbc\x8c\xe5\x8f\x8d\xe4\xbe\x8b\xe5\xb7\xb2\xe6\x97\xa0\xe6\xb3\x95\xe7\xbc\x96\xe8\xaf\x91\xef\xbc\x8c\xe6\x94\xb9\xe4\xb8\xba\xe5\x86\x85\xe8\x81\x94\x20\x2e\x67\x65\x74\x28\x29\xe3\x80\x82\x0a\x2f\x2f\x20\xe7\x9b\xb4\xe6\x8e\xa5\xe5\x86\x99\xe8\xbf\x9b\x20\x76\x69\x73\x69\x62\x6c\x65\x20\x2f\x20\x69\x66\x20\x2f\x20\x73\x77\x69\x74\x63\x68\x20\x2f\x20\x66\x6f\x72\x20\x2f\x20\xe7\xbb\x84\xe4\xbb\xb6\xe5\xb1\x9e\xe6\x80\xa7\xe5\x90\x8c\xe6\xa0\xb7\xe7\xbc\x96\xe8\xaf\x91\xe5\xa4\xb1\xe8\xb4\xa5\xef\xbc\x9b\xe5\x8f\xaf\xe7\x94\xa8\xe5\x86\x99\xe6\xb3\x95\xe6\x98\xaf\xe5\x86\x85\xe8\x81\x94\x20\x2e\x67\x65\x74\x28\x29\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x44\x69\x72\x65\x63\x74\x50\x61\x6e\x65\x6c\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x63\x74\x69\x6f\x6e\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x61\x64\x69\x6e\x67\x7d\x3e\x56\x2d\x34\x20\xe7\x9b\xb4\xe6\x8e\xa5\xe5\x86\x99\x20\x76\x6d\x2e\x66\x69\x65\x6c\x64\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x74\x69\x74\x6c\x65\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x5f\x74\x65\x78\x74\x7d\x3e\x7b\x76\x6d\x2e\x74\x69\x74\x6c\x65\x2e\x67\x65\x74\x28\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x63\x6f\x75\x6e\x74\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x5f\x74\x65\x78\x74\x7d\x3e\x63\x6f\x75\x6e\x74\x3d\x7b\x76\x6d\x2e\x63\x6f\x75\x6e\x74\x2e\x67\x65\x74\x28\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x64\x6f\x75\x62\x6c\x65\x64\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x5f\x74\x65\x78\x74\x7d\x3e\x64\x6f\x75\x62\x6c\x65\x64\x3d\x7b\x76\x6d\x2e\x64\x6f\x75\x62\x6c\x65\x64\x2e\x67\x65\x74\x28\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x6d\x6f\x64\x65\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x5f\x74\x65\x78\x74\x7d\x3e\x6d\x6f\x64\x65\x3d\x7b\x76\x6d\x2e\x6d\x6f\x64\x65\x2e\x67\x65\x74\x28\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x66\x6c\x61\x67\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x5f\x74\x65\x78\x74\x7d\x3e\x63\x61\x6e\x5f\x62\x61\x63\x6b\x3d\x7b\x76\x6d\x2e\x63\x61\x6e\x5f\x62\x61\x63\x6b\x2e\x67\x65\x74\x28\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x76\x69\x73\x69\x62\x6c\x65\x22\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x63\x61\x6e\x5f\x62\x61\x63\x6b\x2e\x67\x65\x74\x28\x29\x7d\x3e\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x75\x74\x65\x64\x7d\x3e\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x22\x7b\x76\x6d\x2e\x63\x61\x6e\x5f\x62\x61\x63\x6b\x2e\x67\x65\x74\x28\x29\x7d\x22\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x22\x20\x6c\x61\x62\x65\x6c\x3d\x22\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x76\x6d\x2e\x63\x61\x6e\x5f\x62\x61\x63\x6b\x2e\x67\x65\x74\x28\x29\x7d\x22\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x76\x6d\x2e\x63\x61\x6e\x5f\x62\x61\x63\x6b\x2e\x67\x65\x74\x28\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x69\x6e\x6c\x69\x6e\x65\x5f\x67\x65\x74\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x5f\x74\x65\x78\x74\x7d\x3e\x7b\x76\x6d\x2e\x63\x6f\x75\x6e\x74\x2e\x67\x65\x74\x28\x29\x20\x2b\x20\x31\x30\x30\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\x56\x2d\x34\x20\xe6\x8e\xa7\xe5\x88\xb6\xe6\xb5\x81\xef\xbc\x9a\xe6\x9d\xa1\xe4\xbb\xb6\x20\x2f\x20\x73\x77\x69\x74\x63\x68\xef\xbc\x88\xe5\x90\xab\x20\x65\x6c\x73\x65\x20\xe5\x88\x86\xe6\x94\xaf\xef\xbc\x89\x2f\x20\xe5\x8f\xaf\xe9\x80\x89\xe6\x8d\x95\xe8\x8e\xb7\x20\x2f\x20\xe5\x88\x97\xe8\xa1\xa8\xef\xbc\x8c\xe7\x94\xa8\xe5\x86\x85\xe8\x81\x94\x20\x2e\x67\x65\x74\x28\x29\xef\xbc\x88\xe7\x9b\xb4\xe6\x8e\xa5\xe5\x86\x99\x20\x76\x6d\x2e\x66\x69\x65\x6c\x64\x20\xe7\xbc\x96\xe8\xaf\x91\xe5\xa4\xb1\xe8\xb4\xa5\xef\xbc\x89\x0a\x70\x75\x62\x20\x66\x6e\x20\x44\x69\x72\x65\x63\x74\x49\x66\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x69\x66\x5f\x72\x6f\x6f\x74\x22\x3e\x7b\x69\x66\x20\x28\x76\x6d\x2e\x63\x61\x6e\x5f\x62\x61\x63\x6b\x2e\x67\x65\x74\x28\x29\x29\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x69\x66\x22\x3e\x79\x65\x73\x3c\x2f\x74\x65\x78\x74\x3e\x20\x65\x6c\x73\x65\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x69\x66\x22\x3e\x6e\x6f\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x3c\x2f\x63\x6f\x6c\x3e\x3b\x0a\x7d\x0a\x70\x75\x62\x20\x66\x6e\x20\x44\x69\x72\x65\x63\x74\x53\x77\x69\x74\x63\x68\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x73\x77\x69\x74\x63\x68\x5f\x72\x6f\x6f\x74\x22\x3e\x7b\x73\x77\x69\x74\x63\x68\x20\x28\x76\x6d\x2e\x6d\x6f\x64\x65\x2e\x67\x65\x74\x28\x29\x29\x20\x7b\x20\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x20\x3d\x3e\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x73\x77\x69\x74\x63\x68\x22\x3e\x6f\x76\x65\x72\x76\x69\x65\x77\x3c\x2f\x74\x65\x78\x74\x3e\x2c\x20\x2e\x70\x61\x6e\x65\x73\x20\x3d\x3e\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x73\x77\x69\x74\x63\x68\x22\x3e\x70\x61\x6e\x65\x73\x3c\x2f\x74\x65\x78\x74\x3e\x2c\x20\x65\x6c\x73\x65\x20\x3d\x3e\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x73\x77\x69\x74\x63\x68\x22\x3e\x73\x65\x61\x72\x63\x68\x3c\x2f\x74\x65\x78\x74\x3e\x20\x7d\x7d\x3c\x2f\x63\x6f\x6c\x3e\x3b\x0a\x7d\x0a\x70\x75\x62\x20\x66\x6e\x20\x44\x69\x72\x65\x63\x74\x4f\x70\x74\x69\x6f\x6e\x61\x6c\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x6f\x70\x74\x5f\x72\x6f\x6f\x74\x22\x3e\x7b\x69\x66\x20\x28\x76\x6d\x2e\x6e\x6f\x74\x65\x2e\x67\x65\x74\x28\x29\x29\x20\x7c\x6e\x7c\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x6f\x70\x74\x22\x3e\x7b\x6e\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x20\x65\x6c\x73\x65\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x6f\x70\x74\x22\x3e\x6e\x6f\x6e\x65\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x3c\x2f\x63\x6f\x6c\x3e\x3b\x0a\x7d\x0a\x70\x75\x62\x20\x66\x6e\x20\x44\x69\x72\x65\x63\x74\x46\x6f\x72\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x34\x2e\x66\x6f\x72\x5f\x72\x6f\x6f\x74\x22\x3e\x7b\x66\x6f\x72\x20\x28\x76\x6d\x2e\x72\x6f\x77\x73\x2e\x67\x65\x74\x28\x29\x29\x20\x7c\x72\x7c\x20\x3c\x74\x65\x78\x74\x20\x6b\x65\x79\x3d\x7b\x72\x2e\x69\x64\x7d\x3e\x7b\x72\x2e\x74\x69\x74\x6c\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x20\x65\x6c\x73\x65\x20\x3c\x74\x65\x78\x74\x3e\x65\x6d\x70\x74\x79\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x3c\x2f\x63\x6f\x6c\x3e\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\x56\x2d\x31\xef\xbc\x9a\x69\x6d\x70\x6f\x72\x74\x20\xe5\xad\x90\xe7\x9b\xae\xe5\xbd\x95\xe7\xbb\x84\xe4\xbb\xb6\xef\xbc\x88\x70\x61\x72\x74\x73\x2f\x63\x6f\x75\x6e\x74\x5f\x72\x6f\x77\x2e\x79\x69\x78\x20\xe5\x86\x85\xe9\x83\xa8\xe5\x86\x8d\xe7\x94\xa8\x20\x2e\x2e\x2f\x20\xe5\xbc\x95\xe5\x9b\x9e\xe4\xb8\x8a\xe5\xb1\x82\xef\xbc\x89\x20\xe2\x94\x80\xe2\x94\x80\x0a\x63\x6f\x6e\x73\x74\x20\x52\x6f\x77\x73\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x70\x61\x72\x74\x73\x2f\x63\x6f\x75\x6e\x74\x5f\x72\x6f\x77\x2e\x79\x69\x78\x22\x29\x3b\x0a\x70\x75\x62\x20\x66\x6e\x20\x49\x6d\x70\x6f\x72\x74\x50\x61\x6e\x65\x6c\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x31\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x63\x74\x69\x6f\x6e\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x61\x64\x69\x6e\x67\x7d\x3e\x56\x2d\x31\x20\xe5\xad\x90\xe7\x9b\xae\xe5\xbd\x95\xe7\xbb\x84\xe4\xbb\xb6\x20\x2b\x20\x2e\x2e\x2f\x20\x69\x6d\x70\x6f\x72\x74\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x52\x6f\x77\x73\x2e\x43\x6f\x75\x6e\x74\x52\x6f\x77\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\x63\x6f\x75\x6e\x74\xef\xbc\x88\xe6\x9d\xa5\xe8\x87\xaa\x20\x70\x61\x72\x74\x73\x2f\x63\x6f\x75\x6e\x74\x5f\x72\x6f\x77\x2e\x79\x69\x78\xef\xbc\x89\x22\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\x56\x2d\x35\xef\xbc\x9a\xe6\x97\xa7\xe5\x91\xbd\xe4\xbb\xa4\xe5\xbc\x8f\xe9\x9d\xa2\xe6\x9d\xbf\xe7\xbb\x8f\x20\x43\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x4f\x66\x20\xe5\xb5\x8c\xe5\x85\xa5\xef\xbc\x8c\xe6\x94\xbe\xe5\x9c\xa8\xe5\x8f\xaf\xe5\x8d\xb8\xe8\xbd\xbd\xe7\x9a\x84\xe6\x9d\xa1\xe4\xbb\xb6\xe5\x88\x86\xe6\x94\xaf\xe9\x87\x8c\x20\xe2\x94\x80\xe2\x94\x80\x0a\x63\x6f\x6e\x73\x74\x20\x6c\x65\x67\x61\x63\x79\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x6c\x65\x67\x61\x63\x79\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x66\x6e\x20\x6c\x65\x67\x61\x63\x79\x53\x68\x6f\x77\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x6c\x65\x67\x61\x63\x79\x5f\x73\x68\x6f\x77\x6e\x2e\x67\x65\x74\x28\x29\x3b\x20\x7d\x0a\x66\x6e\x20\x6c\x65\x67\x61\x63\x79\x4f\x75\x74\x65\x72\x53\x68\x6f\x77\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x6c\x65\x67\x61\x63\x79\x5f\x6f\x75\x74\x65\x72\x5f\x73\x68\x6f\x77\x6e\x2e\x67\x65\x74\x28\x29\x3b\x20\x7d\x0a\x66\x6e\x20\x74\x6f\x67\x67\x6c\x65\x4c\x65\x67\x61\x63\x79\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x76\x6f\x69\x64\x20\x7b\x20\x76\x6d\x2e\x6c\x65\x67\x61\x63\x79\x5f\x73\x68\x6f\x77\x6e\x2e\x73\x65\x74\x28\x21\x76\x6d\x2e\x6c\x65\x67\x61\x63\x79\x5f\x73\x68\x6f\x77\x6e\x2e\x70\x65\x65\x6b\x28\x29\x29\x3b\x20\x7d\x0a\x70\x75\x62\x20\x66\x6e\x20\x4c\x65\x67\x61\x63\x79\x48\x6f\x73\x74\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x35\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x63\x74\x69\x6f\x6e\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x61\x64\x69\x6e\x67\x7d\x3e\x56\x2d\x35\x20\x43\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x4f\x66\x28\xe6\x97\xa7\x20\x6d\x6f\x75\x6e\x74\x43\x6f\x6e\x74\x65\x6e\x74\x29\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x35\x2e\x74\x6f\x67\x67\x6c\x65\x22\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe6\x8c\x82\xe8\xbd\xbd\x20\x2f\x20\xe5\x8d\xb8\xe8\xbd\xbd\xe6\x97\xa7\xe9\x9d\xa2\xe6\x9d\xbf\x22\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x74\x6f\x67\x67\x6c\x65\x4c\x65\x67\x61\x63\x79\x28\x76\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x6c\x65\x67\x61\x63\x79\x53\x68\x6f\x77\x6e\x28\x76\x6d\x29\x29\x20\x3c\x6c\x65\x67\x61\x63\x79\x2e\x4c\x65\x67\x61\x63\x79\x50\x61\x6e\x65\x6c\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe6\x97\xa7\xe9\x9d\xa2\xe6\x9d\xbf\xef\xbc\x88\xe5\xad\x90\x20\x73\x63\x6f\x70\x65\xef\xbc\x89\x22\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x6c\x65\x67\x61\x63\x79\x4f\x75\x74\x65\x72\x53\x68\x6f\x77\x6e\x28\x76\x6d\x29\x29\x20\x3c\x6c\x65\x67\x61\x63\x79\x2e\x4c\x65\x67\x61\x63\x79\x50\x61\x6e\x65\x6c\x4f\x75\x74\x65\x72\x53\x63\x6f\x70\x65\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe6\x97\xa7\xe9\x9d\xa2\xe6\x9d\xbf\xef\xbc\x88\xe5\xa4\x96\xe9\x83\xa8\x20\x73\x63\x6f\x70\x65\xef\xbc\x8c\xe5\x8f\x8d\xe4\xbe\x8b\xef\xbc\x89\x22\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\x56\x2d\x31\x31\xef\xbc\x9a\x77\x69\x6e\x64\x6f\x77\x52\x65\x67\x69\x6f\x6e\x20\xe5\xb1\x9e\xe6\x80\xa7\x20\xe2\x94\x80\xe2\x94\x80\x0a\x66\x6e\x20\x6e\x6f\x6f\x70\x28\x29\x20\x76\x6f\x69\x64\x20\x7b\x7d\x0a\x70\x75\x62\x20\x66\x6e\x20\x43\x68\x72\x6f\x6d\x65\x48\x65\x61\x64\x65\x72\x28\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x31\x31\x2e\x68\x65\x61\x64\x65\x72\x22\x20\x77\x69\x6e\x64\x6f\x77\x52\x65\x67\x69\x6f\x6e\x3d\x7b\x2e\x64\x72\x61\x67\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x61\x64\x65\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x6f\x64\x79\x5f\x74\x65\x78\x74\x7d\x3e\x56\x2d\x31\x31\x20\x77\x69\x6e\x64\x6f\x77\x52\x65\x67\x69\x6f\x6e\x3d\x2e\x64\x72\x61\x67\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x31\x31\x2e\x62\x75\x74\x74\x6f\x6e\x22\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe6\x8c\x89\xe9\x92\xae\x22\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x6e\x6f\x6f\x70\x28\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x31\x31\x2e\x63\x6c\x69\x65\x6e\x74\x22\x20\x77\x69\x6e\x64\x6f\x77\x52\x65\x67\x69\x6f\x6e\x3d\x7b\x2e\x63\x6c\x69\x65\x6e\x74\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x68\x69\x70\x7d\x3e\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x75\x74\x65\x64\x7d\x3e\x2e\x63\x6c\x69\x65\x6e\x74\x3c\x2f\x74\x65\x78\x74\x3e\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x31\x31\x2e\x70\x6c\x61\x69\x6e\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x68\x69\x70\x7d\x3e\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x75\x74\x65\x64\x7d\x3e\x69\x6e\x68\x65\x72\x69\x74\x3c\x2f\x74\x65\x78\x74\x3e\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x73\x70\x61\x63\x65\x72\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x70\x69\x6b\x65\x2e\x76\x31\x31\x2e\x63\x6c\x6f\x73\x65\x22\x20\x77\x69\x6e\x64\x6f\x77\x52\x65\x67\x69\x6f\x6e\x3d\x7b\x2e\x63\x6c\x6f\x73\x65\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x68\x69\x70\x7d\x3e\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x75\x74\x65\x64\x7d\x3e\x2e\x63\x6c\x6f\x73\x65\x3c\x2f\x74\x65\x78\x74\x3e\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"S " = S, }) else void;

//# yix-map-data [[744,739],[8770,1891],[18483,3083],[31093,4231],[34597,4428],[38803,4726],[42476,4934],[47276,5259],[50556,5933],[57381,6522]]

//# yix-map views.yix
