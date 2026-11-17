// GENERATED FILE, do not edit: generated from ai_composer_controls.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! The composer tool row (Pencil Kaf7E A3 / ⑤): attachment, permission, run mode | usage, model,
//! then the host's send / stop. All native: ghost sm Buttons (label + leading icon + chevron),
//! icon-only ghost sm Buttons in native Tooltips on narrow rows, native Menus (menus package
//! `ContextMenu`) for the three selection-only choices, native Popovers for model + effort (O4)
//! and for usage (O6). Escape and outside clicks are the native overlay stack's alone (it closes
//! the topmost layer, also while focus is still on the control that opened it), and so is focus
//! (`trapFocus`: in on open, Tab kept inside, back on close). The view-model only names the
//! controls (`focusId`) and says which name a popover opens on (`initialFocus`) and returns to
//! (`returnFocus`), and hears of a close through `onOpenChange` for its own bookkeeping. State, captures, the shrink rule and the actions live in the view-model
//! (`ai_composer_controls_view.zig`); this file is the view only.
const ui = @import("ui");
const W = ui.widgets;
const S = @import("_ai_composer_controls.yss.zig");
const M = @import("ai_composer_controls_view.zig");

fn keepRow(m: *M.View, root: *ui.view.Ref(*ui.Node), trailing: *ui.view.Ref(*ui.Node), spacer: *ui.view.Ref(*ui.Node)) void {
    m.keepRow(root.get(), trailing.get(), spacer.get());
}
fn keepButtons(m: *M.View, attachment: *ui.view.Ref(*ui.Node), permission: *ui.view.Ref(*ui.Node), model: *ui.view.Ref(*ui.Node), effort: *ui.view.Ref(*ui.Node), usage: *ui.view.Ref(*ui.Node), execution: *ui.view.Ref(*ui.Node)) void {
    m.keepButtons(.{ attachment.get(), permission.get(), model.get(), effort.get(), usage.get(), execution.get() });
}
fn keepCompact(m: *M.View, slot: usize, tip: *ui.view.Ref(W.tooltip.TooltipResult), button: *ui.view.Ref(*ui.Node)) void {
    m.keepCompact(slot, tip.get().?.wrapper, button.get());
}
fn keepPopup(m: *M.View, index: usize, popup: *ui.view.Ref(W.popover.PopoverResult)) void {
    m.keepPopup(index, popup.get());
}
fn sliderKey(m: *M.View, e: ui.view.KeyPress) void {
    if (m.sliderKey(e.key)) e.stop();
}

/// Narrow rows: permission / run mode as an icon-only native ghost Button in a native Tooltip
/// ("名称 · 当前值").
fn Compact(args: anytype) ui.view.ComponentOf(__yix_Compact) {
    return ui.view.component(__yix_Compact, ui.reactive.props.coerce(CompactProps, args));
}
const CompactProps = struct {
    m: ui.Source(*M.View),
    slot: ui.Source(usize),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Compact;
    pub const __yix_preview_mount = __yix_Compact;
};
fn __yix_Compact(__yix_props: CompactProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    const slot = __yix_props.slot;
    try ui.view.previewCheckSetup(scope, true);
    const tip = try ui.view.createRef(scope, W.tooltip.TooltipResult);
    const button = try ui.view.createRef(scope, *ui.Node);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, .slot = slot, .tip = tip, .button = button, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "Compact", .receiver = "W.Tooltip", .tokens = "< W . Tooltip ref = { tip } text = { M . compactText ( m , slot ) } position = { . top } style = { S . no_shrink } visible = { M . compactShown ( m , slot ) } parts = { . { . content = M . compactTooltipId ( m , slot ) } } > < W . Button ref = { button } testId = { M . compactId ( m , slot ) } variant = { . ghost } size = { . sm } iconOnly = { true } iconAsset = { M . compactIcon ( m , slot ) } a11yLabel = { M . compactText ( m , slot ) } disabled = { M . disabled ( m , M . compactKind ( slot ) ) } onClick = { M . toggle ( m , M . compactKind ( slot ) ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "tip ", .kind = .reference, .literal = null }, .{ .name = "text", .tokens = "M . compactText ( m , slot ) ", .kind = .property, .literal = null }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, .{ .name = "style", .tokens = "S . no_shrink ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "M . compactShown ( m , slot ) ", .kind = .property, .literal = null }, .{ .name = "parts", .tokens = ". { . content = M . compactTooltipId ( m , slot ) } ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, .slot = __yix_view_ctx.slot, .tip = __yix_view_ctx.tip, .button = __yix_view_ctx.button, }, ui.view.templateAttrs(.{ .style = S.no_shrink, .visible = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "visible")) |__yix_A| __yix_A else @TypeOf(M.compactShown(__yix_view_ctx.m.peek(), __yix_view_ctx.slot.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .slot = __yix_view_ctx.slot, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.compactShown(__yix_ctx.m.get(), __yix_ctx.slot.get());
        } }.__yix_compute);
    }, .parts = .{ .content = __yix_d3: {
        const __yix_T = @TypeOf(M.compactTooltipId(__yix_view_ctx.m.peek(), __yix_view_ctx.slot.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .slot = __yix_view_ctx.slot, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.compactTooltipId(__yix_ctx.m.get(), __yix_ctx.slot.get());
        } }.__yix_compute);
    } }, }, ui.view.ref(__yix_view_ctx.tip, __yix_builder_2405: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_2405 ui.view.with(W.Tooltip(.{ .text = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(M.compactText(__yix_view_ctx.m.peek(), __yix_view_ctx.slot.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .slot = __yix_view_ctx.slot, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.compactText(__yix_ctx.m.get(), __yix_ctx.slot.get());
        } }.__yix_compute);
    }, .position = .top, }), .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "Compact", .receiver = "W.Button", .tokens = "< W . Button ref = { button } testId = { M . compactId ( m , slot ) } variant = { . ghost } size = { . sm } iconOnly = { true } iconAsset = { M . compactIcon ( m , slot ) } a11yLabel = { M . compactText ( m , slot ) } disabled = { M . disabled ( m , M . compactKind ( slot ) ) } onClick = { M . toggle ( m , M . compactKind ( slot ) ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "button ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "M . compactId ( m , slot ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "icon_only", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "icon_asset", .tokens = "M . compactIcon ( m , slot ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "M . compactText ( m , slot ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "M . disabled ( m , M . compactKind ( slot ) ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . toggle ( m , M . compactKind ( slot ) ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .slot = __yix_view_ctx.slot, .button = __yix_view_ctx.button, }, ui.view.templateAttrs(.{ .test_id = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(M.compactId(__yix_view_ctx.m.peek(), __yix_view_ctx.slot.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .slot = __yix_view_ctx.slot, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.compactId(__yix_ctx.m.get(), __yix_ctx.slot.get());
        } }.__yix_compute);
    }, }, ui.view.ref(__yix_view_ctx.button, __yix_builder_2591: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_2591 W.Button(.{ .variant = .ghost, .size = .sm, .icon_only = true, .icon_asset = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.compactIcon(__yix_view_ctx.m.peek(), __yix_view_ctx.slot.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .slot = __yix_view_ctx.slot, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.compactIcon(__yix_ctx.m.get(), __yix_ctx.slot.get());
        } }.__yix_compute);
    }, .a11y_label = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(M.compactText(__yix_view_ctx.m.peek(), __yix_view_ctx.slot.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .slot = __yix_view_ctx.slot, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.compactText(__yix_ctx.m.get(), __yix_ctx.slot.get());
        } }.__yix_compute);
    }, .disabled = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.disabled(__yix_view_ctx.m.peek(), M.compactKind(__yix_view_ctx.slot.peek())));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .slot = __yix_view_ctx.slot, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.disabled(__yix_ctx.m.get(), M.compactKind(__yix_ctx.slot.get()));
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .slot = __yix_view_ctx.slot, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.toggle(__yix_ctx.m.peek(), M.compactKind(__yix_ctx.slot.peek()));  } }.__yix_run) else __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.toggle(__yix_view_ctx.m.peek(), M.compactKind(__yix_view_ctx.slot.peek())));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .slot = __yix_view_ctx.slot, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.toggle(__yix_ctx.m.get(), M.compactKind(__yix_ctx.slot.get()));
        } }.__yix_compute);
    }, }); }))),
        }); }))));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Compact";
    return __yix_root;
    } }.__yix_render);
    try ui.view.runLifecycleAction(scope, "onMount", .{ .m = m, .slot = slot, .tip = tip, .button = button, .__yix_owner = scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { if (comptime @import("builtin").is_test) __yix_ctx.__yix_owner.recordTestHook(.onMount); __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); keepCompact(__yix_ctx.m.peek(), __yix_ctx.slot.peek(), __yix_ctx.tip, __yix_ctx.button);  } }.__yix_run);
    return __yix_view;

}

pub fn ToolRow(args: anytype) ui.view.ComponentOf(__yix_ToolRow) {
    return ui.view.component(__yix_ToolRow, ui.reactive.props.coerce(ToolRowProps, args));
}
pub const ToolRowProps = struct {
    m: ui.Source(*M.View),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ToolRow;
    pub const __yix_preview_mount = __yix_ToolRow;
};
fn __yix_ToolRow(__yix_props: ToolRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    try ui.view.previewCheckSetup(scope, true);
    const root = try ui.view.createRef(scope, *ui.Node);
    const trailing = try ui.view.createRef(scope, *ui.Node);
    const spacer = try ui.view.createRef(scope, *ui.Node);
    const attachment = try ui.view.createRef(scope, *ui.Node);
    const permission = try ui.view.createRef(scope, *ui.Node);
    const model = try ui.view.createRef(scope, *ui.Node);
    const effort = try ui.view.createRef(scope, *ui.Node);
    const usage = try ui.view.createRef(scope, *ui.Node);
    const execution = try ui.view.createRef(scope, *ui.Node);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, .root = root, .trailing = trailing, .spacer = spacer, .attachment = attachment, .permission = permission, .model = model, .effort = effort, .usage = usage, .execution = execution, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "row", .tokens = "< row ref = { root } testId = { m . space . id ( \"ai.composer.controls\" ) } style = { S . row } > < W . Tooltip text = \"添加附件\" position = { . top } style = { S . no_shrink } > < W . Button ref = { attachment } testId = { m . space . id ( \"ai.composer.attachment\" ) } variant = { . ghost } size = { . sm } iconOnly = { true } iconAsset = { M . glyph ( m , . attachment ) } a11yLabel = \"添加附件\" disabled = { M . disabled ( m , . attachment ) } onClick = { M . toggle ( m , . attachment ) } / > < / W . Tooltip > < W . Button ref = { permission } testId = { M . buttonId ( m , . permission ) } variant = { . ghost } size = { . sm } label = { M . text ( m , . permission ) } iconAsset = { M . glyph ( m , . permission ) } chevron = { true } a11yLabel = { M . chipA11y ( m , . permission , \"执行权限\" ) } disabled = { M . disabled ( m , . permission ) } visible = { M . chipShown ( m , . permission ) } onClick = { M . toggle ( m , . permission ) } / > < Compact m = { m } slot = { 0 } / > < W . Button ref = { execution } testId = { M . buttonId ( m , . execution ) } variant = { . ghost } size = { . sm } label = { M . text ( m , . execution ) } iconAsset = { M . glyph ( m , . execution ) } chevron = { true } a11yLabel = { M . chipA11y ( m , . execution , \"当前对话运行方式\" ) } disabled = { M . disabled ( m , . execution ) } visible = { M . chipShown ( m , . execution ) } onClick = { M . toggle ( m , . execution ) } / > < Compact m = { m } slot = { 1 } / > < spacer ref = { spacer } / > < W . Button ref = { usage } testId = { m . space . id ( \"ai.composer.usage\" ) } focusId = { M . focusName ( m , . usage_anchor ) } variant = { . ghost } size = { . sm } label = { M . text ( m , . usage ) } a11yLabel = \"上下文与来源\" disabled = { M . disabled ( m , . usage ) } onClick = { M . toggle ( m , . usage ) } progress = { M . ringValue ( m ) } iconSize = { M . ring_size } / > < W . Tooltip text = { M . modelHint ( m ) } width = { 320 } wrap = { . char } position = { . top } style = { S . no_shrink } parts = { . { . content = m . space . id ( \"ai.composer.model.tooltip\" ) } } > < W . Button ref = { model } testId = { M . buttonId ( m , . model ) } focusId = { M . focusName ( m , . model_anchor ) } variant = { . ghost } size = { . sm } label = { M . text ( m , . model ) } iconAsset = { M . glyph ( m , . model ) } chevron = { true } a11yLabel = { M . chipA11y ( m , . model , \"选择模型\" ) } disabled = { M . disabled ( m , . model ) } visible = { M . chipShown ( m , . model ) } onClick = { M . toggle ( m , . model ) } / > < / W . Tooltip > < W . Button ref = { effort } testId = { M . buttonId ( m , . effort ) } variant = { . ghost } size = { . sm } label = { M . text ( m , . effort ) } iconAsset = { M . glyph ( m , . effort ) } chevron = { false } a11yLabel = { M . chipA11y ( m , . effort , \"推理档位\" ) } disabled = { M . disabled ( m , . effort ) } visible = { M . chipShown ( m , . effort ) } onClick = { M . toggle ( m , . effort ) } / > < row ref = { trailing } testId = { m . space . id ( \"ai.composer.trailing\" ) } style = { S . trailing } > { if ( M . hasActions ( m ) ) < Actions m = { m } / > } < / row > < ModelPopover m = { m } / > < UsagePopover m = { m } / > < M . ContextMenu open = { M . menuOpen ( m , 0 ) } items = { M . menuRows ( m , 0 ) } anchor = { M . menuAnchor ( m , 0 ) } panelTestId = { m . space . id ( \"ai.attachment.menu\" ) } width = { M . width ( . attachment ) } maxHeight = { null } position = { . top_start } onOpenChange = { | o | M . menuOpenChanged ( m , 0 , o ) } onSelect = { | id | M . menuSelected ( m , 0 , id ) } / > < M . ContextMenu open = { M . menuOpen ( m , 1 ) } items = { M . menuRows ( m , 1 ) } anchor = { M . menuAnchor ( m , 1 ) } panelTestId = { m . space . id ( \"ai.permission.menu\" ) } width = { M . width ( . permission ) } maxHeight = { null } position = { . top_start } onOpenChange = { | o | M . menuOpenChanged ( m , 1 , o ) } onSelect = { | id | M . menuSelected ( m , 1 , id ) } / > < M . ContextMenu open = { M . menuOpen ( m , 2 ) } items = { M . menuRows ( m , 2 ) } anchor = { M . menuAnchor ( m , 2 ) } panelTestId = { m . space . id ( \"ai.execution.menu\" ) } width = { M . width ( . execution ) } maxHeight = { null } position = { . top_start } onOpenChange = { | o | M . menuOpenChanged ( m , 2 , o ) } onSelect = { | id | M . menuSelected ( m , 2 , id ) } / > < / row > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "root ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.composer.controls\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . row ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .root = __yix_view_ctx.root, .m = __yix_view_ctx.m, .attachment = __yix_view_ctx.attachment, .permission = __yix_view_ctx.permission, .execution = __yix_view_ctx.execution, .spacer = __yix_view_ctx.spacer, .usage = __yix_view_ctx.usage, .model = __yix_view_ctx.model, .effort = __yix_view_ctx.effort, .trailing = __yix_view_ctx.trailing, }, ui.view.ref(__yix_view_ctx.root, ui.view.row(.{ .test_id = __yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.composer.controls"));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.composer.controls");
        } }.__yix_compute);
    }, .style = S.row, }, .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = \"添加附件\" position = { . top } style = { S . no_shrink } > < W . Button ref = { attachment } testId = { m . space . id ( \"ai.composer.attachment\" ) } variant = { . ghost } size = { . sm } iconOnly = { true } iconAsset = { M . glyph ( m , . attachment ) } a11yLabel = \"添加附件\" disabled = { M . disabled ( m , . attachment ) } onClick = { M . toggle ( m , . attachment ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "\"添加附件\" ", .kind = .property, .literal = .{ .text = "添加附件" } }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, .{ .name = "style", .tokens = "S . no_shrink ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .attachment = __yix_view_ctx.attachment, }, ui.view.templateAttrs(.{ .style = S.no_shrink, }, __yix_builder_3401: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_3401 ui.view.with(W.Tooltip(.{ .text = "添加附件", .position = .top, }), .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "W.Button", .tokens = "< W . Button ref = { attachment } testId = { m . space . id ( \"ai.composer.attachment\" ) } variant = { . ghost } size = { . sm } iconOnly = { true } iconAsset = { M . glyph ( m , . attachment ) } a11yLabel = \"添加附件\" disabled = { M . disabled ( m , . attachment ) } onClick = { M . toggle ( m , . attachment ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "attachment ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.composer.attachment\" ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "icon_only", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "icon_asset", .tokens = "M . glyph ( m , . attachment ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "\"添加附件\" ", .kind = .property, .literal = .{ .text = "添加附件" } }, .{ .name = "disabled", .tokens = "M . disabled ( m , . attachment ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . toggle ( m , . attachment ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .attachment = __yix_view_ctx.attachment, }, ui.view.templateAttrs(.{ .test_id = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.composer.attachment"));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.composer.attachment");
        } }.__yix_compute);
    }, }, ui.view.ref(__yix_view_ctx.attachment, __yix_builder_3485: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_3485 W.Button(.{ .variant = .ghost, .size = .sm, .icon_only = true, .icon_asset = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyph(__yix_view_ctx.m.peek(), .attachment));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.glyph(__yix_ctx.m.get(), .attachment);
        } }.__yix_compute);
    }, .a11y_label = "添加附件", .disabled = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.disabled(__yix_view_ctx.m.peek(), .attachment));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.disabled(__yix_ctx.m.get(), .attachment);
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.toggle(__yix_ctx.m.peek(), .attachment);  } }.__yix_run) else __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.toggle(__yix_view_ctx.m.peek(), .attachment));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.toggle(__yix_ctx.m.get(), .attachment);
        } }.__yix_compute);
    }, }); }))),
            }); })),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "W.Button", .tokens = "< W . Button ref = { permission } testId = { M . buttonId ( m , . permission ) } variant = { . ghost } size = { . sm } label = { M . text ( m , . permission ) } iconAsset = { M . glyph ( m , . permission ) } chevron = { true } a11yLabel = { M . chipA11y ( m , . permission , \"执行权限\" ) } disabled = { M . disabled ( m , . permission ) } visible = { M . chipShown ( m , . permission ) } onClick = { M . toggle ( m , . permission ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "permission ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "M . buttonId ( m , . permission ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "label", .tokens = "M . text ( m , . permission ) ", .kind = .property, .literal = null }, .{ .name = "icon_asset", .tokens = "M . glyph ( m , . permission ) ", .kind = .property, .literal = null }, .{ .name = "chevron", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "a11y_label", .tokens = "M . chipA11y ( m , . permission , \"执行权限\" ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "M . disabled ( m , . permission ) ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "M . chipShown ( m , . permission ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . toggle ( m , . permission ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .permission = __yix_view_ctx.permission, }, ui.view.templateAttrs(.{ .test_id = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(M.buttonId(__yix_view_ctx.m.peek(), .permission));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.buttonId(__yix_ctx.m.get(), .permission);
        } }.__yix_compute);
    }, .visible = __yix_d11: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(M.chipShown(__yix_view_ctx.m.peek(), .permission));
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.chipShown(__yix_ctx.m.get(), .permission);
        } }.__yix_compute);
    }, }, ui.view.ref(__yix_view_ctx.permission, __yix_builder_3776: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_3776 W.Button(.{ .variant = .ghost, .size = .sm, .label = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Button, "label")) |__yix_A| __yix_A else @TypeOf(M.text(__yix_view_ctx.m.peek(), .permission));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.text(__yix_ctx.m.get(), .permission);
        } }.__yix_compute);
    }, .icon_asset = __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyph(__yix_view_ctx.m.peek(), .permission));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.glyph(__yix_ctx.m.get(), .permission);
        } }.__yix_compute);
    }, .chevron = true, .a11y_label = __yix_d9: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(M.chipA11y(__yix_view_ctx.m.peek(), .permission, "执行权限"));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.chipA11y(__yix_ctx.m.get(), .permission, "执行权限");
        } }.__yix_compute);
    }, .disabled = __yix_d10: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.disabled(__yix_view_ctx.m.peek(), .permission));
        break :__yix_d10 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.disabled(__yix_ctx.m.get(), .permission);
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.toggle(__yix_ctx.m.peek(), .permission);  } }.__yix_run) else __yix_d12: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.toggle(__yix_view_ctx.m.peek(), .permission));
        break :__yix_d12 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.toggle(__yix_ctx.m.get(), .permission);
        } }.__yix_compute);
    }, }); }))),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "Compact", .tokens = "< Compact m = { m } slot = { 0 } / > ", .literal_text = null, .attributes = &.{ .{ .name = "m", .tokens = "m ", .kind = .property, .literal = null }, .{ .name = "slot", .tokens = "0 ", .kind = .property, .literal = .{ .number = 0 } }, } }, .{ .m = __yix_view_ctx.m, }, __yix_builder_4130: { try ui.view.previewCheckBuilder(__yix_view_scope, Compact); break :__yix_builder_4130 Compact(.{ .m = __yix_view_ctx.m, .slot = 0, }); }),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "W.Button", .tokens = "< W . Button ref = { execution } testId = { M . buttonId ( m , . execution ) } variant = { . ghost } size = { . sm } label = { M . text ( m , . execution ) } iconAsset = { M . glyph ( m , . execution ) } chevron = { true } a11yLabel = { M . chipA11y ( m , . execution , \"当前对话运行方式\" ) } disabled = { M . disabled ( m , . execution ) } visible = { M . chipShown ( m , . execution ) } onClick = { M . toggle ( m , . execution ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "execution ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "M . buttonId ( m , . execution ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "label", .tokens = "M . text ( m , . execution ) ", .kind = .property, .literal = null }, .{ .name = "icon_asset", .tokens = "M . glyph ( m , . execution ) ", .kind = .property, .literal = null }, .{ .name = "chevron", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "a11y_label", .tokens = "M . chipA11y ( m , . execution , \"当前对话运行方式\" ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "M . disabled ( m , . execution ) ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "M . chipShown ( m , . execution ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . toggle ( m , . execution ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .execution = __yix_view_ctx.execution, }, ui.view.templateAttrs(.{ .test_id = __yix_d13: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(M.buttonId(__yix_view_ctx.m.peek(), .execution));
        break :__yix_d13 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.buttonId(__yix_ctx.m.get(), .execution);
        } }.__yix_compute);
    }, .visible = __yix_d18: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(M.chipShown(__yix_view_ctx.m.peek(), .execution));
        break :__yix_d18 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.chipShown(__yix_ctx.m.get(), .execution);
        } }.__yix_compute);
    }, }, ui.view.ref(__yix_view_ctx.execution, __yix_builder_4169: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_4169 W.Button(.{ .variant = .ghost, .size = .sm, .label = __yix_d14: {
        const __yix_T = if (ui.view.attrType(W.Button, "label")) |__yix_A| __yix_A else @TypeOf(M.text(__yix_view_ctx.m.peek(), .execution));
        break :__yix_d14 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.text(__yix_ctx.m.get(), .execution);
        } }.__yix_compute);
    }, .icon_asset = __yix_d15: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyph(__yix_view_ctx.m.peek(), .execution));
        break :__yix_d15 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.glyph(__yix_ctx.m.get(), .execution);
        } }.__yix_compute);
    }, .chevron = true, .a11y_label = __yix_d16: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(M.chipA11y(__yix_view_ctx.m.peek(), .execution, "当前对话运行方式"));
        break :__yix_d16 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.chipA11y(__yix_ctx.m.get(), .execution, "当前对话运行方式");
        } }.__yix_compute);
    }, .disabled = __yix_d17: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.disabled(__yix_view_ctx.m.peek(), .execution));
        break :__yix_d17 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.disabled(__yix_ctx.m.get(), .execution);
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.toggle(__yix_ctx.m.peek(), .execution);  } }.__yix_run) else __yix_d19: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.toggle(__yix_view_ctx.m.peek(), .execution));
        break :__yix_d19 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.toggle(__yix_ctx.m.get(), .execution);
        } }.__yix_compute);
    }, }); }))),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "Compact", .tokens = "< Compact m = { m } slot = { 1 } / > ", .literal_text = null, .attributes = &.{ .{ .name = "m", .tokens = "m ", .kind = .property, .literal = null }, .{ .name = "slot", .tokens = "1 ", .kind = .property, .literal = .{ .number = 1 } }, } }, .{ .m = __yix_view_ctx.m, }, __yix_builder_4527: { try ui.view.previewCheckBuilder(__yix_view_scope, Compact); break :__yix_builder_4527 Compact(.{ .m = __yix_view_ctx.m, .slot = 1, }); }),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "spacer", .tokens = "< spacer ref = { spacer } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "spacer ", .kind = .reference, .literal = null }, } }, .{ .spacer = __yix_view_ctx.spacer, }, ui.view.ref(__yix_view_ctx.spacer, ui.view.spacer())),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "W.Button", .tokens = "< W . Button ref = { usage } testId = { m . space . id ( \"ai.composer.usage\" ) } focusId = { M . focusName ( m , . usage_anchor ) } variant = { . ghost } size = { . sm } label = { M . text ( m , . usage ) } a11yLabel = \"上下文与来源\" disabled = { M . disabled ( m , . usage ) } onClick = { M . toggle ( m , . usage ) } progress = { M . ringValue ( m ) } iconSize = { M . ring_size } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "usage ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.composer.usage\" ) ", .kind = .property, .literal = null }, .{ .name = "focus_id", .tokens = "M . focusName ( m , . usage_anchor ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "label", .tokens = "M . text ( m , . usage ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "\"上下文与来源\" ", .kind = .property, .literal = .{ .text = "上下文与来源" } }, .{ .name = "disabled", .tokens = "M . disabled ( m , . usage ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . toggle ( m , . usage ) ", .kind = .event, .literal = null }, .{ .name = "progress", .tokens = "M . ringValue ( m ) ", .kind = .property, .literal = null }, .{ .name = "icon_size", .tokens = "M . ring_size ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .usage = __yix_view_ctx.usage, }, ui.view.templateAttrs(.{ .test_id = __yix_d20: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.composer.usage"));
        break :__yix_d20 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.composer.usage");
        } }.__yix_compute);
    }, .focus_id = __yix_d21: {
        const __yix_T = if (ui.view.attrType(W.Button, "focus_id")) |__yix_A| __yix_A else @TypeOf(M.focusName(__yix_view_ctx.m.peek(), .usage_anchor));
        break :__yix_d21 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.focusName(__yix_ctx.m.get(), .usage_anchor);
        } }.__yix_compute);
    }, }, ui.view.ref(__yix_view_ctx.usage, __yix_builder_4602: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_4602 W.Button(.{ .variant = .ghost, .size = .sm, .label = __yix_d22: {
        const __yix_T = if (ui.view.attrType(W.Button, "label")) |__yix_A| __yix_A else @TypeOf(M.text(__yix_view_ctx.m.peek(), .usage));
        break :__yix_d22 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.text(__yix_ctx.m.get(), .usage);
        } }.__yix_compute);
    }, .a11y_label = "上下文与来源", .disabled = __yix_d23: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.disabled(__yix_view_ctx.m.peek(), .usage));
        break :__yix_d23 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.disabled(__yix_ctx.m.get(), .usage);
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.toggle(__yix_ctx.m.peek(), .usage);  } }.__yix_run) else __yix_d24: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.toggle(__yix_view_ctx.m.peek(), .usage));
        break :__yix_d24 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.toggle(__yix_ctx.m.get(), .usage);
        } }.__yix_compute);
    }, .progress = __yix_d25: {
        const __yix_T = if (ui.view.attrType(W.Button, "progress")) |__yix_A| __yix_A else @TypeOf(M.ringValue(__yix_view_ctx.m.peek()));
        break :__yix_d25 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.ringValue(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .icon_size = M.ring_size, }); }))),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { M . modelHint ( m ) } width = { 320 } wrap = { . char } position = { . top } style = { S . no_shrink } parts = { . { . content = m . space . id ( \"ai.composer.model.tooltip\" ) } } > < W . Button ref = { model } testId = { M . buttonId ( m , . model ) } focusId = { M . focusName ( m , . model_anchor ) } variant = { . ghost } size = { . sm } label = { M . text ( m , . model ) } iconAsset = { M . glyph ( m , . model ) } chevron = { true } a11yLabel = { M . chipA11y ( m , . model , \"选择模型\" ) } disabled = { M . disabled ( m , . model ) } visible = { M . chipShown ( m , . model ) } onClick = { M . toggle ( m , . model ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "M . modelHint ( m ) ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "320 ", .kind = .property, .literal = .{ .number = 320 } }, .{ .name = "wrap", .tokens = ". char ", .kind = .property, .literal = .{ .enum_name = "char" } }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, .{ .name = "style", .tokens = "S . no_shrink ", .kind = .style, .literal = null }, .{ .name = "parts", .tokens = ". { . content = m . space . id ( \"ai.composer.model.tooltip\" ) } ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .model = __yix_view_ctx.model, }, ui.view.templateAttrs(.{ .style = S.no_shrink, .parts = .{ .content = __yix_d27: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.composer.model.tooltip"));
        break :__yix_d27 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.composer.model.tooltip");
        } }.__yix_compute);
    } }, }, __yix_builder_4917: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_4917 ui.view.with(W.Tooltip(.{ .text = __yix_d26: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(M.modelHint(__yix_view_ctx.m.peek()));
        break :__yix_d26 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.modelHint(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .width = 320, .wrap = .char, .position = .top, }), .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "W.Button", .tokens = "< W . Button ref = { model } testId = { M . buttonId ( m , . model ) } focusId = { M . focusName ( m , . model_anchor ) } variant = { . ghost } size = { . sm } label = { M . text ( m , . model ) } iconAsset = { M . glyph ( m , . model ) } chevron = { true } a11yLabel = { M . chipA11y ( m , . model , \"选择模型\" ) } disabled = { M . disabled ( m , . model ) } visible = { M . chipShown ( m , . model ) } onClick = { M . toggle ( m , . model ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "model ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "M . buttonId ( m , . model ) ", .kind = .property, .literal = null }, .{ .name = "focus_id", .tokens = "M . focusName ( m , . model_anchor ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "label", .tokens = "M . text ( m , . model ) ", .kind = .property, .literal = null }, .{ .name = "icon_asset", .tokens = "M . glyph ( m , . model ) ", .kind = .property, .literal = null }, .{ .name = "chevron", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "a11y_label", .tokens = "M . chipA11y ( m , . model , \"选择模型\" ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "M . disabled ( m , . model ) ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "M . chipShown ( m , . model ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . toggle ( m , . model ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .model = __yix_view_ctx.model, }, ui.view.templateAttrs(.{ .test_id = __yix_d28: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(M.buttonId(__yix_view_ctx.m.peek(), .model));
        break :__yix_d28 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.buttonId(__yix_ctx.m.get(), .model);
        } }.__yix_compute);
    }, .focus_id = __yix_d29: {
        const __yix_T = if (ui.view.attrType(W.Button, "focus_id")) |__yix_A| __yix_A else @TypeOf(M.focusName(__yix_view_ctx.m.peek(), .model_anchor));
        break :__yix_d29 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.focusName(__yix_ctx.m.get(), .model_anchor);
        } }.__yix_compute);
    }, .visible = __yix_d34: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(M.chipShown(__yix_view_ctx.m.peek(), .model));
        break :__yix_d34 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.chipShown(__yix_ctx.m.get(), .model);
        } }.__yix_compute);
    }, }, ui.view.ref(__yix_view_ctx.model, __yix_builder_5092: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_5092 W.Button(.{ .variant = .ghost, .size = .sm, .label = __yix_d30: {
        const __yix_T = if (ui.view.attrType(W.Button, "label")) |__yix_A| __yix_A else @TypeOf(M.text(__yix_view_ctx.m.peek(), .model));
        break :__yix_d30 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.text(__yix_ctx.m.get(), .model);
        } }.__yix_compute);
    }, .icon_asset = __yix_d31: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyph(__yix_view_ctx.m.peek(), .model));
        break :__yix_d31 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.glyph(__yix_ctx.m.get(), .model);
        } }.__yix_compute);
    }, .chevron = true, .a11y_label = __yix_d32: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(M.chipA11y(__yix_view_ctx.m.peek(), .model, "选择模型"));
        break :__yix_d32 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.chipA11y(__yix_ctx.m.get(), .model, "选择模型");
        } }.__yix_compute);
    }, .disabled = __yix_d33: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.disabled(__yix_view_ctx.m.peek(), .model));
        break :__yix_d33 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.disabled(__yix_ctx.m.get(), .model);
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.toggle(__yix_ctx.m.peek(), .model);  } }.__yix_run) else __yix_d35: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.toggle(__yix_view_ctx.m.peek(), .model));
        break :__yix_d35 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.toggle(__yix_ctx.m.get(), .model);
        } }.__yix_compute);
    }, }); }))),
            }); })),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "W.Button", .tokens = "< W . Button ref = { effort } testId = { M . buttonId ( m , . effort ) } variant = { . ghost } size = { . sm } label = { M . text ( m , . effort ) } iconAsset = { M . glyph ( m , . effort ) } chevron = { false } a11yLabel = { M . chipA11y ( m , . effort , \"推理档位\" ) } disabled = { M . disabled ( m , . effort ) } visible = { M . chipShown ( m , . effort ) } onClick = { M . toggle ( m , . effort ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "effort ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "M . buttonId ( m , . effort ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "label", .tokens = "M . text ( m , . effort ) ", .kind = .property, .literal = null }, .{ .name = "icon_asset", .tokens = "M . glyph ( m , . effort ) ", .kind = .property, .literal = null }, .{ .name = "chevron", .tokens = "false ", .kind = .property, .literal = .{ .boolean = false } }, .{ .name = "a11y_label", .tokens = "M . chipA11y ( m , . effort , \"推理档位\" ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "M . disabled ( m , . effort ) ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "M . chipShown ( m , . effort ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . toggle ( m , . effort ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .effort = __yix_view_ctx.effort, }, ui.view.templateAttrs(.{ .test_id = __yix_d36: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(M.buttonId(__yix_view_ctx.m.peek(), .effort));
        break :__yix_d36 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.buttonId(__yix_ctx.m.get(), .effort);
        } }.__yix_compute);
    }, .visible = __yix_d41: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(M.chipShown(__yix_view_ctx.m.peek(), .effort));
        break :__yix_d41 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.chipShown(__yix_ctx.m.get(), .effort);
        } }.__yix_compute);
    }, }, ui.view.ref(__yix_view_ctx.effort, __yix_builder_5471: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_5471 W.Button(.{ .variant = .ghost, .size = .sm, .label = __yix_d37: {
        const __yix_T = if (ui.view.attrType(W.Button, "label")) |__yix_A| __yix_A else @TypeOf(M.text(__yix_view_ctx.m.peek(), .effort));
        break :__yix_d37 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.text(__yix_ctx.m.get(), .effort);
        } }.__yix_compute);
    }, .icon_asset = __yix_d38: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyph(__yix_view_ctx.m.peek(), .effort));
        break :__yix_d38 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.glyph(__yix_ctx.m.get(), .effort);
        } }.__yix_compute);
    }, .chevron = false, .a11y_label = __yix_d39: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(M.chipA11y(__yix_view_ctx.m.peek(), .effort, "推理档位"));
        break :__yix_d39 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.chipA11y(__yix_ctx.m.get(), .effort, "推理档位");
        } }.__yix_compute);
    }, .disabled = __yix_d40: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.disabled(__yix_view_ctx.m.peek(), .effort));
        break :__yix_d40 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.disabled(__yix_ctx.m.get(), .effort);
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.toggle(__yix_ctx.m.peek(), .effort);  } }.__yix_run) else __yix_d42: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.toggle(__yix_view_ctx.m.peek(), .effort));
        break :__yix_d42 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.toggle(__yix_ctx.m.get(), .effort);
        } }.__yix_compute);
    }, }); }))),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "row", .tokens = "< row ref = { trailing } testId = { m . space . id ( \"ai.composer.trailing\" ) } style = { S . trailing } > { if ( M . hasActions ( m ) ) < Actions m = { m } / > } < / row > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "trailing ", .kind = .reference, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.composer.trailing\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . trailing ", .kind = .style, .literal = null }, } }, .{ .trailing = __yix_view_ctx.trailing, .m = __yix_view_ctx.m, }, ui.view.ref(__yix_view_ctx.trailing, ui.view.row(.{ .test_id = __yix_d43: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.composer.trailing"));
        break :__yix_d43 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.composer.trailing");
        } }.__yix_compute);
    }, .style = S.trailing, }, .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "control", .tokens = "if ( M . hasActions ( m ) ) < Actions m = { m } / > " }, .{ .m = __yix_view_ctx.m, }, ui.view.lazyIf(__yix_d1: {
        const __yix_T = @TypeOf(M.hasActions(__yix_view_ctx.m.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.hasActions(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow/keyword_if:1/branch:0", .receiver = "Actions", .tokens = "< Actions m = { m } / > ", .literal_text = null, .attributes = &.{ .{ .name = "m", .tokens = "m ", .kind = .property, .literal = null }, } }, .{ .m = __yix_b1_0.m, }, __yix_builder_21: { try ui.view.previewCheckBuilder(__yix_bs1_0, Actions); break :__yix_builder_21 Actions(.{ .m = __yix_b1_0.m, }); }) }); } }.__yix_b, null)),
            }))),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "ModelPopover", .tokens = "< ModelPopover m = { m } / > ", .literal_text = null, .attributes = &.{ .{ .name = "m", .tokens = "m ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, __yix_builder_5966: { try ui.view.previewCheckBuilder(__yix_view_scope, ModelPopover); break :__yix_builder_5966 ModelPopover(.{ .m = __yix_view_ctx.m, }); }),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "UsagePopover", .tokens = "< UsagePopover m = { m } / > ", .literal_text = null, .attributes = &.{ .{ .name = "m", .tokens = "m ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, __yix_builder_6001: { try ui.view.previewCheckBuilder(__yix_view_scope, UsagePopover); break :__yix_builder_6001 UsagePopover(.{ .m = __yix_view_ctx.m, }); }),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "M.ContextMenu", .tokens = "< M . ContextMenu open = { M . menuOpen ( m , 0 ) } items = { M . menuRows ( m , 0 ) } anchor = { M . menuAnchor ( m , 0 ) } panelTestId = { m . space . id ( \"ai.attachment.menu\" ) } width = { M . width ( . attachment ) } maxHeight = { null } position = { . top_start } onOpenChange = { | o | M . menuOpenChanged ( m , 0 , o ) } onSelect = { | id | M . menuSelected ( m , 0 , id ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "open", .tokens = "M . menuOpen ( m , 0 ) ", .kind = .property, .literal = null }, .{ .name = "items", .tokens = "M . menuRows ( m , 0 ) ", .kind = .property, .literal = null }, .{ .name = "anchor", .tokens = "M . menuAnchor ( m , 0 ) ", .kind = .property, .literal = null }, .{ .name = "panel_test_id", .tokens = "m . space . id ( \"ai.attachment.menu\" ) ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "M . width ( . attachment ) ", .kind = .property, .literal = null }, .{ .name = "max_height", .tokens = "null ", .kind = .property, .literal = null }, .{ .name = "position", .tokens = ". top_start ", .kind = .property, .literal = .{ .enum_name = "top_start" } }, .{ .name = "on_open_change", .tokens = "| o | M . menuOpenChanged ( m , 0 , o ) ", .kind = .event, .literal = null }, .{ .name = "on_select", .tokens = "| id | M . menuSelected ( m , 0 , id ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, __yix_builder_6036: { try ui.view.previewCheckBuilder(__yix_view_scope, M.ContextMenu); break :__yix_builder_6036 M.ContextMenu(.{ .open = __yix_d44: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "open")) |__yix_A| __yix_A else @TypeOf(M.menuOpen(__yix_view_ctx.m.peek(), 0));
        break :__yix_d44 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.menuOpen(__yix_ctx.m.get(), 0);
        } }.__yix_compute);
    }, .items = __yix_d45: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "items")) |__yix_A| __yix_A else @TypeOf(M.menuRows(__yix_view_ctx.m.peek(), 0));
        break :__yix_d45 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.menuRows(__yix_ctx.m.get(), 0);
        } }.__yix_compute);
    }, .anchor = __yix_d46: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "anchor")) |__yix_A| __yix_A else @TypeOf(M.menuAnchor(__yix_view_ctx.m.peek(), 0));
        break :__yix_d46 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.menuAnchor(__yix_ctx.m.get(), 0);
        } }.__yix_compute);
    }, .panel_test_id = __yix_d47: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "panel_test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.attachment.menu"));
        break :__yix_d47 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.attachment.menu");
        } }.__yix_compute);
    }, .width = __yix_call49: {
        const __yix_Raw = @TypeOf(M.width(.attachment));
        break :__yix_call49 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.width(.attachment) else __yix_d48: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "width")) |__yix_A| __yix_A else @TypeOf(M.width(.attachment));
        break :__yix_d48 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.width(.attachment);
        } }.__yix_compute);
    };
    }, .max_height = null, .position = .top_start, .on_open_change = ui.view.eventProp(M.ContextMenu, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.menuOpenChanged(__yix_ctx.m.peek(), 0, o);  } }.__yix_run)), .on_select = ui.view.eventProp(M.ContextMenu, "on_select", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, id: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.menuSelected(__yix_ctx.m.peek(), 0, id);  } }.__yix_run)), }); }),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "M.ContextMenu", .tokens = "< M . ContextMenu open = { M . menuOpen ( m , 1 ) } items = { M . menuRows ( m , 1 ) } anchor = { M . menuAnchor ( m , 1 ) } panelTestId = { m . space . id ( \"ai.permission.menu\" ) } width = { M . width ( . permission ) } maxHeight = { null } position = { . top_start } onOpenChange = { | o | M . menuOpenChanged ( m , 1 , o ) } onSelect = { | id | M . menuSelected ( m , 1 , id ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "open", .tokens = "M . menuOpen ( m , 1 ) ", .kind = .property, .literal = null }, .{ .name = "items", .tokens = "M . menuRows ( m , 1 ) ", .kind = .property, .literal = null }, .{ .name = "anchor", .tokens = "M . menuAnchor ( m , 1 ) ", .kind = .property, .literal = null }, .{ .name = "panel_test_id", .tokens = "m . space . id ( \"ai.permission.menu\" ) ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "M . width ( . permission ) ", .kind = .property, .literal = null }, .{ .name = "max_height", .tokens = "null ", .kind = .property, .literal = null }, .{ .name = "position", .tokens = ". top_start ", .kind = .property, .literal = .{ .enum_name = "top_start" } }, .{ .name = "on_open_change", .tokens = "| o | M . menuOpenChanged ( m , 1 , o ) ", .kind = .event, .literal = null }, .{ .name = "on_select", .tokens = "| id | M . menuSelected ( m , 1 , id ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, __yix_builder_6345: { try ui.view.previewCheckBuilder(__yix_view_scope, M.ContextMenu); break :__yix_builder_6345 M.ContextMenu(.{ .open = __yix_d50: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "open")) |__yix_A| __yix_A else @TypeOf(M.menuOpen(__yix_view_ctx.m.peek(), 1));
        break :__yix_d50 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.menuOpen(__yix_ctx.m.get(), 1);
        } }.__yix_compute);
    }, .items = __yix_d51: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "items")) |__yix_A| __yix_A else @TypeOf(M.menuRows(__yix_view_ctx.m.peek(), 1));
        break :__yix_d51 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.menuRows(__yix_ctx.m.get(), 1);
        } }.__yix_compute);
    }, .anchor = __yix_d52: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "anchor")) |__yix_A| __yix_A else @TypeOf(M.menuAnchor(__yix_view_ctx.m.peek(), 1));
        break :__yix_d52 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.menuAnchor(__yix_ctx.m.get(), 1);
        } }.__yix_compute);
    }, .panel_test_id = __yix_d53: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "panel_test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.permission.menu"));
        break :__yix_d53 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.permission.menu");
        } }.__yix_compute);
    }, .width = __yix_call55: {
        const __yix_Raw = @TypeOf(M.width(.permission));
        break :__yix_call55 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.width(.permission) else __yix_d54: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "width")) |__yix_A| __yix_A else @TypeOf(M.width(.permission));
        break :__yix_d54 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.width(.permission);
        } }.__yix_compute);
    };
    }, .max_height = null, .position = .top_start, .on_open_change = ui.view.eventProp(M.ContextMenu, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.menuOpenChanged(__yix_ctx.m.peek(), 1, o);  } }.__yix_run)), .on_select = ui.view.eventProp(M.ContextMenu, "on_select", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, id: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.menuSelected(__yix_ctx.m.peek(), 1, id);  } }.__yix_run)), }); }),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ToolRow", .receiver = "M.ContextMenu", .tokens = "< M . ContextMenu open = { M . menuOpen ( m , 2 ) } items = { M . menuRows ( m , 2 ) } anchor = { M . menuAnchor ( m , 2 ) } panelTestId = { m . space . id ( \"ai.execution.menu\" ) } width = { M . width ( . execution ) } maxHeight = { null } position = { . top_start } onOpenChange = { | o | M . menuOpenChanged ( m , 2 , o ) } onSelect = { | id | M . menuSelected ( m , 2 , id ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "open", .tokens = "M . menuOpen ( m , 2 ) ", .kind = .property, .literal = null }, .{ .name = "items", .tokens = "M . menuRows ( m , 2 ) ", .kind = .property, .literal = null }, .{ .name = "anchor", .tokens = "M . menuAnchor ( m , 2 ) ", .kind = .property, .literal = null }, .{ .name = "panel_test_id", .tokens = "m . space . id ( \"ai.execution.menu\" ) ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "M . width ( . execution ) ", .kind = .property, .literal = null }, .{ .name = "max_height", .tokens = "null ", .kind = .property, .literal = null }, .{ .name = "position", .tokens = ". top_start ", .kind = .property, .literal = .{ .enum_name = "top_start" } }, .{ .name = "on_open_change", .tokens = "| o | M . menuOpenChanged ( m , 2 , o ) ", .kind = .event, .literal = null }, .{ .name = "on_select", .tokens = "| id | M . menuSelected ( m , 2 , id ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, __yix_builder_6654: { try ui.view.previewCheckBuilder(__yix_view_scope, M.ContextMenu); break :__yix_builder_6654 M.ContextMenu(.{ .open = __yix_d56: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "open")) |__yix_A| __yix_A else @TypeOf(M.menuOpen(__yix_view_ctx.m.peek(), 2));
        break :__yix_d56 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.menuOpen(__yix_ctx.m.get(), 2);
        } }.__yix_compute);
    }, .items = __yix_d57: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "items")) |__yix_A| __yix_A else @TypeOf(M.menuRows(__yix_view_ctx.m.peek(), 2));
        break :__yix_d57 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.menuRows(__yix_ctx.m.get(), 2);
        } }.__yix_compute);
    }, .anchor = __yix_d58: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "anchor")) |__yix_A| __yix_A else @TypeOf(M.menuAnchor(__yix_view_ctx.m.peek(), 2));
        break :__yix_d58 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.menuAnchor(__yix_ctx.m.get(), 2);
        } }.__yix_compute);
    }, .panel_test_id = __yix_d59: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "panel_test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.execution.menu"));
        break :__yix_d59 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.execution.menu");
        } }.__yix_compute);
    }, .width = __yix_call61: {
        const __yix_Raw = @TypeOf(M.width(.execution));
        break :__yix_call61 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.width(.execution) else __yix_d60: {
        const __yix_T = if (ui.view.attrType(M.ContextMenu, "width")) |__yix_A| __yix_A else @TypeOf(M.width(.execution));
        break :__yix_d60 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.width(.execution);
        } }.__yix_compute);
    };
    }, .max_height = null, .position = .top_start, .on_open_change = ui.view.eventProp(M.ContextMenu, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.menuOpenChanged(__yix_ctx.m.peek(), 2, o);  } }.__yix_run)), .on_select = ui.view.eventProp(M.ContextMenu, "on_select", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, id: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.menuSelected(__yix_ctx.m.peek(), 2, id);  } }.__yix_run)), }); }),
        }))));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ToolRow";
    return __yix_root;
    } }.__yix_render);
    try ui.view.runLifecycleAction(scope, "onMount", .{ .m = m, .root = root, .trailing = trailing, .spacer = spacer, .__yix_owner = scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { if (comptime @import("builtin").is_test) __yix_ctx.__yix_owner.recordTestHook(.onMount); __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); keepRow(__yix_ctx.m.peek(), __yix_ctx.root, __yix_ctx.trailing, __yix_ctx.spacer);  } }.__yix_run);
    try ui.view.runLifecycleAction(scope, "onMount", .{ .m = m, .attachment = attachment, .permission = permission, .model = model, .effort = effort, .usage = usage, .execution = execution, .__yix_owner = scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { if (comptime @import("builtin").is_test) __yix_ctx.__yix_owner.recordTestHook(.onMount); __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); keepButtons(__yix_ctx.m.peek(), __yix_ctx.attachment, __yix_ctx.permission, __yix_ctx.model, __yix_ctx.effort, __yix_ctx.usage, __yix_ctx.execution);  } }.__yix_run);
    return __yix_view;

}

/// Send / Stop (Pencil Kaf7E A8): native primary sm icon Buttons with native Tooltips. Stop while
/// a turn runs; Send for a draft (it steers or queues, the hint says which).
fn Actions(args: anytype) ui.view.ComponentOf(__yix_Actions) {
    return ui.view.component(__yix_Actions, ui.reactive.props.coerce(ActionsProps, args));
}
const ActionsProps = struct {
    m: ui.Source(*M.View),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Actions;
    pub const __yix_preview_mount = __yix_Actions;
};
fn __yix_Actions(__yix_props: ActionsProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "Actions", .receiver = "row", .tokens = "row style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . trailing ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, }, ui.view.row(.{ .style = S.trailing, }, .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "Actions", .receiver = "box", .tokens = "box style = @static; visible = M . stopShown ( m ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . no_shrink ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "M . stopShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.box(.{ .style = S.no_shrink, .visible = __yix_d1: {
        const __yix_T = @TypeOf(M.stopShown(__yix_view_ctx.m.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.stopShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "Actions", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = \"停止生成\" position = { . top } > < W . Button testId = { m . space . id ( \"ai.stop\" ) } a11yLabel = \"停止生成\" variant = { . primary } size = { . sm } iconOnly = { true } iconAsset = { M . glyphNamed ( \"square\" ) } onClick = { M . stop ( m ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "\"停止生成\" ", .kind = .property, .literal = .{ .text = "停止生成" } }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, } }, .{ .m = __yix_view_ctx.m, }, __yix_builder_7306: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_7306 ui.view.with(W.Tooltip(.{ .text = "停止生成", .position = .top, }), .{
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "Actions", .receiver = "W.Button", .tokens = "< W . Button testId = { m . space . id ( \"ai.stop\" ) } a11yLabel = \"停止生成\" variant = { . primary } size = { . sm } iconOnly = { true } iconAsset = { M . glyphNamed ( \"square\" ) } onClick = { M . stop ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.stop\" ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "\"停止生成\" ", .kind = .property, .literal = .{ .text = "停止生成" } }, .{ .name = "variant", .tokens = ". primary ", .kind = .property, .literal = .{ .enum_name = "primary" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "icon_only", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "icon_asset", .tokens = "M . glyphNamed ( \"square\" ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . stop ( m ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .test_id = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.stop"));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.stop");
        } }.__yix_compute);
    }, }, __yix_builder_7374: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_7374 W.Button(.{ .a11y_label = "停止生成", .variant = .primary, .size = .sm, .icon_only = true, .icon_asset = __yix_call4: {
        const __yix_Raw = @TypeOf(M.glyphNamed("square"));
        break :__yix_call4 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.glyphNamed("square") else __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyphNamed("square"));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.glyphNamed("square");
        } }.__yix_compute);
    };
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.stop(__yix_ctx.m.peek());  } }.__yix_run) else __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.stop(__yix_view_ctx.m.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.stop(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); })),
                }); }),
            })),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "Actions", .receiver = "box", .tokens = "box style = @static; visible = M . sendShown ( m ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . no_shrink ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "M . sendShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.box(.{ .style = S.no_shrink, .visible = __yix_d6: {
        const __yix_T = @TypeOf(M.sendShown(__yix_view_ctx.m.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.sendShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "Actions", .receiver = "W.Tooltip", .tokens = "< W . Tooltip testId = { m . space . id ( \"ai.send.hint\" ) } text = { M . sendHint ( m ) } position = { . top } parts = { . { . content = m . space . id ( \"ai.send.tooltip\" ) } } > < W . Button testId = { m . space . id ( \"ai.send\" ) } a11yLabel = { M . sendLabel ( m ) } variant = { . primary } size = { . sm } iconOnly = { true } iconAsset = { M . glyphNamed ( \"arrow-up\" ) } disabled = { M . sendDisabled ( m ) } onClick = { M . send ( m ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.send.hint\" ) ", .kind = .property, .literal = null }, .{ .name = "text", .tokens = "M . sendHint ( m ) ", .kind = .property, .literal = null }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, .{ .name = "parts", .tokens = ". { . content = m . space . id ( \"ai.send.tooltip\" ) } ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .test_id = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.send.hint"));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.send.hint");
        } }.__yix_compute);
    }, .parts = .{ .content = __yix_d9: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.send.tooltip"));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.send.tooltip");
        } }.__yix_compute);
    } }, }, __yix_builder_7671: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_7671 ui.view.with(W.Tooltip(.{ .text = __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(M.sendHint(__yix_view_ctx.m.peek()));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.sendHint(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .position = .top, }), .{
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "Actions", .receiver = "W.Button", .tokens = "< W . Button testId = { m . space . id ( \"ai.send\" ) } a11yLabel = { M . sendLabel ( m ) } variant = { . primary } size = { . sm } iconOnly = { true } iconAsset = { M . glyphNamed ( \"arrow-up\" ) } disabled = { M . sendDisabled ( m ) } onClick = { M . send ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.send\" ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "M . sendLabel ( m ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". primary ", .kind = .property, .literal = .{ .enum_name = "primary" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "icon_only", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "icon_asset", .tokens = "M . glyphNamed ( \"arrow-up\" ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "M . sendDisabled ( m ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . send ( m ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .test_id = __yix_d10: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.send"));
        break :__yix_d10 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.send");
        } }.__yix_compute);
    }, }, __yix_builder_7830: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_7830 W.Button(.{ .a11y_label = __yix_d11: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(M.sendLabel(__yix_view_ctx.m.peek()));
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.sendLabel(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .variant = .primary, .size = .sm, .icon_only = true, .icon_asset = __yix_call13: {
        const __yix_Raw = @TypeOf(M.glyphNamed("arrow-up"));
        break :__yix_call13 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.glyphNamed("arrow-up") else __yix_d12: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyphNamed("arrow-up"));
        break :__yix_d12 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.glyphNamed("arrow-up");
        } }.__yix_compute);
    };
    }, .disabled = __yix_d14: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(M.sendDisabled(__yix_view_ctx.m.peek()));
        break :__yix_d14 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.sendDisabled(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.send(__yix_ctx.m.peek());  } }.__yix_run) else __yix_d15: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.send(__yix_view_ctx.m.peek()));
        break :__yix_d15 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.send(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); })),
                }); })),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Actions";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// O4: the model list (provider groups, rows with brand, context window and capabilities), then
/// the reasoning control (native Slider with one mark per supported step), then a failure line.
fn ModelPopover(args: anytype) ui.view.ComponentOf(__yix_ModelPopover) {
    return ui.view.component(__yix_ModelPopover, ui.reactive.props.coerce(ModelPopoverProps, args));
}
const ModelPopoverProps = struct {
    m: ui.Source(*M.View),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ModelPopover;
    pub const __yix_preview_mount = __yix_ModelPopover;
};
fn __yix_ModelPopover(__yix_props: ModelPopoverProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    try ui.view.previewCheckSetup(scope, true);
    const popup = try ui.view.createRef(scope, W.popover.PopoverResult);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, .popup = popup, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "W.Popover", .tokens = "< W . Popover ref = { popup } open = { M . popupOpen ( m , 0 ) } trigger = { . manual } position = { . top_end } anchor = { M . popupAnchor ( m , 0 ) } offset = { . { . static = 6 } } width = { M . width ( . model ) } maxHeight = { M . height ( . model ) } closeOnEscape = { true } closeOnOutsideClick = { true } trapFocus = { true } initialFocus = { M . initialFocus ( m , 0 ) } returnFocus = { M . focusName ( m , . model_anchor ) } constrainWidthToViewport = { true } flip = { true } shiftMainAxis = { true } viewportPadding = { 8 } style = { S . wrapper } parts = { . { . chrome = m . space . id ( \"ai.model.menu\" ) } } onOpenChange = { | o | M . popupOpenChanged ( m , 0 , o ) } > < col style = { S . model_body } > < col testId = { m . space . id ( \"ai.model.card\" ) } style = { S . model_card } > < text style = { S . empty_text } box = { S . empty_box } visible = { M . modelsEmpty ( m ) } > 暂无已配置模型</text> < W . Button testId = { m . space . id ( \"ai.model.settings\" ) } label = \"打开 AI 设置\" variant = { . secondary } size = { . sm } visible = { M . settingsShown ( m ) } onClick = { M . openSettings ( m ) } / > < M . ModelList m = { m } testId = { m . space . id ( \"ai.model.list\" ) } style = { S . models } visible = { ! M . modelsEmpty ( m ) } / > < / col > < W . Divider / > < col testId = { m . space . id ( \"ai.model.reasoning_card\" ) } style = { S . reasoning_card } > < row style = { S . reasoning_header } > < text testId = { m . space . id ( \"ai.effort.title\" ) } style = { S . effort_title } box = { S . effort_title_box } visible = { M . effortShown ( m ) } > 推理强度</text> < text testId = { m . space . id ( \"ai.effort.value\" ) } style = { S . effort_name } box = { S . effort_name_box } > { M . effortName ( m ) } < / text > < / row > < col testId = { m . space . id ( \"ai.effort.area\" ) } style = { S . slider_area } visible = { M . effortShown ( m ) } > < box testId = { m . space . id ( \"ai.effort.slider\" ) } style = { S . slider_box } > < W . Slider focusId = { M . focusName ( m , . slider ) } labelText = \"推理档位\" min = { 0 } max = { 4 } step = { 0 } width = { 308 } trackHeight = { 3 } thumbSize = { 12 } value = { M . sliderValue ( m ) } onChange = { | v | M . effortProposed ( m , v ) } disabled = { M . disabled ( m , . effort ) } testId = { m . space . id ( \"ai.effort.slider.track\" ) } marks = { M . marks ( m ) } thumbVisible = { M . thumbShown ( m ) } look = { . stepped } style = { S . slider } onKeyDown = { | e | sliderKey ( m , e ) } / > < / box > < / col > < / col > < text testId = { m . space . id ( \"ai.model.error\" ) } style = { S . error_text } box = { S . error_box } visible = { M . modelError ( m ) } > 无法更新，请重试</text> < / col > < / W . Popover > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "popup ", .kind = .reference, .literal = null }, .{ .name = "open", .tokens = "M . popupOpen ( m , 0 ) ", .kind = .property, .literal = null }, .{ .name = "trigger", .tokens = ". manual ", .kind = .property, .literal = .{ .enum_name = "manual" } }, .{ .name = "position", .tokens = ". top_end ", .kind = .property, .literal = .{ .enum_name = "top_end" } }, .{ .name = "anchor", .tokens = "M . popupAnchor ( m , 0 ) ", .kind = .property, .literal = null }, .{ .name = "offset", .tokens = ". { . static = 6 } ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "M . width ( . model ) ", .kind = .property, .literal = null }, .{ .name = "max_height", .tokens = "M . height ( . model ) ", .kind = .property, .literal = null }, .{ .name = "close_on_escape", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "close_on_outside_click", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "trap_focus", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "initial_focus", .tokens = "M . initialFocus ( m , 0 ) ", .kind = .property, .literal = null }, .{ .name = "return_focus", .tokens = "M . focusName ( m , . model_anchor ) ", .kind = .property, .literal = null }, .{ .name = "constrain_width_to_viewport", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "flip", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "shift_main_axis", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "viewport_padding", .tokens = "8 ", .kind = .property, .literal = .{ .number = 8 } }, .{ .name = "style", .tokens = "S . wrapper ", .kind = .style, .literal = null }, .{ .name = "parts", .tokens = ". { . chrome = m . space . id ( \"ai.model.menu\" ) } ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | M . popupOpenChanged ( m , 0 , o ) ", .kind = .event, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, .popup = __yix_view_ctx.popup, }, ui.view.templateAttrs(.{ .style = S.wrapper, .parts = .{ .chrome = __yix_d9: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.menu"));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.menu");
        } }.__yix_compute);
    } }, }, ui.view.ref(__yix_view_ctx.popup, __yix_builder_8441: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Popover); break :__yix_builder_8441 ui.view.with(W.Popover(.{ .open = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Popover, "open")) |__yix_A| __yix_A else @TypeOf(M.popupOpen(__yix_view_ctx.m.peek(), 0));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.popupOpen(__yix_ctx.m.get(), 0);
        } }.__yix_compute);
    }, .trigger = .manual, .position = .top_end, .anchor = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Popover, "anchor")) |__yix_A| __yix_A else @TypeOf(M.popupAnchor(__yix_view_ctx.m.peek(), 0));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.popupAnchor(__yix_ctx.m.get(), 0);
        } }.__yix_compute);
    }, .offset = .{ .static = 6 }, .width = __yix_call4: {
        const __yix_Raw = @TypeOf(M.width(.model));
        break :__yix_call4 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.width(.model) else __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Popover, "width")) |__yix_A| __yix_A else @TypeOf(M.width(.model));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.width(.model);
        } }.__yix_compute);
    };
    }, .max_height = __yix_call6: {
        const __yix_Raw = @TypeOf(M.height(.model));
        break :__yix_call6 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.height(.model) else __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Popover, "max_height")) |__yix_A| __yix_A else @TypeOf(M.height(.model));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.height(.model);
        } }.__yix_compute);
    };
    }, .close_on_escape = true, .close_on_outside_click = true, .trap_focus = true, .initial_focus = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Popover, "initial_focus")) |__yix_A| __yix_A else @TypeOf(M.initialFocus(__yix_view_ctx.m.peek(), 0));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.initialFocus(__yix_ctx.m.get(), 0);
        } }.__yix_compute);
    }, .return_focus = __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Popover, "return_focus")) |__yix_A| __yix_A else @TypeOf(M.focusName(__yix_view_ctx.m.peek(), .model_anchor));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.focusName(__yix_ctx.m.get(), .model_anchor);
        } }.__yix_compute);
    }, .constrain_width_to_viewport = true, .flip = true, .shift_main_axis = true, .viewport_padding = 8, .on_open_change = ui.view.eventProp(W.Popover, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.popupOpenChanged(__yix_ctx.m.peek(), 0, o);  } }.__yix_run)), }), .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "col", .tokens = "col style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . model_body ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.col(.{ .style = S.model_body, }, .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "col", .tokens = "col testId = m . space . id ( \"ai.model.card\" ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.model.card\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . model_card ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.col(.{ .test_id = __yix_d10: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.card"));
        break :__yix_d10 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.card");
        } }.__yix_compute);
    }, .style = S.model_card, }, .{
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "text", .tokens = "text style = @static; box = S . empty_box ; visible = M . modelsEmpty ( m ) ; ", .literal_text = "暂无已配置模型", .attributes = &.{ .{ .name = "style", .tokens = "S . empty_text ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . empty_box ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "M . modelsEmpty ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .style = S.empty_text, .box = S.empty_box, .visible = __yix_d11: {
        const __yix_T = @TypeOf(M.modelsEmpty(__yix_view_ctx.m.peek()));
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.modelsEmpty(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, ui.view.fmt("暂无已配置模型", .{ }))),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "W.Button", .tokens = "< W . Button testId = { m . space . id ( \"ai.model.settings\" ) } label = \"打开 AI 设置\" variant = { . secondary } size = { . sm } visible = { M . settingsShown ( m ) } onClick = { M . openSettings ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.model.settings\" ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"打开 AI 设置\" ", .kind = .property, .literal = .{ .text = "打开 AI 设置" } }, .{ .name = "variant", .tokens = ". secondary ", .kind = .property, .literal = .{ .enum_name = "secondary" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "visible", .tokens = "M . settingsShown ( m ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . openSettings ( m ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .test_id = __yix_d12: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.settings"));
        break :__yix_d12 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.settings");
        } }.__yix_compute);
    }, .visible = __yix_d13: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(M.settingsShown(__yix_view_ctx.m.peek()));
        break :__yix_d13 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.settingsShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, __yix_builder_9242: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_9242 W.Button(.{ .label = "打开 AI 设置", .variant = .secondary, .size = .sm, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.openSettings(__yix_ctx.m.peek());  } }.__yix_run) else __yix_d14: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.openSettings(__yix_view_ctx.m.peek()));
        break :__yix_d14 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.openSettings(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); })),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "M.ModelList", .tokens = "< M . ModelList m = { m } testId = { m . space . id ( \"ai.model.list\" ) } style = { S . models } visible = { ! M . modelsEmpty ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "m", .tokens = "m ", .kind = .property, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.model.list\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . models ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "! M . modelsEmpty ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .test_id = __yix_d15: {
        const __yix_T = if (ui.view.attrType(M.ModelList, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.list"));
        break :__yix_d15 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.list");
        } }.__yix_compute);
    }, .style = S.models, .visible = __yix_d16: {
        const __yix_T = if (ui.view.attrType(M.ModelList, "visible")) |__yix_A| __yix_A else @TypeOf(!M.modelsEmpty(__yix_view_ctx.m.peek()));
        break :__yix_d16 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !M.modelsEmpty(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, __yix_builder_9430: { try ui.view.previewCheckBuilder(__yix_view_scope, M.ModelList); break :__yix_builder_9430 M.ModelList(.{ .m = __yix_view_ctx.m, }); })),
                })),
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "W.Divider", .tokens = "< W . Divider / > ", .literal_text = null, .attributes = &.{ } }, .{ }, __yix_builder_9573: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Divider); break :__yix_builder_9573 W.Divider(.{ }); }),
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "col", .tokens = "col testId = m . space . id ( \"ai.model.reasoning_card\" ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.model.reasoning_card\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . reasoning_card ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.col(.{ .test_id = __yix_d17: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.reasoning_card"));
        break :__yix_d17 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.reasoning_card");
        } }.__yix_compute);
    }, .style = S.reasoning_card, }, .{
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "row", .tokens = "row style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . reasoning_header ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.row(.{ .style = S.reasoning_header, }, .{
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "text", .tokens = "text testId = m . space . id ( \"ai.effort.title\" ) ; style = @static; box = S . effort_title_box ; visible = M . effortShown ( m ) ; ", .literal_text = "推理强度", .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.effort.title\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . effort_title ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . effort_title_box ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "M . effortShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .test_id = __yix_d18: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.effort.title"));
        break :__yix_d18 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.effort.title");
        } }.__yix_compute);
    }, .style = S.effort_title, .box = S.effort_title_box, .visible = __yix_d19: {
        const __yix_T = @TypeOf(M.effortShown(__yix_view_ctx.m.peek()));
        break :__yix_d19 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.effortShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, ui.view.fmt("推理强度", .{ }))),
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "text", .tokens = "text testId = m . space . id ( \"ai.effort.value\" ) ; style = @static; box = S . effort_name_box ; M . effortName ( m )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.effort.value\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . effort_name ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . effort_name_box ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .test_id = __yix_d20: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.effort.value"));
        break :__yix_d20 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.effort.value");
        } }.__yix_compute);
    }, .style = S.effort_name, .box = S.effort_name_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d21: {
        const __yix_T = @TypeOf(M.effortName(__yix_view_ctx.m.peek()));
        break :__yix_d21 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.effortName(__yix_ctx.m.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d21: {
        const __yix_T = @TypeOf(M.effortName(__yix_view_ctx.m.peek()));
        break :__yix_d21 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.effortName(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }))),
                    })),
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "col", .tokens = "col testId = m . space . id ( \"ai.effort.area\" ) ; style = @static; visible = M . effortShown ( m ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.effort.area\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . slider_area ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "M . effortShown ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.col(.{ .test_id = __yix_d22: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.effort.area"));
        break :__yix_d22 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.effort.area");
        } }.__yix_compute);
    }, .style = S.slider_area, .visible = __yix_d23: {
        const __yix_T = @TypeOf(M.effortShown(__yix_view_ctx.m.peek()));
        break :__yix_d23 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.effortShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, .{
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "box", .tokens = "box testId = m . space . id ( \"ai.effort.slider\" ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.effort.slider\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . slider_box ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.box(.{ .test_id = __yix_d24: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.effort.slider"));
        break :__yix_d24 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.effort.slider");
        } }.__yix_compute);
    }, .style = S.slider_box, }, .{
                            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "W.Slider", .tokens = "< W . Slider focusId = { M . focusName ( m , . slider ) } labelText = \"推理档位\" min = { 0 } max = { 4 } step = { 0 } width = { 308 } trackHeight = { 3 } thumbSize = { 12 } value = { M . sliderValue ( m ) } onChange = { | v | M . effortProposed ( m , v ) } disabled = { M . disabled ( m , . effort ) } testId = { m . space . id ( \"ai.effort.slider.track\" ) } marks = { M . marks ( m ) } thumbVisible = { M . thumbShown ( m ) } look = { . stepped } style = { S . slider } onKeyDown = { | e | sliderKey ( m , e ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "focus_id", .tokens = "M . focusName ( m , . slider ) ", .kind = .property, .literal = null }, .{ .name = "label_text", .tokens = "\"推理档位\" ", .kind = .property, .literal = .{ .text = "推理档位" } }, .{ .name = "min", .tokens = "0 ", .kind = .property, .literal = .{ .number = 0 } }, .{ .name = "max", .tokens = "4 ", .kind = .property, .literal = .{ .number = 4 } }, .{ .name = "step", .tokens = "0 ", .kind = .property, .literal = .{ .number = 0 } }, .{ .name = "width", .tokens = "308 ", .kind = .property, .literal = .{ .number = 308 } }, .{ .name = "track_height", .tokens = "3 ", .kind = .property, .literal = .{ .number = 3 } }, .{ .name = "thumb_size", .tokens = "12 ", .kind = .property, .literal = .{ .number = 12 } }, .{ .name = "value", .tokens = "M . sliderValue ( m ) ", .kind = .property, .literal = null }, .{ .name = "on_change", .tokens = "| v | M . effortProposed ( m , v ) ", .kind = .event, .literal = null }, .{ .name = "disabled", .tokens = "M . disabled ( m , . effort ) ", .kind = .property, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.effort.slider.track\" ) ", .kind = .property, .literal = null }, .{ .name = "marks", .tokens = "M . marks ( m ) ", .kind = .property, .literal = null }, .{ .name = "thumb_visible", .tokens = "M . thumbShown ( m ) ", .kind = .property, .literal = null }, .{ .name = "look", .tokens = ". stepped ", .kind = .property, .literal = .{ .enum_name = "stepped" } }, .{ .name = "style", .tokens = "S . slider ", .kind = .style, .literal = null }, .{ .name = "on_key_down", .tokens = "| e | sliderKey ( m , e ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .focus_id = __yix_d25: {
        const __yix_T = if (ui.view.attrType(W.Slider, "focus_id")) |__yix_A| __yix_A else @TypeOf(M.focusName(__yix_view_ctx.m.peek(), .slider));
        break :__yix_d25 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.focusName(__yix_ctx.m.get(), .slider);
        } }.__yix_compute);
    }, .test_id = __yix_d28: {
        const __yix_T = if (ui.view.attrType(W.Slider, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.effort.slider.track"));
        break :__yix_d28 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.effort.slider.track");
        } }.__yix_compute);
    }, .style = S.slider, .on_key_down = try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, e: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); sliderKey(__yix_ctx.m.peek(), e);  } }.__yix_run), }, __yix_builder_10297: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Slider); break :__yix_builder_10297 W.Slider(.{ .label_text = "推理档位", .min = 0, .max = 4, .step = 0, .width = 308, .track_height = 3, .thumb_size = 12, .value = __yix_d26: {
        const __yix_T = if (ui.view.attrType(W.Slider, "value")) |__yix_A| __yix_A else @TypeOf(M.sliderValue(__yix_view_ctx.m.peek()));
        break :__yix_d26 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.sliderValue(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .on_change = ui.view.eventProp(W.Slider, "on_change", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, v: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.effortProposed(__yix_ctx.m.peek(), v);  } }.__yix_run)), .disabled = __yix_d27: {
        const __yix_T = if (ui.view.attrType(W.Slider, "disabled")) |__yix_A| __yix_A else @TypeOf(M.disabled(__yix_view_ctx.m.peek(), .effort));
        break :__yix_d27 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.disabled(__yix_ctx.m.get(), .effort);
        } }.__yix_compute);
    }, .marks = __yix_d29: {
        const __yix_T = if (ui.view.attrType(W.Slider, "marks")) |__yix_A| __yix_A else @TypeOf(M.marks(__yix_view_ctx.m.peek()));
        break :__yix_d29 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.marks(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .thumb_visible = __yix_d30: {
        const __yix_T = if (ui.view.attrType(W.Slider, "thumb_visible")) |__yix_A| __yix_A else @TypeOf(M.thumbShown(__yix_view_ctx.m.peek()));
        break :__yix_d30 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.thumbShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .look = .stepped, }); })),
                        })),
                    })),
                })),
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelPopover", .receiver = "text", .tokens = "text testId = m . space . id ( \"ai.model.error\" ) ; style = @static; box = S . error_box ; visible = M . modelError ( m ) ; ", .literal_text = "无法更新，请重试", .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.model.error\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . error_text ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . error_box ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "M . modelError ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .test_id = __yix_d31: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.error"));
        break :__yix_d31 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.error");
        } }.__yix_compute);
    }, .style = S.error_text, .box = S.error_box, .visible = __yix_d32: {
        const __yix_T = @TypeOf(M.modelError(__yix_view_ctx.m.peek()));
        break :__yix_d32 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.modelError(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }, ui.view.fmt("无法更新，请重试", .{ }))),
            })),
        }); }))));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ModelPopover";
    return __yix_root;
    } }.__yix_render);
    try ui.view.runLifecycleAction(scope, "onMount", .{ .m = m, .popup = popup, .__yix_owner = scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { if (comptime @import("builtin").is_test) __yix_ctx.__yix_owner.recordTestHook(.onMount); __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); keepPopup(__yix_ctx.m.peek(), 0, __yix_ctx.popup);  } }.__yix_run);
    return __yix_view;

}

/// A model-list row: a provider header or a model.
pub fn ListRow(args: anytype) ui.view.ComponentOf(__yix_ListRow) {
    return ui.view.component(__yix_ListRow, ui.reactive.props.coerce(ListRowProps, args));
}
pub const ListRowProps = struct {
    m: ui.Source(*M.View),
    index: ui.Source(usize),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ListRow;
    pub const __yix_preview_mount = __yix_ListRow;
};
fn __yix_ListRow(__yix_props: ListRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    const index = __yix_props.index;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, .index = index, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ListRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . list_row ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, }, ui.view.box(.{ .style = S.list_row, }, .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ListRow", .receiver = "control", .tokens = "if ( M . isHeader ( m , index ) ) < ProviderRow m = { m } index = { index } / > else < ModelRow m = { m } index = { index } / > " }, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, }, ui.view.lazyIf(__yix_d1: {
        const __yix_T = @TypeOf(M.isHeader(__yix_view_ctx.m.peek(), __yix_view_ctx.index.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.isHeader(__yix_ctx.m.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    }, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ListRow/keyword_if:1/branch:0", .receiver = "ProviderRow", .tokens = "< ProviderRow m = { m } index = { index } / > ", .literal_text = null, .attributes = &.{ .{ .name = "m", .tokens = "m ", .kind = .property, .literal = null }, .{ .name = "index", .tokens = "index ", .kind = .property, .literal = null }, } }, .{ .m = __yix_b1_0.m, .index = __yix_b1_0.index, }, __yix_builder_26: { try ui.view.previewCheckBuilder(__yix_bs1_0, ProviderRow); break :__yix_builder_26 ProviderRow(.{ .m = __yix_b1_0.m, .index = __yix_b1_0.index, }); }) }); } }.__yix_b, struct { fn __yix_b(__yix_b1_1: anytype, __yix_bs1_1: *ui.Scope, __yix_bc1_1: *ui.Cx, __yix_bk1_1: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_1, __yix_bc1_1, __yix_bk1_1, .{ ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ListRow/keyword_if:1/branch:1", .receiver = "ModelRow", .tokens = "< ModelRow m = { m } index = { index } / > ", .literal_text = null, .attributes = &.{ .{ .name = "m", .tokens = "m ", .kind = .property, .literal = null }, .{ .name = "index", .tokens = "index ", .kind = .property, .literal = null }, } }, .{ .m = __yix_b1_1.m, .index = __yix_b1_1.index, }, __yix_builder_67: { try ui.view.previewCheckBuilder(__yix_bs1_1, ModelRow); break :__yix_builder_67 ModelRow(.{ .m = __yix_b1_1.m, .index = __yix_b1_1.index, }); }) }); } }.__yix_b)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ListRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// A provider group header (O4): chevron, brand, name; a press folds the group.
pub fn ProviderRow(args: anytype) ui.view.ComponentOf(__yix_ProviderRow) {
    return ui.view.component(__yix_ProviderRow, ui.reactive.props.coerce(ProviderRowProps, args));
}
pub const ProviderRowProps = struct {
    m: ui.Source(*M.View),
    index: ui.Source(usize),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ProviderRow;
    pub const __yix_preview_mount = __yix_ProviderRow;
};
fn __yix_ProviderRow(__yix_props: ProviderRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    const index = __yix_props.index;
    try ui.view.previewCheckSetup(scope, false);
    const name = try scope.createSignalFor([]const u8, M.providerName(m.peek(), index.peek()));
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, .index = index, .name = name, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ProviderRow", .receiver = "W.Pressable", .tokens = "< W . Pressable testId = { m . space . id ( \"ai.model.provider\" ) } a11yLabel = { name } onClick = { M . toggleProvider ( m , index ) } style = { S . group_row } > < icon src = { M . providerChevron ( m , index ) } style = { S . group_chevron } / > < BrandMark brand = { M . providerBrand ( m , index ) } name = { name } / > < text style = { S . group_name } box = { S . group_name_box } > { name } < / text > < / W . Pressable > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.model.provider\" ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "name ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . toggleProvider ( m , index ) ", .kind = .event, .literal = null }, .{ .name = "style", .tokens = "S . group_row ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, .name = __yix_view_ctx.name, .index = __yix_view_ctx.index, }, ui.view.templateAttrs(.{ .test_id = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.provider"));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.provider");
        } }.__yix_compute);
    }, .style = S.group_row, }, __yix_builder_11580: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Pressable); break :__yix_builder_11580 ui.view.with(W.Pressable(.{ .a11y_label = __yix_view_ctx.name, .on_click = if (comptime ui.view.isEventProp(W.Pressable, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.toggleProvider(__yix_ctx.m.peek(), __yix_ctx.index.peek());  } }.__yix_run) else __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "on_click")) |__yix_A| __yix_A else @TypeOf(M.toggleProvider(__yix_view_ctx.m.peek(), __yix_view_ctx.index.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.toggleProvider(__yix_ctx.m.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    }, }), .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ProviderRow", .receiver = "icon", .tokens = "icon src = M . providerChevron ( m , index ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "M . providerChevron ( m , index ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . group_chevron ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, }, ui.view.icon(.{ .style = S.group_chevron, }, __yix_d3: {
        const __yix_T = @TypeOf(M.providerChevron(__yix_view_ctx.m.peek(), __yix_view_ctx.index.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.providerChevron(__yix_ctx.m.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    })),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ProviderRow", .receiver = "BrandMark", .tokens = "< BrandMark brand = { M . providerBrand ( m , index ) } name = { name } / > ", .literal_text = null, .attributes = &.{ .{ .name = "brand", .tokens = "M . providerBrand ( m , index ) ", .kind = .property, .literal = null }, .{ .name = "name", .tokens = "name ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, .name = __yix_view_ctx.name, }, __yix_builder_11800: { try ui.view.previewCheckBuilder(__yix_view_scope, BrandMark); break :__yix_builder_11800 BrandMark(.{ .brand = __yix_d4: {
        const __yix_T = if (ui.view.attrType(BrandMark, "brand")) |__yix_A| __yix_A else @TypeOf(M.providerBrand(__yix_view_ctx.m.peek(), __yix_view_ctx.index.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.providerBrand(__yix_ctx.m.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    }, .name = __yix_view_ctx.name, }); }),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ProviderRow", .receiver = "text", .tokens = "text style = @static; box = S . group_name_box ; name  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . group_name ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . group_name_box ", .kind = .property, .literal = null }, } }, .{ .name = __yix_view_ctx.name, }, ui.view.text(.{ .style = S.group_name, .box = S.group_name_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_view_ctx.name), ""), .{ __yix_view_ctx.name, }))),
        }); })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ProviderRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// A model row (O4): marker (› for the current model), brand, ID, context window, reasoning and
/// vision capabilities, each with its native Tooltip; the row's details in a 284 native Tooltip.
pub fn ModelRow(args: anytype) ui.view.ComponentOf(__yix_ModelRow) {
    return ui.view.component(__yix_ModelRow, ui.reactive.props.coerce(ModelRowProps, args));
}
pub const ModelRowProps = struct {
    m: ui.Source(*M.View),
    index: ui.Source(usize),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ModelRow;
    pub const __yix_preview_mount = __yix_ModelRow;
};
fn __yix_ModelRow(__yix_props: ModelRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    const index = __yix_props.index;
    try ui.view.previewCheckSetup(scope, false);
    const row = __yix_d1: {
        const __yix_T = @TypeOf(M.modelRow(m.peek(), index.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .m = m, .index = index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.modelRow(__yix_ctx.m.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    };
    const id = try scope.createSignalFor([]const u8, M.modelRow(m.peek(), index.peek()).id);
    const base = try scope.createSignalFor([]const u8, M.modelRow(m.peek(), index.peek()).basename);
    const details = try scope.createSignalFor([]const u8, M.modelRow(m.peek(), index.peek()).description);
    const context = try scope.createSignalFor([]const u8, M.modelRow(m.peek(), index.peek()).context);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, .index = index, .row = row, .id = id, .base = base, .details = details, .context = context, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { details } width = { 284 } wrap = { . word } position = { . right } offset = { 8 } closeOnEscape = { false } style = { S . row_hint } parts = { . { . trigger = . { . style = S . row_trigger } , . content = m . space . id ( \"ai.model.details\" ) } } > < W . Pressable focusId = { M . rowFocusId ( m , index ) } testId = { m . space . id ( \"ai.model.option\" ) } a11yLabel = { details } a11yDescription = { details } selected = { row . selected } disabled = { ! row . choosable } onClick = { M . chooseModel ( m , index ) } style = { S . ModelRow . of ( . { . selected = row . selected } ) } > < box testId = { M . markerId ( m , row . selected ) } style = { S . marker } > { if ( row . selected ) < text style = { S . marker_text } box = { S . marker_text_box } > ›</text> else <box style={S.marker_dot} />} < / box > < BrandMark testId = { m . space . id ( \"ai.model.logo\" ) } brand = { row . brand } name = { base } / > < text testId = { m . space . id ( \"ai.model.name\" ) } style = { S . ModelName . of ( . { . off = ! row . enabled } ) } box = { S . model_name_box } > { id } < / text > < text testId = { m . space . id ( \"ai.model.context\" ) } style = { S . ModelContext . of ( . { . off = ! row . enabled } ) } box = { S . context_box . of ( . { . w = M . contextWidth ( m ) } ) } > { context } < / text > < W . Tooltip text = { M . reasoningHint ( row . reasoning ) } style = { S . capability } parts = { . { . trigger = m . space . id ( \"ai.model.reasoning\" ) , . content = m . space . id ( \"ai.model.reasoning.tooltip\" ) } } > < icon src = { M . glyphNamed ( \"brain\" ) } style = { S . CapabilityIcon . of ( . { . on = row . enabled and row . reasoning } ) } / > < / W . Tooltip > < W . Tooltip text = { M . visionHint ( row . vision ) } style = { S . capability } parts = { . { . trigger = m . space . id ( \"ai.model.vision\" ) } } > < icon src = { M . visionGlyph ( row . vision ) } style = { S . CapabilityIcon . of ( . { . on = row . enabled and row . vision } ) } / > < / W . Tooltip > < / W . Pressable > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "details ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "284 ", .kind = .property, .literal = .{ .number = 284 } }, .{ .name = "wrap", .tokens = ". word ", .kind = .property, .literal = .{ .enum_name = "word" } }, .{ .name = "position", .tokens = ". right ", .kind = .property, .literal = .{ .enum_name = "right" } }, .{ .name = "offset", .tokens = "8 ", .kind = .property, .literal = .{ .number = 8 } }, .{ .name = "close_on_escape", .tokens = "false ", .kind = .property, .literal = .{ .boolean = false } }, .{ .name = "style", .tokens = "S . row_hint ", .kind = .style, .literal = null }, .{ .name = "parts", .tokens = ". { . trigger = . { . style = S . row_trigger } , . content = m . space . id ( \"ai.model.details\" ) } ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, .details = __yix_view_ctx.details, .index = __yix_view_ctx.index, .row = __yix_view_ctx.row, .base = __yix_view_ctx.base, .id = __yix_view_ctx.id, .context = __yix_view_ctx.context, }, ui.view.templateAttrs(.{ .style = S.row_hint, .parts = .{ .trigger = .{ .style = S.row_trigger }, .content = __yix_d2: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.details"));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.details");
        } }.__yix_compute);
    } }, }, __yix_builder_12645: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_12645 ui.view.with(W.Tooltip(.{ .text = __yix_view_ctx.details, .width = 284, .wrap = .word, .position = .right, .offset = 8, .close_on_escape = false, }), .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow", .receiver = "W.Pressable", .tokens = "< W . Pressable focusId = { M . rowFocusId ( m , index ) } testId = { m . space . id ( \"ai.model.option\" ) } a11yLabel = { details } a11yDescription = { details } selected = { row . selected } disabled = { ! row . choosable } onClick = { M . chooseModel ( m , index ) } style = { S . ModelRow . of ( . { . selected = row . selected } ) } > < box testId = { M . markerId ( m , row . selected ) } style = { S . marker } > { if ( row . selected ) < text style = { S . marker_text } box = { S . marker_text_box } > ›</text> else <box style={S.marker_dot} />} < / box > < BrandMark testId = { m . space . id ( \"ai.model.logo\" ) } brand = { row . brand } name = { base } / > < text testId = { m . space . id ( \"ai.model.name\" ) } style = { S . ModelName . of ( . { . off = ! row . enabled } ) } box = { S . model_name_box } > { id } < / text > < text testId = { m . space . id ( \"ai.model.context\" ) } style = { S . ModelContext . of ( . { . off = ! row . enabled } ) } box = { S . context_box . of ( . { . w = M . contextWidth ( m ) } ) } > { context } < / text > < W . Tooltip text = { M . reasoningHint ( row . reasoning ) } style = { S . capability } parts = { . { . trigger = m . space . id ( \"ai.model.reasoning\" ) , . content = m . space . id ( \"ai.model.reasoning.tooltip\" ) } } > < icon src = { M . glyphNamed ( \"brain\" ) } style = { S . CapabilityIcon . of ( . { . on = row . enabled and row . reasoning } ) } / > < / W . Tooltip > < W . Tooltip text = { M . visionHint ( row . vision ) } style = { S . capability } parts = { . { . trigger = m . space . id ( \"ai.model.vision\" ) } } > < icon src = { M . visionGlyph ( row . vision ) } style = { S . CapabilityIcon . of ( . { . on = row . enabled and row . vision } ) } / > < / W . Tooltip > < / W . Pressable > ", .literal_text = null, .attributes = &.{ .{ .name = "focus_id", .tokens = "M . rowFocusId ( m , index ) ", .kind = .property, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.model.option\" ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "details ", .kind = .property, .literal = null }, .{ .name = "a11y_description", .tokens = "details ", .kind = .property, .literal = null }, .{ .name = "selected", .tokens = "row . selected ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "! row . choosable ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . chooseModel ( m , index ) ", .kind = .event, .literal = null }, .{ .name = "style", .tokens = "S . ModelRow . of ( . { . selected = row . selected } ) ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, .row = __yix_view_ctx.row, .details = __yix_view_ctx.details, .base = __yix_view_ctx.base, .id = __yix_view_ctx.id, .context = __yix_view_ctx.context, }, ui.view.templateAttrs(.{ .focus_id = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "focus_id")) |__yix_A| __yix_A else @TypeOf(M.rowFocusId(__yix_view_ctx.m.peek(), __yix_view_ctx.index.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.rowFocusId(__yix_ctx.m.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    }, .test_id = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.option"));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.option");
        } }.__yix_compute);
    }, .style = S.ModelRow.of(.{ .selected = __yix_d8: {
        const __yix_T = @TypeOf(__yix_view_ctx.row.peek().selected);
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().selected;
        } }.__yix_compute);
    } }), }, __yix_builder_12874: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Pressable); break :__yix_builder_12874 ui.view.with(W.Pressable(.{ .a11y_label = __yix_view_ctx.details, .a11y_description = __yix_view_ctx.details, .selected = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "selected")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.row.peek().selected);
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().selected;
        } }.__yix_compute);
    }, .disabled = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "disabled")) |__yix_A| __yix_A else @TypeOf(!__yix_view_ctx.row.peek().choosable);
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !__yix_ctx.row.get().choosable;
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Pressable, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.chooseModel(__yix_ctx.m.peek(), __yix_ctx.index.peek());  } }.__yix_run) else __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "on_click")) |__yix_A| __yix_A else @TypeOf(M.chooseModel(__yix_view_ctx.m.peek(), __yix_view_ctx.index.peek()));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .index = __yix_view_ctx.index, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.chooseModel(__yix_ctx.m.get(), __yix_ctx.index.get());
        } }.__yix_compute);
    }, }), .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow", .receiver = "box", .tokens = "box testId = M . markerId ( m , row . selected ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "M . markerId ( m , row . selected ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . marker ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .row = __yix_view_ctx.row, }, ui.view.box(.{ .test_id = __yix_d9: {
        const __yix_T = @TypeOf(M.markerId(__yix_view_ctx.m.peek(), __yix_view_ctx.row.peek().selected));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.markerId(__yix_ctx.m.get(), __yix_ctx.row.get().selected);
        } }.__yix_compute);
    }, .style = S.marker, }, .{
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow", .receiver = "control", .tokens = "if ( row . selected ) < text style = { S . marker_text } box = { S . marker_text_box } > ›</text> else <box style={S.marker_dot} /> " }, .{ .row = __yix_view_ctx.row, }, ui.view.lazyIf(__yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.row.peek().selected);
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().selected;
        } }.__yix_compute);
    }, .{ }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { _ = __yix_b1_0; return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow/keyword_if:1/branch:0", .receiver = "text", .tokens = "text style = @static; box = S . marker_text_box ; ", .literal_text = "›", .attributes = &.{ .{ .name = "style", .tokens = "S . marker_text ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . marker_text_box ", .kind = .property, .literal = null }, } }, .{ }, ui.view.text(.{ .style = S.marker_text, .box = S.marker_text_box, }, ui.view.fmt("›", .{ }))) }); } }.__yix_b, struct { fn __yix_b(__yix_b1_1: anytype, __yix_bs1_1: *ui.Scope, __yix_bc1_1: *ui.Cx, __yix_bk1_1: ui.view.Sink) anyerror!void { _ = __yix_b1_1; return ui.view.emit(__yix_bs1_1, __yix_bc1_1, __yix_bk1_1, .{ ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow/keyword_if:1/branch:1", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . marker_dot ", .kind = .style, .literal = null }, } }, .{ }, ui.view.box(.{ .style = S.marker_dot, }, .{ })) }); } }.__yix_b)),
                })),
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow", .receiver = "BrandMark", .tokens = "< BrandMark testId = { m . space . id ( \"ai.model.logo\" ) } brand = { row . brand } name = { base } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.model.logo\" ) ", .kind = .property, .literal = null }, .{ .name = "brand", .tokens = "row . brand ", .kind = .property, .literal = null }, .{ .name = "name", .tokens = "base ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .row = __yix_view_ctx.row, .base = __yix_view_ctx.base, }, ui.view.templateAttrs(.{ .test_id = __yix_d10: {
        const __yix_T = if (ui.view.attrType(BrandMark, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.logo"));
        break :__yix_d10 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.logo");
        } }.__yix_compute);
    }, }, __yix_builder_13395: { try ui.view.previewCheckBuilder(__yix_view_scope, BrandMark); break :__yix_builder_13395 BrandMark(.{ .brand = __yix_d11: {
        const __yix_T = if (ui.view.attrType(BrandMark, "brand")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.row.peek().brand);
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().brand;
        } }.__yix_compute);
    }, .name = __yix_view_ctx.base, }); })),
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow", .receiver = "text", .tokens = "text testId = m . space . id ( \"ai.model.name\" ) ; style = S . ModelName . of ( . { . off = ! row . enabled } ) ; box = S . model_name_box ; id  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.model.name\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . ModelName . of ( . { . off = ! row . enabled } ) ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . model_name_box ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .row = __yix_view_ctx.row, .id = __yix_view_ctx.id, }, ui.view.text(.{ .test_id = __yix_d12: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.name"));
        break :__yix_d12 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.name");
        } }.__yix_compute);
    }, .style = S.ModelName.of(.{ .off = __yix_d13: {
        const __yix_T = @TypeOf(!__yix_view_ctx.row.peek().enabled);
        break :__yix_d13 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !__yix_ctx.row.get().enabled;
        } }.__yix_compute);
    } }), .box = S.model_name_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_view_ctx.id), ""), .{ __yix_view_ctx.id, }))),
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow", .receiver = "text", .tokens = "text testId = m . space . id ( \"ai.model.context\" ) ; style = S . ModelContext . of ( . { . off = ! row . enabled } ) ; box = S . context_box . of ( . { . w = M . contextWidth ( m ) } ) ; context  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.model.context\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . ModelContext . of ( . { . off = ! row . enabled } ) ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . context_box . of ( . { . w = M . contextWidth ( m ) } ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .row = __yix_view_ctx.row, .context = __yix_view_ctx.context, }, ui.view.text(.{ .test_id = __yix_d14: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.context"));
        break :__yix_d14 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.context");
        } }.__yix_compute);
    }, .style = S.ModelContext.of(.{ .off = __yix_d15: {
        const __yix_T = @TypeOf(!__yix_view_ctx.row.peek().enabled);
        break :__yix_d15 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !__yix_ctx.row.get().enabled;
        } }.__yix_compute);
    } }), .box = S.context_box.of(.{ .w = __yix_d16: {
        const __yix_T = @TypeOf(M.contextWidth(__yix_view_ctx.m.peek()));
        break :__yix_d16 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.contextWidth(__yix_ctx.m.get());
        } }.__yix_compute);
    } }), }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_view_ctx.context), ""), .{ __yix_view_ctx.context, }))),
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { M . reasoningHint ( row . reasoning ) } style = { S . capability } parts = { . { . trigger = m . space . id ( \"ai.model.reasoning\" ) , . content = m . space . id ( \"ai.model.reasoning.tooltip\" ) } } > < icon src = { M . glyphNamed ( \"brain\" ) } style = { S . CapabilityIcon . of ( . { . on = row . enabled and row . reasoning } ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "M . reasoningHint ( row . reasoning ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . capability ", .kind = .style, .literal = null }, .{ .name = "parts", .tokens = ". { . trigger = m . space . id ( \"ai.model.reasoning\" ) , . content = m . space . id ( \"ai.model.reasoning.tooltip\" ) } ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .row = __yix_view_ctx.row, }, ui.view.templateAttrs(.{ .style = S.capability, .parts = .{ .trigger = __yix_d18: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.reasoning"));
        break :__yix_d18 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.reasoning");
        } }.__yix_compute);
    }, .content = __yix_d19: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.reasoning.tooltip"));
        break :__yix_d19 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.reasoning.tooltip");
        } }.__yix_compute);
    } }, }, __yix_builder_13818: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_13818 ui.view.with(W.Tooltip(.{ .text = __yix_d17: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(M.reasoningHint(__yix_view_ctx.row.peek().reasoning));
        break :__yix_d17 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.reasoningHint(__yix_ctx.row.get().reasoning);
        } }.__yix_compute);
    }, }), .{
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow", .receiver = "icon", .tokens = "icon src = M . glyphNamed ( \"brain\" ) ; style = S . CapabilityIcon . of ( . { . on = row . enabled and row . reasoning } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "M . glyphNamed ( \"brain\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . CapabilityIcon . of ( . { . on = row . enabled and row . reasoning } ) ", .kind = .style, .literal = null }, } }, .{ .row = __yix_view_ctx.row, }, ui.view.icon(.{ .style = S.CapabilityIcon.of(.{ .on = __yix_d22: {
        const __yix_T = @TypeOf(__yix_view_ctx.row.peek().enabled and __yix_view_ctx.row.peek().reasoning);
        break :__yix_d22 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().enabled and __yix_ctx.row.get().reasoning;
        } }.__yix_compute);
    } }), }, __yix_call21: {
        const __yix_Raw = @TypeOf(M.glyphNamed("brain"));
        break :__yix_call21 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.glyphNamed("brain") else __yix_d20: {
        const __yix_T = @TypeOf(M.glyphNamed("brain"));
        break :__yix_d20 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.glyphNamed("brain");
        } }.__yix_compute);
    };
    })),
                }); })),
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { M . visionHint ( row . vision ) } style = { S . capability } parts = { . { . trigger = m . space . id ( \"ai.model.vision\" ) } } > < icon src = { M . visionGlyph ( row . vision ) } style = { S . CapabilityIcon . of ( . { . on = row . enabled and row . vision } ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "M . visionHint ( row . vision ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . capability ", .kind = .style, .literal = null }, .{ .name = "parts", .tokens = ". { . trigger = m . space . id ( \"ai.model.vision\" ) } ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, .row = __yix_view_ctx.row, }, ui.view.templateAttrs(.{ .style = S.capability, .parts = .{ .trigger = __yix_d24: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.model.vision"));
        break :__yix_d24 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.model.vision");
        } }.__yix_compute);
    } }, }, __yix_builder_14171: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_14171 ui.view.with(W.Tooltip(.{ .text = __yix_d23: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(M.visionHint(__yix_view_ctx.row.peek().vision));
        break :__yix_d23 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.visionHint(__yix_ctx.row.get().vision);
        } }.__yix_compute);
    }, }), .{
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "ModelRow", .receiver = "icon", .tokens = "icon src = M . visionGlyph ( row . vision ) ; style = S . CapabilityIcon . of ( . { . on = row . enabled and row . vision } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "M . visionGlyph ( row . vision ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . CapabilityIcon . of ( . { . on = row . enabled and row . vision } ) ", .kind = .style, .literal = null }, } }, .{ .row = __yix_view_ctx.row, }, ui.view.icon(.{ .style = S.CapabilityIcon.of(.{ .on = __yix_d26: {
        const __yix_T = @TypeOf(__yix_view_ctx.row.peek().enabled and __yix_view_ctx.row.peek().vision);
        break :__yix_d26 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.row.get().enabled and __yix_ctx.row.get().vision;
        } }.__yix_compute);
    } }), }, __yix_d25: {
        const __yix_T = @TypeOf(M.visionGlyph(__yix_view_ctx.row.peek().vision));
        break :__yix_d25 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.visionGlyph(__yix_ctx.row.get().vision);
        } }.__yix_compute);
    })),
                }); })),
            }); })),
        }); })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ModelRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// Brand mark (16): the brand glyph on a rounded tile, or the name's first character.
pub fn BrandMark(args: anytype) ui.view.ComponentOf(__yix_BrandMark) {
    return ui.view.component(__yix_BrandMark, ui.reactive.props.coerce(BrandMarkProps, args));
}
pub const BrandMarkProps = struct {
    brand: ui.Source(?ui.SvgAsset),
    name: ui.Source([]const u8),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = BrandMark;
    pub const __yix_preview_mount = __yix_BrandMark;
};
fn __yix_BrandMark(__yix_props: BrandMarkProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const brand = __yix_props.brand;
    const name = __yix_props.name;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .brand = brand, .name = name, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "BrandMark", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . brand_tile ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .brand = __yix_view_ctx.brand, .name = __yix_view_ctx.name, }, ui.view.box(.{ .style = S.brand_tile, }, .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "BrandMark", .receiver = "control", .tokens = "if ( brand != null ) < icon src = { brand } style = { S . brand_glyph } / > else < text style = { S . brand_initial } > { M . initial ( name ) } < / text > " }, .{ .brand = __yix_view_ctx.brand, .name = __yix_view_ctx.name, }, ui.view.lazyIf(__yix_d2: {
        const __yix_T = @TypeOf(__yix_view_ctx.brand.peek() != null);
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .brand = __yix_view_ctx.brand, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.brand.get() != null;
        } }.__yix_compute);
    }, .{ .brand = __yix_view_ctx.brand, .name = __yix_view_ctx.name, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "BrandMark/keyword_if:1/branch:0", .receiver = "icon", .tokens = "icon src = brand ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "brand ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . brand_glyph ", .kind = .style, .literal = null }, } }, .{ .brand = __yix_b1_0.brand, }, ui.view.icon(.{ .style = S.brand_glyph, }, __yix_b1_0.brand)) }); } }.__yix_b, struct { fn __yix_b(__yix_b1_1: anytype, __yix_bs1_1: *ui.Scope, __yix_bc1_1: *ui.Cx, __yix_bk1_1: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_1, __yix_bc1_1, __yix_bk1_1, .{ ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "BrandMark/keyword_if:1/branch:1", .receiver = "text", .tokens = "text style = @static; M . initial ( name )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . brand_initial ", .kind = .style, .literal = null }, } }, .{ .name = __yix_b1_1.name, }, ui.view.text(.{ .style = S.brand_initial, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(M.initial(__yix_b1_1.name.peek()));
        break :__yix_d1 try __yix_bs1_1.derive(__yix_T, .{ .name = __yix_b1_1.name, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.initial(__yix_ctx.name.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(M.initial(__yix_b1_1.name.peek()));
        break :__yix_d1 try __yix_bs1_1.derive(__yix_T, .{ .name = __yix_b1_1.name, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.initial(__yix_ctx.name.get());
        } }.__yix_compute);
    }, }))) }); } }.__yix_b)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "BrandMark";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// O6: head (label · used / limit), the native segmented bar, a legend row per source, a separator
/// and the native secondary sm compaction Button (with its reason in a native Tooltip).
fn UsagePopover(args: anytype) ui.view.ComponentOf(__yix_UsagePopover) {
    return ui.view.component(__yix_UsagePopover, ui.reactive.props.coerce(UsagePopoverProps, args));
}
const UsagePopoverProps = struct {
    m: ui.Source(*M.View),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = UsagePopover;
    pub const __yix_preview_mount = __yix_UsagePopover;
};
fn __yix_UsagePopover(__yix_props: UsagePopoverProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    try ui.view.previewCheckSetup(scope, true);
    const popup = try ui.view.createRef(scope, W.popover.PopoverResult);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, .popup = popup, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsagePopover", .receiver = "W.Popover", .tokens = "< W . Popover ref = { popup } open = { M . popupOpen ( m , 1 ) } trigger = { . manual } position = { . top_start } anchor = { M . popupAnchor ( m , 1 ) } offset = { . { . static = 6 } } width = { M . width ( . usage ) } maxHeight = { M . height ( . usage ) } closeOnEscape = { true } closeOnOutsideClick = { true } trapFocus = { true } initialFocus = { M . initialFocus ( m , 1 ) } returnFocus = { M . focusName ( m , . usage_anchor ) } constrainWidthToViewport = { true } flip = { true } shiftMainAxis = { true } viewportPadding = { 8 } style = { S . wrapper } parts = { . { . chrome = m . space . id ( \"ai.usage.menu\" ) } } onOpenChange = { | o | M . popupOpenChanged ( m , 1 , o ) } > < col style = { S . usage_body } > < W . ScrollArea style = { S . usage_scroll } parts = { . { . content = . { . style = S . usage_content } } } > { if ( M . usageShown ( m ) ) < UsageBody m = { m } / > } < / W . ScrollArea > < / col > < / W . Popover > ", .literal_text = null, .attributes = &.{ .{ .name = "ref", .tokens = "popup ", .kind = .reference, .literal = null }, .{ .name = "open", .tokens = "M . popupOpen ( m , 1 ) ", .kind = .property, .literal = null }, .{ .name = "trigger", .tokens = ". manual ", .kind = .property, .literal = .{ .enum_name = "manual" } }, .{ .name = "position", .tokens = ". top_start ", .kind = .property, .literal = .{ .enum_name = "top_start" } }, .{ .name = "anchor", .tokens = "M . popupAnchor ( m , 1 ) ", .kind = .property, .literal = null }, .{ .name = "offset", .tokens = ". { . static = 6 } ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "M . width ( . usage ) ", .kind = .property, .literal = null }, .{ .name = "max_height", .tokens = "M . height ( . usage ) ", .kind = .property, .literal = null }, .{ .name = "close_on_escape", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "close_on_outside_click", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "trap_focus", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "initial_focus", .tokens = "M . initialFocus ( m , 1 ) ", .kind = .property, .literal = null }, .{ .name = "return_focus", .tokens = "M . focusName ( m , . usage_anchor ) ", .kind = .property, .literal = null }, .{ .name = "constrain_width_to_viewport", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "flip", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "shift_main_axis", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "viewport_padding", .tokens = "8 ", .kind = .property, .literal = .{ .number = 8 } }, .{ .name = "style", .tokens = "S . wrapper ", .kind = .style, .literal = null }, .{ .name = "parts", .tokens = ". { . chrome = m . space . id ( \"ai.usage.menu\" ) } ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | M . popupOpenChanged ( m , 1 , o ) ", .kind = .event, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, .popup = __yix_view_ctx.popup, }, ui.view.templateAttrs(.{ .style = S.wrapper, .parts = .{ .chrome = __yix_d9: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.usage.menu"));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.usage.menu");
        } }.__yix_compute);
    } }, }, ui.view.ref(__yix_view_ctx.popup, __yix_builder_15195: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Popover); break :__yix_builder_15195 ui.view.with(W.Popover(.{ .open = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Popover, "open")) |__yix_A| __yix_A else @TypeOf(M.popupOpen(__yix_view_ctx.m.peek(), 1));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.popupOpen(__yix_ctx.m.get(), 1);
        } }.__yix_compute);
    }, .trigger = .manual, .position = .top_start, .anchor = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Popover, "anchor")) |__yix_A| __yix_A else @TypeOf(M.popupAnchor(__yix_view_ctx.m.peek(), 1));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.popupAnchor(__yix_ctx.m.get(), 1);
        } }.__yix_compute);
    }, .offset = .{ .static = 6 }, .width = __yix_call4: {
        const __yix_Raw = @TypeOf(M.width(.usage));
        break :__yix_call4 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.width(.usage) else __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Popover, "width")) |__yix_A| __yix_A else @TypeOf(M.width(.usage));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.width(.usage);
        } }.__yix_compute);
    };
    }, .max_height = __yix_call6: {
        const __yix_Raw = @TypeOf(M.height(.usage));
        break :__yix_call6 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.height(.usage) else __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Popover, "max_height")) |__yix_A| __yix_A else @TypeOf(M.height(.usage));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.height(.usage);
        } }.__yix_compute);
    };
    }, .close_on_escape = true, .close_on_outside_click = true, .trap_focus = true, .initial_focus = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Popover, "initial_focus")) |__yix_A| __yix_A else @TypeOf(M.initialFocus(__yix_view_ctx.m.peek(), 1));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.initialFocus(__yix_ctx.m.get(), 1);
        } }.__yix_compute);
    }, .return_focus = __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Popover, "return_focus")) |__yix_A| __yix_A else @TypeOf(M.focusName(__yix_view_ctx.m.peek(), .usage_anchor));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.focusName(__yix_ctx.m.get(), .usage_anchor);
        } }.__yix_compute);
    }, .constrain_width_to_viewport = true, .flip = true, .shift_main_axis = true, .viewport_padding = 8, .on_open_change = ui.view.eventProp(W.Popover, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.popupOpenChanged(__yix_ctx.m.peek(), 1, o);  } }.__yix_run)), }), .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsagePopover", .receiver = "col", .tokens = "col style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . usage_body ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.col(.{ .style = S.usage_body, }, .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsagePopover", .receiver = "W.ScrollArea", .tokens = "< W . ScrollArea style = { S . usage_scroll } parts = { . { . content = . { . style = S . usage_content } } } > { if ( M . usageShown ( m ) ) < UsageBody m = { m } / > } < / W . ScrollArea > ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . usage_scroll ", .kind = .style, .literal = null }, .{ .name = "parts", .tokens = ". { . content = . { . style = S . usage_content } } ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .style = S.usage_scroll, .parts = .{ .content = .{ .style = S.usage_content } }, }, __yix_builder_15793: { try ui.view.previewCheckBuilder(__yix_view_scope, W.ScrollArea); break :__yix_builder_15793 ui.view.with(W.ScrollArea(.{ }), .{
                    ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsagePopover", .receiver = "control", .tokens = "if ( M . usageShown ( m ) ) < UsageBody m = { m } / > " }, .{ .m = __yix_view_ctx.m, }, ui.view.lazyIf(__yix_d1: {
        const __yix_T = @TypeOf(M.usageShown(__yix_view_ctx.m.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.usageShown(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsagePopover/keyword_if:1/branch:0", .receiver = "UsageBody", .tokens = "< UsageBody m = { m } / > ", .literal_text = null, .attributes = &.{ .{ .name = "m", .tokens = "m ", .kind = .property, .literal = null }, } }, .{ .m = __yix_b1_0.m, }, __yix_builder_21: { try ui.view.previewCheckBuilder(__yix_bs1_0, UsageBody); break :__yix_builder_21 UsageBody(.{ .m = __yix_b1_0.m, }); }) }); } }.__yix_b, null)),
                }); })),
            })),
        }); }))));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "UsagePopover";
    return __yix_root;
    } }.__yix_render);
    try ui.view.runLifecycleAction(scope, "onMount", .{ .m = m, .popup = popup, .__yix_owner = scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { if (comptime @import("builtin").is_test) __yix_ctx.__yix_owner.recordTestHook(.onMount); __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); keepPopup(__yix_ctx.m.peek(), 1, __yix_ctx.popup);  } }.__yix_run);
    return __yix_view;

}

fn UsageBody(args: anytype) ui.view.ComponentOf(__yix_UsageBody) {
    return ui.view.component(__yix_UsageBody, ui.reactive.props.coerce(UsageBodyProps, args));
}
const UsageBodyProps = struct {
    m: ui.Source(*M.View),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = UsageBody;
    pub const __yix_preview_mount = __yix_UsageBody;
};
fn __yix_UsageBody(__yix_props: UsageBodyProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody", .receiver = "col", .tokens = "col ", .literal_text = null, .attributes = &.{ }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, }, ui.view.col(.{ }, .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody", .receiver = "row", .tokens = "row testId = m . space . id ( \"ai.usage.summary\" ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.usage.summary\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . usage_head ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.row(.{ .test_id = __yix_d1: {
        const __yix_T = @TypeOf(__yix_view_ctx.m.peek().space.id("ai.usage.summary"));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.usage.summary");
        } }.__yix_compute);
    }, .style = S.usage_head, }, .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody", .receiver = "text", .tokens = "text style = @static; box = S . usage_caption_box ; M . usageCaption ( m )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . usage_caption ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . usage_caption_box ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .style = S.usage_caption, .box = S.usage_caption_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d2: {
        const __yix_T = @TypeOf(M.usageCaption(__yix_view_ctx.m.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.usageCaption(__yix_ctx.m.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d2: {
        const __yix_T = @TypeOf(M.usageCaption(__yix_view_ctx.m.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.usageCaption(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody", .receiver = "text", .tokens = "text style = @static; box = S . usage_total_box ; M . usageTotal ( m )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . usage_total ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . usage_total_box ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.text(.{ .style = S.usage_total, .box = S.usage_total_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d3: {
        const __yix_T = @TypeOf(M.usageTotal(__yix_view_ctx.m.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.usageTotal(__yix_ctx.m.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d3: {
        const __yix_T = @TypeOf(M.usageTotal(__yix_view_ctx.m.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.usageTotal(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }))),
            })),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody", .receiver = "W.ProgressSegments", .tokens = "< W . ProgressSegments testId = { m . space . id ( \"ai.usage.track\" ) } segments = { M . usageSegments ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.usage.track\" ) ", .kind = .property, .literal = null }, .{ .name = "segments", .tokens = "M . usageSegments ( m ) ", .kind = .property, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .test_id = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.ProgressSegments, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.usage.track"));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.usage.track");
        } }.__yix_compute);
    }, }, __yix_builder_16391: { try ui.view.previewCheckBuilder(__yix_view_scope, W.ProgressSegments); break :__yix_builder_16391 W.ProgressSegments(.{ .segments = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.ProgressSegments, "segments")) |__yix_A| __yix_A else @TypeOf(M.usageSegments(__yix_view_ctx.m.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.usageSegments(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); })),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody", .receiver = "col", .tokens = "col style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . usage_legend ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.col(.{ .style = S.usage_legend, }, .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody", .receiver = "control", .tokens = "for ( M . usageParts ( m ) ) | part | < row key = { part . index } style = { S . usage_row } > < box style = { S . UsageSwatch . of ( . { . tone = part . tone } ) } / > < text style = { S . usage_name } box = { S . usage_name_box } > { M . usagePartName ( part ) } < / text > < text testId = { m . space . id ( \"ai.usage.part.value\" ) } style = { S . usage_value } box = { S . usage_value_box } > { M . usagePartValue ( part ) } < / text > < / row > " }, .{ .m = __yix_view_ctx.m, }, __yix_e1: { const __yix_items_1 = __yix_d5: {
        const __yix_T = @TypeOf(M.usageParts(__yix_view_ctx.m.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.usageParts(__yix_ctx.m.get());
        } }.__yix_compute);
    }; break :__yix_e1 ui.view.eachWith(.{ .m = __yix_view_ctx.m, }, __yix_items_1, struct { fn __yix_k(part: ui.view.yixItem(@TypeOf(__yix_items_1))) u64 { return ui.view.keyOf(part.index); } }.__yix_k, struct { fn __yix_row(__yix_row_1: anytype, part: ui.Source(ui.view.yixItem(@TypeOf(__yix_items_1))), __yix_scope_1: *ui.Scope, __yix_cx_1: *ui.Cx) anyerror!*ui.Node { return ui.view.render(__yix_scope_1, __yix_cx_1, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody/keyword_for:1", .receiver = "row", .tokens = "row key = part . index ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "key", .tokens = "part . index ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . usage_row ", .kind = .style, .literal = null }, } }, .{ .part = part, .m = __yix_row_1.m, }, ui.view.row(.{ .style = S.usage_row, }, .{
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody/keyword_for:1", .receiver = "box", .tokens = "box style = S . UsageSwatch . of ( . { . tone = part . tone } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . UsageSwatch . of ( . { . tone = part . tone } ) ", .kind = .style, .literal = null }, } }, .{ .part = part, }, ui.view.box(.{ .style = S.UsageSwatch.of(.{ .tone = __yix_d1: {
        const __yix_T = @TypeOf(part.peek().tone);
        break :__yix_d1 try __yix_scope_1.derive(__yix_T, .{ .part = part, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.part.get().tone;
        } }.__yix_compute);
    } }), }, .{ })),
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody/keyword_for:1", .receiver = "text", .tokens = "text style = @static; box = S . usage_name_box ; M . usagePartName ( part )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . usage_name ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . usage_name_box ", .kind = .property, .literal = null }, } }, .{ .part = part, }, ui.view.text(.{ .style = S.usage_name, .box = S.usage_name_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d2: {
        const __yix_T = @TypeOf(M.usagePartName(part.peek()));
        break :__yix_d2 try __yix_scope_1.derive(__yix_T, .{ .part = part, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.usagePartName(__yix_ctx.part.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d2: {
        const __yix_T = @TypeOf(M.usagePartName(part.peek()));
        break :__yix_d2 try __yix_scope_1.derive(__yix_T, .{ .part = part, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.usagePartName(__yix_ctx.part.get());
        } }.__yix_compute);
    }, }))),
                        ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody/keyword_for:1", .receiver = "text", .tokens = "text testId = m . space . id ( \"ai.usage.part.value\" ) ; style = @static; box = S . usage_value_box ; M . usagePartValue ( part )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "m . space . id ( \"ai.usage.part.value\" ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . usage_value ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . usage_value_box ", .kind = .property, .literal = null }, } }, .{ .m = __yix_row_1.m, .part = part, }, ui.view.text(.{ .test_id = __yix_d3: {
        const __yix_T = @TypeOf(__yix_row_1.m.peek().space.id("ai.usage.part.value"));
        break :__yix_d3 try __yix_scope_1.derive(__yix_T, .{ .m = __yix_row_1.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.usage.part.value");
        } }.__yix_compute);
    }, .style = S.usage_value, .box = S.usage_value_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d4: {
        const __yix_T = @TypeOf(M.usagePartValue(part.peek()));
        break :__yix_d4 try __yix_scope_1.derive(__yix_T, .{ .part = part, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.usagePartValue(__yix_ctx.part.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d4: {
        const __yix_T = @TypeOf(M.usagePartValue(part.peek()));
        break :__yix_d4 try __yix_scope_1.derive(__yix_T, .{ .part = part, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.usagePartValue(__yix_ctx.part.get());
        } }.__yix_compute);
    }, }))),
                    }))); } }.__yix_row); }),
            })),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody", .receiver = "W.Divider", .tokens = "< W . Divider / > ", .literal_text = null, .attributes = &.{ } }, .{ }, __yix_builder_16992: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Divider); break :__yix_builder_16992 W.Divider(.{ }); }),
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody", .receiver = "row", .tokens = "row style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . usage_action ", .kind = .style, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.row(.{ .style = S.usage_action, }, .{
                ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody", .receiver = "control", .tokens = "if ( M . compactionRunning ( m ) ) < CompactionCancel m = { m } / > else < CompactionStart m = { m } / > " }, .{ .m = __yix_view_ctx.m, }, ui.view.lazyIf(__yix_d1: {
        const __yix_T = @TypeOf(M.compactionRunning(__yix_view_ctx.m.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.compactionRunning(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_b(__yix_b2_0: anytype, __yix_bs2_0: *ui.Scope, __yix_bc2_0: *ui.Cx, __yix_bk2_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs2_0, __yix_bc2_0, __yix_bk2_0, .{ ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody/keyword_if:2/branch:0", .receiver = "CompactionCancel", .tokens = "< CompactionCancel m = { m } / > ", .literal_text = null, .attributes = &.{ .{ .name = "m", .tokens = "m ", .kind = .property, .literal = null }, } }, .{ .m = __yix_b2_0.m, }, __yix_builder_28: { try ui.view.previewCheckBuilder(__yix_bs2_0, CompactionCancel); break :__yix_builder_28 CompactionCancel(.{ .m = __yix_b2_0.m, }); }) }); } }.__yix_b, struct { fn __yix_b(__yix_b2_1: anytype, __yix_bs2_1: *ui.Scope, __yix_bc2_1: *ui.Cx, __yix_bk2_1: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs2_1, __yix_bc2_1, __yix_bk2_1, .{ ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "UsageBody/keyword_if:2/branch:1", .receiver = "CompactionStart", .tokens = "< CompactionStart m = { m } / > ", .literal_text = null, .attributes = &.{ .{ .name = "m", .tokens = "m ", .kind = .property, .literal = null }, } }, .{ .m = __yix_b2_1.m, }, __yix_builder_60: { try ui.view.previewCheckBuilder(__yix_bs2_1, CompactionStart); break :__yix_builder_60 CompactionStart(.{ .m = __yix_b2_1.m, }); }) }); } }.__yix_b)),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "UsageBody";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// The usage popover's action. Both forms carry the same focusId: it is the popover's first focus
/// (`initialFocus`) while it can act. Its reason Tooltip is a passive hint and stays out of the Escape order,
/// so one Escape closes the popover also while the focused action shows its hint.
fn CompactionCancel(args: anytype) ui.view.ComponentOf(__yix_CompactionCancel) {
    return ui.view.component(__yix_CompactionCancel, ui.reactive.props.coerce(CompactionCancelProps, args));
}
const CompactionCancelProps = struct {
    m: ui.Source(*M.View),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = CompactionCancel;
    pub const __yix_preview_mount = __yix_CompactionCancel;
};
fn __yix_CompactionCancel(__yix_props: CompactionCancelProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "CompactionCancel", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { M . compactionReason ( m ) } closeOnEscape = { false } > < W . Button focusId = { M . focusName ( m , . usage_action ) } testId = { m . space . id ( \"ai.usage.compaction.cancel\" ) } label = \"取消压缩\" a11yLabel = { M . compactionReason ( m ) } iconAsset = { ui . icons . x } variant = { . secondary } size = { . sm } onClick = { M . cancelCompaction ( m ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "M . compactionReason ( m ) ", .kind = .property, .literal = null }, .{ .name = "close_on_escape", .tokens = "false ", .kind = .property, .literal = .{ .boolean = false } }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, }, __yix_builder_17548: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_17548 ui.view.with(W.Tooltip(.{ .text = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(M.compactionReason(__yix_view_ctx.m.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.compactionReason(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .close_on_escape = false, }), .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "CompactionCancel", .receiver = "W.Button", .tokens = "< W . Button focusId = { M . focusName ( m , . usage_action ) } testId = { m . space . id ( \"ai.usage.compaction.cancel\" ) } label = \"取消压缩\" a11yLabel = { M . compactionReason ( m ) } iconAsset = { ui . icons . x } variant = { . secondary } size = { . sm } onClick = { M . cancelCompaction ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "focus_id", .tokens = "M . focusName ( m , . usage_action ) ", .kind = .property, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.usage.compaction.cancel\" ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"取消压缩\" ", .kind = .property, .literal = .{ .text = "取消压缩" } }, .{ .name = "a11y_label", .tokens = "M . compactionReason ( m ) ", .kind = .property, .literal = null }, .{ .name = "icon_asset", .tokens = "ui . icons . x ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". secondary ", .kind = .property, .literal = .{ .enum_name = "secondary" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "on_click", .tokens = "M . cancelCompaction ( m ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .focus_id = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Button, "focus_id")) |__yix_A| __yix_A else @TypeOf(M.focusName(__yix_view_ctx.m.peek(), .usage_action));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.focusName(__yix_ctx.m.get(), .usage_action);
        } }.__yix_compute);
    }, .test_id = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.usage.compaction.cancel"));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.usage.compaction.cancel");
        } }.__yix_compute);
    }, }, __yix_builder_17623: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_17623 W.Button(.{ .label = "取消压缩", .a11y_label = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(M.compactionReason(__yix_view_ctx.m.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.compactionReason(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .icon_asset = ui.icons.x, .variant = .secondary, .size = .sm, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.cancelCompaction(__yix_ctx.m.peek());  } }.__yix_run) else __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.cancelCompaction(__yix_view_ctx.m.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.cancelCompaction(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); })),
        }); }));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "CompactionCancel";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}
fn CompactionStart(args: anytype) ui.view.ComponentOf(__yix_CompactionStart) {
    return ui.view.component(__yix_CompactionStart, ui.reactive.props.coerce(CompactionStartProps, args));
}
const CompactionStartProps = struct {
    m: ui.Source(*M.View),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = CompactionStart;
    pub const __yix_preview_mount = __yix_CompactionStart;
};
fn __yix_CompactionStart(__yix_props: CompactionStartProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const m = __yix_props.m;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .m = m, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "CompactionStart", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { M . compactionReason ( m ) } closeOnEscape = { false } > < W . Button focusId = { M . focusName ( m , . usage_action ) } testId = { m . space . id ( \"ai.usage.compaction.start\" ) } label = \"压缩上下文\" a11yLabel = { M . compactionReason ( m ) } iconAsset = { M . glyphNamed ( \"fold-vertical\" ) } variant = { . secondary } size = { . sm } disabled = { ! M . canCompact ( m ) } onClick = { M . startCompaction ( m ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "M . compactionReason ( m ) ", .kind = .property, .literal = null }, .{ .name = "close_on_escape", .tokens = "false ", .kind = .property, .literal = .{ .boolean = false } }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .m = __yix_view_ctx.m, }, __yix_builder_17957: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_17957 ui.view.with(W.Tooltip(.{ .text = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(M.compactionReason(__yix_view_ctx.m.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.compactionReason(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .close_on_escape = false, }), .{
            ui.view.templateSite(.{ .module = "src/features/ai/composer/view/ai_composer_controls.yix", .path = "CompactionStart", .receiver = "W.Button", .tokens = "< W . Button focusId = { M . focusName ( m , . usage_action ) } testId = { m . space . id ( \"ai.usage.compaction.start\" ) } label = \"压缩上下文\" a11yLabel = { M . compactionReason ( m ) } iconAsset = { M . glyphNamed ( \"fold-vertical\" ) } variant = { . secondary } size = { . sm } disabled = { ! M . canCompact ( m ) } onClick = { M . startCompaction ( m ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "focus_id", .tokens = "M . focusName ( m , . usage_action ) ", .kind = .property, .literal = null }, .{ .name = "test_id", .tokens = "m . space . id ( \"ai.usage.compaction.start\" ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"压缩上下文\" ", .kind = .property, .literal = .{ .text = "压缩上下文" } }, .{ .name = "a11y_label", .tokens = "M . compactionReason ( m ) ", .kind = .property, .literal = null }, .{ .name = "icon_asset", .tokens = "M . glyphNamed ( \"fold-vertical\" ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". secondary ", .kind = .property, .literal = .{ .enum_name = "secondary" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "disabled", .tokens = "! M . canCompact ( m ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "M . startCompaction ( m ) ", .kind = .event, .literal = null }, } }, .{ .m = __yix_view_ctx.m, }, ui.view.templateAttrs(.{ .focus_id = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Button, "focus_id")) |__yix_A| __yix_A else @TypeOf(M.focusName(__yix_view_ctx.m.peek(), .usage_action));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.focusName(__yix_ctx.m.get(), .usage_action);
        } }.__yix_compute);
    }, .test_id = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.m.peek().space.id("ai.usage.compaction.start"));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.m.get().space.id("ai.usage.compaction.start");
        } }.__yix_compute);
    }, }, __yix_builder_18032: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_18032 W.Button(.{ .label = "压缩上下文", .a11y_label = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(M.compactionReason(__yix_view_ctx.m.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.compactionReason(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .icon_asset = __yix_call6: {
        const __yix_Raw = @TypeOf(M.glyphNamed("fold-vertical"));
        break :__yix_call6 if (comptime !ui.view.yixCallMayDerive(__yix_Raw)) M.glyphNamed("fold-vertical") else __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Button, "icon_asset")) |__yix_A| __yix_A else @TypeOf(M.glyphNamed("fold-vertical"));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            _ = __yix_ctx;
            return M.glyphNamed("fold-vertical");
        } }.__yix_compute);
    };
    }, .variant = .secondary, .size = .sm, .disabled = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(!M.canCompact(__yix_view_ctx.m.peek()));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !M.canCompact(__yix_ctx.m.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .m = __yix_view_ctx.m, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); M.startCompaction(__yix_ctx.m.peek());  } }.__yix_run) else __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(M.startCompaction(__yix_view_ctx.m.peek()));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .m = __yix_view_ctx.m, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return M.startCompaction(__yix_ctx.m.get());
        } }.__yix_compute);
    }, }); })),
        }); }));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "CompactionStart";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\x54\x68\x65\x20\x63\x6f\x6d\x70\x6f\x73\x65\x72\x20\x74\x6f\x6f\x6c\x20\x72\x6f\x77\x20\x28\x50\x65\x6e\x63\x69\x6c\x20\x4b\x61\x66\x37\x45\x20\x41\x33\x20\x2f\x20\xe2\x91\xa4\x29\x3a\x20\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x2c\x20\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x2c\x20\x72\x75\x6e\x20\x6d\x6f\x64\x65\x20\x7c\x20\x75\x73\x61\x67\x65\x2c\x20\x6d\x6f\x64\x65\x6c\x2c\x0a\x2f\x2f\x21\x20\x74\x68\x65\x6e\x20\x74\x68\x65\x20\x68\x6f\x73\x74\x27\x73\x20\x73\x65\x6e\x64\x20\x2f\x20\x73\x74\x6f\x70\x2e\x20\x41\x6c\x6c\x20\x6e\x61\x74\x69\x76\x65\x3a\x20\x67\x68\x6f\x73\x74\x20\x73\x6d\x20\x42\x75\x74\x74\x6f\x6e\x73\x20\x28\x6c\x61\x62\x65\x6c\x20\x2b\x20\x6c\x65\x61\x64\x69\x6e\x67\x20\x69\x63\x6f\x6e\x20\x2b\x20\x63\x68\x65\x76\x72\x6f\x6e\x29\x2c\x0a\x2f\x2f\x21\x20\x69\x63\x6f\x6e\x2d\x6f\x6e\x6c\x79\x20\x67\x68\x6f\x73\x74\x20\x73\x6d\x20\x42\x75\x74\x74\x6f\x6e\x73\x20\x69\x6e\x20\x6e\x61\x74\x69\x76\x65\x20\x54\x6f\x6f\x6c\x74\x69\x70\x73\x20\x6f\x6e\x20\x6e\x61\x72\x72\x6f\x77\x20\x72\x6f\x77\x73\x2c\x20\x6e\x61\x74\x69\x76\x65\x20\x4d\x65\x6e\x75\x73\x20\x28\x6d\x65\x6e\x75\x73\x20\x70\x61\x63\x6b\x61\x67\x65\x0a\x2f\x2f\x21\x20\x60\x43\x6f\x6e\x74\x65\x78\x74\x4d\x65\x6e\x75\x60\x29\x20\x66\x6f\x72\x20\x74\x68\x65\x20\x74\x68\x72\x65\x65\x20\x73\x65\x6c\x65\x63\x74\x69\x6f\x6e\x2d\x6f\x6e\x6c\x79\x20\x63\x68\x6f\x69\x63\x65\x73\x2c\x20\x6e\x61\x74\x69\x76\x65\x20\x50\x6f\x70\x6f\x76\x65\x72\x73\x20\x66\x6f\x72\x20\x6d\x6f\x64\x65\x6c\x20\x2b\x20\x65\x66\x66\x6f\x72\x74\x20\x28\x4f\x34\x29\x0a\x2f\x2f\x21\x20\x61\x6e\x64\x20\x66\x6f\x72\x20\x75\x73\x61\x67\x65\x20\x28\x4f\x36\x29\x2e\x20\x45\x73\x63\x61\x70\x65\x20\x61\x6e\x64\x20\x6f\x75\x74\x73\x69\x64\x65\x20\x63\x6c\x69\x63\x6b\x73\x20\x61\x72\x65\x20\x74\x68\x65\x20\x6e\x61\x74\x69\x76\x65\x20\x6f\x76\x65\x72\x6c\x61\x79\x20\x73\x74\x61\x63\x6b\x27\x73\x20\x61\x6c\x6f\x6e\x65\x20\x28\x69\x74\x20\x63\x6c\x6f\x73\x65\x73\x0a\x2f\x2f\x21\x20\x74\x68\x65\x20\x74\x6f\x70\x6d\x6f\x73\x74\x20\x6c\x61\x79\x65\x72\x2c\x20\x61\x6c\x73\x6f\x20\x77\x68\x69\x6c\x65\x20\x66\x6f\x63\x75\x73\x20\x69\x73\x20\x73\x74\x69\x6c\x6c\x20\x6f\x6e\x20\x74\x68\x65\x20\x63\x6f\x6e\x74\x72\x6f\x6c\x20\x74\x68\x61\x74\x20\x6f\x70\x65\x6e\x65\x64\x20\x69\x74\x29\x2c\x20\x61\x6e\x64\x20\x73\x6f\x20\x69\x73\x20\x66\x6f\x63\x75\x73\x0a\x2f\x2f\x21\x20\x28\x60\x74\x72\x61\x70\x46\x6f\x63\x75\x73\x60\x3a\x20\x69\x6e\x20\x6f\x6e\x20\x6f\x70\x65\x6e\x2c\x20\x54\x61\x62\x20\x6b\x65\x70\x74\x20\x69\x6e\x73\x69\x64\x65\x2c\x20\x62\x61\x63\x6b\x20\x6f\x6e\x20\x63\x6c\x6f\x73\x65\x29\x2e\x20\x54\x68\x65\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\x20\x6f\x6e\x6c\x79\x20\x6e\x61\x6d\x65\x73\x20\x74\x68\x65\x0a\x2f\x2f\x21\x20\x63\x6f\x6e\x74\x72\x6f\x6c\x73\x20\x28\x60\x66\x6f\x63\x75\x73\x49\x64\x60\x29\x20\x61\x6e\x64\x20\x73\x61\x79\x73\x20\x77\x68\x69\x63\x68\x20\x6e\x61\x6d\x65\x20\x61\x20\x70\x6f\x70\x6f\x76\x65\x72\x20\x6f\x70\x65\x6e\x73\x20\x6f\x6e\x20\x28\x60\x69\x6e\x69\x74\x69\x61\x6c\x46\x6f\x63\x75\x73\x60\x29\x20\x61\x6e\x64\x20\x72\x65\x74\x75\x72\x6e\x73\x20\x74\x6f\x0a\x2f\x2f\x21\x20\x28\x60\x72\x65\x74\x75\x72\x6e\x46\x6f\x63\x75\x73\x60\x29\x2c\x20\x61\x6e\x64\x20\x68\x65\x61\x72\x73\x20\x6f\x66\x20\x61\x20\x63\x6c\x6f\x73\x65\x20\x74\x68\x72\x6f\x75\x67\x68\x20\x60\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x60\x20\x66\x6f\x72\x20\x69\x74\x73\x20\x6f\x77\x6e\x20\x62\x6f\x6f\x6b\x6b\x65\x65\x70\x69\x6e\x67\x2e\x20\x53\x74\x61\x74\x65\x2c\x20\x63\x61\x70\x74\x75\x72\x65\x73\x2c\x20\x74\x68\x65\x20\x73\x68\x72\x69\x6e\x6b\x20\x72\x75\x6c\x65\x20\x61\x6e\x64\x20\x74\x68\x65\x20\x61\x63\x74\x69\x6f\x6e\x73\x20\x6c\x69\x76\x65\x20\x69\x6e\x20\x74\x68\x65\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\x0a\x2f\x2f\x21\x20\x28\x60\x61\x69\x5f\x63\x6f\x6d\x70\x6f\x73\x65\x72\x5f\x63\x6f\x6e\x74\x72\x6f\x6c\x73\x5f\x76\x69\x65\x77\x2e\x7a\x69\x67\x60\x29\x3b\x20\x74\x68\x69\x73\x20\x66\x69\x6c\x65\x20\x69\x73\x20\x74\x68\x65\x20\x76\x69\x65\x77\x20\x6f\x6e\x6c\x79\x2e\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x53\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x61\x69\x5f\x63\x6f\x6d\x70\x6f\x73\x65\x72\x5f\x63\x6f\x6e\x74\x72\x6f\x6c\x73\x2e\x79\x73\x73\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x4d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x61\x69\x5f\x63\x6f\x6d\x70\x6f\x73\x65\x72\x5f\x63\x6f\x6e\x74\x72\x6f\x6c\x73\x5f\x76\x69\x65\x77\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x0a\x66\x6e\x20\x6b\x65\x65\x70\x52\x6f\x77\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x2c\x20\x72\x6f\x6f\x74\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x2c\x20\x74\x72\x61\x69\x6c\x69\x6e\x67\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x2c\x20\x73\x70\x61\x63\x65\x72\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x6d\x2e\x6b\x65\x65\x70\x52\x6f\x77\x28\x72\x6f\x6f\x74\x2e\x67\x65\x74\x28\x29\x2c\x20\x74\x72\x61\x69\x6c\x69\x6e\x67\x2e\x67\x65\x74\x28\x29\x2c\x20\x73\x70\x61\x63\x65\x72\x2e\x67\x65\x74\x28\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x6b\x65\x65\x70\x42\x75\x74\x74\x6f\x6e\x73\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x2c\x20\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x2c\x20\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x2c\x20\x6d\x6f\x64\x65\x6c\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x2c\x20\x65\x66\x66\x6f\x72\x74\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x2c\x20\x75\x73\x61\x67\x65\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x2c\x20\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x6d\x2e\x6b\x65\x65\x70\x42\x75\x74\x74\x6f\x6e\x73\x28\x2e\x7b\x20\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x2e\x67\x65\x74\x28\x29\x2c\x20\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x2e\x67\x65\x74\x28\x29\x2c\x20\x6d\x6f\x64\x65\x6c\x2e\x67\x65\x74\x28\x29\x2c\x20\x65\x66\x66\x6f\x72\x74\x2e\x67\x65\x74\x28\x29\x2c\x20\x75\x73\x61\x67\x65\x2e\x67\x65\x74\x28\x29\x2c\x20\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x2e\x67\x65\x74\x28\x29\x20\x7d\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x6b\x65\x65\x70\x43\x6f\x6d\x70\x61\x63\x74\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x2c\x20\x73\x6c\x6f\x74\x3a\x20\x75\x73\x69\x7a\x65\x2c\x20\x74\x69\x70\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x57\x2e\x74\x6f\x6f\x6c\x74\x69\x70\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x52\x65\x73\x75\x6c\x74\x29\x2c\x20\x62\x75\x74\x74\x6f\x6e\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x2a\x75\x69\x2e\x4e\x6f\x64\x65\x29\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x6d\x2e\x6b\x65\x65\x70\x43\x6f\x6d\x70\x61\x63\x74\x28\x73\x6c\x6f\x74\x2c\x20\x74\x69\x70\x2e\x67\x65\x74\x28\x29\x2e\x3f\x2e\x77\x72\x61\x70\x70\x65\x72\x2c\x20\x62\x75\x74\x74\x6f\x6e\x2e\x67\x65\x74\x28\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x6b\x65\x65\x70\x50\x6f\x70\x75\x70\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x73\x69\x7a\x65\x2c\x20\x70\x6f\x70\x75\x70\x3a\x20\x2a\x75\x69\x2e\x76\x69\x65\x77\x2e\x52\x65\x66\x28\x57\x2e\x70\x6f\x70\x6f\x76\x65\x72\x2e\x50\x6f\x70\x6f\x76\x65\x72\x52\x65\x73\x75\x6c\x74\x29\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x6d\x2e\x6b\x65\x65\x70\x50\x6f\x70\x75\x70\x28\x69\x6e\x64\x65\x78\x2c\x20\x70\x6f\x70\x75\x70\x2e\x67\x65\x74\x28\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x6c\x69\x64\x65\x72\x4b\x65\x79\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x2c\x20\x65\x3a\x20\x75\x69\x2e\x76\x69\x65\x77\x2e\x4b\x65\x79\x50\x72\x65\x73\x73\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x69\x66\x20\x28\x6d\x2e\x73\x6c\x69\x64\x65\x72\x4b\x65\x79\x28\x65\x2e\x6b\x65\x79\x29\x29\x20\x65\x2e\x73\x74\x6f\x70\x28\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x4e\x61\x72\x72\x6f\x77\x20\x72\x6f\x77\x73\x3a\x20\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x20\x2f\x20\x72\x75\x6e\x20\x6d\x6f\x64\x65\x20\x61\x73\x20\x61\x6e\x20\x69\x63\x6f\x6e\x2d\x6f\x6e\x6c\x79\x20\x6e\x61\x74\x69\x76\x65\x20\x67\x68\x6f\x73\x74\x20\x42\x75\x74\x74\x6f\x6e\x20\x69\x6e\x20\x61\x20\x6e\x61\x74\x69\x76\x65\x20\x54\x6f\x6f\x6c\x74\x69\x70\x0a\x2f\x2f\x2f\x20\x28\x22\xe5\x90\x8d\xe7\xa7\xb0\x20\xc2\xb7\x20\xe5\xbd\x93\xe5\x89\x8d\xe5\x80\xbc\x22\x29\x2e\x0a\x66\x6e\x20\x43\x6f\x6d\x70\x61\x63\x74\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x2c\x20\x73\x6c\x6f\x74\x3a\x20\x75\x73\x69\x7a\x65\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x74\x69\x70\x20\x3d\x20\x72\x65\x66\x28\x57\x2e\x74\x6f\x6f\x6c\x74\x69\x70\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x52\x65\x73\x75\x6c\x74\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x62\x75\x74\x74\x6f\x6e\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x6f\x6e\x4d\x6f\x75\x6e\x74\x28\x6b\x65\x65\x70\x43\x6f\x6d\x70\x61\x63\x74\x28\x6d\x2c\x20\x73\x6c\x6f\x74\x2c\x20\x74\x69\x70\x2c\x20\x62\x75\x74\x74\x6f\x6e\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x72\x65\x66\x3d\x7b\x74\x69\x70\x7d\x20\x74\x65\x78\x74\x3d\x7b\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x54\x65\x78\x74\x28\x6d\x2c\x20\x73\x6c\x6f\x74\x29\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x6f\x5f\x73\x68\x72\x69\x6e\x6b\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x53\x68\x6f\x77\x6e\x28\x6d\x2c\x20\x73\x6c\x6f\x74\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x54\x6f\x6f\x6c\x74\x69\x70\x49\x64\x28\x6d\x2c\x20\x73\x6c\x6f\x74\x29\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x72\x65\x66\x3d\x7b\x62\x75\x74\x74\x6f\x6e\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x49\x64\x28\x6d\x2c\x20\x73\x6c\x6f\x74\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x69\x63\x6f\x6e\x4f\x6e\x6c\x79\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x49\x63\x6f\x6e\x28\x6d\x2c\x20\x73\x6c\x6f\x74\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x54\x65\x78\x74\x28\x6d\x2c\x20\x73\x6c\x6f\x74\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x6d\x2c\x20\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x4b\x69\x6e\x64\x28\x73\x6c\x6f\x74\x29\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x74\x6f\x67\x67\x6c\x65\x28\x6d\x2c\x20\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x4b\x69\x6e\x64\x28\x73\x6c\x6f\x74\x29\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x54\x6f\x6f\x6c\x52\x6f\x77\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x72\x6f\x6f\x74\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x74\x72\x61\x69\x6c\x69\x6e\x67\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x73\x70\x61\x63\x65\x72\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x6d\x6f\x64\x65\x6c\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x65\x66\x66\x6f\x72\x74\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x75\x73\x61\x67\x65\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x20\x3d\x20\x72\x65\x66\x28\x29\x3b\x0a\x20\x20\x20\x20\x6f\x6e\x4d\x6f\x75\x6e\x74\x28\x6b\x65\x65\x70\x52\x6f\x77\x28\x6d\x2c\x20\x72\x6f\x6f\x74\x2c\x20\x74\x72\x61\x69\x6c\x69\x6e\x67\x2c\x20\x73\x70\x61\x63\x65\x72\x29\x29\x3b\x0a\x20\x20\x20\x20\x6f\x6e\x4d\x6f\x75\x6e\x74\x28\x6b\x65\x65\x70\x42\x75\x74\x74\x6f\x6e\x73\x28\x6d\x2c\x20\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x2c\x20\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x2c\x20\x6d\x6f\x64\x65\x6c\x2c\x20\x65\x66\x66\x6f\x72\x74\x2c\x20\x75\x73\x61\x67\x65\x2c\x20\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x72\x65\x66\x3d\x7b\x72\x6f\x6f\x74\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x63\x6f\x6d\x70\x6f\x73\x65\x72\x2e\x63\x6f\x6e\x74\x72\x6f\x6c\x73\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x6f\x77\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x22\xe6\xb7\xbb\xe5\x8a\xa0\xe9\x99\x84\xe4\xbb\xb6\x22\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x6f\x5f\x73\x68\x72\x69\x6e\x6b\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x72\x65\x66\x3d\x7b\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x63\x6f\x6d\x70\x6f\x73\x65\x72\x2e\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x22\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x69\x63\x6f\x6e\x4f\x6e\x6c\x79\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x6d\x2c\x20\x2e\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x22\xe6\xb7\xbb\xe5\x8a\xa0\xe9\x99\x84\xe4\xbb\xb6\x22\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x6d\x2c\x20\x2e\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x74\x6f\x67\x67\x6c\x65\x28\x6d\x2c\x20\x2e\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x72\x65\x66\x3d\x7b\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x4d\x2e\x62\x75\x74\x74\x6f\x6e\x49\x64\x28\x6d\x2c\x20\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x74\x65\x78\x74\x28\x6d\x2c\x20\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x29\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x6d\x2c\x20\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x29\x7d\x20\x63\x68\x65\x76\x72\x6f\x6e\x3d\x7b\x74\x72\x75\x65\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x63\x68\x69\x70\x41\x31\x31\x79\x28\x6d\x2c\x20\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x2c\x20\x22\xe6\x89\xa7\xe8\xa1\x8c\xe6\x9d\x83\xe9\x99\x90\x22\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x6d\x2c\x20\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x63\x68\x69\x70\x53\x68\x6f\x77\x6e\x28\x6d\x2c\x20\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x74\x6f\x67\x67\x6c\x65\x28\x6d\x2c\x20\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x43\x6f\x6d\x70\x61\x63\x74\x20\x6d\x3d\x7b\x6d\x7d\x20\x73\x6c\x6f\x74\x3d\x7b\x30\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x72\x65\x66\x3d\x7b\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x4d\x2e\x62\x75\x74\x74\x6f\x6e\x49\x64\x28\x6d\x2c\x20\x2e\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x74\x65\x78\x74\x28\x6d\x2c\x20\x2e\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x29\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x6d\x2c\x20\x2e\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x29\x7d\x20\x63\x68\x65\x76\x72\x6f\x6e\x3d\x7b\x74\x72\x75\x65\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x63\x68\x69\x70\x41\x31\x31\x79\x28\x6d\x2c\x20\x2e\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x2c\x20\x22\xe5\xbd\x93\xe5\x89\x8d\xe5\xaf\xb9\xe8\xaf\x9d\xe8\xbf\x90\xe8\xa1\x8c\xe6\x96\xb9\xe5\xbc\x8f\x22\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x6d\x2c\x20\x2e\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x63\x68\x69\x70\x53\x68\x6f\x77\x6e\x28\x6d\x2c\x20\x2e\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x74\x6f\x67\x67\x6c\x65\x28\x6d\x2c\x20\x2e\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x43\x6f\x6d\x70\x61\x63\x74\x20\x6d\x3d\x7b\x6d\x7d\x20\x73\x6c\x6f\x74\x3d\x7b\x31\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x73\x70\x61\x63\x65\x72\x20\x72\x65\x66\x3d\x7b\x73\x70\x61\x63\x65\x72\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x72\x65\x66\x3d\x7b\x75\x73\x61\x67\x65\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x63\x6f\x6d\x70\x6f\x73\x65\x72\x2e\x75\x73\x61\x67\x65\x22\x29\x7d\x20\x66\x6f\x63\x75\x73\x49\x64\x3d\x7b\x4d\x2e\x66\x6f\x63\x75\x73\x4e\x61\x6d\x65\x28\x6d\x2c\x20\x2e\x75\x73\x61\x67\x65\x5f\x61\x6e\x63\x68\x6f\x72\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x74\x65\x78\x74\x28\x6d\x2c\x20\x2e\x75\x73\x61\x67\x65\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x22\xe4\xb8\x8a\xe4\xb8\x8b\xe6\x96\x87\xe4\xb8\x8e\xe6\x9d\xa5\xe6\xba\x90\x22\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x6d\x2c\x20\x2e\x75\x73\x61\x67\x65\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x74\x6f\x67\x67\x6c\x65\x28\x6d\x2c\x20\x2e\x75\x73\x61\x67\x65\x29\x7d\x20\x70\x72\x6f\x67\x72\x65\x73\x73\x3d\x7b\x4d\x2e\x72\x69\x6e\x67\x56\x61\x6c\x75\x65\x28\x6d\x29\x7d\x20\x69\x63\x6f\x6e\x53\x69\x7a\x65\x3d\x7b\x4d\x2e\x72\x69\x6e\x67\x5f\x73\x69\x7a\x65\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x4d\x2e\x6d\x6f\x64\x65\x6c\x48\x69\x6e\x74\x28\x6d\x29\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x33\x32\x30\x7d\x20\x77\x72\x61\x70\x3d\x7b\x2e\x63\x68\x61\x72\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x6f\x5f\x73\x68\x72\x69\x6e\x6b\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x63\x6f\x6d\x70\x6f\x73\x65\x72\x2e\x6d\x6f\x64\x65\x6c\x2e\x74\x6f\x6f\x6c\x74\x69\x70\x22\x29\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x72\x65\x66\x3d\x7b\x6d\x6f\x64\x65\x6c\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x4d\x2e\x62\x75\x74\x74\x6f\x6e\x49\x64\x28\x6d\x2c\x20\x2e\x6d\x6f\x64\x65\x6c\x29\x7d\x20\x66\x6f\x63\x75\x73\x49\x64\x3d\x7b\x4d\x2e\x66\x6f\x63\x75\x73\x4e\x61\x6d\x65\x28\x6d\x2c\x20\x2e\x6d\x6f\x64\x65\x6c\x5f\x61\x6e\x63\x68\x6f\x72\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x74\x65\x78\x74\x28\x6d\x2c\x20\x2e\x6d\x6f\x64\x65\x6c\x29\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x6d\x2c\x20\x2e\x6d\x6f\x64\x65\x6c\x29\x7d\x20\x63\x68\x65\x76\x72\x6f\x6e\x3d\x7b\x74\x72\x75\x65\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x63\x68\x69\x70\x41\x31\x31\x79\x28\x6d\x2c\x20\x2e\x6d\x6f\x64\x65\x6c\x2c\x20\x22\xe9\x80\x89\xe6\x8b\xa9\xe6\xa8\xa1\xe5\x9e\x8b\x22\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x6d\x2c\x20\x2e\x6d\x6f\x64\x65\x6c\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x63\x68\x69\x70\x53\x68\x6f\x77\x6e\x28\x6d\x2c\x20\x2e\x6d\x6f\x64\x65\x6c\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x74\x6f\x67\x67\x6c\x65\x28\x6d\x2c\x20\x2e\x6d\x6f\x64\x65\x6c\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x72\x65\x66\x3d\x7b\x65\x66\x66\x6f\x72\x74\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x4d\x2e\x62\x75\x74\x74\x6f\x6e\x49\x64\x28\x6d\x2c\x20\x2e\x65\x66\x66\x6f\x72\x74\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x74\x65\x78\x74\x28\x6d\x2c\x20\x2e\x65\x66\x66\x6f\x72\x74\x29\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x28\x6d\x2c\x20\x2e\x65\x66\x66\x6f\x72\x74\x29\x7d\x20\x63\x68\x65\x76\x72\x6f\x6e\x3d\x7b\x66\x61\x6c\x73\x65\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x63\x68\x69\x70\x41\x31\x31\x79\x28\x6d\x2c\x20\x2e\x65\x66\x66\x6f\x72\x74\x2c\x20\x22\xe6\x8e\xa8\xe7\x90\x86\xe6\xa1\xa3\xe4\xbd\x8d\x22\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x6d\x2c\x20\x2e\x65\x66\x66\x6f\x72\x74\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x63\x68\x69\x70\x53\x68\x6f\x77\x6e\x28\x6d\x2c\x20\x2e\x65\x66\x66\x6f\x72\x74\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x74\x6f\x67\x67\x6c\x65\x28\x6d\x2c\x20\x2e\x65\x66\x66\x6f\x72\x74\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x72\x65\x66\x3d\x7b\x74\x72\x61\x69\x6c\x69\x6e\x67\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x63\x6f\x6d\x70\x6f\x73\x65\x72\x2e\x74\x72\x61\x69\x6c\x69\x6e\x67\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x74\x72\x61\x69\x6c\x69\x6e\x67\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x4d\x2e\x68\x61\x73\x41\x63\x74\x69\x6f\x6e\x73\x28\x6d\x29\x29\x20\x3c\x41\x63\x74\x69\x6f\x6e\x73\x20\x6d\x3d\x7b\x6d\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x4d\x6f\x64\x65\x6c\x50\x6f\x70\x6f\x76\x65\x72\x20\x6d\x3d\x7b\x6d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x55\x73\x61\x67\x65\x50\x6f\x70\x6f\x76\x65\x72\x20\x6d\x3d\x7b\x6d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x4d\x2e\x43\x6f\x6e\x74\x65\x78\x74\x4d\x65\x6e\x75\x20\x6f\x70\x65\x6e\x3d\x7b\x4d\x2e\x6d\x65\x6e\x75\x4f\x70\x65\x6e\x28\x6d\x2c\x20\x30\x29\x7d\x20\x69\x74\x65\x6d\x73\x3d\x7b\x4d\x2e\x6d\x65\x6e\x75\x52\x6f\x77\x73\x28\x6d\x2c\x20\x30\x29\x7d\x20\x61\x6e\x63\x68\x6f\x72\x3d\x7b\x4d\x2e\x6d\x65\x6e\x75\x41\x6e\x63\x68\x6f\x72\x28\x6d\x2c\x20\x30\x29\x7d\x20\x70\x61\x6e\x65\x6c\x54\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x2e\x6d\x65\x6e\x75\x22\x29\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x4d\x2e\x77\x69\x64\x74\x68\x28\x2e\x61\x74\x74\x61\x63\x68\x6d\x65\x6e\x74\x29\x7d\x20\x6d\x61\x78\x48\x65\x69\x67\x68\x74\x3d\x7b\x6e\x75\x6c\x6c\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x5f\x73\x74\x61\x72\x74\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x4d\x2e\x6d\x65\x6e\x75\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x64\x28\x6d\x2c\x20\x30\x2c\x20\x6f\x29\x7d\x20\x6f\x6e\x53\x65\x6c\x65\x63\x74\x3d\x7b\x7c\x69\x64\x7c\x20\x4d\x2e\x6d\x65\x6e\x75\x53\x65\x6c\x65\x63\x74\x65\x64\x28\x6d\x2c\x20\x30\x2c\x20\x69\x64\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x4d\x2e\x43\x6f\x6e\x74\x65\x78\x74\x4d\x65\x6e\x75\x20\x6f\x70\x65\x6e\x3d\x7b\x4d\x2e\x6d\x65\x6e\x75\x4f\x70\x65\x6e\x28\x6d\x2c\x20\x31\x29\x7d\x20\x69\x74\x65\x6d\x73\x3d\x7b\x4d\x2e\x6d\x65\x6e\x75\x52\x6f\x77\x73\x28\x6d\x2c\x20\x31\x29\x7d\x20\x61\x6e\x63\x68\x6f\x72\x3d\x7b\x4d\x2e\x6d\x65\x6e\x75\x41\x6e\x63\x68\x6f\x72\x28\x6d\x2c\x20\x31\x29\x7d\x20\x70\x61\x6e\x65\x6c\x54\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x2e\x6d\x65\x6e\x75\x22\x29\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x4d\x2e\x77\x69\x64\x74\x68\x28\x2e\x70\x65\x72\x6d\x69\x73\x73\x69\x6f\x6e\x29\x7d\x20\x6d\x61\x78\x48\x65\x69\x67\x68\x74\x3d\x7b\x6e\x75\x6c\x6c\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x5f\x73\x74\x61\x72\x74\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x4d\x2e\x6d\x65\x6e\x75\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x64\x28\x6d\x2c\x20\x31\x2c\x20\x6f\x29\x7d\x20\x6f\x6e\x53\x65\x6c\x65\x63\x74\x3d\x7b\x7c\x69\x64\x7c\x20\x4d\x2e\x6d\x65\x6e\x75\x53\x65\x6c\x65\x63\x74\x65\x64\x28\x6d\x2c\x20\x31\x2c\x20\x69\x64\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x4d\x2e\x43\x6f\x6e\x74\x65\x78\x74\x4d\x65\x6e\x75\x20\x6f\x70\x65\x6e\x3d\x7b\x4d\x2e\x6d\x65\x6e\x75\x4f\x70\x65\x6e\x28\x6d\x2c\x20\x32\x29\x7d\x20\x69\x74\x65\x6d\x73\x3d\x7b\x4d\x2e\x6d\x65\x6e\x75\x52\x6f\x77\x73\x28\x6d\x2c\x20\x32\x29\x7d\x20\x61\x6e\x63\x68\x6f\x72\x3d\x7b\x4d\x2e\x6d\x65\x6e\x75\x41\x6e\x63\x68\x6f\x72\x28\x6d\x2c\x20\x32\x29\x7d\x20\x70\x61\x6e\x65\x6c\x54\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x2e\x6d\x65\x6e\x75\x22\x29\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x4d\x2e\x77\x69\x64\x74\x68\x28\x2e\x65\x78\x65\x63\x75\x74\x69\x6f\x6e\x29\x7d\x20\x6d\x61\x78\x48\x65\x69\x67\x68\x74\x3d\x7b\x6e\x75\x6c\x6c\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x5f\x73\x74\x61\x72\x74\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x4d\x2e\x6d\x65\x6e\x75\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x64\x28\x6d\x2c\x20\x32\x2c\x20\x6f\x29\x7d\x20\x6f\x6e\x53\x65\x6c\x65\x63\x74\x3d\x7b\x7c\x69\x64\x7c\x20\x4d\x2e\x6d\x65\x6e\x75\x53\x65\x6c\x65\x63\x74\x65\x64\x28\x6d\x2c\x20\x32\x2c\x20\x69\x64\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x53\x65\x6e\x64\x20\x2f\x20\x53\x74\x6f\x70\x20\x28\x50\x65\x6e\x63\x69\x6c\x20\x4b\x61\x66\x37\x45\x20\x41\x38\x29\x3a\x20\x6e\x61\x74\x69\x76\x65\x20\x70\x72\x69\x6d\x61\x72\x79\x20\x73\x6d\x20\x69\x63\x6f\x6e\x20\x42\x75\x74\x74\x6f\x6e\x73\x20\x77\x69\x74\x68\x20\x6e\x61\x74\x69\x76\x65\x20\x54\x6f\x6f\x6c\x74\x69\x70\x73\x2e\x20\x53\x74\x6f\x70\x20\x77\x68\x69\x6c\x65\x0a\x2f\x2f\x2f\x20\x61\x20\x74\x75\x72\x6e\x20\x72\x75\x6e\x73\x3b\x20\x53\x65\x6e\x64\x20\x66\x6f\x72\x20\x61\x20\x64\x72\x61\x66\x74\x20\x28\x69\x74\x20\x73\x74\x65\x65\x72\x73\x20\x6f\x72\x20\x71\x75\x65\x75\x65\x73\x2c\x20\x74\x68\x65\x20\x68\x69\x6e\x74\x20\x73\x61\x79\x73\x20\x77\x68\x69\x63\x68\x29\x2e\x0a\x66\x6e\x20\x41\x63\x74\x69\x6f\x6e\x73\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x74\x72\x61\x69\x6c\x69\x6e\x67\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x6f\x5f\x73\x68\x72\x69\x6e\x6b\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x73\x74\x6f\x70\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x22\xe5\x81\x9c\xe6\xad\xa2\xe7\x94\x9f\xe6\x88\x90\x22\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x73\x74\x6f\x70\x22\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x22\xe5\x81\x9c\xe6\xad\xa2\xe7\x94\x9f\xe6\x88\x90\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x70\x72\x69\x6d\x61\x72\x79\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x69\x63\x6f\x6e\x4f\x6e\x6c\x79\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x4e\x61\x6d\x65\x64\x28\x22\x73\x71\x75\x61\x72\x65\x22\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x73\x74\x6f\x70\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6e\x6f\x5f\x73\x68\x72\x69\x6e\x6b\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x73\x65\x6e\x64\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x73\x65\x6e\x64\x2e\x68\x69\x6e\x74\x22\x29\x7d\x20\x74\x65\x78\x74\x3d\x7b\x4d\x2e\x73\x65\x6e\x64\x48\x69\x6e\x74\x28\x6d\x29\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x73\x65\x6e\x64\x2e\x74\x6f\x6f\x6c\x74\x69\x70\x22\x29\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x73\x65\x6e\x64\x22\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x73\x65\x6e\x64\x4c\x61\x62\x65\x6c\x28\x6d\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x70\x72\x69\x6d\x61\x72\x79\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x69\x63\x6f\x6e\x4f\x6e\x6c\x79\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x4e\x61\x6d\x65\x64\x28\x22\x61\x72\x72\x6f\x77\x2d\x75\x70\x22\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x73\x65\x6e\x64\x44\x69\x73\x61\x62\x6c\x65\x64\x28\x6d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x73\x65\x6e\x64\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x4f\x34\x3a\x20\x74\x68\x65\x20\x6d\x6f\x64\x65\x6c\x20\x6c\x69\x73\x74\x20\x28\x70\x72\x6f\x76\x69\x64\x65\x72\x20\x67\x72\x6f\x75\x70\x73\x2c\x20\x72\x6f\x77\x73\x20\x77\x69\x74\x68\x20\x62\x72\x61\x6e\x64\x2c\x20\x63\x6f\x6e\x74\x65\x78\x74\x20\x77\x69\x6e\x64\x6f\x77\x20\x61\x6e\x64\x20\x63\x61\x70\x61\x62\x69\x6c\x69\x74\x69\x65\x73\x29\x2c\x20\x74\x68\x65\x6e\x0a\x2f\x2f\x2f\x20\x74\x68\x65\x20\x72\x65\x61\x73\x6f\x6e\x69\x6e\x67\x20\x63\x6f\x6e\x74\x72\x6f\x6c\x20\x28\x6e\x61\x74\x69\x76\x65\x20\x53\x6c\x69\x64\x65\x72\x20\x77\x69\x74\x68\x20\x6f\x6e\x65\x20\x6d\x61\x72\x6b\x20\x70\x65\x72\x20\x73\x75\x70\x70\x6f\x72\x74\x65\x64\x20\x73\x74\x65\x70\x29\x2c\x20\x74\x68\x65\x6e\x20\x61\x20\x66\x61\x69\x6c\x75\x72\x65\x20\x6c\x69\x6e\x65\x2e\x0a\x66\x6e\x20\x4d\x6f\x64\x65\x6c\x50\x6f\x70\x6f\x76\x65\x72\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x70\x6f\x70\x75\x70\x20\x3d\x20\x72\x65\x66\x28\x57\x2e\x70\x6f\x70\x6f\x76\x65\x72\x2e\x50\x6f\x70\x6f\x76\x65\x72\x52\x65\x73\x75\x6c\x74\x29\x3b\x0a\x20\x20\x20\x20\x6f\x6e\x4d\x6f\x75\x6e\x74\x28\x6b\x65\x65\x70\x50\x6f\x70\x75\x70\x28\x6d\x2c\x20\x30\x2c\x20\x70\x6f\x70\x75\x70\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x50\x6f\x70\x6f\x76\x65\x72\x20\x72\x65\x66\x3d\x7b\x70\x6f\x70\x75\x70\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x4d\x2e\x70\x6f\x70\x75\x70\x4f\x70\x65\x6e\x28\x6d\x2c\x20\x30\x29\x7d\x20\x74\x72\x69\x67\x67\x65\x72\x3d\x7b\x2e\x6d\x61\x6e\x75\x61\x6c\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x5f\x65\x6e\x64\x7d\x20\x61\x6e\x63\x68\x6f\x72\x3d\x7b\x4d\x2e\x70\x6f\x70\x75\x70\x41\x6e\x63\x68\x6f\x72\x28\x6d\x2c\x20\x30\x29\x7d\x20\x6f\x66\x66\x73\x65\x74\x3d\x7b\x2e\x7b\x20\x2e\x73\x74\x61\x74\x69\x63\x20\x3d\x20\x36\x20\x7d\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x4d\x2e\x77\x69\x64\x74\x68\x28\x2e\x6d\x6f\x64\x65\x6c\x29\x7d\x20\x6d\x61\x78\x48\x65\x69\x67\x68\x74\x3d\x7b\x4d\x2e\x68\x65\x69\x67\x68\x74\x28\x2e\x6d\x6f\x64\x65\x6c\x29\x7d\x20\x63\x6c\x6f\x73\x65\x4f\x6e\x45\x73\x63\x61\x70\x65\x3d\x7b\x74\x72\x75\x65\x7d\x20\x63\x6c\x6f\x73\x65\x4f\x6e\x4f\x75\x74\x73\x69\x64\x65\x43\x6c\x69\x63\x6b\x3d\x7b\x74\x72\x75\x65\x7d\x20\x74\x72\x61\x70\x46\x6f\x63\x75\x73\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x6e\x69\x74\x69\x61\x6c\x46\x6f\x63\x75\x73\x3d\x7b\x4d\x2e\x69\x6e\x69\x74\x69\x61\x6c\x46\x6f\x63\x75\x73\x28\x6d\x2c\x20\x30\x29\x7d\x20\x72\x65\x74\x75\x72\x6e\x46\x6f\x63\x75\x73\x3d\x7b\x4d\x2e\x66\x6f\x63\x75\x73\x4e\x61\x6d\x65\x28\x6d\x2c\x20\x2e\x6d\x6f\x64\x65\x6c\x5f\x61\x6e\x63\x68\x6f\x72\x29\x7d\x20\x63\x6f\x6e\x73\x74\x72\x61\x69\x6e\x57\x69\x64\x74\x68\x54\x6f\x56\x69\x65\x77\x70\x6f\x72\x74\x3d\x7b\x74\x72\x75\x65\x7d\x20\x66\x6c\x69\x70\x3d\x7b\x74\x72\x75\x65\x7d\x20\x73\x68\x69\x66\x74\x4d\x61\x69\x6e\x41\x78\x69\x73\x3d\x7b\x74\x72\x75\x65\x7d\x20\x76\x69\x65\x77\x70\x6f\x72\x74\x50\x61\x64\x64\x69\x6e\x67\x3d\x7b\x38\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x77\x72\x61\x70\x70\x65\x72\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x68\x72\x6f\x6d\x65\x20\x3d\x20\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x6d\x65\x6e\x75\x22\x29\x20\x7d\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x4d\x2e\x70\x6f\x70\x75\x70\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x64\x28\x6d\x2c\x20\x30\x2c\x20\x6f\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x6f\x64\x65\x6c\x5f\x62\x6f\x64\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x63\x61\x72\x64\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x6f\x64\x65\x6c\x5f\x63\x61\x72\x64\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x65\x6d\x70\x74\x79\x5f\x74\x65\x78\x74\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x65\x6d\x70\x74\x79\x5f\x62\x6f\x78\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x6d\x6f\x64\x65\x6c\x73\x45\x6d\x70\x74\x79\x28\x6d\x29\x7d\x3e\xe6\x9a\x82\xe6\x97\xa0\xe5\xb7\xb2\xe9\x85\x8d\xe7\xbd\xae\xe6\xa8\xa1\xe5\x9e\x8b\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x73\x65\x74\x74\x69\x6e\x67\x73\x22\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe6\x89\x93\xe5\xbc\x80\x20\x41\x49\x20\xe8\xae\xbe\xe7\xbd\xae\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x73\x65\x74\x74\x69\x6e\x67\x73\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x6f\x70\x65\x6e\x53\x65\x74\x74\x69\x6e\x67\x73\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x4d\x2e\x4d\x6f\x64\x65\x6c\x4c\x69\x73\x74\x20\x6d\x3d\x7b\x6d\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x6c\x69\x73\x74\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x6f\x64\x65\x6c\x73\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x21\x4d\x2e\x6d\x6f\x64\x65\x6c\x73\x45\x6d\x70\x74\x79\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x44\x69\x76\x69\x64\x65\x72\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x72\x65\x61\x73\x6f\x6e\x69\x6e\x67\x5f\x63\x61\x72\x64\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x65\x61\x73\x6f\x6e\x69\x6e\x67\x5f\x63\x61\x72\x64\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x65\x61\x73\x6f\x6e\x69\x6e\x67\x5f\x68\x65\x61\x64\x65\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x65\x66\x66\x6f\x72\x74\x2e\x74\x69\x74\x6c\x65\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x65\x66\x66\x6f\x72\x74\x5f\x74\x69\x74\x6c\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x65\x66\x66\x6f\x72\x74\x5f\x74\x69\x74\x6c\x65\x5f\x62\x6f\x78\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x65\x66\x66\x6f\x72\x74\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x3e\xe6\x8e\xa8\xe7\x90\x86\xe5\xbc\xba\xe5\xba\xa6\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x65\x66\x66\x6f\x72\x74\x2e\x76\x61\x6c\x75\x65\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x65\x66\x66\x6f\x72\x74\x5f\x6e\x61\x6d\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x65\x66\x66\x6f\x72\x74\x5f\x6e\x61\x6d\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x4d\x2e\x65\x66\x66\x6f\x72\x74\x4e\x61\x6d\x65\x28\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x65\x66\x66\x6f\x72\x74\x2e\x61\x72\x65\x61\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x6c\x69\x64\x65\x72\x5f\x61\x72\x65\x61\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x65\x66\x66\x6f\x72\x74\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x65\x66\x66\x6f\x72\x74\x2e\x73\x6c\x69\x64\x65\x72\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x6c\x69\x64\x65\x72\x5f\x62\x6f\x78\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x6c\x69\x64\x65\x72\x20\x66\x6f\x63\x75\x73\x49\x64\x3d\x7b\x4d\x2e\x66\x6f\x63\x75\x73\x4e\x61\x6d\x65\x28\x6d\x2c\x20\x2e\x73\x6c\x69\x64\x65\x72\x29\x7d\x20\x6c\x61\x62\x65\x6c\x54\x65\x78\x74\x3d\x22\xe6\x8e\xa8\xe7\x90\x86\xe6\xa1\xa3\xe4\xbd\x8d\x22\x20\x6d\x69\x6e\x3d\x7b\x30\x7d\x20\x6d\x61\x78\x3d\x7b\x34\x7d\x20\x73\x74\x65\x70\x3d\x7b\x30\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x33\x30\x38\x7d\x20\x74\x72\x61\x63\x6b\x48\x65\x69\x67\x68\x74\x3d\x7b\x33\x7d\x20\x74\x68\x75\x6d\x62\x53\x69\x7a\x65\x3d\x7b\x31\x32\x7d\x20\x76\x61\x6c\x75\x65\x3d\x7b\x4d\x2e\x73\x6c\x69\x64\x65\x72\x56\x61\x6c\x75\x65\x28\x6d\x29\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x76\x7c\x20\x4d\x2e\x65\x66\x66\x6f\x72\x74\x50\x72\x6f\x70\x6f\x73\x65\x64\x28\x6d\x2c\x20\x76\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x4d\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x6d\x2c\x20\x2e\x65\x66\x66\x6f\x72\x74\x29\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x65\x66\x66\x6f\x72\x74\x2e\x73\x6c\x69\x64\x65\x72\x2e\x74\x72\x61\x63\x6b\x22\x29\x7d\x20\x6d\x61\x72\x6b\x73\x3d\x7b\x4d\x2e\x6d\x61\x72\x6b\x73\x28\x6d\x29\x7d\x20\x74\x68\x75\x6d\x62\x56\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x74\x68\x75\x6d\x62\x53\x68\x6f\x77\x6e\x28\x6d\x29\x7d\x20\x6c\x6f\x6f\x6b\x3d\x7b\x2e\x73\x74\x65\x70\x70\x65\x64\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x6c\x69\x64\x65\x72\x7d\x20\x6f\x6e\x4b\x65\x79\x44\x6f\x77\x6e\x3d\x7b\x7c\x65\x7c\x20\x73\x6c\x69\x64\x65\x72\x4b\x65\x79\x28\x6d\x2c\x20\x65\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x65\x72\x72\x6f\x72\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x65\x72\x72\x6f\x72\x5f\x74\x65\x78\x74\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x65\x72\x72\x6f\x72\x5f\x62\x6f\x78\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x4d\x2e\x6d\x6f\x64\x65\x6c\x45\x72\x72\x6f\x72\x28\x6d\x29\x7d\x3e\xe6\x97\xa0\xe6\xb3\x95\xe6\x9b\xb4\xe6\x96\xb0\xef\xbc\x8c\xe8\xaf\xb7\xe9\x87\x8d\xe8\xaf\x95\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x6f\x70\x6f\x76\x65\x72\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x41\x20\x6d\x6f\x64\x65\x6c\x2d\x6c\x69\x73\x74\x20\x72\x6f\x77\x3a\x20\x61\x20\x70\x72\x6f\x76\x69\x64\x65\x72\x20\x68\x65\x61\x64\x65\x72\x20\x6f\x72\x20\x61\x20\x6d\x6f\x64\x65\x6c\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x4c\x69\x73\x74\x52\x6f\x77\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x73\x69\x7a\x65\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6c\x69\x73\x74\x5f\x72\x6f\x77\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x4d\x2e\x69\x73\x48\x65\x61\x64\x65\x72\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x29\x20\x3c\x50\x72\x6f\x76\x69\x64\x65\x72\x52\x6f\x77\x20\x6d\x3d\x7b\x6d\x7d\x20\x69\x6e\x64\x65\x78\x3d\x7b\x69\x6e\x64\x65\x78\x7d\x20\x2f\x3e\x20\x65\x6c\x73\x65\x20\x3c\x4d\x6f\x64\x65\x6c\x52\x6f\x77\x20\x6d\x3d\x7b\x6d\x7d\x20\x69\x6e\x64\x65\x78\x3d\x7b\x69\x6e\x64\x65\x78\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x41\x20\x70\x72\x6f\x76\x69\x64\x65\x72\x20\x67\x72\x6f\x75\x70\x20\x68\x65\x61\x64\x65\x72\x20\x28\x4f\x34\x29\x3a\x20\x63\x68\x65\x76\x72\x6f\x6e\x2c\x20\x62\x72\x61\x6e\x64\x2c\x20\x6e\x61\x6d\x65\x3b\x20\x61\x20\x70\x72\x65\x73\x73\x20\x66\x6f\x6c\x64\x73\x20\x74\x68\x65\x20\x67\x72\x6f\x75\x70\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x50\x72\x6f\x76\x69\x64\x65\x72\x52\x6f\x77\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x73\x69\x7a\x65\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x2f\x2f\x20\x52\x6f\x77\x73\x20\x6f\x75\x74\x6c\x69\x76\x65\x20\x74\x68\x65\x20\x70\x72\x6f\x6a\x65\x63\x74\x69\x6f\x6e\x20\x74\x68\x65\x79\x20\x77\x65\x72\x65\x20\x62\x75\x69\x6c\x74\x20\x66\x72\x6f\x6d\x20\x28\x75\x6e\x63\x68\x61\x6e\x67\x65\x64\x20\x72\x6f\x77\x73\x20\x61\x72\x65\x20\x6b\x65\x70\x74\x29\x3a\x20\x6f\x77\x6e\x20\x74\x68\x65\x20\x74\x65\x78\x74\x2e\x0a\x20\x20\x20\x20\x76\x61\x72\x20\x6e\x61\x6d\x65\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x73\x69\x67\x6e\x61\x6c\x28\x4d\x2e\x70\x72\x6f\x76\x69\x64\x65\x72\x4e\x61\x6d\x65\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x70\x72\x6f\x76\x69\x64\x65\x72\x22\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x6e\x61\x6d\x65\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x74\x6f\x67\x67\x6c\x65\x50\x72\x6f\x76\x69\x64\x65\x72\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x67\x72\x6f\x75\x70\x5f\x72\x6f\x77\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x4d\x2e\x70\x72\x6f\x76\x69\x64\x65\x72\x43\x68\x65\x76\x72\x6f\x6e\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x67\x72\x6f\x75\x70\x5f\x63\x68\x65\x76\x72\x6f\x6e\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x42\x72\x61\x6e\x64\x4d\x61\x72\x6b\x20\x62\x72\x61\x6e\x64\x3d\x7b\x4d\x2e\x70\x72\x6f\x76\x69\x64\x65\x72\x42\x72\x61\x6e\x64\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x7d\x20\x6e\x61\x6d\x65\x3d\x7b\x6e\x61\x6d\x65\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x67\x72\x6f\x75\x70\x5f\x6e\x61\x6d\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x67\x72\x6f\x75\x70\x5f\x6e\x61\x6d\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x6e\x61\x6d\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x41\x20\x6d\x6f\x64\x65\x6c\x20\x72\x6f\x77\x20\x28\x4f\x34\x29\x3a\x20\x6d\x61\x72\x6b\x65\x72\x20\x28\xe2\x80\xba\x20\x66\x6f\x72\x20\x74\x68\x65\x20\x63\x75\x72\x72\x65\x6e\x74\x20\x6d\x6f\x64\x65\x6c\x29\x2c\x20\x62\x72\x61\x6e\x64\x2c\x20\x49\x44\x2c\x20\x63\x6f\x6e\x74\x65\x78\x74\x20\x77\x69\x6e\x64\x6f\x77\x2c\x20\x72\x65\x61\x73\x6f\x6e\x69\x6e\x67\x20\x61\x6e\x64\x0a\x2f\x2f\x2f\x20\x76\x69\x73\x69\x6f\x6e\x20\x63\x61\x70\x61\x62\x69\x6c\x69\x74\x69\x65\x73\x2c\x20\x65\x61\x63\x68\x20\x77\x69\x74\x68\x20\x69\x74\x73\x20\x6e\x61\x74\x69\x76\x65\x20\x54\x6f\x6f\x6c\x74\x69\x70\x3b\x20\x74\x68\x65\x20\x72\x6f\x77\x27\x73\x20\x64\x65\x74\x61\x69\x6c\x73\x20\x69\x6e\x20\x61\x20\x32\x38\x34\x20\x6e\x61\x74\x69\x76\x65\x20\x54\x6f\x6f\x6c\x74\x69\x70\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x4d\x6f\x64\x65\x6c\x52\x6f\x77\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x2c\x20\x69\x6e\x64\x65\x78\x3a\x20\x75\x73\x69\x7a\x65\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x72\x6f\x77\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x4d\x2e\x6d\x6f\x64\x65\x6c\x52\x6f\x77\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x29\x3b\x0a\x20\x20\x20\x20\x2f\x2f\x20\x52\x6f\x77\x73\x20\x6f\x75\x74\x6c\x69\x76\x65\x20\x74\x68\x65\x20\x70\x72\x6f\x6a\x65\x63\x74\x69\x6f\x6e\x20\x74\x68\x65\x79\x20\x77\x65\x72\x65\x20\x62\x75\x69\x6c\x74\x20\x66\x72\x6f\x6d\x20\x28\x75\x6e\x63\x68\x61\x6e\x67\x65\x64\x20\x72\x6f\x77\x73\x20\x61\x72\x65\x20\x6b\x65\x70\x74\x29\x3a\x20\x6f\x77\x6e\x20\x74\x68\x65\x20\x74\x65\x78\x74\x2e\x0a\x20\x20\x20\x20\x76\x61\x72\x20\x69\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x73\x69\x67\x6e\x61\x6c\x28\x4d\x2e\x6d\x6f\x64\x65\x6c\x52\x6f\x77\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x2e\x69\x64\x29\x3b\x0a\x20\x20\x20\x20\x76\x61\x72\x20\x62\x61\x73\x65\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x73\x69\x67\x6e\x61\x6c\x28\x4d\x2e\x6d\x6f\x64\x65\x6c\x52\x6f\x77\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x2e\x62\x61\x73\x65\x6e\x61\x6d\x65\x29\x3b\x0a\x20\x20\x20\x20\x76\x61\x72\x20\x64\x65\x74\x61\x69\x6c\x73\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x73\x69\x67\x6e\x61\x6c\x28\x4d\x2e\x6d\x6f\x64\x65\x6c\x52\x6f\x77\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x2e\x64\x65\x73\x63\x72\x69\x70\x74\x69\x6f\x6e\x29\x3b\x0a\x20\x20\x20\x20\x76\x61\x72\x20\x63\x6f\x6e\x74\x65\x78\x74\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x3d\x20\x73\x69\x67\x6e\x61\x6c\x28\x4d\x2e\x6d\x6f\x64\x65\x6c\x52\x6f\x77\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x2e\x63\x6f\x6e\x74\x65\x78\x74\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x64\x65\x74\x61\x69\x6c\x73\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x32\x38\x34\x7d\x20\x77\x72\x61\x70\x3d\x7b\x2e\x77\x6f\x72\x64\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x72\x69\x67\x68\x74\x7d\x20\x6f\x66\x66\x73\x65\x74\x3d\x7b\x38\x7d\x20\x63\x6c\x6f\x73\x65\x4f\x6e\x45\x73\x63\x61\x70\x65\x3d\x7b\x66\x61\x6c\x73\x65\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x72\x6f\x77\x5f\x68\x69\x6e\x74\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x74\x72\x69\x67\x67\x65\x72\x20\x3d\x20\x2e\x7b\x20\x2e\x73\x74\x79\x6c\x65\x20\x3d\x20\x53\x2e\x72\x6f\x77\x5f\x74\x72\x69\x67\x67\x65\x72\x20\x7d\x2c\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x64\x65\x74\x61\x69\x6c\x73\x22\x29\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x20\x66\x6f\x63\x75\x73\x49\x64\x3d\x7b\x4d\x2e\x72\x6f\x77\x46\x6f\x63\x75\x73\x49\x64\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x6f\x70\x74\x69\x6f\x6e\x22\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x64\x65\x74\x61\x69\x6c\x73\x7d\x20\x61\x31\x31\x79\x44\x65\x73\x63\x72\x69\x70\x74\x69\x6f\x6e\x3d\x7b\x64\x65\x74\x61\x69\x6c\x73\x7d\x20\x73\x65\x6c\x65\x63\x74\x65\x64\x3d\x7b\x72\x6f\x77\x2e\x73\x65\x6c\x65\x63\x74\x65\x64\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x21\x72\x6f\x77\x2e\x63\x68\x6f\x6f\x73\x61\x62\x6c\x65\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x63\x68\x6f\x6f\x73\x65\x4d\x6f\x64\x65\x6c\x28\x6d\x2c\x20\x69\x6e\x64\x65\x78\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x4d\x6f\x64\x65\x6c\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x73\x65\x6c\x65\x63\x74\x65\x64\x20\x3d\x20\x72\x6f\x77\x2e\x73\x65\x6c\x65\x63\x74\x65\x64\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x4d\x2e\x6d\x61\x72\x6b\x65\x72\x49\x64\x28\x6d\x2c\x20\x72\x6f\x77\x2e\x73\x65\x6c\x65\x63\x74\x65\x64\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x61\x72\x6b\x65\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x72\x6f\x77\x2e\x73\x65\x6c\x65\x63\x74\x65\x64\x29\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x61\x72\x6b\x65\x72\x5f\x74\x65\x78\x74\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x6d\x61\x72\x6b\x65\x72\x5f\x74\x65\x78\x74\x5f\x62\x6f\x78\x7d\x3e\xe2\x80\xba\x3c\x2f\x74\x65\x78\x74\x3e\x20\x65\x6c\x73\x65\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6d\x61\x72\x6b\x65\x72\x5f\x64\x6f\x74\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x42\x72\x61\x6e\x64\x4d\x61\x72\x6b\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x6c\x6f\x67\x6f\x22\x29\x7d\x20\x62\x72\x61\x6e\x64\x3d\x7b\x72\x6f\x77\x2e\x62\x72\x61\x6e\x64\x7d\x20\x6e\x61\x6d\x65\x3d\x7b\x62\x61\x73\x65\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x6e\x61\x6d\x65\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x4d\x6f\x64\x65\x6c\x4e\x61\x6d\x65\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6f\x66\x66\x20\x3d\x20\x21\x72\x6f\x77\x2e\x65\x6e\x61\x62\x6c\x65\x64\x20\x7d\x29\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x6d\x6f\x64\x65\x6c\x5f\x6e\x61\x6d\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x69\x64\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x63\x6f\x6e\x74\x65\x78\x74\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x4d\x6f\x64\x65\x6c\x43\x6f\x6e\x74\x65\x78\x74\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6f\x66\x66\x20\x3d\x20\x21\x72\x6f\x77\x2e\x65\x6e\x61\x62\x6c\x65\x64\x20\x7d\x29\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x63\x6f\x6e\x74\x65\x78\x74\x5f\x62\x6f\x78\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x77\x20\x3d\x20\x4d\x2e\x63\x6f\x6e\x74\x65\x78\x74\x57\x69\x64\x74\x68\x28\x6d\x29\x20\x7d\x29\x7d\x3e\x7b\x63\x6f\x6e\x74\x65\x78\x74\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x4d\x2e\x72\x65\x61\x73\x6f\x6e\x69\x6e\x67\x48\x69\x6e\x74\x28\x72\x6f\x77\x2e\x72\x65\x61\x73\x6f\x6e\x69\x6e\x67\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x61\x70\x61\x62\x69\x6c\x69\x74\x79\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x74\x72\x69\x67\x67\x65\x72\x20\x3d\x20\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x72\x65\x61\x73\x6f\x6e\x69\x6e\x67\x22\x29\x2c\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x72\x65\x61\x73\x6f\x6e\x69\x6e\x67\x2e\x74\x6f\x6f\x6c\x74\x69\x70\x22\x29\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x4e\x61\x6d\x65\x64\x28\x22\x62\x72\x61\x69\x6e\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x43\x61\x70\x61\x62\x69\x6c\x69\x74\x79\x49\x63\x6f\x6e\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6f\x6e\x20\x3d\x20\x72\x6f\x77\x2e\x65\x6e\x61\x62\x6c\x65\x64\x20\x61\x6e\x64\x20\x72\x6f\x77\x2e\x72\x65\x61\x73\x6f\x6e\x69\x6e\x67\x20\x7d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x4d\x2e\x76\x69\x73\x69\x6f\x6e\x48\x69\x6e\x74\x28\x72\x6f\x77\x2e\x76\x69\x73\x69\x6f\x6e\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x61\x70\x61\x62\x69\x6c\x69\x74\x79\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x74\x72\x69\x67\x67\x65\x72\x20\x3d\x20\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x6d\x6f\x64\x65\x6c\x2e\x76\x69\x73\x69\x6f\x6e\x22\x29\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x4d\x2e\x76\x69\x73\x69\x6f\x6e\x47\x6c\x79\x70\x68\x28\x72\x6f\x77\x2e\x76\x69\x73\x69\x6f\x6e\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x43\x61\x70\x61\x62\x69\x6c\x69\x74\x79\x49\x63\x6f\x6e\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6f\x6e\x20\x3d\x20\x72\x6f\x77\x2e\x65\x6e\x61\x62\x6c\x65\x64\x20\x61\x6e\x64\x20\x72\x6f\x77\x2e\x76\x69\x73\x69\x6f\x6e\x20\x7d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x42\x72\x61\x6e\x64\x20\x6d\x61\x72\x6b\x20\x28\x31\x36\x29\x3a\x20\x74\x68\x65\x20\x62\x72\x61\x6e\x64\x20\x67\x6c\x79\x70\x68\x20\x6f\x6e\x20\x61\x20\x72\x6f\x75\x6e\x64\x65\x64\x20\x74\x69\x6c\x65\x2c\x20\x6f\x72\x20\x74\x68\x65\x20\x6e\x61\x6d\x65\x27\x73\x20\x66\x69\x72\x73\x74\x20\x63\x68\x61\x72\x61\x63\x74\x65\x72\x2e\x0a\x70\x75\x62\x20\x66\x6e\x20\x42\x72\x61\x6e\x64\x4d\x61\x72\x6b\x28\x62\x72\x61\x6e\x64\x3a\x20\x3f\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x2c\x20\x6e\x61\x6d\x65\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x72\x61\x6e\x64\x5f\x74\x69\x6c\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x62\x72\x61\x6e\x64\x20\x21\x3d\x20\x6e\x75\x6c\x6c\x29\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x62\x72\x61\x6e\x64\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x72\x61\x6e\x64\x5f\x67\x6c\x79\x70\x68\x7d\x20\x2f\x3e\x20\x65\x6c\x73\x65\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x62\x72\x61\x6e\x64\x5f\x69\x6e\x69\x74\x69\x61\x6c\x7d\x3e\x7b\x4d\x2e\x69\x6e\x69\x74\x69\x61\x6c\x28\x6e\x61\x6d\x65\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x4f\x36\x3a\x20\x68\x65\x61\x64\x20\x28\x6c\x61\x62\x65\x6c\x20\xc2\xb7\x20\x75\x73\x65\x64\x20\x2f\x20\x6c\x69\x6d\x69\x74\x29\x2c\x20\x74\x68\x65\x20\x6e\x61\x74\x69\x76\x65\x20\x73\x65\x67\x6d\x65\x6e\x74\x65\x64\x20\x62\x61\x72\x2c\x20\x61\x20\x6c\x65\x67\x65\x6e\x64\x20\x72\x6f\x77\x20\x70\x65\x72\x20\x73\x6f\x75\x72\x63\x65\x2c\x20\x61\x20\x73\x65\x70\x61\x72\x61\x74\x6f\x72\x0a\x2f\x2f\x2f\x20\x61\x6e\x64\x20\x74\x68\x65\x20\x6e\x61\x74\x69\x76\x65\x20\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x20\x73\x6d\x20\x63\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x20\x42\x75\x74\x74\x6f\x6e\x20\x28\x77\x69\x74\x68\x20\x69\x74\x73\x20\x72\x65\x61\x73\x6f\x6e\x20\x69\x6e\x20\x61\x20\x6e\x61\x74\x69\x76\x65\x20\x54\x6f\x6f\x6c\x74\x69\x70\x29\x2e\x0a\x66\x6e\x20\x55\x73\x61\x67\x65\x50\x6f\x70\x6f\x76\x65\x72\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x70\x6f\x70\x75\x70\x20\x3d\x20\x72\x65\x66\x28\x57\x2e\x70\x6f\x70\x6f\x76\x65\x72\x2e\x50\x6f\x70\x6f\x76\x65\x72\x52\x65\x73\x75\x6c\x74\x29\x3b\x0a\x20\x20\x20\x20\x6f\x6e\x4d\x6f\x75\x6e\x74\x28\x6b\x65\x65\x70\x50\x6f\x70\x75\x70\x28\x6d\x2c\x20\x31\x2c\x20\x70\x6f\x70\x75\x70\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x50\x6f\x70\x6f\x76\x65\x72\x20\x72\x65\x66\x3d\x7b\x70\x6f\x70\x75\x70\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x4d\x2e\x70\x6f\x70\x75\x70\x4f\x70\x65\x6e\x28\x6d\x2c\x20\x31\x29\x7d\x20\x74\x72\x69\x67\x67\x65\x72\x3d\x7b\x2e\x6d\x61\x6e\x75\x61\x6c\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x5f\x73\x74\x61\x72\x74\x7d\x20\x61\x6e\x63\x68\x6f\x72\x3d\x7b\x4d\x2e\x70\x6f\x70\x75\x70\x41\x6e\x63\x68\x6f\x72\x28\x6d\x2c\x20\x31\x29\x7d\x20\x6f\x66\x66\x73\x65\x74\x3d\x7b\x2e\x7b\x20\x2e\x73\x74\x61\x74\x69\x63\x20\x3d\x20\x36\x20\x7d\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x4d\x2e\x77\x69\x64\x74\x68\x28\x2e\x75\x73\x61\x67\x65\x29\x7d\x20\x6d\x61\x78\x48\x65\x69\x67\x68\x74\x3d\x7b\x4d\x2e\x68\x65\x69\x67\x68\x74\x28\x2e\x75\x73\x61\x67\x65\x29\x7d\x20\x63\x6c\x6f\x73\x65\x4f\x6e\x45\x73\x63\x61\x70\x65\x3d\x7b\x74\x72\x75\x65\x7d\x20\x63\x6c\x6f\x73\x65\x4f\x6e\x4f\x75\x74\x73\x69\x64\x65\x43\x6c\x69\x63\x6b\x3d\x7b\x74\x72\x75\x65\x7d\x20\x74\x72\x61\x70\x46\x6f\x63\x75\x73\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x6e\x69\x74\x69\x61\x6c\x46\x6f\x63\x75\x73\x3d\x7b\x4d\x2e\x69\x6e\x69\x74\x69\x61\x6c\x46\x6f\x63\x75\x73\x28\x6d\x2c\x20\x31\x29\x7d\x20\x72\x65\x74\x75\x72\x6e\x46\x6f\x63\x75\x73\x3d\x7b\x4d\x2e\x66\x6f\x63\x75\x73\x4e\x61\x6d\x65\x28\x6d\x2c\x20\x2e\x75\x73\x61\x67\x65\x5f\x61\x6e\x63\x68\x6f\x72\x29\x7d\x20\x63\x6f\x6e\x73\x74\x72\x61\x69\x6e\x57\x69\x64\x74\x68\x54\x6f\x56\x69\x65\x77\x70\x6f\x72\x74\x3d\x7b\x74\x72\x75\x65\x7d\x20\x66\x6c\x69\x70\x3d\x7b\x74\x72\x75\x65\x7d\x20\x73\x68\x69\x66\x74\x4d\x61\x69\x6e\x41\x78\x69\x73\x3d\x7b\x74\x72\x75\x65\x7d\x20\x76\x69\x65\x77\x70\x6f\x72\x74\x50\x61\x64\x64\x69\x6e\x67\x3d\x7b\x38\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x77\x72\x61\x70\x70\x65\x72\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x68\x72\x6f\x6d\x65\x20\x3d\x20\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x75\x73\x61\x67\x65\x2e\x6d\x65\x6e\x75\x22\x29\x20\x7d\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x4d\x2e\x70\x6f\x70\x75\x70\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x64\x28\x6d\x2c\x20\x31\x2c\x20\x6f\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x62\x6f\x64\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x73\x63\x72\x6f\x6c\x6c\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x2e\x7b\x20\x2e\x73\x74\x79\x6c\x65\x20\x3d\x20\x53\x2e\x75\x73\x61\x67\x65\x5f\x63\x6f\x6e\x74\x65\x6e\x74\x20\x7d\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x4d\x2e\x75\x73\x61\x67\x65\x53\x68\x6f\x77\x6e\x28\x6d\x29\x29\x20\x3c\x55\x73\x61\x67\x65\x42\x6f\x64\x79\x20\x6d\x3d\x7b\x6d\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x53\x63\x72\x6f\x6c\x6c\x41\x72\x65\x61\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x6f\x70\x6f\x76\x65\x72\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x66\x6e\x20\x55\x73\x61\x67\x65\x42\x6f\x64\x79\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x75\x73\x61\x67\x65\x2e\x73\x75\x6d\x6d\x61\x72\x79\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x68\x65\x61\x64\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x63\x61\x70\x74\x69\x6f\x6e\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x63\x61\x70\x74\x69\x6f\x6e\x5f\x62\x6f\x78\x7d\x3e\x7b\x4d\x2e\x75\x73\x61\x67\x65\x43\x61\x70\x74\x69\x6f\x6e\x28\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x74\x6f\x74\x61\x6c\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x74\x6f\x74\x61\x6c\x5f\x62\x6f\x78\x7d\x3e\x7b\x4d\x2e\x75\x73\x61\x67\x65\x54\x6f\x74\x61\x6c\x28\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x50\x72\x6f\x67\x72\x65\x73\x73\x53\x65\x67\x6d\x65\x6e\x74\x73\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x75\x73\x61\x67\x65\x2e\x74\x72\x61\x63\x6b\x22\x29\x7d\x20\x73\x65\x67\x6d\x65\x6e\x74\x73\x3d\x7b\x4d\x2e\x75\x73\x61\x67\x65\x53\x65\x67\x6d\x65\x6e\x74\x73\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x63\x6f\x6c\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x6c\x65\x67\x65\x6e\x64\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x66\x6f\x72\x20\x28\x4d\x2e\x75\x73\x61\x67\x65\x50\x61\x72\x74\x73\x28\x6d\x29\x29\x20\x7c\x70\x61\x72\x74\x7c\x20\x3c\x72\x6f\x77\x20\x6b\x65\x79\x3d\x7b\x70\x61\x72\x74\x2e\x69\x6e\x64\x65\x78\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x72\x6f\x77\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x55\x73\x61\x67\x65\x53\x77\x61\x74\x63\x68\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x74\x6f\x6e\x65\x20\x3d\x20\x70\x61\x72\x74\x2e\x74\x6f\x6e\x65\x20\x7d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x6e\x61\x6d\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x6e\x61\x6d\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x4d\x2e\x75\x73\x61\x67\x65\x50\x61\x72\x74\x4e\x61\x6d\x65\x28\x70\x61\x72\x74\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x75\x73\x61\x67\x65\x2e\x70\x61\x72\x74\x2e\x76\x61\x6c\x75\x65\x22\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x76\x61\x6c\x75\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x76\x61\x6c\x75\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x4d\x2e\x75\x73\x61\x67\x65\x50\x61\x72\x74\x56\x61\x6c\x75\x65\x28\x70\x61\x72\x74\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x44\x69\x76\x69\x64\x65\x72\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x72\x6f\x77\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x75\x73\x61\x67\x65\x5f\x61\x63\x74\x69\x6f\x6e\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x52\x75\x6e\x6e\x69\x6e\x67\x28\x6d\x29\x29\x20\x3c\x43\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x43\x61\x6e\x63\x65\x6c\x20\x6d\x3d\x7b\x6d\x7d\x20\x2f\x3e\x20\x65\x6c\x73\x65\x20\x3c\x43\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x53\x74\x61\x72\x74\x20\x6d\x3d\x7b\x6d\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x72\x6f\x77\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x63\x6f\x6c\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\x54\x68\x65\x20\x75\x73\x61\x67\x65\x20\x70\x6f\x70\x6f\x76\x65\x72\x27\x73\x20\x61\x63\x74\x69\x6f\x6e\x2e\x20\x42\x6f\x74\x68\x20\x66\x6f\x72\x6d\x73\x20\x63\x61\x72\x72\x79\x20\x74\x68\x65\x20\x73\x61\x6d\x65\x20\x66\x6f\x63\x75\x73\x49\x64\x3a\x20\x69\x74\x20\x69\x73\x20\x74\x68\x65\x20\x70\x6f\x70\x6f\x76\x65\x72\x27\x73\x20\x66\x69\x72\x73\x74\x20\x66\x6f\x63\x75\x73\x0a\x2f\x2f\x2f\x20\x28\x60\x69\x6e\x69\x74\x69\x61\x6c\x46\x6f\x63\x75\x73\x60\x29\x20\x77\x68\x69\x6c\x65\x20\x69\x74\x20\x63\x61\x6e\x20\x61\x63\x74\x2e\x20\x49\x74\x73\x20\x72\x65\x61\x73\x6f\x6e\x20\x54\x6f\x6f\x6c\x74\x69\x70\x20\x69\x73\x20\x61\x20\x70\x61\x73\x73\x69\x76\x65\x20\x68\x69\x6e\x74\x20\x61\x6e\x64\x20\x73\x74\x61\x79\x73\x20\x6f\x75\x74\x20\x6f\x66\x20\x74\x68\x65\x20\x45\x73\x63\x61\x70\x65\x20\x6f\x72\x64\x65\x72\x2c\x0a\x2f\x2f\x2f\x20\x73\x6f\x20\x6f\x6e\x65\x20\x45\x73\x63\x61\x70\x65\x20\x63\x6c\x6f\x73\x65\x73\x20\x74\x68\x65\x20\x70\x6f\x70\x6f\x76\x65\x72\x20\x61\x6c\x73\x6f\x20\x77\x68\x69\x6c\x65\x20\x74\x68\x65\x20\x66\x6f\x63\x75\x73\x65\x64\x20\x61\x63\x74\x69\x6f\x6e\x20\x73\x68\x6f\x77\x73\x20\x69\x74\x73\x20\x68\x69\x6e\x74\x2e\x0a\x66\x6e\x20\x43\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x43\x61\x6e\x63\x65\x6c\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x52\x65\x61\x73\x6f\x6e\x28\x6d\x29\x7d\x20\x63\x6c\x6f\x73\x65\x4f\x6e\x45\x73\x63\x61\x70\x65\x3d\x7b\x66\x61\x6c\x73\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x66\x6f\x63\x75\x73\x49\x64\x3d\x7b\x4d\x2e\x66\x6f\x63\x75\x73\x4e\x61\x6d\x65\x28\x6d\x2c\x20\x2e\x75\x73\x61\x67\x65\x5f\x61\x63\x74\x69\x6f\x6e\x29\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x75\x73\x61\x67\x65\x2e\x63\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x2e\x63\x61\x6e\x63\x65\x6c\x22\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe5\x8f\x96\xe6\xb6\x88\xe5\x8e\x8b\xe7\xbc\xa9\x22\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x52\x65\x61\x73\x6f\x6e\x28\x6d\x29\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x78\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x63\x61\x6e\x63\x65\x6c\x43\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x43\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x53\x74\x61\x72\x74\x28\x6d\x3a\x20\x2a\x4d\x2e\x56\x69\x65\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x52\x65\x61\x73\x6f\x6e\x28\x6d\x29\x7d\x20\x63\x6c\x6f\x73\x65\x4f\x6e\x45\x73\x63\x61\x70\x65\x3d\x7b\x66\x61\x6c\x73\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x66\x6f\x63\x75\x73\x49\x64\x3d\x7b\x4d\x2e\x66\x6f\x63\x75\x73\x4e\x61\x6d\x65\x28\x6d\x2c\x20\x2e\x75\x73\x61\x67\x65\x5f\x61\x63\x74\x69\x6f\x6e\x29\x7d\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x2e\x73\x70\x61\x63\x65\x2e\x69\x64\x28\x22\x61\x69\x2e\x75\x73\x61\x67\x65\x2e\x63\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x2e\x73\x74\x61\x72\x74\x22\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe5\x8e\x8b\xe7\xbc\xa9\xe4\xb8\x8a\xe4\xb8\x8b\xe6\x96\x87\x22\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x4d\x2e\x63\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x52\x65\x61\x73\x6f\x6e\x28\x6d\x29\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x4d\x2e\x67\x6c\x79\x70\x68\x4e\x61\x6d\x65\x64\x28\x22\x66\x6f\x6c\x64\x2d\x76\x65\x72\x74\x69\x63\x61\x6c\x22\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x21\x4d\x2e\x63\x61\x6e\x43\x6f\x6d\x70\x61\x63\x74\x28\x6d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x4d\x2e\x73\x74\x61\x72\x74\x43\x6f\x6d\x70\x61\x63\x74\x69\x6f\x6e\x28\x6d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"S " = S, }) else void;

//# yix-map-data [[2226,2221],[11848,2885],[74277,7151],[88334,8300],[121036,11039],[125271,11353],[132368,12170],[160506,14596],[165224,15054],[176758,16030],[192582,17488],[198950,17898]]

//# yix-map ai_composer_controls.yix
