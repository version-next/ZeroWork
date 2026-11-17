// GENERATED FILE, do not edit: generated from rows.yix; after editing the source run `zig build gen-yix` (yix-lsp regenerates it on save).
//! 设置面板正文的行组件（P3 3e 定稿；ARCHITECTURE_PLAN §4.5 `components/rows.yix`）。
//!
//! 后续面板包的 API（参数签名）：
//!
//!     Pane(vm: *m.ViewModel, pane: *const m.PaneSpec, children: View)
//!     ToggleRow(vm: *m.ViewModel, pane: *const m.PaneSpec, row: m.Row)       // 开关
//!     InputRow(vm: *m.ViewModel, pane: *const m.PaneSpec, row: m.Row)        // 文本 / 数字，单位后缀、校验提示
//!     SelectRow(vm: *m.ViewModel, pane: *const m.PaneSpec, row: m.Row, options: []const W.SelectOption)
//!     CustomSelectRow(vm, pane, row, options, noteId: []const u8, note: []const u8, placeholder: []const u8)  // 选项里有 `custom_choice`：原地编辑
//!     DirectoryRow(vm: *m.ViewModel, pane: *const m.PaneSpec, row: m.Row)    // 目录按钮（宿主的系统目录面板）
//!     InfoRow(vm: *m.ViewModel, pane: *const m.PaneSpec, row: m.Row)         // 只读值；路径单行省略 + 全文提示
//!     ActionRow(vm: *m.ViewModel, pane: *const m.PaneSpec, row: m.Row, icon: ?ui.SvgAsset)  // 按钮 → `Intent.runCommand`
//!
//! 约定：
//! - 文案、test_id、焦点标识、单位、依赖、搜索词都在 `model/pane_fields.zig` 的条目里（`m.fields.<分类>.<字段>`），
//!   面板文件只摆顺序、选控件；行组件不拼字符串。id 落在与旧实现相同的语义节点上：行根 `settings.row.<key>`，
//!   开关与按钮在控件根（`testId`），输入框在 `input_container`、选择框在 `trigger`（`parts`），校验提示 `settings.error.<key>`，
//!   帮助按钮 `settings.help.<key>`、提示面板 `….tooltip`、标签下的说明 `settings.help.content.<key>`。
//! - 控件全部是 zenit 原生（`W.Switch` / `W.Input` / `W.Select` / `W.Button` / `W.Tooltip`），不覆盖几何、字体与颜色；
//!   样式只在 `../styles.yss`，颜色只用 token。
//! - 控件是“只读值 + 回调”：值来自 view-model 选择器（按 `revision` 跟随草稿），改动经 `vm.dispatch(Intent)` 上行，
//!   由 Controller 裁决；改一个字段只让读到它的选择器重算，同页其它节点不动（没有整页重挂）。
//! - 行的显示（子页面 / 搜索过滤）与“面板最后一行”（它下面没有分隔线）在内容页挂载时定下（`vm.rowShown` / `vm.rowLast`）。
//! - 横切行为：帮助提示、路径 / 目录全文提示与选择框下拉的开合是 view-model 的 `popup`（整窗 Escape 先收起它）；焦点在输入框上时，
//!   整窗 Escape 撤回它的原文并清焦点（宿主按真实焦点的 test_id 认出它，`ViewModel.consumeEscape`）；输入框带 `focusId`（`focus:field:<test_id>`，`locate_problem` 与 `focusRestore` 用）。
const ui = @import("ui");
/// 浮层规则的唯一来源（OverlayHost `panel`）。
const O = @import("../../../../shared/ui/overlay/overlay_host.zig");
const W = ui.widgets;
const m = @import("../../model/view_model.zig");
const S = @import("../_styles.yss.zig");
const K = @import("../panes/_keys.yss.zig");

fn send(vm: *m.ViewModel, intent: m.Intent) void {
    vm.dispatch(intent);
}
fn shown(vm: *m.ViewModel, pane: *const m.PaneSpec, row: m.Row) bool {
    return vm.rowShown(pane, row) and vm.infoShown(row);
}
fn last(vm: *m.ViewModel, pane: *const m.PaneSpec, row: m.Row) bool {
    return vm.rowLast(pane, row);
}
fn label(row: m.Row) []const u8 {
    return row.label;
}
fn help(row: m.Row) []const u8 {
    return row.help;
}
fn tipHelp(row: m.Row) bool {
    return row.help.len != 0 and !row.inline_help;
}
fn inlineHelp(row: m.Row) bool {
    return row.help.len != 0 and row.inline_help;
}
fn rowId(row: m.Row) []const u8 {
    return row.ids.row;
}
fn fieldId(row: m.Row) []const u8 {
    return row.ids.field;
}
fn errorId(row: m.Row) []const u8 {
    return row.ids.err;
}
fn helpId(row: m.Row) []const u8 {
    return row.ids.help;
}
fn helpTipId(row: m.Row) []const u8 {
    return row.ids.help_tip;
}
fn helpTextId(row: m.Row) []const u8 {
    return row.ids.help_text;
}
fn focusId(row: m.Row) []const u8 {
    return row.ids.focus;
}
/// 单位后缀（没有单位时为 null：不建后缀节点，同旧实现）。
fn unit(row: m.Row) ?[]const u8 {
    return row.unit;
}
fn checked(vm: *m.ViewModel, row: m.Row) bool {
    return vm.boolOf(row.key.?);
}
fn setBool(vm: *m.ViewModel, row: m.Row, value: bool) void {
    vm.dispatch(m.Intent.editValue(row.key.?, .{ .boolean = value }));
}
fn editText(vm: *m.ViewModel, row: m.Row, text: []const u8) void {
    vm.dispatch(m.Intent.editText(row.key.?, text));
}
/// 选择框：“自定义 TERM 声明…”打开原地编辑（`CustomSelectRow`，值不变，下拉按草稿值复位）；其它选项直接写草稿。
fn pick(vm: *m.ViewModel, row: m.Row, value: ?[]const u8) void {
    const picked = value orelse return;
    if (std.mem.eql(u8, picked, custom_choice)) {
        vm.dispatch(m.Intent.chooseFor(row.key.?));
        return;
    }
    vm.dispatch(m.Intent.editValue(row.key.?, .{ .text = picked }));
}
const std = @import("std");
/// 选择框里要宿主原地编辑的选项值（旧 `settings_controls.Field.select` 的 `__custom`）。
pub const custom_choice = "__custom";
/// 目录行全文提示的 id（`settings.directory.tooltip`，同旧实现；也是它在 `popup` 里的名字）。
const directory_tip = "settings.directory.tooltip";
fn popup(vm: *m.ViewModel, id: []const u8) bool {
    return vm.popupOpen(id);
}
fn setPopup(vm: *m.ViewModel, id: []const u8, open: bool) void {
    vm.dispatch(m.Intent.popupChanged(id, open));
}
fn problem(vm: *m.ViewModel, row: m.Row) []const u8 {
    return vm.fieldProblem(row);
}
fn invalid(vm: *m.ViewModel, row: m.Row) bool {
    return vm.fieldInvalid(row);
}
fn disabled(vm: *m.ViewModel, row: m.Row) bool {
    return vm.fieldDisabled(row);
}
fn paneId(pane: *const m.PaneSpec) []const u8 {
    return pane.id;
}
fn headerId(pane: *const m.PaneSpec) []const u8 {
    return pane.header_id;
}
fn summaryId(pane: *const m.PaneSpec) []const u8 {
    return pane.summary_id;
}
fn title(pane: *const m.PaneSpec) []const u8 {
    return pane.title;
}
fn meta(vm: *m.ViewModel, pane: *const m.PaneSpec) []const u8 {
    return vm.paneMeta(pane);
}
fn paneShown(vm: *m.ViewModel, pane: *const m.PaneSpec) bool {
    return vm.paneShown(pane);
}

/// 面板（`v8NDZM`）：页头（`QGtx5`，标题 + 右侧说明）在上，正文卡片（`V4TNB`）在下；行之间的分隔线由行自己画。
pub fn Pane(args: anytype) ui.view.SlottedOf(__yix_Pane) {
    return ui.view.slotted(__yix_Pane, ui.reactive.props.coerce(PaneProps, args));
}
pub const PaneProps = struct {
    vm: ui.Source(*m.ViewModel),
    pane: ui.Source(*const m.PaneSpec),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Pane;
    pub const __yix_preview_mount = __yix_Pane;
};
fn __yix_Pane(__yix_props: PaneProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!ui.view.ViewParts {
    const vm = __yix_props.vm;
    const pane = __yix_props.pane;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .pane = pane, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!ui.view.ViewParts {
    var __yix_slot_children: ?ui.view.SlotPoint = null;
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Pane", .receiver = "box", .tokens = "box testId = paneId ( pane ) ; style = @static; visible = paneShown ( vm , pane ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "paneId ( pane ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . pane ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "paneShown ( vm , pane ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .pane = __yix_view_ctx.pane, .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = __yix_d1: {
        const __yix_T = @TypeOf(paneId(__yix_view_ctx.pane.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .pane = __yix_view_ctx.pane, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return paneId(__yix_ctx.pane.get());
        } }.__yix_compute);
    }, .style = S.pane, .visible = __yix_d2: {
        const __yix_T = @TypeOf(paneShown(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return paneShown(__yix_ctx.vm.get(), __yix_ctx.pane.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Pane", .receiver = "box", .tokens = "box testId = headerId ( pane ) ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "headerId ( pane ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . pane_header ", .kind = .style, .literal = null }, } }, .{ .pane = __yix_view_ctx.pane, .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = __yix_d3: {
        const __yix_T = @TypeOf(headerId(__yix_view_ctx.pane.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .pane = __yix_view_ctx.pane, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return headerId(__yix_ctx.pane.get());
        } }.__yix_compute);
    }, .style = S.pane_header, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Pane", .receiver = "text", .tokens = "text style = @static; title ( pane )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_title ", .kind = .style, .literal = null }, } }, .{ .pane = __yix_view_ctx.pane, }, ui.view.text(.{ .style = S.pane_title, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d4: {
        const __yix_T = @TypeOf(title(__yix_view_ctx.pane.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .pane = __yix_view_ctx.pane, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return title(__yix_ctx.pane.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d4: {
        const __yix_T = @TypeOf(title(__yix_view_ctx.pane.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .pane = __yix_view_ctx.pane, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return title(__yix_ctx.pane.get());
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Pane", .receiver = "spacer", .tokens = "spacer ", .literal_text = null, .attributes = &.{ } }, .{ }, ui.view.spacer()),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Pane", .receiver = "text", .tokens = "text testId = summaryId ( pane ) ; style = @static; box = S . pane_meta_box ; meta ( vm , pane )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "summaryId ( pane ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . pane_meta ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . pane_meta_box ", .kind = .property, .literal = null }, } }, .{ .pane = __yix_view_ctx.pane, .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = __yix_d5: {
        const __yix_T = @TypeOf(summaryId(__yix_view_ctx.pane.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .pane = __yix_view_ctx.pane, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return summaryId(__yix_ctx.pane.get());
        } }.__yix_compute);
    }, .style = S.pane_meta, .box = S.pane_meta_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d6: {
        const __yix_T = @TypeOf(meta(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return meta(__yix_ctx.vm.get(), __yix_ctx.pane.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d6: {
        const __yix_T = @TypeOf(meta(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return meta(__yix_ctx.vm.get(), __yix_ctx.pane.get());
        } }.__yix_compute);
    }, }))),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Pane", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . pane_body ", .kind = .style, .literal = null }, } }, .{ }, ui.view.slotEnd(&__yix_slot_children, ui.view.box(.{ .style = S.pane_body, }, .{ }))),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Pane";
    return ui.view.slottedParts(__yix_root, __yix_slot_children, .{ });
    } }.__yix_render);
    return __yix_view;

}

/// 标题旁的“?”：原生 ghost 图标按钮 + 原生 Tooltip（上方、450ms，悬停 / 聚焦 / 点击打开）。
fn HelpTip(args: anytype) ui.view.ComponentOf(__yix_HelpTip) {
    return ui.view.component(__yix_HelpTip, ui.reactive.props.coerce(HelpTipProps, args));
}
const HelpTipProps = struct {
    vm: ui.Source(*m.ViewModel),
    row: ui.Source(m.Row),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = HelpTip;
    pub const __yix_preview_mount = __yix_HelpTip;
};
fn __yix_HelpTip(__yix_props: HelpTipProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const row = __yix_props.row;
    try ui.view.previewCheckSetup(scope, false);
    const tip = __yix_d1: {
        const __yix_T = @TypeOf(helpTipId(row.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return helpTipId(__yix_ctx.row.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .row = row, .tip = tip, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "HelpTip", .receiver = "box", .tokens = "box style = @static; onFocus = setPopup ( vm , tip , true ) ; onBlur = setPopup ( vm , tip , false ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . help_slot ", .kind = .style, .literal = null }, .{ .name = "on_focus", .tokens = "setPopup ( vm , tip , true ) ", .kind = .event, .literal = null }, .{ .name = "on_blur", .tokens = "setPopup ( vm , tip , false ) ", .kind = .event, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .row = __yix_view_ctx.row, }, ui.view.box(.{ .style = S.help_slot, .on_focus = try ui.on.bind(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), true);  } }.__yix_run), .on_blur = try ui.on.bind(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), false);  } }.__yix_run), }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "HelpTip", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { help ( row ) } position = { . top } width = { 292 } open = { popup ( vm , tip ) } onOpenChange = { | o | setPopup ( vm , tip , o ) } parts = { . { . content = tip } } > < W . Button testId = { helpId ( row ) } variant = { . ghost } size = { . xs } iconOnly = { true } iconAsset = { ui . icons . circle_help } iconSize = { 14 } a11yLabel = { help ( row ) } onClick = { setPopup ( vm , tip , true ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "help ( row ) ", .kind = .property, .literal = null }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, .{ .name = "width", .tokens = "292 ", .kind = .property, .literal = .{ .number = 292 } }, .{ .name = "open", .tokens = "popup ( vm , tip ) ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | setPopup ( vm , tip , o ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . content = tip } ", .kind = .property, .literal = null }, } }, .{ .tip = __yix_view_ctx.tip, .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .parts = .{ .content = __yix_view_ctx.tip }, }, __yix_builder_7381: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_7381 ui.view.with(W.Tooltip(.{ .text = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(help(__yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return help(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .position = .top, .width = 292, .open = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "open")) |__yix_A| __yix_A else @TypeOf(popup(__yix_view_ctx.vm.peek(), __yix_view_ctx.tip.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return popup(__yix_ctx.vm.get(), __yix_ctx.tip.get());
        } }.__yix_compute);
    }, .on_open_change = ui.view.eventProp(W.Tooltip, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), o);  } }.__yix_run)), }), .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "HelpTip", .receiver = "W.Button", .tokens = "< W . Button testId = { helpId ( row ) } variant = { . ghost } size = { . xs } iconOnly = { true } iconAsset = { ui . icons . circle_help } iconSize = { 14 } a11yLabel = { help ( row ) } onClick = { setPopup ( vm , tip , true ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "helpId ( row ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". xs ", .kind = .property, .literal = .{ .enum_name = "xs" } }, .{ .name = "icon_only", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "icon_asset", .tokens = "ui . icons . circle_help ", .kind = .property, .literal = null }, .{ .name = "icon_size", .tokens = "14 ", .kind = .property, .literal = .{ .number = 14 } }, .{ .name = "a11y_label", .tokens = "help ( row ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "setPopup ( vm , tip , true ) ", .kind = .event, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, }, ui.view.templateAttrs(.{ .test_id = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(helpId(__yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return helpId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }, __yix_builder_7544: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_7544 W.Button(.{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = ui.icons.circle_help, .icon_size = 14, .a11y_label = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(help(__yix_view_ctx.row.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return help(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), true);  } }.__yix_run) else __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(setPopup(__yix_view_ctx.vm.peek(), __yix_view_ctx.tip.peek(), true));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return setPopup(__yix_ctx.vm.get(), __yix_ctx.tip.get(), true);
        } }.__yix_compute);
    }, }); })),
            }); })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "HelpTip";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 文案列：标签（+“?”），易误用字段的说明直接写在标签下。
fn Copy(args: anytype) ui.view.ComponentOf(__yix_Copy) {
    return ui.view.component(__yix_Copy, ui.reactive.props.coerce(CopyProps, args));
}
const CopyProps = struct {
    vm: ui.Source(*m.ViewModel),
    row: ui.Source(m.Row),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Copy;
    pub const __yix_preview_mount = __yix_Copy;
};
fn __yix_Copy(__yix_props: CopyProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const row = __yix_props.row;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .row = row, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Copy", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_copy ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .style = S.setting_copy, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Copy", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_heading ", .kind = .style, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .style = S.setting_heading, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Copy", .receiver = "text", .tokens = "text style = @static; label ( row )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_label ", .kind = .style, .literal = null }, } }, .{ .row = __yix_view_ctx.row, }, ui.view.text(.{ .style = S.setting_label, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d1: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d1: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Copy", .receiver = "control", .tokens = "if ( tipHelp ( row ) ) < HelpTip vm = { vm } row = { row } / > " }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.lazyIf(__yix_d1: {
        const __yix_T = @TypeOf(tipHelp(__yix_view_ctx.row.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return tipHelp(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Copy/keyword_if:1/branch:0", .receiver = "HelpTip", .tokens = "< HelpTip vm = { vm } row = { row } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, }, __yix_builder_18: { try ui.view.previewCheckBuilder(__yix_bs1_0, HelpTip); break :__yix_builder_18 HelpTip(.{ .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, }); }) }); } }.__yix_b, null)),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Copy", .receiver = "control", .tokens = "if ( inlineHelp ( row ) ) < text testId = { helpTextId ( row ) } style = { S . setting_hint } box = { S . setting_hint_box } > { help ( row ) } < / text > " }, .{ .row = __yix_view_ctx.row, }, ui.view.lazyIf(__yix_d3: {
        const __yix_T = @TypeOf(inlineHelp(__yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return inlineHelp(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_b(__yix_b2_0: anytype, __yix_bs2_0: *ui.Scope, __yix_bc2_0: *ui.Cx, __yix_bk2_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs2_0, __yix_bc2_0, __yix_bk2_0, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Copy/keyword_if:2/branch:0", .receiver = "text", .tokens = "text testId = helpTextId ( row ) ; style = @static; box = S . setting_hint_box ; help ( row )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "helpTextId ( row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . setting_hint ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . setting_hint_box ", .kind = .property, .literal = null }, } }, .{ .row = __yix_b2_0.row, }, ui.view.text(.{ .test_id = __yix_d1: {
        const __yix_T = @TypeOf(helpTextId(__yix_b2_0.row.peek()));
        break :__yix_d1 try __yix_bs2_0.derive(__yix_T, .{ .row = __yix_b2_0.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return helpTextId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = S.setting_hint, .box = S.setting_hint_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d2: {
        const __yix_T = @TypeOf(help(__yix_b2_0.row.peek()));
        break :__yix_d2 try __yix_bs2_0.derive(__yix_T, .{ .row = __yix_b2_0.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return help(__yix_ctx.row.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d2: {
        const __yix_T = @TypeOf(help(__yix_b2_0.row.peek()));
        break :__yix_d2 try __yix_bs2_0.derive(__yix_T, .{ .row = __yix_b2_0.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return help(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }))) }); } }.__yix_b, null)),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Copy";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 行内校验提示（`settings.error.<key>`，无问题时不显示）。
fn Problem(args: anytype) ui.view.ComponentOf(__yix_Problem) {
    return ui.view.component(__yix_Problem, ui.reactive.props.coerce(ProblemProps, args));
}
const ProblemProps = struct {
    vm: ui.Source(*m.ViewModel),
    row: ui.Source(m.Row),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = Problem;
    pub const __yix_preview_mount = __yix_Problem;
};
fn __yix_Problem(__yix_props: ProblemProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const row = __yix_props.row;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .row = row, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "Problem", .receiver = "text", .tokens = "text testId = errorId ( row ) ; style = @static; visible = invalid ( vm , row ) ; problem ( vm , row )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "errorId ( row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . setting_error ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "invalid ( vm , row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.text(.{ .test_id = __yix_d1: {
        const __yix_T = @TypeOf(errorId(__yix_view_ctx.row.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return errorId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = S.setting_error, .visible = __yix_d2: {
        const __yix_T = @TypeOf(invalid(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return invalid(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d3: {
        const __yix_T = @TypeOf(problem(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return problem(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d3: {
        const __yix_T = @TypeOf(problem(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return problem(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }))));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "Problem";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 开关行（`ow4oe` + 原生 `W.Switch`）。
pub fn ToggleRow(args: anytype) ui.view.ComponentOf(__yix_ToggleRow) {
    return ui.view.component(__yix_ToggleRow, ui.reactive.props.coerce(ToggleRowProps, args));
}
pub const ToggleRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    pane: ui.Source(*const m.PaneSpec),
    row: ui.Source(m.Row),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ToggleRow;
    pub const __yix_preview_mount = __yix_ToggleRow;
};
fn __yix_ToggleRow(__yix_props: ToggleRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const pane = __yix_props.pane;
    const row = __yix_props.row;
    try ui.view.previewCheckSetup(scope, false);
    const switch_a11y = __yix_d1: {
        const __yix_T = @TypeOf(switchA11y(vm.peek(), row.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .vm = vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return switchA11y(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .pane = pane, .row = row, .switch_a11y = switch_a11y, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ToggleRow", .receiver = "box", .tokens = "box testId = rowId ( row ) ; style = S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ; visible = shown ( vm , pane , row ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "rowId ( row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "shown ( vm , pane , row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .switch_a11y = __yix_view_ctx.switch_a11y, }, ui.view.box(.{ .test_id = __yix_d2: {
        const __yix_T = @TypeOf(rowId(__yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return rowId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = S.SettingRow.of(.{ .last = __yix_d3: {
        const __yix_T = @TypeOf(last(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return last(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    } }), .visible = __yix_d4: {
        const __yix_T = @TypeOf(shown(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return shown(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ToggleRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .switch_a11y = __yix_view_ctx.switch_a11y, }, ui.view.box(.{ .style = S.setting_line, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ToggleRow", .receiver = "Copy", .tokens = "< Copy vm = { vm } row = { row } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, __yix_builder_8934: { try ui.view.previewCheckBuilder(__yix_view_scope, Copy); break :__yix_builder_8934 Copy(.{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }); }),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ToggleRow", .receiver = "W.Switch", .tokens = "< W . Switch testId = { fieldId ( row ) } checked = { checked ( vm , row ) } disabled = { disabled ( vm , row ) } a11y = { switch_a11y } onChange = { | v | setBool ( vm , row , v ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "fieldId ( row ) ", .kind = .property, .literal = null }, .{ .name = "checked", .tokens = "checked ( vm , row ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "disabled ( vm , row ) ", .kind = .property, .literal = null }, .{ .name = "a11y", .tokens = "switch_a11y ", .kind = .property, .literal = null }, .{ .name = "on_change", .tokens = "| v | setBool ( vm , row , v ) ", .kind = .event, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .switch_a11y = __yix_view_ctx.switch_a11y, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Switch, "test_id")) |__yix_A| __yix_A else @TypeOf(fieldId(__yix_view_ctx.row.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .a11y = __yix_view_ctx.switch_a11y, }, __yix_builder_8977: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Switch); break :__yix_builder_8977 W.Switch(.{ .checked = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Switch, "checked")) |__yix_A| __yix_A else @TypeOf(checked(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return checked(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, .disabled = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Switch, "disabled")) |__yix_A| __yix_A else @TypeOf(disabled(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return disabled(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, .on_change = ui.view.eventProp(W.Switch, "on_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, v: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setBool(__yix_ctx.vm.peek(), __yix_ctx.row.peek(), v);  } }.__yix_run)), }); })),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ToggleRow", .receiver = "Problem", .tokens = "< Problem vm = { vm } row = { row } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, __yix_builder_9153: { try ui.view.previewCheckBuilder(__yix_view_scope, Problem); break :__yix_builder_9153 Problem(.{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ToggleRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 输入行：原生 `W.Input`（受控：原文经 view-model 同步落地），校验问题标红并在行下提示。
/// 单位是原生后缀（`appendText`，挂载时取值；G25 已由上游补上，S-14 收回）。
pub fn InputRow(args: anytype) ui.view.ComponentOf(__yix_InputRow) {
    return ui.view.component(__yix_InputRow, ui.reactive.props.coerce(InputRowProps, args));
}
pub const InputRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    pane: ui.Source(*const m.PaneSpec),
    row: ui.Source(m.Row),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = InputRow;
    pub const __yix_preview_mount = __yix_InputRow;
};
fn __yix_InputRow(__yix_props: InputRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const pane = __yix_props.pane;
    const row = __yix_props.row;
    try ui.view.previewCheckSetup(scope, false);
    const fid = __yix_d1: {
        const __yix_T = @TypeOf(fieldId(row.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .pane = pane, .row = row, .fid = fid, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InputRow", .receiver = "box", .tokens = "box testId = rowId ( row ) ; style = S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ; visible = shown ( vm , pane , row ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "rowId ( row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "shown ( vm , pane , row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .fid = __yix_view_ctx.fid, }, ui.view.box(.{ .test_id = __yix_d2: {
        const __yix_T = @TypeOf(rowId(__yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return rowId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = S.SettingRow.of(.{ .last = __yix_d3: {
        const __yix_T = @TypeOf(last(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return last(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    } }), .visible = __yix_d4: {
        const __yix_T = @TypeOf(shown(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return shown(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InputRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .fid = __yix_view_ctx.fid, }, ui.view.box(.{ .style = S.setting_line, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InputRow", .receiver = "Copy", .tokens = "< Copy vm = { vm } row = { row } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, __yix_builder_9746: { try ui.view.previewCheckBuilder(__yix_view_scope, Copy); break :__yix_builder_9746 Copy(.{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }); }),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InputRow", .receiver = "W.Input", .tokens = "< W . Input value = { vm . fieldText ( row ) } appendText = { unit ( row ) } width = { 180 } invalid = { invalid ( vm , row ) } disabled = { disabled ( vm , row ) } focusId = { focusId ( row ) } onChange = { | t | editText ( vm , row , t ) } onSubmit = { | t | editText ( vm , row , t ) } parts = { . { . input_container = fid } } / > ", .literal_text = null, .attributes = &.{ .{ .name = "value", .tokens = "vm . fieldText ( row ) ", .kind = .property, .literal = null }, .{ .name = "append_text", .tokens = "unit ( row ) ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "180 ", .kind = .property, .literal = .{ .number = 180 } }, .{ .name = "invalid", .tokens = "invalid ( vm , row ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "disabled ( vm , row ) ", .kind = .property, .literal = null }, .{ .name = "focus_id", .tokens = "focusId ( row ) ", .kind = .property, .literal = null }, .{ .name = "on_change", .tokens = "| t | editText ( vm , row , t ) ", .kind = .event, .literal = null }, .{ .name = "on_submit", .tokens = "| t | editText ( vm , row , t ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . input_container = fid } ", .kind = .property, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .fid = __yix_view_ctx.fid, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .focus_id = __yix_d9: {
        const __yix_T = if (ui.view.attrType(W.Input, "focus_id")) |__yix_A| __yix_A else @TypeOf(focusId(__yix_view_ctx.row.peek()));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return focusId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .parts = .{ .input_container = __yix_view_ctx.fid }, }, __yix_builder_9789: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Input); break :__yix_builder_9789 W.Input(.{ .value = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Input, "value")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().fieldText(__yix_view_ctx.row.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().fieldText(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .append_text = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Input, "append_text")) |__yix_A| __yix_A else @TypeOf(unit(__yix_view_ctx.row.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return unit(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .width = 180, .invalid = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Input, "invalid")) |__yix_A| __yix_A else @TypeOf(invalid(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return invalid(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, .disabled = __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Input, "disabled")) |__yix_A| __yix_A else @TypeOf(disabled(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return disabled(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, .on_change = ui.view.eventProp(W.Input, "on_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, t: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); editText(__yix_ctx.vm.peek(), __yix_ctx.row.peek(), t);  } }.__yix_run)), .on_submit = ui.view.eventProp(W.Input, "on_submit", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, t: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); editText(__yix_ctx.vm.peek(), __yix_ctx.row.peek(), t);  } }.__yix_run)), }); })),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InputRow", .receiver = "Problem", .tokens = "< Problem vm = { vm } row = { row } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, __yix_builder_10080: { try ui.view.previewCheckBuilder(__yix_view_scope, Problem); break :__yix_builder_10080 Problem(.{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "InputRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 选择行：原生 `W.Select`（180 宽，下拉与触发器同宽），下拉开合归 view-model（Escape 收起）。
pub fn SelectRow(args: anytype) ui.view.ComponentOf(__yix_SelectRow) {
    return ui.view.component(__yix_SelectRow, ui.reactive.props.coerce(SelectRowProps, args));
}
pub const SelectRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    pane: ui.Source(*const m.PaneSpec),
    row: ui.Source(m.Row),
    options: ui.Source([]const W.SelectOption),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = SelectRow;
    pub const __yix_preview_mount = __yix_SelectRow;
};
fn __yix_SelectRow(__yix_props: SelectRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const pane = __yix_props.pane;
    const row = __yix_props.row;
    const options = __yix_props.options;
    try ui.view.previewCheckSetup(scope, false);
    const fid = __yix_d1: {
        const __yix_T = @TypeOf(fieldId(row.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .pane = pane, .row = row, .options = options, .fid = fid, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "SelectRow", .receiver = "box", .tokens = "box testId = rowId ( row ) ; style = S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ; visible = shown ( vm , pane , row ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "rowId ( row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "shown ( vm , pane , row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .fid = __yix_view_ctx.fid, .options = __yix_view_ctx.options, }, ui.view.box(.{ .test_id = __yix_d2: {
        const __yix_T = @TypeOf(rowId(__yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return rowId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = S.SettingRow.of(.{ .last = __yix_d3: {
        const __yix_T = @TypeOf(last(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return last(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    } }), .visible = __yix_d4: {
        const __yix_T = @TypeOf(shown(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return shown(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "SelectRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .fid = __yix_view_ctx.fid, .options = __yix_view_ctx.options, }, ui.view.box(.{ .style = S.setting_line, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "SelectRow", .receiver = "Copy", .tokens = "< Copy vm = { vm } row = { row } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, __yix_builder_10605: { try ui.view.previewCheckBuilder(__yix_view_scope, Copy); break :__yix_builder_10605 Copy(.{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }); }),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "SelectRow", .receiver = "W.Select", .tokens = "< W . Select panelWidth = { . trigger } options = { options } value = { vm . selectValue ( row ) } width = { 180 } disabled = { disabled ( vm , row ) } open = { popup ( vm , fid ) } onOpenChange = { | o | setPopup ( vm , fid , o ) } onChange = { | v | pick ( vm , row , v ) } parts = { . { . trigger = fid } } / > ", .literal_text = null, .attributes = &.{ .{ .name = "panel_width", .tokens = ". trigger ", .kind = .property, .literal = .{ .enum_name = "trigger" } }, .{ .name = "options", .tokens = "options ", .kind = .property, .literal = null }, .{ .name = "value", .tokens = "vm . selectValue ( row ) ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "180 ", .kind = .property, .literal = .{ .number = 180 } }, .{ .name = "disabled", .tokens = "disabled ( vm , row ) ", .kind = .property, .literal = null }, .{ .name = "open", .tokens = "popup ( vm , fid ) ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | setPopup ( vm , fid , o ) ", .kind = .event, .literal = null }, .{ .name = "on_change", .tokens = "| v | pick ( vm , row , v ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . trigger = fid } ", .kind = .property, .literal = null }, } }, .{ .fid = __yix_view_ctx.fid, .options = __yix_view_ctx.options, .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.templateAttrs(.{ .parts = .{ .trigger = __yix_view_ctx.fid }, }, __yix_builder_10648: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Select); break :__yix_builder_10648 W.Select(.{ .panel_width = .trigger, .options = __yix_view_ctx.options, .value = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Select, "value")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().selectValue(__yix_view_ctx.row.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().selectValue(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .width = 180, .disabled = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Select, "disabled")) |__yix_A| __yix_A else @TypeOf(disabled(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return disabled(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, .open = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Select, "open")) |__yix_A| __yix_A else @TypeOf(popup(__yix_view_ctx.vm.peek(), __yix_view_ctx.fid.peek()));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .fid = __yix_view_ctx.fid, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return popup(__yix_ctx.vm.get(), __yix_ctx.fid.get());
        } }.__yix_compute);
    }, .on_open_change = ui.view.eventProp(W.Select, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .fid = __yix_view_ctx.fid, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.fid.peek(), o);  } }.__yix_run)), .on_change = ui.view.eventProp(W.Select, "on_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, v: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); pick(__yix_ctx.vm.peek(), __yix_ctx.row.peek(), v);  } }.__yix_run)), }); })),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "SelectRow", .receiver = "Problem", .tokens = "< Problem vm = { vm } row = { row } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, __yix_builder_10923: { try ui.view.previewCheckBuilder(__yix_view_scope, Problem); break :__yix_builder_10923 Problem(.{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "SelectRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 选择行 + 原地编辑（S-13，“自定义 TERM 声明…”）：选项里的 `custom_choice` 在选择框下方打开原生 `W.Popover`
/// （手动触发：开合是 view-model 的 `popup`——点外面 / Escape 收起，锚点滚出视口收起；默认面板外观）。
/// 里面是说明（`noteId`）与原生 `W.Input`（受控：草稿归 view-model，打开即聚焦，Enter 提交，校验失败用原生 `errorMsg`）。
pub fn CustomSelectRow(args: anytype) ui.view.ComponentOf(__yix_CustomSelectRow) {
    return ui.view.component(__yix_CustomSelectRow, ui.reactive.props.coerce(CustomSelectRowProps, args));
}
pub const CustomSelectRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    pane: ui.Source(*const m.PaneSpec),
    row: ui.Source(m.Row),
    options: ui.Source([]const W.SelectOption),
    note_id: ui.Source([]const u8),
    note: ui.Source([]const u8),
    placeholder: ui.Source([]const u8),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = CustomSelectRow;
    pub const __yix_preview_mount = __yix_CustomSelectRow;
};
fn __yix_CustomSelectRow(__yix_props: CustomSelectRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const pane = __yix_props.pane;
    const row = __yix_props.row;
    const options = __yix_props.options;
    const noteId = __yix_props.note_id;
    const note = __yix_props.note;
    const placeholder = __yix_props.placeholder;
    try ui.view.previewCheckSetup(scope, false);
    const fid = __yix_d1: {
        const __yix_T = @TypeOf(fieldId(row.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .pane = pane, .row = row, .options = options, .noteId = noteId, .note = note, .placeholder = placeholder, .fid = fid, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomSelectRow", .receiver = "box", .tokens = "box testId = rowId ( row ) ; style = S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ; visible = shown ( vm , pane , row ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "rowId ( row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "shown ( vm , pane , row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .fid = __yix_view_ctx.fid, .options = __yix_view_ctx.options, .noteId = __yix_view_ctx.noteId, .note = __yix_view_ctx.note, .placeholder = __yix_view_ctx.placeholder, }, ui.view.box(.{ .test_id = __yix_d2: {
        const __yix_T = @TypeOf(rowId(__yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return rowId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = S.SettingRow.of(.{ .last = __yix_d3: {
        const __yix_T = @TypeOf(last(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return last(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    } }), .visible = __yix_d4: {
        const __yix_T = @TypeOf(shown(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return shown(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomSelectRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .fid = __yix_view_ctx.fid, .options = __yix_view_ctx.options, .noteId = __yix_view_ctx.noteId, .note = __yix_view_ctx.note, .placeholder = __yix_view_ctx.placeholder, }, ui.view.box(.{ .style = S.setting_line, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomSelectRow", .receiver = "Copy", .tokens = "< Copy vm = { vm } row = { row } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, __yix_builder_11837: { try ui.view.previewCheckBuilder(__yix_view_scope, Copy); break :__yix_builder_11837 Copy(.{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }); }),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomSelectRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . custom_anchor ", .kind = .style, .literal = null }, } }, .{ .fid = __yix_view_ctx.fid, .options = __yix_view_ctx.options, .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .noteId = __yix_view_ctx.noteId, .note = __yix_view_ctx.note, .placeholder = __yix_view_ctx.placeholder, }, ui.view.box(.{ .style = S.custom_anchor, }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomSelectRow", .receiver = "W.Select", .tokens = "< W . Select panelWidth = { . trigger } options = { options } value = { vm . selectValue ( row ) } width = { 180 } disabled = { disabled ( vm , row ) } open = { popup ( vm , fid ) } onOpenChange = { | o | setPopup ( vm , fid , o ) } onChange = { | v | pick ( vm , row , v ) } parts = { . { . trigger = fid } } / > ", .literal_text = null, .attributes = &.{ .{ .name = "panel_width", .tokens = ". trigger ", .kind = .property, .literal = .{ .enum_name = "trigger" } }, .{ .name = "options", .tokens = "options ", .kind = .property, .literal = null }, .{ .name = "value", .tokens = "vm . selectValue ( row ) ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "180 ", .kind = .property, .literal = .{ .number = 180 } }, .{ .name = "disabled", .tokens = "disabled ( vm , row ) ", .kind = .property, .literal = null }, .{ .name = "open", .tokens = "popup ( vm , fid ) ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | setPopup ( vm , fid , o ) ", .kind = .event, .literal = null }, .{ .name = "on_change", .tokens = "| v | pick ( vm , row , v ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . trigger = fid } ", .kind = .property, .literal = null }, } }, .{ .fid = __yix_view_ctx.fid, .options = __yix_view_ctx.options, .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.templateAttrs(.{ .parts = .{ .trigger = __yix_view_ctx.fid }, }, __yix_builder_11930: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Select); break :__yix_builder_11930 W.Select(.{ .panel_width = .trigger, .options = __yix_view_ctx.options, .value = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Select, "value")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().selectValue(__yix_view_ctx.row.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().selectValue(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .width = 180, .disabled = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Select, "disabled")) |__yix_A| __yix_A else @TypeOf(disabled(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return disabled(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, .open = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Select, "open")) |__yix_A| __yix_A else @TypeOf(popup(__yix_view_ctx.vm.peek(), __yix_view_ctx.fid.peek()));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .fid = __yix_view_ctx.fid, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return popup(__yix_ctx.vm.get(), __yix_ctx.fid.get());
        } }.__yix_compute);
    }, .on_open_change = ui.view.eventProp(W.Select, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .fid = __yix_view_ctx.fid, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.fid.peek(), o);  } }.__yix_run)), .on_change = ui.view.eventProp(W.Select, "on_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, v: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); pick(__yix_ctx.vm.peek(), __yix_ctx.row.peek(), v);  } }.__yix_run)), }); })),
                    ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomSelectRow", .receiver = "W.Popover", .tokens = "< W . Popover trigger = { . manual } open = { popup ( vm , m . ViewModel . custom_popup ) } onOpenChange = { | o | setPopup ( vm , m . ViewModel . custom_popup , o ) } closeOnAnchorScroll = { true } width = { 264 } parts = { . { . chrome = m . ViewModel . custom_popup } } closeOnEscape = { O . panel . escape } closeOnOutsideClick = { O . panel . outside } consumeOutsideClick = { O . consume_outside_click } trapFocus = { O . panel . trap_focus } > { if ( popup ( vm , m . ViewModel . custom_popup ) ) < CustomEditor vm = { vm } noteId = { noteId } note = { note } placeholder = { placeholder } / > } < / W . Popover > ", .literal_text = null, .attributes = &.{ .{ .name = "trigger", .tokens = ". manual ", .kind = .property, .literal = .{ .enum_name = "manual" } }, .{ .name = "open", .tokens = "popup ( vm , m . ViewModel . custom_popup ) ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | setPopup ( vm , m . ViewModel . custom_popup , o ) ", .kind = .event, .literal = null }, .{ .name = "close_on_anchor_scroll", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "width", .tokens = "264 ", .kind = .property, .literal = .{ .number = 264 } }, .{ .name = "parts", .tokens = ". { . chrome = m . ViewModel . custom_popup } ", .kind = .property, .literal = null }, .{ .name = "close_on_escape", .tokens = "O . panel . escape ", .kind = .property, .literal = null }, .{ .name = "close_on_outside_click", .tokens = "O . panel . outside ", .kind = .property, .literal = null }, .{ .name = "consume_outside_click", .tokens = "O . consume_outside_click ", .kind = .property, .literal = null }, .{ .name = "trap_focus", .tokens = "O . panel . trap_focus ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .noteId = __yix_view_ctx.noteId, .note = __yix_view_ctx.note, .placeholder = __yix_view_ctx.placeholder, }, ui.view.templateAttrs(.{ .parts = .{ .chrome = m.ViewModel.custom_popup }, }, __yix_builder_12194: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Popover); break :__yix_builder_12194 ui.view.with(W.Popover(.{ .trigger = .manual, .open = __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Popover, "open")) |__yix_A| __yix_A else @TypeOf(popup(__yix_view_ctx.vm.peek(), m.ViewModel.custom_popup));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return popup(__yix_ctx.vm.get(), m.ViewModel.custom_popup);
        } }.__yix_compute);
    }, .on_open_change = ui.view.eventProp(W.Popover, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), m.ViewModel.custom_popup, o);  } }.__yix_run)), .close_on_anchor_scroll = true, .width = 264, .close_on_escape = O.panel.escape, .close_on_outside_click = O.panel.outside, .consume_outside_click = O.consume_outside_click, .trap_focus = O.panel.trap_focus, }), .{
                        ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomSelectRow", .receiver = "control", .tokens = "if ( popup ( vm , m . ViewModel . custom_popup ) ) < CustomEditor vm = { vm } noteId = { noteId } note = { note } placeholder = { placeholder } / > " }, .{ .vm = __yix_view_ctx.vm, .noteId = __yix_view_ctx.noteId, .note = __yix_view_ctx.note, .placeholder = __yix_view_ctx.placeholder, }, ui.view.lazyIf(__yix_d1: {
        const __yix_T = @TypeOf(popup(__yix_view_ctx.vm.peek(), m.ViewModel.custom_popup));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return popup(__yix_ctx.vm.get(), m.ViewModel.custom_popup);
        } }.__yix_compute);
    }, .{ .vm = __yix_view_ctx.vm, .noteId = __yix_view_ctx.noteId, .note = __yix_view_ctx.note, .placeholder = __yix_view_ctx.placeholder, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomSelectRow/keyword_if:1/branch:0", .receiver = "CustomEditor", .tokens = "< CustomEditor vm = { vm } noteId = { noteId } note = { note } placeholder = { placeholder } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "note_id", .tokens = "noteId ", .kind = .property, .literal = null }, .{ .name = "note", .tokens = "note ", .kind = .property, .literal = null }, .{ .name = "placeholder", .tokens = "placeholder ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_b1_0.vm, .noteId = __yix_b1_0.noteId, .note = __yix_b1_0.note, .placeholder = __yix_b1_0.placeholder, }, __yix_builder_41: { try ui.view.previewCheckBuilder(__yix_bs1_0, CustomEditor); break :__yix_builder_41 CustomEditor(.{ .vm = __yix_b1_0.vm, .note_id = __yix_b1_0.noteId, .note = __yix_b1_0.note, .placeholder = __yix_b1_0.placeholder, }); }) }); } }.__yix_b, null)),
                    }); })),
                })),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomSelectRow", .receiver = "Problem", .tokens = "< Problem vm = { vm } row = { row } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, __yix_builder_12794: { try ui.view.previewCheckBuilder(__yix_view_scope, Problem); break :__yix_builder_12794 Problem(.{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }); }),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "CustomSelectRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}
fn customEdit(vm: *m.ViewModel, text: []const u8) void {
    vm.dispatch(m.Intent.customText(text));
}
fn customSubmit(vm: *m.ViewModel, text: []const u8) void {
    vm.dispatch(m.Intent.customSubmit(text));
}
fn CustomEditor(args: anytype) ui.view.ComponentOf(__yix_CustomEditor) {
    return ui.view.component(__yix_CustomEditor, ui.reactive.props.coerce(CustomEditorProps, args));
}
const CustomEditorProps = struct {
    vm: ui.Source(*m.ViewModel),
    note_id: ui.Source([]const u8),
    note: ui.Source([]const u8),
    placeholder: ui.Source([]const u8),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = CustomEditor;
    pub const __yix_preview_mount = __yix_CustomEditor;
};
fn __yix_CustomEditor(__yix_props: CustomEditorProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const noteId = __yix_props.note_id;
    const note = __yix_props.note;
    const placeholder = __yix_props.placeholder;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .noteId = noteId, .note = note, .placeholder = placeholder, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomEditor", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . custom_editor ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .noteId = __yix_view_ctx.noteId, .note = __yix_view_ctx.note, .vm = __yix_view_ctx.vm, .placeholder = __yix_view_ctx.placeholder, }, ui.view.box(.{ .style = S.custom_editor, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomEditor", .receiver = "text", .tokens = "text testId = noteId ; style = @static; box = S . setting_hint_box ; note  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "noteId ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . setting_hint ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . setting_hint_box ", .kind = .property, .literal = null }, } }, .{ .noteId = __yix_view_ctx.noteId, .note = __yix_view_ctx.note, }, ui.view.text(.{ .test_id = __yix_view_ctx.noteId, .style = S.setting_hint, .box = S.setting_hint_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_view_ctx.note), ""), .{ __yix_view_ctx.note, }))),
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "CustomEditor", .receiver = "W.Input", .tokens = "< W . Input value = { vm . customText ( ) } placeholder = { placeholder } autoFocus = { true } invalid = { vm . customInvalid ( ) } errorMsg = { vm . customProblem ( ) } onChange = { | t | customEdit ( vm , t ) } onSubmit = { | t | customSubmit ( vm , t ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "value", .tokens = "vm . customText ( ) ", .kind = .property, .literal = null }, .{ .name = "placeholder", .tokens = "placeholder ", .kind = .property, .literal = null }, .{ .name = "auto_focus", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "invalid", .tokens = "vm . customInvalid ( ) ", .kind = .property, .literal = null }, .{ .name = "error_msg", .tokens = "vm . customProblem ( ) ", .kind = .property, .literal = null }, .{ .name = "on_change", .tokens = "| t | customEdit ( vm , t ) ", .kind = .event, .literal = null }, .{ .name = "on_submit", .tokens = "| t | customSubmit ( vm , t ) ", .kind = .event, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .placeholder = __yix_view_ctx.placeholder, }, ui.view.templateAttrs(.{ .auto_focus = true, }, __yix_builder_13321: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Input); break :__yix_builder_13321 W.Input(.{ .value = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Input, "value")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().customText());
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().customText();
        } }.__yix_compute);
    }, .placeholder = __yix_view_ctx.placeholder, .invalid = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Input, "invalid")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().customInvalid());
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().customInvalid();
        } }.__yix_compute);
    }, .error_msg = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Input, "error_msg")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().customProblem());
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().customProblem();
        } }.__yix_compute);
    }, .on_change = ui.view.eventProp(W.Input, "on_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, t: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); customEdit(__yix_ctx.vm.peek(), t);  } }.__yix_run)), .on_submit = ui.view.eventProp(W.Input, "on_submit", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, t: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); customSubmit(__yix_ctx.vm.peek(), t);  } }.__yix_run)), }); })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "CustomEditor";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 目录行：原生 secondary 按钮显示当前目录（单行省略），点击交宿主的系统目录面板；悬停 / 聚焦显示全文。
/// 提示开合归 view-model 的 `popup`（同旧 `registerTooltip`：整窗 Escape 先收起它，不关窗）。
pub fn DirectoryRow(args: anytype) ui.view.ComponentOf(__yix_DirectoryRow) {
    return ui.view.component(__yix_DirectoryRow, ui.reactive.props.coerce(DirectoryRowProps, args));
}
pub const DirectoryRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    pane: ui.Source(*const m.PaneSpec),
    row: ui.Source(m.Row),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = DirectoryRow;
    pub const __yix_preview_mount = __yix_DirectoryRow;
};
fn __yix_DirectoryRow(__yix_props: DirectoryRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const pane = __yix_props.pane;
    const row = __yix_props.row;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .pane = pane, .row = row, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DirectoryRow", .receiver = "box", .tokens = "box style = S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ; visible = shown ( vm , pane , row ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "shown ( vm , pane , row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, ui.view.box(.{ .style = S.SettingRow.of(.{ .last = __yix_d1: {
        const __yix_T = @TypeOf(last(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return last(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    } }), .visible = __yix_d2: {
        const __yix_T = @TypeOf(shown(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return shown(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DirectoryRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.box(.{ .style = S.setting_line, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DirectoryRow", .receiver = "Copy", .tokens = "< Copy vm = { vm } row = { row } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, __yix_builder_14072: { try ui.view.previewCheckBuilder(__yix_view_scope, Copy); break :__yix_builder_14072 Copy(.{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }); }),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DirectoryRow", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { vm . fieldText ( row ) } width = { 292 } open = { popup ( vm , directory_tip ) } onOpenChange = { | o | setPopup ( vm , directory_tip , o ) } parts = { . { . content = directory_tip } } > < W . Pressable testId = { fieldId ( row ) } a11yLabel = { vm . fieldText ( row ) } disabled = { vm . isSaving ( ) } style = { S . DirectoryButton . of ( . { . off = vm . isSaving ( ) } ) } onClick = { send ( vm , m . Intent . chooseFor ( row . key . ? ) ) } > < icon src = { ui . icons . folder } style = { S . directory_icon } / > < text testId = \"settings.directory.label\" style = { S . directory_label } box = { S . directory_label_box } > { vm . fieldText ( row ) } < / text > < / W . Pressable > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "vm . fieldText ( row ) ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "292 ", .kind = .property, .literal = .{ .number = 292 } }, .{ .name = "open", .tokens = "popup ( vm , directory_tip ) ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | setPopup ( vm , directory_tip , o ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . content = directory_tip } ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.templateAttrs(.{ .parts = .{ .content = directory_tip }, }, __yix_builder_14115: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_14115 ui.view.with(W.Tooltip(.{ .text = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().fieldText(__yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().fieldText(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .width = 292, .open = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "open")) |__yix_A| __yix_A else @TypeOf(popup(__yix_view_ctx.vm.peek(), directory_tip));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return popup(__yix_ctx.vm.get(), directory_tip);
        } }.__yix_compute);
    }, .on_open_change = ui.view.eventProp(W.Tooltip, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), directory_tip, o);  } }.__yix_run)), }), .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DirectoryRow", .receiver = "W.Pressable", .tokens = "< W . Pressable testId = { fieldId ( row ) } a11yLabel = { vm . fieldText ( row ) } disabled = { vm . isSaving ( ) } style = { S . DirectoryButton . of ( . { . off = vm . isSaving ( ) } ) } onClick = { send ( vm , m . Intent . chooseFor ( row . key . ? ) ) } > < icon src = { ui . icons . folder } style = { S . directory_icon } / > < text testId = \"settings.directory.label\" style = { S . directory_label } box = { S . directory_label_box } > { vm . fieldText ( row ) } < / text > < / W . Pressable > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "fieldId ( row ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "vm . fieldText ( row ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "vm . isSaving ( ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . DirectoryButton . of ( . { . off = vm . isSaving ( ) } ) ", .kind = .style, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , m . Intent . chooseFor ( row . key . ? ) ) ", .kind = .event, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "test_id")) |__yix_A| __yix_A else @TypeOf(fieldId(__yix_view_ctx.row.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = S.DirectoryButton.of(.{ .off = __yix_d8: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().isSaving());
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().isSaving();
        } }.__yix_compute);
    } }), }, __yix_builder_14304: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Pressable); break :__yix_builder_14304 ui.view.with(W.Pressable(.{ .a11y_label = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "a11y_label")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().fieldText(__yix_view_ctx.row.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().fieldText(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .disabled = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "disabled")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().isSaving());
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().isSaving();
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Pressable, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), m.Intent.chooseFor(__yix_ctx.row.peek().key.?));  } }.__yix_run) else __yix_d9: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), m.Intent.chooseFor(__yix_view_ctx.row.peek().key.?)));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), m.Intent.chooseFor(__yix_ctx.row.get().key.?));
        } }.__yix_compute);
    }, }), .{
                        ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DirectoryRow", .receiver = "icon", .tokens = "icon src = ui . icons . folder ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "ui . icons . folder ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . directory_icon ", .kind = .style, .literal = null }, } }, .{ }, ui.view.icon(.{ .style = S.directory_icon, }, ui.icons.folder)),
                        ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DirectoryRow", .receiver = "text", .tokens = "text testId = @static; style = @static; box = S . directory_label_box ; vm . fieldText ( row )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "\"settings.directory.label\" ", .kind = .property, .literal = .{ .text = "settings.directory.label" } }, .{ .name = "style", .tokens = "S . directory_label ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . directory_label_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.text(.{ .test_id = "settings.directory.label", .style = S.directory_label, .box = S.directory_label_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d10: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().fieldText(__yix_view_ctx.row.peek()));
        break :__yix_d10 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().fieldText(__yix_ctx.row.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d10: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().fieldText(__yix_view_ctx.row.peek()));
        break :__yix_d10 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().fieldText(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }))),
                    }); })),
                }); })),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "DirectoryRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 只读行：值右对齐；路径单行省略，悬停 / 聚焦显示全文（`settings.path.<标签>`）。提示开合归 view-model 的 `popup`
/// （同旧 `HintFocus` + `registerTooltip`：聚焦即打开，整窗 Escape 先收起它，不关窗）。
pub fn InfoRow(args: anytype) ui.view.ComponentOf(__yix_InfoRow) {
    return ui.view.component(__yix_InfoRow, ui.reactive.props.coerce(InfoRowProps, args));
}
pub const InfoRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    pane: ui.Source(*const m.PaneSpec),
    row: ui.Source(m.Row),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = InfoRow;
    pub const __yix_preview_mount = __yix_InfoRow;
};
fn __yix_InfoRow(__yix_props: InfoRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const pane = __yix_props.pane;
    const row = __yix_props.row;
    try ui.view.previewCheckSetup(scope, false);
    const tip = __yix_d1: {
        const __yix_T = @TypeOf(helpTipId(row.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return helpTipId(__yix_ctx.row.get());
        } }.__yix_compute);
    };
    const value = __yix_d2: {
        const __yix_T = @TypeOf(vm.peek().infoValue(row.peek()));
        break :__yix_d2 try scope.derive(__yix_T, .{ .vm = vm, .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().infoValue(__yix_ctx.row.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .pane = pane, .row = row, .tip = tip, .value = value, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InfoRow", .receiver = "box", .tokens = "box style = S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ; visible = shown ( vm , pane , row ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "shown ( vm , pane , row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, .tip = __yix_view_ctx.tip, .value = __yix_view_ctx.value, }, ui.view.box(.{ .style = S.SettingRow.of(.{ .last = __yix_d3: {
        const __yix_T = @TypeOf(last(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return last(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    } }), .visible = __yix_d4: {
        const __yix_T = @TypeOf(shown(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return shown(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InfoRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .value = __yix_view_ctx.value, }, ui.view.box(.{ .style = S.setting_line, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InfoRow", .receiver = "text", .tokens = "text style = @static; box = S . info_label_box ; label ( row )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_label ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . info_label_box ", .kind = .property, .literal = null }, } }, .{ .row = __yix_view_ctx.row, }, ui.view.text(.{ .style = S.setting_label, .box = S.info_label_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d5: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d5: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InfoRow", .receiver = "control", .tokens = "if ( vm . infoIsPath ( row ) ) < W . Tooltip text = { vm . infoValue ( row ) } width = { 292 } open = { popup ( vm , tip ) } onOpenChange = { | o | setPopup ( vm , tip , o ) } parts = { . { . content = tip } } > < box testId = { fieldId ( row ) } style = { S . info_value_box } focusable = { true } a11y = { . { . label = value } } onFocus = { setPopup ( vm , tip , true ) } onBlur = { setPopup ( vm , tip , false ) } > < text style = { S . info_path } box = { S . info_path_box } > { vm . infoValue ( row ) } < / text > < / box > < / W . Tooltip > else < text style = { S . info_value } box = { S . info_value_box } > { vm . infoValue ( row ) } < / text > " }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .tip = __yix_view_ctx.tip, .value = __yix_view_ctx.value, }, ui.view.lazyIf(__yix_d6: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().infoIsPath(__yix_view_ctx.row.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().infoIsPath(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .tip = __yix_view_ctx.tip, .value = __yix_view_ctx.value, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InfoRow/keyword_if:1/branch:0", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { vm . infoValue ( row ) } width = { 292 } open = { popup ( vm , tip ) } onOpenChange = { | o | setPopup ( vm , tip , o ) } parts = { . { . content = tip } } > < box testId = { fieldId ( row ) } style = { S . info_value_box } focusable = { true } a11y = { . { . label = value } } onFocus = { setPopup ( vm , tip , true ) } onBlur = { setPopup ( vm , tip , false ) } > < text style = { S . info_path } box = { S . info_path_box } > { vm . infoValue ( row ) } < / text > < / box > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "vm . infoValue ( row ) ", .kind = .property, .literal = null }, .{ .name = "width", .tokens = "292 ", .kind = .property, .literal = .{ .number = 292 } }, .{ .name = "open", .tokens = "popup ( vm , tip ) ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | setPopup ( vm , tip , o ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . content = tip } ", .kind = .property, .literal = null }, } }, .{ .tip = __yix_b1_0.tip, .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, .value = __yix_b1_0.value, }, ui.view.templateAttrs(.{ .parts = .{ .content = __yix_b1_0.tip }, }, __yix_builder_24: { try ui.view.previewCheckBuilder(__yix_bs1_0, W.Tooltip); break :__yix_builder_24 ui.view.with(W.Tooltip(.{ .text = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(__yix_b1_0.vm.peek().infoValue(__yix_b1_0.row.peek()));
        break :__yix_d1 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().infoValue(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .width = 292, .open = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "open")) |__yix_A| __yix_A else @TypeOf(popup(__yix_b1_0.vm.peek(), __yix_b1_0.tip.peek()));
        break :__yix_d2 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, .tip = __yix_b1_0.tip, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return popup(__yix_ctx.vm.get(), __yix_ctx.tip.get());
        } }.__yix_compute);
    }, .on_open_change = ui.view.eventProp(W.Tooltip, "on_open_change", try ui.on.bindAny(__yix_bs1_0, .{ .vm = __yix_b1_0.vm, .tip = __yix_b1_0.tip, .__yix_owner = __yix_bs1_0.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), o);  } }.__yix_run)), }), .{
                        ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InfoRow/keyword_if:1/branch:0", .receiver = "box", .tokens = "box testId = fieldId ( row ) ; style = @static; focusable = @static; a11y = . { . label = value } ; onFocus = setPopup ( vm , tip , true ) ; onBlur = setPopup ( vm , tip , false ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "fieldId ( row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . info_value_box ", .kind = .style, .literal = null }, .{ .name = "focusable", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "a11y", .tokens = ". { . label = value } ", .kind = .property, .literal = null }, .{ .name = "on_focus", .tokens = "setPopup ( vm , tip , true ) ", .kind = .event, .literal = null }, .{ .name = "on_blur", .tokens = "setPopup ( vm , tip , false ) ", .kind = .event, .literal = null }, } }, .{ .row = __yix_b1_0.row, .value = __yix_b1_0.value, .vm = __yix_b1_0.vm, .tip = __yix_b1_0.tip, }, ui.view.box(.{ .test_id = __yix_d3: {
        const __yix_T = @TypeOf(fieldId(__yix_b1_0.row.peek()));
        break :__yix_d3 try __yix_bs1_0.derive(__yix_T, .{ .row = __yix_b1_0.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = S.info_value_box, .focusable = true, .a11y = .{ .label = __yix_b1_0.value }, .on_focus = try ui.on.bind(__yix_bs1_0, .{ .vm = __yix_b1_0.vm, .tip = __yix_b1_0.tip, .__yix_owner = __yix_bs1_0.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), true);  } }.__yix_run), .on_blur = try ui.on.bind(__yix_bs1_0, .{ .vm = __yix_b1_0.vm, .tip = __yix_b1_0.tip, .__yix_owner = __yix_bs1_0.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), false);  } }.__yix_run), }, .{
                            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InfoRow/keyword_if:1/branch:0", .receiver = "text", .tokens = "text style = @static; box = S . info_path_box ; vm . infoValue ( row )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . info_path ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . info_path_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, }, ui.view.text(.{ .style = S.info_path, .box = S.info_path_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d4: {
        const __yix_T = @TypeOf(__yix_b1_0.vm.peek().infoValue(__yix_b1_0.row.peek()));
        break :__yix_d4 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().infoValue(__yix_ctx.row.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d4: {
        const __yix_T = @TypeOf(__yix_b1_0.vm.peek().infoValue(__yix_b1_0.row.peek()));
        break :__yix_d4 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().infoValue(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }))),
                        })),
                    }); })) }); } }.__yix_b, struct { fn __yix_b(__yix_b1_1: anytype, __yix_bs1_1: *ui.Scope, __yix_bc1_1: *ui.Cx, __yix_bk1_1: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_1, __yix_bc1_1, __yix_bk1_1, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "InfoRow/keyword_if:1/branch:1", .receiver = "text", .tokens = "text style = @static; box = S . info_value_box ; vm . infoValue ( row )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . info_value ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . info_value_box ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_b1_1.vm, .row = __yix_b1_1.row, }, ui.view.text(.{ .style = S.info_value, .box = S.info_value_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d5: {
        const __yix_T = @TypeOf(__yix_b1_1.vm.peek().infoValue(__yix_b1_1.row.peek()));
        break :__yix_d5 try __yix_bs1_1.derive(__yix_T, .{ .vm = __yix_b1_1.vm, .row = __yix_b1_1.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().infoValue(__yix_ctx.row.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d5: {
        const __yix_T = @TypeOf(__yix_b1_1.vm.peek().infoValue(__yix_b1_1.row.peek()));
        break :__yix_d5 try __yix_bs1_1.derive(__yix_T, .{ .vm = __yix_b1_1.vm, .row = __yix_b1_1.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().infoValue(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }))) }); } }.__yix_b)),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "InfoRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 动作行：标签 + 原生按钮（危险操作用 danger 色调）；不可用且有原因时悬停 / 聚焦说明原因（`<按钮 id>.tooltip`）。
pub fn ActionRow(args: anytype) ui.view.ComponentOf(__yix_ActionRow) {
    return ui.view.component(__yix_ActionRow, ui.reactive.props.coerce(ActionRowProps, args));
}
pub const ActionRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    pane: ui.Source(*const m.PaneSpec),
    row: ui.Source(m.Row),
    icon: ui.Source(?ui.SvgAsset),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ActionRow;
    pub const __yix_preview_mount = __yix_ActionRow;
};
fn __yix_ActionRow(__yix_props: ActionRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const pane = __yix_props.pane;
    const row = __yix_props.row;
    const icon = __yix_props.icon;
    try ui.view.previewCheckSetup(scope, false);
    const tip = __yix_d1: {
        const __yix_T = @TypeOf(buttonTipId(row.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return buttonTipId(__yix_ctx.row.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .pane = pane, .row = row, .icon = icon, .tip = tip, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ActionRow", .receiver = "box", .tokens = "box style = S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ; visible = shown ( vm , pane , row ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "shown ( vm , pane , row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, .tip = __yix_view_ctx.tip, .icon = __yix_view_ctx.icon, }, ui.view.box(.{ .style = S.SettingRow.of(.{ .last = __yix_d2: {
        const __yix_T = @TypeOf(last(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return last(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    } }), .visible = __yix_d3: {
        const __yix_T = @TypeOf(shown(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return shown(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ActionRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .icon = __yix_view_ctx.icon, }, ui.view.box(.{ .style = S.setting_line, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ActionRow", .receiver = "text", .tokens = "text style = @static; box = S . info_label_box ; label ( row )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_label ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . info_label_box ", .kind = .property, .literal = null }, } }, .{ .row = __yix_view_ctx.row, }, ui.view.text(.{ .style = S.setting_label, .box = S.info_label_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d4: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d4: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ActionRow", .receiver = "control", .tokens = "if ( hasReason ( vm , row ) ) < W . Tooltip text = { vm . actionReason ( row ) } parts = { . { . content = tip } } > < ActionButton vm = { vm } row = { row } icon = { icon } / > < / W . Tooltip > else < ActionButton vm = { vm } row = { row } icon = { icon } / > " }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .tip = __yix_view_ctx.tip, .icon = __yix_view_ctx.icon, }, ui.view.lazyIf(__yix_d2: {
        const __yix_T = @TypeOf(hasReason(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return hasReason(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .icon = __yix_view_ctx.icon, .tip = __yix_view_ctx.tip, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ActionRow/keyword_if:1/branch:0", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { vm . actionReason ( row ) } parts = { . { . content = tip } } > < ActionButton vm = { vm } row = { row } icon = { icon } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "vm . actionReason ( row ) ", .kind = .property, .literal = null }, .{ .name = "parts", .tokens = ". { . content = tip } ", .kind = .property, .literal = null }, } }, .{ .tip = __yix_b1_0.tip, .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, .icon = __yix_b1_0.icon, }, ui.view.templateAttrs(.{ .parts = .{ .content = __yix_b1_0.tip }, }, __yix_builder_24: { try ui.view.previewCheckBuilder(__yix_bs1_0, W.Tooltip); break :__yix_builder_24 ui.view.with(W.Tooltip(.{ .text = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(__yix_b1_0.vm.peek().actionReason(__yix_b1_0.row.peek()));
        break :__yix_d1 try __yix_bs1_0.derive(__yix_T, .{ .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().actionReason(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }), .{
                        ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ActionRow/keyword_if:1/branch:0", .receiver = "ActionButton", .tokens = "< ActionButton vm = { vm } row = { row } icon = { icon } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, .{ .name = "icon", .tokens = "icon ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, .icon = __yix_b1_0.icon, }, __yix_builder_112: { try ui.view.previewCheckBuilder(__yix_bs1_0, ActionButton); break :__yix_builder_112 ActionButton(.{ .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, .icon = __yix_b1_0.icon, }); }),
                    }); })) }); } }.__yix_b, struct { fn __yix_b(__yix_b1_1: anytype, __yix_bs1_1: *ui.Scope, __yix_bc1_1: *ui.Cx, __yix_bk1_1: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_1, __yix_bc1_1, __yix_bk1_1, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ActionRow/keyword_if:1/branch:1", .receiver = "ActionButton", .tokens = "< ActionButton vm = { vm } row = { row } icon = { icon } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, .{ .name = "icon", .tokens = "icon ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_b1_1.vm, .row = __yix_b1_1.row, .icon = __yix_b1_1.icon, }, __yix_builder_193: { try ui.view.previewCheckBuilder(__yix_bs1_1, ActionButton); break :__yix_builder_193 ActionButton(.{ .vm = __yix_b1_1.vm, .row = __yix_b1_1.row, .icon = __yix_b1_1.icon, }); }) }); } }.__yix_b)),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ActionRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}
fn ActionButton(args: anytype) ui.view.ComponentOf(__yix_ActionButton) {
    return ui.view.component(__yix_ActionButton, ui.reactive.props.coerce(ActionButtonProps, args));
}
const ActionButtonProps = struct {
    vm: ui.Source(*m.ViewModel),
    row: ui.Source(m.Row),
    icon: ui.Source(?ui.SvgAsset),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ActionButton;
    pub const __yix_preview_mount = __yix_ActionButton;
};
fn __yix_ActionButton(__yix_props: ActionButtonProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const row = __yix_props.row;
    const icon = __yix_props.icon;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .row = row, .icon = icon, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ActionButton", .receiver = "W.Button", .tokens = "< W . Button testId = { fieldId ( row ) } label = { buttonLabel ( row ) } variant = { variant ( row ) } size = { . sm } iconAsset = { icon } iconSize = { 14 } a11yLabel = { actionA11y ( vm , row ) } disabled = { ! vm . actionEnabled ( row ) } focusId = { actionFocus ( row ) } onClick = { send ( vm , m . Intent . runCommand ( row . command . ? ) ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "fieldId ( row ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "buttonLabel ( row ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = "variant ( row ) ", .kind = .property, .literal = null }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "icon_asset", .tokens = "icon ", .kind = .property, .literal = null }, .{ .name = "icon_size", .tokens = "14 ", .kind = .property, .literal = .{ .number = 14 } }, .{ .name = "a11y_label", .tokens = "actionA11y ( vm , row ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "! vm . actionEnabled ( row ) ", .kind = .property, .literal = null }, .{ .name = "focus_id", .tokens = "actionFocus ( row ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , m . Intent . runCommand ( row . command . ? ) ) ", .kind = .event, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .row = __yix_view_ctx.row, .icon = __yix_view_ctx.icon, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(fieldId(__yix_view_ctx.row.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .focus_id = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Button, "focus_id")) |__yix_A| __yix_A else @TypeOf(actionFocus(__yix_view_ctx.row.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return actionFocus(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }, __yix_builder_17086: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_17086 W.Button(.{ .label = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Button, "label")) |__yix_A| __yix_A else @TypeOf(buttonLabel(__yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return buttonLabel(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .variant = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Button, "variant")) |__yix_A| __yix_A else @TypeOf(variant(__yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return variant(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .size = .sm, .icon_asset = __yix_view_ctx.icon, .icon_size = 14, .a11y_label = __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Button, "a11y_label")) |__yix_A| __yix_A else @TypeOf(actionA11y(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return actionA11y(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, .disabled = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(!__yix_view_ctx.vm.peek().actionEnabled(__yix_view_ctx.row.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !__yix_ctx.vm.get().actionEnabled(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), m.Intent.runCommand(__yix_ctx.row.peek().command.?));  } }.__yix_run) else __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), m.Intent.runCommand(__yix_view_ctx.row.peek().command.?)));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), m.Intent.runCommand(__yix_ctx.row.get().command.?));
        } }.__yix_compute);
    }, }); })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ActionButton";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}
fn hasReason(vm: *m.ViewModel, row: m.Row) bool {
    return vm.actionReason(row).len != 0;
}
fn buttonLabel(row: m.Row) []const u8 {
    return row.button;
}
fn buttonTipId(row: m.Row) []const u8 {
    return row.ids.button_tip;
}
fn variant(row: m.Row) W.ButtonVariant {
    return if (row.danger) .danger else .secondary;
}
fn actionA11y(vm: *m.ViewModel, row: m.Row) []const u8 {
    const reason = vm.actionReason(row);
    return if (reason.len != 0) reason else row.button;
}
/// 清理按钮的焦点标识（清理流程结束 / 取消后宿主经 `requestFocus` 回焦）；其它按钮没有。
fn actionFocus(row: m.Row) []const u8 {
    const command = row.command orelse return "";
    return switch (command) {
        .clear_all => m.focus_ids.data_clear_all,
        .clear_logs => m.focus_ids.data_clear_logs,
        else => "",
    };
}
/// 开关的无障碍属性（原生 `label` 会把文字画在开关旁边，所以名字只进 a11y，同旧 `a11y.label = label`）。
fn switchA11y(vm: *m.ViewModel, row: m.Row) ?ui.A11yProps {
    return .{ .role = .switch_role, .label = row.label, .checked = vm.boolOf(row.key.?), .disabled = vm.fieldDisabled(row) };
}

// ── 快捷键行（P3 3e 第二批，人工验收反馈第 7 条；交互设计见 docs/ui-revamp/YIX_SPIKE.md“快捷键行的编辑交互”） ──
//
//     KeybindingRow(vm: *m.ViewModel, pane: *const m.PaneSpec, row: m.Row)   // row = m.fields.keys.row(<动作>)
//
// 动作名（固定动作带锁、改过未保存带“未保存”徽标）+ 键帽区（原生 `W.Pressable`：原生 `W.Kbd` 键帽，每个修饰键 / 主键一个，
// 录制 / 无效 / 冲突用它的 accent / danger / warning 色调；
// 淡色铅笔；悬停 / 聚焦有原生 Tooltip）+ 行尾单行恢复默认（原生 ghost 图标按钮）；行下是无效原因或冲突提示与【交换】【取消】。
// 录制状态是 view-model 的 `key_edit` 信号，键帽区的 `onKeyDown`（组件根捕获槽）把按键交给 `vm.keyDown`；
// 焦点离开键帽区（Tab、点别处）由它的 `onBlurWithin` 结束录制（G31；冲突态只是不再接按键）。

fn act(row: m.Row) m.KeyAction {
    return row.shortcut.?;
}
fn isFixed(row: m.Row) bool {
    return m.keybinding_edit.fixed(row.shortcut.?);
}
fn markId(row: m.Row) []const u8 {
    return row.ids.mark;
}
fn resetId(row: m.Row) []const u8 {
    return row.ids.reset;
}
fn resetTipId(row: m.Row) []const u8 {
    return row.ids.reset_tip;
}
fn swapId(row: m.Row) []const u8 {
    return row.ids.swap;
}
fn cancelId(row: m.Row) []const u8 {
    return row.ids.cancel;
}
fn fixedTipId(row: m.Row) []const u8 {
    return row.ids.button_tip;
}
fn capTone(vm: *m.ViewModel, row: m.Row) W.KbdTone {
    return switch (vm.keyTone(row.shortcut.?)) {
        .rest => .neutral,
        .recording => .accent,
        .invalid => .danger,
        .conflict => .warning,
    };
}
/// 键帽区的提示只在静止时打开：录制 / 无效 / 冲突时行内已有说明，而且打开着的提示会先吃掉 Escape（框架先收起提示），
/// 用户按一次 Esc 就该取消录制。
fn tipOpen(vm: *m.ViewModel, row: m.Row, id: []const u8) bool {
    return vm.popupOpen(id) and !vm.keyActive(row.shortcut.?);
}
fn pencilShown(vm: *m.ViewModel, row: m.Row) bool {
    return vm.keyEditable(row.shortcut.?) and !vm.keyActive(row.shortcut.?);
}
fn invalidShown(vm: *m.ViewModel, row: m.Row) bool {
    return vm.keyPhase(row.shortcut.?) == .invalid;
}
fn keyDown(vm: *m.ViewModel, row: m.Row, e: ui.view.KeyPress) void {
    if (vm.keyDown(row.shortcut.?, e.key, e.modifiers)) e.stop();
}
fn keyUp(vm: *m.ViewModel, row: m.Row, e: ui.view.KeyPress) void {
    if (vm.keyUp(row.shortcut.?, e.key, e.modifiers)) e.stop();
}
/// 固定动作的锁：原生 ghost 图标按钮 + 原生 Tooltip “保留给应用，不可修改”（同旧 `controls.inlineHint`；悬停 / 聚焦 / 点击打开）。
/// 聚焦开合写在外层盒子的 `onFocusWithin` / `onBlurWithin`（G31）：焦点落在里面的按钮上，盒子自己的 `onFocus` / `onBlur` 收不到。
fn FixedHint(args: anytype) ui.view.ComponentOf(__yix_FixedHint) {
    return ui.view.component(__yix_FixedHint, ui.reactive.props.coerce(FixedHintProps, args));
}
const FixedHintProps = struct {
    vm: ui.Source(*m.ViewModel),
    row: ui.Source(m.Row),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = FixedHint;
    pub const __yix_preview_mount = __yix_FixedHint;
};
fn __yix_FixedHint(__yix_props: FixedHintProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const row = __yix_props.row;
    try ui.view.previewCheckSetup(scope, false);
    const tip = __yix_d1: {
        const __yix_T = @TypeOf(fixedTipId(row.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fixedTipId(__yix_ctx.row.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .row = row, .tip = tip, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "FixedHint", .receiver = "box", .tokens = "box style = @static; onFocusWithin = setPopup ( vm , tip , true ) ; onBlurWithin = setPopup ( vm , tip , false ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . help_slot ", .kind = .style, .literal = null }, .{ .name = "on_focus_within", .tokens = "setPopup ( vm , tip , true ) ", .kind = .event, .literal = null }, .{ .name = "on_blur_within", .tokens = "setPopup ( vm , tip , false ) ", .kind = .event, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .row = __yix_view_ctx.row, }, ui.view.box(.{ .style = S.help_slot, .on_focus_within = try ui.on.bind(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), true);  } }.__yix_run), .on_blur_within = try ui.on.bind(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), false);  } }.__yix_run), }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "FixedHint", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = \"保留给应用，不可修改\" position = { . top } width = { 292 } open = { popup ( vm , tip ) } onOpenChange = { | o | setPopup ( vm , tip , o ) } parts = { . { . content = tip } } > < W . Button testId = { helpId ( row ) } variant = { . ghost } size = { . xs } iconOnly = { true } iconAsset = { ui . icons . lock } iconSize = { 14 } a11yLabel = \"保留给应用，不可修改\" onClick = { setPopup ( vm , tip , true ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "\"保留给应用，不可修改\" ", .kind = .property, .literal = .{ .text = "保留给应用，不可修改" } }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, .{ .name = "width", .tokens = "292 ", .kind = .property, .literal = .{ .number = 292 } }, .{ .name = "open", .tokens = "popup ( vm , tip ) ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | setPopup ( vm , tip , o ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . content = tip } ", .kind = .property, .literal = null }, } }, .{ .tip = __yix_view_ctx.tip, .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.templateAttrs(.{ .parts = .{ .content = __yix_view_ctx.tip }, }, __yix_builder_21712: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_21712 ui.view.with(W.Tooltip(.{ .text = "保留给应用，不可修改", .position = .top, .width = 292, .open = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "open")) |__yix_A| __yix_A else @TypeOf(popup(__yix_view_ctx.vm.peek(), __yix_view_ctx.tip.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return popup(__yix_ctx.vm.get(), __yix_ctx.tip.get());
        } }.__yix_compute);
    }, .on_open_change = ui.view.eventProp(W.Tooltip, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), o);  } }.__yix_run)), }), .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "FixedHint", .receiver = "W.Button", .tokens = "< W . Button testId = { helpId ( row ) } variant = { . ghost } size = { . xs } iconOnly = { true } iconAsset = { ui . icons . lock } iconSize = { 14 } a11yLabel = \"保留给应用，不可修改\" onClick = { setPopup ( vm , tip , true ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "helpId ( row ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". xs ", .kind = .property, .literal = .{ .enum_name = "xs" } }, .{ .name = "icon_only", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "icon_asset", .tokens = "ui . icons . lock ", .kind = .property, .literal = null }, .{ .name = "icon_size", .tokens = "14 ", .kind = .property, .literal = .{ .number = 14 } }, .{ .name = "a11y_label", .tokens = "\"保留给应用，不可修改\" ", .kind = .property, .literal = .{ .text = "保留给应用，不可修改" } }, .{ .name = "on_click", .tokens = "setPopup ( vm , tip , true ) ", .kind = .event, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, }, ui.view.templateAttrs(.{ .test_id = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(helpId(__yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return helpId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }, __yix_builder_21896: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_21896 W.Button(.{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = ui.icons.lock, .icon_size = 14, .a11y_label = "保留给应用，不可修改", .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), true);  } }.__yix_run) else __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(setPopup(__yix_view_ctx.vm.peek(), __yix_view_ctx.tip.peek(), true));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return setPopup(__yix_ctx.vm.get(), __yix_ctx.tip.get(), true);
        } }.__yix_compute);
    }, }); })),
            }); })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "FixedHint";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}


pub fn KeybindingRow(args: anytype) ui.view.ComponentOf(__yix_KeybindingRow) {
    return ui.view.component(__yix_KeybindingRow, ui.reactive.props.coerce(KeybindingRowProps, args));
}
pub const KeybindingRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    pane: ui.Source(*const m.PaneSpec),
    row: ui.Source(m.Row),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = KeybindingRow;
    pub const __yix_preview_mount = __yix_KeybindingRow;
};
fn __yix_KeybindingRow(__yix_props: KeybindingRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const pane = __yix_props.pane;
    const row = __yix_props.row;
    try ui.view.previewCheckSetup(scope, false);
    const tip = __yix_d1: {
        const __yix_T = @TypeOf(helpTipId(row.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return helpTipId(__yix_ctx.row.get());
        } }.__yix_compute);
    };
    const reset_tip = __yix_d2: {
        const __yix_T = @TypeOf(resetTipId(row.peek()));
        break :__yix_d2 try scope.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return resetTipId(__yix_ctx.row.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .pane = pane, .row = row, .tip = tip, .reset_tip = reset_tip, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "box", .tokens = "box testId = rowId ( row ) ; style = S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ; visible = shown ( vm , pane , row ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "rowId ( row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "shown ( vm , pane , row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .tip = __yix_view_ctx.tip, .reset_tip = __yix_view_ctx.reset_tip, }, ui.view.box(.{ .test_id = __yix_d3: {
        const __yix_T = @TypeOf(rowId(__yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return rowId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = S.SettingRow.of(.{ .last = __yix_d4: {
        const __yix_T = @TypeOf(last(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return last(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    } }), .visible = __yix_d5: {
        const __yix_T = @TypeOf(shown(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return shown(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .reset_tip = __yix_view_ctx.reset_tip, }, ui.view.box(.{ .style = S.setting_line, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_heading ", .kind = .style, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .style = S.setting_heading, }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "text", .tokens = "text style = @static; label ( row )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_label ", .kind = .style, .literal = null }, } }, .{ .row = __yix_view_ctx.row, }, ui.view.text(.{ .style = S.setting_label, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d6: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d6: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }))),
                    ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "control", .tokens = "if ( isFixed ( row ) ) < FixedHint vm = { vm } row = { row } / > " }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.lazyIf(__yix_d1: {
        const __yix_T = @TypeOf(isFixed(__yix_view_ctx.row.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return isFixed(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow/keyword_if:1/branch:0", .receiver = "FixedHint", .tokens = "< FixedHint vm = { vm } row = { row } / > ", .literal_text = null, .attributes = &.{ .{ .name = "vm", .tokens = "vm ", .kind = .property, .literal = null }, .{ .name = "row", .tokens = "row ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, }, __yix_builder_18: { try ui.view.previewCheckBuilder(__yix_bs1_0, FixedHint); break :__yix_builder_18 FixedHint(.{ .vm = __yix_b1_0.vm, .row = __yix_b1_0.row, }); }) }); } }.__yix_b, null)),
                    ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "W.Badge", .tokens = "< W . Badge testId = { markId ( row ) } label = \"未保存\" status = { . info } size = { . sm } visible = { vm . keyModified ( act ( row ) ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "markId ( row ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"未保存\" ", .kind = .property, .literal = .{ .text = "未保存" } }, .{ .name = "status", .tokens = ". info ", .kind = .property, .literal = .{ .enum_name = "info" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "visible", .tokens = "vm . keyModified ( act ( row ) ) ", .kind = .property, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Badge, "test_id")) |__yix_A| __yix_A else @TypeOf(markId(__yix_view_ctx.row.peek()));
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return markId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .visible = __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Badge, "visible")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().keyModified(act(__yix_view_ctx.row.peek())));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyModified(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, }, __yix_builder_22703: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Badge); break :__yix_builder_22703 W.Badge(.{ .label = "未保存", .status = .info, .size = .sm, }); })),
                })),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "K . key_slot ", .kind = .style, .literal = null }, } }, .{ .tip = __yix_view_ctx.tip, .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.box(.{ .style = K.key_slot, }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = { vm . keyTip ( act ( row ) ) } position = { . top } open = { tipOpen ( vm , row , tip ) } onOpenChange = { | o | setPopup ( vm , tip , o ) } parts = { . { . content = tip } } > < W . Pressable testId = { fieldId ( row ) } focusId = { focusId ( row ) } a11yLabel = { vm . keyA11y ( act ( row ) ) } disabled = { ! vm . keyEditable ( act ( row ) ) } selected = { vm . keyActive ( act ( row ) ) } style = { K . KeyArea . of ( . { . tone = vm . keyTone ( act ( row ) ) , . fixed = isFixed ( row ) } ) } onClick = { send ( vm , m . Intent . recordKey ( act ( row ) ) ) } onBlurWithin = { send ( vm , m . Intent . blurKey ( act ( row ) ) ) } onKeyDown = { | e | keyDown ( vm , row , e ) } onKeyUp = { | e | keyUp ( vm , row , e ) } > < W . Kbd keys = { vm . keyCaps ( act ( row ) ) } tone = { capTone ( vm , row ) } / > < text style = { K . key_prompt } visible = { vm . keyRecording ( act ( row ) ) } > 按下新快捷键…</text> < text style = { K . key_escape } visible = { vm . keyRecording ( act ( row ) ) } > Esc 取消</text> < icon src = { ui . icons . pencil } style = { K . key_pencil } visible = { pencilShown ( vm , row ) } / > < / W . Pressable > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "vm . keyTip ( act ( row ) ) ", .kind = .property, .literal = null }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, .{ .name = "open", .tokens = "tipOpen ( vm , row , tip ) ", .kind = .property, .literal = null }, .{ .name = "on_open_change", .tokens = "| o | setPopup ( vm , tip , o ) ", .kind = .event, .literal = null }, .{ .name = "parts", .tokens = ". { . content = tip } ", .kind = .property, .literal = null }, } }, .{ .tip = __yix_view_ctx.tip, .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.templateAttrs(.{ .parts = .{ .content = __yix_view_ctx.tip }, }, __yix_builder_22899: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_22899 ui.view.with(W.Tooltip(.{ .text = __yix_d9: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "text")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().keyTip(act(__yix_view_ctx.row.peek())));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyTip(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, .position = .top, .open = __yix_d10: {
        const __yix_T = if (ui.view.attrType(W.Tooltip, "open")) |__yix_A| __yix_A else @TypeOf(tipOpen(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek(), __yix_view_ctx.tip.peek()));
        break :__yix_d10 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .tip = __yix_view_ctx.tip, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return tipOpen(__yix_ctx.vm.get(), __yix_ctx.row.get(), __yix_ctx.tip.get());
        } }.__yix_compute);
    }, .on_open_change = ui.view.eventProp(W.Tooltip, "on_open_change", try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .tip = __yix_view_ctx.tip, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, o: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); setPopup(__yix_ctx.vm.peek(), __yix_ctx.tip.peek(), o);  } }.__yix_run)), }), .{
                        ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "W.Pressable", .tokens = "< W . Pressable testId = { fieldId ( row ) } focusId = { focusId ( row ) } a11yLabel = { vm . keyA11y ( act ( row ) ) } disabled = { ! vm . keyEditable ( act ( row ) ) } selected = { vm . keyActive ( act ( row ) ) } style = { K . KeyArea . of ( . { . tone = vm . keyTone ( act ( row ) ) , . fixed = isFixed ( row ) } ) } onClick = { send ( vm , m . Intent . recordKey ( act ( row ) ) ) } onBlurWithin = { send ( vm , m . Intent . blurKey ( act ( row ) ) ) } onKeyDown = { | e | keyDown ( vm , row , e ) } onKeyUp = { | e | keyUp ( vm , row , e ) } > < W . Kbd keys = { vm . keyCaps ( act ( row ) ) } tone = { capTone ( vm , row ) } / > < text style = { K . key_prompt } visible = { vm . keyRecording ( act ( row ) ) } > 按下新快捷键…</text> < text style = { K . key_escape } visible = { vm . keyRecording ( act ( row ) ) } > Esc 取消</text> < icon src = { ui . icons . pencil } style = { K . key_pencil } visible = { pencilShown ( vm , row ) } / > < / W . Pressable > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "fieldId ( row ) ", .kind = .property, .literal = null }, .{ .name = "focus_id", .tokens = "focusId ( row ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "vm . keyA11y ( act ( row ) ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "! vm . keyEditable ( act ( row ) ) ", .kind = .property, .literal = null }, .{ .name = "selected", .tokens = "vm . keyActive ( act ( row ) ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "K . KeyArea . of ( . { . tone = vm . keyTone ( act ( row ) ) , . fixed = isFixed ( row ) } ) ", .kind = .style, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , m . Intent . recordKey ( act ( row ) ) ) ", .kind = .event, .literal = null }, .{ .name = "on_blur_within", .tokens = "send ( vm , m . Intent . blurKey ( act ( row ) ) ) ", .kind = .event, .literal = null }, .{ .name = "on_key_down", .tokens = "| e | keyDown ( vm , row , e ) ", .kind = .event, .literal = null }, .{ .name = "on_key_up", .tokens = "| e | keyUp ( vm , row , e ) ", .kind = .event, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = __yix_d11: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "test_id")) |__yix_A| __yix_A else @TypeOf(fieldId(__yix_view_ctx.row.peek()));
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .focus_id = __yix_d12: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "focus_id")) |__yix_A| __yix_A else @TypeOf(focusId(__yix_view_ctx.row.peek()));
        break :__yix_d12 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return focusId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = K.KeyArea.of(.{ .tone = __yix_d16: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().keyTone(act(__yix_view_ctx.row.peek())));
        break :__yix_d16 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyTone(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, .fixed = __yix_d17: {
        const __yix_T = @TypeOf(isFixed(__yix_view_ctx.row.peek()));
        break :__yix_d17 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return isFixed(__yix_ctx.row.get());
        } }.__yix_compute);
    } }), .on_blur_within = if (comptime ui.view.isEventProp(W.Pressable, "on_blur_within")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), m.Intent.blurKey(act(__yix_ctx.row.peek())));  } }.__yix_run) else __yix_d19: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "on_blur_within")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), m.Intent.blurKey(act(__yix_view_ctx.row.peek()))));
        break :__yix_d19 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), m.Intent.blurKey(act(__yix_ctx.row.get())));
        } }.__yix_compute);
    }, .on_key_down = try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, e: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); keyDown(__yix_ctx.vm.peek(), __yix_ctx.row.peek(), e);  } }.__yix_run), .on_key_up = try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype, e: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); keyUp(__yix_ctx.vm.peek(), __yix_ctx.row.peek(), e);  } }.__yix_run), }, __yix_builder_23075: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Pressable); break :__yix_builder_23075 ui.view.with(W.Pressable(.{ .a11y_label = __yix_d13: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "a11y_label")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().keyA11y(act(__yix_view_ctx.row.peek())));
        break :__yix_d13 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyA11y(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, .disabled = __yix_d14: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "disabled")) |__yix_A| __yix_A else @TypeOf(!__yix_view_ctx.vm.peek().keyEditable(act(__yix_view_ctx.row.peek())));
        break :__yix_d14 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return !__yix_ctx.vm.get().keyEditable(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, .selected = __yix_d15: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "selected")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().keyActive(act(__yix_view_ctx.row.peek())));
        break :__yix_d15 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyActive(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Pressable, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), m.Intent.recordKey(act(__yix_ctx.row.peek())));  } }.__yix_run) else __yix_d18: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), m.Intent.recordKey(act(__yix_view_ctx.row.peek()))));
        break :__yix_d18 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), m.Intent.recordKey(act(__yix_ctx.row.get())));
        } }.__yix_compute);
    }, }), .{
                            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "W.Kbd", .tokens = "< W . Kbd keys = { vm . keyCaps ( act ( row ) ) } tone = { capTone ( vm , row ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "keys", .tokens = "vm . keyCaps ( act ( row ) ) ", .kind = .property, .literal = null }, .{ .name = "tone", .tokens = "capTone ( vm , row ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, __yix_builder_23514: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Kbd); break :__yix_builder_23514 W.Kbd(.{ .keys = __yix_d20: {
        const __yix_T = if (ui.view.attrType(W.Kbd, "keys")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().keyCaps(act(__yix_view_ctx.row.peek())));
        break :__yix_d20 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyCaps(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, .tone = __yix_d21: {
        const __yix_T = if (ui.view.attrType(W.Kbd, "tone")) |__yix_A| __yix_A else @TypeOf(capTone(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d21 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return capTone(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }); }),
                            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "text", .tokens = "text style = @static; visible = vm . keyRecording ( act ( row ) ) ; ", .literal_text = "按下新快捷键…", .attributes = &.{ .{ .name = "style", .tokens = "K . key_prompt ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . keyRecording ( act ( row ) ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.text(.{ .style = K.key_prompt, .visible = __yix_d22: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().keyRecording(act(__yix_view_ctx.row.peek())));
        break :__yix_d22 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyRecording(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, }, ui.view.fmt("按下新快捷键…", .{ }))),
                            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "text", .tokens = "text style = @static; visible = vm . keyRecording ( act ( row ) ) ; ", .literal_text = "Esc 取消", .attributes = &.{ .{ .name = "style", .tokens = "K . key_escape ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . keyRecording ( act ( row ) ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.text(.{ .style = K.key_escape, .visible = __yix_d23: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().keyRecording(act(__yix_view_ctx.row.peek())));
        break :__yix_d23 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyRecording(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, }, ui.view.fmt("Esc 取消", .{ }))),
                            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "icon", .tokens = "icon src = ui . icons . pencil ; style = @static; visible = pencilShown ( vm , row ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "ui . icons . pencil ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "K . key_pencil ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "pencilShown ( vm , row ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.icon(.{ .style = K.key_pencil, .visible = __yix_d24: {
        const __yix_T = @TypeOf(pencilShown(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d24 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return pencilShown(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, ui.icons.pencil)),
                        }); })),
                    }); })),
                })),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "K . key_reset_slot ", .kind = .style, .literal = null }, } }, .{ .reset_tip = __yix_view_ctx.reset_tip, .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .style = K.key_reset_slot, }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "W.Tooltip", .tokens = "< W . Tooltip text = \"恢复默认快捷键\" position = { . top } parts = { . { . content = reset_tip } } > < W . Button testId = { resetId ( row ) } visible = { vm . keyResettable ( act ( row ) ) } variant = { . ghost } size = { . xs } iconOnly = { true } iconAsset = { ui . icons . rotate_ccw } iconSize = { 14 } a11yLabel = \"恢复默认快捷键\" onClick = { send ( vm , m . Intent . resetKey ( act ( row ) ) ) } / > < / W . Tooltip > ", .literal_text = null, .attributes = &.{ .{ .name = "text", .tokens = "\"恢复默认快捷键\" ", .kind = .property, .literal = .{ .text = "恢复默认快捷键" } }, .{ .name = "position", .tokens = ". top ", .kind = .property, .literal = .{ .enum_name = "top" } }, .{ .name = "parts", .tokens = ". { . content = reset_tip } ", .kind = .property, .literal = null }, } }, .{ .reset_tip = __yix_view_ctx.reset_tip, .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .parts = .{ .content = __yix_view_ctx.reset_tip }, }, __yix_builder_24078: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Tooltip); break :__yix_builder_24078 ui.view.with(W.Tooltip(.{ .text = "恢复默认快捷键", .position = .top, }), .{
                        ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "W.Button", .tokens = "< W . Button testId = { resetId ( row ) } visible = { vm . keyResettable ( act ( row ) ) } variant = { . ghost } size = { . xs } iconOnly = { true } iconAsset = { ui . icons . rotate_ccw } iconSize = { 14 } a11yLabel = \"恢复默认快捷键\" onClick = { send ( vm , m . Intent . resetKey ( act ( row ) ) ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "resetId ( row ) ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "vm . keyResettable ( act ( row ) ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". xs ", .kind = .property, .literal = .{ .enum_name = "xs" } }, .{ .name = "icon_only", .tokens = "true ", .kind = .property, .literal = .{ .boolean = true } }, .{ .name = "icon_asset", .tokens = "ui . icons . rotate_ccw ", .kind = .property, .literal = null }, .{ .name = "icon_size", .tokens = "14 ", .kind = .property, .literal = .{ .number = 14 } }, .{ .name = "a11y_label", .tokens = "\"恢复默认快捷键\" ", .kind = .property, .literal = .{ .text = "恢复默认快捷键" } }, .{ .name = "on_click", .tokens = "send ( vm , m . Intent . resetKey ( act ( row ) ) ) ", .kind = .event, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = __yix_d25: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(resetId(__yix_view_ctx.row.peek()));
        break :__yix_d25 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return resetId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .visible = __yix_d26: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().keyResettable(act(__yix_view_ctx.row.peek())));
        break :__yix_d26 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyResettable(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, }, __yix_builder_24193: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_24193 W.Button(.{ .variant = .ghost, .size = .xs, .icon_only = true, .icon_asset = ui.icons.rotate_ccw, .icon_size = 14, .a11y_label = "恢复默认快捷键", .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), m.Intent.resetKey(act(__yix_ctx.row.peek())));  } }.__yix_run) else __yix_d27: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), m.Intent.resetKey(act(__yix_view_ctx.row.peek()))));
        break :__yix_d27 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), m.Intent.resetKey(act(__yix_ctx.row.get())));
        } }.__yix_compute);
    }, }); })),
                    }); })),
                })),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "box", .tokens = "box testId = errorId ( row ) ; style = @static; visible = vm . keyProblemShown ( act ( row ) ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "errorId ( row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "K . key_problem ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "vm . keyProblemShown ( act ( row ) ) ", .kind = .property, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .test_id = __yix_d28: {
        const __yix_T = @TypeOf(errorId(__yix_view_ctx.row.peek()));
        break :__yix_d28 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return errorId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = K.key_problem, .visible = __yix_d29: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().keyProblemShown(act(__yix_view_ctx.row.peek())));
        break :__yix_d29 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyProblemShown(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "text", .tokens = "text style = @static; box = K . key_problem_text_box ; visible = invalidShown ( vm , row ) ; vm . keyProblem ( act ( row ) )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "K . key_problem_text ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "K . key_problem_text_box ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "invalidShown ( vm , row ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.text(.{ .style = K.key_problem_text, .box = K.key_problem_text_box, .visible = __yix_d30: {
        const __yix_T = @TypeOf(invalidShown(__yix_view_ctx.vm.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d30 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return invalidShown(__yix_ctx.vm.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d31: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().keyProblem(act(__yix_view_ctx.row.peek())));
        break :__yix_d31 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyProblem(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }), ""), .{ __yix_d31: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().keyProblem(act(__yix_view_ctx.row.peek())));
        break :__yix_d31 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyProblem(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "text", .tokens = "text style = @static; box = K . key_problem_text_box ; visible = vm . keyConflict ( act ( row ) ) ; vm . keyProblem ( act ( row ) )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "K . key_conflict_text ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "K . key_problem_text_box ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "vm . keyConflict ( act ( row ) ) ", .kind = .property, .literal = null }, } }, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, ui.view.text(.{ .style = K.key_conflict_text, .box = K.key_problem_text_box, .visible = __yix_d32: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().keyConflict(act(__yix_view_ctx.row.peek())));
        break :__yix_d32 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyConflict(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d33: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().keyProblem(act(__yix_view_ctx.row.peek())));
        break :__yix_d33 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyProblem(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }), ""), .{ __yix_d33: {
        const __yix_T = @TypeOf(__yix_view_ctx.vm.peek().keyProblem(act(__yix_view_ctx.row.peek())));
        break :__yix_d33 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyProblem(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "W.Button", .tokens = "< W . Button testId = { swapId ( row ) } visible = { vm . keyConflict ( act ( row ) ) } label = \"交换\" variant = { . secondary } size = { . xs } onClick = { send ( vm , m . Intent . swapKey ( ) ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "swapId ( row ) ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "vm . keyConflict ( act ( row ) ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"交换\" ", .kind = .property, .literal = .{ .text = "交换" } }, .{ .name = "variant", .tokens = ". secondary ", .kind = .property, .literal = .{ .enum_name = "secondary" } }, .{ .name = "size", .tokens = ". xs ", .kind = .property, .literal = .{ .enum_name = "xs" } }, .{ .name = "on_click", .tokens = "send ( vm , m . Intent . swapKey ( ) ) ", .kind = .event, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = __yix_d34: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(swapId(__yix_view_ctx.row.peek()));
        break :__yix_d34 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return swapId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .visible = __yix_d35: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().keyConflict(act(__yix_view_ctx.row.peek())));
        break :__yix_d35 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyConflict(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, }, __yix_builder_24919: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_24919 W.Button(.{ .label = "交换", .variant = .secondary, .size = .xs, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), m.Intent.swapKey());  } }.__yix_run) else __yix_d36: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), m.Intent.swapKey()));
        break :__yix_d36 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), m.Intent.swapKey());
        } }.__yix_compute);
    }, }); })),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "KeybindingRow", .receiver = "W.Button", .tokens = "< W . Button testId = { cancelId ( row ) } visible = { vm . keyConflict ( act ( row ) ) } label = \"取消\" variant = { . ghost } size = { . xs } onClick = { send ( vm , m . Intent . cancelKey ( ) ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "cancelId ( row ) ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "vm . keyConflict ( act ( row ) ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "\"取消\" ", .kind = .property, .literal = .{ .text = "取消" } }, .{ .name = "variant", .tokens = ". ghost ", .kind = .property, .literal = .{ .enum_name = "ghost" } }, .{ .name = "size", .tokens = ". xs ", .kind = .property, .literal = .{ .enum_name = "xs" } }, .{ .name = "on_click", .tokens = "send ( vm , m . Intent . cancelKey ( ) ) ", .kind = .event, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = __yix_d37: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(cancelId(__yix_view_ctx.row.peek()));
        break :__yix_d37 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return cancelId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .visible = __yix_d38: {
        const __yix_T = if (ui.view.attrType(W.Button, "visible")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().keyConflict(act(__yix_view_ctx.row.peek())));
        break :__yix_d38 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().keyConflict(act(__yix_ctx.row.get()));
        } }.__yix_compute);
    }, }, __yix_builder_25090: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_25090 W.Button(.{ .label = "取消", .variant = .ghost, .size = .xs, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), m.Intent.cancelKey());  } }.__yix_run) else __yix_d39: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), m.Intent.cancelKey()));
        break :__yix_d39 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), m.Intent.cancelKey());
        } }.__yix_compute);
    }, }); })),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "KeybindingRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

// ── 关于与更新用到的行（P3 3e 第二批） ──
//
//     ValueRow(vm, pane, row: m.Row, value: Text)                 // 标签 + 右侧只读值（值由调用方给，跟随信号）
//     LinkRow(vm, pane, row: m.Row, icon: ?ui.SvgAsset)           // 标签 + 原生 link 按钮（`row.button` / `row.command`）

/// 只读值行：标签左、值右（12，次要墨色，单行），值的 test_id 是 `row.ids.field`（同旧 `settings_updates.factRow`）。
pub fn ValueRow(args: anytype) ui.view.ComponentOf(__yix_ValueRow) {
    return ui.view.component(__yix_ValueRow, ui.reactive.props.coerce(ValueRowProps, args));
}
pub const ValueRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    pane: ui.Source(*const m.PaneSpec),
    row: ui.Source(m.Row),
    value: ui.Source([]const u8),
    /// Text children of the tag go into this parameter (ui.view.textChild)
    pub const text_child = "value";
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = ValueRow;
    pub const __yix_preview_mount = __yix_ValueRow;
};
fn __yix_ValueRow(__yix_props: ValueRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const pane = __yix_props.pane;
    const row = __yix_props.row;
    const value = __yix_props.value;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .pane = pane, .row = row, .value = value, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ValueRow", .receiver = "box", .tokens = "box style = S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ; visible = shown ( vm , pane , row ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "shown ( vm , pane , row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, .value = __yix_view_ctx.value, }, ui.view.box(.{ .style = S.SettingRow.of(.{ .last = __yix_d1: {
        const __yix_T = @TypeOf(last(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return last(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    } }), .visible = __yix_d2: {
        const __yix_T = @TypeOf(shown(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return shown(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ValueRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .value = __yix_view_ctx.value, }, ui.view.box(.{ .style = S.setting_line, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ValueRow", .receiver = "text", .tokens = "text style = @static; box = S . info_label_box ; label ( row )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_label ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . info_label_box ", .kind = .property, .literal = null }, } }, .{ .row = __yix_view_ctx.row, }, ui.view.text(.{ .style = S.setting_label, .box = S.info_label_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d3: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d3: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "ValueRow", .receiver = "text", .tokens = "text testId = fieldId ( row ) ; style = @static; box = S . info_value_box ; value  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "fieldId ( row ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . info_value ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . info_value_box ", .kind = .property, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .value = __yix_view_ctx.value, }, ui.view.text(.{ .test_id = __yix_d4: {
        const __yix_T = @TypeOf(fieldId(__yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .style = S.info_value, .box = S.info_value_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_view_ctx.value), ""), .{ __yix_view_ctx.value, }))),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "ValueRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

/// 链接行：标签 + 原生 link 按钮（尾随外链图标：`iconPosition={.trailing}`，G33），点击发 `row.command`；保存中不可用（同旧“发布来源”）。
pub fn LinkRow(args: anytype) ui.view.ComponentOf(__yix_LinkRow) {
    return ui.view.component(__yix_LinkRow, ui.reactive.props.coerce(LinkRowProps, args));
}
pub const LinkRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    pane: ui.Source(*const m.PaneSpec),
    row: ui.Source(m.Row),
    icon: ui.Source(?ui.SvgAsset),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = LinkRow;
    pub const __yix_preview_mount = __yix_LinkRow;
};
fn __yix_LinkRow(__yix_props: LinkRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const pane = __yix_props.pane;
    const row = __yix_props.row;
    const icon = __yix_props.icon;
    try ui.view.previewCheckSetup(scope, false);
    const name = __yix_d1: {
        const __yix_T = @TypeOf(linkA11y(row.peek()));
        break :__yix_d1 try scope.derive(__yix_T, .{ .row = row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return linkA11y(__yix_ctx.row.get());
        } }.__yix_compute);
    };
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .pane = pane, .row = row, .icon = icon, .name = name, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "LinkRow", .receiver = "box", .tokens = "box style = S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ; visible = shown ( vm , pane , row ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . SettingRow . of ( . { . last = last ( vm , pane , row ) } ) ", .kind = .style, .literal = null }, .{ .name = "visible", .tokens = "shown ( vm , pane , row ) ", .kind = .property, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, .icon = __yix_view_ctx.icon, .name = __yix_view_ctx.name, }, ui.view.box(.{ .style = S.SettingRow.of(.{ .last = __yix_d2: {
        const __yix_T = @TypeOf(last(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return last(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    } }), .visible = __yix_d3: {
        const __yix_T = @TypeOf(shown(__yix_view_ctx.vm.peek(), __yix_view_ctx.pane.peek(), __yix_view_ctx.row.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .pane = __yix_view_ctx.pane, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return shown(__yix_ctx.vm.get(), __yix_ctx.pane.get(), __yix_ctx.row.get());
        } }.__yix_compute);
    }, }, .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "LinkRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_line ", .kind = .style, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .icon = __yix_view_ctx.icon, .name = __yix_view_ctx.name, .vm = __yix_view_ctx.vm, }, ui.view.box(.{ .style = S.setting_line, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "LinkRow", .receiver = "text", .tokens = "text style = @static; box = S . info_label_box ; label ( row )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . setting_label ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . info_label_box ", .kind = .property, .literal = null }, } }, .{ .row = __yix_view_ctx.row, }, ui.view.text(.{ .style = S.setting_label, .box = S.info_label_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d4: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d4: {
        const __yix_T = @TypeOf(label(__yix_view_ctx.row.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return label(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "LinkRow", .receiver = "W.Button", .tokens = "< W . Button testId = { fieldId ( row ) } label = { buttonLabel ( row ) } variant = { . link } size = { . sm } iconAsset = { icon } iconPosition = { . trailing } iconSize = { 12 } a11yLabel = { name } disabled = { vm . isSaving ( ) } onClick = { send ( vm , m . Intent . runCommand ( row . command . ? ) ) } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "fieldId ( row ) ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "buttonLabel ( row ) ", .kind = .property, .literal = null }, .{ .name = "variant", .tokens = ". link ", .kind = .property, .literal = .{ .enum_name = "link" } }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, .{ .name = "icon_asset", .tokens = "icon ", .kind = .property, .literal = null }, .{ .name = "icon_position", .tokens = ". trailing ", .kind = .property, .literal = .{ .enum_name = "trailing" } }, .{ .name = "icon_size", .tokens = "12 ", .kind = .property, .literal = .{ .number = 12 } }, .{ .name = "a11y_label", .tokens = "name ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "vm . isSaving ( ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "send ( vm , m . Intent . runCommand ( row . command . ? ) ) ", .kind = .event, .literal = null }, } }, .{ .row = __yix_view_ctx.row, .icon = __yix_view_ctx.icon, .name = __yix_view_ctx.name, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = __yix_d5: {
        const __yix_T = if (ui.view.attrType(W.Button, "test_id")) |__yix_A| __yix_A else @TypeOf(fieldId(__yix_view_ctx.row.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return fieldId(__yix_ctx.row.get());
        } }.__yix_compute);
    }, }, __yix_builder_26842: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Button); break :__yix_builder_26842 W.Button(.{ .label = __yix_d6: {
        const __yix_T = if (ui.view.attrType(W.Button, "label")) |__yix_A| __yix_A else @TypeOf(buttonLabel(__yix_view_ctx.row.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return buttonLabel(__yix_ctx.row.get());
        } }.__yix_compute);
    }, .variant = .link, .size = .sm, .icon_asset = __yix_view_ctx.icon, .icon_position = .trailing, .icon_size = 12, .a11y_label = __yix_view_ctx.name, .disabled = __yix_d7: {
        const __yix_T = if (ui.view.attrType(W.Button, "disabled")) |__yix_A| __yix_A else @TypeOf(__yix_view_ctx.vm.peek().isSaving());
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.vm.get().isSaving();
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Button, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); send(__yix_ctx.vm.peek(), m.Intent.runCommand(__yix_ctx.row.peek().command.?));  } }.__yix_run) else __yix_d8: {
        const __yix_T = if (ui.view.attrType(W.Button, "on_click")) |__yix_A| __yix_A else @TypeOf(send(__yix_view_ctx.vm.peek(), m.Intent.runCommand(__yix_view_ctx.row.peek().command.?)));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .row = __yix_view_ctx.row, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return send(__yix_ctx.vm.get(), m.Intent.runCommand(__yix_ctx.row.get().command.?));
        } }.__yix_compute);
    }, }); })),
            })),
        })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "LinkRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}
fn linkA11y(row: m.Row) []const u8 {
    return row.match;
}

// ── 两级导航的列表行（F-set-plugins 起；协议插件列表 `T5k96`，AI 辅助 › 服务提供方等列表页可复用） ──
//
//     DrillRow(vm: *m.ViewModel, item: m.DrillItem)
//
// 原生 `W.Pressable`（可点击根，`item.row_id`）：30 方块图标底（`item.icon` 是 `ui.icons` 的名字，找不到用 plug）+ 标题 / 摘要两行
// （13 / 11.5，gap 1）+ 尾注（11.5，空串不显示）+ 状态标签（原生 `W.Tag`，`item.badge`，空串不显示）+ 箭头；被禁用的插件
// （`item.muted`）图标与标题降为次要色；行内 padding [9, 0]、gap 8，与图标底 gap 12；除本组最后一行
// （`item.last`）外底部一条发丝线（人工验收反馈 6）。点击发 `item.target`；保存中不可点（同概览行）。
// 标题 / 摘要 / 尾注的 test_id 是 `item.title_id` / `summary_id` / `trail_id`。

fn drillIcon(item: m.DrillItem) ui.SvgAsset {
    return ui.icons.get(item.icon) orelse ui.icons.plug;
}
fn drillRowId(item: m.DrillItem) []const u8 {
    return item.row_id;
}
fn drillTitleId(item: m.DrillItem) []const u8 {
    return item.title_id;
}
fn drillSummaryId(item: m.DrillItem) []const u8 {
    return item.summary_id;
}
fn drillTrailId(item: m.DrillItem) []const u8 {
    return item.trail_id;
}
fn drillTitle(item: m.DrillItem) []const u8 {
    return item.title;
}
fn drillSummary(item: m.DrillItem) []const u8 {
    return item.summary;
}
fn drillTrail(item: m.DrillItem) []const u8 {
    return item.trail;
}
fn drillHasTrail(item: m.DrillItem) bool {
    return item.trail.len != 0;
}
fn drillHasBadge(item: m.DrillItem) bool {
    return item.badge.len != 0;
}
fn drillBadgeColor(item: m.DrillItem) W.TagColor {
    return if (item.badge_warning) .warning else .neutral;
}
fn drillLast(item: m.DrillItem) bool {
    return item.last;
}
fn drillOpen(vm: *m.ViewModel, item: m.DrillItem) void {
    vm.dispatch(item.target);
}
fn drillLocked(vm: *m.ViewModel) bool {
    return vm.controlsLocked();
}

pub fn DrillRow(args: anytype) ui.view.ComponentOf(__yix_DrillRow) {
    return ui.view.component(__yix_DrillRow, ui.reactive.props.coerce(DrillRowProps, args));
}
pub const DrillRowProps = struct {
    vm: ui.Source(*m.ViewModel),
    item: ui.Source(m.DrillItem),
    pub const __yix_preview_setup = true;
    pub const __yix_preview_builder = DrillRow;
    pub const __yix_preview_mount = __yix_DrillRow;
};
fn __yix_DrillRow(__yix_props: DrillRowProps, scope: *ui.Scope, cx: *ui.Cx) anyerror!*ui.Node {
    const vm = __yix_props.vm;
    const item = __yix_props.item;
    try ui.view.previewCheckSetup(scope, true);
    const __yix_view = try ui.view.renderComponentView(scope, cx, .{ .vm = vm, .item = item, }, struct { fn __yix_render(__yix_view_ctx: anytype, __yix_view_scope: *ui.Scope, __yix_view_cx: *ui.Cx, __yix_sink: ui.view.Sink) anyerror!*ui.Node {
    try ui.view.previewCheckSetup(__yix_view_scope, false);
    try ui.view.emit(__yix_view_scope, __yix_view_cx, __yix_sink, ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DrillRow", .receiver = "W.Pressable", .tokens = "< W . Pressable testId = { drillRowId ( item ) } a11yLabel = { drillTitle ( item ) } disabled = { drillLocked ( vm ) } onClick = { drillOpen ( vm , item ) } style = { S . DrillRow . of ( . { . locked = drillLocked ( vm ) } ) } > < box style = { S . overview_tile } > < icon src = { drillIcon ( item ) } style = { S . DrillIcon . of ( . { . muted = item . muted } ) } / > < / box > < box style = { S . DrillInner . of ( . { . last = drillLast ( item ) } ) } > < box style = { S . drill_copy } > < text testId = { drillTitleId ( item ) } style = { S . DrillTitle . of ( . { . muted = item . muted } ) } box = { S . drill_text_box } > { drillTitle ( item ) } < / text > < text testId = { drillSummaryId ( item ) } style = { S . drill_summary } box = { S . drill_text_box } > { drillSummary ( item ) } < / text > < / box > < text testId = { drillTrailId ( item ) } style = { S . drill_trail } box = { S . drill_trail_box } visible = { drillHasTrail ( item ) } > { drillTrail ( item ) } < / text > { if ( drillHasBadge ( item ) ) < W . Tag testId = { item . badge_id } label = { item . badge } color = { drillBadgeColor ( item ) } size = { . sm } / > } < icon src = { ui . icons . chevron_right } style = { S . overview_chevron } / > < / box > < / W . Pressable > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "drillRowId ( item ) ", .kind = .property, .literal = null }, .{ .name = "a11y_label", .tokens = "drillTitle ( item ) ", .kind = .property, .literal = null }, .{ .name = "disabled", .tokens = "drillLocked ( vm ) ", .kind = .property, .literal = null }, .{ .name = "on_click", .tokens = "drillOpen ( vm , item ) ", .kind = .event, .literal = null }, .{ .name = "style", .tokens = "S . DrillRow . of ( . { . locked = drillLocked ( vm ) } ) ", .kind = .style, .literal = null }, }, .source = __yix_preview_source, .catalog = __YixStyleCatalog }, .{ .item = __yix_view_ctx.item, .vm = __yix_view_ctx.vm, }, ui.view.templateAttrs(.{ .test_id = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "test_id")) |__yix_A| __yix_A else @TypeOf(drillRowId(__yix_view_ctx.item.peek()));
        break :__yix_d1 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillRowId(__yix_ctx.item.get());
        } }.__yix_compute);
    }, .style = S.DrillRow.of(.{ .locked = __yix_d5: {
        const __yix_T = @TypeOf(drillLocked(__yix_view_ctx.vm.peek()));
        break :__yix_d5 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillLocked(__yix_ctx.vm.get());
        } }.__yix_compute);
    } }), }, __yix_builder_29276: { try ui.view.previewCheckBuilder(__yix_view_scope, W.Pressable); break :__yix_builder_29276 ui.view.with(W.Pressable(.{ .a11y_label = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "a11y_label")) |__yix_A| __yix_A else @TypeOf(drillTitle(__yix_view_ctx.item.peek()));
        break :__yix_d2 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillTitle(__yix_ctx.item.get());
        } }.__yix_compute);
    }, .disabled = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "disabled")) |__yix_A| __yix_A else @TypeOf(drillLocked(__yix_view_ctx.vm.peek()));
        break :__yix_d3 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillLocked(__yix_ctx.vm.get());
        } }.__yix_compute);
    }, .on_click = if (comptime ui.view.isEventProp(W.Pressable, "on_click")) try ui.on.bindAny(__yix_view_scope, .{ .vm = __yix_view_ctx.vm, .item = __yix_view_ctx.item, .__yix_owner = __yix_view_scope.owner, }, struct { fn __yix_run(__yix_ctx: anytype) void { __yix_ctx.__yix_owner.beginBatch(); defer __yix_ctx.__yix_owner.endBatch(); drillOpen(__yix_ctx.vm.peek(), __yix_ctx.item.peek());  } }.__yix_run) else __yix_d4: {
        const __yix_T = if (ui.view.attrType(W.Pressable, "on_click")) |__yix_A| __yix_A else @TypeOf(drillOpen(__yix_view_ctx.vm.peek(), __yix_view_ctx.item.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .vm = __yix_view_ctx.vm, .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillOpen(__yix_ctx.vm.get(), __yix_ctx.item.get());
        } }.__yix_compute);
    }, }), .{
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DrillRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . overview_tile ", .kind = .style, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.box(.{ .style = S.overview_tile, }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DrillRow", .receiver = "icon", .tokens = "icon src = drillIcon ( item ) ; style = S . DrillIcon . of ( . { . muted = item . muted } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "drillIcon ( item ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . DrillIcon . of ( . { . muted = item . muted } ) ", .kind = .style, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.icon(.{ .style = S.DrillIcon.of(.{ .muted = __yix_d7: {
        const __yix_T = @TypeOf(__yix_view_ctx.item.peek().muted);
        break :__yix_d7 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().muted;
        } }.__yix_compute);
    } }), }, __yix_d6: {
        const __yix_T = @TypeOf(drillIcon(__yix_view_ctx.item.peek()));
        break :__yix_d6 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillIcon(__yix_ctx.item.get());
        } }.__yix_compute);
    })),
            })),
            ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DrillRow", .receiver = "box", .tokens = "box style = S . DrillInner . of ( . { . last = drillLast ( item ) } ) ; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . DrillInner . of ( . { . last = drillLast ( item ) } ) ", .kind = .style, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.box(.{ .style = S.DrillInner.of(.{ .last = __yix_d8: {
        const __yix_T = @TypeOf(drillLast(__yix_view_ctx.item.peek()));
        break :__yix_d8 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillLast(__yix_ctx.item.get());
        } }.__yix_compute);
    } }), }, .{
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DrillRow", .receiver = "box", .tokens = "box style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "style", .tokens = "S . drill_copy ", .kind = .style, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.box(.{ .style = S.drill_copy, }, .{
                    ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DrillRow", .receiver = "text", .tokens = "text testId = drillTitleId ( item ) ; style = S . DrillTitle . of ( . { . muted = item . muted } ) ; box = S . drill_text_box ; drillTitle ( item )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "drillTitleId ( item ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . DrillTitle . of ( . { . muted = item . muted } ) ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . drill_text_box ", .kind = .property, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.text(.{ .test_id = __yix_d9: {
        const __yix_T = @TypeOf(drillTitleId(__yix_view_ctx.item.peek()));
        break :__yix_d9 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillTitleId(__yix_ctx.item.get());
        } }.__yix_compute);
    }, .style = S.DrillTitle.of(.{ .muted = __yix_d10: {
        const __yix_T = @TypeOf(__yix_view_ctx.item.peek().muted);
        break :__yix_d10 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().muted;
        } }.__yix_compute);
    } }), .box = S.drill_text_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d11: {
        const __yix_T = @TypeOf(drillTitle(__yix_view_ctx.item.peek()));
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillTitle(__yix_ctx.item.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d11: {
        const __yix_T = @TypeOf(drillTitle(__yix_view_ctx.item.peek()));
        break :__yix_d11 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillTitle(__yix_ctx.item.get());
        } }.__yix_compute);
    }, }))),
                    ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DrillRow", .receiver = "text", .tokens = "text testId = drillSummaryId ( item ) ; style = @static; box = S . drill_text_box ; drillSummary ( item )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "drillSummaryId ( item ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . drill_summary ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . drill_text_box ", .kind = .property, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.text(.{ .test_id = __yix_d12: {
        const __yix_T = @TypeOf(drillSummaryId(__yix_view_ctx.item.peek()));
        break :__yix_d12 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillSummaryId(__yix_ctx.item.get());
        } }.__yix_compute);
    }, .style = S.drill_summary, .box = S.drill_text_box, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d13: {
        const __yix_T = @TypeOf(drillSummary(__yix_view_ctx.item.peek()));
        break :__yix_d13 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillSummary(__yix_ctx.item.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d13: {
        const __yix_T = @TypeOf(drillSummary(__yix_view_ctx.item.peek()));
        break :__yix_d13 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillSummary(__yix_ctx.item.get());
        } }.__yix_compute);
    }, }))),
                })),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DrillRow", .receiver = "text", .tokens = "text testId = drillTrailId ( item ) ; style = @static; box = S . drill_trail_box ; visible = drillHasTrail ( item ) ; drillTrail ( item )  @interpolation ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "drillTrailId ( item ) ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . drill_trail ", .kind = .style, .literal = null }, .{ .name = "box", .tokens = "S . drill_trail_box ", .kind = .property, .literal = null }, .{ .name = "visible", .tokens = "drillHasTrail ( item ) ", .kind = .property, .literal = null }, } }, .{ .item = __yix_view_ctx.item, }, ui.view.text(.{ .test_id = __yix_d14: {
        const __yix_T = @TypeOf(drillTrailId(__yix_view_ctx.item.peek()));
        break :__yix_d14 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillTrailId(__yix_ctx.item.get());
        } }.__yix_compute);
    }, .style = S.drill_trail, .box = S.drill_trail_box, .visible = __yix_d15: {
        const __yix_T = @TypeOf(drillHasTrail(__yix_view_ctx.item.peek()));
        break :__yix_d15 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillHasTrail(__yix_ctx.item.get());
        } }.__yix_compute);
    }, }, ui.view.fmt(ui.view.yixFormat(@TypeOf(__yix_d16: {
        const __yix_T = @TypeOf(drillTrail(__yix_view_ctx.item.peek()));
        break :__yix_d16 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillTrail(__yix_ctx.item.get());
        } }.__yix_compute);
    }), ""), .{ __yix_d16: {
        const __yix_T = @TypeOf(drillTrail(__yix_view_ctx.item.peek()));
        break :__yix_d16 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillTrail(__yix_ctx.item.get());
        } }.__yix_compute);
    }, }))),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DrillRow", .receiver = "control", .tokens = "if ( drillHasBadge ( item ) ) < W . Tag testId = { item . badge_id } label = { item . badge } color = { drillBadgeColor ( item ) } size = { . sm } / > " }, .{ .item = __yix_view_ctx.item, }, ui.view.lazyIf(__yix_d4: {
        const __yix_T = @TypeOf(drillHasBadge(__yix_view_ctx.item.peek()));
        break :__yix_d4 try __yix_view_scope.derive(__yix_T, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillHasBadge(__yix_ctx.item.get());
        } }.__yix_compute);
    }, .{ .item = __yix_view_ctx.item, }, struct { fn __yix_b(__yix_b1_0: anytype, __yix_bs1_0: *ui.Scope, __yix_bc1_0: *ui.Cx, __yix_bk1_0: ui.view.Sink) anyerror!void { return ui.view.emit(__yix_bs1_0, __yix_bc1_0, __yix_bk1_0, .{ ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DrillRow/keyword_if:1/branch:0", .receiver = "W.Tag", .tokens = "< W . Tag testId = { item . badge_id } label = { item . badge } color = { drillBadgeColor ( item ) } size = { . sm } / > ", .literal_text = null, .attributes = &.{ .{ .name = "test_id", .tokens = "item . badge_id ", .kind = .property, .literal = null }, .{ .name = "label", .tokens = "item . badge ", .kind = .property, .literal = null }, .{ .name = "color", .tokens = "drillBadgeColor ( item ) ", .kind = .property, .literal = null }, .{ .name = "size", .tokens = ". sm ", .kind = .property, .literal = .{ .enum_name = "sm" } }, } }, .{ .item = __yix_b1_0.item, }, ui.view.templateAttrs(.{ .test_id = __yix_d1: {
        const __yix_T = if (ui.view.attrType(W.Tag, "test_id")) |__yix_A| __yix_A else @TypeOf(__yix_b1_0.item.peek().badge_id);
        break :__yix_d1 try __yix_bs1_0.derive(__yix_T, .{ .item = __yix_b1_0.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().badge_id;
        } }.__yix_compute);
    }, }, __yix_builder_25: { try ui.view.previewCheckBuilder(__yix_bs1_0, W.Tag); break :__yix_builder_25 W.Tag(.{ .label = __yix_d2: {
        const __yix_T = if (ui.view.attrType(W.Tag, "label")) |__yix_A| __yix_A else @TypeOf(__yix_b1_0.item.peek().badge);
        break :__yix_d2 try __yix_bs1_0.derive(__yix_T, .{ .item = __yix_b1_0.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return __yix_ctx.item.get().badge;
        } }.__yix_compute);
    }, .color = __yix_d3: {
        const __yix_T = if (ui.view.attrType(W.Tag, "color")) |__yix_A| __yix_A else @TypeOf(drillBadgeColor(__yix_b1_0.item.peek()));
        break :__yix_d3 try __yix_bs1_0.derive(__yix_T, .{ .item = __yix_b1_0.item, }, struct { fn __yix_compute(__yix_ctx: anytype) __yix_T {
            return drillBadgeColor(__yix_ctx.item.get());
        } }.__yix_compute);
    }, .size = .sm, }); })) }); } }.__yix_b, null)),
                ui.view.templateSite(.{ .module = "src/features/settings/view/components/rows.yix", .path = "DrillRow", .receiver = "icon", .tokens = "icon src = ui . icons . chevron_right ; style = @static; ", .literal_text = null, .attributes = &.{ .{ .name = "src", .tokens = "ui . icons . chevron_right ", .kind = .property, .literal = null }, .{ .name = "style", .tokens = "S . overview_chevron ", .kind = .style, .literal = null }, } }, .{ }, ui.view.icon(.{ .style = S.overview_chevron, }, ui.icons.chevron_right)),
            })),
        }); })));
    const __yix_root = __yix_sink.root.?.* orelse return error.ViewEmptyRoot;
    __yix_root.meta.ownership.meta.component_name = "DrillRow";
    return __yix_root;
    } }.__yix_render);
    return __yix_view;

}

const __yix_preview_source: ?[]const u8 = if (ui.view.template.preview_enabled) "\x2f\x2f\x21\x20\xe8\xae\xbe\xe7\xbd\xae\xe9\x9d\xa2\xe6\x9d\xbf\xe6\xad\xa3\xe6\x96\x87\xe7\x9a\x84\xe8\xa1\x8c\xe7\xbb\x84\xe4\xbb\xb6\xef\xbc\x88\x50\x33\x20\x33\x65\x20\xe5\xae\x9a\xe7\xa8\xbf\xef\xbc\x9b\x41\x52\x43\x48\x49\x54\x45\x43\x54\x55\x52\x45\x5f\x50\x4c\x41\x4e\x20\xc2\xa7\x34\x2e\x35\x20\x60\x63\x6f\x6d\x70\x6f\x6e\x65\x6e\x74\x73\x2f\x72\x6f\x77\x73\x2e\x79\x69\x78\x60\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x21\x0a\x2f\x2f\x21\x20\xe5\x90\x8e\xe7\xbb\xad\xe9\x9d\xa2\xe6\x9d\xbf\xe5\x8c\x85\xe7\x9a\x84\x20\x41\x50\x49\xef\xbc\x88\xe5\x8f\x82\xe6\x95\xb0\xe7\xad\xbe\xe5\x90\x8d\xef\xbc\x89\xef\xbc\x9a\x0a\x2f\x2f\x21\x0a\x2f\x2f\x21\x20\x20\x20\x20\x20\x50\x61\x6e\x65\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x63\x68\x69\x6c\x64\x72\x65\x6e\x3a\x20\x56\x69\x65\x77\x29\x0a\x2f\x2f\x21\x20\x20\x20\x20\x20\x54\x6f\x67\x67\x6c\x65\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x20\x20\x20\x20\x20\x20\x2f\x2f\x20\xe5\xbc\x80\xe5\x85\xb3\x0a\x2f\x2f\x21\x20\x20\x20\x20\x20\x49\x6e\x70\x75\x74\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x20\x20\x20\x20\x20\x20\x20\x2f\x2f\x20\xe6\x96\x87\xe6\x9c\xac\x20\x2f\x20\xe6\x95\xb0\xe5\xad\x97\xef\xbc\x8c\xe5\x8d\x95\xe4\xbd\x8d\xe5\x90\x8e\xe7\xbc\x80\xe3\x80\x81\xe6\xa0\xa1\xe9\xaa\x8c\xe6\x8f\x90\xe7\xa4\xba\x0a\x2f\x2f\x21\x20\x20\x20\x20\x20\x53\x65\x6c\x65\x63\x74\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x6f\x70\x74\x69\x6f\x6e\x73\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x57\x2e\x53\x65\x6c\x65\x63\x74\x4f\x70\x74\x69\x6f\x6e\x29\x0a\x2f\x2f\x21\x20\x20\x20\x20\x20\x43\x75\x73\x74\x6f\x6d\x53\x65\x6c\x65\x63\x74\x52\x6f\x77\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x2c\x20\x6f\x70\x74\x69\x6f\x6e\x73\x2c\x20\x6e\x6f\x74\x65\x49\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x2c\x20\x6e\x6f\x74\x65\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x2c\x20\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x20\x2f\x2f\x20\xe9\x80\x89\xe9\xa1\xb9\xe9\x87\x8c\xe6\x9c\x89\x20\x60\x63\x75\x73\x74\x6f\x6d\x5f\x63\x68\x6f\x69\x63\x65\x60\xef\xbc\x9a\xe5\x8e\x9f\xe5\x9c\xb0\xe7\xbc\x96\xe8\xbe\x91\x0a\x2f\x2f\x21\x20\x20\x20\x20\x20\x44\x69\x72\x65\x63\x74\x6f\x72\x79\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x20\x20\x20\x2f\x2f\x20\xe7\x9b\xae\xe5\xbd\x95\xe6\x8c\x89\xe9\x92\xae\xef\xbc\x88\xe5\xae\xbf\xe4\xb8\xbb\xe7\x9a\x84\xe7\xb3\xbb\xe7\xbb\x9f\xe7\x9b\xae\xe5\xbd\x95\xe9\x9d\xa2\xe6\x9d\xbf\xef\xbc\x89\x0a\x2f\x2f\x21\x20\x20\x20\x20\x20\x49\x6e\x66\x6f\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x20\x20\x20\x20\x20\x20\x20\x20\x2f\x2f\x20\xe5\x8f\xaa\xe8\xaf\xbb\xe5\x80\xbc\xef\xbc\x9b\xe8\xb7\xaf\xe5\xbe\x84\xe5\x8d\x95\xe8\xa1\x8c\xe7\x9c\x81\xe7\x95\xa5\x20\x2b\x20\xe5\x85\xa8\xe6\x96\x87\xe6\x8f\x90\xe7\xa4\xba\x0a\x2f\x2f\x21\x20\x20\x20\x20\x20\x41\x63\x74\x69\x6f\x6e\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x69\x63\x6f\x6e\x3a\x20\x3f\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x29\x20\x20\x2f\x2f\x20\xe6\x8c\x89\xe9\x92\xae\x20\xe2\x86\x92\x20\x60\x49\x6e\x74\x65\x6e\x74\x2e\x72\x75\x6e\x43\x6f\x6d\x6d\x61\x6e\x64\x60\x0a\x2f\x2f\x21\x0a\x2f\x2f\x21\x20\xe7\xba\xa6\xe5\xae\x9a\xef\xbc\x9a\x0a\x2f\x2f\x21\x20\x2d\x20\xe6\x96\x87\xe6\xa1\x88\xe3\x80\x81\x74\x65\x73\x74\x5f\x69\x64\xe3\x80\x81\xe7\x84\xa6\xe7\x82\xb9\xe6\xa0\x87\xe8\xaf\x86\xe3\x80\x81\xe5\x8d\x95\xe4\xbd\x8d\xe3\x80\x81\xe4\xbe\x9d\xe8\xb5\x96\xe3\x80\x81\xe6\x90\x9c\xe7\xb4\xa2\xe8\xaf\x8d\xe9\x83\xbd\xe5\x9c\xa8\x20\x60\x6d\x6f\x64\x65\x6c\x2f\x70\x61\x6e\x65\x5f\x66\x69\x65\x6c\x64\x73\x2e\x7a\x69\x67\x60\x20\xe7\x9a\x84\xe6\x9d\xa1\xe7\x9b\xae\xe9\x87\x8c\xef\xbc\x88\x60\x6d\x2e\x66\x69\x65\x6c\x64\x73\x2e\x3c\xe5\x88\x86\xe7\xb1\xbb\x3e\x2e\x3c\xe5\xad\x97\xe6\xae\xb5\x3e\x60\xef\xbc\x89\xef\xbc\x8c\x0a\x2f\x2f\x21\x20\x20\x20\xe9\x9d\xa2\xe6\x9d\xbf\xe6\x96\x87\xe4\xbb\xb6\xe5\x8f\xaa\xe6\x91\x86\xe9\xa1\xba\xe5\xba\x8f\xe3\x80\x81\xe9\x80\x89\xe6\x8e\xa7\xe4\xbb\xb6\xef\xbc\x9b\xe8\xa1\x8c\xe7\xbb\x84\xe4\xbb\xb6\xe4\xb8\x8d\xe6\x8b\xbc\xe5\xad\x97\xe7\xac\xa6\xe4\xb8\xb2\xe3\x80\x82\x69\x64\x20\xe8\x90\xbd\xe5\x9c\xa8\xe4\xb8\x8e\xe6\x97\xa7\xe5\xae\x9e\xe7\x8e\xb0\xe7\x9b\xb8\xe5\x90\x8c\xe7\x9a\x84\xe8\xaf\xad\xe4\xb9\x89\xe8\x8a\x82\xe7\x82\xb9\xe4\xb8\x8a\xef\xbc\x9a\xe8\xa1\x8c\xe6\xa0\xb9\x20\x60\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x72\x6f\x77\x2e\x3c\x6b\x65\x79\x3e\x60\xef\xbc\x8c\x0a\x2f\x2f\x21\x20\x20\x20\xe5\xbc\x80\xe5\x85\xb3\xe4\xb8\x8e\xe6\x8c\x89\xe9\x92\xae\xe5\x9c\xa8\xe6\x8e\xa7\xe4\xbb\xb6\xe6\xa0\xb9\xef\xbc\x88\x60\x74\x65\x73\x74\x49\x64\x60\xef\xbc\x89\xef\xbc\x8c\xe8\xbe\x93\xe5\x85\xa5\xe6\xa1\x86\xe5\x9c\xa8\x20\x60\x69\x6e\x70\x75\x74\x5f\x63\x6f\x6e\x74\x61\x69\x6e\x65\x72\x60\xe3\x80\x81\xe9\x80\x89\xe6\x8b\xa9\xe6\xa1\x86\xe5\x9c\xa8\x20\x60\x74\x72\x69\x67\x67\x65\x72\x60\xef\xbc\x88\x60\x70\x61\x72\x74\x73\x60\xef\xbc\x89\xef\xbc\x8c\xe6\xa0\xa1\xe9\xaa\x8c\xe6\x8f\x90\xe7\xa4\xba\x20\x60\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x65\x72\x72\x6f\x72\x2e\x3c\x6b\x65\x79\x3e\x60\xef\xbc\x8c\x0a\x2f\x2f\x21\x20\x20\x20\xe5\xb8\xae\xe5\x8a\xa9\xe6\x8c\x89\xe9\x92\xae\x20\x60\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x68\x65\x6c\x70\x2e\x3c\x6b\x65\x79\x3e\x60\xe3\x80\x81\xe6\x8f\x90\xe7\xa4\xba\xe9\x9d\xa2\xe6\x9d\xbf\x20\x60\xe2\x80\xa6\x2e\x74\x6f\x6f\x6c\x74\x69\x70\x60\xe3\x80\x81\xe6\xa0\x87\xe7\xad\xbe\xe4\xb8\x8b\xe7\x9a\x84\xe8\xaf\xb4\xe6\x98\x8e\x20\x60\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x68\x65\x6c\x70\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x2e\x3c\x6b\x65\x79\x3e\x60\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe6\x8e\xa7\xe4\xbb\xb6\xe5\x85\xa8\xe9\x83\xa8\xe6\x98\xaf\x20\x7a\x65\x6e\x69\x74\x20\xe5\x8e\x9f\xe7\x94\x9f\xef\xbc\x88\x60\x57\x2e\x53\x77\x69\x74\x63\x68\x60\x20\x2f\x20\x60\x57\x2e\x49\x6e\x70\x75\x74\x60\x20\x2f\x20\x60\x57\x2e\x53\x65\x6c\x65\x63\x74\x60\x20\x2f\x20\x60\x57\x2e\x42\x75\x74\x74\x6f\x6e\x60\x20\x2f\x20\x60\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x60\xef\xbc\x89\xef\xbc\x8c\xe4\xb8\x8d\xe8\xa6\x86\xe7\x9b\x96\xe5\x87\xa0\xe4\xbd\x95\xe3\x80\x81\xe5\xad\x97\xe4\xbd\x93\xe4\xb8\x8e\xe9\xa2\x9c\xe8\x89\xb2\xef\xbc\x9b\x0a\x2f\x2f\x21\x20\x20\x20\xe6\xa0\xb7\xe5\xbc\x8f\xe5\x8f\xaa\xe5\x9c\xa8\x20\x60\x2e\x2e\x2f\x73\x74\x79\x6c\x65\x73\x2e\x79\x73\x73\x60\xef\xbc\x8c\xe9\xa2\x9c\xe8\x89\xb2\xe5\x8f\xaa\xe7\x94\xa8\x20\x74\x6f\x6b\x65\x6e\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe6\x8e\xa7\xe4\xbb\xb6\xe6\x98\xaf\xe2\x80\x9c\xe5\x8f\xaa\xe8\xaf\xbb\xe5\x80\xbc\x20\x2b\x20\xe5\x9b\x9e\xe8\xb0\x83\xe2\x80\x9d\xef\xbc\x9a\xe5\x80\xbc\xe6\x9d\xa5\xe8\x87\xaa\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\x20\xe9\x80\x89\xe6\x8b\xa9\xe5\x99\xa8\xef\xbc\x88\xe6\x8c\x89\x20\x60\x72\x65\x76\x69\x73\x69\x6f\x6e\x60\x20\xe8\xb7\x9f\xe9\x9a\x8f\xe8\x8d\x89\xe7\xa8\xbf\xef\xbc\x89\xef\xbc\x8c\xe6\x94\xb9\xe5\x8a\xa8\xe7\xbb\x8f\x20\x60\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x49\x6e\x74\x65\x6e\x74\x29\x60\x20\xe4\xb8\x8a\xe8\xa1\x8c\xef\xbc\x8c\x0a\x2f\x2f\x21\x20\x20\x20\xe7\x94\xb1\x20\x43\x6f\x6e\x74\x72\x6f\x6c\x6c\x65\x72\x20\xe8\xa3\x81\xe5\x86\xb3\xef\xbc\x9b\xe6\x94\xb9\xe4\xb8\x80\xe4\xb8\xaa\xe5\xad\x97\xe6\xae\xb5\xe5\x8f\xaa\xe8\xae\xa9\xe8\xaf\xbb\xe5\x88\xb0\xe5\xae\x83\xe7\x9a\x84\xe9\x80\x89\xe6\x8b\xa9\xe5\x99\xa8\xe9\x87\x8d\xe7\xae\x97\xef\xbc\x8c\xe5\x90\x8c\xe9\xa1\xb5\xe5\x85\xb6\xe5\xae\x83\xe8\x8a\x82\xe7\x82\xb9\xe4\xb8\x8d\xe5\x8a\xa8\xef\xbc\x88\xe6\xb2\xa1\xe6\x9c\x89\xe6\x95\xb4\xe9\xa1\xb5\xe9\x87\x8d\xe6\x8c\x82\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe8\xa1\x8c\xe7\x9a\x84\xe6\x98\xbe\xe7\xa4\xba\xef\xbc\x88\xe5\xad\x90\xe9\xa1\xb5\xe9\x9d\xa2\x20\x2f\x20\xe6\x90\x9c\xe7\xb4\xa2\xe8\xbf\x87\xe6\xbb\xa4\xef\xbc\x89\xe4\xb8\x8e\xe2\x80\x9c\xe9\x9d\xa2\xe6\x9d\xbf\xe6\x9c\x80\xe5\x90\x8e\xe4\xb8\x80\xe8\xa1\x8c\xe2\x80\x9d\xef\xbc\x88\xe5\xae\x83\xe4\xb8\x8b\xe9\x9d\xa2\xe6\xb2\xa1\xe6\x9c\x89\xe5\x88\x86\xe9\x9a\x94\xe7\xba\xbf\xef\xbc\x89\xe5\x9c\xa8\xe5\x86\x85\xe5\xae\xb9\xe9\xa1\xb5\xe6\x8c\x82\xe8\xbd\xbd\xe6\x97\xb6\xe5\xae\x9a\xe4\xb8\x8b\xef\xbc\x88\x60\x76\x6d\x2e\x72\x6f\x77\x53\x68\x6f\x77\x6e\x60\x20\x2f\x20\x60\x76\x6d\x2e\x72\x6f\x77\x4c\x61\x73\x74\x60\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x21\x20\x2d\x20\xe6\xa8\xaa\xe5\x88\x87\xe8\xa1\x8c\xe4\xb8\xba\xef\xbc\x9a\xe5\xb8\xae\xe5\x8a\xa9\xe6\x8f\x90\xe7\xa4\xba\xe3\x80\x81\xe8\xb7\xaf\xe5\xbe\x84\x20\x2f\x20\xe7\x9b\xae\xe5\xbd\x95\xe5\x85\xa8\xe6\x96\x87\xe6\x8f\x90\xe7\xa4\xba\xe4\xb8\x8e\xe9\x80\x89\xe6\x8b\xa9\xe6\xa1\x86\xe4\xb8\x8b\xe6\x8b\x89\xe7\x9a\x84\xe5\xbc\x80\xe5\x90\x88\xe6\x98\xaf\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\x20\xe7\x9a\x84\x20\x60\x70\x6f\x70\x75\x70\x60\xef\xbc\x88\xe6\x95\xb4\xe7\xaa\x97\x20\x45\x73\x63\x61\x70\x65\x20\xe5\x85\x88\xe6\x94\xb6\xe8\xb5\xb7\xe5\xae\x83\xef\xbc\x89\xef\xbc\x9b\xe7\x84\xa6\xe7\x82\xb9\xe5\x9c\xa8\xe8\xbe\x93\xe5\x85\xa5\xe6\xa1\x86\xe4\xb8\x8a\xe6\x97\xb6\xef\xbc\x8c\x0a\x2f\x2f\x21\x20\x20\x20\xe6\x95\xb4\xe7\xaa\x97\x20\x45\x73\x63\x61\x70\x65\x20\xe6\x92\xa4\xe5\x9b\x9e\xe5\xae\x83\xe7\x9a\x84\xe5\x8e\x9f\xe6\x96\x87\xe5\xb9\xb6\xe6\xb8\x85\xe7\x84\xa6\xe7\x82\xb9\xef\xbc\x88\xe5\xae\xbf\xe4\xb8\xbb\xe6\x8c\x89\xe7\x9c\x9f\xe5\xae\x9e\xe7\x84\xa6\xe7\x82\xb9\xe7\x9a\x84\x20\x74\x65\x73\x74\x5f\x69\x64\x20\xe8\xae\xa4\xe5\x87\xba\xe5\xae\x83\xef\xbc\x8c\x60\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2e\x63\x6f\x6e\x73\x75\x6d\x65\x45\x73\x63\x61\x70\x65\x60\xef\xbc\x89\xef\xbc\x9b\xe8\xbe\x93\xe5\x85\xa5\xe6\xa1\x86\xe5\xb8\xa6\x20\x60\x66\x6f\x63\x75\x73\x49\x64\x60\xef\xbc\x88\x60\x66\x6f\x63\x75\x73\x3a\x66\x69\x65\x6c\x64\x3a\x3c\x74\x65\x73\x74\x5f\x69\x64\x3e\x60\xef\xbc\x8c\x60\x6c\x6f\x63\x61\x74\x65\x5f\x70\x72\x6f\x62\x6c\x65\x6d\x60\x20\xe4\xb8\x8e\x20\x60\x66\x6f\x63\x75\x73\x52\x65\x73\x74\x6f\x72\x65\x60\x20\xe7\x94\xa8\xef\xbc\x89\xe3\x80\x82\x0a\x63\x6f\x6e\x73\x74\x20\x75\x69\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x75\x69\x22\x29\x3b\x0a\x2f\x2f\x2f\x20\xe6\xb5\xae\xe5\xb1\x82\xe8\xa7\x84\xe5\x88\x99\xe7\x9a\x84\xe5\x94\xaf\xe4\xb8\x80\xe6\x9d\xa5\xe6\xba\x90\xef\xbc\x88\x4f\x76\x65\x72\x6c\x61\x79\x48\x6f\x73\x74\x20\x60\x70\x61\x6e\x65\x6c\x60\xef\xbc\x89\xe3\x80\x82\x0a\x63\x6f\x6e\x73\x74\x20\x4f\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x2e\x2e\x2f\x2e\x2e\x2f\x2e\x2e\x2f\x73\x68\x61\x72\x65\x64\x2f\x75\x69\x2f\x6f\x76\x65\x72\x6c\x61\x79\x2f\x6f\x76\x65\x72\x6c\x61\x79\x5f\x68\x6f\x73\x74\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x57\x20\x3d\x20\x75\x69\x2e\x77\x69\x64\x67\x65\x74\x73\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x6d\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x2e\x2e\x2f\x6d\x6f\x64\x65\x6c\x2f\x76\x69\x65\x77\x5f\x6d\x6f\x64\x65\x6c\x2e\x7a\x69\x67\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x53\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x73\x74\x79\x6c\x65\x73\x2e\x79\x73\x73\x22\x29\x3b\x0a\x63\x6f\x6e\x73\x74\x20\x4b\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x2e\x2e\x2f\x70\x61\x6e\x65\x73\x2f\x6b\x65\x79\x73\x2e\x79\x73\x73\x22\x29\x3b\x0a\x0a\x66\x6e\x20\x73\x65\x6e\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x6e\x74\x65\x6e\x74\x3a\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x69\x6e\x74\x65\x6e\x74\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x68\x6f\x77\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x72\x6f\x77\x53\x68\x6f\x77\x6e\x28\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x20\x61\x6e\x64\x20\x76\x6d\x2e\x69\x6e\x66\x6f\x53\x68\x6f\x77\x6e\x28\x72\x6f\x77\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x6c\x61\x73\x74\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x72\x6f\x77\x4c\x61\x73\x74\x28\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x6c\x61\x62\x65\x6c\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x6c\x61\x62\x65\x6c\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x65\x6c\x70\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x68\x65\x6c\x70\x3b\x0a\x7d\x0a\x66\x6e\x20\x74\x69\x70\x48\x65\x6c\x70\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x68\x65\x6c\x70\x2e\x6c\x65\x6e\x20\x21\x3d\x20\x30\x20\x61\x6e\x64\x20\x21\x72\x6f\x77\x2e\x69\x6e\x6c\x69\x6e\x65\x5f\x68\x65\x6c\x70\x3b\x0a\x7d\x0a\x66\x6e\x20\x69\x6e\x6c\x69\x6e\x65\x48\x65\x6c\x70\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x68\x65\x6c\x70\x2e\x6c\x65\x6e\x20\x21\x3d\x20\x30\x20\x61\x6e\x64\x20\x72\x6f\x77\x2e\x69\x6e\x6c\x69\x6e\x65\x5f\x68\x65\x6c\x70\x3b\x0a\x7d\x0a\x66\x6e\x20\x72\x6f\x77\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x72\x6f\x77\x3b\x0a\x7d\x0a\x66\x6e\x20\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x66\x69\x65\x6c\x64\x3b\x0a\x7d\x0a\x66\x6e\x20\x65\x72\x72\x6f\x72\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x65\x72\x72\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x65\x6c\x70\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x68\x65\x6c\x70\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x65\x6c\x70\x54\x69\x70\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x68\x65\x6c\x70\x5f\x74\x69\x70\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x65\x6c\x70\x54\x65\x78\x74\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x68\x65\x6c\x70\x5f\x74\x65\x78\x74\x3b\x0a\x7d\x0a\x66\x6e\x20\x66\x6f\x63\x75\x73\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x66\x6f\x63\x75\x73\x3b\x0a\x7d\x0a\x2f\x2f\x2f\x20\xe5\x8d\x95\xe4\xbd\x8d\xe5\x90\x8e\xe7\xbc\x80\xef\xbc\x88\xe6\xb2\xa1\xe6\x9c\x89\xe5\x8d\x95\xe4\xbd\x8d\xe6\x97\xb6\xe4\xb8\xba\x20\x6e\x75\x6c\x6c\xef\xbc\x9a\xe4\xb8\x8d\xe5\xbb\xba\xe5\x90\x8e\xe7\xbc\x80\xe8\x8a\x82\xe7\x82\xb9\xef\xbc\x8c\xe5\x90\x8c\xe6\x97\xa7\xe5\xae\x9e\xe7\x8e\xb0\xef\xbc\x89\xe3\x80\x82\x0a\x66\x6e\x20\x75\x6e\x69\x74\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x3f\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x75\x6e\x69\x74\x3b\x0a\x7d\x0a\x66\x6e\x20\x63\x68\x65\x63\x6b\x65\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x62\x6f\x6f\x6c\x4f\x66\x28\x72\x6f\x77\x2e\x6b\x65\x79\x2e\x3f\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x65\x74\x42\x6f\x6f\x6c\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x76\x61\x6c\x75\x65\x3a\x20\x62\x6f\x6f\x6c\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x65\x64\x69\x74\x56\x61\x6c\x75\x65\x28\x72\x6f\x77\x2e\x6b\x65\x79\x2e\x3f\x2c\x20\x2e\x7b\x20\x2e\x62\x6f\x6f\x6c\x65\x61\x6e\x20\x3d\x20\x76\x61\x6c\x75\x65\x20\x7d\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x65\x64\x69\x74\x54\x65\x78\x74\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x74\x65\x78\x74\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x65\x64\x69\x74\x54\x65\x78\x74\x28\x72\x6f\x77\x2e\x6b\x65\x79\x2e\x3f\x2c\x20\x74\x65\x78\x74\x29\x29\x3b\x0a\x7d\x0a\x2f\x2f\x2f\x20\xe9\x80\x89\xe6\x8b\xa9\xe6\xa1\x86\xef\xbc\x9a\xe2\x80\x9c\xe8\x87\xaa\xe5\xae\x9a\xe4\xb9\x89\x20\x54\x45\x52\x4d\x20\xe5\xa3\xb0\xe6\x98\x8e\xe2\x80\xa6\xe2\x80\x9d\xe6\x89\x93\xe5\xbc\x80\xe5\x8e\x9f\xe5\x9c\xb0\xe7\xbc\x96\xe8\xbe\x91\xef\xbc\x88\x60\x43\x75\x73\x74\x6f\x6d\x53\x65\x6c\x65\x63\x74\x52\x6f\x77\x60\xef\xbc\x8c\xe5\x80\xbc\xe4\xb8\x8d\xe5\x8f\x98\xef\xbc\x8c\xe4\xb8\x8b\xe6\x8b\x89\xe6\x8c\x89\xe8\x8d\x89\xe7\xa8\xbf\xe5\x80\xbc\xe5\xa4\x8d\xe4\xbd\x8d\xef\xbc\x89\xef\xbc\x9b\xe5\x85\xb6\xe5\xae\x83\xe9\x80\x89\xe9\xa1\xb9\xe7\x9b\xb4\xe6\x8e\xa5\xe5\x86\x99\xe8\x8d\x89\xe7\xa8\xbf\xe3\x80\x82\x0a\x66\x6e\x20\x70\x69\x63\x6b\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x76\x61\x6c\x75\x65\x3a\x20\x3f\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x70\x69\x63\x6b\x65\x64\x20\x3d\x20\x76\x61\x6c\x75\x65\x20\x6f\x72\x65\x6c\x73\x65\x20\x72\x65\x74\x75\x72\x6e\x3b\x0a\x20\x20\x20\x20\x69\x66\x20\x28\x73\x74\x64\x2e\x6d\x65\x6d\x2e\x65\x71\x6c\x28\x75\x38\x2c\x20\x70\x69\x63\x6b\x65\x64\x2c\x20\x63\x75\x73\x74\x6f\x6d\x5f\x63\x68\x6f\x69\x63\x65\x29\x29\x20\x7b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x63\x68\x6f\x6f\x73\x65\x46\x6f\x72\x28\x72\x6f\x77\x2e\x6b\x65\x79\x2e\x3f\x29\x29\x3b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x3b\x0a\x20\x20\x20\x20\x7d\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x65\x64\x69\x74\x56\x61\x6c\x75\x65\x28\x72\x6f\x77\x2e\x6b\x65\x79\x2e\x3f\x2c\x20\x2e\x7b\x20\x2e\x74\x65\x78\x74\x20\x3d\x20\x70\x69\x63\x6b\x65\x64\x20\x7d\x29\x29\x3b\x0a\x7d\x0a\x63\x6f\x6e\x73\x74\x20\x73\x74\x64\x20\x3d\x20\x40\x69\x6d\x70\x6f\x72\x74\x28\x22\x73\x74\x64\x22\x29\x3b\x0a\x2f\x2f\x2f\x20\xe9\x80\x89\xe6\x8b\xa9\xe6\xa1\x86\xe9\x87\x8c\xe8\xa6\x81\xe5\xae\xbf\xe4\xb8\xbb\xe5\x8e\x9f\xe5\x9c\xb0\xe7\xbc\x96\xe8\xbe\x91\xe7\x9a\x84\xe9\x80\x89\xe9\xa1\xb9\xe5\x80\xbc\xef\xbc\x88\xe6\x97\xa7\x20\x60\x73\x65\x74\x74\x69\x6e\x67\x73\x5f\x63\x6f\x6e\x74\x72\x6f\x6c\x73\x2e\x46\x69\x65\x6c\x64\x2e\x73\x65\x6c\x65\x63\x74\x60\x20\xe7\x9a\x84\x20\x60\x5f\x5f\x63\x75\x73\x74\x6f\x6d\x60\xef\xbc\x89\xe3\x80\x82\x0a\x70\x75\x62\x20\x63\x6f\x6e\x73\x74\x20\x63\x75\x73\x74\x6f\x6d\x5f\x63\x68\x6f\x69\x63\x65\x20\x3d\x20\x22\x5f\x5f\x63\x75\x73\x74\x6f\x6d\x22\x3b\x0a\x2f\x2f\x2f\x20\xe7\x9b\xae\xe5\xbd\x95\xe8\xa1\x8c\xe5\x85\xa8\xe6\x96\x87\xe6\x8f\x90\xe7\xa4\xba\xe7\x9a\x84\x20\x69\x64\xef\xbc\x88\x60\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x64\x69\x72\x65\x63\x74\x6f\x72\x79\x2e\x74\x6f\x6f\x6c\x74\x69\x70\x60\xef\xbc\x8c\xe5\x90\x8c\xe6\x97\xa7\xe5\xae\x9e\xe7\x8e\xb0\xef\xbc\x9b\xe4\xb9\x9f\xe6\x98\xaf\xe5\xae\x83\xe5\x9c\xa8\x20\x60\x70\x6f\x70\x75\x70\x60\x20\xe9\x87\x8c\xe7\x9a\x84\xe5\x90\x8d\xe5\xad\x97\xef\xbc\x89\xe3\x80\x82\x0a\x63\x6f\x6e\x73\x74\x20\x64\x69\x72\x65\x63\x74\x6f\x72\x79\x5f\x74\x69\x70\x20\x3d\x20\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x64\x69\x72\x65\x63\x74\x6f\x72\x79\x2e\x74\x6f\x6f\x6c\x74\x69\x70\x22\x3b\x0a\x66\x6e\x20\x70\x6f\x70\x75\x70\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6f\x70\x75\x70\x4f\x70\x65\x6e\x28\x69\x64\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x2c\x20\x6f\x70\x65\x6e\x3a\x20\x62\x6f\x6f\x6c\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x70\x6f\x70\x75\x70\x43\x68\x61\x6e\x67\x65\x64\x28\x69\x64\x2c\x20\x6f\x70\x65\x6e\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x70\x72\x6f\x62\x6c\x65\x6d\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x66\x69\x65\x6c\x64\x50\x72\x6f\x62\x6c\x65\x6d\x28\x72\x6f\x77\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x69\x6e\x76\x61\x6c\x69\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x66\x69\x65\x6c\x64\x49\x6e\x76\x61\x6c\x69\x64\x28\x72\x6f\x77\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x66\x69\x65\x6c\x64\x44\x69\x73\x61\x62\x6c\x65\x64\x28\x72\x6f\x77\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x70\x61\x6e\x65\x49\x64\x28\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x70\x61\x6e\x65\x2e\x69\x64\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x65\x61\x64\x65\x72\x49\x64\x28\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x70\x61\x6e\x65\x2e\x68\x65\x61\x64\x65\x72\x5f\x69\x64\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x75\x6d\x6d\x61\x72\x79\x49\x64\x28\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x70\x61\x6e\x65\x2e\x73\x75\x6d\x6d\x61\x72\x79\x5f\x69\x64\x3b\x0a\x7d\x0a\x66\x6e\x20\x74\x69\x74\x6c\x65\x28\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x70\x61\x6e\x65\x2e\x74\x69\x74\x6c\x65\x3b\x0a\x7d\x0a\x66\x6e\x20\x6d\x65\x74\x61\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x61\x6e\x65\x4d\x65\x74\x61\x28\x70\x61\x6e\x65\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x70\x61\x6e\x65\x53\x68\x6f\x77\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x61\x6e\x65\x53\x68\x6f\x77\x6e\x28\x70\x61\x6e\x65\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe9\x9d\xa2\xe6\x9d\xbf\xef\xbc\x88\x60\x76\x38\x4e\x44\x5a\x4d\x60\xef\xbc\x89\xef\xbc\x9a\xe9\xa1\xb5\xe5\xa4\xb4\xef\xbc\x88\x60\x51\x47\x74\x78\x35\x60\xef\xbc\x8c\xe6\xa0\x87\xe9\xa2\x98\x20\x2b\x20\xe5\x8f\xb3\xe4\xbe\xa7\xe8\xaf\xb4\xe6\x98\x8e\xef\xbc\x89\xe5\x9c\xa8\xe4\xb8\x8a\xef\xbc\x8c\xe6\xad\xa3\xe6\x96\x87\xe5\x8d\xa1\xe7\x89\x87\xef\xbc\x88\x60\x56\x34\x54\x4e\x42\x60\xef\xbc\x89\xe5\x9c\xa8\xe4\xb8\x8b\xef\xbc\x9b\xe8\xa1\x8c\xe4\xb9\x8b\xe9\x97\xb4\xe7\x9a\x84\xe5\x88\x86\xe9\x9a\x94\xe7\xba\xbf\xe7\x94\xb1\xe8\xa1\x8c\xe8\x87\xaa\xe5\xb7\xb1\xe7\x94\xbb\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x50\x61\x6e\x65\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x63\x68\x69\x6c\x64\x72\x65\x6e\x3a\x20\x56\x69\x65\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x70\x61\x6e\x65\x49\x64\x28\x70\x61\x6e\x65\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x70\x61\x6e\x65\x53\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x68\x65\x61\x64\x65\x72\x49\x64\x28\x70\x61\x6e\x65\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x68\x65\x61\x64\x65\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x74\x69\x74\x6c\x65\x7d\x3e\x7b\x74\x69\x74\x6c\x65\x28\x70\x61\x6e\x65\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x73\x70\x61\x63\x65\x72\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x73\x75\x6d\x6d\x61\x72\x79\x49\x64\x28\x70\x61\x6e\x65\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x6d\x65\x74\x61\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x6d\x65\x74\x61\x5f\x62\x6f\x78\x7d\x3e\x7b\x6d\x65\x74\x61\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x70\x61\x6e\x65\x5f\x62\x6f\x64\x79\x7d\x3e\x7b\x63\x68\x69\x6c\x64\x72\x65\x6e\x7d\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe6\xa0\x87\xe9\xa2\x98\xe6\x97\x81\xe7\x9a\x84\xe2\x80\x9c\x3f\xe2\x80\x9d\xef\xbc\x9a\xe5\x8e\x9f\xe7\x94\x9f\x20\x67\x68\x6f\x73\x74\x20\xe5\x9b\xbe\xe6\xa0\x87\xe6\x8c\x89\xe9\x92\xae\x20\x2b\x20\xe5\x8e\x9f\xe7\x94\x9f\x20\x54\x6f\x6f\x6c\x74\x69\x70\xef\xbc\x88\xe4\xb8\x8a\xe6\x96\xb9\xe3\x80\x81\x34\x35\x30\x6d\x73\xef\xbc\x8c\xe6\x82\xac\xe5\x81\x9c\x20\x2f\x20\xe8\x81\x9a\xe7\x84\xa6\x20\x2f\x20\xe7\x82\xb9\xe5\x87\xbb\xe6\x89\x93\xe5\xbc\x80\xef\xbc\x89\xe3\x80\x82\x0a\x66\x6e\x20\x48\x65\x6c\x70\x54\x69\x70\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x74\x69\x70\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x68\x65\x6c\x70\x54\x69\x70\x49\x64\x28\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x6c\x70\x5f\x73\x6c\x6f\x74\x7d\x20\x6f\x6e\x46\x6f\x63\x75\x73\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x74\x72\x75\x65\x29\x7d\x20\x6f\x6e\x42\x6c\x75\x72\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x66\x61\x6c\x73\x65\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x68\x65\x6c\x70\x28\x72\x6f\x77\x29\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x32\x39\x32\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x70\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x29\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x6f\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x74\x69\x70\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x68\x65\x6c\x70\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x78\x73\x7d\x20\x69\x63\x6f\x6e\x4f\x6e\x6c\x79\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x69\x72\x63\x6c\x65\x5f\x68\x65\x6c\x70\x7d\x20\x69\x63\x6f\x6e\x53\x69\x7a\x65\x3d\x7b\x31\x34\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x68\x65\x6c\x70\x28\x72\x6f\x77\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x74\x72\x75\x65\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe6\x96\x87\xe6\xa1\x88\xe5\x88\x97\xef\xbc\x9a\xe6\xa0\x87\xe7\xad\xbe\xef\xbc\x88\x2b\xe2\x80\x9c\x3f\xe2\x80\x9d\xef\xbc\x89\xef\xbc\x8c\xe6\x98\x93\xe8\xaf\xaf\xe7\x94\xa8\xe5\xad\x97\xe6\xae\xb5\xe7\x9a\x84\xe8\xaf\xb4\xe6\x98\x8e\xe7\x9b\xb4\xe6\x8e\xa5\xe5\x86\x99\xe5\x9c\xa8\xe6\xa0\x87\xe7\xad\xbe\xe4\xb8\x8b\xe3\x80\x82\x0a\x66\x6e\x20\x43\x6f\x70\x79\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x63\x6f\x70\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x68\x65\x61\x64\x69\x6e\x67\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x61\x62\x65\x6c\x7d\x3e\x7b\x6c\x61\x62\x65\x6c\x28\x72\x6f\x77\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x74\x69\x70\x48\x65\x6c\x70\x28\x72\x6f\x77\x29\x29\x20\x3c\x48\x65\x6c\x70\x54\x69\x70\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x69\x6e\x6c\x69\x6e\x65\x48\x65\x6c\x70\x28\x72\x6f\x77\x29\x29\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x68\x65\x6c\x70\x54\x65\x78\x74\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x68\x69\x6e\x74\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x68\x69\x6e\x74\x5f\x62\x6f\x78\x7d\x3e\x7b\x68\x65\x6c\x70\x28\x72\x6f\x77\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe8\xa1\x8c\xe5\x86\x85\xe6\xa0\xa1\xe9\xaa\x8c\xe6\x8f\x90\xe7\xa4\xba\xef\xbc\x88\x60\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x65\x72\x72\x6f\x72\x2e\x3c\x6b\x65\x79\x3e\x60\xef\xbc\x8c\xe6\x97\xa0\xe9\x97\xae\xe9\xa2\x98\xe6\x97\xb6\xe4\xb8\x8d\xe6\x98\xbe\xe7\xa4\xba\xef\xbc\x89\xe3\x80\x82\x0a\x66\x6e\x20\x50\x72\x6f\x62\x6c\x65\x6d\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x65\x72\x72\x6f\x72\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x65\x72\x72\x6f\x72\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x69\x6e\x76\x61\x6c\x69\x64\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x7b\x70\x72\x6f\x62\x6c\x65\x6d\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe5\xbc\x80\xe5\x85\xb3\xe8\xa1\x8c\xef\xbc\x88\x60\x6f\x77\x34\x6f\x65\x60\x20\x2b\x20\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x53\x77\x69\x74\x63\x68\x60\xef\xbc\x89\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x54\x6f\x67\x67\x6c\x65\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x73\x77\x69\x74\x63\x68\x5f\x61\x31\x31\x79\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x73\x77\x69\x74\x63\x68\x41\x31\x31\x79\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x72\x6f\x77\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x6c\x61\x73\x74\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x20\x7d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x73\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x43\x6f\x70\x79\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x77\x69\x74\x63\x68\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x63\x68\x65\x63\x6b\x65\x64\x3d\x7b\x63\x68\x65\x63\x6b\x65\x64\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x20\x61\x31\x31\x79\x3d\x7b\x73\x77\x69\x74\x63\x68\x5f\x61\x31\x31\x79\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x76\x7c\x20\x73\x65\x74\x42\x6f\x6f\x6c\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2c\x20\x76\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x50\x72\x6f\x62\x6c\x65\x6d\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe8\xbe\x93\xe5\x85\xa5\xe8\xa1\x8c\xef\xbc\x9a\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x49\x6e\x70\x75\x74\x60\xef\xbc\x88\xe5\x8f\x97\xe6\x8e\xa7\xef\xbc\x9a\xe5\x8e\x9f\xe6\x96\x87\xe7\xbb\x8f\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\x20\xe5\x90\x8c\xe6\xad\xa5\xe8\x90\xbd\xe5\x9c\xb0\xef\xbc\x89\xef\xbc\x8c\xe6\xa0\xa1\xe9\xaa\x8c\xe9\x97\xae\xe9\xa2\x98\xe6\xa0\x87\xe7\xba\xa2\xe5\xb9\xb6\xe5\x9c\xa8\xe8\xa1\x8c\xe4\xb8\x8b\xe6\x8f\x90\xe7\xa4\xba\xe3\x80\x82\x0a\x2f\x2f\x2f\x20\xe5\x8d\x95\xe4\xbd\x8d\xe6\x98\xaf\xe5\x8e\x9f\xe7\x94\x9f\xe5\x90\x8e\xe7\xbc\x80\xef\xbc\x88\x60\x61\x70\x70\x65\x6e\x64\x54\x65\x78\x74\x60\xef\xbc\x8c\xe6\x8c\x82\xe8\xbd\xbd\xe6\x97\xb6\xe5\x8f\x96\xe5\x80\xbc\xef\xbc\x9b\x47\x32\x35\x20\xe5\xb7\xb2\xe7\x94\xb1\xe4\xb8\x8a\xe6\xb8\xb8\xe8\xa1\xa5\xe4\xb8\x8a\xef\xbc\x8c\x53\x2d\x31\x34\x20\xe6\x94\xb6\xe5\x9b\x9e\xef\xbc\x89\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x49\x6e\x70\x75\x74\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x66\x69\x64\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x72\x6f\x77\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x6c\x61\x73\x74\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x20\x7d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x73\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x43\x6f\x70\x79\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x49\x6e\x70\x75\x74\x20\x76\x61\x6c\x75\x65\x3d\x7b\x76\x6d\x2e\x66\x69\x65\x6c\x64\x54\x65\x78\x74\x28\x72\x6f\x77\x29\x7d\x20\x61\x70\x70\x65\x6e\x64\x54\x65\x78\x74\x3d\x7b\x75\x6e\x69\x74\x28\x72\x6f\x77\x29\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x31\x38\x30\x7d\x20\x69\x6e\x76\x61\x6c\x69\x64\x3d\x7b\x69\x6e\x76\x61\x6c\x69\x64\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x20\x66\x6f\x63\x75\x73\x49\x64\x3d\x7b\x66\x6f\x63\x75\x73\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x74\x7c\x20\x65\x64\x69\x74\x54\x65\x78\x74\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2c\x20\x74\x29\x7d\x20\x6f\x6e\x53\x75\x62\x6d\x69\x74\x3d\x7b\x7c\x74\x7c\x20\x65\x64\x69\x74\x54\x65\x78\x74\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2c\x20\x74\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x69\x6e\x70\x75\x74\x5f\x63\x6f\x6e\x74\x61\x69\x6e\x65\x72\x20\x3d\x20\x66\x69\x64\x20\x7d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x50\x72\x6f\x62\x6c\x65\x6d\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe9\x80\x89\xe6\x8b\xa9\xe8\xa1\x8c\xef\xbc\x9a\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x53\x65\x6c\x65\x63\x74\x60\xef\xbc\x88\x31\x38\x30\x20\xe5\xae\xbd\xef\xbc\x8c\xe4\xb8\x8b\xe6\x8b\x89\xe4\xb8\x8e\xe8\xa7\xa6\xe5\x8f\x91\xe5\x99\xa8\xe5\x90\x8c\xe5\xae\xbd\xef\xbc\x89\xef\xbc\x8c\xe4\xb8\x8b\xe6\x8b\x89\xe5\xbc\x80\xe5\x90\x88\xe5\xbd\x92\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\xef\xbc\x88\x45\x73\x63\x61\x70\x65\x20\xe6\x94\xb6\xe8\xb5\xb7\xef\xbc\x89\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x53\x65\x6c\x65\x63\x74\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x6f\x70\x74\x69\x6f\x6e\x73\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x57\x2e\x53\x65\x6c\x65\x63\x74\x4f\x70\x74\x69\x6f\x6e\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x66\x69\x64\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x72\x6f\x77\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x6c\x61\x73\x74\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x20\x7d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x73\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x43\x6f\x70\x79\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x65\x6c\x65\x63\x74\x20\x70\x61\x6e\x65\x6c\x57\x69\x64\x74\x68\x3d\x7b\x2e\x74\x72\x69\x67\x67\x65\x72\x7d\x20\x6f\x70\x74\x69\x6f\x6e\x73\x3d\x7b\x6f\x70\x74\x69\x6f\x6e\x73\x7d\x20\x76\x61\x6c\x75\x65\x3d\x7b\x76\x6d\x2e\x73\x65\x6c\x65\x63\x74\x56\x61\x6c\x75\x65\x28\x72\x6f\x77\x29\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x31\x38\x30\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x70\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x66\x69\x64\x29\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x66\x69\x64\x2c\x20\x6f\x29\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x76\x7c\x20\x70\x69\x63\x6b\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2c\x20\x76\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x74\x72\x69\x67\x67\x65\x72\x20\x3d\x20\x66\x69\x64\x20\x7d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x50\x72\x6f\x62\x6c\x65\x6d\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe9\x80\x89\xe6\x8b\xa9\xe8\xa1\x8c\x20\x2b\x20\xe5\x8e\x9f\xe5\x9c\xb0\xe7\xbc\x96\xe8\xbe\x91\xef\xbc\x88\x53\x2d\x31\x33\xef\xbc\x8c\xe2\x80\x9c\xe8\x87\xaa\xe5\xae\x9a\xe4\xb9\x89\x20\x54\x45\x52\x4d\x20\xe5\xa3\xb0\xe6\x98\x8e\xe2\x80\xa6\xe2\x80\x9d\xef\xbc\x89\xef\xbc\x9a\xe9\x80\x89\xe9\xa1\xb9\xe9\x87\x8c\xe7\x9a\x84\x20\x60\x63\x75\x73\x74\x6f\x6d\x5f\x63\x68\x6f\x69\x63\x65\x60\x20\xe5\x9c\xa8\xe9\x80\x89\xe6\x8b\xa9\xe6\xa1\x86\xe4\xb8\x8b\xe6\x96\xb9\xe6\x89\x93\xe5\xbc\x80\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x50\x6f\x70\x6f\x76\x65\x72\x60\x0a\x2f\x2f\x2f\x20\xef\xbc\x88\xe6\x89\x8b\xe5\x8a\xa8\xe8\xa7\xa6\xe5\x8f\x91\xef\xbc\x9a\xe5\xbc\x80\xe5\x90\x88\xe6\x98\xaf\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\x20\xe7\x9a\x84\x20\x60\x70\x6f\x70\x75\x70\x60\xe2\x80\x94\xe2\x80\x94\xe7\x82\xb9\xe5\xa4\x96\xe9\x9d\xa2\x20\x2f\x20\x45\x73\x63\x61\x70\x65\x20\xe6\x94\xb6\xe8\xb5\xb7\xef\xbc\x8c\xe9\x94\x9a\xe7\x82\xb9\xe6\xbb\x9a\xe5\x87\xba\xe8\xa7\x86\xe5\x8f\xa3\xe6\x94\xb6\xe8\xb5\xb7\xef\xbc\x9b\xe9\xbb\x98\xe8\xae\xa4\xe9\x9d\xa2\xe6\x9d\xbf\xe5\xa4\x96\xe8\xa7\x82\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x2f\x20\xe9\x87\x8c\xe9\x9d\xa2\xe6\x98\xaf\xe8\xaf\xb4\xe6\x98\x8e\xef\xbc\x88\x60\x6e\x6f\x74\x65\x49\x64\x60\xef\xbc\x89\xe4\xb8\x8e\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x49\x6e\x70\x75\x74\x60\xef\xbc\x88\xe5\x8f\x97\xe6\x8e\xa7\xef\xbc\x9a\xe8\x8d\x89\xe7\xa8\xbf\xe5\xbd\x92\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\xef\xbc\x8c\xe6\x89\x93\xe5\xbc\x80\xe5\x8d\xb3\xe8\x81\x9a\xe7\x84\xa6\xef\xbc\x8c\x45\x6e\x74\x65\x72\x20\xe6\x8f\x90\xe4\xba\xa4\xef\xbc\x8c\xe6\xa0\xa1\xe9\xaa\x8c\xe5\xa4\xb1\xe8\xb4\xa5\xe7\x94\xa8\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x65\x72\x72\x6f\x72\x4d\x73\x67\x60\xef\xbc\x89\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x43\x75\x73\x74\x6f\x6d\x53\x65\x6c\x65\x63\x74\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x6f\x70\x74\x69\x6f\x6e\x73\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x57\x2e\x53\x65\x6c\x65\x63\x74\x4f\x70\x74\x69\x6f\x6e\x2c\x20\x6e\x6f\x74\x65\x49\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x2c\x20\x6e\x6f\x74\x65\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x2c\x20\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x66\x69\x64\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x72\x6f\x77\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x6c\x61\x73\x74\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x20\x7d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x73\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x43\x6f\x70\x79\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x75\x73\x74\x6f\x6d\x5f\x61\x6e\x63\x68\x6f\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x53\x65\x6c\x65\x63\x74\x20\x70\x61\x6e\x65\x6c\x57\x69\x64\x74\x68\x3d\x7b\x2e\x74\x72\x69\x67\x67\x65\x72\x7d\x20\x6f\x70\x74\x69\x6f\x6e\x73\x3d\x7b\x6f\x70\x74\x69\x6f\x6e\x73\x7d\x20\x76\x61\x6c\x75\x65\x3d\x7b\x76\x6d\x2e\x73\x65\x6c\x65\x63\x74\x56\x61\x6c\x75\x65\x28\x72\x6f\x77\x29\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x31\x38\x30\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x64\x69\x73\x61\x62\x6c\x65\x64\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x70\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x66\x69\x64\x29\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x66\x69\x64\x2c\x20\x6f\x29\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x76\x7c\x20\x70\x69\x63\x6b\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2c\x20\x76\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x74\x72\x69\x67\x67\x65\x72\x20\x3d\x20\x66\x69\x64\x20\x7d\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x50\x6f\x70\x6f\x76\x65\x72\x20\x74\x72\x69\x67\x67\x65\x72\x3d\x7b\x2e\x6d\x61\x6e\x75\x61\x6c\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x70\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2e\x63\x75\x73\x74\x6f\x6d\x5f\x70\x6f\x70\x75\x70\x29\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2e\x63\x75\x73\x74\x6f\x6d\x5f\x70\x6f\x70\x75\x70\x2c\x20\x6f\x29\x7d\x20\x63\x6c\x6f\x73\x65\x4f\x6e\x41\x6e\x63\x68\x6f\x72\x53\x63\x72\x6f\x6c\x6c\x3d\x7b\x74\x72\x75\x65\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x32\x36\x34\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x68\x72\x6f\x6d\x65\x20\x3d\x20\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2e\x63\x75\x73\x74\x6f\x6d\x5f\x70\x6f\x70\x75\x70\x20\x7d\x7d\x20\x63\x6c\x6f\x73\x65\x4f\x6e\x45\x73\x63\x61\x70\x65\x3d\x7b\x4f\x2e\x70\x61\x6e\x65\x6c\x2e\x65\x73\x63\x61\x70\x65\x7d\x20\x63\x6c\x6f\x73\x65\x4f\x6e\x4f\x75\x74\x73\x69\x64\x65\x43\x6c\x69\x63\x6b\x3d\x7b\x4f\x2e\x70\x61\x6e\x65\x6c\x2e\x6f\x75\x74\x73\x69\x64\x65\x7d\x20\x63\x6f\x6e\x73\x75\x6d\x65\x4f\x75\x74\x73\x69\x64\x65\x43\x6c\x69\x63\x6b\x3d\x7b\x4f\x2e\x63\x6f\x6e\x73\x75\x6d\x65\x5f\x6f\x75\x74\x73\x69\x64\x65\x5f\x63\x6c\x69\x63\x6b\x7d\x20\x74\x72\x61\x70\x46\x6f\x63\x75\x73\x3d\x7b\x4f\x2e\x70\x61\x6e\x65\x6c\x2e\x74\x72\x61\x70\x5f\x66\x6f\x63\x75\x73\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x70\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2e\x63\x75\x73\x74\x6f\x6d\x5f\x70\x6f\x70\x75\x70\x29\x29\x20\x3c\x43\x75\x73\x74\x6f\x6d\x45\x64\x69\x74\x6f\x72\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x6e\x6f\x74\x65\x49\x64\x3d\x7b\x6e\x6f\x74\x65\x49\x64\x7d\x20\x6e\x6f\x74\x65\x3d\x7b\x6e\x6f\x74\x65\x7d\x20\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x3d\x7b\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x6f\x70\x6f\x76\x65\x72\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x50\x72\x6f\x62\x6c\x65\x6d\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x63\x75\x73\x74\x6f\x6d\x45\x64\x69\x74\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x74\x65\x78\x74\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x63\x75\x73\x74\x6f\x6d\x54\x65\x78\x74\x28\x74\x65\x78\x74\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x63\x75\x73\x74\x6f\x6d\x53\x75\x62\x6d\x69\x74\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x74\x65\x78\x74\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x63\x75\x73\x74\x6f\x6d\x53\x75\x62\x6d\x69\x74\x28\x74\x65\x78\x74\x29\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x43\x75\x73\x74\x6f\x6d\x45\x64\x69\x74\x6f\x72\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x6e\x6f\x74\x65\x49\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x2c\x20\x6e\x6f\x74\x65\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x2c\x20\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x63\x75\x73\x74\x6f\x6d\x5f\x65\x64\x69\x74\x6f\x72\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6e\x6f\x74\x65\x49\x64\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x68\x69\x6e\x74\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x68\x69\x6e\x74\x5f\x62\x6f\x78\x7d\x3e\x7b\x6e\x6f\x74\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x49\x6e\x70\x75\x74\x20\x76\x61\x6c\x75\x65\x3d\x7b\x76\x6d\x2e\x63\x75\x73\x74\x6f\x6d\x54\x65\x78\x74\x28\x29\x7d\x20\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x3d\x7b\x70\x6c\x61\x63\x65\x68\x6f\x6c\x64\x65\x72\x7d\x20\x61\x75\x74\x6f\x46\x6f\x63\x75\x73\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x6e\x76\x61\x6c\x69\x64\x3d\x7b\x76\x6d\x2e\x63\x75\x73\x74\x6f\x6d\x49\x6e\x76\x61\x6c\x69\x64\x28\x29\x7d\x20\x65\x72\x72\x6f\x72\x4d\x73\x67\x3d\x7b\x76\x6d\x2e\x63\x75\x73\x74\x6f\x6d\x50\x72\x6f\x62\x6c\x65\x6d\x28\x29\x7d\x20\x6f\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x74\x7c\x20\x63\x75\x73\x74\x6f\x6d\x45\x64\x69\x74\x28\x76\x6d\x2c\x20\x74\x29\x7d\x20\x6f\x6e\x53\x75\x62\x6d\x69\x74\x3d\x7b\x7c\x74\x7c\x20\x63\x75\x73\x74\x6f\x6d\x53\x75\x62\x6d\x69\x74\x28\x76\x6d\x2c\x20\x74\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe7\x9b\xae\xe5\xbd\x95\xe8\xa1\x8c\xef\xbc\x9a\xe5\x8e\x9f\xe7\x94\x9f\x20\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x20\xe6\x8c\x89\xe9\x92\xae\xe6\x98\xbe\xe7\xa4\xba\xe5\xbd\x93\xe5\x89\x8d\xe7\x9b\xae\xe5\xbd\x95\xef\xbc\x88\xe5\x8d\x95\xe8\xa1\x8c\xe7\x9c\x81\xe7\x95\xa5\xef\xbc\x89\xef\xbc\x8c\xe7\x82\xb9\xe5\x87\xbb\xe4\xba\xa4\xe5\xae\xbf\xe4\xb8\xbb\xe7\x9a\x84\xe7\xb3\xbb\xe7\xbb\x9f\xe7\x9b\xae\xe5\xbd\x95\xe9\x9d\xa2\xe6\x9d\xbf\xef\xbc\x9b\xe6\x82\xac\xe5\x81\x9c\x20\x2f\x20\xe8\x81\x9a\xe7\x84\xa6\xe6\x98\xbe\xe7\xa4\xba\xe5\x85\xa8\xe6\x96\x87\xe3\x80\x82\x0a\x2f\x2f\x2f\x20\xe6\x8f\x90\xe7\xa4\xba\xe5\xbc\x80\xe5\x90\x88\xe5\xbd\x92\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\x20\xe7\x9a\x84\x20\x60\x70\x6f\x70\x75\x70\x60\xef\xbc\x88\xe5\x90\x8c\xe6\x97\xa7\x20\x60\x72\x65\x67\x69\x73\x74\x65\x72\x54\x6f\x6f\x6c\x74\x69\x70\x60\xef\xbc\x9a\xe6\x95\xb4\xe7\xaa\x97\x20\x45\x73\x63\x61\x70\x65\x20\xe5\x85\x88\xe6\x94\xb6\xe8\xb5\xb7\xe5\xae\x83\xef\xbc\x8c\xe4\xb8\x8d\xe5\x85\xb3\xe7\xaa\x97\xef\xbc\x89\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x44\x69\x72\x65\x63\x74\x6f\x72\x79\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x6c\x61\x73\x74\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x20\x7d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x73\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x43\x6f\x70\x79\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x76\x6d\x2e\x66\x69\x65\x6c\x64\x54\x65\x78\x74\x28\x72\x6f\x77\x29\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x32\x39\x32\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x70\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x64\x69\x72\x65\x63\x74\x6f\x72\x79\x5f\x74\x69\x70\x29\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x64\x69\x72\x65\x63\x74\x6f\x72\x79\x5f\x74\x69\x70\x2c\x20\x6f\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x64\x69\x72\x65\x63\x74\x6f\x72\x79\x5f\x74\x69\x70\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x76\x6d\x2e\x66\x69\x65\x6c\x64\x54\x65\x78\x74\x28\x72\x6f\x77\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x76\x6d\x2e\x69\x73\x53\x61\x76\x69\x6e\x67\x28\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x44\x69\x72\x65\x63\x74\x6f\x72\x79\x42\x75\x74\x74\x6f\x6e\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6f\x66\x66\x20\x3d\x20\x76\x6d\x2e\x69\x73\x53\x61\x76\x69\x6e\x67\x28\x29\x20\x7d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x63\x68\x6f\x6f\x73\x65\x46\x6f\x72\x28\x72\x6f\x77\x2e\x6b\x65\x79\x2e\x3f\x29\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x66\x6f\x6c\x64\x65\x72\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x64\x69\x72\x65\x63\x74\x6f\x72\x79\x5f\x69\x63\x6f\x6e\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x22\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x64\x69\x72\x65\x63\x74\x6f\x72\x79\x2e\x6c\x61\x62\x65\x6c\x22\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x64\x69\x72\x65\x63\x74\x6f\x72\x79\x5f\x6c\x61\x62\x65\x6c\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x64\x69\x72\x65\x63\x74\x6f\x72\x79\x5f\x6c\x61\x62\x65\x6c\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x66\x69\x65\x6c\x64\x54\x65\x78\x74\x28\x72\x6f\x77\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe5\x8f\xaa\xe8\xaf\xbb\xe8\xa1\x8c\xef\xbc\x9a\xe5\x80\xbc\xe5\x8f\xb3\xe5\xaf\xb9\xe9\xbd\x90\xef\xbc\x9b\xe8\xb7\xaf\xe5\xbe\x84\xe5\x8d\x95\xe8\xa1\x8c\xe7\x9c\x81\xe7\x95\xa5\xef\xbc\x8c\xe6\x82\xac\xe5\x81\x9c\x20\x2f\x20\xe8\x81\x9a\xe7\x84\xa6\xe6\x98\xbe\xe7\xa4\xba\xe5\x85\xa8\xe6\x96\x87\xef\xbc\x88\x60\x73\x65\x74\x74\x69\x6e\x67\x73\x2e\x70\x61\x74\x68\x2e\x3c\xe6\xa0\x87\xe7\xad\xbe\x3e\x60\xef\xbc\x89\xe3\x80\x82\xe6\x8f\x90\xe7\xa4\xba\xe5\xbc\x80\xe5\x90\x88\xe5\xbd\x92\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\x20\xe7\x9a\x84\x20\x60\x70\x6f\x70\x75\x70\x60\x0a\x2f\x2f\x2f\x20\xef\xbc\x88\xe5\x90\x8c\xe6\x97\xa7\x20\x60\x48\x69\x6e\x74\x46\x6f\x63\x75\x73\x60\x20\x2b\x20\x60\x72\x65\x67\x69\x73\x74\x65\x72\x54\x6f\x6f\x6c\x74\x69\x70\x60\xef\xbc\x9a\xe8\x81\x9a\xe7\x84\xa6\xe5\x8d\xb3\xe6\x89\x93\xe5\xbc\x80\xef\xbc\x8c\xe6\x95\xb4\xe7\xaa\x97\x20\x45\x73\x63\x61\x70\x65\x20\xe5\x85\x88\xe6\x94\xb6\xe8\xb5\xb7\xe5\xae\x83\xef\xbc\x8c\xe4\xb8\x8d\xe5\x85\xb3\xe7\xaa\x97\xef\xbc\x89\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x49\x6e\x66\x6f\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x74\x69\x70\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x68\x65\x6c\x70\x54\x69\x70\x49\x64\x28\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x76\x61\x6c\x75\x65\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x76\x6d\x2e\x69\x6e\x66\x6f\x56\x61\x6c\x75\x65\x28\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x6c\x61\x73\x74\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x20\x7d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x73\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x61\x62\x65\x6c\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x6c\x61\x62\x65\x6c\x5f\x62\x6f\x78\x7d\x3e\x7b\x6c\x61\x62\x65\x6c\x28\x72\x6f\x77\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x76\x6d\x2e\x69\x6e\x66\x6f\x49\x73\x50\x61\x74\x68\x28\x72\x6f\x77\x29\x29\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x76\x6d\x2e\x69\x6e\x66\x6f\x56\x61\x6c\x75\x65\x28\x72\x6f\x77\x29\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x32\x39\x32\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x70\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x29\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x6f\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x74\x69\x70\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x76\x61\x6c\x75\x65\x5f\x62\x6f\x78\x7d\x20\x66\x6f\x63\x75\x73\x61\x62\x6c\x65\x3d\x7b\x74\x72\x75\x65\x7d\x20\x61\x31\x31\x79\x3d\x7b\x2e\x7b\x20\x2e\x6c\x61\x62\x65\x6c\x20\x3d\x20\x76\x61\x6c\x75\x65\x20\x7d\x7d\x20\x6f\x6e\x46\x6f\x63\x75\x73\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x74\x72\x75\x65\x29\x7d\x20\x6f\x6e\x42\x6c\x75\x72\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x66\x61\x6c\x73\x65\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x70\x61\x74\x68\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x70\x61\x74\x68\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x69\x6e\x66\x6f\x56\x61\x6c\x75\x65\x28\x72\x6f\x77\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x20\x65\x6c\x73\x65\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x76\x61\x6c\x75\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x76\x61\x6c\x75\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x6d\x2e\x69\x6e\x66\x6f\x56\x61\x6c\x75\x65\x28\x72\x6f\x77\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe5\x8a\xa8\xe4\xbd\x9c\xe8\xa1\x8c\xef\xbc\x9a\xe6\xa0\x87\xe7\xad\xbe\x20\x2b\x20\xe5\x8e\x9f\xe7\x94\x9f\xe6\x8c\x89\xe9\x92\xae\xef\xbc\x88\xe5\x8d\xb1\xe9\x99\xa9\xe6\x93\x8d\xe4\xbd\x9c\xe7\x94\xa8\x20\x64\x61\x6e\x67\x65\x72\x20\xe8\x89\xb2\xe8\xb0\x83\xef\xbc\x89\xef\xbc\x9b\xe4\xb8\x8d\xe5\x8f\xaf\xe7\x94\xa8\xe4\xb8\x94\xe6\x9c\x89\xe5\x8e\x9f\xe5\x9b\xa0\xe6\x97\xb6\xe6\x82\xac\xe5\x81\x9c\x20\x2f\x20\xe8\x81\x9a\xe7\x84\xa6\xe8\xaf\xb4\xe6\x98\x8e\xe5\x8e\x9f\xe5\x9b\xa0\xef\xbc\x88\x60\x3c\xe6\x8c\x89\xe9\x92\xae\x20\x69\x64\x3e\x2e\x74\x6f\x6f\x6c\x74\x69\x70\x60\xef\xbc\x89\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x41\x63\x74\x69\x6f\x6e\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x69\x63\x6f\x6e\x3a\x20\x3f\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x74\x69\x70\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x62\x75\x74\x74\x6f\x6e\x54\x69\x70\x49\x64\x28\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x6c\x61\x73\x74\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x20\x7d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x73\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x61\x62\x65\x6c\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x6c\x61\x62\x65\x6c\x5f\x62\x6f\x78\x7d\x3e\x7b\x6c\x61\x62\x65\x6c\x28\x72\x6f\x77\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x68\x61\x73\x52\x65\x61\x73\x6f\x6e\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x29\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x76\x6d\x2e\x61\x63\x74\x69\x6f\x6e\x52\x65\x61\x73\x6f\x6e\x28\x72\x6f\x77\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x74\x69\x70\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x41\x63\x74\x69\x6f\x6e\x42\x75\x74\x74\x6f\x6e\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x69\x63\x6f\x6e\x3d\x7b\x69\x63\x6f\x6e\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x20\x65\x6c\x73\x65\x20\x3c\x41\x63\x74\x69\x6f\x6e\x42\x75\x74\x74\x6f\x6e\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x69\x63\x6f\x6e\x3d\x7b\x69\x63\x6f\x6e\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x41\x63\x74\x69\x6f\x6e\x42\x75\x74\x74\x6f\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x69\x63\x6f\x6e\x3a\x20\x3f\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x62\x75\x74\x74\x6f\x6e\x4c\x61\x62\x65\x6c\x28\x72\x6f\x77\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x76\x61\x72\x69\x61\x6e\x74\x28\x72\x6f\x77\x29\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x69\x63\x6f\x6e\x7d\x20\x69\x63\x6f\x6e\x53\x69\x7a\x65\x3d\x7b\x31\x34\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x61\x63\x74\x69\x6f\x6e\x41\x31\x31\x79\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x21\x76\x6d\x2e\x61\x63\x74\x69\x6f\x6e\x45\x6e\x61\x62\x6c\x65\x64\x28\x72\x6f\x77\x29\x7d\x20\x66\x6f\x63\x75\x73\x49\x64\x3d\x7b\x61\x63\x74\x69\x6f\x6e\x46\x6f\x63\x75\x73\x28\x72\x6f\x77\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x72\x75\x6e\x43\x6f\x6d\x6d\x61\x6e\x64\x28\x72\x6f\x77\x2e\x63\x6f\x6d\x6d\x61\x6e\x64\x2e\x3f\x29\x29\x7d\x20\x2f\x3e\x3b\x0a\x7d\x0a\x66\x6e\x20\x68\x61\x73\x52\x65\x61\x73\x6f\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x61\x63\x74\x69\x6f\x6e\x52\x65\x61\x73\x6f\x6e\x28\x72\x6f\x77\x29\x2e\x6c\x65\x6e\x20\x21\x3d\x20\x30\x3b\x0a\x7d\x0a\x66\x6e\x20\x62\x75\x74\x74\x6f\x6e\x4c\x61\x62\x65\x6c\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x62\x75\x74\x74\x6f\x6e\x3b\x0a\x7d\x0a\x66\x6e\x20\x62\x75\x74\x74\x6f\x6e\x54\x69\x70\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x62\x75\x74\x74\x6f\x6e\x5f\x74\x69\x70\x3b\x0a\x7d\x0a\x66\x6e\x20\x76\x61\x72\x69\x61\x6e\x74\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x57\x2e\x42\x75\x74\x74\x6f\x6e\x56\x61\x72\x69\x61\x6e\x74\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x66\x20\x28\x72\x6f\x77\x2e\x64\x61\x6e\x67\x65\x72\x29\x20\x2e\x64\x61\x6e\x67\x65\x72\x20\x65\x6c\x73\x65\x20\x2e\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x3b\x0a\x7d\x0a\x66\x6e\x20\x61\x63\x74\x69\x6f\x6e\x41\x31\x31\x79\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x72\x65\x61\x73\x6f\x6e\x20\x3d\x20\x76\x6d\x2e\x61\x63\x74\x69\x6f\x6e\x52\x65\x61\x73\x6f\x6e\x28\x72\x6f\x77\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x66\x20\x28\x72\x65\x61\x73\x6f\x6e\x2e\x6c\x65\x6e\x20\x21\x3d\x20\x30\x29\x20\x72\x65\x61\x73\x6f\x6e\x20\x65\x6c\x73\x65\x20\x72\x6f\x77\x2e\x62\x75\x74\x74\x6f\x6e\x3b\x0a\x7d\x0a\x2f\x2f\x2f\x20\xe6\xb8\x85\xe7\x90\x86\xe6\x8c\x89\xe9\x92\xae\xe7\x9a\x84\xe7\x84\xa6\xe7\x82\xb9\xe6\xa0\x87\xe8\xaf\x86\xef\xbc\x88\xe6\xb8\x85\xe7\x90\x86\xe6\xb5\x81\xe7\xa8\x8b\xe7\xbb\x93\xe6\x9d\x9f\x20\x2f\x20\xe5\x8f\x96\xe6\xb6\x88\xe5\x90\x8e\xe5\xae\xbf\xe4\xb8\xbb\xe7\xbb\x8f\x20\x60\x72\x65\x71\x75\x65\x73\x74\x46\x6f\x63\x75\x73\x60\x20\xe5\x9b\x9e\xe7\x84\xa6\xef\xbc\x89\xef\xbc\x9b\xe5\x85\xb6\xe5\xae\x83\xe6\x8c\x89\xe9\x92\xae\xe6\xb2\xa1\xe6\x9c\x89\xe3\x80\x82\x0a\x66\x6e\x20\x61\x63\x74\x69\x6f\x6e\x46\x6f\x63\x75\x73\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x63\x6f\x6d\x6d\x61\x6e\x64\x20\x3d\x20\x72\x6f\x77\x2e\x63\x6f\x6d\x6d\x61\x6e\x64\x20\x6f\x72\x65\x6c\x73\x65\x20\x72\x65\x74\x75\x72\x6e\x20\x22\x22\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x73\x77\x69\x74\x63\x68\x20\x28\x63\x6f\x6d\x6d\x61\x6e\x64\x29\x20\x7b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x63\x6c\x65\x61\x72\x5f\x61\x6c\x6c\x20\x3d\x3e\x20\x6d\x2e\x66\x6f\x63\x75\x73\x5f\x69\x64\x73\x2e\x64\x61\x74\x61\x5f\x63\x6c\x65\x61\x72\x5f\x61\x6c\x6c\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x63\x6c\x65\x61\x72\x5f\x6c\x6f\x67\x73\x20\x3d\x3e\x20\x6d\x2e\x66\x6f\x63\x75\x73\x5f\x69\x64\x73\x2e\x64\x61\x74\x61\x5f\x63\x6c\x65\x61\x72\x5f\x6c\x6f\x67\x73\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x65\x6c\x73\x65\x20\x3d\x3e\x20\x22\x22\x2c\x0a\x20\x20\x20\x20\x7d\x3b\x0a\x7d\x0a\x2f\x2f\x2f\x20\xe5\xbc\x80\xe5\x85\xb3\xe7\x9a\x84\xe6\x97\xa0\xe9\x9a\x9c\xe7\xa2\x8d\xe5\xb1\x9e\xe6\x80\xa7\xef\xbc\x88\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x6c\x61\x62\x65\x6c\x60\x20\xe4\xbc\x9a\xe6\x8a\x8a\xe6\x96\x87\xe5\xad\x97\xe7\x94\xbb\xe5\x9c\xa8\xe5\xbc\x80\xe5\x85\xb3\xe6\x97\x81\xe8\xbe\xb9\xef\xbc\x8c\xe6\x89\x80\xe4\xbb\xa5\xe5\x90\x8d\xe5\xad\x97\xe5\x8f\xaa\xe8\xbf\x9b\x20\x61\x31\x31\x79\xef\xbc\x8c\xe5\x90\x8c\xe6\x97\xa7\x20\x60\x61\x31\x31\x79\x2e\x6c\x61\x62\x65\x6c\x20\x3d\x20\x6c\x61\x62\x65\x6c\x60\xef\xbc\x89\xe3\x80\x82\x0a\x66\x6e\x20\x73\x77\x69\x74\x63\x68\x41\x31\x31\x79\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x3f\x75\x69\x2e\x41\x31\x31\x79\x50\x72\x6f\x70\x73\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x2e\x7b\x20\x2e\x72\x6f\x6c\x65\x20\x3d\x20\x2e\x73\x77\x69\x74\x63\x68\x5f\x72\x6f\x6c\x65\x2c\x20\x2e\x6c\x61\x62\x65\x6c\x20\x3d\x20\x72\x6f\x77\x2e\x6c\x61\x62\x65\x6c\x2c\x20\x2e\x63\x68\x65\x63\x6b\x65\x64\x20\x3d\x20\x76\x6d\x2e\x62\x6f\x6f\x6c\x4f\x66\x28\x72\x6f\x77\x2e\x6b\x65\x79\x2e\x3f\x29\x2c\x20\x2e\x64\x69\x73\x61\x62\x6c\x65\x64\x20\x3d\x20\x76\x6d\x2e\x66\x69\x65\x6c\x64\x44\x69\x73\x61\x62\x6c\x65\x64\x28\x72\x6f\x77\x29\x20\x7d\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\xe5\xbf\xab\xe6\x8d\xb7\xe9\x94\xae\xe8\xa1\x8c\xef\xbc\x88\x50\x33\x20\x33\x65\x20\xe7\xac\xac\xe4\xba\x8c\xe6\x89\xb9\xef\xbc\x8c\xe4\xba\xba\xe5\xb7\xa5\xe9\xaa\x8c\xe6\x94\xb6\xe5\x8f\x8d\xe9\xa6\x88\xe7\xac\xac\x20\x37\x20\xe6\x9d\xa1\xef\xbc\x9b\xe4\xba\xa4\xe4\xba\x92\xe8\xae\xbe\xe8\xae\xa1\xe8\xa7\x81\x20\x64\x6f\x63\x73\x2f\x75\x69\x2d\x72\x65\x76\x61\x6d\x70\x2f\x59\x49\x58\x5f\x53\x50\x49\x4b\x45\x2e\x6d\x64\xe2\x80\x9c\xe5\xbf\xab\xe6\x8d\xb7\xe9\x94\xae\xe8\xa1\x8c\xe7\x9a\x84\xe7\xbc\x96\xe8\xbe\x91\xe4\xba\xa4\xe4\xba\x92\xe2\x80\x9d\xef\xbc\x89\x20\xe2\x94\x80\xe2\x94\x80\x0a\x2f\x2f\x0a\x2f\x2f\x20\x20\x20\x20\x20\x4b\x65\x79\x62\x69\x6e\x64\x69\x6e\x67\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x20\x20\x2f\x2f\x20\x72\x6f\x77\x20\x3d\x20\x6d\x2e\x66\x69\x65\x6c\x64\x73\x2e\x6b\x65\x79\x73\x2e\x72\x6f\x77\x28\x3c\xe5\x8a\xa8\xe4\xbd\x9c\x3e\x29\x0a\x2f\x2f\x0a\x2f\x2f\x20\xe5\x8a\xa8\xe4\xbd\x9c\xe5\x90\x8d\xef\xbc\x88\xe5\x9b\xba\xe5\xae\x9a\xe5\x8a\xa8\xe4\xbd\x9c\xe5\xb8\xa6\xe9\x94\x81\xe3\x80\x81\xe6\x94\xb9\xe8\xbf\x87\xe6\x9c\xaa\xe4\xbf\x9d\xe5\xad\x98\xe5\xb8\xa6\xe2\x80\x9c\xe6\x9c\xaa\xe4\xbf\x9d\xe5\xad\x98\xe2\x80\x9d\xe5\xbe\xbd\xe6\xa0\x87\xef\xbc\x89\x2b\x20\xe9\x94\xae\xe5\xb8\xbd\xe5\x8c\xba\xef\xbc\x88\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x60\xef\xbc\x9a\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x4b\x62\x64\x60\x20\xe9\x94\xae\xe5\xb8\xbd\xef\xbc\x8c\xe6\xaf\x8f\xe4\xb8\xaa\xe4\xbf\xae\xe9\xa5\xb0\xe9\x94\xae\x20\x2f\x20\xe4\xb8\xbb\xe9\x94\xae\xe4\xb8\x80\xe4\xb8\xaa\xef\xbc\x8c\x0a\x2f\x2f\x20\xe5\xbd\x95\xe5\x88\xb6\x20\x2f\x20\xe6\x97\xa0\xe6\x95\x88\x20\x2f\x20\xe5\x86\xb2\xe7\xaa\x81\xe7\x94\xa8\xe5\xae\x83\xe7\x9a\x84\x20\x61\x63\x63\x65\x6e\x74\x20\x2f\x20\x64\x61\x6e\x67\x65\x72\x20\x2f\x20\x77\x61\x72\x6e\x69\x6e\x67\x20\xe8\x89\xb2\xe8\xb0\x83\xef\xbc\x9b\x0a\x2f\x2f\x20\xe6\xb7\xa1\xe8\x89\xb2\xe9\x93\x85\xe7\xac\x94\xef\xbc\x9b\xe6\x82\xac\xe5\x81\x9c\x20\x2f\x20\xe8\x81\x9a\xe7\x84\xa6\xe6\x9c\x89\xe5\x8e\x9f\xe7\x94\x9f\x20\x54\x6f\x6f\x6c\x74\x69\x70\xef\xbc\x89\x2b\x20\xe8\xa1\x8c\xe5\xb0\xbe\xe5\x8d\x95\xe8\xa1\x8c\xe6\x81\xa2\xe5\xa4\x8d\xe9\xbb\x98\xe8\xae\xa4\xef\xbc\x88\xe5\x8e\x9f\xe7\x94\x9f\x20\x67\x68\x6f\x73\x74\x20\xe5\x9b\xbe\xe6\xa0\x87\xe6\x8c\x89\xe9\x92\xae\xef\xbc\x89\xef\xbc\x9b\xe8\xa1\x8c\xe4\xb8\x8b\xe6\x98\xaf\xe6\x97\xa0\xe6\x95\x88\xe5\x8e\x9f\xe5\x9b\xa0\xe6\x88\x96\xe5\x86\xb2\xe7\xaa\x81\xe6\x8f\x90\xe7\xa4\xba\xe4\xb8\x8e\xe3\x80\x90\xe4\xba\xa4\xe6\x8d\xa2\xe3\x80\x91\xe3\x80\x90\xe5\x8f\x96\xe6\xb6\x88\xe3\x80\x91\xe3\x80\x82\x0a\x2f\x2f\x20\xe5\xbd\x95\xe5\x88\xb6\xe7\x8a\xb6\xe6\x80\x81\xe6\x98\xaf\x20\x76\x69\x65\x77\x2d\x6d\x6f\x64\x65\x6c\x20\xe7\x9a\x84\x20\x60\x6b\x65\x79\x5f\x65\x64\x69\x74\x60\x20\xe4\xbf\xa1\xe5\x8f\xb7\xef\xbc\x8c\xe9\x94\xae\xe5\xb8\xbd\xe5\x8c\xba\xe7\x9a\x84\x20\x60\x6f\x6e\x4b\x65\x79\x44\x6f\x77\x6e\x60\xef\xbc\x88\xe7\xbb\x84\xe4\xbb\xb6\xe6\xa0\xb9\xe6\x8d\x95\xe8\x8e\xb7\xe6\xa7\xbd\xef\xbc\x89\xe6\x8a\x8a\xe6\x8c\x89\xe9\x94\xae\xe4\xba\xa4\xe7\xbb\x99\x20\x60\x76\x6d\x2e\x6b\x65\x79\x44\x6f\x77\x6e\x60\xef\xbc\x9b\x0a\x2f\x2f\x20\xe7\x84\xa6\xe7\x82\xb9\xe7\xa6\xbb\xe5\xbc\x80\xe9\x94\xae\xe5\xb8\xbd\xe5\x8c\xba\xef\xbc\x88\x54\x61\x62\xe3\x80\x81\xe7\x82\xb9\xe5\x88\xab\xe5\xa4\x84\xef\xbc\x89\xe7\x94\xb1\xe5\xae\x83\xe7\x9a\x84\x20\x60\x6f\x6e\x42\x6c\x75\x72\x57\x69\x74\x68\x69\x6e\x60\x20\xe7\xbb\x93\xe6\x9d\x9f\xe5\xbd\x95\xe5\x88\xb6\xef\xbc\x88\x47\x33\x31\xef\xbc\x9b\xe5\x86\xb2\xe7\xaa\x81\xe6\x80\x81\xe5\x8f\xaa\xe6\x98\xaf\xe4\xb8\x8d\xe5\x86\x8d\xe6\x8e\xa5\xe6\x8c\x89\xe9\x94\xae\xef\xbc\x89\xe3\x80\x82\x0a\x0a\x66\x6e\x20\x61\x63\x74\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x6d\x2e\x4b\x65\x79\x41\x63\x74\x69\x6f\x6e\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x73\x68\x6f\x72\x74\x63\x75\x74\x2e\x3f\x3b\x0a\x7d\x0a\x66\x6e\x20\x69\x73\x46\x69\x78\x65\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x6d\x2e\x6b\x65\x79\x62\x69\x6e\x64\x69\x6e\x67\x5f\x65\x64\x69\x74\x2e\x66\x69\x78\x65\x64\x28\x72\x6f\x77\x2e\x73\x68\x6f\x72\x74\x63\x75\x74\x2e\x3f\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x6d\x61\x72\x6b\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x6d\x61\x72\x6b\x3b\x0a\x7d\x0a\x66\x6e\x20\x72\x65\x73\x65\x74\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x72\x65\x73\x65\x74\x3b\x0a\x7d\x0a\x66\x6e\x20\x72\x65\x73\x65\x74\x54\x69\x70\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x72\x65\x73\x65\x74\x5f\x74\x69\x70\x3b\x0a\x7d\x0a\x66\x6e\x20\x73\x77\x61\x70\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x73\x77\x61\x70\x3b\x0a\x7d\x0a\x66\x6e\x20\x63\x61\x6e\x63\x65\x6c\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x63\x61\x6e\x63\x65\x6c\x3b\x0a\x7d\x0a\x66\x6e\x20\x66\x69\x78\x65\x64\x54\x69\x70\x49\x64\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x69\x64\x73\x2e\x62\x75\x74\x74\x6f\x6e\x5f\x74\x69\x70\x3b\x0a\x7d\x0a\x66\x6e\x20\x63\x61\x70\x54\x6f\x6e\x65\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x57\x2e\x4b\x62\x64\x54\x6f\x6e\x65\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x73\x77\x69\x74\x63\x68\x20\x28\x76\x6d\x2e\x6b\x65\x79\x54\x6f\x6e\x65\x28\x72\x6f\x77\x2e\x73\x68\x6f\x72\x74\x63\x75\x74\x2e\x3f\x29\x29\x20\x7b\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x72\x65\x73\x74\x20\x3d\x3e\x20\x2e\x6e\x65\x75\x74\x72\x61\x6c\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x72\x65\x63\x6f\x72\x64\x69\x6e\x67\x20\x3d\x3e\x20\x2e\x61\x63\x63\x65\x6e\x74\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x69\x6e\x76\x61\x6c\x69\x64\x20\x3d\x3e\x20\x2e\x64\x61\x6e\x67\x65\x72\x2c\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x2e\x63\x6f\x6e\x66\x6c\x69\x63\x74\x20\x3d\x3e\x20\x2e\x77\x61\x72\x6e\x69\x6e\x67\x2c\x0a\x20\x20\x20\x20\x7d\x3b\x0a\x7d\x0a\x2f\x2f\x2f\x20\xe9\x94\xae\xe5\xb8\xbd\xe5\x8c\xba\xe7\x9a\x84\xe6\x8f\x90\xe7\xa4\xba\xe5\x8f\xaa\xe5\x9c\xa8\xe9\x9d\x99\xe6\xad\xa2\xe6\x97\xb6\xe6\x89\x93\xe5\xbc\x80\xef\xbc\x9a\xe5\xbd\x95\xe5\x88\xb6\x20\x2f\x20\xe6\x97\xa0\xe6\x95\x88\x20\x2f\x20\xe5\x86\xb2\xe7\xaa\x81\xe6\x97\xb6\xe8\xa1\x8c\xe5\x86\x85\xe5\xb7\xb2\xe6\x9c\x89\xe8\xaf\xb4\xe6\x98\x8e\xef\xbc\x8c\xe8\x80\x8c\xe4\xb8\x94\xe6\x89\x93\xe5\xbc\x80\xe7\x9d\x80\xe7\x9a\x84\xe6\x8f\x90\xe7\xa4\xba\xe4\xbc\x9a\xe5\x85\x88\xe5\x90\x83\xe6\x8e\x89\x20\x45\x73\x63\x61\x70\x65\xef\xbc\x88\xe6\xa1\x86\xe6\x9e\xb6\xe5\x85\x88\xe6\x94\xb6\xe8\xb5\xb7\xe6\x8f\x90\xe7\xa4\xba\xef\xbc\x89\xef\xbc\x8c\x0a\x2f\x2f\x2f\x20\xe7\x94\xa8\xe6\x88\xb7\xe6\x8c\x89\xe4\xb8\x80\xe6\xac\xa1\x20\x45\x73\x63\x20\xe5\xb0\xb1\xe8\xaf\xa5\xe5\x8f\x96\xe6\xb6\x88\xe5\xbd\x95\xe5\x88\xb6\xe3\x80\x82\x0a\x66\x6e\x20\x74\x69\x70\x4f\x70\x65\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x69\x64\x3a\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x70\x6f\x70\x75\x70\x4f\x70\x65\x6e\x28\x69\x64\x29\x20\x61\x6e\x64\x20\x21\x76\x6d\x2e\x6b\x65\x79\x41\x63\x74\x69\x76\x65\x28\x72\x6f\x77\x2e\x73\x68\x6f\x72\x74\x63\x75\x74\x2e\x3f\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x70\x65\x6e\x63\x69\x6c\x53\x68\x6f\x77\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x6b\x65\x79\x45\x64\x69\x74\x61\x62\x6c\x65\x28\x72\x6f\x77\x2e\x73\x68\x6f\x72\x74\x63\x75\x74\x2e\x3f\x29\x20\x61\x6e\x64\x20\x21\x76\x6d\x2e\x6b\x65\x79\x41\x63\x74\x69\x76\x65\x28\x72\x6f\x77\x2e\x73\x68\x6f\x72\x74\x63\x75\x74\x2e\x3f\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x69\x6e\x76\x61\x6c\x69\x64\x53\x68\x6f\x77\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x6b\x65\x79\x50\x68\x61\x73\x65\x28\x72\x6f\x77\x2e\x73\x68\x6f\x72\x74\x63\x75\x74\x2e\x3f\x29\x20\x3d\x3d\x20\x2e\x69\x6e\x76\x61\x6c\x69\x64\x3b\x0a\x7d\x0a\x66\x6e\x20\x6b\x65\x79\x44\x6f\x77\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x65\x3a\x20\x75\x69\x2e\x76\x69\x65\x77\x2e\x4b\x65\x79\x50\x72\x65\x73\x73\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x69\x66\x20\x28\x76\x6d\x2e\x6b\x65\x79\x44\x6f\x77\x6e\x28\x72\x6f\x77\x2e\x73\x68\x6f\x72\x74\x63\x75\x74\x2e\x3f\x2c\x20\x65\x2e\x6b\x65\x79\x2c\x20\x65\x2e\x6d\x6f\x64\x69\x66\x69\x65\x72\x73\x29\x29\x20\x65\x2e\x73\x74\x6f\x70\x28\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x6b\x65\x79\x55\x70\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x65\x3a\x20\x75\x69\x2e\x76\x69\x65\x77\x2e\x4b\x65\x79\x50\x72\x65\x73\x73\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x69\x66\x20\x28\x76\x6d\x2e\x6b\x65\x79\x55\x70\x28\x72\x6f\x77\x2e\x73\x68\x6f\x72\x74\x63\x75\x74\x2e\x3f\x2c\x20\x65\x2e\x6b\x65\x79\x2c\x20\x65\x2e\x6d\x6f\x64\x69\x66\x69\x65\x72\x73\x29\x29\x20\x65\x2e\x73\x74\x6f\x70\x28\x29\x3b\x0a\x7d\x0a\x2f\x2f\x2f\x20\xe5\x9b\xba\xe5\xae\x9a\xe5\x8a\xa8\xe4\xbd\x9c\xe7\x9a\x84\xe9\x94\x81\xef\xbc\x9a\xe5\x8e\x9f\xe7\x94\x9f\x20\x67\x68\x6f\x73\x74\x20\xe5\x9b\xbe\xe6\xa0\x87\xe6\x8c\x89\xe9\x92\xae\x20\x2b\x20\xe5\x8e\x9f\xe7\x94\x9f\x20\x54\x6f\x6f\x6c\x74\x69\x70\x20\xe2\x80\x9c\xe4\xbf\x9d\xe7\x95\x99\xe7\xbb\x99\xe5\xba\x94\xe7\x94\xa8\xef\xbc\x8c\xe4\xb8\x8d\xe5\x8f\xaf\xe4\xbf\xae\xe6\x94\xb9\xe2\x80\x9d\xef\xbc\x88\xe5\x90\x8c\xe6\x97\xa7\x20\x60\x63\x6f\x6e\x74\x72\x6f\x6c\x73\x2e\x69\x6e\x6c\x69\x6e\x65\x48\x69\x6e\x74\x60\xef\xbc\x9b\xe6\x82\xac\xe5\x81\x9c\x20\x2f\x20\xe8\x81\x9a\xe7\x84\xa6\x20\x2f\x20\xe7\x82\xb9\xe5\x87\xbb\xe6\x89\x93\xe5\xbc\x80\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x2f\x20\xe8\x81\x9a\xe7\x84\xa6\xe5\xbc\x80\xe5\x90\x88\xe5\x86\x99\xe5\x9c\xa8\xe5\xa4\x96\xe5\xb1\x82\xe7\x9b\x92\xe5\xad\x90\xe7\x9a\x84\x20\x60\x6f\x6e\x46\x6f\x63\x75\x73\x57\x69\x74\x68\x69\x6e\x60\x20\x2f\x20\x60\x6f\x6e\x42\x6c\x75\x72\x57\x69\x74\x68\x69\x6e\x60\xef\xbc\x88\x47\x33\x31\xef\xbc\x89\xef\xbc\x9a\xe7\x84\xa6\xe7\x82\xb9\xe8\x90\xbd\xe5\x9c\xa8\xe9\x87\x8c\xe9\x9d\xa2\xe7\x9a\x84\xe6\x8c\x89\xe9\x92\xae\xe4\xb8\x8a\xef\xbc\x8c\xe7\x9b\x92\xe5\xad\x90\xe8\x87\xaa\xe5\xb7\xb1\xe7\x9a\x84\x20\x60\x6f\x6e\x46\x6f\x63\x75\x73\x60\x20\x2f\x20\x60\x6f\x6e\x42\x6c\x75\x72\x60\x20\xe6\x94\xb6\xe4\xb8\x8d\xe5\x88\xb0\xe3\x80\x82\x0a\x66\x6e\x20\x46\x69\x78\x65\x64\x48\x69\x6e\x74\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x74\x69\x70\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x66\x69\x78\x65\x64\x54\x69\x70\x49\x64\x28\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x68\x65\x6c\x70\x5f\x73\x6c\x6f\x74\x7d\x20\x6f\x6e\x46\x6f\x63\x75\x73\x57\x69\x74\x68\x69\x6e\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x74\x72\x75\x65\x29\x7d\x20\x6f\x6e\x42\x6c\x75\x72\x57\x69\x74\x68\x69\x6e\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x66\x61\x6c\x73\x65\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x22\xe4\xbf\x9d\xe7\x95\x99\xe7\xbb\x99\xe5\xba\x94\xe7\x94\xa8\xef\xbc\x8c\xe4\xb8\x8d\xe5\x8f\xaf\xe4\xbf\xae\xe6\x94\xb9\x22\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x20\x77\x69\x64\x74\x68\x3d\x7b\x32\x39\x32\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x70\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x29\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x6f\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x74\x69\x70\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x68\x65\x6c\x70\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x78\x73\x7d\x20\x69\x63\x6f\x6e\x4f\x6e\x6c\x79\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x6c\x6f\x63\x6b\x7d\x20\x69\x63\x6f\x6e\x53\x69\x7a\x65\x3d\x7b\x31\x34\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x22\xe4\xbf\x9d\xe7\x95\x99\xe7\xbb\x99\xe5\xba\x94\xe7\x94\xa8\xef\xbc\x8c\xe4\xb8\x8d\xe5\x8f\xaf\xe4\xbf\xae\xe6\x94\xb9\x22\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x74\x72\x75\x65\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x4b\x65\x79\x62\x69\x6e\x64\x69\x6e\x67\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x74\x69\x70\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x68\x65\x6c\x70\x54\x69\x70\x49\x64\x28\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x72\x65\x73\x65\x74\x5f\x74\x69\x70\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x72\x65\x73\x65\x74\x54\x69\x70\x49\x64\x28\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x72\x6f\x77\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x6c\x61\x73\x74\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x20\x7d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x73\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x68\x65\x61\x64\x69\x6e\x67\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x61\x62\x65\x6c\x7d\x3e\x7b\x6c\x61\x62\x65\x6c\x28\x72\x6f\x77\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x69\x73\x46\x69\x78\x65\x64\x28\x72\x6f\x77\x29\x29\x20\x3c\x46\x69\x78\x65\x64\x48\x69\x6e\x74\x20\x76\x6d\x3d\x7b\x76\x6d\x7d\x20\x72\x6f\x77\x3d\x7b\x72\x6f\x77\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x61\x64\x67\x65\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x6d\x61\x72\x6b\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe6\x9c\xaa\xe4\xbf\x9d\xe5\xad\x98\x22\x20\x73\x74\x61\x74\x75\x73\x3d\x7b\x2e\x69\x6e\x66\x6f\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x4d\x6f\x64\x69\x66\x69\x65\x64\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x4b\x2e\x6b\x65\x79\x5f\x73\x6c\x6f\x74\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x54\x69\x70\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x20\x6f\x70\x65\x6e\x3d\x7b\x74\x69\x70\x4f\x70\x65\x6e\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2c\x20\x74\x69\x70\x29\x7d\x20\x6f\x6e\x4f\x70\x65\x6e\x43\x68\x61\x6e\x67\x65\x3d\x7b\x7c\x6f\x7c\x20\x73\x65\x74\x50\x6f\x70\x75\x70\x28\x76\x6d\x2c\x20\x74\x69\x70\x2c\x20\x6f\x29\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x74\x69\x70\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x66\x6f\x63\x75\x73\x49\x64\x3d\x7b\x66\x6f\x63\x75\x73\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x41\x31\x31\x79\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x21\x76\x6d\x2e\x6b\x65\x79\x45\x64\x69\x74\x61\x62\x6c\x65\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x20\x73\x65\x6c\x65\x63\x74\x65\x64\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x41\x63\x74\x69\x76\x65\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x4b\x2e\x4b\x65\x79\x41\x72\x65\x61\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x74\x6f\x6e\x65\x20\x3d\x20\x76\x6d\x2e\x6b\x65\x79\x54\x6f\x6e\x65\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x2c\x20\x2e\x66\x69\x78\x65\x64\x20\x3d\x20\x69\x73\x46\x69\x78\x65\x64\x28\x72\x6f\x77\x29\x20\x7d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x72\x65\x63\x6f\x72\x64\x4b\x65\x79\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x29\x7d\x20\x6f\x6e\x42\x6c\x75\x72\x57\x69\x74\x68\x69\x6e\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x62\x6c\x75\x72\x4b\x65\x79\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x29\x7d\x20\x6f\x6e\x4b\x65\x79\x44\x6f\x77\x6e\x3d\x7b\x7c\x65\x7c\x20\x6b\x65\x79\x44\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2c\x20\x65\x29\x7d\x20\x6f\x6e\x4b\x65\x79\x55\x70\x3d\x7b\x7c\x65\x7c\x20\x6b\x65\x79\x55\x70\x28\x76\x6d\x2c\x20\x72\x6f\x77\x2c\x20\x65\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x4b\x62\x64\x20\x6b\x65\x79\x73\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x43\x61\x70\x73\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x20\x74\x6f\x6e\x65\x3d\x7b\x63\x61\x70\x54\x6f\x6e\x65\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x4b\x2e\x6b\x65\x79\x5f\x70\x72\x6f\x6d\x70\x74\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x52\x65\x63\x6f\x72\x64\x69\x6e\x67\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x3e\xe6\x8c\x89\xe4\xb8\x8b\xe6\x96\xb0\xe5\xbf\xab\xe6\x8d\xb7\xe9\x94\xae\xe2\x80\xa6\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x4b\x2e\x6b\x65\x79\x5f\x65\x73\x63\x61\x70\x65\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x52\x65\x63\x6f\x72\x64\x69\x6e\x67\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x3e\x45\x73\x63\x20\xe5\x8f\x96\xe6\xb6\x88\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x70\x65\x6e\x63\x69\x6c\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x4b\x2e\x6b\x65\x79\x5f\x70\x65\x6e\x63\x69\x6c\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x70\x65\x6e\x63\x69\x6c\x53\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x4b\x2e\x6b\x65\x79\x5f\x72\x65\x73\x65\x74\x5f\x73\x6c\x6f\x74\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x20\x74\x65\x78\x74\x3d\x22\xe6\x81\xa2\xe5\xa4\x8d\xe9\xbb\x98\xe8\xae\xa4\xe5\xbf\xab\xe6\x8d\xb7\xe9\x94\xae\x22\x20\x70\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x6f\x70\x7d\x20\x70\x61\x72\x74\x73\x3d\x7b\x2e\x7b\x20\x2e\x63\x6f\x6e\x74\x65\x6e\x74\x20\x3d\x20\x72\x65\x73\x65\x74\x5f\x74\x69\x70\x20\x7d\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x72\x65\x73\x65\x74\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x52\x65\x73\x65\x74\x74\x61\x62\x6c\x65\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x78\x73\x7d\x20\x69\x63\x6f\x6e\x4f\x6e\x6c\x79\x3d\x7b\x74\x72\x75\x65\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x72\x6f\x74\x61\x74\x65\x5f\x63\x63\x77\x7d\x20\x69\x63\x6f\x6e\x53\x69\x7a\x65\x3d\x7b\x31\x34\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x22\xe6\x81\xa2\xe5\xa4\x8d\xe9\xbb\x98\xe8\xae\xa4\xe5\xbf\xab\xe6\x8d\xb7\xe9\x94\xae\x22\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x72\x65\x73\x65\x74\x4b\x65\x79\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x54\x6f\x6f\x6c\x74\x69\x70\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x65\x72\x72\x6f\x72\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x4b\x2e\x6b\x65\x79\x5f\x70\x72\x6f\x62\x6c\x65\x6d\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x50\x72\x6f\x62\x6c\x65\x6d\x53\x68\x6f\x77\x6e\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x4b\x2e\x6b\x65\x79\x5f\x70\x72\x6f\x62\x6c\x65\x6d\x5f\x74\x65\x78\x74\x7d\x20\x62\x6f\x78\x3d\x7b\x4b\x2e\x6b\x65\x79\x5f\x70\x72\x6f\x62\x6c\x65\x6d\x5f\x74\x65\x78\x74\x5f\x62\x6f\x78\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x69\x6e\x76\x61\x6c\x69\x64\x53\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x7b\x76\x6d\x2e\x6b\x65\x79\x50\x72\x6f\x62\x6c\x65\x6d\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x4b\x2e\x6b\x65\x79\x5f\x63\x6f\x6e\x66\x6c\x69\x63\x74\x5f\x74\x65\x78\x74\x7d\x20\x62\x6f\x78\x3d\x7b\x4b\x2e\x6b\x65\x79\x5f\x70\x72\x6f\x62\x6c\x65\x6d\x5f\x74\x65\x78\x74\x5f\x62\x6f\x78\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x43\x6f\x6e\x66\x6c\x69\x63\x74\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x3e\x7b\x76\x6d\x2e\x6b\x65\x79\x50\x72\x6f\x62\x6c\x65\x6d\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x73\x77\x61\x70\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x43\x6f\x6e\x66\x6c\x69\x63\x74\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe4\xba\xa4\xe6\x8d\xa2\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x73\x65\x63\x6f\x6e\x64\x61\x72\x79\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x78\x73\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x73\x77\x61\x70\x4b\x65\x79\x28\x29\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x63\x61\x6e\x63\x65\x6c\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x76\x6d\x2e\x6b\x65\x79\x43\x6f\x6e\x66\x6c\x69\x63\x74\x28\x61\x63\x74\x28\x72\x6f\x77\x29\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x22\xe5\x8f\x96\xe6\xb6\x88\x22\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x67\x68\x6f\x73\x74\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x78\x73\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x63\x61\x6e\x63\x65\x6c\x4b\x65\x79\x28\x29\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\xe5\x85\xb3\xe4\xba\x8e\xe4\xb8\x8e\xe6\x9b\xb4\xe6\x96\xb0\xe7\x94\xa8\xe5\x88\xb0\xe7\x9a\x84\xe8\xa1\x8c\xef\xbc\x88\x50\x33\x20\x33\x65\x20\xe7\xac\xac\xe4\xba\x8c\xe6\x89\xb9\xef\xbc\x89\x20\xe2\x94\x80\xe2\x94\x80\x0a\x2f\x2f\x0a\x2f\x2f\x20\x20\x20\x20\x20\x56\x61\x6c\x75\x65\x52\x6f\x77\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x76\x61\x6c\x75\x65\x3a\x20\x54\x65\x78\x74\x29\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x2f\x2f\x20\xe6\xa0\x87\xe7\xad\xbe\x20\x2b\x20\xe5\x8f\xb3\xe4\xbe\xa7\xe5\x8f\xaa\xe8\xaf\xbb\xe5\x80\xbc\xef\xbc\x88\xe5\x80\xbc\xe7\x94\xb1\xe8\xb0\x83\xe7\x94\xa8\xe6\x96\xb9\xe7\xbb\x99\xef\xbc\x8c\xe8\xb7\x9f\xe9\x9a\x8f\xe4\xbf\xa1\xe5\x8f\xb7\xef\xbc\x89\x0a\x2f\x2f\x20\x20\x20\x20\x20\x4c\x69\x6e\x6b\x52\x6f\x77\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x69\x63\x6f\x6e\x3a\x20\x3f\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x29\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x2f\x2f\x20\xe6\xa0\x87\xe7\xad\xbe\x20\x2b\x20\xe5\x8e\x9f\xe7\x94\x9f\x20\x6c\x69\x6e\x6b\x20\xe6\x8c\x89\xe9\x92\xae\xef\xbc\x88\x60\x72\x6f\x77\x2e\x62\x75\x74\x74\x6f\x6e\x60\x20\x2f\x20\x60\x72\x6f\x77\x2e\x63\x6f\x6d\x6d\x61\x6e\x64\x60\xef\xbc\x89\x0a\x0a\x2f\x2f\x2f\x20\xe5\x8f\xaa\xe8\xaf\xbb\xe5\x80\xbc\xe8\xa1\x8c\xef\xbc\x9a\xe6\xa0\x87\xe7\xad\xbe\xe5\xb7\xa6\xe3\x80\x81\xe5\x80\xbc\xe5\x8f\xb3\xef\xbc\x88\x31\x32\xef\xbc\x8c\xe6\xac\xa1\xe8\xa6\x81\xe5\xa2\xa8\xe8\x89\xb2\xef\xbc\x8c\xe5\x8d\x95\xe8\xa1\x8c\xef\xbc\x89\xef\xbc\x8c\xe5\x80\xbc\xe7\x9a\x84\x20\x74\x65\x73\x74\x5f\x69\x64\x20\xe6\x98\xaf\x20\x60\x72\x6f\x77\x2e\x69\x64\x73\x2e\x66\x69\x65\x6c\x64\x60\xef\xbc\x88\xe5\x90\x8c\xe6\x97\xa7\x20\x60\x73\x65\x74\x74\x69\x6e\x67\x73\x5f\x75\x70\x64\x61\x74\x65\x73\x2e\x66\x61\x63\x74\x52\x6f\x77\x60\xef\xbc\x89\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x56\x61\x6c\x75\x65\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x76\x61\x6c\x75\x65\x3a\x20\x54\x65\x78\x74\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x6c\x61\x73\x74\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x20\x7d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x73\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x61\x62\x65\x6c\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x6c\x61\x62\x65\x6c\x5f\x62\x6f\x78\x7d\x3e\x7b\x6c\x61\x62\x65\x6c\x28\x72\x6f\x77\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x76\x61\x6c\x75\x65\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x76\x61\x6c\x75\x65\x5f\x62\x6f\x78\x7d\x3e\x7b\x76\x61\x6c\x75\x65\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x2f\x20\xe9\x93\xbe\xe6\x8e\xa5\xe8\xa1\x8c\xef\xbc\x9a\xe6\xa0\x87\xe7\xad\xbe\x20\x2b\x20\xe5\x8e\x9f\xe7\x94\x9f\x20\x6c\x69\x6e\x6b\x20\xe6\x8c\x89\xe9\x92\xae\xef\xbc\x88\xe5\xb0\xbe\xe9\x9a\x8f\xe5\xa4\x96\xe9\x93\xbe\xe5\x9b\xbe\xe6\xa0\x87\xef\xbc\x9a\x60\x69\x63\x6f\x6e\x50\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x72\x61\x69\x6c\x69\x6e\x67\x7d\x60\xef\xbc\x8c\x47\x33\x33\xef\xbc\x89\xef\xbc\x8c\xe7\x82\xb9\xe5\x87\xbb\xe5\x8f\x91\x20\x60\x72\x6f\x77\x2e\x63\x6f\x6d\x6d\x61\x6e\x64\x60\xef\xbc\x9b\xe4\xbf\x9d\xe5\xad\x98\xe4\xb8\xad\xe4\xb8\x8d\xe5\x8f\xaf\xe7\x94\xa8\xef\xbc\x88\xe5\x90\x8c\xe6\x97\xa7\xe2\x80\x9c\xe5\x8f\x91\xe5\xb8\x83\xe6\x9d\xa5\xe6\xba\x90\xe2\x80\x9d\xef\xbc\x89\xe3\x80\x82\x0a\x70\x75\x62\x20\x66\x6e\x20\x4c\x69\x6e\x6b\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x70\x61\x6e\x65\x3a\x20\x2a\x63\x6f\x6e\x73\x74\x20\x6d\x2e\x50\x61\x6e\x65\x53\x70\x65\x63\x2c\x20\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x2c\x20\x69\x63\x6f\x6e\x3a\x20\x3f\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x63\x6f\x6e\x73\x74\x20\x6e\x61\x6d\x65\x20\x3d\x20\x63\x6f\x6d\x70\x75\x74\x65\x64\x28\x6c\x69\x6e\x6b\x41\x31\x31\x79\x28\x72\x6f\x77\x29\x29\x3b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x53\x65\x74\x74\x69\x6e\x67\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x6c\x61\x73\x74\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x20\x7d\x29\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x73\x68\x6f\x77\x6e\x28\x76\x6d\x2c\x20\x70\x61\x6e\x65\x2c\x20\x72\x6f\x77\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x69\x6e\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x73\x65\x74\x74\x69\x6e\x67\x5f\x6c\x61\x62\x65\x6c\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x69\x6e\x66\x6f\x5f\x6c\x61\x62\x65\x6c\x5f\x62\x6f\x78\x7d\x3e\x7b\x6c\x61\x62\x65\x6c\x28\x72\x6f\x77\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x42\x75\x74\x74\x6f\x6e\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x66\x69\x65\x6c\x64\x49\x64\x28\x72\x6f\x77\x29\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x62\x75\x74\x74\x6f\x6e\x4c\x61\x62\x65\x6c\x28\x72\x6f\x77\x29\x7d\x20\x76\x61\x72\x69\x61\x6e\x74\x3d\x7b\x2e\x6c\x69\x6e\x6b\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x69\x63\x6f\x6e\x41\x73\x73\x65\x74\x3d\x7b\x69\x63\x6f\x6e\x7d\x20\x69\x63\x6f\x6e\x50\x6f\x73\x69\x74\x69\x6f\x6e\x3d\x7b\x2e\x74\x72\x61\x69\x6c\x69\x6e\x67\x7d\x20\x69\x63\x6f\x6e\x53\x69\x7a\x65\x3d\x7b\x31\x32\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x6e\x61\x6d\x65\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x76\x6d\x2e\x69\x73\x53\x61\x76\x69\x6e\x67\x28\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x73\x65\x6e\x64\x28\x76\x6d\x2c\x20\x6d\x2e\x49\x6e\x74\x65\x6e\x74\x2e\x72\x75\x6e\x43\x6f\x6d\x6d\x61\x6e\x64\x28\x72\x6f\x77\x2e\x63\x6f\x6d\x6d\x61\x6e\x64\x2e\x3f\x29\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x6c\x69\x6e\x6b\x41\x31\x31\x79\x28\x72\x6f\x77\x3a\x20\x6d\x2e\x52\x6f\x77\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x72\x6f\x77\x2e\x6d\x61\x74\x63\x68\x3b\x0a\x7d\x0a\x0a\x2f\x2f\x20\xe2\x94\x80\xe2\x94\x80\x20\xe4\xb8\xa4\xe7\xba\xa7\xe5\xaf\xbc\xe8\x88\xaa\xe7\x9a\x84\xe5\x88\x97\xe8\xa1\xa8\xe8\xa1\x8c\xef\xbc\x88\x46\x2d\x73\x65\x74\x2d\x70\x6c\x75\x67\x69\x6e\x73\x20\xe8\xb5\xb7\xef\xbc\x9b\xe5\x8d\x8f\xe8\xae\xae\xe6\x8f\x92\xe4\xbb\xb6\xe5\x88\x97\xe8\xa1\xa8\x20\x60\x54\x35\x6b\x39\x36\x60\xef\xbc\x8c\x41\x49\x20\xe8\xbe\x85\xe5\x8a\xa9\x20\xe2\x80\xba\x20\xe6\x9c\x8d\xe5\x8a\xa1\xe6\x8f\x90\xe4\xbe\x9b\xe6\x96\xb9\xe7\xad\x89\xe5\x88\x97\xe8\xa1\xa8\xe9\xa1\xb5\xe5\x8f\xaf\xe5\xa4\x8d\xe7\x94\xa8\xef\xbc\x89\x20\xe2\x94\x80\xe2\x94\x80\x0a\x2f\x2f\x0a\x2f\x2f\x20\x20\x20\x20\x20\x44\x72\x69\x6c\x6c\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x0a\x2f\x2f\x0a\x2f\x2f\x20\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x60\xef\xbc\x88\xe5\x8f\xaf\xe7\x82\xb9\xe5\x87\xbb\xe6\xa0\xb9\xef\xbc\x8c\x60\x69\x74\x65\x6d\x2e\x72\x6f\x77\x5f\x69\x64\x60\xef\xbc\x89\xef\xbc\x9a\x33\x30\x20\xe6\x96\xb9\xe5\x9d\x97\xe5\x9b\xbe\xe6\xa0\x87\xe5\xba\x95\xef\xbc\x88\x60\x69\x74\x65\x6d\x2e\x69\x63\x6f\x6e\x60\x20\xe6\x98\xaf\x20\x60\x75\x69\x2e\x69\x63\x6f\x6e\x73\x60\x20\xe7\x9a\x84\xe5\x90\x8d\xe5\xad\x97\xef\xbc\x8c\xe6\x89\xbe\xe4\xb8\x8d\xe5\x88\xb0\xe7\x94\xa8\x20\x70\x6c\x75\x67\xef\xbc\x89\x2b\x20\xe6\xa0\x87\xe9\xa2\x98\x20\x2f\x20\xe6\x91\x98\xe8\xa6\x81\xe4\xb8\xa4\xe8\xa1\x8c\x0a\x2f\x2f\x20\xef\xbc\x88\x31\x33\x20\x2f\x20\x31\x31\x2e\x35\xef\xbc\x8c\x67\x61\x70\x20\x31\xef\xbc\x89\x2b\x20\xe5\xb0\xbe\xe6\xb3\xa8\xef\xbc\x88\x31\x31\x2e\x35\xef\xbc\x8c\xe7\xa9\xba\xe4\xb8\xb2\xe4\xb8\x8d\xe6\x98\xbe\xe7\xa4\xba\xef\xbc\x89\x2b\x20\xe7\x8a\xb6\xe6\x80\x81\xe6\xa0\x87\xe7\xad\xbe\xef\xbc\x88\xe5\x8e\x9f\xe7\x94\x9f\x20\x60\x57\x2e\x54\x61\x67\x60\xef\xbc\x8c\x60\x69\x74\x65\x6d\x2e\x62\x61\x64\x67\x65\x60\xef\xbc\x8c\xe7\xa9\xba\xe4\xb8\xb2\xe4\xb8\x8d\xe6\x98\xbe\xe7\xa4\xba\xef\xbc\x89\x2b\x20\xe7\xae\xad\xe5\xa4\xb4\xef\xbc\x9b\xe8\xa2\xab\xe7\xa6\x81\xe7\x94\xa8\xe7\x9a\x84\xe6\x8f\x92\xe4\xbb\xb6\x0a\x2f\x2f\x20\xef\xbc\x88\x60\x69\x74\x65\x6d\x2e\x6d\x75\x74\x65\x64\x60\xef\xbc\x89\xe5\x9b\xbe\xe6\xa0\x87\xe4\xb8\x8e\xe6\xa0\x87\xe9\xa2\x98\xe9\x99\x8d\xe4\xb8\xba\xe6\xac\xa1\xe8\xa6\x81\xe8\x89\xb2\xef\xbc\x9b\xe8\xa1\x8c\xe5\x86\x85\x20\x70\x61\x64\x64\x69\x6e\x67\x20\x5b\x39\x2c\x20\x30\x5d\xe3\x80\x81\x67\x61\x70\x20\x38\xef\xbc\x8c\xe4\xb8\x8e\xe5\x9b\xbe\xe6\xa0\x87\xe5\xba\x95\x20\x67\x61\x70\x20\x31\x32\xef\xbc\x9b\xe9\x99\xa4\xe6\x9c\xac\xe7\xbb\x84\xe6\x9c\x80\xe5\x90\x8e\xe4\xb8\x80\xe8\xa1\x8c\x0a\x2f\x2f\x20\xef\xbc\x88\x60\x69\x74\x65\x6d\x2e\x6c\x61\x73\x74\x60\xef\xbc\x89\xe5\xa4\x96\xe5\xba\x95\xe9\x83\xa8\xe4\xb8\x80\xe6\x9d\xa1\xe5\x8f\x91\xe4\xb8\x9d\xe7\xba\xbf\xef\xbc\x88\xe4\xba\xba\xe5\xb7\xa5\xe9\xaa\x8c\xe6\x94\xb6\xe5\x8f\x8d\xe9\xa6\x88\x20\x36\xef\xbc\x89\xe3\x80\x82\xe7\x82\xb9\xe5\x87\xbb\xe5\x8f\x91\x20\x60\x69\x74\x65\x6d\x2e\x74\x61\x72\x67\x65\x74\x60\xef\xbc\x9b\xe4\xbf\x9d\xe5\xad\x98\xe4\xb8\xad\xe4\xb8\x8d\xe5\x8f\xaf\xe7\x82\xb9\xef\xbc\x88\xe5\x90\x8c\xe6\xa6\x82\xe8\xa7\x88\xe8\xa1\x8c\xef\xbc\x89\xe3\x80\x82\x0a\x2f\x2f\x20\xe6\xa0\x87\xe9\xa2\x98\x20\x2f\x20\xe6\x91\x98\xe8\xa6\x81\x20\x2f\x20\xe5\xb0\xbe\xe6\xb3\xa8\xe7\x9a\x84\x20\x74\x65\x73\x74\x5f\x69\x64\x20\xe6\x98\xaf\x20\x60\x69\x74\x65\x6d\x2e\x74\x69\x74\x6c\x65\x5f\x69\x64\x60\x20\x2f\x20\x60\x73\x75\x6d\x6d\x61\x72\x79\x5f\x69\x64\x60\x20\x2f\x20\x60\x74\x72\x61\x69\x6c\x5f\x69\x64\x60\xe3\x80\x82\x0a\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x49\x63\x6f\x6e\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x75\x69\x2e\x53\x76\x67\x41\x73\x73\x65\x74\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x67\x65\x74\x28\x69\x74\x65\x6d\x2e\x69\x63\x6f\x6e\x29\x20\x6f\x72\x65\x6c\x73\x65\x20\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x70\x6c\x75\x67\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x52\x6f\x77\x49\x64\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x74\x65\x6d\x2e\x72\x6f\x77\x5f\x69\x64\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x54\x69\x74\x6c\x65\x49\x64\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x74\x65\x6d\x2e\x74\x69\x74\x6c\x65\x5f\x69\x64\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x53\x75\x6d\x6d\x61\x72\x79\x49\x64\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x74\x65\x6d\x2e\x73\x75\x6d\x6d\x61\x72\x79\x5f\x69\x64\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x54\x72\x61\x69\x6c\x49\x64\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x74\x65\x6d\x2e\x74\x72\x61\x69\x6c\x5f\x69\x64\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x54\x69\x74\x6c\x65\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x74\x65\x6d\x2e\x74\x69\x74\x6c\x65\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x53\x75\x6d\x6d\x61\x72\x79\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x74\x65\x6d\x2e\x73\x75\x6d\x6d\x61\x72\x79\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x54\x72\x61\x69\x6c\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x5b\x5d\x63\x6f\x6e\x73\x74\x20\x75\x38\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x74\x65\x6d\x2e\x74\x72\x61\x69\x6c\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x48\x61\x73\x54\x72\x61\x69\x6c\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x74\x65\x6d\x2e\x74\x72\x61\x69\x6c\x2e\x6c\x65\x6e\x20\x21\x3d\x20\x30\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x48\x61\x73\x42\x61\x64\x67\x65\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x74\x65\x6d\x2e\x62\x61\x64\x67\x65\x2e\x6c\x65\x6e\x20\x21\x3d\x20\x30\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x42\x61\x64\x67\x65\x43\x6f\x6c\x6f\x72\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x57\x2e\x54\x61\x67\x43\x6f\x6c\x6f\x72\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x66\x20\x28\x69\x74\x65\x6d\x2e\x62\x61\x64\x67\x65\x5f\x77\x61\x72\x6e\x69\x6e\x67\x29\x20\x2e\x77\x61\x72\x6e\x69\x6e\x67\x20\x65\x6c\x73\x65\x20\x2e\x6e\x65\x75\x74\x72\x61\x6c\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x4c\x61\x73\x74\x28\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x69\x74\x65\x6d\x2e\x6c\x61\x73\x74\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x4f\x70\x65\x6e\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x76\x6f\x69\x64\x20\x7b\x0a\x20\x20\x20\x20\x76\x6d\x2e\x64\x69\x73\x70\x61\x74\x63\x68\x28\x69\x74\x65\x6d\x2e\x74\x61\x72\x67\x65\x74\x29\x3b\x0a\x7d\x0a\x66\x6e\x20\x64\x72\x69\x6c\x6c\x4c\x6f\x63\x6b\x65\x64\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x29\x20\x62\x6f\x6f\x6c\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x76\x6d\x2e\x63\x6f\x6e\x74\x72\x6f\x6c\x73\x4c\x6f\x63\x6b\x65\x64\x28\x29\x3b\x0a\x7d\x0a\x0a\x70\x75\x62\x20\x66\x6e\x20\x44\x72\x69\x6c\x6c\x52\x6f\x77\x28\x76\x6d\x3a\x20\x2a\x6d\x2e\x56\x69\x65\x77\x4d\x6f\x64\x65\x6c\x2c\x20\x69\x74\x65\x6d\x3a\x20\x6d\x2e\x44\x72\x69\x6c\x6c\x49\x74\x65\x6d\x29\x20\x56\x69\x65\x77\x20\x7b\x0a\x20\x20\x20\x20\x72\x65\x74\x75\x72\x6e\x20\x28\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x64\x72\x69\x6c\x6c\x52\x6f\x77\x49\x64\x28\x69\x74\x65\x6d\x29\x7d\x20\x61\x31\x31\x79\x4c\x61\x62\x65\x6c\x3d\x7b\x64\x72\x69\x6c\x6c\x54\x69\x74\x6c\x65\x28\x69\x74\x65\x6d\x29\x7d\x20\x64\x69\x73\x61\x62\x6c\x65\x64\x3d\x7b\x64\x72\x69\x6c\x6c\x4c\x6f\x63\x6b\x65\x64\x28\x76\x6d\x29\x7d\x20\x6f\x6e\x43\x6c\x69\x63\x6b\x3d\x7b\x64\x72\x69\x6c\x6c\x4f\x70\x65\x6e\x28\x76\x6d\x2c\x20\x69\x74\x65\x6d\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x44\x72\x69\x6c\x6c\x52\x6f\x77\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x6f\x63\x6b\x65\x64\x20\x3d\x20\x64\x72\x69\x6c\x6c\x4c\x6f\x63\x6b\x65\x64\x28\x76\x6d\x29\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x74\x69\x6c\x65\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x64\x72\x69\x6c\x6c\x49\x63\x6f\x6e\x28\x69\x74\x65\x6d\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x44\x72\x69\x6c\x6c\x49\x63\x6f\x6e\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6d\x75\x74\x65\x64\x20\x3d\x20\x69\x74\x65\x6d\x2e\x6d\x75\x74\x65\x64\x20\x7d\x29\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x44\x72\x69\x6c\x6c\x49\x6e\x6e\x65\x72\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6c\x61\x73\x74\x20\x3d\x20\x64\x72\x69\x6c\x6c\x4c\x61\x73\x74\x28\x69\x74\x65\x6d\x29\x20\x7d\x29\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x62\x6f\x78\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x64\x72\x69\x6c\x6c\x5f\x63\x6f\x70\x79\x7d\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x64\x72\x69\x6c\x6c\x54\x69\x74\x6c\x65\x49\x64\x28\x69\x74\x65\x6d\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x44\x72\x69\x6c\x6c\x54\x69\x74\x6c\x65\x2e\x6f\x66\x28\x2e\x7b\x20\x2e\x6d\x75\x74\x65\x64\x20\x3d\x20\x69\x74\x65\x6d\x2e\x6d\x75\x74\x65\x64\x20\x7d\x29\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x64\x72\x69\x6c\x6c\x5f\x74\x65\x78\x74\x5f\x62\x6f\x78\x7d\x3e\x7b\x64\x72\x69\x6c\x6c\x54\x69\x74\x6c\x65\x28\x69\x74\x65\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x64\x72\x69\x6c\x6c\x53\x75\x6d\x6d\x61\x72\x79\x49\x64\x28\x69\x74\x65\x6d\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x64\x72\x69\x6c\x6c\x5f\x73\x75\x6d\x6d\x61\x72\x79\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x64\x72\x69\x6c\x6c\x5f\x74\x65\x78\x74\x5f\x62\x6f\x78\x7d\x3e\x7b\x64\x72\x69\x6c\x6c\x53\x75\x6d\x6d\x61\x72\x79\x28\x69\x74\x65\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x74\x65\x78\x74\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x64\x72\x69\x6c\x6c\x54\x72\x61\x69\x6c\x49\x64\x28\x69\x74\x65\x6d\x29\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x64\x72\x69\x6c\x6c\x5f\x74\x72\x61\x69\x6c\x7d\x20\x62\x6f\x78\x3d\x7b\x53\x2e\x64\x72\x69\x6c\x6c\x5f\x74\x72\x61\x69\x6c\x5f\x62\x6f\x78\x7d\x20\x76\x69\x73\x69\x62\x6c\x65\x3d\x7b\x64\x72\x69\x6c\x6c\x48\x61\x73\x54\x72\x61\x69\x6c\x28\x69\x74\x65\x6d\x29\x7d\x3e\x7b\x64\x72\x69\x6c\x6c\x54\x72\x61\x69\x6c\x28\x69\x74\x65\x6d\x29\x7d\x3c\x2f\x74\x65\x78\x74\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x7b\x69\x66\x20\x28\x64\x72\x69\x6c\x6c\x48\x61\x73\x42\x61\x64\x67\x65\x28\x69\x74\x65\x6d\x29\x29\x20\x3c\x57\x2e\x54\x61\x67\x20\x74\x65\x73\x74\x49\x64\x3d\x7b\x69\x74\x65\x6d\x2e\x62\x61\x64\x67\x65\x5f\x69\x64\x7d\x20\x6c\x61\x62\x65\x6c\x3d\x7b\x69\x74\x65\x6d\x2e\x62\x61\x64\x67\x65\x7d\x20\x63\x6f\x6c\x6f\x72\x3d\x7b\x64\x72\x69\x6c\x6c\x42\x61\x64\x67\x65\x43\x6f\x6c\x6f\x72\x28\x69\x74\x65\x6d\x29\x7d\x20\x73\x69\x7a\x65\x3d\x7b\x2e\x73\x6d\x7d\x20\x2f\x3e\x7d\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x69\x63\x6f\x6e\x20\x73\x72\x63\x3d\x7b\x75\x69\x2e\x69\x63\x6f\x6e\x73\x2e\x63\x68\x65\x76\x72\x6f\x6e\x5f\x72\x69\x67\x68\x74\x7d\x20\x73\x74\x79\x6c\x65\x3d\x7b\x53\x2e\x6f\x76\x65\x72\x76\x69\x65\x77\x5f\x63\x68\x65\x76\x72\x6f\x6e\x7d\x20\x2f\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x62\x6f\x78\x3e\x0a\x20\x20\x20\x20\x20\x20\x20\x20\x3c\x2f\x57\x2e\x50\x72\x65\x73\x73\x61\x62\x6c\x65\x3e\x0a\x20\x20\x20\x20\x29\x3b\x0a\x7d\x0a" else null;
const __YixStyleCatalog = if (ui.view.template.preview_enabled) ui.view.template.styleCatalog(.{ .@"S " = S, .@"K " = K, .@"custom_choice " = custom_choice, .@"directory_tip " = directory_tip, }) else void;

//# yix-map-data [[6515,6505],[13793,7164],[22839,7863],[30089,8389],[33607,8611],[42242,9439],[52470,10264],[62505,11427],[79051,13058],[85474,13821],[99030,15100],[114192,16316],[123710,17002],[134501,21480],[143005,22146],[187218,25778],[193374,26445],[204588,29199]]

//# yix-map rows.yix
